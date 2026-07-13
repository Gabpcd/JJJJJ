-- Ces deux vues ont ete introduites comme projections de partage lors du P0,
-- mais aucun client applicatif, Edge Function ni objet SQL ne les consomme.
-- Elles restent SECURITY DEFINER par defaut et sont donc signalees ERROR par
-- les Security Advisors Supabase.
--
-- security_invoker=true ne preserve pas leur contrat : les RLS P0 des tables
-- soignants/etablissements n'autorisent volontairement que le profil propre ou
-- l'admin. Il ne faut surtout pas elargir ces policies, car cela rendrait aussi
-- les colonnes sensibles des tables directement lisibles.
--
-- RESTRICT (comportement par defaut, rendu explicite ici) garantit qu'un objet
-- SQL dependant fera echouer le deploiement au lieu d'etre supprime en cascade.
DROP VIEW IF EXISTS public.vue_soignants_etablissement RESTRICT;
DROP VIEW IF EXISTS public.vue_etablissements_soignant RESTRICT;
