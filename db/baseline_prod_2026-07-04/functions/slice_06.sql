CREATE OR REPLACE FUNCTION public.fn_is_valid_uuid(p_text text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    PERFORM p_text::UUID;
    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    RETURN FALSE;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_list_admin_user_ids()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT id
    FROM auth.users
   WHERE raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME';
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_lister_factures_a_regenerer(p_limit integer DEFAULT 50)
 RETURNS TABLE(id uuid, numero_facture text, type_document type_document_facture, soignant_id uuid, cree_le timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT f.id, f.numero_facture, f.type_document, f.soignant_id, f.cree_le
    FROM public.factures_honoraires f
   WHERE f.pdf_a_regenerer = TRUE
     AND f.statut IN ('BROUILLON', 'EMISE')
     AND f.modifie_le < NOW() - INTERVAL '1 hour'
   ORDER BY f.cree_le ASC
   LIMIT p_limit;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_lire_secret_cron()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'extensions'
AS $function$
DECLARE v_secret text;
BEGIN
  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key';
  RETURN v_secret;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_inscrire_liste_attente_prevoyance(p_email text, p_niveau text DEFAULT 'INDIFFERENT'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_inviter_membre_etab(p_email text, p_role text, p_etablissement_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_invitation_id uuid;
  v_token text;
  v_perms jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_role NOT IN ('ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY', 'LECTURE_SEULE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ROLE_INVALIDE');
  END IF;

  IF p_email IS NULL OR length(trim(p_email)) = 0 OR p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'EMAIL_INVALIDE');
  END IF;

  v_etab_id := COALESCE(p_etablissement_id, public.mon_etablissement_id());

  -- Vérif autorisation : seul PROPRIETAIRE peut inviter
  SELECT public.fn_mes_permissions_etab(v_etab_id) INTO v_perms;
  IF NOT COALESCE((v_perms->'permissions'->>'gerer_equipe')::boolean, false) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Seul un PROPRIETAIRE peut inviter des membres');
  END IF;

  -- Pas déjà membre actif
  IF EXISTS (
    SELECT 1 FROM public.membres_etablissement m
    JOIN auth.users u ON u.id = m.user_id
    WHERE m.etablissement_id = v_etab_id
      AND lower(u.email) = lower(trim(p_email))
      AND m.actif = true
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_MEMBRE');
  END IF;

  -- Pas déjà invité en attente
  IF EXISTS (
    SELECT 1 FROM public.invitations_etablissement
    WHERE etablissement_id = v_etab_id
      AND lower(email_invite) = lower(trim(p_email))
      AND statut = 'EN_ATTENTE'
      AND expire_le > now()
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'INVITATION_DEJA_EN_ATTENTE');
  END IF;

  INSERT INTO public.invitations_etablissement (
    etablissement_id, email_invite, role_propose, invite_par
  ) VALUES (
    v_etab_id, lower(trim(p_email)), p_role, v_uid
  )
  RETURNING id, token INTO v_invitation_id, v_token;

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'MODIFICATION_PROFIL', 'invitation_etab', v_invitation_id,
    jsonb_build_object(
      'evenement', 'INVITATION_MEMBRE_CREEE',
      'email', lower(trim(p_email)),
      'role', p_role,
      'etablissement_id', v_etab_id
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'invitation_id', v_invitation_id,
    'token', v_token,
    'expire_le', (now() + INTERVAL '7 days')
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_lister_membres_etab(p_etablissement_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_perms jsonb;
  v_membres jsonb;
  v_invitations jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  v_etab_id := COALESCE(p_etablissement_id, public.mon_etablissement_id());
  SELECT public.fn_mes_permissions_etab(v_etab_id) INTO v_perms;
  IF (v_perms->>'role') IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'user_id', m.user_id,
    'email', u.email,
    'role', m.role,
    'accepte_le', m.accepte_le,
    'actif', m.actif
  ) ORDER BY m.accepte_le DESC), '[]'::jsonb)
  INTO v_membres
  FROM public.membres_etablissement m
  JOIN auth.users u ON u.id = m.user_id
  WHERE m.etablissement_id = v_etab_id
    AND m.actif = true;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'email_invite', email_invite,
    'role_propose', role_propose,
    'statut', statut,
    'invite_le', invite_le,
    'expire_le', expire_le
  ) ORDER BY invite_le DESC), '[]'::jsonb)
  INTO v_invitations
  FROM public.invitations_etablissement
  WHERE etablissement_id = v_etab_id
    AND statut = 'EN_ATTENTE'
    AND expire_le > now();

  RETURN jsonb_build_object(
    'success', true,
    'role_courant', v_perms->>'role',
    'membres', v_membres,
    'invitations', v_invitations
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_initialiser_preferences_matching(p_pref_nuit numeric, p_pref_jour numeric, p_pref_weekend numeric, p_pref_semaine numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;
  IF p_pref_nuit NOT BETWEEN 0 AND 1 OR p_pref_jour NOT BETWEEN 0 AND 1
     OR p_pref_weekend NOT BETWEEN 0 AND 1 OR p_pref_semaine NOT BETWEEN 0 AND 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Préférences hors bornes [0,1]');
  END IF;

  INSERT INTO public.matching_preferences_soignant
    (soignant_id, pref_nuit, pref_jour, pref_weekend, pref_semaine, nb_signaux, maj_le)
  VALUES (v_uid, p_pref_nuit, p_pref_jour, p_pref_weekend, p_pref_semaine, 0, now())
  ON CONFLICT (soignant_id) DO UPDATE SET
    pref_nuit = EXCLUDED.pref_nuit,
    pref_jour = EXCLUDED.pref_jour,
    pref_weekend = EXCLUDED.pref_weekend,
    pref_semaine = EXCLUDED.pref_semaine,
    maj_le = now()
  WHERE matching_preferences_soignant.nb_signaux = 0;

  RETURN jsonb_build_object('success', true);
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_litige_pour_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN COALESCE((
        SELECT row_to_json(x)::JSONB FROM (
            SELECT l.id::TEXT AS litige_id, l.statut, l.initie_par, l.motif, l.cree_le,
                l.accord_soignant, l.accord_etablissement, l.resolution
            FROM litiges l
            WHERE l.mission_id = p_mission_id
            AND (l.soignant_id = auth.uid() OR l.etablissement_id = mon_etablissement_id() OR est_admin())
            ORDER BY l.cree_le DESC LIMIT 1
        ) x
    ), '{"exists": false}'::JSONB);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_litige_push_notification(p_destinataire_id uuid, p_type_destinataire text, p_type_notif text, p_titre text, p_corps text, p_litige_id uuid, p_email_data jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_telephone TEXT;
  v_sms_eligible BOOLEAN;
  v_sms_contenu TEXT;
  v_lien TEXT;
BEGIN
  v_lien := CASE p_type_destinataire
    WHEN 'SOIGNANT'       THEN '/soignant/litiges'
    WHEN 'ETABLISSEMENT'  THEN '/etablissement/litiges'
    WHEN 'ADMIN'          THEN '/admin/moderation'
    ELSE NULL
  END;

  INSERT INTO public.notifications (
    destinataire_id, type_destinataire, type, titre, corps,
    id_ressource, type_ressource, lien
  ) VALUES (
    p_destinataire_id, p_type_destinataire, p_type_notif, p_titre, p_corps,
    p_litige_id, 'litige', v_lien
  );

  INSERT INTO public.email_queue (type, destinataire_id, data)
  VALUES (
    p_type_notif,
    p_destinataire_id,
    p_email_data || jsonb_build_object('litige_id', p_litige_id, 'url_litige', v_lien)
  );

  v_sms_eligible := p_type_notif IN (
    'LITIGE_OUVERTURE',
    'REMBOURSEMENT_CONFIRME',
    'LITIGE_RAPPEL_J1',
    'LITIGE_RAPPEL_J3',
    'LITIGE_RAPPEL_J5'
  );

  IF NOT v_sms_eligible THEN
    RETURN;
  END IF;

  IF p_type_destinataire = 'SOIGNANT' THEN
    SELECT s.telephone INTO v_telephone
      FROM public.soignants s WHERE s.id = p_destinataire_id;
  ELSIF p_type_destinataire = 'ETABLISSEMENT' THEN
    SELECT e.telephone_contact INTO v_telephone
      FROM public.etablissements e
     WHERE e.id = p_destinataire_id;
  END IF;

  IF v_telephone IS NULL OR length(trim(v_telephone)) < 10 THEN
    RETURN;
  END IF;

  v_sms_contenu := CASE p_type_notif
    WHEN 'LITIGE_OUVERTURE'       THEN 'un litige ' || COALESCE(p_email_data->>'type_litige', '') || ' a été ouvert sur votre mission. Répondez sous 72h.'
    WHEN 'REMBOURSEMENT_CONFIRME' THEN 'remboursement de ' || COALESCE(p_email_data->>'montant', '?') || '€ effectué (avoir ' || COALESCE(p_email_data->>'numero_avoir', '') || '). Délai bancaire 2-5j.'
    WHEN 'LITIGE_RAPPEL_J1'       THEN 'litige en attente depuis 1j. Répondez sous 24h pour éviter l''escalade.'
    WHEN 'LITIGE_RAPPEL_J3'       THEN 'litige en attente depuis 3j. Réponse urgente requise.'
    WHEN 'LITIGE_RAPPEL_J5'       THEN 'litige en attente depuis 5j ouvrés. Escalade imminente.'
    ELSE p_corps
  END;

  INSERT INTO public.email_queue (type, destinataire_id, data)
  VALUES (
    'SMS_' || p_type_notif,
    p_destinataire_id,
    jsonb_build_object(
      'telephone', v_telephone,
      'contenu', v_sms_contenu,
      'litige_id', p_litige_id
    )
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_litige_preuves_agregees(p_litige_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_litige            public.litiges%ROWTYPE;
  v_mission           public.missions%ROWTYPE;
  v_soignant          RECORD;
  v_etab              RECORD;
  v_presence          RECORD;
  v_result            JSONB;
  v_pointages         JSONB;
  v_factures          JSONB;
  v_messages          JSONB;
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'fn_litige_preuves_agregees: accès admin requis'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Litige % introuvable', p_litige_id
      USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = v_litige.mission_id;

  SELECT s.id, s.nom, s.prenom, s.numero_rpps, s.note_moyenne,
         s.telephone, s.est_salarie_etablissement, s.profession
    INTO v_soignant
    FROM public.soignants s
   WHERE s.id = v_litige.soignant_id;

  SELECT e.id, e.nom, e.siret,
         e.adresse_rue, e.adresse_code_postal, e.adresse_ville,
         e.telephone_contact, e.email_contact, e.est_secteur_public
    INTO v_etab
    FROM public.etablissements e
   WHERE e.id = v_litige.etablissement_id;

  SELECT p.* INTO v_presence
    FROM public.presences p
   WHERE p.id = v_litige.presence_id;

  IF v_presence.id IS NOT NULL AND v_presence.id IS NOT NULL THEN
    v_pointages := jsonb_build_array(
      jsonb_build_object(
        'id', v_presence.id,
        'type', 'ARRIVEE',
        'horodatage', v_presence.pointage_arrivee_le,
        'latitude', v_presence.arrivee_lat,
        'longitude', v_presence.arrivee_lng,
        'precision_gps_m', v_presence.arrivee_precision_gps_m,
        'methode', v_presence.methode_pointage_arrivee,
        'is_geo_ok', v_presence.perimetre_gps_valide
      ),
      jsonb_build_object(
        'id', v_presence.id,
        'type', 'DEPART',
        'horodatage', v_presence.pointage_depart_le,
        'latitude', v_presence.depart_lat,
        'longitude', v_presence.depart_lng,
        'precision_gps_m', v_presence.depart_precision_gps_m,
        'methode', v_presence.methode_pointage_depart,
        'is_geo_ok', v_presence.perimetre_gps_valide
      )
    );
  ELSE
    v_pointages := '[]'::jsonb;
  END IF;

  SELECT COALESCE(jsonb_agg(f_row ORDER BY f_row->>'date_emission' DESC), '[]'::jsonb)
    INTO v_factures
    FROM (
      SELECT jsonb_build_object(
        'id', f.id,
        'numero_facture', f.numero_facture,
        'type_document', f.type_document,
        'statut', f.statut,
        'statut_litige', f.statut_litige,
        'montant_ht', f.montant_ht,
        'montant_ttc', f.montant_ttc,
        'date_emission', f.date_emission,
        'facture_precedente_id', f.facture_precedente_id
      ) AS f_row
        FROM public.factures_honoraires f
       WHERE f.litige_id = p_litige_id
          OR f.id = v_litige.facture_id
    ) sub;

  SELECT COALESCE(jsonb_agg(m_row ORDER BY (m_row->>'cree_le')::timestamptz ASC), '[]'::jsonb)
    INTO v_messages
    FROM (
      SELECT jsonb_build_object(
        'id', m.id,
        'auteur_type', m.type_auteur,
        'auteur_id', m.auteur_id,
        'auteur_nom', CASE m.type_auteur
          WHEN 'SOIGNANT' THEN (
            SELECT trim(s.prenom || ' ' || s.nom)
              FROM public.soignants s WHERE s.id = m.auteur_id
          )
          WHEN 'ETABLISSEMENT' THEN (
            SELECT e.nom FROM public.etablissements e
             WHERE e.id = v_litige.etablissement_id
          )
          WHEN 'ADMIN' THEN 'Admin Jolene'
          ELSE NULL
        END,
        'contenu', m.contenu,
        'cree_le', m.cree_le
      ) AS m_row
        FROM public.messages_litige m
       WHERE m.litige_id = p_litige_id
    ) sub;

  v_result := jsonb_build_object(
    'litige', jsonb_build_object(
      'id', v_litige.id,
      'type_litige', v_litige.type_litige,
      'categorie_litige', v_litige.categorie_litige,
      'statut', v_litige.statut,
      'initie_par', v_litige.initie_par,
      'cree_le', v_litige.cree_le,
      'motif', v_litige.motif,
      'resolution', v_litige.resolution,
      'resolu_le', v_litige.resolu_le,
      'resolu_par', v_litige.resolu_par,
      'escalade_auto_le', v_litige.escalade_auto_le,
      'escalade_auto_motif', v_litige.escalade_auto_motif,
      'est_informatif', v_litige.est_informatif,
      'type_legacy', v_litige.type_legacy,
      'montant_tresorerie_bloquee', v_litige.montant_tresorerie_bloquee,
      'facture_id', v_litige.facture_id,
      'mission_id', v_litige.mission_id
    ),
    'mission', CASE WHEN v_mission.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_mission.id,
      'intitule', v_mission.intitule,
      'service', v_mission.service,
      'debut_le', v_mission.debut_le,
      'fin_le', v_mission.fin_le,
      'duree_heures', v_mission.duree_heures,
      'type_contrat_applique', v_mission.type_contrat_applique,
      'taux_horaire_base', v_mission.taux_horaire_base,
      'profession_requise', v_mission.profession_requise,
      'soignant_assigne_id', v_mission.soignant_assigne_id,
      'statut', v_mission.statut,
      'regularisation_sociale_requise', v_mission.regularisation_sociale_requise
    ) END,
    'soignant', CASE WHEN v_soignant.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_soignant.id,
      'nom', v_soignant.nom,
      'prenom', v_soignant.prenom,
      'rpps', v_soignant.numero_rpps,
      'profession', v_soignant.profession,
      'note_moyenne', v_soignant.note_moyenne,
      'telephone', v_soignant.telephone,
      'est_salarie_etablissement', v_soignant.est_salarie_etablissement
    ) END,
    'etablissement', CASE WHEN v_etab.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_etab.id,
      'nom', v_etab.nom,
      'siret', v_etab.siret,
      'adresse', concat_ws(', ', v_etab.adresse_rue, v_etab.adresse_code_postal, v_etab.adresse_ville),
      'telephone_contact', v_etab.telephone_contact,
      'email_contact', v_etab.email_contact,
      'est_secteur_public', v_etab.est_secteur_public
    ) END,
    'pointages', v_pointages,
    'heures', jsonb_build_object(
      'prevues', CASE WHEN v_mission.id IS NULL THEN NULL ELSE jsonb_build_object(
        'debut', v_mission.debut_le,
        'fin', v_mission.fin_le,
        'duree_h', v_mission.duree_heures
      ) END,
      'declarees', CASE WHEN v_presence IS NULL OR v_presence.id IS NULL THEN NULL ELSE jsonb_build_object(
        'debut', v_presence.pointage_arrivee_le,
        'fin', v_presence.pointage_depart_le,
        'duree_nette_min', v_presence.duree_nette_min,
        'heures_reelles', v_presence.heures_reelles,
        'retard_min', v_presence.retard_min,
        'depart_anticipe_min', v_presence.depart_anticipe_min,
        'valide_par_etablissement', v_presence.valide_par_etablissement,
        'valide_le', v_presence.valide_le
      ) END
    ),
    'factures_liees', v_factures,
    'messages', v_messages
  );

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_lister_missions_a_facturer(p_today date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_finales jsonb;
  v_hebdo jsonb;
BEGIN
  -- 1. Missions TERMINEE non encore facturées en finale.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mode', 'FINALE',
    'mission_id', m.id,
    'soignant_id', m.soignant_assigne_id,
    'etablissement_id', m.etablissement_id,
    'periode_debut', m.debut_le::date,
    'periode_fin', m.fin_le::date,
    'numero_semaine_iso', NULL,
    'annee_iso', NULL,
    'strategie_facturation', m.strategie_facturation::text,
    'est_facture_finale_mission', true
  )), '[]'::jsonb)
  INTO v_finales
  FROM missions m
  JOIN soignants s ON s.id = m.soignant_assigne_id
  WHERE m.statut = 'TERMINEE'
    AND m.fin_le::date < p_today
    AND m.type_contrat_applique = 'LIBERAL'
    AND COALESCE(s.mandat_facturation_signe, false) = true
    AND NOT EXISTS (
      SELECT 1 FROM factures_honoraires fh
      WHERE fh.mission_id = m.id
        AND fh.est_facture_finale_mission = true
        AND fh.statut NOT IN ('ANNULEE','REMPLACEE','ERREUR_GENERATION')
    )
    AND EXISTS (
      SELECT 1 FROM mission_creneaux mc
      WHERE mc.mission_id = m.id
        AND (
          (mc.type_creneau = 'EFFECTIF' AND mc.fin IS NOT NULL)
          OR mc.type_creneau = 'PREVISIONNEL'
        )
    )
    -- 7b-B : gate validation des présences (voir en-tête de la migration).
    AND NOT EXISTS (
      SELECT 1 FROM presences p
      WHERE p.mission_id = m.id
        AND COALESCE(p.valide_par_etablissement, false) = false
        AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL)
    );

  -- 2. Missions HEBDO_ET_FINALE → semaines ISO closes non facturées.
  WITH semaines AS (
    SELECT
      m.id AS mission_id,
      m.soignant_assigne_id,
      m.etablissement_id,
      m.debut_le, m.fin_le,
      m.strategie_facturation,
      gs.lundi_semaine
    FROM missions m
    JOIN soignants s ON s.id = m.soignant_assigne_id
    CROSS JOIN LATERAL generate_series(
      date_trunc('week', m.debut_le)::date,
      LEAST(m.fin_le::date, p_today - INTERVAL '1 day')::date,
      '7 days'::interval
    ) AS gs(lundi_semaine)
    WHERE m.statut IN ('EN_COURS','TERMINEE')
      AND m.strategie_facturation = 'HEBDO_ET_FINALE'
      AND m.type_contrat_applique = 'LIBERAL'
      AND COALESCE(s.mandat_facturation_signe, false) = true
      -- 7b-B : une présence contestée gèle aussi les factures hebdo.
      AND NOT EXISTS (
        SELECT 1 FROM presences p
        WHERE p.mission_id = m.id
          AND COALESCE(p.valide_par_etablissement, false) = false
          AND p.motif_litige IS NOT NULL
      )
  ),
  semaines_closes AS (
    SELECT
      sm.*,
      (sm.lundi_semaine + INTERVAL '6 days')::date AS dimanche_semaine,
      EXTRACT(WEEK FROM sm.lundi_semaine)::smallint AS num_sem,
      EXTRACT(ISOYEAR FROM sm.lundi_semaine)::smallint AS ann_iso,
      GREATEST(sm.lundi_semaine::date, sm.debut_le::date) AS periode_d,
      LEAST((sm.lundi_semaine + INTERVAL '6 days')::date, sm.fin_le::date) AS periode_f
    FROM semaines sm
    WHERE (sm.lundi_semaine + INTERVAL '6 days')::date < p_today
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mode', 'HEBDO',
    'mission_id', sa.mission_id,
    'soignant_id', sa.soignant_assigne_id,
    'etablissement_id', sa.etablissement_id,
    'periode_debut', sa.periode_d,
    'periode_fin', sa.periode_f,
    'numero_semaine_iso', sa.num_sem,
    'annee_iso', sa.ann_iso,
    'strategie_facturation', sa.strategie_facturation::text,
    'est_facture_finale_mission', false
  )), '[]'::jsonb)
  INTO v_hebdo
  FROM semaines_closes sa
  WHERE NOT EXISTS (
    SELECT 1 FROM factures_honoraires fh
    WHERE fh.mission_id = sa.mission_id
      AND fh.annee_iso = sa.ann_iso
      AND fh.numero_semaine_iso = sa.num_sem
      AND fh.est_facture_finale_mission = false
      AND fh.statut NOT IN ('ANNULEE','REMPLACEE','ERREUR_GENERATION')
  )
  AND EXISTS (
    SELECT 1 FROM mission_creneaux mc
    WHERE mc.mission_id = sa.mission_id
      AND (
        (mc.type_creneau = 'EFFECTIF' AND mc.fin IS NOT NULL)
        OR mc.type_creneau = 'PREVISIONNEL'
      )
      AND mc.debut::date <= sa.periode_f
      AND COALESCE(mc.fin::date, mc.debut::date) >= sa.periode_d
  );

  RETURN jsonb_build_object(
    'today', p_today,
    'finales', v_finales,
    'hebdo', v_hebdo,
    'total', jsonb_array_length(v_finales) + jsonb_array_length(v_hebdo)
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_lister_missions_contrat_travail_manquant()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mission_id', m.id,
    'etablissement_id', m.etablissement_id,
    'soignant_id', m.soignant_assigne_id,
    'intitule', m.intitule,
    'debut_le', m.debut_le,
    'nom_etablissement', e.nom,
    'prenom_soignant', s.prenom,
    'nom_soignant', s.nom
  )), '[]'::jsonb)
  INTO v_result
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  JOIN soignants s ON s.id = m.soignant_assigne_id
  WHERE m.statut IN ('ASSIGNEE','EN_COURS')
    AND m.type_contrat_applique = 'SALARIE'
    AND m.debut_le >= now()
    AND m.debut_le < now() + INTERVAL '36 hours'
    AND m.soignant_assigne_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM contrats_travail_missions ct WHERE ct.mission_id = m.id)
    AND NOT EXISTS (SELECT 1 FROM rappels_contrat_travail rct
                    WHERE rct.mission_id = m.id AND rct.envoye_le = CURRENT_DATE);

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_lister_mes_filtres_sauvegardes(p_audience filtre_audience DEFAULT NULL::filtre_audience)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id, 'nom', nom, 'audience', audience::text,
    'filtres', filtres, 'alerte_active', alerte_active,
    'frequence_alerte', frequence_alerte::text,
    'dernier_check_le', dernier_check_le,
    'nb_resultats_dernier_check', nb_resultats_dernier_check,
    'cree_le', cree_le, 'mis_a_jour_le', mis_a_jour_le
  ) ORDER BY mis_a_jour_le DESC), '[]'::jsonb)
  INTO v_result
  FROM filtres_sauvegardes
  WHERE utilisateur_id = v_uid
    AND (p_audience IS NULL OR audience = p_audience);

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_lister_notations_recues(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_target_id UUID;
  v_target_sens public.sens_notation;
  v_result JSONB;
  v_limit INT;
BEGIN
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);

  IF v_etab_id IS NOT NULL THEN
    v_target_id := v_etab_id;
    v_target_sens := 'SOIGNANT_VERS_ETAB';
  ELSIF v_uid IS NOT NULL THEN
    v_target_id := v_uid;
    v_target_sens := 'ETAB_VERS_SOIGNANT';
  ELSE
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', n.id,
    'mission_id', n.mission_id,
    'mission_intitule', m.intitule,
    'mission_fin_le', m.fin_le,
    'critere_1', n.critere_1,
    'critere_2', n.critere_2,
    'critere_3', n.critere_3,
    'critere_4', n.critere_4,
    'note_moyenne', ROUND(((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0)::numeric, 1),
    'commentaire', n.commentaire,
    'cree_le', n.cree_le
  ) ORDER BY n.cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM notations_missions n
  JOIN missions m ON m.id = n.mission_id
  WHERE n.note_id = v_target_id AND n.sens = v_target_sens AND n.masque = false
  LIMIT v_limit;

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_lister_missions_a_noter_etab()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_missions jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mission_id', m.id,
    'intitule', m.intitule,
    'debut_le', m.debut_le,
    'fin_le', m.fin_le,
    'soignant_id', m.soignant_assigne_id,
    'soignant_prenom', s.prenom,
    'soignant_nom', s.nom,
    'soignant_profession', s.profession,
    'duree_heures', m.duree_heures,
    'taux_horaire_base', m.taux_horaire_base,
    'jours_depuis_fin', EXTRACT(DAY FROM NOW() - m.fin_le)::int
  ) ORDER BY m.fin_le DESC), '[]'::jsonb)
  INTO v_missions
  FROM public.missions m
  JOIN public.soignants s ON s.id = m.soignant_assigne_id
  WHERE m.etablissement_id = v_etab_id
    AND m.statut = 'TERMINEE'
    AND m.soignant_assigne_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.notations_missions nm
      WHERE nm.mission_id = m.id
        AND nm.sens = 'ETAB_VERS_SOIGNANT'
        AND nm.notateur_id = v_uid
    )
    AND m.fin_le > NOW() - INTERVAL '60 days';

  RETURN jsonb_build_object('success', true, 'missions', v_missions);
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_maj_activite_soignant()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    UPDATE soignants SET
        derniere_activite_le = NOW()
    WHERE id = auth.uid();
    RETURN '{"success":true}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_litiges_etablissement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
