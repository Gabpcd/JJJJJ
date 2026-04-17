-- ============================================================
-- CP-LITIGES-1 — DDL : extension du système de litiges
-- ============================================================
-- Sub-PR 2 quater — Extension système litiges (Option A+)
--
-- Objectif : étendre le système existant sans refonte.
--   - 5 nouveaux enums (categorie, type, statut facture, type document, mode remboursement)
--   - 8 colonnes sur litiges (type, categorie, facture_id, est_informatif, ...)
--   - 7 colonnes sur factures_honoraires (type_document, statut_litige, litige_id, ...)
--   - 2 colonnes sur missions (regularisation_sociale_requise, commission_a_recalculer)
--   - Nouvelle table parametres_litiges (k/v configurable admin)
--   - Index pour perf dashboard + idempotence auto-création
--   - Backfill type_legacy=TRUE sur les litiges existants
--   - Extension fn_protect_facture_honoraire_immutability (verrou type_document + facture_precedente_id)
--
-- Les triggers (mapping catégorie, gel/dégel facture, auto-création présence)
-- et les RPCs (fn_fenetre_contestation_ouverte, fn_admin_creer_litige_force,
-- fn_ajouter_jours_ouvres, wrapper fn_ouvrir_litige_rate_limited) sont livrés
-- dans CP-LITIGES-2.
--
-- Cf. audit Sub-PR 2 quater (sections 1 à 11, messages chat Gabrielle).
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- 1. ENUMS
-- ──────────────────────────────────────────────────────────────

-- 5 catégories pour groupement dashboard admin
CREATE TYPE public.categorie_litige AS ENUM (
  'PRESENCE',
  'FINANCIER',
  'CONDITIONS',
  'COMPORTEMENT',
  'AUTRE'
);

-- 12 types fins (mapping vers catégorie via trigger CP2)
CREATE TYPE public.type_litige AS ENUM (
  'ABSENCE_SOIGNANT',
  'DEPART_ANTICIPE',
  'RETARD_IMPORTANT',
  'DESACCORD_MONTANT_FACTURE',
  'DESACCORD_HEURES_POINTAGE',
  'NON_PAIEMENT',
  'FRAIS_COMPLEMENTAIRES',
  'CONDITIONS_MISSION_NON_RESPECTEES',
  'SECURITE_DANGER',
  'COMPORTEMENT_SOIGNANT',
  'COMPORTEMENT_ETABLISSEMENT',
  'AUTRE'
);

-- 4 statuts de litige sur facture (gel/dégel)
CREATE TYPE public.statut_litige_facture AS ENUM (
  'NORMAL',
  'EN_ATTENTE_LITIGE',
  'LITIGE_RESOLU_AJUSTE',
  'LITIGE_RESOLU_CONFIRME'
);

-- Type document facturaire (facture vs avoir)
CREATE TYPE public.type_document_facture AS ENUM (
  'FACTURE',
  'AVOIR'
);

-- Mode de remboursement pour les avoirs
CREATE TYPE public.mode_remboursement_avoir AS ENUM (
  'N_A',
  'AUTO_STRIPE',
  'VIREMENT_MANUEL'
);

-- ──────────────────────────────────────────────────────────────
-- 2. ALTER public.litiges — 8 nouvelles colonnes
-- ──────────────────────────────────────────────────────────────

ALTER TABLE public.litiges
  ADD COLUMN type_litige public.type_litige NOT NULL DEFAULT 'AUTRE',
  ADD COLUMN categorie_litige public.categorie_litige NOT NULL DEFAULT 'AUTRE',
  ADD COLUMN facture_id UUID REFERENCES public.factures_honoraires(id) ON DELETE SET NULL,
  ADD COLUMN est_informatif BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN type_legacy BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN montant_tresorerie_bloquee NUMERIC(12,2),
  ADD COLUMN derniers_rappels_envoyes JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN escalade_auto_le TIMESTAMPTZ,
  ADD COLUMN escalade_auto_motif TEXT;

