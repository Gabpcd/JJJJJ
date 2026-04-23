-- Phase C Session 2 : correction nomenclature ANS officielle (TRE-R38)
-- Session 1 avait peuplé 42 codes indicatifs (mélange SM/SC imaginaires).
-- Cette migration remplace par les 55 SM + 5 SI officiels (cross-validés
-- avec CPS3 DICO-FR.GIP table R01).

-- Vider la table (aucun FK en prod, safe)
TRUNCATE public.specialites_medicales CASCADE;

-- Repeupler avec la nomenclature ANS officielle
INSERT INTO public.specialites_medicales (code, label, profession_parent) VALUES
  ('SM01', 'Anatomie et cytologie pathologiques', 'MEDECIN'),
  ('SM02', 'Anesthésie-réanimation', 'MEDECIN'),
  ('SM03', 'Biologie médicale', 'MEDECIN'),
  ('SM04', 'Cardiologie et maladies vasculaires', 'MEDECIN'),
  ('SM05', 'Chirurgie générale', 'MEDECIN'),
  ('SM06', 'Chirurgie maxillo-faciale', 'MEDECIN'),
  ('SM07', 'Chirurgie maxillo-faciale et stomatologie', 'MEDECIN'),
  ('SM08', 'Chirurgie orthopédique et traumatologie', 'MEDECIN'),
  ('SM09', 'Chirurgie infantile', 'MEDECIN'),
  ('SM10', 'Chirurgie plastique reconstructrice et esthétique', 'MEDECIN'),
  ('SM11', 'Chirurgie thoracique et cardio-vasculaire', 'MEDECIN'),
  ('SM12', 'Chirurgie urologique', 'MEDECIN'),
  ('SM13', 'Chirurgie vasculaire', 'MEDECIN'),
  ('SM14', 'Chirurgie viscérale et digestive', 'MEDECIN'),
  ('SM15', 'Dermatologie et vénéréologie', 'MEDECIN'),
  ('SM16', 'Endocrinologie et métabolisme', 'MEDECIN'),
  ('SM17', 'Génétique médicale', 'MEDECIN'),
  ('SM18', 'Gériatrie', 'MEDECIN'),
  ('SM19', 'Gynécologie médicale', 'MEDECIN'),
  ('SM20', 'Gynécologie-obstétrique', 'MEDECIN'),
  ('SM21', 'Hématologie', 'MEDECIN'),
  ('SM22', 'Hématologie option Maladie du sang', 'MEDECIN'),
  ('SM23', 'Hématologie option Onco-hématologie', 'MEDECIN'),
  ('SM24', 'Gastro-entérologie et hépatologie', 'MEDECIN'),
  ('SM25', 'Médecine du travail', 'MEDECIN'),
  ('SM26', 'Qualifié en Médecine Générale', 'MEDECIN'),
  ('SM27', 'Médecine interne', 'MEDECIN'),
  ('SM28', 'Médecine nucléaire', 'MEDECIN'),
  ('SM29', 'Médecine physique et réadaptation', 'MEDECIN'),
  ('SM30', 'Néphrologie', 'MEDECIN'),
  ('SM31', 'Neuro-chirurgie', 'MEDECIN'),
  ('SM32', 'Neurologie', 'MEDECIN'),
  ('SM33', 'Neuro-psychiatrie', 'MEDECIN'),
  ('SM34', 'O.R.L et chirurgie cervico-faciale', 'MEDECIN'),
  ('SM35', 'Oncologie option onco-hématologie', 'MEDECIN'),
  ('SM36', 'Oncologie option médicale', 'MEDECIN'),
  ('SM37', 'Oncologie option radiothérapie', 'MEDECIN'),
  ('SM38', 'Ophtalmologie', 'MEDECIN'),
  ('SM39', 'Oto-rhino-laryngologie', 'MEDECIN'),
  ('SM40', 'Pédiatrie', 'MEDECIN'),
  ('SM41', 'Pneumologie', 'MEDECIN'),
  ('SM42', 'Psychiatrie', 'MEDECIN'),
  ('SM43', 'Psychiatrie option enfant et adolescent', 'MEDECIN'),
  ('SM44', 'Radiodiagnostic', 'MEDECIN'),
  ('SM45', 'Radiothérapie', 'MEDECIN'),
  ('SM46', 'Réanimation médicale', 'MEDECIN'),
  ('SM47', 'Recherche médicale', 'MEDECIN'),
  ('SM48', 'Rhumatologie', 'MEDECIN'),
  ('SM49', 'Santé publique et médecine sociale', 'MEDECIN'),
  ('SM50', 'Stomatologie', 'MEDECIN'),
  ('SM51', 'Gynéco-obstétrique et Gynéco médicale option Gynéco-obstétrique', 'MEDECIN'),
  ('SM52', 'Gynéco-obstétrique et Gynéco médicale option Gynéco-médicale', 'MEDECIN'),
  ('SM53', 'Spécialiste en Médecine Générale', 'MEDECIN'),
  ('SM54', 'Médecine Générale', 'MEDECIN'),
  ('SM55', 'Radiodiagnostic et radiothérapie', 'MEDECIN'),
  ('SI01', 'IPA pathologies chroniques stabilisées', 'IDE'),
  ('SI02', 'IPA oncologie et hémato-oncologie', 'IDE'),
  ('SI03', 'IPA maladie rénale chronique, dialyse, transplantation rénale', 'IDE'),
  ('SI04', 'IPA psychiatrie et santé mentale', 'IDE'),
  ('SI05', 'IPA urgences', 'IDE')
ON CONFLICT (code) DO UPDATE SET
  label = EXCLUDED.label,
  profession_parent = EXCLUDED.profession_parent;

NOTIFY pgrst, 'reload schema';
