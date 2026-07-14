-- Helpers locaux de revue et de révocation des preuves établissement/soignant.
--
-- La revalidation périodique automatique des registres officiels est
-- volontairement hors périmètre de lancement : cette migration ne crée ni
-- file, ni cron, ni appel HTTP, et ne modifie aucune donnée existante. Les
-- contrôles restent déclenchés explicitement par les parcours applicatifs.

-- Ouvre ou reutilise une vraie entree de revue admin pour les documents du
-- representant. Les Edge Functions ne peuvent donc pas afficher une promesse
-- de revue humaine sans artefact durable correspondant.
CREATE OR REPLACE FUNCTION public.fn_ouvrir_revue_verification_etablissement(
  p_etablissement_id uuid,
  p_service text,
  p_motif text,
  p_donnees jsonb DEFAULT '{}'::jsonb,
  p_priorite integer DEFAULT 3
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_revue_id uuid;
  v_service text := upper(btrim(COALESCE(p_service, '')));
  v_motif text := left(btrim(COALESCE(p_motif, '')), 1000);
  v_priorite integer := greatest(1, least(COALESCE(p_priorite, 3), 5));
BEGIN
  IF COALESCE(
       auth.jwt()->>'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;

  IF p_etablissement_id IS NULL
     OR v_service NOT IN (
       'VERIFY_PIECE_IDENTITE_ETAB',
       'VERIFY_JUSTIFICATIF_FONCTION',
       'VERIFY_FINESS_RECOUPEMENT',
       'VERIFY_RIB_ETABLISSEMENT'
     )
     OR length(v_motif) < 10 THEN
    RAISE EXCEPTION 'Demande de revue etablissement invalide'
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.etablissements e
    WHERE e.id = p_etablissement_id AND e.supprime_le IS NULL
  ) THEN
    RAISE EXCEPTION 'Etablissement introuvable' USING ERRCODE = 'P0002';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_etablissement_id::text || '|' || v_service, 0)
  );

  SELECT r.id
    INTO v_revue_id
  FROM public.file_revue_manuelle r
  WHERE r.type_entite = 'ETABLISSEMENT'
    AND r.id_entite = p_etablissement_id
    AND r.service_en_echec = v_service
    AND r.statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE')
  ORDER BY r.cree_le DESC
  LIMIT 1
  FOR UPDATE;

  IF v_revue_id IS NULL THEN
    INSERT INTO public.file_revue_manuelle (
      type_entite, id_entite, service_en_echec, motif_echec,
      donnees_originales, statut, priorite, expire_le
    ) VALUES (
      'ETABLISSEMENT', p_etablissement_id, v_service, v_motif,
      COALESCE(p_donnees, '{}'::jsonb) || jsonb_build_object(
        'etablissement_id', p_etablissement_id,
        'demande_le', now()
      ),
      'EN_ATTENTE', v_priorite, now() + interval '7 days'
    )
    RETURNING id INTO v_revue_id;
  ELSE
    UPDATE public.file_revue_manuelle
    SET motif_echec = v_motif,
        donnees_originales = COALESCE(donnees_originales, '{}'::jsonb)
          || COALESCE(p_donnees, '{}'::jsonb)
          || jsonb_build_object('derniere_relance_le', now()),
        priorite = greatest(priorite, v_priorite),
        expire_le = greatest(COALESCE(expire_le, now()), now() + interval '7 days')
    WHERE id = v_revue_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'revue_id', v_revue_id);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_ouvrir_revue_verification_etablissement(
  uuid, text, text, jsonb, integer
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_ouvrir_revue_verification_etablissement(
  uuid, text, text, jsonb, integer
) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_resoudre_revue_verification_etablissement(
  p_etablissement_id uuid,
  p_service text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_service text := upper(btrim(COALESCE(p_service, '')));
  v_count integer;
BEGIN
  IF COALESCE(
       auth.jwt()->>'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;
  IF p_etablissement_id IS NULL
     OR v_service NOT IN (
       'VERIFY_PIECE_IDENTITE_ETAB',
       'VERIFY_JUSTIFICATIF_FONCTION',
       'VERIFY_FINESS_RECOUPEMENT',
       'VERIFY_RIB_ETABLISSEMENT'
     ) THEN
    RAISE EXCEPTION 'Resolution de revue etablissement invalide'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.file_revue_manuelle
  SET statut = 'RESOLU_AUTO',
      notes_resolution = 'Verification automatique reussie lors d une nouvelle tentative.',
      revu_le = COALESCE(revu_le, now()),
      resolu_le = now()
  WHERE type_entite = 'ETABLISSEMENT'
    AND id_entite = p_etablissement_id
    AND service_en_echec = v_service
    AND statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE');
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_resoudre_revue_verification_etablissement(
  uuid, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_resoudre_revue_verification_etablissement(
  uuid, text
) TO service_role;

-- Applique le verdict EN_ATTENTE et crée/réutilise la revue dans une seule
-- transaction. Si la source a changé ou si l'upsert de file échoue, aucune
-- moitié de l'opération n'est conservée.
CREATE OR REPLACE FUNCTION public.fn_mettre_preuve_etablissement_en_revue_atomique(
  p_etablissement_id uuid,
  p_service text,
  p_source_snapshot jsonb,
  p_motif text,
  p_cause text,
  p_resultat jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_service text := upper(btrim(COALESCE(p_service, '')));
  v_motif text := left(btrim(COALESCE(p_motif, '')), 1000);
  v_cause text := left(upper(btrim(COALESCE(p_cause, 'INCONNU'))), 100);
  v_applique boolean := false;
  v_revue jsonb;
  v_rattachement jsonb;
  v_version bigint;
  v_source_key text;
  v_resultat jsonb;
BEGIN
  IF COALESCE(
       auth.jwt()->>'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;
  IF p_etablissement_id IS NULL
     OR v_service NOT IN ('VERIFY_PIECE_IDENTITE_ETAB', 'VERIFY_JUSTIFICATIF_FONCTION')
     OR jsonb_typeof(COALESCE(p_source_snapshot, '{}'::jsonb)) <> 'object'
     OR NULLIF(p_source_snapshot->>'verification_source_version', '') IS NULL
     OR length(v_motif) < 10 THEN
    RAISE EXCEPTION 'Mise en revue atomique invalide' USING ERRCODE = '22023';
  END IF;

  v_resultat := COALESCE(p_resultat, '{}'::jsonb) || jsonb_build_object(
    'verdict_final', 'EN_ATTENTE',
    'motif', v_motif,
    'revue_manuelle_requise', true,
    'cause_revue', v_cause,
    'regle_version', '2026-07-14'
  );

  IF v_service = 'VERIFY_PIECE_IDENTITE_ETAB' THEN
    v_source_key := p_source_snapshot->>'representant_piece_s3_key';
    v_applique := public.fn_appliquer_verification_identite_etablissement(
      p_etablissement_id,
      (p_source_snapshot->>'verification_source_version')::bigint,
      v_source_key,
      p_source_snapshot->>'representant_piece_type_mime',
      p_source_snapshot->>'representant_piece_type_document',
      p_source_snapshot->>'representant_nom',
      p_source_snapshot->>'representant_prenom',
      false,
      v_resultat
    );
  ELSE
    v_source_key := p_source_snapshot->>'justificatif_fonction_s3_key';
    v_applique := public.fn_appliquer_verification_fonction_etablissement(
      p_etablissement_id,
      (p_source_snapshot->>'verification_source_version')::bigint,
      v_source_key,
      p_source_snapshot->>'justificatif_fonction_type',
      p_source_snapshot->>'justificatif_fonction_type_mime',
      p_source_snapshot->>'representant_nom',
      p_source_snapshot->>'representant_prenom',
      p_source_snapshot->>'nom',
      p_source_snapshot->>'siret',
      p_source_snapshot->>'siret_raison_sociale',
      p_source_snapshot->>'finess_raison_sociale',
      false,
      v_resultat
    );
  END IF;

  IF v_applique IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'source_changed', true);
  END IF;

  v_rattachement := public.fn_evaluer_rattachement_etablissement(p_etablissement_id);
  UPDATE public.etablissements e
  SET peut_publier_missions = CASE
        WHEN e.siret_verifie IS TRUE
         AND e.siret_est_actif IS NOT FALSE
         AND e.finess_verifie IS TRUE
         AND e.representant_identite_verifiee IS TRUE
         AND e.rattachement_verifie IS TRUE
         AND e.contrat_service_signe IS TRUE
        THEN e.peut_publier_missions
        ELSE false
      END,
      modifie_le = now()
  WHERE e.id = p_etablissement_id;

  v_revue := public.fn_ouvrir_revue_verification_etablissement(
    p_etablissement_id,
    v_service,
    v_motif,
    jsonb_build_object(
      'cause', v_cause,
      'source_version', (p_source_snapshot->>'verification_source_version')::bigint,
      'source_s3_key', v_source_key
    ),
    4
  );
  IF COALESCE((v_revue->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Ouverture de revue non confirmee' USING ERRCODE = 'P0001';
  END IF;
  SELECT verification_source_version INTO v_version
  FROM public.etablissements WHERE id = p_etablissement_id;
  RETURN jsonb_build_object(
    'success', true,
    'revue_id', v_revue->>'revue_id',
    'verification_source_version', v_version,
    'rattachement', v_rattachement
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_mettre_preuve_etablissement_en_revue_atomique(
  uuid, text, jsonb, text, text, jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_mettre_preuve_etablissement_en_revue_atomique(
  uuid, text, jsonb, text, text, jsonb
) TO service_role;

-- L'absence de date de naissance publiee par le registre SIRENE ne prouve ni
-- une usurpation ni une radiation. Elle ouvre une revue idempotente sans
-- modifier le verdict SIRET canonique existant.
CREATE OR REPLACE FUNCTION public.fn_ouvrir_revue_siret_liberal_soignant(
  p_soignant_id uuid,
  p_code text,
  p_donnees jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_revue_id uuid;
  v_code text := upper(btrim(COALESCE(p_code, '')));
BEGIN
  IF COALESCE(
       auth.jwt()->>'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;
  IF p_soignant_id IS NULL OR v_code <> 'IDENTITE_NON_CONFIRMABLE' THEN
    RAISE EXCEPTION 'Demande de revue SIRET invalide' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.soignants s
    WHERE s.id = p_soignant_id AND s.supprime_le IS NULL
  ) THEN
    RAISE EXCEPTION 'Soignant introuvable' USING ERRCODE = 'P0002';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_soignant_id::text || '|VERIFY_SIRET_IDENTITE_NON_CONCLUANTE', 0)
  );
  SELECT r.id INTO v_revue_id
  FROM public.file_revue_manuelle r
  WHERE r.type_entite = 'SOIGNANT'
    AND r.id_entite = p_soignant_id
    AND r.service_en_echec = 'VERIFY_SIRET_IDENTITE_NON_CONCLUANTE'
    AND r.statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE')
  ORDER BY r.cree_le DESC LIMIT 1 FOR UPDATE;

  IF v_revue_id IS NULL THEN
    INSERT INTO public.file_revue_manuelle (
      type_entite, id_entite, service_en_echec, motif_echec,
      donnees_originales, statut, priorite, expire_le
    ) VALUES (
      'SOIGNANT', p_soignant_id, 'VERIFY_SIRET_IDENTITE_NON_CONCLUANTE',
      'Le registre ne publie pas assez de traits civils pour confirmer automatiquement le titulaire du SIRET.',
      COALESCE(p_donnees, '{}'::jsonb) || jsonb_build_object(
        'code', v_code,
        'demande_le', now()
      ),
      'EN_ATTENTE', 4, now() + interval '7 days'
    ) RETURNING id INTO v_revue_id;
  ELSE
    UPDATE public.file_revue_manuelle
    SET donnees_originales = COALESCE(donnees_originales, '{}'::jsonb)
          || COALESCE(p_donnees, '{}'::jsonb)
          || jsonb_build_object('derniere_relance_le', now()),
        expire_le = greatest(COALESCE(expire_le, now()), now() + interval '7 days')
    WHERE id = v_revue_id;
  END IF;
  RETURN jsonb_build_object('success', true, 'revue_id', v_revue_id);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_ouvrir_revue_siret_liberal_soignant(
  uuid, text, jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_ouvrir_revue_siret_liberal_soignant(
  uuid, text, jsonb
) TO service_role;

-- Rejet global explicite du dossier : la nouvelle UI admin ne doit pas
-- retomber sur l'ancienne RPC sans CAS revoquee par la migration 063000.
CREATE OR REPLACE FUNCTION public.fn_admin_rejeter_dossier_etablissement(
  p_etablissement_id uuid,
  p_version_attendue bigint,
  p_motif text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_etab public.etablissements%ROWTYPE;
  v_motif text := left(btrim(COALESCE(p_motif, '')), 1000);
  v_version_finale bigint;
  v_snapshot jsonb;
BEGIN
  IF v_uid IS NULL
     OR COALESCE(auth.jwt()->>'aal', '') IS DISTINCT FROM 'aal2'
     OR NOT public.est_admin_valide() THEN
    RAISE EXCEPTION 'Administrateur AAL2 autorise requis'
      USING ERRCODE = '42501';
  END IF;
  IF p_etablissement_id IS NULL OR p_version_attendue IS NULL
     OR length(v_motif) < 10 THEN
    RAISE EXCEPTION 'Un motif de rejet explicite de 10 caracteres minimum est requis'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Etablissement introuvable' USING ERRCODE = 'P0002';
  END IF;
  IF v_etab.verification_source_version IS DISTINCT FROM p_version_attendue THEN
    RAISE EXCEPTION 'Le dossier a change : rechargez avant de rejeter'
      USING ERRCODE = '40001';
  END IF;

  v_snapshot := jsonb_build_object(
    'source_version', v_etab.verification_source_version,
    'siret', v_etab.siret,
    'siret_verifie', v_etab.siret_verifie,
    'finess', v_etab.finess,
    'finess_verifie', v_etab.finess_verifie,
    'representant_piece_s3_key', v_etab.representant_piece_s3_key,
    'representant_identite_verifiee', v_etab.representant_identite_verifiee,
    'justificatif_fonction_s3_key', v_etab.justificatif_fonction_s3_key,
    'justificatif_fonction_verifie', v_etab.justificatif_fonction_verifie,
    'rattachement_methode', v_etab.rattachement_methode,
    'rattachement_verifie', v_etab.rattachement_verifie,
    'contrat_service_signe', v_etab.contrat_service_signe
  );

  UPDATE public.etablissements
  SET statut_verification = 'REJETE',
      peut_publier_missions = false,
      motif_rejet = v_motif,
      verifie_le = NULL,
      verifie_par = NULL,
      modifie_le = now()
  WHERE id = p_etablissement_id;

  SELECT verification_source_version INTO v_version_finale
  FROM public.etablissements WHERE id = p_etablissement_id;

  INSERT INTO public.etablissement_preuve_audit (
    etablissement_id, preuve, evenement, acteur_id, source_version,
    source_snapshot, motif
  ) VALUES (
    p_etablissement_id, 'DOSSIER', 'REJETE', v_uid,
    v_etab.verification_source_version, v_snapshot, v_motif
  );
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_PLATEFORME', 'ADMIN_ACTION', 'etablissement',
    p_etablissement_id,
    jsonb_build_object(
      'sous_action', 'REJET_DOSSIER_ETABLISSEMENT',
      'motif', v_motif,
      'source_snapshot', v_snapshot
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'nom', v_etab.nom,
    'verification_source_version', v_version_finale
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_admin_rejeter_dossier_etablissement(
  uuid, bigint, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_rejeter_dossier_etablissement(
  uuid, bigint, text
) TO authenticated;

-- Revocation ciblee du SIRET liberal. La verification reseau appelle cette RPC
-- seulement apres un verdict definitif du registre et avec le numero exact lu
-- avant l'appel, ce qui ferme toute course avec une modification de profil.
CREATE OR REPLACE FUNCTION public.fn_revoquer_siret_liberal_soignant(
  p_soignant_id uuid,
  p_siret_attendu text,
  p_code text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_soignant record;
  v_code text := upper(left(btrim(COALESCE(p_code, '')), 100));
  v_audit jsonb;
BEGIN
  IF COALESCE(
       auth.jwt()->>'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;

  IF p_soignant_id IS NULL
     OR COALESCE(p_siret_attendu, '') !~ '^[0-9]{14}$'
     OR v_code = '' THEN
    RAISE EXCEPTION 'Revocation SIRET invalide' USING ERRCODE = '22023';
  END IF;

  SELECT s.siret_liberal, s.siret_liberal_verifie
    INTO v_soignant
  FROM public.soignants s
  WHERE s.id = p_soignant_id AND s.supprime_le IS NULL
  FOR UPDATE;

  IF NOT FOUND OR v_soignant.siret_liberal IS DISTINCT FROM p_siret_attendu THEN
    RETURN false;
  END IF;

  UPDATE public.soignants
  SET siret_liberal_verifie = false,
      siret_liberal_verifie_le = NULL,
      siret_liberal_raison_sociale = NULL,
      siret_liberal_coherence_identite = NULL,
      tous_documents_valides = false,
      modifie_le = now()
  WHERE id = p_soignant_id;

  v_audit := public.fn_ecrire_audit_safe(
    p_acteur_id := p_soignant_id,
    p_type_acteur := 'SYSTEME',
    p_action := 'VERIFICATION_DOCUMENT',
    p_type_ressource := 'soignant',
    p_id_ressource := p_soignant_id,
    p_details := jsonb_build_object(
      'sous_action', 'REVOQUER_SIRET_LIBERAL',
      'code', v_code,
      'siret_last4', right(p_siret_attendu, 4),
      'source', 'fn_revoquer_siret_liberal_soignant'
    )
  );
  IF COALESCE(v_audit @> '{"success": true}'::jsonb, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Audit de revocation SIRET non ecrit';
  END IF;

  PERFORM public.fn_calculer_tous_documents_valides(p_soignant_id);
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_revoquer_siret_liberal_soignant(
  uuid, text, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_revoquer_siret_liberal_soignant(
  uuid, text, text
) TO service_role;
