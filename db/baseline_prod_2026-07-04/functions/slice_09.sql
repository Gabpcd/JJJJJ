CREATE OR REPLACE FUNCTION public.fn_trg_email_mission_terminee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_sg RECORD; v_etab RECORD;
BEGIN
    IF NEW.statut = 'TERMINEE' AND (OLD.statut IS NULL OR OLD.statut <> 'TERMINEE') THEN
        SELECT prenom, nom, email INTO v_sg FROM soignants WHERE id = NEW.soignant_assigne_id;
        SELECT nom, email_contact INTO v_etab FROM etablissements WHERE id = NEW.etablissement_id;
        IF v_sg.email IS NOT NULL THEN
            INSERT INTO email_queue (type, destinataire_id, destinataire_email, data) VALUES
            ('MISSION_TERMINEE', NEW.soignant_assigne_id, v_sg.email, jsonb_build_object(
                'prenom', v_sg.prenom, 'mission', NEW.intitule,
                'etablissement', v_etab.nom, 'mission_id', NEW.id
            ));
        END IF;
        IF v_etab.email_contact IS NOT NULL THEN
            INSERT INTO email_queue (type, destinataire_id, destinataire_email, data) VALUES
            ('MISSION_TERMINEE', NEW.etablissement_id, v_etab.email_contact, jsonb_build_object(
                'soignant', v_sg.prenom || ' ' || v_sg.nom, 'mission', NEW.intitule,
                'mission_id', NEW.id
            ));
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_email_evaluation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_email TEXT; v_prenom TEXT; v_mission TEXT;
BEGIN
    SELECT email INTO v_email FROM soignants WHERE id = NEW.evalue_id;
    IF v_email IS NULL THEN
        SELECT email_contact INTO v_email FROM etablissements WHERE id = NEW.evalue_id;
    END IF;
    SELECT intitule INTO v_mission FROM missions WHERE id = NEW.mission_id;
    IF v_email IS NOT NULL THEN
        INSERT INTO email_queue (type, destinataire_id, destinataire_email, data) VALUES
        ('EVALUATION_RECUE', NEW.evalue_id, v_email, jsonb_build_object(
            'note', NEW.note, 'commentaire', COALESCE(NEW.commentaire, ''),
            'mission', COALESCE(v_mission, ''), 'type_evaluateur', NEW.type_evaluateur
        ));
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_email_paiement_confirme()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_email TEXT; v_sg RECORD; v_mission TEXT;
BEGIN
    IF NEW.statut = 'CONFIRME' AND (OLD.statut IS NULL OR OLD.statut <> 'CONFIRME') THEN
        SELECT email_contact INTO v_email FROM etablissements WHERE id = NEW.etablissement_id;
        SELECT prenom, nom INTO v_sg FROM soignants WHERE id = NEW.soignant_id;
        SELECT intitule INTO v_mission FROM missions WHERE id = NEW.mission_id;
        IF v_email IS NOT NULL THEN
            INSERT INTO email_queue (type, destinataire_id, destinataire_email, data) VALUES
            ('PAIEMENT_CONFIRME', NEW.etablissement_id, v_email, jsonb_build_object(
                'soignant', v_sg.prenom || ' ' || v_sg.nom,
                'montant', NEW.montant_net, 'reference', NEW.reference_virement,
                'mission', COALESCE(v_mission, '')
            ));
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_litige_gel_degel_facture()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_statuts_ouverts TEXT[] := ARRAY['OUVERT','EN_DISCUSSION','EN_MEDIATION','CONTESTEE'];
  v_statuts_resolus TEXT[] := ARRAY['RESOLU','RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME','CLOTURE'];
  v_became_open BOOLEAN;
  v_became_resolved BOOLEAN;
  v_scope text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_became_open := NEW.statut = ANY(v_statuts_ouverts);
    v_became_resolved := FALSE;
  ELSE
    v_became_open := NEW.statut = ANY(v_statuts_ouverts) AND (OLD.statut IS NULL OR OLD.statut <> NEW.statut);
    v_became_resolved := NEW.statut = ANY(v_statuts_resolus) AND (OLD.statut IS NULL OR OLD.statut <> NEW.statut);
  END IF;
  v_scope := COALESCE(NEW.gel_facture_scope, 'MISSION_ENTIERE');

  IF v_became_open AND NOT NEW.est_informatif AND v_scope <> 'AUCUN' THEN
    IF NEW.categorie_litige = 'FINANCIER' AND NEW.facture_id IS NOT NULL THEN
      UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=NEW.id
       WHERE id=NEW.facture_id AND statut_litige='NORMAL' AND statut<>'PAYEE';
    ELSIF NEW.categorie_litige IN ('PRESENCE','CONDITIONS','COMPORTEMENT') THEN
      IF v_scope = 'FACTURE_UNIQUE' AND NEW.facture_id IS NOT NULL THEN
        UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=NEW.id
         WHERE id=NEW.facture_id AND statut_litige='NORMAL' AND statut<>'PAYEE';
      ELSIF v_scope = 'PERIODE_LITIGIEUSE' AND NEW.periode_debut IS NOT NULL AND NEW.periode_fin IS NOT NULL THEN
        UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=NEW.id
         WHERE mission_id=NEW.mission_id AND statut_litige='NORMAL' AND statut<>'PAYEE'
           AND periode_debut <= NEW.periode_fin AND periode_fin >= NEW.periode_debut;
      ELSE
        UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=NEW.id
         WHERE mission_id=NEW.mission_id AND statut_litige='NORMAL' AND statut<>'PAYEE';
      END IF;
    END IF;
  END IF;

  IF v_became_resolved THEN
    UPDATE factures_honoraires SET statut_litige='LITIGE_RESOLU_CONFIRME'
     WHERE litige_id=NEW.id AND statut_litige='EN_ATTENTE_LITIGE';
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_favori_nouvelle_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab RECORD;
  v_soignant_id UUID;
  v_url TEXT := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token TEXT;
