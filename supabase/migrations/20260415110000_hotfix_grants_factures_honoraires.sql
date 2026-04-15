-- ═══════════════════════════════════════════════════════════════════════════
-- HOTFIX : GRANTs manquants sur factures_honoraires + tables PR1
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Root cause : la migration PR1 (20260413140000) a créé 3 nouvelles tables
-- et étendu factures_honoraires SANS ajouter de GRANT pour les roles
-- authenticated et service_role. PostgREST retournait "permission denied"
-- (403) pour tout accès direct à ces tables.
--
-- factures_honoraires était AUSSI sans GRANTs AVANT PR1 (table créée par
-- Lovable via dashboard, pas via CLI). Ça "marchait" uniquement parce que
-- les RPCs SECURITY DEFINER (fn_mes_factures_honoraires) s'exécutent en
-- tant que postgres. Le SELECT direct dans MesFacturesHonoraires.tsx:67
-- échouait silencieusement (masqué par maybeSingle()).
--
-- Principes appliqués :
-- - Pas de DELETE pour authenticated (obligation fiscale 10 ans)
-- - chorus_submissions + factoring_partners : lecture seule authenticated
-- - invoice_audit_log : append-only au niveau GRANT (SELECT + INSERT)

-- factures_honoraires
GRANT SELECT, INSERT, UPDATE ON public.factures_honoraires TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.factures_honoraires TO service_role;

-- chorus_submissions (écriture via edge functions uniquement)
GRANT SELECT ON public.chorus_submissions TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.chorus_submissions TO service_role;

-- invoice_audit_log (append-only strict)
GRANT SELECT, INSERT ON public.invoice_audit_log TO authenticated;
GRANT SELECT, INSERT ON public.invoice_audit_log TO service_role;

-- factoring_partners (lecture seule authenticated, admin via service_role)
GRANT SELECT ON public.factoring_partners TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.factoring_partners TO service_role;
