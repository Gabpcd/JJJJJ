-- Phase C Session 1 : Spécialités médecin + infrastructure matching libéral
-- Préparation pour refacto verify-rpps (Session 2) + formulaire mission étab
-- avec filtre par spécialité.

-- 1. Table référence spécialités médicales (nomenclature ANS)
CREATE TABLE IF NOT EXISTS public.specialites_medicales (
  code TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  profession_parent TEXT NOT NULL,
  actif BOOLEAN DEFAULT true,
  cree_le TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.specialites_medicales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Lecture publique specialites_medicales" ON public.specialites_medicales;
CREATE POLICY "Lecture publique specialites_medicales"
  ON public.specialites_medicales
  FOR SELECT TO authenticated
  USING (true);

GRANT SELECT ON public.specialites_medicales TO authenticated;

-- 2. Colonnes sur soignants
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS specialite_medicale TEXT NULL REFERENCES public.specialites_medicales(code),
  ADD COLUMN IF NOT EXISTS specialite_code TEXT NULL,
  ADD COLUMN IF NOT EXISTS specialite_source TEXT DEFAULT 'RPPS',
  ADD COLUMN IF NOT EXISTS specialite_verifiee BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS specialite_verifiee_le TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS accepte_missions_generalistes BOOLEAN DEFAULT true;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'soignants_specialite_source_check'
  ) THEN
    ALTER TABLE public.soignants
      ADD CONSTRAINT soignants_specialite_source_check
      CHECK (specialite_source IS NULL OR specialite_source IN ('RPPS', 'MANUEL'));
  END IF;
END $$;

-- 3. Colonnes sur missions
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS specialite_medicale_requise TEXT NULL REFERENCES public.specialites_medicales(code),
  ADD COLUMN IF NOT EXISTS accepte_non_specialises BOOLEAN DEFAULT true;

-- 4. Peupler les spécialités ANS (nomenclature indicative, à vérifier en Session 2)
INSERT INTO public.specialites_medicales (code, label, profession_parent) VALUES
  -- Spécialités MÉDECIN
  ('SM26', 'Médecine générale', 'MEDECIN'),
  ('SM27', 'Dermatologie et vénéréologie', 'MEDECIN'),
  ('SM28', 'Endocrinologie-diabétologie-nutrition', 'MEDECIN'),
  ('SM29', 'Gastro-entérologie et hépatologie', 'MEDECIN'),
  ('SM30', 'Génétique médicale', 'MEDECIN'),
  ('SM31', 'Gériatrie', 'MEDECIN'),
  ('SM32', 'Gynécologie médicale', 'MEDECIN'),
  ('SM33', 'Hématologie', 'MEDECIN'),
  ('SM34', 'Médecine interne', 'MEDECIN'),
  ('SM35', 'Néphrologie', 'MEDECIN'),
  ('SM36', 'Neurologie', 'MEDECIN'),
  ('SM37', 'Oncologie médicale', 'MEDECIN'),
  ('SM38', 'Pédiatrie', 'MEDECIN'),
  ('SM39', 'Pneumologie', 'MEDECIN'),
  ('SM40', 'Psychiatrie', 'MEDECIN'),
  ('SM41', 'Rhumatologie', 'MEDECIN'),
  ('SM42', 'Radiodiagnostic et imagerie médicale', 'MEDECIN'),
  ('SM43', 'Radiothérapie', 'MEDECIN'),
  ('SM44', 'Réanimation médicale', 'MEDECIN'),
  ('SM45', 'Santé publique et médecine sociale', 'MEDECIN'),
  ('SM46', 'Médecine du travail', 'MEDECIN'),
  ('SM47', 'Médecine physique et de réadaptation', 'MEDECIN'),
  ('SM48', 'Cardiologie et maladies vasculaires', 'MEDECIN'),
  ('SM49', 'Anesthésie-réanimation', 'MEDECIN'),
  ('SM50', 'Ophtalmologie', 'MEDECIN'),
  ('SM51', 'Oto-rhino-laryngologie', 'MEDECIN'),
  ('SM52', 'Médecine nucléaire', 'MEDECIN'),
  ('SM53', 'Allergologie', 'MEDECIN'),
  ('SM54', 'Biologie médicale', 'MEDECIN'),
  ('SM55', 'Médecine d''urgence', 'MEDECIN'),
  -- Spécialités CHIRURGIE
  ('SC36', 'Chirurgie générale', 'MEDECIN'),
  ('SC37', 'Neurochirurgie', 'MEDECIN'),
  ('SC38', 'Chirurgie infantile', 'MEDECIN'),
  ('SC39', 'Chirurgie maxillo-faciale', 'MEDECIN'),
  ('SC40', 'Chirurgie orthopédique et traumatologie', 'MEDECIN'),
  ('SC41', 'Chirurgie plastique, reconstructrice et esthétique', 'MEDECIN'),
  ('SC42', 'Chirurgie thoracique et cardio-vasculaire', 'MEDECIN'),
  ('SC43', 'Chirurgie urologique', 'MEDECIN'),
  ('SC44', 'Chirurgie vasculaire', 'MEDECIN'),
  ('SC45', 'Chirurgie viscérale et digestive', 'MEDECIN'),
  ('SC46', 'Gynécologie-obstétrique et gynécologie médicale', 'MEDECIN'),
  ('SC47', 'Stomatologie', 'MEDECIN')
ON CONFLICT (code) DO NOTHING;

-- 5. Notify PostgREST
NOTIFY pgrst, 'reload schema';
