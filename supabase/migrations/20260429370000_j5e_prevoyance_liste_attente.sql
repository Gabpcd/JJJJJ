-- J5.E — Prévoyance Madelin : liste d'attente (pas de partenariat April actif)
--
-- Décision business : PAS de redirection partenaire pour l'instant.
-- Levier de négociation futur ("J'ai X soignants intéressés").
-- L'ancienne RPC fn_souscrire_prevoyance interne reste en DB (dépréciée côté UI),
-- les tables plans_prevoyance + souscriptions_prevoyance conservées (cf. tech-debt.md).

-- 1) Enum niveau souhaité
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'niveau_prevoyance_souhaite') THEN
    CREATE TYPE public.niveau_prevoyance_souhaite AS ENUM ('BRONZE','ARGENT','OR','INDIFFERENT');
  END IF;
END $$;

-- 2) Table prevoyance_liste_attente
CREATE TABLE IF NOT EXISTS public.prevoyance_liste_attente (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id UUID REFERENCES public.soignants(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  niveau_souhaite public.niveau_prevoyance_souhaite NOT NULL DEFAULT 'INDIFFERENT',
  cree_le TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  mis_a_jour_le TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (email)
);

CREATE INDEX IF NOT EXISTS idx_prevoyance_la_soignant ON public.prevoyance_liste_attente (soignant_id);
CREATE INDEX IF NOT EXISTS idx_prevoyance_la_cree ON public.prevoyance_liste_attente (cree_le DESC);

ALTER TABLE public.prevoyance_liste_attente ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_prev_la_select ON public.prevoyance_liste_attente;
CREATE POLICY pol_prev_la_select ON public.prevoyance_liste_attente FOR SELECT
  USING (soignant_id = auth.uid() OR (SELECT est_admin()));

DROP POLICY IF EXISTS pol_prev_la_insert ON public.prevoyance_liste_attente;
CREATE POLICY pol_prev_la_insert ON public.prevoyance_liste_attente FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS pol_prev_la_update ON public.prevoyance_liste_attente;
CREATE POLICY pol_prev_la_update ON public.prevoyance_liste_attente FOR UPDATE
  USING (soignant_id = auth.uid() OR (SELECT est_admin()));

GRANT SELECT, INSERT, UPDATE ON public.prevoyance_liste_attente TO authenticated;
GRANT SELECT, INSERT ON public.prevoyance_liste_attente TO anon;
GRANT ALL ON public.prevoyance_liste_attente TO service_role;

-- 3) Audit constraint étendu : INSCRIPTION_LISTE_ATTENTE_PREVOYANCE
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
  'INSCRIPTION_LISTE_ATTENTE_PREVOYANCE'
]));

-- 4) RPC fn_inscrire_liste_attente_prevoyance
CREATE OR REPLACE FUNCTION public.fn_inscrire_liste_attente_prevoyance(
  p_email TEXT,
  p_niveau TEXT DEFAULT 'INDIFFERENT'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_email_clean TEXT;
  v_niveau public.niveau_prevoyance_souhaite;
  v_id UUID;
  v_existing UUID;
BEGIN
  v_email_clean := LOWER(TRIM(COALESCE(p_email, '')));
  IF v_email_clean = '' OR v_email_clean !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Email invalide');
  END IF;

  BEGIN
    v_niveau := COALESCE(UPPER(TRIM(p_niveau)), 'INDIFFERENT')::public.niveau_prevoyance_souhaite;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'Niveau invalide (BRONZE/ARGENT/OR/INDIFFERENT)');
  END;

  SELECT id INTO v_existing FROM prevoyance_liste_attente WHERE email = v_email_clean;
  IF v_existing IS NOT NULL THEN
    UPDATE prevoyance_liste_attente
    SET niveau_souhaite = v_niveau,
        soignant_id = COALESCE(v_uid, soignant_id),
        mis_a_jour_le = NOW()
    WHERE id = v_existing
    RETURNING id INTO v_id;
  ELSE
    INSERT INTO prevoyance_liste_attente (soignant_id, email, niveau_souhaite)
    VALUES (v_uid, v_email_clean, v_niveau)
    RETURNING id INTO v_id;
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := COALESCE(v_uid, v_id),
    p_type_acteur := CASE WHEN v_uid IS NULL THEN 'SYSTEME' ELSE 'SOIGNANT' END,
    p_action := 'INSCRIPTION_LISTE_ATTENTE_PREVOYANCE',
    p_type_ressource := 'prevoyance_liste_attente',
    p_id_ressource := v_id,
    p_details := jsonb_build_object('email', v_email_clean, 'niveau', v_niveau::text, 'updated', v_existing IS NOT NULL)
  );

  RETURN jsonb_build_object(
    'success', true,
    'id', v_id,
    'updated', v_existing IS NOT NULL,
    'message', 'Vous êtes inscrit·e sur la liste d''attente. Vous serez prévenu·e dès le lancement.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_inscrire_liste_attente_prevoyance(TEXT, TEXT) TO authenticated, anon;

-- 5) fn_exporter_mes_donnees v7 : 27 clés (ajout prevoyance_liste_attente)
CREATE OR REPLACE FUNCTION public.fn_exporter_mes_donnees()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
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
    'parrainages', (SELECT COALESCE(jsonb_agg(jsonb_build_object('role', CASE WHEN parrain_id = v_uid THEN 'parrain' ELSE 'filleul' END,'code_parrainage',code_parrainage,'statut',statut,'valide_le',valide_le,'cree_le',cree_le)), '[]'::jsonb) FROM parrainages WHERE parrain_id = v_uid OR filleul_id = v_uid),
    'preferences_notifications', (SELECT to_jsonb(p) - 'utilisateur_id' FROM preferences_notifications p WHERE utilisateur_id = v_uid),
    'preferences_notifications_par_evenement', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type_evenement',type_evenement,'canal',canal,'actif',actif)), '[]'::jsonb) FROM preferences_notifications_par_evenement WHERE utilisateur_id = v_uid),
    'serie_email_envois', (SELECT COALESCE(jsonb_agg(jsonb_build_object('serie',serie,'etape',etape,'planifie_le',planifie_le,'envoye_le',envoye_le,'statut',statut,'skip_raison',skip_raison) ORDER BY planifie_le DESC), '[]'::jsonb) FROM serie_email_envois WHERE utilisateur_id = v_uid),
    'filtres_sauvegardes', (SELECT COALESCE(jsonb_agg(jsonb_build_object('nom',nom,'audience',audience,'filtres',filtres,'alerte_active',alerte_active,'frequence_alerte',frequence_alerte,'dernier_check_le',dernier_check_le,'nb_resultats_dernier_check',nb_resultats_dernier_check,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM filtres_sauvegardes WHERE utilisateur_id = v_uid),
    'favoris_etablissements', (SELECT COALESCE(jsonb_agg(jsonb_build_object('etablissement_id', etablissement_id, 'cree_le', cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM favoris_soignant_etab WHERE soignant_id = v_uid),
    'prevoyance_liste_attente', (SELECT COALESCE(jsonb_agg(jsonb_build_object('email', email, 'niveau_souhaite', niveau_souhaite, 'cree_le', cree_le, 'mis_a_jour_le', mis_a_jour_le)), '[]'::jsonb) FROM prevoyance_liste_attente WHERE soignant_id = v_uid)
  ) INTO v_result;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'RGPD_EXPORT_DONNEES',
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object('version', 'v7_avec_prevoyance_liste_attente')
  );

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
