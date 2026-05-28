-- Sprint 17-A Phase B — IBAN soignant pour versement primes parrainage
--
-- Colonnes :
--   soignants.iban_virement    TEXT — IBAN complet (FR76...) pour virement SWAN SCT
--   soignants.iban_titulaire   TEXT — nom du titulaire du compte
--   (soignants.iban_last4 existe déjà — synced depuis Stripe Connect)
--
-- Sécurité :
--   - RLS : soignant lit/écrit uniquement son propre IBAN
--   - RPCs SECURITY DEFINER : fn_enregistrer_mon_iban + fn_consulter_mon_iban
--   - Le worker (service_role) lit l'IBAN pour initier le virement SWAN
--   - L'établissement ne voit JAMAIS l'IBAN via ces RPCs
--
-- Audit : IBAN_RENSEIGNE / IBAN_MODIFIE ajoutés au CHECK constraint

-- 1) Colonnes
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS iban_virement TEXT,
  ADD COLUMN IF NOT EXISTS iban_titulaire TEXT;

COMMENT ON COLUMN public.soignants.iban_virement IS
  'IBAN complet (format FR76XXXX...) saisi par le soignant pour recevoir '
  'les primes de parrainage par virement SWAN SCT. Jamais pré-rempli, '
  'jamais partagé avec l''établissement.';

COMMENT ON COLUMN public.soignants.iban_titulaire IS
  'Nom du titulaire du compte bancaire (doit correspondre à l''identité du soignant).';

