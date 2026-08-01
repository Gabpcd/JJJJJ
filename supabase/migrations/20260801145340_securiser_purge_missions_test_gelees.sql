-- La purge E2E historique supprimait directement mission_creneaux. Depuis le
-- gel du planning, ce DELETE est légitimement refusé. Le purgeur reste réservé
-- au service_role et pose ici les overrides attendus par les triggers, avec
-- une raison d'audit explicite, uniquement après preuve que toute la mission
-- (établissement, soignant assigné et candidats) est une donnée de test.

CREATE OR REPLACE FUNCTION public.fn_test_purge_mission(p_mission_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  r record;
  v_mission record;
  v_reason constant text := 'PURGE_E2E_MISSION_TECHNIQUE';
  v_previous_test_bypass text := COALESCE(
    pg_catalog.current_setting('app.test_bypass_protections', true),
    ''
  );
  v_previous_gel_id text := COALESCE(
    pg_catalog.current_setting('jolene.admin_override_gel', true),
    ''
  );
  v_previous_gel_reason text := COALESCE(
    pg_catalog.current_setting('jolene.admin_override_reason', true),
    ''
  );
  v_previous_invoice_id text := COALESCE(
    pg_catalog.current_setting('jolene.admin_correction_mission_id', true),
    ''
  );
  v_previous_invoice_reason text := COALESCE(
    pg_catalog.current_setting('jolene.admin_correction_reason', true),
    ''
  );
  v_error_state text;
  v_error_message text;
  v_has_non_test_soignant boolean;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION
      'fn_test_purge_mission réservé au service_role'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT
    m.id,
    m.intitule,
    m.etablissement_id,
    m.soignant_assigne_id,
    m.statut,
    m.fige_le,
    e.est_compte_test AS etablissement_est_test
  INTO v_mission
  FROM public.missions m
  JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE m.id = p_mission_id
  FOR UPDATE OF m;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF (
    v_mission.intitule NOT LIKE '[pw-test:%'
    AND v_mission.intitule NOT LIKE '[playwright-test]%'
  ) OR v_mission.etablissement_est_test IS DISTINCT FROM true THEN
    RAISE EXCEPTION
      'Purge refusée : mission % hors périmètre E2E strict',
      p_mission_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_mission.soignant_assigne_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.soignants s
       WHERE s.id = v_mission.soignant_assigne_id
         AND s.est_compte_test IS TRUE
     ) THEN
    RAISE EXCEPTION
      'Purge refusée : mission % assignée à un soignant non-test',
      p_mission_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.candidatures c
    LEFT JOIN public.soignants s ON s.id = c.soignant_id
    WHERE c.mission_id = p_mission_id
      AND s.est_compte_test IS DISTINCT FROM true
  ) THEN
    RAISE EXCEPTION
      'Purge refusée : mission % liée à une candidature non-test',
      p_mission_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Refuser aussi une relation opérationnelle anormale qui relierait cette
  -- mission technique à un soignant non-test sans passer par candidature ou
  -- affectation. Le contrôle couvre dynamiquement toutes les tables ayant à
  -- la fois une FK directe vers missions.id et une colonne soignant_id.
  FOR r IN
    SELECT
      ns.nspname AS table_schema,
      rel.relname AS table_name,
      mission_col.attname AS mission_column
    FROM pg_catalog.pg_constraint fk
    JOIN pg_catalog.pg_class rel ON rel.oid = fk.conrelid
    JOIN pg_catalog.pg_namespace ns ON ns.oid = rel.relnamespace
    JOIN pg_catalog.pg_attribute mission_col
      ON mission_col.attrelid = fk.conrelid
     AND mission_col.attnum = fk.conkey[1]
    JOIN pg_catalog.pg_attribute soignant_col
      ON soignant_col.attrelid = fk.conrelid
     AND soignant_col.attname = 'soignant_id'
     AND NOT soignant_col.attisdropped
    JOIN pg_catalog.pg_attribute target
      ON target.attrelid = fk.confrelid
     AND target.attnum = fk.confkey[1]
    WHERE fk.contype = 'f'
      AND fk.confrelid = 'public.missions'::pg_catalog.regclass
      AND pg_catalog.array_length(fk.conkey, 1) = 1
      AND pg_catalog.array_length(fk.confkey, 1) = 1
      AND target.attname = 'id'
  LOOP
    EXECUTE pg_catalog.format(
      'SELECT EXISTS ('
      || 'SELECT 1 FROM %I.%I enfant '
      || 'LEFT JOIN public.soignants s ON s.id = enfant.soignant_id '
      || 'WHERE enfant.%I = $1 AND enfant.soignant_id IS NOT NULL '
      || 'AND s.est_compte_test IS DISTINCT FROM true)',
      r.table_schema,
      r.table_name,
      r.mission_column
    ) INTO v_has_non_test_soignant USING p_mission_id;

    IF v_has_non_test_soignant THEN
      RAISE EXCEPTION
        'Purge refusée : mission % liée à un soignant non-test via %.%',
        p_mission_id,
        r.table_schema,
        r.table_name
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END LOOP;

  PERFORM pg_catalog.set_config(
    'app.test_bypass_protections', 'true', true
  );
  PERFORM pg_catalog.set_config(
    'jolene.admin_override_gel', p_mission_id::text, true
  );
  PERFORM pg_catalog.set_config(
    'jolene.admin_override_reason', v_reason, true
  );
  PERFORM pg_catalog.set_config(
    'jolene.admin_correction_mission_id', p_mission_id::text, true
  );
  PERFORM pg_catalog.set_config(
    'jolene.admin_correction_reason', v_reason, true
  );

  INSERT INTO public.journaux_audit (
    acteur_id,
    type_acteur,
    action,
    type_ressource,
    id_ressource,
    details
  ) VALUES (
    auth.uid(),
    'SERVICE_API',
    'SYSTEM',
    'mission',
    p_mission_id,
    pg_catalog.jsonb_build_object(
      'reason', v_reason,
      'test_data_only', true,
      'previous_status', v_mission.statut,
      'was_frozen', v_mission.fige_le IS NOT NULL,
      'etablissement_id', v_mission.etablissement_id
    )
  );

  -- Neutraliser d'abord la fixture évite que la resynchronisation déclenchée
  -- par la suppression du dernier créneau considère encore une mission active
  -- assignée. Les statuts terminaux restent inchangés.
  UPDATE public.missions m
  SET statut = CASE
        WHEN m.statut IN (
          'OUVERTE',
          'ASSIGNEE',
          'EN_COURS',
          'LITIGE'
        ) THEN 'ANNULEE_PAR_ETABLISSEMENT'::public.statut_mission
        ELSE m.statut
      END,
      soignant_assigne_id = NULL,
      fige_le = NULL
  WHERE m.id = p_mission_id;

  -- Enfants indirects et références JSON sans cascade.
  DELETE FROM public.messages_chat mc
  WHERE mc.conversation_id IN (
    SELECT c.id
    FROM public.conversations c
    WHERE c.mission_id = p_mission_id
  );

  DELETE FROM public.notifications n
  WHERE n.id_ressource = p_mission_id
     OR n.lien = '/etablissement/missions/' || p_mission_id::text;

  DELETE FROM public.email_queue q
  WHERE q.data @> pg_catalog.jsonb_build_object('mission_id', p_mission_id);

  -- Enfants indirects RESTRICT/NO ACTION : ils doivent disparaître avant les
  -- lignes directes factures_honoraires, factures et litiges.
  DELETE FROM public.stripe_refunds_queue q
  WHERE q.facture_origine_id IN (
      SELECT fh.id FROM public.factures_honoraires fh
      WHERE fh.mission_id = p_mission_id
    )
     OR q.avoir_id IN (
      SELECT fh.id FROM public.factures_honoraires fh
      WHERE fh.mission_id = p_mission_id
    );

  DELETE FROM public.chorus_submissions cs
  WHERE cs.invoice_id IN (
    SELECT fh.id FROM public.factures_honoraires fh
    WHERE fh.mission_id = p_mission_id
  );

  DELETE FROM public.invoice_audit_log ial
  WHERE ial.invoice_id IN (
    SELECT fh.id FROM public.factures_honoraires fh
    WHERE fh.mission_id = p_mission_id
  );

  DELETE FROM public.messages_litige ml
  WHERE ml.litige_id IN (
    SELECT l.id FROM public.litiges l
    WHERE l.mission_id = p_mission_id
  );

  DELETE FROM public.stripe_transfers st
  WHERE st.mission_id = p_mission_id
     OR st.facture_id IN (
      SELECT f.id FROM public.factures f
      WHERE f.mission_id = p_mission_id
    );

  DELETE FROM public.stripe_refunds_queue q
  WHERE q.paiement_escrow_id IN (
    SELECT pe.id FROM public.paiements_escrow pe
    WHERE pe.mission_id = p_mission_id
  );
  DELETE FROM public.escrow_release_queue q
  WHERE q.paiement_escrow_id IN (
    SELECT pe.id FROM public.paiements_escrow pe
    WHERE pe.mission_id = p_mission_id
  );
  DELETE FROM public.escrow_exposition_releases q
  WHERE q.paiement_escrow_id IN (
    SELECT pe.id FROM public.paiements_escrow pe
    WHERE pe.mission_id = p_mission_id
  );

  -- partages_rib dépend aussi du contrat et du document : le supprimer avant
  -- le parcours générique rend l'ordre déterministe.
  DELETE FROM public.partages_rib pr
  WHERE pr.mission_id = p_mission_id;

  -- Toutes les FK directes, mono-colonne, vers missions.id. Les identifiants
  -- proviennent exclusivement des catalogues PostgreSQL et sont quotés.
  FOR r IN
    SELECT
      ns.nspname AS table_schema,
      rel.relname AS table_name,
      src.attname AS column_name
    FROM pg_catalog.pg_constraint fk
    JOIN pg_catalog.pg_class rel ON rel.oid = fk.conrelid
    JOIN pg_catalog.pg_namespace ns ON ns.oid = rel.relnamespace
    JOIN pg_catalog.pg_attribute src
      ON src.attrelid = fk.conrelid
     AND src.attnum = fk.conkey[1]
    JOIN pg_catalog.pg_attribute target
      ON target.attrelid = fk.confrelid
     AND target.attnum = fk.confkey[1]
    WHERE fk.contype = 'f'
      AND fk.confrelid = 'public.missions'::pg_catalog.regclass
      AND fk.conrelid <> 'public.missions'::pg_catalog.regclass
      AND pg_catalog.array_length(fk.conkey, 1) = 1
      AND pg_catalog.array_length(fk.confkey, 1) = 1
      AND target.attname = 'id'
    ORDER BY
      CASE WHEN rel.relname = 'mission_creneaux' THEN 1 ELSE 0 END,
      fk.oid
  LOOP
    EXECUTE pg_catalog.format(
      'DELETE FROM %I.%I WHERE %I = $1',
      r.table_schema,
      r.table_name,
      r.column_name
    ) USING p_mission_id;
  END LOOP;

  DELETE FROM public.missions m WHERE m.id = p_mission_id;

  PERFORM pg_catalog.set_config(
    'app.test_bypass_protections', v_previous_test_bypass, true
  );
  PERFORM pg_catalog.set_config(
    'jolene.admin_override_gel', v_previous_gel_id, true
  );
  PERFORM pg_catalog.set_config(
    'jolene.admin_override_reason', v_previous_gel_reason, true
  );
  PERFORM pg_catalog.set_config(
    'jolene.admin_correction_mission_id', v_previous_invoice_id, true
  );
  PERFORM pg_catalog.set_config(
    'jolene.admin_correction_reason', v_previous_invoice_reason, true
  );
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS
    v_error_state = RETURNED_SQLSTATE,
    v_error_message = MESSAGE_TEXT;
  PERFORM pg_catalog.set_config(
    'app.test_bypass_protections', v_previous_test_bypass, true
  );
  PERFORM pg_catalog.set_config(
    'jolene.admin_override_gel', v_previous_gel_id, true
  );
  PERFORM pg_catalog.set_config(
    'jolene.admin_override_reason', v_previous_gel_reason, true
  );
  PERFORM pg_catalog.set_config(
    'jolene.admin_correction_mission_id', v_previous_invoice_id, true
  );
  PERFORM pg_catalog.set_config(
    'jolene.admin_correction_reason', v_previous_invoice_reason, true
  );
  RAISE EXCEPTION '[PURGE_E2E_DURABLE] %', v_error_message
    USING ERRCODE = v_error_state;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_test_purge_mission(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_test_purge_mission(uuid)
  TO service_role;

COMMENT ON FUNCTION public.fn_test_purge_mission(uuid) IS
  'Purge auditée, service_role-only, des missions E2E dont toutes les parties liées sont explicitement marquées test.';

DO $assertions$
DECLARE
  v_security_definer boolean;
BEGIN
  SELECT p.prosecdef
  INTO v_security_definer
  FROM pg_catalog.pg_proc p
  WHERE p.oid = 'public.fn_test_purge_mission(uuid)'::pg_catalog.regprocedure;

  IF v_security_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'fn_test_purge_mission doit rester SECURITY DEFINER';
  END IF;
  IF pg_catalog.has_function_privilege(
       'anon', 'public.fn_test_purge_mission(uuid)', 'EXECUTE'
     ) OR pg_catalog.has_function_privilege(
       'authenticated', 'public.fn_test_purge_mission(uuid)', 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'fn_test_purge_mission exposée à un utilisateur ordinaire';
  END IF;
  IF NOT pg_catalog.has_function_privilege(
    'service_role', 'public.fn_test_purge_mission(uuid)', 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'fn_test_purge_mission inaccessible au service_role';
  END IF;
END;
$assertions$;
