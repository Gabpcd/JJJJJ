"""Qualification PG17 du correctif sur le banc OTP original, sans fournisseur.

Le pilote importe les mêmes tables/fonctions exactes et les deux triggers ; il
applique la migration entière dans le ROLLBACK du banc. Aucun document réel.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('otp_diagnostic', ROOT/'scripts/ci/signature-otp-diagnostic-pg17.py')
diagnostic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostic)
MIGRATION = '20261004124300_refuser_signature_otp_et_document_incoherents.sql'


class WitnessFailure(Exception):
    def __init__(self, code, sqlstate=None):
        self.code, self.sqlstate = code, sqlstate


def build_sql(snapshot, before, auth, migration):
    # Le snapshot evoluera apres la livraison : le negatif historique reste
    # epingle au catalogue avant correction, pas remplace par le corps corrige.
    original = diagnostic.build_sql(snapshot, before, auth, require_original_snapshot=False)
    setup = original.split('CREATE TEMP TABLE observations')[0]
    # Policies de lecture exactes des deux tables et leurs dependances. Le banc
    # n'importe toujours pas les notifications, FKs ou les autres policies App.
    for name in ['mon_etablissement_id', 'fn_a_permission_etablissement']:
        setup += diagnostic.definition(snapshot, name) + '\n'
    for table in ['contrats_mission', 'signatures_contrats']:
        setup += f'ALTER TABLE public.{table} ENABLE ROW LEVEL SECURITY;\n'
        for policy in ['pol_compte_auth_actif_restrictive',
                       'pol_contrat_select' if table == 'contrats_mission' else 'pol_sig_contrats_select']:
            setup += diagnostic.exact(r'CREATE POLICY "'+policy+r'" ON "public"\."'+table+r'"[^;]+;', snapshot) + '\n'
    setup += """
GRANT USAGE ON SCHEMA public,auth TO authenticated,anon,service_role;
GRANT SELECT ON public.contrats_mission,public.signatures_contrats TO authenticated;
GRANT ALL ON public.signatures_contrats TO service_role;
CREATE TEMP TABLE policies_before AS
 SELECT oid,polrelid,polname,polcmd,polpermissive,polroles,polqual::text,polwithcheck::text
 FROM pg_policy WHERE polrelid IN ('public.contrats_mission'::regclass,'public.signatures_contrats'::regclass);
DO $acl_original$
BEGIN
 IF NOT has_column_privilege('authenticated','public.signatures_contrats','otp_code_hash','SELECT')
 THEN RAISE EXCEPTION 'ORIGINAL_HASH_EXPOSURE_NOT_MOUNTED'; END IF;
END;
$acl_original$;
"""
    # Registre annexe exact de la migration ; ses autres lignes n'existent pas
    # dans ce banc reduit. Ce n'est pas une qualification de l'inventaire global.
    setup += """
CREATE SCHEMA private;
CREATE TABLE private.security_definer_inventory(signature text PRIMARY KEY,categorie text NOT NULL,
 definition_md5 text NOT NULL,justification text NOT NULL,recense_le timestamptz NOT NULL);
INSERT INTO private.security_definer_inventory
 SELECT 'fn_signer_contrat_otp(uuid,text,text,text)','RPC_UTILISATEUR_AUTH_INTERNE',md5(prosrc),'Source avant correction',now()
 FROM pg_proc WHERE oid='public.fn_signer_contrat_otp(uuid,text,text,text)'::regprocedure;
"""
    tests = r"""
CREATE TEMP TABLE observations(case_name text PRIMARY KEY, passed boolean NOT NULL);
CREATE FUNCTION pg_temp.signature_photo() RETURNS jsonb LANGUAGE sql AS $photo$
 SELECT jsonb_build_object('contrats',(SELECT jsonb_agg(to_jsonb(c) ORDER BY id) FROM public.contrats_mission c),
                          'signatures',(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM public.signatures_contrats s));
