-- B9 — app iOS native, lot 3, tranche B3 : contestation d'un paiement déclaré
-- exécutable et idempotente. Paiements + DROP CONSTRAINT : jamais d'auto-merge,
-- go explicite de Gabrielle requis (CLAUDE.md, B9). Préalable à la tranche T13.
--
-- Départ : définitions LIVE de production relues le 02/11/2026 (garde-fou 9.0
-- n°2), identiques à supabase/schema/public.sql et capturées dans
-- tests/fixtures/contestation-paiement-live-20261102.json :
--   - fn_contester_paiement_soignant : md5(prosrc) fbd951f42e23cf3d8ea13b47bb442325 ;
--   - notifications_type_check : md5(pg_get_constraintdef) 9abaa9884a7cba5a880244fb4a877d8c.
--
-- Défauts corrigés :
--   1. La fonction insère une notification CONTESTATION_PAIEMENT absente du CHECK
--      des notifications : violation 23514, toute la contestation est annulée,
--      sur le web comme dans l'app (même famille que l'incident Lot 13
--      CONTESTATION_PRESENCE).
--   2. Aucune garde de compte, de motif, de statut ni d'idempotence : UPDATE
--      inconditionnel ; un second appel, ou une contestation alors qu'un litige
--      AUTRE sans facture est déjà ouvert sur la mission, échoue en 23505 sur
--      uq_litige_mission_type_ouvert_legacy.
--
-- Correctif :
--   - CHECK des notifications = liste LIVE (57 types, ordre conservé) suivie de
--     CONTESTATION_PAIEMENT ;
--   - fonction redéfinie depuis le corps LIVE : compte authentifié actif
--     (fn_compte_auth_actif), motif obligatoire de 1 à 500 caractères (bornes des
--     deux clients), ligne verrouillée FOR UPDATE, statut DECLARE ou EN_ATTENTE
--     (comme fn_confirmer_paiement_soignant), second appel refusé sans second
--     litige, collision de litige restituée en erreur structurée sans écriture ;
--     textes du litige, des notifications et des erreurs historiques inchangés ;
--     error_code ajouté à côté de chaque error (le web ne lit que error).
--   - Propriétaire, ACL, search_path et catégorie d'inventaire inchangés
--     (CREATE OR REPLACE) ; seule l'empreinte d'inventaire suit le nouveau corps.
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

DO $contestation_preflight$
DECLARE
  v_fn constant regprocedure := 'public.fn_contester_paiement_soignant(uuid,text)'::regprocedure;
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = v_fn)
       IS DISTINCT FROM 'fbd951f42e23cf3d8ea13b47bb442325'
    OR (SELECT p.proconfig FROM pg_proc p WHERE p.oid = v_fn)
       IS DISTINCT FROM ARRAY['search_path=public']::text[]
    OR (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = v_fn) IS DISTINCT FROM true
    OR (SELECT pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid = v_fn) IS DISTINCT FROM 'postgres'
    OR has_function_privilege('anon', v_fn, 'EXECUTE')
    OR NOT has_function_privilege('authenticated', v_fn, 'EXECUTE')
    OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTESTATION_SOURCE_OU_ACL_MODIFIEE : repartir de la définition LIVE';
  END IF;
  IF (SELECT md5(pg_get_constraintdef(c.oid)) FROM pg_constraint c
      WHERE c.conrelid = 'public.notifications'::regclass
        AND c.conname = 'notifications_type_check'
        AND c.contype = 'c' AND c.convalidated)
       IS DISTINCT FROM '9abaa9884a7cba5a880244fb4a877d8c' THEN
    RAISE EXCEPTION 'CONTESTATION_CHECK_NOTIFICATIONS_MODIFIE : repartir de pg_get_constraintdef LIVE';
  END IF;
  -- Si l'inventaire connaît cette fonction, il doit décrire le corps LIVE.
  IF EXISTS (SELECT 1 FROM private.security_definer_inventory
      WHERE signature IN ('fn_contester_paiement_soignant(uuid,text)',
                          'public.fn_contester_paiement_soignant(uuid,text)')
        AND (definition_md5 IS DISTINCT FROM 'fbd951f42e23cf3d8ea13b47bb442325'
             OR categorie IS DISTINCT FROM 'MIXTE_TENANT_ADMIN')) THEN
    RAISE EXCEPTION 'CONTESTATION_INVENTAIRE_MODIFIE';
  END IF;
END;
$contestation_preflight$;

