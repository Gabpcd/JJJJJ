-- ─── Hardening : fix function_search_path_mutable (Supabase advisor) ───
--
-- 18 fonctions n'avaient pas `SET search_path TO 'public'` → vulnérable au
-- search path hijacking (un attaquant avec le droit CREATE sur un schéma
-- dans le search_path peut injecter des fonctions qui shadow les fonctions
-- système comme `auth.uid()`). Fix via ALTER FUNCTION.
--
-- Advisor : https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable

ALTER FUNCTION public.fn_admin_cohort_economics(p_mois integer) SET search_path TO 'public';
ALTER FUNCTION public.fn_analytics_etablissement(p_etablissement_id uuid, p_mois integer) SET search_path TO 'public';
ALTER FUNCTION public.fn_calculer_heures_majorees(p_debut timestamp with time zone, p_fin timestamp with time zone) SET search_path TO 'public';
ALTER FUNCTION public.fn_check_rate_limit(p_action text, p_max_per_minute integer) SET search_path TO 'public';
ALTER FUNCTION public.fn_dashboard_soignant_complet() SET search_path TO 'public';
ALTER FUNCTION public.fn_matching_soignants(p_mission_id uuid) SET search_path TO 'public';
ALTER FUNCTION public.fn_postuler_mission(p_mission_id uuid, p_message text, p_choix_contrat text) SET search_path TO 'public';
ALTER FUNCTION public.fn_supprimer_mon_compte() SET search_path TO 'public';
ALTER FUNCTION public.fn_trg_auto_commission_facturee() SET search_path TO 'public';
ALTER FUNCTION public.fn_trg_auto_heures_majorees() SET search_path TO 'public';
ALTER FUNCTION public.fn_trg_auto_proposition_pool_urgence() SET search_path TO 'public';
ALTER FUNCTION public.fn_trg_coherence_statut_soignant() SET search_path TO 'public';
ALTER FUNCTION public.fn_trg_email_evaluation() SET search_path TO 'public';
ALTER FUNCTION public.fn_trg_email_mission_terminee() SET search_path TO 'public';
ALTER FUNCTION public.fn_trg_email_paiement_confirme() SET search_path TO 'public';
ALTER FUNCTION public.fn_trg_sms_annulation_tardive() SET search_path TO 'public';
ALTER FUNCTION public.fn_trg_sms_mission_urgente() SET search_path TO 'public';
ALTER FUNCTION public.fn_upsert_token_push(p_token text, p_plateforme text) SET search_path TO 'public';
