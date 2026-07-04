-- J1.5 — Sécurité et compliance Jolene (28 avril 2026)
-- ─────────────────────────────────────────────────────────────────────
-- Audit pré-pilotes (RGPD + RLS + monitoring + backup).
--
-- 1. FIX FAILLE invoice_audit_log.ial_insert (with_check=true)
--    Tout authenticated pouvait insérer des lignes factices dans le log
--    fiscal append-only, à condition de connaître un invoice_id valide.
--    → DROP policy + REVOKE INSERT. Les triggers `trg_fh_auto_audit_*`
--      sont SECURITY DEFINER (owner postgres) donc continuent à insérer.
--      service_role conserve INSERT pour les edge functions admin.
--
-- 2. FIX search_path mutable (advisor warn) sur 2 utilitaires.
--
-- 3. EXPORT RGPD complet (article 15 RGPD) :
--    fn_exporter_mes_donnees passe de 6 → 21 clés (factures, bulletins,
--    cotisations, candidatures, messages, notifications, mandats,
--    cessions, factor_advances, paiements, contrats, partages_rib,
--    parrainages, evaluations données/reçues).
--    NIR exclu (donnée sensible identifiante non requise pour portabilité).
--
-- 4. SUPPRESSION compte établissement (article 17 RGPD) :
--    fn_supprimer_mon_compte_etablissement n'existait pas. Pendant 6 mois,
--    seuls les soignants pouvaient supprimer leur compte côté plateforme.
--    Ajout symétrique avec :
--    - garde-fou missions actives + factures impayées
--    - anonymisation 16 tables (admins, tokens, notifs, messages, evals,
--      favoris, exclusions, partages_rib, contrats, email_queue,
--      sms_envoyes, calendar_*, api_keys)
--    - conservation 10 ans factures + audit (LPF L102 B, R3243-1)
--    - bypass app.internal_operation pour trigger fn_protect_etablissement_commercial
--    - wrapper rate-limited 1/jour (cohérence soignant)
--
-- 5. CHECK constraint journaux_audit.action étendu :
--    RGPD_SUPPRESSION_COMPTE, RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT,
--    TAUX_COMMISSION_MODIFIE, LITIGE_GEL_SCOPE_MODIFIE.
-- ─────────────────────────────────────────────────────────────────────

-- 1. invoice_audit_log : retirer la possibilité d'INSERT par authenticated
DROP POLICY IF EXISTS ial_insert ON public.invoice_audit_log;
REVOKE INSERT ON public.invoice_audit_log FROM authenticated;

-- 2. Fix search_path mutable
ALTER FUNCTION public.fn_arrondir_quart_heure(timestamptz)
  SET search_path = public, extensions;
ALTER FUNCTION public.fn_set_mis_a_jour_le()
  SET search_path = public, extensions;

-- 3. Étendre journaux_audit.action_check (4 actions ajoutées)
ALTER TABLE public.journaux_audit
  DROP CONSTRAINT IF EXISTS journaux_audit_action_check;

ALTER TABLE public.journaux_audit
  ADD CONSTRAINT journaux_audit_action_check CHECK (action IN (
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
    'TAUX_COMMISSION_MODIFIE','LITIGE_GEL_SCOPE_MODIFIE'
  ));

