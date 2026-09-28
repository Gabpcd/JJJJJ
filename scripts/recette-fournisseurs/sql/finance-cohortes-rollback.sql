-- Recette SQL uniquement sur staging mejpriaetwgtcstbgfid.
-- Ne crée aucun acteur persistant, aucun mandat, aucune mission ni paiement.
-- Le paramètre temporaire n'est jamais visible des autres transactions.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout = '15s';
SET LOCAL lock_timeout = '3s';
DO $recette$
DECLARE
  v_avant numeric;
  v_ancien_test uuid := gen_random_uuid();
  v_soignant uuid := gen_random_uuid();
  v_etablissement uuid := gen_random_uuid();
  v_apres uuid := gen_random_uuid();
  v_id uuid;
  v_siret text;
BEGIN
  IF auth.uid() IS NOT NULL THEN RAISE EXCEPTION 'Backend de recette attendu'; END IF;
  SELECT valeur INTO STRICT v_avant FROM public.parametres_systeme
    WHERE cle='inscriptions_publiques_actives' FOR UPDATE;
  IF v_avant <> 0 THEN RAISE EXCEPTION 'Etat staging inattendu'; END IF;

  FOREACH v_id IN ARRAY ARRAY[v_ancien_test,v_soignant,v_etablissement,v_apres] LOOP
    INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
    VALUES(v_id,'authenticated','authenticated',v_id::text||'@example.invalid',now(),
      jsonb_build_object('provider','email','role',CASE WHEN v_id=v_etablissement THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
        'recette_finance_rollback',true),'{}'::jsonb);
  END LOOP;
  INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice)
    VALUES(v_ancien_test,'Recette','Cohorte initiale',v_ancien_test::text||'@example.invalid','MEDECIN','SALARIE');
  IF (SELECT est_compte_test FROM public.soignants WHERE id=v_ancien_test) IS DISTINCT FROM true
    THEN RAISE EXCEPTION 'Exclusion initiale absente'; END IF;

  UPDATE public.parametres_systeme SET valeur=1 WHERE cle='inscriptions_publiques_actives';
  INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,statut_liberal)
    VALUES(v_soignant,'Recette','Nouvel acteur financier',v_soignant::text||'@example.invalid','MEDECIN','LIBERAL','ACTIF');
  -- Identifiant explicitement fictif, libre dans cette transaction : ne pas
  -- heurter le SIRET de la fixture persistante ni modifier un acteur existant.
  SELECT '000000' || lpad(n::text,8,'0') INTO v_siret
    FROM generate_series(1,100) n
    WHERE NOT EXISTS (SELECT 1 FROM public.etablissements e
      WHERE e.siret='000000' || lpad(n::text,8,'0'))
    ORDER BY n LIMIT 1;
  IF v_siret IS NULL THEN RAISE EXCEPTION 'Plage de recette indisponible'; END IF;
  INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES(v_etablissement,'Recette financière annulée',v_siret,'CLINIQUE_PRIVEE',
      'Adresse fictive de recette','Paris','75001',v_etablissement::text||'@example.invalid');
  IF (SELECT est_compte_test FROM public.soignants WHERE id=v_soignant) IS DISTINCT FROM false
    OR (SELECT est_compte_test FROM public.etablissements WHERE id=v_etablissement) IS DISTINCT FROM false
    THEN RAISE EXCEPTION 'Acteurs financiers non admissibles'; END IF;
  IF (SELECT peut_publier_missions FROM public.etablissements WHERE id=v_etablissement) IS TRUE
    THEN RAISE EXCEPTION 'Droits de publication indus'; END IF;
  -- L'ancien compte de cette transaction reste protégé, même pour le backend.
  UPDATE public.soignants SET est_compte_test=false WHERE id=v_ancien_test;
  IF (SELECT est_compte_test FROM public.soignants WHERE id=v_ancien_test) IS DISTINCT FROM true
    THEN RAISE EXCEPTION 'Cohorte existante requalifiée'; END IF;

  UPDATE public.parametres_systeme SET valeur=v_avant WHERE cle='inscriptions_publiques_actives';
  INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice)
    VALUES(v_apres,'Recette','Cohorte restaurée',v_apres::text||'@example.invalid','MEDECIN','SALARIE');
  IF (SELECT est_compte_test FROM public.soignants WHERE id=v_apres) IS DISTINCT FROM true
    OR (SELECT valeur FROM public.parametres_systeme WHERE cle='inscriptions_publiques_actives') <> v_avant
    THEN RAISE EXCEPTION 'Restauration absente'; END IF;
END
$recette$;
SELECT 'COHORTES_ISOLEES_ASSERTIONS_OK_ROLLBACK' AS resultat;
ROLLBACK;
