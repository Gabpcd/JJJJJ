-- Refonte.A.1 — Scoring v2 : schéma DB (tables + enums + colonnes)

-- 1) Enums
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'niveau_qualitatif') THEN
    CREATE TYPE public.niveau_qualitatif AS ENUM ('BRONZE','ARGENT','OR','PLATINE');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sens_notation') THEN
    CREATE TYPE public.sens_notation AS ENUM ('ETAB_VERS_SOIGNANT','SOIGNANT_VERS_ETAB');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'statut_compte_soignant') THEN
    CREATE TYPE public.statut_compte_soignant AS ENUM ('ACTIF','SUSPENDU','SUPPRIME','EN_REVISION_ADMIN');
  END IF;
END $$;

-- 2) Colonnes soignants
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS statut_compte public.statut_compte_soignant NOT NULL DEFAULT 'ACTIF',
  ADD COLUMN IF NOT EXISTS niveau public.niveau_qualitatif,
  ADD COLUMN IF NOT EXISTS en_periode_probatoire BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS score_breakdown_id UUID,
  ADD COLUMN IF NOT EXISTS suspension_raison TEXT,
  ADD COLUMN IF NOT EXISTS suspension_le TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_soignants_statut_compte ON public.soignants (statut_compte) WHERE statut_compte <> 'ACTIF';

-- 3) Colonnes etablissements
ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS score_qualite NUMERIC,
  ADD COLUMN IF NOT EXISTS niveau public.niveau_qualitatif;

-- 4) Table notations_missions
CREATE TABLE IF NOT EXISTS public.notations_missions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id UUID NOT NULL REFERENCES public.missions(id) ON DELETE CASCADE,
  notateur_id UUID NOT NULL,
  note_id UUID NOT NULL,
  sens public.sens_notation NOT NULL,
  critere_1 INT NOT NULL CHECK (critere_1 BETWEEN 1 AND 5),
  critere_2 INT NOT NULL CHECK (critere_2 BETWEEN 1 AND 5),
  critere_3 INT NOT NULL CHECK (critere_3 BETWEEN 1 AND 5),
  critere_4 INT NOT NULL CHECK (critere_4 BETWEEN 1 AND 5),
  commentaire TEXT CHECK (commentaire IS NULL OR LENGTH(commentaire) <= 2000),
  signale BOOLEAN NOT NULL DEFAULT false,
  masque BOOLEAN NOT NULL DEFAULT false,
  masque_par UUID,
  masque_le TIMESTAMPTZ,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  mis_a_jour_le TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notateur_anonymise BOOLEAN NOT NULL DEFAULT false,
  UNIQUE (mission_id, sens)
);

CREATE INDEX IF NOT EXISTS idx_notations_note_id ON public.notations_missions (note_id, sens, cree_le DESC);
CREATE INDEX IF NOT EXISTS idx_notations_notateur ON public.notations_missions (notateur_id);
CREATE INDEX IF NOT EXISTS idx_notations_mission ON public.notations_missions (mission_id);

ALTER TABLE public.notations_missions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_notations_select ON public.notations_missions;
CREATE POLICY pol_notations_select ON public.notations_missions FOR SELECT
  USING (
    (note_id = auth.uid() AND masque = false)
    OR (note_id = mon_etablissement_id() AND masque = false)
    OR notateur_id = auth.uid()
    OR notateur_id = mon_etablissement_id()
    OR (SELECT est_admin())
  );

DROP POLICY IF EXISTS pol_notations_insert ON public.notations_missions;
CREATE POLICY pol_notations_insert ON public.notations_missions FOR INSERT
  WITH CHECK (
    notateur_id IN (auth.uid(), COALESCE(mon_etablissement_id(), '00000000-0000-0000-0000-000000000000'::uuid))
    OR (SELECT est_admin())
  );

DROP POLICY IF EXISTS pol_notations_update ON public.notations_missions;
CREATE POLICY pol_notations_update ON public.notations_missions FOR UPDATE
  USING (
    notateur_id IN (auth.uid(), COALESCE(mon_etablissement_id(), '00000000-0000-0000-0000-000000000000'::uuid))
    OR (SELECT est_admin())
  );

GRANT SELECT, INSERT, UPDATE ON public.notations_missions TO authenticated;
GRANT ALL ON public.notations_missions TO service_role;

-- 5) Table scoring_breakdown
CREATE TABLE IF NOT EXISTS public.scoring_breakdown (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id UUID NOT NULL REFERENCES public.soignants(id) ON DELETE CASCADE,
  score_total NUMERIC NOT NULL,
  niveau public.niveau_qualitatif NOT NULL,
  en_periode_probatoire BOOLEAN NOT NULL DEFAULT false,
  notation_etab_soignant_pct NUMERIC,
  notation_etab_soignant_poids NUMERIC,
  presentisme_pct NUMERIC,
  presentisme_poids NUMERIC,
  ponctualite_pct NUMERIC,
  ponctualite_poids NUMERIC,
  reactivite_pct NUMERIC,
  reactivite_poids NUMERIC,
  anciennete_volume_pct NUMERIC,
  anciennete_volume_poids NUMERIC,
  notation_soignant_etab_pct NUMERIC,
  notation_soignant_etab_poids NUMERIC,
  litiges_malus NUMERIC NOT NULL DEFAULT 0,
  absence_sans_prevenir_malus NUMERIC NOT NULL DEFAULT 0,
  bonus_super_actif NUMERIC NOT NULL DEFAULT 0,
  composantes_inactives_json JSONB,
  composantes_actives_count INT NOT NULL,
  redistribution_json JSONB,
  raison_recalcul TEXT,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scoring_breakdown_soignant ON public.scoring_breakdown (soignant_id, cree_le DESC);

ALTER TABLE public.scoring_breakdown ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_scoring_bd_select ON public.scoring_breakdown;
CREATE POLICY pol_scoring_bd_select ON public.scoring_breakdown FOR SELECT
  USING (soignant_id = auth.uid() OR (SELECT est_admin()));

GRANT SELECT ON public.scoring_breakdown TO authenticated;
GRANT ALL ON public.scoring_breakdown TO service_role;

-- 6) FK soignants.score_breakdown_id (after table exists)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_soignants_score_breakdown') THEN
    ALTER TABLE public.soignants
      ADD CONSTRAINT fk_soignants_score_breakdown
      FOREIGN KEY (score_breakdown_id) REFERENCES public.scoring_breakdown(id) ON DELETE SET NULL;
  END IF;