COMMENT ON COLUMN public.litiges.type_litige IS 'Type fin parmi 12 valeurs (ABSENCE_SOIGNANT, DEPART_ANTICIPE, ...). AUTRE par défaut.';
COMMENT ON COLUMN public.litiges.categorie_litige IS 'Catégorie de regroupement (PRESENCE, FINANCIER, CONDITIONS, COMPORTEMENT, AUTRE). Auto-synchronisée depuis type_litige via trigger.';
COMMENT ON COLUMN public.litiges.facture_id IS 'FK facture impactée par le litige. Nullable (litige de présence sans facture encore émise).';
COMMENT ON COLUMN public.litiges.est_informatif IS 'TRUE si litige hors fenêtre légale (> 6 mois pour COMPORTEMENT/CONDITIONS). Pas de propagation financière, juste traçabilité.';
COMMENT ON COLUMN public.litiges.type_legacy IS 'TRUE pour litiges créés avant typologie (type_litige=AUTRE par défaut). Utilisé pour re-catégorisation admin rétroactive.';
COMMENT ON COLUMN public.litiges.montant_tresorerie_bloquee IS 'Cache calculé par cron : SUM(montant_ht) des factures gelées par ce litige. Utilisé pour tri dashboard.';
COMMENT ON COLUMN public.litiges.derniers_rappels_envoyes IS 'Idempotence rappels cron : {"J+1": "2026-04-17T08:00:00Z", "J+3": null, "J+5": null}.';
COMMENT ON COLUMN public.litiges.escalade_auto_le IS 'Timestamp de l''escalade automatique EN_MEDIATION par le cron.';
COMMENT ON COLUMN public.litiges.escalade_auto_motif IS 'Motif textuel de l''escalade (ex: "Pas de réponse dans le délai libéral 72h").';

-- ──────────────────────────────────────────────────────────────
-- 3. ALTER public.factures_honoraires — 7 nouvelles colonnes
-- ──────────────────────────────────────────────────────────────
-- Ordre d'ajout crucial : type_document AVANT montant_signe GENERATED.

ALTER TABLE public.factures_honoraires
  ADD COLUMN type_document public.type_document_facture NOT NULL DEFAULT 'FACTURE',
  ADD COLUMN statut_litige public.statut_litige_facture NOT NULL DEFAULT 'NORMAL',
  ADD COLUMN litige_id UUID REFERENCES public.litiges(id) ON DELETE SET NULL,
  ADD COLUMN facture_precedente_id UUID REFERENCES public.factures_honoraires(id) ON DELETE SET NULL,
  ADD COLUMN mode_remboursement public.mode_remboursement_avoir NOT NULL DEFAULT 'N_A',
  ADD COLUMN date_remboursement TIMESTAMPTZ,
  ADD COLUMN reference_remboursement TEXT;

-- Colonne calculée (signe négatif pour AVOIR) : agrégats comptables propres.
ALTER TABLE public.factures_honoraires
  ADD COLUMN montant_signe NUMERIC(12,2)
    GENERATED ALWAYS AS (
      CASE WHEN type_document = 'AVOIR' THEN -montant_ht ELSE montant_ht END
    ) STORED;

