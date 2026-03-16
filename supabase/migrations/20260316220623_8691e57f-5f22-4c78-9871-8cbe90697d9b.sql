
-- Insert open test missions for Clinique Test Jolene (Paris) visible in public search
INSERT INTO public.missions (intitule, description, profession_requise, service, debut_le, fin_le,
  taux_horaire_base, est_urgente, niveau_urgence, statut, etablissement_id, mode_attribution)
VALUES
  ('IDE — Soins généraux jour', 'Surveillance patients et administration des soins', 'IDE', 'Médecine',
   (now() + interval '3 days')::timestamptz, (now() + interval '3 days' + interval '12 hours')::timestamptz,
   24.05, false, 0, 'OUVERTE', '8500dba5-2c73-4035-8383-b854d59a9864', 'PREMIER_ARRIVE'),
  ('IDE — Garde de nuit urgences', 'Garde de nuit aux urgences', 'IDE', 'Urgences',
   (now() + interval '5 days')::timestamptz, (now() + interval '5 days' + interval '12 hours')::timestamptz,
   28.00, true, 2, 'OUVERTE', '8500dba5-2c73-4035-8383-b854d59a9864', 'PREMIER_ARRIVE'),
  ('AS — Aide aux soins matin', 'Toilettes et aide aux repas', 'AS', 'Gériatrie',
   (now() + interval '4 days')::timestamptz, (now() + interval '4 days' + interval '8 hours')::timestamptz,
   16.50, false, 0, 'OUVERTE', '8500dba5-2c73-4035-8383-b854d59a9864', 'CANDIDATURE'),
  ('IDE — Perfusions et bilans', 'Poses de perfusions et prélèvements sanguins', 'IDE', 'Consultation',
   (now() + interval '7 days')::timestamptz, (now() + interval '7 days' + interval '6 hours')::timestamptz,
   25.00, false, 0, 'OUVERTE', '8500dba5-2c73-4035-8383-b854d59a9864', 'PREMIER_ARRIVE');
