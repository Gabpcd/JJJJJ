
-- Désactiver uniquement les triggers utilisateur
ALTER TABLE missions DISABLE TRIGGER USER;

-- 1. GROUPE DE SANTÉ
INSERT INTO groupes_sante (id, nom, siren, raison_sociale_facturation, remise_groupe_pourcent, formule_abonnement)
VALUES ('a0000000-0000-0000-0000-000000000001', 'Groupe Santé Île-de-France', '987654321', 'GSIF SAS', 5.00, 'ENTERPRISE')
ON CONFLICT DO NOTHING;

-- 2. ÉTABLISSEMENTS
INSERT INTO etablissements (id, nom, siret, finess, type, groupe_sante_id,
    adresse_rue, adresse_ville, adresse_code_postal, adresse_departement,
    adresse_lat, adresse_lng, email_contact, telephone_contact,
    formule_abonnement, rist_plafond_actif,
    taux_majoration_nuit_pourcent, taux_majoration_dimanche_pourcent, taux_majoration_ferie_pourcent)
VALUES 
    ('b0000000-0000-0000-0000-000000000001', 'Clinique Rivoli', '11111111111111', '750000001', 'CLINIQUE_PRIVEE',
     'a0000000-0000-0000-0000-000000000001', '18 rue de Rivoli', 'Paris', '75001', '75',
     48.8566, 2.3522, 'rh@clinique-rivoli.fr', '01 42 60 00 01', 'PRO', FALSE, 25.00, 50.00, 100.00),
    ('b0000000-0000-0000-0000-000000000002', 'EHPAD Les Glycines', '22222222222222', '920000001', 'EHPAD',
     'a0000000-0000-0000-0000-000000000001', '45 avenue Jean-Baptiste Clément', 'Boulogne-Billancourt', '92100', '92',
     48.8397, 2.2399, 'direction@ehpad-glycines.fr', '01 46 03 00 02', 'STARTER', TRUE, 30.00, 50.00, 100.00),
    ('b0000000-0000-0000-0000-000000000003', 'Hôpital Saint-Antoine', '33333333333333', '750000003', 'HOPITAL_PUBLIC',
     NULL, '184 rue du Faubourg Saint-Antoine', 'Paris', '75012', '75',
     48.8489, 2.3833, 'drh@saint-antoine.aphp.fr', '01 49 28 20 00', 'GRATUIT', TRUE, 25.00, 50.00, 100.00),
    ('b0000000-0000-0000-0000-000000000004', 'HAD Île-de-France', '44444444444444', '940000001', 'HAD',
     'a0000000-0000-0000-0000-000000000001', '12 rue de Fontenay', 'Vincennes', '94300', '94',
     48.8474, 2.4392, 'coordination@had-idf.fr', '01 43 28 00 04', 'PRO', TRUE, 25.00, 50.00, 100.00)
ON CONFLICT (siret) DO NOTHING;

-- 3. SOIGNANTS
INSERT INTO soignants (id, prenom, nom, email, telephone, date_naissance,
    profession, numero_rpps, type_contrat,
    score_fiabilite, total_missions_terminees, total_missions_annulees, total_retards_pointage, total_absences,
    heures_cumulees, prevoyance_inscrit,
    adresse_lat, adresse_lng, rayon_deplacement_km,
    tous_documents_valides, identite_verifiee, diplome_verifie, rpps_verifie, statut_verification_aria)
VALUES 
    ('c0000000-0000-0000-0000-000000000001', 'Marie', 'Lefèvre', 'marie.lefevre@demo.fr', '06 12 34 56 01', '1989-03-15', 'IDE', '10000000001', 'CDDU', 92.00, 28, 0, 1, 0, 1847.50, TRUE, 48.8530, 2.3490, 30, TRUE, TRUE, TRUE, TRUE, 'VERIFIE'),
    ('c0000000-0000-0000-0000-000000000002', 'Thomas', 'Dubois', 'thomas.dubois@demo.fr', '06 12 34 56 02', '1992-07-22', 'IDE', '10000000002', 'CDDU', 68.00, 15, 2, 3, 0, 720.00, FALSE, 48.8450, 2.3200, 25, TRUE, TRUE, TRUE, TRUE, 'VERIFIE'),
    ('c0000000-0000-0000-0000-000000000003', 'Fatima', 'Benali', 'fatima.benali@demo.fr', '06 12 34 56 03', '1985-11-08', 'AS', NULL, 'CDDU', 95.00, 35, 0, 0, 0, 2450.00, TRUE, 48.8320, 2.2500, 20, TRUE, TRUE, TRUE, FALSE, 'VERIFIE'),
    ('c0000000-0000-0000-0000-000000000004', 'Lucas', 'Martin', 'lucas.martin@demo.fr', '06 12 34 56 04', '1990-01-30', 'IBODE', '10000000004', 'CDDU', 85.00, 22, 1, 0, 0, 1320.00, TRUE, 48.8600, 2.3700, 35, TRUE, TRUE, TRUE, TRUE, 'VERIFIE'),
    ('c0000000-0000-0000-0000-000000000005', 'Sophie', 'Roux', 'sophie.roux@demo.fr', '06 12 34 56 05', '1987-06-14', 'IADE', '10000000005', 'LIBERAL', 88.00, 18, 0, 2, 0, 980.00, FALSE, 48.8700, 2.3300, 40, TRUE, TRUE, TRUE, TRUE, 'VERIFIE')
