-- Enrichissement Annuaire Santé (FHIR ANS) : enrichi_le marque les prospects
-- déjà interrogés (avec ou sans résultat) pour avancer par tranches sans
-- re-consommer le quota API sur les mêmes fiches.
ALTER TABLE public.prospects_etablissements ADD COLUMN IF NOT EXISTS enrichi_le timestamptz;
ALTER TABLE public.prospects_soignants ADD COLUMN IF NOT EXISTS enrichi_le timestamptz;
CREATE INDEX IF NOT EXISTS idx_prospects_etab_a_enrichir ON public.prospects_etablissements (maj_le) WHERE enrichi_le IS NULL;
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_a_enrichir ON public.prospects_soignants (maj_le) WHERE enrichi_le IS NULL;