BEGIN
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;
    
    RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(x)) FROM (
            SELECT l.id::TEXT AS litige_id, l.mission_id::TEXT, l.statut, l.initie_par,
                l.motif, l.cree_le, l.resolu_le, l.resolution,
                l.accord_soignant, l.accord_etablissement,
                m.intitule AS mission_intitule, m.debut_le AS mission_debut,
                COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                s.profession::TEXT AS soignant_profession,
                (SELECT COUNT(*) FROM messages_litige ml WHERE ml.litige_id = l.id) AS nb_messages,
                (SELECT ml2.contenu FROM messages_litige ml2 WHERE ml2.litige_id = l.id ORDER BY ml2.cree_le DESC LIMIT 1) AS dernier_message
            FROM litiges l
            JOIN missions m ON m.id = l.mission_id
            JOIN soignants s ON s.id = l.soignant_id
            WHERE l.etablissement_id = v_etab_id
            ORDER BY 
                CASE WHEN l.statut IN ('OUVERT', 'EN_MEDIATION', 'CONTESTEE') THEN 0 ELSE 1 END,
                l.cree_le DESC
        ) x
    ), '[]'::JSONB);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_litiges_escalader_auto()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_delai_liberal_h INT;
  v_delai_salarie_j_ouvres INT;
  v_nb_escalades INT := 0;
  v_litige RECORD;
  v_admin_id UUID;
