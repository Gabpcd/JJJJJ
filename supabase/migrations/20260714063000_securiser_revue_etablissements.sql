-- Revue manuelle des preuves établissement : file exhaustive, décisions CAS
-- AAL2, rapprochement de la date de naissance et remplacement documentaire
-- sans fenêtre de perte de preuve.
--
-- Cette migration ne modifie aucune ligne métier existante (y compris les
-- comptes de démonstration). Elle ajoute uniquement les garde-fous et APIs.

-- ---------------------------------------------------------------------------
-- 1. Journal append-only des sources et décisions
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.etablissement_preuve_audit (
  id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  etablissement_id uuid NOT NULL REFERENCES public.etablissements(id),
  preuve text NOT NULL CHECK (preuve IN ('IDENTITE', 'FONCTION', 'DOSSIER')),
  evenement text NOT NULL CHECK (
    evenement IN ('REMPLACEMENT', 'APPROUVE', 'REJETE', 'FINALISE')
  ),
  acteur_id uuid,
  source_version bigint NOT NULL,
  source_s3_key text,
  source_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  motif text,
  cree_le timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.etablissement_preuve_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.etablissement_preuve_audit FORCE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_etablissement_preuve_audit_dossier
  ON public.etablissement_preuve_audit (
    etablissement_id,
    cree_le DESC
  );

REVOKE ALL ON TABLE public.etablissement_preuve_audit
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.etablissement_preuve_audit TO service_role;

COMMENT ON TABLE public.etablissement_preuve_audit IS
  'Journal append-only des remplacements et décisions sur les preuves établissement; les octets peuvent être nettoyés après remplacement, le snapshot reste auditable.';

-- ---------------------------------------------------------------------------
-- 2. Rapprochement déterministe date de naissance pièce <-> registre
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.fn_rapprocher_naissance_representant(
  p_resultat_identite jsonb,
  p_dirigeants jsonb,
  p_representant_nom text,
  p_representant_prenom text,
  p_date_confirmee date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_dirigeant jsonb;
  v_date_piece_raw text;
  v_date_piece date;
  v_date_registre text;
  v_correspond boolean;
BEGIN
  IF jsonb_typeof(p_dirigeants) IS DISTINCT FROM 'array'
     OR NULLIF(public.fn_normaliser_nom(p_representant_nom), '') IS NULL
     OR NULLIF(public.fn_normaliser_nom(p_representant_prenom), '') IS NULL THEN
    RETURN jsonb_build_object('statut', 'DIRIGEANT_NON_TROUVE');
  END IF;

  SELECT d
    INTO v_dirigeant
  FROM jsonb_array_elements(p_dirigeants) AS dirigeants(d)
  WHERE public.fn_normaliser_nom(d ->> 'type_dirigeant') LIKE '%physique%'
    AND public.fn_normaliser_nom(d ->> 'nom')
        = public.fn_normaliser_nom(p_representant_nom)
    AND NOT EXISTS (
      SELECT 1
      FROM unnest(
        regexp_split_to_array(
          public.fn_normaliser_nom(p_representant_prenom),
          ' +'
        )
      ) AS attendu(prenom)
      WHERE attendu.prenom <> ''
        AND NOT (
          attendu.prenom = ANY (
            regexp_split_to_array(
              public.fn_normaliser_nom(
                COALESCE(d ->> 'prenoms', d ->> 'prenom')
              ),
              ' +'
            )
          )
        )
    )
  LIMIT 1;

  IF v_dirigeant IS NULL THEN
    RETURN jsonb_build_object('statut', 'DIRIGEANT_NON_TROUVE');
  END IF;

  v_date_registre := COALESCE(
    NULLIF(btrim(v_dirigeant ->> 'date_de_naissance'), ''),
    NULLIF(btrim(v_dirigeant ->> 'annee_de_naissance'), '')
  );

  IF v_date_registre IS NULL THEN
    RETURN jsonb_build_object(
      'statut', 'NON_DISPONIBLE',
      'date_piece', COALESCE(
        p_date_confirmee::text,
        NULLIF(p_resultat_identite #>> '{revue_admin,date_naissance_confirmee}', ''),
        NULLIF(p_resultat_identite ->> 'date_naissance_extraite', ''),
        NULLIF(p_resultat_identite ->> 'date_naissance', '')
      )
    );
  END IF;

  IF v_date_registre !~ '^\d{4}(?:-\d{2}(?:-\d{2})?)?$' THEN
    RETURN jsonb_build_object(
      'statut', 'REGISTRE_INEXPLOITABLE',
      'date_registre', v_date_registre
    );
  END IF;

  v_date_piece_raw := COALESCE(
    p_date_confirmee::text,
    NULLIF(p_resultat_identite #>> '{revue_admin,date_naissance_confirmee}', ''),
    NULLIF(p_resultat_identite ->> 'date_naissance_extraite', ''),
    NULLIF(p_resultat_identite ->> 'date_naissance', '')
  );

  IF v_date_piece_raw IS NULL
     OR v_date_piece_raw !~ '^\d{4}-\d{2}-\d{2}$' THEN
    RETURN jsonb_build_object(
      'statut', 'PIECE_NON_LUE',
      'date_registre', v_date_registre
    );
  END IF;

  BEGIN
    v_date_piece := v_date_piece_raw::date;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
    RETURN jsonb_build_object(
      'statut', 'PIECE_NON_LUE',
      'date_registre', v_date_registre
    );
  END;

  -- L'Annuaire des Entreprises expose selon les dossiers l'année, le mois ou
  -- la date complète. On ne compare que la précision effectivement publiée.
  v_correspond := left(v_date_piece::text, length(v_date_registre)) = v_date_registre;

  RETURN jsonb_build_object(
    'statut', CASE WHEN v_correspond THEN 'CORRESPOND' ELSE 'DIVERGE' END,
    'date_piece', v_date_piece,
    'date_registre', v_date_registre
  );
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_rapprocher_naissance_representant(
  jsonb, jsonb, text, text, date
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_rapprocher_naissance_representant(
  jsonb, jsonb, text, text, date
) TO service_role;

-- Le rapprochement automatique d'un dirigeant inclut désormais la date de
-- naissance lorsque le registre la publie. Une date contradictoire ou non lue
-- ne peut jamais produire AUTO_DIRIGEANT.
CREATE OR REPLACE FUNCTION public.fn_evaluer_rattachement_etablissement(
  p_etablissement_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_etab record;
  v_methode text := 'ADMIN';
  v_verifie boolean := false;
  v_match_nom boolean := false;
  v_rapprochement jsonb := jsonb_build_object('statut', 'DIRIGEANT_NON_TROUVE');
BEGIN
  IF COALESCE(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true), '')
       IS DISTINCT FROM 'service_role'
     AND NOT public.est_admin()
     AND p_etablissement_id IS DISTINCT FROM public.mon_etablissement_id() THEN
    RAISE EXCEPTION 'Non autorisé' USING ERRCODE = '42501';
  END IF;

  SELECT dirigeants, representant_nom, representant_prenom,
         representant_identite_verifiee, representant_identite_resultat_ia,
         justificatif_fonction_verifie
    INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id AND supprime_le IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Établissement introuvable' USING ERRCODE = 'P0002';
  END IF;

  IF v_etab.representant_identite_verifiee IS TRUE
     AND NULLIF(btrim(v_etab.representant_nom), '') IS NOT NULL
     AND NULLIF(btrim(v_etab.representant_prenom), '') IS NOT NULL
     AND jsonb_typeof(v_etab.dirigeants) = 'array' THEN
    SELECT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(v_etab.dirigeants) AS dirigeants(d)
      WHERE public.fn_normaliser_nom(d ->> 'type_dirigeant') LIKE '%physique%'
        AND public.fn_normaliser_nom(d ->> 'nom')
            = public.fn_normaliser_nom(v_etab.representant_nom)
        AND NOT EXISTS (
          SELECT 1
          FROM unnest(
            regexp_split_to_array(
              public.fn_normaliser_nom(v_etab.representant_prenom),
              ' +'
            )
          ) AS attendu(prenom)
          WHERE attendu.prenom <> ''
            AND NOT (
              attendu.prenom = ANY (
                regexp_split_to_array(
                  public.fn_normaliser_nom(
                    COALESCE(d ->> 'prenoms', d ->> 'prenom')
                  ),
                  ' +'
                )
              )
            )
        )
    ) INTO v_match_nom;

    IF v_match_nom THEN
      v_rapprochement := private.fn_rapprocher_naissance_representant(
        v_etab.representant_identite_resultat_ia,
        v_etab.dirigeants,
        v_etab.representant_nom,
        v_etab.representant_prenom,
        NULL
      );
      IF v_rapprochement ->> 'statut' IN ('CORRESPOND', 'NON_DISPONIBLE') THEN
        v_methode := 'AUTO_DIRIGEANT';
        v_verifie := true;
      END IF;
    END IF;
  END IF;

  IF NOT v_verifie
     AND v_etab.representant_identite_verifiee IS TRUE
     AND v_etab.justificatif_fonction_verifie IS TRUE THEN
    v_methode := 'JUSTIFICATIF';
    v_verifie := true;
  END IF;

  UPDATE public.etablissements
  SET rattachement_methode = v_methode,
      rattachement_verifie = v_verifie,
      rattachement_verifie_le = CASE WHEN v_verifie THEN now() ELSE NULL END,
      modifie_le = now()
  WHERE id = p_etablissement_id;

  RETURN jsonb_build_object(
    'success', true,
    'methode', v_methode,
    'verifie', v_verifie,
    'match_dirigeant', v_match_nom,
    'rapprochement_naissance', v_rapprochement
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_evaluer_rattachement_etablissement(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_evaluer_rattachement_etablissement(uuid)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 3. Remplacement atomique du pointeur documentaire
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_remplacer_preuve_etablissement(
  p_etablissement_id uuid,
  p_preuve text,
  p_nouvelle_s3_key text,
  p_type_mime text,
  p_type_document text,
  p_version_attendue bigint,
  p_representant_nom text DEFAULT NULL,
  p_representant_prenom text DEFAULT NULL,
  p_acteur_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_acteur_id uuid;
  v_role text := COALESCE(
    auth.jwt() ->> 'role',
    current_setting('request.jwt.claim.role', true),
    ''
  );
  v_etab public.etablissements%ROWTYPE;
  v_ancienne_s3_key text;
  v_ancien_resultat jsonb;
  v_version_nouvelle bigint;
  v_est_admin boolean := false;
BEGIN
  v_acteur_id := COALESCE(v_uid, p_acteur_id);
  v_est_admin := v_uid IS NOT NULL AND public.est_admin();
  IF v_role IS DISTINCT FROM 'service_role'
     AND NOT v_est_admin
     AND (
       v_uid IS NULL
       OR p_etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
     ) THEN
    RAISE EXCEPTION 'Gestionnaire établissement autorisé requis'
      USING ERRCODE = '42501';
  END IF;

  IF p_preuve NOT IN ('IDENTITE', 'FONCTION')
     OR NULLIF(btrim(p_nouvelle_s3_key), '') IS NULL
     OR p_nouvelle_s3_key LIKE '%..%'
     OR position(chr(92) in p_nouvelle_s3_key) > 0
     OR p_nouvelle_s3_key NOT LIKE p_etablissement_id::text || '/%' THEN
    RAISE EXCEPTION 'Source documentaire invalide' USING ERRCODE = '22023';
  END IF;

  IF p_type_mime NOT IN ('application/pdf', 'image/jpeg', 'image/png', 'image/webp') THEN
    RAISE EXCEPTION 'Type MIME non autorisé' USING ERRCODE = '22023';
  END IF;
  IF p_preuve = 'IDENTITE'
     AND p_type_document NOT IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR') THEN
    RAISE EXCEPTION 'Type de pièce d identité invalide' USING ERRCODE = '22023';
  END IF;
  IF p_preuve = 'FONCTION'
     AND p_type_document NOT IN (
       'ATTESTATION_EMPLOYEUR', 'DELEGATION_SIGNATURE', 'FICHE_POSTE',
       'CONTRAT_TRAVAIL', 'DECISION_NOMINATION'
     ) THEN
    RAISE EXCEPTION 'Type de justificatif invalide' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Établissement introuvable' USING ERRCODE = 'P0002';
  END IF;
  IF v_etab.verification_source_version IS DISTINCT FROM p_version_attendue THEN
    RAISE EXCEPTION 'Le dossier a changé : rechargez avant de téléverser'
      USING ERRCODE = '40001';
  END IF;

  IF p_preuve = 'IDENTITE' THEN
    IF NULLIF(btrim(p_representant_nom), '') IS NULL
       OR NULLIF(btrim(p_representant_prenom), '') IS NULL THEN
      RAISE EXCEPTION 'Nom et prénom du représentant requis'
        USING ERRCODE = '22023';
    END IF;
    v_ancienne_s3_key := v_etab.representant_piece_s3_key;
    v_ancien_resultat := v_etab.representant_identite_resultat_ia;
    IF v_ancienne_s3_key IS NOT DISTINCT FROM p_nouvelle_s3_key THEN
      RAISE EXCEPTION 'Une nouvelle clé immuable est requise'
        USING ERRCODE = '22023';
    END IF;
    UPDATE public.etablissements
    SET representant_nom = btrim(p_representant_nom),
        representant_prenom = btrim(p_representant_prenom),
        representant_piece_s3_key = p_nouvelle_s3_key,
        representant_piece_type_mime = p_type_mime,
        representant_piece_type_document = p_type_document,
        modifie_le = now()
    WHERE id = p_etablissement_id;
  ELSE
    v_ancienne_s3_key := v_etab.justificatif_fonction_s3_key;
    v_ancien_resultat := v_etab.justificatif_fonction_resultat_ia;
    IF v_ancienne_s3_key IS NOT DISTINCT FROM p_nouvelle_s3_key THEN
      RAISE EXCEPTION 'Une nouvelle clé immuable est requise'
        USING ERRCODE = '22023';
    END IF;
    UPDATE public.etablissements
    SET justificatif_fonction_s3_key = p_nouvelle_s3_key,
        justificatif_fonction_type_mime = p_type_mime,
        justificatif_fonction_type = p_type_document,
        modifie_le = now()
    WHERE id = p_etablissement_id;
  END IF;

  SELECT verification_source_version INTO v_version_nouvelle
  FROM public.etablissements
  WHERE id = p_etablissement_id;

  INSERT INTO public.etablissement_preuve_audit (
    etablissement_id, preuve, evenement, acteur_id, source_version,
    source_s3_key, source_snapshot
  ) VALUES (
    p_etablissement_id, p_preuve, 'REMPLACEMENT', v_acteur_id,
    p_version_attendue, v_ancienne_s3_key,
    jsonb_strip_nulls(jsonb_build_object(
      'ancienne_s3_key', v_ancienne_s3_key,
      'nouvelle_s3_key', p_nouvelle_s3_key,
      'ancien_resultat', v_ancien_resultat,
      'nouvelle_type_mime', p_type_mime,
      'nouveau_type_document', p_type_document,
      'representant_nom', CASE WHEN p_preuve = 'IDENTITE' THEN btrim(p_representant_nom) ELSE v_etab.representant_nom END,
      'representant_prenom', CASE WHEN p_preuve = 'IDENTITE' THEN btrim(p_representant_prenom) ELSE v_etab.representant_prenom END
    ))
  );

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    cle_s3_ressource, details
  ) VALUES (
    v_acteur_id,
    CASE WHEN v_est_admin THEN 'ADMIN_PLATEFORME' ELSE 'ADMIN_ETABLISSEMENT' END,
    'DOCUMENT_TELEVERSEMENT', 'etablissement', p_etablissement_id,
    p_nouvelle_s3_key,
    jsonb_build_object(
      'sous_action', 'REMPLACEMENT_PREUVE_ETABLISSEMENT',
      'preuve', p_preuve,
      'source_version', p_version_attendue,
      'ancienne_s3_key', v_ancienne_s3_key,
      'nouvelle_s3_key', p_nouvelle_s3_key
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'ancienne_s3_key', v_ancienne_s3_key,
    'nouvelle_s3_key', p_nouvelle_s3_key,
    'verification_source_version', v_version_nouvelle
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_remplacer_preuve_etablissement(
  uuid, text, text, text, text, bigint, text, text, uuid
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_remplacer_preuve_etablissement(
  uuid, text, text, text, text, bigint, text, text, uuid
) TO service_role;

-- ---------------------------------------------------------------------------
-- 4. File admin exhaustive et contextualisée
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_admin_lister_etablissements_a_verifier(
  p_limit integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_resultat jsonb;
BEGIN
  IF auth.uid() IS NULL
     OR COALESCE(auth.jwt() ->> 'aal', '') IS DISTINCT FROM 'aal2'
     OR NOT public.est_admin_valide() THEN
    RAISE EXCEPTION 'Administrateur AAL2 autorisé requis'
      USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(file)), '[]'::jsonb)
    INTO v_resultat
  FROM (
    SELECT
      e.id, e.nom, e.est_compte_test,
      e.verification_source_version,
      e.siret, e.siret_verifie, e.siret_verifie_le,
      e.siret_raison_sociale, e.siret_categorie_juridique,
      e.siret_code_naf, e.siret_est_actif,
      e.finess, e.finess_verifie, e.finess_verifie_le,
      e.finess_raison_sociale, e.finess_categorie,
      e.finess_secteur, e.finess_est_public,
      e.adresse_rue, e.adresse_code_postal, e.adresse_ville,
      e.adresse_departement,
      e.telephone_contact, e.telephone_verifie,
      e.representant_nom, e.representant_prenom,
      e.representant_identite_verifiee,
      e.representant_identite_verifiee_le,
      e.representant_piece_s3_key,
      e.representant_piece_type_mime,
      e.representant_piece_type_document,
      e.representant_identite_resultat_ia,
      e.justificatif_fonction_s3_key,
      e.justificatif_fonction_type,
      e.justificatif_fonction_type_mime,
      e.justificatif_fonction_verifie,
      e.justificatif_fonction_verifie_le,
      e.justificatif_fonction_resultat_ia,
      e.dirigeants,
      private.fn_rapprocher_naissance_representant(
        e.representant_identite_resultat_ia,
        e.dirigeants,
        e.representant_nom,
        e.representant_prenom,
        NULL
      ) AS rapprochement_naissance,
      e.email_contact, e.email_contact_verifie,
      e.rattachement_methode, e.rattachement_verifie,
      e.rattachement_verifie_le,
      e.statut_verification, e.motif_rejet,
      e.contrat_valide, e.contrat_service_signe,
      e.contrat_service_signe_le,
      e.peut_publier_missions, e.cree_le, e.modifie_le
    FROM public.etablissements e
    WHERE e.supprime_le IS NULL
      AND (
        COALESCE(e.statut_verification, 'EN_ATTENTE') IN ('EN_ATTENTE', 'EN_COURS')
        OR (
          e.statut_verification = 'VERIFIE'
          AND (
            e.siret_verifie IS NOT TRUE
            OR e.finess_verifie IS NOT TRUE
            OR e.representant_identite_verifiee IS NOT TRUE
            OR e.rattachement_verifie IS NOT TRUE
            OR e.contrat_service_signe IS NOT TRUE
          )
        )
      )
    ORDER BY
      CASE
        WHEN e.representant_identite_resultat_ia ->> 'verdict_final' = 'EN_ATTENTE'
          OR e.justificatif_fonction_resultat_ia ->> 'verdict_final' = 'EN_ATTENTE'
          THEN 0
        WHEN e.rattachement_verifie IS TRUE THEN 1
        ELSE 2
      END,
      e.cree_le DESC NULLS LAST
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500))
  ) AS file;

  RETURN jsonb_build_object('success', true, 'etablissements', v_resultat);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_lister_etablissements_a_verifier(integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_lister_etablissements_a_verifier(integer)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Décision atomique par preuve (AAL2 + RBAC + CAS + audit)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_admin_decider_preuve_etablissement(
  p_etablissement_id uuid,
  p_preuve text,
  p_decision text,
  p_motif text,
  p_version_attendue bigint,
  p_source_s3_key_attendue text,
  p_date_naissance_confirmee date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab public.etablissements%ROWTYPE;
  v_source_s3_key text;
  v_resultat jsonb;
  v_resultat_final jsonb;
  v_snapshot jsonb;
  v_rapprochement jsonb;
  v_rattachement jsonb;
  v_version_finale bigint;
  v_motif text := NULLIF(btrim(p_motif), '');
BEGIN
  IF v_uid IS NULL
     OR COALESCE(auth.jwt() ->> 'aal', '') IS DISTINCT FROM 'aal2'
     OR NOT public.est_admin_valide() THEN
    RAISE EXCEPTION 'Administrateur AAL2 autorisé requis'
      USING ERRCODE = '42501';
  END IF;
  IF p_preuve NOT IN ('IDENTITE', 'FONCTION')
     OR p_decision NOT IN ('APPROUVER', 'REJETER') THEN
    RAISE EXCEPTION 'Décision de preuve invalide' USING ERRCODE = '22023';
  END IF;
  IF p_decision = 'REJETER' AND COALESCE(length(v_motif), 0) < 5 THEN
    RAISE EXCEPTION 'Un motif de rejet d au moins 5 caractères est requis'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Établissement introuvable' USING ERRCODE = 'P0002';
  END IF;
  IF v_etab.statut_verification = 'REJETE' THEN
    RAISE EXCEPTION 'Le dossier global est rejeté; rechargez la file'
      USING ERRCODE = '40001';
  END IF;
  IF v_etab.verification_source_version IS DISTINCT FROM p_version_attendue THEN
    RAISE EXCEPTION 'Le dossier a changé : rechargez avant de décider'
      USING ERRCODE = '40001';
  END IF;

  IF p_preuve = 'IDENTITE' THEN
    v_source_s3_key := v_etab.representant_piece_s3_key;
    v_resultat := COALESCE(v_etab.representant_identite_resultat_ia, '{}'::jsonb);
  ELSE
    v_source_s3_key := v_etab.justificatif_fonction_s3_key;
    v_resultat := COALESCE(v_etab.justificatif_fonction_resultat_ia, '{}'::jsonb);
  END IF;
  IF NULLIF(v_source_s3_key, '') IS NULL
     OR v_source_s3_key IS DISTINCT FROM p_source_s3_key_attendue THEN
    RAISE EXCEPTION 'La source documentaire a changé : rechargez avant de décider'
      USING ERRCODE = '40001';
  END IF;

  v_rapprochement := private.fn_rapprocher_naissance_representant(
    v_resultat,
    v_etab.dirigeants,
    v_etab.representant_nom,
    v_etab.representant_prenom,
    CASE WHEN p_preuve = 'IDENTITE' THEN p_date_naissance_confirmee ELSE NULL END
  );

  IF p_preuve = 'IDENTITE' AND p_decision = 'APPROUVER'
     AND v_rapprochement ->> 'statut' IN ('DIVERGE', 'PIECE_NON_LUE') THEN
    RAISE EXCEPTION 'La date de naissance de la pièce doit correspondre au registre avant approbation'
      USING ERRCODE = '22023';
  END IF;
  IF p_preuve = 'FONCTION' AND p_decision = 'APPROUVER'
     AND v_etab.representant_identite_verifiee IS NOT TRUE THEN
    RAISE EXCEPTION 'L identité du représentant doit être approuvée en premier'
      USING ERRCODE = '22023';
  END IF;

  v_snapshot := jsonb_strip_nulls(jsonb_build_object(
    'source_version', v_etab.verification_source_version,
    'source_s3_key', v_source_s3_key,
    'preuve', p_preuve,
    'resultat_ia', v_resultat,
    'representant_nom', v_etab.representant_nom,
    'representant_prenom', v_etab.representant_prenom,
    'siret', v_etab.siret,
    'siret_verifie', v_etab.siret_verifie,
    'siret_raison_sociale', v_etab.siret_raison_sociale,
    'finess', v_etab.finess,
    'finess_verifie', v_etab.finess_verifie,
    'finess_raison_sociale', v_etab.finess_raison_sociale,
    'rapprochement_naissance', v_rapprochement
  ));

  v_resultat_final := v_resultat || jsonb_build_object(
    'verdict_final', CASE WHEN p_decision = 'APPROUVER' THEN 'VERIFIE' ELSE 'REJETE' END,
    'motif', CASE
      WHEN p_decision = 'APPROUVER' THEN COALESCE(v_motif, 'Approuvé après revue humaine contextualisée.')
      ELSE v_motif
    END,
    'revue_admin', jsonb_strip_nulls(jsonb_build_object(
      'decision', p_decision,
      'admin_id', v_uid,
      'decide_le', now(),
      'motif', v_motif,
      'date_naissance_confirmee', CASE
        WHEN p_preuve = 'IDENTITE' THEN p_date_naissance_confirmee
        ELSE NULL
      END,
      'rapprochement_naissance', v_rapprochement,
      'source_version', p_version_attendue,
      'source_s3_key', v_source_s3_key
    ))
  );

  IF p_preuve = 'IDENTITE' THEN
    UPDATE public.etablissements
    SET representant_identite_verifiee = p_decision = 'APPROUVER',
        representant_identite_verifiee_le = CASE
          WHEN p_decision = 'APPROUVER' THEN now() ELSE NULL
        END,
        representant_identite_resultat_ia = v_resultat_final,
        modifie_le = now()
    WHERE id = p_etablissement_id;
  ELSE
    UPDATE public.etablissements
    SET justificatif_fonction_verifie = p_decision = 'APPROUVER',
        justificatif_fonction_verifie_le = CASE
          WHEN p_decision = 'APPROUVER' THEN now() ELSE NULL
        END,
        justificatif_fonction_resultat_ia = v_resultat_final,
        modifie_le = now()
    WHERE id = p_etablissement_id;
  END IF;

  v_rattachement := public.fn_evaluer_rattachement_etablissement(p_etablissement_id);

  SELECT verification_source_version INTO v_version_finale
  FROM public.etablissements
  WHERE id = p_etablissement_id;

  INSERT INTO public.etablissement_preuve_audit (
    etablissement_id, preuve, evenement, acteur_id, source_version,
    source_s3_key, source_snapshot, motif
  ) VALUES (
    p_etablissement_id,
    p_preuve,
    CASE WHEN p_decision = 'APPROUVER' THEN 'APPROUVE' ELSE 'REJETE' END,
    v_uid, p_version_attendue, v_source_s3_key, v_snapshot,
    CASE
      WHEN p_decision = 'APPROUVER' THEN COALESCE(v_motif, 'Revue humaine contextualisée')
      ELSE v_motif
    END
  );

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    cle_s3_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_PLATEFORME', 'ADMIN_ACTION', 'etablissement',
    p_etablissement_id, v_source_s3_key,
    jsonb_build_object(
      'sous_action', 'DECISION_PREUVE_ETABLISSEMENT',
      'preuve', p_preuve,
      'decision', p_decision,
      'motif', v_motif,
      'source_version', p_version_attendue,
      'source_snapshot', v_snapshot,
      'rattachement_apres_decision', v_rattachement
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'preuve', p_preuve,
    'decision', p_decision,
    'rattachement', v_rattachement,
    'verification_source_version', v_version_finale
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_decider_preuve_etablissement(
  uuid, text, text, text, bigint, text, date
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_decider_preuve_etablissement(
  uuid, text, text, text, bigint, text, date
) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. Finalisation globale CAS, sans promotion implicite d'une preuve
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_admin_finaliser_verification_etablissement(
  p_etablissement_id uuid,
  p_version_attendue bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab public.etablissements%ROWTYPE;
  v_rattachement jsonb;
  v_version_finale bigint;
  v_snapshot jsonb;
BEGIN
  IF v_uid IS NULL
     OR COALESCE(auth.jwt() ->> 'aal', '') IS DISTINCT FROM 'aal2'
     OR NOT public.est_admin_valide() THEN
    RAISE EXCEPTION 'Administrateur AAL2 autorisé requis'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Établissement introuvable' USING ERRCODE = 'P0002';
  END IF;
  IF v_etab.verification_source_version IS DISTINCT FROM p_version_attendue THEN
    RAISE EXCEPTION 'Le dossier a changé : rechargez avant de finaliser'
      USING ERRCODE = '40001';
  END IF;

  -- Recalcule toujours le rattachement depuis les sources courantes, notamment
  -- le rapprochement de naissance ajouté par cette migration.
  v_rattachement := public.fn_evaluer_rattachement_etablissement(p_etablissement_id);

  SELECT * INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id
  FOR UPDATE;

  IF v_etab.siret_verifie IS NOT TRUE OR v_etab.siret_est_actif IS FALSE THEN
    RAISE EXCEPTION 'Le SIRET officiel actif doit être vérifié'
      USING ERRCODE = '22023';
  END IF;
  IF v_etab.finess IS NULL OR v_etab.finess_verifie IS NOT TRUE THEN
    RAISE EXCEPTION 'Le FINESS officiel doit être vérifié'
      USING ERRCODE = '22023';
  END IF;
  IF v_etab.representant_identite_verifiee IS NOT TRUE THEN
    RAISE EXCEPTION 'L identité du représentant doit être vérifiée'
      USING ERRCODE = '22023';
  END IF;
  IF v_etab.rattachement_verifie IS NOT TRUE THEN
    RAISE EXCEPTION 'L habilitation du représentant doit être vérifiée'
      USING ERRCODE = '22023';
  END IF;
  IF v_etab.contrat_service_signe IS NOT TRUE THEN
    RAISE EXCEPTION 'Le contrat de service Jolene doit être signé'
      USING ERRCODE = '22023';
  END IF;

  v_snapshot := jsonb_build_object(
    'source_version', v_etab.verification_source_version,
    'siret', v_etab.siret,
    'siret_verifie', v_etab.siret_verifie,
    'finess', v_etab.finess,
    'finess_verifie', v_etab.finess_verifie,
    'representant_identite_verifiee', v_etab.representant_identite_verifiee,
    'representant_piece_s3_key', v_etab.representant_piece_s3_key,
    'justificatif_fonction_verifie', v_etab.justificatif_fonction_verifie,
    'justificatif_fonction_s3_key', v_etab.justificatif_fonction_s3_key,
    'rattachement_methode', v_etab.rattachement_methode,
    'rattachement_verifie', v_etab.rattachement_verifie,
    'contrat_service_signe', v_etab.contrat_service_signe,
    'rattachement_recalcule', v_rattachement
  );

  UPDATE public.etablissements
  SET statut_verification = 'VERIFIE',
      peut_publier_missions = true,
      verifie_le = now(),
      verifie_par = v_uid,
      motif_rejet = NULL,
      modifie_le = now()
  WHERE id = p_etablissement_id;

  SELECT verification_source_version INTO v_version_finale
  FROM public.etablissements
  WHERE id = p_etablissement_id;

  INSERT INTO public.etablissement_preuve_audit (
    etablissement_id, preuve, evenement, acteur_id, source_version,
    source_snapshot, motif
  ) VALUES (
    p_etablissement_id, 'DOSSIER', 'FINALISE', v_uid,
    v_etab.verification_source_version, v_snapshot,
    'Toutes les gates serveur sont satisfaites'
  );

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_PLATEFORME', 'ADMIN_ACTION', 'etablissement',
    p_etablissement_id,
    jsonb_build_object(
      'sous_action', 'FINALISATION_VERIFICATION_ETABLISSEMENT',
      'source_snapshot', v_snapshot
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'nom', v_etab.nom,
    'verification_source_version', v_version_finale
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_finaliser_verification_etablissement(
  uuid, bigint
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_finaliser_verification_etablissement(
  uuid, bigint
) TO authenticated;

-- Les anciens endpoints sans CAS ne doivent plus être appelables par le
-- navigateur admin. Le service_role les conserve uniquement pour compatibilité
-- de migrations/ops historiques; la nouvelle UI utilise les RPC ci-dessus.
REVOKE EXECUTE ON FUNCTION public.fn_admin_valider_etablissement(uuid)
  FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_admin_rejeter_etablissement(uuid, text)
  FROM authenticated;
