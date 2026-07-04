
-- Fix trigger function: column is valide_le, not validee_le
CREATE OR REPLACE FUNCTION dec_contestation_48h()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_valide_le TIMESTAMPTZ;
BEGIN
    SELECT valide_le INTO v_valide_le FROM presences WHERE id = NEW.presence_id;
    IF v_valide_le IS NOT NULL AND v_valide_le + INTERVAL '48 hours' < NOW() THEN
        RAISE EXCEPTION 'Le délai de contestation de 48h est dépassé.';
    END IF;
    RETURN NEW;
END;
$$;

-- Contrats
INSERT INTO contrats_mission (mission_id, etablissement_id, soignant_id, numero_contrat, type_contrat, statut, signature_soignant, signature_soignant_le, signature_etablissement, signature_etablissement_le)
VALUES
  ('5c00c580-a798-41df-a126-a0fde96061e3', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'CTR-2026-0001', 'CDDU', 'SIGNE_COMPLET', true, now() - interval '13 days', true, now() - interval '13 days'),
  ('467330d7-0214-4f3c-8ba0-eba345d1dae5', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'CTR-2026-0002', 'CDDU', 'SIGNE_COMPLET', true, now() - interval '12 days', true, now() - interval '12 days'),
  ('6a6a1297-242b-430f-9cb5-8a5acf5e1f2f', 'b0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000003', 'CTR-2026-0003', 'CDDU', 'SIGNE_COMPLET', true, now() - interval '11 days', true, now() - interval '11 days'),
  ('a7eb8a52-3e82-4f66-8770-3e7765f75bb7', 'b0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000006', 'CTR-2026-0004', 'CDDU', 'SIGNE_COMPLET', true, now() - interval '10 days', true, now() - interval '10 days'),
  ('1b7167b1-43ba-4dc2-85e9-2375f038e1b7', 'b0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000004', 'CTR-2026-0005', 'CDDU', 'SIGNE_COMPLET', true, now() - interval '10 days', true, now() - interval '10 days'),
  ('1199ef41-ae37-43bb-a2ed-ab5185530bea', 'b0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000009', 'CTR-2026-0006', 'CDDU', 'SIGNE_COMPLET', true, now() - interval '9 days', true, now() - interval '9 days'),
  ('3f9cd6fa-44ad-4423-b48e-c718bd87dbea', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000005', 'CTR-2026-0007', 'CDDU', 'SIGNE_COMPLET', true, now() - interval '9 days', true, now() - interval '9 days'),
  ('7e039191-cd2a-45d9-91c0-81fde7eb7010', 'b0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000010', 'CTR-2026-0008', 'CDDU', 'SIGNE_COMPLET', true, now() - interval '8 days', true, now() - interval '8 days'),
  ('0e0d4dac-3a87-4d29-8f45-c46243d21889', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000007', 'CTR-2026-0009', 'CDDU', 'SIGNE_COMPLET', true, now() - interval '8 days', true, now() - interval '8 days'),
  ('5256c3aa-27f4-4c33-a03e-ce3b8d6e44e1', 'b0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001', 'CTR-2026-0010', 'CDDU', 'SIGNE_COMPLET', true, now() - interval '7 days', true, now() - interval '7 days');

-- Presences
INSERT INTO presences (mission_id, soignant_id, pointage_arrivee_le, pointage_depart_le, valide_par_etablissement, valide_le, methode_pointage_arrivee, methode_pointage_depart)
VALUES
  ('5c00c580-a798-41df-a126-a0fde96061e3', 'c0000000-0000-0000-0000-000000000001', '2026-03-03 06:02:00+00', '2026-03-03 17:58:00+00', true, now() - interval '12 days', 'GPS', 'GPS'),
  ('467330d7-0214-4f3c-8ba0-eba345d1dae5', 'c0000000-0000-0000-0000-000000000002', '2026-03-04 18:05:00+00', '2026-03-05 06:01:00+00', true, now() - interval '11 days', 'GPS', 'GPS'),
  ('6a6a1297-242b-430f-9cb5-8a5acf5e1f2f', 'c0000000-0000-0000-0000-000000000003', '2026-03-05 06:10:00+00', '2026-03-05 14:02:00+00', true, now() - interval '11 days', 'GPS', 'GPS');

-- Factures
INSERT INTO factures (etablissement_id, numero_facture, montant_ht, montant_tva, montant_ttc, statut, date_emission, date_echeance, nombre_missions, periode_debut, periode_fin, mode_paiement)
VALUES
  ('b0000000-0000-0000-0000-000000000001', 'FACT-2026-0001', 190.31, 38.06, 228.37, 'PAYEE', now() - interval '10 days', (now() - interval '10 days' + interval '30 days')::date, 3, '2026-03-01', '2026-03-09', 'STRIPE'),
  ('b0000000-0000-0000-0000-000000000002', 'FACT-2026-0002', 79.00, 15.80, 94.80, 'EMISE', now() - interval '45 days', (now() - interval '45 days' + interval '30 days')::date, 3, '2026-01-15', '2026-01-31', 'VIREMENT'),
  ('b0000000-0000-0000-0000-000000000003', 'FACT-2026-0003', 104.76, 20.95, 125.71, 'EMISE', now() - interval '40 days', (now() - interval '40 days' + interval '30 days')::date, 2, '2026-02-01', '2026-02-15', 'VIREMENT');

-- Litige : désactiver/réactiver le trigger 48h
ALTER TABLE litiges DISABLE TRIGGER dec_litige_48h;

INSERT INTO litiges (mission_id, soignant_id, etablissement_id, presence_id, initie_par, motif, statut)
SELECT
  '5c00c580-a798-41df-a126-a0fde96061e3',
  'c0000000-0000-0000-0000-000000000001',
  'b0000000-0000-0000-0000-000000000001',
  p.id,
  'SOIGNANT',
  'Heures de nuit non comptabilisées — arrivée à 6h02 mais système a enregistré 6h30',
  'OUVERT'
FROM presences p
WHERE p.mission_id = '5c00c580-a798-41df-a126-a0fde96061e3'
LIMIT 1;

ALTER TABLE litiges ENABLE TRIGGER dec_litige_48h;
