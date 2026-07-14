-- Documents, RIB et démarrage de mission : invariants transactionnels finaux.
-- Les preuves historiques sont conservées (y compris les données de démo),
-- mais une seule version courante existe par classe de preuve.

-- ---------------------------------------------------------------------------
-- 1. Remplacement atomique d'une preuve soignant
-- ---------------------------------------------------------------------------

ALTER TABLE public.documents_soignants
  ADD COLUMN IF NOT EXISTS revoque_le timestamptz,
  ADD COLUMN IF NOT EXISTS revoque_raison text,
  ADD COLUMN IF NOT EXISTS remplace_par_document_id uuid;

-- Une mission attribuée ne doit jamais empêcher le dépôt d'un document plus
-- récent. La mission existante n'est pas annulée ; son premier pointage sera
-- simplement bloqué tant que la nouvelle preuve n'est pas vérifiée.
DROP TRIGGER IF EXISTS trg_05_bloquer_retrait_preuve_mission_active
  ON public.documents_soignants;
DROP FUNCTION IF EXISTS public.fn_bloquer_retrait_preuve_mission_active();

CREATE OR REPLACE FUNCTION public.fn_remplacer_preuves_documentaires_actives()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_classe text;
  v_ids_revoques jsonb := '[]'::jsonb;
  v_document_server_update_precedent text := COALESCE(
    current_setting('jolene.document_server_update', true),
    ''
  );
BEGIN
  IF NEW.supprime_le IS NOT NULL OR NEW.revoque_le IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_classe := CASE
    WHEN NEW.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
      THEN 'IDENTITE_OFFICIELLE'
    ELSE NEW.type_document::text
  END;
  PERFORM pg_advisory_xact_lock(
    hashtextextended(NEW.soignant_id::text || ':preuve:' || v_classe, 0)
  );

  PERFORM set_config('jolene.document_replacement', 'true', true);
  -- La révocation invalide aussi l'identifiant CAS d'une analyse IA en vol.
  -- Le trigger de protection documentaire n'autorise cette écriture sensible
  -- que sous le contexte serveur borné au trigger de remplacement.
  PERFORM set_config('jolene.document_server_update', 'true', true);
  WITH revoquees AS (
    UPDATE public.documents_soignants precedent
    SET supprime_le = now(),
        revoque_le = now(),
        revoque_raison = 'REMPLACEMENT',
        remplace_par_document_id = NEW.id,
        verification_attempt_id = NULL,
        modifie_le = now()
    WHERE precedent.soignant_id = NEW.soignant_id
      AND precedent.id IS DISTINCT FROM NEW.id
      AND precedent.supprime_le IS NULL
      AND precedent.revoque_le IS NULL
      AND CASE
        WHEN precedent.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
          THEN 'IDENTITE_OFFICIELLE'
        ELSE precedent.type_document::text
      END = v_classe
    RETURNING precedent.id
  )
  SELECT COALESCE(jsonb_agg(id), '[]'::jsonb)
    INTO v_ids_revoques
  FROM revoquees;
  PERFORM set_config(
    'jolene.document_server_update',
    v_document_server_update_precedent,
    true
  );
  PERFORM set_config('jolene.document_replacement', '', true);

  IF jsonb_array_length(v_ids_revoques) > 0 THEN
    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := NEW.soignant_id,
      p_type_acteur := 'SOIGNANT',
      p_action := 'VERIFICATION_DOCUMENT',
      p_type_ressource := 'document_soignant',
      p_id_ressource := NEW.id,
      p_details := jsonb_build_object(
        'sous_action', 'REMPLACEMENT_PREUVE',
        'classe_preuve', v_classe,
        'documents_revoques', v_ids_revoques
      )
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_10_remplacer_preuves_documentaires_actives
  ON public.documents_soignants;
CREATE TRIGGER trg_10_remplacer_preuves_documentaires_actives
BEFORE INSERT ON public.documents_soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_remplacer_preuves_documentaires_actives();

REVOKE ALL ON FUNCTION public.fn_remplacer_preuves_documentaires_actives()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_remplacer_preuves_documentaires_actives()
  TO service_role;

-- Aucun UPDATE de réconciliation n'est exécuté ici : les lignes historiques
-- et de démonstration restent intégralement visibles. Pour tout nouveau dépôt,
-- le verrou transactionnel du trigger ci-dessus sérialise la classe de preuve
-- et révoque atomiquement les seules versions qui étaient alors courantes.

-- Les historiques existants ne sont ni masqués ni réconciliés par cette
-- migration. L'unicité des nouveaux dépôts est garantie par le verrou
-- transactionnel du trigger ci-dessus ; aucun index rétroactif ne doit faire
-- échouer le déploiement sur des doublons de démonstration déjà présents.