-- ── 1. CHECK notifications : liste LIVE + CONTESTATION_PAIEMENT ─────────────
ALTER TABLE public.notifications
  DROP CONSTRAINT notifications_type_check,
  ADD CONSTRAINT notifications_type_check CHECK (type = ANY (ARRAY[
    'CANDIDATURE_ACCEPTEE', 'CANDIDATURE_REFUSEE', 'CANDIDATURE_PROPOSEE', 'CANDIDATURE_RECUE',
    'MISSION_ACCEPTEE', 'MISSION_ANNULEE', 'MISSION_TERMINEE', 'MISSION_URGENTE',
    'MISSION_NON_POURVUE', 'MISSION_ASSIGNEE', 'MISSION_A_POURVOIR', 'CONTRAT_A_SIGNER',
    'CONTRAT_SIGNE', 'FACTURE_EMISE', 'FACTURE_PAYEE', 'DOCUMENT_EXPIRANT', 'RAPPEL_DOCUMENTS',
    'DOCUMENT_VERIFIE', 'DOCUMENT_REJETE', 'MESSAGE_RECU', 'MESSAGE_ADMIN', 'POINTAGE_ARRIVEE',
    'POINTAGE_DEPART', 'EVALUATION_RECUE', 'PARRAINAGE', 'CREDIT_PARRAINAGE',
    'PARRAINAGE_PRIME_VERSEE', 'RAPPEL_MISSION', 'RAPPEL_CANDIDATURES', 'POOL_URGENCE',
    'POOL_URGENCE_ACCEPTATION', 'SYSTEM', 'LITIGE_OUVERT', 'LITIGE_REPONSE', 'LITIGE_RESOLU',
    'LITIGE_MEDIATION', 'LITIGE_RESOLU_AJUSTE', 'LITIGE_ESCALADE_ADMIN',
    'LITIGE_MEDIATION_PRIORITAIRE', 'LITIGE_RAPPEL_J1', 'LITIGE_RAPPEL_J3', 'LITIGE_RAPPEL_J5',
    'CHORUS_DEPOSEE', 'CHORUS_MISE_A_DISPOSITION', 'CHORUS_PAIEMENT_EN_COURS',
    'CHORUS_PAIEMENT_COMPTABILISE', 'CHORUS_REJETEE', 'FAVORI_NOUVELLE_MISSION', 'AVOIR_EMIS',
    'COMMISSION_AJUSTEE', 'REMBOURSEMENT_MANUEL_A_FAIRE', 'REMBOURSEMENT_CONFIRME',
    'MATCHING_SUPER_LIKE', 'FAVORI_MISSION_EXPIRE', 'RAPPEL_VALIDATION_PRESENCE',
    'CONTESTATION_PRESENCE', 'PRESENCE_VALIDEE', 'CONTESTATION_PAIEMENT'
  ]));

