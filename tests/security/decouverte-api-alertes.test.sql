BEGIN;
DO $preuve$
DECLARE valeur_originale numeric;
BEGIN
 IF NOT has_function_privilege('authenticated','public.fn_param_bool(text,boolean)','execute') THEN RAISE EXCEPTION 'Découverte indisponible aux comptes connectés'; END IF;
 IF public.fn_param_bool('recette_cle_decouverte_inexistante',false) IS DISTINCT FROM false THEN RAISE EXCEPTION 'Ancien backend ne replie pas sur false'; END IF;
 SELECT valeur INTO valeur_originale FROM public.parametres_systeme WHERE cle='api_alertes_recherches_v1';
 IF valeur_originale IS NULL THEN RAISE EXCEPTION 'Contrat API non annoncé'; END IF;
 IF to_regprocedure('public.fn_capacite_alertes_recherches()') IS NULL THEN RAISE EXCEPTION 'API annoncée avant sa création'; END IF;
 UPDATE public.parametres_systeme SET valeur=1 WHERE cle='api_alertes_recherches_v1';
 IF public.fn_param_bool('api_alertes_recherches_v1',false) IS DISTINCT FROM true THEN RAISE EXCEPTION 'Annonce v1 non lisible'; END IF;
 UPDATE public.parametres_systeme SET valeur=0 WHERE cle='api_alertes_recherches_v1';
 IF public.fn_param_bool('api_alertes_recherches_v1',false) IS DISTINCT FROM false THEN RAISE EXCEPTION 'Désactivation explicite ignorée'; END IF;
 UPDATE public.parametres_systeme SET valeur=valeur_originale WHERE cle='api_alertes_recherches_v1';
END $preuve$;
ROLLBACK;