$photo$;
DO $witness$
DECLARE who text; code text; h text; r jsonb; old jsonb; mutation text; label text; guc_label text; mutation_applied boolean;
        cid uuid := 'f1040000-0000-4000-8000-000000000003';
        sid uuid := 'f1040000-0000-4000-8000-000000000001';
        eid uuid := 'f1040000-0000-4000-8000-000000000002';
        other_uid uuid; other_role text; first_role text; second_role text; denied boolean; n bigint; query_text text;
BEGIN
 IF has_function_privilege('anon','public.fn_signer_contrat_otp(uuid,text,text,text)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.fn_signer_contrat_otp(uuid,text,text,text)','EXECUTE')
    OR NOT has_function_privilege('service_role','public.fn_signer_contrat_otp(uuid,text,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'FIX_ACL_CHANGED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i JOIN pg_proc p
   ON p.oid='public.fn_signer_contrat_otp(uuid,text,text,text)'::regprocedure
   WHERE i.signature='fn_signer_contrat_otp(uuid,text,text,text)' AND i.definition_md5=md5(p.prosrc))
 THEN RAISE EXCEPTION 'FIX_INVENTORY'; END IF;
 INSERT INTO observations VALUES('acl-and-registry',true);

 IF has_column_privilege('authenticated','public.signatures_contrats','otp_code_hash','SELECT')
    OR has_column_privilege('anon','public.signatures_contrats','otp_code_hash','SELECT')
    OR NOT has_column_privilege('service_role','public.signatures_contrats','otp_code_hash','SELECT')
    OR (SELECT count(*) FROM pg_attribute a WHERE a.attrelid='public.signatures_contrats'::regclass
       AND a.attnum>0 AND NOT a.attisdropped AND a.attname IN ('id','contrat_id','signataire_user_id','signataire_role','signe_a','ip_signature','user_agent','hash_document','otp_valide_a','psc_session_active','rpps_verifie','traits_identite_verifies','statut_signature','cree_le')
       AND has_column_privilege('authenticated',a.attrelid,a.attnum,'SELECT'))<>14
    OR EXISTS((SELECT * FROM policies_before) EXCEPT
       (SELECT oid,polrelid,polname,polcmd,polpermissive,polroles,polqual::text,polwithcheck::text
        FROM pg_policy WHERE polrelid IN ('public.contrats_mission'::regclass,'public.signatures_contrats'::regclass)))
 THEN RAISE EXCEPTION 'COLUMN_ACL_OR_RLS_CHANGED'; END IF;
 INSERT INTO observations VALUES('column-acl-and-policies',true);
 FOREACH who IN ARRAY ARRAY['soignant','etablissement'] LOOP
  PERFORM pg_temp.seed_signature(who);
  FOREACH query_text IN ARRAY ARRAY[
   'SELECT otp_code_hash FROM public.signatures_contrats',
   'SELECT * FROM public.signatures_contrats',
   'SELECT to_jsonb(s) FROM public.signatures_contrats s'
  ] LOOP
   denied:=false;
   EXECUTE 'SET LOCAL ROLE authenticated';
   BEGIN EXECUTE query_text; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
   EXECUTE 'RESET ROLE';
   IF denied IS NOT TRUE THEN RAISE EXCEPTION 'AUTH_HASH_READ_ALLOWED'; END IF;
   INSERT INTO observations VALUES('hash-denied-'||who||'-'||query_text,true);
  END LOOP;
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT count(*) INTO n FROM (SELECT id,contrat_id,signataire_user_id,signataire_role,signe_a,ip_signature,
     user_agent,hash_document,otp_valide_a,psc_session_active,rpps_verifie,
     traits_identite_verifies,statut_signature,cree_le FROM public.signatures_contrats
     WHERE contrat_id=cid ORDER BY cree_le) certificate;
  EXECUTE 'RESET ROLE';
  IF n<>1 THEN RAISE EXCEPTION 'CERTIFICATE_COLUMNS_UNREADABLE'; END IF;
  INSERT INTO observations VALUES('certificate-columns-readable-'||who,true);
 END LOOP;
 PERFORM set_config('request.jwt.claim.sub','f1040000-0000-4000-8000-000000000099',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 SELECT count(id) INTO n FROM public.signatures_contrats;
 EXECUTE 'RESET ROLE';
 IF n<>0 THEN RAISE EXCEPTION 'FOREIGN_SIGNATURE_VISIBLE'; END IF;
 INSERT INTO observations VALUES('foreign-reader-denied-by-rls',true);
 PERFORM pg_temp.seed_signature('soignant');
 UPDATE auth.users SET banned_until=now()+interval '1 hour' WHERE id=sid;
 EXECUTE 'SET LOCAL ROLE authenticated';
 SELECT count(id) INTO n FROM public.signatures_contrats;
 EXECUTE 'RESET ROLE';
 UPDATE auth.users SET banned_until=NULL WHERE id=sid;
 IF n<>0 THEN RAISE EXCEPTION 'INACTIVE_SIGNATURE_VISIBLE'; END IF;
 INSERT INTO observations VALUES('inactive-reader-denied-by-rls',true);
 denied:=false;
 EXECUTE 'SET LOCAL ROLE anon';
 BEGIN PERFORM id FROM public.signatures_contrats; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 EXECUTE 'RESET ROLE';
 IF denied IS NOT TRUE THEN RAISE EXCEPTION 'ANON_CERTIFICATE_READ_ALLOWED'; END IF;
 INSERT INTO observations VALUES('anonymous-reader-denied',true);

 FOREACH who IN ARRAY ARRAY['soignant','etablissement'] LOOP
  FOREACH code IN ARRAY ARRAY[NULL,'','12345','1234567','abcdef',' 123456','123456 ',E'123456\n','１２３４５６','000000'] LOOP
   PERFORM pg_temp.seed_signature(who);
   SELECT hash_document INTO h FROM public.contrats_mission;
   r:=public.fn_signer_contrat_otp(cid,code,h,NULL);
   IF r->>'error_code' IS DISTINCT FROM 'OTP_INCORRECT' OR (r->>'success')::boolean IS DISTINCT FROM false
      OR NOT EXISTS(SELECT 1 FROM public.signatures_contrats WHERE otp_tentatives=1 AND statut_signature='otp_envoye'
         AND signe_a IS NULL AND otp_valide_a IS NULL AND hash_document IS NULL)
      OR EXISTS(SELECT 1 FROM public.contrats_mission WHERE signature_soignant OR signature_etablissement)
   THEN RAISE EXCEPTION 'INVALID_OTP_WITNESS'; END IF;
   INSERT INTO observations VALUES('invalid-otp-'||who||'-'||COALESCE(code,'NULL'),true);
  END LOOP;
  PERFORM pg_temp.seed_signature(who);
  UPDATE public.signatures_contrats SET otp_code_hash=NULL;
  SELECT hash_document INTO h FROM public.contrats_mission;
  r:=public.fn_signer_contrat_otp(cid,'123456',h,NULL);
  IF r->>'error_code' IS DISTINCT FROM 'OTP_INCORRECT' THEN RAISE EXCEPTION 'NULL_STORED_OTP'; END IF;
  INSERT INTO observations VALUES('null-stored-otp-'||who,true);
 END LOOP;

 PERFORM pg_temp.seed_signature('etablissement');
 SELECT hash_document INTO h FROM public.contrats_mission;
 FOR i IN 1..5 LOOP
  r:=public.fn_signer_contrat_otp(cid,NULL,h,NULL);
  IF r->>'error_code' IS DISTINCT FROM 'OTP_INCORRECT' OR (r->>'tentatives_restantes')::int<>5-i
  THEN RAISE EXCEPTION 'ATTEMPT_COUNT'; END IF;
 END LOOP;
 r:=public.fn_signer_contrat_otp(cid,'123456',h,NULL);
 IF r->>'error_code' IS DISTINCT FROM 'TROP_DE_TENTATIVES' THEN RAISE EXCEPTION 'ATTEMPT_LIMIT'; END IF;
 INSERT INTO observations VALUES('five-invalid-attempts-block-valid-sixth',true);

 PERFORM pg_temp.seed_signature('etablissement');
 SELECT hash_document INTO h FROM public.contrats_mission;
 PERFORM set_config('request.jwt.claim.sub','',true);
 old:=pg_temp.signature_photo(); r:=public.fn_signer_contrat_otp(cid,'123456',h,NULL);
 IF r->>'error_code' IS DISTINCT FROM 'NON_AUTHENTIFIE' OR pg_temp.signature_photo() IS DISTINCT FROM old
 THEN RAISE EXCEPTION 'AUTH_REFUSAL_CHANGED'; END IF;
 INSERT INTO observations VALUES('unauthenticated-preserved',true);
 PERFORM pg_temp.seed_signature('etablissement');
 DELETE FROM public.signatures_contrats; old:=pg_temp.signature_photo();
 r:=public.fn_signer_contrat_otp(cid,'123456',h,NULL);
 IF r->>'error_code' IS DISTINCT FROM 'OTP_NON_DEMANDE' OR pg_temp.signature_photo() IS DISTINCT FROM old
 THEN RAISE EXCEPTION 'MISSING_OTP_REFUSAL_CHANGED'; END IF;
 INSERT INTO observations VALUES('missing-otp-preserved',true);
 PERFORM pg_temp.seed_signature('etablissement');
 UPDATE public.signatures_contrats SET otp_envoye_a=now()-interval '11 minutes';
 r:=public.fn_signer_contrat_otp(cid,'123456',h,NULL);
 IF r->>'error_code' IS DISTINCT FROM 'OTP_EXPIRE'
    OR NOT EXISTS(SELECT 1 FROM public.signatures_contrats WHERE statut_signature='expire' AND signe_a IS NULL)
 THEN RAISE EXCEPTION 'EXPIRED_OTP_REFUSAL_CHANGED'; END IF;
 INSERT INTO observations VALUES('expired-otp-preserved',true);
 PERFORM pg_temp.seed_signature('etablissement');
 UPDATE public.contrats_mission SET statut='ANNULE'; old:=pg_temp.signature_photo();
 r:=public.fn_signer_contrat_otp(cid,'123456',h,NULL);
 IF r->>'error_code' IS DISTINCT FROM 'CONTRAT_INACTIF' OR pg_temp.signature_photo() IS DISTINCT FROM old
 THEN RAISE EXCEPTION 'INACTIVE_CONTRACT_REFUSAL_CHANGED'; END IF;
 INSERT INTO observations VALUES('inactive-contract-preserved',true);

 FOREACH who IN ARRAY ARRAY['soignant','etablissement'] LOOP
  FOREACH code IN ARRAY ARRAY[NULL,'',repeat('f',64),'not-a-sha256'] LOOP
   PERFORM pg_temp.seed_signature(who); old:=pg_temp.signature_photo();
   r:=public.fn_signer_contrat_otp(cid,'123456',code,NULL);
   IF r->>'error_code' IS DISTINCT FROM 'HASH_DOCUMENT_CHANGE' OR pg_temp.signature_photo() IS DISTINCT FROM old
   THEN RAISE EXCEPTION 'CLIENT_HASH_REFUSAL'; END IF;
   INSERT INTO observations VALUES('client-hash-'||who||'-'||COALESCE(code,'NULL'),true);
  END LOOP;
 END LOOP;

 FOR label,mutation IN SELECT * FROM (VALUES
  ('html-null','contenu_html=NULL'),('html-empty','contenu_html='''''),
  ('html-placeholder','contenu_html=''<p>{{mission}}</p>'''),
  ('server-hash-null','hash_document=NULL'),('server-hash-malformed','hash_document=''invalid'''),
  ('server-hash-mismatch','hash_document=repeat(''f'',64)'),
  ('storage-null','storage_path=NULL'),('storage-empty','storage_path='''''),
  ('render-time-null','contenu_html_rendu_le=NULL')
 ) v(label,mutation) LOOP
  PERFORM pg_temp.seed_signature('etablissement');
  SELECT hash_document INTO h FROM public.contrats_mission;
  -- Construction privilegiee de la fixture AVANT appel utilisateur. Les
  -- triggers restent actifs ; aucun document deja signe n'est modifie.
  PERFORM set_config('request.jwt.claim.sub','',true);
  EXECUTE 'UPDATE public.contrats_mission SET '||mutation;
  EXECUTE 'SELECT ('||replace(mutation,'=',' IS NOT DISTINCT FROM ')||') FROM public.contrats_mission'
    INTO mutation_applied;
  IF mutation_applied IS NOT TRUE THEN RAISE EXCEPTION 'INVALID_DOCUMENT_FIXTURE_NOT_CREATED'; END IF;
  PERFORM set_config('request.jwt.claim.sub',eid::text,true);
  old:=pg_temp.signature_photo();
  r:=public.fn_signer_contrat_otp(cid,'123456',h,NULL);
  IF r->>'error_code' IS DISTINCT FROM 'HASH_DOCUMENT_CHANGE' OR pg_temp.signature_photo() IS DISTINCT FROM old
  THEN RAISE EXCEPTION 'SERVER_DOCUMENT_REFUSAL'; END IF;
  INSERT INTO observations VALUES('server-document-'||label,true);
 END LOOP;

 -- Un document signe historiquement avec une preuve absente/divergente est
 -- conserve byte-identique ; sa deuxieme signature n'invente pas une coherence.
 FOREACH who IN ARRAY ARRAY['soignant','etablissement'] LOOP
  FOREACH code IN ARRAY ARRAY[NULL,repeat('f',64)] LOOP
   PERFORM pg_temp.seed_signature(who);
   other_uid:=CASE who WHEN 'soignant' THEN eid ELSE sid END;
   other_role:=CASE who WHEN 'soignant' THEN 'etablissement' ELSE 'soignant' END;
   INSERT INTO public.signatures_contrats(contrat_id,signataire_user_id,signataire_role,statut_signature,hash_document,signe_a)
     VALUES(cid,other_uid,other_role,'signe',code,now());
   SELECT hash_document INTO h FROM public.contrats_mission;
   old:=pg_temp.signature_photo();
   r:=public.fn_signer_contrat_otp(cid,'123456',h,NULL);
   IF r->>'error_code' IS DISTINCT FROM 'HASH_DOCUMENT_CHANGE' OR pg_temp.signature_photo() IS DISTINCT FROM old
   THEN RAISE EXCEPTION 'HISTORICAL_SIGNATURE_REFUSAL'; END IF;
   INSERT INTO observations VALUES('historical-hash-'||who||'-'||COALESCE(code,'NULL'),true);
  END LOOP;
 END LOOP;

 PERFORM pg_temp.seed_signature('etablissement');
 UPDATE public.signatures_contrats SET statut_signature='signe',hash_document=NULL,signe_a=now();
 old:=pg_temp.signature_photo();
 r:=public.fn_signer_contrat_otp(cid,NULL,NULL,NULL);
 IF r->>'error_code' IS DISTINCT FROM 'DEJA_SIGNE' OR pg_temp.signature_photo() IS DISTINCT FROM old
 THEN RAISE EXCEPTION 'ALREADY_SIGNED_REWRITTEN'; END IF;
 INSERT INTO observations VALUES('already-signed-preserved',true);

 -- Deux signatures positives : ordre S/E puis E/S. Aucun GUC privilegie
 -- d'override ajoute par le banc ; il expose aussi la valeur vide des pools.
 FOREACH guc_label IN ARRAY ARRAY['absent','empty'] LOOP
  IF guc_label='empty' THEN PERFORM set_config('jolene.signature_soignant_en_cours','',true); END IF;
  FOREACH first_role IN ARRAY ARRAY['soignant','etablissement'] LOOP
  PERFORM pg_temp.seed_signature(first_role);
  SELECT hash_document INTO h FROM public.contrats_mission;
  r:=public.fn_signer_contrat_otp(cid,'123456',h,NULL);
  IF (r->>'success')::boolean IS NOT TRUE OR (r->>'contrat_complet')::boolean IS NOT FALSE
  THEN RAISE EXCEPTION 'FIRST_SIGNATURE'; END IF;
  second_role:=CASE first_role WHEN 'soignant' THEN 'etablissement' ELSE 'soignant' END;
  other_uid:=CASE first_role WHEN 'soignant' THEN eid ELSE sid END;
  INSERT INTO public.signatures_contrats(contrat_id,signataire_user_id,signataire_role,otp_envoye_a,otp_code_hash,statut_signature)
    VALUES(cid,other_uid,second_role,now(),encode(extensions.digest('123456|'||cid::text||'|'||other_uid::text,'sha256'),'hex'),'otp_envoye');
  PERFORM set_config('request.jwt.claim.sub',other_uid::text,true);
  r:=public.fn_signer_contrat_otp(cid,'123456',h,NULL);
  IF (r->>'success')::boolean IS NOT TRUE OR (r->>'contrat_complet')::boolean IS NOT TRUE
     OR NOT EXISTS(SELECT 1 FROM public.contrats_mission WHERE statut='SIGNE_COMPLET' AND signature_soignant AND signature_etablissement)
     OR (SELECT count(*) FROM public.signatures_contrats WHERE statut_signature='signe' AND hash_document=h)<>2
  THEN RAISE EXCEPTION 'COMPLETE_SIGNATURE_ORDER'; END IF;
  INSERT INTO observations VALUES('two-orders-'||first_role||'-guc-'||guc_label,true);
  END LOOP;
 END LOOP;

 -- Le premier signe CANVAS ne cree historiquement aucune ligne OTP. Le
 -- document canonique et ses champs restent exacts ; le parcours mixte reste
 -- possible, sans inventer une preuve OTP pour la signature manuscrite.
 FOREACH who IN ARRAY ARRAY['soignant','etablissement'] LOOP
  PERFORM pg_temp.seed_signature(who);
  other_uid:=CASE who WHEN 'soignant' THEN eid ELSE sid END;
  PERFORM set_config('request.jwt.claim.sub',other_uid::text,true);
  IF who='soignant' THEN
   UPDATE public.contrats_mission SET signature_etablissement=true,signature_etablissement_le=now(),
      signature_image_etablissement='data:image/png;base64,SYNTHETIC',statut='SIGNE_ETABLISSEMENT';
  ELSE
   UPDATE public.contrats_mission SET signature_soignant=true,signature_soignant_le=now(),
      signature_image_soignant='data:image/png;base64,SYNTHETIC',statut='SIGNE_SOIGNANT';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',CASE who WHEN 'soignant' THEN sid::text ELSE eid::text END,true);
  SELECT hash_document INTO h FROM public.contrats_mission;
  r:=public.fn_signer_contrat_otp(cid,'123456',h,NULL);
  IF (r->>'success')::boolean IS NOT TRUE OR (r->>'contrat_complet')::boolean IS NOT TRUE
    OR NOT EXISTS(SELECT 1 FROM public.contrats_mission WHERE statut='SIGNE_COMPLET' AND hash_document=h)
    OR (SELECT count(*) FROM public.signatures_contrats WHERE statut_signature='signe' AND hash_document=h)<>1
  THEN RAISE EXCEPTION 'MIXED_CANVAS_OTP_CHANGED'; END IF;
  INSERT INTO observations VALUES('mixed-canvas-then-otp-'||who,true);
 END LOOP;

 PERFORM pg_temp.seed_signature('etablissement');
 UPDATE public.signatures_contrats SET otp_code_hash=encode(extensions.digest('012345|'||cid::text||'|'||eid::text,'sha256'),'hex');
 SELECT hash_document INTO h FROM public.contrats_mission;
 EXECUTE 'SET LOCAL ROLE authenticated';
 r:=public.fn_signer_contrat_otp(cid,'012345',h,NULL);
 EXECUTE 'RESET ROLE';
 IF (r->>'success')::boolean IS NOT TRUE OR NOT EXISTS(SELECT 1 FROM public.signatures_contrats WHERE hash_document=h AND statut_signature='signe')
 THEN RAISE EXCEPTION 'AUTHENTICATED_LEADING_ZERO'; END IF;
 INSERT INTO observations VALUES('authenticated-leading-zero-otp',true);
END;
$witness$;
SELECT jsonb_build_object('schemaVersion',1,'phase','fixed-qualification','postgresMajor',17,'providerCalls',0,
 'casesPassed',(SELECT count(*) FROM observations),'cases',(SELECT jsonb_object_agg(case_name,passed) FROM observations));
ROLLBACK;
"""
    return setup + migration + tests


def main():
    diagnostic.guard(os.environ)
    env={k:os.environ[k] for k in ('PATH','PGHOST','PGPORT','PGDATABASE','PGUSER','PGPASSWORD') if k in os.environ}
    def run(source):
        result=subprocess.run(['psql','-X','-qAt','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],input=source,env=env,text=True,capture_output=True,timeout=60)
        if result.returncode:
            # Seuls les codes constants inscrits dans ce banc passent dans le
            # recu public ; ni SQL, ni DETAIL/CONTEXT, ni message arbitraire.
            state=re.search(r'ERROR:\s+([A-Z0-9]{5}):',result.stderr)
            literal=re.search(r'ERROR:\s+[A-Z0-9]{5}: ([A-Z][A-Z_0-9]+)(?:\n|$)',result.stderr)
            allowed=set(re.findall(r"RAISE EXCEPTION '([A-Z_0-9]+)'|MESSAGE='([A-Z_0-9]+)'",source))
            codes={part for match in allowed for part in match if part}
            code=literal.group(1) if literal and literal.group(1) in codes else 'SIGNATURE_FIX_SQL_FAILED'
            raise WitnessFailure(code,state.group(1) if state else None)
        return result.stdout.strip()
    empty="SELECT (SELECT count(*) FROM pg_class WHERE relnamespace='public'::regnamespace)=0 AND (SELECT count(*) FROM pg_namespace WHERE nspname IN('auth','extensions','private'))=0 AND (SELECT count(*) FROM pg_roles WHERE rolname IN('anon','authenticated','service_role'))=0"
    assert run("SELECT current_setting('server_version_num')::int/10000")=='17'
    assert run(empty)=='t'
    definitions=[p.name for p in sorted((ROOT/'supabase/migrations').glob('*.sql'))
      if re.search(r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public|"public")\s*\.\s*"?fn_signer_contrat_otp"?\s*\(',p.read_text(),re.I)]
    assert definitions and definitions[-1]==MIGRATION, 'NEW_SIGNATURE_DEFINITION_REQUIRES_QUALIFICATION'
    sql=build_sql((ROOT/'supabase/schema/public.sql').read_text(),
      json.loads((ROOT/'tests/fixtures/signature-otp-catalogue-before.json').read_text()),
      json.loads((ROOT/'tests/fixtures/connect-pretransfer-auth-dependencies.json').read_text()),
      (ROOT/'supabase/migrations'/MIGRATION).read_text())
    report=json.loads(run(sql).splitlines()[-1]); assert run(empty)=='t'
    assert report['casesPassed']==69 and all(report['cases'].values())
    report['migrationSha256']=hashlib.sha256((ROOT/'supabase/migrations'/MIGRATION).read_bytes()).hexdigest()
    report['sourceBeforeBodySha256']=diagnostic.BEFORE_BODY
    report['scope']='PG17 synthetic canonical OTP, two contract triggers, certificate SELECT policies; no SMS/Storage/HTTP/full App RLS' 
    report['rollbackVerified']=True
    print(json.dumps(report,ensure_ascii=False))


if __name__=='__main__':
    try: main()
    except Exception as error:
        print(json.dumps({'schemaVersion':1,'completed':False,
          'error':error.code if isinstance(error,WitnessFailure) else 'SIGNATURE_FIX_WITNESS_FAILED',
          'sqlstate':error.sqlstate if isinstance(error,WitnessFailure) else None}))
        raise SystemExit(1)
