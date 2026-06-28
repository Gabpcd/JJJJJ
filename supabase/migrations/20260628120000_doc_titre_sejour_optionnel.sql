-- Carte/titre de séjour : ajoute TITRE_SEJOUR comme document OPTIONNEL (autorisation
-- de travail) pour toutes les professions. Le type existait dans l'enum + était géré
-- par verify-document, mais n'était dans AUCUNE ligne de documents_requis_par_profession
-- → jamais proposé au soignant. Optionnel : à fournir uniquement par les ressortissants
-- hors UE. a_expiration = true (le titre a une date de validité).

INSERT INTO documents_requis_par_profession (profession, type_document, est_critique, a_expiration, duree_validite_mois, description, type_exercice_requis)
SELECT DISTINCT d.profession, 'TITRE_SEJOUR'::type_document, false, true, NULL::integer,
  'Titre de séjour en cours de validité — uniquement si vous êtes ressortissant(e) hors Union européenne (autorisation de travail).',
  ci.type_exercice_requis
FROM documents_requis_par_profession d
JOIN documents_requis_par_profession ci ON ci.profession = d.profession AND ci.type_document = 'CARTE_IDENTITE'
WHERE NOT EXISTS (
  SELECT 1 FROM documents_requis_par_profession x
  WHERE x.profession = d.profession AND x.type_document = 'TITRE_SEJOUR'
);
