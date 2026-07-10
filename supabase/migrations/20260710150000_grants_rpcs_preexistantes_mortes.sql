-- Fix (audit 10/07/2026) : 3 RPC appelées par le frontend mais SANS GRANT
-- authenticated → 42501 « permission denied » pour tout utilisateur connecté.
-- Bugs PRÉ-EXISTANTS (antérieurs aux lots 11-17), surfacés par l'audit croisé
-- « toutes les RPC appelées par src/ vs leurs droits en prod ». Chacune a un
-- contrôle d'accès INTERNE (est_admin() ou auth.uid()) — granter authenticated
-- ne les expose donc pas, ça les rend seulement exécutables par le chemin UI
-- prévu.
--
--   fn_scanner_code_pointage : scan QR rotatif soignant (PointageRotatifSoignant,
--     monté dans PresencesSoignant). Contrôle auth.uid() interne. Sans grant, le
--     pointage rotatif échouait pour tout soignant.
--   fn_admin_lister_parametres / fn_admin_maj_parametre : page /admin/config
--     (ADMIN_PLATEFORME). Contrôle est_admin() interne. Sans grant, l'admin ne
--     pouvait ni lister ni éditer les paramètres via l'UI.
--
-- NOTE : fn_calculer_bfa_safe (WidgetBFA) est aussi sans grant, mais (a) le
-- composant n'est monté nulle part (code mort) et (b) la fonction n'a AUCUN
-- contrôle d'accès interne → on ne la grante PAS (ce serait une exposition). À
-- traiter séparément (ajouter un check ou retirer le code mort) avant câblage.
GRANT EXECUTE ON FUNCTION public.fn_scanner_code_pointage(text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_lister_parametres() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_maj_parametre(text, numeric) TO authenticated;
