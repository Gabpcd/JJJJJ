BEGIN;

-- Une cellule NON_PROPOSE ne favorise aucun régime et n'est pas une
-- interdiction. Seul BLOQUE retire le choix libéral sur toute la chaîne.
CREATE OR REPLACE FUNCTION public.dec_valider_compatibilite_mission_liberal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_type_etab text;
  v_est_public boolean;
  v_mode jsonb;
BEGIN
  SELECT type::text, COALESCE(est_secteur_public, false)
    INTO v_type_etab, v_est_public
    FROM public.etablissements
   WHERE id = NEW.etablissement_id;

  IF NEW.profession_requise IS NULL OR v_type_etab IS NULL THEN
    RETURN NEW;
  END IF;

  v_mode := public.fn_mode_exercice(
    NEW.profession_requise::text,
    v_type_etab,
    CASE WHEN v_est_public THEN 'PUBLIC' ELSE NULL END
  );

  IF NEW.type_contrat_recherche IN ('LIBERAL', 'TOUS')
     AND COALESCE(v_mode->>'niveau', 'BLOQUE') = 'BLOQUE' THEN
    NEW.type_contrat_recherche := 'SALARIE';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_valider_compatibilite_mission_liberal()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_valider_compatibilite_mission_liberal()
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_resoudre_contrat_mission(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_choix_contrat text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_mission record;
  v_soignant record;
  v_etablissement record;
  v_recherche text;
  v_choix text;
  v_mode jsonb;
  v_liberal_verifie boolean := false;
BEGIN
  SELECT id, profession_requise, type_contrat_recherche, etablissement_id
    INTO v_mission
  FROM public.missions
  WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Mission introuvable');
  END IF;

  SELECT
    id,
    COALESCE(type_exercice, 'SALARIE') AS type_exercice,
    preference_contrat_mixte
  INTO v_soignant
  FROM public.soignants
  WHERE id = p_soignant_id
    AND supprime_le IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Profil soignant introuvable'
    );
  END IF;

  SELECT
    type::text AS type_etablissement,
    COALESCE(est_secteur_public, false) AS est_public
  INTO v_etablissement
  FROM public.etablissements
  WHERE id = v_mission.etablissement_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Établissement introuvable'
    );
  END IF;

  IF NOT private.fn_comptes_meme_cohorte_test(
    p_soignant_id,
    v_mission.etablissement_id
  ) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Mission indisponible pour ce compte'
    );
  END IF;

  v_liberal_verifie :=
    public.fn_soignant_liberal_actif_verifie(p_soignant_id);

  IF p_choix_contrat IS NOT NULL
     AND upper(p_choix_contrat) NOT IN ('SALARIE', 'LIBERAL') THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Choix de contrat invalide'
    );
  END IF;

  v_recherche := CASE
    WHEN upper(COALESCE(
      v_mission.type_contrat_recherche::text,
      'SALARIE'
    )) IN ('SALARIE', 'LIBERAL', 'TOUS')
      THEN upper(COALESCE(
        v_mission.type_contrat_recherche::text,
        'SALARIE'
      ))
    ELSE 'SALARIE'
  END;

  IF v_recherche = 'SALARIE' THEN
    v_choix := 'SALARIE';
  ELSIF v_recherche = 'LIBERAL' THEN
    IF v_soignant.type_exercice NOT IN ('LIBERAL', 'MIXTE')
       OR NOT v_liberal_verifie THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
          'Cette mission est proposée en libéral ; activez un profil libéral avec SIRET et identité vérifiés.'
      );
    END IF;
    v_choix := 'LIBERAL';
  ELSE
    v_choix := upper(p_choix_contrat);

    IF v_choix = 'LIBERAL' AND NOT v_liberal_verifie THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
          'Votre profil libéral doit être actif, avec SIRET et identité vérifiés.'
      );
    END IF;

    IF v_choix IS NULL THEN
      IF v_soignant.type_exercice = 'MIXTE' AND v_liberal_verifie THEN
        v_choix := CASE
          WHEN upper(COALESCE(
            v_soignant.preference_contrat_mixte,
            ''
          )) IN ('SALARIE', 'LIBERAL')
            THEN upper(v_soignant.preference_contrat_mixte)
          ELSE NULL
        END;
        IF v_choix IS NULL THEN
          RETURN jsonb_build_object(
            'ok', false,
            'choix_requis', true,
            'error', 'Choisissez votre mode de contrat.',
            'options', jsonb_build_array(
              jsonb_build_object(
                'value', 'SALARIE',
                'label', 'Salarié (CDD / bulletin de paie)'
              ),
              jsonb_build_object(
                'value', 'LIBERAL',
                'label', 'Libéral (note d''honoraires)'
              )
            )
          );
        END IF;
      ELSIF v_soignant.type_exercice = 'LIBERAL'
            AND v_liberal_verifie THEN
        v_choix := 'LIBERAL';
      ELSE
        v_choix := 'SALARIE';
      END IF;
    END IF;

    IF v_choix = 'LIBERAL'
       AND (
         v_soignant.type_exercice NOT IN ('LIBERAL', 'MIXTE')
         OR NOT v_liberal_verifie
       ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
          'Votre profil n''est pas activé pour un contrat libéral vérifié.'
      );
    END IF;
  END IF;

  IF v_choix = 'LIBERAL' THEN
    v_mode := public.fn_mode_exercice(
      v_mission.profession_requise::text,
      v_etablissement.type_etablissement,
      CASE
        WHEN v_etablissement.est_public THEN 'PUBLIC'
        ELSE NULL
      END
    );
    IF COALESCE(v_mode->>'niveau', 'BLOQUE') = 'BLOQUE' THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', COALESCE(
          v_mode->>'source_libelle',
          'Le mode libéral est indisponible pour cette mission.'
        ),
        'niveau', COALESCE(v_mode->>'niveau', 'BLOQUE')
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'contrat', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'type_contrat_recherche', v_recherche
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_resoudre_contrat_mission(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_resoudre_contrat_mission(uuid, uuid, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.dec_verifier_eligibilite_liberal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_heures_cumulees numeric;
  v_seuil_heures numeric;
  v_etablissement record;
  v_mode jsonb;
  v_verifier boolean := false;
BEGIN
  IF NEW.soignant_assigne_id IS NOT NULL
     AND NEW.statut = 'ASSIGNEE'
     AND NEW.type_contrat_applique::text = 'LIBERAL' THEN
    IF TG_OP = 'INSERT' THEN
      v_verifier := true;
    ELSE
      v_verifier := OLD.statut IS DISTINCT FROM NEW.statut
        OR OLD.soignant_assigne_id IS DISTINCT FROM NEW.soignant_assigne_id
        OR OLD.type_contrat_applique IS DISTINCT FROM NEW.type_contrat_applique;
    END IF;
  END IF;

  IF NOT v_verifier THEN
    RETURN NEW;
  END IF;

  IF upper(COALESCE(NEW.type_contrat_recherche::text, 'SALARIE'))
       NOT IN ('LIBERAL', 'TOUS') THEN
    RAISE EXCEPTION 'La mission n''est pas ouverte a un contrat liberal.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT e.type::text AS type_etablissement,
         COALESCE(e.est_secteur_public, false) AS est_public
  INTO v_etablissement
  FROM public.etablissements e
  WHERE e.id = NEW.etablissement_id
    AND e.supprime_le IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Etablissement introuvable pour la mission.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_mode := public.fn_mode_exercice(
    NEW.profession_requise::text,
    v_etablissement.type_etablissement,
    CASE WHEN v_etablissement.est_public THEN 'PUBLIC' ELSE NULL END
  );
  IF COALESCE(v_mode->>'niveau', 'BLOQUE') = 'BLOQUE' THEN
    RAISE EXCEPTION '%', COALESCE(
      v_mode->>'source_libelle',
      'Le mode liberal est indisponible pour cette mission.'
    ) USING ERRCODE = 'check_violation';
  END IF;

  IF NOT public.fn_soignant_liberal_actif_verifie(
    NEW.soignant_assigne_id
  ) THEN
    RAISE EXCEPTION 'Le profil liberal doit etre actif, avec SIRET et identite verifies.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT public.fn_documents_ok_pour_mission(
    NEW.soignant_assigne_id, 'LIBERAL'
  ) THEN
    RAISE EXCEPTION 'Les documents requis pour la mission liberale ne sont pas tous verifies.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.soignants s
    WHERE s.id = NEW.soignant_assigne_id
      AND s.supprime_le IS NULL
  ) THEN
    RAISE EXCEPTION 'Profil soignant introuvable.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT h.heures_totales
  INTO v_heures_cumulees
  FROM private.fn_heures_exercice_verifiees(
    NEW.soignant_assigne_id
  ) h;

  SELECT private.fn_seuil_heures_liberal(
    NEW.soignant_assigne_id,
    NEW.profession_requise::text
  )
  INTO v_seuil_heures;
  IF v_seuil_heures IS NULL THEN
    RAISE EXCEPTION 'Le parcours kine (2 240 heures ou zone sous-dotee) doit etre choisi avant une mission liberale.'
      USING ERRCODE = 'check_violation';
  END IF;
  IF COALESCE(v_heures_cumulees, 0) < v_seuil_heures THEN
    RAISE EXCEPTION 'Vous devez cumuler % heures d''exercice pour accepter cette mission liberale. Vous avez actuellement % heures.',
      v_seuil_heures,
      round(COALESCE(v_heures_cumulees, 0), 2)
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_verifier_eligibilite_liberal()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_verifier_eligibilite_liberal()
  TO service_role;

