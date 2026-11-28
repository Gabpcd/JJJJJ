-- Journal d'audit : trois actions écrites par le code et refusées par le CHECK.
--
-- Constat (production relue en lecture seule le 28/11/2026) :
-- journaux_audit_action_check (pg_get_constraintdef md5
-- 5d8ca35986765f1530b47d63b9f8f432, 160 actions) ne contient pas :
--   * IDENTITE_PROFIL_MODIFIEE, écrite par
--     public.fn_invalider_preuves_identite_sur_changement (déclencheur des
--     changements de nom, prénom ou date de naissance d'un soignant, dont la
--     suppression du compte) via public.fn_ecrire_audit_safe. Cette fonction
--     avale l'erreur du CHECK (EXCEPTION WHEN OTHERS → success false) : l'audit
--     de modification d'identité est muet, sans erreur visible. Aucune ligne
--     IDENTITE_PROFIL_MODIFIEE n'existe en production.
--   * RGPD_SUPPRESSION_COMPTE_MEMBRE_ETABLISSEMENT et
--     RGPD_SUPPRESSION_COMPTE_ADMIN_GROUPE, insérées directement par l'edge
--     delete-account (retrait d'un collaborateur ou d'un administrateur de
--     groupe à la suppression de son compte) ; l'erreur est ignorée côté edge.
-- Même défaut que les alignements de CHECK du Sprint 17 (contrainte
-- désynchronisée du code applicatif) : on ajoute les trois actions.
--
-- Hors périmètre, relevé par la même lecture (requête p_action := '…' sur
-- pg_proc) : quatorze autres actions écrites par des fonctions LIVE sont
-- absentes du CHECK (docs/CONFORMITE.md §6.6) ; alignement complet et garde
-- statique à traiter séparément.
--
-- Méthode : préflight fail-closed sur l'empreinte LIVE de la contrainte (la
-- liste ci-dessous est la liste LIVE, dans le même ordre, suivie des trois
-- actions), DROP puis ADD dans la même transaction (validation de toutes les
-- lignes existantes : 221 784 lignes, 160 Mo au 28/11/2026), post-condition sur
-- l'empreinte installée. journaux_audit reste immuable : aucune ligne n'est
-- écrite, modifiée ou supprimée.
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

DO $audit_actions_avant$
DECLARE
  v_def text;
BEGIN
  SELECT pg_catalog.pg_get_constraintdef(c.oid) INTO v_def
    FROM pg_catalog.pg_constraint c
   WHERE c.conrelid = 'public.journaux_audit'::pg_catalog.regclass
     AND c.conname = 'journaux_audit_action_check' AND c.contype = 'c';
  IF v_def IS NULL OR pg_catalog.md5(v_def) IS DISTINCT FROM '5d8ca35986765f1530b47d63b9f8f432' THEN
    RAISE EXCEPTION 'AUDIT_ACTIONS_SOURCE_DIVERGENTE : journaux_audit_action_check (md5 %) ne correspond plus à la contrainte LIVE relue le 28/11/2026 (md5 5d8ca35986765f1530b47d63b9f8f432). Repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
      COALESCE(pg_catalog.md5(v_def), 'contrainte absente');
  END IF;
END
$audit_actions_avant$;

