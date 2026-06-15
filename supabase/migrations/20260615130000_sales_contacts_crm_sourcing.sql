-- CRM sourcing : réponse au contact, file « à rappeler », filtres dept/type.
ALTER TABLE public.sales_contacts
  ADD COLUMN IF NOT EXISTS reponse text,
  ADD COLUMN IF NOT EXISTS a_rappeler boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS departement text,
  ADD COLUMN IF NOT EXISTS type_etab text,
  ADD COLUMN IF NOT EXISTS dernier_contact_le timestamptz;

ALTER TABLE public.sales_contacts DROP CONSTRAINT IF EXISTS sales_contacts_reponse_check;
ALTER TABLE public.sales_contacts ADD CONSTRAINT sales_contacts_reponse_check
  CHECK (reponse IS NULL OR reponse IN ('EN_ATTENTE', 'POSITIVE', 'NEGATIVE'));

-- Backfill département + type établissement depuis les prospects FINESS déjà sourcés.
UPDATE public.sales_contacts sc
SET departement = pe.departement, type_etab = pe.type_jolene
FROM public.prospects_etablissements pe
WHERE sc.finess = pe.finess AND sc.departement IS NULL;
