-- Définition LIVE relue le 25/09/2026 : ce trigger imposait true sans condition.
-- Le stock conserve sa cohorte. Seules les INSERT futures changent après
-- activation explicite, à la fin du déploiement production vérifié.
INSERT INTO public.parametres_systeme
  (cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES
  ('inscriptions_publiques_actives',0,'Inscriptions publiques actives',
   'Classe les futures inscriptions publiques comme réelles. 0 conserve la création en cohorte test. Aucun effet sur les profils existants.',
   'booléen',0,1,'GENERAL','Le retour à 0 ne requalifie aucun compte existant.',true),
  ('activation_inscriptions_publiques_planifiee',1,'Activation initiale des inscriptions publiques',
   'Consommée une seule fois par le déploiement production, après les sondes Edge. Un déploiement ultérieur respecte le kill-switch.',
   'booléen',0,1,'GENERAL','Ne pas réarmer pour contourner un arrêt volontaire.',true)
ON CONFLICT (cle) DO NOTHING;

ALTER TABLE public.soignants ALTER COLUMN est_compte_test SET DEFAULT false;
ALTER TABLE public.etablissements ALTER COLUMN est_compte_test SET DEFAULT false;

CREATE OR REPLACE FUNCTION private.fn_forcer_compte_test_prelaunch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_role text := COALESCE(auth.jwt()->>'role', NULLIF(current_setting('request.jwt.claim.role',true),''), '');
  v_backend boolean;
  v_public boolean;
  v_test_auth boolean;
BEGIN
  v_backend := v_role = 'service_role'
    OR (v_role = '' AND auth.uid() IS NULL AND session_user IN ('postgres','supabase_admin'));

  IF TG_OP = 'UPDATE' THEN
    -- Un upsert serveur omettant ce champ reprendrait désormais le défaut false.
    -- Il ne doit jamais convertir un ancien compte test en compte réel.
    IF NOT v_backend AND NEW.est_compte_test IS DISTINCT FROM OLD.est_compte_test THEN
      RAISE EXCEPTION 'La cohorte du compte ne peut pas être modifiée depuis le client.'
        USING ERRCODE = '42501';
    END IF;
    NEW.est_compte_test := OLD.est_compte_test;
    RETURN NEW;
  END IF;

  SELECT COALESCE((SELECT valeur = 1 FROM public.parametres_systeme
    WHERE cle='inscriptions_publiques_actives'),false) INTO v_public;
  IF NOT v_public THEN
    NEW.est_compte_test := true;
    RETURN NEW;
  END IF;

  -- Sources privées : ni user_metadata ni email_contact/NEW.email envoyé
  -- par le client. Les inscriptions CI historiques passent par les mêmes Edge.
  SELECT COALESCE((u.raw_app_meta_data->'est_compte_test') = 'true'::jsonb,false)
    OR COALESCE((u.raw_app_meta_data->'is_test_playwright') = 'true'::jsonb,false)
    OR lower(COALESCE(u.email,'')) ~ '^playwright-(soignant|etab|test-[a-z0-9][a-z0-9._+-]*)@jolene[.]app$'
  INTO v_test_auth
  FROM auth.users u WHERE u.id=NEW.id;

  NEW.est_compte_test := COALESCE(v_test_auth,false)
    OR (v_backend AND NEW.est_compte_test IS TRUE);
  RETURN NEW;
END;
$function$;

-- Les ACL du trigger restent privées ; aucun nouveau droit client.
REVOKE ALL ON FUNCTION private.fn_forcer_compte_test_prelaunch() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_forcer_compte_test_prelaunch() TO service_role;

CREATE OR REPLACE FUNCTION private.fn_activer_inscriptions_publiques_planifiees(
  p_projet_ref text, p_confirmation text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
DECLARE
  v_count integer;
  v_active numeric;
  v_pending numeric;
BEGIN
  IF p_projet_ref IS DISTINCT FROM 'flripxtsyegjshnhzjkz'
     OR p_confirmation IS DISTINCT FROM 'EDGE_PROBES_OK' THEN
    RAISE EXCEPTION 'Activation réservée au déploiement production vérifié.' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM public.parametres_systeme
  WHERE cle IN ('inscriptions_publiques_actives','activation_inscriptions_publiques_planifiee')
  ORDER BY cle FOR UPDATE;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 2 THEN RAISE EXCEPTION 'Paramètres d’activation manquants.'; END IF;
  SELECT valeur INTO v_active FROM public.parametres_systeme WHERE cle='inscriptions_publiques_actives';
  SELECT valeur INTO v_pending FROM public.parametres_systeme WHERE cle='activation_inscriptions_publiques_planifiee';
  IF v_active IS NULL OR v_active NOT IN (0,1) OR v_pending IS NULL OR v_pending NOT IN (0,1) THEN
    RAISE EXCEPTION 'Paramètres d’activation invalides.';
  END IF;
  IF v_pending=1 THEN
    UPDATE public.parametres_systeme SET valeur=1,maj_le=now() WHERE cle='inscriptions_publiques_actives';
    UPDATE public.parametres_systeme SET valeur=0,maj_le=now() WHERE cle='activation_inscriptions_publiques_planifiee';
    v_active := 1;
  END IF;
  RETURN jsonb_build_object('success',true,'active',v_active=1,'activation_effectuee',v_pending=1,'planifiee',false);
END;
$function$;
REVOKE ALL ON FUNCTION private.fn_activer_inscriptions_publiques_planifiees(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_activer_inscriptions_publiques_planifiees(text,text) TO service_role;

NOTIFY pgrst,'reload schema';