ON CONFLICT (email) DO NOTHING;

INSERT INTO soignants (id, prenom, nom, email, telephone, date_naissance,
    profession, type_contrat, score_fiabilite, total_missions_terminees, heures_cumulees,
    adresse_lat, adresse_lng, rayon_deplacement_km, tous_documents_valides, statut_verification_aria)
VALUES 
    ('c0000000-0000-0000-0000-000000000006', 'Amadou', 'Diallo', 'amadou.diallo@demo.fr', '06 12 34 56 06', '1995-09-03', 'AS', 'CDDU', 52.00, 3, 36.00, 48.8250, 2.3600, 15, TRUE, 'VERIFIE'),
    ('c0000000-0000-0000-0000-000000000010', 'Pierre', 'Durand', 'pierre.durand@demo.fr', '06 12 34 56 10', '1994-02-11', 'AES', 'CDDU', 70.00, 8, 192.00, 48.8350, 2.2600, 15, TRUE, 'VERIFIE')
ON CONFLICT (email) DO NOTHING;

INSERT INTO soignants (id, prenom, nom, email, telephone, date_naissance,
    profession, numero_rpps, type_contrat,
    score_fiabilite, total_missions_terminees, heures_cumulees, prevoyance_inscrit,
    adresse_lat, adresse_lng, rayon_deplacement_km,
    tous_documents_valides, identite_verifiee, diplome_verifie, rpps_verifie, statut_verification_aria)
VALUES 
    ('c0000000-0000-0000-0000-000000000007', 'Camille', 'Petit', 'camille.petit@demo.fr', '06 12 34 56 07', '1991-12-25', 'SAGE_FEMME', '10000000007', 'CDDU', 78.00, 12, 540.00, TRUE, 48.8400, 2.4000, 25, TRUE, TRUE, TRUE, TRUE, 'VERIFIE'),
    ('c0000000-0000-0000-0000-000000000008', 'Julien', 'Moreau', 'julien.moreau@demo.fr', '06 12 34 56 08', '1988-04-17', 'KINE', '10000000008', 'LIBERAL', 75.00, 10, 420.00, FALSE, 48.8550, 2.2800, 30, TRUE, TRUE, TRUE, TRUE, 'VERIFIE')
ON CONFLICT (email) DO NOTHING;

INSERT INTO soignants (id, prenom, nom, email, telephone, date_naissance,
    profession, numero_rpps, type_contrat,
    score_fiabilite, total_missions_terminees, total_missions_annulees, total_retards_pointage, total_absences,
    heures_cumulees, eligible_conversion_3200h, prevoyance_inscrit,
    adresse_lat, adresse_lng, rayon_deplacement_km,
    tous_documents_valides, identite_verifiee, diplome_verifie, rpps_verifie, statut_verification_aria)
VALUES (
    'c0000000-0000-0000-0000-000000000009', 'Nadia', 'Hammadi', 'nadia.hammadi@demo.fr', '06 12 34 56 09', '1993-08-20',
    'IDE', '10000000009', 'CDDU', 82.00, 20, 1, 2, 0, 2980.00, FALSE, TRUE, 48.8480, 2.3600, 20, TRUE, TRUE, TRUE, TRUE, 'VERIFIE'
) ON CONFLICT (email) DO NOTHING;