-- L'invitation manuelle doit réellement partir, même depuis l'établissement
-- de recette utilisé par sa propriétaire. Les adresses automatiques E2E
-- restent filtrées par send-email.
CREATE OR REPLACE FUNCTION public.dec_email_invitation_equipe_etab()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_etab_nom text;
  v_invite_par_email text;
  v_invite_par_nom text;
  v_request_id bigint;
  v_erreur text;
BEGIN
  IF NEW.statut <> 'EN_ATTENTE' THEN
    RETURN NEW;
  END IF;

  SELECT e.nom
    INTO v_etab_nom
    FROM public.etablissements e
   WHERE e.id = NEW.etablissement_id;
  IF v_etab_nom IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT u.email INTO v_invite_par_email
    FROM auth.users u WHERE u.id = NEW.invite_par;
  v_invite_par_nom := COALESCE(v_invite_par_email, 'Un administrateur');

  BEGIN
    SELECT net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret FROM vault.decrypted_secrets
           WHERE name = 'service_role_key' LIMIT 1
        )
      ),
      body := jsonb_build_object(
        'type', 'INVITATION_EQUIPE_ETAB',
        'destinataire_email', NEW.email_invite,
        'idempotency_key', 'invitation-equipe-etab:' || NEW.id::text,
        'data', jsonb_build_object(
          'token', NEW.token,
          'nom_etablissement', v_etab_nom,
          'role', NEW.role_propose,
          'invite_par_nom', v_invite_par_nom,
          'expire_le', to_char(
            NEW.expire_le AT TIME ZONE 'Europe/Paris',
            'DD/MM/YYYY à HH24:MI'
          )
        )
      )
    ) INTO v_request_id;
  EXCEPTION WHEN OTHERS THEN
    v_erreur := SQLERRM;
  END;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    NEW.invite_par, 'SYSTEME', 'SYSTEM', 'invitation_etab', NEW.id,
    jsonb_build_object(
      'evenement', CASE
        WHEN v_request_id IS NOT NULL THEN 'EMAIL_INVITATION_EQUIPE_MIS_EN_FILE'
        ELSE 'EMAIL_INVITATION_EQUIPE_ECHEC_ENFILEMENT'
      END,
      'request_id', v_request_id,
      'erreur', v_erreur,
      'destinataire_email', NEW.email_invite,
      'etablissement_id', NEW.etablissement_id,
      'role_propose', NEW.role_propose
    )
  );

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_email_invitation_equipe_etab()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_email_invitation_equipe_etab()
  TO service_role;

