-- Vérification IA des attestations d'heures externes (parcours 3200h libéral)
--
-- Jusqu'ici, les heures externes déclarées par un soignant (expérience avant
-- Jolene) étaient stockées avec statut EN_ATTENTE et validées MANUELLEMENT.
-- L'attestation téléversée n'était jamais lue. On ajoute ici les colonnes
-- nécessaires pour que l'edge function `verify-heures-externes` lise le
-- document via Anthropic Vision (comme verify-document pour l'identité),
-- extraie le nombre d'heures, et confronte au déclaré.
--
-- Validation auto VALIDE uniquement si cohérent (extrait ≈ déclaré) ;
-- sinon EN_ATTENTE (revue admin) ; REJETE si document non conforme.

ALTER TABLE public.heures_externes_soignants
  ADD COLUMN IF NOT EXISTS heures_extraites_ia INTEGER NULL,
  ADD COLUMN IF NOT EXISTS resultat_ia JSONB NULL,
  ADD COLUMN IF NOT EXISTS coherence_ia BOOLEAN NULL,
  ADD COLUMN IF NOT EXISTS verifie_ia_le TIMESTAMPTZ NULL;

COMMENT ON COLUMN public.heures_externes_soignants.heures_extraites_ia IS
  'Nombre d''heures lu par l''IA sur l''attestation (NULL si non extrait).';
COMMENT ON COLUMN public.heures_externes_soignants.resultat_ia IS
  'Verdict JSON complet renvoyé par Anthropic Vision (traçabilité / diagnostic).';
COMMENT ON COLUMN public.heures_externes_soignants.coherence_ia IS
  'TRUE si heures_extraites_ia cohérent avec heures_declarees (tolérance), FALSE sinon, NULL si non évalué.';
COMMENT ON COLUMN public.heures_externes_soignants.verifie_ia_le IS
  'Horodatage de la vérification IA automatique.';
