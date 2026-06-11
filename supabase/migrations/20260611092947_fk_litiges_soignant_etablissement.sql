-- Fix AdminLitiges « Impossible de charger les litiges » : PostgREST ne peut pas
-- résoudre les embeds soignants:soignant_id / etablissements:etablissement_id
-- sans FK. 0 orphelin vérifié avant ajout.
ALTER TABLE public.litiges
  ADD CONSTRAINT litiges_soignant_id_fkey
  FOREIGN KEY (soignant_id) REFERENCES public.soignants(id) ON DELETE CASCADE;

ALTER TABLE public.litiges
  ADD CONSTRAINT litiges_etablissement_id_fkey
  FOREIGN KEY (etablissement_id) REFERENCES public.etablissements(id) ON DELETE CASCADE;

NOTIFY pgrst, 'reload schema';
