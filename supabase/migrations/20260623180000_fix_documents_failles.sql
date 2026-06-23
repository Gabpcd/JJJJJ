-- Fixes failles vérification documents (#3, #4, #6).
--
-- #3 : fn_verifier_coherence_documents — flag docs sans nom lisible au lieu de
--      les exclure silencieusement du cross-check.
-- #4 : fn_verifier_coherence_documents — quand incohérence détectée, poser un
--      flag admin (pas de blocage dur, risque faux positifs noms composés/mariée).
-- #6 : fn_postuler_mission_rate_limited — bloquer un étudiant qui postule dans
--      une profession plus haute que scolarite_profession_autorisee.

-- Ajout de l'action 'COHERENCE_DOCUMENTS_ALERTE' au CHECK constraint des journaux_audit
-- (nécessaire pour le #4 — audit best-effort quand incohérence détectée).
ALTER TABLE journaux_audit DROP CONSTRAINT IF EXISTS journaux_audit_action_check;
ALTER TABLE journaux_audit ADD CONSTRAINT journaux_audit_action_check CHECK (action = ANY (ARRAY['INSCRIPTION','CONNEXION','DECONNEXION','MODIFICATION_PROFIL','SUPPRESSION_COMPTE','UPLOAD_DOCUMENT','TELECHARGEMENT_DOCUMENT','VERIFICATION_DOCUMENT','VERIFICATION_RPPS','CREATION_MISSION','MODIFICATION_MISSION','ANNULATION_MISSION','CANDIDATURE','ASSIGNATION','POINTAGE','SIGNATURE_CONTRAT','EVALUATION','PAIEMENT','FACTURATION','DONNEES_PERSO_CONSULTATION','DONNEES_PERSO_EXPORT','DONNEES_PERSO_SUPPRESSION','ADMIN_ACTION','SYSTEM','RIB_CONSULTE','RIB_PARTAGE','CONTRAT_SIGNE','DOCUMENT_CONSULTATION','DOCUMENT_TELEVERSEMENT','DONNEES_PERSO_MODIFICATION','EXPORT_RH_PAIE','FINANCE_FACTURE_PAYEE','MISSION_ASSIGNATION','MISSION_CREATION','RGPD_EXPORT_DONNEES','RGPD_SUPPRESSION_COMPTE','RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT','DEGEL_APPLIED','OVERRIDE_CHAMP_POST_GEL','GEL_APPLIED','OVERRIDE_ANTI_SEED','CONNECT_METADATA_MANQUANTE','DOCUMENT_VERIFICATION_AUTO','FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE','FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE','FINANCE_CHARGE_EXPIRED','FINANCE_CHARGE_FAILED','FINANCE_CHARGE_PENDING','FINANCE_CHARGE_REFUNDED','FINANCE_DISPUTE_CLOSE','FINANCE_DISPUTE_OUVERTE','FINANCE_PAYOUT_CANCELED','FINANCE_PAYOUT_CREATED','FINANCE_PAYOUT_FAILED','FINANCE_PAYOUT_PAID','FINANCE_SEPA_CAPTURE','FINANCE_TRANSFER_CONNECT','FINANCE_TRANSFER_CREATED','FINANCE_TRANSFER_FAILED','FINANCE_TRANSFER_REVERSED','FINANCE_TRANSFER_UPDATED','STRIPE_CHECKOUT_ORPHANED_RECOVERED','STRIPE_CONNECT_ACCOUNT_DELETED','ATTESTATION_SANTE_SIGNEE','EXCLUSION_CREEE','EXCLUSION_SUPPRIMEE','FACTURE_GENEREE','MISSION_ANNULATION_SERIE','MISSION_MODIFICATION','PAIEMENT_SOIGNANT_DECLARE_ETAB','RECLAMATION_CREEE','ADMIN_CONSULTATION_ETABLISSEMENT','ADMIN_CONSULTATION_SOIGNANT','DOCUMENT_SUPPRESSION','HEURES_EXTERNES_DECLAREES','MISSION_ANNULATION','NOTE_HONORAIRES_GENEREE','PRESENCE_CONTESTATION','PRESENCE_POINTAGE_ARRIVEE','PRESENCE_VALIDATION','PRESENCE_VALIDATION_LOT','RGPD_CONSENTEMENT_DONNE','PAIEMENT_MONTANT_ECART','FACTURE_COMMISSION_CREATED_VIA_STRIPE','TAUX_COMMISSION_MODIFIE','LITIGE_GEL_SCOPE_MODIFIE','PREFERENCE_NOTIFICATION_MODIFIEE','NOTIFICATION_SKIPPED','SERIE_EMAIL_ENVOYE','SERIE_EMAIL_SKIPPED','FILTRE_CREE','FILTRE_MODIFIE','FILTRE_SUPPRIME','ALERTE_ACTIVEE','ALERTE_DESACTIVEE','ALERTE_ENVOYEE','POOL_URGENCE_NOTIFICATIONS_ENVOYEES','POOL_URGENCE_ACCEPTATION_RAPIDE','POOL_URGENCE_VALIDATION_ETAB','POOL_URGENCE_REFUS_ETAB','POOL_URGENCE_SMS_TOGGLE','FAVORI_AJOUTE','FAVORI_RETIRE','SCORE_FIABILITE_PENALITE_LITIGE','PARRAINAGE_ETAB_APPLIQUE','PARRAINAGE_ETAB_VALIDE','CREDIT_PARRAINAGE_CREE','CREDIT_PARRAINAGE_APPLIQUE','PARRAINAGE_ETAB_ANOMALIE','PARRAINAGE_SOIGNANT_FILLEUL_ACTIF','PARRAINAGE_SOIGNANT_SEUIL_ATTEINT','PARRAINAGE_SOIGNANT_PRIME_VERSEE','PARRAINAGE_SOIGNANT_FRAUDE','INSCRIPTION_LISTE_ATTENTE_PREVOYANCE','SCORE_RECALCULE_V2','IBAN_RENSEIGNE','IBAN_MODIFIE','AVOIR_REMBOURSEMENT_CONFIRME','ETABLISSEMENT_MODIFICATION','LITIGE_ACCORD_CLOTURE','LITIGE_AUTO_CREATION','LITIGE_CLOTURE_AMIABLE','LITIGE_CREATION','LITIGE_ESCALADE_AUTO','LITIGE_FORCE_CREATION','LITIGE_OUVERTURE','LITIGE_OUVERTURE_LEGACY','LITIGE_RECATEGORISATION_LEGACY','LITIGE_REPONSE','LITIGE_RESOLUTION','PRESENCE_ALERTE_FRAUDE','RGPD_SUPPRESSION_DONNEES','TVA_MODIFICATION','API_KEY_CREEE','API_KEY_REVOQUEE','API_KEY_SUPPRIMEE','FACTURE_MARQUEE_EN_RETARD','HEURES_EXTERNES_VALIDATION_MANUELLE','MISSION_ANNULEE_PAR_SOIGNANT','MISSION_ANNULEE_PAR_ETABLISSEMENT','MISSION_LITIGE','MISSION_TYPE_CONTRAT_MODIFIE','MODERATION_DOCUMENT','COHERENCE_IDENTITE_VERIFIEE','MODERATION_EVALUATION','COHERENCE_DOCUMENTS_ALERTE']));

-- ═══ #3 + #4 : fn_verifier_coherence_documents améliorée ═══
CREATE OR REPLACE FUNCTION public.fn_verifier_coherence_documents(p_soignant_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_soignant_id UUID := COALESCE(p_soignant_id, auth.uid());
    v_soignant RECORD;
    v_docs JSONB;
    v_docs_sans_nom INT;
    v_noms_extraits TEXT[];
    v_coherent BOOLEAN := TRUE;
    v_problemes TEXT[] := '{}';
BEGIN
    SELECT prenom, nom INTO v_soignant FROM soignants WHERE id = v_soignant_id;
    IF v_soignant IS NULL THEN RETURN jsonb_build_object('error', 'Soignant introuvable'); END IF;

    SELECT jsonb_agg(jsonb_build_object(
        'type', d.type_document,
        'nom_extrait', d.nom_extrait_ia,
        'prenom_extrait', d.prenom_extrait_ia,
        'coherence_nom', d.coherence_nom,
        'score_confiance', d.score_confiance_ia,
        'statut', d.statut_verification
    )) INTO v_docs
    FROM documents_soignants d
    WHERE d.soignant_id = v_soignant_id
      AND d.supprime_le IS NULL
      AND d.statut_verification IN ('VERIFIE', 'EN_ATTENTE');

    IF v_docs IS NULL OR jsonb_array_length(v_docs) = 0 THEN
        RETURN jsonb_build_object('coherent', TRUE, 'message', 'Pas assez de documents vérifiés', 'documents', '[]'::JSONB);
    END IF;

    -- #3 : compter les docs sans nom lisible (au lieu de les exclure silencieusement)
    SELECT COUNT(*) INTO v_docs_sans_nom
    FROM jsonb_array_elements(v_docs) elem
    WHERE elem->>'nom_extrait' IS NULL OR TRIM(elem->>'nom_extrait') = '';

    IF v_docs_sans_nom > 0 THEN
        v_problemes := v_problemes || (v_docs_sans_nom || ' document(s) sans nom lisible — cohérence non vérifiable sur ces pièces');
    END IF;

    SELECT array_agg(DISTINCT UPPER(TRIM(elem->>'nom_extrait')))
    INTO v_noms_extraits
    FROM jsonb_array_elements(v_docs) elem
    WHERE elem->>'nom_extrait' IS NOT NULL AND TRIM(elem->>'nom_extrait') != '';

    IF array_length(v_noms_extraits, 1) > 1 THEN
        v_coherent := FALSE;
        v_problemes := v_problemes || ('Noms différents détectés entre documents : ' || array_to_string(v_noms_extraits, ', '));
    END IF;

    IF v_noms_extraits IS NOT NULL AND array_length(v_noms_extraits, 1) > 0 THEN
        DECLARE
            v_profil_nom TEXT := UPPER(TRIM(v_soignant.nom));
            v_match BOOLEAN := FALSE;
        BEGIN
            FOR i IN 1..array_length(v_noms_extraits, 1) LOOP
                IF v_noms_extraits[i] LIKE '%' || v_profil_nom || '%' OR v_profil_nom LIKE '%' || v_noms_extraits[i] || '%' THEN
                    v_match := TRUE;
                END IF;
            END LOOP;
            IF NOT v_match THEN
                v_coherent := FALSE;
                v_problemes := v_problemes || ('Nom du profil (' || v_soignant.nom || ') ne correspond pas aux documents');
            END IF;
        END;
    END IF;

    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_docs) elem WHERE (elem->>'coherence_nom')::BOOLEAN = FALSE) THEN
        v_coherent := FALSE;
        v_problemes := v_problemes || 'Un ou plusieurs documents ont un nom incohérent avec le profil';
    END IF;

    -- #4 : si incohérent, poser un flag admin pour revue (pas de blocage dur,
    -- risque faux positifs noms composés / nom d'usage ≠ nom de naissance).
    IF NOT v_coherent THEN
        BEGIN
            INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
            VALUES (v_soignant_id, 'SYSTEM', 'COHERENCE_DOCUMENTS_ALERTE', 'soignant', v_soignant_id,
              jsonb_build_object('problemes', to_jsonb(v_problemes), 'profil_nom', v_soignant.nom, 'profil_prenom', v_soignant.prenom));
        EXCEPTION WHEN OTHERS THEN NULL; -- audit best-effort
        END;
    END IF;

    RETURN jsonb_build_object(
        'coherent', v_coherent,
        'problemes', to_jsonb(v_problemes),
        'documents', v_docs,
        'profil_nom', v_soignant.nom,
        'profil_prenom', v_soignant.prenom,
        'docs_sans_nom_lisible', v_docs_sans_nom
    );
END;
$function$;

-- ═══ #6 : enforcement étudiant via trigger BEFORE INSERT sur candidatures ═══
-- Plus sûr qu'un patch de fn_postuler_mission_rate_limited : couvre TOUS les
-- chemins de candidature (présents et futurs). Un étudiant ne peut postuler
-- qu'aux missions de sa profession autorisée (scolarite_profession_autorisee).

CREATE OR REPLACE FUNCTION public.dec_verifier_profession_etudiant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_soignant RECORD;
  v_mission_prof TEXT;
BEGIN
  SELECT est_etudiant, scolarite_profession_autorisee
    INTO v_soignant
    FROM soignants WHERE id = NEW.soignant_id;

  IF v_soignant.est_etudiant
     AND v_soignant.scolarite_profession_autorisee IS NOT NULL THEN
    SELECT profession_requise INTO v_mission_prof
      FROM missions WHERE id = NEW.mission_id;
    IF v_mission_prof IS NOT NULL
       AND UPPER(v_mission_prof) != UPPER(v_soignant.scolarite_profession_autorisee) THEN
      RAISE EXCEPTION
        'En tant qu''étudiant(e), vous ne pouvez postuler qu''aux missions % (profession autorisée par votre scolarité vérifiée).',
        v_soignant.scolarite_profession_autorisee
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_verifier_profession_etudiant ON candidatures;
CREATE TRIGGER trg_verifier_profession_etudiant
  BEFORE INSERT ON candidatures
  FOR EACH ROW EXECUTE FUNCTION dec_verifier_profession_etudiant();