-- Une proposition de résolution est un événement à part entière : notification
-- immédiate de la contrepartie, puis conservation des notifications de clôture.
CREATE OR REPLACE FUNCTION public.dec_notifier_resolution_litige()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant_nom text;
  v_mission_intitule text;
  v_resolution_label text;
  v_admin_id uuid;
BEGIN
  SELECT COALESCE(prenom || ' ', '') || nom
    INTO v_soignant_nom
    FROM public.soignants
   WHERE id = NEW.soignant_id;
  SELECT intitule
    INTO v_mission_intitule
    FROM public.missions
   WHERE id = NEW.mission_id;

  IF NEW.payload_modifications IS NOT NULL
     AND (
       OLD.payload_modifications IS DISTINCT FROM NEW.payload_modifications
       OR OLD.accord_soignant IS DISTINCT FROM NEW.accord_soignant
       OR OLD.accord_etablissement IS DISTINCT FROM NEW.accord_etablissement
     ) THEN
    IF NEW.accord_etablissement IS TRUE
       AND NEW.accord_soignant IS NOT TRUE THEN
      PERFORM public.fn_creer_notification(
        NEW.soignant_id,
        'SOIGNANT',
        'LITIGE_REPONSE',
        'Proposition d''accord reçue',
        'L''établissement a proposé une résolution pour la mission "' ||
          COALESCE(v_mission_intitule, 'Mission') ||
          '". Votre réponse est attendue.',
        '/soignant/litiges?litige=' || NEW.id::text,
        'litige',
        NEW.id
      );
    ELSIF NEW.accord_soignant IS TRUE
          AND NEW.accord_etablissement IS NOT TRUE THEN
      PERFORM public.fn_creer_notification(
        NEW.etablissement_id,
        'ETABLISSEMENT',
        'LITIGE_REPONSE',
        'Proposition d''accord reçue',
        COALESCE(v_soignant_nom, 'Le soignant') ||
          ' a proposé une résolution pour la mission "' ||
          COALESCE(v_mission_intitule, 'Mission') ||
          '". Votre réponse est attendue.',
        '/etablissement/litiges?litige=' || NEW.id::text,
        'litige',
        NEW.id
      );
    END IF;

    FOR v_admin_id IN
      SELECT ea.user_id
        FROM public.equipe_admin ea
       WHERE ea.actif IS TRUE
         AND ea.user_id IS NOT NULL
    LOOP
      PERFORM public.fn_creer_notification(
        v_admin_id,
        'ADMIN',
        'LITIGE_REPONSE',
        'Proposition de résolution de litige',
        'Une proposition d''accord attend la réponse de la contrepartie pour la mission "' ||
          COALESCE(v_mission_intitule, 'Mission') || '".',
        '/admin/litiges?litige=' || NEW.id::text,
        'litige',
        NEW.id
      );
    END LOOP;
  END IF;

  IF OLD.statut = NEW.statut THEN
    RETURN NEW;
  END IF;
  IF NEW.statut NOT IN (
    'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN', 'FERME'
  ) THEN
    RETURN NEW;
  END IF;

  CASE NEW.statut
    WHEN 'RESOLU_SOIGNANT' THEN
      v_resolution_label := 'résolu en faveur du soignant';
    WHEN 'RESOLU_ETABLISSEMENT' THEN
      v_resolution_label := 'résolu en faveur de l''établissement';
    WHEN 'RESOLU_ADMIN' THEN
      v_resolution_label := 'résolu par l''administrateur';
    WHEN 'FERME' THEN
      v_resolution_label := 'clôturé par accord mutuel';
  END CASE;

  PERFORM public.fn_creer_notification(
    NEW.soignant_id, 'SOIGNANT', 'LITIGE_RESOLU',
    'Litige ' || v_resolution_label,
    'Le litige concernant la mission "' ||
      COALESCE(v_mission_intitule, 'Mission') || '" a été ' ||
      v_resolution_label || '.',
    '/soignant/litiges?litige=' || NEW.id::text,
    'litige', NEW.id
  );

  PERFORM public.fn_creer_notification(
    NEW.etablissement_id, 'ETABLISSEMENT', 'LITIGE_RESOLU',
    'Litige ' || v_resolution_label,
    'Le litige avec ' || COALESCE(v_soignant_nom, 'un soignant') ||
      ' sur la mission "' || COALESCE(v_mission_intitule, 'Mission') ||
      '" a été ' || v_resolution_label || '.',
    '/etablissement/litiges?litige=' || NEW.id::text,
    'litige', NEW.id
  );
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_notifier_resolution_litige()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_notifier_resolution_litige()
  TO service_role;

