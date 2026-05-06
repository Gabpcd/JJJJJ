-- Bug pré-existant : la table mandats_facturation_signatures avait des
-- policies RLS pour SELECT (admin/soignant) mais aucun GRANT SELECT sur
-- authenticated. Résultat : le soignant ne pouvait pas relire sa propre
-- signature pour générer le PDF du mandat → "permission denied for table".
--
-- Fix : ajout du GRANT SELECT pour le rôle authenticated. La RLS reste
-- active et applique toujours `auth.uid() = soignant_id OR est_admin()`.

GRANT SELECT ON public.mandats_facturation_signatures TO authenticated;

NOTIFY pgrst, 'reload schema';
