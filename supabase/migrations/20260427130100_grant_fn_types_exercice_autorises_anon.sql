-- fn_types_exercice_autorises est appelée pendant l'inscription soignant
-- (avant que le user soit authentifié comme SOIGNANT) → 401 Unauthorized.
--
-- La fonction ne lit que des données publiques (table de référence
-- regles_exercice_profession qui mappe profession → types autorisés). Aucun
-- secret. Elle est SECURITY DEFINER + STABLE.
--
-- Fix : grant EXECUTE à anon pour que les inscrits non-authentifiés
-- puissent voir les types d'exercice autorisés selon leur profession choisie
-- dans le formulaire d'inscription (utilisé par le hook
-- useTypesExerciceAutorises et ExerciceTypeSection).

GRANT EXECUTE ON FUNCTION public.fn_types_exercice_autorises(text) TO anon;
