-- ============================================================
-- CP-C-1 : fn_declarer_paiement_soignant v2 — attestation + audit
-- ============================================================
-- Refonte de la RPC déclaration paiement soignant côté étab.
-- Nouveauté majeure : attestation sur l'honneur obligatoire
-- (responsabilité URSSAF + article 441-1 Code pénal).
--
-- Changements vs v1 :
--   - Nouveau param p_attestation_sur_l_honneur BOOLEAN DEFAULT FALSE
--     (rétrocompat préservée, mais RAISE si FALSE → force frontend TRUE)
--   - Enum méthode strict : VIREMENT, CHEQUE, BULLETIN_PAIE, NOTE_HONORAIRES
--     (ESPECES retiré : illégal >1500€ + traçabilité URSSAF)
--   - Audit RGPD fn_ecrire_audit_safe action=PAIEMENT_SOIGNANT_DECLARE_ETAB
--   - Le reste (détection Stripe Connect, validation, calcul échéance,
--     INSERT paiements_soignant, notification in-app) inchangé
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_declarer_paiement_soignant(
  p_mission_id UUID,
  p_montant NUMERIC,
  p_methode TEXT DEFAULT NULL,
  p_reference TEXT DEFAULT NULL,
  p_date_paiement DATE DEFAULT CURRENT_DATE,
  p_attestation_sur_l_honneur BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
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
BEGIN
  -- [CP-C-1] Attestation sur l'honneur OBLIGATOIRE (URSSAF + Code pénal art. 441-1)
  IF NOT p_attestation_sur_l_honneur THEN
    RETURN jsonb_build_object(
      'error', 'ATTESTATION_REQUISE',
      'message', 'L''attestation sur l''honneur est obligatoire pour déclarer un paiement soignant.'
    );
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

  IF EXISTS (
    SELECT 1 FROM paiements_soignant
    WHERE mission_id = p_mission_id AND statut IN ('DECLARE', 'CONFIRME')
  ) THEN
    RETURN jsonb_build_object('error', 'Paiement déjà déclaré pour cette mission');
  END IF;

  SELECT * INTO v_soignant FROM soignants WHERE id = v_mission.soignant_assigne_id;
  SELECT * INTO v_etab FROM etablissements WHERE id = v_etab_id;

  -- Vérifier si Stripe Connect est VRAIMENT actif
  SELECT EXISTS(
    SELECT 1 FROM stripe_connect_onboarding
    WHERE soignant_id = v_soignant.id
      AND charges_enabled = TRUE
      AND payouts_enabled = TRUE
  ) INTO v_stripe_actif;

  -- Déduire la méthode + [CP-C-1] enum strict (ESPECES retiré)
  IF p_methode IS NOT NULL THEN
    IF p_methode NOT IN ('VIREMENT', 'CHEQUE', 'BULLETIN_PAIE', 'NOTE_HONORAIRES') THEN
      RETURN jsonb_build_object(
        'error', 'METHODE_INVALIDE',
        'message', 'Méthode de paiement non autorisée. Valeurs acceptées : VIREMENT, CHEQUE, BULLETIN_PAIE, NOTE_HONORAIRES.'
      );
    END IF;
    v_methode := p_methode;
  ELSIF v_mission.type_paiement_soignant = 'NOTE_HONORAIRES' THEN
    IF v_stripe_actif THEN
      RETURN jsonb_build_object(
        'error', 'use_stripe_connect',
        'message', 'Ce soignant a un compte Stripe Connect actif. Utilisez le paiement Stripe.',
        'use_stripe_connect', TRUE
      );
    END IF;
    v_methode := 'NOTE_HONORAIRES';
  ELSE
    v_methode := 'VIREMENT';
  END IF;

  -- Validation référence (obligatoire sauf BULLETIN_PAIE)
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
  )
  RETURNING id INTO v_paiement_id;

  -- [CP-C-1] Notification in-app soignant (inchangé)
  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (
    v_mission.soignant_assigne_id, 'SYSTEM', 'Paiement déclaré',
    'Paiement de ' || p_montant || ' € déclaré pour "' || COALESCE(v_mission.intitule, 'Mission') || '" (réf. ' || v_ref || ').',
    '/soignant/mes-gains', 'SOIGNANT'
  );

  -- [CP-C-1] Audit RGPD : trace de l'attestation sur l'honneur
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

COMMENT ON FUNCTION public.fn_declarer_paiement_soignant(UUID, NUMERIC, TEXT, TEXT, DATE, BOOLEAN) IS
  'Déclaration paiement soignant par l''étab (flow SALARIE + NOTE_HONORAIRES hors Connect). '
  'CP-C-1 : attestation sur l''honneur obligatoire + audit RGPD + enum méthode strict.';