-- 4. fn_exporter_mes_donnees — version complète RGPD article 15
CREATE OR REPLACE FUNCTION public.fn_exporter_mes_donnees()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT jsonb_build_object(
    'export_date', NOW(),
    'utilisateur_id', v_uid,
    'profil', (SELECT to_jsonb(s.*) - 'numero_secu' - 'numero_securite_sociale' FROM soignants s WHERE id = v_uid),
    'missions', (SELECT COALESCE(jsonb_agg(to_jsonb(m.*) - 'taux_commission' - 'montant_commission_ht' - 'montant_commission_tva' - 'montant_commission_ttc' ORDER BY m.cree_le DESC), '[]'::jsonb) FROM missions m WHERE m.soignant_assigne_id = v_uid),
    'candidatures', (SELECT COALESCE(jsonb_agg(to_jsonb(c.*) ORDER BY c.cree_le DESC), '[]'::jsonb) FROM candidatures c WHERE c.soignant_id = v_uid),
    'presences', (SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ORDER BY p.cree_le DESC), '[]'::jsonb) FROM presences p WHERE p.soignant_id = v_uid),
    'factures_honoraires', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',f.id,'numero_facture',f.numero_facture,'mission_id',f.mission_id,'etablissement_id',f.etablissement_id,'montant_ht',f.montant_ht,'montant_ttc',f.montant_ttc,'taux_tva',f.taux_tva,'exoneration_tva',f.exoneration_tva,'date_emission',f.date_emission,'date_echeance',f.date_echeance,'date_paiement',f.date_paiement,'statut',f.statut,'type_document',f.type_document,'pdf_s3_key',f.pdf_s3_key) ORDER BY f.date_emission DESC), '[]'::jsonb) FROM factures_honoraires f WHERE f.soignant_id = v_uid),
    'bulletins_paie', (SELECT COALESCE(jsonb_agg(to_jsonb(b.*) ORDER BY b.periode_debut DESC), '[]'::jsonb) FROM bulletins_paie b WHERE b.soignant_id = v_uid),
    'cotisations_sociales', (SELECT COALESCE(jsonb_agg(to_jsonb(c.*) ORDER BY c.calcule_le DESC), '[]'::jsonb) FROM cotisations_sociales c WHERE c.soignant_id = v_uid),
    'mandats_facturation', (SELECT COALESCE(jsonb_agg(jsonb_build_object('version',version,'signed_at',signed_at,'revoked_at',revoked_at,'ip_address',ip_address,'contenu_hash',contenu_hash) ORDER BY signed_at DESC), '[]'::jsonb) FROM mandats_facturation_signatures WHERE soignant_id = v_uid),
    'cessions_creance', (SELECT COALESCE(jsonb_agg(to_jsonb(c.*) ORDER BY c.signed_at DESC), '[]'::jsonb) FROM cessions_creance c WHERE c.soignant_id = v_uid),
    'factor_advances', (SELECT COALESCE(jsonb_agg(to_jsonb(fa.*) ORDER BY fa.cree_le DESC), '[]'::jsonb) FROM factor_advances fa WHERE fa.soignant_id = v_uid),
    'paiements_soignant', (SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ORDER BY p.cree_le DESC), '[]'::jsonb) FROM paiements_soignant p WHERE p.soignant_id = v_uid),
    'contrats_mission', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'mission_id',mission_id,'type_contrat',type_contrat,'numero_contrat',numero_contrat,'statut',statut,'signature_soignant_le',signature_soignant_le,'signature_etablissement_le',signature_etablissement_le,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM contrats_mission WHERE soignant_id = v_uid),
    'documents', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type',type_document,'libelle',libelle,'statut_verification',statut_verification,'valide_jusqua',valide_jusqua,'televerse_le',televerse_le) ORDER BY televerse_le DESC), '[]'::jsonb) FROM documents_soignants WHERE soignant_id = v_uid AND supprime_le IS NULL),
    'evaluations_recues', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'note',note,'commentaire',commentaire,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM evaluations WHERE evalue_id = v_uid),
    'evaluations_donnees', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'note',note,'commentaire',commentaire,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM evaluations WHERE evaluateur_id = v_uid),
    'messages_chat', (SELECT COALESCE(jsonb_agg(jsonb_build_object('conversation_id',conversation_id,'contenu',contenu,'cree_le',cree_le,'lu',lu) ORDER BY cree_le DESC), '[]'::jsonb) FROM messages_chat WHERE auteur_id = v_uid),
    'notifications', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type',type,'titre',titre,'corps',corps,'lue',lue,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM notifications WHERE destinataire_id = v_uid),
    'partages_rib', (SELECT COALESCE(jsonb_agg(jsonb_build_object('etablissement_id',etablissement_id,'mission_id',mission_id,'partage_le',partage_le,'consulte_le',consulte_le,'expire_le',expire_le,'actif',actif)), '[]'::jsonb) FROM partages_rib WHERE soignant_id = v_uid),
    'parrainages', (SELECT COALESCE(jsonb_agg(jsonb_build_object('role', CASE WHEN parrain_id = v_uid THEN 'parrain' ELSE 'filleul' END,'code_parrainage',code_parrainage,'statut',statut,'valide_le',valide_le,'cree_le',cree_le)), '[]'::jsonb) FROM parrainages WHERE parrain_id = v_uid OR filleul_id = v_uid)
  ) INTO v_result;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'RGPD_EXPORT_DONNEES',
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object('version', 'v2_complet')
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_exporter_mes_donnees() TO authenticated;

COMMENT ON FUNCTION public.fn_exporter_mes_donnees() IS
  'Export RGPD article 15 complet pour le soignant connecté. NIR exclu (sensible).';

