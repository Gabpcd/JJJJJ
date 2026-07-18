-- Une mission libérale longue porte plusieurs notes d'honoraires. Le paiement
-- manuel doit donc cibler une facture/période exacte, comme le flux Stripe.
CREATE OR REPLACE FUNCTION public.fn_declarer_paiement_facture_soignant(
  p_facture_honoraire_id uuid,
  p_montant numeric,
  p_methode text DEFAULT NULL,
  p_reference text DEFAULT NULL,
  p_date_paiement date DEFAULT CURRENT_DATE,
  p_attestation_sur_l_honneur boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fh public.factures_honoraires%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_soignant public.soignants%ROWTYPE;
  v_etab public.etablissements%ROWTYPE;
  v_etab_id uuid := public.mon_etablissement_id();
  v_methode text;
  v_ref text;
  v_echeance date;
  v_paiement_id uuid;
BEGIN
  IF NOT p_attestation_sur_l_honneur THEN
    RETURN jsonb_build_object(
      'error', 'ATTESTATION_REQUISE',
      'message', 'L''attestation sur l''honneur est obligatoire pour déclarer un paiement soignant.'
    );
  END IF;

  SELECT * INTO v_fh
  FROM public.factures_honoraires
  WHERE id = p_facture_honoraire_id
  FOR UPDATE;
  IF v_fh.id IS NULL OR v_fh.type_document <> 'FACTURE' THEN
    RETURN jsonb_build_object('error', 'Facture d''honoraires introuvable');
  END IF;

  SELECT * INTO v_mission
  FROM public.missions
  WHERE id = v_fh.mission_id
  FOR UPDATE;
  IF v_mission.id IS NULL
     OR v_fh.etablissement_id <> v_mission.etablissement_id
     OR v_fh.soignant_id <> v_mission.soignant_assigne_id THEN
    RETURN jsonb_build_object('error', 'Facture et mission incohérentes');
  END IF;

  IF v_etab_id IS NULL
     OR v_etab_id <> v_mission.etablissement_id
     OR public.fn_a_permission_etablissement('paiement', v_etab_id) IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  IF v_mission.type_contrat_applique <> 'LIBERAL' THEN
    RETURN jsonb_build_object(
      'error', 'CONTRAT_INCOMPATIBLE',
      'message', 'Le paiement par facture est réservé aux missions libérales.'
    );
  END IF;
  IF v_fh.statut NOT IN ('EMISE', 'EN_RETARD') THEN
    RETURN jsonb_build_object('error', 'Cette facture n''est plus payable');
  END IF;
  IF v_mission.statut NOT IN ('EN_COURS', 'TERMINEE')
     OR (
       v_mission.statut = 'EN_COURS'
       AND (
         v_mission.strategie_facturation <> 'HEBDO_ET_FINALE'
         OR v_fh.est_facture_finale_mission
         OR v_fh.periode_fin >= CURRENT_DATE
       )
     ) THEN
    RETURN jsonb_build_object(
      'error', 'PERIODE_NON_PAYABLE',
      'message', 'Seule une période hebdomadaire close ou une mission terminée peut être payée.'
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.paiements_soignant p
    WHERE p.facture_honoraire_id = v_fh.id
      AND p.statut IN ('DECLARE', 'CONFIRME', 'RESOLU')
  ) OR EXISTS (
    SELECT 1 FROM public.stripe_transfers st
    WHERE st.facture_honoraire_id = v_fh.id
      AND st.statut IN ('CHARGE_REUSSI', 'TRANSFERE', 'PAYE')
  ) THEN
    RETURN jsonb_build_object('error', 'Paiement déjà déclaré pour cette période');
  END IF;

  IF p_montant IS NULL OR p_montant <= 0 THEN
    RETURN jsonb_build_object('error', 'Le montant doit être supérieur à 0.');
  END IF;
  IF abs(round(p_montant, 2) - round(v_fh.montant_ttc, 2)) > 0.01 THEN
    RETURN jsonb_build_object(
      'error', 'MONTANT_FACTURE_INCOHERENT',
      'message', 'Le montant déclaré doit correspondre au montant exact de la facture (' || v_fh.montant_ttc || ' €).'
    );
  END IF;
  IF p_date_paiement > CURRENT_DATE THEN
    RETURN jsonb_build_object('error', 'La date de paiement ne peut pas être dans le futur.');
  END IF;

  IF p_methode IS NOT NULL
     AND p_methode NOT IN ('VIREMENT', 'CHEQUE', 'NOTE_HONORAIRES') THEN
    RETURN jsonb_build_object(
      'error', 'METHODE_INVALIDE',
      'message', 'Pour une note d''honoraires, utilisez VIREMENT, CHEQUE ou NOTE_HONORAIRES.'
    );
  END IF;
  v_methode := COALESCE(p_methode, 'NOTE_HONORAIRES');
  v_ref := btrim(COALESCE(p_reference, ''));
  IF length(v_ref) < 5 OR v_ref !~ '[0-9]' THEN
    RETURN jsonb_build_object(
      'error', 'REFERENCE_INVALIDE',
      'message', 'La référence doit contenir au moins 5 caractères et un chiffre.'
    );
  END IF;

  SELECT * INTO v_soignant FROM public.soignants WHERE id = v_fh.soignant_id;
  SELECT * INTO v_etab FROM public.etablissements WHERE id = v_etab_id;
  v_echeance := p_date_paiement + COALESCE(v_etab.delai_paiement_jours, 30);

  INSERT INTO public.paiements_soignant (
    mission_id, facture_honoraire_id, soignant_id, etablissement_id,
    montant_net, methode, reference_virement, date_paiement, echeance_le,
    statut, confirme_par_etablissement, confirme_par_etablissement_le
  ) VALUES (
    v_mission.id, v_fh.id, v_fh.soignant_id, v_etab_id,
    round(p_montant, 2), v_methode, v_ref, p_date_paiement, v_echeance,
    'DECLARE', true, now()
  )
  RETURNING id INTO v_paiement_id;

  INSERT INTO public.notifications (
    destinataire_id, type, titre, corps, lien, type_destinataire
  ) VALUES (
    v_fh.soignant_id,
    'SYSTEM',
    'Paiement hebdomadaire déclaré',
    'Paiement de ' || round(p_montant, 2) || ' € déclaré pour la période du '
      || to_char(v_fh.periode_debut, 'DD/MM/YYYY') || ' au '
      || to_char(v_fh.periode_fin, 'DD/MM/YYYY') || ' de « '
      || public.fn_html_escape(v_mission.intitule) || ' » (réf. ' || v_ref || ').',
    '/soignant/mes-gains',
    'SOIGNANT'
  );

  PERFORM public.fn_ecrire_audit_safe(
    auth.uid(), 'ETABLISSEMENT', 'PAIEMENT_SOIGNANT_DECLARE_ETAB',
    'factures_honoraires', v_fh.id, NULL,
    jsonb_build_object(
      'mission_id', v_mission.id,
      'facture_honoraire_id', v_fh.id,
      'periode_debut', v_fh.periode_debut,
      'periode_fin', v_fh.periode_fin,
      'montant_net', round(p_montant, 2),
      'methode', v_methode,
      'reference_virement', v_ref,
      'date_paiement', p_date_paiement,
      'attestation_sur_l_honneur', true
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', true,
    'paiement_id', v_paiement_id,
    'facture_honoraires_id', v_fh.id,
    'soignant_id', v_fh.soignant_id,
    'mission_intitule', v_mission.intitule,
    'echeance', v_echeance
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_declarer_paiement_facture_soignant(
  uuid, numeric, text, text, date, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_declarer_paiement_facture_soignant(
  uuid, numeric, text, text, date, boolean
) TO authenticated, service_role;

-- La confirmation soignant solde aussi la note d'honoraires exacte. Le flux
-- historique mission-level reste inchangé quand facture_honoraire_id est NULL.
CREATE OR REPLACE FUNCTION public.fn_confirmer_paiement_soignant(p_paiement_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_paiement public.paiements_soignant%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT * INTO v_paiement
  FROM public.paiements_soignant
  WHERE id = p_paiement_id
  FOR UPDATE;
  IF v_paiement.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Paiement introuvable');
  END IF;
  IF v_paiement.soignant_id <> v_uid THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  IF v_paiement.confirme_par_soignant THEN
    RETURN jsonb_build_object('error', 'Paiement déjà confirmé');
  END IF;
  IF v_paiement.statut NOT IN ('DECLARE', 'EN_ATTENTE') THEN
    RETURN jsonb_build_object(
      'error',
      'Ce paiement ne peut plus être confirmé (statut: ' || v_paiement.statut || ')'
    );
  END IF;

  UPDATE public.paiements_soignant
  SET statut = 'CONFIRME',
      confirme_par_soignant = true,
      confirme_par_soignant_le = now(),
      modifie_le = now()
  WHERE id = p_paiement_id;

  IF v_paiement.facture_honoraire_id IS NOT NULL THEN
    UPDATE public.factures_honoraires
    SET statut = 'PAYEE',
        date_paiement = COALESCE(v_paiement.date_paiement, CURRENT_DATE),
        modifie_le = now()
    WHERE id = v_paiement.facture_honoraire_id
      AND statut IN ('EMISE', 'EN_RETARD');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'confirme_le', now(),
    'facture_honoraires_id', v_paiement.facture_honoraire_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_confirmer_paiement_soignant(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_confirmer_paiement_soignant(uuid)
  TO authenticated, service_role;
