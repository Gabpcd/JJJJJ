-- Helper de test : purge robuste d'une mission de test et de TOUS ses enfants FK.
--
-- Les cleanups E2E (global-setup + afterEach) listaient les tables enfant à la
-- main et en oubliaient (rappels_contrat_travail, messages_chat) → le DELETE
-- missions échouait en silence (FK) → mission laissée ASSIGNÉE au soignant de
-- test partagé → test suivant en échec par chevauchement (run CI à 1 worker, donc
-- en série). Cette fonction supprime dynamiquement tous les enfants FK + la mission.
--
-- Garde-fou STRICT : refuse toute mission dont l'intitulé n'est pas un préfixe de
-- test ([pw-test… / [playwright-test]…). Aucune donnée réelle ne peut être touchée.

CREATE OR REPLACE FUNCTION public.fn_test_purge_mission(p_mission_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r RECORD;
  v_intitule text;
BEGIN
  SELECT intitule INTO v_intitule FROM missions WHERE id = p_mission_id;
  IF v_intitule IS NULL THEN RETURN; END IF;
  IF v_intitule NOT LIKE '[pw-test%' AND v_intitule NOT LIKE '[playwright-test]%' THEN
    RAISE EXCEPTION 'fn_test_purge_mission reserve aux missions de test (intitule=%)', v_intitule;
  END IF;

  -- messages_chat : enfant de conversations (FK conversation_id, pas mission_id).
  DELETE FROM messages_chat WHERE conversation_id IN (SELECT id FROM conversations WHERE mission_id = p_mission_id);

  -- Toutes les tables ayant une FK directe vers missions.id (hors auto-référence missions).
  FOR r IN
    SELECT c.conrelid::regclass::text AS tbl, a.attname AS col
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'f' AND c.confrelid = 'public.missions'::regclass
      AND c.conrelid <> 'public.missions'::regclass
  LOOP
    EXECUTE format('DELETE FROM %s WHERE %I = $1', r.tbl, r.col) USING p_mission_id;
  END LOOP;

  DELETE FROM missions WHERE id = p_mission_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_test_purge_mission(uuid) TO service_role;
