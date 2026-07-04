-- Sprint Hotfix UX Documents PR 1 — Matrice documents requis par profession + exercice
--
-- Bug : la table documents_requis_par_profession propose des documents non
-- pertinents selon profession + type d'exercice :
--   - AS/AES voyaient RPPS_ADELI + RCP_ASSURANCE (ni Ordre, ni libéral)
--   - PHARMACIEN/MANIPULATEUR_RADIO voyaient RCP (toujours salariés)
--   - Libéraux voyaient KBIS (= sociétés ; les libéraux soignants sont en BNC)
--
-- Fix :
--   1. Ajout colonne type_exercice_requis (SALARIE_ONLY / LIBERAL_ONLY / TOUS)
--   2. Re-seed complet selon matrice validée CEO
--   3. Retrait total du KBIS (remplacé par RIB + ATTESTATION_URSSAF côté libéral)
--
-- Matrice CEO :
--   - CARTE_IDENTITE + DIPLOME : critique TOUS, toutes professions
--   - AS, AES, PREPARATEUR_PHARMA : rien d'autre (pas d'Ordre, jamais libéral)
--   - PHARMACIEN, MANIPULATEUR_RADIO : RPPS/ADELI critique TOUS + rien d'autre
--   - IDE/IBODE/IADE/SAGE_FEMME/MEDECIN/KINE : RPPS critique TOUS
--       + RCP/RIB/URSSAF critique LIBERAL_ONLY
--   - ORTHOPHONISTE/ERGO/PSYCHOMOT/DIETETICIEN : ADELI critique TOUS
--       + RCP/RIB/URSSAF critique LIBERAL_ONLY
--
-- Note RPPS vs ADELI : le type_document reste RPPS_ADELI (enum unique).
-- La distinction est portée par la colonne description + gérée par la
-- vérification Annuaire Santé (verify-rpps) qui accepte les 2 numéros.

ALTER TABLE public.documents_requis_par_profession
  ADD COLUMN IF NOT EXISTS type_exercice_requis text NOT NULL DEFAULT 'TOUS';

ALTER TABLE public.documents_requis_par_profession
  DROP CONSTRAINT IF EXISTS chk_type_exercice_requis;
ALTER TABLE public.documents_requis_par_profession
  ADD CONSTRAINT chk_type_exercice_requis
  CHECK (type_exercice_requis IN ('SALARIE_ONLY', 'LIBERAL_ONLY', 'TOUS'));

-- Re-seed complet
DELETE FROM public.documents_requis_par_profession;

-- 1. CARTE_IDENTITE — critique TOUS, toutes professions
INSERT INTO public.documents_requis_par_profession
  (profession, type_document, est_critique, type_exercice_requis, a_expiration, duree_validite_mois, description)
SELECT p::type_profession, 'CARTE_IDENTITE'::type_document, true, 'TOUS', true, NULL,
  'Carte d''identité ou passeport en cours de validité'
FROM unnest(ARRAY['IDE','AS','AES','IBODE','IADE','SAGE_FEMME','KINE','MEDECIN','PHARMACIEN','MANIPULATEUR_RADIO','PREPARATEUR_PHARMA','DIETETICIEN','ERGOTHERAPEUTE','PSYCHOMOTRICIEN','ORTHOPHONISTE']) AS p;

-- 2. DIPLOME — critique TOUS, toutes professions
INSERT INTO public.documents_requis_par_profession
  (profession, type_document, est_critique, type_exercice_requis, a_expiration, duree_validite_mois, description)
SELECT p::type_profession, 'DIPLOME'::type_document, true, 'TOUS', false, NULL,
  'Diplôme d''État ou équivalent'
FROM unnest(ARRAY['IDE','AS','AES','IBODE','IADE','SAGE_FEMME','KINE','MEDECIN','PHARMACIEN','MANIPULATEUR_RADIO','PREPARATEUR_PHARMA','DIETETICIEN','ERGOTHERAPEUTE','PSYCHOMOTRICIEN','ORTHOPHONISTE']) AS p;

-- 3. RPPS — critique TOUS pour professions à identifiant RPPS
INSERT INTO public.documents_requis_par_profession
  (profession, type_document, est_critique, type_exercice_requis, a_expiration, duree_validite_mois, description)
SELECT p::type_profession, 'RPPS_ADELI'::type_document, true, 'TOUS', false, NULL,
  'Attestation d''inscription RPPS'
FROM unnest(ARRAY['IDE','IBODE','IADE','SAGE_FEMME','KINE','MEDECIN','PHARMACIEN']) AS p;

-- 4. ADELI — critique TOUS pour professions à identifiant ADELI
INSERT INTO public.documents_requis_par_profession
  (profession, type_document, est_critique, type_exercice_requis, a_expiration, duree_validite_mois, description)
SELECT p::type_profession, 'RPPS_ADELI'::type_document, true, 'TOUS', false, NULL,
  'Attestation d''inscription ADELI'
FROM unnest(ARRAY['MANIPULATEUR_RADIO','ORTHOPHONISTE','ERGOTHERAPEUTE','PSYCHOMOTRICIEN','DIETETICIEN']) AS p;

-- 5. RCP_ASSURANCE — critique LIBERAL_ONLY pour professions éligibles libéral
INSERT INTO public.documents_requis_par_profession
  (profession, type_document, est_critique, type_exercice_requis, a_expiration, duree_validite_mois, description)
SELECT p::type_profession, 'RCP_ASSURANCE'::type_document, true, 'LIBERAL_ONLY', true, 12,
  'Assurance Responsabilité Civile Professionnelle (exercice libéral)'
FROM unnest(ARRAY['IDE','IBODE','IADE','SAGE_FEMME','KINE','MEDECIN','ORTHOPHONISTE','ERGOTHERAPEUTE','PSYCHOMOTRICIEN','DIETETICIEN']) AS p;

-- 6. RIB — critique LIBERAL_ONLY
INSERT INTO public.documents_requis_par_profession
  (profession, type_document, est_critique, type_exercice_requis, a_expiration, duree_validite_mois, description)
SELECT p::type_profession, 'RIB'::type_document, true, 'LIBERAL_ONLY', false, NULL,
  'Relevé d''Identité Bancaire (compte professionnel libéral)'
FROM unnest(ARRAY['IDE','IBODE','IADE','SAGE_FEMME','KINE','MEDECIN','ORTHOPHONISTE','ERGOTHERAPEUTE','PSYCHOMOTRICIEN','DIETETICIEN']) AS p;

-- 7. ATTESTATION_URSSAF — critique LIBERAL_ONLY
INSERT INTO public.documents_requis_par_profession
  (profession, type_document, est_critique, type_exercice_requis, a_expiration, duree_validite_mois, description)
SELECT p::type_profession, 'ATTESTATION_URSSAF'::type_document, true, 'LIBERAL_ONLY', true, 6,
  'Attestation d''affiliation URSSAF (exercice libéral)'
FROM unnest(ARRAY['IDE','IBODE','IADE','SAGE_FEMME','KINE','MEDECIN','ORTHOPHONISTE','ERGOTHERAPEUTE','PSYCHOMOTRICIEN','DIETETICIEN']) AS p;

COMMENT ON COLUMN public.documents_requis_par_profession.type_exercice_requis IS
'Sprint Hotfix UX Documents : SALARIE_ONLY / LIBERAL_ONLY / TOUS. Filtre côté frontend selon soignant.type_exercice (LIBERAL/MIXTE inclut LIBERAL_ONLY ; SALARIE/CDD l''exclut).';
