
-- Feature 2: Salaire minimum soignant
ALTER TABLE public.soignants 
ADD COLUMN IF NOT EXISTS taux_horaire_minimum numeric DEFAULT NULL;

-- Feature 5: Parrainage revu - badge ambassadeur
ALTER TABLE public.soignants 
ADD COLUMN IF NOT EXISTS badge_ambassadeur boolean NOT NULL DEFAULT false;

ALTER TABLE public.soignants 
ADD COLUMN IF NOT EXISTS priorite_missions_urgentes boolean NOT NULL DEFAULT false;
