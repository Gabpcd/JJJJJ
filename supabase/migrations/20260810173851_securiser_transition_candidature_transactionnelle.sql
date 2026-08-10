-- Autorisation interne, précise et transactionnelle des transitions de
-- candidature déclenchées par fn_repondre_proposition. Aucun rôle applicatif
-- ne peut écrire dans cette table privée ; le trigger exige la même connexion,
-- la même transaction, la même candidature et le statut exact attendu.
BEGIN;

CREATE TABLE IF NOT EXISTS private.candidature_transition_context (
  operation_id uuid NOT NULL,
  backend_pid integer NOT NULL,
  transaction_id bigint NOT NULL,
  candidature_id uuid NOT NULL,
  mission_id uuid NOT NULL,
  allowed_status text NOT NULL,
  CONSTRAINT candidature_transition_context_pkey
    PRIMARY KEY (operation_id, candidature_id, allowed_status),
  CONSTRAINT candidature_transition_context_status_check
    CHECK (allowed_status IN ('ACCEPTEE', 'REFUSEE', 'EXPIREE'))
);

ALTER TABLE private.candidature_transition_context OWNER TO postgres;
CREATE INDEX IF NOT EXISTS idx_candidature_transition_context_lookup
  ON private.candidature_transition_context (
    backend_pid, transaction_id, candidature_id, mission_id, allowed_status
  );
REVOKE ALL ON TABLE private.candidature_transition_context
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE private.candidature_transition_context IS
  'Contexte éphémère d’autorisation des transitions de candidature : PID + transaction + ligne + statut.';

