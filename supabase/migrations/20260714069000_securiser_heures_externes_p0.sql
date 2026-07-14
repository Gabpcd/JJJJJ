-- Heures externes du parcours libéral : fermeture P0 du chemin qui permettait
-- au propriétaire de fournir lui-même le verdict et les heures comptabilisées.
--
-- Cette migration ne crée aucune attestation hebdomadaire et ne supprime ni ne
-- masque aucune ligne historique. Les anciennes validations ne sont reconnues
-- par le compteur que lorsqu'une décision admin traçable et une preuve Storage
-- non ambiguë existent déjà ; les autres lignes restent visibles pour revue.

-- ---------------------------------------------------------------------------
-- 1. Versionner la source et matérialiser une provenance serveur vérifiable
-- ---------------------------------------------------------------------------

ALTER TABLE public.heures_externes_soignants
  ADD COLUMN IF NOT EXISTS version_source uuid NOT NULL DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS empreinte_preuve_sha256 text,
  ADD COLUMN IF NOT EXISTS source_validation_serveur text,
  ADD COLUMN IF NOT EXISTS empreinte_snapshot_source text;

CREATE OR REPLACE FUNCTION private.fn_snapshot_heures_externes(
  p_ligne public.heures_externes_soignants
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $function$
  SELECT jsonb_build_object(
    'id', p_ligne.id,
    'soignant_id', p_ligne.soignant_id,
    'etablissement_nom', p_ligne.etablissement_nom,
    'etablissement_type', p_ligne.etablissement_type,
    'date_debut', p_ligne.date_debut,
    'date_fin', p_ligne.date_fin,
    'heures_declarees', p_ligne.heures_declarees,
    'attestation_url', p_ligne.attestation_url,
    'attestation_nom_fichier', p_ligne.attestation_nom_fichier,
    'version_source', p_ligne.version_source
  );
$function$;

CREATE OR REPLACE FUNCTION private.fn_empreinte_snapshot_heures_externes(
  p_ligne public.heures_externes_soignants
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public, extensions
AS $function$
  SELECT encode(
    extensions.digest(
      convert_to(private.fn_snapshot_heures_externes(p_ligne)::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );
$function$;

REVOKE ALL ON FUNCTION private.fn_snapshot_heures_externes(
  public.heures_externes_soignants
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_empreinte_snapshot_heures_externes(
  public.heures_externes_soignants
) FROM PUBLIC, anon, authenticated, service_role;

-- Rattrapage conservateur : une ancienne ligne VALIDE ne garde sa valeur dans
-- le compteur que si elle porte un audit admin indépendant, corrélé à la
-- décision et à sa source, une preuve Storage existante, un chemin non
-- réutilisé et aucune période validée concurrente. valide_par/valide_le seuls
-- ne suffisent pas : ces champs étaient forgeables avant ce verrouillage.
-- Aucun statut historique n'est modifié.
UPDATE public.heures_externes_soignants h
SET source_validation_serveur = 'ADMIN_LEGACY_AUDITE',
    empreinte_snapshot_source = private.fn_empreinte_snapshot_heures_externes(h)
WHERE h.statut_validation = 'VALIDE'
  AND h.valide_par IS NOT NULL
  AND h.valide_le IS NOT NULL
  AND NULLIF(btrim(COALESCE(h.attestation_url, '')), '') IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM public.journaux_audit j
    JOIN auth.users admin_historique ON admin_historique.id = j.acteur_id
    WHERE j.id_ressource = h.id
      AND j.type_ressource = 'heures_externes_soignants'
      AND j.action = 'HEURES_EXTERNES_VALIDATION_MANUELLE'
      AND j.type_acteur IN ('ADMIN', 'ADMIN_PLATEFORME')
      AND j.acteur_id = h.valide_par
      AND admin_historique.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
      AND j.details ->> 'decision' = 'VALIDE'
      AND j.details ->> 'soignant_id' = h.soignant_id::text
      AND j.details ->> 'heures_declarees' = h.heures_declarees::text
      AND j.cle_s3_ressource IS NOT DISTINCT FROM h.attestation_url
      AND j.cree_le BETWEEN h.valide_le - interval '5 minutes'
                        AND h.valide_le + interval '5 minutes'
  )
  AND EXISTS (
    SELECT 1
    FROM storage.objects o
    WHERE o.name = h.attestation_url
      AND o.bucket_id IN ('jolene-documents', 'attestations-heures-externes')
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.heures_externes_soignants autre
    WHERE autre.id <> h.id
      AND autre.attestation_url = h.attestation_url
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.heures_externes_soignants autre
    WHERE autre.id <> h.id
      AND autre.soignant_id = h.soignant_id
      AND autre.statut_validation = 'VALIDE'
      AND daterange(autre.date_debut, autre.date_fin, '[]')
          && daterange(h.date_debut, h.date_fin, '[]')
  );

ALTER TABLE public.heures_externes_soignants
  DROP CONSTRAINT IF EXISTS heures_externes_source_validation_serveur_check,
  ADD CONSTRAINT heures_externes_source_validation_serveur_check CHECK (
    source_validation_serveur IS NULL
    OR source_validation_serveur IN (
      'ADMIN_LEGACY_AUDITE', 'ADMIN_AAL2', 'IA_REVUE', 'IA_REJET_CONCLUSIF'
    )
  ) NOT VALID,
  DROP CONSTRAINT IF EXISTS heures_externes_empreinte_preuve_check,
  ADD CONSTRAINT heures_externes_empreinte_preuve_check CHECK (
    empreinte_preuve_sha256 IS NULL
    OR empreinte_preuve_sha256 ~ '^[0-9a-f]{64}$'
  ) NOT VALID,
  DROP CONSTRAINT IF EXISTS heures_externes_empreinte_snapshot_check,
  ADD CONSTRAINT heures_externes_empreinte_snapshot_check CHECK (
    empreinte_snapshot_source IS NULL
    OR empreinte_snapshot_source ~ '^[0-9a-f]{64}$'
  ) NOT VALID,
  DROP CONSTRAINT IF EXISTS heures_externes_valide_provenance_check,
  ADD CONSTRAINT heures_externes_valide_provenance_check CHECK (
    statut_validation <> 'VALIDE'
    OR (
      source_validation_serveur IN ('ADMIN_LEGACY_AUDITE', 'ADMIN_AAL2')
      AND empreinte_snapshot_source IS NOT NULL
      AND (
        source_validation_serveur = 'ADMIN_LEGACY_AUDITE'
        OR empreinte_preuve_sha256 IS NOT NULL
      )
    )
  ) NOT VALID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_heures_externes_preuve_validee
  ON public.heures_externes_soignants (empreinte_preuve_sha256)
  WHERE statut_validation = 'VALIDE'
    AND empreinte_preuve_sha256 IS NOT NULL;

COMMENT ON COLUMN public.heures_externes_soignants.version_source IS
  'Jeton serveur de la source immuable utilisé par les CAS de vérification et de décision.';
COMMENT ON COLUMN public.heures_externes_soignants.empreinte_preuve_sha256 IS
  'SHA-256 des octets téléchargés depuis le bucket privé, calculé par l Edge Function.';
COMMENT ON COLUMN public.heures_externes_soignants.source_validation_serveur IS
  'Provenance du dernier verdict serveur. Seules ADMIN_AAL2 et ADMIN_LEGACY_AUDITE peuvent alimenter le compteur.';
COMMENT ON COLUMN public.heures_externes_soignants.empreinte_snapshot_source IS
  'SHA-256 du snapshot complet et immuable sur lequel le verdict serveur a été rendu.';

-- ---------------------------------------------------------------------------
-- 2. Un seul chemin d'écriture : RPC propriétaire ou finaliseurs serveur/admin
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_proteger_heures_externes_soignants()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF COALESCE(
       current_setting('jolene.heures_externes_server_update', true), ''
     ) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Écriture directe des heures externes interdite'
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'UPDATE' AND (
       NEW.soignant_id IS DISTINCT FROM OLD.soignant_id
    OR NEW.etablissement_nom IS DISTINCT FROM OLD.etablissement_nom
    OR NEW.etablissement_type IS DISTINCT FROM OLD.etablissement_type
    OR NEW.date_debut IS DISTINCT FROM OLD.date_debut
    OR NEW.date_fin IS DISTINCT FROM OLD.date_fin
    OR NEW.heures_declarees IS DISTINCT FROM OLD.heures_declarees
    OR NEW.attestation_url IS DISTINCT FROM OLD.attestation_url
    OR NEW.attestation_nom_fichier IS DISTINCT FROM OLD.attestation_nom_fichier
  ) THEN
    NEW.version_source := gen_random_uuid();
    NEW.statut_validation := 'EN_ATTENTE';
    NEW.commentaire_validation := NULL;
    NEW.valide_par := NULL;
    NEW.valide_le := NULL;
    NEW.heures_extraites_ia := NULL;
    NEW.resultat_ia := NULL;
    NEW.coherence_ia := NULL;
    NEW.verifie_ia_le := NULL;
    NEW.empreinte_preuve_sha256 := NULL;
    NEW.source_validation_serveur := NULL;
    NEW.empreinte_snapshot_source := NULL;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_00_proteger_heures_externes_soignants
  ON public.heures_externes_soignants;
CREATE TRIGGER trg_00_proteger_heures_externes_soignants
BEFORE INSERT OR UPDATE ON public.heures_externes_soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_proteger_heures_externes_soignants();

REVOKE ALL ON FUNCTION public.fn_proteger_heures_externes_soignants()
  FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.heures_externes_soignants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.heures_externes_soignants FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS soignant_gere_ses_heures_externes
  ON public.heures_externes_soignants;
DROP POLICY IF EXISTS soignant_modifie_ses_heures_externes
  ON public.heures_externes_soignants;
DROP POLICY IF EXISTS soignant_supprime_ses_heures_en_attente
  ON public.heures_externes_soignants;
DROP POLICY IF EXISTS soignant_voit_ses_heures_externes
  ON public.heures_externes_soignants;

CREATE POLICY soignant_voit_ses_heures_externes
ON public.heures_externes_soignants
FOR SELECT TO authenticated
USING (
  public.fn_compte_auth_actif()
  AND (
    soignant_id = (SELECT auth.uid())
    OR public.est_admin_valide()
  )
);

REVOKE INSERT, UPDATE, DELETE
  ON public.heures_externes_soignants FROM authenticated;
GRANT SELECT ON public.heures_externes_soignants TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_declarer_heures_externes_soignant(
  p_etablissement_nom text,
  p_etablissement_type text,
  p_date_debut date,
  p_date_fin date,
  p_heures_declarees integer,
  p_attestation_url text,
  p_attestation_nom_fichier text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, storage
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_version_source uuid;
  v_guc_precedent text := COALESCE(
    current_setting('jolene.heures_externes_server_update', true), ''
  );
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RAISE EXCEPTION 'Compte authentifié actif requis' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_etablissement_nom, '')), '') IS NULL
     OR char_length(btrim(p_etablissement_nom)) > 255
     OR char_length(COALESCE(p_etablissement_type, '')) > 100
     OR p_date_debut IS NULL
     OR p_date_fin IS NULL
     OR p_date_fin < p_date_debut
     OR p_heures_declarees IS NULL
     OR p_heures_declarees < 1
     OR p_heures_declarees > 10000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'DECLARATION_INVALIDE',
      'error', 'Les données de la déclaration sont invalides.'
    );
  END IF;

  IF NULLIF(btrim(COALESCE(p_attestation_url, '')), '') IS NULL
     OR NULLIF(btrim(COALESCE(p_attestation_nom_fichier, '')), '') IS NULL
     OR char_length(p_attestation_nom_fichier) > 255
     OR p_attestation_url !~ (
       '^' || v_uid::text
       || '/heures-externes/[0-9]{10,17}_[A-Za-z0-9_-]{1,80}[.](pdf|jpg|png|webp)$'
     ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'PREUVE_REQUISE',
      'error', 'Une preuve privée appartenant au soignant est obligatoire.'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM storage.objects o
    WHERE o.bucket_id = 'jolene-documents'
      AND o.name = p_attestation_url
      AND o.owner_id = v_uid::text
      AND CASE
        WHEN COALESCE(o.metadata ->> 'size', '') ~ '^[0-9]+$'
          THEN (o.metadata ->> 'size')::numeric > 0
        ELSE false
      END
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'PREUVE_STORAGE_INVALIDE',
      'error', 'La preuve privée est absente, vide ou ne vous appartient pas.'
    );
  END IF;

  -- Les verrous sérialisent à la fois la réutilisation du chemin et les
  -- déclarations concurrentes du même soignant.
  PERFORM pg_advisory_xact_lock(
    hashtextextended('heures-path:' || p_attestation_url, 0)
  );
  PERFORM pg_advisory_xact_lock(
    hashtextextended('heures-soignant:' || v_uid::text, 0)
  );

  IF EXISTS (
    SELECT 1
    FROM public.heures_externes_soignants h
    WHERE h.attestation_url = p_attestation_url
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'PREUVE_DEJA_UTILISEE',
      'error', 'Cette preuve est déjà rattachée à une déclaration.'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.heures_externes_soignants h
    WHERE h.soignant_id = v_uid
      AND h.statut_validation IN ('EN_ATTENTE', 'VALIDE')
      AND daterange(h.date_debut, h.date_fin, '[]')
          && daterange(p_date_debut, p_date_fin, '[]')
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'PERIODE_CHEVAUCHANTE',
      'error', 'Une déclaration active couvre déjà tout ou partie de cette période.'
    );
  END IF;

  PERFORM set_config('jolene.heures_externes_server_update', 'true', true);
  INSERT INTO public.heures_externes_soignants (
    soignant_id,
    etablissement_nom,
    etablissement_type,
    date_debut,
    date_fin,
    heures_declarees,
    attestation_url,
    attestation_nom_fichier,
    statut_validation,
    commentaire_validation,
    valide_par,
    valide_le,
    heures_extraites_ia,
    resultat_ia,
    coherence_ia,
    verifie_ia_le,
    empreinte_preuve_sha256,
    source_validation_serveur,
    empreinte_snapshot_source
  ) VALUES (
    v_uid,
    left(btrim(p_etablissement_nom), 255),
    NULLIF(left(btrim(COALESCE(p_etablissement_type, '')), 100), ''),
    p_date_debut,
    p_date_fin,
    p_heures_declarees,
    p_attestation_url,
    left(btrim(p_attestation_nom_fichier), 255),
    'EN_ATTENTE',
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
  )
  RETURNING id, version_source INTO v_id, v_version_source;
  PERFORM set_config(
    'jolene.heures_externes_server_update', v_guc_precedent, true
  );

  -- Action déjà autorisée par la contrainte journaux_audit. Écriture directe :
  -- une erreur d'audit annule aussi la déclaration, elle n'est jamais avalée.
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    cle_s3_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'HEURES_EXTERNES_DECLAREES',
    'heures_externes_soignants', v_id, p_attestation_url,
    jsonb_build_object(
      'date_debut', p_date_debut,
      'date_fin', p_date_fin,
      'heures_declarees', p_heures_declarees,
      'version_source', v_version_source
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'id', v_id,
    'version_source', v_version_source,
    'statut', 'EN_ATTENTE'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_declarer_heures_externes_soignant(
  text, text, date, date, integer, text, text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_declarer_heures_externes_soignant(
  text, text, date, date, integer, text, text
) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Finaliseur service_role : snapshot complet, empreinte et aucun auto-VALIDE
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_service_finaliser_heures_externes(
  p_id uuid,
  p_snapshot_source jsonb,
  p_empreinte_preuve_sha256 text,
  p_verdict text,
  p_rejet_conclusif boolean,
  p_heures_extraites integer,
  p_coherence boolean,
  p_resultat_ia jsonb,
  p_commentaire text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, storage, extensions
AS $function$
DECLARE
  v_ligne public.heures_externes_soignants%ROWTYPE;
  v_snapshot jsonb;
  v_empreinte_snapshot text;
  v_statut text;
  v_source text;
  v_preuve_dupliquee boolean;
  v_row_count integer;
  v_commentaire text;
  v_resultat jsonb;
  v_guc_precedent text := COALESCE(
    current_setting('jolene.heures_externes_server_update', true), ''
  );
BEGIN
  IF COALESCE(
       auth.jwt() ->> 'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Finaliseur réservé au service_role'
      USING ERRCODE = '42501';
  END IF;

  IF p_verdict NOT IN ('EN_ATTENTE', 'REJETE') THEN
    RAISE EXCEPTION 'Le verdict automatique ne peut jamais être VALIDE'
      USING ERRCODE = '22023';
  END IF;
  IF p_empreinte_preuve_sha256 IS NULL
     OR p_empreinte_preuve_sha256 !~ '^[0-9a-f]{64}$'
     OR p_resultat_ia IS NULL
     OR jsonb_typeof(p_resultat_ia) IS DISTINCT FROM 'object'
     OR pg_column_size(p_resultat_ia) > 65536
     OR char_length(COALESCE(p_commentaire, '')) > 1000
     OR (
       p_heures_extraites IS NOT NULL
       AND (p_heures_extraites < 0 OR p_heures_extraites > 10000)
     ) THEN
    RAISE EXCEPTION 'Résultat de vérification invalide'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_ligne
  FROM public.heures_externes_soignants
  WHERE id = p_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'INTROUVABLE'
    );
  END IF;

  v_snapshot := private.fn_snapshot_heures_externes(v_ligne);
  v_empreinte_snapshot := private.fn_empreinte_snapshot_heures_externes(v_ligne);
  IF p_snapshot_source IS DISTINCT FROM v_snapshot
     OR v_ligne.statut_validation IS DISTINCT FROM 'EN_ATTENTE' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'CONFLIT_SOURCE',
      'error', 'La déclaration a changé pendant la vérification.'
    );
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('heures-preuve:' || p_empreinte_preuve_sha256, 0)
  );
  SELECT EXISTS (
    SELECT 1
    FROM public.heures_externes_soignants autre
    WHERE autre.id <> v_ligne.id
      AND autre.empreinte_preuve_sha256 = p_empreinte_preuve_sha256
      AND autre.statut_validation IN ('EN_ATTENTE', 'VALIDE')
  ) INTO v_preuve_dupliquee;

  -- Même un résultat IA entièrement concordant reste en revue humaine au
  -- lancement. REJETE n'est accepté que pour une invalidité concluante fournie
  -- explicitement par le service (signature/type de fichier ou non-attestation
  -- lisible à haute confiance).
  IF p_verdict = 'REJETE' AND COALESCE(p_rejet_conclusif, false) THEN
    v_statut := 'REJETE';
    v_source := 'IA_REJET_CONCLUSIF';
  ELSE
    v_statut := 'EN_ATTENTE';
    v_source := 'IA_REVUE';
  END IF;

  v_commentaire := CASE
    WHEN v_preuve_dupliquee AND v_statut = 'EN_ATTENTE' THEN
      'Cette preuve binaire est déjà rattachée à une autre déclaration. Revue manuelle obligatoire.'
    ELSE NULLIF(left(btrim(COALESCE(p_commentaire, '')), 1000), '')
  END;
  v_resultat := p_resultat_ia || jsonb_build_object(
    'decision_serveur', v_statut,
    'rejet_conclusif_serveur',
      (v_statut = 'REJETE' AND COALESCE(p_rejet_conclusif, false)),
    'preuve_dupliquee_serveur', v_preuve_dupliquee,
    'empreinte_snapshot_source', v_empreinte_snapshot,
    'regle_version', 'heures-externes-p0-2026-07-14'
  );

  PERFORM set_config('jolene.heures_externes_server_update', 'true', true);
  UPDATE public.heures_externes_soignants h
  SET statut_validation = v_statut,
      heures_extraites_ia = p_heures_extraites,
      coherence_ia = p_coherence,
      resultat_ia = v_resultat,
      commentaire_validation = v_commentaire,
      verifie_ia_le = now(),
      valide_par = NULL,
      valide_le = NULL,
      empreinte_preuve_sha256 = p_empreinte_preuve_sha256,
      source_validation_serveur = v_source,
      empreinte_snapshot_source = v_empreinte_snapshot,
      mis_a_jour_le = now()
  WHERE h.id = v_ligne.id
    AND h.version_source = v_ligne.version_source
    AND h.statut_validation = 'EN_ATTENTE'
    AND private.fn_empreinte_snapshot_heures_externes(h) = v_empreinte_snapshot;
  GET DIAGNOSTICS v_row_count = ROW_COUNT;
  PERFORM set_config(
    'jolene.heures_externes_server_update', v_guc_precedent, true
  );
  IF v_row_count <> 1 THEN
    RAISE EXCEPTION 'Conflit CAS pendant la finalisation des heures externes'
      USING ERRCODE = '40001';
  END IF;

  -- VERIFICATION_DOCUMENT est une action autorisée. Pas de wrapper safe : si
  -- l'audit échoue, le verdict est annulé dans la même transaction.
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    cle_s3_ressource, details, navigateur_acteur
  ) VALUES (
    v_ligne.soignant_id, 'SYSTEME', 'VERIFICATION_DOCUMENT',
    'heures_externes_soignants', v_ligne.id, v_ligne.attestation_url,
    jsonb_build_object(
      'sous_action', 'HEURES_EXTERNES_VERIFICATION_AUTO',
      'decision', v_statut,
      'rejet_conclusif', (v_statut = 'REJETE'),
      'preuve_dupliquee', v_preuve_dupliquee,
      'heures_declarees', v_ligne.heures_declarees,
      'heures_extraites', p_heures_extraites,
      'empreinte_snapshot_source', v_empreinte_snapshot
    ),
    'edge-function/verify-heures-externes'
  );

  RETURN jsonb_build_object(
    'success', true,
    'statut', v_statut,
    'preuve_dupliquee', v_preuve_dupliquee,
    'empreinte_snapshot_source', v_empreinte_snapshot
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_service_finaliser_heures_externes(
  uuid, jsonb, text, text, boolean, integer, boolean, jsonb, text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_service_finaliser_heures_externes(
  uuid, jsonb, text, text, boolean, integer, boolean, jsonb, text
) TO service_role;

-- ---------------------------------------------------------------------------
-- 4. Décision admin AAL2, atomique et sans cumul de preuve/période
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_admin_valider_heures_externes(
  p_id uuid,
  p_decision text,
  p_commentaire text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, storage
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_ligne public.heures_externes_soignants%ROWTYPE;
  v_empreinte_snapshot text;
  v_row_count integer;
  v_guc_precedent text := COALESCE(
    current_setting('jolene.heures_externes_server_update', true), ''
  );
BEGIN
  IF v_uid IS NULL
     OR NOT public.fn_compte_auth_actif()
     OR COALESCE(auth.jwt() ->> 'aal', '') IS DISTINCT FROM 'aal2'
     OR NOT public.est_admin_valide() THEN
    RAISE EXCEPTION 'Administrateur AAL2 valide requis'
      USING ERRCODE = '42501';
  END IF;

  IF p_decision NOT IN ('VALIDE', 'REJETE') THEN
    RAISE EXCEPTION 'Décision invalide (VALIDE ou REJETE)'
      USING ERRCODE = '22023';
  END IF;
  IF p_decision = 'REJETE'
     AND char_length(btrim(COALESCE(p_commentaire, ''))) < 5 THEN
    RAISE EXCEPTION 'Motif requis pour un rejet (min 5 caractères)'
      USING ERRCODE = '22023';
  END IF;
  IF char_length(COALESCE(p_commentaire, '')) > 1000 THEN
    RAISE EXCEPTION 'Commentaire trop long' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_ligne
  FROM public.heures_externes_soignants
  WHERE id = p_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'INTROUVABLE',
      'error', 'Déclaration introuvable.'
    );
  END IF;
  IF v_ligne.statut_validation IS DISTINCT FROM 'EN_ATTENTE' THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'DECISION_CONCURRENTE',
      'error', 'Cette déclaration a déjà été traitée.'
    );
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('heures-soignant:' || v_ligne.soignant_id::text, 0)
  );
  v_empreinte_snapshot :=
    private.fn_empreinte_snapshot_heures_externes(v_ligne);

  IF p_decision = 'VALIDE' THEN
    IF v_ligne.empreinte_preuve_sha256 IS NULL
       OR v_ligne.empreinte_snapshot_source IS DISTINCT FROM v_empreinte_snapshot
       OR NOT EXISTS (
         SELECT 1
         FROM storage.objects o
         WHERE o.name = v_ligne.attestation_url
           AND o.bucket_id IN (
             'jolene-documents', 'attestations-heures-externes'
           )
       ) THEN
      RETURN jsonb_build_object(
        'success', false, 'error_code', 'PREUVE_NON_FINALISEE',
        'error', 'La preuve doit être vérifiée sur ce snapshot avant validation.'
      );
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.heures_externes_soignants autre
      WHERE autre.id <> v_ligne.id
        AND autre.empreinte_preuve_sha256 = v_ligne.empreinte_preuve_sha256
        AND autre.statut_validation IN ('EN_ATTENTE', 'VALIDE')
    ) THEN
      RETURN jsonb_build_object(
        'success', false, 'error_code', 'PREUVE_DUPLIQUEE',
        'error', 'Cette preuve binaire est déjà utilisée par une autre déclaration.'
      );
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.heures_externes_soignants autre
      WHERE autre.id <> v_ligne.id
        AND autre.soignant_id = v_ligne.soignant_id
        AND autre.statut_validation = 'VALIDE'
        AND daterange(autre.date_debut, autre.date_fin, '[]')
            && daterange(v_ligne.date_debut, v_ligne.date_fin, '[]')
    ) THEN
      RETURN jsonb_build_object(
        'success', false, 'error_code', 'PERIODE_DEJA_VALIDEE',
        'error', 'Une autre preuve validée couvre déjà cette période.'
      );
    END IF;
  END IF;

  PERFORM set_config('jolene.heures_externes_server_update', 'true', true);
  UPDATE public.heures_externes_soignants h
  SET statut_validation = p_decision,
      commentaire_validation = NULLIF(
        left(btrim(COALESCE(p_commentaire, '')), 1000), ''
      ),
      valide_par = v_uid,
      valide_le = now(),
      source_validation_serveur = 'ADMIN_AAL2',
      empreinte_snapshot_source = v_empreinte_snapshot,
      mis_a_jour_le = now()
  WHERE h.id = v_ligne.id
    AND h.version_source = v_ligne.version_source
    AND h.statut_validation = 'EN_ATTENTE'
    AND private.fn_empreinte_snapshot_heures_externes(h) = v_empreinte_snapshot;
  GET DIAGNOSTICS v_row_count = ROW_COUNT;
  PERFORM set_config(
    'jolene.heures_externes_server_update', v_guc_precedent, true
  );
  IF v_row_count <> 1 THEN
    RAISE EXCEPTION 'Décision concurrente détectée'
      USING ERRCODE = '40001';
  END IF;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    cle_s3_ressource, details
  ) VALUES (
    v_uid, 'ADMIN', 'HEURES_EXTERNES_VALIDATION_MANUELLE',
    'heures_externes_soignants', v_ligne.id, v_ligne.attestation_url,
    jsonb_build_object(
      'decision', p_decision,
      'soignant_id', v_ligne.soignant_id,
      'heures_declarees', v_ligne.heures_declarees,
      'heures_extraites_ia', v_ligne.heures_extraites_ia,
      'empreinte_snapshot_source', v_empreinte_snapshot,
      'source', 'ADMIN_AAL2'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'statut', p_decision,
    'source', 'ADMIN_AAL2'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_valider_heures_externes(
  uuid, text, text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_valider_heures_externes(
  uuid, text, text
) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Le compteur refuse tout VALIDE sans provenance et snapshot courant
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_compteur_heures_soignant(
  p_soignant_id uuid
)
RETURNS TABLE(
  heures_jolene integer,
  heures_externes_validees integer,
  heures_externes_en_attente integer,
  heures_totales integer,
  eligible_free_transition boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_heures_jolene integer := 0;
  v_heures_ext_val integer := 0;
  v_heures_ext_att integer := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RAISE EXCEPTION 'Compte authentifié actif requis' USING ERRCODE = '42501';
  END IF;
  IF auth.uid() <> p_soignant_id AND NOT public.est_admin_valide() THEN
    RAISE EXCEPTION 'Accès non autorisé' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(sum(
    COALESCE(
      (
        SELECT sum(pr.heures_reelles)
        FROM public.presences pr
        WHERE pr.mission_id = m.id
          AND pr.heures_reelles IS NOT NULL
      ),
      m.duree_heures_effective,
      m.duree_heures
    )
  )::integer, 0)
  INTO v_heures_jolene
  FROM public.missions m
  WHERE m.soignant_assigne_id = p_soignant_id
    AND m.statut = 'TERMINEE';

  SELECT COALESCE(sum(h.heures_declarees)::integer, 0)
  INTO v_heures_ext_val
  FROM public.heures_externes_soignants h
  WHERE h.soignant_id = p_soignant_id
    AND h.statut_validation = 'VALIDE'
    AND h.source_validation_serveur IN ('ADMIN_AAL2', 'ADMIN_LEGACY_AUDITE')
    AND h.empreinte_snapshot_source =
        private.fn_empreinte_snapshot_heures_externes(h)
    AND (
      h.source_validation_serveur = 'ADMIN_LEGACY_AUDITE'
      OR h.empreinte_preuve_sha256 IS NOT NULL
    );

  SELECT COALESCE(sum(h.heures_declarees)::integer, 0)
  INTO v_heures_ext_att
  FROM public.heures_externes_soignants h
  WHERE h.soignant_id = p_soignant_id
    AND h.statut_validation = 'EN_ATTENTE';

  RETURN QUERY
  SELECT
    v_heures_jolene,
    v_heures_ext_val,
    v_heures_ext_att,
    v_heures_jolene + v_heures_ext_val,
    v_heures_jolene + v_heures_ext_val >= 3200;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_compteur_heures_soignant(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_compteur_heures_soignant(uuid)
  TO authenticated, service_role;
