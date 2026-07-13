-- Le résultat INSEE du SIRET libéral ne peut être appliqué qu'au profil exact
-- ayant servi au rapprochement. La ligne est verrouillée et tous les traits
-- d'identité/statut lus avant l'appel réseau sont comparés dans la même
-- transaction que l'activation de la preuve.

CREATE OR REPLACE FUNCTION public.fn_appliquer_verification_siret_soignant(
  p_soignant_id uuid,
  p_expected_prenom text,
  p_expected_nom text,
  p_expected_date_naissance date,
  p_expected_siret_liberal text,
  p_expected_statut_liberal text,
  p_expected_type_contrat text,
  p_siret text,
  p_raison_sociale text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_soignant record;
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
     OR NULLIF(btrim(p_expected_prenom), '') IS NULL
     OR NULLIF(btrim(p_expected_nom), '') IS NULL
     OR p_expected_date_naissance IS NULL
     OR COALESCE(p_siret, '') !~ '^[0-9]{14}$'
     OR p_siret ~ '^0+$' THEN
    RAISE EXCEPTION 'Snapshot SIRET ou identité incomplet'
      USING ERRCODE = '22023';
  END IF;

  SELECT s.prenom,
         s.nom,
         s.date_naissance,
         s.siret_liberal,
         s.statut_liberal,
         s.type_contrat::text AS type_contrat
    INTO v_soignant
  FROM public.soignants s
  WHERE s.id = p_soignant_id
    AND s.supprime_le IS NULL
  FOR UPDATE;

  IF NOT FOUND
     OR v_soignant.prenom IS DISTINCT FROM p_expected_prenom
     OR v_soignant.nom IS DISTINCT FROM p_expected_nom
     OR v_soignant.date_naissance IS DISTINCT FROM p_expected_date_naissance
     OR v_soignant.siret_liberal IS DISTINCT FROM p_expected_siret_liberal
     OR v_soignant.statut_liberal IS DISTINCT FROM p_expected_statut_liberal
     OR v_soignant.type_contrat IS DISTINCT FROM p_expected_type_contrat THEN
    RETURN false;
  END IF;

  -- Même sous service_role, une vérification ne remplace jamais le SIRET d'un
  -- exercice déjà actif. Le support doit d'abord révoquer explicitement la
  -- preuve et le statut dans un parcours séparé et audité.
  IF (v_soignant.statut_liberal = 'ACTIF' OR v_soignant.type_contrat = 'LIBERAL')
     AND v_soignant.siret_liberal IS NOT NULL
     AND v_soignant.siret_liberal IS DISTINCT FROM p_siret THEN
    RETURN false;
  END IF;

  UPDATE public.soignants
  SET siret_liberal = p_siret,
      statut_liberal = CASE
        WHEN v_soignant.statut_liberal = 'ACTIF' THEN 'ACTIF'
        ELSE 'EN_COURS'
      END,
      siret_liberal_verifie = true,
      siret_liberal_verifie_le = now(),
      siret_liberal_raison_sociale = NULLIF(btrim(p_raison_sociale), ''),
      siret_liberal_coherence_identite = true,
      modifie_le = now()
  WHERE id = p_soignant_id;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_appliquer_verification_siret_soignant(
  uuid, text, text, date, text, text, text, text, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_appliquer_verification_siret_soignant(
  uuid, text, text, date, text, text, text, text, text
) TO service_role;
