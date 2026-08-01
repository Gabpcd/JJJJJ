BEGIN;

-- ---------------------------------------------------------------------------
-- Finance établissement : une permission de lecture distincte des mutations.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_mes_permissions_etab(
  p_etablissement_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_etab_id uuid := COALESCE(p_etablissement_id, public.mon_etablissement_id());
  v_role text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'role', NULL, 'permissions', '{}'::jsonb);
  END IF;
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'role', NULL, 'etablissement_id', NULL, 'permissions', '{}'::jsonb);
  END IF;

  v_role := public.fn_role_etablissement_courant(v_etab_id);
  IF v_role IS NULL AND NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', true, 'role', NULL, 'etablissement_id', NULL, 'permissions', '{}'::jsonb);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'role', COALESCE(v_role, 'ADMIN_PLATEFORME'),
    'etablissement_id', v_etab_id,
    'permissions', jsonb_build_object(
      'gerer_equipe', public.fn_a_permission_etablissement('gerer_equipe', v_etab_id),
      'supprimer_compte', public.fn_a_permission_etablissement('supprimer_compte', v_etab_id),
      'profil_etab', public.fn_a_permission_etablissement('profil_etab', v_etab_id),
      'paiement', public.fn_a_permission_etablissement('paiement', v_etab_id),
      'lecture_paiement', public.fn_a_permission_etablissement('lecture_paiement', v_etab_id),
      'missions', public.fn_a_permission_etablissement('missions', v_etab_id),
      'candidatures', public.fn_a_permission_etablissement('candidatures', v_etab_id),
      'contrats', public.fn_a_permission_etablissement('contrats', v_etab_id),
      'pointage', public.fn_a_permission_etablissement('pointage', v_etab_id),
      'rh', public.fn_a_permission_etablissement('rh', v_etab_id),
      'lecture', public.fn_a_permission_etablissement('lecture', v_etab_id)
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_mes_permissions_etab(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_mes_permissions_etab(uuid) TO authenticated, service_role;

-- Les anciennes fonctions de lecture sont conservées comme implémentations
-- internes SECURITY INVOKER. Les nouveaux points d'entrée vérifient d'abord
-- lecture_paiement, puis appellent le corps historique avec les droits du
-- propriétaire de la fonction wrapper.
ALTER FUNCTION public.fn_obligations_financieres()
  RENAME TO fn_obligations_financieres_internal_20260801;
ALTER FUNCTION public.fn_obligations_financieres_internal_20260801() SECURITY INVOKER;
ALTER FUNCTION public.fn_obligations_financieres_internal_20260801()
  SET search_path = pg_catalog, public, auth;
REVOKE ALL ON FUNCTION public.fn_obligations_financieres_internal_20260801()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.fn_obligations_financieres()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_etab_id uuid := public.mon_etablissement_id();
  v_result jsonb;
  v_lignes jsonb := '[]'::jsonb;
  v_total_soignants numeric := 0;
  v_total_commissions numeric := 0;
BEGIN
  IF NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       v_etab_id IS NULL
       OR public.fn_a_permission_etablissement('lecture_paiement', v_etab_id) IS NOT TRUE
     ) THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_result := public.fn_obligations_financieres_internal_20260801();
  IF v_result ? 'error' THEN
    RETURN v_result;
  END IF;

  -- Pour une mission salariée, net_a_payer est historiquement le brut chargé
  -- d'IFM/ICP. L'échéance réellement due au salarié est net_estime.
  WITH lignes_corrigees AS (
    SELECT CASE
      WHEN ligne->>'type_contrat_applique' = 'SALARIE' THEN
        jsonb_set(
          ligne,
          '{net_a_payer}',
          to_jsonb(COALESCE(
            (
              SELECT NULLIF(m.net_estime, 0)
              FROM public.missions m
              WHERE m.id = (ligne->>'mission_id')::uuid
            ),
            (
              SELECT round(NULLIF(m.net_a_payer, 0) * 0.78, 2)
              FROM public.missions m
              WHERE m.id = (ligne->>'mission_id')::uuid
            ),
            0
          )),
          true
        )
      ELSE ligne
    END AS ligne
    FROM jsonb_array_elements(COALESCE(v_result->'missions_non_payees', '[]'::jsonb)) AS lignes(ligne)
  )
  SELECT
    COALESCE(jsonb_agg(ligne), '[]'::jsonb),
    COALESCE(sum((ligne->>'net_a_payer')::numeric), 0)
  INTO v_lignes, v_total_soignants
  FROM lignes_corrigees;

  v_total_commissions := COALESCE((v_result->>'total_commissions_du')::numeric, 0);
  v_result := jsonb_set(v_result, '{missions_non_payees}', v_lignes, true);
  v_result := jsonb_set(v_result, '{total_soignants_du}', to_jsonb(v_total_soignants), true);
  v_result := jsonb_set(v_result, '{total_du}', to_jsonb(v_total_soignants + v_total_commissions), true);
  RETURN v_result;
END;
$$;

ALTER FUNCTION public.fn_mes_factures() RENAME TO fn_mes_factures_internal_20260801;
ALTER FUNCTION public.fn_mes_factures_internal_20260801() SECURITY INVOKER;
ALTER FUNCTION public.fn_mes_factures_internal_20260801()
  SET search_path = pg_catalog, public, auth;
REVOKE ALL ON FUNCTION public.fn_mes_factures_internal_20260801()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.fn_mes_factures()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_etab_id uuid := public.mon_etablissement_id();
BEGIN
  IF NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       v_etab_id IS NULL
       OR public.fn_a_permission_etablissement('lecture_paiement', v_etab_id) IS NOT TRUE
     ) THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  RETURN public.fn_mes_factures_internal_20260801();
