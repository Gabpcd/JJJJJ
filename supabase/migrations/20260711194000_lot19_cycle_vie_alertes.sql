-- Lot 19 — Canal d'alerte fiable. Aujourd'hui `alertes_systeme` empile N lignes
-- par (source, type) (fenêtre de dédup 1h) et n'a pas d'états ni d'auto-résolution
-- → 23 lignes actives = 3 problèmes réels noyés. On rend le canal fiable :
--   1) dédup par (source, type) avec compteur + première/dernière occurrence ;
--   2) états Active / Résolue / Acquittée ;
--   3) auto-résolution sur run VERT (jamais sur absence de run) + fenêtre de grâce
--      72h pour les crons décommissionnés (orphelins) ;
--   4) RPC admin des alertes ACTIVES dédupliquées (vue par défaut).

-- 1. Cycle de vie sur la table.
ALTER TABLE public.alertes_systeme
  ADD COLUMN IF NOT EXISTS occurrences integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS derniere_occurrence timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS acquitte_le timestamptz,
  ADD COLUMN IF NOT EXISTS resolu_motif text;

-- Collapse des doublons ACTIFS existants (sinon l'index unique échoue) : on garde
-- la ligne la plus récente par (source, type), avec occurrences = count et
-- première/dernière occurrence recalculées ; les autres sont résolues « fusion ».
WITH ranked AS (
  SELECT id,
    row_number() OVER (PARTITION BY source, type_alerte ORDER BY cree_le DESC) AS rn,
    count(*)      OVER (PARTITION BY source, type_alerte) AS cnt,
    min(cree_le)  OVER (PARTITION BY source, type_alerte) AS premiere,
    max(cree_le)  OVER (PARTITION BY source, type_alerte) AS derniere
  FROM public.alertes_systeme WHERE resolu_le IS NULL
)
UPDATE public.alertes_systeme a
   SET occurrences = r.cnt, cree_le = r.premiere, derniere_occurrence = r.derniere
  FROM ranked r WHERE a.id = r.id AND r.rn = 1;

WITH ranked AS (
  SELECT id, row_number() OVER (PARTITION BY source, type_alerte ORDER BY cree_le DESC) AS rn
  FROM public.alertes_systeme WHERE resolu_le IS NULL
)
UPDATE public.alertes_systeme a
   SET resolu_le = now(), resolu_motif = 'fusion doublon (dédup Lot 19)'
  FROM ranked r WHERE a.id = r.id AND r.rn > 1;

-- A4-bis — triage des alertes historiques (cause écrite + résolution). Les 3
-- séries actives correspondent à des crons superseded/reconfigurés :
UPDATE public.alertes_systeme SET resolu_le = now(),
  resolu_motif = 'triage Lot 19 : doublon de jolene_recalcul_scores_etab (vert) — ancien cron décommissionné'
  WHERE resolu_le IS NULL AND source = 'matching_scores_recalcul_hourly';
UPDATE public.alertes_systeme SET resolu_le = now(),
  resolu_motif = 'triage Lot 19 : remplacé par les vagues de notification (Lot 17) — cron décommissionné'
  WHERE resolu_le IS NULL AND source = 'relance-candidatures-en-attente';
UPDATE public.alertes_systeme SET resolu_le = now(),
  resolu_motif = 'triage Lot 19 : retards fin juin (planning/seuil corrigé), zéro récurrence depuis 10j'
  WHERE resolu_le IS NULL AND source = 'sepa-auto-charge-daily';

-- Index de dédup : une seule alerte ACTIVE par (source, type_alerte).
CREATE UNIQUE INDEX IF NOT EXISTS uidx_alertes_actives_source_type
  ON public.alertes_systeme (source, type_alerte) WHERE resolu_le IS NULL;

-- 2. Émission dédupliquée : UPSERT sur l'alerte active (source, type) → incrémente
-- le compteur + rafraîchit dernière occurrence/message, au lieu d'empiler.
CREATE OR REPLACE FUNCTION public.fn_emettre_alerte_monitoring(p_type text, p_severite text, p_source text, p_message text, p_details jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_id UUID;
BEGIN
  IF NOT fn_est_contexte_cron_ou_admin() THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  INSERT INTO alertes_systeme (type_alerte, severite, source, message, details, occurrences, derniere_occurrence)
  VALUES (p_type, p_severite, p_source, p_message, p_details, 1, now())
  ON CONFLICT (source, type_alerte) WHERE resolu_le IS NULL
  DO UPDATE SET
    occurrences = alertes_systeme.occurrences + 1,
    derniere_occurrence = now(),
    severite = EXCLUDED.severite,
    message = EXCLUDED.message,
    details = EXCLUDED.details
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- 3. Résolution / acquittement (admin).
CREATE OR REPLACE FUNCTION public.fn_resoudre_alerte(p_id uuid, p_motif text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  UPDATE alertes_systeme SET resolu_le = now(), resolu_motif = p_motif WHERE id = p_id AND resolu_le IS NULL;
  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_acquitter_alerte(p_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  UPDATE alertes_systeme SET acquitte_le = now() WHERE id = p_id AND resolu_le IS NULL;
  RETURN jsonb_build_object('success', true);
END;
$function$;

-- 4. Auto-résolution : une alerte CRON ne se résout QUE sur run VERT (jamais sur
-- absence de run), OU si son cron est décommissionné (orphelin) et la dernière
-- occurrence date de > 72h (fenêtre de grâce — le cron aurait re-fired sinon).
CREATE OR REPLACE FUNCTION public.fn_auto_resoudre_alertes_crons()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_alerte RECORD; v_last_status text; v_last_run timestamptz; v_job_exists boolean; v_n int := 0;
BEGIN
  IF NOT fn_est_contexte_cron_ou_admin() THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  FOR v_alerte IN SELECT id, source, derniere_occurrence FROM alertes_systeme
                  WHERE resolu_le IS NULL AND type_alerte LIKE 'CRON%' LOOP
    SELECT true, d.status, d.start_time INTO v_job_exists, v_last_status, v_last_run
    FROM cron.job j
    LEFT JOIN LATERAL (SELECT status, start_time FROM cron.job_run_details WHERE jobid = j.jobid ORDER BY start_time DESC LIMIT 1) d ON true
    WHERE j.jobname = v_alerte.source
    LIMIT 1;

    IF v_job_exists AND v_last_status = 'succeeded' AND v_last_run > v_alerte.derniere_occurrence THEN
      UPDATE alertes_systeme SET resolu_le = now(), resolu_motif = 'auto: cron repassé vert' WHERE id = v_alerte.id;
      v_n := v_n + 1;
    ELSIF v_job_exists IS NULL AND v_alerte.derniere_occurrence < now() - INTERVAL '72 hours' THEN
      -- cron décommissionné (plus dans cron.job) + fenêtre de grâce écoulée
      UPDATE alertes_systeme SET resolu_le = now(), resolu_motif = 'auto: cron décommissionné (orphelin, >72h)' WHERE id = v_alerte.id;
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('success', true, 'resolues', v_n);
END;
$function$;

-- 5. RPC admin : alertes ACTIVES dédupliquées (vue par défaut du cockpit).
CREATE OR REPLACE FUNCTION public.fn_admin_alertes_actives()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'id', id, 'type', type_alerte, 'severite', severite, 'source', source,
    'message', message, 'occurrences', occurrences,
    'premiere', cree_le, 'derniere', derniere_occurrence,
    'acquittee', acquitte_le IS NOT NULL
  ) ORDER BY (severite = 'CRITICAL') DESC, derniere_occurrence DESC)
  FROM alertes_systeme WHERE resolu_le IS NULL), '[]'::jsonb);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_resoudre_alerte(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_acquitter_alerte(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_alertes_actives() TO authenticated;

-- 6. Cron d'auto-résolution (recapturé en repo — garde pg_cron pour les branches).
SELECT cron.schedule('jolene_auto_resoudre_alertes', '20 */2 * * *', $$SELECT public.fn_auto_resoudre_alertes_crons();$$)
WHERE NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'jolene_auto_resoudre_alertes');