-- Rattrapage borné de l'invitation manuelle récente que l'ancien trigger a
-- volontairement ignorée. L'idempotency_key empêche tout double envoi.
DO $backfill_email$
DECLARE
  v_invitation record;
  v_request_id bigint;
  v_invite_par_nom text;
BEGIN
  FOR v_invitation IN
    SELECT i.*, e.nom AS etablissement_nom
      FROM public.invitations_etablissement i
      JOIN public.etablissements e ON e.id = i.etablissement_id
     WHERE i.statut = 'EN_ATTENTE'
       AND i.expire_le > now()
       AND i.invite_le >= now() - interval '24 hours'
       AND i.email_invite !~* '^playwright[^@]*@jolene\\.app$'
       AND i.email_invite !~* '@jolene-demo\\.dev$'
       AND NOT EXISTS (
         SELECT 1
           FROM public.emails_envoyes ee
          WHERE ee.idempotency_key = 'invitation-equipe-etab:' || i.id::text
       )
  LOOP
    SELECT COALESCE(u.email, 'Un administrateur')
      INTO v_invite_par_nom
      FROM auth.users u
     WHERE u.id = v_invitation.invite_par;

    BEGIN
      SELECT net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (
            SELECT decrypted_secret FROM vault.decrypted_secrets
             WHERE name = 'service_role_key' LIMIT 1
          )
        ),
        body := jsonb_build_object(
          'type', 'INVITATION_EQUIPE_ETAB',
          'destinataire_email', v_invitation.email_invite,
          'idempotency_key', 'invitation-equipe-etab:' || v_invitation.id::text,
          'data', jsonb_build_object(
            'token', v_invitation.token,
            'nom_etablissement', v_invitation.etablissement_nom,
            'role', v_invitation.role_propose,
            'invite_par_nom', v_invite_par_nom,
            'expire_le', to_char(
              v_invitation.expire_le AT TIME ZONE 'Europe/Paris',
              'DD/MM/YYYY à HH24:MI'
            )
          )
        )
      ) INTO v_request_id;

      INSERT INTO public.journaux_audit (
        acteur_id, type_acteur, action, type_ressource, id_ressource, details
      ) VALUES (
        v_invitation.invite_par,
        'SYSTEME',
        'SYSTEM',
        'invitation_etab',
        v_invitation.id,
        jsonb_build_object(
          'evenement', 'EMAIL_INVITATION_EQUIPE_RATTRAPAGE_MIS_EN_FILE',
          'request_id', v_request_id,
          'destinataire_email', v_invitation.email_invite,
          'etablissement_id', v_invitation.etablissement_id
        )
      );
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.journaux_audit (
        acteur_id, type_acteur, action, type_ressource, id_ressource, details
      ) VALUES (
        v_invitation.invite_par,
        'SYSTEME',
        'SYSTEM',
        'invitation_etab',
        v_invitation.id,
        jsonb_build_object(
          'evenement', 'EMAIL_INVITATION_EQUIPE_RATTRAPAGE_ECHEC',
          'erreur', SQLERRM,
          'destinataire_email', v_invitation.email_invite,
          'etablissement_id', v_invitation.etablissement_id
        )
      );
    END;
  END LOOP;
