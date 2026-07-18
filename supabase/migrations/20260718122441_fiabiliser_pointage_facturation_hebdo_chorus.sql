-- Correctifs pré-lancement :
-- 1. le temps réellement travaillé provient de tous les créneaux EFFECTIF ;
-- 2. une mission longue peut porter plusieurs factures/paiements hebdomadaires ;
-- 3. chaque facture d'honoraires possède sa facture de commission Jolene.

ALTER TABLE public.factures
  ADD COLUMN IF NOT EXISTS facture_honoraire_id uuid
    REFERENCES public.factures_honoraires(id) ON DELETE RESTRICT;

ALTER TABLE public.stripe_transfers
  ADD COLUMN IF NOT EXISTS facture_honoraire_id uuid
    REFERENCES public.factures_honoraires(id) ON DELETE RESTRICT;

ALTER TABLE public.paiements_soignant
  ADD COLUMN IF NOT EXISTS facture_honoraire_id uuid
    REFERENCES public.factures_honoraires(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_factures_facture_honoraire
  ON public.factures (facture_honoraire_id)
  WHERE facture_honoraire_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stripe_transfers_facture_honoraire
  ON public.stripe_transfers (facture_honoraire_id)
  WHERE facture_honoraire_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_paiements_soignant_facture_honoraire
  ON public.paiements_soignant (facture_honoraire_id)
  WHERE facture_honoraire_id IS NOT NULL;

DROP INDEX IF EXISTS public.uniq_factures_mission_active;
CREATE UNIQUE INDEX uniq_factures_mission_active
  ON public.factures (mission_id)
  WHERE mission_id IS NOT NULL
    AND facture_honoraire_id IS NULL
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION');

CREATE UNIQUE INDEX IF NOT EXISTS uniq_factures_honoraire_active
  ON public.factures (facture_honoraire_id)
  WHERE facture_honoraire_id IS NOT NULL
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION');

COMMENT ON COLUMN public.factures.facture_honoraire_id IS
  'Facture de commission Jolene correspondant exactement à cette facture d''honoraires (hebdomadaire ou finale).';

-- Le trigger historique recalculait heures_reelles avec le seul couple
-- arrivée/départ de presences et écrasait la somme déjà calculée par le scanner.
-- Dès qu'un créneau EFFECTIF existe, il devient la source canonique : les trous
-- entre deux créneaux sont des pauses, y compris après plusieurs reprises.
CREATE OR REPLACE FUNCTION public.dec_calculer_duree_presence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_debut_mission timestamptz;
  v_fin_mission timestamptz;
  v_total_pauses numeric := 0;
  v_effectif_minutes numeric;
  v_effectif_premier timestamptz;
  v_effectif_dernier timestamptz;
  v_effectif_count integer := 0;
BEGIN
  IF NEW.pointage_depart_le IS NOT NULL AND NEW.pointage_arrivee_le IS NOT NULL THEN
    SELECT
      count(*),
      COALESCE(sum(EXTRACT(EPOCH FROM (mc.fin - mc.debut)) / 60.0)
        FILTER (WHERE mc.fin IS NOT NULL AND NOT mc.est_pause), 0),
      min(mc.debut) FILTER (WHERE NOT mc.est_pause),
      max(mc.fin) FILTER (WHERE mc.fin IS NOT NULL AND NOT mc.est_pause)
    INTO v_effectif_count, v_effectif_minutes, v_effectif_premier, v_effectif_dernier
    FROM public.mission_creneaux mc
    WHERE mc.mission_id = NEW.mission_id
      AND mc.type_creneau = 'EFFECTIF';

    IF v_effectif_count > 0 THEN
      NEW.duree_brute_min := round(
        EXTRACT(EPOCH FROM (COALESCE(v_effectif_dernier, NEW.pointage_depart_le)
          - COALESCE(v_effectif_premier, NEW.pointage_arrivee_le))) / 60.0,
        2
      );
      NEW.duree_nette_min := round(GREATEST(v_effectif_minutes, 0), 2);
      NEW.duree_pause_min := round(
        GREATEST(NEW.duree_brute_min - NEW.duree_nette_min, 0),
        2
      );
      NEW.heures_reelles := round(NEW.duree_nette_min / 60.0, 2);
    ELSE
      NEW.duree_brute_min := round(
        EXTRACT(EPOCH FROM (NEW.pointage_depart_le - NEW.pointage_arrivee_le)) / 60.0,
        2
      );
      SELECT COALESCE(sum(
        CASE WHEN pp.fin_le IS NOT NULL
          THEN EXTRACT(EPOCH FROM (pp.fin_le - pp.debut_le)) / 60.0
          ELSE 0 END
      ), 0)
      INTO v_total_pauses
      FROM public.pauses_presence pp
      WHERE pp.presence_id = NEW.id;
      NEW.duree_pause_min := round(v_total_pauses, 2);
      NEW.duree_nette_min := GREATEST(0, NEW.duree_brute_min - NEW.duree_pause_min);
      NEW.heures_reelles := round(NEW.duree_nette_min / 60.0, 2);
    END IF;

    SELECT m.debut_le, m.fin_le
    INTO v_debut_mission, v_fin_mission
    FROM public.missions m
    WHERE m.id = NEW.mission_id;

    NEW.retard_min := CASE
      WHEN v_debut_mission IS NOT NULL AND NEW.pointage_arrivee_le > v_debut_mission
        THEN round(EXTRACT(EPOCH FROM (NEW.pointage_arrivee_le - v_debut_mission)) / 60.0, 2)
      ELSE 0
    END;
    NEW.depart_anticipe_min := CASE
      WHEN v_fin_mission IS NOT NULL AND NEW.pointage_depart_le < v_fin_mission
        THEN round(EXTRACT(EPOCH FROM (v_fin_mission - NEW.pointage_depart_le)) / 60.0, 2)
      ELSE 0
    END;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.dec_calculer_duree_presence() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_calculer_duree_presence() TO service_role;

-- Création idempotente de la facture de commission correspondant à une note
-- d'honoraires. La dernière facture absorbe l'éventuel centime d'arrondi.
CREATE OR REPLACE FUNCTION public.fn_preparer_facture_commission_periode(
  p_facture_honoraire_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fh public.factures_honoraires%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_etab public.etablissements%ROWTYPE;
  v_existing public.factures%ROWTYPE;
  v_total_precedent numeric := 0;
  v_ttc numeric(10,2);
  v_ht numeric(10,2);
  v_tva numeric(10,2);
  v_numero text;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_fh
  FROM public.factures_honoraires
  WHERE id = p_facture_honoraire_id
    AND type_document = 'FACTURE'
    AND statut IN ('EMISE', 'EN_RETARD', 'PAYEE')
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture d''honoraires introuvable ou non payable' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_existing
  FROM public.factures
  WHERE facture_honoraire_id = v_fh.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'facture_id', v_existing.id,
      'numero_facture', v_existing.numero_facture,
      'montant_ttc', v_existing.montant_ttc,
      'existing', true
    );
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = v_fh.mission_id FOR UPDATE;
  SELECT * INTO v_etab FROM public.etablissements WHERE id = v_fh.etablissement_id;
  IF NOT FOUND OR v_mission.id IS NULL OR v_etab.id IS NULL
     OR v_mission.type_contrat_applique <> 'LIBERAL'
     OR v_mission.soignant_assigne_id <> v_fh.soignant_id
     OR v_mission.etablissement_id <> v_fh.etablissement_id
     OR COALESCE(v_mission.net_a_payer, 0) <= 0
     OR COALESCE(v_mission.montant_commission_ttc, 0) <= 0 THEN
    RAISE EXCEPTION 'Mission incohérente pour la facture de commission' USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(sum(f.montant_ttc), 0)
  INTO v_total_precedent
  FROM public.factures f
  WHERE f.mission_id = v_mission.id
    AND f.facture_honoraire_id IS NOT NULL
    AND f.type_document = 'FACTURE'
    AND f.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION');

  IF v_fh.est_facture_finale_mission THEN
    v_ttc := round(GREATEST(v_mission.montant_commission_ttc - v_total_precedent, 0), 2);
  ELSE
    v_ttc := round(
      LEAST(
        v_mission.montant_commission_ttc - v_total_precedent,
        v_mission.montant_commission_ttc * v_fh.montant_ttc / v_mission.net_a_payer
      ),
      2
    );
  END IF;
  IF v_ttc <= 0 THEN
    RAISE EXCEPTION 'Commission de période nulle ou déjà intégralement facturée' USING ERRCODE = '23514';
  END IF;

  v_ht := round(v_ttc / 1.20, 2);
  v_tva := v_ttc - v_ht;
  v_numero := 'JOL-' || to_char(CURRENT_DATE, 'YYYY') || '-H-' || upper(left(replace(v_fh.id::text, '-', ''), 10));

  INSERT INTO public.factures (
    etablissement_id, mission_id, facture_honoraire_id, numero_facture,
    periode_debut, periode_fin, montant_ht, taux_tva, montant_tva, montant_ttc,
    nombre_missions, statut, date_emission, date_echeance,
    est_secteur_public, mode_paiement, chorus_pro_statut, type_document
  ) VALUES (
    v_fh.etablissement_id, v_fh.mission_id, v_fh.id, v_numero,
    v_fh.periode_debut, v_fh.periode_fin, v_ht, 20, v_tva, v_ttc,
    1, 'EMISE', now(), CURRENT_DATE + 30,
    COALESCE(v_etab.est_secteur_public, false),
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'CHORUS_PRO' ELSE 'STRIPE' END,
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'A_DEPOSER' ELSE 'NON_APPLICABLE' END,
    'FACTURE'
  )
  RETURNING * INTO v_existing;

  IF v_fh.est_facture_finale_mission THEN
    UPDATE public.missions
    SET commission_facturee = true,
        facture_id = v_existing.id,
        modifie_le = now()
    WHERE id = v_mission.id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'facture_id', v_existing.id,
    'numero_facture', v_existing.numero_facture,
    'montant_ttc', v_existing.montant_ttc,
    'est_secteur_public', v_existing.est_secteur_public,
    'existing', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_preparer_facture_commission_periode(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_preparer_facture_commission_periode(uuid)
  TO service_role;

-- Un paiement hebdomadaire revendique sa facture de commission, pas la mission
-- entière : les semaines suivantes doivent rester payables indépendamment.
ALTER TABLE public.stripe_payment_flow_claims
  DROP CONSTRAINT IF EXISTS stripe_payment_flow_claims_flow_check;
ALTER TABLE public.stripe_payment_flow_claims
  ADD CONSTRAINT stripe_payment_flow_claims_flow_check
  CHECK (flow IN (
    'CHECKOUT_INVOICE', 'SEPA_INVOICE', 'CONNECT_MISSION',
    'CONNECT_INVOICE', 'LEGACY_UNKNOWN'
  ));

CREATE OR REPLACE FUNCTION public.fn_stripe_payment_flow_claim(
  p_flow text,
  p_owner_token text,
  p_facture_id uuid DEFAULT NULL,
  p_mission_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_resources text[];
  v_resource text;
  v_conflict public.stripe_payment_flow_claims%ROWTYPE;
  v_session_ids text[];
  v_intent_ids text[];
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  IF p_flow NOT IN ('CHECKOUT_INVOICE', 'SEPA_INVOICE', 'CONNECT_MISSION', 'CONNECT_INVOICE')
     OR NULLIF(btrim(p_owner_token), '') IS NULL
     OR ((p_facture_id IS NULL) = (p_mission_id IS NULL)) THEN
    RAISE EXCEPTION 'Paramètres de claim Stripe invalides' USING ERRCODE = '22023';
  END IF;

  IF p_facture_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.factures f
      WHERE f.id = p_facture_id
        AND f.type_document = 'FACTURE'
        AND f.statut <> 'ANNULEE'
    ) THEN
      RAISE EXCEPTION 'Facture de claim introuvable ou non payable' USING ERRCODE = 'P0002';
    END IF;
    IF p_flow = 'CONNECT_INVOICE' THEN
      v_resources := ARRAY['FACTURE:' || p_facture_id::text];
    ELSE
      SELECT array_agg(DISTINCT r.resource_key ORDER BY r.resource_key)
      INTO v_resources
      FROM (
        SELECT 'FACTURE:' || p_facture_id::text AS resource_key
        UNION ALL
        SELECT 'MISSION:' || f.mission_id::text
        FROM public.factures f
        WHERE f.id = p_facture_id AND f.mission_id IS NOT NULL
        UNION ALL
        SELECT 'MISSION:' || m.id::text
        FROM public.missions m
        WHERE m.facture_id = p_facture_id
      ) r;
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.missions m WHERE m.id = p_mission_id) THEN
      RAISE EXCEPTION 'Mission de claim introuvable' USING ERRCODE = 'P0002';
    END IF;
    v_resources := ARRAY['MISSION:' || p_mission_id::text];
  END IF;

  FOREACH v_resource IN ARRAY v_resources LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(v_resource, 0));
  END LOOP;

  SELECT c.* INTO v_conflict
  FROM public.stripe_payment_flow_claims c
  WHERE c.resource_key = ANY(v_resources)
    AND (c.flow <> p_flow OR c.owner_token <> p_owner_token)
  ORDER BY c.resource_key
  LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'acquired', false,
      'flow', v_conflict.flow,
      'owner_token', v_conflict.owner_token,
      'resources', v_resources,
      'stripe_checkout_session_id', v_conflict.stripe_checkout_session_id,
      'stripe_payment_intent_id', v_conflict.stripe_payment_intent_id
    );
  END IF;

  INSERT INTO public.stripe_payment_flow_claims (resource_key, flow, owner_token)
  SELECT r.resource_key, p_flow, p_owner_token
  FROM unnest(v_resources) AS r(resource_key)
  ON CONFLICT (resource_key) DO NOTHING;

  SELECT
    array_agg(DISTINCT c.stripe_checkout_session_id)
      FILTER (WHERE c.stripe_checkout_session_id IS NOT NULL),
    array_agg(DISTINCT c.stripe_payment_intent_id)
      FILTER (WHERE c.stripe_payment_intent_id IS NOT NULL)
  INTO v_session_ids, v_intent_ids
  FROM public.stripe_payment_flow_claims c
  WHERE c.resource_key = ANY(v_resources)
    AND c.flow = p_flow
    AND c.owner_token = p_owner_token;

  IF COALESCE(array_length(v_session_ids, 1), 0) > 1
     OR COALESCE(array_length(v_intent_ids, 1), 0) > 1 THEN
    RAISE EXCEPTION 'Claims Stripe du même flux incohérents' USING ERRCODE = '23514';
  END IF;
  IF COALESCE(array_length(v_session_ids, 1), 0) = 1 THEN
    UPDATE public.stripe_payment_flow_claims c
    SET stripe_checkout_session_id = v_session_ids[1], modifie_le = now()
    WHERE c.resource_key = ANY(v_resources)
      AND c.flow = p_flow
      AND c.owner_token = p_owner_token
      AND c.stripe_checkout_session_id IS NULL;
  END IF;
  IF COALESCE(array_length(v_intent_ids, 1), 0) = 1 THEN
    UPDATE public.stripe_payment_flow_claims c
    SET stripe_payment_intent_id = v_intent_ids[1], modifie_le = now()
    WHERE c.resource_key = ANY(v_resources)
      AND c.flow = p_flow
      AND c.owner_token = p_owner_token
      AND c.stripe_payment_intent_id IS NULL;
  END IF;

  RETURN jsonb_build_object(
    'acquired', true,
    'flow', p_flow,
    'owner_token', p_owner_token,
    'resources', v_resources,
    'stripe_checkout_session_id', v_session_ids[1],
    'stripe_payment_intent_id', v_intent_ids[1]
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_stripe_payment_flow_claim(text, text, uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_stripe_payment_flow_claim(text, text, uuid, uuid)
  TO service_role;

-- Rapprochement atomique d'un paiement Connect portant sur une facture exacte.
-- Contrairement à l'ancien RPC mission-level, EN_COURS est valide pour une
-- semaine close et seules les deux factures concernées passent à PAYEE.
CREATE OR REPLACE FUNCTION public.fn_stripe_connect_rapprocher_facture(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_etablissement_id uuid,
  p_facture_honoraires_id uuid,
  p_facture_commission_id uuid,
  p_stripe_checkout_session_id text,
  p_stripe_payment_intent_id text,
  p_stripe_charge_id text,
  p_stripe_transfer_id text,
  p_montant_soignant_cts integer,
  p_montant_commission_cts integer,
  p_montant_total_cts integer,
  p_rapproche_le timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_fh public.factures_honoraires%ROWTYPE;
  v_commission public.factures%ROWTYPE;
  v_transfer public.stripe_transfers%ROWTYPE;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  IF p_montant_soignant_cts <= 0
     OR p_montant_commission_cts <= 0
     OR p_montant_total_cts <> p_montant_soignant_cts + p_montant_commission_cts
     OR NULLIF(p_stripe_checkout_session_id, '') IS NULL
     OR NULLIF(p_stripe_payment_intent_id, '') IS NULL
     OR NULLIF(p_stripe_charge_id, '') IS NULL
     OR NULLIF(p_stripe_transfer_id, '') IS NULL THEN
    RAISE EXCEPTION 'Paramètres de rapprochement invalides' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id FOR UPDATE;
  SELECT * INTO v_fh FROM public.factures_honoraires WHERE id = p_facture_honoraires_id FOR UPDATE;
  SELECT * INTO v_commission FROM public.factures WHERE id = p_facture_commission_id FOR UPDATE;
  SELECT * INTO v_transfer
  FROM public.stripe_transfers
  WHERE mission_id = p_mission_id
    AND facture_honoraire_id = p_facture_honoraires_id
    AND stripe_checkout_session_id = p_stripe_checkout_session_id
  FOR UPDATE;

  IF v_mission.id IS NULL
     OR v_mission.statut NOT IN ('EN_COURS', 'TERMINEE')
     OR v_mission.type_contrat_applique <> 'LIBERAL'
     OR v_mission.soignant_assigne_id <> p_soignant_id
     OR v_mission.etablissement_id <> p_etablissement_id
     OR v_fh.id IS NULL
     OR v_fh.mission_id <> p_mission_id
     OR v_fh.soignant_id <> p_soignant_id
     OR v_fh.etablissement_id <> p_etablissement_id
     OR v_fh.statut NOT IN ('EMISE', 'EN_RETARD', 'PAYEE')
     OR round(v_fh.montant_ttc * 100)::integer <> p_montant_soignant_cts
     OR v_commission.id IS NULL
     OR v_commission.facture_honoraire_id <> v_fh.id
     OR v_commission.mission_id <> p_mission_id
     OR v_commission.etablissement_id <> p_etablissement_id
     OR v_commission.statut NOT IN ('EMISE', 'EN_RETARD', 'PAYEE')
     OR round(v_commission.montant_ttc * 100)::integer <> p_montant_commission_cts
     OR v_transfer.id IS NULL
     OR v_transfer.statut NOT IN ('TRANSFERE', 'CHARGE_REUSSI', 'PAYE')
     OR v_transfer.stripe_payment_intent_id <> p_stripe_payment_intent_id
     OR v_transfer.stripe_transfer_id <> p_stripe_transfer_id
     OR (v_transfer.stripe_charge_id IS NOT NULL AND v_transfer.stripe_charge_id <> p_stripe_charge_id)
     OR round(v_transfer.montant_soignant * 100)::integer <> p_montant_soignant_cts
     OR round(v_transfer.montant_commission * 100)::integer <> p_montant_commission_cts
     OR round(v_transfer.montant_total * 100)::integer <> p_montant_total_cts THEN
    RAISE EXCEPTION 'Identité du rapprochement Connect incohérente' USING ERRCODE = '23514';
  END IF;
  IF v_mission.statut = 'EN_COURS'
     AND (v_fh.est_facture_finale_mission OR v_fh.periode_fin >= CURRENT_DATE) THEN
    RAISE EXCEPTION 'Période hebdomadaire non close' USING ERRCODE = '23514';
  END IF;

  UPDATE public.stripe_transfers
  SET statut = 'TRANSFERE',
      stripe_charge_id = p_stripe_charge_id,
      transfere_le = COALESCE(transfere_le, p_rapproche_le),
      erreur = NULL
  WHERE id = v_transfer.id;

  INSERT INTO public.paiements_soignant (
    mission_id, facture_honoraire_id, soignant_id, etablissement_id,
    montant_net, methode, reference_virement, date_paiement, statut,
    confirme_par_etablissement, confirme_par_etablissement_le,
    confirme_par_soignant, confirme_par_soignant_le, stripe_transfer_id
  ) VALUES (
    p_mission_id, v_fh.id, p_soignant_id, p_etablissement_id,
    p_montant_soignant_cts::numeric / 100, 'NOTE_HONORAIRES',
    'STRIPE-' || p_stripe_transfer_id, p_rapproche_le::date, 'CONFIRME',
    true, p_rapproche_le, true, p_rapproche_le, p_stripe_transfer_id
  )
  ON CONFLICT (stripe_transfer_id) WHERE stripe_transfer_id IS NOT NULL
  DO NOTHING;

  UPDATE public.factures_honoraires
  SET statut = 'PAYEE',
      date_paiement = p_rapproche_le::date,
      stripe_payment_intent_id = p_stripe_payment_intent_id,
      modifie_le = now()
  WHERE id = v_fh.id
    AND (stripe_payment_intent_id IS NULL OR stripe_payment_intent_id = p_stripe_payment_intent_id);

  UPDATE public.factures
  SET statut = 'PAYEE',
      date_paiement = p_rapproche_le,
      stripe_payment_intent_id = p_stripe_payment_intent_id,
      mode_paiement = 'STRIPE',
      modifie_le = now()
  WHERE id = v_commission.id
    AND (stripe_payment_intent_id IS NULL OR stripe_payment_intent_id = p_stripe_payment_intent_id);

  UPDATE public.missions
  SET mode_paiement_soignant = 'STRIPE_CONNECT',
      commission_facturee = commission_facturee OR v_fh.est_facture_finale_mission,
      facture_id = CASE WHEN v_fh.est_facture_finale_mission THEN v_commission.id ELSE facture_id END,
      modifie_le = now()
  WHERE id = p_mission_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details, navigateur_acteur
  ) VALUES (
    p_soignant_id, 'SYSTEME', 'FINANCE_TRANSFER_CONNECT', 'facture_honoraires', v_fh.id,
    jsonb_build_object(
      'mission_id', p_mission_id,
      'stripe_transfer_id', p_stripe_transfer_id,
      'stripe_charge_id', p_stripe_charge_id,
      'stripe_payment_intent_id', p_stripe_payment_intent_id,
      'stripe_session_id', p_stripe_checkout_session_id,
      'facture_commission_id', v_commission.id,
      'montant_cents', p_montant_soignant_cts,
      'evenement', 'CONNECT_FACTURE_RAPPROCHEMENT_ATOMIQUE'
    ),
    'fn_stripe_connect_rapprocher_facture'
  );

  RETURN jsonb_build_object(
    'success', true,
    'stripe_transfer_id', p_stripe_transfer_id,
    'facture_honoraires_id', v_fh.id,
    'facture_commission_id', v_commission.id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_stripe_connect_rapprocher_facture(
  uuid, uuid, uuid, uuid, uuid,
  text, text, text, text,
  integer, integer, integer, timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_stripe_connect_rapprocher_facture(
  uuid, uuid, uuid, uuid, uuid,
  text, text, text, text,
  integer, integer, integer, timestamptz
) TO service_role;

-- Le cockpit établissement raisonne désormais par facture pour le libéral et
-- conserve une ligne mission pour le salarié. Une mission longue peut ainsi
-- afficher S1 payée et S2 encore due sans disparaître entièrement.
CREATE OR REPLACE FUNCTION public.fn_obligations_financieres()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_etab_id uuid := mon_etablissement_id();
  v_total_soignants_du numeric := 0;
  v_total_commissions_du numeric := 0;
  v_lignes jsonb := '[]'::jsonb;
BEGIN
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Etablissement introuvable');
  END IF;

  WITH obligations AS (
    SELECT
      ('facture:' || fh.id::text) AS payment_key,
      m.id::text AS mission_id,
      fh.id::text AS facture_honoraires_id,
      m.intitule,
      m.debut_le,
      m.fin_le,
      fh.periode_debut,
      fh.periode_fin,
      fh.est_facture_finale_mission,
      fh.montant_ttc AS total_brut,
      fh.montant_ttc AS net_a_payer,
      COALESCE(fc.montant_ttc, 0) AS montant_commission_ttc,
      m.soignant_assigne_id::text AS soignant_id,
      GREATEST(0, EXTRACT(EPOCH FROM (
        LEAST(m.fin_le, (fh.periode_fin + 1)::timestamptz)
        - GREATEST(m.debut_le, fh.periode_debut::timestamptz)
      )) / 3600) AS heures,
      (CURRENT_DATE - fh.periode_fin)::integer AS jours_depuis_fin,
      COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
      s.profession::text AS soignant_profession,
      s.type_exercice AS soignant_type_exercice,
      m.type_contrat_applique::text AS type_contrat_applique,
      m.type_paiement_soignant AS type_paiement_soignant,
      COALESCE(m.mode_paiement_soignant, 'STRIPE_CONNECT') AS mode_paiement_soignant,
      (s.stripe_account_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.stripe_connect_onboarding sco
        WHERE sco.soignant_id = s.id
          AND sco.charges_enabled = true
          AND sco.payouts_enabled = true
      )) AS soignant_stripe_connect,
      EXISTS (
        SELECT 1 FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut = 'CONTESTE'
      ) AS a_paiement_conteste,
      (
        SELECT p.id::text FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut = 'CONTESTE'
        ORDER BY p.cree_le DESC LIMIT 1
      ) AS paiement_conteste_id,
      fh.periode_fin::timestamptz AS ordre_fin
    FROM public.factures_honoraires fh
    JOIN public.missions m ON m.id = fh.mission_id
    JOIN public.soignants s ON s.id = fh.soignant_id
    LEFT JOIN public.factures fc
      ON fc.facture_honoraire_id = fh.id
     AND fc.type_document = 'FACTURE'
     AND fc.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
    WHERE fh.etablissement_id = v_etab_id
      AND fh.type_document = 'FACTURE'
      AND fh.statut IN ('EMISE', 'EN_RETARD')
      AND m.type_contrat_applique = 'LIBERAL'
      AND m.statut IN ('EN_COURS', 'TERMINEE')
      AND (m.statut = 'TERMINEE' OR (NOT fh.est_facture_finale_mission AND fh.periode_fin < CURRENT_DATE))
      AND NOT EXISTS (
        SELECT 1 FROM public.paiements_soignant p
        WHERE p.facture_honoraire_id = fh.id
          AND p.statut IN ('DECLARE', 'CONFIRME', 'RESOLU')
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.stripe_transfers st
        WHERE st.facture_honoraire_id = fh.id
          AND st.statut IN ('TRANSFERE', 'CHARGE_REUSSI', 'PAYE')
      )

    UNION ALL

    SELECT
      ('mission:' || m.id::text), m.id::text, NULL::text, m.intitule,
      m.debut_le, m.fin_le, m.debut_le::date, m.fin_le::date, true,
      m.total_brut, m.net_a_payer, m.montant_commission_ttc,
      m.soignant_assigne_id::text,
      EXTRACT(EPOCH FROM (m.fin_le - m.debut_le)) / 3600,
      EXTRACT(DAY FROM now() - m.fin_le)::integer,
      COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, ''),
      s.profession::text, s.type_exercice,
      m.type_contrat_applique::text, m.type_paiement_soignant,
      m.mode_paiement_soignant, false,
      EXISTS (
        SELECT 1 FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut = 'CONTESTE'
      ),
      (
        SELECT p.id::text FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut = 'CONTESTE'
        ORDER BY p.cree_le DESC LIMIT 1
      ),
      m.fin_le
    FROM public.missions m
    JOIN public.soignants s ON s.id = m.soignant_assigne_id
    WHERE m.etablissement_id = v_etab_id
      AND m.statut = 'TERMINEE'
      AND m.type_contrat_applique = 'SALARIE'
      AND NOT EXISTS (
        SELECT 1 FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut IN ('DECLARE', 'CONFIRME', 'RESOLU')
      )
  )
  SELECT
    COALESCE(sum(o.net_a_payer), 0),
    COALESCE(jsonb_agg(to_jsonb(o) - 'ordre_fin' ORDER BY o.ordre_fin), '[]'::jsonb)
  INTO v_total_soignants_du, v_lignes
  FROM obligations o;

  SELECT COALESCE(sum(f.montant_ttc), 0)
  INTO v_total_commissions_du
  FROM public.factures f
  WHERE f.etablissement_id = v_etab_id
    AND f.statut IN ('EMISE', 'EN_RETARD');

  RETURN jsonb_build_object(
    'total_du', v_total_soignants_du + v_total_commissions_du,
    'total_soignants_du', v_total_soignants_du,
    'total_commissions_du', v_total_commissions_du,
    'nb_missions_non_payees', jsonb_array_length(v_lignes),
    'nb_paiements_en_attente', (
      SELECT count(*) FROM public.paiements_soignant
      WHERE etablissement_id = v_etab_id AND statut = 'DECLARE'
    ),
    'nb_factures_impayees', (
      SELECT count(*) FROM public.factures
      WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD')
    ),
    'nb_factures_commission_historique', (
      SELECT count(*) FROM public.factures
      WHERE etablissement_id = v_etab_id AND statut IN ('PAYEE', 'ANNULEE')
    ),
    'missions_non_payees', v_lignes,
    'paiements_soignants_en_attente', COALESCE((
      SELECT jsonb_agg(row_to_json(x)) FROM (
        SELECT p.id::text AS paiement_id, p.mission_id::text, p.montant_net,
          p.methode, p.reference_virement, p.date_paiement, p.statut,
          m.intitule AS mission_intitule,
          COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
          s.profession::text AS soignant_profession,
          COALESCE(p.facture_honoraire_id::text, (
            SELECT fh.id::text FROM public.factures_honoraires fh
            WHERE fh.mission_id = m.id ORDER BY fh.date_emission DESC LIMIT 1
          )) AS facture_honoraires_id
        FROM public.paiements_soignant p
        JOIN public.missions m ON m.id = p.mission_id
        JOIN public.soignants s ON s.id = p.soignant_id
        WHERE p.etablissement_id = v_etab_id AND p.statut = 'DECLARE'
        ORDER BY p.date_paiement DESC
      ) x
    ), '[]'::jsonb),
    'paiements_soignants_confirmes', COALESCE((
      SELECT jsonb_agg(row_to_json(x)) FROM (
        SELECT p.id::text AS paiement_id, p.mission_id::text, p.montant_net,
          p.methode, p.reference_virement, p.date_paiement,
          p.confirme_par_soignant_le, m.intitule AS mission_intitule,
          COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
          p.facture_honoraire_id::text AS facture_honoraires_id
        FROM public.paiements_soignant p
        JOIN public.missions m ON m.id = p.mission_id
        JOIN public.soignants s ON s.id = p.soignant_id
        WHERE p.etablissement_id = v_etab_id AND p.statut = 'CONFIRME'
        ORDER BY p.confirme_par_soignant_le DESC LIMIT 10
      ) x
    ), '[]'::jsonb),
    'factures_impayees', COALESCE((
      SELECT jsonb_agg(row_to_json(x)) FROM (
        SELECT f.id::text AS facture_id, f.numero_facture, f.montant_ht,
          f.montant_tva, f.montant_ttc, f.nombre_missions, f.date_echeance,
          f.statut, f.stripe_hosted_url, f.est_secteur_public,
          f.chorus_pro_statut, f.chorus_pro_numero_flux
        FROM public.factures f
        WHERE f.etablissement_id = v_etab_id
          AND f.statut IN ('EMISE', 'EN_RETARD', 'VIREMENT_DECLARE')
        ORDER BY f.date_echeance
      ) x
    ), '[]'::jsonb),
    'factures_commission_historique', COALESCE((
      SELECT jsonb_agg(row_to_json(x)) FROM (
        SELECT f.id::text AS facture_id, f.numero_facture, f.statut,
          f.montant_ttc, f.nombre_missions, f.date_emission, f.date_paiement,
          f.mode_paiement, f.virement_reference, f.stripe_payment_intent_id,
          f.mission_id::text AS mission_id, f.facture_honoraire_id::text,
          f.est_secteur_public, f.chorus_pro_statut
        FROM public.factures f
        WHERE f.etablissement_id = v_etab_id AND f.statut IN ('PAYEE', 'ANNULEE')
        ORDER BY f.date_paiement DESC NULLS LAST, f.date_emission DESC LIMIT 10
      ) x
    ), '[]'::jsonb),
    'missions_non_facturees', '[]'::jsonb
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_obligations_financieres() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_obligations_financieres() TO authenticated, service_role;