ALTER TABLE public.journaux_audit DROP CONSTRAINT journaux_audit_action_check;
ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_action_check CHECK ((action = ANY (ARRAY[
    'ANNULATION_EMPECHEMENT_IMPERIEUX'::text, 'INSCRIPTION'::text, 'CONNEXION'::text,
    'DECONNEXION'::text, 'MODIFICATION_PROFIL'::text, 'SUPPRESSION_COMPTE'::text,
    'UPLOAD_DOCUMENT'::text, 'TELECHARGEMENT_DOCUMENT'::text, 'VERIFICATION_DOCUMENT'::text,
    'VERIFICATION_RPPS'::text, 'CREATION_MISSION'::text, 'MODIFICATION_MISSION'::text,
    'ANNULATION_MISSION'::text, 'CANDIDATURE'::text, 'ASSIGNATION'::text,
    'POINTAGE'::text, 'SIGNATURE_CONTRAT'::text, 'EVALUATION'::text,
    'PAIEMENT'::text, 'FACTURATION'::text, 'DONNEES_PERSO_CONSULTATION'::text,
    'DONNEES_PERSO_EXPORT'::text, 'DONNEES_PERSO_SUPPRESSION'::text, 'ADMIN_ACTION'::text,
    'SYSTEM'::text, 'RIB_CONSULTE'::text, 'RIB_PARTAGE'::text,
    'CONTRAT_SIGNE'::text, 'DOCUMENT_CONSULTATION'::text, 'DOCUMENT_TELEVERSEMENT'::text,
    'DONNEES_PERSO_MODIFICATION'::text, 'EXPORT_RH_PAIE'::text, 'FINANCE_FACTURE_PAYEE'::text,
    'MISSION_ASSIGNATION'::text, 'MISSION_CREATION'::text, 'RGPD_EXPORT_DONNEES'::text,
    'RGPD_SUPPRESSION_COMPTE'::text, 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT'::text, 'DEGEL_APPLIED'::text,
    'OVERRIDE_CHAMP_POST_GEL'::text, 'GEL_APPLIED'::text, 'OVERRIDE_ANTI_SEED'::text,
    'CONNECT_METADATA_MANQUANTE'::text, 'DOCUMENT_VERIFICATION_AUTO'::text, 'FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE'::text,
    'FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE'::text, 'FINANCE_CHARGE_EXPIRED'::text, 'FINANCE_CHARGE_FAILED'::text,
    'FINANCE_CHARGE_PENDING'::text, 'FINANCE_CHARGE_REFUNDED'::text, 'FINANCE_DISPUTE_CLOSE'::text,
    'FINANCE_DISPUTE_OUVERTE'::text, 'FINANCE_PAYOUT_CANCELED'::text, 'FINANCE_PAYOUT_CREATED'::text,
    'FINANCE_PAYOUT_FAILED'::text, 'FINANCE_PAYOUT_PAID'::text, 'FINANCE_SEPA_CAPTURE'::text,
    'FINANCE_TRANSFER_CONNECT'::text, 'FINANCE_TRANSFER_CREATED'::text, 'FINANCE_TRANSFER_FAILED'::text,
    'FINANCE_TRANSFER_REVERSED'::text, 'FINANCE_TRANSFER_UPDATED'::text, 'STRIPE_CHECKOUT_ORPHANED_RECOVERED'::text,
    'STRIPE_CONNECT_ACCOUNT_DELETED'::text, 'ATTESTATION_SANTE_SIGNEE'::text, 'EXCLUSION_CREEE'::text,
    'EXCLUSION_SUPPRIMEE'::text, 'FACTURE_GENEREE'::text, 'MISSION_ANNULATION_SERIE'::text,
    'MISSION_MODIFICATION'::text, 'PAIEMENT_SOIGNANT_DECLARE_ETAB'::text, 'RECLAMATION_CREEE'::text,
    'ADMIN_CONSULTATION_ETABLISSEMENT'::text, 'ADMIN_CONSULTATION_SOIGNANT'::text, 'DOCUMENT_SUPPRESSION'::text,
    'HEURES_EXTERNES_DECLAREES'::text, 'MISSION_ANNULATION'::text, 'NOTE_HONORAIRES_GENEREE'::text,
    'PRESENCE_CONTESTATION'::text, 'PRESENCE_POINTAGE_ARRIVEE'::text, 'PRESENCE_VALIDATION'::text,
    'PRESENCE_VALIDATION_LOT'::text, 'RGPD_CONSENTEMENT_DONNE'::text, 'PAIEMENT_MONTANT_ECART'::text,
    'FACTURE_COMMISSION_CREATED_VIA_STRIPE'::text, 'TAUX_COMMISSION_MODIFIE'::text, 'LITIGE_GEL_SCOPE_MODIFIE'::text,
    'PREFERENCE_NOTIFICATION_MODIFIEE'::text, 'NOTIFICATION_SKIPPED'::text, 'SERIE_EMAIL_ENVOYE'::text,
    'SERIE_EMAIL_SKIPPED'::text, 'FILTRE_CREE'::text, 'FILTRE_MODIFIE'::text,
    'FILTRE_SUPPRIME'::text, 'ALERTE_ACTIVEE'::text, 'ALERTE_DESACTIVEE'::text,
    'ALERTE_ENVOYEE'::text, 'POOL_URGENCE_NOTIFICATIONS_ENVOYEES'::text, 'POOL_URGENCE_ACCEPTATION_RAPIDE'::text,
    'POOL_URGENCE_VALIDATION_ETAB'::text, 'POOL_URGENCE_REFUS_ETAB'::text, 'POOL_URGENCE_SMS_TOGGLE'::text,
    'FAVORI_AJOUTE'::text, 'FAVORI_RETIRE'::text, 'SCORE_FIABILITE_PENALITE_LITIGE'::text,
    'PARRAINAGE_ETAB_APPLIQUE'::text, 'PARRAINAGE_ETAB_VALIDE'::text, 'CREDIT_PARRAINAGE_CREE'::text,
    'CREDIT_PARRAINAGE_APPLIQUE'::text, 'PARRAINAGE_ETAB_ANOMALIE'::text, 'PARRAINAGE_SOIGNANT_FILLEUL_ACTIF'::text,
    'PARRAINAGE_SOIGNANT_SEUIL_ATTEINT'::text, 'PARRAINAGE_SOIGNANT_PRIME_VERSEE'::text, 'PARRAINAGE_SOIGNANT_FRAUDE'::text,
    'INSCRIPTION_LISTE_ATTENTE_PREVOYANCE'::text, 'SCORE_RECALCULE_V2'::text, 'IBAN_RENSEIGNE'::text,
    'IBAN_MODIFIE'::text, 'AVOIR_REMBOURSEMENT_CONFIRME'::text, 'ETABLISSEMENT_MODIFICATION'::text,
    'LITIGE_ACCORD_CLOTURE'::text, 'LITIGE_AUTO_CREATION'::text, 'LITIGE_CLOTURE_AMIABLE'::text,
    'LITIGE_CREATION'::text, 'LITIGE_ESCALADE_AUTO'::text, 'LITIGE_FORCE_CREATION'::text,
    'LITIGE_OUVERTURE'::text, 'LITIGE_OUVERTURE_LEGACY'::text, 'LITIGE_RECATEGORISATION_LEGACY'::text,
    'LITIGE_REPONSE'::text, 'LITIGE_RESOLUTION'::text, 'PRESENCE_ALERTE_FRAUDE'::text,
    'RGPD_SUPPRESSION_DONNEES'::text, 'TVA_MODIFICATION'::text, 'API_KEY_CREEE'::text,
    'API_KEY_REVOQUEE'::text, 'API_KEY_SUPPRIMEE'::text, 'FACTURE_MARQUEE_EN_RETARD'::text,
    'HEURES_EXTERNES_VALIDATION_MANUELLE'::text, 'MISSION_ANNULEE_PAR_SOIGNANT'::text, 'MISSION_ANNULEE_PAR_ETABLISSEMENT'::text,
    'MISSION_LITIGE'::text, 'MISSION_TYPE_CONTRAT_MODIFIE'::text, 'MODERATION_DOCUMENT'::text,
    'COHERENCE_IDENTITE_VERIFIEE'::text, 'MODERATION_EVALUATION'::text, 'COHERENCE_DOCUMENTS_ALERTE'::text,
    'ESCROW_INITIE'::text, 'ESCROW_DEBIT_INITIE'::text, 'ESCROW_DEBITE'::text,
    'ESCROW_ETAB_GELE'::text, 'ESCROW_ETAB_DEGELE'::text, 'ESCROW_REMBOURSEMENT_ENFILE'::text,
    'ESCROW_REMBOURSE'::text, 'ESCROW_DISPONIBLE'::text, 'ESCROW_RELEASE_PAYE'::text,
    'ESCROW_RELEASE_ATTENTE_FONDS'::text, 'PRESENCE_RELANCE_VALIDATION'::text, 'SUSPENSION_COMPTE'::text,
    'REACTIVATION_COMPTE'::text, 'IDENTITE_PROFIL_MODIFIEE'::text, 'RGPD_SUPPRESSION_COMPTE_MEMBRE_ETABLISSEMENT'::text,
    'RGPD_SUPPRESSION_COMPTE_ADMIN_GROUPE'::text
])));

DO $audit_actions_apres$
DECLARE
  v_def text;
BEGIN
  SELECT pg_catalog.pg_get_constraintdef(c.oid) INTO v_def
    FROM pg_catalog.pg_constraint c
   WHERE c.conrelid = 'public.journaux_audit'::pg_catalog.regclass
     AND c.conname = 'journaux_audit_action_check' AND c.contype = 'c' AND c.convalidated;
  IF v_def IS NULL OR pg_catalog.md5(v_def) IS DISTINCT FROM 'd34d197dbf9da68e8ba340e0824ce765' THEN
    RAISE EXCEPTION 'AUDIT_ACTIONS_POSTCONDITION : contrainte installée inattendue (md5 %).', COALESCE(pg_catalog.md5(v_def), 'absente ou non validée');
  END IF;
END
$audit_actions_apres$;
