-- ============================================================
-- CP-LITIGES-4 — Cron escalade + auto-création litiges présence
-- ============================================================
-- Dépend de : CP-LITIGES-1/2/3 (20260417130000-130300) + fixes CP2.
--
-- Livre :
--   0. fn_list_admin_user_ids() — helper interne (lookup auth.users JWT).
--   1. fn_litiges_escalader_auto() — escalade auto après 72h libéral /
--      5 jours ouvrés salarié.
--   2. fn_auto_creation_litiges_presence() — auto-création ABSENCE_SOIGNANT
--      pour présences ABSENT non contestées > 48h.
--   3. fn_envoyer_rappels_litiges() — rappels J+1/J+3/J+5 avec
--      idempotence via derniers_rappels_envoyes.
--   4. fn_alerter_mediation_prioritaire() — alerte admin EN_MEDIATION > 7j.
--
-- Toutes les notifications passent par email_queue (consommée par
-- email-cron existant) + notifications (in-app). Aucun appel direct
-- à send-email/send-sms depuis ces RPCs.
--
-- auth.users.raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME' est utilisé
-- pour identifier les admins (pattern JWT Jolene).
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- 0. fn_list_admin_user_ids — helper interne
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_list_admin_user_ids()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
  SELECT id
    FROM auth.users
   WHERE raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME';
$$;

COMMENT ON FUNCTION public.fn_list_admin_user_ids() IS
  'Retourne la liste des user_ids ADMIN_PLATEFORME via auth.users JWT. Utilisé par les crons litiges pour notifier les admins.';

GRANT EXECUTE ON FUNCTION public.fn_list_admin_user_ids() TO service_role;

