-- Machine d'acquisition zéro coût (Sprint growth) :
-- ① Google for Jobs : RPC publique détail mission + liste sitemap
-- ② Générateur de posts hebdo admin (stats réelles)
-- ③ Digest hebdo soignants + emails post-mission (avis Google + nudge parrainage)
-- NOTE : déjà appliquée en prod via MCP apply_migration (version 20260610123643).

-- ① Google for Jobs : détail public d'une mission OUVERTE (page indexable + JSON-LD)
CREATE OR REPLACE FUNCTION public.fn_mission_publique(p_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT to_jsonb(t) FROM (
    SELECT m.id, m.intitule, left(coalesce(m.description, ''), 1500) AS description,
           m.profession_requise::text, m.debut_le, m.fin_le, m.taux_horaire_base,
           m.est_urgente, m.service,
           e.nom AS etablissement_nom, e.type::text AS etablissement_type,
           e.adresse_ville::text AS ville, e.adresse_code_postal::text AS code_postal
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.id = p_id AND m.statut = 'OUVERTE'
  ) t;
$$;
GRANT EXECUTE ON FUNCTION public.fn_mission_publique(uuid) TO anon, authenticated, service_role;

-- Liste des missions ouvertes pour le sitemap dynamique (service_role only)
CREATE OR REPLACE FUNCTION public.fn_missions_ouvertes_sitemap()
RETURNS TABLE (id uuid, maj timestamptz)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT m.id, greatest(m.cree_le, coalesce(m.modifie_le, m.cree_le)) AS maj
  FROM missions m WHERE m.statut = 'OUVERTE'
  ORDER BY m.cree_le DESC LIMIT 2000;
$$;
GRANT EXECUTE ON FUNCTION public.fn_missions_ouvertes_sitemap() TO service_role;

-- ② Générateur de posts hebdo (stats réelles par profession)
CREATE OR REPLACE FUNCTION public.fn_admin_generer_posts()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE v jsonb;
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.nb DESC), '[]'::jsonb) INTO v
  FROM (
    SELECT m.profession_requise::text AS profession,
           count(*) AS nb,
           max(m.taux_horaire_base) AS taux_max,
           (SELECT string_agg(DISTINCT e2.adresse_ville, ', ')
            FROM (SELECT e3.adresse_ville FROM missions m3
                  JOIN etablissements e3 ON e3.id = m3.etablissement_id
                  WHERE m3.statut='OUVERTE' AND m3.profession_requise = m.profession_requise
                  LIMIT 3) e2(adresse_ville)) AS villes
    FROM missions m
    WHERE m.statut = 'OUVERTE'
    GROUP BY m.profession_requise
  ) t;
  RETURN v;
END;
$body$;
GRANT EXECUTE ON FUNCTION public.fn_admin_generer_posts() TO authenticated, service_role;

-- ③ Journal des emails post-mission (avis + parrainage) + config growth
CREATE TABLE IF NOT EXISTS public.emails_post_mission (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL,
  cible text NOT NULL,
  envoye_le timestamptz NOT NULL DEFAULT now(),
  UNIQUE (mission_id, cible)
);
ALTER TABLE public.emails_post_mission ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_all_emails_post_mission ON public.emails_post_mission;
CREATE POLICY admin_all_emails_post_mission ON public.emails_post_mission
  FOR ALL USING (public.est_admin()) WITH CHECK (public.est_admin());
GRANT SELECT, INSERT ON public.emails_post_mission TO authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.growth_config (
  cle text PRIMARY KEY,
  valeur text,
  maj_le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.growth_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_all_growth_config ON public.growth_config;
CREATE POLICY admin_all_growth_config ON public.growth_config
  FOR ALL USING (public.est_admin()) WITH CHECK (public.est_admin());
GRANT SELECT, INSERT, UPDATE ON public.growth_config TO authenticated, service_role;
INSERT INTO public.growth_config (cle, valeur) VALUES ('lien_avis_google', '')
ON CONFLICT (cle) DO NOTHING;

-- Ciblage digest hebdo : soignants avec missions ouvertes pour leur profession
CREATE OR REPLACE FUNCTION public.fn_digest_hebdo_cibles(p_limit int DEFAULT 500)
RETURNS TABLE (id uuid, prenom text, email text, profession text, nb_missions bigint, taux_max numeric)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT s.id, s.prenom::text, s.email::text, s.profession::text,
    (SELECT count(*) FROM missions m WHERE m.statut='OUVERTE' AND m.profession_requise = s.profession),
    (SELECT max(m.taux_horaire_base) FROM missions m WHERE m.statut='OUVERTE' AND m.profession_requise = s.profession)
  FROM soignants s
  WHERE s.email IS NOT NULL
    AND EXISTS (SELECT 1 FROM missions m WHERE m.statut='OUVERTE' AND m.profession_requise = s.profession)
  LIMIT greatest(p_limit, 1);
$$;
GRANT EXECUTE ON FUNCTION public.fn_digest_hebdo_cibles(int) TO service_role;

-- Missions terminées récemment (avis + nudge parrainage)
CREATE OR REPLACE FUNCTION public.fn_missions_terminees_a_remercier()
RETURNS TABLE (mission_id uuid, soignant_id uuid, soignant_prenom text, soignant_email text,
               etab_email text, etab_nom text, code_parrainage text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT m.id, s.id, s.prenom::text, s.email::text, e.email_contact::text, e.nom::text, s.code_parrainage::text
  FROM missions m
  JOIN soignants s ON s.id = m.soignant_assigne_id
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE m.statut = 'TERMINEE'
    AND coalesce(m.terminee_le, m.modifie_le) > now() - interval '2 days'
    AND NOT EXISTS (SELECT 1 FROM emails_post_mission ep WHERE ep.mission_id = m.id AND ep.cible = 'SOIGNANT')
  LIMIT 100;
$$;
GRANT EXECUTE ON FUNCTION public.fn_missions_terminees_a_remercier() TO service_role;

-- Crons : digest jeudi 9h UTC ; avis/parrainage tous les jours 11h UTC
DO $cron$
BEGIN
  PERFORM cron.schedule('digest-hebdo-soignants', '0 9 * * 4',
    $$SELECT net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/digest-hebdo',
      body := '{"secret":"jolene-digest-2026"}'::jsonb,
      headers := '{"Content-Type":"application/json"}'::jsonb,
      timeout_milliseconds := 120000)$$);
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron$;
DO $cron$
BEGIN
  PERFORM cron.schedule('avis-parrainage-post-mission', '0 11 * * *',
    $$SELECT net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/avis-parrainage',
      body := '{"secret":"jolene-avis-2026"}'::jsonb,
      headers := '{"Content-Type":"application/json"}'::jsonb,
      timeout_milliseconds := 120000)$$);
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron$;
