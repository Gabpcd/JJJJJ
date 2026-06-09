-- Vérification IA du contrat de travail de mission (salarié).
--
-- BlocContratTravailMission téléverse le contrat de travail (CDD/CDI) signé pour une
-- mission salariée, dans contrats_travail_missions, sans AUCUNE vérification IA.
-- Cette migration ajoute les colonnes de résultat ; la vérification est faite par
-- l'edge function verify-contrat-travail (Anthropic Vision) : confirme que c'est un
-- contrat de travail, et que les parties (soignant + établissement) concordent.

ALTER TABLE public.contrats_travail_missions
  ADD COLUMN IF NOT EXISTS ia_resultat jsonb,
  ADD COLUMN IF NOT EXISTS ia_coherent boolean,
  ADD COLUMN IF NOT EXISTS ia_verifie_le timestamptz;
