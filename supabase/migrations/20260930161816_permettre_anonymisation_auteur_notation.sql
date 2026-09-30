-- Définitions LIVE relues le 30/09/2026. Réparer l'état déjà prévu par
-- fn_trg_anonymiser_notations_suppression sans supprimer de notes ni toucher
-- à la cible, aux délais ou à la publication. Pas de GRANT ni de politique RLS.
-- Le trigger, ses deux attachements et son empreinte restent inchangés.
DO $preflight$
DECLARE v_signature text; v_avant text; v_apres text; v_categorie text; p record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.notations_missions'::regclass
      AND attname='note_id' AND atttypid='uuid'::regtype AND attnotnull AND NOT attisdropped)
    OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.notations_missions'::regclass
      AND attname='notateur_id' AND atttypid='uuid'::regtype AND NOT attisdropped
      AND (attnotnull OR EXISTS (SELECT 1 FROM pg_constraint
        WHERE conrelid='public.notations_missions'::regclass AND conname='notations_missions_auteur_anonymise_check'
          AND pg_get_constraintdef(oid)='CHECK (((notateur_id IS NOT NULL) OR (notateur_anonymise IS TRUE)))')))
    OR EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.notations_missions'::regclass
      AND conname='notations_missions_auteur_anonymise_check'
      AND (NOT convalidated OR pg_get_constraintdef(oid) IS DISTINCT FROM
        'CHECK (((notateur_id IS NOT NULL) OR (notateur_anonymise IS TRUE)))'))
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.fn_trg_anonymiser_notations_suppression()'::regprocedure
      AND md5(prosrc)='c1075608a0b29574cd78451c8e9e703d'
      AND proacl='{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
      AND prosecdef AND pg_get_userbyid(proowner)='postgres') THEN
    RAISE EXCEPTION 'Anonymisation notation : schéma ou trigger inattendu';
  END IF;
  FOR v_signature,v_avant,v_apres,v_categorie IN VALUES
    ('fn_modifier_notation_mission(uuid,integer,integer,integer,integer,text)','519608bb01e325189ce23f860d9e2794','63f28d2ca3ad4580538aa7de55020edb','MIXTE_TENANT_ADMIN'),
    ('fn_signaler_notation(uuid,text)','2cc5ec80ff301f99ae0e488e9e0578b0','4f58a286981573d8b1096568af11d2f8','RPC_UTILISATEUR_AUTH_INTERNE')
  LOOP
    SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure('public.'||v_signature);
    IF NOT FOUND OR md5(p.prosrc) NOT IN (v_avant,v_apres)
      OR p.prosecdef IS DISTINCT FROM true OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
      OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public, extensions']::text[]
      OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[]
      OR NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i
        WHERE i.signature=v_signature AND i.categorie=v_categorie AND i.definition_md5 IN(v_avant,v_apres)) THEN
      RAISE EXCEPTION 'Anonymisation notation : définition, droits ou inventaire divergent pour %',v_signature;
    END IF;
  END LOOP;
END;
$preflight$;

ALTER TABLE public.notations_missions ALTER COLUMN notateur_id DROP NOT NULL;
DO $contrainte$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.notations_missions'::regclass
    AND conname='notations_missions_auteur_anonymise_check') THEN
    ALTER TABLE public.notations_missions ADD CONSTRAINT notations_missions_auteur_anonymise_check
      CHECK (notateur_id IS NOT NULL OR notateur_anonymise IS TRUE);
  END IF;
END;
$contrainte$;

