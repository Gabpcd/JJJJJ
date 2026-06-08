-- Diplôme étranger : autorisation d'exercice (PAE) + routage admin.
--
-- Un soignant formé à l'étranger doit fournir, en plus de son diplôme, son
-- AUTORISATION D'EXERCICE délivrée par le ministère (procédure PAE / liste
-- d'aptitude). On ajoute ce type de document comme OPTIONNEL (non critique) pour
-- toutes les professions : il ne bloque pas l'inscription des soignants formés en
-- France, mais permet aux soignants étrangers de téléverser leur autorisation,
-- qui part en revue admin (EN_ATTENTE → AdminModeration).

INSERT INTO public.documents_requis_par_profession
  (profession, type_document, description, est_critique, a_expiration, type_exercice_requis)
SELECT p.profession, 'AUTORISATION_EXERCICE',
       'Autorisation d''exercice (diplôme étranger — procédure PAE / liste d''aptitude). Optionnel : à fournir uniquement si vous êtes formé(e) hors France.',
       false, false, 'TOUS'
FROM (SELECT DISTINCT profession FROM public.documents_requis_par_profession) p
WHERE NOT EXISTS (
  SELECT 1 FROM public.documents_requis_par_profession d
  WHERE d.profession = p.profession AND d.type_document = 'AUTORISATION_EXERCICE'
);
