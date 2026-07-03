-- Escrow 7b-D — PR 2 : machine à états + plafond d'exposition (A2) + release
-- sur validation des présences (trou 5). Backend pur, INACTIF tant que
-- feature_paiement_rapide_actif = 0 : aucune ligne paiements_escrow n'existe
-- avant la PR 3 (débit à la confirmation), donc le trigger et la queue sont
-- des no-ops sur tout le trafic actuel.
--
-- Décisions encodées (docs/ESCROW_7BD_MAPPING.md §6) :
--   A2 : exposition = fonds libérés encore remboursables (fenêtre glissante
--        8 semaines post-débit) ; plafond 2 000 € → 5 000 € après 3 missions
--        sans incident ; gel au 1er incident, déblocage admin manuel.
--   A3 : DEBITE (PaymentIntent succeeded) ≠ DISPONIBLE (balance available) —
--        le consumer de release (PR 5) vérifie les DEUX conditions.
--   Trou 5 : l'événement de release = flip de la dernière présence bloquante,
--        miroir exact du gate 7b-B (migration 20260702154526).

-- ── 1. Paramètres système ──────────────────────────────────────────────────

INSERT INTO parametres_systeme (cle, valeur, label, description, unite, categorie, val_min, val_max, cablee)
VALUES
  ('escrow_plafond_base_cents', 200000,
   'Plafond exposition escrow (base)',
   'A2 §11.1 — plafond des fonds libérés encore remboursables par établissement (fenêtre 8 semaines). Au-delà, les nouvelles missions repassent en régime standard.',
   'cents', 'FINANCE', 0, 100000000, true),
  ('escrow_plafond_confiance_cents', 500000,
   'Plafond exposition escrow (confiance)',
   'A2 — plafond relevé après N missions sans incident (cf. escrow_missions_confiance_seuil).',
   'cents', 'FINANCE', 0, 100000000, true),
  ('escrow_missions_confiance_seuil', 3,
   'Seuil de confiance escrow',
   'A2 — nombre de missions escrow sans incident pour passer au plafond confiance.',
   'missions', 'FINANCE', 0, 100, true),
  ('escrow_fenetre_remboursable_jours', 56,
   'Fenêtre remboursable escrow',
   'A2 — durée pendant laquelle un release compte dans l''exposition (8 semaines post-débit SEPA).',
   'jours', 'FINANCE', 1, 365, true)
ON CONFLICT (cle) DO NOTHING;

-- ── 2. Tables ──────────────────────────────────────────────────────────────

