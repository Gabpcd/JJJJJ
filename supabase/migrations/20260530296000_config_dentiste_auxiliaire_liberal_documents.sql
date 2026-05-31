-- 1) Chirurgien-dentiste : profession médicale réglementée pouvant exercer en
--    libéral (art. L4141-1 CSP, Ordre national des chirurgiens-dentistes).
CREATE OR REPLACE FUNCTION public.fn_profession_peut_etre_liberal(p_profession text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN p_profession IN (
        'IDE', 'IADE', 'IBODE', 'SAGE_FEMME', 'KINE', 'MEDECIN',
        'PHARMACIEN', 'ORTHOPHONISTE', 'DIETETICIEN',
        'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'MANIPULATEUR_RADIO',
        'DENTISTE'
    );
    -- SALARIÉES UNIQUEMENT : AS, AES, AUXILIAIRE_PUERICULTURE (DEAP, sous
    -- supervision, pas d'autonomie d'exercice), PREPARATEUR_PHARMA.
END;
$function$;

-- 2) Documents requis — DENTISTE (calqué sur MEDECIN : profession à ordre + RPPS)
INSERT INTO public.documents_requis_par_profession
  (profession, type_document, est_critique, a_expiration, duree_validite_mois, type_exercice_requis, description)
VALUES
  ('DENTISTE'::type_profession, 'CARTE_IDENTITE'::type_document, true,  true,  NULL, 'TOUS',         'Carte d''identité ou passeport en cours de validité'),
  ('DENTISTE'::type_profession, 'DIPLOME'::type_document,        true,  false, NULL, 'TOUS',         'Diplôme d''État de docteur en chirurgie dentaire'),
  ('DENTISTE'::type_profession, 'RPPS_ADELI'::type_document,     true,  false, NULL, 'TOUS',         'Attestation d''inscription RPPS / Ordre des chirurgiens-dentistes'),
  ('DENTISTE'::type_profession, 'RCP_ASSURANCE'::type_document,  true,  true,  12,   'LIBERAL_ONLY', 'Assurance Responsabilité Civile Professionnelle (exercice libéral)'),
  ('DENTISTE'::type_profession, 'RIB'::type_document,            true,  false, NULL, 'LIBERAL_ONLY', 'Relevé d''Identité Bancaire (compte professionnel libéral)'),
  ('DENTISTE'::type_profession, 'ATTESTATION_URSSAF'::type_document, true, true, 6,   'LIBERAL_ONLY', 'Attestation d''affiliation URSSAF (exercice libéral)')
ON CONFLICT DO NOTHING;

-- 3) Documents requis — AUXILIAIRE_PUERICULTURE (calqué sur AS : salarié, pas de RPPS)
INSERT INTO public.documents_requis_par_profession
  (profession, type_document, est_critique, a_expiration, duree_validite_mois, type_exercice_requis, description)
VALUES
  ('AUXILIAIRE_PUERICULTURE'::type_profession, 'CARTE_IDENTITE'::type_document, true, true,  NULL, 'TOUS', 'Carte d''identité ou passeport en cours de validité'),
  ('AUXILIAIRE_PUERICULTURE'::type_profession, 'DIPLOME'::type_document,        true, false, NULL, 'TOUS', 'Diplôme d''État d''auxiliaire de puériculture (DEAP)')
ON CONFLICT DO NOTHING;
