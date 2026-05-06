-- ============================================================
-- CP6 — Anti-seed triggers (factures_honoraires + missions)
-- ============================================================
-- Objectif : empêcher les INSERT directs de données de test
--            contournant generate-invoice / fn_creer_mission.
--
-- Bypass autorisés :
--   1. `jolene.generate_invoice_context = 'true'` (edge function)
--   2. `jolene.creer_mission_context = 'true'`    (RPC fn_creer_mission)
--   3. `jolene.admin_seed_override_reason` IS NOT NULL → audit + pass
--
-- Sinon vérification de cohérence :
--   factures_honoraires : |montant_ht - mission.net_a_payer| <= 0.50€
--   missions            : |total_brut - (taux × duree × (1 + majorations))| <= 1€
--                         |net_a_payer - (total_brut - commission)|         <= 1€
--
-- Cas passe sans bypass :
--   - missions : total_brut IS NULL AND net_a_payer IS NULL (sync trigger
--     les populera depuis mission_creneaux).
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 1. Extension journaux_audit.action pour OVERRIDE_ANTI_SEED
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
  'DEGEL_APPLIED','OVERRIDE_CHAMP_POST_GEL','GEL_APPLIED',
  'OVERRIDE_ANTI_SEED'
]));

-- ──────────────────────────────────────────────────────────────
-- 2. fn_anti_seed_facture_honoraire
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_anti_seed_facture_honoraire()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_mission_net numeric;
  v_ecart numeric;
  v_ctx text;
  v_admin_reason text;
BEGIN
  -- Bypass 1 : edge function generate-invoice (wrap RPC)
  v_ctx := NULLIF(current_setting('jolene.generate_invoice_context', true), '');
  IF v_ctx = 'true' THEN
    RETURN NEW;
  END IF;

  -- Bypass 2 : admin override avec raison → audit + pass
  v_admin_reason := NULLIF(current_setting('jolene.admin_seed_override_reason', true), '');
  IF v_admin_reason IS NOT NULL THEN
    INSERT INTO journaux_audit
      (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
      auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_ANTI_SEED',
      'factures_honoraires', NEW.id,
      jsonb_build_object(
        'reason', v_admin_reason,
        'mission_id', NEW.mission_id,
        'montant_ht', NEW.montant_ht,
        'numero_facture', NEW.numero_facture
      )
    );
    RETURN NEW;
  END IF;

  -- Vérification cohérence : montant_ht ≈ mission.net_a_payer
  SELECT net_a_payer INTO v_mission_net
  FROM missions WHERE id = NEW.mission_id;

  IF v_mission_net IS NULL THEN
    RAISE EXCEPTION 'anti-seed facture: mission % sans snapshot financier (net_a_payer=NULL). Utilisez generate-invoice ou définissez jolene.admin_seed_override_reason.',
      NEW.mission_id USING ERRCODE = 'check_violation';
  END IF;

  v_ecart := ABS(COALESCE(NEW.montant_ht, 0) - v_mission_net);
  IF v_ecart > 0.50 THEN
    RAISE EXCEPTION 'anti-seed facture: montant_ht % incoherent avec mission.net_a_payer % (ecart=%€ > 0.50€). Utilisez generate-invoice ou jolene.admin_seed_override_reason.',
      NEW.montant_ht, v_mission_net, v_ecart
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_anti_seed_facture_honoraire ON public.factures_honoraires;
CREATE TRIGGER trg_anti_seed_facture_honoraire
  BEFORE INSERT ON public.factures_honoraires
  FOR EACH ROW EXECUTE FUNCTION public.fn_anti_seed_facture_honoraire();

-- ──────────────────────────────────────────────────────────────
-- 3. fn_anti_seed_mission
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_anti_seed_mission()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_ctx text;
  v_admin_reason text;
  v_expected_brut numeric;
  v_expected_net numeric;
  v_ecart_brut numeric;
  v_ecart_net numeric;
  v_taux_commission numeric;