BEGIN
  SELECT valeur::INT INTO v_delai_liberal_h
    FROM public.parametres_litiges WHERE cle = 'delai_escalade_liberal_h';
  SELECT valeur::INT INTO v_delai_salarie_j_ouvres
    FROM public.parametres_litiges WHERE cle = 'delai_escalade_salarie_jours_ouvres';

  FOR v_litige IN
    SELECT l.id, l.mission_id, l.soignant_id, l.etablissement_id,
           l.type_litige, l.cree_le,
           CASE
             WHEN m.type_contrat_applique = 'SALARIE' THEN TRUE
             WHEN m.type_contrat_applique = 'LIBERAL' THEN FALSE
             ELSE COALESCE(s.est_salarie_etablissement, FALSE)
           END AS est_salarie
      FROM public.litiges l
      LEFT JOIN public.soignants s ON s.id = l.soignant_id
      LEFT JOIN public.missions  m ON m.id = l.mission_id
     WHERE l.statut IN ('OUVERT', 'EN_DISCUSSION')
       AND l.escalade_auto_le IS NULL
       AND (l.reponse IS NULL OR length(trim(l.reponse)) = 0)
       AND NOT l.est_informatif
       AND (
         (CASE
            WHEN m.type_contrat_applique = 'SALARIE' THEN TRUE
            WHEN m.type_contrat_applique = 'LIBERAL' THEN FALSE
            ELSE COALESCE(s.est_salarie_etablissement, FALSE)
          END = FALSE
          AND l.cree_le < NOW() - make_interval(hours => v_delai_liberal_h))
         OR
         (CASE
            WHEN m.type_contrat_applique = 'SALARIE' THEN TRUE
            WHEN m.type_contrat_applique = 'LIBERAL' THEN FALSE
            ELSE COALESCE(s.est_salarie_etablissement, FALSE)
          END = TRUE
          AND l.cree_le < public.fn_ajouter_jours_ouvres(NOW(), -v_delai_salarie_j_ouvres))
       )
  LOOP
    UPDATE public.litiges
       SET statut = 'EN_MEDIATION',
           escalade_auto_le = NOW(),
           escalade_auto_motif = CASE
             WHEN v_litige.est_salarie THEN 'Pas de réponse dans le délai salarié (5 jours ouvrés)'
             ELSE 'Pas de réponse dans le délai libéral (72h)'
           END
     WHERE id = v_litige.id;

    PERFORM public.fn_ecrire_audit(
      NULL, 'SYSTEM', 'LITIGE_ESCALADE_AUTO',
      'litige', v_litige.id, NULL,
      jsonb_build_object(
        'type_litige', v_litige.type_litige,
        'mission_id', v_litige.mission_id,
        'est_salarie', v_litige.est_salarie
      ),
      NULL, NULL
    );

    FOR v_admin_id IN SELECT * FROM public.fn_list_admin_user_ids()
    LOOP
      PERFORM public.fn_litige_push_notification(
        v_admin_id,
        'ADMIN',
        'LITIGE_ESCALADE_ADMIN',
        'Litige escaladé : ' || v_litige.type_litige,
        'Un litige ' || v_litige.type_litige || ' sur mission '
          || v_litige.mission_id::text
          || ' a été auto-escaladé en médiation.',
        v_litige.id,
        jsonb_build_object(
          'type_litige', v_litige.type_litige,
          'mission_id', v_litige.mission_id,
          'prioritaire', TRUE
        )
      );
    END LOOP;

    v_nb_escalades := v_nb_escalades + 1;
  END LOOP;

  RETURN jsonb_build_object('escalades', v_nb_escalades);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_litiges_historique_similaires(p_litige_id uuid, p_limit integer DEFAULT 5)
 RETURNS TABLE(id uuid, type_litige type_litige, resolution text, en_faveur_de text, cree_le timestamp with time zone, resolu_le timestamp with time zone, motif text, statut text, mission_id uuid, montant_tresorerie_bloquee numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_type_litige   public.type_litige;
  v_etab_id       UUID;
  v_limit         INTEGER := GREATEST(1, LEAST(p_limit, 50));
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'fn_litiges_historique_similaires: accès admin requis'
      USING ERRCODE = '42501';
  END IF;

  SELECT l.type_litige, l.etablissement_id
    INTO v_type_litige, v_etab_id
    FROM public.litiges l
   WHERE l.id = p_litige_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Litige % introuvable', p_litige_id
      USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
    SELECT
      l.id,
      l.type_litige,
      l.resolution,
      CASE l.statut
        WHEN 'RESOLU_SOIGNANT'      THEN 'SOIGNANT'
        WHEN 'RESOLU_ETABLISSEMENT' THEN 'ETABLISSEMENT'
        WHEN 'RESOLU_ADMIN'         THEN 'PARTAGE'
        ELSE NULL
      END AS en_faveur_de,
      l.cree_le,
      l.resolu_le,
      l.motif,
      l.statut,
      l.mission_id,
      l.montant_tresorerie_bloquee
      FROM public.litiges l
     WHERE l.id <> p_litige_id
       AND l.type_litige = v_type_litige
       AND l.etablissement_id = v_etab_id
       AND l.statut IN (
         'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN',
         'FERME', 'CLOTURE', 'RESOLU'
       )
     ORDER BY l.resolu_le DESC NULLS LAST, l.cree_le DESC
     LIMIT v_limit;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_maj_etape_parcours(p_etape_cle text, p_valeur boolean)
 RETURNS parcours_liberal_soignants
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_parcours public.parcours_liberal_soignants;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;
  IF p_etape_cle !~ '^[a-z0-9_]{1,50}$' THEN
    RAISE EXCEPTION 'Clé étape invalide';
  END IF;

  PERFORM public.fn_get_or_create_parcours_liberal();

  UPDATE public.parcours_liberal_soignants
  SET etapes = etapes || jsonb_build_object(
    p_etape_cle, p_valeur,
    p_etape_cle || '_date', CASE WHEN p_valeur THEN to_jsonb(now()::TEXT) ELSE 'null'::jsonb END
  )
  WHERE soignant_id = auth.uid()
  RETURNING * INTO v_parcours;

  RETURN v_parcours;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_maj_infos_dpae(p_sexe text, p_lieu_naissance_commune text, p_lieu_naissance_departement text, p_pays_naissance text, p_nationalite text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_manquants text[] := ARRAY[]::text[];
  v_pays text := COALESCE(NULLIF(trim(p_pays_naissance), ''), 'France');
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  -- Validation champs obligatoires
  IF p_sexe IS NULL OR p_sexe NOT IN ('M', 'F') THEN
    v_manquants := array_append(v_manquants, 'Sexe (état civil)');
  END IF;
  IF p_nationalite IS NULL OR length(trim(p_nationalite)) = 0 THEN
    v_manquants := array_append(v_manquants, 'Nationalité');
  END IF;
  -- Commune + département obligatoires si naissance en France
  IF v_pays = 'France' THEN
    IF p_lieu_naissance_commune IS NULL OR length(trim(p_lieu_naissance_commune)) = 0 THEN
      v_manquants := array_append(v_manquants, 'Commune de naissance');
    END IF;
    IF p_lieu_naissance_departement IS NULL OR length(trim(p_lieu_naissance_departement)) = 0 THEN
      v_manquants := array_append(v_manquants, 'Département de naissance');
    END IF;
    IF p_lieu_naissance_departement IS NOT NULL
       AND p_lieu_naissance_departement !~ '^(0[1-9]|[1-8][0-9]|9[0-5]|2A|2B|97[1-6])$' THEN
      RETURN jsonb_build_object('success', false, 'error',
        'Département invalide (attendu : 01-95, 2A, 2B, 971-976).');
    END IF;
  END IF;

  IF array_length(v_manquants, 1) IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Champs obligatoires manquants : ' || array_to_string(v_manquants, ', ') || '.');
  END IF;

  UPDATE public.soignants
  SET sexe = p_sexe,
      lieu_naissance_commune = NULLIF(trim(p_lieu_naissance_commune), ''),
      lieu_naissance_departement = NULLIF(trim(p_lieu_naissance_departement), ''),
      pays_naissance = v_pays,
      nationalite = COALESCE(NULLIF(trim(p_nationalite), ''), 'Française'),
      modifie_le = NOW()
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profil soignant introuvable');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_maj_nir_soignant(p_nir text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_normalise text;
  v_nir_base bigint;
  v_cle_attendue int;
  v_cle_fournie int;
  v_ancien text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  -- Vérifier si le NIR est déjà verrouillé (nir_verifie = true)
  SELECT numero_securite_sociale INTO v_ancien FROM soignants WHERE id = v_uid;
  IF v_ancien IS NOT NULL AND EXISTS (
    SELECT 1 FROM soignants WHERE id = v_uid AND (nir_verifie = true)
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NIR_VERROUILLE',
      'error', 'Votre NIR a déjà été vérifié et ne peut plus être modifié.');
  END IF;

  IF p_nir IS NULL OR length(trim(p_nir)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NIR_REQUIS');
  END IF;

  v_normalise := regexp_replace(upper(trim(p_nir)), '\s+', '', 'g');

  -- Corse : 2A → 19, 2B → 18 pour le calcul de clé
  -- Format : sexe(1) année(2) mois(2) dept(2-3) commune(3) ordre(3) [clé(2)]
  IF v_normalise !~ '^[12][0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01]|2A|2B|9[0-9])[0-9]{6}([0-9]{2})?$' THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'NIR_FORMAT_INVALIDE',
      'error', 'Le NIR doit faire 13 chiffres (sans clé) ou 15 chiffres (avec clé). Vérifiez votre carte Vitale.'
    );
  END IF;

  -- Validation de la clé si 15 chiffres fournis
  IF length(v_normalise) = 15 THEN
    DECLARE
      v_base_str text := left(v_normalise, 13);
    BEGIN
      -- Gestion Corse : 2A → remplacer par 19, 2B → remplacer par 18
      v_base_str := replace(v_base_str, '2A', '19');
      v_base_str := replace(v_base_str, '2B', '18');
      v_nir_base := v_base_str::bigint;
      v_cle_fournie := right(v_normalise, 2)::int;
      v_cle_attendue := 97 - (v_nir_base % 97);
      IF v_cle_fournie != v_cle_attendue THEN
        RETURN jsonb_build_object(
          'success', false, 'error_code', 'NIR_CLE_INVALIDE',
          'error', 'La clé de contrôle du NIR est incorrecte. Vérifiez les 2 derniers chiffres sur votre carte Vitale.'
        );
      END IF;
    END;
  END IF;

  UPDATE public.soignants
  SET numero_securite_sociale = v_normalise,
      nir_verifie = CASE WHEN length(v_normalise) = 15 THEN true ELSE false END,
      modifie_le = now()
  WHERE id = v_uid;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'DONNEES_PERSO_MODIFICATION', 'soignant', v_uid,
    jsonb_build_object(
      'champ', 'numero_securite_sociale',
      'nir_verifie', length(v_normalise) = 15,
      'horodatage', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'nir_verifie', length(v_normalise) = 15,
    'message', CASE WHEN length(v_normalise) = 15
      THEN 'NIR vérifié et verrouillé (clé valide).'
      ELSE 'NIR enregistré. Ajoutez les 2 chiffres de clé (carte Vitale) pour verrouiller.'
    END
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_ma_streak()
 RETURNS TABLE(streak_count integer, max_streak integer, last_activity_date date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    CASE WHEN s.last_activity_date >= current_date - 1 THEN s.streak_count ELSE 0 END,
    COALESCE(s.max_streak, 0),
    s.last_activity_date
  FROM public.streaks_soignant s
  WHERE s.soignant_id = auth.uid();
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_evaluations_recues()
 RETURNS TABLE(mission_id uuid, mission_intitule text, note integer, commentaire text, type_evaluateur text, cree_le timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        e.mission_id,
        m.intitule,
        e.note,
        CASE WHEN e.visible THEN e.commentaire ELSE NULL END,
        e.type_evaluateur,
        e.cree_le
    FROM evaluations e
    JOIN missions m ON m.id = e.mission_id
    WHERE e.evalue_id = auth.uid()
    ORDER BY e.cree_le DESC;
    -- PAS de evaluateur_id retourné = anonyme
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_marquer_messages_lus(p_conversation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    UPDATE messages_chat SET lu = TRUE
    WHERE conversation_id = p_conversation_id
      AND auteur_id != auth.uid()
      AND lu = FALSE;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_avances_factor()
 RETURNS TABLE(id uuid, numero_facture text, etablissement_nom text, mission_intitule text, montant_facture_ttc numeric, frais_factor numeric, frais_jolene numeric, montant_net_soignant numeric, statut text, cree_le timestamp with time zone, financee_le timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT a.id, fh.numero_facture, e.nom, m.intitule,
           a.montant_facture_ttc, a.frais_factor, a.frais_jolene, a.montant_net_soignant,
           a.statut, a.cree_le, a.financee_le
    FROM factor_advances a
    JOIN factures_honoraires fh ON fh.id = a.facture_honoraire_id
    JOIN etablissements e ON e.id = a.etablissement_id
    LEFT JOIN missions m ON m.id = a.mission_id
    WHERE a.soignant_id = auth.uid()
    ORDER BY a.cree_le DESC;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_bulletins_paie()
 RETURNS TABLE(id uuid, numero_bulletin text, mission_id uuid, etablissement_id uuid, etablissement_nom text, mission_intitule text, periode_debut date, periode_fin date, salaire_brut numeric, total_cotisations_salariales numeric, net_avant_impot numeric, ifm numeric, icp numeric, statut text, date_emission date, date_paiement date, pdf_s3_key text, cree_le timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT bp.id, bp.numero_bulletin, bp.mission_id, bp.etablissement_id,
    e.nom AS etablissement_nom, m.intitule AS mission_intitule,
    bp.periode_debut, bp.periode_fin,
    bp.salaire_brut, bp.total_cotisations_salariales, bp.net_avant_impot,
    bp.ifm, bp.icp, bp.statut, bp.date_emission, bp.date_paiement,
    bp.pdf_s3_key, bp.cree_le
  FROM bulletins_paie bp
  LEFT JOIN missions m ON m.id = bp.mission_id
  LEFT JOIN etablissements e ON e.id = bp.etablissement_id
  WHERE bp.soignant_id = auth.uid()
  ORDER BY bp.periode_debut DESC, bp.cree_le DESC;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_marquer_rappel_contrat_travail_envoye(p_mission_id uuid, p_cible_etab boolean, p_cible_soignant boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  INSERT INTO rappels_contrat_travail (mission_id, cible_etab, cible_soignant)
  VALUES (p_mission_id, p_cible_etab, p_cible_soignant)
  ON CONFLICT (mission_id, envoye_le) DO UPDATE
    SET cible_etab = rappels_contrat_travail.cible_etab OR EXCLUDED.cible_etab,
        cible_soignant = rappels_contrat_travail.cible_soignant OR EXCLUDED.cible_soignant;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_credits_etab()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id UUID := mon_etablissement_id();
  v_total_dispo NUMERIC;
  v_total_applique NUMERIC;
  v_credits JSONB;
BEGIN
  IF v_etab_id IS NULL AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  SELECT COALESCE(SUM(montant_eur) FILTER (WHERE applique_le IS NULL), 0),
         COALESCE(SUM(montant_eur) FILTER (WHERE applique_le IS NOT NULL), 0)
  INTO v_total_dispo, v_total_applique
  FROM credits_etablissement WHERE etablissement_id = v_etab_id OR est_admin();

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'montant_eur', c.montant_eur,
    'motif', c.motif,
    'applique_le', c.applique_le,
    'facture_id', c.facture_id,
    'cree_le', c.cree_le
  ) ORDER BY c.cree_le DESC), '[]'::jsonb)
  INTO v_credits
  FROM credits_etablissement c WHERE c.etablissement_id = v_etab_id OR est_admin();

  RETURN jsonb_build_object(
    'total_disponible_eur', v_total_dispo,
    'total_applique_eur', v_total_applique,
    'credits', v_credits
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_dpae()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_dpae jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'contrat_id', cm.id,
    'mission_id', cm.mission_id,
    'mission_intitule', m.intitule,
    'etablissement_id', m.etablissement_id,
    'etablissement_nom', e.nom,
    'debut_le', m.debut_le,
    'fin_le', m.fin_le,
    'type_contrat', cm.type_contrat,
    'dpae_effectuee', cm.dpae_effectuee,
    'dpae_numero', cm.dpae_numero,
    'dpae_effectuee_le', cm.dpae_effectuee_le,
    'rappel_dpae_affiche', cm.rappel_dpae_affiche,
    'rappel_dpae_affiche_le', cm.rappel_dpae_affiche_le,
    'statut_contrat', cm.statut
  ) ORDER BY m.debut_le DESC), '[]'::jsonb)
  INTO v_dpae
  FROM public.contrats_mission cm
  JOIN public.missions m ON m.id = cm.mission_id
  JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE cm.soignant_id = v_uid
    AND cm.type_contrat IN ('CDD', 'CDD', 'SALARIE')
    AND cm.statut IN ('SIGNE_COMPLET', 'SIGNE_PARTIEL');

  RETURN jsonb_build_object('success', true, 'dpae', v_dpae);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_marquer_etape_onboarding(p_etape_id text, p_termine boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_etape_id IS NULL OR length(trim(p_etape_id)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ETAPE_INVALIDE');
  END IF;

  -- Soignant
  IF EXISTS (SELECT 1 FROM public.soignants WHERE id = v_uid) THEN
    UPDATE public.soignants
    SET onboarding_etapes_completees = CASE
          WHEN onboarding_etapes_completees @> to_jsonb(p_etape_id::text)
          THEN onboarding_etapes_completees
          ELSE onboarding_etapes_completees || to_jsonb(p_etape_id::text)
        END,
        onboarding_termine_le = CASE WHEN p_termine THEN now() ELSE onboarding_termine_le END
    WHERE id = v_uid;
    RETURN jsonb_build_object('success', true, 'role', 'SOIGNANT');
  END IF;

  -- Étab
  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NOT NULL THEN
    UPDATE public.etablissements
    SET onboarding_etapes_completees = CASE
          WHEN onboarding_etapes_completees @> to_jsonb(p_etape_id::text)
          THEN onboarding_etapes_completees
          ELSE onboarding_etapes_completees || to_jsonb(p_etape_id::text)
        END,
        onboarding_termine_le = CASE WHEN p_termine THEN now() ELSE onboarding_termine_le END
    WHERE id = v_etab_id;
    RETURN jsonb_build_object('success', true, 'role', 'ETAB');
  END IF;

  RETURN jsonb_build_object('success', false, 'error_code', 'PROFIL_INTROUVABLE');
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_exclusions_recues()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', e.id,
            'exclu_par', e.exclu_par,
            'type_exclu_par', e.type_exclu_par,
            'motif', e.motif,
            'etablissement_nom', et.nom,
            'cree_le', e.cree_le
        ) ORDER BY e.cree_le DESC), '[]'::JSONB)
        FROM exclusions e
        LEFT JOIN etablissements et ON e.exclu_par = et.id
        WHERE e.exclu_id = auth.uid()
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_filleuls()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_result JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::JSONB; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'filleul_id',p.filleul_id,'prenom',s.prenom,'statut',p.statut,'cree_le',p.cree_le,'valide_le',p.valide_le,'filleul_active_le',p.filleul_active_le,'commission_cumulee_filleul',p.commission_cumulee_filleul,'prime_versee_le',p.prime_versee_le,'premiere_mission_le',s.premiere_mission_le,'bonus_heures_parrain',p.bonus_heures_parrain) ORDER BY p.cree_le DESC), '[]'::jsonb) INTO v_result FROM parrainages p JOIN soignants s ON s.id = p.filleul_id WHERE p.parrain_id = v_uid;
  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_factures()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_result JSONB;
