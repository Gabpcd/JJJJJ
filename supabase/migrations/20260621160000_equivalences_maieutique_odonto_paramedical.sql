-- Équivalences manquantes (arrêté du 3 février 2022 + arrêté du 5 juillet 2022) :
-- maïeutique, odontologie, kiné, ergo, psychomot, manip radio → faisant fonction AS.
-- Appliquée prod via MCP puis enregistrée.
INSERT INTO public.equivalences_scolarite (formation, libelle_formation, annee_validee_min, profession_autorisee, base_reglementaire) VALUES
  ('MAIEUTIQUE', 'Maieutique (sage-femme)', 2, 'AS',
   'Arrete du 3 fevrier 2022 - etudiant en maieutique ayant valide la 2e annee du 1er cycle : faisant fonction aide-soignant.'),
  ('ODONTOLOGIE', 'Odontologie (chirurgien-dentiste)', 3, 'AS',
   'Arrete du 3 fevrier 2022 - etudiant en odontologie ayant valide la 3e annee du 1er cycle : faisant fonction aide-soignant.'),
  ('KINE', 'Masso-kinesitherapie (IFMK)', 1, 'AS',
   'Arrete du 5 juillet 2022 - etudiant masseur-kinesitherapeute admis en 2e annee (52 ECTS) : faisant fonction aide-soignant.'),
  ('ERGOTHERAPIE', 'Ergotherapie', 1, 'AS',
   'Arrete du 5 juillet 2022 - etudiant ergotherapeute (1re annee validee) : faisant fonction aide-soignant.'),
  ('PSYCHOMOTRICITE', 'Psychomotricite', 1, 'AS',
   'Arrete du 5 juillet 2022 - etudiant psychomotricien (1re annee validee) : faisant fonction aide-soignant.'),
  ('MANIP_RADIO', 'Manipulateur radio (MERM)', 1, 'AS',
   'Arrete du 5 juillet 2022 - etudiant manipulateur en electroradiologie medicale (1re annee validee) : faisant fonction aide-soignant.')
ON CONFLICT ON CONSTRAINT uq_equiv_scolarite DO NOTHING;