BEGIN
  -- Bypass 1 : RPC fn_creer_mission
  v_ctx := NULLIF(current_setting('jolene.creer_mission_context', true), '');
  IF v_ctx = 'true' THEN
    RETURN NEW;
  END IF;

  -- Bypass 2 : admin override avec raison → audit + pass
  v_admin_reason := NULLIF(current_setting('jolene.admin_seed_override_reason', true), '');
  IF v_admin_reason IS NOT NULL THEN
    INSERT INTO journaux_audit
      (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
      auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_ANTI_SEED',
      'missions', NEW.id,
      jsonb_build_object(
        'reason', v_admin_reason,
        'intitule', NEW.intitule,
        'etablissement_id', NEW.etablissement_id,
        'total_brut', NEW.total_brut,
        'net_a_payer', NEW.net_a_payer
      )
    );
    RETURN NEW;
  END IF;

  -- Path normal : total_brut et net_a_payer seront peuplés par le sync
  -- trigger depuis mission_creneaux. On autorise NULL à l'INSERT.
  IF NEW.total_brut IS NULL AND NEW.net_a_payer IS NULL THEN
    RETURN NEW;
  END IF;

  -- Seed direct : total_brut/net_a_payer posés sans duree → incohérent
  IF NEW.duree_heures IS NULL OR NEW.taux_horaire_base IS NULL THEN
    RAISE EXCEPTION 'anti-seed mission: total_brut/net_a_payer posés sans duree_heures ni taux_horaire_base. Utilisez fn_creer_mission ou jolene.admin_seed_override_reason.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Estimation : taux × duree (majorations inconnues à l'INSERT, tolérance 1€)
  v_expected_brut := NEW.taux_horaire_base * NEW.duree_heures;
  v_taux_commission := COALESCE(NEW.taux_commission, 0);
  v_expected_net := v_expected_brut * (1 - v_taux_commission);

  v_ecart_brut := ABS(COALESCE(NEW.total_brut, 0) - v_expected_brut);
  v_ecart_net  := ABS(COALESCE(NEW.net_a_payer, 0) - v_expected_net);

  -- Tolérance 1€ sur chaque montant (majorations nuit/we ignorées → marge)
  IF v_ecart_brut > 1 THEN
    RAISE EXCEPTION 'anti-seed mission: total_brut % incoherent avec taux×duree=% (ecart=%€ > 1€). Utilisez fn_creer_mission ou jolene.admin_seed_override_reason.',
      NEW.total_brut, v_expected_brut, v_ecart_brut
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_ecart_net > 1 THEN
    RAISE EXCEPTION 'anti-seed mission: net_a_payer % incoherent avec brut×(1-commission)=% (ecart=%€ > 1€). Utilisez fn_creer_mission ou jolene.admin_seed_override_reason.',
      NEW.net_a_payer, v_expected_net, v_ecart_net
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_anti_seed_mission ON public.missions;
CREATE TRIGGER trg_anti_seed_mission
  BEFORE INSERT ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.fn_anti_seed_mission();

