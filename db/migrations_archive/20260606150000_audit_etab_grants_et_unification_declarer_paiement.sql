-- AUDIT cohérence interface établissement — corrections backend.
-- Trois RPC appelées par le frontend établissement existaient mais n'étaient PAS
-- exécutables par le rôle authenticated → erreur 403 au runtime (PostgREST).
-- Toutes sont SECURITY DEFINER avec autorisation interne (est_admin / mon_etablissement_id).
--
-- 1) fn_proposer_mission_soignant : grantée à postgres seulement.
--    Appelée par DetailMission → RechercheRemplacantUrgence (proposer un remplaçant).
-- 2) fn_auto_facturation_mensuelle : non grantée.
--    Appelée par AdminFacturation (génération facture mensuelle). Garde est_admin() interne.
-- 3) fn_declarer_paiement_soignant : DEUX overloads coexistaient.
--    - 5-arg (legacy, SANS attestation sur l'honneur)
--    - 6-arg (complet, AVEC attestation légale + détection Stripe Connect)
--    Le 6-arg n'était pas granté → FacturationEtablissement (qui passe l'attestation)
--    tombait en 403. WorkflowPaiementMission appelait le 5-arg (sans attestation légale).
--    UNIFICATION : on supprime le 5-arg legacy et on grante le 6-arg. Le frontend
--    (WorkflowPaiementMission) passe désormais l'attestation sur l'honneur (case ajoutée),
--    cohérent avec FacturationEtablissement. Évite aussi l'ambiguïté de résolution
--    PostgREST entre les deux overloads.

-- 1) proposer mission
GRANT EXECUTE ON FUNCTION public.fn_proposer_mission_soignant(uuid, uuid, text) TO authenticated;

-- 2) facturation mensuelle (admin)
GRANT EXECUTE ON FUNCTION public.fn_auto_facturation_mensuelle() TO authenticated;

-- 3) déclaration paiement soignant — supprimer le legacy 5-arg, granter le 6-arg
DROP FUNCTION IF EXISTS public.fn_declarer_paiement_soignant(uuid, numeric, text, text, date);
GRANT EXECUTE ON FUNCTION public.fn_declarer_paiement_soignant(uuid, numeric, text, text, date, boolean) TO authenticated;