BEGIN
  IF TG_OP <> 'INSERT' OR NEW.statut <> 'OUVERTE' THEN RETURN NEW; END IF;

  SELECT id, nom, adresse_ville INTO v_etab FROM etablissements WHERE id = NEW.etablissement_id;

  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN
    v_token := NULL;
  END;

  FOR v_soignant_id IN
    SELECT f.soignant_id FROM favoris_soignant_etab f
    JOIN soignants s ON s.id = f.soignant_id AND s.supprime_le IS NULL
    WHERE f.etablissement_id = NEW.etablissement_id
      AND public.fn_soignant_compatible_mission(
        s.profession, s.specialite_medicale,
        NEW.profession_requise, NEW.specialite_medicale_requise,
        COALESCE(NEW.accepte_non_specialises, true)
      ) = true
  LOOP
    IF public.fn_doit_notifier(v_soignant_id, 'FAVORI_NOUVELLE_MISSION'::type_evenement_notification, 'IN_APP'::canal_notification) THEN
      INSERT INTO notifications (
        destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource
      ) VALUES (
        v_soignant_id, 'SOIGNANT', 'FAVORI_NOUVELLE_MISSION',
        '⭐ Nouvelle mission chez ' || v_etab.nom,
        v_etab.nom || ' a publié "' || COALESCE(NEW.intitule, NEW.profession_requise::text)
          || '" à ' || COALESCE(v_etab.adresse_ville, 'votre zone')
          || ' · ' || COALESCE(NEW.taux_horaire_base::text, '?') || '€/h.',
        '/soignant/missions/' || NEW.id::text, 'mission', NEW.id
      );
    END IF;

    IF v_token IS NOT NULL
       AND public.fn_doit_notifier(v_soignant_id, 'FAVORI_NOUVELLE_MISSION'::type_evenement_notification, 'EMAIL'::canal_notification) THEN
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-email',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
          body := jsonb_build_object(
            'type', 'FAVORI_NOUVELLE_MISSION',
            'destinataire_id', v_soignant_id,
            'data', jsonb_build_object(
              'mission_id', NEW.id, 'mission_intitule', NEW.intitule,
              'etab_nom', v_etab.nom, 'etab_ville', v_etab.adresse_ville,
              'taux_horaire', NEW.taux_horaire_base, 'debut_le', NEW.debut_le
            )
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_litige_accord_mutuel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  IF NEW.accord_soignant_le IS NOT NULL AND NEW.accord_etablissement_le IS NOT NULL
     AND NEW.statut IN ('OUVERT','EN_DISCUSSION','EN_MEDIATION','MEDIATION_EN_COURS') THEN
    NEW.statut := 'RESOLU_ACCORD_PARTIES';
    NEW.resolu_le := COALESCE(NEW.resolu_le, NOW());
    NEW.accord_soignant := true;
    NEW.accord_etablissement := true;
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_init_preferences_notifications()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  IF EXISTS (SELECT 1 FROM auth.users WHERE id = NEW.id) THEN
    INSERT INTO preferences_notifications (utilisateur_id, canal_email, canal_sms, canal_push, canal_in_app)
    VALUES (NEW.id, true, false, true, true)
    ON CONFLICT (utilisateur_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_desistement_garanti()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.statut = 'ASSIGNEE' AND NEW.statut = 'OUVERTE'
     AND NEW.garantie_remplacement IS TRUE
     AND NEW.est_arret_maladie IS NOT TRUE
     AND NEW.debut_le < NOW() + INTERVAL '48 hours'
     AND NEW.debut_le > NOW() - INTERVAL '4 hours' THEN
    PERFORM fn_diffuser_pool_urgence(NEW.id);
    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (NEW.etablissement_id, 'SYSTEM', 'Désistement — pool urgence alerté 🚨',
      'Le soignant s''est désisté de "' || fn_html_escape(NEW.intitule) ||
      '" à moins de 48h du début. Garantie remplacement : le pool d''urgence vient d''être alerté automatiquement.',
      '/etablissement/missions/' || NEW.id, 'ETABLISSEMENT');
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_litige_mapping_categorie()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.categorie_litige := CASE NEW.type_litige
    WHEN 'ABSENCE_SOIGNANT'                   THEN 'PRESENCE'::public.categorie_litige
    WHEN 'DEPART_ANTICIPE'                    THEN 'PRESENCE'::public.categorie_litige
    WHEN 'RETARD_IMPORTANT'                   THEN 'PRESENCE'::public.categorie_litige
    WHEN 'DESACCORD_HEURES_POINTAGE'          THEN 'PRESENCE'::public.categorie_litige
    WHEN 'DESACCORD_MONTANT_FACTURE'          THEN 'FINANCIER'::public.categorie_litige
    WHEN 'NON_PAIEMENT'                       THEN 'FINANCIER'::public.categorie_litige
    WHEN 'FRAIS_COMPLEMENTAIRES'              THEN 'FINANCIER'::public.categorie_litige
    WHEN 'CONDITIONS_MISSION_NON_RESPECTEES'  THEN 'CONDITIONS'::public.categorie_litige
    WHEN 'SECURITE_DANGER'                    THEN 'CONDITIONS'::public.categorie_litige
    WHEN 'COMPORTEMENT_SOIGNANT'              THEN 'COMPORTEMENT'::public.categorie_litige
    WHEN 'COMPORTEMENT_ETABLISSEMENT'         THEN 'COMPORTEMENT'::public.categorie_litige
    ELSE 'AUTRE'::public.categorie_litige
  END;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_pn_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$ BEGIN NEW.mis_a_jour_le := now(); RETURN NEW; END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_recalculer_score_v2()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_soignant_id UUID;
  v_etab_id UUID;
BEGIN
  IF TG_TABLE_NAME = 'notations_missions' THEN
    IF NEW.sens = 'ETAB_VERS_SOIGNANT' THEN
      v_soignant_id := NEW.note_id; v_etab_id := NEW.notateur_id;
    ELSE
      v_soignant_id := NEW.notateur_id; v_etab_id := NEW.note_id;
    END IF;
    PERFORM public.fn_calculer_score_fiabilite_v2(v_soignant_id, 'notation_recue');
    IF v_etab_id IS NOT NULL THEN
      PERFORM public.fn_calculer_score_etablissement(v_etab_id);
    END IF;

  ELSIF TG_TABLE_NAME = 'missions' THEN
    IF NEW.statut IN ('TERMINEE','ABSENCE') AND COALESCE(OLD.statut, '') <> NEW.statut::text
       AND NEW.soignant_assigne_id IS NOT NULL THEN
      PERFORM public.fn_calculer_score_fiabilite_v2(NEW.soignant_assigne_id, 'mission_' || NEW.statut::text);
    END IF;

  ELSIF TG_TABLE_NAME = 'litiges' THEN
    IF NEW.statut IN ('RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME','RESOLU_FAVEUR_SOIGNANT','RESOLU_FAVEUR_ETAB','RESOLU_PARTAGE','RESOLU_ACCORD_PARTIES')
       AND COALESCE(OLD.statut, '') <> NEW.statut::text
       AND NEW.soignant_id IS NOT NULL THEN
      PERFORM public.fn_calculer_score_fiabilite_v2(NEW.soignant_id, 'litige_resolu');
      IF NEW.etablissement_id IS NOT NULL THEN
        PERFORM public.fn_calculer_score_etablissement(NEW.etablissement_id);
      END IF;
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_recalcul_badge_ambassadeur()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_parrain_id UUID;
  v_nb_filleuls INT;
BEGIN
  IF (OLD.supprime_le IS NULL AND NEW.supprime_le IS NOT NULL)
     OR (COALESCE(OLD.statut_compte::text, '') <> 'SUSPENDU' AND NEW.statut_compte::text = 'SUSPENDU') THEN
    v_parrain_id := NEW.parraine_par;
    IF v_parrain_id IS NOT NULL THEN
      SELECT COUNT(*) INTO v_nb_filleuls FROM soignants
      WHERE parraine_par = v_parrain_id
        AND premiere_mission_le IS NOT NULL
        AND supprime_le IS NULL
        AND COALESCE(statut_compte::text, 'ACTIF') = 'ACTIF';
      IF v_nb_filleuls < 3 THEN
        UPDATE soignants SET badge_ambassadeur = false
        WHERE id = v_parrain_id AND COALESCE(badge_ambassadeur, false) = true;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_parrainage_commission_encaissee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_mission RECORD; v_parrainage RECORD; v_commission NUMERIC;
BEGIN
  IF NEW.statut <> 'PAYEE' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.statut, '') = 'PAYEE' THEN RETURN NEW; END IF;
  IF NEW.mission_id IS NULL THEN RETURN NEW; END IF;
  SELECT id, soignant_assigne_id INTO v_mission FROM missions WHERE id = NEW.mission_id;
  IF v_mission IS NULL OR v_mission.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_parrainage FROM parrainages WHERE filleul_id = v_mission.soignant_assigne_id AND statut IN ('FILLEUL_ACTIF','VALIDE_EN_ATTENTE_SEUIL') LIMIT 1;
  IF v_parrainage IS NULL THEN RETURN NEW; END IF;
  v_commission := COALESCE(NEW.montant_ht, 0);
  IF v_commission <= 0 THEN RETURN NEW; END IF;
  UPDATE parrainages SET commission_cumulee_filleul = COALESCE(commission_cumulee_filleul, 0) + v_commission WHERE id = v_parrainage.id;
  PERFORM public.fn_parrainage_verifier_seuils(v_parrainage.id);
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_notif_admin_remboursement_manuel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id UUID;
  v_soignant RECORD;
  v_montant NUMERIC;
  v_a_iban BOOLEAN;
BEGIN
  IF NEW.type_document <> 'AVOIR' OR NEW.mode_remboursement <> 'VIREMENT_MANUEL'
     OR NEW.date_remboursement IS NOT NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.mode_remboursement = 'VIREMENT_MANUEL'
     AND OLD.type_document = 'AVOIR' THEN
    RETURN NEW;
  END IF;

  SELECT prenom, nom, iban_virement INTO v_soignant
  FROM public.soignants WHERE id = NEW.soignant_id;
  v_a_iban := v_soignant.iban_virement IS NOT NULL AND length(trim(v_soignant.iban_virement)) > 0;
  v_montant := COALESCE(NEW.montant_ttc, NEW.montant_ht, 0);

  IF v_a_iban THEN
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES (
      'REMBOURSEMENT_AVOIR_SWAN',
      jsonb_build_object('avoir_id', NEW.id, 'soignant_id', NEW.soignant_id, 'montant', v_montant),
      'remboursement_avoir', NEW.id
    );
  END IF;

  FOR v_admin_id IN SELECT public.fn_list_admin_user_ids() LOOP
    INSERT INTO public.notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
    VALUES (
      v_admin_id, 'ADMIN', 'REMBOURSEMENT_MANUEL_A_FAIRE',
      CASE WHEN v_a_iban THEN '💸 Remboursement (virement SEPA auto)' ELSE '💸 Remboursement par virement à effectuer' END,
      'Avoir ' || COALESCE(NEW.numero_facture, '') || ' — ' ||
        to_char(v_montant, 'FM999G999D00') || ' € pour ' ||
        COALESCE(v_soignant.prenom, '') || ' ' || COALESCE(v_soignant.nom, '') ||
        CASE WHEN v_a_iban
             THEN ' : virement SEPA SWAN automatique initié.'
             ELSE ' : IBAN MANQUANT — virement manuel requis (relancer le soignant). Admin > Litiges > Avoirs.' END,
      '/admin/litiges',
      'facture_honoraire', NEW.id
    );
  END LOOP;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_litige_notify_support()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
BEGIN
  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
    IF v_token IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-support',
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
        body := jsonb_build_object(
          'sujet', 'Nouveau litige ouvert (' || COALESCE(NEW.type_litige::text, '') || ')',
          'corps', COALESCE(NEW.motif, '(sans motif)'),
          'source', 'Litige',
          'lien', '/admin/litiges'
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_parrainage_gmv_encaisse()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_parrainage RECORD; v_gmv NUMERIC;
BEGIN
  IF NEW.statut <> 'PAYEE' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.statut, '') = 'PAYEE' THEN RETURN NEW; END IF;
  IF NEW.soignant_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_parrainage FROM parrainages WHERE filleul_id = NEW.soignant_id AND statut IN ('FILLEUL_ACTIF','VALIDE_EN_ATTENTE_SEUIL') LIMIT 1;
  IF v_parrainage IS NULL THEN RETURN NEW; END IF;
  v_gmv := COALESCE(NEW.montant_ht, 0);
  IF v_gmv <= 0 THEN RETURN NEW; END IF;
  UPDATE parrainages SET gmv_cumule_filleul = COALESCE(gmv_cumule_filleul, 0) + v_gmv WHERE id = v_parrainage.id;
  PERFORM public.fn_parrainage_verifier_seuils(v_parrainage.id);
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_sms_annulation_tardive()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
    v_heures_avant NUMERIC;
BEGIN
    IF NEW.statut = 'OUVERTE' AND OLD.statut = 'ASSIGNEE' AND NEW.soignant_assigne_id IS NULL THEN
        v_heures_avant := EXTRACT(EPOCH FROM (NEW.debut_le - NOW())) / 3600;
        
        IF v_heures_avant < 24 THEN
            SELECT e.id, e.telephone_contact, e.nom, e.sms_actif
            INTO v_etab
            FROM etablissements e WHERE e.id = NEW.etablissement_id;
            
            IF v_etab.sms_actif AND v_etab.telephone_contact IS NOT NULL THEN
                INSERT INTO email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('SMS_ANNULATION_TARDIVE', v_etab.id, v_etab.telephone_contact, jsonb_build_object(
                    'etablissement', v_etab.nom,
                    'mission', NEW.intitule,
                    'heures_avant', ROUND(v_heures_avant, 1),
                    'telephone', v_etab.telephone_contact
                ));
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trigger_regen_pdf_immediate(p_facture_id uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_url TEXT;
  v_key TEXT;
  v_request_id BIGINT;
BEGIN
  IF p_facture_id IS NULL THEN RETURN NULL; END IF;

  SELECT valeur INTO v_url
    FROM public.parametres_litiges WHERE cle = 'generate_invoice_url';
  IF v_url IS NULL OR length(v_url) = 0 THEN
    RETURN NULL;
  END IF;

  BEGIN
    SELECT decrypted_secret INTO v_key
      FROM vault.decrypted_secrets
     WHERE name = 'service_role_key'
     LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_key := NULL;
  END;
  IF v_key IS NULL OR length(v_key) = 0 THEN
    RETURN NULL;
  END IF;

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := jsonb_build_object(
      'facture_id', p_facture_id,
      'service_role_reason', 'admin_resoudre_litige_immediate'
    )
  ) INTO v_request_id;

  RETURN v_request_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_verifier_onboarding_etab()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab RECORD;
BEGIN
  IF est_admin() THEN RETURN NEW; END IF;
  IF COALESCE(current_setting('app.internal_operation', true), '') = 'true' THEN RETURN NEW; END IF;

  SELECT contrat_service_signe, rib_s3_key, representant_identite_verifiee,
         coherence_identite, rattachement_verifie
  INTO v_etab
  FROM etablissements WHERE id = NEW.etablissement_id;

  IF NOT FOUND THEN RETURN NEW; END IF;

  IF NOT COALESCE(v_etab.contrat_service_signe, false) THEN
    RAISE EXCEPTION 'Inscription incomplète : vous devez signer le contrat de service Jolene avant de publier des missions. Rendez-vous sur /etablissement/finaliser-inscription.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- RIB retiré de la gate d'onboarding : il n'est pas nécessaire pour publier une mission
  -- (Jolene n'est pas tiers-payeur / agence d'intérim, pas de prélèvement direct au lancement).
  -- Il sera demandé au moment réellement utile (1er prélèvement SEPA / 1er remboursement).

  IF NOT COALESCE(v_etab.representant_identite_verifiee, false) THEN
    RAISE EXCEPTION 'Inscription incomplète : l''identité du représentant légal doit être vérifiée avant de publier des missions. Rendez-vous sur /etablissement/verification.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_etab.coherence_identite = 'INCOHERENT' AND NOT COALESCE(v_etab.rattachement_verifie, false) THEN
    RAISE EXCEPTION 'Vérification en cours : le nom de votre établissement ne correspond pas à la raison sociale officielle (SIRET/FINESS). Corrigez vos informations sur /etablissement/profil, ou attendez la validation de notre équipe (24-48h).'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT COALESCE(v_etab.rattachement_verifie, false) THEN
    RAISE EXCEPTION 'Vérification en cours : votre rattachement à l''établissement doit être confirmé. Si vous êtes le dirigeant, c''est automatique ; sinon, fournissez un justificatif de fonction sur /etablissement/verification. À défaut, notre équipe valide sous 24-48h.'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_valider_parrainage_etab()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  -- Mécanique déplacée vers fn_trg_valider_parrainage_etab_commission (seuil 100€ de
  -- commission encaissée, crédit 50€ parrain + 50€ filleul). No-op de compatibilité.
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_valider_parrainage_soignant_premiere_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_parrainage RECORD;
  v_parrain_a_mission BOOLEAN;
  v_nb_filleuls_actifs INT;
  v_filleul_parrainage RECORD;
  v_prime integer := (public.fn_param_num('prime_parrainage_eur', 25))::integer;
  v_seuil_gmv numeric := public.fn_param_num('seuil_gmv_parrainage_eur', 500);
BEGIN
  IF NEW.statut::text <> 'TERMINEE' OR COALESCE(OLD.statut::text, '') = 'TERMINEE' THEN RETURN NEW; END IF;
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_parrainage FROM parrainages
  WHERE filleul_id = NEW.soignant_assigne_id AND statut = 'EN_ATTENTE'
  LIMIT 1;

  IF v_parrainage IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM missions
      WHERE soignant_assigne_id = v_parrainage.parrain_id AND statut = 'TERMINEE'
      LIMIT 1
    ) INTO v_parrain_a_mission;

    IF v_parrain_a_mission THEN
      SELECT COUNT(*) INTO v_nb_filleuls_actifs FROM parrainages
      WHERE parrain_id = v_parrainage.parrain_id
        AND statut IN ('VALIDE', 'FILLEUL_ACTIF', 'VALIDE_EN_ATTENTE_SEUIL', 'PRIME_VERSEE');

      IF v_nb_filleuls_actifs < 20 THEN
        UPDATE parrainages
        SET statut = 'FILLEUL_ACTIF', filleul_active_le = NOW(), valide_le = NOW()
        WHERE id = v_parrainage.id;

        INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
        VALUES (
          v_parrainage.parrain_id, 'SOIGNANT', 'PARRAINAGE',
          '🎉 Ton filleul a fait sa 1ʳᵉ mission !',
          'Vos primes de ' || v_prime || '€ chacun seront versées quand il aura atteint ' || v_seuil_gmv || '€ de missions encaissées. Suis sa progression sur ta page parrainage.',
          '/soignant/parrainage'
        );

        PERFORM public.fn_ecrire_audit_safe(
          p_acteur_id := v_parrainage.parrain_id, p_type_acteur := 'SYSTEME',
          p_action := 'PARRAINAGE_SOIGNANT_FILLEUL_ACTIF',
          p_type_ressource := 'parrainage', p_id_ressource := v_parrainage.id,
          p_details := jsonb_build_object('filleul_id', v_parrainage.filleul_id, 'mission_id', NEW.id)
        );
      ELSE
        UPDATE parrainages SET statut = 'EXPIRED' WHERE id = v_parrainage.id;
      END IF;
    END IF;
  END IF;

  FOR v_filleul_parrainage IN
    SELECT p.*, s.premiere_mission_le FROM parrainages p
    JOIN soignants s ON s.id = p.filleul_id
    WHERE p.parrain_id = NEW.soignant_assigne_id
      AND p.statut = 'EN_ATTENTE'
      AND s.premiere_mission_le IS NOT NULL
  LOOP
    SELECT COUNT(*) INTO v_nb_filleuls_actifs FROM parrainages
    WHERE parrain_id = NEW.soignant_assigne_id
      AND statut IN ('VALIDE', 'FILLEUL_ACTIF', 'VALIDE_EN_ATTENTE_SEUIL', 'PRIME_VERSEE');

    IF v_nb_filleuls_actifs < 20 THEN
      UPDATE parrainages
      SET statut = 'FILLEUL_ACTIF', filleul_active_le = NOW(), valide_le = NOW()
      WHERE id = v_filleul_parrainage.id;

      INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
      VALUES (
        NEW.soignant_assigne_id, 'SOIGNANT', 'PARRAINAGE',
        '🎉 Ton filleul est activé !',
        'Vos primes de ' || v_prime || '€ chacun seront versées à ' || v_seuil_gmv || '€ de missions encaissées par ton filleul.',
        '/soignant/parrainage'
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_recompute_score_urgence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  IF EXISTS (SELECT 1 FROM missions m WHERE m.id = NEW.mission_id AND COALESCE(m.est_urgente, false) = true) THEN
    IF TG_OP = 'INSERT' OR NEW.statut IS DISTINCT FROM OLD.statut THEN
      PERFORM public.fn_calculer_score_fiabilite_v2(NEW.soignant_id, 'engagement_urgence');
    END IF;
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_valider_parrainage_etab_commission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_parrainage RECORD;
  v_filleul_nom TEXT;
  v_parrain_nom TEXT;
  v_total_commission NUMERIC;
  v_credit_parrain UUID;
  v_credit_filleul UUID;
  v_nb_validations_mois INT;
  v_prime INT := 50;
BEGIN
  IF NEW.statut <> 'PAYEE' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.statut, '') = 'PAYEE' THEN RETURN NEW; END IF;
  IF NEW.etablissement_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_parrainage FROM parrainages_etablissements
  WHERE filleul_etab_id = NEW.etablissement_id AND statut = 'PENDING'
  LIMIT 1;
  IF v_parrainage.id IS NULL THEN RETURN NEW; END IF;

  SELECT COALESCE(SUM(montant_ht), 0) INTO v_total_commission
  FROM factures
  WHERE etablissement_id = NEW.etablissement_id
    AND statut = 'PAYEE'
    AND COALESCE(montant_ht, 0) > 0;

  IF v_total_commission < 100 THEN RETURN NEW; END IF;

  UPDATE parrainages_etablissements
  SET statut = 'VALIDATED', valide_le = NOW(), mis_a_jour_le = NOW()
  WHERE id = v_parrainage.id;

  SELECT nom INTO v_filleul_nom FROM etablissements WHERE id = v_parrainage.filleul_etab_id;
  SELECT nom INTO v_parrain_nom FROM etablissements WHERE id = v_parrainage.parrain_etab_id;

  INSERT INTO credits_etablissement (etablissement_id, montant_eur, motif, parrainage_id)
  VALUES (v_parrainage.parrain_etab_id, v_prime, 'PARRAINAGE', v_parrainage.id)
  RETURNING id INTO v_credit_parrain;

  INSERT INTO credits_etablissement (etablissement_id, montant_eur, motif, parrainage_id)
  VALUES (v_parrainage.filleul_etab_id, v_prime, 'PARRAINAGE', v_parrainage.id)
  RETURNING id INTO v_credit_filleul;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_parrainage.parrain_etab_id, p_type_acteur := 'SYSTEME',
    p_action := 'CREDIT_PARRAINAGE_CREE', p_type_ressource := 'parrainage_etab', p_id_ressource := v_parrainage.id,
    p_details := jsonb_build_object('credit_parrain_id', v_credit_parrain, 'credit_filleul_id', v_credit_filleul,
                                    'montant_eur', v_prime, 'filleul_etab_id', v_parrainage.filleul_etab_id,
                                    'commission_cumulee', v_total_commission)
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_parrainage.filleul_etab_id, p_type_acteur := 'SYSTEME',
    p_action := 'PARRAINAGE_ETAB_VALIDE', p_type_ressource := 'parrainage_etab', p_id_ressource := v_parrainage.id,
    p_details := jsonb_build_object('parrain_etab_id', v_parrainage.parrain_etab_id, 'facture_id', NEW.id)
  );

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES (
    v_parrainage.parrain_etab_id, 'ETABLISSEMENT', 'CREDIT_PARRAINAGE',
    '🎉 +' || v_prime || '€ de crédit Jolene !',
    'Votre filleul ' || COALESCE(v_filleul_nom, 'établissement') || ' a généré 100€ de commission. ' || v_prime || '€ de crédit ont été ajoutés et seront déduits de votre prochaine facture commission.',
    '/etablissement/parrainage'
  );

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES (
    v_parrainage.filleul_etab_id, 'ETABLISSEMENT', 'CREDIT_PARRAINAGE',
    '🎉 +' || v_prime || '€ de crédit parrainage !',
    'Grâce au parrainage de ' || COALESCE(v_parrain_nom, 'votre parrain') || ', ' || v_prime || '€ de crédit ont été ajoutés et seront déduits de votre prochaine facture commission.',
    '/etablissement/parrainage'
  );

  SELECT COUNT(*) INTO v_nb_validations_mois FROM parrainages_etablissements
  WHERE parrain_etab_id = v_parrainage.parrain_etab_id
    AND statut = 'VALIDATED' AND valide_le >= DATE_TRUNC('month', NOW());
  IF v_nb_validations_mois > 5 THEN
    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_parrainage.parrain_etab_id, p_type_acteur := 'SYSTEME',
      p_action := 'PARRAINAGE_ETAB_ANOMALIE', p_type_ressource := 'etablissement',
      p_id_ressource := v_parrainage.parrain_etab_id,
      p_details := jsonb_build_object('nb_validations_mois', v_nb_validations_mois)
    );
  END IF;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_trg_verifier_mandat_avant_debut()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.type_contrat_applique = 'LIBERAL' AND NEW.soignant_assigne_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM soignants s
      WHERE s.id = NEW.soignant_assigne_id AND s.mandat_facturation_signe IS TRUE
    ) THEN
      RAISE EXCEPTION 'Mandat de facturation non signé — signe-le (Profil > Mandat de facturation, 1 min) pour démarrer cette mission libérale. Sans lui, Jolene ne peut pas émettre tes factures d''honoraires.';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_update_document_verification(p_document_id uuid, p_statut_verification text, p_motif_rejet text DEFAULT NULL::text, p_valide_depuis date DEFAULT NULL::date, p_valide_jusqua date DEFAULT NULL::date, p_verifie_le timestamp with time zone DEFAULT now())
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Cette fonction est appelée par les Edge Functions (service_role)
    -- Les triggers ont maintenant un passthrough service_role, donc plus besoin de DISABLE
    UPDATE public.documents_soignants
    SET
        statut_verification = p_statut_verification::statut_verification,
        motif_rejet = p_motif_rejet,
        valide_depuis = COALESCE(p_valide_depuis, valide_depuis),
        valide_jusqua = COALESCE(p_valide_jusqua, valide_jusqua),
        verifie_le = p_verifie_le,
        modifie_le = NOW()
    WHERE id = p_document_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_uploader_contrat_plateforme(p_contrat_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
BEGIN
    IF v_etab_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Non autorise');
    END IF;

    UPDATE etablissements SET
        contrat_url = p_contrat_url,
        contrat_uploade_le = NOW(),
        contrat_valide = FALSE
    WHERE id = v_etab_id;

    RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_types_exercice_autorises(p_profession text)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_result TEXT[];
BEGIN
    SELECT types_exercice_autorises INTO v_result
    FROM regles_exercice_profession WHERE profession::TEXT = p_profession;
    RETURN COALESCE(v_result, ARRAY['SALARIE', 'LIBERAL', 'MIXTE']);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_uploader_contrat_travail_mission(p_mission_id uuid, p_pdf_s3_key text, p_nom_fichier text, p_taille_octets bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_etab_id uuid;
  v_soignant_id uuid;
  v_existing_id uuid;
  v_action text;
BEGIN
  -- Récupérer etab + soignant de la mission
  SELECT etablissement_id, soignant_assigne_id
  INTO v_etab_id, v_soignant_id
  FROM public.missions
  WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  -- Vérification : actor doit être l'établissement (ou admin)
  IF NOT est_admin() AND v_etab_id IS DISTINCT FROM mon_etablissement_id() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  IF v_soignant_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Mission sans soignant assigné');
  END IF;

  -- INSERT ou UPDATE (idempotent par mission_id)
  SELECT id INTO v_existing_id FROM public.contrats_travail_missions WHERE mission_id = p_mission_id;

  IF v_existing_id IS NULL THEN
    INSERT INTO public.contrats_travail_missions (mission_id, etablissement_id, soignant_id, pdf_s3_key, nom_fichier, taille_octets, uploaded_by, uploaded_at)
    VALUES (p_mission_id, v_etab_id, v_soignant_id, p_pdf_s3_key, p_nom_fichier, p_taille_octets, v_actor, now());
    v_action := 'CONTRAT_TRAVAIL_UPLOADE';
  ELSE
    UPDATE public.contrats_travail_missions
    SET pdf_s3_key = p_pdf_s3_key,
        nom_fichier = p_nom_fichier,
        taille_octets = p_taille_octets,
        uploaded_at = now(),
        uploaded_by = v_actor
    WHERE id = v_existing_id;
    v_action := 'CONTRAT_TRAVAIL_REMPLACE';
  END IF;

  PERFORM fn_ecrire_audit_safe(
    v_actor,
    CASE WHEN est_admin() THEN 'ADMIN_PLATEFORME' ELSE 'ADMIN_ETABLISSEMENT' END,
    v_action, 'mission', p_mission_id,
    NULL, jsonb_build_object('nom_fichier', p_nom_fichier, 'taille_octets', p_taille_octets),
    NULL, NULL
  );

  RETURN jsonb_build_object('ok', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_update_presence()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO presence_status(user_id, last_seen_at, status, maj_le)
  VALUES (v_user_id, NOW(), 'ONLINE', NOW())
  ON CONFLICT (user_id) DO UPDATE
    SET last_seen_at = NOW(),
        status = 'ONLINE',
        maj_le = NOW();
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_typing_start(p_conversation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_is_participant boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'NON_AUTHENTIFIE';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM conversations
    WHERE id = p_conversation_id
      AND (participant_1_id = v_user_id OR participant_2_id = v_user_id)
  ) INTO v_is_participant;

  IF NOT v_is_participant THEN
    RAISE EXCEPTION 'NON_AUTORISE';
  END IF;

  INSERT INTO typing_status(conversation_id, user_id, started_at)
  VALUES (p_conversation_id, v_user_id, NOW())
  ON CONFLICT (conversation_id, user_id) DO UPDATE
    SET started_at = NOW();
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_typing_stop(p_conversation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  DELETE FROM typing_status
  WHERE conversation_id = p_conversation_id
    AND user_id = v_user_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_update_streak_on_swipe()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_last_date date;
  v_today date := current_date;
  v_new_streak integer;
  v_max_streak integer;
BEGIN
  SELECT last_activity_date, streak_count, max_streak
    INTO v_last_date, v_new_streak, v_max_streak
    FROM public.streaks_soignant
   WHERE soignant_id = NEW.soignant_id;

  IF v_last_date IS NULL THEN
    INSERT INTO public.streaks_soignant (soignant_id, streak_count, last_activity_date, max_streak, updated_at)
      VALUES (NEW.soignant_id, 1, v_today, 1, now())
      ON CONFLICT (soignant_id) DO NOTHING;
    RETURN NEW;
  END IF;

  IF v_last_date = v_today THEN
    RETURN NEW;
  END IF;

  IF v_last_date = v_today - interval '1 day' THEN
    v_new_streak := v_new_streak + 1;
  ELSE
    v_new_streak := 1;
  END IF;

  IF v_new_streak > v_max_streak THEN
    v_max_streak := v_new_streak;
  END IF;

  UPDATE public.streaks_soignant
     SET streak_count = v_new_streak,
         last_activity_date = v_today,
         max_streak = v_max_streak,
         updated_at = now()
   WHERE soignant_id = NEW.soignant_id;

  IF v_new_streak = 30 THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type, metadata)
      VALUES (NEW.soignant_id, '30_DAYS_STREAK', jsonb_build_object('streak', 30))
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  IF v_new_streak = 100 THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type, metadata)
      VALUES (NEW.soignant_id, '100_DAYS_STREAK', jsonb_build_object('streak', 100))
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_valider_presence(p_presence_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid;
  v_presence record;
BEGIN
  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  SELECT p.* INTO v_presence
  FROM presences p
  JOIN missions m ON m.id = p.mission_id
  WHERE p.id = p_presence_id
    AND m.etablissement_id = v_etab_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Présence introuvable');
  END IF;

  IF v_presence.valide_par_etablissement = true THEN
    RETURN jsonb_build_object('success', false, 'error', 'Déjà validée');
  END IF;

  UPDATE presences
  SET valide_par_etablissement = true,
      valide_le = now(),
      modifie_le = now()
  WHERE id = p_presence_id;

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_valider_presences_lot(p_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid;
  v_count integer;
BEGIN
  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  UPDATE presences p
  SET valide_par_etablissement = true,
      valide_le = now(),
      modifie_le = now()
  FROM missions m
  WHERE p.id = ANY(p_ids)
    AND p.mission_id = m.id
    AND m.etablissement_id = v_etab_id
    AND p.valide_par_etablissement = false
    AND p.perimetre_gps_valide = true
    AND (p.alerte_teleportation = false OR p.alerte_teleportation IS NULL);

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN jsonb_build_object('success', true, 'nb_validees', v_count);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_upsert_token_push(p_token text, p_plateforme text DEFAULT 'WEB'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_json JSONB;
    v_endpoint TEXT;
    v_p256dh TEXT;
    v_auth_key TEXT;
BEGIN
    -- Tenter de parser le token comme JSON (Web Push subscription)
    BEGIN
        v_json := p_token::JSONB;
        v_endpoint := v_json->>'endpoint';
        v_p256dh := v_json->'keys'->>'p256dh';
        v_auth_key := v_json->'keys'->>'auth';
    EXCEPTION WHEN OTHERS THEN
        -- Pas du JSON = ancien token FCM, on garde tel quel
        v_endpoint := NULL;
        v_p256dh := NULL;
        v_auth_key := NULL;
    END;

    INSERT INTO tokens_push (utilisateur_id, token, plateforme, endpoint, p256dh, auth_key)
    VALUES (auth.uid(), p_token, p_plateforme, v_endpoint, v_p256dh, v_auth_key)
    ON CONFLICT (token) DO UPDATE SET
        utilisateur_id = auth.uid(),
        plateforme = p_plateforme,
        endpoint = COALESCE(EXCLUDED.endpoint, tokens_push.endpoint),
        p256dh = COALESCE(EXCLUDED.p256dh, tokens_push.p256dh),
        auth_key = COALESCE(EXCLUDED.auth_key, tokens_push.auth_key),
        derniere_utilisation = now();
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_user_id_pour_etablissement(p_etablissement_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid;
  v_caller uuid := auth.uid();
  v_autorise boolean;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;

  v_autorise :=
       est_admin()
    OR (mon_etablissement_id() IS NOT NULL AND p_etablissement_id = mon_etablissement_id())
    OR EXISTS (
         SELECT 1 FROM public.missions m
         WHERE m.etablissement_id = p_etablissement_id AND m.soignant_assigne_id = v_caller
       )
    OR EXISTS (
         SELECT 1 FROM public.candidatures c
         JOIN public.missions m ON m.id = c.mission_id
         WHERE m.etablissement_id = p_etablissement_id AND c.soignant_id = v_caller
       );

  IF NOT COALESCE(v_autorise, false) THEN
    RAISE EXCEPTION 'Non autorisé' USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_user_id FROM auth.users
  WHERE (raw_app_meta_data ->> 'etablissement_id')::uuid = p_etablissement_id
  LIMIT 1;
  RETURN v_user_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_valider_alerte_presence(p_presence_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_presence RECORD;
    v_etab_id UUID := mon_etablissement_id();
BEGIN
    SELECT p.*, m.etablissement_id FROM presences p 
    JOIN missions m ON m.id = p.mission_id 
    WHERE p.id = p_presence_id INTO v_presence;
    
    IF v_presence IS NULL THEN RETURN jsonb_build_object('error', 'Présence introuvable'); END IF;
    
    IF v_presence.etablissement_id != v_etab_id AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    
    UPDATE presences SET 
        valide_par_etablissement = TRUE, 
        valide_le = NOW()
    WHERE id = p_presence_id;
    
    RETURN jsonb_build_object('success', TRUE, 'message', 'Présence validée');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_valider_presences_72h_auto()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count int;
  v_delai interval := ((public.fn_param_num('delai_autovalidation_presence_h', 72))::text || ' hours')::interval;
BEGIN
  UPDATE public.presences
  SET valide_auto_72h_le = NOW(), valide_par_etablissement = true,
      valide_le = COALESCE(valide_le, NOW()), modifie_le = NOW()
  WHERE pointage_depart_le IS NOT NULL
    AND pointage_depart_le < NOW() - v_delai
    AND COALESCE(valide_par_etablissement, false) = false
    AND motif_litige IS NULL
    AND valide_auto_72h_le IS NULL
    AND COALESCE(alerte_teleportation, false) = false
    AND (alertes_fraude IS NULL OR alertes_fraude = '[]'::JSONB);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count > 0 THEN
    INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'cron', NULL,
      jsonb_build_object('evenement', 'PRESENCES_VALIDEES_AUTO_72H', 'count', v_count, 'exec_le', NOW()));
  END IF;
  RETURN jsonb_build_object('success', true, 'count_validees', v_count);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_valider_code_secours(p_mission_id uuid, p_code text, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_precision numeric DEFAULT NULL::numeric, p_terminal_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_mission RECORD;
  v_code_row RECORD;
  v_presence RECORD;
  v_type_detecte text;
  v_now timestamptz := NOW();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_code IS NULL OR p_code !~ '^[0-9]{6}$' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CODE_FORMAT_INVALIDE',
                                'error', 'Le code doit être 6 chiffres.');
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL OR v_mission.soignant_assigne_id != v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Vous n''êtes pas assigné à cette mission.');
  END IF;

  -- Trouver le code matching (non utilisé, non expiré)
  -- Boucle car bcrypt nécessite la comparaison hash par hash
  SELECT * INTO v_code_row FROM public.codes_secours_mission
  WHERE mission_id = p_mission_id
    AND utilise = false
    AND expire_le > v_now
    AND code_hash = crypt(p_code, code_hash)
  LIMIT 1;

  IF v_code_row IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INVALIDE',
                                'error', 'Code incorrect, déjà utilisé ou expiré.');
  END IF;

  -- Déterminer type pointage selon presences
  SELECT * INTO v_presence FROM public.presences
  WHERE mission_id = v_mission.id AND soignant_id = v_uid LIMIT 1;

  IF v_code_row.type = 'ARRIVEE' THEN
    v_type_detecte := 'ARRIVEE';
  ELSIF v_code_row.type = 'DEPART' THEN
    v_type_detecte := 'DEPART';
  ELSE
    v_type_detecte := CASE WHEN v_presence IS NULL THEN 'ARRIVEE' ELSE 'DEPART' END;
  END IF;

  -- Vérifs identiques scan QR
  IF v_type_detecte = 'ARRIVEE' AND v_presence.id IS NOT NULL AND v_presence.pointage_arrivee_le IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_POINTE');
  END IF;
  IF v_type_detecte = 'DEPART' THEN
    IF v_presence IS NULL OR v_presence.pointage_arrivee_le IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_SANS_ARRIVEE');
    END IF;
    IF v_presence.pointage_depart_le IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_DEJA_POINTE');
    END IF;
    IF v_now < v_presence.pointage_arrivee_le + INTERVAL '30 minutes' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_TROP_RAPIDE');
    END IF;
  END IF;

  -- Marquer code utilisé
  UPDATE public.codes_secours_mission SET
    utilise = true, utilise_le = v_now, utilise_par = v_uid
  WHERE id = v_code_row.id;

  -- INSERT/UPDATE presence
  IF v_type_detecte = 'ARRIVEE' THEN
    IF v_presence IS NULL THEN
      INSERT INTO public.presences (
        mission_id, soignant_id, pointage_arrivee_le,
        arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
        arrivee_id_terminal, methode_pointage_arrivee
      ) VALUES (v_mission.id, v_uid, v_now, p_lat, p_lng, p_precision,
        p_terminal_id, 'CODE_SECOURS');
    ELSE
      UPDATE public.presences SET
        pointage_arrivee_le = v_now,
        arrivee_lat = p_lat, arrivee_lng = p_lng,
        arrivee_precision_gps_m = p_precision,
        arrivee_id_terminal = p_terminal_id,
        methode_pointage_arrivee = 'CODE_SECOURS'
      WHERE id = v_presence.id;
    END IF;
    UPDATE public.missions SET statut = 'EN_COURS', modifie_le = NOW()
    WHERE id = v_mission.id AND statut = 'ASSIGNEE';
  ELSE
    UPDATE public.presences SET
      pointage_depart_le = v_now,
      depart_lat = p_lat, depart_lng = p_lng,
      depart_precision_gps_m = p_precision,
      depart_id_terminal = p_terminal_id,
      methode_pointage_depart = 'CODE_SECOURS'
    WHERE id = v_presence.id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'methode_detectee', v_type_detecte,
    'mission_id', v_mission.id,
    'horodatage', v_now
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_vagues_notification_urgentes()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_m RECORD;
  v_s RECORD;
  v_taille int;
  v_envoyes int := 0;
  v_missions int := 0;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_corps text;
BEGIN
  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN v_token := NULL; END;

  FOR v_m IN
    SELECT m.id, m.intitule, m.profession_requise, m.taux_horaire_base,
           m.debut_le, m.cree_le, m.etablissement_id,
           e.adresse_ville AS etab_ville, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND m.est_urgente
      AND m.remplacement_de_mission_id IS NULL           -- la chaîne remplacement a sa propre diffusion
      AND m.debut_le BETWEEN NOW() AND NOW() + INTERVAL '48 hours'
      AND m.intitule NOT LIKE '[%'                        -- jamais les missions de test
      AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.mission_id = m.id)
  LOOP
    v_missions := v_missions + 1;
    -- Taille de vague selon l'ancienneté de la mission (cron */15 → deltas).
    v_taille := CASE
      WHEN v_m.cree_le > NOW() - INTERVAL '15 minutes' THEN 10
      WHEN v_m.cree_le > NOW() - INTERVAL '30 minutes' THEN 30
      ELSE 60
    END;

    v_corps := fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') ||
               ', débute le ' || TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') ||
               ' à ' || COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h.';

    FOR v_s IN
      SELECT s.id AS soignant_id
      FROM soignants s
      LEFT JOIN matching_scores ms ON ms.soignant_id = s.id AND ms.mission_id = v_m.id
      WHERE s.profession = v_m.profession_requise
        AND s.supprime_le IS NULL
        AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
        AND COALESCE(s.tous_documents_valides, false)
        AND NOT fn_est_exclu(s.id, v_m.etablissement_id)
        AND NOT EXISTS (SELECT 1 FROM swipes sw WHERE sw.mission_id = v_m.id AND sw.soignant_id = s.id)
        AND (s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
             OR fn_haversine_distance_m(s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng)
                <= COALESCE(s.rayon_deplacement_km, 50) * 1000)
        -- dédup par (soignant, mission) : chaque cron n'envoie que le delta
        AND NOT EXISTS (
          SELECT 1 FROM notifications n
          WHERE n.destinataire_id = s.id AND n.type = 'MISSION_URGENTE'
            AND n.lien = '/soignant/missions/' || v_m.id)
        -- anti-spam : max 3 pushs urgents / 24 h / soignant
        AND (SELECT COUNT(*) FROM notifications n2
             WHERE n2.destinataire_id = s.id AND n2.type = 'MISSION_URGENTE'
               AND n2.cree_le > NOW() - INTERVAL '24 hours') < 3
      ORDER BY COALESCE(ms.score_global, 0) DESC,
               fn_haversine_distance_m(COALESCE(s.adresse_lat, 0), COALESCE(s.adresse_lng, 0),
                                       COALESCE(v_m.etab_lat, 0), COALESCE(v_m.etab_lng, 0)) ASC
      LIMIT v_taille
    LOOP
      INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (v_s.soignant_id, 'MISSION_URGENTE',
        '⚡ Mission urgente sélectionnée pour toi',
        v_corps, '/soignant/missions/' || v_m.id, 'SOIGNANT');

      IF v_token IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-push',
            headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
            body := jsonb_build_object(
              'destinataire_id', v_s.soignant_id, 'type_evenement', 'MISSION_URGENTE',
              'titre', '⚡ Mission urgente sélectionnée pour toi', 'corps', v_corps,
              'data', jsonb_build_object('mission_id', v_m.id, 'lien', '/soignant/missions/' || v_m.id)
            )
          );
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;

      v_envoyes := v_envoyes + 1;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'missions', v_missions, 'notifications', v_envoyes);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_valider_transition_statut_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_transitions_valides text[][];
    v_valide boolean := false;
    v_pair text[];
BEGIN
    IF NEW.statut IS NOT DISTINCT FROM OLD.statut THEN
        RETURN NEW;
    END IF;

    v_transitions_valides := ARRAY[
        ARRAY['OUVERTE', 'ASSIGNEE'],
        ARRAY['OUVERTE', 'ANNULEE_PAR_ETABLISSEMENT'],
        ARRAY['OUVERTE', 'EXPIREE'],
        ARRAY['ASSIGNEE', 'EN_COURS'],
        ARRAY['ASSIGNEE', 'OUVERTE'],
        ARRAY['ASSIGNEE', 'ANNULEE_PAR_ETABLISSEMENT'],
        ARRAY['ASSIGNEE', 'ANNULEE_PAR_SOIGNANT'],
        ARRAY['ASSIGNEE', 'ABSENCE'],
        ARRAY['ASSIGNEE', 'EXPIREE'],
        ARRAY['EN_COURS', 'TERMINEE'],
        ARRAY['EN_COURS', 'ABSENCE'],
        ARRAY['EN_COURS', 'LITIGE'],
        ARRAY['EN_COURS', 'ANNULEE_PAR_ETABLISSEMENT'],
        ARRAY['LITIGE', 'TERMINEE'],
        ARRAY['LITIGE', 'ANNULEE_PAR_ETABLISSEMENT']
    ];

    FOREACH v_pair SLICE 1 IN ARRAY v_transitions_valides LOOP
        IF OLD.statut::text = v_pair[1] AND NEW.statut::text = v_pair[2] THEN
            v_valide := true;
            EXIT;
        END IF;
    END LOOP;

    IF NOT v_valide AND NOT est_admin() THEN
        RAISE EXCEPTION 'Transition de statut invalide : % → %', OLD.statut, NEW.statut;
    END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_verifier_documents_expirants()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count INTEGER := 0; v_doc RECORD; v_sid UUID;
BEGIN
    FOR v_doc IN
        SELECT d.id, d.soignant_id, d.type_document, d.valide_jusqua, s.prenom, s.email
        FROM documents_soignants d JOIN soignants s ON s.id = d.soignant_id
        WHERE d.valide_jusqua IS NOT NULL AND d.valide_jusqua BETWEEN CURRENT_DATE AND CURRENT_DATE + 30
          AND d.supprime_le IS NULL AND d.statut_verification = 'VERIFIE' AND d.rappel_j30_envoye = FALSE
    LOOP
        UPDATE documents_soignants SET rappel_j30_envoye = TRUE WHERE id = v_doc.id;
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_doc.soignant_id, 'DOCUMENT_EXPIRANT', 'Document bientôt expiré ⚠️',
            'Votre ' || v_doc.type_document || ' expire le ' || v_doc.valide_jusqua, '/soignant/documents', 'SOIGNANT');
        v_count := v_count + 1;
    END LOOP;
    FOR v_doc IN
        SELECT d.id, d.soignant_id, d.type_document, d.valide_jusqua FROM documents_soignants d
        WHERE d.valide_jusqua IS NOT NULL AND d.valide_jusqua BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
          AND d.supprime_le IS NULL AND d.rappel_j7_envoye = FALSE
    LOOP
        UPDATE documents_soignants SET rappel_j7_envoye = TRUE WHERE id = v_doc.id;
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_doc.soignant_id, 'DOCUMENT_EXPIRANT', '⚠️ Document expire dans 7 jours',
            'Votre ' || v_doc.type_document || ' expire le ' || v_doc.valide_jusqua || '. Renouvelez-le maintenant.', '/soignant/documents', 'SOIGNANT');
        v_count := v_count + 1;
    END LOOP;
    FOR v_sid IN
        SELECT DISTINCT d.soignant_id FROM documents_soignants d
        JOIN documents_requis_par_profession r ON d.type_document = r.type_document
        JOIN soignants s ON s.id = d.soignant_id AND s.profession = r.profession
        WHERE d.valide_jusqua < CURRENT_DATE AND d.supprime_le IS NULL AND r.est_critique = TRUE
    LOOP
        PERFORM fn_calculer_tous_documents_valides(v_sid);
    END LOOP;
    RETURN v_count;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_verifier_coherence_identite(p_soignant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_soignant RECORD;
    v_doc_identite RECORD;
    v_coherence_profil_rpps BOOLEAN;
    v_coherence_profil_doc BOOLEAN;
    v_coherence_rpps_doc BOOLEAN;
    v_all_ok BOOLEAN;
    v_details JSONB;
BEGIN
    SELECT * INTO v_soignant FROM soignants WHERE id = p_soignant_id;
    IF v_soignant IS NULL THEN RETURN jsonb_build_object('error', 'Soignant introuvable'); END IF;

    SELECT * INTO v_doc_identite FROM documents_soignants 
    WHERE soignant_id = p_soignant_id AND type_document = 'CARTE_IDENTITE' 
    AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
    ORDER BY televerse_le DESC LIMIT 1;

    -- 1. Profil vs RPPS API
    v_coherence_profil_rpps := FALSE;
    IF v_soignant.rpps_verifie AND v_soignant.rpps_nom_api IS NOT NULL THEN
        v_coherence_profil_rpps := (
            UPPER(TRIM(v_soignant.nom)) = UPPER(TRIM(v_soignant.rpps_nom_api))
            OR UPPER(TRIM(v_soignant.nom)) LIKE '%' || UPPER(TRIM(v_soignant.rpps_nom_api)) || '%'
            OR UPPER(TRIM(v_soignant.rpps_nom_api)) LIKE '%' || UPPER(TRIM(v_soignant.nom)) || '%'
        );
    END IF;

    -- 2. Profil vs Document CNI (IA)
    v_coherence_profil_doc := FALSE;
    IF v_doc_identite.id IS NOT NULL AND v_doc_identite.nom_extrait_ia IS NOT NULL THEN
        v_coherence_profil_doc := (
            UPPER(TRIM(v_soignant.nom)) = UPPER(TRIM(v_doc_identite.nom_extrait_ia))
            OR UPPER(TRIM(v_soignant.nom)) LIKE '%' || UPPER(TRIM(v_doc_identite.nom_extrait_ia)) || '%'
            OR UPPER(TRIM(v_doc_identite.nom_extrait_ia)) LIKE '%' || UPPER(TRIM(v_soignant.nom)) || '%'
        );
    END IF;

    -- 3. RPPS API vs Document CNI
    v_coherence_rpps_doc := FALSE;
    IF v_soignant.rpps_nom_api IS NOT NULL AND v_doc_identite.id IS NOT NULL AND v_doc_identite.nom_extrait_ia IS NOT NULL THEN
        v_coherence_rpps_doc := (
            UPPER(TRIM(v_soignant.rpps_nom_api)) = UPPER(TRIM(v_doc_identite.nom_extrait_ia))
            OR UPPER(TRIM(v_soignant.rpps_nom_api)) LIKE '%' || UPPER(TRIM(v_doc_identite.nom_extrait_ia)) || '%'
            OR UPPER(TRIM(v_doc_identite.nom_extrait_ia)) LIKE '%' || UPPER(TRIM(v_soignant.rpps_nom_api)) || '%'
        );
    END IF;

    v_all_ok := v_coherence_profil_rpps AND v_coherence_profil_doc AND v_coherence_rpps_doc;

    v_details := jsonb_build_object(
        'nom_profil', v_soignant.nom,
        'prenom_profil', v_soignant.prenom,
        'nom_rpps', v_soignant.rpps_nom_api,
        'prenom_rpps', v_soignant.rpps_prenom_api,
        'nom_document', v_doc_identite.nom_extrait_ia,
        'prenom_document', v_doc_identite.prenom_extrait_ia,
        'profil_vs_rpps', v_coherence_profil_rpps,
        'profil_vs_document', v_coherence_profil_doc,
        'rpps_vs_document', v_coherence_rpps_doc,
        'verifie_le', NOW()
    );

    UPDATE soignants SET
        coherence_identite = CASE
            WHEN NOT v_soignant.rpps_verifie THEN 'NON_VERIFIE'
            WHEN v_doc_identite IS NULL THEN 'NON_VERIFIE'
            WHEN v_all_ok THEN 'COHERENT'
            ELSE 'INCOHERENT'
        END,
        coherence_details = v_details,
        identite_verifiee = v_all_ok,
        modifie_le = NOW()
    WHERE id = p_soignant_id;

    -- Si incohérent → file de revue manuelle
    IF NOT v_all_ok AND v_soignant.rpps_verifie AND v_doc_identite.id IS NOT NULL THEN
        INSERT INTO file_revue_manuelle (type_entite, id_entite, service_en_echec, motif_echec, donnees_originales, statut, priorite)
        VALUES ('SOIGNANT', p_soignant_id, 'COHERENCE_IDENTITE', 
            'Incohérence entre le nom du profil, le RPPS et/ou le document d''identité.',
            v_details, 'EN_ATTENTE', 4)
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN jsonb_build_object('coherent', v_all_ok, 'details', v_details);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_verifier_coherence_publication()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Si quelqu'un tente de mettre peut_publier = TRUE sans être VERIFIE
    IF NEW.peut_publier_missions = TRUE AND NEW.statut_verification != 'VERIFIE' THEN
        -- Service role / admin peut forcer
        IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' 
           OR auth.uid() IS NULL OR est_admin() THEN
            RETURN NEW; -- Admin override autorisé
        END IF;
        RAISE EXCEPTION 'Impossible de publier sans être vérifié';
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_verifier_api_key(p_cle_api text, p_cle_secret text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_key RECORD;
BEGIN
    SELECT * INTO v_key FROM api_keys
    WHERE cle_api = p_cle_api AND actif = TRUE
    AND (expire_le IS NULL OR expire_le > NOW());
    
    IF v_key IS NULL THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'Clé API invalide ou expirée');
    END IF;
    
    -- Vérifier le secret hashé
    IF v_key.cle_secret_hash IS NOT NULL THEN
        -- Nouveau format : hash bcrypt
        IF v_key.cle_secret_hash = crypt(p_cle_secret, v_key.cle_secret_hash) THEN
            UPDATE api_keys SET derniere_utilisation = NOW() WHERE id = v_key.id;
            RETURN jsonb_build_object(
                'valid', TRUE,
                'etablissement_id', v_key.etablissement_id,
                'groupe_sante_id', v_key.groupe_sante_id,
                'permissions', v_key.permissions
            );
        END IF;
    ELSIF v_key.cle_secret IS NOT NULL THEN
        -- Ancien format : clair (migration)
        IF v_key.cle_secret = p_cle_secret THEN
            -- Migrer automatiquement vers le hash
            UPDATE api_keys SET 
                cle_secret_hash = crypt(p_cle_secret, gen_salt('bf', 8)),
                cle_secret = NULL,
                derniere_utilisation = NOW()
            WHERE id = v_key.id;
            RETURN jsonb_build_object(
                'valid', TRUE,
                'etablissement_id', v_key.etablissement_id,
                'groupe_sante_id', v_key.groupe_sante_id,
                'permissions', v_key.permissions
            );
        END IF;
    END IF;
    
    RETURN jsonb_build_object('valid', FALSE, 'error', 'Secret invalide');
END;
$function$


---FIN-FONCTION---

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
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_valider_scan_qr(p_token text, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_precision numeric DEFAULT NULL::numeric, p_terminal_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_qr RECORD;
  v_mission RECORD;
  v_etab RECORD;
  v_presence RECORD;
  v_type_detecte text;
  v_distance_m numeric;
  v_perimetre_ok boolean;
  v_now timestamptz := NOW();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  SELECT * INTO v_qr FROM public.qr_codes_mission WHERE token = p_token AND actif = true;
  IF v_qr IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'QR_INVALIDE',
                                'error', 'QR non valide ou déjà invalidé.');
  END IF;

  IF v_qr.expire_le < v_now THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'QR_EXPIRE',
                                'error', 'Ce QR a expiré. Demandez à l''établissement de régénérer.');
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = v_qr.mission_id;
  -- FIX : IS DISTINCT FROM (sémantique NULL correcte) — refuse aussi les
  -- missions sans assigné, qui passaient le garde `!=` (NULL ≠ TRUE).
  IF v_mission.id IS NULL OR v_mission.soignant_assigne_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'QR_MISSION_AUTRE',
                                'error', 'Ce QR ne correspond pas à votre mission active.');
  END IF;

  -- Cohérence temporelle
  IF v_now < v_mission.debut_le - INTERVAL '1 hour' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'HEURE_TROP_TOT',
                                'error', 'Trop tôt pour pointer. Mission démarre à ' ||
                                  to_char(v_mission.debut_le, 'DD/MM HH24:MI') || '.');
  END IF;
  IF v_now > COALESCE(v_mission.fin_le, v_now + INTERVAL '1 day') + INTERVAL '2 hours' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'HEURE_TROP_TARD',
                                'error', 'Trop tard pour pointer. Mission terminée depuis plus de 2 heures.');
  END IF;

  -- Détecter le type de pointage selon presences existantes
  SELECT * INTO v_presence FROM public.presences
  WHERE mission_id = v_mission.id AND soignant_id = v_uid LIMIT 1;

  IF v_qr.type = 'ARRIVEE' THEN
    v_type_detecte := 'ARRIVEE';
  ELSIF v_qr.type = 'DEPART' THEN
    v_type_detecte := 'DEPART';
  ELSE
    -- UNIVERSEL : pas de presence → ARRIVEE, sinon DEPART
    v_type_detecte := CASE WHEN v_presence IS NULL THEN 'ARRIVEE' ELSE 'DEPART' END;
  END IF;

  -- Vérif double pointage / cohérence départ > arrivée + 30 min
  IF v_type_detecte = 'ARRIVEE' AND v_presence.id IS NOT NULL AND v_presence.pointage_arrivee_le IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_POINTE',
                                'error', 'Vous avez déjà pointé votre arrivée.');
  END IF;
  IF v_type_detecte = 'DEPART' THEN
    IF v_presence IS NULL OR v_presence.pointage_arrivee_le IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_SANS_ARRIVEE',
                                  'error', 'Vous devez d''abord pointer votre arrivée.');
    END IF;
    IF v_presence.pointage_depart_le IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_DEJA_POINTE',
                                  'error', 'Vous avez déjà pointé votre départ.');
    END IF;
    IF v_now < v_presence.pointage_arrivee_le + INTERVAL '30 minutes' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_TROP_RAPIDE',
                                  'error', 'Vous ne pouvez pointer votre départ moins de 30 minutes après l''arrivée.');
    END IF;
  END IF;

  -- Double sécurité GPS : calcul distance si coords fournies (non bloquant)
  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    SELECT adresse_lat, adresse_lng, COALESCE(tolerance_pointage_m, 100) AS tolerance_m
    INTO v_etab FROM public.etablissements WHERE id = v_mission.etablissement_id;
    IF v_etab.adresse_lat IS NOT NULL AND v_etab.adresse_lng IS NOT NULL THEN
      v_distance_m := public.fn_haversine_distance_m(
        p_lat, p_lng, v_etab.adresse_lat::numeric, v_etab.adresse_lng::numeric);
      v_perimetre_ok := v_distance_m <= GREATEST(v_etab.tolerance_m, 1000);
      -- Si distance > 1 km : alerte admin mais pas bloquant (QR = source de vérité)
      IF v_distance_m > 1000 THEN
        INSERT INTO public.journaux_audit (
          acteur_id, type_acteur, action, type_ressource, id_ressource, details
        ) VALUES (
          v_uid, 'SOIGNANT', 'SYSTEM', 'presence', v_mission.id,
          jsonb_build_object(
            'evenement', 'QR_SCAN_GPS_ELOIGNE',
            'niveau', 'WARNING',
            'mission_id', v_mission.id,
            'distance_m', v_distance_m,
            'qr_id', v_qr.id
          )
        );
      END IF;
    END IF;
  END IF;

  -- Insert ou Update presence
  IF v_type_detecte = 'ARRIVEE' THEN
    IF v_presence IS NULL THEN
      INSERT INTO public.presences (
        mission_id, soignant_id, pointage_arrivee_le,
        arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
        arrivee_id_terminal,
        methode_pointage_arrivee, qr_token_arrivee,
        distance_etablissement_m, perimetre_gps_valide
      ) VALUES (
        v_mission.id, v_uid, v_now,
        p_lat, p_lng, p_precision,
        p_terminal_id,
        'QR', p_token,
        v_distance_m, v_perimetre_ok
      );
    ELSE
      UPDATE public.presences SET
        pointage_arrivee_le = v_now,
        arrivee_lat = p_lat, arrivee_lng = p_lng,
        arrivee_precision_gps_m = p_precision,
        arrivee_id_terminal = p_terminal_id,
        methode_pointage_arrivee = 'QR',
        qr_token_arrivee = p_token,
        distance_etablissement_m = COALESCE(v_distance_m, distance_etablissement_m),
        perimetre_gps_valide = COALESCE(v_perimetre_ok, perimetre_gps_valide)
      WHERE id = v_presence.id;
    END IF;
    UPDATE public.missions SET statut = 'EN_COURS', modifie_le = NOW()
    WHERE id = v_mission.id AND statut = 'ASSIGNEE';
  ELSE  -- DEPART
    UPDATE public.presences SET
      pointage_depart_le = v_now,
      depart_lat = p_lat, depart_lng = p_lng,
      depart_precision_gps_m = p_precision,
      depart_id_terminal = p_terminal_id,
      methode_pointage_depart = 'QR',
      qr_token_depart = p_token,
      distance_etablissement_m = COALESCE(distance_etablissement_m, v_distance_m),
      perimetre_gps_valide = COALESCE(perimetre_gps_valide, v_perimetre_ok)
    WHERE id = v_presence.id;
  END IF;

  -- Incrémenter compteur QR
  UPDATE public.qr_codes_mission SET
    nb_scans = nb_scans + 1, dernier_scan_le = v_now
  WHERE id = v_qr.id;

  RETURN jsonb_build_object(
    'success', true,
    'methode_detectee', v_type_detecte,
    'mission_id', v_mission.id,
    'distance_m', v_distance_m,
    'perimetre_valide', v_perimetre_ok,
    'horodatage', v_now
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_verifier_otp_telephone(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_otp RECORD;
  v_etab_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_code IS NULL OR p_code !~ '^[0-9]{6}$' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INVALIDE');
  END IF;

  -- Trouver le dernier OTP actif pour ce user
  SELECT * INTO v_otp FROM public.otps_telephone
  WHERE user_id = v_uid AND utilise = false AND expire_le > NOW()
  ORDER BY cree_le DESC LIMIT 1;

  IF v_otp.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'OTP_INEXISTANT_OU_EXPIRE');
  END IF;

  -- Blocage après 5 tentatives
  IF v_otp.tentatives >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TROP_TENTATIVES',
                                'error', 'Trop de tentatives. Demandez un nouveau code.');
  END IF;

  -- Incrémenter tentatives avant vérif
  UPDATE public.otps_telephone SET tentatives = tentatives + 1 WHERE id = v_otp.id;

  -- Vérifier hash
  IF extensions.crypt(p_code, v_otp.code_hash) != v_otp.code_hash THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INCORRECT',
                                'tentatives_restantes', 5 - (v_otp.tentatives + 1));
  END IF;

  -- Code correct : marquer OTP utilisé + téléphone vérifié sur profil
  UPDATE public.otps_telephone SET utilise = true WHERE id = v_otp.id;

  IF EXISTS (SELECT 1 FROM public.soignants WHERE id = v_uid) THEN
    UPDATE public.soignants
    SET telephone = v_otp.telephone,
        telephone_verifie = true,
        telephone_verifie_le = NOW(),
        telephone_en_attente_verification = NULL
    WHERE id = v_uid;
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NOT NULL THEN
    UPDATE public.etablissements
    SET telephone_contact = v_otp.telephone,
        telephone_verifie = true,
        telephone_verifie_le = NOW(),
        telephone_en_attente_verification = NULL
    WHERE id = v_etab_id;
  END IF;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'SYSTEM', 'otp_telephone', v_otp.id,
    jsonb_build_object('evenement', 'OTP_TELEPHONE_VERIFIE', 'telephone', v_otp.telephone)
  );

  RETURN jsonb_build_object('success', true, 'telephone', v_otp.telephone);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.mon_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT COALESCE(
        (SELECT raw_app_meta_data ->> 'role' FROM auth.users WHERE id = auth.uid()),
        'INCONNU'
    );
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.mon_etablissement_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    NULLIF(raw_app_meta_data ->> 'etablissement_id', '')::uuid,
    CASE
      WHEN raw_app_meta_data ->> 'role' IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT') THEN id
      ELSE NULL
    END
  )
  FROM auth.users
  WHERE id = auth.uid();
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_verifier_rate_limit(p_cle text, p_action text, p_max_tentatives integer DEFAULT 10, p_fenetre_secondes integer DEFAULT 60)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_record RECORD;
    v_fenetre_debut TIMESTAMPTZ;
