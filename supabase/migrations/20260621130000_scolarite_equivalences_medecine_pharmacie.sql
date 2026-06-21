-- Équivalences supplémentaires (arrêté du 3 février 2022 + CNOP). Formations encodant
-- le cycle pour lever l'ambiguïté d'année (DFGSM = 1er cycle, DFASM = 2e cycle).
-- Appliquée en prod via MCP puis enregistrée.
INSERT INTO public.equivalences_scolarite (formation, libelle_formation, annee_validee_min, profession_autorisee, base_reglementaire) VALUES
  ('MEDECINE_DFGSM', 'Medecine - 1er cycle (DFGSM)', 2, 'AS',
   'Arrete du 3 fevrier 2022 - etudiant en medecine ayant valide la 2e annee du 1er cycle (DFGSM2) : faisant fonction aide-soignant.'),
  ('MEDECINE_DFASM', 'Medecine - 2e cycle (DFASM)', 1, 'AS',
   'Arrete du 3 fevrier 2022 - etudiant en medecine ayant valide le 1er cycle : faisant fonction aide-soignant.'),
  ('MEDECINE_DFASM', 'Medecine - 2e cycle (DFASM)', 2, 'IDE',
   'Arrete du 3 fevrier 2022 - etudiant en medecine ayant valide la 2e annee du 2e cycle (DFASM2) : actes et activites d''infirmier (supervise).'),
  ('PHARMACIE', 'Pharmacie (officine)', 5, 'PHARMACIEN',
   'CNOP - etudiant en pharmacie ayant valide la 5e annee hospitalo-universitaire + stage 6 mois : pharmacien remplacant en officine (certificat CROP, max 4 mois).')
ON CONFLICT ON CONSTRAINT uq_equiv_scolarite DO NOTHING;
