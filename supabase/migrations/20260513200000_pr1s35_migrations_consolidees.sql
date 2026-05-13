-- PR 1 Sprint 3.5 — Migrations DB consolidées
--
-- Cette migration prépare le schéma pour les chantiers Sprint 3.5 :
--   Chantier 1 : litiges.payload_modifications + table avoirs
--   Chantier 3 : candidatures.acceptee_a + missions.est_asap +
--                evenements_score_soignant + evenements_score_etab
--   Chantier 4 : reclamations_score
--
-- Aucune logique métier ici, juste la structure. Les RPCs et triggers
-- sont implémentés dans les PRs suivantes Sprint 3.5.

-- ============================================================
-- CHANTIER 1 — Litiges : payload structuré + table avoirs
-- ============================================================

ALTER TABLE public.litiges
  ADD COLUMN IF NOT EXISTS payload_modifications jsonb,
  ADD COLUMN IF NOT EXISTS modifications_executees boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS modifications_executees_a timestamptz,
  ADD COLUMN IF NOT EXISTS modifications_executees_par uuid;

COMMENT ON COLUMN public.litiges.payload_modifications IS
  'Payload JSON structuré décrivant les modifications convenues en cas d''accord '
  'avec changement de données aval (heures, montant, annulation, compensation). '
  'Structure : { type, modifications: {...}, justification }. '
  'Cf. docs/LITIGES_RESOLUTION_AUTOMATIQUE.md.';

CREATE TABLE IF NOT EXISTS public.avoirs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  facture_origine_id uuid,
  facture_origine_type text NOT NULL CHECK (facture_origine_type IN (
    'FACTURE_ETAB', 'FACTURE_HONORAIRES_SOIGNANT', 'BULLETIN_PAIE'
  )),
  numero text NOT NULL,
  montant_ht numeric(12,2) NOT NULL CHECK (montant_ht >= 0),
  montant_ttc numeric(12,2) NOT NULL CHECK (montant_ttc >= 0),
  motif text NOT NULL CHECK (motif IN (
    'LITIGE_ACCORD_MUTUEL', 'LITIGE_MEDIATION_ADMIN',
    'ANNULATION_MISSION_ETAB', 'ANNULATION_MISSION_SOIGNANT',
    'MODIFICATION_HORAIRES', 'COMPENSATION_PARTIELLE', 'AUTRE'
  )),
  source_litige_id uuid REFERENCES public.litiges(id) ON DELETE SET NULL,
  source_mission_id uuid REFERENCES public.missions(id) ON DELETE SET NULL,
  pdf_storage_path text,
  emis_par uuid NOT NULL,
  emis_le timestamptz NOT NULL DEFAULT NOW(),
  details jsonb DEFAULT '{}'::jsonb,
  cree_le timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_avoirs_facture_origine ON public.avoirs(facture_origine_id);
CREATE INDEX IF NOT EXISTS idx_avoirs_source_litige ON public.avoirs(source_litige_id) WHERE source_litige_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_avoirs_source_mission ON public.avoirs(source_mission_id) WHERE source_mission_id IS NOT NULL;

ALTER TABLE public.avoirs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_avoirs_select ON public.avoirs;
CREATE POLICY pol_avoirs_select ON public.avoirs
  FOR SELECT TO authenticated
  USING (
    est_admin() OR emis_par = auth.uid()
    OR EXISTS (SELECT 1 FROM public.missions m
               WHERE m.id = source_mission_id
                 AND (m.soignant_assigne_id = auth.uid()
                      OR m.etablissement_id = mon_etablissement_id()))
  );

DROP POLICY IF EXISTS pol_avoirs_deny_write ON public.avoirs;
CREATE POLICY pol_avoirs_deny_write ON public.avoirs
  FOR INSERT TO authenticated WITH CHECK (false);

-- ============================================================
-- CHANTIER 3 — Annulation : fenêtre rétractation + ASAP + events
-- ============================================================

ALTER TABLE public.candidatures
  ADD COLUMN IF NOT EXISTS acceptee_a timestamptz;

COMMENT ON COLUMN public.candidatures.acceptee_a IS
  'Timestamp précis de l''acceptation par l''étab. Sert au calcul de la '
  'fenêtre de rétractation 30 min côté soignant (annulation libre sans '
  'impact score).';

ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS est_asap boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.missions.est_asap IS
  'Mission urgente publiée < 2h avant son début (pool urgence). Annulation '
  'soignant après la fenêtre de rétractation = -25 pts de score (vs -10 '
  'pour une mission classique).';

