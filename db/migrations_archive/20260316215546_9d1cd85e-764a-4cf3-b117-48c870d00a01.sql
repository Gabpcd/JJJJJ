-- Temporarily disable USER triggers for test data insertion
ALTER TABLE public.missions DISABLE TRIGGER USER;
ALTER TABLE public.presences DISABLE TRIGGER USER;
ALTER TABLE public.litiges DISABLE TRIGGER USER;

-- Insert 3 TERMINEE missions for Clinique Test Jolene with commission_facturee=false
INSERT INTO public.missions (intitule, description, profession_requise, service, debut_le, fin_le,
  taux_horaire_base, total_brut, net_a_payer, montant_ifm, montant_icp,
  montant_commission_ht, montant_commission_tva, montant_commission_ttc, taux_commission,
  statut, soignant_assigne_id, etablissement_id, commission_facturee, est_urgente)
VALUES
  ('IDE — Soins post-opératoires jour', 'Surveillance post-op et administration traitements', 'IDE', 'Chirurgie',
   '2026-03-01T07:00:00+01:00', '2026-03-01T19:00:00+01:00',
   24.05, 288.60, 270.13, 28.86, 28.86, 43.29, 8.66, 51.95, 15,
   'TERMINEE', '57d814fb-c09b-4528-b4e0-ed8369328bd3', '8500dba5-2c73-4035-8383-b854d59a9864', false, false),
  ('IDE — Nuit urgences week-end', 'Garde de nuit service urgences', 'IDE', 'Urgences',
   '2026-03-08T19:00:00+01:00', '2026-03-09T07:00:00+01:00',
   24.05, 481.00, 450.00, 48.10, 48.10, 72.15, 14.43, 86.58, 15,
   'TERMINEE', '57d814fb-c09b-4528-b4e0-ed8369328bd3', '8500dba5-2c73-4035-8383-b854d59a9864', false, true),
  ('IDE — Consultations matin', 'Consultations et bilans sanguins', 'IDE', 'Consultation',
   '2026-03-12T08:00:00+01:00', '2026-03-12T14:00:00+01:00',
   24.05, 144.30, 135.00, 14.43, 14.43, 21.65, 4.33, 25.98, 15,
   'TERMINEE', '57d814fb-c09b-4528-b4e0-ed8369328bd3', '8500dba5-2c73-4035-8383-b854d59a9864', false, false);

-- Create a presence for the first mission (for the dispute)
INSERT INTO public.presences (mission_id, soignant_id,
  pointage_arrivee_le, pointage_depart_le,
  arrivee_lat, arrivee_lng, depart_lat, depart_lng,
  distance_etablissement_m, perimetre_gps_valide,
  valide_par_etablissement, valide_le,
  methode_pointage_arrivee, methode_pointage_depart)
SELECT m.id, '57d814fb-c09b-4528-b4e0-ed8369328bd3',
  '2026-03-01T07:05:00+01:00', '2026-03-01T18:45:00+01:00',
  48.8566, 2.3522, 48.8566, 2.3522,
  150, true,
  true, '2026-03-02T10:00:00+01:00',
  'GPS', 'GPS'
FROM public.missions m
WHERE m.intitule = 'IDE — Soins post-opératoires jour'
  AND m.etablissement_id = '8500dba5-2c73-4035-8383-b854d59a9864'
  AND m.soignant_assigne_id = '57d814fb-c09b-4528-b4e0-ed8369328bd3'
ORDER BY m.cree_le DESC
LIMIT 1;

-- Create a dispute for that mission
INSERT INTO public.litiges (mission_id, soignant_id, etablissement_id, presence_id, initie_par, motif, statut)
SELECT m.id,
  '57d814fb-c09b-4528-b4e0-ed8369328bd3',
  '8500dba5-2c73-4035-8383-b854d59a9864',
  p.id,
  'SOIGNANT',
  'Heures non comptabilisées : j''ai travaillé de 7h00 à 19h15 mais le pointage indique 18h45. Il manque 30 minutes sur ma fiche de présence.',
  'OUVERT'
FROM public.missions m
JOIN public.presences p ON p.mission_id = m.id
WHERE m.intitule = 'IDE — Soins post-opératoires jour'
  AND m.etablissement_id = '8500dba5-2c73-4035-8383-b854d59a9864'
  AND m.soignant_assigne_id = '57d814fb-c09b-4528-b4e0-ed8369328bd3'
ORDER BY m.cree_le DESC
LIMIT 1;

-- Re-enable all user triggers
ALTER TABLE public.missions ENABLE TRIGGER USER;
ALTER TABLE public.presences ENABLE TRIGGER USER;
ALTER TABLE public.litiges ENABLE TRIGGER USER;