BEGIN
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(f) ORDER BY f.date_emission DESC), '[]'::JSONB)
    INTO v_result
    FROM (
        SELECT 
            id, numero_facture, statut, 
            montant_ht, taux_tva, montant_tva, montant_ttc,
            nombre_missions, mode_paiement,
            periode_debut, periode_fin,
            date_emission, date_echeance, date_paiement,
            stripe_hosted_url, est_secteur_public,
            chorus_pro_statut, chorus_pro_id,
            virement_reference, virement_confirme_le
        FROM factures 
        WHERE etablissement_id = v_etab_id
        ORDER BY date_emission DESC
    ) f;

    RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_favoris_etablissements()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_result JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'etablissement_id', e.id,
    'nom', e.nom,
    'ville', e.adresse_ville,
    'logo_url', e.logo_url,
    'type_etablissement', e.type,
    'nb_missions_ouvertes', (
      SELECT count(*) FROM missions m
      WHERE m.etablissement_id = e.id AND m.statut = 'OUVERTE' AND m.debut_le > NOW()
    ),
    'cree_le', f.cree_le
  ) ORDER BY f.cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM favoris_soignant_etab f
  JOIN etablissements e ON e.id = f.etablissement_id
  WHERE f.soignant_id = v_uid;

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_favoris_soignants()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id UUID;
  v_result JSONB;
BEGIN
  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'soignant_id', s.id,
    'prenom', s.prenom,
    'nom_initiale', LEFT(s.nom, 1) || '.',
    'profession', s.profession::text,
    'specialite_medicale', s.specialite_medicale,
    'avatar_url', s.avatar_url,
    'score_fiabilite', CASE WHEN COALESCE(s.total_missions_terminees, 0) >= 3 THEN s.score_fiabilite ELSE NULL END,
    'note_moyenne', CASE WHEN COALESCE(s.nb_evaluations, 0) >= 3 THEN s.note_moyenne ELSE NULL END,
    'rpps_verifie', COALESCE(s.rpps_verifie, false),
    'tous_documents_valides', COALESCE(s.tous_documents_valides, false),
    'disponible_urgence', COALESCE(s.disponible_urgence, false),
    'cree_le', f.cree_le
  ) ORDER BY f.cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM favoris_etab_soignant f
  JOIN soignants s ON s.id = f.soignant_id
  WHERE (f.etablissement_id = v_etab_id OR est_admin())
    AND s.supprime_le IS NULL;

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_filleuls_etab()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id UUID := mon_etablissement_id();
  v_result JSONB;
