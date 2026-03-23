
-- Insert missing contracts for the 3 terminated missions
INSERT INTO contrats_mission (mission_id, soignant_id, etablissement_id, type_contrat, numero_contrat, statut, signature_soignant, signature_soignant_le, signature_etablissement, signature_etablissement_le)
VALUES
  ('61e7425d-17eb-4574-beea-1430cdef95e1', '57d814fb-c09b-4528-b4e0-ed8369328bd3', '8500dba5-2c73-4035-8383-b854d59a9864', 'CDDU', 'CTR-2026-0301-001', 'SIGNE_COMPLET', true, '2026-02-28 18:00:00+00', true, '2026-02-28 17:00:00+00'),
  ('457b65da-4f00-4888-b9cd-e163e1231b24', '57d814fb-c09b-4528-b4e0-ed8369328bd3', '8500dba5-2c73-4035-8383-b854d59a9864', 'CDDU', 'CTR-2026-0308-002', 'SIGNE_COMPLET', true, '2026-03-07 18:00:00+00', true, '2026-03-07 17:00:00+00'),
  ('7fd6da9f-6bfe-470c-91f2-de77519983a3', '57d814fb-c09b-4528-b4e0-ed8369328bd3', '8500dba5-2c73-4035-8383-b854d59a9864', 'CDDU', 'CTR-2026-0312-003', 'SIGNE_COMPLET', true, '2026-03-11 18:00:00+00', true, '2026-03-11 17:00:00+00');

-- Insert missing presences for the 2 missions that don't have them
INSERT INTO presences (mission_id, soignant_id, pointage_arrivee_le, pointage_depart_le, arrivee_lat, arrivee_lng, arrivee_precision_gps_m, depart_lat, depart_lng, depart_precision_gps_m, distance_etablissement_m, perimetre_gps_valide, alerte_teleportation, valide_par_etablissement, valide_le)
VALUES
  ('457b65da-4f00-4888-b9cd-e163e1231b24', '57d814fb-c09b-4528-b4e0-ed8369328bd3', '2026-03-08 18:05:00+00', '2026-03-09 06:10:00+00', 48.8566, 2.3522, 12, 48.8566, 2.3522, 10, 85, true, false, true, '2026-03-09 10:00:00+00'),
  ('7fd6da9f-6bfe-470c-91f2-de77519983a3', '57d814fb-c09b-4528-b4e0-ed8369328bd3', '2026-03-12 07:03:00+00', '2026-03-12 13:05:00+00', 48.8566, 2.3522, 8, 48.8566, 2.3522, 9, 72, true, false, true, '2026-03-12 15:00:00+00');