END;
$backfill_email$;

-- La proposition déjà en attente devient immédiatement visible dans la cloche
-- du soignant, sans créer de doublon si elle avait déjà été notifiée.
INSERT INTO public.notifications (
  destinataire_id,
  type_destinataire,
  type,
  titre,
  corps,
  lien,
  type_ressource,
  id_ressource
)
SELECT
  l.soignant_id,
  'SOIGNANT',
  'LITIGE_REPONSE',
  'Proposition d''accord reçue',
  'L''établissement a proposé une résolution pour la mission "' ||
    COALESCE(m.intitule, 'Mission') || '". Votre réponse est attendue.',
  '/soignant/litiges?litige=' || l.id::text,
  'litige',
  l.id
FROM public.litiges l
LEFT JOIN public.missions m ON m.id = l.mission_id
WHERE l.payload_modifications IS NOT NULL
  AND l.accord_etablissement IS TRUE
  AND l.accord_soignant IS NOT TRUE
  AND l.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS')
  AND NOT EXISTS (
    SELECT 1
      FROM public.notifications n
     WHERE n.destinataire_id = l.soignant_id
       AND n.type = 'LITIGE_REPONSE'
       AND n.titre = 'Proposition d''accord reçue'
       AND n.type_ressource = 'litige'
       AND n.id_ressource = l.id
  );

