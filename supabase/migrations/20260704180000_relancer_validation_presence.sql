-- 9.1 — « Relancer l'établissement » : le soignant peut, depuis le détail d'une
-- mission dont la présence attend validation, envoyer une relance à
-- l'établissement (throttlée 24h). Complète le deep link « À valider » singleton.

-- ── 1. Autoriser le nouveau type de notification + action d'audit ──────────
DO $notif$
DECLARE v_src text;
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO v_src
  FROM pg_constraint c JOIN pg_class cl ON cl.oid=c.conrelid JOIN pg_namespace n ON n.oid=cl.relnamespace
  WHERE n.nspname='public' AND cl.relname='notifications' AND c.conname='notifications_type_check';
  IF v_src IS NOT NULL AND position('RAPPEL_VALIDATION_PRESENCE' IN v_src)=0 THEN
    v_src := replace(v_src, '])))', ', ''RAPPEL_VALIDATION_PRESENCE''::text])))');
    EXECUTE 'ALTER TABLE notifications DROP CONSTRAINT notifications_type_check';
    EXECUTE 'ALTER TABLE notifications ADD CONSTRAINT notifications_type_check ' || v_src;
  END IF;
END
$notif$;

DO $audit$
DECLARE v_src text;
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO v_src
  FROM pg_constraint c JOIN pg_class cl ON cl.oid=c.conrelid JOIN pg_namespace n ON n.oid=cl.relnamespace
  WHERE n.nspname='public' AND cl.relname='journaux_audit' AND c.conname='journaux_audit_action_check';
  IF v_src IS NOT NULL AND position('PRESENCE_RELANCE_VALIDATION' IN v_src)=0 THEN
    v_src := replace(v_src, '])))', ', ''PRESENCE_RELANCE_VALIDATION''::text])))');
    EXECUTE 'ALTER TABLE journaux_audit DROP CONSTRAINT journaux_audit_action_check';
    EXECUTE 'ALTER TABLE journaux_audit ADD CONSTRAINT journaux_audit_action_check ' || v_src;
  END IF;
END
$audit$;

-- ── 2. RPC de relance (throttle 24h par mission) ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_relancer_validation_presence(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_soignant uuid := auth.uid();
  v_mission RECORD;
  v_intitule text;
BEGIN
  IF v_soignant IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'NON_AUTHENTIFIE');
  END IF;

  SELECT id, etablissement_id, intitule INTO v_mission
  FROM missions
  WHERE id = p_mission_id AND soignant_assigne_id = v_soignant;
  IF v_mission.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'MISSION_INCONNUE');
  END IF;

  -- Il doit exister une présence à pointage complet non encore validée
  -- (miroir du gate 7b-B). Sinon il n'y a rien à relancer.
  IF NOT EXISTS (
    SELECT 1 FROM presences p
    WHERE p.mission_id = p_mission_id
      AND COALESCE(p.valide_par_etablissement, false) = false
      AND p.pointage_depart_le IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'RIEN_A_VALIDER');
  END IF;

  -- Throttle 24h : pas deux relances pour la même mission dans la journée.
  IF EXISTS (
    SELECT 1 FROM notifications
    WHERE type = 'RAPPEL_VALIDATION_PRESENCE'
      AND id_ressource = p_mission_id
      AND cree_le > now() - interval '24 hours'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'DEJA_RELANCE',
      'message', 'Tu as déjà relancé cet établissement aujourd''hui. Il a été notifié.');
  END IF;

  v_intitule := COALESCE(v_mission.intitule, 'une mission');

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
  VALUES (
    v_mission.etablissement_id, 'ETABLISSEMENT', 'RAPPEL_VALIDATION_PRESENCE',
    '⏳ Une présence attend votre validation',
    'Le soignant de « ' || v_intitule || ' » attend la validation de ses présences pour être payé. Merci de valider depuis vos présences.',
    '/etablissement/presences', 'mission', p_mission_id
  );

  PERFORM public.fn_ecrire_audit_safe(
    v_soignant, 'SOIGNANT', 'PRESENCE_RELANCE_VALIDATION', 'mission', p_mission_id,
    NULL, jsonb_build_object('etablissement_id', v_mission.etablissement_id), NULL, 'fn_relancer_validation_presence'
  );

  RETURN jsonb_build_object('success', true,
    'message', 'Établissement relancé. Il a été notifié de valider tes présences.');
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.fn_relancer_validation_presence(uuid) TO authenticated;