BEGIN
    v_fenetre_debut := NOW() - (p_fenetre_secondes || ' seconds')::INTERVAL;
    
    -- Nettoyer les entrées expirées
    DELETE FROM rate_limits WHERE premiere_tentative < v_fenetre_debut AND action = p_action;
    
    -- Chercher l'entrée existante
    SELECT * INTO v_record FROM rate_limits 
    WHERE cle = p_cle AND action = p_action AND premiere_tentative >= v_fenetre_debut
    LIMIT 1;
    
    IF v_record IS NULL THEN
        -- Première tentative dans la fenêtre
        INSERT INTO rate_limits (cle, action, tentatives, premiere_tentative, derniere_tentative)
        VALUES (p_cle, p_action, 1, NOW(), NOW());
        RETURN TRUE;
    END IF;
    
    IF v_record.tentatives >= p_max_tentatives THEN
        -- Limite atteinte
        UPDATE rate_limits SET derniere_tentative = NOW() WHERE id = v_record.id;
        RETURN FALSE;
    END IF;
    
    -- Incrémenter
    UPDATE rate_limits SET tentatives = tentatives + 1, derniere_tentative = NOW() WHERE id = v_record.id;
    RETURN TRUE;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.next_avoir_commission_number(p_etablissement_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_mois TEXT; v_last_seq INTEGER; v_lock_key BIGINT;
BEGIN
  v_lock_key := ('x' || left(md5('AVC:' || p_etablissement_id::text), 15))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);
  v_mois := TO_CHAR(now(), 'YYYY-MM');
  SELECT MAX(NULLIF(SPLIT_PART(numero_facture, '-', 4), '')::INTEGER)
    INTO v_last_seq FROM public.factures
   WHERE numero_facture LIKE 'AVC-' || v_mois || '-%';
  RETURN 'AVC-' || v_mois || '-' || LPAD((COALESCE(v_last_seq, 0) + 1)::TEXT, 4, '0');
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_verifier_pre_facturation(p_mission_id uuid, p_periode_debut date DEFAULT NULL::date, p_periode_fin date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_mission RECORD;
  v_nb_effectif_ouvert integer;
  v_nb_effectif_ferme integer;
  v_nb_previsionnel integer;
  v_duree_previsionnelle numeric;
  v_duree_effective numeric;
  v_ecart_heures numeric;
  v_ecart_pourcent numeric;
  v_source text;
  v_periode_active boolean;
BEGIN
  SELECT id, duree_heures, duree_heures_effective, statut, debut_le, fin_le
  INTO v_mission
  FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mission % introuvable.', p_mission_id
      USING ERRCODE = 'no_data_found';
  END IF;

  v_periode_active := (p_periode_debut IS NOT NULL AND p_periode_fin IS NOT NULL);

  SELECT
    COUNT(*) FILTER (WHERE type_creneau='EFFECTIF' AND fin IS NULL),
    COUNT(*) FILTER (WHERE type_creneau='EFFECTIF' AND fin IS NOT NULL),
    COUNT(*) FILTER (WHERE type_creneau='PREVISIONNEL')
  INTO v_nb_effectif_ouvert, v_nb_effectif_ferme, v_nb_previsionnel
  FROM mission_creneaux
  WHERE mission_id = p_mission_id
    AND (
      NOT v_periode_active
      OR (debut::date <= p_periode_fin AND COALESCE(fin::date, debut::date) >= p_periode_debut)
    );

  IF v_nb_effectif_ouvert > 0 THEN
    RAISE EXCEPTION 'Facturation bloquée : % créneau(x) effectif(s) ouvert(s) sur la période. Utilisez fn_declarer_fin_retroactive.',
      v_nb_effectif_ouvert USING ERRCODE = 'check_violation';
  END IF;

  SELECT
    COALESCE(ROUND(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
             FILTER (WHERE type_creneau='PREVISIONNEL' AND NOT est_pause)::numeric, 2), 0),
    COALESCE(ROUND(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
             FILTER (WHERE type_creneau='EFFECTIF' AND fin IS NOT NULL AND NOT est_pause)::numeric, 2), 0)
  INTO v_duree_previsionnelle, v_duree_effective
  FROM mission_creneaux
  WHERE mission_id = p_mission_id
    AND (
      NOT v_periode_active
      OR (debut::date <= p_periode_fin AND COALESCE(fin::date, debut::date) >= p_periode_debut)
    );

  v_ecart_heures := ROUND(ABS(v_duree_previsionnelle - v_duree_effective), 2);
  IF v_duree_previsionnelle > 0 THEN
    v_ecart_pourcent := ROUND(v_ecart_heures / v_duree_previsionnelle * 100, 2);
  ELSE
    v_ecart_pourcent := 0;
  END IF;

  IF v_duree_previsionnelle > 0 AND v_duree_effective > v_duree_previsionnelle * 1.10 THEN
    RAISE EXCEPTION 'Facturation bloquée : effectif %h dépasse prévisionnel %h de plus de 10 pct (écart % pct). Validation étab/admin requise.',
      v_duree_effective, v_duree_previsionnelle, v_ecart_pourcent
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_duree_effective = 0 AND v_duree_previsionnelle = 0 THEN
    RAISE EXCEPTION 'Facturation bloquée : aucun créneau (effectif ni prévisionnel) sur la période. Mission probablement absente — passer en statut ABSENCE ou décaler la période.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_source := CASE
    WHEN v_duree_effective > 0 AND v_duree_effective >= v_duree_previsionnelle THEN 'EFFECTIF'
    WHEN v_duree_effective = 0 AND v_duree_previsionnelle > 0 THEN 'PREVISIONNEL_PLANCHER'
    ELSE 'PREVISIONNEL'
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'mode_periode', v_periode_active,
    'periode_debut', p_periode_debut,
    'periode_fin', p_periode_fin,
    'source_facturation', v_source,
    'duree_previsionnelle', v_duree_previsionnelle,
    'duree_effective', v_duree_effective,
    'duree_facturee', GREATEST(v_duree_previsionnelle, v_duree_effective),
    'ecart_heures', v_ecart_heures,
    'ecart_pourcent', v_ecart_pourcent,
    'nb_creneaux_effectif_fermes', v_nb_effectif_ferme,
    'nb_creneaux_previsionnels', v_nb_previsionnel
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_verifier_skip_serie_onboarding(p_envoi_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_envoi RECORD;
  v_etab RECORD;
  v_soignant RECORD;
  v_count integer;
  v_j1_skipped boolean;
BEGIN
  SELECT * INTO v_envoi FROM serie_email_envois WHERE id = p_envoi_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('skip', true, 'raison', 'ENVOI_INTROUVABLE');
  END IF;

  -- ════════ SOIGNANT ════════
  IF v_envoi.serie = 'SOIGNANT_ONBOARDING' THEN
    SELECT prenom, nom, profession,
           rpps_verifie, mandat_facturation_signe,
           tous_documents_valides, type_exercice
    INTO v_soignant FROM soignants WHERE id = v_envoi.utilisateur_id;

    IF v_envoi.etape = 'J0' THEN RETURN jsonb_build_object('skip', false); END IF;

    IF v_envoi.etape = 'J1' THEN
      -- Skip si profil "complet" (RPPS vérifié + documents valides + mandat
      -- signé pour libéraux)
      IF v_soignant.tous_documents_valides = true
         AND COALESCE(v_soignant.rpps_verifie, true) = true
         AND (v_soignant.type_exercice = 'SALARIE'
              OR v_soignant.mandat_facturation_signe = true) THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'PROFIL_DEJA_COMPLET');
      END IF;
      RETURN jsonb_build_object('skip', false);
    END IF;

    IF v_envoi.etape = 'J3' THEN
      -- Skip si déjà candidaté
      SELECT count(*) INTO v_count FROM candidatures WHERE soignant_id = v_envoi.utilisateur_id;
      IF v_count > 0 THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'CANDIDATURE_DEJA_EFFECTUEE');
      END IF;
      -- Skip si J1 a été SKIPPED avec raison PROFIL_DEJA_COMPLET → c'est OK
      -- mais surtout skip si J1 SKIPPED pour profil incomplet (= on a pas
      -- réussi à le faire compléter, on insiste pas davantage)
      SELECT EXISTS(
        SELECT 1 FROM serie_email_envois
        WHERE utilisateur_id = v_envoi.utilisateur_id
          AND serie = 'SOIGNANT_ONBOARDING' AND etape = 'J1'
          AND statut = 'SKIPPED'
          AND skip_raison = 'NOTIFICATION_DESACTIVEE'
      ) INTO v_j1_skipped;
      IF v_j1_skipped THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'NOTIFICATIONS_DESACTIVEES_J1');
      END IF;
      RETURN jsonb_build_object('skip', false);
    END IF;

    IF v_envoi.etape = 'J7' THEN
      -- Skip si mission déjà assignée/en cours/terminée
      SELECT count(*) INTO v_count FROM missions
      WHERE soignant_assigne_id = v_envoi.utilisateur_id
        AND statut IN ('ASSIGNEE','EN_COURS','TERMINEE');
      IF v_count > 0 THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'MISSION_DEJA_ASSIGNEE');
      END IF;
      RETURN jsonb_build_object('skip', false);
    END IF;
  END IF;

  -- ════════ ÉTABLISSEMENT ════════
  IF v_envoi.serie = 'ETAB_ONBOARDING' THEN
    SELECT nom, type, contrat_service_signe, rib_s3_key
    INTO v_etab FROM etablissements WHERE id = v_envoi.utilisateur_id;

    IF v_envoi.etape = 'J0' THEN RETURN jsonb_build_object('skip', false); END IF;

    IF v_envoi.etape = 'J1' THEN
      -- Skip si onboarding complet (contrat signé ET RIB uploadé non-legacy)
      IF v_etab.contrat_service_signe = true
         AND v_etab.rib_s3_key IS NOT NULL
         AND v_etab.rib_s3_key <> 'legacy/auto-backfill' THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'ONBOARDING_DEJA_COMPLET');
      END IF;
      RETURN jsonb_build_object('skip', false);
    END IF;

    IF v_envoi.etape = 'J3' THEN
      SELECT count(*) INTO v_count FROM missions WHERE etablissement_id = v_envoi.utilisateur_id;
      IF v_count > 0 THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'MISSION_DEJA_PUBLIEE');
      END IF;
      RETURN jsonb_build_object('skip', false);
    END IF;

    IF v_envoi.etape = 'J7' THEN
      -- Skip si l'étab a reçu au moins 1 candidature
      SELECT count(*) INTO v_count FROM candidatures c
      JOIN missions m ON m.id = c.mission_id
      WHERE m.etablissement_id = v_envoi.utilisateur_id;
      IF v_count > 0 THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'CANDIDATURE_DEJA_RECUE');
      END IF;
      RETURN jsonb_build_object('skip', false);
    END IF;
  END IF;

  RETURN jsonb_build_object('skip', false);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_vitesse_entre_pointages(p_lat1 numeric, p_lng1 numeric, p_ts1 timestamp with time zone, p_lat2 numeric, p_lng2 numeric, p_ts2 timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE
  v_distance_m numeric;
  v_duree_h numeric;
  v_vitesse_kmh numeric;
BEGIN
  IF p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL
     OR p_ts1 IS NULL OR p_ts2 IS NULL THEN
    RETURN jsonb_build_object('calculable', false);
  END IF;

  v_distance_m := public.fn_haversine_distance_m(p_lat1, p_lng1, p_lat2, p_lng2);
  v_duree_h := EXTRACT(EPOCH FROM (p_ts2 - p_ts1)) / 3600.0;

  IF v_duree_h <= 0 THEN
    RETURN jsonb_build_object('calculable', false, 'raison', 'duree_invalide');
  END IF;

  v_vitesse_kmh := (v_distance_m / 1000.0) / v_duree_h;

  RETURN jsonb_build_object(
    'calculable', true,
    'distance_m', v_distance_m,
    'duree_h', v_duree_h,
    'vitesse_kmh', v_vitesse_kmh,
    'teleportation', v_vitesse_kmh > 200
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_verifier_pointages_incoherents()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_presence record;
  v_mission record;
  v_incidents jsonb;
  v_incident jsonb;
  v_severite_max text;
  v_count_verifiees integer := 0;
  v_count_alertes integer := 0;
BEGIN
  -- Vérifie les presences :
  --  - pas encore vérifiées (coherence_verifiee_le IS NULL)
  --  - dont la mission est terminée depuis au moins 1h (ou pointage arrivée >2h sans départ)
  FOR v_presence IN
    SELECT p.*
    FROM public.presences p
    JOIN public.missions m ON m.id = p.mission_id
    WHERE p.coherence_verifiee_le IS NULL
      AND (
        (p.pointage_depart_le IS NOT NULL AND m.fin_le < now() - INTERVAL '1 hour')
        OR (p.pointage_arrivee_le IS NOT NULL AND p.pointage_depart_le IS NULL AND m.fin_le < now() - INTERVAL '6 hours')
      )
    LIMIT 500
  LOOP
    SELECT * INTO v_mission FROM public.missions WHERE id = v_presence.mission_id;
    CONTINUE WHEN v_mission IS NULL;

    v_incidents := public.fn_evaluer_coherence_pointage(
      v_presence.pointage_arrivee_le,
      v_presence.pointage_depart_le,
      v_mission.debut_le,
      v_mission.fin_le,
      v_presence.duree_nette_min
    );

    -- Cas spécial : arrivée sans départ après fin mission + 6h
    IF v_presence.pointage_arrivee_le IS NOT NULL
       AND v_presence.pointage_depart_le IS NULL
       AND v_mission.fin_le < now() - INTERVAL '6 hours' THEN
      v_incidents := v_incidents || jsonb_build_object(
        'code', 'DEPART_MANQUANT',
        'severite', 'CRITICAL',
        'message', 'Arrivée pointée mais aucun départ enregistré'
      );
    END IF;

    -- Calcule sévérité max
    v_severite_max := NULL;
    FOR v_incident IN SELECT * FROM jsonb_array_elements(v_incidents)
    LOOP
      IF v_incident->>'severite' = 'CRITICAL' THEN
        v_severite_max := 'CRITICAL';
        EXIT;
      ELSIF v_incident->>'severite' = 'WARNING' AND v_severite_max IS NULL THEN
        v_severite_max := 'WARNING';
      END IF;
    END LOOP;

    -- Marque la presence comme vérifiée
    UPDATE public.presences
    SET coherence_verifiee_le = now(),
        coherence_incidents = v_incidents
    WHERE id = v_presence.id;
    v_count_verifiees := v_count_verifiees + 1;

    -- Crée une alerte_systeme si incident détecté
    IF jsonb_array_length(v_incidents) > 0 THEN
      INSERT INTO public.alertes_systeme (
        type_alerte, severite, source, message, details
      ) VALUES (
        'POINTAGE_INCOHERENT',
        COALESCE(v_severite_max, 'WARNING'),
        'cron:jolene_verifier_pointages_incoherents',
        format('Incident pointage mission %s (soignant %s)', v_mission.id, v_presence.soignant_id),
        jsonb_build_object(
          'mission_id', v_mission.id,
          'presence_id', v_presence.id,
          'soignant_id', v_presence.soignant_id,
          'etablissement_id', v_mission.etablissement_id,
          'mission_debut', v_mission.debut_le,
          'mission_fin', v_mission.fin_le,
          'pointage_arrivee', v_presence.pointage_arrivee_le,
          'pointage_depart', v_presence.pointage_depart_le,
          'duree_nette_min', v_presence.duree_nette_min,
          'incidents', v_incidents
        )
      );
      v_count_alertes := v_count_alertes + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'verifiees', v_count_verifiees,
    'alertes', v_count_alertes,
    'horodatage', now()
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.next_invoice_number(p_soignant_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ DECLARE v_siret TEXT; v_year TEXT; v_last_seq INTEGER; v_next_seq INTEGER; v_lock_key BIGINT; v_result TEXT; BEGIN v_lock_key := ('x' || left(md5(p_soignant_id::text), 15))::bit(64)::bigint; PERFORM pg_advisory_xact_lock(v_lock_key); SELECT COALESCE(LEFT(siret_liberal, 8), LEFT(p_soignant_id::text, 8)) INTO v_siret FROM soignants WHERE id = p_soignant_id; IF v_siret IS NULL THEN v_siret := LEFT(p_soignant_id::text, 8); END IF; v_year := TO_CHAR(CURRENT_DATE, 'YYYY'); SELECT MAX(NULLIF(SPLIT_PART(numero_facture, '-', 4), '')::INTEGER) INTO v_last_seq FROM factures_honoraires WHERE soignant_id = p_soignant_id AND numero_facture LIKE 'JOL-%'; v_next_seq := COALESCE(v_last_seq, 0) + 1; v_result := 'JOL-' || v_siret || '-' || v_year || '-' || LPAD(v_next_seq::TEXT, 5, '0'); RETURN v_result; END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.next_avoir_number(p_soignant_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_siret TEXT;
  v_year TEXT;
  v_last_seq INTEGER;
  v_next_seq INTEGER;
  v_lock_key BIGINT;
  v_result TEXT;
BEGIN
  v_lock_key := ('x' || left(md5('AV:' || p_soignant_id::text), 15))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  SELECT COALESCE(LEFT(siret_liberal, 8), LEFT(p_soignant_id::text, 8))
    INTO v_siret
    FROM public.soignants WHERE id = p_soignant_id;
  IF v_siret IS NULL THEN
    v_siret := LEFT(p_soignant_id::text, 8);
  END IF;

  v_year := TO_CHAR(CURRENT_DATE, 'YYYY');

  SELECT MAX(
    NULLIF(SPLIT_PART(numero_facture, '-', 4), '')::INTEGER
  ) INTO v_last_seq
    FROM public.factures_honoraires
   WHERE soignant_id = p_soignant_id
     AND type_document = 'AVOIR'
     AND numero_facture LIKE 'AV-%';

  v_next_seq := COALESCE(v_last_seq, 0) + 1;
  v_result := 'AV-' || v_siret || '-' || v_year || '-' || LPAD(v_next_seq::TEXT, 5, '0');
  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.trg_fn_maj_tresorerie_bloquee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.fn_recalculer_tresorerie_bloquee(NEW.litige_id);
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.litige_id IS DISTINCT FROM OLD.litige_id THEN
      PERFORM public.fn_recalculer_tresorerie_bloquee(OLD.litige_id);
    END IF;
    PERFORM public.fn_recalculer_tresorerie_bloquee(NEW.litige_id);
  END IF;
  RETURN NULL;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.next_facture_complementaire_number(p_etablissement_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_mois TEXT; v_last_seq INTEGER; v_lock_key BIGINT;
BEGIN
  v_lock_key := ('x' || left(md5('FC:' || p_etablissement_id::text), 15))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);
  v_mois := TO_CHAR(now(), 'YYYY-MM');
  SELECT MAX(NULLIF(SPLIT_PART(numero_facture, '-', 4), '')::INTEGER)
    INTO v_last_seq FROM public.factures
   WHERE numero_facture LIKE 'FC-' || v_mois || '-%';
  RETURN 'FC-' || v_mois || '-' || LPAD((COALESCE(v_last_seq, 0) + 1)::TEXT, 4, '0');
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.peut_exercer_liberal(p_profession text, p_type_etablissement text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Matrice validée juridiquement par Gabrielle :
  --   MEDECIN libéral : cabinets, cliniques privées, EHPAD, SSIAD, HAD,
  --     centre de santé, MAS, FAM (CNOM art. R.4127-65).
  --   DENTISTE libéral : cabinet dentaire uniquement (CNOC art. R.4127-274).
  --   IDE libéral (IDEL) : cabinet IDEL UNIQUEMENT (R.4312-12 CSP).
  --     Tout autre = piège Mediflash requalifiable en travail dissimulé.
  --   SAGE_FEMME libérale : cabinet sage-femme, clinique privée (maternités),
  --     HAD, centre de santé.
  --   KINE libéral : cabinet kiné, clinique privée (rééducation), SSIAD,
  --     HAD, MAS, FAM.
  --   ORTHOPHONISTE libéral : cabinet ortho uniquement.
  --   ERGOTHERAPEUTE libéral : cabinet ergo ou HAD (intervention domicile).
  --   PSYCHOMOTRICIEN libéral : cabinet psychomot ou HAD.
  --   Toutes les autres professions : pas de libéral autorisé.
  RETURN CASE p_profession
    WHEN 'MEDECIN' THEN p_type_etablissement IN ('CABINET_MEDICAL', 'CLINIQUE_PRIVEE', 'EHPAD', 'SSIAD', 'HAD', 'CENTRE_SANTE', 'MAS', 'FAM')
    WHEN 'DENTISTE' THEN p_type_etablissement = 'CABINET_DENTAIRE'
    WHEN 'IDE' THEN p_type_etablissement = 'CABINET_IDEL'
    WHEN 'SAGE_FEMME' THEN p_type_etablissement IN ('CABINET_SAGE_FEMME', 'CLINIQUE_PRIVEE', 'HAD', 'CENTRE_SANTE')
    WHEN 'KINE' THEN p_type_etablissement IN ('CABINET_KINE', 'CLINIQUE_PRIVEE', 'SSIAD', 'HAD', 'MAS', 'FAM')
    WHEN 'ORTHOPHONISTE' THEN p_type_etablissement = 'CABINET_ORTHO'
    WHEN 'ERGOTHERAPEUTE' THEN p_type_etablissement IN ('CABINET_ERGO', 'HAD')
    WHEN 'PSYCHOMOTRICIEN' THEN p_type_etablissement IN ('CABINET_PSYCHOMOT', 'HAD')
    ELSE FALSE
  END;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.peut_exercer(p_profession text, p_type_exercice text, p_type_etablissement text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_type_exercice IN ('SALARIE', 'CDD', 'CDD', 'VACATION') THEN
    RETURN TRUE;
  END IF;

  IF p_type_exercice IN ('LIBERAL', 'MIXTE') THEN
    RETURN public.peut_exercer_liberal(p_profession, p_type_etablissement);
  END IF;

  RETURN TRUE;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.tg_candidature_acceptee_creer_conversation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid;
BEGIN
  SELECT etablissement_id INTO v_etab_id
  FROM missions
  WHERE id = NEW.mission_id;

  IF v_etab_id IS NULL THEN
    RETURN NEW;
  END IF;

  BEGIN
    PERFORM public.fn_creer_conversation_si_absente(
      NEW.mission_id,
      NEW.soignant_id,
      v_etab_id
    );
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.journaux_audit(acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'candidatures', NEW.id,
            jsonb_build_object(
              'evenement', 'MESSAGERIE_TRIGGER_ECHEC',
              'sql_state', SQLSTATE,
              'sql_errm', SQLERRM,
              'mission_id', NEW.mission_id,
              'soignant_id', NEW.soignant_id
            ));
  END;

  RETURN NEW;
END;
$function$
