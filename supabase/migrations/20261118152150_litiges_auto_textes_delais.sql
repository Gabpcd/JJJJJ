-- Litiges auto-créés : textes de délai dérivés des paramètres, promesse
-- « Répondez sous 72h » retirée (suite de D12, 18/11/2026).
--
-- B9 (SECURITY DEFINER) + HARD STOP n°4 (texte exposé à l'utilisateur) :
-- validation explicite de Gabrielle requise avant merge.
--
-- Constat (définitions LIVE relues en lecture seule le 18/11/2026 sur
-- flripxtsyegjshnhzjkz ; md5(prosrc) identiques aux corps de
-- 20260729121442_securiser_auth_et_crons_critiques.sql) :
-- * public.fn_auto_creation_litiges_presence() sélectionne les présences avec
--   parametres_litiges.delai_contestation_pointage_h (48 en production au
--   18/11/2026 ; 72 avec la PR #1140, décision D12 de
--   docs/mobile-swift/DECISIONS_LOT2.md), mais écrit « 48h » en dur dans
--   litiges.motif, affiché au soignant et à l'établissement, et dans la raison
--   de l'audit LITIGE_AUTO_CREATION ;
-- * la même fonction notifie « Répondez sous 72h pour éviter l'escalade
--   automatique. », et public.fn_litige_push_notification(...) envoie le SMS
--   LITIGE_OUVERTURE « ... Répondez sous 72h. » (litiges auto-créés et
--   manuels). Or public.fn_litiges_escalader_auto() escalade après
--   delai_escalade_liberal_h (72) en libéral et après
--   delai_escalade_salarie_jours_ouvres (5 jours ouvrés) en salarié : la
--   promesse est fausse en salarié. C'est le défaut que D12 (point 3) retire
--   du web, sans le remplacer.
--
-- Correction, textes seulement (CLAUDE.md, « État dérivé ») :
-- 1. motif ABSENCE_SOIGNANT et raisons d'audit : délai formaté depuis
--    v_delai_pointage_h, la valeur que la fonction lit déjà pour choisir les
--    présences. Le texte suit le paramètre, une seule source ;
-- 2. « Répondez sous 72h ... » retiré des deux notifications in-app (absence,
--    départ anticipé) et du SMS LITIGE_OUVERTURE, sans nouveau délai ;
-- 3. COMMENT ON FUNCTION : « 48h » remplacé par le nom du paramètre.
-- Rien d'autre ne change : sélection, anti-boucle, insertion du litige,
-- audit, destinataires, éligibilité SMS, file email. En-têtes, SECURITY
-- DEFINER, search_path vide, propriétaire et ACL (EXECUTE réservé à postgres
-- et service_role) sont conservés par CREATE OR REPLACE : aucun GRANT ni
-- REVOKE. Aucune des deux fonctions n'est inscrite dans
-- private.security_definer_inventory.
--
-- 0. Préflight fail-closed (CLAUDE.md, garde-fous 9.0 n°2) : md5(prosrc),
--    attributs, propriétaire et ACL LIVE attendus, sinon la migration entière
--    est refusée avant toute écriture.
-- 4. Post-condition : nouveaux md5(prosrc), attributs, ACL et commentaire.
-- Contrôles : tests/node/litiges-auto-textes-delais.node.mjs (statique, CI)
-- et tests/litiges/fix-textes-delais-auto-creation.test.sql (psql sur
-- staging ou base locale, ROLLBACK).
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

-- ── 0. Préflight : corps LIVE attendus ──────────────────────────────────────
DO $litiges_textes_delais_avant$
DECLARE
  v_attendu record;
  v_proc record;
BEGIN
  FOR v_attendu IN
    SELECT * FROM (VALUES
      ('fn_auto_creation_litiges_presence()', 'b418c1958bbb5489d220315c2763f0b3'),
      ('fn_litige_push_notification(uuid,text,text,text,text,uuid,jsonb)', '8e6fd51152b7b15f5673fe13872df5e9')
    ) AS t(signature, empreinte)
  LOOP
    SELECT p.oid, p.prosrc, p.prosecdef, p.provolatile::text AS volatilite,
           p.proconfig, p.proacl, p.proowner,
           pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
      INTO v_proc
      FROM pg_catalog.pg_proc p
     WHERE p.oid = pg_catalog.to_regprocedure('public.' || v_attendu.signature);
    IF NOT FOUND
      OR pg_catalog.md5(v_proc.prosrc) IS DISTINCT FROM v_attendu.empreinte
      OR v_proc.proprietaire IS DISTINCT FROM 'postgres'
      OR v_proc.prosecdef IS NOT TRUE
      OR v_proc.volatilite IS DISTINCT FROM 'v'
      OR v_proc.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
    THEN
      RAISE EXCEPTION 'LITIGES_TEXTES_DELAIS_SOURCE_DIVERGENTE : public.% en base (md5 %) ne correspond plus au corps LIVE relu le 18/11/2026 (md5 %, SECURITY DEFINER, VOLATILE, search_path vide, propriétaire postgres). Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
        v_attendu.signature,
        COALESCE(pg_catalog.md5(v_proc.prosrc), 'fonction absente'),
        v_attendu.empreinte;
    END IF;
    IF pg_catalog.has_function_privilege('anon', v_proc.oid, 'EXECUTE')
      OR pg_catalog.has_function_privilege('authenticated', v_proc.oid, 'EXECUTE')
      OR NOT pg_catalog.has_function_privilege('service_role', v_proc.oid, 'EXECUTE')
      OR EXISTS (
        SELECT FROM pg_catalog.aclexplode(COALESCE(v_proc.proacl, pg_catalog.acldefault('f', v_proc.proowner))) a
         WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
    THEN
      RAISE EXCEPTION 'LITIGES_TEXTES_DELAIS_ACL_DIVERGENTE : public.% (EXECUTE attendu pour postgres et service_role seulement).',
        v_attendu.signature;
    END IF;
    IF EXISTS (SELECT FROM private.security_definer_inventory i
                WHERE i.signature IN (v_attendu.signature, 'public.' || v_attendu.signature))
    THEN
      RAISE EXCEPTION 'LITIGES_TEXTES_DELAIS_INVENTAIRE_INATTENDU : public.% est inscrite dans private.security_definer_inventory, empreinte à mettre à jour.',
        v_attendu.signature;
    END IF;
  END LOOP;
END
$litiges_textes_delais_avant$;

-- ── 1-2. Cron d'auto-création : motif et audit dérivés, promesse retirée ───
CREATE OR REPLACE FUNCTION public.fn_auto_creation_litiges_presence()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn_auto_creation_litiges_presence$
DECLARE
  v_delai_pointage_h integer;
  v_nb_abs integer := 0;
  v_nb_dep integer := 0;
  v_presence record;
  v_litige_id uuid;
  v_type_litige public.type_litige;
  v_motif text;
  v_notif_corps text;
BEGIN
  SELECT pl.valeur::integer
    INTO v_delai_pointage_h
    FROM public.parametres_litiges pl
   WHERE pl.cle = 'delai_contestation_pointage_h';

  FOR v_presence IN
    SELECT p.id AS presence_id,
           p.mission_id,
           p.soignant_id,
           p.heures_reelles,
           m.duree_heures,
           m.etablissement_id,
           m.soignant_assigne_id
      FROM public.presences p
      JOIN public.missions m ON m.id = p.mission_id
     WHERE private.fn_mission_est_reelle(p.mission_id)
       AND p.valide_par_etablissement IS TRUE
       AND p.valide_le IS NOT NULL
       AND p.valide_le <
         now() - make_interval(hours => v_delai_pointage_h)
       AND p.motif_litige IS NOT NULL
       AND p.litige_auto_cree_le IS NULL
  LOOP
    IF v_presence.heures_reelles IS NULL
       OR v_presence.heures_reelles = 0 THEN
      v_type_litige := 'ABSENCE_SOIGNANT';
      v_motif := format(
        'Auto-création : soignant marqué absent sans contestation dans les %sh',
        v_delai_pointage_h
      );
      v_notif_corps :=
        'Votre établissement a signalé une absence.';
    ELSIF v_presence.duree_heures IS NOT NULL
      AND v_presence.duree_heures > 0
      AND v_presence.heures_reelles < v_presence.duree_heures * 0.80
    THEN
      v_type_litige := 'DEPART_ANTICIPE';
      v_motif := format(
        'Auto-création : départ anticipé (%sh effectuées sur %sh prévues, soit %s %%).',
        v_presence.heures_reelles,
        v_presence.duree_heures,
        round(
          (v_presence.heures_reelles / v_presence.duree_heures) * 100
        )
      );
      v_notif_corps :=
        'Votre établissement a signalé un départ anticipé.';
    ELSE
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1
        FROM public.litiges l
       WHERE l.mission_id = v_presence.mission_id
         AND l.type_litige = v_type_litige
         AND l.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION')
    ) THEN
      UPDATE public.presences
         SET litige_auto_cree_le = now()
       WHERE id = v_presence.presence_id;
      CONTINUE;
    END IF;

    INSERT INTO public.litiges (
      mission_id,
      soignant_id,
      etablissement_id,
      presence_id,
      initie_par,
      motif,
      statut,
      type_litige,
      est_informatif
    ) VALUES (
      v_presence.mission_id,
      COALESCE(v_presence.soignant_assigne_id, v_presence.soignant_id),
      v_presence.etablissement_id,
      v_presence.presence_id,
      'SYSTEME',
      v_motif,
      'OUVERT',
      v_type_litige,
      false
    )
    RETURNING id INTO v_litige_id;

    UPDATE public.presences
       SET litige_auto_cree_le = now()
     WHERE id = v_presence.presence_id;

    PERFORM public.fn_ecrire_audit(
      NULL,
      'SYSTEM',
      'LITIGE_AUTO_CREATION',
      'litige',
      v_litige_id,
      NULL,
      jsonb_build_object(
        'type_litige', v_type_litige,
        'mission_id', v_presence.mission_id,
        'presence_id', v_presence.presence_id,
        'heures_reelles', v_presence.heures_reelles,
        'duree_heures_prevues', v_presence.duree_heures,
        'raison', CASE v_type_litige
          WHEN 'ABSENCE_SOIGNANT' THEN
            format(
              'Absence non contestée dans les %sh post-validation présence',
              v_delai_pointage_h
            )
          WHEN 'DEPART_ANTICIPE' THEN
            format(
              'Départ anticipé (< 80 %% heures prévues) non contesté dans les %sh',
              v_delai_pointage_h
            )
        END
      ),
      NULL,
      NULL
    );

    PERFORM public.fn_litige_push_notification(
      COALESCE(v_presence.soignant_assigne_id, v_presence.soignant_id),
      'SOIGNANT',
      'LITIGE_OUVERTURE',
      'Litige ouvert sur votre mission',
      v_notif_corps,
      v_litige_id,
      jsonb_build_object(
        'type_litige', v_type_litige,
        'mission_id', v_presence.mission_id,
        'auto_cree', true
      )
    );

    IF v_type_litige = 'ABSENCE_SOIGNANT' THEN
      v_nb_abs := v_nb_abs + 1;
    ELSE
      v_nb_dep := v_nb_dep + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'litiges_crees', v_nb_abs + v_nb_dep,
    'absence_soignant', v_nb_abs,
    'depart_anticipe', v_nb_dep
  );
