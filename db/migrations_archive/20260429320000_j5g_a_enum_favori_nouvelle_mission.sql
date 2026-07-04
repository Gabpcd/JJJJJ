-- J5.G.A — Favoris bidirectionnels (rename + nouvelle table + RPCs + trigger)
--
-- Étape 1 : ajout enum value (doit committer seul, ALTER TYPE)
ALTER TYPE public.type_evenement_notification ADD VALUE IF NOT EXISTS 'FAVORI_NOUVELLE_MISSION';