COMMENT ON COLUMN public.factures_honoraires.type_document IS 'FACTURE ou AVOIR. Un avoir référence une facture via facture_precedente_id.';
COMMENT ON COLUMN public.factures_honoraires.statut_litige IS 'NORMAL | EN_ATTENTE_LITIGE (gelée) | LITIGE_RESOLU_AJUSTE (modifiée) | LITIGE_RESOLU_CONFIRME (validée sans changement).';
COMMENT ON COLUMN public.factures_honoraires.litige_id IS 'FK litige ayant déclenché le gel. Renseigné par trigger trg_litige_gel_facture (CP2).';
COMMENT ON COLUMN public.factures_honoraires.facture_precedente_id IS 'Pour type_document=AVOIR : FK facture annulée/ajustée. Pour facture hebdomadaire : chaînage facture précédente.';
COMMENT ON COLUMN public.factures_honoraires.mode_remboursement IS 'Pour AVOIR : AUTO_STRIPE (<120j), VIREMENT_MANUEL, ou N_A (pas un avoir).';
COMMENT ON COLUMN public.factures_honoraires.date_remboursement IS 'Timestamp effectif du remboursement (webhook Stripe ou confirmation admin).';
COMMENT ON COLUMN public.factures_honoraires.reference_remboursement IS 'Référence du virement manuel OU stripe_refund_id.';
COMMENT ON COLUMN public.factures_honoraires.montant_signe IS 'Montant signé (négatif si AVOIR) pour agrégats comptables.';

-- ──────────────────────────────────────────────────────────────
-- 4. ALTER public.missions — 2 nouvelles colonnes
-- ──────────────────────────────────────────────────────────────

ALTER TABLE public.missions
  ADD COLUMN regularisation_sociale_requise BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN commission_a_recalculer BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.missions.regularisation_sociale_requise IS 'TRUE si résolution admin modifie heures d''une facture > 3 mois (déclarée URSSAF/Carpimko).';
COMMENT ON COLUMN public.missions.commission_a_recalculer IS 'TRUE si ajustement financier nécessite recalcul commission Jolene au prochain cycle mensuel.';

-- ──────────────────────────────────────────────────────────────
-- 5. Nouvelle table public.parametres_litiges (k/v admin)
-- ──────────────────────────────────────────────────────────────

CREATE TABLE public.parametres_litiges (
  cle TEXT PRIMARY KEY,
  valeur TEXT NOT NULL,
  description TEXT NOT NULL,
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_par UUID
);

COMMENT ON TABLE public.parametres_litiges IS 'Paramètres globaux du système litiges (délais, seuils). Modifiables par admin uniquement.';

-- Seed valeurs par défaut (alignées sur audit Sub-PR 2 quater).
INSERT INTO public.parametres_litiges (cle, valeur, description) VALUES
  ('delai_contestation_pointage_h',         '48',  'Fenêtre 48h post-pointage pour contester présence (types PRESENCE).'),
  ('delai_contestation_facture_liberal_h',  '48',  'Fenêtre 48h post-émission facture pour soignant libéral (types FINANCIER).'),
  ('delai_contestation_paiement_salarie_j', '60',  'Fenêtre 60j post-paiement salarié CDDU pour contester montant.'),
  ('delai_comportement_mois',               '6',   'Fenêtre 6 mois post-mission pour COMPORTEMENT/CONDITIONS. Au-delà, litige informatif.'),
  ('delai_escalade_liberal_h',              '72',  'Escalade auto libéral après 72h sans réponse.'),
  ('delai_escalade_salarie_jours_ouvres',   '5',   'Escalade auto salarié après 5 jours ouvrés sans réponse.'),
  ('delai_mediation_alerte_prioritaire_j',  '7',   'Alerte prioritaire EN_MEDIATION sans action admin > 7 jours.'),
  ('seuil_tresorerie_alerte_euros',         '500', 'Alerte rouge dashboard si montant_tresorerie_bloquee > 500 €.'),
  ('seuil_tresorerie_alerte_jours',         '5',   'Alerte rouge dashboard si jours_ouverture > 5 jours.'),
  ('delai_notif_urssaf_mois',               '3',   'Notif URSSAF/Carpimko si ajustement sur facture émise > 3 mois.'),
  ('rate_limit_litiges_par_24h',            '3',   'Rate limit : 3 litiges par 24h par entité (existant, paramétrisé).'),
  ('delai_stripe_refund_auto_j',            '120', 'Limite Stripe refund automatique. Au-delà → virement manuel.'),
  ('seuil_retard_minutes',                  '30',  'Seuil minimum en minutes pour signaler RETARD_IMPORTANT.');