-- ──────────────────────────────────────────────────────────────
-- Helper interne : pousse une notification in-app + email_queue
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_litige_push_notification(
  p_destinataire_id UUID,
  p_type_destinataire TEXT,
  p_type_notif TEXT,
  p_titre TEXT,
  p_corps TEXT,
  p_litige_id UUID,
  p_email_data JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  INSERT INTO public.notifications (
    destinataire_id, type_destinataire, type, titre, corps,
    id_ressource, type_ressource, lien
  ) VALUES (
    p_destinataire_id, p_type_destinataire, p_type_notif, p_titre, p_corps,
    p_litige_id, 'litige',
    CASE p_type_destinataire
      WHEN 'SOIGNANT'       THEN '/soignant/litiges'
      WHEN 'ETABLISSEMENT'  THEN '/etablissement/litiges'
      WHEN 'ADMIN'          THEN '/admin/moderation'
      ELSE NULL
    END
  );

  INSERT INTO public.email_queue (type, destinataire_id, data)
  VALUES (
    p_type_notif,
    p_destinataire_id,
    p_email_data || jsonb_build_object('litige_id', p_litige_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_litige_push_notification(UUID, TEXT, TEXT, TEXT, TEXT, UUID, JSONB)
  TO service_role;

-- ──────────────────────────────────────────────────────────────
-- 1. fn_litiges_escalader_auto()
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_litiges_escalader_auto()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
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
           COALESCE(s.est_salarie_etablissement, FALSE) AS est_salarie
      FROM public.litiges l
      LEFT JOIN public.soignants s ON s.id = l.soignant_id
     WHERE l.statut IN ('OUVERT', 'EN_DISCUSSION')
       AND l.escalade_auto_le IS NULL
       AND (l.reponse IS NULL OR length(trim(l.reponse)) = 0)
       AND NOT l.est_informatif
       AND (
         (COALESCE(s.est_salarie_etablissement, FALSE) = FALSE
          AND l.cree_le < NOW() - make_interval(hours => v_delai_liberal_h))
         OR
         (COALESCE(s.est_salarie_etablissement, FALSE) = TRUE
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

    -- Notification + email_queue pour chaque admin
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
$$;

COMMENT ON FUNCTION public.fn_litiges_escalader_auto() IS
  'Cron : escalade les litiges OUVERT/EN_DISCUSSION sans réponse après délai (libéral 72h / salarié 5 jours ouvrés). Retourne { escalades: N }.';

GRANT EXECUTE ON FUNCTION public.fn_litiges_escalader_auto() TO service_role;

-- ──────────────────────────────────────────────────────────────
-- 2. fn_auto_creation_litiges_presence()
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_auto_creation_litiges_presence()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_delai_pointage_h INT;
  v_nb_crees INT := 0;
  v_presence RECORD;
  v_litige_id UUID;
BEGIN
  SELECT valeur::INT INTO v_delai_pointage_h
    FROM public.parametres_litiges WHERE cle = 'delai_contestation_pointage_h';

  FOR v_presence IN
    SELECT p.id AS presence_id, p.mission_id, p.soignant_id,
           m.etablissement_id, m.soignant_assigne_id
      FROM public.presences p
      JOIN public.missions m ON m.id = p.mission_id
     WHERE p.valide_par_etablissement = TRUE
       AND p.valide_le IS NOT NULL
       AND p.valide_le < NOW() - make_interval(hours => v_delai_pointage_h)
       AND (p.heures_reelles IS NULL OR p.heures_reelles = 0)
       AND p.motif_litige IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.litiges l
          WHERE l.mission_id = p.mission_id
            AND l.type_litige = 'ABSENCE_SOIGNANT'
            AND l.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION')
       )
  LOOP
    INSERT INTO public.litiges (
      mission_id, soignant_id, etablissement_id, presence_id,
      initie_par, motif, statut, type_litige, est_informatif
    ) VALUES (
      v_presence.mission_id,
      COALESCE(v_presence.soignant_assigne_id, v_presence.soignant_id),
      v_presence.etablissement_id,
      v_presence.presence_id,
      'ETABLISSEMENT',
      'Auto-création : soignant marqué absent sans contestation dans les 48h',
      'OUVERT',
      'ABSENCE_SOIGNANT',
      FALSE
    )
    RETURNING id INTO v_litige_id;

    PERFORM public.fn_ecrire_audit(
      NULL, 'SYSTEM', 'LITIGE_AUTO_CREATION',
      'litige', v_litige_id, NULL,
      jsonb_build_object(
        'type_litige', 'ABSENCE_SOIGNANT',
        'mission_id', v_presence.mission_id,
        'presence_id', v_presence.presence_id,
        'raison', 'Absence non contestée dans les 48h post-validation présence'
      ),
      NULL, NULL
    );

    -- Notification soignant (J+0) — 72h pour répondre avant escalade
    PERFORM public.fn_litige_push_notification(
      COALESCE(v_presence.soignant_assigne_id, v_presence.soignant_id),
      'SOIGNANT',
      'LITIGE_OUVERTURE',
      'Litige ouvert sur votre mission',
      'Votre établissement a signalé une absence. Répondez sous 72h pour éviter l''escalade automatique.',
      v_litige_id,
      jsonb_build_object(
        'type_litige', 'ABSENCE_SOIGNANT',
        'mission_id', v_presence.mission_id,
        'auto_cree', TRUE
      )
    );

    v_nb_crees := v_nb_crees + 1;
  END LOOP;

  RETURN jsonb_build_object('litiges_crees', v_nb_crees);
END;
$$;

COMMENT ON FUNCTION public.fn_auto_creation_litiges_presence() IS
  'Cron : crée automatiquement des litiges ABSENCE_SOIGNANT pour les présences marquées absentes non contestées dans les 48h post-validation étab.';

GRANT EXECUTE ON FUNCTION public.fn_auto_creation_litiges_presence() TO service_role;

-- ──────────────────────────────────────────────────────────────
-- 3. fn_envoyer_rappels_litiges()
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_envoyer_rappels_litiges()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_litige RECORD;
  v_destinataire_id UUID;
  v_destinataire_type TEXT;
  v_age_h INT;
  v_rappel_key TEXT;
  v_rappel_libelle TEXT;
  v_nb_rappels INT := 0;
BEGIN
  FOR v_litige IN
    SELECT l.id, l.mission_id, l.soignant_id, l.etablissement_id,
           l.initie_par, l.cree_le, l.reponse, l.type_litige,
           l.derniers_rappels_envoyes
      FROM public.litiges l
     WHERE l.statut IN ('OUVERT', 'EN_DISCUSSION')
       AND NOT l.est_informatif
       AND l.escalade_auto_le IS NULL
       AND (l.reponse IS NULL OR length(trim(l.reponse)) = 0)
  LOOP
    v_age_h := EXTRACT(EPOCH FROM NOW() - v_litige.cree_le)::INT / 3600;

    IF v_age_h >= 120 AND NOT (v_litige.derniers_rappels_envoyes ? 'J+5') THEN
      v_rappel_key := 'J+5';
      v_rappel_libelle := 'Rappel litige 5 jours — dernière relance';
    ELSIF v_age_h >= 72 AND NOT (v_litige.derniers_rappels_envoyes ? 'J+3') THEN
      v_rappel_key := 'J+3';
      v_rappel_libelle := 'Rappel litige 3 jours';
    ELSIF v_age_h >= 24 AND NOT (v_litige.derniers_rappels_envoyes ? 'J+1') THEN
      v_rappel_key := 'J+1';
      v_rappel_libelle := 'Rappel litige 1 jour';
    ELSE
      CONTINUE;
    END IF;

    -- Ciblage : partie opposée à l'initiateur
    IF v_litige.initie_par = 'SOIGNANT' THEN
      v_destinataire_id := v_litige.etablissement_id;
      v_destinataire_type := 'ETABLISSEMENT';
    ELSE
      v_destinataire_id := v_litige.soignant_id;
      v_destinataire_type := 'SOIGNANT';
    END IF;

    IF v_destinataire_id IS NULL THEN
      CONTINUE;
    END IF;

    PERFORM public.fn_litige_push_notification(
      v_destinataire_id,
      v_destinataire_type,
      'LITIGE_RAPPEL_' || REPLACE(v_rappel_key, '+', ''),  -- LITIGE_RAPPEL_J1/J3/J5
      v_rappel_libelle,
      'Un litige est en attente de votre réponse depuis ' || v_age_h || 'h. Répondez pour éviter l''escalade.',
      v_litige.id,
      jsonb_build_object(
        'type_litige', v_litige.type_litige,
        'mission_id', v_litige.mission_id,
        'age_heures', v_age_h,
        'rappel', v_rappel_key
      )
    );

    UPDATE public.litiges
       SET derniers_rappels_envoyes = derniers_rappels_envoyes
         || jsonb_build_object(v_rappel_key, NOW())
     WHERE id = v_litige.id;

    v_nb_rappels := v_nb_rappels + 1;
  END LOOP;

  RETURN jsonb_build_object('rappels_envoyes', v_nb_rappels);
END;
$$;

COMMENT ON FUNCTION public.fn_envoyer_rappels_litiges() IS
  'Cron : envoie les rappels J+1/J+3/J+5 aux parties sans réponse. Idempotence via derniers_rappels_envoyes.';

GRANT EXECUTE ON FUNCTION public.fn_envoyer_rappels_litiges() TO service_role;

-- ──────────────────────────────────────────────────────────────
-- 4. fn_alerter_mediation_prioritaire()
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_alerter_mediation_prioritaire()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_delai_j INT;
  v_nb_alertes INT := 0;
  v_litige RECORD;
  v_admin_id UUID;
BEGIN
  SELECT valeur::INT INTO v_delai_j
    FROM public.parametres_litiges WHERE cle = 'delai_mediation_alerte_prioritaire_j';

  FOR v_litige IN
    SELECT id, mission_id, type_litige, escalade_auto_le
      FROM public.litiges
     WHERE statut = 'EN_MEDIATION'
       AND escalade_auto_le IS NOT NULL
       AND escalade_auto_le < NOW() - make_interval(days => v_delai_j)
       AND NOT (derniers_rappels_envoyes ? 'MEDIATION_7J')
  LOOP
    FOR v_admin_id IN SELECT * FROM public.fn_list_admin_user_ids()
    LOOP
      PERFORM public.fn_litige_push_notification(
        v_admin_id,
        'ADMIN',
        'LITIGE_MEDIATION_PRIORITAIRE',
        '🚨 Litige en médiation depuis > ' || v_delai_j || ' jours',
        'Le litige ' || v_litige.type_litige || ' sur mission '
          || v_litige.mission_id::text
          || ' est en médiation sans action admin depuis plus de '
          || v_delai_j || ' jours.',
        v_litige.id,
        jsonb_build_object(
          'type_litige', v_litige.type_litige,
          'mission_id', v_litige.mission_id,
          'jours_depuis_escalade', v_delai_j,
          'prioritaire', TRUE
        )
      );
    END LOOP;

    UPDATE public.litiges
       SET derniers_rappels_envoyes = derniers_rappels_envoyes
         || jsonb_build_object('MEDIATION_7J', NOW())
     WHERE id = v_litige.id;

    v_nb_alertes := v_nb_alertes + 1;
  END LOOP;

  RETURN jsonb_build_object('alertes_mediation', v_nb_alertes);
END;
$$;

COMMENT ON FUNCTION public.fn_alerter_mediation_prioritaire() IS
  'Cron : alerte admin si litige EN_MEDIATION sans action > 7 jours. Idempotence via derniers_rappels_envoyes.MEDIATION_7J.';

GRANT EXECUTE ON FUNCTION public.fn_alerter_mediation_prioritaire() TO service_role;

COMMIT;

-- ============================================================
-- Déploiement production (à coordonner avec Gabrielle) :
--
--   1. Déployer l'edge function litige-escalation-cron
--      (supabase/functions/litige-escalation-cron/index.ts).
--   2. Ajouter un schedule dans Supabase dashboard :
--      Settings > Edge Functions > Schedules
--      - Name: litige-escalation-cron-daily
--      - Cron: 0 8 * * *  (08h UTC = 09h Paris hiver / 10h été)
--      - Function: litige-escalation-cron
--   3. Secrets requis : SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
--      (déjà présents pour email-cron).
--
-- process-stripe-refunds est livrée en SQUELETTE (T13).
-- Schedule à configurer uniquement après T12 + T13 fermés.
-- ============================================================