-- L'admin plateforme est également alerté pour chaque accord encore en
-- attente, y compris la proposition déjà enregistrée avant ce correctif.
INSERT INTO public.notifications (
  destinataire_id,
  type_destinataire,
  type,
  titre,
  corps,
  lien,
  type_ressource,
  id_ressource
)
SELECT
  ea.user_id,
  'ADMIN',
  'LITIGE_REPONSE',
  'Proposition de résolution de litige',
  'Une proposition d''accord attend la réponse de la contrepartie pour la mission "' ||
    COALESCE(m.intitule, 'Mission') || '".',
  '/admin/litiges?litige=' || l.id::text,
  'litige',
  l.id
FROM public.litiges l
LEFT JOIN public.missions m ON m.id = l.mission_id
CROSS JOIN public.equipe_admin ea
WHERE ea.actif IS TRUE
  AND ea.user_id IS NOT NULL
  AND l.payload_modifications IS NOT NULL
  AND l.accord_etablissement IS DISTINCT FROM l.accord_soignant
  AND l.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS')
  AND NOT EXISTS (
    SELECT 1
      FROM public.notifications n
     WHERE n.destinataire_id = ea.user_id
       AND n.type_destinataire = 'ADMIN'
       AND n.type = 'LITIGE_REPONSE'
       AND n.titre = 'Proposition de résolution de litige'
       AND n.type_ressource = 'litige'
       AND n.id_ressource = l.id
  );

INSERT INTO private.security_definer_inventory (
  signature,
  categorie,
  definition_md5,
  justification,
  recense_le
)
VALUES
  (
    'dec_valider_compatibilite_mission_liberal()',
    'SERVICE_ONLY_REVOQUE',
    md5(pg_get_functiondef('public.dec_valider_compatibilite_mission_liberal()'::regprocedure)),
    'Trigger serveur : ne favorise aucun régime pour NON_PROPOSE et retire le choix libéral uniquement pour une cellule BLOQUE.',
    now()
  ),
  (
    'dec_verifier_eligibilite_liberal()',
    'SERVICE_ONLY_REVOQUE',
    md5(pg_get_functiondef('public.dec_verifier_eligibilite_liberal()'::regprocedure)),
    'Trigger serveur : vérifie le profil, les pièces et l''expérience du soignant, tout en réservant l''interdiction de régime aux cellules BLOQUE.',
    now()
  ),
  (
    'dec_email_invitation_equipe_etab()',
    'SERVICE_ONLY_REVOQUE',
    md5(pg_get_functiondef('public.dec_email_invitation_equipe_etab()'::regprocedure)),
    'Trigger interne : met réellement en file les invitations manuelles et journalise l''identifiant pg_net ou l''erreur d''enfilement.',
    now()
  ),
  (
    'dec_notifier_resolution_litige()',
    'SERVICE_ONLY_REVOQUE',
    md5(pg_get_functiondef('public.dec_notifier_resolution_litige()'::regprocedure)),
    'Trigger interne : notifie chaque proposition d''accord à la contrepartie et aux admins, puis les résolutions finales aux deux parties.',
    now()
  )
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

COMMIT;
