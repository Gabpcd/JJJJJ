-- ============================================================
-- Fix F — Gardes type_contrat_applique + méthode paiement
-- Référence : docs/logique-paiements-v1.md §2, §3, §4
-- ============================================================
-- Ajoute 3 gardes métier à fn_declarer_paiement_soignant (version 6-args) :
-- 1. RAISE si type_contrat_applique IS NULL (mission non figée)
-- 2. RAISE si SALARIE + méthode NOTE_HONORAIRES (incompatible)
-- 3. RAISE si LIBERAL + méthode BULLETIN_PAIE (incompatible)
-- + Warning non-bloquant si écart montant > 10% vs net_a_payer mission
--   (audit action='PAIEMENT' avec sous_action='PAIEMENT_MONTANT_ECART')
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_declarer_paiement_soignant(
  p_mission_id uuid,
  p_montant numeric,
  p_methode text DEFAULT NULL::text,
  p_reference text DEFAULT NULL::text,
  p_date_paiement date DEFAULT CURRENT_DATE,
  p_attestation_sur_l_honneur boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD;
  v_soignant RECORD;
  v_etab RECORD;
  v_etab_id UUID := mon_etablissement_id();
  v_methode TEXT;
  v_echeance DATE;
  v_ref TEXT;
  v_stripe_actif BOOLEAN;
  v_paiement_id UUID;
  v_ecart_pct NUMERIC;
BEGIN
  IF NOT p_attestation_sur_l_honneur THEN
    RETURN jsonb_build_object('error', 'ATTESTATION_REQUISE',
      'message', 'L''attestation sur l''honneur est obligatoire pour déclarer un paiement soignant.');
  END IF;

  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF v_mission.etablissement_id != v_etab_id AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  IF v_mission.statut != 'TERMINEE' THEN
    RETURN jsonb_build_object('error', 'La mission doit être terminée');
  END IF;

  IF EXISTS (SELECT 1 FROM paiements_soignant WHERE mission_id = p_mission_id AND statut IN ('DECLARE', 'CONFIRME')) THEN
    RETURN jsonb_build_object('error', 'Paiement déjà déclaré pour cette mission');
  END IF;

  -- Fix F — garde 1 : type_contrat_applique NON NULL
  -- Une mission non figée (pas encore assignée ou choix MIXTE pas acté) ne peut
  -- recevoir de paiement : on ne sait ni la méthode compatible ni la logique URSSAF.
  IF v_mission.type_contrat_applique IS NULL THEN
    RETURN jsonb_build_object('error', 'CONTRAT_NON_FIGE',
      'message', 'Le type de contrat de cette mission n''est pas encore figé (assignation incomplète ou MIXTE sans choix). Impossible de déclarer un paiement tant que type_contrat_applique = NULL.');
  END IF;

  SELECT * INTO v_soignant FROM soignants WHERE id = v_mission.soignant_assigne_id;
  SELECT * INTO v_etab FROM etablissements WHERE id = v_etab_id;

  SELECT EXISTS(
    SELECT 1 FROM stripe_connect_onboarding
    WHERE soignant_id = v_soignant.id AND charges_enabled = TRUE AND payouts_enabled = TRUE
  ) INTO v_stripe_actif;

  -- Déduire la méthode
  IF p_methode IS NOT NULL THEN
    IF p_methode NOT IN ('VIREMENT', 'CHEQUE', 'BULLETIN_PAIE', 'NOTE_HONORAIRES') THEN
      RETURN jsonb_build_object('error', 'METHODE_INVALIDE',
        'message', 'Méthode de paiement non autorisée. Valeurs acceptées : VIREMENT, CHEQUE, BULLETIN_PAIE, NOTE_HONORAIRES.');
    END IF;
    v_methode := p_methode;
  ELSIF v_mission.type_paiement_soignant = 'NOTE_HONORAIRES' THEN
    IF v_stripe_actif THEN
      RETURN jsonb_build_object('error', 'use_stripe_connect',
        'message', 'Ce soignant a un compte Stripe Connect actif. Utilisez le paiement Stripe.',
        'use_stripe_connect', TRUE);
    END IF;
    v_methode := 'NOTE_HONORAIRES';
  ELSE
    v_methode := 'VIREMENT';
  END IF;

  -- Fix F — garde 2 : SALARIE + NOTE_HONORAIRES incompatibles (logique-paiements-v1 §3)
  IF v_mission.type_contrat_applique = 'SALARIE' AND v_methode = 'NOTE_HONORAIRES' THEN
    RETURN jsonb_build_object('error', 'CONTRAT_SALARIE_METHODE_INCOMPATIBLE',
      'message', 'Les missions en contrat salarié (CDDU) ne peuvent pas être payées par note d''honoraires. Utilisez VIREMENT ou BULLETIN_PAIE. La note d''honoraires est réservée aux missions LIBERAL.');
  END IF;

  -- Fix F — garde 3 : LIBERAL + BULLETIN_PAIE incompatibles (logique-paiements-v1 §2)
  IF v_mission.type_contrat_applique = 'LIBERAL' AND v_methode = 'BULLETIN_PAIE' THEN
    RETURN jsonb_build_object('error', 'CONTRAT_LIBERAL_METHODE_INCOMPATIBLE',
      'message', 'Les missions en contrat libéral ne génèrent pas de bulletin de paie. Utilisez VIREMENT ou NOTE_HONORAIRES. Le bulletin de paie est réservé aux missions SALARIE.');
  END IF;

  -- Validation référence
  IF v_methode IN ('VIREMENT', 'CHEQUE', 'NOTE_HONORAIRES') THEN
    v_ref := TRIM(COALESCE(p_reference, ''));
    IF LENGTH(v_ref) < 5 THEN
      RETURN jsonb_build_object('error', 'La référence doit contenir au moins 5 caractères.');
    END IF;
    IF v_ref !~ '[0-9]' THEN
      RETURN jsonb_build_object('error', 'La référence doit contenir au moins un chiffre.');
    END IF;
  ELSE
    v_ref := TRIM(COALESCE(p_reference, ''));
  END IF;

  IF p_montant <= 0 THEN
    RETURN jsonb_build_object('error', 'Le montant doit être supérieur à 0.');
  END IF;

  IF p_date_paiement > CURRENT_DATE THEN
    RETURN jsonb_build_object('error', 'La date de paiement ne peut pas être dans le futur.');
  END IF;

  v_echeance := p_date_paiement + COALESCE(v_etab.delai_paiement_jours, 30);

  INSERT INTO paiements_soignant (
    mission_id, soignant_id, etablissement_id, montant_net, methode, reference_virement,
    date_paiement, confirme_par_etablissement, confirme_par_etablissement_le, statut, echeance_le
  ) VALUES (
    p_mission_id, v_mission.soignant_assigne_id, v_etab_id,
    p_montant, v_methode, v_ref, p_date_paiement, TRUE, NOW(), 'DECLARE', v_echeance
  ) RETURNING id INTO v_paiement_id;

  -- Fix F — warning non-bloquant si écart montant > 10 % vs net_a_payer attendu.
  -- Audit sous action='PAIEMENT' + sous_action='PAIEMENT_MONTANT_ECART' dans details
  -- (le CHECK journaux_audit_action_check n'accepte pas d'action custom pour l'instant).
  IF v_mission.net_a_payer IS NOT NULL AND v_mission.net_a_payer > 0 THEN
    v_ecart_pct := ABS(p_montant - v_mission.net_a_payer) / v_mission.net_a_payer * 100;
    IF v_ecart_pct > 10 THEN
      PERFORM fn_ecrire_audit_safe(
        auth.uid(),
        'ETABLISSEMENT',
        'PAIEMENT',
        'paiements_soignant',
        v_paiement_id,
        NULL,
        jsonb_build_object(
          'sous_action', 'PAIEMENT_MONTANT_ECART',
          'mission_id', p_mission_id,
          'mission_intitule', v_mission.intitule,
          'montant_declare', p_montant,
          'montant_attendu_net_a_payer', v_mission.net_a_payer,
          'ecart_pct', ROUND(v_ecart_pct, 2),
          'methode', v_methode,
          'type_contrat_applique', v_mission.type_contrat_applique
        ),
        NULL,
        NULL
      );
    END IF;
  END IF;

  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (
    v_mission.soignant_assigne_id, 'SYSTEM', 'Paiement déclaré',
    'Paiement de ' || p_montant || ' € déclaré pour "' || COALESCE(v_mission.intitule, 'Mission') || '" (réf. ' || v_ref || ').',
    '/soignant/mes-gains', 'SOIGNANT'
  );

  PERFORM public.fn_ecrire_audit_safe(
    auth.uid(),
    'ETABLISSEMENT',
    'PAIEMENT_SOIGNANT_DECLARE_ETAB',
    'paiements_soignant',
    v_paiement_id,
    NULL,
    jsonb_build_object(
      'mission_id', p_mission_id,
      'mission_intitule', v_mission.intitule,
      'soignant_id', v_mission.soignant_assigne_id,
      'etablissement_id', v_etab_id,
      'montant_net', p_montant,
      'methode', v_methode,
      'reference_virement', v_ref,
      'date_paiement', p_date_paiement,
      'echeance_le', v_echeance,
      'type_contrat_applique', v_mission.type_contrat_applique,
      'attestation_sur_l_honneur', TRUE,
      'attestation_timestamp', NOW()
    ),
    NULL,
    NULL
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'paiement_id', v_paiement_id,
    'methode', v_methode,
    'echeance', v_echeance,
    'soignant_id', v_mission.soignant_assigne_id,
    'mission_intitule', v_mission.intitule
  );
END;
$function$;
