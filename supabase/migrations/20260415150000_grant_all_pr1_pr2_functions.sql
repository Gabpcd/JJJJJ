-- GRANT EXECUTE on ALL functions created by PR1, PR2, and réclamations
-- that were missing permissions for authenticated / service_role.
--
-- Root cause : CREATE OR REPLACE FUNCTION in Supabase grants EXECUTE
-- only to postgres by default. The authenticated and service_role roles
-- need explicit GRANT to call functions via PostgREST.

-- PR1: next_invoice_number
GRANT EXECUTE ON FUNCTION public.next_invoice_number(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.next_invoice_number(uuid) TO service_role;

-- PR1: trigger functions (needed by PostgREST for trigger execution context)
GRANT EXECUTE ON FUNCTION public.fn_protect_facture_honoraire_immutability() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_protect_facture_honoraire_immutability() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_fh_auto_audit() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fh_auto_audit() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_fh_updated_at() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fh_updated_at() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_fh_detect_public_sector() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fh_detect_public_sector() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_block_audit_log_delete() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_block_audit_log_delete() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_block_audit_log_update() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_block_audit_log_update() TO service_role;

-- Réclamations: fn_soumettre_reclamation (called by frontend authenticated users)
GRANT EXECUTE ON FUNCTION public.fn_soumettre_reclamation(text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_soumettre_reclamation(text, text, text, uuid) TO service_role;

-- Réclamations: fn_traiter_reclamation_generale (admin-only via est_admin() check)
GRANT EXECUTE ON FUNCTION public.fn_traiter_reclamation_generale(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_traiter_reclamation_generale(uuid, text, text) TO service_role;

-- Fix 2: fn_admin_stripe_connect_stats (service_role was missing)
GRANT EXECUTE ON FUNCTION public.fn_admin_stripe_connect_stats() TO service_role;
