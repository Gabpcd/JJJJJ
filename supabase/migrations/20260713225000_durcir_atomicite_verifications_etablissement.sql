-- Empêche une réponse externe/IA obsolète de réactiver une preuve établissement.
-- La version est monotone et avance à chaque UPDATE du profil : une vérification
-- commencée avant n'importe quelle modification ne peut donc plus être appliquée.
-- Aucune donnée (réelle ou de démonstration) n'est modifiée par cette migration.

ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS verification_source_version bigint NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.etablissements.verification_source_version IS
  'Version monotone utilisée par les RPC de vérification pour rejeter toute réponse externe obsolète.';

CREATE OR REPLACE FUNCTION public.fn_versionner_verifications_etablissement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  -- On ignore toujours une valeur proposée par le client. Le compteur avance
  -- aussi pour un UPDATE sans delta : c'est volontairement conservateur.
  NEW.verification_source_version := OLD.verification_source_version + 1;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_00_versionner_verifications_etablissement ON public.etablissements;
CREATE TRIGGER trg_00_versionner_verifications_etablissement
BEFORE UPDATE ON public.etablissements
FOR EACH ROW EXECUTE FUNCTION public.fn_versionner_verifications_etablissement();

REVOKE UPDATE (verification_source_version) ON public.etablissements FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_versionner_verifications_etablissement()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_versionner_verifications_etablissement()
  TO service_role;

