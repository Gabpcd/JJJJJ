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
