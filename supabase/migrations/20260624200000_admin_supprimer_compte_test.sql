-- Outil admin self-service : supprimer entièrement un compte (par email) pour les essais.
-- Supprimer un user depuis l'UI Supabase Auth ne supprime PAS la ligne `soignants`
-- (aucune cascade auth.users -> soignants), donc le RPPS restait « associé à un compte ».
--
-- Usage (éditeur SQL Supabase) :
--   SELECT fn_admin_supprimer_compte_test('email@exemple.app');
-- → supprime la ligne soignant (libère le RPPS via l'unicité) + le compte auth (libère l'email).
--
-- Réservé admin / contexte service_role (éditeur SQL). Non exécutable par anon/authenticated.
-- NB : échoue si le compte a des données dépendantes (missions, etc.) en FK RESTRICT —
-- conçu pour les comptes de test fraîchement créés.

CREATE OR REPLACE FUNCTION public.fn_admin_supprimer_compte_test(p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_email text := lower(trim(p_email));
  v_id uuid;
  v_rpps text;
  v_nb_soignant int := 0;
  v_nb_auth int := 0;
BEGIN
  IF NOT fn_est_contexte_cron_ou_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Réservé à l''administrateur.');
  END IF;

  SELECT id, numero_rpps INTO v_id, v_rpps FROM soignants WHERE lower(email) = v_email;

  DELETE FROM soignants WHERE lower(email) = v_email;
  GET DIAGNOSTICS v_nb_soignant = ROW_COUNT;

  DELETE FROM auth.users WHERE lower(email) = v_email;
  GET DIAGNOSTICS v_nb_auth = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true,
    'email', v_email,
    'soignant_id', v_id,
    'rpps_libere', v_rpps,
    'lignes_soignant_supprimees', v_nb_soignant,
    'comptes_auth_supprimes', v_nb_auth
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.fn_admin_supprimer_compte_test(text) FROM PUBLIC, anon, authenticated;
