-- Parcours réels en SQL, avec comptes jetables annulés par la transaction CI.
BEGIN;
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
VALUES
 ('69000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','parcours-soignant@test.invalid','authenticated','authenticated','{}',now()),
 ('69000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','parcours-etab@test.invalid','authenticated','authenticated','{}',now());

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"69000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
DO $soignant$
DECLARE r jsonb; refuse boolean;
BEGIN
  r := public.fn_demarrer_inscription('SOIGNANT','IDE',NULL,true,false);
  IF r->>'type_compte' <> 'SOIGNANT' OR r->'donnees'->>'profession' <> 'IDE' THEN RAISE EXCEPTION 'Création minimale soignant échouée'; END IF;
  IF (public.fn_get_my_role()->>'role') <> 'INCONNU' THEN RAISE EXCEPTION 'Un brouillon a obtenu un rôle professionnel'; END IF;
  r := public.fn_enregistrer_parcours_inscription('{"prenom":"Camille","typesContrat":["CDD"]}');
  r := public.fn_demarrer_inscription('SOIGNANT','IDE',NULL,true,false);
  IF r->'donnees'->>'prenom' <> 'Camille' THEN RAISE EXCEPTION 'La reprise écrase le brouillon'; END IF;
  refuse := false;
  BEGIN PERFORM public.fn_demarrer_inscription('ETABLISSEMENT',NULL,'Autre rôle',true,true);
  EXCEPTION WHEN unique_violation THEN refuse := true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Changement de famille de compte possible'; END IF;
  refuse := false;
  BEGIN PERFORM public.fn_enregistrer_parcours_inscription('{"password":"secret"}');
  EXCEPTION WHEN invalid_parameter_value THEN refuse := true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Mot de passe accepté dans le brouillon'; END IF;
  refuse := false;
  BEGIN PERFORM public.fn_enregistrer_parcours_inscription('{"rpps_verifie":true}');
  EXCEPTION WHEN invalid_parameter_value THEN refuse := true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'État de vérification accepté depuis le client'; END IF;
  r := public.fn_explorer_missions_inscription(NULL, 0, 100);
  IF jsonb_typeof(r) <> 'array' OR jsonb_array_length(r) > 100 THEN RAISE EXCEPTION 'Exploration non bornée'; END IF;
  IF NOT has_function_privilege('authenticated','public.fn_explorer_missions_inscription(uuid,integer,integer)','EXECUTE')
    OR has_function_privilege('anon','public.fn_explorer_missions_inscription(uuid,integer,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'ACL exploration incorrectes';
  END IF;
  -- La consultation ne crée ni candidature ni identité professionnelle.
  r := public.fn_missions_decouverte_inscription(NULL);
  IF jsonb_typeof(r) <> 'array' OR jsonb_array_length(r) > 20 THEN RAISE EXCEPTION 'Aperçu non borné'; END IF;
END;
$soignant$;

SELECT set_config('request.jwt.claims','{"sub":"69000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
DO $etablissement$
DECLARE r jsonb; refuse boolean;
BEGIN
  IF EXISTS (SELECT 1 FROM public.parcours_inscription) THEN RAISE EXCEPTION 'Fuite du brouillon entre deux comptes'; END IF;
  refuse := false;
  BEGIN PERFORM public.fn_demarrer_inscription('ETABLISSEMENT',NULL,'Résidence test',true,false);
  EXCEPTION WHEN invalid_parameter_value THEN refuse := true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'CGV absentes acceptées'; END IF;
  r := public.fn_demarrer_inscription('ETABLISSEMENT',NULL,'Résidence test',true,true);
  IF r->>'type_compte' <> 'ETABLISSEMENT' THEN RAISE EXCEPTION 'Création minimale établissement échouée'; END IF;
  r := public.fn_enregistrer_parcours_inscription('{"missionProfession":"IDE","missionVille":"Lyon","missionDate":"2027-01-12","brouillonMission":true}');
  IF r->'donnees'->>'missionVille' <> 'Lyon' THEN RAISE EXCEPTION 'Brouillon mission non enregistré'; END IF;
  r := public.fn_enregistrer_parcours_inscription('{"missionFormulaire":{"intitule":"Renfort de nuit","description":"À reprendre","creneaux":[{"debut":"2027-01-12T07:00:00Z","fin":"2027-01-12T15:00:00Z"}]}}');
  IF r#>>'{donnees,missionFormulaire,intitule}' <> 'Renfort de nuit' THEN RAISE EXCEPTION 'Brouillon complet perdu'; END IF;
  refuse := false;
  BEGIN PERFORM public.fn_enregistrer_parcours_inscription('{"missionFormulaire":{"peut_publier_missions":true}}');
  EXCEPTION WHEN invalid_parameter_value THEN refuse := true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Champ sensible accepté dans la mission'; END IF;
  refuse := false;
  BEGIN PERFORM public.fn_explorer_missions_inscription(NULL,0,100);
  EXCEPTION WHEN insufficient_privilege THEN refuse := true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Exploration soignant accessible à établissement'; END IF;
  IF (public.fn_get_my_role()->>'role') <> 'INCONNU' THEN RAISE EXCEPTION 'Brouillon promu en établissement'; END IF;
  refuse := false;
  BEGIN PERFORM public.fn_missions_decouverte_inscription(NULL);
  EXCEPTION WHEN insufficient_privilege THEN refuse := true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Aperçu soignant accessible à un établissement'; END IF;
END;
$etablissement$;

RESET ROLE;
DO $reprise_finalisation$
DECLARE r jsonb; token uuid := gen_random_uuid(); autre uuid := gen_random_uuid();
BEGIN
  IF EXISTS (SELECT 1 FROM public.soignants WHERE id='69000000-0000-4000-8000-000000000001')
    OR EXISTS (SELECT 1 FROM public.etablissements WHERE id='69000000-0000-4000-8000-000000000002') THEN
    RAISE EXCEPTION 'Profil métier créé avant la complétion';
  END IF;
  r := public.fn_reserver_type_compte('69000000-0000-4000-8000-000000000001','SOIGNANT',token);
  IF (r->>'allowed')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'Complétion du compte partiel impossible'; END IF;
  PERFORM public.fn_liberer_inscription_progressive('69000000-0000-4000-8000-000000000001',autre);
  r := public.fn_reserver_type_compte('69000000-0000-4000-8000-000000000001','SOIGNANT',autre);
  IF r->>'code' <> 'ACCOUNT_REGISTRATION_IN_PROGRESS' THEN RAISE EXCEPTION 'Un autre appel a libéré la réservation'; END IF;
  PERFORM public.fn_liberer_inscription_progressive('69000000-0000-4000-8000-000000000001',token);
  r := public.fn_reserver_type_compte('69000000-0000-4000-8000-000000000001','SOIGNANT',autre);
  IF (r->>'allowed')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'Nouvelle tentative bloquée après erreur corrigible'; END IF;
  IF has_table_privilege('anon','public.parcours_inscription','SELECT')
     OR has_table_privilege('authenticated','public.parcours_inscription','INSERT')
     OR has_table_privilege('authenticated','public.parcours_inscription','UPDATE')
     OR has_function_privilege('anon','public.fn_demarrer_inscription(text,text,text,boolean,boolean)','EXECUTE')
     OR has_function_privilege('authenticated','public.fn_liberer_inscription_progressive(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'ACL du parcours trop permissives';
  END IF;
END;
$reprise_finalisation$;

UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id='69000000-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"69000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
DO $suspension$
DECLARE refuse boolean := false;
BEGIN
  IF EXISTS (SELECT 1 FROM public.parcours_inscription) THEN RAISE EXCEPTION 'Compte suspendu : lecture encore possible'; END IF;
  BEGIN PERFORM public.fn_enregistrer_parcours_inscription('{"prenom":"test"}');
  EXCEPTION WHEN insufficient_privilege THEN refuse := true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Compte suspendu : écriture encore possible'; END IF;
END;
$suspension$;
RESET ROLE;
ROLLBACK;
