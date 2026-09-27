-- Catalogue transactionnel, aucun compte Auth, aucun transport ni donnée durable.
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
LOCK TABLE public.etablissements,public.missions IN ACCESS EXCLUSIVE MODE;
CREATE TEMP TABLE recette_comptage_triggers AS
SELECT tgrelid,tgname,tgenabled FROM pg_trigger
WHERE tgrelid IN ('public.etablissements'::regclass,'public.missions'::regclass)
  AND NOT tgisinternal;
DO $fixtures$
DECLARE t record;
BEGIN
  IF EXISTS(SELECT 1 FROM recette_comptage_triggers WHERE tgenabled IN('A','R'))
  THEN RAISE EXCEPTION 'Trigger ALWAYS/REPLICA inattendu'; END IF;
  FOR t IN SELECT a.* FROM recette_comptage_triggers a JOIN pg_trigger p
    ON p.tgrelid=a.tgrelid AND p.tgname=a.tgname
    WHERE a.tgenabled='O' AND (p.tgtype & 4)<>0
  LOOP EXECUTE format('ALTER TABLE %s DISABLE TRIGGER %I',t.tgrelid::regclass,t.tgname); END LOOP;
  INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,
    est_compte_test,statut_verification,peut_publier_missions)
  VALUES
    ('69600000-0000-4000-8000-000000000001','Recette comptage Paris','69600000000001','CLINIQUE_PRIVEE',
      'Adresse fictive','Paris Recette comptage 696','75001','recette-compte-paris@example.invalid',false,'VERIFIE',true),
    ('69600000-0000-4000-8000-000000000002','Recette comptage Lyon','69600000000002','CLINIQUE_PRIVEE',
      'Adresse fictive','Lyon Recette comptage 696','69001','recette-compte-lyon@example.invalid',false,'VERIFIE',true);
  INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
    taux_horaire_base,statut,type_contrat_recherche,est_urgente,cree_le)
  SELECT ('69600000-0000-4000-8000-'||lpad((1000+n)::text,12,'0'))::uuid,
    CASE WHEN n<=250 THEN '69600000-0000-4000-8000-000000000001' ELSE '69600000-0000-4000-8000-000000000002' END::uuid,
    'Recette comptage '||n,CASE WHEN n%2=0 THEN 'IDE' ELSE 'AS' END::public.type_profession,
    now()+interval '7 days',now()+interval '7 days 8 hours',30,'OUVERTE','SALARIE',n%3=0,
    now()-n*interval '1 second'
  FROM generate_series(1,500) n;
  SET CONSTRAINTS ALL IMMEDIATE;
  FOR t IN SELECT a.* FROM recette_comptage_triggers a JOIN pg_trigger p
    ON p.tgrelid=a.tgrelid AND p.tgname=a.tgname WHERE a.tgenabled='O' AND p.tgenabled='D'
  LOOP EXECUTE format('ALTER TABLE %s ENABLE TRIGGER %I',t.tgrelid::regclass,t.tgname); END LOOP;
  IF EXISTS(SELECT 1 FROM recette_comptage_triggers a JOIN pg_trigger p
    ON p.tgrelid=a.tgrelid AND p.tgname=a.tgname WHERE p.tgenabled<>a.tgenabled)
  THEN RAISE EXCEPTION 'Triggers non restaurés'; END IF;
END $fixtures$;
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims','{"role":"anon"}',true),set_config('request.jwt.claim.sub','',true);
DO $preuve$
DECLARE cas record; n bigint; tot_min bigint; tot_max bigint;
BEGIN
  FOR cas IN SELECT * FROM (VALUES
    (NULL::text,'Recette comptage 696',500),('IDE','Recette comptage 696',250),
    (' AS ',' paris recette comptage 696 ',125),('IDE','Lyon Recette comptage 696',125),
    ('','Recette comptage 696',500),('INCONNUE','Recette comptage 696',0),
    (NULL,'Aucune ville recette 696',0)) AS c(profession,ville,attendu)
  LOOP
    SELECT count(*),min(total_count),max(total_count) INTO n,tot_min,tot_max
      FROM public.fn_missions_publiques_recherche(cas.profession,cas.ville);
    IF n<>cas.attendu OR (n>0 AND (tot_min IS DISTINCT FROM n OR tot_max IS DISTINCT FROM n))
    THEN RAISE EXCEPTION 'Comptage incohérent pour %, % : % / % / %',cas.profession,cas.ville,n,tot_min,tot_max; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM (
      SELECT est_urgente,lag(est_urgente) OVER () AS precedente
      FROM public.fn_missions_publiques_recherche(NULL,'Recette comptage 696')
    ) r WHERE precedente=false AND est_urgente=true)
  THEN RAISE EXCEPTION 'Priorité urgente perdue'; END IF;
END $preuve$;
RESET ROLE;
ROLLBACK;