CREATE OR REPLACE FUNCTION public.fn_enforce_etablissement_rbac_trigger()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_row jsonb;
  v_old_row jsonb;
  v_new_row jsonb;
  v_etab_id uuid;
  v_mission_id uuid;
  v_permission text := TG_ARGV[0];
  v_context text := COALESCE(
    current_setting('jolene.empechement_mission_context', true), ''
  );
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  IF TG_TABLE_NAME = 'missions'
     AND v_context <> ''
     AND v_context = COALESCE(
       current_setting('jolene.empechement_mission_validated', true), ''
     )
     AND (
       (
         TG_OP = 'UPDATE'
         AND (
           v_context IN (
             'FLAG:' || (to_jsonb(OLD)->>'id') || ':' || auth.uid()::text,
             'CLOSE:' || (to_jsonb(OLD)->>'id') || ':' || auth.uid()::text
           )
           OR (
             to_jsonb(NEW)->>'remplacement_de_mission_id' IS NOT NULL
             AND v_context = 'REPLACEMENT:'
               || (to_jsonb(NEW)->>'remplacement_de_mission_id')
               || ':' || auth.uid()::text
           )
         )
       )
       OR (
         TG_OP = 'INSERT'
         AND to_jsonb(NEW)->>'remplacement_de_mission_id' IS NOT NULL
         AND v_context = 'REPLACEMENT:'
           || (to_jsonb(NEW)->>'remplacement_de_mission_id')
           || ':' || auth.uid()::text
       )
     ) THEN
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'candidatures' THEN
    v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
    IF v_row ->> 'soignant_id' = auth.uid()::text
       OR EXISTS (
         SELECT 1
           FROM private.candidature_transition_context ctx
          WHERE ctx.backend_pid = pg_backend_pid()
            AND ctx.transaction_id = txid_current()
            AND ctx.candidature_id = (v_row ->> 'id')::uuid
            AND ctx.mission_id = (v_row ->> 'mission_id')::uuid
            AND ctx.allowed_status = v_row ->> 'statut'
       ) THEN
      IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
  END IF;

  IF public.fn_role_etablissement_courant(NULL) IS NULL THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  IF TG_OP = 'UPDATE' THEN
    v_old_row := to_jsonb(OLD);
    v_new_row := to_jsonb(NEW);
  END IF;
  IF COALESCE(v_row ->> 'etablissement_id', '') ~ '^[0-9a-fA-F-]{36}$' THEN
    v_etab_id := (v_row ->> 'etablissement_id')::uuid;
  END IF;
  IF v_etab_id IS NULL
     AND COALESCE(v_row ->> 'mission_id', '') ~ '^[0-9a-fA-F-]{36}$' THEN
    v_mission_id := (v_row ->> 'mission_id')::uuid;
    SELECT m.etablissement_id INTO v_etab_id
    FROM public.missions m WHERE m.id = v_mission_id;
  END IF;

  IF v_etab_id IS NOT NULL
     AND v_permission = 'missions'
     AND TG_TABLE_NAME = 'missions'
     AND TG_OP = 'UPDATE'
     AND public.fn_a_permission_etablissement('pointage', v_etab_id)
     AND (
       v_new_row - ARRAY[
         'code_arrivee', 'code_depart', 'code_pointage_actif',
         'code_pointage_hmac', 'prochain_type_scan', 'nb_scans',
         'presence_confirmee_le', 'modifie_le'
       ]::text[]
     ) = (
       v_old_row - ARRAY[
         'code_arrivee', 'code_depart', 'code_pointage_actif',
         'code_pointage_hmac', 'prochain_type_scan', 'nb_scans',
         'presence_confirmee_le', 'modifie_le'
       ]::text[]
     ) THEN
    RETURN NEW;
  END IF;

  IF v_etab_id IS NULL
     OR NOT public.fn_a_permission_etablissement(v_permission, v_etab_id) THEN
    RAISE EXCEPTION 'Permission etablissement % requise', v_permission
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_protect_candidature_statut()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF auth.uid() IS NULL OR public.est_admin() THEN RETURN NEW; END IF;

  IF EXISTS (
    SELECT 1
      FROM private.candidature_transition_context ctx
     WHERE ctx.backend_pid = pg_backend_pid()
       AND ctx.transaction_id = txid_current()
       AND ctx.candidature_id = OLD.id
       AND ctx.mission_id = OLD.mission_id
       AND ctx.allowed_status = NEW.statut
  ) THEN
    IF NEW.mission_id IS DISTINCT FROM OLD.mission_id
       OR NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
      RAISE EXCEPTION 'Modification interdite';
    END IF;
    IF OLD.statut = 'PROPOSEE'
       AND NEW.statut IN ('ACCEPTEE', 'REFUSEE', 'EXPIREE') THEN
      NEW.message := OLD.message;
      RETURN NEW;
    END IF;
    IF OLD.statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE')
       AND NEW.statut = 'REFUSEE' THEN
      NEW.message := OLD.message;
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Transition de statut candidature non autorisée: % → %', OLD.statut, NEW.statut;
  END IF;

  IF auth.uid() = OLD.soignant_id THEN
    IF NEW.mission_id IS DISTINCT FROM OLD.mission_id
       OR NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
      RAISE EXCEPTION 'Modification interdite';
    END IF;
    IF NEW.statut IS DISTINCT FROM OLD.statut THEN
      IF OLD.statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB')
         AND NEW.statut = 'ANNULEE' THEN
        RETURN NEW;
      ELSIF OLD.statut = 'ACCEPTEE'
            AND NEW.statut = 'ANNULEE'
            AND COALESCE(current_setting('jolene.annulation_soignant_ctx', true), '') = 'true' THEN
        RETURN NEW;
      ELSE
        RAISE EXCEPTION 'Vous ne pouvez pas modifier le statut de votre candidature (% → %)',
          OLD.statut, NEW.statut;
      END IF;
    END IF;
    IF NEW.message IS DISTINCT FROM OLD.message AND OLD.statut <> 'EN_ATTENTE' THEN
      RAISE EXCEPTION 'Vous ne pouvez plus modifier votre message';
    END IF;
    NEW.motif_refus := OLD.motif_refus;
    NEW.traite_le := OLD.traite_le;
    RETURN NEW;
  END IF;

  IF public.mon_etablissement_id() IS NOT NULL THEN
    IF NEW.mission_id IS DISTINCT FROM OLD.mission_id
       OR NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
      RAISE EXCEPTION 'Modification interdite';
    END IF;
    IF NEW.statut IS DISTINCT FROM OLD.statut
       AND NOT (
         (OLD.statut = 'EN_ATTENTE' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE'))
         OR (OLD.statut = 'EN_ATTENTE_VALIDATION_ETAB' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE'))
         OR (OLD.statut = 'PROPOSEE' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE', 'EXPIREE'))
       ) THEN
      RAISE EXCEPTION 'Transition de statut candidature non autorisée: % → %', OLD.statut, NEW.statut;
    END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Accès refusé à cette candidature';
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_repondre_proposition(
  p_candidature_id uuid,
  p_accepter boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_candidature record;
  v_result jsonb;
  v_operation_id uuid := gen_random_uuid();
  v_backend_pid integer := pg_backend_pid();
  v_transaction_id bigint := txid_current();
BEGIN
  SELECT c.* INTO v_candidature
    FROM public.candidatures c
   WHERE c.id = p_candidature_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Candidature introuvable'); END IF;
  IF v_candidature.soignant_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  IF v_candidature.statut <> 'PROPOSEE' THEN
    RETURN jsonb_build_object('error', 'Cette proposition n’est plus en attente');
  END IF;

  IF v_candidature.cree_le < now() - interval '2 hours' THEN
    INSERT INTO private.candidature_transition_context (
      operation_id, backend_pid, transaction_id,
      candidature_id, mission_id, allowed_status
    ) VALUES (
      v_operation_id, v_backend_pid, v_transaction_id,
      p_candidature_id, v_candidature.mission_id, 'EXPIREE'
    );
    UPDATE public.candidatures
       SET statut = 'EXPIREE', traite_le = now()
     WHERE id = p_candidature_id;
    DELETE FROM private.candidature_transition_context
     WHERE operation_id = v_operation_id;
    RETURN jsonb_build_object('error', 'Cette proposition a expiré');
  END IF;

  IF NOT p_accepter THEN
    INSERT INTO private.candidature_transition_context (
      operation_id, backend_pid, transaction_id,
      candidature_id, mission_id, allowed_status
    ) VALUES (
      v_operation_id, v_backend_pid, v_transaction_id,
      p_candidature_id, v_candidature.mission_id, 'REFUSEE'
    );
    UPDATE public.candidatures
       SET statut = 'REFUSEE', traite_le = now()
     WHERE id = p_candidature_id;
    DELETE FROM private.candidature_transition_context
     WHERE operation_id = v_operation_id;
    RETURN jsonb_build_object('success', true, 'message', 'Proposition refusée');
  END IF;

  v_result := public.fn_finaliser_attribution_mission(
    v_candidature.mission_id,
    v_candidature.soignant_id,
    v_candidature.type_contrat_choisi
  );
  IF COALESCE((v_result->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_result;
  END IF;

  INSERT INTO private.candidature_transition_context (
    operation_id, backend_pid, transaction_id,
    candidature_id, mission_id, allowed_status
  ) VALUES (
    v_operation_id, v_backend_pid, v_transaction_id,
    p_candidature_id, v_candidature.mission_id, 'ACCEPTEE'
  );
  INSERT INTO private.candidature_transition_context (
    operation_id, backend_pid, transaction_id,
    candidature_id, mission_id, allowed_status
  )
  SELECT
    v_operation_id, v_backend_pid, v_transaction_id,
    c.id, c.mission_id, 'REFUSEE'
    FROM public.candidatures c
   WHERE c.mission_id = v_candidature.mission_id
     AND c.id <> p_candidature_id
     AND c.statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE');

  UPDATE public.candidatures
     SET statut = 'ACCEPTEE', traite_le = now()
   WHERE id = p_candidature_id;
  UPDATE public.candidatures
     SET statut = 'REFUSEE', motif_refus = 'Mission attribuée', traite_le = now()
   WHERE mission_id = v_candidature.mission_id
     AND id <> p_candidature_id
     AND statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE');
  DELETE FROM private.candidature_transition_context
   WHERE operation_id = v_operation_id;

  RETURN v_result || jsonb_build_object('message', 'Proposition acceptée');
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_repondre_proposition(uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_repondre_proposition(uuid, boolean)
  TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_protect_candidature_statut()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_protect_candidature_statut()
  TO service_role;
REVOKE ALL ON FUNCTION public.fn_enforce_etablissement_rbac_trigger()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_enforce_etablissement_rbac_trigger()
  TO service_role;

WITH reviewed(signature, qualified_signature, categorie, justification) AS (
  VALUES
    (
      'fn_repondre_proposition(uuid,boolean)',
      'public.fn_repondre_proposition(uuid,boolean)',
      'RPC_UTILISATEUR_AUTH_INTERNE',
      'RPC authenticated : autorisation de transition exacte, privée et bornée à la transaction.'
    ),
    (
      'fn_protect_candidature_statut()',
      'public.fn_protect_candidature_statut()',
      'SERVICE_ONLY_REVOQUE',
      'Trigger interne : protège les transitions et exige une autorisation privée exacte de la RPC métier.'
    ),
    (
      'fn_enforce_etablissement_rbac_trigger()',
      'public.fn_enforce_etablissement_rbac_trigger()',
      'SERVICE_ONLY_REVOQUE',
      'Trigger interne RBAC : reconnaît uniquement le contexte candidature privé de la même transaction.'
    )
)
INSERT INTO private.security_definer_inventory (
  signature, categorie, definition_md5, justification, recense_le
)
SELECT r.signature, r.categorie, md5(p.prosrc), r.justification, now()
  FROM reviewed r
  JOIN pg_catalog.pg_proc p
    ON p.oid = pg_catalog.to_regprocedure(r.qualified_signature)
 WHERE p.prosecdef IS TRUE
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

DO $assert_candidature_transition_context$
BEGIN
  IF has_table_privilege(
       'anon', 'private.candidature_transition_context', 'SELECT'
     )
     OR has_table_privilege(
       'authenticated', 'private.candidature_transition_context', 'SELECT'
     )
     OR has_table_privilege(
       'authenticated', 'private.candidature_transition_context', 'INSERT'
     )
     OR has_table_privilege(
       'service_role', 'private.candidature_transition_context', 'INSERT'
     ) THEN
    RAISE EXCEPTION 'Le contexte de transition candidature est exposé à un rôle applicatif';
  END IF;

  IF (
    SELECT count(*)
      FROM private.security_definer_inventory i
      JOIN pg_catalog.pg_proc p
        ON p.oid = pg_catalog.to_regprocedure('public.' || i.signature)
     WHERE i.signature IN (
       'fn_repondre_proposition(uuid,boolean)',
       'fn_protect_candidature_statut()',
       'fn_enforce_etablissement_rbac_trigger()'
     )
       AND i.definition_md5 = md5(p.prosrc)
  ) <> 3 THEN
    RAISE EXCEPTION 'Inventaire SECURITY DEFINER candidature non aligné';
  END IF;
END;
$assert_candidature_transition_context$;

COMMIT;
