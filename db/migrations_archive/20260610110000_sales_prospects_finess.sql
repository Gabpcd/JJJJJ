-- Prospection nationale "Série A" : base FINESS importée en interne (~270k
-- établissements de santé AVEC téléphone), favoris, archive douce des sourcés,
-- recherche nationale sans département obligatoire, relance auto J+7.
--
-- L'import est réalisé par l'edge function import-finess (tranches HTTP Range
-- auto-relançantes depuis le fichier officiel data.gouv).

CREATE TABLE IF NOT EXISTS public.prospects_etablissements (
  finess text PRIMARY KEY,
  siret text,
  nom text NOT NULL,
  type_jolene text NOT NULL,
  categorie_lib text,
  telephone text,
  email text,
  adresse text,
  code_postal text,
  ville text,
  departement text,
  favori boolean NOT NULL DEFAULT false,
  maj_le timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_prospects_etab_type ON public.prospects_etablissements(type_jolene);
CREATE INDEX IF NOT EXISTS idx_prospects_etab_dept ON public.prospects_etablissements(departement);
CREATE INDEX IF NOT EXISTS idx_prospects_etab_favori ON public.prospects_etablissements(favori) WHERE favori;

ALTER TABLE public.prospects_etablissements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_all_prospects_etab ON public.prospects_etablissements;
CREATE POLICY admin_all_prospects_etab ON public.prospects_etablissements
  FOR ALL USING (public.est_admin()) WITH CHECK (public.est_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.prospects_etablissements TO authenticated, service_role;

ALTER TABLE public.sales_contacts
  ADD COLUMN IF NOT EXISTS favori boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS archive boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS finess text;
ALTER TABLE public.sales_groupes
  ADD COLUMN IF NOT EXISTS favori boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.fn_admin_chercher_prospects(
  p_type text DEFAULT NULL,
  p_departement text DEFAULT NULL,
  p_q text DEFAULT NULL,
  p_favoris boolean DEFAULT false,
  p_page int DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_total bigint;
  v_resultats jsonb;
  v_par_page int := 30;
  v_offset int := (greatest(p_page,1)-1) * 30;
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;

  SELECT count(*) INTO v_total
  FROM prospects_etablissements p
  WHERE (p_type IS NULL OR p_type = '' OR p.type_jolene = p_type)
    AND (p_departement IS NULL OR p_departement = '' OR p.departement = upper(p_departement))
    AND (NOT p_favoris OR p.favori)
    AND (p_q IS NULL OR p_q = '' OR p.nom ILIKE '%'||p_q||'%' OR p.ville ILIKE '%'||p_q||'%');

  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb) INTO v_resultats
  FROM (
    SELECT p.finess, p.siret, p.nom, p.type_jolene, p.categorie_lib, p.telephone,
           p.email, p.adresse, p.code_postal, p.ville, p.departement, p.favori
    FROM prospects_etablissements p
    WHERE (p_type IS NULL OR p_type = '' OR p.type_jolene = p_type)
      AND (p_departement IS NULL OR p_departement = '' OR p.departement = upper(p_departement))
      AND (NOT p_favoris OR p.favori)
      AND (p_q IS NULL OR p_q = '' OR p.nom ILIKE '%'||p_q||'%' OR p.ville ILIKE '%'||p_q||'%')
    ORDER BY p.favori DESC, p.nom
    LIMIT v_par_page OFFSET v_offset
  ) t;

  RETURN jsonb_build_object(
    'total', v_total,
    'page', greatest(p_page,1),
    'total_pages', ceil(v_total::numeric / v_par_page),
    'resultats', v_resultats
  );
END;
$body$;
GRANT EXECUTE ON FUNCTION public.fn_admin_chercher_prospects(text, text, text, boolean, int) TO authenticated;

-- Relance auto : prospect CONTACTE depuis plus de 7 jours → RELANCE
DO $cron$
BEGIN
  PERFORM cron.schedule(
    'sales-relance-auto', '0 8 * * *',
    $$UPDATE public.sales_contacts SET statut='RELANCE', maj_le=now()
      WHERE statut='CONTACTE' AND archive=false AND maj_le < now() - interval '7 days'$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END
$cron$;

-- Dédup des sourcés par n° FINESS (NULL multiples autorisés)
CREATE UNIQUE INDEX IF NOT EXISTS uq_sales_contacts_finess ON public.sales_contacts(finess);