-- Machine à états du paiement escrow — 1 mission ↔ 1 paiement (trou 6).
CREATE TABLE IF NOT EXISTS paiements_escrow (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL UNIQUE REFERENCES missions(id),
  etablissement_id uuid NOT NULL REFERENCES etablissements(id),
  soignant_id uuid NOT NULL REFERENCES soignants(id),
  montant_total_cents integer NOT NULL CHECK (montant_total_cents > 0),
  commission_cents integer NOT NULL CHECK (commission_cents >= 0),
  honoraires_cents integer NOT NULL CHECK (honoraires_cents > 0),
  methode_debit text CHECK (methode_debit IN ('SEPA', 'CARTE', 'VIREMENT_INSTANTANE')),
  stripe_payment_intent_id text,
  stripe_charge_id text,
  stripe_payout_id text,
  -- A3 : DEBITE = PaymentIntent succeeded ; DISPONIBLE = fonds available sur le
  -- solde connecté (balance transaction available_on atteint). Un release ne
  -- part JAMAIS d'un simple DEBITE.
  statut text NOT NULL DEFAULT 'INITIE' CHECK (statut IN (
    'INITIE', 'DEBITE', 'DISPONIBLE', 'RELEASE_PLANIFIE', 'PAYE',
    'ECHOUE', 'REMBOURSE', 'DISPUTE'
  )),
  available_on timestamptz,
  relance_prevue_le timestamptz,
  erreur text,
  initie_le timestamptz NOT NULL DEFAULT now(),
  debite_le timestamptz,
  disponible_le timestamptz,
  release_planifie_le timestamptz,
  paye_le timestamptz,
  cree_le timestamptz NOT NULL DEFAULT now(),
  modifie_le timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_paiements_escrow_etab_statut
  ON paiements_escrow (etablissement_id, statut);
CREATE INDEX IF NOT EXISTS idx_paiements_escrow_statut
  ON paiements_escrow (statut);
CREATE INDEX IF NOT EXISTS idx_paiements_escrow_soignant
  ON paiements_escrow (soignant_id);

-- État ⚡ par établissement : confiance (plafond relevé) + gel incident (A2).
CREATE TABLE IF NOT EXISTS escrow_etablissement_etat (
  etablissement_id uuid PRIMARY KEY REFERENCES etablissements(id) ON DELETE CASCADE,
  missions_sans_incident integer NOT NULL DEFAULT 0 CHECK (missions_sans_incident >= 0),
  gele boolean NOT NULL DEFAULT false,
  gele_le timestamptz,
  gele_raison text,
  modifie_le timestamptz NOT NULL DEFAULT now()
);

-- Exposition A2 : un enregistrement par release, fenêtre 8 semaines post-débit.
-- Exposition courante = SUM(montant_cents) des lignes ACTIF. Décrément par
-- expiration (cron quotidien) ou règlement définitif (REGLE, posé par PR 4/5).
CREATE TABLE IF NOT EXISTS escrow_exposition_releases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL REFERENCES etablissements(id),
  paiement_escrow_id uuid NOT NULL UNIQUE REFERENCES paiements_escrow(id),
  montant_cents integer NOT NULL CHECK (montant_cents > 0),
  debite_le timestamptz NOT NULL,
  release_le timestamptz NOT NULL DEFAULT now(),
  expire_le timestamptz NOT NULL,
  statut text NOT NULL DEFAULT 'ACTIF' CHECK (statut IN ('ACTIF', 'EXPIRE', 'REGLE')),
  cree_le timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_escrow_exposition_etab_statut
  ON escrow_exposition_releases (etablissement_id, statut);
CREATE INDEX IF NOT EXISTS idx_escrow_exposition_expire
  ON escrow_exposition_releases (expire_le) WHERE statut = 'ACTIF';

-- File de release — produite par le trigger présences, consommée par l'edge
-- function de payout (PR 5). UNIQUE(paiement_escrow_id) = idempotence du flip.
CREATE TABLE IF NOT EXISTS escrow_release_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  paiement_escrow_id uuid NOT NULL UNIQUE REFERENCES paiements_escrow(id),
  mission_id uuid NOT NULL REFERENCES missions(id),
  statut text NOT NULL DEFAULT 'EN_ATTENTE' CHECK (statut IN ('EN_ATTENTE', 'EN_COURS', 'TRAITE', 'ECHEC')),
  tentatives integer NOT NULL DEFAULT 0,
  prochaine_tentative_le timestamptz NOT NULL DEFAULT now(),
  erreur text,
  cree_le timestamptz NOT NULL DEFAULT now(),
  traite_le timestamptz
);

CREATE INDEX IF NOT EXISTS idx_escrow_release_queue_a_traiter
  ON escrow_release_queue (prochaine_tentative_le) WHERE statut = 'EN_ATTENTE';

-- ── 3. RLS ─────────────────────────────────────────────────────────────────
-- Écritures : service_role uniquement (bypass RLS) — aucune policy d'écriture.

ALTER TABLE paiements_escrow ENABLE ROW LEVEL SECURITY;
ALTER TABLE escrow_etablissement_etat ENABLE ROW LEVEL SECURITY;
ALTER TABLE escrow_exposition_releases ENABLE ROW LEVEL SECURITY;
ALTER TABLE escrow_release_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS paiements_escrow_select_soignant ON paiements_escrow;
CREATE POLICY paiements_escrow_select_soignant ON paiements_escrow
  FOR SELECT USING (soignant_id = auth.uid());

