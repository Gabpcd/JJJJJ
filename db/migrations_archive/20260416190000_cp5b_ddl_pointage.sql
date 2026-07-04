-- ============================================================
-- CP5b Step 1 — DDL : type_creneau + colonnes pointage + scans_pointage
-- ============================================================
-- Audit: /docs/cp5b-creneaux-et-pointage.md sections 1.1, 2.1, 2.2
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 1a. mission_creneaux : colonne type_creneau
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.mission_creneaux
  ADD COLUMN IF NOT EXISTS type_creneau text NOT NULL DEFAULT 'PREVISIONNEL';

ALTER TABLE public.mission_creneaux
  ADD CONSTRAINT chk_type_creneau CHECK (type_creneau IN ('PREVISIONNEL', 'EFFECTIF'));

-- ──────────────────────────────────────────────────────────────
-- 1b. missions : colonnes effectives + pointage
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS debut_effectif timestamptz,
  ADD COLUMN IF NOT EXISTS fin_effective timestamptz,
  ADD COLUMN IF NOT EXISTS duree_heures_effective numeric,
  ADD COLUMN IF NOT EXISTS code_pointage_actif text,
  ADD COLUMN IF NOT EXISTS code_pointage_hmac text,
  ADD COLUMN IF NOT EXISTS prochain_type_scan text DEFAULT 'OUVERTURE',
  ADD COLUMN IF NOT EXISTS nb_scans smallint DEFAULT 0;

ALTER TABLE public.missions
  ADD CONSTRAINT chk_prochain_type_scan CHECK (prochain_type_scan IN ('OUVERTURE', 'FERMETURE'));

-- Allow NULL fin for EFFECTIF (open slots from OUVERTURE scan without FERMETURE)
ALTER TABLE public.mission_creneaux ALTER COLUMN fin DROP NOT NULL;
ALTER TABLE public.mission_creneaux
  ADD CONSTRAINT chk_fin_previsionnel CHECK (type_creneau = 'EFFECTIF' OR fin IS NOT NULL);

-- Relax ck_creneau_coherent to allow NULL fin (EFFECTIF open slots)
ALTER TABLE public.mission_creneaux DROP CONSTRAINT IF EXISTS ck_creneau_coherent;
ALTER TABLE public.mission_creneaux ADD CONSTRAINT ck_creneau_coherent CHECK (fin IS NULL OR fin > debut);

-- ──────────────────────────────────────────────────────────────
-- 1c. Table scans_pointage
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.scans_pointage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL REFERENCES missions(id),
  soignant_id uuid NOT NULL REFERENCES auth.users(id),

  code_saisi text NOT NULL,
  numero_scan smallint NOT NULL,
  type_scan text NOT NULL CHECK (type_scan IN ('OUVERTURE', 'FERMETURE')),
  scanne_le timestamptz NOT NULL DEFAULT now(),
  horodatage_arrondi timestamptz NOT NULL,

  creneau_effectif_id uuid REFERENCES mission_creneaux(id) ON DELETE CASCADE,

  est_en_avance boolean NOT NULL DEFAULT false,
  validation_etab_requise boolean NOT NULL DEFAULT false,
  valide_par_etab boolean NOT NULL DEFAULT false,
  valide_le timestamptz,
  valide_par uuid REFERENCES auth.users(id),

  latitude numeric,
  longitude numeric,
  precision_gps_m numeric,
  id_terminal text,
  ip_address inet,
  distance_etablissement_m numeric,

  cree_le timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.scans_pointage ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_scans_pointage_mission ON scans_pointage(mission_id, numero_scan);
CREATE INDEX IF NOT EXISTS idx_scans_pointage_code ON scans_pointage(code_saisi);

-- RLS policies
CREATE POLICY sp_insert ON scans_pointage FOR INSERT WITH CHECK (
  auth.uid() = soignant_id
);

CREATE POLICY sp_select ON scans_pointage FOR SELECT USING (
  auth.uid() = soignant_id
  OR est_admin()
  OR est_admin_etablissement()
);

CREATE POLICY sp_update ON scans_pointage FOR UPDATE USING (
  est_admin() OR est_admin_etablissement()
);

-- GRANTs
GRANT INSERT, SELECT ON public.scans_pointage TO authenticated;
GRANT UPDATE ON public.scans_pointage TO authenticated;
GRANT ALL ON public.scans_pointage TO service_role;

-- ──────────────────────────────────────────────────────────────
-- 1d. Deprecation presences
-- ──────────────────────────────────────────────────────────────
COMMENT ON TABLE public.presences IS 'DEPRECATED CP5b — remplacée par scans_pointage + mission_creneaux EFFECTIF. Ne pas utiliser pour les nouvelles fonctionnalités.';

-- ──────────────────────────────────────────────────────────────
-- 1e. Deprecation code_arrivee / code_depart
-- ──────────────────────────────────────────────────────────────
COMMENT ON COLUMN public.missions.code_arrivee IS 'DEPRECATED CP5b — remplacé par code_pointage_actif (code unique régénéré à chaque scan).';
COMMENT ON COLUMN public.missions.code_depart IS 'DEPRECATED CP5b — remplacé par code_pointage_actif.';

-- ──────────────────────────────────────────────────────────────
-- 1f. Extend journaux_audit CHECK for GEL_APPLIED
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.journaux_audit DROP CONSTRAINT IF EXISTS journaux_audit_action_check;
ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_action_check CHECK (action = ANY (ARRAY[
  'INSCRIPTION','CONNEXION','DECONNEXION','MODIFICATION_PROFIL','SUPPRESSION_COMPTE',
  'UPLOAD_DOCUMENT','TELECHARGEMENT_DOCUMENT','VERIFICATION_DOCUMENT','VERIFICATION_RPPS',
  'CREATION_MISSION','MODIFICATION_MISSION','ANNULATION_MISSION','CANDIDATURE','ASSIGNATION',
  'POINTAGE','SIGNATURE_CONTRAT','EVALUATION','PAIEMENT','FACTURATION',
  'DONNEES_PERSO_CONSULTATION','DONNEES_PERSO_EXPORT','DONNEES_PERSO_SUPPRESSION',
  'ADMIN_ACTION','SYSTEM','RIB_CONSULTE','RIB_PARTAGE','CONTRAT_SIGNE',
  'DOCUMENT_CONSULTATION','DOCUMENT_TELEVERSEMENT','DONNEES_PERSO_MODIFICATION',
  'EXPORT_RH_PAIE','FINANCE_FACTURE_PAYEE','MISSION_ASSIGNATION','MISSION_CREATION',
  'RGPD_EXPORT_DONNEES',
  'DEGEL_APPLIED','OVERRIDE_CHAMP_POST_GEL','GEL_APPLIED'
]));