-- ── 2. Fonction : gardes, verrou et idempotence depuis le corps LIVE ────────
CREATE OR REPLACE FUNCTION public.fn_contester_paiement_soignant(p_paiement_id uuid, p_motif text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn_contester$
DECLARE
    v_uid UUID := auth.uid();
    v_motif TEXT := btrim(COALESCE(p_motif, ''));
    v_paiement public.paiements_soignant%ROWTYPE;
    v_litige_id UUID;
    v_contrainte TEXT;
BEGIN
    -- Appelant authentifié dont le compte est actif (ni supprimé ni suspendu).
    IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
        RETURN jsonb_build_object('error', 'Non authentifié ou compte inactif', 'error_code', 'NON_AUTHENTIFIE');
    END IF;
    -- Motif obligatoire, borné comme les clients (web maxLength 500, natif).
    IF v_motif = '' THEN
        RETURN jsonb_build_object('error', 'Motif requis', 'error_code', 'MOTIF_INVALIDE');
    END IF;
    IF char_length(v_motif) > 500 THEN
        RETURN jsonb_build_object('error', 'Motif trop long (500 caractères maximum)', 'error_code', 'MOTIF_INVALIDE');
    END IF;

    -- Verrou de ligne : deux contestations simultanées du même paiement sont
    -- sérialisées ; la seconde relit CONTESTE et s'arrête sans écrire.
    SELECT * INTO v_paiement
    FROM public.paiements_soignant
    WHERE id = p_paiement_id
    FOR UPDATE;
    IF v_paiement.id IS NULL THEN
        RETURN jsonb_build_object('error', 'Paiement introuvable', 'error_code', 'PAIEMENT_INTROUVABLE');
    END IF;
    IF v_paiement.soignant_id IS DISTINCT FROM v_uid THEN
        RETURN jsonb_build_object('error', 'Accès refusé', 'error_code', 'ACCES_REFUSE');
    END IF;
    -- Idempotence : un paiement déjà contesté ne crée jamais un second litige.
    IF v_paiement.statut = 'CONTESTE' OR v_paiement.conteste IS TRUE THEN
        RETURN jsonb_build_object('error', 'Paiement déjà contesté', 'error_code', 'DEJA_CONTESTE');
    END IF;
    IF v_paiement.confirme_par_soignant IS TRUE THEN
        RETURN jsonb_build_object('error', 'Paiement déjà confirmé', 'error_code', 'DEJA_CONFIRME');
    END IF;
    IF v_paiement.statut NOT IN ('DECLARE', 'EN_ATTENTE') THEN
        RETURN jsonb_build_object(
            'error', 'Ce paiement ne peut plus être contesté (statut: ' || v_paiement.statut || ')',
            'error_code', 'STATUT_INVALIDE'
        );
    END IF;

    -- Paiement et litige sont écrits ensemble ou pas du tout.
    BEGIN
        -- Marquer le paiement contesté
        UPDATE public.paiements_soignant SET
            conteste = TRUE,
            motif_contestation = v_motif,
            statut = 'CONTESTE',
            modifie_le = NOW()
        WHERE id = p_paiement_id;

        -- Créer automatiquement un litige
        INSERT INTO public.litiges (
            mission_id, soignant_id, etablissement_id, initie_par, motif,
            statut, paiement_soignant_id
        ) VALUES (
            v_paiement.mission_id,
            v_paiement.soignant_id,
            v_paiement.etablissement_id,
            'SOIGNANT',
            'Paiement contesté — ' || v_motif,
            'OUVERT',
            p_paiement_id
        ) RETURNING id INTO v_litige_id;
    EXCEPTION WHEN unique_violation THEN
        -- Un litige ouvert sans facture existe déjà sur la mission : le paiement
        -- reste tel quel (sous-bloc annulé) et l'appelant reçoit un refus net.
        GET STACKED DIAGNOSTICS v_contrainte = CONSTRAINT_NAME;
        IF v_contrainte IS DISTINCT FROM 'uq_litige_mission_type_ouvert_legacy' THEN
            RAISE;
        END IF;
        RETURN jsonb_build_object(
            'error', 'Un litige de ce type est déjà ouvert pour cette mission.',
            'error_code', 'LITIGE_DEJA_OUVERT'
        );
    END;

    -- Notifier l'établissement
    INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
    VALUES (
        v_paiement.etablissement_id,
        'CONTESTATION_PAIEMENT',
        'Paiement contesté ⚠️',
        'Le soignant conteste un paiement. Motif : ' || v_motif,
        '/etablissement/facturation',
        'ETABLISSEMENT',
        'litige',
        v_litige_id
    );

    -- Notifier l'admin
    INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
    SELECT id, 'SYSTEM', 'Paiement contesté ⚠️',
        'Un soignant conteste un paiement. Motif : ' || v_motif,
        '/admin/facturation', 'ADMIN', 'litige', v_litige_id
    FROM auth.users WHERE raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME'
    LIMIT 1;

    RETURN jsonb_build_object('success', true, 'litige_id', v_litige_id);
END;
$fn_contester$;

-- ── 3. Inventaire SECURITY DEFINER : seule l'empreinte suit le corps ────────
UPDATE private.security_definer_inventory
SET definition_md5 = (SELECT md5(p.prosrc) FROM pg_proc p
      WHERE p.oid = 'public.fn_contester_paiement_soignant(uuid,text)'::regprocedure),
    justification = 'RPC mixte : branche tenant (auth.uid, compte actif, paiement verrouillé du soignant appelant, statut DECLARE ou EN_ATTENTE, motif 1 à 500, litige unique) et notification admin (admin_plateforme) conservée. Source : migration B3 contestation_paiement_soignant (lot 3 iOS)',
    recense_le = now()
WHERE signature IN ('fn_contester_paiement_soignant(uuid,text)',
                    'public.fn_contester_paiement_soignant(uuid,text)')
  AND definition_md5 = 'fbd951f42e23cf3d8ea13b47bb442325';

DO $contestation_postflight$
DECLARE
  v_fn constant regprocedure := 'public.fn_contester_paiement_soignant(uuid,text)'::regprocedure;
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = v_fn)
       IS DISTINCT FROM 'c992ac5cea41693151dd38df0daf580f'
    OR (SELECT p.proconfig FROM pg_proc p WHERE p.oid = v_fn)
       IS DISTINCT FROM ARRAY['search_path=public']::text[]
    OR (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = v_fn) IS DISTINCT FROM true
    OR (SELECT pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid = v_fn) IS DISTINCT FROM 'postgres'
    OR has_function_privilege('anon', v_fn, 'EXECUTE')
    OR NOT has_function_privilege('authenticated', v_fn, 'EXECUTE')
    OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTESTATION_CORPS_OU_ACL_INATTENDU';
  END IF;
  IF (SELECT md5(pg_get_constraintdef(c.oid)) FROM pg_constraint c
      WHERE c.conrelid = 'public.notifications'::regclass
        AND c.conname = 'notifications_type_check'
        AND c.contype = 'c' AND c.convalidated)
       IS DISTINCT FROM '14541c0abd3dd26e884e66e9fda9c3fc' THEN
    RAISE EXCEPTION 'CONTESTATION_CHECK_NOTIFICATIONS_INATTENDU';
  END IF;
  IF EXISTS (SELECT 1 FROM private.security_definer_inventory
      WHERE signature IN ('fn_contester_paiement_soignant(uuid,text)',
                          'public.fn_contester_paiement_soignant(uuid,text)')
        AND (definition_md5 IS DISTINCT FROM 'c992ac5cea41693151dd38df0daf580f'
             OR categorie IS DISTINCT FROM 'MIXTE_TENANT_ADMIN')) THEN
    RAISE EXCEPTION 'CONTESTATION_INVENTAIRE_NON_ALIGNE';
  END IF;
END;
$contestation_postflight$;
