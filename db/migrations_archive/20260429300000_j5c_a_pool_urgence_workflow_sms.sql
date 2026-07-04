-- J5.C.A — Pool urgence : workflow acceptation 1-clic + SMS opt-in + auto-notify trigger
--
-- Ajoute :
--   * soignants.pool_urgence_sms_opt_in (toggle SMS opt-in séparé du pool ON)
--   * Étend journaux_audit_action_check : 5 nouvelles actions POOL_URGENCE_*
--   * Étend candidatures_statut_check : EN_ATTENTE_VALIDATION_ETAB
--   * Étend notifications_type_check : POOL_URGENCE_ACCEPTATION + MISSION_ASSIGNEE
--   * fn_protect_candidature_statut : autorise transitions EN_ATTENTE_VALIDATION_ETAB → ACCEPTEE/REFUSEE/ANNULEE
--   * fn_trg_auto_notify_mission_urgente : trigger refondu (cap 50, distance Haversine, hiérarchie pro, docs OK, mandat, RPPS)
--   * fn_accepter_mission_urgence : RPC soignant 1-clic → candidature EN_ATTENTE_VALIDATION_ETAB
--   * fn_etab_valider_acceptation_urgence : RPC étab valider/refuser
--   * fn_toggle_pool_urgence_sms : RPC soignant toggle SMS
--   * fn_pool_urgence_missions_pour_soignant : liste missions urgentes pour soignant pool

-- 1) Colonne SMS opt-in
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS pool_urgence_sms_opt_in BOOLEAN NOT NULL DEFAULT false;

-- 2) Audit constraint étendu
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
  'POOL_URGENCE_VALIDATION_ETAB','POOL_URGENCE_REFUS_ETAB',
  'POOL_URGENCE_SMS_TOGGLE'
]));

-- 3) Candidatures : statut EN_ATTENTE_VALIDATION_ETAB
ALTER TABLE public.candidatures DROP CONSTRAINT IF EXISTS candidatures_statut_check;
ALTER TABLE public.candidatures ADD CONSTRAINT candidatures_statut_check CHECK (
  statut = ANY (ARRAY['EN_ATTENTE'::text, 'EN_ATTENTE_VALIDATION_ETAB'::text, 'ACCEPTEE'::text, 'REFUSEE'::text, 'ANNULEE'::text, 'PROPOSEE'::text, 'EXPIREE'::text])
);

-- 4) Notifications : nouveaux types POOL_URGENCE_ACCEPTATION + MISSION_ASSIGNEE
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type = ANY (ARRAY[
  'CANDIDATURE_ACCEPTEE','CANDIDATURE_REFUSEE','CANDIDATURE_PROPOSEE',
  'MISSION_ACCEPTEE','MISSION_ANNULEE','MISSION_TERMINEE','MISSION_URGENTE','MISSION_NON_POURVUE','MISSION_ASSIGNEE',
  'CONTRAT_A_SIGNER','CONTRAT_SIGNE','FACTURE_EMISE','FACTURE_PAYEE',
  'DOCUMENT_EXPIRANT','RAPPEL_DOCUMENTS','DOCUMENT_VERIFIE','DOCUMENT_REJETE',
  'MESSAGE_RECU','MESSAGE_ADMIN','POINTAGE_ARRIVEE','POINTAGE_DEPART','EVALUATION_RECUE','PARRAINAGE',
  'RAPPEL_MISSION','POOL_URGENCE','POOL_URGENCE_ACCEPTATION','SYSTEM',
  'LITIGE_OUVERT','LITIGE_REPONSE','LITIGE_RESOLU','LITIGE_MEDIATION',
  'CHORUS_DEPOSEE','CHORUS_MISE_A_DISPOSITION','CHORUS_PAIEMENT_EN_COURS','CHORUS_PAIEMENT_COMPTABILISE','CHORUS_REJETEE'
]));

