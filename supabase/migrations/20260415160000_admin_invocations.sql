-- ═══════════════════════════════════════════════════════════════════════════
-- admin-invoke infrastructure : table, triggers, RPC, rétention, GRANTs
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1. Table admin_invocations ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.admin_invocations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id UUID NOT NULL REFERENCES auth.users(id),
  target_function TEXT NOT NULL,
  target_payload JSONB,
  reason TEXT NOT NULL,
  dry_run BOOLEAN NOT NULL DEFAULT false,
  is_test BOOLEAN NOT NULL DEFAULT false,
  -- Filled BEFORE invocation
  invoked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Filled AFTER invocation (initially NULL, filled atomically in 1 UPDATE)
  status_returned INTEGER,
  duration_ms INTEGER,
  response_excerpt TEXT,
  completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_admin_inv_user ON public.admin_invocations(admin_user_id, invoked_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_inv_function ON public.admin_invocations(target_function, invoked_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_inv_invoked ON public.admin_invocations(invoked_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_inv_pending ON public.admin_invocations(invoked_at) WHERE completed_at IS NULL;

-- ─── 2. Trigger append-only (strict) ──────────────────────────────────────
--
-- UPDATE : les 4 colonnes résultat doivent être remplies ATOMIQUEMENT
-- (toutes ensemble, de NULL vers NOT NULL, en un seul UPDATE).
-- Pas de réécriture, pas d'update partiel.
-- DELETE : refusé sauf par la purge via advisory lock transactionnel.

CREATE OR REPLACE FUNCTION public.fn_admin_invocations_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_immutable_changed BOOLEAN;
  v_result_cols_were_null BOOLEAN;
  v_result_cols_now_set BOOLEAN;
  v_result_cols_unchanged BOOLEAN;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- Seul la purge peut delete (le lock est déjà acquis dans la même tx)
    IF pg_try_advisory_xact_lock(hashtext('admin_invocations_purge')) THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'DELETE interdit sur admin_invocations (audit ops)';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- ── Colonnes immuables : aucune ne doit changer ──
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.admin_user_id IS DISTINCT FROM OLD.admin_user_id
       OR NEW.target_function IS DISTINCT FROM OLD.target_function
       OR NEW.target_payload IS DISTINCT FROM OLD.target_payload
       OR NEW.reason IS DISTINCT FROM OLD.reason
       OR NEW.dry_run IS DISTINCT FROM OLD.dry_run
       OR NEW.is_test IS DISTINCT FROM OLD.is_test
       OR NEW.invoked_at IS DISTINCT FROM OLD.invoked_at
    THEN
      RAISE EXCEPTION 'admin_invocations: colonnes contexte immuables après INSERT';
    END IF;

    -- ── Colonnes résultat : vérification atomique ──
    v_result_cols_were_null :=
      OLD.status_returned IS NULL
      AND OLD.duration_ms IS NULL
      AND OLD.response_excerpt IS NULL
      AND OLD.completed_at IS NULL;

    v_result_cols_now_set :=
      NEW.status_returned IS NOT NULL
      AND NEW.duration_ms IS NOT NULL
      AND NEW.response_excerpt IS NOT NULL
      AND NEW.completed_at IS NOT NULL;

    v_result_cols_unchanged :=
      NEW.status_returned IS NOT DISTINCT FROM OLD.status_returned
      AND NEW.duration_ms IS NOT DISTINCT FROM OLD.duration_ms
      AND NEW.response_excerpt IS NOT DISTINCT FROM OLD.response_excerpt
      AND NEW.completed_at IS NOT DISTINCT FROM OLD.completed_at;

    -- Cas 1 : silent update (rien ne change) → OK
    IF v_result_cols_unchanged THEN
      RETURN NEW;
    END IF;

    -- Cas 2 : toutes les 4 passent de NULL à NOT NULL → OK
    IF v_result_cols_were_null AND v_result_cols_now_set THEN
      RETURN NEW;
    END IF;

    -- Tout autre cas → rejet
    IF NOT v_result_cols_were_null THEN
      RAISE EXCEPTION 'admin_invocations: résultat déjà rempli, réécriture interdite';
    ELSE
      RAISE EXCEPTION 'admin_invocations: les 4 colonnes résultat (status_returned, duration_ms, response_excerpt, completed_at) doivent être remplies ensemble en un seul UPDATE';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_admin_inv_append_only ON public.admin_invocations;
CREATE TRIGGER trg_admin_inv_append_only
  BEFORE UPDATE OR DELETE ON public.admin_invocations
  FOR EACH ROW
  EXECUTE FUNCTION fn_admin_invocations_append_only();

-- ─── 3. RPC est_admin_valide() ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.est_admin_valide()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(
    (SELECT
      raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
      AND COALESCE(banned_until, '1970-01-01'::timestamptz) < now()
      AND email_confirmed_at IS NOT NULL
    FROM auth.users WHERE id = auth.uid()),
    false
  );
$$;

-- ─── 4. Purge scheduled (rétention différenciée) ─────────────────────────
--
-- Politique de rétention :
-- - Fonctions sensibles (generate-invoice, submit-to-chorus,
--   factor-request-advance) : 10 ANS (= durée de vie facture)
-- - Invocations ECHOUEES non-sensibles : 2 ans
-- - Invocations REUSSIES non-sensibles + jamais complétées : 90 jours

CREATE OR REPLACE FUNCTION public.fn_admin_invocations_purge()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_deleted INTEGER := 0;
  v_partial INTEGER;
  v_lock_acquired BOOLEAN;
BEGIN
  v_lock_acquired := pg_try_advisory_xact_lock(hashtext('admin_invocations_purge'));
  IF NOT v_lock_acquired THEN
    RAISE EXCEPTION 'Purge déjà en cours (lock non acquis)';
  END IF;

  -- Fonctions sensibles : 10 ans (aligné sur conservation factures)
  DELETE FROM admin_invocations
  WHERE target_function IN ('generate-invoice', 'submit-to-chorus', 'factor-request-advance')
    AND invoked_at < now() - INTERVAL '10 years';
  GET DIAGNOSTICS v_partial = ROW_COUNT;
  v_deleted := v_deleted + v_partial;

  -- Echecs non-sensibles : 2 ans
  DELETE FROM admin_invocations
  WHERE target_function NOT IN ('generate-invoice', 'submit-to-chorus', 'factor-request-advance')
    AND status_returned IS NOT NULL
    AND status_returned >= 400
    AND invoked_at < now() - INTERVAL '2 years';
  GET DIAGNOSTICS v_partial = ROW_COUNT;
  v_deleted := v_deleted + v_partial;

  -- Succès non-sensibles + jamais complétés : 90 jours
  DELETE FROM admin_invocations
  WHERE target_function NOT IN ('generate-invoice', 'submit-to-chorus', 'factor-request-advance')
    AND (status_returned IS NULL OR status_returned < 400)
    AND invoked_at < now() - INTERVAL '90 days';
  GET DIAGNOSTICS v_partial = ROW_COUNT;
  v_deleted := v_deleted + v_partial;

  RETURN v_deleted;
END;
$$;

-- ─── 5. RLS ───────────────────────────────────────────────────────────────

ALTER TABLE public.admin_invocations ENABLE ROW LEVEL SECURITY;

-- Admins peuvent LIRE les invocations
DROP POLICY IF EXISTS "admin_inv_select" ON public.admin_invocations;
CREATE POLICY "admin_inv_select" ON public.admin_invocations
  FOR SELECT TO authenticated
  USING (est_admin_valide());

-- Pas de policy INSERT/UPDATE pour authenticated :
-- l'écriture passe par service_role depuis l'edge function admin-invoke.

-- ─── 6. GRANTs ────────────────────────────────────────────────────────────

-- authenticated : SELECT uniquement (lecture via admin UI)
GRANT SELECT ON public.admin_invocations TO authenticated;
-- Pas de INSERT/UPDATE pour authenticated (surface d'attaque minimale)

-- service_role : full write (edge function admin-invoke)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.admin_invocations TO service_role;

-- Functions
GRANT EXECUTE ON FUNCTION public.est_admin_valide() TO authenticated;
GRANT EXECUTE ON FUNCTION public.est_admin_valide() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_invocations_purge() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_invocations_append_only() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_invocations_append_only() TO service_role;
