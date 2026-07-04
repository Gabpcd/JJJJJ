-- Escrow 7b-D — PR 3 : débit à la confirmation (le cœur du chantier).
-- INACTIF tant que feature_paiement_rapide_actif = 0 : le trigger sort
-- immédiatement (garde flag en tête), aucune ligne paiements_escrow n'est
-- créée sur le trafic actuel.
--
-- Chaîne : mission → ASSIGNEE (confirmation) → trigger crée paiements_escrow
-- INITIE avec methode_debit + debit_prevu_le décidés ici → cron
-- escrow-debit-echeance (edge function) crée la destination charge à échéance.
--
-- Décisions encodées (docs/ESCROW_7BD_MAPPING.md §6) :
--   A4 : méthode = SEPA si marge >= escrow_sepa_marge_jours avant le début,
--        sinon VIREMENT_INSTANTANE (débit initié immédiatement). La carte
--        n'est jamais un prérequis ; si l'étab n'a pas de mandat SEPA →
--        PAS d'escrow, la mission reste en régime standard (aucune ligne).
--   A2 : 1re mission escrow d'un établissement = VIREMENT_INSTANTANE (débit
--        immédiat, pas de crédit différé à J-7) + contrôle du plafond
--        (fn_escrow_etab_eligible avec le montant candidat).
--   « Débit initié immédiatement » vs « à J-7 » = une différence de TIMING
--        (debit_prevu_le), pas de primitive Stripe : les deux passent par le
--        mandat SEPA. Jolene absorbe l'écart de settlement sous le plafond A2
--        (cohérent avec DEBITE ≠ DISPONIBLE, PR 2).

-- ── 0. CHECK journaux_audit : autoriser les actions ESCROW_* ───────────────
-- fn_ecrire_audit_safe avale l'exception → sans ces valeurs, les audits escrow
-- (dont ESCROW_ETAB_GELE de la PR 2) étaient silencieusement PERDUS. On étend
-- la liste IN existante par manipulation textuelle (robuste : pas de re-saisie
-- des ~150 valeurs). Idempotent (guard position).
DO $audit$
DECLARE
  v_src text;
  v_inject text := ', ''ESCROW_INITIE''::text, ''ESCROW_DEBIT_INITIE''::text, ''ESCROW_DEBITE''::text, ''ESCROW_ETAB_GELE''::text, ''ESCROW_ETAB_DEGELE''::text';
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO v_src
  FROM pg_constraint c
  JOIN pg_class cl ON cl.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = cl.relnamespace
  WHERE n.nspname = 'public' AND cl.relname = 'journaux_audit'
    AND c.conname = 'journaux_audit_action_check';

  IF v_src IS NOT NULL AND position('ESCROW_INITIE' IN v_src) = 0 THEN
    -- La définition se termine par exactement un « ])) » : on injecte avant.
    v_src := replace(v_src, '])))', v_inject || '])))');
    EXECUTE 'ALTER TABLE journaux_audit DROP CONSTRAINT journaux_audit_action_check';
    EXECUTE 'ALTER TABLE journaux_audit ADD CONSTRAINT journaux_audit_action_check ' || v_src;
  END IF;
END
$audit$;

-- ── 1. Paramètre : marge SEPA ──────────────────────────────────────────────

INSERT INTO parametres_systeme (cle, valeur, label, description, unite, categorie, val_min, val_max, cablee)
VALUES ('escrow_sepa_marge_jours', 8,
  'Marge SEPA escrow',
  'A4 — marge calendaire minimale avant le début de mission pour initier le débit en SEPA différé (8 j calendaires ≈ 6 j ouvrés). En-deçà : débit immédiat (VIREMENT_INSTANTANE).',
  'jours', 'FINANCE', 0, 60, true)
ON CONFLICT (cle) DO NOTHING;

-- ── 2. Colonnes de pilotage sur paiements_escrow ───────────────────────────

ALTER TABLE paiements_escrow
  ADD COLUMN IF NOT EXISTS debit_prevu_le timestamptz,
  ADD COLUMN IF NOT EXISTS premiere_mission_etab boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS tentatives_debit integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS derniere_tentative_le timestamptz;

CREATE INDEX IF NOT EXISTS idx_paiements_escrow_a_debiter
  ON paiements_escrow (debit_prevu_le)
  WHERE statut = 'INITIE';

-- ── 3. Trigger : création de l'escrow à la confirmation (statut → ASSIGNEE) ─

CREATE OR REPLACE FUNCTION public.fn_trg_escrow_creer_a_confirmation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $esc_conf$
DECLARE
  v_etab           etablissements%ROWTYPE;
  v_soignant_id    uuid;
  v_commission_c   integer;
  v_honoraires_c   integer;
  v_total_c        integer;
  v_premiere       boolean;
  v_marge_jours    integer;
  v_methode        text;
  v_debit_prevu    timestamptz;