-- 5) fn_protect_candidature_statut : autoriser transitions pool urgence
CREATE OR REPLACE FUNCTION public.fn_protect_candidature_statut()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN RETURN NEW; END IF;
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;
    IF est_admin() THEN RETURN NEW; END IF;

    -- Soignant
    IF auth.uid() = OLD.soignant_id THEN
        IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;
        IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;

        IF NEW.statut IS DISTINCT FROM OLD.statut THEN
            IF OLD.statut = 'EN_ATTENTE' AND NEW.statut = 'ANNULEE' THEN
                RETURN NEW;
            ELSIF OLD.statut = 'EN_ATTENTE_VALIDATION_ETAB' AND NEW.statut = 'ANNULEE' THEN
                RETURN NEW;
            ELSE
                RAISE EXCEPTION 'Vous ne pouvez pas modifier le statut de votre candidature (% → %)', OLD.statut, NEW.statut;
            END IF;
        END IF;

        IF NEW.message IS DISTINCT FROM OLD.message AND OLD.statut != 'EN_ATTENTE' THEN
            RAISE EXCEPTION 'Vous ne pouvez plus modifier votre message';
        END IF;

        NEW.motif_refus := OLD.motif_refus;
        NEW.traite_le := OLD.traite_le;
        RETURN NEW;
    END IF;

    -- Établissement
    IF mon_etablissement_id() IS NOT NULL THEN
        IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;
        IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;

        IF NEW.statut IS DISTINCT FROM OLD.statut THEN
            IF NOT (
                (OLD.statut = 'EN_ATTENTE' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE'))
                OR (OLD.statut = 'EN_ATTENTE_VALIDATION_ETAB' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE'))
                OR (OLD.statut = 'PROPOSEE' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE', 'EXPIREE'))
            ) THEN
                RAISE EXCEPTION 'Transition de statut candidature non autorisée: % → %', OLD.statut, NEW.statut;
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Accès refusé à cette candidature';
END;
$function$;

-- 6) fn_trg_auto_notify_mission_urgente : trigger refondu
CREATE OR REPLACE FUNCTION public.fn_trg_auto_notify_mission_urgente()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_etab RECORD;
  v_count INT := 0;
  v_soignant RECORD;
  v_url TEXT;
  v_token TEXT;
  v_should_fire BOOLEAN := false;
BEGIN
  IF (TG_OP = 'INSERT' AND COALESCE(NEW.est_urgente, false) = true AND NEW.statut = 'OUVERTE') THEN
    v_should_fire := true;
  ELSIF (TG_OP = 'UPDATE' AND COALESCE(NEW.est_urgente, false) = true AND NEW.statut = 'OUVERTE'
         AND (
           COALESCE(OLD.est_urgente, false) IS DISTINCT FROM COALESCE(NEW.est_urgente, false)
           OR (OLD.statut = 'ASSIGNEE' AND NEW.statut = 'OUVERTE')
         )) THEN
    v_should_fire := true;
  END IF;

  IF NOT v_should_fire THEN
    RETURN NEW;
  END IF;

  SELECT id, nom, adresse_lat, adresse_lng, adresse_ville
  INTO v_etab
  FROM etablissements
  WHERE id = NEW.etablissement_id;

  BEGIN
    v_url := public.fn_lire_secret_cron('supabase_url');
    v_token := public.fn_lire_secret_cron('service_role_key');
  EXCEPTION WHEN OTHERS THEN
    v_url := NULL;
    v_token := NULL;
  END;

  FOR v_soignant IN
    SELECT s.id, s.email, s.prenom, s.telephone,
      COALESCE(s.pool_urgence_sms_opt_in, false) AS sms_opt_in,
      CASE
        WHEN v_etab.adresse_lat IS NOT NULL AND s.adresse_lat IS NOT NULL THEN
          (6371 * 2 * asin(sqrt(
            power(sin(radians(s.adresse_lat - v_etab.adresse_lat) / 2), 2) +
            cos(radians(v_etab.adresse_lat)) * cos(radians(s.adresse_lat)) *
            power(sin(radians(s.adresse_lng - v_etab.adresse_lng) / 2), 2)
          )))
        ELSE NULL
      END AS distance_km
    FROM soignants s
    WHERE s.supprime_le IS NULL
      AND COALESCE(s.disponible_urgence, false) = true
      AND COALESCE(s.tous_documents_valides, false) = true
      AND public.fn_soignant_compatible_mission(
        s.profession, s.specialite_medicale,
        NEW.profession_requise, NEW.specialite_medicale_requise,
        COALESCE(NEW.accepte_non_specialises, true)
      ) = true
      AND NOT EXISTS (
        SELECT 1 FROM candidatures c
        WHERE c.mission_id = NEW.id AND c.soignant_id = s.id
      )
      AND (COALESCE(s.type_exercice, 'SALARIE') NOT IN ('LIBERAL','MIXTE')
           OR COALESCE(s.mandat_facturation_signe, false) = true)
      AND (s.profession::text IN ('AS','AES')
           OR COALESCE(s.rpps_verifie, false) = true)
      AND (
        v_etab.adresse_lat IS NULL OR s.adresse_lat IS NULL OR
        (6371 * 2 * asin(sqrt(
          power(sin(radians(s.adresse_lat - v_etab.adresse_lat) / 2), 2) +
          cos(radians(v_etab.adresse_lat)) * cos(radians(s.adresse_lat)) *
          power(sin(radians(s.adresse_lng - v_etab.adresse_lng) / 2), 2)
        ))) <= COALESCE(s.urgence_rayon_km, 30)
      )
    ORDER BY distance_km ASC NULLS LAST, COALESCE(s.score_fiabilite, 0) DESC
    LIMIT 50
  LOOP
    INSERT INTO notifications (
      destinataire_id, type_destinataire, type, titre, corps, lien,
      type_ressource, id_ressource
    ) VALUES (
      v_soignant.id, 'SOIGNANT', 'MISSION_URGENTE',
      '🚨 Mission urgente près de chez vous',
      'Mission ' || COALESCE(NEW.intitule, NEW.profession_requise::text)
        || ' à ' || COALESCE(v_etab.adresse_ville, 'votre zone')
        || CASE WHEN v_soignant.distance_km IS NOT NULL THEN ' (' || ROUND(v_soignant.distance_km::numeric, 1) || ' km)' ELSE '' END
        || ' · ' || COALESCE(NEW.taux_horaire_base::text, '?') || '€/h. Acceptez en 1 clic.',
      '/soignant/pool-urgence',
      'mission', NEW.id
    );

    IF v_url IS NOT NULL AND v_token IS NOT NULL THEN
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-email',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
          body := jsonb_build_object(
            'type', 'MISSION_URGENTE_POOL',
            'destinataire_id', v_soignant.id,
            'data', jsonb_build_object(
              'prenom', v_soignant.prenom,
              'mission_id', NEW.id,
              'mission_intitule', NEW.intitule,
              'profession', NEW.profession_requise::text,
              'ville', v_etab.adresse_ville,
              'distance_km', v_soignant.distance_km,
              'taux_horaire', NEW.taux_horaire_base,
              'debut_le', NEW.debut_le
            )
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;

      IF v_soignant.sms_opt_in = true AND COALESCE(v_soignant.telephone, '') <> '' THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-sms',
            headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
            body := jsonb_build_object(
              'destinataire_id', v_soignant.id,
              'telephone', v_soignant.telephone,
              'message', 'URGENT - Mission ' || COALESCE(NEW.profession_requise::text, '')
                || ' ' || COALESCE(v_etab.adresse_ville, '')
                || ' ' || TO_CHAR(NEW.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM HH24h')
                || ' - ' || COALESCE(NEW.taux_horaire_base::text, '?') || E'€/h - Acceptez sur jolene.app/pool-urgence'
            )
          );
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;
    END IF;

    v_count := v_count + 1;
  END LOOP;

  IF v_count > 0 THEN
    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := NEW.etablissement_id,
      p_type_acteur := 'SYSTEME',
      p_action := 'POOL_URGENCE_NOTIFICATIONS_ENVOYEES',
      p_type_ressource := 'mission',
      p_id_ressource := NEW.id,
      p_details := jsonb_build_object(
        'count', v_count,
        'mission_intitule', NEW.intitule,
        'event', TG_OP,
        'transition', CASE WHEN TG_OP = 'UPDATE' THEN OLD.statut::text || ' -> ' || NEW.statut::text ELSE 'INSERT' END
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

-- 7) Trigger sur missions
DROP TRIGGER IF EXISTS trg_auto_proposition_pool_urgence ON public.missions;
DROP TRIGGER IF EXISTS trg_auto_notify_mission_urgente ON public.missions;
CREATE TRIGGER trg_auto_notify_mission_urgente
  AFTER INSERT OR UPDATE OF est_urgente, statut, soignant_assigne_id ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_auto_notify_mission_urgente();

-- 8) RPC fn_accepter_mission_urgence : soignant 1-clic
CREATE OR REPLACE FUNCTION public.fn_accepter_mission_urgence(p_mission_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_soignant RECORD;
  v_mission RECORD;
  v_existing UUID;
  v_candidature_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT * INTO v_soignant FROM soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF v_soignant IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profil soignant introuvable');
  END IF;

  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;
  IF v_mission.statut <> 'OUVERTE' OR COALESCE(v_mission.est_urgente, false) = false THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission non disponible (non-urgente ou non-ouverte)');
  END IF;

  IF NOT public.fn_soignant_compatible_mission(
    v_soignant.profession, v_soignant.specialite_medicale,
    v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true)
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profession ou spécialité incompatible');
  END IF;

  IF COALESCE(v_soignant.tous_documents_valides, false) = false THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vos documents ne sont pas tous validés');
  END IF;

  SELECT id INTO v_existing FROM candidatures
  WHERE mission_id = p_mission_id AND soignant_id = v_uid
  LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous avez déjà candidaté à cette mission');
  END IF;

  INSERT INTO candidatures (mission_id, soignant_id, statut, message, cree_le)
  VALUES (
    p_mission_id, v_uid, 'EN_ATTENTE_VALIDATION_ETAB',
    'Acceptation rapide via pool urgence',
    NOW()
  )
  RETURNING id INTO v_candidature_id;

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
  VALUES (
    v_mission.etablissement_id, 'ETABLISSEMENT', 'POOL_URGENCE_ACCEPTATION',
    '🚨 Acceptation rapide pool urgence',
    v_soignant.prenom || ' ' || LEFT(v_soignant.nom, 1) || '. (' || v_soignant.profession::text
      || ') a accepté votre mission urgente. Validez ou refusez sous 1h.',
    '/etablissement/missions/' || p_mission_id::text,
    'candidature', v_candidature_id
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'POOL_URGENCE_ACCEPTATION_RAPIDE',
    p_type_ressource := 'candidature',
    p_id_ressource := v_candidature_id,
    p_details := jsonb_build_object('mission_id', p_mission_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'candidature_id', v_candidature_id,
    'message', 'Acceptation enregistrée. Attente validation établissement.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_accepter_mission_urgence(UUID) TO authenticated;

-- 9) RPC fn_etab_valider_acceptation_urgence
CREATE OR REPLACE FUNCTION public.fn_etab_valider_acceptation_urgence(
  p_candidature_id UUID,
  p_action TEXT,
  p_motif_refus TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID;
  v_cand RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF p_action NOT IN ('VALIDER', 'REFUSER') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action invalide (VALIDER ou REFUSER)');
  END IF;

  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
    END IF;
  END IF;

  SELECT c.*, m.etablissement_id, m.statut AS mission_statut, m.intitule AS mission_intitule
  INTO v_cand
  FROM candidatures c
  JOIN missions m ON m.id = c.mission_id
  WHERE c.id = p_candidature_id;

  IF v_cand IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Candidature introuvable');
  END IF;

  IF NOT est_admin() AND v_cand.etablissement_id <> v_etab_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cette candidature n''appartient pas à votre étab');
  END IF;

  IF v_cand.statut <> 'EN_ATTENTE_VALIDATION_ETAB' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Candidature déjà traitée (statut: ' || v_cand.statut || ')');
  END IF;

  IF p_action = 'VALIDER' THEN
    IF v_cand.mission_statut <> 'OUVERTE' THEN
      RETURN jsonb_build_object('success', false, 'error', 'Mission n''est plus disponible');
    END IF;

    UPDATE missions
    SET statut = 'ASSIGNEE',
        soignant_assigne_id = v_cand.soignant_id
    WHERE id = v_cand.mission_id;

    UPDATE candidatures
    SET statut = 'ACCEPTEE', traite_le = NOW()
    WHERE id = p_candidature_id;

    UPDATE candidatures
    SET statut = 'REFUSEE', traite_le = NOW(),
        motif_refus = COALESCE(motif_refus, 'Mission attribuée à un autre soignant')
    WHERE mission_id = v_cand.mission_id
      AND id <> p_candidature_id
      AND statut IN ('EN_ATTENTE','EN_ATTENTE_VALIDATION_ETAB','PROPOSEE');

    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
    VALUES (
      v_cand.soignant_id, 'SOIGNANT', 'MISSION_ASSIGNEE',
      '✅ Mission urgente confirmée',
      'L''établissement a validé votre acceptation. Mission "' || v_cand.mission_intitule || '" assignée.',
      '/soignant/missions/' || v_cand.mission_id::text,
      'mission', v_cand.mission_id
    );

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_uid,
      p_type_acteur := 'ADMIN_ETABLISSEMENT',
      p_action := 'POOL_URGENCE_VALIDATION_ETAB',
      p_type_ressource := 'candidature',
      p_id_ressource := p_candidature_id,
      p_details := jsonb_build_object('mission_id', v_cand.mission_id, 'soignant_id', v_cand.soignant_id)
    );

    RETURN jsonb_build_object('success', true, 'action', 'VALIDER', 'mission_id', v_cand.mission_id);
  ELSE
    UPDATE candidatures
    SET statut = 'REFUSEE', traite_le = NOW(),
        motif_refus = COALESCE(p_motif_refus, 'Candidature refusée par l''établissement')
    WHERE id = p_candidature_id;

    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
    VALUES (
      v_cand.soignant_id, 'SOIGNANT', 'CANDIDATURE_REFUSEE',
      'Acceptation pool urgence refusée',
      'L''établissement a refusé votre acceptation. Motif : '
        || COALESCE(p_motif_refus, 'non précisé') || '.',
      '/soignant/pool-urgence',
      'candidature', p_candidature_id
    );

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_uid,
      p_type_acteur := 'ADMIN_ETABLISSEMENT',
      p_action := 'POOL_URGENCE_REFUS_ETAB',
      p_type_ressource := 'candidature',
      p_id_ressource := p_candidature_id,
      p_details := jsonb_build_object('mission_id', v_cand.mission_id, 'motif', p_motif_refus)
    );

    RETURN jsonb_build_object('success', true, 'action', 'REFUSER');
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_etab_valider_acceptation_urgence(UUID, TEXT, TEXT) TO authenticated;

-- 10) RPC fn_toggle_pool_urgence_sms
CREATE OR REPLACE FUNCTION public.fn_toggle_pool_urgence_sms(p_actif BOOLEAN)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  UPDATE soignants
  SET pool_urgence_sms_opt_in = COALESCE(p_actif, false)
  WHERE id = v_uid AND supprime_le IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profil soignant introuvable');
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'POOL_URGENCE_SMS_TOGGLE',
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object('actif', p_actif)
  );

  RETURN jsonb_build_object('success', true, 'pool_urgence_sms_opt_in', COALESCE(p_actif, false));
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_toggle_pool_urgence_sms(BOOLEAN) TO authenticated;

-- 11) RPC fn_pool_urgence_missions_pour_soignant
CREATE OR REPLACE FUNCTION public.fn_pool_urgence_missions_pour_soignant()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_soignant RECORD;
  v_result JSONB;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT * INTO v_soignant FROM soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF v_soignant IS NULL THEN
    RETURN jsonb_build_object('error', 'Profil soignant introuvable');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'intitule', m.intitule,
    'profession_requise', m.profession_requise::text,
    'specialite_medicale_requise', m.specialite_medicale_requise,
    'taux_horaire_base', m.taux_horaire_base,
    'debut_le', m.debut_le,
    'fin_le', m.fin_le,
    'service', m.service,
    'etablissement_nom', e.nom,
    'etablissement_ville', e.adresse_ville,
    'distance_km',
      CASE
        WHEN e.adresse_lat IS NOT NULL AND v_soignant.adresse_lat IS NOT NULL THEN
          ROUND((6371 * 2 * asin(sqrt(
            power(sin(radians(v_soignant.adresse_lat - e.adresse_lat) / 2), 2) +
            cos(radians(e.adresse_lat)) * cos(radians(v_soignant.adresse_lat)) *
            power(sin(radians(v_soignant.adresse_lng - e.adresse_lng) / 2), 2)
          )))::NUMERIC, 1)
        ELSE NULL
      END,
    'deja_candidate', EXISTS (
      SELECT 1 FROM candidatures c
      WHERE c.mission_id = m.id AND c.soignant_id = v_uid
    ),
    'statut_candidature', (
      SELECT statut FROM candidatures c
      WHERE c.mission_id = m.id AND c.soignant_id = v_uid
      LIMIT 1
    )
  ) ORDER BY
    CASE
      WHEN e.adresse_lat IS NOT NULL AND v_soignant.adresse_lat IS NOT NULL THEN
        (6371 * 2 * asin(sqrt(
          power(sin(radians(v_soignant.adresse_lat - e.adresse_lat) / 2), 2) +
          cos(radians(e.adresse_lat)) * cos(radians(v_soignant.adresse_lat)) *
          power(sin(radians(v_soignant.adresse_lng - e.adresse_lng) / 2), 2)
        )))
      ELSE 9999
    END ASC,
    m.debut_le ASC
  ), '[]'::jsonb)
  INTO v_result
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE m.statut = 'OUVERTE'
    AND COALESCE(m.est_urgente, false) = true
    AND m.debut_le > NOW()
    AND public.fn_soignant_compatible_mission(
      v_soignant.profession, v_soignant.specialite_medicale,
      m.profession_requise, m.specialite_medicale_requise,
      COALESCE(m.accepte_non_specialises, true)
    ) = true
    AND (
      e.adresse_lat IS NULL OR v_soignant.adresse_lat IS NULL OR
      (6371 * 2 * asin(sqrt(
        power(sin(radians(v_soignant.adresse_lat - e.adresse_lat) / 2), 2) +
        cos(radians(e.adresse_lat)) * cos(radians(v_soignant.adresse_lat)) *
        power(sin(radians(v_soignant.adresse_lng - e.adresse_lng) / 2), 2)
      ))) <= COALESCE(v_soignant.urgence_rayon_km, 30)
    );

  RETURN jsonb_build_object(
    'missions', v_result,
    'pool_actif', COALESCE(v_soignant.disponible_urgence, false),
    'rayon_km', COALESCE(v_soignant.urgence_rayon_km, 30),
    'sms_opt_in', COALESCE(v_soignant.pool_urgence_sms_opt_in, false)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_pool_urgence_missions_pour_soignant() TO authenticated;

NOTIFY pgrst, 'reload schema';
