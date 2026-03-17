
-- Insert mission on a free day (March 26) for pointage test
INSERT INTO missions (
  id, intitule, profession_requise, etablissement_id,
  debut_le, fin_le, taux_horaire_base, statut,
  code_arrivee, code_depart, service, description
) VALUES (
  'f0000000-aaaa-bbbb-cccc-000000000001',
  'IDE — Mission test pointage',
  'IDE',
  'b0000000-0000-0000-0000-000000000001',
  '2026-03-26 08:00:00+00',
  '2026-03-26 14:00:00+00',
  25.00,
  'OUVERTE',
  '1234',
  '5678',
  'Urgences',
  'Mission fictive pour tester le pointage arrivée/départ.'
) ON CONFLICT (id) DO NOTHING;

UPDATE missions
SET soignant_assigne_id = '57d814fb-c09b-4528-b4e0-ed8369328bd3',
    statut = 'ASSIGNEE'
WHERE id = 'f0000000-aaaa-bbbb-cccc-000000000001';