BEGIN
  -- Garde flag : escrow éteint → no-op total (tout le trafic actuel).
  IF public.fn_param_num('feature_paiement_rapide_actif', 0) <> 1 THEN
    RETURN NEW;
  END IF;

  -- Escrow réservé au LIBERAL (le régime SALARIE ne passe jamais par Stripe).
  IF NEW.type_contrat_applique <> 'LIBERAL' THEN
    RETURN NEW;
  END IF;

  v_soignant_id := NEW.soignant_assigne_id;
  IF v_soignant_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Déjà un escrow pour cette mission (re-confirmation, idempotence).
  IF EXISTS (SELECT 1 FROM paiements_escrow WHERE mission_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_etab FROM etablissements WHERE id = NEW.etablissement_id;

  -- Mandat SEPA obligatoire : sans lui, pas d'escrow → régime standard (A4).
  IF v_etab.mode_paiement_commission <> 'SEPA_DEBIT'
     OR v_etab.stripe_sepa_payment_method_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_commission_c := ROUND(COALESCE(NEW.montant_commission_ttc, 0) * 100)::integer;
  v_honoraires_c := ROUND(COALESCE(NEW.net_a_payer, 0) * 100)::integer;
  v_total_c := v_commission_c + v_honoraires_c;

  IF v_honoraires_c <= 0 THEN
    RETURN NEW;
  END IF;

  -- Plafond A2 : l'exposition courante + ce montant doit rester sous le plafond,
  -- et l'établissement ne doit pas être gelé. Sinon → régime standard.
  IF NOT public.fn_escrow_etab_eligible(NEW.etablissement_id, v_honoraires_c) THEN
    RETURN NEW;
  END IF;

  -- 1re mission escrow de cet établissement (A2) → débit immédiat.
  v_premiere := NOT EXISTS (
    SELECT 1 FROM paiements_escrow WHERE etablissement_id = NEW.etablissement_id
  );

  v_marge_jours := public.fn_param_num('escrow_sepa_marge_jours', 8)::integer;

  -- A4 + A2 : méthode et timing du débit.
  IF v_premiere THEN
    -- 1re mission : débit immédiat, Jolene fronte sous plafond.
    v_methode := 'VIREMENT_INSTANTANE';
    v_debit_prevu := now();
  ELSIF NEW.debut_le - now() >= make_interval(days => v_marge_jours) THEN
    -- Marge suffisante : SEPA différé, débit initié à J-7 du début.
    v_methode := 'SEPA';
    v_debit_prevu := GREATEST(now(), NEW.debut_le - interval '7 days');
  ELSE
    -- Marge courte : débit immédiat.
    v_methode := 'VIREMENT_INSTANTANE';
    v_debit_prevu := now();
  END IF;

  INSERT INTO paiements_escrow (
    mission_id, etablissement_id, soignant_id,
    montant_total_cents, commission_cents, honoraires_cents,
    methode_debit, statut, debit_prevu_le, premiere_mission_etab
  ) VALUES (
    NEW.id, NEW.etablissement_id, v_soignant_id,
    v_total_c, v_commission_c, v_honoraires_c,
    v_methode, 'INITIE', v_debit_prevu, v_premiere
  );

  PERFORM public.fn_ecrire_audit_safe(
    '00000000-0000-0000-0000-000000000000'::uuid, 'SYSTEME',
    'ESCROW_INITIE', 'mission', NEW.id, NULL,
    jsonb_build_object(
      'etablissement_id', NEW.etablissement_id, 'soignant_id', v_soignant_id,
      'total_cents', v_total_c, 'honoraires_cents', v_honoraires_c,
      'commission_cents', v_commission_c, 'methode', v_methode,
      'premiere_mission_etab', v_premiere, 'debit_prevu_le', v_debit_prevu
    ), NULL, 'fn_trg_escrow_creer_a_confirmation'
  );

  RETURN NEW;
END;
$esc_conf$;

DROP TRIGGER IF EXISTS trg_escrow_creer_a_confirmation ON missions;
CREATE TRIGGER trg_escrow_creer_a_confirmation
  AFTER UPDATE OF statut ON missions
  FOR EACH ROW
  WHEN (NEW.statut = 'ASSIGNEE'::statut_mission
        AND OLD.statut IS DISTINCT FROM 'ASSIGNEE'::statut_mission)
  EXECUTE FUNCTION public.fn_trg_escrow_creer_a_confirmation();

-- ── 4. Enregistrement de l'exposition au débit (A2) ────────────────────────
-- Appelé par l'edge function quand le débit est initié : ouvre la fenêtre
-- remboursable de 8 semaines. (Le décrément = expiration cron PR 2, ou
-- règlement définitif REGLE posé en PR 4/5.)

CREATE OR REPLACE FUNCTION public.fn_escrow_enregistrer_exposition(
  p_paiement_escrow_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $esc_expo$
DECLARE
  v_row paiements_escrow%ROWTYPE;
  v_fenetre_jours integer;
BEGIN
  SELECT * INTO v_row FROM paiements_escrow WHERE id = p_paiement_escrow_id;
  IF v_row.id IS NULL THEN
    RETURN;
  END IF;

  v_fenetre_jours := public.fn_param_num('escrow_fenetre_remboursable_jours', 56)::integer;

  INSERT INTO escrow_exposition_releases (
    etablissement_id, paiement_escrow_id, montant_cents,
    debite_le, expire_le, statut
  ) VALUES (
    v_row.etablissement_id, v_row.id, v_row.honoraires_cents,
    now(), now() + make_interval(days => v_fenetre_jours), 'ACTIF'
  )
  ON CONFLICT (paiement_escrow_id) DO NOTHING;
END;
$esc_expo$;

-- ── 5. Incident → gel + relance (A2) ───────────────────────────────────────
-- Appelé par les handlers webhook (payment_intent.payment_failed, dispute).
-- Gèle l'établissement et programme une relance J+3 sur le paiement.

CREATE OR REPLACE FUNCTION public.fn_escrow_marquer_incident(
  p_paiement_escrow_id uuid,
  p_type_incident text,       -- 'ECHEC' | 'DISPUTE'
  p_detail text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $esc_inc$
DECLARE
  v_row paiements_escrow%ROWTYPE;
  v_nouveau_statut text;
BEGIN
  SELECT * INTO v_row FROM paiements_escrow WHERE id = p_paiement_escrow_id;
  IF v_row.id IS NULL THEN
    RETURN;
  END IF;

  v_nouveau_statut := CASE WHEN p_type_incident = 'DISPUTE' THEN 'DISPUTE' ELSE 'ECHOUE' END;

  UPDATE paiements_escrow
  SET statut = v_nouveau_statut,
      erreur = p_detail,
      -- Relance J+3 uniquement sur un échec de débit (pas sur une dispute,
      -- qui suit son propre circuit contentieux).
      relance_prevue_le = CASE WHEN p_type_incident = 'ECHEC' THEN now() + interval '3 days' ELSE relance_prevue_le END,
      modifie_le = now()
  WHERE id = p_paiement_escrow_id;

  -- Gel du ⚡ de l'établissement au premier incident (A2). Réinitialise aussi
  -- le compteur de confiance.
  PERFORM public.fn_escrow_geler_etablissement(
    v_row.etablissement_id,
    format('%s escrow mission %s : %s', p_type_incident, v_row.mission_id, COALESCE(p_detail, ''))
  );

  UPDATE escrow_etablissement_etat
  SET missions_sans_incident = 0, modifie_le = now()
  WHERE etablissement_id = v_row.etablissement_id;
END;
$esc_inc$;

-- ── 6. Sélection des débits à échéance (consommé par l'edge function) ───────

CREATE OR REPLACE FUNCTION public.fn_escrow_debits_a_echeance(p_limit integer DEFAULT 50)
RETURNS SETOF paiements_escrow
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $esc_due$
  SELECT * FROM paiements_escrow
  WHERE statut = 'INITIE'
    AND debit_prevu_le <= now()
    AND tentatives_debit < 3
  ORDER BY debit_prevu_le ASC
  LIMIT p_limit;
$esc_due$;

-- ── 7. Cron d'appel de l'edge function escrow-debit-echeance ───────────────
-- Toutes les heures : réveille l'edge function qui crée les destination
-- charges des escrows à échéance. Auth via secret vault (cf. CLAUDE.md).

DO $do$
DECLARE v_url text; v_secret text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'escrow-debit-echeance') THEN
    -- L'URL du projet et le secret cron sont lus au moment de l'exécution par
    -- l'edge function elle-même (fn_lire_secret_cron) ; ici on planifie juste
    -- l'appel HTTP. On récupère l'URL projet via un paramètre si disponible,
    -- sinon on laisse l'edge function no-op si le flag est à 0.
    PERFORM cron.schedule('escrow-debit-echeance', '5 * * * *', $cron$
      SELECT net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/escrow-debit-echeance',
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
  RAISE NOTICE 'schedule escrow-debit-echeance: %', SQLERRM;
END
$do$;

-- ── 8. Durcissement des accès ──────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.fn_escrow_enregistrer_exposition(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_escrow_marquer_incident(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_escrow_debits_a_echeance(integer) FROM PUBLIC, anon, authenticated;