-- 4. MISSIONS TERMINÉES (sans duree_heures car c'est une colonne générée)
INSERT INTO missions (etablissement_id, intitule, profession_requise, service,
    debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence, statut, soignant_assigne_id,
    net_a_payer, total_brut, taux_commission, montant_commission_ht, montant_commission_tva, montant_commission_ttc)
VALUES 
    ('b0000000-0000-0000-0000-000000000001', 'IDE Bloc opératoire — Chirurgie cardiaque', 'IDE', 'Bloc opératoire',
     '2026-03-03 06:00:00+00', '2026-03-03 18:00:00+00', 28.00, FALSE, 0, 'TERMINEE', 'c0000000-0000-0000-0000-000000000001',
     443.52, 336.00, 15.00, 66.53, 13.31, 79.83),
    ('b0000000-0000-0000-0000-000000000001', 'IDE de nuit — Soins intensifs', 'IDE', 'Réanimation',
     '2026-03-04 18:00:00+00', '2026-03-05 06:00:00+00', 30.00, FALSE, 0, 'TERMINEE', 'c0000000-0000-0000-0000-000000000002',
     475.20, 360.00, 15.00, 71.28, 14.26, 85.54),
    ('b0000000-0000-0000-0000-000000000002', 'Aide-soignante — Toilette et soins de confort', 'AS', 'Gériatrie',
     '2026-03-05 06:00:00+00', '2026-03-05 14:00:00+00', 16.00, FALSE, 0, 'TERMINEE', 'c0000000-0000-0000-0000-000000000003',
     168.96, 128.00, 15.00, 25.34, 5.07, 30.41),
    ('b0000000-0000-0000-0000-000000000002', 'AS de nuit — Surveillance résidents', 'AS', 'Gériatrie',
     '2026-03-05 19:00:00+00', '2026-03-06 05:00:00+00', 15.50, FALSE, 0, 'TERMINEE', 'c0000000-0000-0000-0000-000000000006',
     204.60, 155.00, 15.00, 30.69, 6.14, 36.83),
    ('b0000000-0000-0000-0000-000000000003', 'IBODE — Bloc orthopédie', 'IBODE', 'Bloc opératoire',
     '2026-03-06 07:00:00+00', '2026-03-06 17:00:00+00', 24.05, FALSE, 0, 'TERMINEE', 'c0000000-0000-0000-0000-000000000004',
     317.46, 240.50, 15.00, 47.62, 9.52, 57.14),
    ('b0000000-0000-0000-0000-000000000004', 'IDE — Soins techniques à domicile', 'IDE', 'HAD Médecine',
     '2026-03-07 07:00:00+00', '2026-03-07 15:00:00+00', 26.00, FALSE, 0, 'TERMINEE', 'c0000000-0000-0000-0000-000000000009',
     274.56, 208.00, 15.00, 41.18, 8.24, 49.42),
    ('b0000000-0000-0000-0000-000000000001', 'IADE — Anesthésie chirurgie digestive', 'IADE', 'Anesthésie',
     '2026-03-07 06:30:00+00', '2026-03-07 16:30:00+00', 35.00, FALSE, 0, 'TERMINEE', 'c0000000-0000-0000-0000-000000000005',
     350.00, 350.00, 15.00, 52.50, 10.50, 63.00),
    ('b0000000-0000-0000-0000-000000000002', 'AES — Animation et accompagnement', 'AES', 'Animation',
     '2026-03-08 08:00:00+00', '2026-03-08 16:00:00+00', 14.50, FALSE, 0, 'TERMINEE', 'c0000000-0000-0000-0000-000000000010',
     153.12, 116.00, 15.00, 22.97, 4.59, 27.56),
    ('b0000000-0000-0000-0000-000000000001', 'Sage-femme — Garde maternité dimanche', 'SAGE_FEMME', 'Maternité',
     '2026-03-08 06:00:00+00', '2026-03-08 18:00:00+00', 32.00, FALSE, 0, 'TERMINEE', 'c0000000-0000-0000-0000-000000000007',
     506.88, 384.00, 15.00, 76.03, 15.21, 91.24),
    ('b0000000-0000-0000-0000-000000000003', 'IDE — Urgences nuit du dimanche', 'IDE', 'Urgences',
     '2026-03-08 18:00:00+00', '2026-03-09 06:00:00+00', 24.05, TRUE, 2, 'TERMINEE', 'c0000000-0000-0000-0000-000000000001',
     380.95, 288.60, 15.00, 57.14, 11.43, 68.57);

-- MISSIONS ASSIGNÉES
INSERT INTO missions (etablissement_id, intitule, profession_requise, service,
    debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence, statut, soignant_assigne_id)
VALUES 
    ('b0000000-0000-0000-0000-000000000001', 'IDE — Chirurgie ambulatoire', 'IDE', 'Chirurgie',
     NOW() + INTERVAL '1 day' + TIME '07:00', NOW() + INTERVAL '1 day' + TIME '19:00', 28.00, FALSE, 0, 'ASSIGNEE', 'c0000000-0000-0000-0000-000000000001'),
    ('b0000000-0000-0000-0000-000000000002', 'AS — Soins de nursing matin', 'AS', 'Gériatrie',
     NOW() + INTERVAL '1 day' + TIME '06:30', NOW() + INTERVAL '1 day' + TIME '14:30', 16.00, FALSE, 0, 'ASSIGNEE', 'c0000000-0000-0000-0000-000000000003');

-- MISSIONS OUVERTES
INSERT INTO missions (etablissement_id, intitule, description, profession_requise, service,
    debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence, statut)
VALUES 
    ('b0000000-0000-0000-0000-000000000001', 'IDE urgence — Remplacement arrêt maladie', 'Remplacement au pied levé.', 'IDE', 'Réanimation',
     NOW() + INTERVAL '2 days' + TIME '07:00', NOW() + INTERVAL '2 days' + TIME '19:00', 30.00, TRUE, 3, 'OUVERTE'),
    ('b0000000-0000-0000-0000-000000000002', 'AS — Remplacement congé maternité', NULL, 'AS', 'Gériatrie',
     NOW() + INTERVAL '3 days' + TIME '07:00', NOW() + INTERVAL '3 days' + TIME '15:00', 15.50, FALSE, 0, 'OUVERTE'),
    ('b0000000-0000-0000-0000-000000000003', 'IBODE — Bloc digestif', NULL, 'IBODE', 'Bloc opératoire',
     NOW() + INTERVAL '4 days' + TIME '08:00', NOW() + INTERVAL '4 days' + TIME '18:00', 24.05, FALSE, 0, 'OUVERTE'),
    ('b0000000-0000-0000-0000-000000000004', 'IDE — Visite de nuit HAD', NULL, 'IDE', 'HAD Médecine',
     NOW() + INTERVAL '2 days' + TIME '20:00', NOW() + INTERVAL '3 days' + TIME '06:00', 27.00, TRUE, 1, 'OUVERTE'),
    ('b0000000-0000-0000-0000-000000000001', 'Kinésithérapeute — Rééducation post-op', NULL, 'KINE', 'Rééducation',
     NOW() + INTERVAL '5 days' + TIME '09:00', NOW() + INTERVAL '5 days' + TIME '17:00', 22.00, FALSE, 0, 'OUVERTE'),
    ('b0000000-0000-0000-0000-000000000001', 'Sage-femme — Suite de couches', NULL, 'SAGE_FEMME', 'Maternité',
     NOW() + INTERVAL '3 days' + TIME '08:00', NOW() + INTERVAL '3 days' + TIME '20:00', 31.00, FALSE, 0, 'OUVERTE');

-- SÉRIE RÉCURRENTE
INSERT INTO missions (etablissement_id, intitule, description, profession_requise, service,
    debut_le, fin_le, taux_horaire_base, statut)
SELECT
    'b0000000-0000-0000-0000-000000000002',
    'IDE — Remplacement vacances 2 semaines',
    '[SERIE_ID:SERIE_DEMO_001] Remplacement congés annuels poste IDE gériatrie.',
    'IDE', 'Gériatrie',
    (DATE '2026-03-16' + (n * INTERVAL '1 day') + TIME '07:00'),
    (DATE '2026-03-16' + (n * INTERVAL '1 day') + TIME '19:00'),
    22.00, 'OUVERTE'
FROM generate_series(0, 9) AS n
WHERE EXTRACT(DOW FROM DATE '2026-03-16' + (n * INTERVAL '1 day')) BETWEEN 1 AND 5;

-- 7. SUIVI CONVERSION 3200H
INSERT INTO suivi_conversion_3200h (soignant_id, profession_cible_liberal,
    heures_a_inscription, heures_actuelles, jalon_800h_atteint, jalon_1600h_atteint, jalon_2400h_atteint)
VALUES ('c0000000-0000-0000-0000-000000000009', 'IDE libérale', 450.00, 2980.00, TRUE, TRUE, TRUE)
ON CONFLICT (soignant_id) DO NOTHING;

INSERT INTO suivi_conversion_3200h (soignant_id, profession_cible_liberal,
    heures_a_inscription, heures_actuelles, jalon_800h_atteint, jalon_1600h_atteint)
VALUES ('c0000000-0000-0000-0000-000000000001', 'IDE libérale', 120.00, 1847.50, TRUE, TRUE)
ON CONFLICT (soignant_id) DO NOTHING;

-- Réactiver les triggers
ALTER TABLE missions ENABLE TRIGGER USER;
