-- Refonte.D.3.a — Ajout enum NOTATION_RAPPEL (committed seul, ALTER TYPE)
ALTER TYPE public.type_evenement_notification ADD VALUE IF NOT EXISTS 'NOTATION_RAPPEL';
