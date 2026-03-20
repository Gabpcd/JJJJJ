
-- Add type_contrat_recherche column to missions
ALTER TABLE public.missions 
ADD COLUMN IF NOT EXISTS type_contrat_recherche text NOT NULL DEFAULT 'TOUS';

-- Add check constraint
ALTER TABLE public.missions 
ADD CONSTRAINT chk_type_contrat_recherche 
CHECK (type_contrat_recherche IN ('TOUS', 'SALARIE', 'LIBERAL'));

-- Backfill from existing description tags
UPDATE public.missions 
SET type_contrat_recherche = 'SALARIE' 
WHERE description LIKE '%[CONTRAT:SALARIE]%';

UPDATE public.missions 
SET type_contrat_recherche = 'LIBERAL' 
WHERE description LIKE '%[CONTRAT:LIBERAL]%';