-- ──────────────────────────────────────────────────────────────
-- 4. fn_creer_mission : signal bypass via set_config
-- ──────────────────────────────────────────────────────────────
-- On modifie fn_creer_mission pour poser jolene.creer_mission_context
-- avant l'INSERT (transaction-local).
CREATE OR REPLACE FUNCTION public.fn_creer_mission(
  p_intitule text,
  p_description text DEFAULT NULL,
  p_profession_requise type_profession DEFAULT NULL,
  p_service text DEFAULT NULL,
  p_debut_le timestamptz DEFAULT NULL,
  p_fin_le timestamptz DEFAULT NULL,
  p_taux_horaire_base numeric DEFAULT NULL,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0,
  p_mode_attribution text DEFAULT 'PREMIER_ARRIVE'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_etablissement_id uuid;
  v_factures_impayees integer;
  v_mission_id uuid;
  v_mode text;
BEGIN
  v_etablissement_id := mon_etablissement_id();
  IF v_etablissement_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement non trouvé.');
  END IF;

  IF p_intitule IS NULL OR p_profession_requise IS NULL OR p_debut_le IS NULL OR p_fin_le IS NULL OR p_taux_horaire_base IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Champs obligatoires manquants.');
  END IF;

  IF p_fin_le <= p_debut_le THEN
    RETURN jsonb_build_object('success', false, 'error', 'La fin doit être après le début.');
  END IF;
  IF p_debut_le < now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'La mission ne peut pas commencer dans le passé.');
  END IF;

  SELECT count(*) INTO v_factures_impayees
  FROM factures
  WHERE etablissement_id = v_etablissement_id
    AND statut IN ('EMISE', 'EN_RETARD')
    AND date_echeance < CURRENT_DATE;

  IF v_factures_impayees > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous avez des factures impayées. Veuillez régulariser avant de publier.');
  END IF;

  v_mode := COALESCE(p_mode_attribution, 'PREMIER_ARRIVE');
  IF v_mode NOT IN ('PREMIER_ARRIVE', 'CANDIDATURE') THEN
    v_mode := 'PREMIER_ARRIVE';
  END IF;

  -- CP6 anti-seed : signal bypass pour fn_anti_seed_mission
  PERFORM set_config('jolene.creer_mission_context', 'true', true);

  INSERT INTO missions (
    etablissement_id, intitule, description, profession_requise, service,
    debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence, mode_attribution
  ) VALUES (
    v_etablissement_id, p_intitule, p_description, p_profession_requise, p_service,
    p_debut_le, p_fin_le, p_taux_horaire_base, p_est_urgente, CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END,
    v_mode
  )
  RETURNING id INTO v_mission_id;

  RETURN jsonb_build_object('success', true, 'mission_id', v_mission_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

-- ──────────────────────────────────────────────────────────────
-- 4b. fn_creer_mission — overload avec p_serie_id (signal bypass)
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_creer_mission(
  p_intitule text,
  p_description text DEFAULT NULL,
  p_profession_requise type_profession DEFAULT NULL,
  p_service text DEFAULT NULL,
  p_debut_le timestamptz DEFAULT NULL,
  p_fin_le timestamptz DEFAULT NULL,
  p_taux_horaire_base numeric DEFAULT NULL,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0,
  p_serie_id uuid DEFAULT NULL,
  p_mode_attribution text DEFAULT 'PREMIER_ARRIVE'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
    v_etab_id UUID;
    v_etab RECORD;
    v_mission_id UUID;
    v_mode TEXT;
BEGIN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;

    SELECT peut_publier_missions, statut_verification, contrat_valide
    INTO v_etab FROM etablissements WHERE id = v_etab_id;

    IF NOT est_admin() AND (v_etab.peut_publier_missions IS NOT TRUE) THEN
        IF v_etab.statut_verification = 'EN_ATTENTE' THEN
            RETURN '{"error":"Votre établissement est en attente de vérification. Vous pourrez publier des missions une fois vérifié."}'::JSONB;
        ELSIF v_etab.statut_verification = 'REJETE' THEN
            RETURN '{"error":"Votre établissement a été rejeté. Contactez support@jolene.app."}'::JSONB;
        ELSIF v_etab.statut_verification = 'SUSPENDU' THEN
            RETURN '{"error":"Votre compte est suspendu."}'::JSONB;
        ELSE
            RETURN '{"error":"Votre établissement doit être vérifié avant de publier des missions."}'::JSONB;
        END IF;
    END IF;

    IF NOT est_admin() AND (v_etab.contrat_valide IS NOT TRUE) THEN
        RETURN '{"error":"Votre contrat de service Jolene doit être validé avant de publier des missions."}'::JSONB;
    END IF;

    IF p_intitule IS NULL OR p_profession_requise IS NULL OR p_debut_le IS NULL OR p_fin_le IS NULL OR p_taux_horaire_base IS NULL THEN
        RETURN '{"error":"Champs obligatoires manquants."}'::JSONB;
    END IF;
    IF p_fin_le <= p_debut_le THEN
        RETURN '{"error":"La fin doit être après le début."}'::JSONB;
    END IF;
    IF p_debut_le < NOW() AND NOT est_admin() THEN
        RETURN '{"error":"La mission ne peut pas commencer dans le passé."}'::JSONB;
    END IF;

    IF EXISTS (
        SELECT 1 FROM factures
        WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD')
          AND date_echeance < CURRENT_DATE
    ) AND NOT est_admin() THEN
        RETURN '{"error":"Vous avez des factures impayées. Veuillez régulariser."}'::JSONB;
    END IF;

    v_mode := COALESCE(p_mode_attribution, 'PREMIER_ARRIVE');
    IF v_mode NOT IN ('PREMIER_ARRIVE', 'CANDIDATURE') THEN
        v_mode := 'PREMIER_ARRIVE';
    END IF;

    -- CP6 anti-seed : signal bypass pour fn_anti_seed_mission
    PERFORM set_config('jolene.creer_mission_context', 'true', true);

    INSERT INTO missions (
        etablissement_id, intitule, description,
        profession_requise, service, debut_le, fin_le,
        taux_horaire_base, est_urgente, niveau_urgence,
        serie_id, mode_attribution
    ) VALUES (
        v_etab_id, p_intitule, p_description,
        p_profession_requise, p_service, p_debut_le, p_fin_le,
        p_taux_horaire_base, p_est_urgente,
        CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END,
        p_serie_id, v_mode
    ) RETURNING id INTO v_mission_id;

    RETURN jsonb_build_object('success', true, 'mission_id', v_mission_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

-- ──────────────────────────────────────────────────────────────
-- 5. GRANTs
-- ──────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.fn_anti_seed_facture_honoraire() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_anti_seed_mission() TO authenticated, service_role;
