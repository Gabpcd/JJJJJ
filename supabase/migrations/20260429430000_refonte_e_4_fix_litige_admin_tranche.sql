-- Refonte.E.4 — FIX bug détecté en tests E2E (S19) :
-- fn_admin_trancher_litige utilisait p_action='MISSION_LITIGE' non présent dans
-- journaux_audit_action_check → toute tentative admin tranche un litige plantait.
-- Solution : ajouter action 'LITIGE_ADMIN_TRANCHE' + corriger la RPC.

-- 1) Étendre le check constraint
ALTER TABLE public.journaux_audit DROP CONSTRAINT IF EXISTS journaux_audit_action_check;
ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_action_check CHECK (action = ANY (ARRAY[
  'INSCRIPTION', 'CONNEXION', 'DECONNEXION', 'MODIFICATION_PROFIL', 'SUPPRESSION_COMPTE',
  'UPLOAD_DOCUMENT', 'TELECHARGEMENT_DOCUMENT', 'VERIFICATION_DOCUMENT', 'VERIFICATION_RPPS',
  'CREATION_MISSION', 'MODIFICATION_MISSION', 'ANNULATION_MISSION', 'CANDIDATURE', 'ASSIGNATION',
  'POINTAGE', 'SIGNATURE_CONTRAT', 'EVALUATION', 'PAIEMENT', 'FACTURATION',
  'DONNEES_PERSO_CONSULTATION', 'DONNEES_PERSO_EXPORT', 'DONNEES_PERSO_SUPPRESSION',
  'ADMIN_ACTION', 'SYSTEM', 'RIB_CONSULTE', 'RIB_PARTAGE', 'CONTRAT_SIGNE',
  'DOCUMENT_CONSULTATION', 'DOCUMENT_TELEVERSEMENT', 'DONNEES_PERSO_MODIFICATION',
  'EXPORT_RH_PAIE', 'FINANCE_FACTURE_PAYEE', 'MISSION_ASSIGNATION', 'MISSION_CREATION',
  'RGPD_EXPORT_DONNEES', 'RGPD_SUPPRESSION_COMPTE', 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT',
  'DEGEL_APPLIED', 'OVERRIDE_CHAMP_POST_GEL', 'GEL_APPLIED', 'OVERRIDE_ANTI_SEED',
  'CONNECT_METADATA_MANQUANTE', 'DOCUMENT_VERIFICATION_AUTO',
  'FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE', 'FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE',
  'FINANCE_CHARGE_EXPIRED', 'FINANCE_CHARGE_FAILED', 'FINANCE_CHARGE_PENDING',
  'FINANCE_CHARGE_REFUNDED', 'FINANCE_DISPUTE_CLOSE', 'FINANCE_DISPUTE_OUVERTE',
  'FINANCE_PAYOUT_CANCELED', 'FINANCE_PAYOUT_CREATED', 'FINANCE_PAYOUT_FAILED',
  'FINANCE_PAYOUT_PAID', 'FINANCE_SEPA_CAPTURE', 'FINANCE_TRANSFER_CONNECT',
  'FINANCE_TRANSFER_CREATED', 'FINANCE_TRANSFER_FAILED', 'FINANCE_TRANSFER_REVERSED',
  'FINANCE_TRANSFER_UPDATED', 'STRIPE_CHECKOUT_ORPHANED_RECOVERED',
  'STRIPE_CONNECT_ACCOUNT_DELETED', 'ATTESTATION_SANTE_SIGNEE',
  'EXCLUSION_CREEE', 'EXCLUSION_SUPPRIMEE', 'FACTURE_GENEREE',
  'MISSION_ANNULATION_SERIE', 'MISSION_MODIFICATION', 'PAIEMENT_SOIGNANT_DECLARE_ETAB',
  'RECLAMATION_CREEE', 'ADMIN_CONSULTATION_ETABLISSEMENT', 'ADMIN_CONSULTATION_SOIGNANT',
  'DOCUMENT_SUPPRESSION', 'HEURES_EXTERNES_DECLAREES', 'MISSION_ANNULATION',
  'NOTE_HONORAIRES_GENEREE', 'PRESENCE_CONTESTATION', 'PRESENCE_POINTAGE_ARRIVEE',
  'PRESENCE_VALIDATION', 'PRESENCE_VALIDATION_LOT', 'RGPD_CONSENTEMENT_DONNE',
  'PAIEMENT_MONTANT_ECART', 'FACTURE_COMMISSION_CREATED_VIA_STRIPE',
  'TAUX_COMMISSION_MODIFIE', 'LITIGE_GEL_SCOPE_MODIFIE',
  'PREFERENCE_NOTIFICATION_MODIFIEE', 'NOTIFICATION_SKIPPED',
  'SERIE_EMAIL_ENVOYE', 'SERIE_EMAIL_SKIPPED', 'FILTRE_CREE', 'FILTRE_MODIFIE', 'FILTRE_SUPPRIME',
  'ALERTE_ACTIVEE', 'ALERTE_DESACTIVEE', 'ALERTE_ENVOYEE',
  'POOL_URGENCE_NOTIFICATIONS_ENVOYEES', 'POOL_URGENCE_ACCEPTATION_RAPIDE',
  'POOL_URGENCE_VALIDATION_ETAB', 'POOL_URGENCE_REFUS_ETAB', 'POOL_URGENCE_SMS_TOGGLE',
  'FAVORI_AJOUTE', 'FAVORI_RETIRE',
  'SCORE_FIABILITE_PENALITE_LITIGE', 'PARRAINAGE_ETAB_APPLIQUE', 'PARRAINAGE_ETAB_VALIDE',
  'CREDIT_PARRAINAGE_CREE', 'CREDIT_PARRAINAGE_APPLIQUE', 'PARRAINAGE_ETAB_ANOMALIE',
  'INSCRIPTION_LISTE_ATTENTE_PREVOYANCE',
  'SCORE_RECALCULE_V2', 'NOTATION_DONNEE', 'NOTATION_RECUE', 'NOTATION_MASQUEE', 'NOTATION_SIGNALE',
  'SCORE_ETAB_RECALCULE', 'COMPTE_SUSPENDU', 'COMPTE_LEVEE_SUSPENSION',
  'MEDIATION_OUVERTE', 'MEDIATION_ACCORD_PARTIES', 'MEDIATION_REVUE_ADMIN_DEMANDEE',
  'RAPPEL_NOTATION_J1_ENVOYE',
  'LITIGE_ADMIN_TRANCHE'
]));