-- Helper : calcule le délai depuis l'acceptation (utilisé en SELECT)
CREATE OR REPLACE FUNCTION public.fn_dans_fenetre_retractation(p_candidature_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_acceptee_a timestamptz;
BEGIN
  SELECT acceptee_a INTO v_acceptee_a FROM public.candidatures WHERE id = p_candidature_id;
  IF v_acceptee_a IS NULL THEN RETURN false; END IF;
  RETURN NOW() - v_acceptee_a < INTERVAL '30 minutes';
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_dans_fenetre_retractation(uuid) TO authenticated;

-- Table evenements_score_soignant
CREATE TABLE IF NOT EXISTS public.evenements_score_soignant (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  type_evenement text NOT NULL CHECK (type_evenement IN (
    'ANNULATION_12_24H', 'ANNULATION_1_12H',
    'ASAP_ANNULEE_APRES_FENETRE', 'NO_SHOW',
    'LITIGE_TORT_RECONNU', 'NOTE_BASSE_RECUE',
    'EVALUATION_NEGATIVE', 'BONUS_AMBASSADEUR',
    'BONUS_FIDELITE', 'AUTRE'
  )),
  points int NOT NULL,  -- négatif = pénalité, positif = bonus
  motif text NOT NULL,
  contestable boolean NOT NULL DEFAULT true,
  -- Lien vers la réclamation si contestée
  reclamation_id uuid,  -- FK posée plus tard (cycle avec reclamations_score)
  -- Décision admin si réclamation traitée
  decision_admin text CHECK (decision_admin IS NULL OR decision_admin IN ('MAINTENIR', 'REDUIRE', 'ANNULER')),
  points_corriges int,  -- nouveau total si REDUIRE
  motif_admin text,
  traite_par_admin_id uuid,
  traite_le timestamptz,
  -- Contexte
  mission_id uuid REFERENCES public.missions(id) ON DELETE SET NULL,
  candidature_id uuid REFERENCES public.candidatures(id) ON DELETE SET NULL,
  litige_id uuid REFERENCES public.litiges(id) ON DELETE SET NULL,
  justificatif_storage_path text,
  details jsonb DEFAULT '{}'::jsonb,
  cree_le timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_evt_score_sg_soignant ON public.evenements_score_soignant(soignant_id, cree_le DESC);
CREATE INDEX IF NOT EXISTS idx_evt_score_sg_pending_admin ON public.evenements_score_soignant(traite_par_admin_id) WHERE traite_par_admin_id IS NULL AND reclamation_id IS NOT NULL;

ALTER TABLE public.evenements_score_soignant ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_evt_score_sg_select ON public.evenements_score_soignant;
CREATE POLICY pol_evt_score_sg_select ON public.evenements_score_soignant
  FOR SELECT TO authenticated
  USING (est_admin() OR soignant_id = auth.uid());
DROP POLICY IF EXISTS pol_evt_score_sg_deny_write ON public.evenements_score_soignant;
CREATE POLICY pol_evt_score_sg_deny_write ON public.evenements_score_soignant
  FOR INSERT TO authenticated WITH CHECK (false);

-- Table evenements_score_etab (parallèle)
CREATE TABLE IF NOT EXISTS public.evenements_score_etab (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL,
  type_evenement text NOT NULL CHECK (type_evenement IN (
    'ANNULATION_AVANT_CONTRAT', 'ANNULATION_CDD_SIGNE',
    'ANNULATION_LIBERAL_SIGNE', 'ANNULATION_APRES_POINTAGE',
    'PAIEMENT_RETARD', 'LITIGE_TORT_RECONNU',
    'NOTE_BASSE_RECUE', 'AUTRE'
  )),
  points int NOT NULL,  -- négatif = pénalité
  motif text NOT NULL,
  contestable boolean NOT NULL DEFAULT true,
  reclamation_id uuid,
  decision_admin text CHECK (decision_admin IS NULL OR decision_admin IN ('MAINTENIR', 'REDUIRE', 'ANNULER')),
  points_corriges int,
  motif_admin text,
  traite_par_admin_id uuid,
  traite_le timestamptz,
  mission_id uuid REFERENCES public.missions(id) ON DELETE SET NULL,
  litige_id uuid REFERENCES public.litiges(id) ON DELETE SET NULL,
  facture_id uuid,
  justificatif_storage_path text,
  details jsonb DEFAULT '{}'::jsonb,
  cree_le timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_evt_score_etab_etab ON public.evenements_score_etab(etablissement_id, cree_le DESC);

ALTER TABLE public.evenements_score_etab ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_evt_score_etab_select ON public.evenements_score_etab;
CREATE POLICY pol_evt_score_etab_select ON public.evenements_score_etab
  FOR SELECT TO authenticated
  USING (est_admin() OR etablissement_id = mon_etablissement_id());
DROP POLICY IF EXISTS pol_evt_score_etab_deny_write ON public.evenements_score_etab;
CREATE POLICY pol_evt_score_etab_deny_write ON public.evenements_score_etab
  FOR INSERT TO authenticated WITH CHECK (false);

-- ============================================================
-- CHANTIER 4 — Réclamations score
-- ============================================================

CREATE TABLE IF NOT EXISTS public.reclamations_score (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Polymorphe : pointe soit vers evenements_score_soignant soit _etab
  evenement_type text NOT NULL CHECK (evenement_type IN ('SOIGNANT', 'ETAB')),
  evenement_soignant_id uuid REFERENCES public.evenements_score_soignant(id) ON DELETE CASCADE,
  evenement_etab_id uuid REFERENCES public.evenements_score_etab(id) ON DELETE CASCADE,
  CONSTRAINT chk_evt_xor CHECK (
    (evenement_type = 'SOIGNANT' AND evenement_soignant_id IS NOT NULL AND evenement_etab_id IS NULL)
    OR
    (evenement_type = 'ETAB' AND evenement_etab_id IS NOT NULL AND evenement_soignant_id IS NULL)
  ),
  contesteur_id uuid NOT NULL,
  motif_categorie text NOT NULL CHECK (motif_categorie IN (
    'URGENCE_MEDICALE', 'DEUIL', 'FORCE_MAJEURE',
    'ERREUR_JOLENE', 'CONTEXTE_PARTICULIER', 'AUTRE'
  )),
  texte_libre text NOT NULL,
  justificatif_storage_path text,
  statut text NOT NULL DEFAULT 'PENDING' CHECK (statut IN ('PENDING', 'TREATED', 'CANCELLED')),
  decision_admin text CHECK (decision_admin IS NULL OR decision_admin IN ('MAINTENIR', 'REDUIRE', 'ANNULER')),
  motif_admin text,
  traitee_par_admin_id uuid,
  traitee_le timestamptz,
  cree_le timestamptz NOT NULL DEFAULT NOW(),
  modifiee_le timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rec_score_pending
  ON public.reclamations_score(statut, cree_le) WHERE statut = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_rec_score_contesteur
  ON public.reclamations_score(contesteur_id);
CREATE INDEX IF NOT EXISTS idx_rec_score_evt_soignant
  ON public.reclamations_score(evenement_soignant_id) WHERE evenement_soignant_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_rec_score_evt_etab
  ON public.reclamations_score(evenement_etab_id) WHERE evenement_etab_id IS NOT NULL;

ALTER TABLE public.reclamations_score ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_rec_score_select ON public.reclamations_score;
CREATE POLICY pol_rec_score_select ON public.reclamations_score
  FOR SELECT TO authenticated
  USING (est_admin() OR contesteur_id = auth.uid());
DROP POLICY IF EXISTS pol_rec_score_deny_write ON public.reclamations_score;
CREATE POLICY pol_rec_score_deny_write ON public.reclamations_score
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- ============================================================
-- Audit
-- ============================================================
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'table', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT35_PR1_MIGRATIONS_CONSOLIDEES',
    'pr', 'PR 1 Sprint 3.5',
    'tables_creees', ARRAY['avoirs', 'evenements_score_soignant',
                            'evenements_score_etab', 'reclamations_score'],
    'colonnes_ajoutees', ARRAY['litiges.payload_modifications',
                                'litiges.modifications_executees',
                                'litiges.modifications_executees_a',
                                'litiges.modifications_executees_par',
                                'candidatures.acceptee_a',
                                'missions.est_asap'],
    'helpers', ARRAY['fn_dans_fenetre_retractation']
  )
);