END;
$$;

ALTER FUNCTION public.fn_paiements_etablissement()
  RENAME TO fn_paiements_etablissement_internal_20260801;
ALTER FUNCTION public.fn_paiements_etablissement_internal_20260801() SECURITY INVOKER;
ALTER FUNCTION public.fn_paiements_etablissement_internal_20260801()
  SET search_path = pg_catalog, public, auth;
REVOKE ALL ON FUNCTION public.fn_paiements_etablissement_internal_20260801()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.fn_paiements_etablissement()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_etab_id uuid := public.mon_etablissement_id();
  v_result jsonb;
  v_lignes jsonb;
BEGIN
  IF NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       v_etab_id IS NULL
       OR public.fn_a_permission_etablissement('lecture_paiement', v_etab_id) IS NOT TRUE
     ) THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_result := public.fn_paiements_etablissement_internal_20260801();
  IF v_result ? 'error' THEN
    RETURN v_result;
  END IF;

  SELECT COALESCE(jsonb_agg(
    CASE
      WHEN EXISTS (
        SELECT 1 FROM public.missions m
        WHERE m.id = (ligne->>'mission_id')::uuid
          AND m.type_contrat_applique = 'SALARIE'
      ) THEN jsonb_set(
        ligne,
        '{net_a_payer}',
        to_jsonb(COALESCE(
          (
            SELECT NULLIF(m.net_estime, 0)
            FROM public.missions m
            WHERE m.id = (ligne->>'mission_id')::uuid
          ),
          (
            SELECT round(NULLIF(m.net_a_payer, 0) * 0.78, 2)
            FROM public.missions m
            WHERE m.id = (ligne->>'mission_id')::uuid
          ),
          0
        )),
        true
      )
      ELSE ligne
    END
  ), '[]'::jsonb)
  INTO v_lignes
  FROM jsonb_array_elements(COALESCE(v_result->'missions_a_payer', '[]'::jsonb)) AS lignes(ligne);

  RETURN jsonb_set(v_result, '{missions_a_payer}', v_lignes, true);
END;
$$;

ALTER FUNCTION public.fn_detail_facture(uuid) RENAME TO fn_detail_facture_internal_20260801;
ALTER FUNCTION public.fn_detail_facture_internal_20260801(uuid) SECURITY INVOKER;
ALTER FUNCTION public.fn_detail_facture_internal_20260801(uuid)
  SET search_path = pg_catalog, public, auth;