CREATE OR REPLACE FUNCTION public.fn_modifier_notation_mission(p_notation_id uuid, p_critere_1 integer, p_critere_2 integer, p_critere_3 integer, p_critere_4 integer, p_commentaire text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID;
  v_admin BOOLEAN;
  v_notation RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Compte suspendu, supprimé ou désactivé');
  END IF;
  v_etab_id := public.mon_etablissement_id();
  v_admin := public.est_admin() IS TRUE;

  IF p_critere_1 NOT BETWEEN 1 AND 5 OR p_critere_2 NOT BETWEEN 1 AND 5
     OR p_critere_3 NOT BETWEEN 1 AND 5 OR p_critere_4 NOT BETWEEN 1 AND 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Critères doivent être entre 1 et 5');
  END IF;

  IF p_commentaire IS NOT NULL AND LENGTH(p_commentaire) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Commentaire max 2000 caractères');
  END IF;

  -- Un auteur anonymisé ne confère aucun droit à un tiers. Le verrou évite
  -- qu'une anonymisation concurrente change l'auteur entre contrôle et écriture.
  SELECT n.* INTO v_notation FROM public.notations_missions n
  WHERE n.id = p_notation_id AND (
    v_admin OR (n.notateur_id IS NOT NULL AND (
      n.notateur_id IS NOT DISTINCT FROM v_uid
      OR (v_etab_id IS NOT NULL AND n.notateur_id IS NOT DISTINCT FROM v_etab_id)
    ))
  ) FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error',
      CASE WHEN v_admin THEN 'Notation introuvable' ELSE 'Accès refusé' END);
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
    p_acteur_id := COALESCE(v_notation.notateur_id, v_uid),
    p_type_acteur := CASE WHEN v_notation.sens = 'ETAB_VERS_SOIGNANT' THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'NOTATION_DONNEE',
    p_type_ressource := 'mission',
    p_id_ressource := v_notation.mission_id,
    p_details := jsonb_build_object('notation_id', p_notation_id, 'sens', v_notation.sens::text, 'modification', true)
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_signaler_notation(p_notation_id uuid, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID;
  v_notation RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Compte suspendu, supprimé ou désactivé');
  END IF;
  v_etab_id := public.mon_etablissement_id();

  -- Seule la cible canonique peut signaler, y compris après anonymisation
  -- de l'auteur. Aucun privilège supplémentaire pour un administrateur.
  SELECT n.* INTO v_notation FROM public.notations_missions n
  WHERE n.id = p_notation_id AND n.note_id IS NOT NULL AND (
    n.note_id IS NOT DISTINCT FROM v_uid
    OR (v_etab_id IS NOT NULL AND n.note_id IS NOT DISTINCT FROM v_etab_id)
  ) FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous ne pouvez signaler que les notations vous concernant');
  END IF;

  IF v_notation.signale = true THEN
    RETURN jsonb_build_object('success', false, 'error', 'Notation déjà signalée');
  END IF;

  UPDATE notations_missions SET signale = true, mis_a_jour_le = NOW()
  WHERE id = p_notation_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := CASE WHEN v_etab_id IS NOT NULL THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'NOTATION_SIGNALE',
    p_type_ressource := 'notation',
    p_id_ressource := p_notation_id,
    p_details := jsonb_build_object('motif', p_motif, 'mission_id', v_notation.mission_id)
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

UPDATE private.security_definer_inventory SET definition_md5='63f28d2ca3ad4580538aa7de55020edb',
  justification='Compte actif puis auteur canonique ou administrateur valide ; auteur NULL ne confère aucun accès.', recense_le=now()
WHERE signature='fn_modifier_notation_mission(uuid,integer,integer,integer,integer,text)' AND categorie='MIXTE_TENANT_ADMIN'
  AND definition_md5 IN ('519608bb01e325189ce23f860d9e2794','63f28d2ca3ad4580538aa7de55020edb');
UPDATE private.security_definer_inventory SET definition_md5='4f58a286981573d8b1096568af11d2f8',
  justification='Compte actif puis cible canonique ; refus NULL-safe avant lecture métier et sans privilège admin supplémentaire.', recense_le=now()
WHERE signature='fn_signaler_notation(uuid,text)' AND categorie='RPC_UTILISATEUR_AUTH_INTERNE'
  AND definition_md5 IN ('2cc5ec80ff301f99ae0e488e9e0578b0','4f58a286981573d8b1096568af11d2f8');

DO $postflight$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i JOIN pg_proc p
    ON p.oid=to_regprocedure('public.'||i.signature) WHERE i.signature='fn_modifier_notation_mission(uuid,integer,integer,integer,integer,text)'
      AND i.definition_md5='63f28d2ca3ad4580538aa7de55020edb' AND md5(p.prosrc)='63f28d2ca3ad4580538aa7de55020edb')
  THEN RAISE EXCEPTION 'Empreinte finale notation divergente'; END IF;
  IF NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i JOIN pg_proc p
    ON p.oid=to_regprocedure('public.'||i.signature) WHERE i.signature='fn_signaler_notation(uuid,text)'
      AND i.definition_md5='4f58a286981573d8b1096568af11d2f8' AND md5(p.prosrc)='4f58a286981573d8b1096568af11d2f8')
  THEN RAISE EXCEPTION 'Empreinte finale notation divergente'; END IF;
END;
$postflight$;