-- ---------------------------------------------------------------------------
-- Pièce d'identité du représentant
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_appliquer_verification_identite_etablissement(
  p_etablissement_id uuid,
  p_version_attendue bigint,
  p_piece_s3_key text,
  p_piece_type_mime text,
  p_piece_type_document text,
  p_representant_nom text,
  p_representant_prenom text,
  p_verifie boolean,
  p_resultat jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_etab record;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT verification_source_version, representant_piece_s3_key,
         representant_piece_type_mime, representant_piece_type_document,
         representant_nom, representant_prenom
    INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id AND supprime_le IS NULL
  FOR UPDATE;

  IF NOT FOUND
     OR v_etab.verification_source_version IS DISTINCT FROM p_version_attendue
     OR v_etab.representant_piece_s3_key IS DISTINCT FROM p_piece_s3_key
     OR v_etab.representant_piece_type_mime IS DISTINCT FROM p_piece_type_mime
     OR v_etab.representant_piece_type_document IS DISTINCT FROM p_piece_type_document
     OR v_etab.representant_nom IS DISTINCT FROM p_representant_nom
     OR v_etab.representant_prenom IS DISTINCT FROM p_representant_prenom THEN
    RETURN false;
  END IF;

  UPDATE public.etablissements
  SET representant_identite_verifiee = COALESCE(p_verifie, false),
      representant_identite_verifiee_le = CASE WHEN p_verifie IS TRUE THEN now() ELSE NULL END,
      representant_identite_resultat_ia = COALESCE(p_resultat, '{}'::jsonb),
      modifie_le = now()
  WHERE id = p_etablissement_id;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_appliquer_verification_identite_etablissement(
  uuid, bigint, text, text, text, text, text, boolean, jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_appliquer_verification_identite_etablissement(
  uuid, bigint, text, text, text, text, text, boolean, jsonb
) TO service_role;

-- ---------------------------------------------------------------------------
-- Justificatif de fonction
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_appliquer_verification_fonction_etablissement(
  p_etablissement_id uuid,
  p_version_attendue bigint,
  p_justificatif_s3_key text,
  p_justificatif_type text,
  p_justificatif_type_mime text,
  p_representant_nom text,
  p_representant_prenom text,
  p_nom_etablissement text,
  p_siret text,
  p_siret_raison_sociale text,
  p_finess_raison_sociale text,
  p_verifie boolean,
  p_resultat jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_etab record;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT verification_source_version, justificatif_fonction_s3_key,
         justificatif_fonction_type, justificatif_fonction_type_mime,
         representant_nom, representant_prenom, nom, siret,
         siret_raison_sociale, finess_raison_sociale
    INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id AND supprime_le IS NULL
  FOR UPDATE;

  IF NOT FOUND
     OR v_etab.verification_source_version IS DISTINCT FROM p_version_attendue
     OR v_etab.justificatif_fonction_s3_key IS DISTINCT FROM p_justificatif_s3_key
     OR v_etab.justificatif_fonction_type IS DISTINCT FROM p_justificatif_type
     OR v_etab.justificatif_fonction_type_mime IS DISTINCT FROM p_justificatif_type_mime
     OR v_etab.representant_nom IS DISTINCT FROM p_representant_nom
     OR v_etab.representant_prenom IS DISTINCT FROM p_representant_prenom
     OR v_etab.nom IS DISTINCT FROM p_nom_etablissement
     OR v_etab.siret IS DISTINCT FROM p_siret
     OR v_etab.siret_raison_sociale IS DISTINCT FROM p_siret_raison_sociale
     OR v_etab.finess_raison_sociale IS DISTINCT FROM p_finess_raison_sociale THEN
    RETURN false;
  END IF;

  UPDATE public.etablissements
  SET justificatif_fonction_verifie = COALESCE(p_verifie, false),
      justificatif_fonction_verifie_le = CASE WHEN p_verifie IS TRUE THEN now() ELSE NULL END,
      justificatif_fonction_resultat_ia = COALESCE(p_resultat, '{}'::jsonb),
      modifie_le = now()
  WHERE id = p_etablissement_id;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_appliquer_verification_fonction_etablissement(
  uuid, bigint, text, text, text, text, text, text, text, text, text, boolean, jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_appliquer_verification_fonction_etablissement(
  uuid, bigint, text, text, text, text, text, text, text, text, text, boolean, jsonb
) TO service_role;

-- ---------------------------------------------------------------------------
-- RIB établissement
-- ---------------------------------------------------------------------------

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
AS $$
DECLARE
  v_etab record;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT verification_source_version, rib_s3_key, nom,
         siret_raison_sociale, finess_raison_sociale
    INTO v_etab
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
      modifie_le = now()
  WHERE id = p_etablissement_id;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_appliquer_verification_rib_etablissement(
  uuid, bigint, text, text, text, text, boolean, jsonb, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_appliquer_verification_rib_etablissement(
  uuid, bigint, text, text, text, text, boolean, jsonb, text
) TO service_role;

-- ---------------------------------------------------------------------------
-- Contrat établissement
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_appliquer_verification_contrat_etablissement(
  p_etablissement_id uuid,
  p_version_attendue bigint,
  p_contrat_url text,
  p_nom_etablissement text,
  p_siret text,
  p_siret_raison_sociale text,
  p_finess_raison_sociale text,
  p_representant_nom text,
  p_representant_prenom text,
  p_coherent boolean,
  p_resultat jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_etab record;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT verification_source_version, contrat_url, nom, siret,
         siret_raison_sociale, finess_raison_sociale,
         representant_nom, representant_prenom
    INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id AND supprime_le IS NULL
  FOR UPDATE;

  IF NOT FOUND
     OR v_etab.verification_source_version IS DISTINCT FROM p_version_attendue
     OR v_etab.contrat_url IS DISTINCT FROM p_contrat_url
     OR v_etab.nom IS DISTINCT FROM p_nom_etablissement
     OR v_etab.siret IS DISTINCT FROM p_siret
     OR v_etab.siret_raison_sociale IS DISTINCT FROM p_siret_raison_sociale
     OR v_etab.finess_raison_sociale IS DISTINCT FROM p_finess_raison_sociale
     OR v_etab.representant_nom IS DISTINCT FROM p_representant_nom
     OR v_etab.representant_prenom IS DISTINCT FROM p_representant_prenom THEN
    RETURN false;
  END IF;

  UPDATE public.etablissements
  SET contrat_ia_resultat = COALESCE(p_resultat, '{}'::jsonb),
      contrat_ia_coherent = p_coherent,
      contrat_ia_verifie_le = now(),
      modifie_le = now()
  WHERE id = p_etablissement_id;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_appliquer_verification_contrat_etablissement(
  uuid, bigint, text, text, text, text, text, text, text, boolean, jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_appliquer_verification_contrat_etablissement(
  uuid, bigint, text, text, text, text, text, text, text, boolean, jsonb
) TO service_role;

-- ---------------------------------------------------------------------------
-- SIRET et FINESS : résultats des registres officiels
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_appliquer_verification_siret_etablissement(
  p_etablissement_id uuid,
  p_version_attendue bigint,
  p_siret text,
  p_verifie boolean,
  p_est_actif boolean,
  p_code_naf text,
  p_raison_sociale text,
  p_categorie_juridique text,
  p_dirigeants jsonb,
  p_est_secteur_public boolean
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_etab record;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT verification_source_version, siret
    INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id AND supprime_le IS NULL
  FOR UPDATE;

  IF NOT FOUND
     OR v_etab.verification_source_version IS DISTINCT FROM p_version_attendue
     OR v_etab.siret IS DISTINCT FROM p_siret THEN
    RETURN false;
  END IF;

  UPDATE public.etablissements
  SET siret_verifie = COALESCE(p_verifie, false),
      siret_verifie_le = CASE WHEN p_verifie IS TRUE THEN now() ELSE NULL END,
      siret_est_actif = p_est_actif,
      siret_code_naf = p_code_naf,
      siret_raison_sociale = p_raison_sociale,
      siret_categorie_juridique = p_categorie_juridique,
      dirigeants = p_dirigeants,
      est_secteur_public = COALESCE(p_est_secteur_public, false),
      modifie_le = now()
  WHERE id = p_etablissement_id;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_appliquer_verification_siret_etablissement(
  uuid, bigint, text, boolean, boolean, text, text, text, jsonb, boolean
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_appliquer_verification_siret_etablissement(
  uuid, bigint, text, boolean, boolean, text, text, text, jsonb, boolean
) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_appliquer_verification_finess_etablissement(
  p_etablissement_id uuid,
  p_version_attendue bigint,
  p_finess_source_attendu text,
  p_finess_nouveau text,
  p_trouve boolean,
  p_verifie boolean,
  p_raison_sociale text,
  p_categorie text,
  p_secteur text,
  p_est_public boolean
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_etab record;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT verification_source_version, finess
    INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id AND supprime_le IS NULL
  FOR UPDATE;

  IF NOT FOUND
     OR v_etab.verification_source_version IS DISTINCT FROM p_version_attendue
     OR v_etab.finess IS DISTINCT FROM p_finess_source_attendu THEN
    RETURN false;
  END IF;

  -- Le changement de numéro doit d'abord passer seul afin que le trigger
  -- d'invalidation révoque l'ancien verdict. Le verrou de ligne conserve
  -- néanmoins les deux écritures dans une seule transaction atomique.
  IF v_etab.finess IS DISTINCT FROM p_finess_nouveau THEN
    UPDATE public.etablissements
    SET finess = p_finess_nouveau,
        modifie_le = now()
    WHERE id = p_etablissement_id;
  END IF;

  UPDATE public.etablissements
  SET finess_verifie = COALESCE(p_verifie, false),
      finess_verifie_le = CASE WHEN p_verifie IS TRUE THEN now() ELSE NULL END,
      finess_raison_sociale = CASE WHEN p_trouve IS TRUE THEN p_raison_sociale ELSE NULL END,
      finess_categorie = CASE WHEN p_trouve IS TRUE THEN p_categorie ELSE NULL END,
      finess_secteur = CASE WHEN p_trouve IS TRUE THEN p_secteur ELSE NULL END,
      finess_est_public = CASE WHEN p_trouve IS TRUE THEN p_est_public ELSE NULL END,
      modifie_le = now()
  WHERE id = p_etablissement_id;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_appliquer_verification_finess_etablissement(
  uuid, bigint, text, text, boolean, boolean, text, text, text, boolean
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_appliquer_verification_finess_etablissement(
  uuid, bigint, text, text, boolean, boolean, text, text, text, boolean
) TO service_role;
