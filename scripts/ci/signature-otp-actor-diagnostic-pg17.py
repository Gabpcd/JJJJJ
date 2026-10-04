"""Observation synthetique des autorisations apres emission OTP ; aucun fournisseur."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('signature_fixed',ROOT/'scripts/ci/signature-otp-fix-pg17.py')
fixed=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixed)

def build_sql(snapshot,before,auth,migration,phase):
    setup=fixed.build_sql(snapshot,before,auth,migration).split('CREATE TEMP TABLE observations')[0].rstrip()+'\n'
    if phase=='original':
        assert setup.endswith(migration)
        setup=setup[:-len(migration)]
    tests=r"""
CREATE TEMP TABLE observations(case_name text PRIMARY KEY, observed jsonb NOT NULL);
DO $actor_witness$
DECLARE who text; r jsonb; h text; active_before boolean; active_after boolean;
        attached_before boolean; attached_after boolean; failure_state text;
        cid uuid:='f1040000-0000-4000-8000-000000000003';
        sid uuid:='f1040000-0000-4000-8000-000000000001';
        eid uuid:='f1040000-0000-4000-8000-000000000002';
        mid uuid:='f1040000-0000-4000-8000-000000000005';
BEGIN
 FOREACH who IN ARRAY ARRAY['soignant','etablissement'] LOOP
  PERFORM pg_temp.seed_signature(who);
  active_before:=public.fn_compte_auth_actif();
  UPDATE auth.users SET banned_until=now()+interval '1 hour' WHERE id=auth.uid();
  active_after:=public.fn_compte_auth_actif();
  IF active_before IS NOT TRUE OR active_after IS NOT FALSE THEN RAISE EXCEPTION 'ACTOR_SEED_INVALID'; END IF;
  SELECT hash_document INTO h FROM public.contrats_mission;
  r:=NULL; failure_state:=NULL;
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN r:=public.fn_signer_contrat_otp(cid,'123456',h,NULL);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS failure_state=RETURNED_SQLSTATE; END;
  EXECUTE 'RESET ROLE';
  INSERT INTO observations SELECT 'banned-'||who,jsonb_build_object(
   'activeBefore',active_before,'activeAfter',active_after,
   'returnedSuccess',COALESCE((r->>'success')::boolean,false),'sqlstate',failure_state,
   'persistedOtpSignature',EXISTS(SELECT 1 FROM public.signatures_contrats WHERE statut_signature='signe'),
   'persistedContractSignature',CASE who WHEN 'soignant' THEN signature_soignant ELSE signature_etablissement END)
   FROM public.contrats_mission;
  UPDATE auth.users SET banned_until=NULL;
 END LOOP;

 PERFORM pg_temp.seed_signature('etablissement');
 INSERT INTO auth.users(id,raw_app_meta_data,email_confirmed_at)
 VALUES(mid,'{"role":"ADMIN_ETABLISSEMENT"}',now());
 INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif) VALUES(eid,mid,'RH',true);
 PERFORM set_config('request.jwt.claim.sub',mid::text,true);
 attached_before:=public.mon_etablissement_id()=eid;
 IF attached_before IS NOT TRUE OR public.fn_a_permission_etablissement('contrats',eid) IS NOT TRUE
 THEN RAISE EXCEPTION 'MEMBER_SEED_INVALID'; END IF;
 -- La demande existait avec un membre actif ; aucune emission reseau n'est executee.
 UPDATE public.signatures_contrats SET signataire_user_id=mid,
   otp_code_hash=encode(extensions.digest('123456|'||cid::text||'|'||mid::text,'sha256'),'hex');
 UPDATE public.membres_etablissement SET actif=false WHERE user_id=mid;
 attached_after:=COALESCE(public.mon_etablissement_id()=eid,false);
 IF attached_after IS NOT FALSE OR public.fn_a_permission_etablissement('contrats',eid) IS NOT FALSE
 THEN RAISE EXCEPTION 'MEMBER_REVOCATION_INVALID'; END IF;
 SELECT hash_document INTO h FROM public.contrats_mission;
 r:=NULL;failure_state:=NULL;
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN r:=public.fn_signer_contrat_otp(cid,'123456',h,NULL);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS failure_state=RETURNED_SQLSTATE; END;
 EXECUTE 'RESET ROLE';
 INSERT INTO observations SELECT 'removed-establishment-member',jsonb_build_object(
   'activeBefore',true,'activeAfter',public.fn_compte_auth_actif(),
   'attachedBefore',attached_before,'attachedAfter',attached_after,
   'returnedSuccess',COALESCE((r->>'success')::boolean,false),'sqlstate',failure_state,
   'persistedOtpSignature',EXISTS(SELECT 1 FROM public.signatures_contrats WHERE statut_signature='signe'),
   'persistedContractSignature',signature_etablissement) FROM public.contrats_mission;
END;
$actor_witness$;
SELECT jsonb_object_agg(case_name,observed) FROM observations;
ROLLBACK;
"""
    return setup+tests

def main():
    fixed.diagnostic.guard(os.environ)
    env={k:os.environ[k] for k in ('PATH','PGHOST','PGPORT','PGDATABASE','PGUSER','PGPASSWORD') if k in os.environ}
    def run(sql):
        result=subprocess.run(['psql','-X','-qAt','-v','ON_ERROR_STOP=1'],input=sql,text=True,capture_output=True,env=env,timeout=60)
        if result.returncode: raise RuntimeError('ACTOR_DIAGNOSTIC_SQL_FAILED')
        return result.stdout.strip()
    empty="SELECT (SELECT count(*) FROM pg_class WHERE relnamespace='public'::regnamespace)=0 AND (SELECT count(*) FROM pg_namespace WHERE nspname IN('auth','extensions','private'))=0 AND (SELECT count(*) FROM pg_roles WHERE rolname IN('anon','authenticated','service_role'))=0"
    assert run("SELECT current_setting('server_version_num')::int/10000")=='17'
    reports={}
    for phase in ['original','fixed']:
        assert run(empty)=='t'
        sql=build_sql((ROOT/'supabase/schema/public.sql').read_text(),json.loads((ROOT/'tests/fixtures/signature-otp-catalogue-before.json').read_text()),json.loads((ROOT/'tests/fixtures/connect-pretransfer-auth-dependencies.json').read_text()),(ROOT/'supabase/migrations'/fixed.MIGRATION).read_text(),phase)
        reports[phase]=json.loads(run(sql).splitlines()[-1]);assert run(empty)=='t'
    print(json.dumps({'schemaVersion':1,'phase':'actor-after-otp-observation','postgresMajor':17,
      'providerCalls':0,'rollbackVerified':True,'cases':reports,'scope':'observation synthetic valid OTP after ban/removal, no HTTP/SMS'}))

if __name__=='__main__':
    try:main()
    except Exception:
        print(json.dumps({'schemaVersion':1,'completed':False,'error':'ACTOR_DIAGNOSTIC_FAILED'}))
        raise SystemExit(1)
