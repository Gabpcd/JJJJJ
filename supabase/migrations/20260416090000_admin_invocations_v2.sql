-- V2: Add internal_status + request_id columns
-- V5-V8 adjustments to trigger

ALTER TABLE public.admin_invocations
  ADD COLUMN IF NOT EXISTS internal_status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (internal_status IN ('PENDING', 'INVOKED', 'COMPLETED', 'CRASHED')),
  ADD COLUMN IF NOT EXISTS request_id UUID DEFAULT gen_random_uuid();

-- Index for crash detection monitoring
CREATE INDEX IF NOT EXISTS idx_admin_inv_pending ON public.admin_invocations(invoked_at) WHERE completed_at IS NULL;

-- Updated trigger with:
-- - internal_status strict transitions (PENDING→INVOKED→COMPLETED, CRASHED from any non-terminal)
-- - request_id as immutable column
-- - V2 atomicity (4 result columns together)
-- See fn_admin_invocations_append_only() applied via MCP apply_migration