CREATE OR REPLACE FUNCTION public.fn_remplacer_document_soignant(
  p_type_document text,
  p_libelle text,
  p_s3_cle text,
  p_nom_fichier text,
  p_type_mime text,
  p_taille_octets bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_type public.type_document;
  v_doc_id uuid;
  v_doc_est_actif boolean;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typname = 'type_document'
      AND e.enumlabel = p_type_document
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_DOCUMENT_INVALIDE');
  END IF;
  v_type := p_type_document::public.type_document;

  IF p_s3_cle IS NULL
     OR length(p_s3_cle) > 512
     OR p_s3_cle NOT LIKE v_uid::text || '/documents/' || p_type_document || '/%'
     OR p_s3_cle LIKE '%..%'
     OR p_s3_cle LIKE E'%\\%'
     OR split_part(p_s3_cle, '/', 4) !~ '^[A-Za-z0-9._-]+$' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CHEMIN_DOCUMENT_INVALIDE');
  END IF;
  IF p_type_mime NOT IN ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')
     OR p_taille_octets IS NULL OR p_taille_octets < 1
     OR p_taille_octets > 10485760
     OR NULLIF(btrim(COALESCE(p_nom_fichier, '')), '') IS NULL
     OR length(p_nom_fichier) > 255
     OR length(COALESCE(p_libelle, '')) > 500 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'METADONNEES_DOCUMENT_INVALIDES');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('document:' || p_s3_cle, 0));
  SELECT id, supprime_le IS NULL AND revoque_le IS NULL
  INTO v_doc_id, v_doc_est_actif
  FROM public.documents_soignants
  WHERE soignant_id = v_uid AND s3_bucket = 'jolene-documents' AND s3_cle = p_s3_cle
  ORDER BY televerse_le DESC NULLS LAST
  LIMIT 1;
  IF v_doc_id IS NOT NULL THEN
    IF v_doc_est_actif IS NOT TRUE THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'DOCUMENT_INACTIF'
      );
    END IF;
    RETURN jsonb_build_object('success', true, 'document_id', v_doc_id, 'idempotent', true);
  END IF;

  PERFORM set_config('jolene.document_server_update', 'true', true);
  INSERT INTO public.documents_soignants (
    soignant_id, type_document, libelle, s3_bucket, s3_cle,
    nom_fichier, type_mime, taille_octets, statut_verification,
    verifie_par, verifie_le, resultat_ia
  ) VALUES (
    v_uid, v_type, NULLIF(left(btrim(COALESCE(p_libelle, '')), 500), ''),
    'jolene-documents', p_s3_cle, left(btrim(p_nom_fichier), 255),
    p_type_mime, p_taille_octets, 'EN_ATTENTE', NULL, NULL, NULL
  ) RETURNING id INTO v_doc_id;
  PERFORM set_config('jolene.document_server_update', '', true);

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'DOCUMENT_TELEVERSEMENT',
    p_type_ressource := 'document_soignant',
    p_id_ressource := v_doc_id,
    p_cle_s3 := p_s3_cle,
    p_details := jsonb_build_object(
      'type_document', p_type_document,
      'taille_octets', p_taille_octets,
      'remplacement_atomique', true
    )
  );
  RETURN jsonb_build_object('success', true, 'document_id', v_doc_id, 'idempotent', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_remplacer_document_soignant(
  text, text, text, text, text, bigint
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_remplacer_document_soignant(
  text, text, text, text, text, bigint
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_declarer_heures_externes_avec_document(
  p_employeur_nom text,
  p_employeur_type text,
  p_date_debut date,
  p_date_fin date,
  p_heures_declarees numeric,
  p_type_preuve text,
  p_s3_cle text,
  p_nom_fichier text,
  p_type_mime text,
  p_taille_octets bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_document jsonb;
  v_document_id uuid;
  v_heures_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_type_preuve NOT IN ('BULLETIN_PAIE', 'ATTESTATION_EMPLOYEUR', 'CERTIFICAT_TRAVAIL')
     OR NULLIF(btrim(COALESCE(p_employeur_nom, '')), '') IS NULL
     OR length(p_employeur_nom) > 255
     OR p_date_debut IS NULL OR p_date_fin IS NULL OR p_date_fin < p_date_debut
     OR p_heures_declarees IS NULL OR p_heures_declarees < 1 OR p_heures_declarees > 10000 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DECLARATION_INVALIDE');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('heures:' || COALESCE(p_s3_cle, ''), 0));
  v_document := public.fn_remplacer_document_soignant(
    p_type_preuve, 'Justificatif d''heures externes', p_s3_cle,
    p_nom_fichier, p_type_mime, p_taille_octets
  );
  IF COALESCE((v_document->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_document;
  END IF;
  v_document_id := (v_document->>'document_id')::uuid;

  SELECT id INTO v_heures_id
  FROM public.heures_externes
  WHERE soignant_id = v_uid AND document_id = v_document_id
  LIMIT 1;
  IF v_heures_id IS NULL THEN
    INSERT INTO public.heures_externes (
      soignant_id, employeur_nom, employeur_type, date_debut, date_fin,
      heures_declarees, document_id, type_preuve, statut
    ) VALUES (
      v_uid, left(btrim(p_employeur_nom), 255),
      NULLIF(left(btrim(COALESCE(p_employeur_type, '')), 100), ''),
      p_date_debut, p_date_fin, p_heures_declarees,
      v_document_id, p_type_preuve, 'EN_ATTENTE'
    ) RETURNING id INTO v_heures_id;

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_uid,
      p_type_acteur := 'SOIGNANT',
      p_action := 'HEURES_EXTERNES_DECLAREES',
      p_type_ressource := 'heures_externes',
      p_id_ressource := v_heures_id,
      p_details := jsonb_build_object(
        'document_id', v_document_id,
        'heures', p_heures_declarees,
        'date_debut', p_date_debut,
        'date_fin', p_date_fin
      )
    );
  END IF;
  RETURN jsonb_build_object(
    'success', true,
    'document_id', v_document_id,
    'heures_id', v_heures_id,
    'idempotent', COALESCE((v_document->>'idempotent')::boolean, false)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_declarer_heures_externes_avec_document(
  text, text, date, date, numeric, text, text, text, text, bigint
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_declarer_heures_externes_avec_document(
  text, text, date, date, numeric, text, text, text, text, bigint
) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Toute vérification non concluante possède une vraie revue humaine
-- ---------------------------------------------------------------------------

WITH doublons AS (
  SELECT id,
    row_number() OVER (
      PARTITION BY id_entite
      ORDER BY cree_le DESC NULLS LAST, id DESC
    ) AS rang
  FROM public.file_revue_manuelle
  WHERE type_entite = 'TELEVERSEMENT_DOCUMENT'
    AND statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE')
)
UPDATE public.file_revue_manuelle f
SET statut = 'EXPIRE', expire_le = now()
FROM doublons d
WHERE f.id = d.id AND d.rang > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_file_revue_document_active
  ON public.file_revue_manuelle (id_entite)
  WHERE type_entite = 'TELEVERSEMENT_DOCUMENT'
    AND statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE');

CREATE OR REPLACE FUNCTION public.fn_document_marquer_revue_manuelle(
  p_document_id uuid,
  p_attempt_id uuid,
  p_service text,
  p_motif text,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_doc public.documents_soignants%ROWTYPE;
  v_revue_id uuid;
  v_motif text := left(COALESCE(NULLIF(btrim(p_motif), ''),
    'Vérification automatique non concluante — revue humaine en attente.'), 1000);
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND current_user NOT IN ('postgres', 'supabase_admin', 'service_role') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;
  IF p_document_id IS NULL THEN
    RAISE EXCEPTION 'Document requis' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('revue-document:' || p_document_id::text, 0));
  SELECT * INTO v_doc
  FROM public.documents_soignants
  WHERE id = p_document_id AND supprime_le IS NULL AND revoque_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DOCUMENT_INACTIF');
  END IF;
  IF p_attempt_id IS NOT NULL
     AND v_doc.verification_attempt_id IS DISTINCT FROM p_attempt_id THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TENTATIVE_PERIMEE');
  END IF;

  PERFORM set_config('jolene.document_server_update', 'true', true);
  UPDATE public.documents_soignants
  SET statut_verification = 'REVUE_MANUELLE_REQUISE',
      motif_rejet = v_motif,
      verifie_par = NULL,
      verifie_le = NULL,
      verification_attempt_id = NULL,
      modifie_le = now()
  WHERE id = p_document_id;
  PERFORM set_config('jolene.document_server_update', '', true);

  SELECT id INTO v_revue_id
  FROM public.file_revue_manuelle
  WHERE type_entite = 'TELEVERSEMENT_DOCUMENT'
    AND id_entite = p_document_id
    AND statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE')
  FOR UPDATE;
  IF v_revue_id IS NULL THEN
    INSERT INTO public.file_revue_manuelle (
      type_entite, id_entite, service_en_echec, motif_echec,
      donnees_originales, statut, priorite
    ) VALUES (
      'TELEVERSEMENT_DOCUMENT', p_document_id,
      left(COALESCE(NULLIF(btrim(p_service), ''), 'VERIFICATION_DOCUMENT'), 100),
      v_motif,
      jsonb_build_object(
        'document_id', p_document_id,
        'soignant_id', v_doc.soignant_id,
        'type_document', v_doc.type_document::text,
        'code', left(COALESCE(p_details->>'code', 'NON_CONCLUANT'), 100),
        'mis_en_file_le', now()
      ),
      'EN_ATTENTE', 3
    ) RETURNING id INTO v_revue_id;
  ELSE
    UPDATE public.file_revue_manuelle
    SET motif_echec = v_motif,
        service_en_echec = left(COALESCE(NULLIF(btrim(p_service), ''), service_en_echec), 100),
        donnees_originales = COALESCE(donnees_originales, '{}'::jsonb)
          || jsonb_build_object('code', left(COALESCE(p_details->>'code', 'NON_CONCLUANT'), 100),
                                'derniere_tentative_le', now())
    WHERE id = v_revue_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'revue_id', v_revue_id, 'statut', 'EN_ATTENTE_ATTRIBUTION');
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_document_marquer_revue_manuelle(
  uuid, uuid, text, text, jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_document_marquer_revue_manuelle(
  uuid, uuid, text, text, jsonb
) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_demander_revue_document(
  p_document_id uuid,
  p_motif text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_doc public.documents_soignants%ROWTYPE;
  v_revue_id uuid;
  v_motif text := left(btrim(COALESCE(p_motif, '')), 1000);
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF length(v_motif) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_INVALIDE');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('revue-document:' || p_document_id::text, 0));
  SELECT * INTO v_doc
  FROM public.documents_soignants
  WHERE id = p_document_id AND soignant_id = v_uid
    AND supprime_le IS NULL AND revoque_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DOCUMENT_INTROUVABLE');
  END IF;

  SELECT id INTO v_revue_id
  FROM public.file_revue_manuelle
  WHERE type_entite = 'TELEVERSEMENT_DOCUMENT'
    AND id_entite = p_document_id
    AND statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE')
  FOR UPDATE;
  IF v_revue_id IS NULL THEN
    INSERT INTO public.file_revue_manuelle (
      type_entite, id_entite, service_en_echec, motif_echec,
      donnees_originales, statut, priorite
    ) VALUES (
      'TELEVERSEMENT_DOCUMENT', p_document_id,
      'REVUE_DEMANDEE_PAR_SOIGNANT', v_motif,
      jsonb_build_object(
        'document_id', p_document_id,
        'soignant_id', v_uid,
        'type_document', v_doc.type_document::text,
        'ancien_statut', v_doc.statut_verification::text,
        'demande_le', now()
      ),
      'EN_ATTENTE', 3
    ) RETURNING id INTO v_revue_id;
  END IF;

  PERFORM set_config('jolene.document_server_update', 'true', true);
  UPDATE public.documents_soignants
  SET statut_verification = 'REVUE_MANUELLE_REQUISE',
      motif_rejet = 'Demande transmise — en attente d''attribution à un membre de l''équipe.',
      verifie_par = NULL,
      verifie_le = NULL,
      verification_attempt_id = NULL,
      modifie_le = now()
  WHERE id = p_document_id;
  PERFORM set_config('jolene.document_server_update', '', true);

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'VERIFICATION_DOCUMENT',
    p_type_ressource := 'document_soignant',
    p_id_ressource := p_document_id,
    p_details := jsonb_build_object(
      'sous_action', 'REVUE_MANUELLE_DEMANDEE',
      'revue_id', v_revue_id
    )
  );
  RETURN jsonb_build_object(
    'success', true,
    'revue_id', v_revue_id,
    'message', 'Demande transmise — en attente d''attribution.'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_demander_revue_document(uuid, text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.fn_demander_revue_document(uuid, text)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. TOCTOU : contrat et documents sont revalidés au premier pointage
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_exiger_conformite_demarrage_mission(
  p_mission_id uuid,
  p_soignant_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_regime text;
BEGIN
  IF p_mission_id IS NULL OR p_soignant_id IS NULL THEN
    RAISE EXCEPTION 'Mission et soignant requis' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_mission
  FROM public.missions
  WHERE id = p_mission_id
  FOR SHARE;
  IF NOT FOUND
     OR v_mission.soignant_assigne_id IS DISTINCT FROM p_soignant_id THEN
    RAISE EXCEPTION 'Le soignant n''est pas affecté à cette mission.'
      USING ERRCODE = '42501';
  END IF;
  IF v_mission.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN
    RAISE EXCEPTION 'La mission ne peut pas être démarrée dans son état actuel.'
      USING ERRCODE = '23514';
  END IF;

  -- Snapshot transactionnel des preuves et du profil. L'ordre
  -- mission -> documents -> soignant -> contrats suit celui des triggers de
  -- remplacement/RIB afin d'éviter un deadlock. Une révocation concurrente
  -- finit donc avant ce contrôle, ou attend la fin du démarrage.
  PERFORM 1
  FROM public.documents_soignants ds
  WHERE ds.soignant_id = p_soignant_id
    AND ds.supprime_le IS NULL
    AND ds.revoque_le IS NULL
  ORDER BY ds.id
  FOR SHARE;

  PERFORM 1
  FROM public.soignants s
  WHERE s.id = p_soignant_id
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profil soignant introuvable.' USING ERRCODE = '23503';
  END IF;

  PERFORM 1
  FROM public.contrats_mission cm
  WHERE cm.mission_id = p_mission_id
    AND cm.soignant_id = p_soignant_id
  ORDER BY cm.id
  FOR SHARE;

  IF NOT EXISTS (
    SELECT 1
    FROM public.contrats_mission cm
    WHERE cm.mission_id = p_mission_id
      AND cm.soignant_id = p_soignant_id
      AND cm.statut = 'SIGNE_COMPLET'
      AND cm.signature_soignant IS TRUE
      AND cm.signature_etablissement IS TRUE
  ) THEN
    RAISE EXCEPTION 'Le contrat signé par les deux parties est requis avant le pointage.'
      USING ERRCODE = '23514';
  END IF;

  v_regime := COALESCE(v_mission.type_contrat_applique::text, 'SALARIE');
  IF NOT public.fn_documents_ok_pour_mission(p_soignant_id, v_regime) THEN
    RAISE EXCEPTION 'Les justificatifs requis ne sont plus tous vérifiés. Déposez ou faites valider la preuve courante avant de démarrer.'
      USING ERRCODE = '23514';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_exiger_conformite_demarrage_mission(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_exiger_conformite_demarrage_mission(uuid, uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.trg_exiger_conformite_premier_pointage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.pointage_arrivee_le IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.pointage_arrivee_le IS NULL) THEN
    PERFORM public.fn_exiger_conformite_demarrage_mission(
      NEW.mission_id,
      NEW.soignant_id
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_01_exiger_conformite_premier_pointage
  ON public.presences;
CREATE TRIGGER trg_01_exiger_conformite_premier_pointage
BEFORE INSERT OR UPDATE OF pointage_arrivee_le ON public.presences
FOR EACH ROW
EXECUTE FUNCTION public.trg_exiger_conformite_premier_pointage();

CREATE OR REPLACE FUNCTION public.trg_exiger_conformite_mission_en_cours()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.statut = 'EN_COURS'
     AND OLD.statut IS DISTINCT FROM 'EN_COURS' THEN
    PERFORM public.fn_exiger_conformite_demarrage_mission(
      NEW.id,
      NEW.soignant_assigne_id
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_01_exiger_conformite_mission_en_cours
  ON public.missions;
CREATE TRIGGER trg_01_exiger_conformite_mission_en_cours
BEFORE UPDATE OF statut ON public.missions
FOR EACH ROW
EXECUTE FUNCTION public.trg_exiger_conformite_mission_en_cours();

-- Une ligne n'existe pas encore pendant un BEFORE INSERT : la fonction de
-- revalidation ci-dessus ne peut donc pas la relire avec FOR SHARE. On ferme
-- séparément la voie PostgREST qui permettrait sinon de créer directement un
-- historique, une mission EN_COURS ou une mission déjà terminée. La seule
-- création applicative autorisée est une mission OUVERTE et non affectée.
-- Les seeds transactionnels réservés au service_role restent possibles sans
-- masquer ni altérer les données de démonstration existantes.
CREATE OR REPLACE FUNCTION public.trg_verrouiller_etat_initial_mission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_role text := COALESCE(auth.role(), '');
  v_operation_interne text := COALESCE(
    current_setting('app.internal_operation', true), ''
  );
  v_raison_seed text := COALESCE(
    current_setting('jolene.admin_seed_override_reason', true), ''
  );
BEGIN
  -- Migrations/maintenance SQL sans identité applicative.
  IF session_user IN ('postgres', 'supabase_admin')
     AND auth.uid() IS NULL
     AND v_role NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  -- Seeds E2E explicites : jamais accessible à un JWT utilisateur.
  IF v_role = 'service_role'
     AND (v_operation_interne = 'true' OR NULLIF(btrim(v_raison_seed), '') IS NOT NULL) THEN
    RETURN NEW;
  END IF;

  IF NEW.statut IS DISTINCT FROM 'OUVERTE'
     OR NEW.soignant_assigne_id IS NOT NULL THEN
    RAISE EXCEPTION 'Une mission doit être créée OUVERTE et sans soignant affecté.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_00_verrouiller_etat_initial_mission
  ON public.missions;
CREATE TRIGGER trg_00_verrouiller_etat_initial_mission
BEFORE INSERT ON public.missions
FOR EACH ROW
EXECUTE FUNCTION public.trg_verrouiller_etat_initial_mission();

CREATE OR REPLACE FUNCTION public.trg_exiger_conformite_code_pointage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
BEGIN
  SELECT * INTO v_mission
  FROM public.missions
  WHERE id = NEW.mission_id
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mission introuvable' USING ERRCODE = '23503';
  END IF;

  -- Une mission en cours peut toujours générer un code de départ, même si une
  -- preuve a expiré entre-temps : on ne bloque jamais la sortie du soignant.
  IF v_mission.statut = 'EN_COURS' THEN
    RETURN NEW;
  END IF;
  IF v_mission.statut IS DISTINCT FROM 'ASSIGNEE'
     OR v_mission.soignant_assigne_id IS NULL THEN
    RAISE EXCEPTION 'Le code de pointage ne peut être généré qu''après affectation.'
      USING ERRCODE = '23514';
  END IF;
  PERFORM public.fn_exiger_conformite_demarrage_mission(
    v_mission.id,
    v_mission.soignant_assigne_id
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_01_exiger_conformite_qr_mission
  ON public.qr_codes_mission;
CREATE TRIGGER trg_01_exiger_conformite_qr_mission
BEFORE INSERT ON public.qr_codes_mission
FOR EACH ROW
EXECUTE FUNCTION public.trg_exiger_conformite_code_pointage();

DROP TRIGGER IF EXISTS trg_01_exiger_conformite_code_secours_mission
  ON public.codes_secours_mission;
CREATE TRIGGER trg_01_exiger_conformite_code_secours_mission
BEFORE INSERT ON public.codes_secours_mission
FOR EACH ROW
EXECUTE FUNCTION public.trg_exiger_conformite_code_pointage();

REVOKE ALL ON FUNCTION public.trg_exiger_conformite_premier_pointage()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_exiger_conformite_mission_en_cours()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_verrouiller_etat_initial_mission()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_exiger_conformite_code_pointage()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_exiger_conformite_premier_pointage()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.trg_exiger_conformite_mission_en_cours()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.trg_verrouiller_etat_initial_mission()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.trg_exiger_conformite_code_pointage()
  TO service_role;

-- Ces quatre parcours historiques écrivent tous dans les tables protégées
-- ci-dessus : fn_pointer_arrivee, fn_valider_scan_qr,
-- fn_valider_code_secours et fn_scanner_code_pointage. Les générateurs
-- fn_generer_qr_mission et fn_generer_code_secours_mission sont protégés par
-- les triggers INSERT correspondants.

-- ---------------------------------------------------------------------------
-- 4. IBAN : liaison exacte au RIB courant et à l'identité courante
-- ---------------------------------------------------------------------------

ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS iban_source_document_id uuid,
  ADD COLUMN IF NOT EXISTS iban_identite_document_id uuid,
  ADD COLUMN IF NOT EXISTS iban_source_s3_cle text,
  ADD COLUMN IF NOT EXISTS iban_empreinte_sha256 text,
  ADD COLUMN IF NOT EXISTS iban_verifie_le timestamptz,
  ADD COLUMN IF NOT EXISTS iban_titulaire_coherent boolean NOT NULL DEFAULT false;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'soignants_iban_identite_document_id_fkey'
      AND conrelid = 'public.soignants'::regclass
  ) THEN
    ALTER TABLE public.soignants
      ADD CONSTRAINT soignants_iban_identite_document_id_fkey
      FOREIGN KEY (iban_identite_document_id)
      REFERENCES public.documents_soignants(id)
      ON DELETE SET NULL
      DEFERRABLE INITIALLY DEFERRED;
  END IF;
END;
$migration$;

ALTER TABLE public.soignants
  DROP CONSTRAINT IF EXISTS soignants_iban_provenance_coherente_check;
ALTER TABLE public.soignants
  ADD CONSTRAINT soignants_iban_provenance_coherente_check
  CHECK (
    iban_titulaire_coherent IS FALSE
    OR (
      iban_source_document_id IS NOT NULL
      AND iban_identite_document_id IS NOT NULL
      AND NULLIF(iban_source_s3_cle, '') IS NOT NULL
      AND iban_empreinte_sha256 ~ '^[0-9a-f]{64}$'
      AND iban_verifie_le IS NOT NULL
    )
  );

COMMENT ON COLUMN public.soignants.iban_empreinte_sha256 IS
  'Empreinte SHA-256 de l IBAN normalisé salée par l UUID de la version RIB ; jamais l IBAN dans l audit ou le résultat IA.';

CREATE OR REPLACE FUNCTION public.fn_proteger_provenance_iban_soignant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF auth.role() = 'service_role'
     OR auth.uid() IS NULL
     OR session_user IN ('postgres', 'supabase_admin')
     OR COALESCE(current_setting('jolene.bank_server_update', true), '') = 'true' THEN
    RETURN NEW;
  END IF;
  IF NEW.iban_virement IS DISTINCT FROM OLD.iban_virement
     OR NEW.iban_titulaire IS DISTINCT FROM OLD.iban_titulaire
     OR NEW.iban_last4 IS DISTINCT FROM OLD.iban_last4
     OR NEW.iban_source_document_id IS DISTINCT FROM OLD.iban_source_document_id
     OR NEW.iban_identite_document_id IS DISTINCT FROM OLD.iban_identite_document_id
     OR NEW.iban_source_s3_cle IS DISTINCT FROM OLD.iban_source_s3_cle
     OR NEW.iban_empreinte_sha256 IS DISTINCT FROM OLD.iban_empreinte_sha256
     OR NEW.iban_verifie_le IS DISTINCT FROM OLD.iban_verifie_le
     OR NEW.iban_titulaire_coherent IS DISTINCT FROM OLD.iban_titulaire_coherent THEN
    RAISE EXCEPTION 'Les coordonnées bancaires sont enregistrées exclusivement depuis un RIB courant vérifié.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_proteger_provenance_iban_soignant
  ON public.soignants;
CREATE TRIGGER trg_proteger_provenance_iban_soignant
BEFORE UPDATE OF iban_virement, iban_titulaire, iban_last4,
  iban_source_document_id, iban_identite_document_id, iban_source_s3_cle,
  iban_empreinte_sha256, iban_verifie_le, iban_titulaire_coherent
ON public.soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_proteger_provenance_iban_soignant();

CREATE OR REPLACE FUNCTION public.fn_lier_iban_verifie_document(
  p_document_id uuid,
  p_expected_s3_cle text,
  p_iban text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $function$
DECLARE
  v_doc public.documents_soignants%ROWTYPE;
  v_soignant public.soignants%ROWTYPE;
  v_identite public.documents_soignants%ROWTYPE;
  v_iban text;
  v_hash text;
  v_titulaire text;
  v_action text;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND current_user NOT IN ('postgres', 'supabase_admin', 'service_role') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;
  v_iban := upper(regexp_replace(COALESCE(p_iban, ''), '[^A-Za-z0-9]', '', 'g'));
  IF NOT public.fn_iban_est_valide(v_iban) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'IBAN_INVALIDE');
  END IF;

  SELECT * INTO v_doc
  FROM public.documents_soignants
  WHERE id = p_document_id
    AND type_document = 'RIB'
    AND s3_cle = p_expected_s3_cle
    AND statut_verification = 'VERIFIE'
    AND supprime_le IS NULL AND revoque_le IS NULL
  FOR SHARE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'RIB_COURANT_REQUIS');
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = v_doc.soignant_id AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND
     OR v_soignant.identite_verifiee IS NOT TRUE
     OR v_soignant.coherence_identite IS DISTINCT FROM 'COHERENT' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'IDENTITE_VERIFIEE_REQUISE');
  END IF;

  SELECT * INTO v_identite
  FROM public.documents_soignants
  WHERE soignant_id = v_soignant.id
    AND type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
    AND statut_verification = 'VERIFIE'
    AND supprime_le IS NULL AND revoque_le IS NULL
  ORDER BY verifie_le DESC NULLS LAST, televerse_le DESC NULLS LAST, id DESC
  LIMIT 1
  FOR SHARE;
  IF NOT FOUND
     OR v_identite.coherence_nom IS NOT TRUE
     OR NOT public.fn_noms_personne_correspondent(
       v_soignant.nom, v_soignant.prenom,
       v_identite.nom_extrait_ia, v_identite.prenom_extrait_ia
     ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'IDENTITE_COURANTE_REQUISE');
  END IF;

  v_hash := encode(
    extensions.digest(convert_to(v_iban || ':' || v_doc.id::text, 'UTF8'), 'sha256'),
    'hex'
  );
  IF COALESCE(v_doc.resultat_ia->>'verdict_serveur', '') <> 'VERIFIE'
     OR COALESCE(v_doc.resultat_ia->>'iban_valide', '') <> 'true'
     OR COALESCE(v_doc.resultat_ia->>'iban_last4', '') <> right(v_iban, 4)
     OR COALESCE(v_doc.resultat_ia->>'iban_preuve_hash_v1', '') <> v_hash
     OR v_doc.coherence_nom IS NOT TRUE
     OR NOT public.fn_noms_personne_correspondent(
       v_soignant.nom, v_soignant.prenom,
       v_doc.nom_extrait_ia, v_doc.prenom_extrait_ia
     ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'RIB_NON_CONCORDANT');
  END IF;

  v_titulaire := btrim(v_soignant.prenom || ' ' || v_soignant.nom);
  v_action := CASE WHEN NULLIF(v_soignant.iban_virement, '') IS NULL
    THEN 'IBAN_RENSEIGNE' ELSE 'IBAN_MODIFIE' END;
  PERFORM set_config('jolene.bank_server_update', 'true', true);
  UPDATE public.soignants
  SET iban_virement = v_iban,
      iban_titulaire = v_titulaire,
      iban_last4 = right(v_iban, 4),
      iban_source_document_id = v_doc.id,
      iban_identite_document_id = v_identite.id,
      iban_source_s3_cle = v_doc.s3_cle,
      iban_empreinte_sha256 = v_hash,
      iban_verifie_le = now(),
      iban_titulaire_coherent = true,
      modifie_le = now()
  WHERE id = v_soignant.id;
  PERFORM set_config('jolene.bank_server_update', '', true);

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_soignant.id,
    p_type_acteur := 'SYSTEME',
    p_action := v_action,
    p_type_ressource := 'soignant',
    p_id_ressource := v_soignant.id,
    p_details := jsonb_build_object(
      'iban_last4', right(v_iban, 4),
      'source_document_id', v_doc.id,
      'identite_document_id', v_identite.id,
      'liaison_directe', true
    )
  );
  RETURN jsonb_build_object(
    'success', true,
    'iban_last4', right(v_iban, 4),
    'titulaire', v_titulaire,
    'source_document_id', v_doc.id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_lier_iban_verifie_document(uuid, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_lier_iban_verifie_document(uuid, text, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_enregistrer_mon_iban(
  p_iban text,
  p_titulaire text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_soignant public.soignants%ROWTYPE;
  v_rib public.documents_soignants%ROWTYPE;
  v_titulaire_normalise text;
  v_attendu_1 text;
  v_attendu_2 text;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = v_uid AND supprime_le IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'PROFIL_INTROUVABLE');
  END IF;

  v_titulaire_normalise := btrim(regexp_replace(
    public.fn_normaliser_nom(COALESCE(p_titulaire, '')), '[^a-z0-9]+', ' ', 'g'
  ));
  v_attendu_1 := btrim(regexp_replace(
    public.fn_normaliser_nom(v_soignant.prenom || ' ' || v_soignant.nom), '[^a-z0-9]+', ' ', 'g'
  ));
  v_attendu_2 := btrim(regexp_replace(
    public.fn_normaliser_nom(v_soignant.nom || ' ' || v_soignant.prenom), '[^a-z0-9]+', ' ', 'g'
  ));
  IF v_titulaire_normalise NOT IN (v_attendu_1, v_attendu_2) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'TITULAIRE_NON_CONCORDANT',
      'error', 'Le titulaire doit correspondre exactement à votre identité vérifiée.'
    );
  END IF;

  SELECT * INTO v_rib
  FROM public.documents_soignants
  WHERE soignant_id = v_uid
    AND type_document = 'RIB'
    AND statut_verification = 'VERIFIE'
    AND supprime_le IS NULL AND revoque_le IS NULL
  ORDER BY verifie_le DESC NULLS LAST, televerse_le DESC NULLS LAST, id DESC
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'RIB_VERIFIE_REQUIS',
      'error', 'Téléversez puis faites vérifier le RIB correspondant.'
    );
  END IF;
  RETURN public.fn_lier_iban_verifie_document(v_rib.id, v_rib.s3_cle, p_iban);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_enregistrer_mon_iban(text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_enregistrer_mon_iban(text, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_coordonnees_bancaires_soignant_verifiees(
  p_soignant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $function$
DECLARE
  v_s public.soignants%ROWTYPE;
  v_rib public.documents_soignants%ROWTYPE;
  v_identite public.documents_soignants%ROWTYPE;
  v_hash text;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND current_user NOT IN ('postgres', 'supabase_admin', 'service_role') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_s FROM public.soignants
  WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND
     OR NULLIF(v_s.iban_virement, '') IS NULL
     OR v_s.iban_titulaire_coherent IS NOT TRUE
     OR v_s.identite_verifiee IS NOT TRUE
     OR v_s.coherence_identite IS DISTINCT FROM 'COHERENT'
     OR NOT public.fn_iban_est_valide(v_s.iban_virement) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'RIB_VERIFIE_REQUIS');
  END IF;

  SELECT * INTO v_rib FROM public.documents_soignants
  WHERE id = v_s.iban_source_document_id
    AND soignant_id = v_s.id
    AND type_document = 'RIB'
    AND s3_cle = v_s.iban_source_s3_cle
    AND statut_verification = 'VERIFIE'
    AND supprime_le IS NULL AND revoque_le IS NULL;
  SELECT * INTO v_identite FROM public.documents_soignants
  WHERE id = v_s.iban_identite_document_id
    AND soignant_id = v_s.id
    AND type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
    AND statut_verification = 'VERIFIE'
    AND supprime_le IS NULL AND revoque_le IS NULL;
  IF v_rib.id IS NULL OR v_identite.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'PREUVE_REVOQUEE');
  END IF;

  v_hash := encode(extensions.digest(
    convert_to(v_s.iban_virement || ':' || v_rib.id::text, 'UTF8'), 'sha256'
  ), 'hex');
  IF v_hash IS DISTINCT FROM v_s.iban_empreinte_sha256
     OR v_hash IS DISTINCT FROM v_rib.resultat_ia->>'iban_preuve_hash_v1'
     OR right(v_s.iban_virement, 4) IS DISTINCT FROM v_rib.resultat_ia->>'iban_last4'
     OR v_rib.resultat_ia->>'verdict_serveur' IS DISTINCT FROM 'VERIFIE'
     OR v_rib.coherence_nom IS NOT TRUE
     OR v_identite.coherence_nom IS NOT TRUE
     OR NOT public.fn_noms_personne_correspondent(
       v_s.nom, v_s.prenom, v_rib.nom_extrait_ia, v_rib.prenom_extrait_ia
     )
     OR NOT public.fn_noms_personne_correspondent(
       v_s.nom, v_s.prenom, v_identite.nom_extrait_ia, v_identite.prenom_extrait_ia
     ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'RIB_NON_CONCORDANT');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'iban', v_s.iban_virement,
    'titulaire', v_s.iban_titulaire,
    'iban_last4', right(v_s.iban_virement, 4),
    'source_document_id', v_rib.id,
    'verifie_le', v_s.iban_verifie_le
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_coordonnees_bancaires_soignant_verifiees(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_coordonnees_bancaires_soignant_verifiees(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_consulter_mon_iban()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_s public.soignants%ROWTYPE;
  v_verifie boolean := false;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;
  SELECT * INTO v_s FROM public.soignants
  WHERE id = v_uid AND supprime_le IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('iban_renseigne', false, 'iban_verifie', false);
  END IF;
  v_verifie := v_s.iban_titulaire_coherent IS TRUE
    AND v_s.iban_verifie_le IS NOT NULL
    AND v_s.iban_empreinte_sha256 ~ '^[0-9a-f]{64}$'
    AND EXISTS (
      SELECT 1 FROM public.documents_soignants ds
      WHERE ds.id = v_s.iban_source_document_id
        AND ds.s3_cle = v_s.iban_source_s3_cle
        AND ds.soignant_id = v_s.id
        AND ds.type_document = 'RIB'
        AND ds.statut_verification = 'VERIFIE'
        AND ds.supprime_le IS NULL AND ds.revoque_le IS NULL
    )
    AND EXISTS (
      SELECT 1 FROM public.documents_soignants ds
      WHERE ds.id = v_s.iban_identite_document_id
        AND ds.soignant_id = v_s.id
        AND ds.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
        AND ds.statut_verification = 'VERIFIE'
        AND ds.supprime_le IS NULL AND ds.revoque_le IS NULL
    );
  RETURN jsonb_build_object(
    'iban_renseigne', NULLIF(v_s.iban_virement, '') IS NOT NULL,
    'iban_verifie', v_verifie,
    'verification_requise', NULLIF(v_s.iban_virement, '') IS NOT NULL AND NOT v_verifie,
    'iban_last4', v_s.iban_last4,
    'iban_titulaire', v_s.iban_titulaire
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_consulter_mon_iban() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_consulter_mon_iban()
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_invalider_provenance_iban_depuis_document()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_document_id uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
  v_type public.type_document := CASE WHEN TG_OP = 'DELETE' THEN OLD.type_document ELSE NEW.type_document END;
BEGIN
  PERFORM set_config('jolene.bank_server_update', 'true', true);
  UPDATE public.soignants
  SET iban_source_document_id = NULL,
      iban_identite_document_id = NULL,
      iban_source_s3_cle = NULL,
      iban_empreinte_sha256 = NULL,
      iban_verifie_le = NULL,
      iban_titulaire_coherent = false,
      modifie_le = now()
  WHERE iban_source_document_id = v_document_id
     OR iban_identite_document_id = v_document_id;
  PERFORM set_config('jolene.bank_server_update', '', true);

  IF v_type = 'RIB' THEN
    UPDATE public.partages_rib
    SET actif = false,
        expire_le = LEAST(COALESCE(expire_le, now()), now())
    WHERE document_rib_id = v_document_id AND actif IS TRUE;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_invalider_provenance_iban_document_update
  ON public.documents_soignants;
CREATE TRIGGER trg_invalider_provenance_iban_document_update
AFTER UPDATE OF statut_verification, resultat_ia, coherence_nom, supprime_le,
  revoque_le, soignant_id, type_document, s3_cle
ON public.documents_soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_invalider_provenance_iban_depuis_document();

DROP TRIGGER IF EXISTS trg_invalider_provenance_iban_document_delete
  ON public.documents_soignants;
CREATE TRIGGER trg_invalider_provenance_iban_document_delete
AFTER DELETE ON public.documents_soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_invalider_provenance_iban_depuis_document();

CREATE OR REPLACE FUNCTION public.fn_invalider_provenance_iban_sur_identite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.nom IS DISTINCT FROM OLD.nom
     OR NEW.prenom IS DISTINCT FROM OLD.prenom
     OR NEW.identite_verifiee IS DISTINCT FROM OLD.identite_verifiee
     OR NEW.coherence_identite IS DISTINCT FROM OLD.coherence_identite THEN
    PERFORM set_config('jolene.bank_server_update', 'true', true);
    UPDATE public.soignants
    SET iban_source_document_id = NULL,
        iban_identite_document_id = NULL,
        iban_source_s3_cle = NULL,
        iban_empreinte_sha256 = NULL,
        iban_verifie_le = NULL,
        iban_titulaire_coherent = false,
        modifie_le = now()
    WHERE id = NEW.id;
    PERFORM set_config('jolene.bank_server_update', '', true);
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_invalider_provenance_iban_sur_identite
  ON public.soignants;
CREATE TRIGGER trg_invalider_provenance_iban_sur_identite
AFTER UPDATE OF nom, prenom, identite_verifiee, coherence_identite
ON public.soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_invalider_provenance_iban_sur_identite();

REVOKE ALL ON FUNCTION public.fn_invalider_provenance_iban_depuis_document()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_invalider_provenance_iban_sur_identite()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_invalider_provenance_iban_depuis_document()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_invalider_provenance_iban_sur_identite()
  TO service_role;

-- Le partage à un établissement ne survit jamais à la révocation ou au
-- remplacement de la version exacte du RIB.
CREATE OR REPLACE FUNCTION public.fn_peut_gerer_objet_jolene(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, storage
AS $function$
  SELECT auth.uid() IS NOT NULL
    AND public.fn_compte_auth_actif()
    AND (
      split_part(p_name, '/', 1) = auth.uid()::text
      OR public.est_admin()
      OR EXISTS (
        SELECT 1
        FROM public.membres_etablissement me
        WHERE me.user_id = auth.uid()
          AND me.actif
          AND me.role IN ('PROPRIETAIRE', 'ADMIN_GROUPE')
          AND split_part(p_name, '/', 1) = me.etablissement_id::text
      )
    );
$function$;

REVOKE ALL ON FUNCTION public.fn_peut_gerer_objet_jolene(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_peut_gerer_objet_jolene(text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_peut_lire_objet_jolene(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, storage
AS $function$
  SELECT auth.uid() IS NOT NULL
    AND public.fn_compte_auth_actif()
    AND (
      public.fn_peut_gerer_objet_jolene(p_name)
      OR EXISTS (
        SELECT 1
        FROM public.documents_soignants ds
        JOIN public.partages_rib pr ON pr.document_rib_id = ds.id
        WHERE ds.s3_bucket = 'jolene-documents'
          AND ds.s3_cle = p_name
          AND ds.type_document = 'RIB'
          AND ds.statut_verification = 'VERIFIE'
          AND ds.supprime_le IS NULL
          AND ds.revoque_le IS NULL
          AND ds.resultat_ia->>'verdict_serveur' = 'VERIFIE'
          AND pr.soignant_id = ds.soignant_id
          AND pr.etablissement_id = public.mon_etablissement_id()
          AND pr.actif IS TRUE
          AND (pr.expire_le IS NULL OR pr.expire_le > now())
      )
    );
$function$;

REVOKE ALL ON FUNCTION public.fn_peut_lire_objet_jolene(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_peut_lire_objet_jolene(text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_consulter_rib_soignant(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_partage public.partages_rib%ROWTYPE;
  v_doc public.documents_soignants%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  SELECT * INTO v_partage
  FROM public.partages_rib
  WHERE mission_id = p_mission_id
    AND (etablissement_id = public.mon_etablissement_id() OR public.est_admin())
    AND actif IS TRUE
    AND (expire_le IS NULL OR expire_le > now())
  ORDER BY partage_le DESC NULLS LAST, id DESC
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND OR v_partage.document_rib_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'PARTAGE_RIB_INACTIF',
      'error', 'Le partage de RIB vérifié n''est pas actif pour cette mission.'
    );
  END IF;

  SELECT * INTO v_doc
  FROM public.documents_soignants
  WHERE id = v_partage.document_rib_id
    AND soignant_id = v_partage.soignant_id
    AND type_document = 'RIB'
    AND statut_verification = 'VERIFIE'
    AND supprime_le IS NULL AND revoque_le IS NULL
    AND resultat_ia->>'verdict_serveur' = 'VERIFIE';
  IF NOT FOUND THEN
    UPDATE public.partages_rib SET actif = false, expire_le = now()
    WHERE id = v_partage.id;
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'RIB_REVOQUE',
      'error', 'Le RIB partagé n''est plus une preuve courante vérifiée.'
    );
  END IF;

  UPDATE public.partages_rib
  SET consulte_le = now(), consulte_par = auth.uid()
  WHERE id = v_partage.id;
  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := auth.uid(),
    p_type_acteur := 'ADMIN_ETABLISSEMENT',
    p_action := 'RIB_CONSULTE',
    p_type_ressource := 'document',
    p_id_ressource := v_doc.id,
    p_details := jsonb_build_object(
      'mission_id', p_mission_id,
      'soignant_id', v_partage.soignant_id
    )
  );
  RETURN jsonb_build_object(
    'success', true,
    'document_id', v_doc.id,
    'nom_fichier', v_doc.nom_fichier,
    's3_cle', v_doc.s3_cle,
    's3_bucket', v_doc.s3_bucket
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_consulter_rib_soignant(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_consulter_rib_soignant(uuid)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. RIB établissement : verdict lié à la version exacte du fichier
-- ---------------------------------------------------------------------------

ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS rib_verifie_s3_key text,
  ADD COLUMN IF NOT EXISTS rib_verifie_source_version bigint;

UPDATE public.etablissements
SET rib_verifie_s3_key = rib_s3_key,
    rib_verifie_source_version = verification_source_version
WHERE rib_ia_coherent IS TRUE
  AND rib_ia_verifie_le IS NOT NULL
  AND rib_s3_key IS NOT NULL
  AND (rib_verifie_s3_key IS NULL OR rib_verifie_source_version IS NULL);

ALTER TABLE public.etablissements
  DROP CONSTRAINT IF EXISTS etablissements_rib_provenance_courante_check;
ALTER TABLE public.etablissements
  ADD CONSTRAINT etablissements_rib_provenance_courante_check
  CHECK (
    rib_ia_coherent IS DISTINCT FROM true
    OR (
      rib_ia_verifie_le IS NOT NULL
      AND rib_verifie_s3_key IS NOT NULL
      AND rib_verifie_s3_key = rib_s3_key
      AND rib_verifie_source_version IS NOT NULL
    )
  );

CREATE OR REPLACE FUNCTION public.fn_appliquer_verification_rib_etablissement(
  p_etablissement_id uuid,
  p_version_attendue bigint,
  p_rib_s3_key text,
  p_nom_etablissement text,
  p_siret_raison_sociale text,
  p_finess_raison_sociale text,
  p_coherent boolean,
  p_resultat jsonb,
  p_iban_last4 text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_etab public.etablissements%ROWTYPE;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND current_user NOT IN ('postgres', 'supabase_admin', 'service_role') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND
     OR v_etab.verification_source_version IS DISTINCT FROM p_version_attendue
     OR v_etab.rib_s3_key IS DISTINCT FROM p_rib_s3_key
     OR v_etab.nom IS DISTINCT FROM p_nom_etablissement
     OR v_etab.siret_raison_sociale IS DISTINCT FROM p_siret_raison_sociale
     OR v_etab.finess_raison_sociale IS DISTINCT FROM p_finess_raison_sociale THEN
    RETURN false;
  END IF;

  UPDATE public.etablissements
  SET rib_ia_resultat = COALESCE(p_resultat, '{}'::jsonb),
      rib_ia_coherent = p_coherent,
      rib_ia_verifie_le = now(),
      iban_last4 = CASE
        WHEN p_coherent IS TRUE AND upper(COALESCE(p_iban_last4, '')) ~ '^[A-Z0-9]{4}$'
          THEN upper(p_iban_last4)
        ELSE NULL
      END,
      rib_verifie_s3_key = CASE WHEN p_coherent IS TRUE THEN p_rib_s3_key ELSE NULL END,
      -- trg_00_versionner_verifications_etablissement incrémente la version
      -- globale pendant cet UPDATE. On journalise la version effectivement
      -- écrite ; les mises à jour sans changement de RIB ne révoquent pas la
      -- provenance bancaire.
      rib_verifie_source_version = CASE WHEN p_coherent IS TRUE THEN p_version_attendue + 1 ELSE NULL END,
      modifie_le = now()
  WHERE id = p_etablissement_id;
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_appliquer_verification_rib_etablissement(
  uuid, bigint, text, text, text, text, boolean, jsonb, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_appliquer_verification_rib_etablissement(
  uuid, bigint, text, text, text, text, boolean, jsonb, text
) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_invalider_provenance_rib_etablissement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.rib_s3_key IS DISTINCT FROM OLD.rib_s3_key
     OR NEW.nom IS DISTINCT FROM OLD.nom
     OR NEW.siret IS DISTINCT FROM OLD.siret
     OR NEW.siret_raison_sociale IS DISTINCT FROM OLD.siret_raison_sociale
     OR NEW.finess IS DISTINCT FROM OLD.finess
     OR NEW.finess_raison_sociale IS DISTINCT FROM OLD.finess_raison_sociale THEN
    -- BEFORE : la ligne NEW est rendue cohérente avant l'évaluation des
    -- contraintes. Un remplacement de fichier reste donc possible et révoque
    -- atomiquement l'ancien verdict, quelle que soit l'ordre des triggers.
    NEW.rib_ia_resultat := NULL;
    NEW.rib_ia_coherent := NULL;
    NEW.rib_ia_verifie_le := NULL;
    NEW.iban_last4 := NULL;
    NEW.rib_verifie_s3_key := NULL;
    NEW.rib_verifie_source_version := NULL;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_invalider_provenance_rib_etablissement
  ON public.etablissements;
DROP TRIGGER IF EXISTS trg_zz_invalider_provenance_rib_etablissement
  ON public.etablissements;
-- Les triggers BEFORE d'un même événement sont exécutés par ordre
-- alphabétique. Le protector historique doit d'abord refuser toute écriture
-- directe d'un verdict ; cette révocation interne s'applique ensuite à la
-- source légitime qui vient d'être modifiée.
CREATE TRIGGER trg_zz_invalider_provenance_rib_etablissement
BEFORE UPDATE OF rib_s3_key, nom, siret, siret_raison_sociale,
  finess, finess_raison_sociale
ON public.etablissements
FOR EACH ROW
EXECUTE FUNCTION public.fn_invalider_provenance_rib_etablissement();

CREATE OR REPLACE FUNCTION public.fn_rib_etablissement_courant_verifie(
  p_etablissement_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.etablissements e
    WHERE e.id = p_etablissement_id
      AND e.supprime_le IS NULL
      AND e.rib_ia_coherent IS TRUE
      AND e.rib_ia_verifie_le IS NOT NULL
      AND e.rib_verifie_s3_key = e.rib_s3_key
      AND e.rib_verifie_source_version IS NOT NULL
      AND e.iban_last4 ~ '^[A-Z0-9]{4}$'
  );
$function$;

REVOKE ALL ON FUNCTION public.fn_invalider_provenance_rib_etablissement()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_rib_etablissement_courant_verifie(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_invalider_provenance_rib_etablissement()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_rib_etablissement_courant_verifie(uuid)
  TO service_role;

-- La file de revue établissement et sa garde AAL2 restent définies par la
-- migration 20260714063000. Ne jamais redéfinir ici sa signature : l'ordre des
-- migrations doit conserver est_admin_valide(), le CAS et le snapshot complet.