-- 2) Patch fn_admin_trancher_litige : remplacer 'MISSION_LITIGE' par 'LITIGE_ADMIN_TRANCHE'
CREATE OR REPLACE FUNCTION public.fn_admin_trancher_litige(p_litige_id UUID, p_decision TEXT, p_motif TEXT DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_litige RECORD;
  v_decision_clean TEXT;
  v_statut_final TEXT;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Seul l''administrateur peut trancher');
  END IF;

  v_decision_clean := UPPER(TRIM(p_decision));
  IF v_decision_clean NOT IN ('FAVEUR_SOIGNANT','FAVEUR_ETAB','PARTAGE') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Décision invalide (FAVEUR_SOIGNANT/FAVEUR_ETAB/PARTAGE)');
  END IF;

  v_statut_final := 'RESOLU_' || v_decision_clean;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable'); END IF;

  UPDATE litiges SET statut = v_statut_final, resolution = p_motif, resolu_par = v_uid, resolu_le = NOW()
  WHERE id = p_litige_id;

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES
    (v_litige.soignant_id, 'SOIGNANT', 'LITIGE_RESOLU',
     CASE v_decision_clean
       WHEN 'FAVEUR_SOIGNANT' THEN 'Litige tranché en votre faveur ✅'
       WHEN 'FAVEUR_ETAB' THEN 'Litige tranché en faveur de l''établissement'
       ELSE 'Litige tranché : décision partagée'
     END,
     COALESCE(p_motif, 'L''administrateur a tranché.'),
     '/soignant/litiges'),
    (v_litige.etablissement_id, 'ETABLISSEMENT', 'LITIGE_RESOLU',
     CASE v_decision_clean
       WHEN 'FAVEUR_SOIGNANT' THEN 'Litige tranché en faveur du soignant'
       WHEN 'FAVEUR_ETAB' THEN 'Litige tranché en votre faveur ✅'
       ELSE 'Litige tranché : décision partagée'
     END,
     COALESCE(p_motif, 'L''administrateur a tranché.'),
     '/etablissement/litiges');

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'LITIGE_ADMIN_TRANCHE',
    p_type_ressource := 'litige', p_id_ressource := p_litige_id,
    p_details := jsonb_build_object('decision', v_decision_clean, 'statut_final', v_statut_final, 'motif', p_motif)
  );

  RETURN jsonb_build_object('success', true, 'statut_final', v_statut_final);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_trancher_litige(UUID, TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
