-- Sweep advisors Supabase (sécurité + performance) — pré-lancement / Série A.
--
-- Sécurité : 0 finding ERROR (aucune table RLS désactivée, aucune vue SECURITY
-- DEFINER, aucune fuite auth). Les 366 « authenticated_security_definer_function_
-- executable » = couche RPC by-design. Les 8 « anon_security_definer_… » = surface
-- publique intentionnelle (aperçu marché, missions publiques SEO, données de
-- référence, inscription liste d'attente) — toutes read-only/reference, aucune
-- donnée privée exposée. Rien à corriger.
--
-- Performance : on corrige les 2 classes sûres et utiles à l'échelle.
--
-- 1. Clés étrangères non indexées (3) — jointures/DELETE plus rapides.
--    litiges est requêté des deux côtés (étab + soignant) en permanence.
CREATE INDEX IF NOT EXISTS idx_litiges_etablissement_id ON public.litiges(etablissement_id);
CREATE INDEX IF NOT EXISTS idx_litiges_soignant_id ON public.litiges(soignant_id);
CREATE INDEX IF NOT EXISTS idx_sales_contacts_groupe_id ON public.sales_contacts(groupe_id);

-- 2. auth_rls_initplan (3) — auth.uid() était ré-évalué PAR LIGNE. Enveloppé dans
--    un sous-select scalaire → évalué une seule fois par requête. Sémantique
--    strictement identique (auth.uid() est STABLE).
ALTER POLICY messages_contact_insert_self ON public.messages_contact
  WITH CHECK (expediteur_id = (SELECT auth.uid()));
ALTER POLICY messages_contact_select_self ON public.messages_contact
  USING (expediteur_id = (SELECT auth.uid()));
ALTER POLICY pol_signalements_select ON public.signalements
  USING ((signaleur_id = (SELECT auth.uid())) OR est_admin());

-- NON corrigé volontairement :
-- - 115 unused_index (INFO) : normal en pré-lancement (pas de charge) ; les
--   supprimer risquerait de pénaliser les requêtes futures.
-- - 7 multiple_permissive_policies (WARN) : paires « admin voit tout » + « user
--   voit le sien » sur des tables financières (factures_honoraires, factor_advances).
--   Les fusionner changerait la structure RLS pour un gain marginal → risque non
--   justifié sur des tables sensibles. Accepté.
