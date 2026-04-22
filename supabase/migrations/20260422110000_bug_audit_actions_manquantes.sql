-- ============================================================
-- BUG-AUDIT-ACTIONS-MANQUANTES (P1) — CHECK constraint étendu
-- ============================================================
-- Problème : journaux_audit_action_check refusait silencieusement
-- ~42 actions utilisées en prod par le code Stripe/Connect +
-- RPCs + frontend. `fn_ecrire_audit_safe` swallow les CHECK
-- violations (EXCEPTION WHEN OTHERS → RAISE WARNING + return
-- success=false) → 0 audit persisté pour ces actions malgré
-- le code les écrivant.
--
-- Conséquences :
--   - Traçabilité RGPD dégradée
--   - Diagnostic webhook impossible (cf. M2 paiement Stripe
--     22/04 09:08 — on ne peut pas savoir pourquoi la branche
--     CONNECT_MISSION_PAYMENT n'a pas mis à jour la DB)
--   - 0 audit FINANCE_TRANSFER_CONNECT en prod malgré ≥ 1
--     paiement Stripe Connect effectué
--
-- Ce fix : DROP + recreate CHECK avec la liste complète des
-- actions utilisées dans :
--   - supabase/functions/*/index.ts (22 actions Stripe/Connect)
--   - supabase/migrations/*.sql RPCs (8 actions)
--   - src/**/*.ts(x) frontend (12 actions)
--
-- Actions maintenues : toutes les 39 actions déjà autorisées.
-- Actions ajoutées : 42.
-- Total : 81 actions.
-- ============================================================

ALTER TABLE public.journaux_audit
DROP CONSTRAINT IF EXISTS journaux_audit_action_check;

ALTER TABLE public.journaux_audit
ADD CONSTRAINT journaux_audit_action_check CHECK (
    action = ANY (ARRAY[
        -- ── Existantes (39) ──────────────────────────────────
        'INSCRIPTION',
        'CONNEXION',
        'DECONNEXION',
        'MODIFICATION_PROFIL',
        'SUPPRESSION_COMPTE',
        'UPLOAD_DOCUMENT',
        'TELECHARGEMENT_DOCUMENT',
        'VERIFICATION_DOCUMENT',
        'VERIFICATION_RPPS',
        'CREATION_MISSION',
        'MODIFICATION_MISSION',
        'ANNULATION_MISSION',
        'CANDIDATURE',
        'ASSIGNATION',
        'POINTAGE',
        'SIGNATURE_CONTRAT',
        'EVALUATION',
        'PAIEMENT',
        'FACTURATION',
        'DONNEES_PERSO_CONSULTATION',
        'DONNEES_PERSO_EXPORT',
        'DONNEES_PERSO_SUPPRESSION',
        'ADMIN_ACTION',
        'SYSTEM',
        'RIB_CONSULTE',
        'RIB_PARTAGE',
        'CONTRAT_SIGNE',
        'DOCUMENT_CONSULTATION',
        'DOCUMENT_TELEVERSEMENT',
        'DONNEES_PERSO_MODIFICATION',
        'EXPORT_RH_PAIE',
        'FINANCE_FACTURE_PAYEE',
        'MISSION_ASSIGNATION',
        'MISSION_CREATION',
        'RGPD_EXPORT_DONNEES',
        'DEGEL_APPLIED',
        'OVERRIDE_CHAMP_POST_GEL',
        'GEL_APPLIED',
        'OVERRIDE_ANTI_SEED',

        -- ── Stripe / Connect (22) ────────────────────────────
        'CONNECT_METADATA_MANQUANTE',
        'DOCUMENT_VERIFICATION_AUTO',
        'FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE',
        'FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE',
        'FINANCE_CHARGE_EXPIRED',
        'FINANCE_CHARGE_FAILED',
        'FINANCE_CHARGE_PENDING',
        'FINANCE_CHARGE_REFUNDED',
        'FINANCE_DISPUTE_CLOSE',
        'FINANCE_DISPUTE_OUVERTE',
        'FINANCE_PAYOUT_CANCELED',
        'FINANCE_PAYOUT_CREATED',
        'FINANCE_PAYOUT_FAILED',
        'FINANCE_PAYOUT_PAID',
        'FINANCE_SEPA_CAPTURE',
        'FINANCE_TRANSFER_CONNECT',
        'FINANCE_TRANSFER_CREATED',
        'FINANCE_TRANSFER_FAILED',
        'FINANCE_TRANSFER_REVERSED',
        'FINANCE_TRANSFER_UPDATED',
        'STRIPE_CHECKOUT_ORPHANED_RECOVERED',
        'STRIPE_CONNECT_ACCOUNT_DELETED',

        -- ── RPCs SQL (8) ─────────────────────────────────────
        'ATTESTATION_SANTE_SIGNEE',
        'EXCLUSION_CREEE',
        'EXCLUSION_SUPPRIMEE',
        'FACTURE_GENEREE',
        'MISSION_ANNULATION_SERIE',
        'MISSION_MODIFICATION',
        'PAIEMENT_SOIGNANT_DECLARE_ETAB',
        'RECLAMATION_CREEE',

        -- ── Frontend src/ (12) ───────────────────────────────
        'ADMIN_CONSULTATION_ETABLISSEMENT',
        'ADMIN_CONSULTATION_SOIGNANT',
        'DOCUMENT_SUPPRESSION',
        'HEURES_EXTERNES_DECLAREES',
        'MISSION_ANNULATION',
        'NOTE_HONORAIRES_GENEREE',
        'PRESENCE_CONTESTATION',
        'PRESENCE_POINTAGE_ARRIVEE',
        'PRESENCE_VALIDATION',
        'PRESENCE_VALIDATION_LOT',
        'RGPD_CONSENTEMENT_DONNE',
        'PAIEMENT_MONTANT_ECART'  -- utilisée aussi comme p_action en fallback (Fix F sous_action promue)
    ])
);

-- Vérification finale : aucune row existante ne doit violer le
-- nouveau CHECK (impossible car on a ELARGI la liste, jamais
-- retiré).
