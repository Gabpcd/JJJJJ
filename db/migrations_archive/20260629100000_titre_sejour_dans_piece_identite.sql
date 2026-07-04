-- Le titre de séjour est une PIÈCE D'IDENTITÉ (document officiel avec photo), pas
-- un document à part. Il doit être accepté AU MÊME NIVEAU que la carte d'identité
-- et le passeport dans le slot « Pièce d'identité » — exactement comme le fait déjà
-- le parcours établissement (dropdown CNI/passeport/titre de séjour).
--
-- La migration 20260628120000 l'avait ajouté comme ligne OPTIONNELLE séparée pour
-- toutes les professions → incohérent (un soignant dont l'identité est déjà vérifiée
-- voyait quand même « Titre de séjour » proposé à part). On retire ces lignes : le
-- titre de séjour se téléverse désormais dans le slot identité (type CARTE_IDENTITE),
-- que verify-document accepte indifféremment (CNI / passeport / titre de séjour).

DELETE FROM documents_requis_par_profession WHERE type_document = 'TITRE_SEJOUR';

-- Libellé du slot identité : rendre explicite que le titre de séjour est accepté.
UPDATE documents_requis_par_profession
SET description = 'Carte nationale d''identité, passeport ou titre de séjour en cours de validité.'
WHERE type_document = 'CARTE_IDENTITE';