REVOKE ALL ON FUNCTION public.fn_detail_facture_internal_20260801(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.fn_detail_facture(p_facture_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_etab_id uuid;
  v_result jsonb;
  v_facture public.factures%ROWTYPE;
BEGIN
  SELECT * INTO v_facture
  FROM public.factures
  WHERE id = p_facture_id;
  IF v_facture.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Facture introuvable');
  END IF;
  v_etab_id := v_facture.etablissement_id;

  IF NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       v_etab_id IS DISTINCT FROM public.mon_etablissement_id()
       OR public.fn_a_permission_etablissement('lecture_paiement', v_etab_id) IS NOT TRUE
     ) THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_result := public.fn_detail_facture_internal_20260801(p_facture_id);
  IF v_result ? 'error' THEN
    RETURN v_result;
  END IF;

  -- Champs indispensables pour interdire les moyens de paiement incompatibles.
  v_result := jsonb_set(
    v_result,
    '{facture}',
    COALESCE(v_result->'facture', '{}'::jsonb) || jsonb_build_object(
      'est_secteur_public', v_facture.est_secteur_public,
      'virement_reference', v_facture.virement_reference,
      'virement_confirme_le', v_facture.virement_confirme_le,
      'stripe_payment_intent_id', v_facture.stripe_payment_intent_id
    ),
    true
  );
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_obligations_financieres() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_mes_factures() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_paiements_etablissement() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_detail_facture(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_obligations_financieres() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_mes_factures() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_paiements_etablissement() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_detail_facture(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Mutations financières : paiement obligatoire, lecture seule non mutante.
-- ---------------------------------------------------------------------------

ALTER FUNCTION public.fn_declarer_paiement_soignant(uuid, numeric, text, text, date, boolean)
  RENAME TO fn_declarer_paiement_soignant_internal_20260801;
ALTER FUNCTION public.fn_declarer_paiement_soignant_internal_20260801(uuid, numeric, text, text, date, boolean)
  SECURITY INVOKER;
ALTER FUNCTION public.fn_declarer_paiement_soignant_internal_20260801(uuid, numeric, text, text, date, boolean)
  SET search_path = pg_catalog, public, auth;
REVOKE ALL ON FUNCTION public.fn_declarer_paiement_soignant_internal_20260801(uuid, numeric, text, text, date, boolean)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.fn_declarer_paiement_soignant(
  p_mission_id uuid,
  p_montant numeric,
  p_methode text DEFAULT NULL,
  p_reference text DEFAULT NULL,
  p_date_paiement date DEFAULT CURRENT_DATE,
  p_attestation_sur_l_honneur boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_montant_du numeric;
  v_plafond_brut numeric;
BEGIN
  SELECT * INTO v_mission
  FROM public.missions
  WHERE id = p_mission_id;
  IF v_mission.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       v_mission.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
       OR public.fn_a_permission_etablissement('paiement', v_mission.etablissement_id) IS NOT TRUE
     ) THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  IF p_montant IS NULL OR p_montant <= 0 THEN
    RETURN jsonb_build_object('error', 'Le montant doit être supérieur à 0.');
  END IF;

  IF v_mission.type_contrat_applique = 'SALARIE' THEN
    -- `net_estime` est une projection forfaitaire avant PAS, pas le net du
    -- bulletin officiel. L'établissement doit déclarer le montant réellement
    -- viré d'après sa paie ; on ne remplace donc jamais sa saisie par 78 %.
    v_plafond_brut := COALESCE(
      NULLIF(v_mission.net_a_payer, 0),
      NULLIF(v_mission.total_brut, 0)
        + COALESCE(v_mission.montant_ifm, 0)
        + COALESCE(v_mission.montant_icp, 0)
    );
    IF v_plafond_brut IS NULL OR v_plafond_brut <= 0 THEN
      RETURN jsonb_build_object(
        'error', 'BRUT_SALARIE_INDISPONIBLE',
        'message', 'La base brute du salarié est indisponible. Le paiement est bloqué pour éviter un montant erroné.'
      );
    END IF;
    IF round(p_montant, 2) > round(v_plafond_brut, 2) THEN
      RETURN jsonb_build_object(
        'error', 'MONTANT_NET_SALARIE_SUPERIEUR_AU_BRUT',
        'message', 'Le net déclaré ne peut pas dépasser la rémunération brute de référence (' || round(v_plafond_brut, 2) || ' €).',
        'montant_maximum', round(v_plafond_brut, 2)
      );
    END IF;
    v_montant_du := round(p_montant, 2);
  ELSE
    v_montant_du := round(p_montant, 2);
  END IF;

  RETURN public.fn_declarer_paiement_soignant_internal_20260801(
    p_mission_id,
    v_montant_du,
    p_methode,
    p_reference,
    p_date_paiement,
    p_attestation_sur_l_honneur
  );
END;
$$;

ALTER FUNCTION public.fn_modifier_reference_paiement(uuid, text)
  RENAME TO fn_modifier_reference_paiement_internal_20260801;
ALTER FUNCTION public.fn_modifier_reference_paiement_internal_20260801(uuid, text) SECURITY INVOKER;
ALTER FUNCTION public.fn_modifier_reference_paiement_internal_20260801(uuid, text)
  SET search_path = pg_catalog, public, auth;
REVOKE ALL ON FUNCTION public.fn_modifier_reference_paiement_internal_20260801(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.fn_modifier_reference_paiement(p_paiement_id uuid, p_nouvelle_reference text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_etab_id uuid;
BEGIN
  SELECT etablissement_id INTO v_etab_id
  FROM public.paiements_soignant
  WHERE id = p_paiement_id;
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Paiement introuvable');
  END IF;
  IF NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       v_etab_id IS DISTINCT FROM public.mon_etablissement_id()
       OR public.fn_a_permission_etablissement('paiement', v_etab_id) IS NOT TRUE
     ) THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  RETURN public.fn_modifier_reference_paiement_internal_20260801(p_paiement_id, p_nouvelle_reference);
END;
$$;

ALTER FUNCTION public.fn_consulter_rib_soignant(uuid)
  RENAME TO fn_consulter_rib_soignant_internal_20260801;
ALTER FUNCTION public.fn_consulter_rib_soignant_internal_20260801(uuid) SECURITY INVOKER;
ALTER FUNCTION public.fn_consulter_rib_soignant_internal_20260801(uuid)
  SET search_path = pg_catalog, public, auth;
REVOKE ALL ON FUNCTION public.fn_consulter_rib_soignant_internal_20260801(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.fn_consulter_rib_soignant(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_etab_id uuid;
BEGIN
  SELECT etablissement_id INTO v_etab_id
  FROM public.missions
  WHERE id = p_mission_id;
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;
  IF NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       v_etab_id IS DISTINCT FROM public.mon_etablissement_id()
       OR public.fn_a_permission_etablissement('paiement', v_etab_id) IS NOT TRUE
     ) THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  RETURN public.fn_consulter_rib_soignant_internal_20260801(p_mission_id);
END;
$$;

ALTER FUNCTION public.fn_generer_facture_mensuelle(uuid)
  RENAME TO fn_generer_facture_mensuelle_internal_20260801;
ALTER FUNCTION public.fn_generer_facture_mensuelle_internal_20260801(uuid) SECURITY INVOKER;
ALTER FUNCTION public.fn_generer_facture_mensuelle_internal_20260801(uuid)
  SET search_path = pg_catalog, public, auth;
REVOKE ALL ON FUNCTION public.fn_generer_facture_mensuelle_internal_20260801(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.fn_generer_facture_mensuelle(p_etablissement_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       p_etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
       OR public.fn_a_permission_etablissement('paiement', p_etablissement_id) IS NOT TRUE
     ) THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  RETURN public.fn_generer_facture_mensuelle_internal_20260801(p_etablissement_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_generer_facture_rate_limited()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_etab_id uuid := public.mon_etablissement_id();
BEGIN
  IF v_user_id IS NULL OR v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;
  IF NOT public.est_admin()
     AND public.fn_a_permission_etablissement('paiement', v_etab_id) IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  IF NOT public.fn_verifier_rate_limit(v_user_id::text, 'facture', 5, 3600) THEN
    RETURN jsonb_build_object('error', 'Trop de tentatives. Réessayez dans quelques minutes.');
  END IF;
  RETURN public.fn_generer_facture_mensuelle(v_etab_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_declarer_virement(p_facture_id uuid, p_reference text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_facture public.factures%ROWTYPE;
  v_mode_commission text;
BEGIN
  SELECT * INTO v_facture
  FROM public.factures
  WHERE id = p_facture_id
  FOR UPDATE;
  IF v_facture.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Facture introuvable');
  END IF;
  IF NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       v_facture.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
       OR public.fn_a_permission_etablissement('paiement', v_facture.etablissement_id) IS NOT TRUE
     ) THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;

  SELECT mode_paiement_commission INTO v_mode_commission
  FROM public.etablissements
  WHERE id = v_facture.etablissement_id;
  IF v_facture.est_secteur_public THEN
    RETURN jsonb_build_object('error', 'Cette facture est réglée via Chorus Pro.');
  END IF;
  IF v_mode_commission = 'SEPA_DEBIT' THEN
    RETURN jsonb_build_object(
      'error', 'PAIEMENT_SEPA_AUTOMATIQUE',
      'message', 'Le prélèvement SEPA est automatique : aucun virement manuel ne doit être déclaré.'
    );
  END IF;
  IF v_facture.statut NOT IN ('EMISE', 'EN_RETARD') THEN
    RETURN jsonb_build_object('error', 'Statut incorrect : ' || v_facture.statut);
  END IF;
  IF p_reference IS NULL OR length(btrim(p_reference)) < 3 THEN
    RETURN jsonb_build_object('error', 'Référence de virement requise.');
  END IF;

  UPDATE public.factures
  SET virement_reference = btrim(p_reference),
      mode_paiement = 'VIREMENT',
      statut = 'VIREMENT_DECLARE',
      modifie_le = now()
  WHERE id = p_facture_id;
  RETURN jsonb_build_object('success', true);
END;
$$;

-- Mode et montant canonique affichés par la fiche mission établissement.
CREATE OR REPLACE FUNCTION public.fn_mode_paiement_mission(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_mission record;
  v_connect_actif boolean;
  v_rib_partage boolean;
  v_regime text;
  v_montant_soignant numeric;
BEGIN
  SELECT m.*, s.type_exercice AS profil_type_exercice,
         s.iban_last4 AS soignant_iban_last4
  INTO v_mission
  FROM public.missions m
  JOIN public.soignants s ON s.id = m.soignant_assigne_id
  WHERE m.id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF v_mission.soignant_assigne_id IS DISTINCT FROM auth.uid()
     AND NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       v_mission.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
       OR public.fn_a_permission_etablissement('lecture_paiement', v_mission.etablissement_id) IS NOT TRUE
     ) THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_regime := COALESCE(
    v_mission.type_contrat_applique::text,
    CASE WHEN v_mission.type_paiement_soignant = 'NOTE_HONORAIRES' THEN 'LIBERAL' ELSE 'SALARIE' END
  );
  v_montant_soignant := CASE
    WHEN v_regime = 'SALARIE' THEN COALESCE(
      NULLIF(v_mission.net_estime, 0),
      round(NULLIF(v_mission.net_a_payer, 0) * 0.78, 2)
    )
    ELSE v_mission.net_a_payer
  END;
  v_connect_actif := v_regime = 'LIBERAL'
    AND public.fn_soignant_stripe_connect_actif(v_mission.soignant_assigne_id);
  v_rib_partage := EXISTS (
    SELECT 1 FROM public.partages_rib
    WHERE mission_id = p_mission_id
      AND actif
      AND (expire_le IS NULL OR expire_le > now())
  );

  RETURN jsonb_build_object(
    'mode_recommande', CASE
      WHEN v_regime = 'LIBERAL' AND v_connect_actif THEN 'STRIPE_CONNECT'
      WHEN v_regime = 'LIBERAL' THEN 'VIREMENT_NOTE_HONORAIRES'
      ELSE 'VIREMENT_PAIE'
    END,
    'type_contrat_applique', v_regime,
    'type_exercice', v_mission.profil_type_exercice,
    'stripe_connect_actif', v_connect_actif,
    'rib_partage', v_rib_partage,
    'iban_last4', v_mission.soignant_iban_last4,
    'montant_soignant', v_montant_soignant,
    'montant_soignant_estime', v_regime = 'SALARIE',
    'total_brut', v_mission.total_brut,
    'net_estime', v_mission.net_estime,
    'commission_ht', v_mission.montant_commission_ht,
    'commission_ttc', v_mission.montant_commission_ttc,
    'total', COALESCE(v_montant_soignant, 0) + COALESCE(v_mission.montant_commission_ttc, 0)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_declarer_paiement_soignant(uuid, numeric, text, text, date, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_modifier_reference_paiement(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_consulter_rib_soignant(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_generer_facture_mensuelle(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_generer_facture_rate_limited() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_declarer_virement(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_mode_paiement_mission(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_declarer_paiement_soignant(uuid, numeric, text, text, date, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_modifier_reference_paiement(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_consulter_rib_soignant(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_generer_facture_mensuelle(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_generer_facture_rate_limited() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_declarer_virement(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_mode_paiement_mission(uuid) TO authenticated, service_role;

-- Les coordonnées bancaires ne sont pas une donnée opérationnelle générale :
-- seuls le soignant concerné, l'admin plateforme et un membre autorisé à payer
-- peuvent lire un partage RIB actif. Un rôle RH/POINTAGE/lecture simple ne doit
-- pas pouvoir contourner l'interface via PostgREST.
DROP POLICY IF EXISTS pol_rib_select ON public.partages_rib;
CREATE POLICY pol_rib_select ON public.partages_rib
  FOR SELECT TO authenticated
  USING (
    actif = true
    AND (expire_le IS NULL OR expire_le > now())
    AND (
      soignant_id = (SELECT auth.uid())
      OR (SELECT public.est_admin())
      OR (
        etablissement_id = (SELECT public.mon_etablissement_id())
        AND (SELECT public.fn_a_permission_etablissement('paiement', etablissement_id))
      )
    )
  );

-- ---------------------------------------------------------------------------
-- RLS : empêcher qu'un membre RH/pointage contourne les RPC via PostgREST.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS pol_fact_select ON public.factures;
CREATE POLICY pol_fact_select ON public.factures
  FOR SELECT TO authenticated
  USING (
    (SELECT public.est_admin())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('lecture_paiement', etablissement_id))
    )
  );

DROP POLICY IF EXISTS fh_select_own ON public.factures_honoraires;
CREATE POLICY fh_select_own ON public.factures_honoraires
  FOR SELECT TO authenticated
  USING (
    soignant_id = (SELECT auth.uid())
    OR (SELECT public.est_admin())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('lecture_paiement', etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_paim_select ON public.paiements_mission;
CREATE POLICY pol_paim_select ON public.paiements_mission
  FOR SELECT TO authenticated
  USING (
    (SELECT public.est_admin())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('lecture_paiement', etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_transfer_select ON public.stripe_transfers;
CREATE POLICY pol_transfer_select ON public.stripe_transfers
  FOR SELECT TO authenticated
  USING (
    soignant_id = (SELECT auth.uid())
    OR (SELECT public.est_admin())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('lecture_paiement', etablissement_id))
    )
  );

-- Les empreintes restent littérales : toute modification ultérieure des corps
-- SECURITY DEFINER continuera d'être détectée par le manifeste.
UPDATE private.security_definer_inventory SET definition_md5 = 'f73521225f50a70b9ae48fdc1a56cc94', justification = 'RPC établissement: matrice explicite incluant lecture_paiement.' WHERE signature = 'fn_mes_permissions_etab(uuid)';
UPDATE private.security_definer_inventory SET definition_md5 = '8bb6035e316442ff3a4c0263fddd648c', justification = 'RPC établissement: lecture financière bornée par lecture_paiement et net salarié canonique.' WHERE signature = 'fn_obligations_financieres()';
UPDATE private.security_definer_inventory SET definition_md5 = '11f32c82a353a36fe64f30c5665c2c92', justification = 'RPC établissement: lecture des factures bornée par lecture_paiement.' WHERE signature = 'fn_mes_factures()';
UPDATE private.security_definer_inventory SET definition_md5 = '511c293a63a7b99d10e61e253b761147', justification = 'RPC établissement: lecture des paiements bornée par lecture_paiement.' WHERE signature = 'fn_paiements_etablissement()';
UPDATE private.security_definer_inventory SET definition_md5 = 'c1afddd3b75db82d26e6c5b85374745d', justification = 'RPC établissement: détail facture borné par lecture_paiement.' WHERE signature = 'fn_detail_facture(uuid)';
UPDATE private.security_definer_inventory SET definition_md5 = '48089196bb4cce2ee9d33a12a2c92612', justification = 'RPC établissement: mutation bornée par paiement; le net salarié déclaré provient du bulletin employeur et reste plafonné au brut.' WHERE signature = 'fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)';
UPDATE private.security_definer_inventory SET definition_md5 = 'fd7ec51478dbc228716396bf0b0d794c', justification = 'RPC établissement: modification de référence bornée par paiement.' WHERE signature = 'fn_modifier_reference_paiement(uuid,text)';
UPDATE private.security_definer_inventory SET definition_md5 = 'bb44a9e8a69544d67b27a02e73804885', justification = 'RPC établissement: consultation RIB bornée par paiement.' WHERE signature = 'fn_consulter_rib_soignant(uuid)';
UPDATE private.security_definer_inventory SET definition_md5 = '18bc7e1ff9b907b5a1a1ea93bd5548fe', justification = 'RPC établissement: génération de facture bornée par paiement.' WHERE signature = 'fn_generer_facture_mensuelle(uuid)';
UPDATE private.security_definer_inventory SET definition_md5 = 'a1e2e304e0f0d9be47d967d174e44615', justification = 'RPC établissement: génération rate-limitée bornée par paiement.' WHERE signature = 'fn_generer_facture_rate_limited()';
UPDATE private.security_definer_inventory SET definition_md5 = 'fa7138054e010be32d5d3db3edc5acc7', justification = 'RPC établissement: virement borné par paiement et interdit en SEPA/Chorus.' WHERE signature = 'fn_declarer_virement(uuid,text)';
UPDATE private.security_definer_inventory SET definition_md5 = '40ebe876222bef2485f7b6cbca2e5b58', justification = 'RPC mission: lecture financière bornée; toute estimation salariale est explicitement signalée.' WHERE signature = 'fn_mode_paiement_mission(uuid)';

DO $assert_finance_etablissement_security$
DECLARE
  v_invalide text;
BEGIN
  WITH expected(signature, definition_md5) AS (VALUES
    ('fn_mes_permissions_etab(uuid)', 'f73521225f50a70b9ae48fdc1a56cc94'),
    ('fn_obligations_financieres()', '8bb6035e316442ff3a4c0263fddd648c'),
    ('fn_mes_factures()', '11f32c82a353a36fe64f30c5665c2c92'),
    ('fn_paiements_etablissement()', '511c293a63a7b99d10e61e253b761147'),
    ('fn_detail_facture(uuid)', 'c1afddd3b75db82d26e6c5b85374745d'),
    ('fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)', '48089196bb4cce2ee9d33a12a2c92612'),
    ('fn_modifier_reference_paiement(uuid,text)', 'fd7ec51478dbc228716396bf0b0d794c'),
    ('fn_consulter_rib_soignant(uuid)', 'bb44a9e8a69544d67b27a02e73804885'),
    ('fn_generer_facture_mensuelle(uuid)', '18bc7e1ff9b907b5a1a1ea93bd5548fe'),
    ('fn_generer_facture_rate_limited()', 'a1e2e304e0f0d9be47d967d174e44615'),
    ('fn_declarer_virement(uuid,text)', 'fa7138054e010be32d5d3db3edc5acc7'),
    ('fn_mode_paiement_mission(uuid)', '40ebe876222bef2485f7b6cbca2e5b58')
  )
  SELECT pg_catalog.string_agg(e.signature, ', ' ORDER BY e.signature)
  INTO v_invalide
  FROM expected e
  LEFT JOIN private.security_definer_inventory i USING (signature)
  LEFT JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(e.signature)
  WHERE i.signature IS NULL
     OR i.definition_md5 <> e.definition_md5
     OR p.oid IS NULL
     OR p.prosecdef IS NOT TRUE
     OR pg_catalog.md5(p.prosrc) <> e.definition_md5
     OR pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
     OR COALESCE(pg_catalog.array_to_string(p.proconfig, ','), '') NOT LIKE '%search_path=pg_catalog, public, auth%';

  IF v_invalide IS NOT NULL THEN
    RAISE EXCEPTION 'Invariants SECURITY DEFINER finances invalides : %', v_invalide;
  END IF;

  WITH internal(signature) AS (VALUES
    ('fn_obligations_financieres_internal_20260801()'),
    ('fn_mes_factures_internal_20260801()'),
    ('fn_paiements_etablissement_internal_20260801()'),
    ('fn_detail_facture_internal_20260801(uuid)'),
    ('fn_declarer_paiement_soignant_internal_20260801(uuid,numeric,text,text,date,boolean)'),
    ('fn_modifier_reference_paiement_internal_20260801(uuid,text)'),
    ('fn_consulter_rib_soignant_internal_20260801(uuid)'),
    ('fn_generer_facture_mensuelle_internal_20260801(uuid)')
  )
  SELECT pg_catalog.string_agg(i.signature, ', ' ORDER BY i.signature)
  INTO v_invalide
  FROM internal i
  LEFT JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(i.signature)
  WHERE p.oid IS NULL
     OR p.prosecdef IS TRUE
     OR pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE');

  IF v_invalide IS NOT NULL THEN
    RAISE EXCEPTION 'Sous-routines financières internes exposées : %', v_invalide;
  END IF;
END
$assert_finance_etablissement_security$;

COMMIT;
