-- Le client service-role Supabase expose le rôle via auth.role() dans
-- PostgREST. Conserver aussi le claim historique pour compatibilité.
CREATE OR REPLACE FUNCTION public.fn_acquisition_upsert_bmo(p_rows jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE v_count integer := 0;
BEGIN
  IF NOT (
    public.est_admin()
    OR COALESCE(auth.role(), '') = 'service_role'
    OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role'
  ) THEN
    RAISE EXCEPTION 'Acces refuse' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.acquisition_territoires (
    departement, profession, bmo_annee, bmo_projets_recrutement,
    bmo_difficulte_pct, bmo_saisonnier_pct, bmo_code_metier,
    bmo_libelle_metier, bmo_precision, bmo_source_maj_le, source_url, maj_le
  )
  SELECT
    upper(btrim(r.departement)), upper(btrim(r.profession)), r.bmo_annee,
    GREATEST(COALESCE(r.bmo_projets_recrutement, 0), 0),
    CASE WHEN r.bmo_difficulte_pct IS NULL THEN NULL
      ELSE LEAST(GREATEST(r.bmo_difficulte_pct, 0), 100) END,
    CASE WHEN r.bmo_saisonnier_pct IS NULL THEN NULL
      ELSE LEAST(GREATEST(r.bmo_saisonnier_pct, 0), 100) END,
    NULLIF(btrim(r.bmo_code), ''), NULLIF(btrim(r.bmo_libelle), ''),
    CASE WHEN upper(r.precision) = 'EXACT' THEN 'EXACT' ELSE 'AGREGAT' END,
    COALESCE(r.bmo_source_maj_le, now()), NULLIF(btrim(r.source_url), ''), now()
  FROM jsonb_to_recordset(COALESCE(p_rows, '[]'::jsonb)) AS r(
    departement text, profession text, bmo_annee smallint,
    bmo_projets_recrutement integer, bmo_difficulte_pct numeric,
    bmo_saisonnier_pct numeric, bmo_code text, bmo_libelle text,
    precision text, bmo_source_maj_le timestamptz, source_url text
  )
  WHERE upper(btrim(COALESCE(r.departement, ''))) ~ '^([0-9]{2,3}|2A|2B)$'
    AND upper(btrim(COALESCE(r.profession, ''))) IN (
      'IDE', 'AS', 'AES', 'AUXILIAIRE_PUERICULTURE', 'SAGE_FEMME',
      'KINE', 'MEDECIN', 'DENTISTE', 'PREPARATEUR_PHARMA',
      'DIETETICIEN', 'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'ORTHOPHONISTE'
    )
    AND r.bmo_annee BETWEEN 2024 AND 2100
  ON CONFLICT (departement, profession) DO UPDATE SET
    bmo_annee = EXCLUDED.bmo_annee,
    bmo_projets_recrutement = EXCLUDED.bmo_projets_recrutement,
    bmo_difficulte_pct = EXCLUDED.bmo_difficulte_pct,
    bmo_saisonnier_pct = EXCLUDED.bmo_saisonnier_pct,
    bmo_code_metier = EXCLUDED.bmo_code_metier,
    bmo_libelle_metier = EXCLUDED.bmo_libelle_metier,
    bmo_precision = EXCLUDED.bmo_precision,
    bmo_source_maj_le = EXCLUDED.bmo_source_maj_le,
    source_url = EXCLUDED.source_url,
    maj_le = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_acquisition_upsert_bmo(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_acquisition_upsert_bmo(jsonb)
  TO service_role;
