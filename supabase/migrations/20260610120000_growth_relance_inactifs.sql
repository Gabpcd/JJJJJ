-- Réactivation soignants inactifs : journal des relances + ciblage + cron hebdo.
-- L'edge function relance-inactifs (Resend) envoie l'email avec le nb de
-- missions ouvertes pour la profession + CTA UTM (utm_campaign=reactivation).
CREATE TABLE IF NOT EXISTS public.relances_soignants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  type text NOT NULL DEFAULT 'REACTIVATION',
  envoye_le timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_relances_soignant ON public.relances_soignants(soignant_id, envoye_le DESC);
ALTER TABLE public.relances_soignants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_all_relances ON public.relances_soignants;
CREATE POLICY admin_all_relances ON public.relances_soignants
  FOR ALL USING (public.est_admin()) WITH CHECK (public.est_admin());
GRANT SELECT, INSERT ON public.relances_soignants TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_soignants_inactifs_a_relancer(p_limit int DEFAULT 150)
RETURNS TABLE (id uuid, prenom text, email text, profession text, nb_missions_ouvertes bigint)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT s.id, s.prenom, s.email, s.profession::text,
    (SELECT count(*) FROM missions m
      WHERE m.statut = 'OUVERTE' AND m.profession_requise = s.profession) AS nb_missions_ouvertes
  FROM soignants s
  WHERE s.cree_le < now() - interval '3 days'
    AND s.email IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.soignant_id = s.id)
    AND NOT EXISTS (
      SELECT 1 FROM relances_soignants r
      WHERE r.soignant_id = s.id AND r.envoye_le > now() - interval '14 days'
    )
  ORDER BY s.cree_le DESC
  LIMIT greatest(p_limit, 1);
$$;

-- Cron hebdo : lundi 10h (UTC)
DO $cron$
BEGIN
  PERFORM cron.schedule(
    'relance-soignants-inactifs', '0 10 * * 1',
    $$SELECT net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/relance-inactifs',
      body := '{"secret":"jolene-relance-inactifs-2026"}'::jsonb,
      headers := '{"Content-Type":"application/json"}'::jsonb,
      timeout_milliseconds := 120000
    )$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END
$cron$;
