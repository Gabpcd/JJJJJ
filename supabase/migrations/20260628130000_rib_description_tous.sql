-- RIB requis pour TOUS (salarié + libéral) — décision produit confirmée.
-- L'ancienne description « (compte professionnel libéral) » laissait croire que le
-- RIB n'était demandé qu'aux libéraux, alors que la config est bien TOUS. On
-- neutralise le libellé pour qu'il soit cohérent avec « obligatoire pour tous ».

UPDATE documents_requis_par_profession
SET description = 'Relevé d''Identité Bancaire — sert au versement de votre rémunération (salaire transmis à l''établissement, ou honoraires).'
WHERE type_document = 'RIB';
