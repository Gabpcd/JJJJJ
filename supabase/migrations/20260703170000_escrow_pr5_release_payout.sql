-- Escrow 7b-D — PR 5 : release du payout après validation des présences.
-- INACTIF sans escrow (flag ⚡ = 0 : escrow_release_queue reste vide, le cron
-- est un no-op).
--
-- Chaîne : trigger présences (PR 2) enfile escrow_release_queue → cron
-- escrow-release (edge function) : vérifie A3 (présences validées via le trigger
-- + fonds `available` sur le solde connecté) puis payouts.create sur le compte
-- connecté du soignant → paiements_escrow PAYE. Incrémente le compteur de
-- confiance de l'établissement (plafond A2 relevé après N missions sans incident).

-- ── 1. Incrément du compteur de confiance (A2) ─────────────────────────────
-- Appelé au release réussi. N'incrémente pas si l'établissement est gelé.

CREATE OR REPLACE FUNCTION public.fn_escrow_incrementer_confiance(p_etablissement_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $esc_conf$
BEGIN
  INSERT INTO escrow_etablissement_etat (etablissement_id, missions_sans_incident, modifie_le)
  VALUES (p_etablissement_id, 1, now())
  ON CONFLICT (etablissement_id) DO UPDATE
    SET missions_sans_incident = CASE
          WHEN escrow_etablissement_etat.gele THEN escrow_etablissement_etat.missions_sans_incident
          ELSE escrow_etablissement_etat.missions_sans_incident + 1
        END,
        modifie_le = now();
END;
$esc_conf$;

-- ── 2. Sélection des releases à traiter (consommé par l'edge function) ──────

CREATE OR REPLACE FUNCTION public.fn_escrow_releases_a_traiter(p_limit integer DEFAULT 50)
RETURNS TABLE(
  queue_id uuid,
  paiement_escrow_id uuid,
  mission_id uuid,
  soignant_id uuid,
  etablissement_id uuid,
  honoraires_cents integer,
  escrow_statut text,
  tentatives integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $esc_rel$
  SELECT q.id, q.paiement_escrow_id, q.mission_id,
         pe.soignant_id, pe.etablissement_id, pe.honoraires_cents,
         pe.statut, q.tentatives
  FROM escrow_release_queue q
  JOIN paiements_escrow pe ON pe.id = q.paiement_escrow_id
  WHERE q.statut = 'EN_ATTENTE'
    AND q.prochaine_tentative_le <= now()
    AND q.tentatives < 5
  ORDER BY q.prochaine_tentative_le ASC
  LIMIT p_limit;
$esc_rel$;

REVOKE EXECUTE ON FUNCTION public.fn_escrow_incrementer_confiance(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_escrow_releases_a_traiter(integer) FROM PUBLIC, anon, authenticated;

-- ── 3. Cron d'appel de l'edge function escrow-release ──────────────────────
-- Toutes les 15 min : réveille le consumer qui vérifie la dispo des fonds et
-- déclenche les payouts. Auth via secret vault (cf. CLAUDE.md).

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'escrow-release') THEN
    PERFORM cron.schedule('escrow-release', '*/15 * * * *', $cron$
      SELECT net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/escrow-release',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 120000
      );
    $cron$);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'schedule escrow-release: %', SQLERRM;
END
$do$;

-- ── 4. CHECK journaux_audit : actions du release ───────────────────────────
DO $audit$
DECLARE
  v_src text;
  v_inject text := ', ''ESCROW_DISPONIBLE''::text, ''ESCROW_RELEASE_PAYE''::text, ''ESCROW_RELEASE_ATTENTE_FONDS''::text';
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO v_src
  FROM pg_constraint c
  JOIN pg_class cl ON cl.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = cl.relnamespace
  WHERE n.nspname = 'public' AND cl.relname = 'journaux_audit'
    AND c.conname = 'journaux_audit_action_check';

  IF v_src IS NOT NULL AND position('ESCROW_RELEASE_PAYE' IN v_src) = 0 THEN
    v_src := replace(v_src, '])))', v_inject || '])))');
    EXECUTE 'ALTER TABLE journaux_audit DROP CONSTRAINT journaux_audit_action_check';
    EXECUTE 'ALTER TABLE journaux_audit ADD CONSTRAINT journaux_audit_action_check ' || v_src;
  END IF;
END
$audit$;