-- 2) RPC fn_enregistrer_mon_iban — saisi par le soignant LUI-MÊME
CREATE OR REPLACE FUNCTION public.fn_enregistrer_mon_iban(
  p_iban TEXT,
  p_titulaire TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_iban TEXT;
  v_last4 TEXT;
  v_ancien_iban TEXT;
  v_action TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  -- Normaliser : majuscules, supprimer espaces
  v_iban := UPPER(REGEXP_REPLACE(TRIM(p_iban), '\s+', '', 'g'));

  -- Validation format IBAN basique (2 lettres + 2 chiffres + 10-30 alphanum)
  IF v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$' THEN
    RETURN jsonb_build_object('error', 'Format IBAN invalide. Exemple : FR7630006000011234567890189');
  END IF;

  -- Validation checksum IBAN (ISO 7064 mod-97)
  DECLARE
    v_rearranged TEXT;
    v_numeric TEXT := '';
    v_char TEXT;
    v_remainder NUMERIC;
  BEGIN
    -- Déplacer les 4 premiers chars à la fin
    v_rearranged := SUBSTRING(v_iban FROM 5) || SUBSTRING(v_iban FROM 1 FOR 4);
    -- Convertir lettres en chiffres (A=10, B=11, ..., Z=35)
    FOR i IN 1..LENGTH(v_rearranged) LOOP
      v_char := SUBSTRING(v_rearranged FROM i FOR 1);
      IF v_char ~ '[A-Z]' THEN
        v_numeric := v_numeric || (ASCII(v_char) - 55)::TEXT;
      ELSE
        v_numeric := v_numeric || v_char;
      END IF;
    END LOOP;
    -- Mod 97 (traitement par blocs pour éviter overflow)
    v_remainder := 0;
    FOR i IN 1..LENGTH(v_numeric) LOOP
      v_remainder := (v_remainder * 10 + SUBSTRING(v_numeric FROM i FOR 1)::INT) % 97;
    END LOOP;
    IF v_remainder <> 1 THEN
      RETURN jsonb_build_object('error', 'IBAN invalide (checksum incorrecte). Vérifiez votre saisie.');
    END IF;
  END;

  IF TRIM(COALESCE(p_titulaire, '')) = '' THEN
    RETURN jsonb_build_object('error', 'Le nom du titulaire est obligatoire.');
  END IF;

  v_last4 := RIGHT(v_iban, 4);

  -- Vérifier si c'est un ajout ou une modification
  SELECT iban_virement INTO v_ancien_iban FROM soignants WHERE id = v_uid;
  v_action := CASE WHEN v_ancien_iban IS NULL OR v_ancien_iban = '' THEN 'IBAN_RENSEIGNE' ELSE 'IBAN_MODIFIE' END;

  UPDATE soignants
  SET iban_virement = v_iban,
      iban_titulaire = TRIM(p_titulaire),
      iban_last4 = v_last4
  WHERE id = v_uid;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := v_action,
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object('iban_last4', v_last4, 'titulaire', TRIM(p_titulaire))
  );

  RETURN jsonb_build_object(
    'success', true,
    'iban_last4', v_last4,
    'titulaire', TRIM(p_titulaire),
    'message', 'IBAN enregistré. Il sera utilisé pour le versement de vos primes.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_enregistrer_mon_iban(TEXT, TEXT) TO authenticated;

-- 3) RPC fn_consulter_mon_iban — retourne last4 + titulaire (jamais l'IBAN complet côté front)
CREATE OR REPLACE FUNCTION public.fn_consulter_mon_iban()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_result RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT iban_last4, iban_titulaire, iban_virement IS NOT NULL AS iban_renseigne
  INTO v_result
  FROM soignants WHERE id = v_uid;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('iban_renseigne', false);
  END IF;

  RETURN jsonb_build_object(
    'iban_renseigne', COALESCE(v_result.iban_renseigne, false),
    'iban_last4', v_result.iban_last4,
    'iban_titulaire', v_result.iban_titulaire
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_consulter_mon_iban() TO authenticated;

-- 4) RLS : masquer iban_virement dans les SELECT directs (defense-in-depth)
-- Le soignant peut lire sa propre ligne via les RPCs SECURITY DEFINER.
-- RLS empêche un autre soignant ou établissement de lire l'IBAN via query directe.
-- (La colonne est visible via service_role pour le worker SWAN.)

-- Pas besoin de nouvelle policy : la policy SELECT existante sur soignants
-- filtre déjà par auth.uid(). Mais on ajoute une couche : masquer iban_virement
-- dans les résultats des SELECT non service_role via une vue sécurisée n'est pas
-- nécessaire car les RPCs ne retournent jamais l'IBAN complet.

-- 5) Étendre audit CHECK pour IBAN actions
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
  'RGPD_EXPORT_DONNEES','RGPD_SUPPRESSION_COMPTE','RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT',
  'DEGEL_APPLIED','OVERRIDE_CHAMP_POST_GEL','GEL_APPLIED','OVERRIDE_ANTI_SEED',
  'CONNECT_METADATA_MANQUANTE','DOCUMENT_VERIFICATION_AUTO',
  'FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE','FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE',
  'FINANCE_CHARGE_EXPIRED','FINANCE_CHARGE_FAILED','FINANCE_CHARGE_PENDING',
  'FINANCE_CHARGE_REFUNDED','FINANCE_DISPUTE_CLOSE','FINANCE_DISPUTE_OUVERTE',
  'FINANCE_PAYOUT_CANCELED','FINANCE_PAYOUT_CREATED','FINANCE_PAYOUT_FAILED',
  'FINANCE_PAYOUT_PAID','FINANCE_SEPA_CAPTURE','FINANCE_TRANSFER_CONNECT',
  'FINANCE_TRANSFER_CREATED','FINANCE_TRANSFER_FAILED','FINANCE_TRANSFER_REVERSED',
  'FINANCE_TRANSFER_UPDATED','STRIPE_CHECKOUT_ORPHANED_RECOVERED',
  'STRIPE_CONNECT_ACCOUNT_DELETED','ATTESTATION_SANTE_SIGNEE',
  'EXCLUSION_CREEE','EXCLUSION_SUPPRIMEE','FACTURE_GENEREE',
  'MISSION_ANNULATION_SERIE','MISSION_MODIFICATION','PAIEMENT_SOIGNANT_DECLARE_ETAB',
  'RECLAMATION_CREEE','ADMIN_CONSULTATION_ETABLISSEMENT','ADMIN_CONSULTATION_SOIGNANT',
  'DOCUMENT_SUPPRESSION','HEURES_EXTERNES_DECLAREES','MISSION_ANNULATION',
  'NOTE_HONORAIRES_GENEREE','PRESENCE_CONTESTATION','PRESENCE_POINTAGE_ARRIVEE',
  'PRESENCE_VALIDATION','PRESENCE_VALIDATION_LOT','RGPD_CONSENTEMENT_DONNE',
  'PAIEMENT_MONTANT_ECART','FACTURE_COMMISSION_CREATED_VIA_STRIPE',
  'TAUX_COMMISSION_MODIFIE','LITIGE_GEL_SCOPE_MODIFIE','PREFERENCE_NOTIFICATION_MODIFIEE',
  'NOTIFICATION_SKIPPED','SERIE_EMAIL_ENVOYE','SERIE_EMAIL_SKIPPED',
  'FILTRE_CREE','FILTRE_MODIFIE','FILTRE_SUPPRIME',
  'ALERTE_ACTIVEE','ALERTE_DESACTIVEE','ALERTE_ENVOYEE',
  'POOL_URGENCE_NOTIFICATIONS_ENVOYEES','POOL_URGENCE_ACCEPTATION_RAPIDE',
  'POOL_URGENCE_VALIDATION_ETAB','POOL_URGENCE_REFUS_ETAB','POOL_URGENCE_SMS_TOGGLE',
  'FAVORI_AJOUTE','FAVORI_RETIRE','SCORE_FIABILITE_PENALITE_LITIGE',
  'PARRAINAGE_ETAB_APPLIQUE','PARRAINAGE_ETAB_VALIDE','CREDIT_PARRAINAGE_CREE',
  'CREDIT_PARRAINAGE_APPLIQUE','PARRAINAGE_ETAB_ANOMALIE',
  'PARRAINAGE_SOIGNANT_FILLEUL_ACTIF','PARRAINAGE_SOIGNANT_SEUIL_ATTEINT',
  'PARRAINAGE_SOIGNANT_PRIME_VERSEE','PARRAINAGE_SOIGNANT_FRAUDE',
  'INSCRIPTION_LISTE_ATTENTE_PREVOYANCE','SCORE_RECALCULE_V2',
  'IBAN_RENSEIGNE','IBAN_MODIFIE'
]));

NOTIFY pgrst, 'reload schema';
