-- Signature manuscrite : mêmes parties et états terminaux que le parcours OTP.
-- Source : définitions LIVE production/staging relues le 19/10/2026 ; aucune
-- modification des contrats existants, paramètres, propriétaires ou ACL.
DO $canvas_before$
DECLARE f record;
BEGIN
  FOR f IN SELECT * FROM (VALUES
    ('public.fn_signer_contrat_etablissement(uuid,text)','843f2b048bf73674081c8291ddb1c7bb','MIXTE_TENANT_ADMIN'),
    ('public.fn_signer_contrat_soignant(uuid,text)','c93635fd3a389a0e5c21217c34abe023','RPC_UTILISATEUR_AUTH_INTERNE')
  ) x(signature,body_md5,categorie) LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid=to_regprocedure(f.signature) AND md5(p.prosrc)=f.body_md5
        AND p.prosecdef AND p.proowner='postgres'::regrole)
      OR NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i
        WHERE i.signature=replace(f.signature,'public.','') AND i.categorie=f.categorie AND i.definition_md5=f.body_md5)
    THEN RAISE EXCEPTION 'SIGNATURE_CANVAS_SOURCE_DIVERGENTE: %',f.signature; END IF;
  END LOOP;
END;
$canvas_before$;

CREATE OR REPLACE FUNCTION public.fn_signer_contrat_etablissement(p_contrat_id uuid, p_signature_image text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_contrat public.contrats_mission%ROWTYPE;
  v_document_hash text;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success',false,'error_code','NON_AUTHENTIFIE','error','Non authentifié ou compte inactif');
  END IF;

  SELECT * INTO v_contrat FROM public.contrats_mission
  WHERE id=p_contrat_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Contrat introuvable'); END IF;

  -- Une absence d'établissement ou de permission doit toujours refuser.
  -- Conserve l'autorisation administrative existante, sans confondre un rôle
  -- de navigation avec le droit de signer pour cet établissement précis.
  IF public.est_admin() IS NOT TRUE AND (
    public.fn_role_etablissement_courant(v_contrat.etablissement_id) IS NULL
    OR public.fn_a_permission_etablissement('contrats',v_contrat.etablissement_id) IS NOT TRUE
  ) THEN
    RETURN jsonb_build_object('success',false,'error_code','NON_AUTORISE','error','Ce contrat ne vous concerne pas');
  END IF;
  IF v_contrat.statut IS NULL OR v_contrat.statut IN ('ANNULE','EXPIRE','REFUSE') THEN
    RETURN jsonb_build_object('success',false,'error_code','CONTRAT_INACTIF','error','Ce contrat ne peut plus être signé.');
  END IF;
  IF v_contrat.signature_etablissement IS TRUE THEN RETURN jsonb_build_object('error','Déjà signé'); END IF;

  -- Identiques octets UTF-8 au document serveur courant : pas de régénération,
  -- de normalisation, de réécriture de contenu ni de modification d'anciennes preuves.
  v_document_hash := encode(extensions.digest(convert_to(v_contrat.contenu_html,'UTF8'),'sha256'),'hex');
  IF (
    v_contrat.contenu_html IS NOT NULL AND btrim(v_contrat.contenu_html)<>''
    AND v_contrat.contenu_html !~ '\{\{[[:space:]]*[^}]+[[:space:]]*\}\}'
    AND v_contrat.hash_document ~ '^[a-f0-9]{64}$'
    AND v_contrat.hash_document=v_document_hash
    AND NULLIF(btrim(v_contrat.storage_path),'') IS NOT NULL
    AND v_contrat.contenu_html_rendu_le IS NOT NULL
  ) IS NOT TRUE OR EXISTS (
    SELECT 1 FROM public.signatures_contrats sc
    WHERE sc.contrat_id=p_contrat_id AND sc.statut_signature='signe'
      AND sc.hash_document IS DISTINCT FROM v_document_hash
  ) THEN
    RETURN jsonb_build_object('success',false,'error_code','HASH_DOCUMENT_CHANGE',
      'error','Le document a changé ou sa preuve est indisponible. Rechargez la page avant de signer.');
  END IF;

  UPDATE public.contrats_mission SET
    signature_etablissement=true,
    signature_etablissement_le=now(),
    signature_image_etablissement=p_signature_image,
    signature_navigateur_etablissement=current_setting('request.headers',true)::json->>'user-agent',
    statut=CASE WHEN signature_soignant IS TRUE THEN 'SIGNE_COMPLET' ELSE 'SIGNE_ETABLISSEMENT' END,
    modifie_le=now()
  WHERE id=p_contrat_id;
  RETURN jsonb_build_object('success',true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_signer_contrat_soignant(p_contrat_id uuid, p_signature_image text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_contrat public.contrats_mission%ROWTYPE;
  v_document_hash text;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success',false,'error_code','NON_AUTHENTIFIE','error','Non authentifié ou compte inactif');
  END IF;

  SELECT * INTO v_contrat FROM public.contrats_mission
  WHERE id=p_contrat_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Contrat introuvable'); END IF;
  IF v_contrat.soignant_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success',false,'error_code','NON_AUTORISE','error','Ce contrat ne vous concerne pas');
  END IF;
  IF v_contrat.statut IS NULL OR v_contrat.statut IN ('ANNULE','EXPIRE','REFUSE') THEN
    RETURN jsonb_build_object('success',false,'error_code','CONTRAT_INACTIF','error','Ce contrat ne peut plus être signé.');
  END IF;
  IF v_contrat.signature_soignant IS TRUE THEN RETURN jsonb_build_object('error','Déjà signé'); END IF;

  v_document_hash := encode(extensions.digest(convert_to(v_contrat.contenu_html,'UTF8'),'sha256'),'hex');
  IF (
    v_contrat.contenu_html IS NOT NULL AND btrim(v_contrat.contenu_html)<>''
    AND v_contrat.contenu_html !~ '\{\{[[:space:]]*[^}]+[[:space:]]*\}\}'
    AND v_contrat.hash_document ~ '^[a-f0-9]{64}$'
    AND v_contrat.hash_document=v_document_hash
    AND NULLIF(btrim(v_contrat.storage_path),'') IS NOT NULL
    AND v_contrat.contenu_html_rendu_le IS NOT NULL
  ) IS NOT TRUE OR EXISTS (
    SELECT 1 FROM public.signatures_contrats sc
    WHERE sc.contrat_id=p_contrat_id AND sc.statut_signature='signe'
      AND sc.hash_document IS DISTINCT FROM v_document_hash
  ) THEN
    RETURN jsonb_build_object('success',false,'error_code','HASH_DOCUMENT_CHANGE',
      'error','Le document a changé ou sa preuve est indisponible. Rechargez la page avant de signer.');
  END IF;

  -- Drapeau interne déjà utilisé par le trigger d'intégrité du soignant.
  PERFORM set_config('jolene.signature_soignant_en_cours','1',true);
  UPDATE public.contrats_mission SET
    signature_soignant=true,
    signature_soignant_le=now(),
    signature_image_soignant=p_signature_image,
    signature_navigateur_soignant=current_setting('request.headers',true)::json->>'user-agent',
    statut=CASE WHEN signature_etablissement IS TRUE THEN 'SIGNE_COMPLET' ELSE 'SIGNE_SOIGNANT' END,
    modifie_le=now()
  WHERE id=p_contrat_id;
  RETURN jsonb_build_object('success',true);
END;
$function$;

-- L'inventaire suit uniquement les deux corps revus ; leurs classifications et
-- autorisations existantes restent conservées.
UPDATE private.security_definer_inventory i
SET definition_md5=md5(p.prosrc),recense_le=now()
FROM pg_catalog.pg_proc p
WHERE p.oid=to_regprocedure('public.'||i.signature)
AND i.signature IN ('fn_signer_contrat_etablissement(uuid,text)','fn_signer_contrat_soignant(uuid,text)');