DROP POLICY IF EXISTS paiements_escrow_select_etab ON paiements_escrow;
CREATE POLICY paiements_escrow_select_etab ON paiements_escrow
  FOR SELECT USING (etablissement_id = mon_etablissement_id());

DROP POLICY IF EXISTS paiements_escrow_select_admin ON paiements_escrow;
CREATE POLICY paiements_escrow_select_admin ON paiements_escrow
  FOR SELECT USING (est_admin());

DROP POLICY IF EXISTS escrow_etat_select_etab ON escrow_etablissement_etat;
CREATE POLICY escrow_etat_select_etab ON escrow_etablissement_etat
  FOR SELECT USING (etablissement_id = mon_etablissement_id() OR est_admin());

DROP POLICY IF EXISTS escrow_exposition_select_admin ON escrow_exposition_releases;
CREATE POLICY escrow_exposition_select_admin ON escrow_exposition_releases
  FOR SELECT USING (est_admin());

DROP POLICY IF EXISTS escrow_release_queue_select_admin ON escrow_release_queue;
CREATE POLICY escrow_release_queue_select_admin ON escrow_release_queue
  FOR SELECT USING (est_admin());

-- ── 4. Fonctions plafond / exposition / gel (A2) ───────────────────────────

CREATE OR REPLACE FUNCTION public.fn_escrow_exposition_courante(p_etablissement_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $esc1$
  SELECT COALESCE(SUM(montant_cents), 0)::integer
  FROM escrow_exposition_releases
  WHERE etablissement_id = p_etablissement_id AND statut = 'ACTIF';
$esc1$;

CREATE OR REPLACE FUNCTION public.fn_escrow_plafond_cents(p_etablissement_id uuid)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $esc2$
DECLARE
  v_sans_incident integer := 0;
BEGIN
  SELECT missions_sans_incident INTO v_sans_incident
  FROM escrow_etablissement_etat
  WHERE etablissement_id = p_etablissement_id;

  IF COALESCE(v_sans_incident, 0) >= public.fn_param_num('escrow_missions_confiance_seuil', 3) THEN
    RETURN public.fn_param_num('escrow_plafond_confiance_cents', 500000)::integer;
  END IF;
  RETURN public.fn_param_num('escrow_plafond_base_cents', 200000)::integer;
END;
$esc2$;

-- Éligibilité ⚡ d'un établissement : pas gelé, et l'exposition courante
-- (+ le montant candidat, au moment du débit PR 3) reste sous le plafond.
-- Appelée par le gating badge (fn_etablissements_safe / fn_obtenir_missions_swipe,
-- redéfinies §6) et par le débit à la confirmation (PR 3).
CREATE OR REPLACE FUNCTION public.fn_escrow_etab_eligible(
  p_etablissement_id uuid,
  p_montant_cents integer DEFAULT 0
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $esc3$
DECLARE
  v_gele boolean := false;
BEGIN
  SELECT gele INTO v_gele
  FROM escrow_etablissement_etat
  WHERE etablissement_id = p_etablissement_id;

  IF COALESCE(v_gele, false) THEN
    RETURN false;
  END IF;

  RETURN public.fn_escrow_exposition_courante(p_etablissement_id)
         + COALESCE(p_montant_cents, 0)
         <= public.fn_escrow_plafond_cents(p_etablissement_id);
END;
$esc3$;

-- Gel au premier incident (dispute ou échec de paiement) — appelé par les
-- handlers webhook (PR 3). Idempotent.
CREATE OR REPLACE FUNCTION public.fn_escrow_geler_etablissement(
  p_etablissement_id uuid,
  p_raison text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $esc4$
BEGIN
  INSERT INTO escrow_etablissement_etat (etablissement_id, gele, gele_le, gele_raison, modifie_le)
  VALUES (p_etablissement_id, true, now(), p_raison, now())
  ON CONFLICT (etablissement_id) DO UPDATE
    SET gele = true,
        gele_le = COALESCE(escrow_etablissement_etat.gele_le, now()),
        gele_raison = EXCLUDED.gele_raison,
        modifie_le = now();

  PERFORM public.fn_ecrire_audit_safe(
    '00000000-0000-0000-0000-000000000000'::uuid, 'SYSTEME',
    'ESCROW_ETAB_GELE', 'etablissement', p_etablissement_id,
    NULL, jsonb_build_object('raison', p_raison), NULL, 'fn_escrow_geler_etablissement'
  );
END;
$esc4$;

-- Déblocage : décision admin manuelle uniquement (A2).
CREATE OR REPLACE FUNCTION public.fn_admin_degeler_escrow_etablissement(p_etablissement_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $esc5$
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADMIN_REQUIS');
  END IF;

  UPDATE escrow_etablissement_etat
  SET gele = false, gele_le = NULL, gele_raison = NULL, modifie_le = now()
  WHERE etablissement_id = p_etablissement_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ETAB_INCONNU_OU_NON_GELE');
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    auth.uid(), 'ADMIN',
    'ESCROW_ETAB_DEGELE', 'etablissement', p_etablissement_id,
    NULL, '{}'::jsonb, NULL, 'fn_admin_degeler_escrow_etablissement'
  );

  RETURN jsonb_build_object('success', true);
END;
$esc5$;

-- Expiration de la fenêtre remboursable (décrément d'exposition) — cron quotidien.
CREATE OR REPLACE FUNCTION public.fn_escrow_expirer_expositions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $esc6$
DECLARE
  v_count integer;
BEGIN
  UPDATE escrow_exposition_releases
  SET statut = 'EXPIRE'
  WHERE statut = 'ACTIF' AND expire_le < now();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$esc6$;

-- ── 5. Release sur validation des présences (trou 5) ──────────────────────
-- Miroir EXACT du gate 7b-B (20260702154526) : une mission est « présences
-- validées » quand plus aucune présence à pointage complet non validée NI
-- contestée ne subsiste. Le trigger n'ÉMET que l'enqueue — la transition
-- DISPONIBLE → RELEASE_PLANIFIE et la double vérification A3 (présences
-- validées ET fonds available) appartiennent au consumer (PR 5).

CREATE OR REPLACE FUNCTION public.fn_trg_escrow_release_check()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $esc7$
DECLARE
  v_escrow_id uuid;
BEGIN
  -- Pas de paiement escrow en séquestre pour cette mission → no-op total
  -- (tout le trafic actuel, flag ⚡ à 0). Antipattern record-NULL évité :
  -- on sélectionne l'id directement.
  SELECT id INTO v_escrow_id
  FROM paiements_escrow
  WHERE mission_id = NEW.mission_id
    AND statut IN ('DEBITE', 'DISPONIBLE');

  IF v_escrow_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Gate 7b-B : une présence bloquante subsiste → pas de release.
  IF EXISTS (
    SELECT 1 FROM presences p
    WHERE p.mission_id = NEW.mission_id
      AND COALESCE(p.valide_par_etablissement, false) = false
      AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL)
  ) THEN
    RETURN NEW;
  END IF;

  INSERT INTO escrow_release_queue (paiement_escrow_id, mission_id)
  VALUES (v_escrow_id, NEW.mission_id)
  ON CONFLICT (paiement_escrow_id) DO NOTHING;

  RETURN NEW;
END;
$esc7$;

DROP TRIGGER IF EXISTS trg_escrow_release_on_validation ON presences;
CREATE TRIGGER trg_escrow_release_on_validation
  AFTER UPDATE OF valide_par_etablissement ON presences
  FOR EACH ROW
  WHEN (NEW.valide_par_etablissement = true
        AND COALESCE(OLD.valide_par_etablissement, false) = false)
  EXECUTE FUNCTION public.fn_trg_escrow_release_check();

-- ── 6. Gating badge ⚡ : brancher l'éligibilité A2 ──────────────────────────
-- Redéfinitions depuis les définitions LIVE prod (pg_get_functiondef du
-- 03/07/2026, vérifiées identiques au repo 20260702161909 + 7d-A2) — règle
-- garde-fous 9.0. Seul ajout : fn_escrow_etab_eligible() dans l'expression
-- paiement_rapide. Un étab gelé ou au plafond n'affiche plus le badge ; ses
-- missions restent publiées en régime standard (A4).

CREATE OR REPLACE FUNCTION public.fn_etablissements_safe(p_ids uuid[])
RETURNS TABLE(id uuid, nom text, adresse_rue text, adresse_code_postal text, adresse_ville text, adresse_departement text, adresse_lat numeric, adresse_lng numeric, type text, finess text, taux_majoration_nuit_pourcent numeric, taux_majoration_dimanche_pourcent numeric, taux_majoration_ferie_pourcent numeric, logo_url text, couleur_theme text, paiement_rapide boolean, jour_paie_habituel smallint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT DISTINCT
        e.id, e.nom::TEXT, e.adresse_rue::TEXT, e.adresse_code_postal::TEXT,
        e.adresse_ville::TEXT, e.adresse_departement::TEXT, e.adresse_lat, e.adresse_lng,
        e.type::TEXT, e.finess::TEXT,
        e.taux_majoration_nuit_pourcent, e.taux_majoration_dimanche_pourcent,
        e.taux_majoration_ferie_pourcent, e.logo_url::TEXT, e.couleur_theme::TEXT,
        -- 7c : capacité ⚡ de l'ÉTABLISSEMENT (flag + SEPA). La condition mission
        -- LIBERAL est appliquée par le consommateur (le régime est une propriété
        -- de la mission, jamais de l'établissement).
        -- 7b-D PR 2 (A2) : + éligibilité escrow (pas gelé, sous plafond).
        (public.fn_param_num('feature_paiement_rapide_actif', 0) = 1
         AND e.mode_paiement_commission = 'SEPA_DEBIT'
         AND e.stripe_sepa_payment_method_id IS NOT NULL
         AND public.fn_escrow_etab_eligible(e.id)) AS paiement_rapide,
        e.jour_paie_habituel
    FROM etablissements e
    WHERE e.id = ANY(p_ids)
      AND (
        EXISTS (SELECT 1 FROM missions m WHERE m.etablissement_id = e.id AND m.soignant_assigne_id = auth.uid())
        OR EXISTS (SELECT 1 FROM missions m WHERE m.etablissement_id = e.id AND m.statut = 'OUVERTE')
        OR e.id = mon_etablissement_id()
        OR est_admin()
      );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_obtenir_missions_swipe(p_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_soignant_id uuid := auth.uid(); v_sg soignants%ROWTYPE; v_missions jsonb;
        v_flag_pr boolean := (public.fn_param_num('feature_paiement_rapide_actif', 0) = 1);
BEGIN
  IF v_soignant_id IS NULL THEN RETURN jsonb_build_object('missions', '[]'::jsonb, 'error', 'auth_required'); END IF;
  SELECT * INTO v_sg FROM soignants WHERE id = v_soignant_id;
  -- 7d-A2 : tri = score + jitter aléatoire 0-12 pts → les meilleures restent
  -- devant, mais 10-15 % de missions à score moyen remontent (exploration).
  SELECT COALESCE(jsonb_agg(payload ORDER BY tri DESC), '[]'::jsonb) INTO v_missions
  FROM (
    SELECT (COALESCE(ms.score_global, 0) + floor(random() * 13))::int AS tri,
      jsonb_build_object(
      'mission_id', m.id, 'intitule', m.intitule, 'profession_requise', m.profession_requise,
      'etablissement_id', m.etablissement_id, 'etablissement_nom', e.nom, 'etablissement_ville', e.adresse_ville,
      'etablissement_code_postal', e.adresse_code_postal, 'etablissement_logo_url', e.logo_url,
      'etablissement_score', e.score_qualite, 'taux_horaire_base', m.taux_horaire_base, 'duree_heures', m.duree_heures,
      'debut_le', m.debut_le, 'fin_le', m.fin_le, 'est_urgente', m.est_urgente, 'service', m.service,
      'type_contrat_applique', m.type_contrat_applique, 'type_contrat_recherche', m.type_contrat_recherche,
      'nb_creneaux', m.nb_creneaux, 'total_brut', m.total_brut, 'net_a_payer', m.net_a_payer,
      'net_estime', m.net_estime, 'montant_ifm', COALESCE(m.montant_ifm, 0), 'montant_icp', COALESCE(m.montant_icp, 0),
      'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0), 'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
      'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0), 'score', COALESCE(ms.score_global, 0),
      'breakdown', COALESCE(ms.breakdown, '{}'::jsonb),
      -- 7b-D PR 2 (A2) : + éligibilité escrow (pas gelé, sous plafond).
      'paiement_rapide', (
        v_flag_pr
        AND m.type_contrat_recherche = 'LIBERAL'
        AND e.mode_paiement_commission = 'SEPA_DEBIT'
        AND e.stripe_sepa_payment_method_id IS NOT NULL
        AND public.fn_escrow_etab_eligible(m.etablissement_id)
      ),
      'distance_km', CASE
        WHEN v_sg.adresse_lat IS NOT NULL AND v_sg.adresse_lng IS NOT NULL
         AND e.adresse_lat IS NOT NULL AND e.adresse_lng IS NOT NULL
        THEN ROUND((fn_haversine_distance_m(v_sg.adresse_lat, v_sg.adresse_lng, e.adresse_lat, e.adresse_lng) / 1000.0)::numeric, 1)
        ELSE NULL END
    ) AS payload
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.matching_scores ms ON ms.mission_id = m.id AND ms.soignant_id = v_soignant_id
     WHERE m.statut = 'OUVERTE'
       AND (m.intitule NOT LIKE '[%' OR v_sg.email LIKE 'playwright-%')
       AND fn_soignant_compatible_mission(
             v_sg.profession, v_sg.specialite_medicale,
             m.profession_requise, m.specialite_medicale_requise, m.accepte_non_specialises)
       AND (m.type_contrat_recherche = 'TOUS' OR v_sg.type_exercice IS NULL OR v_sg.type_exercice = 'MIXTE'
            OR (m.type_contrat_recherche = 'SALARIE' AND v_sg.type_exercice IN ('SALARIE', 'MIXTE'))
            OR (m.type_contrat_recherche = 'LIBERAL' AND v_sg.type_exercice IN ('LIBERAL', 'MIXTE')))
       AND (v_sg.taux_horaire_minimum IS NULL OR m.taux_horaire_base IS NULL
            OR m.taux_horaire_base >= v_sg.taux_horaire_minimum)
       AND m.id NOT IN (SELECT s.mission_id FROM public.swipes s WHERE s.soignant_id = v_soignant_id)
     ORDER BY COALESCE(ms.score_global, 0) DESC, m.est_urgente DESC, m.cree_le DESC
     LIMIT p_limit
  ) t;
  RETURN jsonb_build_object('missions', v_missions);
END;
$function$;

-- ── 7. Cron expiration exposition ──────────────────────────────────────────

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'escrow-expirer-expositions') THEN
    PERFORM cron.schedule('escrow-expirer-expositions', '30 3 * * *',
      'SELECT public.fn_escrow_expirer_expositions()');
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'schedule escrow-expirer-expositions: %', SQLERRM;
END
$do$;

-- ── 8. Durcissement des accès ──────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.fn_escrow_geler_etablissement(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_escrow_expirer_expositions() FROM PUBLIC, anon, authenticated;