END $$;

-- 7) Audit constraint étendu (12 nouvelles actions Refonte.A)
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
  'RGPD_EXPORT_DONNEES','RGPD_SUPPRESSION_COMPTE','RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT',
  'DEGEL_APPLIED','OVERRIDE_CHAMP_POST_GEL','GEL_APPLIED','OVERRIDE_ANTI_SEED',
  'CONNECT_METADATA_MANQUANTE','DOCUMENT_VERIFICATION_AUTO',
  'FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE','FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE',
  'FINANCE_CHARGE_EXPIRED','FINANCE_CHARGE_FAILED','FINANCE_CHARGE_PENDING',
  'FINANCE_CHARGE_REFUNDED','FINANCE_DISPUTE_CLOSE','FINANCE_DISPUTE_OUVERTE',
  'FINANCE_PAYOUT_CANCELED','FINANCE_PAYOUT_CREATED','FINANCE_PAYOUT_FAILED',
  'FINANCE_PAYOUT_PAID','FINANCE_SEPA_CAPTURE','FINANCE_TRANSFER_CONNECT',
  'FINANCE_TRANSFER_CREATED','FINANCE_TRANSFER_FAILED','FINANCE_TRANSFER_REVERSED',
  'FINANCE_TRANSFER_UPDATED','STRIPE_CHECKOUT_ORPHANED_RECOVERED',
  'STRIPE_CONNECT_ACCOUNT_DELETED','ATTESTATION_SANTE_SIGNEE',
  'EXCLUSION_CREEE','EXCLUSION_SUPPRIMEE','FACTURE_GENEREE',
  'MISSION_ANNULATION_SERIE','MISSION_MODIFICATION','PAIEMENT_SOIGNANT_DECLARE_ETAB',
  'RECLAMATION_CREEE','ADMIN_CONSULTATION_ETABLISSEMENT','ADMIN_CONSULTATION_SOIGNANT',
  'DOCUMENT_SUPPRESSION','HEURES_EXTERNES_DECLAREES','MISSION_ANNULATION',
  'NOTE_HONORAIRES_GENEREE','PRESENCE_CONTESTATION','PRESENCE_POINTAGE_ARRIVEE',
  'PRESENCE_VALIDATION','PRESENCE_VALIDATION_LOT','RGPD_CONSENTEMENT_DONNE',
  'PAIEMENT_MONTANT_ECART','FACTURE_COMMISSION_CREATED_VIA_STRIPE',
  'TAUX_COMMISSION_MODIFIE','LITIGE_GEL_SCOPE_MODIFIE','PREFERENCE_NOTIFICATION_MODIFIEE',
  'NOTIFICATION_SKIPPED','SERIE_EMAIL_ENVOYE','SERIE_EMAIL_SKIPPED',
  'FILTRE_CREE','FILTRE_MODIFIE','FILTRE_SUPPRIME',
  'ALERTE_ACTIVEE','ALERTE_DESACTIVEE','ALERTE_ENVOYEE',
  'POOL_URGENCE_NOTIFICATIONS_ENVOYEES','POOL_URGENCE_ACCEPTATION_RAPIDE',
  'POOL_URGENCE_VALIDATION_ETAB','POOL_URGENCE_REFUS_ETAB','POOL_URGENCE_SMS_TOGGLE',
  'FAVORI_AJOUTE','FAVORI_RETIRE','SCORE_FIABILITE_PENALITE_LITIGE',
  'PARRAINAGE_ETAB_APPLIQUE','PARRAINAGE_ETAB_VALIDE','CREDIT_PARRAINAGE_CREE',
  'CREDIT_PARRAINAGE_APPLIQUE','PARRAINAGE_ETAB_ANOMALIE',
  'INSCRIPTION_LISTE_ATTENTE_PREVOYANCE',
  'SCORE_RECALCULE_V2','NOTATION_DONNEE','NOTATION_RECUE','NOTATION_MASQUEE',
  'NOTATION_SIGNALE','SCORE_ETAB_RECALCULE',
  'COMPTE_SUSPENDU','COMPTE_LEVEE_SUSPENSION','MEDIATION_OUVERTE','MEDIATION_ACCORD_PARTIES',
  'MEDIATION_REVUE_ADMIN_DEMANDEE','RAPPEL_NOTATION_J1_ENVOYE'
]));

NOTIFY pgrst, 'reload schema';
