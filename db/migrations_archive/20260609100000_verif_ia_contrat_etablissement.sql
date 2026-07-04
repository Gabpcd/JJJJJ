-- Vérification IA du contrat de service établissement.
--
-- Avant : l'upload du contrat (ContratPlateforme) appelait verify-document avec un
-- document_id factice ("contrat-plateforme-<id>", pas un UUID de documents_soignants)
-- → échec silencieux. AUCUNE vérification IA n'avait lieu : le contrat n'était que
-- validé manuellement par un admin, sans contrôle que c'est bien un contrat, que le
-- SIRET / la raison sociale / le signataire correspondent à l'établissement vérifié.
--
-- Cette migration ajoute les colonnes de stockage du résultat IA. La vérification
-- elle-même est faite par l'edge function verify-contrat-etablissement (Anthropic
-- Vision sur le PDF), appelée à l'upload ET au re-upload.

ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS contrat_ia_resultat jsonb,
  ADD COLUMN IF NOT EXISTS contrat_ia_coherent boolean,
  ADD COLUMN IF NOT EXISTS contrat_ia_verifie_le timestamptz;

COMMENT ON COLUMN public.etablissements.contrat_ia_resultat IS
  'Résultat brut de la vérification IA du contrat (type détecté, SIRET extrait, signataires, indices falsification, verdict).';
COMMENT ON COLUMN public.etablissements.contrat_ia_coherent IS
  'true = IA confirme contrat + SIRET + identité cohérents ; false = incohérence/falsification → revue admin ; NULL = non vérifié.';
