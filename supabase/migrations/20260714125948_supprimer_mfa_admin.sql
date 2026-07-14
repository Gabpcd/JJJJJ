-- Retire l'obligation TOTP/AAL2 du portail administrateur.
--
-- Les garde-fous d'autorisation restent inchangés : rôle Auth canonique,
-- compte actif et confirmé, inscription active dans equipe_admin et accès
-- complet aux huit groupes de lancement. Seul le second facteur est retiré.
--
-- Les fonctions sensibles ont été introduites dans plusieurs migrations et
-- certaines sont très longues. Pour éviter de recopier leurs corps (et de
-- diverger de leur dernière version), on remplace uniquement la condition AAL2
-- dans leur définition courante. La liste est explicite et la migration échoue
-- si l'une des dix signatures attendues n'a pas été modifiée.

DO $migration$
DECLARE
  v_fonction record;
  v_definition text;
  v_nouvelle_definition text;
  v_nombre_modifie integer := 0;
BEGIN
  FOR v_fonction IN
    SELECT p.oid, n.nspname, p.proname,
           pg_get_function_identity_arguments(p.oid) AS arguments
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname IN (
        'est_admin_valide',
        'fn_admin_decider_preuve_etablissement',
        'fn_admin_decider_revue_manuelle',
        'fn_admin_finaliser_verification_etablissement',
        'fn_admin_lister_etablissements_a_verifier',
        'fn_admin_lister_revues_manuelles',
        'fn_admin_moderer_document',
        'fn_admin_rejeter_dossier_etablissement',
        'fn_admin_valider_heures_externes'
      )
      AND pg_get_functiondef(p.oid) ILIKE '%auth.jwt()%'
      AND pg_get_functiondef(p.oid) ILIKE '%aal2%'
    ORDER BY p.proname, arguments
  LOOP
    v_definition := pg_get_functiondef(v_fonction.oid);
    v_nouvelle_definition := regexp_replace(
      v_definition,
      E'\\n[[:blank:]]+(AND|OR)[[:blank:]]+COALESCE\\(auth\\.jwt\\(\\)[[:blank:]]*->>[[:blank:]]*''aal''[[:blank:]]*,[[:blank:]]*''''\\)[[:blank:]]*(=|IS[[:blank:]]+DISTINCT[[:blank:]]+FROM)[[:blank:]]*''aal2''',
      '',
      'g'
    );
    v_nouvelle_definition := replace(
      v_nouvelle_definition,
      'Administrateur AAL2 autorisé requis',
      'Administrateur autorisé requis'
    );
    v_nouvelle_definition := replace(
      v_nouvelle_definition,
      'Administrateur AAL2 autorise requis',
      'Administrateur autorise requis'
    );
    v_nouvelle_definition := replace(
      v_nouvelle_definition,
      'Administrateur AAL2 valide requis',
      'Administrateur valide requis'
    );

    IF v_nouvelle_definition = v_definition THEN
      RAISE EXCEPTION 'La garde AAL2 de %.%(%) n''a pas été trouvée',
        v_fonction.nspname, v_fonction.proname, v_fonction.arguments;
    END IF;

    EXECUTE v_nouvelle_definition;
    v_nombre_modifie := v_nombre_modifie + 1;
  END LOOP;

  IF v_nombre_modifie <> 10 THEN
    RAISE EXCEPTION
      'Retrait MFA admin incomplet : 10 fonctions attendues, % modifiées',
      v_nombre_modifie;
  END IF;
END
$migration$;

COMMENT ON FUNCTION public.est_admin_valide() IS
  'Garde admin de lancement : compte actif et confirmé, rôle ADMIN_PLATEFORME et ligne equipe_admin active avec les 8 groupes canoniques. Aucun second facteur requis.';

-- ADMIN_AAL2 reste une valeur historique de provenance dans les lignes déjà
-- auditées et dans leur contrainte de domaine. Elle ne constitue plus une
-- affirmation sur le niveau AAL de la session courante.