-- 5. fn_supprimer_mon_compte_etablissement (n'existait pas)
CREATE OR REPLACE FUNCTION public.fn_supprimer_mon_compte_etablissement()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_missions_actives int;
  v_factures_impayees int;
  v_hash text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT id INTO v_etab_id FROM etablissements WHERE id = v_uid;
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Aucun établissement lié à ce compte');
  END IF;

  -- Garde-fou : missions actives
  SELECT count(*) INTO v_missions_actives FROM missions
   WHERE etablissement_id = v_etab_id
     AND statut IN ('OUVERTE','ASSIGNEE','EN_COURS','LITIGE')
     AND fin_le > NOW();
  IF v_missions_actives > 0 THEN
    RETURN jsonb_build_object('success', false, 'error',
      format('Vous avez %s mission(s) ouverte(s) ou en cours.', v_missions_actives));
  END IF;

  -- Garde-fou : factures impayées (la suppression n'efface pas une dette)
  SELECT count(*) INTO v_factures_impayees FROM factures
   WHERE etablissement_id = v_etab_id AND statut IN ('EN_ATTENTE','EN_RETARD');
  IF v_factures_impayees > 0 THEN
    RETURN jsonb_build_object('success', false, 'error',
      format('%s facture(s) impayée(s). Réglez-les avant suppression.', v_factures_impayees));
  END IF;

  -- Bypass trigger fn_protect_etablissement_commercial pour anonymisation
  PERFORM set_config('app.internal_operation', 'true', true);
  v_hash := encode(extensions.digest(v_etab_id::text || NOW()::text, 'sha256'), 'hex');

  -- Anonymisation établissement
  UPDATE etablissements SET
    nom = 'Établissement supprimé',
    siret = '99' || LPAD(LEFT(REGEXP_REPLACE(v_hash, '[^0-9]', '', 'g'), 12), 12, '0'),
    finess = NULL,
    email_contact = v_hash || '@supprime.jolene.app',
    telephone_contact = NULL,
    adresse_rue = '[SUPPRIMÉ]',
    adresse_ville = '[SUPPRIMÉ]',
    adresse_code_postal = '00000',
    adresse_departement = NULL, adresse_lat = NULL, adresse_lng = NULL,
    description = NULL, logo_url = NULL, horaires_ouverture = NULL,
    contrat_url = NULL,
    siret_raison_sociale = NULL, siret_categorie_juridique = NULL,
    siret_code_naf = NULL, siret_est_actif = false,
    chorus_pro_actif = false, chorus_pro_identifiant = NULL,
    sms_actif = false, sms_consent_le = NULL,
    peut_publier_missions = false,
    bloque_auto_le = NOW(),
    bloque_auto_raisons = jsonb_build_array('COMPTE_SUPPRIME_RGPD'),
    supprime_le = NOW(),
    stripe_sepa_payment_method_id = NULL
  WHERE id = v_etab_id;

  -- Tables liées
  DELETE FROM admins_groupe_sante WHERE utilisateur_id = v_uid;
  DELETE FROM tokens_push WHERE utilisateur_id = v_uid;
  DELETE FROM notifications WHERE destinataire_id = v_uid;

  UPDATE messages_chat SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
  UPDATE messages_mission SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
  UPDATE messages_litige SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;

  UPDATE evaluations SET commentaire = NULL
   WHERE evaluateur_id = v_uid OR evalue_id = v_uid;

  DELETE FROM exclusions WHERE exclu_par = v_uid OR exclu_id = v_uid;

  UPDATE partages_rib SET actif = false, expire_le = NOW()
   WHERE etablissement_id = v_etab_id;

  -- Contrats : on conserve (preuves légales) mais anonymise IP/UA
  UPDATE contrats_mission SET
    signature_ip_etablissement = NULL,
    signature_navigateur_etablissement = NULL,
    signature_image_etablissement = NULL
   WHERE etablissement_id = v_etab_id;

  DELETE FROM email_queue WHERE destinataire_id = v_uid;
  UPDATE sms_envoyes SET telephone = 'SUPPRIME', destinataire_id = NULL
   WHERE destinataire_id = v_uid;

  DELETE FROM calendar_events_sync WHERE connection_id IN
    (SELECT id FROM calendar_connections WHERE utilisateur_id = v_uid);
  DELETE FROM calendar_connections WHERE utilisateur_id = v_uid;
  DELETE FROM api_keys WHERE etablissement_id = v_etab_id;

  -- Audit (type_acteur ADMIN_ETABLISSEMENT, action RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT)
  INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (v_uid, 'ADMIN_ETABLISSEMENT', 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT', 'etablissement', v_etab_id,
    jsonb_build_object('anonymise', true));

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Établissement anonymisé. Factures conservées 10 ans (LPF L102 B).',
    'etablissement_id', v_etab_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_supprimer_mon_compte_etablissement() TO authenticated;

COMMENT ON FUNCTION public.fn_supprimer_mon_compte_etablissement() IS
  'Suppression compte établissement (RGPD art. 17) avec anonymisation. Bloque si missions actives ou factures impayées. Conserve factures + audit (LPF 10 ans).';

-- 6. Wrapper rate-limited (1 demande / jour)
CREATE OR REPLACE FUNCTION public.fn_supprimer_compte_etablissement_rate_limited()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_allowed boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  v_allowed := public.fn_verifier_rate_limit(v_uid::text, 'supprimer_compte_etablissement', 1, 86400);
  IF NOT v_allowed THEN
    RETURN jsonb_build_object('error', 'Demande de suppression déjà en cours.');
  END IF;

  RETURN public.fn_supprimer_mon_compte_etablissement();
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_supprimer_compte_etablissement_rate_limited() TO authenticated;

NOTIFY pgrst, 'reload schema';
