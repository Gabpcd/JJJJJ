-- Attribution d'acquisition — colonnes UTM/referrer/parrainage sur soignants &
-- établissements + classification automatique en canal + RPC dashboard.

-- ═══════════════════════════════════════════════════════════
-- 1. Colonnes brutes + canal dérivé
-- ═══════════════════════════════════════════════════════════
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS utm_source text,
  ADD COLUMN IF NOT EXISTS utm_medium text,
  ADD COLUMN IF NOT EXISTS utm_campaign text,
  ADD COLUMN IF NOT EXISTS utm_content text,
  ADD COLUMN IF NOT EXISTS utm_term text,
  ADD COLUMN IF NOT EXISTS http_referrer text,
  ADD COLUMN IF NOT EXISTS ref_capture text,
  ADD COLUMN IF NOT EXISTS source_acquisition text;

ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS utm_source text,
  ADD COLUMN IF NOT EXISTS utm_medium text,
  ADD COLUMN IF NOT EXISTS utm_campaign text,
  ADD COLUMN IF NOT EXISTS utm_content text,
  ADD COLUMN IF NOT EXISTS utm_term text,
  ADD COLUMN IF NOT EXISTS http_referrer text,
  ADD COLUMN IF NOT EXISTS ref_capture text,
  ADD COLUMN IF NOT EXISTS source_acquisition text;

-- ═══════════════════════════════════════════════════════════
-- 2. Classification du canal (source de vérité unique)
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_classifier_canal(
  p_utm_source text,
  p_utm_medium text,
  p_referrer text,
  p_ref_code text
) RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $body$
DECLARE
  s text := lower(coalesce(p_utm_source, ''));
  m text := lower(coalesce(p_utm_medium, ''));
  r text := lower(coalesce(p_referrer, ''));
BEGIN
  IF coalesce(p_ref_code, '') <> '' THEN RETURN 'PARRAINAGE'; END IF;
  IF m IN ('cpc','ppc','paid','paidsearch','paid-search','paid_search','ads','display','cpm','retargeting') THEN RETURN 'PAID'; END IF;
  IF m IN ('social','paid-social','paid_social','social-paid')
     OR s ~ '(facebook|instagram|linkedin|tiktok|twitter|youtube|snapchat|pinterest)'
     OR r ~ '(facebook|instagram|linkedin|tiktok|twitter|t\.co|youtube|snapchat|pinterest)' THEN RETURN 'SOCIAL'; END IF;
  IF m IN ('email','newsletter','mail') OR s = 'email' THEN RETURN 'EMAIL'; END IF;
  IF s <> '' OR m <> '' THEN RETURN 'CAMPAGNE'; END IF;
  IF r ~ '(google|bing|yahoo|duckduckgo|qwant|ecosia)' THEN RETURN 'SEO'; END IF;
  IF r <> '' THEN RETURN 'REFERRAL'; END IF;
  RETURN 'DIRECT';
END;
$body$;

-- ═══════════════════════════════════════════════════════════
-- 3. Trigger BEFORE INSERT (réutilisé soignants + établissements)
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_trg_classifier_acquisition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $body$
BEGIN
  IF NEW.source_acquisition IS NULL THEN
    NEW.source_acquisition := fn_classifier_canal(
      NEW.utm_source, NEW.utm_medium, NEW.http_referrer, NEW.ref_capture
    );
  END IF;
  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_classifier_acquisition_soignant ON public.soignants;
CREATE TRIGGER trg_classifier_acquisition_soignant
  BEFORE INSERT ON public.soignants
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_classifier_acquisition();

DROP TRIGGER IF EXISTS trg_classifier_acquisition_etab ON public.etablissements;
CREATE TRIGGER trg_classifier_acquisition_etab
  BEFORE INSERT ON public.etablissements
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_classifier_acquisition();

-- Backfill : les inscrits existants sans canal → DIRECT (pas de donnée source).
UPDATE public.soignants SET source_acquisition = 'DIRECT' WHERE source_acquisition IS NULL;
UPDATE public.etablissements SET source_acquisition = 'DIRECT' WHERE source_acquisition IS NULL;

-- ═══════════════════════════════════════════════════════════
-- 4. RPC dashboard : acquisition par canal + par campagne
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_canaux(p_jours int DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_result jsonb;
  v_depuis timestamptz := now() - (p_jours || ' days')::interval;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = auth.uid() AND raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME'
  ) THEN
    RAISE EXCEPTION 'Accès admin requis';
  END IF;

  WITH soignants_p AS (
    SELECT coalesce(source_acquisition, 'DIRECT') AS canal, id
    FROM soignants WHERE cree_le >= v_depuis
  ),
  etabs_p AS (
    SELECT coalesce(source_acquisition, 'DIRECT') AS canal, id
    FROM etablissements WHERE cree_le >= v_depuis AND supprime_le IS NULL
  ),
  soignants_actifs AS (
    SELECT DISTINCT soignant_id FROM candidatures
  ),
  par_canal AS (
    SELECT
      canal,
      count(*) FILTER (WHERE src = 'S') AS soignants,
      count(*) FILTER (WHERE src = 'E') AS etablissements,
      count(*) FILTER (WHERE src = 'S' AND actif) AS soignants_actifs
    FROM (
      SELECT canal, 'S' AS src, (id IN (SELECT soignant_id FROM soignants_actifs)) AS actif FROM soignants_p
      UNION ALL
      SELECT canal, 'E' AS src, false AS actif FROM etabs_p
    ) u
    GROUP BY canal
  ),
  par_campagne AS (
    SELECT campagne, sum(n) AS inscriptions FROM (
      SELECT coalesce(nullif(utm_campaign, ''), '(aucune)') AS campagne, count(*) AS n
      FROM soignants WHERE cree_le >= v_depuis AND utm_campaign IS NOT NULL GROUP BY 1
      UNION ALL
      SELECT coalesce(nullif(utm_campaign, ''), '(aucune)'), count(*)
      FROM etablissements WHERE cree_le >= v_depuis AND supprime_le IS NULL AND utm_campaign IS NOT NULL GROUP BY 1
    ) c GROUP BY campagne
  )
  SELECT jsonb_build_object(
    'periode_jours', p_jours,
    'par_canal', coalesce((
      SELECT jsonb_agg(row_to_json(t)::jsonb ORDER BY (t.soignants + t.etablissements) DESC)
      FROM par_canal t
    ), '[]'::jsonb),
    'par_campagne', coalesce((
      SELECT jsonb_agg(row_to_json(t)::jsonb ORDER BY t.inscriptions DESC)
      FROM par_campagne t
    ), '[]'::jsonb),
    'total_soignants', (SELECT count(*) FROM soignants_p),
    'total_etabs', (SELECT count(*) FROM etabs_p)
  ) INTO v_result;

  RETURN v_result;
END;
$body$;