-- ──────────────────────────────────────────────────────────────
-- 6. Indexes (perf dashboard + idempotence auto-création)
-- ──────────────────────────────────────────────────────────────

CREATE INDEX idx_litiges_type_statut_ouverts
  ON public.litiges(type_litige, statut)
  WHERE statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE');

CREATE INDEX idx_litiges_categorie_ouverts
  ON public.litiges(categorie_litige)
  WHERE statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE');

CREATE INDEX idx_litiges_facture_id
  ON public.litiges(facture_id)
  WHERE facture_id IS NOT NULL;

CREATE INDEX idx_litiges_escalade_auto
  ON public.litiges(escalade_auto_le)
  WHERE escalade_auto_le IS NOT NULL;

CREATE INDEX idx_fh_litige_id
  ON public.factures_honoraires(litige_id)
  WHERE litige_id IS NOT NULL;

CREATE INDEX idx_fh_statut_litige
  ON public.factures_honoraires(statut_litige)
  WHERE statut_litige <> 'NORMAL';

CREATE INDEX idx_fh_facture_precedente
  ON public.factures_honoraires(facture_precedente_id)
  WHERE facture_precedente_id IS NOT NULL;

CREATE INDEX idx_fh_type_document
  ON public.factures_honoraires(type_document)
  WHERE type_document = 'AVOIR';

-- Unique partiel : évite doublons auto-création pour un même (mission, type) encore ouvert.
CREATE UNIQUE INDEX uq_litige_mission_type_ouvert
  ON public.litiges(mission_id, type_litige)
  WHERE statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION');

-- ──────────────────────────────────────────────────────────────
-- 7. Backfill : tous les litiges existants sont "legacy"
-- ──────────────────────────────────────────────────────────────
-- type_litige/categorie_litige ont reçu 'AUTRE' via DEFAULT.
-- On marque explicitement type_legacy=TRUE pour permettre re-catégorisation
-- admin rétroactive (R1 dans section 11 des risques).

UPDATE public.litiges SET type_legacy = TRUE;

-- Sanity check : aucun litige ne doit avoir type_legacy=FALSE à ce stade.
DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM public.litiges WHERE type_legacy = FALSE;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Backfill type_legacy échoué : % litiges non marqués', v_count;
  END IF;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- 8. RLS pour parametres_litiges
-- ──────────────────────────────────────────────────────────────

ALTER TABLE public.parametres_litiges ENABLE ROW LEVEL SECURITY;

CREATE POLICY pol_param_litiges_select
  ON public.parametres_litiges
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY pol_param_litiges_insert_admin
  ON public.parametres_litiges
  FOR INSERT
  TO authenticated
  WITH CHECK (public.est_admin());

CREATE POLICY pol_param_litiges_update_admin
  ON public.parametres_litiges
  FOR UPDATE
  TO authenticated
  USING (public.est_admin())
  WITH CHECK (public.est_admin());

CREATE POLICY pol_param_litiges_delete_admin
  ON public.parametres_litiges
  FOR DELETE
  TO authenticated
  USING (public.est_admin());

-- Grants (aligné sur autres tables paramétriques)
GRANT SELECT ON public.parametres_litiges TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.parametres_litiges TO authenticated;
GRANT ALL ON public.parametres_litiges TO service_role;

-- ──────────────────────────────────────────────────────────────
-- 9. Extension fn_protect_facture_honoraire_immutability
-- ──────────────────────────────────────────────────────────────
-- Verrouille type_document et facture_precedente_id après EMISE
-- (une facture ne peut jamais devenir un avoir et inversement ;
--  le chaînage avoir→facture est fixé à la création).
-- Les colonnes statut_litige, litige_id, mode_remboursement,
-- date_remboursement, reference_remboursement restent modifiables
-- (gel/dégel/remboursement appliqués post-EMISE).