END;
$fn_auto_creation_litiges_presence$;

-- ── 2. SMS LITIGE_OUVERTURE : promesse « Répondez sous 72h » retirée ───────
CREATE OR REPLACE FUNCTION public.fn_litige_push_notification(
  p_destinataire_id uuid,
  p_type_destinataire text,
  p_type_notif text,
  p_titre text,
  p_corps text,
  p_litige_id uuid,
  p_email_data jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn_litige_push_notification$
DECLARE
  v_telephone text;
  v_sms_eligible boolean;
  v_sms_contenu text;
  v_lien text;
  v_mission_reelle boolean := false;
BEGIN
  v_lien := CASE p_type_destinataire
    WHEN 'SOIGNANT' THEN '/soignant/litiges'
    WHEN 'ETABLISSEMENT' THEN '/etablissement/litiges'
    WHEN 'ADMIN' THEN '/admin/moderation'
    ELSE NULL
  END;

  INSERT INTO public.notifications (
    destinataire_id,
    type_destinataire,
    type,
    titre,
    corps,
    id_ressource,
    type_ressource,
    lien
  ) VALUES (
    p_destinataire_id,
    p_type_destinataire,
    p_type_notif,
    p_titre,
    p_corps,
    p_litige_id,
    'litige',
    v_lien
  );

  SELECT private.fn_mission_est_reelle(l.mission_id)
    INTO v_mission_reelle
    FROM public.litiges l
   WHERE l.id = p_litige_id;

  IF v_mission_reelle IS DISTINCT FROM true THEN
    RETURN;
  END IF;

  INSERT INTO public.email_queue (type, destinataire_id, data)
  VALUES (
    p_type_notif,
    p_destinataire_id,
    p_email_data || jsonb_build_object(
      'litige_id', p_litige_id,
      'url_litige', v_lien
    )
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
    SELECT s.telephone
      INTO v_telephone
      FROM public.soignants s
     WHERE s.id = p_destinataire_id;
  ELSIF p_type_destinataire = 'ETABLISSEMENT' THEN
    SELECT e.telephone_contact
      INTO v_telephone
      FROM public.etablissements e
     WHERE e.id = p_destinataire_id;
  END IF;

  IF v_telephone IS NULL OR length(trim(v_telephone)) < 10 THEN
    RETURN;
  END IF;

  v_sms_contenu := CASE p_type_notif
    WHEN 'LITIGE_OUVERTURE' THEN
      'un litige '
        || COALESCE(p_email_data ->> 'type_litige', '')
        || ' a été ouvert sur votre mission.'
    WHEN 'REMBOURSEMENT_CONFIRME' THEN
      'remboursement de '
        || COALESCE(p_email_data ->> 'montant', '?')
        || '€ effectué (avoir '
        || COALESCE(p_email_data ->> 'numero_avoir', '')
        || '). Délai bancaire 2-5j.'
    WHEN 'LITIGE_RAPPEL_J1' THEN
      'litige en attente depuis 1j. Répondez sous 24h pour éviter l''escalade.'
    WHEN 'LITIGE_RAPPEL_J3' THEN
      'litige en attente depuis 3j. Réponse urgente requise.'
    WHEN 'LITIGE_RAPPEL_J5' THEN
      'litige en attente depuis 5j ouvrés. Escalade imminente.'
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
$fn_litige_push_notification$;

-- ── 3. Commentaire : le délai est celui du paramètre ────────────────────────
COMMENT ON FUNCTION public.fn_auto_creation_litiges_presence() IS 'Cron : crée automatiquement des litiges ABSENCE_SOIGNANT (heures_reelles=0/NULL) et DEPART_ANTICIPE (< 80 % des heures prévues) pour les présences non contestées dans le délai parametres_litiges.delai_contestation_pointage_h post-validation étab. Anti-boucle via presences.litige_auto_cree_le. initie_par=SYSTEME. Retourne { litiges_crees, absence_soignant, depart_anticipe }. Cas DESACCORD_HEURES_POINTAGE non auto-détectable (schéma presences mono-colonne) — reste manuel via fn_ouvrir_litige_rate_limited.';

-- ── 4. Post-condition : corps écrits, attributs et ACL inchangés ───────────
DO $litiges_textes_delais_apres$
DECLARE
  v_attendu record;
  v_proc record;
  v_fragment text;
BEGIN
  FOR v_attendu IN
    SELECT * FROM (VALUES
      ('fn_auto_creation_litiges_presence()', '43e9244304a10b0206650e94f7e94153',
       ARRAY['48h', 'Répondez sous']::text[]),
      ('fn_litige_push_notification(uuid,text,text,text,text,uuid,jsonb)', '1c06d468f9c4e92c449c3570016a3608',
       ARRAY['Répondez sous 72h']::text[])
    ) AS t(signature, empreinte, interdits)
  LOOP
    SELECT p.oid, p.prosrc, p.prosecdef, p.provolatile::text AS volatilite,
           p.proconfig, p.proacl, p.proowner,
           pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
      INTO v_proc
      FROM pg_catalog.pg_proc p
     WHERE p.oid = pg_catalog.to_regprocedure('public.' || v_attendu.signature);
    IF NOT FOUND
      OR pg_catalog.md5(v_proc.prosrc) IS DISTINCT FROM v_attendu.empreinte
      OR v_proc.proprietaire IS DISTINCT FROM 'postgres'
      OR v_proc.prosecdef IS NOT TRUE
      OR v_proc.volatilite IS DISTINCT FROM 'v'
      OR v_proc.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
    THEN
      RAISE EXCEPTION 'LITIGES_TEXTES_DELAIS_POSTCONDITION : public.% (md5 % au lieu de %).',
        v_attendu.signature,
        COALESCE(pg_catalog.md5(v_proc.prosrc), 'fonction absente'),
        v_attendu.empreinte;
    END IF;
    FOREACH v_fragment IN ARRAY v_attendu.interdits LOOP
      IF pg_catalog.strpos(v_proc.prosrc, v_fragment) > 0 THEN
        RAISE EXCEPTION 'LITIGES_TEXTES_DELAIS_POSTCONDITION : public.% contient encore « % ».',
          v_attendu.signature, v_fragment;
      END IF;
    END LOOP;
    IF pg_catalog.has_function_privilege('anon', v_proc.oid, 'EXECUTE')
      OR pg_catalog.has_function_privilege('authenticated', v_proc.oid, 'EXECUTE')
      OR NOT pg_catalog.has_function_privilege('service_role', v_proc.oid, 'EXECUTE')
      OR EXISTS (
        SELECT FROM pg_catalog.aclexplode(COALESCE(v_proc.proacl, pg_catalog.acldefault('f', v_proc.proowner))) a
         WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
    THEN
      RAISE EXCEPTION 'LITIGES_TEXTES_DELAIS_POSTCONDITION_ACL : public.%', v_attendu.signature;
    END IF;
  END LOOP;

  IF pg_catalog.obj_description(
       pg_catalog.to_regprocedure('public.fn_auto_creation_litiges_presence()'), 'pg_proc')
     IS DISTINCT FROM 'Cron : crée automatiquement des litiges ABSENCE_SOIGNANT (heures_reelles=0/NULL) et DEPART_ANTICIPE (< 80 % des heures prévues) pour les présences non contestées dans le délai parametres_litiges.delai_contestation_pointage_h post-validation étab. Anti-boucle via presences.litige_auto_cree_le. initie_par=SYSTEME. Retourne { litiges_crees, absence_soignant, depart_anticipe }. Cas DESACCORD_HEURES_POINTAGE non auto-détectable (schéma presences mono-colonne) — reste manuel via fn_ouvrir_litige_rate_limited.'
  THEN
    RAISE EXCEPTION 'LITIGES_TEXTES_DELAIS_POSTCONDITION_COMMENTAIRE';
  END IF;
END
$litiges_textes_delais_apres$;