BEGIN
  IF v_etab_id IS NULL AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'parrainage_id', pe.id,
    'filleul_etab_id', e.id,
    'filleul_nom', e.nom,
    'filleul_ville', e.adresse_ville,
    'statut', pe.statut,
    'cree_le', pe.cree_le,
    'valide_le', pe.valide_le,
    'credit_montant_eur', (
      SELECT SUM(c.montant_eur) FROM credits_etablissement c
      WHERE c.parrainage_id = pe.id AND c.etablissement_id = pe.parrain_etab_id
    )
  ) ORDER BY pe.cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM parrainages_etablissements pe
  JOIN etablissements e ON e.id = pe.filleul_etab_id
  WHERE pe.parrain_etab_id = v_etab_id OR est_admin();

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_evenements_score(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_events jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF EXISTS (SELECT 1 FROM public.soignants WHERE id = v_uid) THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', id, 'type_evenement', type_evenement, 'points', points,
      'points_corriges', points_corriges, 'motif', motif,
      'contestable', contestable AND decision_admin IS NULL AND reclamation_id IS NULL,
      'decision_admin', decision_admin, 'cree_le', cree_le,
      'mission_id', mission_id
    ) ORDER BY cree_le DESC), '[]'::jsonb)
    INTO v_events
    FROM (
      SELECT * FROM public.evenements_score_soignant
      WHERE soignant_id = v_uid
        AND cree_le > NOW() - INTERVAL '12 months'
      ORDER BY cree_le DESC LIMIT p_limit
    ) t;
    RETURN jsonb_build_object('success', true, 'type', 'SOIGNANT', 'events', v_events);
  END IF;

  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', id, 'type_evenement', type_evenement, 'points', points,
      'points_corriges', points_corriges, 'motif', motif,
      'contestable', contestable AND decision_admin IS NULL AND reclamation_id IS NULL,
      'decision_admin', decision_admin, 'cree_le', cree_le,
      'mission_id', mission_id
    ) ORDER BY cree_le DESC), '[]'::jsonb)
    INTO v_events
    FROM (
      SELECT * FROM public.evenements_score_etab
      WHERE etablissement_id = v_etab_id
        AND cree_le > NOW() - INTERVAL '12 months'
      ORDER BY cree_le DESC LIMIT p_limit
    ) t;
    RETURN jsonb_build_object('success', true, 'type', 'ETAB', 'events', v_events);
  END IF;

  RETURN jsonb_build_object('success', false, 'error', 'Profil non identifié');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_factures_honoraires()
 RETURNS TABLE(id uuid, numero_facture text, etablissement_nom text, mission_intitule text, montant_ttc numeric, statut text, date_emission date, date_echeance date, date_paiement date, mission_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT fh.id, fh.numero_facture, e.nom, m.intitule,
           fh.montant_ttc, fh.statut, fh.date_emission, fh.date_echeance, fh.date_paiement,
           fh.mission_id
    FROM factures_honoraires fh
    JOIN etablissements e ON e.id = fh.etablissement_id
    LEFT JOIN missions m ON m.id = fh.mission_id
    WHERE fh.soignant_id = auth.uid()
    ORDER BY fh.date_emission DESC;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_messages_non_lus()
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM messages_chat mc
    JOIN conversations c ON c.id = mc.conversation_id
    WHERE mc.lu = FALSE
      AND mc.auteur_id != auth.uid()
      AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid() OR est_admin());
    RETURN v_count;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_revenus_connect(p_mois_debut date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_debut DATE;
    v_connect_mois NUMERIC;
    v_connect_total NUMERIC;
    v_connect_attente NUMERIC;
    v_paiements_mois NUMERIC;
    v_paiements_total NUMERIC;
BEGIN
    v_debut := COALESCE(p_mois_debut, DATE_TRUNC('month', CURRENT_DATE)::DATE);

    -- Stripe Connect transfers
    SELECT COALESCE(SUM(montant_soignant), 0) INTO v_connect_mois
    FROM stripe_transfers WHERE soignant_id = auth.uid() AND statut IN ('TRANSFERE','PAYE') AND transfere_le >= v_debut;

    SELECT COALESCE(SUM(montant_soignant), 0) INTO v_connect_total
    FROM stripe_transfers WHERE soignant_id = auth.uid() AND statut IN ('TRANSFERE','PAYE');

    SELECT COALESCE(SUM(montant_soignant), 0) INTO v_connect_attente
    FROM stripe_transfers WHERE soignant_id = auth.uid() AND statut IN ('EN_ATTENTE');

    -- Also count confirmed manual payments (virement/note honoraires)
    SELECT COALESCE(SUM(montant_net), 0) INTO v_paiements_mois
    FROM paiements_soignant WHERE soignant_id = auth.uid() AND statut = 'CONFIRME' AND confirme_par_soignant_le >= v_debut;

    SELECT COALESCE(SUM(montant_net), 0) INTO v_paiements_total
    FROM paiements_soignant WHERE soignant_id = auth.uid() AND statut = 'CONFIRME';

    RETURN jsonb_build_object(
        'mois_en_cours', v_connect_mois + v_paiements_mois,
        'total', v_connect_total + v_paiements_total,
        'en_attente', v_connect_attente,
        'stripe_connect_actif', fn_soignant_stripe_connect_actif(auth.uid())
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_soignants_etablissement()
 RETURNS TABLE(id uuid, prenom text, nom text, profession text, telephone text, numero_rpps text, score_fiabilite numeric, total_missions_terminees bigint, rpps_verifie boolean, tous_documents_valides boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (s.id)
        s.id, s.prenom::TEXT, s.nom::TEXT, s.profession::TEXT, s.telephone::TEXT,
        s.numero_rpps::TEXT, s.score_fiabilite,
        (SELECT COUNT(*) FROM missions m2 WHERE m2.soignant_assigne_id = s.id AND m2.statut = 'TERMINEE')::BIGINT,
        s.rpps_verifie, s.tous_documents_valides
    FROM soignants s
    JOIN missions m ON m.soignant_assigne_id = s.id
    WHERE m.etablissement_id = mon_etablissement_id()
      AND m.soignant_assigne_id IS NOT NULL;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_reclamations(p_statut text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'evenement_type', r.evenement_type,
    'evenement_id', COALESCE(r.evenement_soignant_id, r.evenement_etab_id),
    'motif_categorie', r.motif_categorie,
    'texte_libre', r.texte_libre,
    'justificatif_storage_path', r.justificatif_storage_path,
    'statut', r.statut,
    'decision_admin', r.decision_admin,
    'motif_admin', r.motif_admin,
    'traitee_le', r.traitee_le,
    'cree_le', r.cree_le
  ) ORDER BY r.cree_le DESC), '[]'::jsonb) INTO v_result
  FROM public.reclamations_score r
  WHERE r.contesteur_id = v_uid
    AND (p_statut IS NULL OR r.statut = p_statut);

  RETURN jsonb_build_object('success', true, 'reclamations', v_result);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_permissions_etab(p_etablissement_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_role text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'role', NULL);
  END IF;

  v_etab_id := COALESCE(p_etablissement_id, public.mon_etablissement_id());

  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'role', NULL, 'permissions', '{}'::jsonb);
  END IF;

  SELECT role INTO v_role
  FROM public.membres_etablissement
  WHERE etablissement_id = v_etab_id
    AND user_id = v_uid
    AND actif = true
  LIMIT 1;

  IF v_role IS NULL THEN
    RETURN jsonb_build_object('success', true, 'role', NULL, 'permissions', '{}'::jsonb);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'role', v_role,
    'permissions', jsonb_build_object(
      'gerer_equipe', v_role = 'PROPRIETAIRE',
      'supprimer_compte', v_role = 'PROPRIETAIRE',
      'profil_etab', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE'),
      'paiement', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE'),
      'missions', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH'),
      'candidatures', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH'),
      'contrats', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH'),
      'pointage', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY'),
      'rh', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH'),
      'lecture', v_role IS NOT NULL
    )
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_notations_recues_avec_stats(p_periode text DEFAULT 'TOUT'::text, p_note_min integer DEFAULT NULL::integer, p_etablissement_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid := public.mon_etablissement_id();
  v_target_id uuid;
  v_target_sens public.sens_notation;
  v_seuil_periode timestamptz;
  v_total int;
  v_notations jsonb;
  v_stats jsonb;
  v_etabs_disponibles jsonb;
  v_evolution jsonb;
  v_limit int;
BEGIN
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);

  IF v_etab_id IS NOT NULL THEN
    v_target_id := v_etab_id;
    v_target_sens := 'SOIGNANT_VERS_ETAB';
  ELSIF v_uid IS NOT NULL THEN
    v_target_id := v_uid;
    v_target_sens := 'ETAB_VERS_SOIGNANT';
  ELSE
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  v_seuil_periode := CASE p_periode
    WHEN '3M' THEN now() - INTERVAL '3 months'
    WHEN '6M' THEN now() - INTERVAL '6 months'
    WHEN '12M' THEN now() - INTERVAL '12 months'
    ELSE '1900-01-01'::timestamptz
  END;

  -- Total filtré
  SELECT COUNT(*) INTO v_total
  FROM public.notations_missions n
  JOIN public.missions m ON m.id = n.mission_id
  WHERE n.note_id = v_target_id
    AND n.sens = v_target_sens
    AND n.masque = false
    AND n.cree_le > v_seuil_periode
    AND (p_note_min IS NULL OR ROUND(((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0)::numeric, 1) >= p_note_min)
    AND (p_etablissement_id IS NULL OR m.etablissement_id = p_etablissement_id);

  -- Liste paginée
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', x.id,
    'mission_id', x.mission_id,
    'mission_intitule', x.mission_intitule,
    'mission_fin_le', x.mission_fin_le,
    'etablissement_id', x.etablissement_id,
    'etablissement_nom', x.etablissement_nom,
    'critere_1', x.critere_1,
    'critere_2', x.critere_2,
    'critere_3', x.critere_3,
    'critere_4', x.critere_4,
    'note_moyenne', ROUND(((x.critere_1 + x.critere_2 + x.critere_3 + x.critere_4) / 4.0)::numeric, 1),
    'commentaire', x.commentaire,
    'signale', x.signale,
    'cree_le', x.cree_le
  ) ORDER BY x.cree_le DESC), '[]'::jsonb)
  INTO v_notations
  FROM (
    SELECT n.id, n.mission_id, m.intitule AS mission_intitule, m.fin_le AS mission_fin_le,
           m.etablissement_id, e.nom AS etablissement_nom,
           n.critere_1, n.critere_2, n.critere_3, n.critere_4, n.commentaire, n.signale, n.cree_le
    FROM public.notations_missions n
    JOIN public.missions m ON m.id = n.mission_id
    LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE n.note_id = v_target_id
      AND n.sens = v_target_sens
      AND n.masque = false
      AND n.cree_le > v_seuil_periode
      AND (p_note_min IS NULL OR ROUND(((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0)::numeric, 1) >= p_note_min)
      AND (p_etablissement_id IS NULL OR m.etablissement_id = p_etablissement_id)
    ORDER BY n.cree_le DESC
    LIMIT v_limit OFFSET p_offset
  ) x;

  -- Stats globales (toutes périodes, pas de filtres pour avoir une vue globale)
  SELECT jsonb_build_object(
    'note_moyenne_globale', COALESCE(ROUND(AVG((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0)::numeric, 1), 0),
    'total_evaluations', COUNT(*),
    'pct_5_etoiles', CASE WHEN COUNT(*) > 0
      THEN ROUND(100.0 * SUM(CASE WHEN (n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) >= 19 THEN 1 ELSE 0 END) / COUNT(*), 1)
      ELSE 0 END
  )
  INTO v_stats
  FROM public.notations_missions n
  WHERE n.note_id = v_target_id AND n.sens = v_target_sens AND n.masque = false;

  -- Évolution 6 derniers mois (note moyenne par mois)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mois', to_char(x.mois, 'YYYY-MM'),
    'note_moyenne', ROUND(x.moyenne::numeric, 1),
    'nb', x.nb
  ) ORDER BY x.mois), '[]'::jsonb)
  INTO v_evolution
  FROM (
    SELECT date_trunc('month', n.cree_le) AS mois,
           AVG((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0) AS moyenne,
           COUNT(*) AS nb
    FROM public.notations_missions n
    WHERE n.note_id = v_target_id
      AND n.sens = v_target_sens
      AND n.masque = false
      AND n.cree_le > now() - INTERVAL '6 months'
    GROUP BY 1
  ) x;

  -- Liste étabs ayant évalué le soignant (pour dropdown filtre)
  -- (uniquement pour sens ETAB_VERS_SOIGNANT, sinon liste les soignants — moins pertinent côté soignant)
  IF v_target_sens = 'ETAB_VERS_SOIGNANT' THEN
    SELECT COALESCE(jsonb_agg(DISTINCT jsonb_build_object('id', e.id, 'nom', e.nom)), '[]'::jsonb)
    INTO v_etabs_disponibles
    FROM public.notations_missions n
    JOIN public.missions m ON m.id = n.mission_id
    JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE n.note_id = v_target_id AND n.sens = v_target_sens AND n.masque = false;
  ELSE
    v_etabs_disponibles := '[]'::jsonb;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'total', v_total,
    'limit', v_limit,
    'offset', p_offset,
    'notations', v_notations,
    'stats', v_stats,
    'evolution_6m', v_evolution,
    'etabs_disponibles', v_etabs_disponibles
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_messagerie_cleanup_periodique()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_typing_supprimes int;
  v_away_marques int;
  v_offline_marques int;
BEGIN
  WITH supp AS (
    DELETE FROM typing_status
    WHERE started_at < NOW() - INTERVAL '5 seconds'
    RETURNING 1
  )
  SELECT count(*) INTO v_typing_supprimes FROM supp;

  WITH upd AS (
    UPDATE presence_status
    SET status = 'AWAY', maj_le = NOW()
    WHERE status = 'ONLINE'
      AND last_seen_at < NOW() - INTERVAL '1 minute'
      AND last_seen_at >= NOW() - INTERVAL '15 minutes'
    RETURNING 1
  )
  SELECT count(*) INTO v_away_marques FROM upd;

  WITH upd AS (
    UPDATE presence_status
    SET status = 'OFFLINE', maj_le = NOW()
    WHERE status IN ('ONLINE', 'AWAY')
      AND last_seen_at < NOW() - INTERVAL '15 minutes'
    RETURNING 1
  )
  SELECT count(*) INTO v_offline_marques FROM upd;

  RETURN jsonb_build_object(
    'typing_supprimes', v_typing_supprimes,
    'away_marques', v_away_marques,
    'offline_marques', v_offline_marques,
    'execute_le', NOW()
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mes_matches()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant_id uuid := auth.uid();
  v_matches jsonb;
  v_total_swipes integer;
  v_total_likes integer;
  v_total_matches integer;
  v_taux_match numeric;
BEGIN
  IF v_soignant_id IS NULL THEN
    RETURN jsonb_build_object('error', 'auth_required');
  END IF;

  SELECT count(*) INTO v_total_swipes FROM public.swipes WHERE soignant_id = v_soignant_id;
  SELECT count(*) INTO v_total_likes FROM public.swipes
   WHERE soignant_id = v_soignant_id AND direction IN ('LIKE', 'SUPER_LIKE');

  -- Un "match" = candidature issue d'un like/super-like qui a été ACCEPTÉE par l'étab.
  -- (Auparavant le filtre testait des statuts de MISSION — ASSIGNEE/EN_COURS/TERMINEE —
  --  qu'une candidature ne prend jamais : la page était donc toujours vide.)
  SELECT COALESCE(jsonb_agg(payload ORDER BY (payload->>'updated_at') DESC), '[]'::jsonb)
    INTO v_matches
    FROM (
      SELECT jsonb_build_object(
        'candidature_id', c.id,
        'mission_id', m.id,
        'mission_intitule', m.intitule,
        'mission_debut_le', m.debut_le,
        'mission_fin_le', m.fin_le,
        'mission_taux_horaire_base', m.taux_horaire_base,
        'mission_statut', m.statut,
        'etablissement_id', m.etablissement_id,
        'etablissement_nom', e.nom,
        'etablissement_ville', e.adresse_ville,
        'swipe_direction', s.direction,
        'candidature_statut', c.statut,
        'updated_at', GREATEST(COALESCE(c.acceptee_a, c.traite_le, c.cree_le), s.created_at)
      ) AS payload
        FROM public.candidatures c
        JOIN public.missions m ON m.id = c.mission_id
        JOIN public.etablissements e ON e.id = m.etablissement_id
        JOIN public.swipes s ON s.soignant_id = c.soignant_id AND s.mission_id = c.mission_id
       WHERE c.soignant_id = v_soignant_id
         AND s.direction IN ('LIKE', 'SUPER_LIKE')
         AND c.statut = 'ACCEPTEE'
    ) t;

  v_total_matches := COALESCE(jsonb_array_length(v_matches), 0);
  v_taux_match := CASE
    WHEN v_total_likes > 0 THEN round((v_total_matches::numeric / v_total_likes) * 100, 1)
    ELSE 0
  END;

  RETURN jsonb_build_object(
    'matches', v_matches,
    'stats', jsonb_build_object(
      'total_swipes', v_total_swipes,
      'total_likes', v_total_likes,
      'total_matches', v_total_matches,
      'taux_match', v_taux_match
    )
  );
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_missions_publiques_etablissement(p_etablissement_id uuid)
 RETURNS TABLE(id uuid, intitule text, profession_requise type_profession, debut_le timestamp with time zone, fin_le timestamp with time zone, taux_horaire_base numeric, service text, nom_etablissement text, ville_etablissement text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT 
    m.id,
    m.intitule,
    m.profession_requise,
    m.debut_le,
    m.fin_le,
    m.taux_horaire_base,
    m.service,
    e.nom,
    e.adresse_ville
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE m.etablissement_id = p_etablissement_id
    AND m.statut = 'OUVERTE'
    AND e.supprime_le IS NULL
  ORDER BY m.debut_le
  LIMIT 10;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mode_paiement_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD; v_connect_actif BOOLEAN; v_rib_partage BOOLEAN;
BEGIN
    SELECT m.*, s.type_exercice, s.iban_last4 AS soignant_iban_last4
    INTO v_mission FROM missions m JOIN soignants s ON s.id = m.soignant_assigne_id WHERE m.id = p_mission_id;
    IF v_mission IS NULL THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;

    -- ★ OWNERSHIP CHECK: seul l'étab de la mission, le soignant assigné, ou admin
    IF v_mission.etablissement_id != mon_etablissement_id() 
       AND v_mission.soignant_assigne_id != auth.uid()
       AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    v_connect_actif := v_mission.type_exercice IN ('LIBERAL','MIXTE') AND fn_soignant_stripe_connect_actif(v_mission.soignant_assigne_id);
    v_rib_partage := EXISTS(SELECT 1 FROM partages_rib WHERE mission_id = p_mission_id AND actif = TRUE AND (expire_le IS NULL OR expire_le > NOW()));

    RETURN jsonb_build_object(
        'mode_recommande', CASE
            WHEN v_connect_actif THEN 'STRIPE_CONNECT'
            WHEN v_mission.type_exercice IN ('LIBERAL','MIXTE') THEN 'VIREMENT_NOTE_HONORAIRES'
            ELSE 'VIREMENT_PAIE'
        END,
        'type_exercice', v_mission.type_exercice,
        'stripe_connect_actif', v_connect_actif,
        'rib_partage', v_rib_partage,
        'iban_last4', v_mission.soignant_iban_last4,
        'montant_soignant', v_mission.net_a_payer,
        'total_brut', v_mission.total_brut,
        'net_estime', v_mission.net_estime,
        'commission_ht', v_mission.montant_commission_ht,
        'commission_ttc', v_mission.montant_commission_ttc,
        'total', COALESCE(v_mission.net_a_payer, 0) + COALESCE(v_mission.montant_commission_ttc, 0)
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_missions_publiques_recherche(p_profession text DEFAULT NULL::text, p_ville text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, intitule text, profession_requise text, ville text, code_postal text, debut_le timestamp with time zone, fin_le timestamp with time zone, taux_horaire_base numeric, est_urgente boolean, type_contrat_recherche text, total_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_soignant_id UUID;
    v_type_exercice TEXT;
BEGIN
    v_soignant_id := auth.uid();
    SELECT s.type_exercice INTO v_type_exercice FROM soignants s WHERE s.id = v_soignant_id;
    RETURN QUERY
    WITH filtered AS (
        SELECT m.id AS mid, m.intitule AS mintitule, m.profession_requise::TEXT AS mprof,
            e.adresse_ville::TEXT AS mville, e.adresse_code_postal::TEXT AS mcp,
            m.debut_le AS mdebut, m.fin_le AS mfin, m.taux_horaire_base AS mtaux,
            COALESCE(m.est_urgente, FALSE) AS murgente, m.type_contrat_recherche::TEXT AS mcontrat, m.cree_le AS mcree
        FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
        WHERE m.statut = 'OUVERTE' AND m.debut_le > NOW() AND e.supprime_le IS NULL
          AND m.intitule NOT LIKE '[%'  -- exclut les missions de test E2E
          AND (p_profession IS NULL OR BTRIM(p_profession) = '' OR m.profession_requise::TEXT = BTRIM(p_profession))
          AND (p_ville IS NULL OR BTRIM(p_ville) = '' OR e.adresse_ville ILIKE '%' || BTRIM(p_ville) || '%' OR e.adresse_code_postal LIKE BTRIM(p_ville) || '%')
          AND (v_soignant_id IS NULL OR NOT fn_est_exclu(v_soignant_id, m.etablissement_id))
          AND (m.type_contrat_recherche = 'TOUS' OR v_type_exercice IS NULL OR v_type_exercice = 'MIXTE'
              OR (m.type_contrat_recherche = 'SALARIE' AND v_type_exercice IN ('SALARIE', 'MIXTE'))
              OR (m.type_contrat_recherche = 'LIBERAL' AND v_type_exercice IN ('LIBERAL', 'MIXTE')))
    ), counted AS (SELECT COUNT(*)::BIGINT AS cnt FROM filtered)
    SELECT f.mid, f.mintitule, f.mprof, f.mville, f.mcp, f.mdebut, f.mfin, f.mtaux, f.murgente, f.mcontrat, c.cnt
    FROM filtered f CROSS JOIN counted c
    ORDER BY f.murgente DESC, f.mcree DESC;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_modifier_filtre_sauvegarde(p_id uuid, p_nom text DEFAULT NULL::text, p_alerte_active boolean DEFAULT NULL::boolean, p_frequence_alerte filtre_frequence_alerte DEFAULT NULL::filtre_frequence_alerte)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_old RECORD;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;

  SELECT * INTO v_old FROM filtres_sauvegardes WHERE id = p_id AND utilisateur_id = v_uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Filtre introuvable'); END IF;

  IF p_nom IS NOT NULL AND (length(p_nom) = 0 OR length(p_nom) > 100) THEN
    RETURN jsonb_build_object('error','Nom invalide (1-100 caractères)');
  END IF;

  UPDATE filtres_sauvegardes SET
    nom = COALESCE(p_nom, nom),
    alerte_active = COALESCE(p_alerte_active, alerte_active),
    frequence_alerte = COALESCE(p_frequence_alerte, frequence_alerte)
  WHERE id = p_id;

  PERFORM fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
    p_action := 'FILTRE_MODIFIE', p_type_ressource := 'filtre_sauvegarde',
    p_id_ressource := p_id,
    p_details := jsonb_build_object(
      'nom_avant', v_old.nom, 'nom_apres', COALESCE(p_nom, v_old.nom),
      'alerte_active_avant', v_old.alerte_active,
      'alerte_active_apres', COALESCE(p_alerte_active, v_old.alerte_active),
      'frequence_avant', v_old.frequence_alerte::text,
      'frequence_apres', COALESCE(p_frequence_alerte, v_old.frequence_alerte)::text
    )
  );

  -- Audit toggle alerte
  IF p_alerte_active IS NOT NULL AND p_alerte_active <> v_old.alerte_active THEN
    PERFORM fn_ecrire_audit_safe(
      p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
      p_action := CASE WHEN p_alerte_active THEN 'ALERTE_ACTIVEE' ELSE 'ALERTE_DESACTIVEE' END,
      p_type_ressource := 'filtre_sauvegarde', p_id_ressource := p_id,
      p_details := jsonb_build_object('frequence', COALESCE(p_frequence_alerte, v_old.frequence_alerte)::text)
    );
  END IF;

  RETURN jsonb_build_object('success', true);
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'Un filtre avec ce nom existe déjà');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mission_est_de_nuit(p_debut timestamp with time zone, p_fin timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE v_heures_nuit numeric := 0; v_curseur timestamptz; v_curseur_fin timestamptz; v_h_debut int;
BEGIN
  v_curseur := p_debut;
  WHILE v_curseur < p_fin LOOP
    v_curseur_fin := LEAST(v_curseur + INTERVAL '30 minutes', p_fin);
    v_h_debut := EXTRACT(HOUR FROM v_curseur)::int;
    IF v_h_debut >= 21 OR v_h_debut < 6 THEN
      v_heures_nuit := v_heures_nuit + EXTRACT(EPOCH FROM (v_curseur_fin - v_curseur)) / 3600.0;
    END IF;
    v_curseur := v_curseur_fin;
  END LOOP;
  RETURN v_heures_nuit >= 3.0;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mission_publique(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT to_jsonb(t) FROM (
    SELECT m.id, m.intitule, left(coalesce(m.description, ''), 1500) AS description,
           m.profession_requise::text, m.debut_le, m.fin_le, m.taux_horaire_base,
           m.est_urgente, m.service,
           e.nom AS etablissement_nom, e.type::text AS etablissement_type,
           e.adresse_ville::text AS ville, e.adresse_code_postal::text AS code_postal
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.id = p_id AND m.statut = 'OUVERTE'
  ) t;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_missions_ouvertes_sitemap()
 RETURNS TABLE(id uuid, maj timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT m.id, greatest(m.cree_le, coalesce(m.modifie_le, m.cree_le)) AS maj
  FROM missions m WHERE m.statut = 'OUVERTE'
  ORDER BY m.cree_le DESC LIMIT 2000;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_missions_terminees_a_remercier()
 RETURNS TABLE(mission_id uuid, soignant_id uuid, soignant_prenom text, soignant_email text, etab_email text, etab_nom text, code_parrainage text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT m.id, s.id, s.prenom::text, s.email::text, e.email_contact::text, e.nom::text, s.code_parrainage::text
  FROM missions m
  JOIN soignants s ON s.id = m.soignant_assigne_id
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE m.statut = 'TERMINEE'
    AND coalesce(m.terminee_le, m.modifie_le) > now() - interval '2 days'
    AND NOT EXISTS (SELECT 1 FROM emails_post_mission ep WHERE ep.mission_id = m.id AND ep.cible = 'SOIGNANT')
  LIMIT 100;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_modifier_mission_etablissement(p_mission_id uuid, p_intitule text, p_description text DEFAULT NULL::text, p_service text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission missions%ROWTYPE;
BEGIN
  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id AND etablissement_id = mon_etablissement_id();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable ou accès refusé.');
  END IF;

  IF v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Seules les missions ouvertes peuvent être modifiées.');
  END IF;

  IF p_intitule IS NULL OR length(trim(p_intitule)) < 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'L''intitulé doit contenir au moins 3 caractères.');
  END IF;

  UPDATE missions SET
    intitule = trim(p_intitule),
    description = p_description,
    service = p_service,
    modifie_le = now()
  WHERE id = p_mission_id;

  PERFORM fn_ecrire_audit_safe(
    auth.uid(), 'ADMIN_ETABLISSEMENT', 'MISSION_MODIFICATION',
    'mission', p_mission_id, NULL,
    jsonb_build_object('intitule', p_intitule, 'service', p_service),
    NULL, NULL
  );

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_modifier_mon_etablissement(p_nom text DEFAULT NULL::text, p_finess text DEFAULT NULL::text, p_adresse_rue text DEFAULT NULL::text, p_adresse_ville text DEFAULT NULL::text, p_adresse_code_postal text DEFAULT NULL::text, p_adresse_departement text DEFAULT NULL::text, p_email_contact text DEFAULT NULL::text, p_telephone text DEFAULT NULL::text, p_adresse_lat numeric DEFAULT NULL::numeric, p_adresse_lng numeric DEFAULT NULL::numeric, p_taux_majoration_nuit numeric DEFAULT NULL::numeric, p_taux_majoration_dimanche numeric DEFAULT NULL::numeric, p_taux_majoration_ferie numeric DEFAULT NULL::numeric, p_couleur_theme text DEFAULT NULL::text, p_convention_collective text DEFAULT NULL::text, p_mode_paiement_commission text DEFAULT NULL::text, p_logo_url text DEFAULT NULL::text, p_contrat_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_ip inet;
    v_user_agent text;
    v_headers jsonb;
    v_champs_modifies jsonb := '[]'::jsonb;
BEGIN
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN '{"error":"Établissement non trouvé"}'::JSONB;
    END IF;

    -- Validation couleur hex
    IF p_couleur_theme IS NOT NULL AND p_couleur_theme !~ '^#[0-9a-fA-F]{6}$' THEN
        RETURN '{"error":"Couleur invalide (format #RRGGBB)"}'::JSONB;
    END IF;

    UPDATE etablissements SET
        nom = COALESCE(p_nom, nom),
        finess = COALESCE(p_finess, finess),
        adresse_rue = COALESCE(p_adresse_rue, adresse_rue),
        adresse_ville = COALESCE(p_adresse_ville, adresse_ville),
        adresse_code_postal = COALESCE(p_adresse_code_postal, adresse_code_postal),
        adresse_departement = COALESCE(p_adresse_departement, adresse_departement),
        email_contact = COALESCE(p_email_contact, email_contact),
        telephone_contact = COALESCE(p_telephone, telephone_contact),
        adresse_lat = COALESCE(p_adresse_lat, adresse_lat),
        adresse_lng = COALESCE(p_adresse_lng, adresse_lng),
        taux_majoration_nuit_pourcent = COALESCE(p_taux_majoration_nuit, taux_majoration_nuit_pourcent),
        taux_majoration_dimanche_pourcent = COALESCE(p_taux_majoration_dimanche, taux_majoration_dimanche_pourcent),
        taux_majoration_ferie_pourcent = COALESCE(p_taux_majoration_ferie, taux_majoration_ferie_pourcent),
        couleur_theme = COALESCE(p_couleur_theme, couleur_theme),
        convention_collective = COALESCE(p_convention_collective, convention_collective),
        mode_paiement_commission = COALESCE(p_mode_paiement_commission, mode_paiement_commission),
        logo_url = COALESCE(p_logo_url, logo_url),
        contrat_url = COALESCE(p_contrat_url, contrat_url),
        contrat_uploade_le = CASE WHEN p_contrat_url IS NOT NULL THEN NOW() ELSE contrat_uploade_le END,
        modifie_le = NOW()
    WHERE id = v_etab_id;

    -- Audit RGPD
    BEGIN
      v_headers := current_setting('request.headers', true)::jsonb;
      v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
      v_user_agent := NULLIF(v_headers->>'user-agent', '');
    EXCEPTION WHEN OTHERS THEN
      v_ip := NULL; v_user_agent := NULL;
    END;

    IF p_nom IS NOT NULL OR p_finess IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"identite"'::jsonb; END IF;
    IF p_adresse_rue IS NOT NULL OR p_adresse_ville IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"adresse"'::jsonb; END IF;
    IF p_email_contact IS NOT NULL OR p_telephone IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"contact"'::jsonb; END IF;
    IF p_taux_majoration_nuit IS NOT NULL OR p_taux_majoration_dimanche IS NOT NULL OR p_taux_majoration_ferie IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"taux_majoration"'::jsonb; END IF;
    IF p_convention_collective IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"convention_collective"'::jsonb; END IF;

    PERFORM fn_ecrire_audit(
      auth.uid(), 'ADMIN_ETABLISSEMENT', 'ETABLISSEMENT_MODIFICATION',
      'etablissement', v_etab_id, NULL,
      jsonb_build_object('champs_modifies', v_champs_modifies),
      v_ip, v_user_agent
    );

    RETURN '{"success":true}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_modifier_reference_paiement(p_paiement_id uuid, p_nouvelle_reference text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_paiement RECORD;
    v_ref TEXT;
BEGIN
    SELECT * INTO v_paiement FROM paiements_soignant WHERE id = p_paiement_id;
    IF v_paiement IS NULL THEN RETURN jsonb_build_object('error', 'Paiement introuvable'); END IF;
    
    IF v_paiement.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé'); 
    END IF;
    
    -- Seul un paiement DECLARE (non confirmé par le soignant) peut être modifié
    IF v_paiement.statut != 'DECLARE' THEN
        RETURN jsonb_build_object('error', 'Ce paiement ne peut plus être modifié (statut: ' || v_paiement.statut || ').');
    END IF;
    IF v_paiement.confirme_par_soignant = TRUE THEN
        RETURN jsonb_build_object('error', 'Le soignant a déjà confirmé ce paiement.');
    END IF;
    
    -- Validation référence
    v_ref := TRIM(COALESCE(p_nouvelle_reference, ''));
    IF LENGTH(v_ref) < 5 THEN
        RETURN jsonb_build_object('error', 'La référence doit contenir au moins 5 caractères.');
    END IF;
    IF v_ref !~ '[0-9]' THEN
        RETURN jsonb_build_object('error', 'La référence doit contenir au moins un chiffre.');
    END IF;
    
    UPDATE paiements_soignant SET reference_virement = v_ref, modifie_le = NOW()
    WHERE id = p_paiement_id;
    
    -- Notifier le soignant du changement
    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_paiement.soignant_id, 'SYSTEM', 'Référence de paiement modifiée',
        'La référence du paiement a été mise à jour : ' || v_ref,
        '/soignant/mes-gains', 'SOIGNANT');
    
    RETURN jsonb_build_object('success', TRUE, 'nouvelle_reference', v_ref);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_modifier_mon_profil(p_prenom text DEFAULT NULL::text, p_nom text DEFAULT NULL::text, p_telephone text DEFAULT NULL::text, p_date_naissance date DEFAULT NULL::date, p_adresse_rue text DEFAULT NULL::text, p_adresse_ville text DEFAULT NULL::text, p_adresse_code_postal text DEFAULT NULL::text, p_adresse_lat numeric DEFAULT NULL::numeric, p_adresse_lng numeric DEFAULT NULL::numeric, p_rayon_deplacement_km integer DEFAULT NULL::integer, p_numero_rpps text DEFAULT NULL::text, p_numero_adeli text DEFAULT NULL::text, p_avatar_url text DEFAULT NULL::text, p_types_contrat text[] DEFAULT NULL::text[], p_bio text DEFAULT NULL::text, p_annees_experience integer DEFAULT NULL::integer, p_specialites text[] DEFAULT NULL::text[], p_taux_horaire_minimum numeric DEFAULT NULL::numeric, p_type_exercice text DEFAULT NULL::text, p_ville_recherche text DEFAULT NULL::text, p_ville_urgence text DEFAULT NULL::text, p_disponible_urgence boolean DEFAULT NULL::boolean, p_urgence_rayon_km integer DEFAULT NULL::integer, p_attestation_cumul_activite boolean DEFAULT NULL::boolean, p_est_cumul_activite boolean DEFAULT NULL::boolean, p_est_salarie_etablissement boolean DEFAULT NULL::boolean, p_consentement_gps boolean DEFAULT NULL::boolean, p_types_contrat_acceptes text DEFAULT NULL::text, p_profession text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_ip inet;
  v_user_agent text;
  v_headers jsonb;
  v_champs_modifies jsonb := '[]'::jsonb;
  v_existe boolean;
  v_email text;
BEGIN
    IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;

    PERFORM set_config('jolene.rpc_update', 'true', true);

    SELECT EXISTS(SELECT 1 FROM soignants WHERE id = v_uid) INTO v_existe;

    IF NOT v_existe THEN
      SELECT email INTO v_email FROM auth.users WHERE id = v_uid;
      INSERT INTO soignants (
        id, email, prenom, nom, telephone, date_naissance,
        numero_rpps, numero_adeli, profession
      )
      VALUES (
        v_uid,
        COALESCE(v_email, 'inconnu@jolene.app'),
        COALESCE(p_prenom, ''),
        COALESCE(p_nom, ''),
        p_telephone,
        p_date_naissance,
        p_numero_rpps,
        p_numero_adeli,
        CASE WHEN p_profession IS NOT NULL THEN p_profession::type_profession ELSE NULL END
      );
    END IF;

    UPDATE soignants SET
        prenom = CASE
            WHEN identite_verifiee = TRUE THEN prenom
            ELSE COALESCE(p_prenom, prenom)
        END,
        nom = CASE
            WHEN identite_verifiee = TRUE THEN nom
            ELSE COALESCE(p_nom, nom)
        END,
        profession = CASE
            -- Profession verrouillée une fois définie (vérifiée RPPS ou choisie).
            -- Premier set autorisé via le wizard quand profession est NULL.
            WHEN profession IS NOT NULL THEN profession
            WHEN p_profession IS NOT NULL THEN p_profession::type_profession
            ELSE NULL
        END,
        telephone = COALESCE(p_telephone, telephone),
        date_naissance = COALESCE(p_date_naissance, date_naissance),
        adresse_rue = COALESCE(p_adresse_rue, adresse_rue),
        adresse_ville = COALESCE(p_adresse_ville, adresse_ville),
        adresse_code_postal = COALESCE(p_adresse_code_postal, adresse_code_postal),
        adresse_lat = COALESCE(p_adresse_lat, adresse_lat),
        adresse_lng = COALESCE(p_adresse_lng, adresse_lng),
        rayon_deplacement_km = COALESCE(p_rayon_deplacement_km, rayon_deplacement_km),
        numero_rpps = CASE
            WHEN rpps_verifie = TRUE THEN numero_rpps
            ELSE COALESCE(p_numero_rpps, numero_rpps)
        END,
        numero_adeli = COALESCE(p_numero_adeli, numero_adeli),
        avatar_url = COALESCE(p_avatar_url, avatar_url),
        types_contrat_acceptes = CASE
            WHEN p_types_contrat_acceptes IS NOT NULL THEN p_types_contrat_acceptes
            WHEN p_types_contrat IS NOT NULL THEN array_to_string(p_types_contrat, ',')
            ELSE types_contrat_acceptes END,
        bio = COALESCE(p_bio, bio),
        annees_experience = COALESCE(p_annees_experience, annees_experience),
        specialites = COALESCE(p_specialites, specialites),
        taux_horaire_minimum = COALESCE(p_taux_horaire_minimum, taux_horaire_minimum),
        type_exercice = COALESCE(p_type_exercice, type_exercice),
        ville_recherche = COALESCE(p_ville_recherche, ville_recherche),
        ville_urgence = COALESCE(p_ville_urgence, ville_urgence),
        disponible_urgence = COALESCE(p_disponible_urgence, disponible_urgence),
        urgence_rayon_km = COALESCE(p_urgence_rayon_km, urgence_rayon_km),
        attestation_cumul_activite = COALESCE(p_attestation_cumul_activite, attestation_cumul_activite),
        est_cumul_activite = COALESCE(p_est_cumul_activite, est_cumul_activite),
        est_salarie_etablissement = COALESCE(p_est_salarie_etablissement, est_salarie_etablissement),
        consentement_gps = COALESCE(p_consentement_gps, consentement_gps),
        attestation_cumul_le = CASE WHEN p_attestation_cumul_activite = TRUE THEN NOW() ELSE attestation_cumul_le END,
        consentement_gps_le = CASE WHEN p_consentement_gps IS NOT NULL THEN NOW() ELSE consentement_gps_le END,
        modifie_le = NOW()
    WHERE id = v_uid;

    BEGIN
      v_headers := current_setting('request.headers', true)::jsonb;
      v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
      v_user_agent := NULLIF(v_headers->>'user-agent', '');
    EXCEPTION WHEN OTHERS THEN
      v_ip := NULL; v_user_agent := NULL;
    END;

    IF p_prenom IS NOT NULL OR p_nom IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"identite"'::jsonb; END IF;
    IF p_telephone IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"telephone"'::jsonb; END IF;
    IF p_date_naissance IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"date_naissance"'::jsonb; END IF;
    IF p_adresse_rue IS NOT NULL OR p_adresse_ville IS NOT NULL OR p_adresse_lat IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"adresse"'::jsonb; END IF;
    IF p_numero_rpps IS NOT NULL OR p_numero_adeli IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"identifiants_professionnels"'::jsonb; END IF;
    IF p_type_exercice IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"type_exercice"'::jsonb; END IF;
    IF p_consentement_gps IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"consentement_gps"'::jsonb; END IF;
    IF p_profession IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"profession"'::jsonb; END IF;

    BEGIN
      PERFORM fn_ecrire_audit(
        v_uid, 'SOIGNANT', 'MODIFICATION_PROFIL',
        'soignant', v_uid, NULL,
        jsonb_build_object('champs_modifies', v_champs_modifies),
        v_ip, v_user_agent
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    RETURN jsonb_build_object('success', TRUE);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_modifier_mon_nir(p_nir text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  RETURN fn_maj_nir_soignant(p_nir);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_modifier_preferences_notifications(p_canal_email boolean DEFAULT NULL::boolean, p_canal_sms boolean DEFAULT NULL::boolean, p_canal_push boolean DEFAULT NULL::boolean, p_canal_in_app boolean DEFAULT NULL::boolean, p_par_evenement jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_item jsonb;
  v_old jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;

  -- UPSERT global
  INSERT INTO preferences_notifications (utilisateur_id, canal_email, canal_sms, canal_push, canal_in_app)
  VALUES (v_uid,
          COALESCE(p_canal_email, true),
          COALESCE(p_canal_sms, false),
          COALESCE(p_canal_push, true),
          COALESCE(p_canal_in_app, true))
  ON CONFLICT (utilisateur_id) DO UPDATE
    SET canal_email = COALESCE(p_canal_email, preferences_notifications.canal_email),
        canal_sms = COALESCE(p_canal_sms, preferences_notifications.canal_sms),
        canal_push = COALESCE(p_canal_push, preferences_notifications.canal_push),
        canal_in_app = COALESCE(p_canal_in_app, preferences_notifications.canal_in_app);

  -- UPSERT par événement
  IF p_par_evenement IS NOT NULL THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_par_evenement)
    LOOP
      INSERT INTO preferences_notifications_par_evenement
        (utilisateur_id, type_evenement, canal, actif)
      VALUES (v_uid,
              (v_item->>'type_evenement')::public.type_evenement_notification,
              (v_item->>'canal')::public.canal_notification,
              (v_item->>'actif')::boolean)
      ON CONFLICT (utilisateur_id, type_evenement, canal) DO UPDATE
        SET actif = EXCLUDED.actif;
    END LOOP;
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
    p_action := 'PREFERENCE_NOTIFICATION_MODIFIEE',
    p_type_ressource := 'preferences', p_id_ressource := v_uid,
    p_details := jsonb_build_object('canaux',
      jsonb_build_object('email',p_canal_email,'sms',p_canal_sms,'push',p_canal_push,'in_app',p_canal_in_app),
      'par_evenement', p_par_evenement)
  );

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_modifier_notation_mission(p_notation_id uuid, p_critere_1 integer, p_critere_2 integer, p_critere_3 integer, p_critere_4 integer, p_commentaire text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_notation RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF p_critere_1 NOT BETWEEN 1 AND 5 OR p_critere_2 NOT BETWEEN 1 AND 5
     OR p_critere_3 NOT BETWEEN 1 AND 5 OR p_critere_4 NOT BETWEEN 1 AND 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Critères doivent être entre 1 et 5');
  END IF;

  IF p_commentaire IS NOT NULL AND LENGTH(p_commentaire) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Commentaire max 2000 caractères');
  END IF;

  SELECT * INTO v_notation FROM notations_missions WHERE id = p_notation_id;
  IF v_notation IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Notation introuvable');
  END IF;

  IF NOT est_admin() THEN
    IF v_notation.notateur_id NOT IN (v_uid, COALESCE(v_etab_id, '00000000-0000-0000-0000-000000000000'::uuid)) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
    END IF;
  END IF;

  IF v_notation.cree_le < NOW() - INTERVAL '7 days' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Notation non modifiable après 7 jours');
  END IF;

  UPDATE notations_missions SET
    critere_1 = p_critere_1, critere_2 = p_critere_2,
    critere_3 = p_critere_3, critere_4 = p_critere_4,
    commentaire = NULLIF(TRIM(p_commentaire), ''),
    mis_a_jour_le = NOW()
  WHERE id = p_notation_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_notation.notateur_id,
    p_type_acteur := CASE WHEN v_notation.sens = 'ETAB_VERS_SOIGNANT' THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'NOTATION_DONNEE',
    p_type_ressource := 'mission',
    p_id_ressource := v_notation.mission_id,
    p_details := jsonb_build_object('notation_id', p_notation_id, 'sens', v_notation.sens::text, 'modification', true)
  );

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_modifier_horaires_presence(p_presence_id uuid, p_pointage_arrivee_le timestamp with time zone, p_pointage_depart_le timestamp with time zone, p_motif text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_presence RECORD;
  v_duree_min int;
BEGIN
  SELECT * INTO v_presence FROM public.presences WHERE id = p_presence_id;
  IF v_presence IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Presence introuvable');
  END IF;

  IF p_pointage_depart_le <= p_pointage_arrivee_le THEN
    RETURN jsonb_build_object('success', false, 'error', 'Heure départ doit être après arrivée');
  END IF;

  v_duree_min := EXTRACT(EPOCH FROM (p_pointage_depart_le - p_pointage_arrivee_le)) / 60;

  UPDATE public.presences SET
    pointage_arrivee_le = p_pointage_arrivee_le,
    pointage_depart_le = p_pointage_depart_le,
    duree_brute_min = v_duree_min,
    duree_nette_min = v_duree_min - COALESCE(duree_pause_min, 0),
    modifie_le = NOW()
  WHERE id = p_presence_id;

  RETURN jsonb_build_object(
    'success', true,
    'presence_id', p_presence_id,
    'nouvelle_duree_min', v_duree_min,
    'duree_h', ROUND(v_duree_min::numeric / 60, 2)
  );
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_modifier_tva_liberal(p_assujetti_tva boolean, p_numero_tva text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ancien_assujetti BOOLEAN;
  v_ancien_numero TEXT;
  v_ip inet;
  v_user_agent text;
  v_headers jsonb;
BEGIN
  -- Validation : si assujetti, le numéro de TVA est obligatoire
  IF p_assujetti_tva AND (p_numero_tva IS NULL OR length(trim(p_numero_tva)) = 0) THEN
    RETURN jsonb_build_object('error', 'Numéro de TVA intracommunautaire requis si vous êtes assujetti.');
  END IF;

  -- Validation format TVA intracommunautaire français (FRxx + 9-11 chiffres)
  IF p_assujetti_tva AND p_numero_tva IS NOT NULL AND trim(p_numero_tva) !~ '^FR[0-9A-Z]{2}[0-9]{9}$' THEN
    RETURN jsonb_build_object('error', 'Format de TVA invalide. Attendu : FRxx suivi de 9 chiffres (ex. FR12345678901).');
  END IF;

  SELECT assujetti_tva, numero_tva INTO v_ancien_assujetti, v_ancien_numero
  FROM soignants WHERE id = auth.uid();

  UPDATE soignants
  SET assujetti_tva = p_assujetti_tva,
      numero_tva = CASE WHEN p_assujetti_tva THEN trim(p_numero_tva) ELSE NULL END,
      modifie_le = now()
  WHERE id = auth.uid();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Soignant introuvable');
  END IF;

  BEGIN
    v_headers := current_setting('request.headers', true)::jsonb;
    v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
    v_user_agent := NULLIF(v_headers->>'user-agent', '');
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL; v_user_agent := NULL;
  END;

  PERFORM fn_ecrire_audit(
    auth.uid(), 'SOIGNANT', 'TVA_MODIFICATION',
    'soignant', auth.uid(), NULL,
    jsonb_build_object(
      'ancien_assujetti', v_ancien_assujetti,
      'nouveau_assujetti', p_assujetti_tva,
      'ancien_numero', v_ancien_numero,
      'nouveau_numero', CASE WHEN p_assujetti_tva THEN trim(p_numero_tva) ELSE NULL END
    ),
    v_ip, v_user_agent
  );

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mon_bfa()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_groupe_id UUID;
    v_bfa_eligible BOOLEAN;
    v_result JSONB;
BEGIN
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    -- Trouver le groupe de l'établissement
    SELECT groupe_sante_id INTO v_groupe_id FROM etablissements WHERE id = v_etab_id;
    
    IF v_groupe_id IS NULL THEN
        RETURN jsonb_build_object('eligible', false, 'raison', 'Votre établissement ne fait pas partie d''un groupe de santé');
    END IF;

    -- Vérifier si le groupe a signé un contrat BFA
    SELECT bfa_eligible INTO v_bfa_eligible FROM groupes_sante WHERE id = v_groupe_id;
    
    IF NOT COALESCE(v_bfa_eligible, FALSE) THEN
        RETURN jsonb_build_object('eligible', false, 'raison', 'Le BFA n''est pas activé pour votre groupe');
    END IF;

    -- Retourner les infos BFA
    SELECT jsonb_build_object(
        'eligible', true,
        'groupe_nom', g.nom,
        'annee', b.annee,
        'missions_cumulees', b.missions_cumulees,
        'commissions_cumulees', b.commissions_cumulees,
        'palier_bfa', b.palier_bfa,
        'taux_bfa', b.taux_bfa,
        'montant_bfa', b.montant_bfa,
        'bfa_verse', b.bfa_verse,
        'calcule_le', b.calcule_le
    ) INTO v_result
    FROM bfa_suivi b
    JOIN groupes_sante g ON g.id = b.groupe_id
    WHERE b.groupe_id = v_groupe_id AND b.annee = EXTRACT(YEAR FROM NOW())
    ORDER BY b.calcule_le DESC LIMIT 1;

    RETURN COALESCE(v_result, jsonb_build_object('eligible', true, 'palier_bfa', 'AUCUN', 'missions_cumulees', 0, 'montant_bfa', 0));
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mon_contrat_plateforme()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_etab RECORD;
BEGIN
    IF v_etab_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT contrat_valide, contrat_url, contrat_uploade_le, nom, siret, taux_commission_negocie
    INTO v_etab FROM etablissements WHERE id = v_etab_id;

    IF v_etab IS NULL THEN RETURN NULL; END IF;

    RETURN jsonb_build_object(
        'contrat_valide', COALESCE(v_etab.contrat_valide, false),
        'contrat_url', v_etab.contrat_url,
        'contrat_uploade_le', v_etab.contrat_uploade_le,
        'nom', v_etab.nom,
        'siret', v_etab.siret,
        'taux_commission_negocie', COALESCE(v_etab.taux_commission_negocie, 15)
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mon_breakdown_actuel()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_result JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  SELECT to_jsonb(b.*) INTO v_result FROM scoring_breakdown b
  WHERE b.soignant_id = v_uid ORDER BY b.cree_le DESC LIMIT 1;
  RETURN COALESCE(v_result, '{}'::jsonb);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mon_etab_alerte_cddu(p_soignant_id uuid, p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id UUID := mon_etablissement_id();
BEGIN
  IF NOT est_admin() AND v_etab_id IS DISTINCT FROM p_etablissement_id THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  RETURN public.fn_alerte_cddu_repetitif(p_soignant_id, p_etablissement_id);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_modifier_type_contrat_mission(p_mission_id uuid, p_type_contrat text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_etab_id uuid;
  v_ancien text;
BEGIN
  SELECT etablissement_id, type_contrat_recherche INTO v_etab_id, v_ancien
  FROM public.missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF NOT est_admin() AND v_etab_id IS DISTINCT FROM mon_etablissement_id() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  UPDATE public.missions SET type_contrat_recherche = p_type_contrat WHERE id = p_mission_id;

  PERFORM fn_ecrire_audit_safe(
    v_actor,
    CASE WHEN est_admin() THEN 'ADMIN_PLATEFORME' ELSE 'ADMIN_ETABLISSEMENT' END,
    'MISSION_TYPE_CONTRAT_MODIFIE', 'mission', p_mission_id,
    NULL,
    jsonb_build_object('ancien', v_ancien, 'nouveau', p_type_contrat),
    NULL, NULL
  );

  RETURN jsonb_build_object('ok', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_modifier_tolerance_pointage_etab(p_tolerance_pointage_m integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_ancienne_valeur integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_tolerance_pointage_m IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'VALEUR_REQUISE');
  END IF;

  IF p_tolerance_pointage_m < 30 OR p_tolerance_pointage_m > 1000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'HORS_RANGE',
      'error', 'Tolérance doit être entre 30 et 1000 mètres'
    );
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT tolerance_pointage_m INTO v_ancienne_valeur FROM public.etablissements WHERE id = v_etab_id;

  UPDATE public.etablissements
  SET tolerance_pointage_m = p_tolerance_pointage_m,
      mis_a_jour_le = now()
  WHERE id = v_etab_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'MODIFICATION_PROFIL', 'etablissement', v_etab_id,
    jsonb_build_object(
      'champ', 'tolerance_pointage_m',
      'ancienne_valeur', v_ancienne_valeur,
      'nouvelle_valeur', p_tolerance_pointage_m,
      'horodatage', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'tolerance_pointage_m', p_tolerance_pointage_m,
    'horodatage', now()
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_modifier_role_membre(p_membre_id uuid, p_nouveau_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_membre RECORD;
  v_perms jsonb;
  v_ancien_role text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_nouveau_role NOT IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY', 'LECTURE_SEULE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ROLE_INVALIDE');
  END IF;

  SELECT * INTO v_membre FROM public.membres_etablissement WHERE id = p_membre_id;
  IF v_membre IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MEMBRE_INTROUVABLE');
  END IF;

  SELECT public.fn_mes_permissions_etab(v_membre.etablissement_id) INTO v_perms;
  IF NOT COALESCE((v_perms->'permissions'->>'gerer_equipe')::boolean, false) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  -- Ne pas pouvoir se rétrograder soi-même PROPRIETAIRE → autre
  IF v_membre.user_id = v_uid AND v_membre.role = 'PROPRIETAIRE' AND p_nouveau_role != 'PROPRIETAIRE' THEN
    -- Vérifier qu'au moins un autre PROPRIETAIRE existe
    IF NOT EXISTS (
      SELECT 1 FROM public.membres_etablissement
      WHERE etablissement_id = v_membre.etablissement_id
        AND role = 'PROPRIETAIRE'
        AND actif = true
        AND user_id != v_uid
    ) THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DERNIER_PROPRIETAIRE',
                                  'error', 'Au moins un PROPRIETAIRE doit rester actif');
    END IF;
  END IF;

  v_ancien_role := v_membre.role;

  UPDATE public.membres_etablissement
  SET role = p_nouveau_role, maj_le = now()
  WHERE id = p_membre_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'MODIFICATION_PROFIL', 'membre_etablissement', p_membre_id,
    jsonb_build_object(
      'evenement', 'MEMBRE_ROLE_MODIFIE',
      'ancien_role', v_ancien_role,
      'nouveau_role', p_nouveau_role
    )
  );

  RETURN jsonb_build_object('success', true, 'role', p_nouveau_role);
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_nettoyer_missions_fantomes()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count INTEGER := 0;
    v_count2 INTEGER := 0;
BEGIN
    -- 1. Missions OUVERTE dont debut_le est passé → ANNULEE
    UPDATE missions SET
        statut = 'ANNULEE_PAR_ETABLISSEMENT',
        modifie_le = NOW()
    WHERE statut = 'OUVERTE'
      AND debut_le < NOW();
    GET DIAGNOSTICS v_count = ROW_COUNT;

    -- 2. Missions ASSIGNEE dont fin_le + 24h est passée sans pointage → ABSENCE
    UPDATE missions SET
        statut = 'ABSENCE',
        modifie_le = NOW()
    WHERE statut = 'ASSIGNEE'
      AND fin_le + INTERVAL '24 hours' < NOW()
      AND id NOT IN (SELECT mission_id FROM presences);
    GET DIAGNOSTICS v_count2 = ROW_COUNT;

    -- Pénaliser les no-show
    IF v_count2 > 0 THEN
        UPDATE soignants SET
            total_absences = total_absences + 1,
            score_fiabilite = GREATEST(0, score_fiabilite - 20),
            modifie_le = NOW()
        WHERE id IN (
            SELECT soignant_assigne_id FROM missions
            WHERE statut = 'ABSENCE'
              AND modifie_le > NOW() - INTERVAL '1 minute'
              AND soignant_assigne_id IS NOT NULL
        );
    END IF;

    RETURN v_count + v_count2;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_nettoyer_tokens_push()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count INTEGER;
BEGIN
    DELETE FROM tokens_push
    WHERE derniere_utilisation < NOW() - INTERVAL '90 days'
       OR actif = FALSE;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mon_token_calendrier()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_token text;
BEGIN
  SELECT token INTO v_token FROM tokens_calendrier WHERE soignant_id = auth.uid();
  IF v_token IS NULL THEN
    INSERT INTO tokens_calendrier (soignant_id)
    VALUES (auth.uid())
    ON CONFLICT (soignant_id) DO NOTHING
    RETURNING token INTO v_token;
    -- In case of race condition
    IF v_token IS NULL THEN
      SELECT token INTO v_token FROM tokens_calendrier WHERE soignant_id = auth.uid();
    END IF;
  END IF;
  RETURN v_token;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_nettoyer_partages_rib_expires()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    UPDATE partages_rib SET actif = FALSE WHERE expire_le < NOW() AND actif = TRUE;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mon_profil_soignant_complet()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_result JSONB;
BEGIN
    IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
    SELECT row_to_json(s)::JSONB INTO v_result FROM (
        SELECT id, prenom, nom, email, telephone, date_naissance, profession::TEXT,
            numero_rpps, numero_adeli, numero_secu, type_contrat::TEXT, type_exercice,
            adresse_rue, adresse_ville, adresse_code_postal, adresse_lat, adresse_lng,
            rayon_deplacement_km, score_fiabilite, note_moyenne, nb_evaluations,
            total_missions_terminees, heures_cumulees, statut_liberal,
            siret_liberal, code_ape, assujetti_tva, numero_tva,
            tous_documents_valides, rpps_verifie, identite_verifiee, diplome_verifie,
            disponible_urgence, urgence_rayon_km, bio, annees_experience, specialites,
            types_contrat_acceptes, avatar_url, stripe_account_id, iban_last4,
            attestation_cumul_activite, taux_horaire_minimum, badge_ambassadeur,
            ville_recherche, ville_urgence, consentement_gps,
            cree_le, modifie_le
        FROM soignants WHERE id = v_uid
    ) s;
    RETURN COALESCE(v_result, jsonb_build_object('error', 'Profil introuvable'));
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mon_etablissement_complet()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_result JSONB;
BEGIN
    IF v_etab_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Etablissement introuvable');
    END IF;

    SELECT row_to_json(e)::JSONB INTO v_result FROM (
        SELECT
            et.id, et.nom, et.siret, et.finess, et.type::TEXT, et.groupe_sante_id,
            et.adresse_rue, et.adresse_ville, et.adresse_code_postal, et.adresse_departement,
            et.adresse_lat, et.adresse_lng, et.email_contact, et.telephone_contact,
            et.stripe_customer_id, et.stripe_account_id,
            et.taux_commission_negocie, et.mode_facturation, et.mode_paiement_commission,
            et.palier_commission_id, et.missions_mois_precedent, et.palier_recalcule_le,
            et.chorus_pro_actif, et.chorus_pro_identifiant, et.delai_paiement_jours,
            et.formule_abonnement, et.convention_collective, et.couleur_theme, et.logo_url,
            et.contrat_url, et.contrat_uploade_le, et.contrat_valide,
            et.taux_majoration_nuit_pourcent, et.taux_majoration_dimanche_pourcent,
            et.taux_majoration_ferie_pourcent,
            et.est_secteur_public, et.peut_publier_missions, et.statut_verification,
            et.note_moyenne, et.nb_evaluations, et.description, et.horaires_ouverture,
            et.rist_plafond_actif, et.rist_taux_base_horaire,
            et.bloque_auto_le, et.bloque_auto_raisons,
            et.cree_le, et.modifie_le,
            CASE WHEN pc.id IS NOT NULL THEN jsonb_build_object(
                'id', pc.id,
                'nom', pc.nom,
                'taux_commission', pc.taux_commission,
                'missions_min', pc.missions_min
            ) ELSE NULL END AS paliers_commission,
            CASE WHEN gs.id IS NOT NULL THEN jsonb_build_object(
                'id', gs.id,
                'nom', gs.nom
            ) ELSE NULL END AS groupes_sante
        FROM etablissements et
        LEFT JOIN paliers_commission pc ON pc.id = et.palier_commission_id
        LEFT JOIN groupes_sante gs ON gs.id = et.groupe_sante_id
        WHERE et.id = v_etab_id
    ) e;

    RETURN COALESCE(v_result, jsonb_build_object('error', 'Etablissement introuvable'));
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_nettoyer_psc_sessions_expirees()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    DELETE FROM psc_auth_sessions WHERE expire_le < now();
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_mon_score_etab()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id UUID := mon_etablissement_id();
  v_result JSONB;
  v_since TIMESTAMPTZ := NOW() - INTERVAL '12 months';
  v_nb_notations INT;
  v_notation_pct NUMERIC;
  v_total_factures INT;
  v_factures_a_temps INT;
  v_paiement_pct NUMERIC;
  v_nb_litiges INT;
BEGIN
  IF v_etab_id IS NULL AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  SELECT COUNT(*),
    SUM(((critere_1 + critere_2 + critere_3 + critere_4) / 4.0) * GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))) /
    NULLIF(SUM(GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))), 0)
  INTO v_nb_notations, v_notation_pct
  FROM notations_missions
  WHERE note_id = v_etab_id AND sens = 'SOIGNANT_VERS_ETAB' AND cree_le >= v_since AND masque = false;

  IF v_nb_notations < 3 OR v_notation_pct IS NULL THEN v_notation_pct := NULL;
  ELSE v_notation_pct := GREATEST(0, LEAST(100, (v_notation_pct - 1) * 25)); END IF;

  SELECT COUNT(*), COUNT(*) FILTER (WHERE date_paiement IS NOT NULL AND date_paiement <= date_echeance)
  INTO v_total_factures, v_factures_a_temps
  FROM factures
  WHERE etablissement_id = v_etab_id AND statut = 'PAYEE' AND COALESCE(date_emission, cree_le) >= v_since;

  IF v_total_factures = 0 THEN v_paiement_pct := NULL;
  ELSE v_paiement_pct := (v_factures_a_temps::NUMERIC / v_total_factures) * 100; END IF;

  SELECT COUNT(*) INTO v_nb_litiges FROM litiges
  WHERE etablissement_id = v_etab_id
    AND statut IN ('RESOLU_SOIGNANT', 'RESOLU_FAVEUR_SOIGNANT')
    AND COALESCE(resolu_le, NOW()) >= v_since;

  SELECT jsonb_build_object(
    'score_qualite', e.score_qualite, 'niveau', e.niveau,
    'composantes', jsonb_build_object(
      'notation_pct', v_notation_pct, 'nb_notations', v_nb_notations,
      'paiement_pct', v_paiement_pct, 'nb_factures', v_total_factures,
      'nb_litiges_perdus', v_nb_litiges
    )
  ) INTO v_result FROM etablissements e WHERE e.id = v_etab_id;

  RETURN COALESCE(v_result, '{}'::jsonb);
END;
$function$