CREATE OR REPLACE FUNCTION public.fn_protect_facture_honoraire_immutability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Bypass pour service_role et admin
  IF COALESCE(current_setting('request.jwt.claim.role', true) = 'service_role', auth.uid() IS NULL) THEN
    RETURN NEW;
  END IF;
  IF est_admin() THEN RETURN NEW; END IF;

  -- Avant EMISE, tout est modifiable
  IF OLD.statut = 'BROUILLON' THEN RETURN NEW; END IF;

  -- Après EMISE : montants, numéro, identités sont verrouillés
  IF NEW.montant_ht IS DISTINCT FROM OLD.montant_ht THEN
    RAISE EXCEPTION 'Facture honoraire émise : montant_ht verrouillé';
  END IF;
  IF NEW.montant_ttc IS DISTINCT FROM OLD.montant_ttc THEN
    RAISE EXCEPTION 'Facture honoraire émise : montant_ttc verrouillé';
  END IF;
  IF NEW.montant_tva IS DISTINCT FROM OLD.montant_tva THEN
    RAISE EXCEPTION 'Facture honoraire émise : montant_tva verrouillé';
  END IF;
  IF NEW.taux_tva IS DISTINCT FROM OLD.taux_tva THEN
    RAISE EXCEPTION 'Facture honoraire émise : taux_tva verrouillé';
  END IF;
  IF NEW.numero_facture IS DISTINCT FROM OLD.numero_facture THEN
    RAISE EXCEPTION 'Facture honoraire émise : numero_facture verrouillé';
  END IF;
  IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
    RAISE EXCEPTION 'Facture honoraire émise : soignant_id verrouillé';
  END IF;
  IF NEW.etablissement_id IS DISTINCT FROM OLD.etablissement_id THEN
    RAISE EXCEPTION 'Facture honoraire émise : etablissement_id verrouillé';
  END IF;
  IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN
    RAISE EXCEPTION 'Facture honoraire émise : mission_id verrouillé';
  END IF;
  IF NEW.date_emission IS DISTINCT FROM OLD.date_emission THEN
    RAISE EXCEPTION 'Facture honoraire émise : date_emission verrouillée';
  END IF;

  -- [CP-LITIGES-1] Verrous structurels sur les nouvelles colonnes
  IF NEW.type_document IS DISTINCT FROM OLD.type_document THEN
    RAISE EXCEPTION 'Facture honoraire émise : type_document verrouillé (FACTURE ne devient pas AVOIR et inversement)';
  END IF;
  IF NEW.facture_precedente_id IS DISTINCT FROM OLD.facture_precedente_id THEN
    RAISE EXCEPTION 'Facture honoraire émise : facture_precedente_id verrouillé (chaînage figé à la création)';
  END IF;

  RETURN NEW;
END;
$$;

-- Le trigger trg_fh_immutability existant reste attaché à cette fonction
-- (CREATE OR REPLACE remplace le corps, pas besoin de DROP/CREATE TRIGGER).

COMMIT;

-- ============================================================
-- Vérifications post-migration (à exécuter manuellement en prod
-- après déploiement pour valider l'état final) :
--
--   SELECT type_litige, categorie_litige, type_legacy, COUNT(*)
--   FROM public.litiges GROUP BY 1,2,3;
--     -- attendu : tout en AUTRE/AUTRE/TRUE
--
--   SELECT type_document, statut_litige, COUNT(*)
--   FROM public.factures_honoraires GROUP BY 1,2;
--     -- attendu : tout en FACTURE/NORMAL
--
--   SELECT COUNT(*) FROM public.parametres_litiges;
--     -- attendu : 13 lignes
--
--   SELECT COUNT(*) FROM public.missions WHERE regularisation_sociale_requise;
--     -- attendu : 0
-- ============================================================
