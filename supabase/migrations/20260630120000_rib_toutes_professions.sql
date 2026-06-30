-- RÉGRESSION : 6 professions n'avaient PAS de ligne RIB dans
-- documents_requis_par_profession → le RIB n'était jamais demandé à ces soignants
-- (AS, AES, PHARMACIEN, MANIPULATEUR_RADIO, PREPARATEUR_PHARMA, AUXILIAIRE_PUERICULTURE).
-- Or ils sont rémunérés comme les autres → ils ont besoin d'un RIB (salaire transmis
-- à l'établissement employeur, ou honoraires). La décision « RIB pour tous » date de
-- 20260621170000_rib_visible_tous_exercices mais ces professions (salariées-only /
-- sans RPPS, dont 2 ajoutées au Sprint 17) n'avaient jamais eu la ligne.
--
-- Fix idempotent : ajoute RIB (critique, TOUS) à toute profession qui a une CNI mais
-- pas de RIB. Aligné sur la config RIB existante (IDE). Déjà appliqué en prod via MCP.

INSERT INTO documents_requis_par_profession (profession, type_document, est_critique, a_expiration, duree_validite_mois, description, type_exercice_requis)
SELECT DISTINCT d.profession, 'RIB'::type_document, true, false, NULL::integer,
  'Relevé d''Identité Bancaire — sert au versement de votre rémunération (salaire transmis à l''établissement, ou honoraires).',
  ci.type_exercice_requis
FROM documents_requis_par_profession d
JOIN documents_requis_par_profession ci ON ci.profession = d.profession AND ci.type_document = 'CARTE_IDENTITE'
WHERE NOT EXISTS (
  SELECT 1 FROM documents_requis_par_profession x
  WHERE x.profession = d.profession AND x.type_document = 'RIB'
);
