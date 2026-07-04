-- Ajouter admin_notes sur factures_honoraires pour les annotations admin
-- (nettoyage test, notes internes, motif d'annulation)
ALTER TABLE public.factures_honoraires ADD COLUMN IF NOT EXISTS admin_notes TEXT;
