-- L'overload 6-args fn_ecrire_audit_safe (ajouté pour les 3 appels positionnels
-- finissant en jsonb) créait une AMBIGUÏTÉ avec l'overload 9-args-à-défauts pour
-- les ~40 appelants en 6 args nommés (p_acteur_id..p_details) → « function is not
-- unique » → écriture d'audit cassée (parrainage, litige, scoring, notation...).
-- Fix : convertir les 3 appels positionnels-jsonb pour insérer NULL (p_cle_s3)
-- avant le jsonb (→ 7 positionnels, matchent le 9-args), puis DROP l'overload 6-args.
DO $mig$
DECLARE r RECORD; v_def text; v_new text;
BEGIN
  FOR r IN SELECT p.oid, p.proname FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
    AND p.proname IN ('fn_annuler_mission_etablissement','fn_annuler_mission_soignant','fn_toggle_favori_etablissement')
  LOOP
    v_def := pg_get_functiondef(r.oid);
    IF r.proname='fn_annuler_mission_etablissement' THEN
      v_new := regexp_replace(v_def, '(''MISSION_ANNULEE_PAR_ETABLISSEMENT'',\s*''mission'',\s*p_mission_id,)(\s*)jsonb_build_object', '\1 NULL,\2jsonb_build_object');
    ELSIF r.proname='fn_annuler_mission_soignant' THEN
      v_new := regexp_replace(v_def, '(''MISSION_ANNULEE_PAR_SOIGNANT'',\s*''mission'',\s*p_mission_id,)(\s*)jsonb_build_object', '\1 NULL,\2jsonb_build_object');
    ELSE
      v_new := regexp_replace(v_def, '(''etablissement'',\s*p_etablissement_id,)(\s*)jsonb_build_object', '\1 NULL,\2jsonb_build_object', 'g');
    END IF;
    IF v_new <> v_def THEN EXECUTE v_new; ELSE RAISE EXCEPTION 'Pas de remplacement pour %', r.proname; END IF;
  END LOOP;

  DROP FUNCTION public.fn_ecrire_audit_safe(uuid, text, text, text, uuid, jsonb);
END $mig$;
