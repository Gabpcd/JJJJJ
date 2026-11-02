-- B9 — app iOS native, lot 3, tranche B3 : contestation d'un paiement déclaré
-- exécutable et idempotente. Paiements : jamais d'auto-merge, go explicite de
-- Gabrielle requis (CLAUDE.md, B9). Préalable à la tranche T13.
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
-- Correctif (option D19, LOT3_PLAN.md §7 décision 19 et §3 B3 corrigé v2) :
--   - aucun DDL : le CHECK des notifications reste la définition LIVE (vérifiée
--     par le postflight) ; l'INSERT CONTESTATION_PAIEMENT est retiré, car
--     trg_notifier_creation_litige (dec_notifier_creation_litige) notifie déjà
--     l'établissement en LITIGE_OUVERT pour tout litige initié par le soignant ;
--     le motif reste lisible dans litiges.motif (« Paiement contesté — … ») ;
--   - fonction redéfinie depuis le corps LIVE : compte authentifié actif
--     (fn_compte_auth_actif), motif obligatoire de 1 à 500 caractères (bornes des
--     deux clients ; char_length après btrim, donc en points de code Unicode),
--     ligne verrouillée FOR UPDATE, statut DECLARE ou EN_ATTENTE
--     (comme fn_confirmer_paiement_soignant), second appel refusé sans second
--     litige, collision de litige restituée en erreur structurée sans écriture ;
--     textes du litige, de la notification admin et des erreurs historiques
--     inchangés ; error_code ajouté à côté de chaque error (le web ne lit que
--     error).
--   - Propriétaire, ACL, search_path et catégorie d'inventaire inchangés
--     (CREATE OR REPLACE) ; seule l'empreinte d'inventaire suit le nouveau corps.
--
-- Comportement historique conservé (hors périmètre B3) : le litige est créé
-- avec facture_id NULL, même quand le paiement porte facture_honoraire_id ; il
-- n'y a donc ni gel ni traçage de la facture, et l'index legacy s'applique. Un
-- litige AUTRE sans facture déjà ouvert sur la mission (présence, par exemple)
-- bloque la contestation : choix « erreur LITIGE_DEJA_OUVERT » plutôt que
-- rattachement du paiement à ce litige.
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

-- ── 1. Fonction : gardes, verrou et idempotence depuis le corps LIVE ────────
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

    -- L'établissement est notifié par trg_notifier_creation_litige (LITIGE_OUVERT,
    -- litige initié par le soignant) : aucune notification dédiée ici.

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

-- ── 2. Inventaire SECURITY DEFINER : seule l'empreinte suit le corps ────────
UPDATE private.security_definer_inventory
SET definition_md5 = (SELECT md5(p.prosrc) FROM pg_proc p
      WHERE p.oid = 'public.fn_contester_paiement_soignant(uuid,text)'::regprocedure),
    justification = 'RPC mixte : branche tenant (auth.uid, compte actif, paiement verrouillé du soignant appelant, statut DECLARE ou EN_ATTENTE, motif 1 à 500, litige unique, établissement notifié par trg_notifier_creation_litige) et notification admin (admin_plateforme) conservée. Source : migration B3 contestation_paiement_soignant (lot 3 iOS)',
    recense_le = now()
WHERE signature IN ('fn_contester_paiement_soignant(uuid,text)',
                    'public.fn_contester_paiement_soignant(uuid,text)')
  AND definition_md5 = 'fbd951f42e23cf3d8ea13b47bb442325';

DO $contestation_postflight$
DECLARE
  v_fn constant regprocedure := 'public.fn_contester_paiement_soignant(uuid,text)'::regprocedure;
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = v_fn)
       IS DISTINCT FROM '368f41ca6e0157cd48ebbf6a638cecae'
    OR (SELECT p.proconfig FROM pg_proc p WHERE p.oid = v_fn)
       IS DISTINCT FROM ARRAY['search_path=public']::text[]
    OR (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = v_fn) IS DISTINCT FROM true
    OR (SELECT pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid = v_fn) IS DISTINCT FROM 'postgres'
    OR has_function_privilege('anon', v_fn, 'EXECUTE')
    OR NOT has_function_privilege('authenticated', v_fn, 'EXECUTE')
    OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTESTATION_CORPS_OU_ACL_INATTENDU';
  END IF;
  -- Option D19 : le CHECK des notifications reste la définition LIVE relue.
  IF (SELECT md5(pg_get_constraintdef(c.oid)) FROM pg_constraint c
      WHERE c.conrelid = 'public.notifications'::regclass
        AND c.conname = 'notifications_type_check'
        AND c.contype = 'c' AND c.convalidated)
       IS DISTINCT FROM '9abaa9884a7cba5a880244fb4a877d8c' THEN
    RAISE EXCEPTION 'CONTESTATION_CHECK_NOTIFICATIONS_MODIFIE : repartir de pg_get_constraintdef LIVE';
  END IF;
  IF EXISTS (SELECT 1 FROM private.security_definer_inventory
      WHERE signature IN ('fn_contester_paiement_soignant(uuid,text)',
                          'public.fn_contester_paiement_soignant(uuid,text)')
        AND (definition_md5 IS DISTINCT FROM '368f41ca6e0157cd48ebbf6a638cecae'
             OR categorie IS DISTINCT FROM 'MIXTE_TENANT_ADMIN')) THEN
    RAISE EXCEPTION 'CONTESTATION_INVENTAIRE_NON_ALIGNE';
  END IF;
END;
$contestation_postflight$;
