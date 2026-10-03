"""Vrais verrous PostgreSQL 17 ; schéma minimal isolé, aucun Supabase/Stripe.

Ne prouve pas RLS, callbacks fournisseur ou graphe métier complet. Les deux
triggers et les deux versions du claim sont chargés byte-identiques depuis le lot
testé. La barrière reste fermée dans la livraison ; ce banc seul l’ouvre dans sa
base éphémère après avoir vérifié les refus ancien client / protocole fermé.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
if os.environ.get('JOLENE_PG_CONCURRENCY') != 'CI_EPHEMERE' or os.environ.get('PGHOST') != '127.0.0.1' or os.environ.get('PGDATABASE') != 'paiements_concurrence':
    raise SystemExit('Refus : PostgreSQL éphémère loopback explicitement désigné requis')
PSQL = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
CTX = "SET statement_timeout='12s'; SET lock_timeout='8s'; SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',false);"

def sql(source):
    r = subprocess.run(PSQL, input=source, text=True, capture_output=True, timeout=20)
    if r.returncode:
        raise AssertionError(r.stderr)
    return r.stdout.strip()

assert sql("SELECT current_setting('server_version_num')::int/10000") == '17'
assert sql("SELECT count(*) FROM pg_tables WHERE schemaname='public'") == '0'
migration = (ROOT/'supabase/migrations/20261001122318_lier_paiements_liberaux_aux_factures.sql').read_text()
snapshot = (ROOT/'supabase/schema/public.sql').read_text()
garde = migration[migration.index('CREATE OR REPLACE FUNCTION private.fn_garder_paiement_liberal_facture()'):migration.index('CREATE OR REPLACE FUNCTION public.fn_declarer_paiement_soignant_v2(')]
old_claim = re.search(r'CREATE OR REPLACE FUNCTION "public"\."fn_stripe_payment_flow_claim"\(.*?\nALTER FUNCTION "public"\."fn_stripe_payment_flow_claim"[^;]+;', snapshot, re.S)[0]
claim = re.search(r'CREATE OR REPLACE FUNCTION "public"\."fn_stripe_payment_flow_claim_connect_v1"\(.*?\nALTER FUNCTION "public"\."fn_stripe_payment_flow_claim_connect_v1"[^;]+;', snapshot, re.S)[0]
claim_acl = re.findall(r'(?:REVOKE|GRANT) [^\n]* ON FUNCTION public\.fn_stripe_payment_flow_claim_connect_v1\(text,text,uuid,uuid\)[^\n]*;', snapshot)
assert len(claim_acl) == 2
release_migration = (ROOT/'supabase/migrations/20261001201055_reserver_remboursement_connect_avant_transfert.sql').read_text()
gate = re.search(r"CREATE TABLE private\.stripe_connect_release_gate \(.*?INSERT INTO private\.stripe_connect_release_gate\(protocol,enabled\) VALUES\('CONNECT_PRETRANSFER_V1',false\);", release_migration, re.S)[0]
confirm = re.search(r'CREATE OR REPLACE FUNCTION "public"\."fn_confirmer_paiement_soignant"\(.*?\nALTER FUNCTION "public"\."fn_confirmer_paiement_soignant"[^;]+;', snapshot, re.S)[0]
sql((ROOT/'tests/fixtures/paiements-concurrence-pg17.sql').read_text())
print(json.dumps({'garde_sha256': hashlib.sha256(garde.encode()).hexdigest(), 'claim_sha256': hashlib.sha256(claim.encode()).hexdigest(), 'old_claim_sha256': hashlib.sha256(old_claim.encode()).hexdigest(), 'gate_sha256': hashlib.sha256(gate.encode()).hexdigest(), 'postgres': 17}), flush=True)
M='f1530000-0000-4000-8000-000000000001'
S='f1530000-0000-4000-8000-000000000002'
E='f1530000-0000-4000-8000-000000000003'
H='f1530000-0000-4000-8000-000000000004'
F='f1530000-0000-4000-8000-000000000005'
MANUAL=f"INSERT INTO public.paiements_soignant(mission_id,soignant_id,etablissement_id,facture_honoraire_id,montant_net) VALUES('{M}','{S}','{E}','{H}',80);"
INVOICE=f"SELECT public.fn_stripe_payment_flow_claim_connect_v1('CONNECT_INVOICE','connect-invoice:{H}','{F}',NULL);"
MISSION=f"SELECT public.fn_stripe_payment_flow_claim_connect_v1('CONNECT_MISSION','connect:{M}',NULL,'{M}');"

def seed():
    sql(f"""TRUNCATE public.stripe_payment_flow_claims,public.stripe_transfers,public.paiements_soignant,public.factures,public.factures_honoraires,public.missions;
    INSERT INTO public.missions(id,soignant_assigne_id,etablissement_id,type_contrat_applique,statut,strategie_facturation) VALUES('{M}','{S}','{E}','LIBERAL','EN_COURS','HEBDO_ET_FINALE');
    INSERT INTO public.factures_honoraires(id,mission_id,soignant_id,etablissement_id,type_document,statut,montant_ttc,est_facture_finale_mission,periode_fin)
      VALUES('{H}','{M}','{S}','{E}','FACTURE','EMISE',80,false,current_date-1);
    INSERT INTO public.factures(id,mission_id,etablissement_id,facture_honoraire_id,type_document,statut) VALUES('{F}','{M}','{E}','{H}','FACTURE','EMISE');""")

# Historique présent AVANT l'installation du vrai trigger : aucun disable/bypass.
seed()
sql(f"""INSERT INTO public.paiements_soignant(mission_id,soignant_id,etablissement_id,montant_net)
  VALUES('{M}','{S}','{E}',160);
INSERT INTO public.stripe_payment_flow_claims(resource_key,flow,owner_token,stripe_checkout_session_id)
  VALUES('FACTURE:{F}','CONNECT_INVOICE','connect-invoice:{H}','cs_f153ancien');""")
legacy=re.search(r'CREATE OR REPLACE FUNCTION public.fn_stripe_connect_rapprocher_local\(.*?\$function\$;',migration,re.S)[0]
ML='f1530000-0000-4000-8000-000000000010'
HL='f1530000-0000-4000-8000-000000000011'
FL='f1530000-0000-4000-8000-000000000012'
sql(f"""INSERT INTO public.missions(id,soignant_assigne_id,etablissement_id,type_contrat_applique,statut,strategie_facturation,
  net_a_payer,montant_commission_ht,montant_commission_tva,montant_commission_ttc)
  VALUES('{ML}','{S}','{E}','LIBERAL','TERMINEE','FINALE_UNIQUE',80,12,2.4,14.4);
INSERT INTO public.factures_honoraires(id,mission_id,soignant_id,etablissement_id,type_document,statut,montant_ttc,est_facture_finale_mission,periode_fin)
  VALUES('{HL}','{ML}','{S}','{E}','FACTURE','EMISE',80,true,current_date-1);
INSERT INTO public.factures(id,mission_id,etablissement_id,facture_honoraire_id,type_document,statut,montant_ttc)
  VALUES('{FL}','{ML}','{E}','{HL}','FACTURE','EMISE',14.4);
INSERT INTO public.stripe_transfers(mission_id,soignant_id,etablissement_id,montant_soignant,montant_commission,montant_total,
  statut,stripe_transfer_id,stripe_checkout_session_id,stripe_payment_intent_id,stripe_charge_id)
  VALUES('{ML}','{S}','{E}',80,14.4,94.4,'TRANSFERE','tr_F153ancien','cs_F153ancien','pi_F153ancien','ch_F153ancien');
INSERT INTO public.paiements_soignant(mission_id,soignant_id,etablissement_id,montant_net,statut,stripe_transfer_id,confirme_par_soignant)
  VALUES('{ML}','{S}','{E}',80,'CONFIRME','tr_F153ancien',true);
INSERT INTO public.stripe_payment_flow_claims(resource_key,flow,owner_token,stripe_checkout_session_id,stripe_payment_intent_id)
  VALUES('MISSION:{ML}','CONNECT_MISSION','connect:{ML}','cs_F153ancien','pi_F153ancien');""")
sql(garde + '\n' + gate + '\n' + old_claim + '\n' + claim + '\n' + '\n'.join(claim_acl) + '\n' + confirm + '\n' + legacy)
# Livraison fermée et ancienne signature refusée, sans changer les lignes
# historiques. L'ouverture ci-dessous ne concerne que cette base loopback CI.
def claim_refused(statement, code):
    result = subprocess.run(PSQL,input=CTX+statement,text=True,capture_output=True,timeout=15)
    assert result.returncode != 0 and code in result.stderr and '55000' in result.stderr,result.stderr

claim_photo = "SELECT jsonb_build_array((SELECT jsonb_agg(to_jsonb(c) ORDER BY resource_key) FROM public.stripe_payment_flow_claims c),(SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM public.paiements_soignant p))"
photo = sql(claim_photo)
assert sql("SELECT count(*)=1 AND bool_and(enabled IS FALSE) FROM private.stripe_connect_release_gate") == 't'
for statement in [INVOICE,MISSION]:
    claim_refused(statement.replace('fn_stripe_payment_flow_claim_connect_v1','fn_stripe_payment_flow_claim'),'CONNECT_CLIENT_VERSION_REQUIRED')
    claim_refused(statement,'CONNECT_RELEASE_CLOSED')
assert sql(claim_photo) == photo
sql("UPDATE private.stripe_connect_release_gate SET enabled=true WHERE protocol='CONNECT_PRETRANSFER_V1';")
for statement in [INVOICE,MISSION]:
    claim_refused(statement.replace('fn_stripe_payment_flow_claim_connect_v1','fn_stripe_payment_flow_claim'),'CONNECT_CLIENT_VERSION_REQUIRED')
assert sql(claim_photo) == photo
print('ANCIEN_CLIENT_REFUSE_AVANT_APRES_OUVERTURE_EPHEMERE_ET_NOUVEAU_FERME_SANS_EFFET',flush=True)

# Le claim versionné exact ne permet pas d'engager Stripe au-dessus du virement.
r=subprocess.run(PSQL,input=CTX+INVOICE,text=True,capture_output=True,timeout=15)
assert r.returncode!=0 and 'PAIEMENT_FACTURE_DEJA_DECLARE' in r.stderr and '23514' in r.stderr,r.stderr
result=sql(f"SELECT set_config('request.jwt.claims','{{\"role\":\"authenticated\",\"sub\":\"{S}\"}}',false); SELECT public.fn_confirmer_paiement_soignant((SELECT id FROM public.paiements_soignant WHERE mission_id='{M}'));").splitlines()[-1]
assert json.loads(result).get('success') is True,result
assert sql(f"SELECT montant_net=160 AND facture_honoraire_id IS NULL AND statut='CONFIRME' FROM public.paiements_soignant WHERE mission_id='{M}'")=='t'
assert sql(f"SELECT statut FROM public.factures_honoraires WHERE id='{H}'")=='EMISE'
print('HISTORIQUE_NULL_FK_CONFIRME_SANS_ATTRIBUTION',flush=True)
# Le même événement acquis retrouve sa FH explicite et ne réattribue pas PS.
old_payment=sql(f"SELECT row_to_json(p) FROM public.paiements_soignant p WHERE mission_id='{ML}'")
assert json.loads(sql(CTX+f"SELECT public.fn_stripe_payment_flow_claim_connect_v1('CONNECT_MISSION','connect:{ML}',NULL,'{ML}');").splitlines()[-1])['acquired'] is True
legacy_call=f"SELECT public.fn_stripe_connect_rapprocher_local('{ML}','{S}','{E}','{HL}','{FL}','cs_F153ancien','pi_F153ancien','ch_F153ancien','tr_F153ancien',8000,1440,9440);"
for _ in range(2):
    assert json.loads(sql(CTX+legacy_call).splitlines()[-1])['success'] is True
    assert sql(f"SELECT row_to_json(p) FROM public.paiements_soignant p WHERE mission_id='{ML}'")==old_payment
    assert sql(f"SELECT facture_honoraire_id FROM public.stripe_transfers WHERE mission_id='{ML}'")==HL
    assert sql(f"SELECT statut FROM public.factures_honoraires WHERE id='{HL}'")=='PAYEE'
print('LEGACY_ACQUIS_NULL_FK_REJOUE_SANS_REECRIRE_PAIEMENT',flush=True)
for field,wrong in [('stripe_charge_id','ch_contradictoire'),('stripe_payment_intent_id','pi_contradictoire'),('facture_honoraire_id',H)]:
    old_trace=sql(f"SELECT row_to_json(st) FROM public.stripe_transfers st WHERE mission_id='{ML}'")
    old_value=json.loads(old_trace)[field]
    sql(f"UPDATE public.stripe_transfers SET {field}='{wrong}' WHERE mission_id='{ML}'")
    result=subprocess.run(PSQL,input=CTX+legacy_call,text=True,capture_output=True,timeout=20)
    assert result.returncode!=0 and 'Trace Connect incohérente' in result.stderr,result.stderr
    assert sql(f"SELECT row_to_json(p) FROM public.paiements_soignant p WHERE mission_id='{ML}'")==old_payment
    sql(f"UPDATE public.stripe_transfers SET {field}='{old_value}' WHERE mission_id='{ML}'")
print('LEGACY_CONTRADICTIONS_REFUSEES_SANS_REECRITURE',flush=True)



def open_session(statement):
    p=subprocess.Popen(PSQL,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
    p.stdin.write('BEGIN;'+CTX+"SELECT 'PID:'||pg_backend_pid();"+statement+"SELECT 'PRET';\n")
    p.stdin.flush()
    p.output_buffer=''
    os.set_blocking(p.stdout.fileno(),False)
    return p

def line(p,prefix):
    deadline=time.monotonic()+12
    # psql écrit chaque résultat avec fflush ; lecture bornée sans sleep long.
    sel=selectors.DefaultSelector(); sel.register(p.stdout,selectors.EVENT_READ)
    try:
        while time.monotonic()<deadline:
            while '\n' in p.output_buffer:
                value,p.output_buffer=p.output_buffer.split('\n',1)
                if value.strip().startswith(prefix): return value.strip()
            if not sel.select(timeout=0.2):
                if p.poll() is not None: raise AssertionError(p.stderr.read())
                continue
            chunk=os.read(p.stdout.fileno(),65536)
            if not chunk and p.poll() is not None: raise AssertionError(p.stderr.read())
            p.output_buffer+=chunk.decode()
        raise AssertionError('Session PostgreSQL sans marqueur attendu')
    finally: sel.close()

def race(name,first,second,error,counts):
    seed(); a=b=None
    try:
        a=open_session(first); pid_a=int(line(a,'PID:')[4:]); line(a,'PRET')
        b=open_session(second); pid=int(line(b,'PID:')[4:])
        deadline=time.monotonic()+5; blocked=False
        while time.monotonic()<deadline:
            blocked=sql(f"SELECT wait_event_type='Lock' AND {pid_a}=ANY(pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid={pid}")=='t'
            if blocked: break
            if b.poll() is not None: raise AssertionError('Deuxième écriture terminée sans attendre le verrou : '+b.stderr.read())
            time.sleep(0.05)
        assert blocked, 'Aucun verrou réellement attendu'
        a.stdin.write('COMMIT;\n'); a.stdin.close(); a.wait(timeout=12)
        assert a.returncode==0,a.stderr.read()
        if error:
            b.stdin.close(); b.wait(timeout=12); stderr=b.stderr.read()
            assert b.returncode!=0 and '23514' in stderr and error in stderr,stderr
        else:
            line(b,'PRET'); b.stdin.write('COMMIT;\n'); b.stdin.close(); b.wait(timeout=12)
            assert b.returncode==0,b.stderr.read()
        actual=sql("SELECT (SELECT count(*) FROM public.paiements_soignant)||','||(SELECT count(*) FROM public.stripe_payment_flow_claims)")
        assert actual==counts,(name,actual)
        print(json.dumps({'cas':name,'attente_verrou_observee':True,'resultat':error or 'rejeu_exact','compteurs':actual}),flush=True)
    finally:
        for p in [a,b]:
            if p is not None and p.poll() is None:
                p.kill(); p.wait(timeout=5)

race('manuel_puis_connect',MANUAL,INVOICE,'PAIEMENT_FACTURE_DEJA_DECLARE','1,0')
race('connect_puis_manuel',INVOICE,MANUAL,'PAIEMENT_STRIPE_EN_COURS','0,1')
race('facture_puis_global',INVOICE,MISSION,'PAIEMENT_STRIPE_EN_COURS','0,1')
race('global_puis_facture',MISSION,INVOICE,'PAIEMENT_STRIPE_EN_COURS','0,1')
race('claim_identique_concurrent',INVOICE,INVOICE,None,'0,1')

seed()
sql(CTX+INVOICE+f"""
UPDATE public.stripe_payment_flow_claims SET stripe_checkout_session_id='cs_f153',stripe_payment_intent_id='pi_f153';
INSERT INTO public.stripe_transfers(mission_id,soignant_id,etablissement_id,facture_honoraire_id,montant_soignant,statut,
  stripe_transfer_id,stripe_checkout_session_id,stripe_payment_intent_id,stripe_charge_id)
VALUES('{M}','{S}','{E}','{H}',80,'TRANSFERE','tr_f153','cs_f153','pi_f153','ch_f153');
INSERT INTO public.paiements_soignant(mission_id,soignant_id,etablissement_id,facture_honoraire_id,montant_net,statut,
  stripe_transfer_id,confirme_par_soignant) VALUES('{M}','{S}','{E}','{H}',80,'CONFIRME','tr_f153',true);
""")
before=sql('SELECT row_to_json(p) FROM public.paiements_soignant p')
assert json.loads(sql(CTX+INVOICE).splitlines()[-1])['acquired'] is True
assert sql('SELECT row_to_json(p) FROM public.paiements_soignant p')==before
print('CLAIM_ACQUIS_REJOUE_SANS_REECRITURE',flush=True)
# Le crédit synthétique n'ouvre jamais une nouvelle dette ; une reprise acquise
# sur la même FH reste possible quand seule l'écriture PS a échoué précédemment.
sql(f"DELETE FROM public.paiements_soignant; INSERT INTO public.factures_honoraires(id,mission_id,soignant_id,etablissement_id,type_document,statut,montant_ttc,facture_precedente_id) VALUES('f1530000-0000-4000-8000-000000000020','{M}','{S}','{E}','AVOIR','BROUILLON',20,'{H}');")
assert json.loads(sql(CTX+INVOICE).splitlines()[-1])['acquired'] is True
sql('DELETE FROM public.stripe_transfers; DELETE FROM public.stripe_payment_flow_claims;')
for candidate in [INVOICE,MISSION]:
    result=subprocess.run(PSQL,input=CTX+candidate,text=True,capture_output=True,timeout=20)
    assert result.returncode!=0 and 'AVOIR_A_RAPPROCHER' in result.stderr and '23514' in result.stderr,result.stderr
assert sql('SELECT count(*) FROM public.stripe_payment_flow_claims')=='0'
print('AVOIR_NOUVEAU_CLAIM_REFUSE_REPRISE_ACQUISE_PRESERVEE',flush=True)


# Deux pièces distinctes de la même mission restent réglables indépendamment.
seed()
H2='f1530000-0000-4000-8000-000000000006'
F2='f1530000-0000-4000-8000-000000000007'
sql(f"""INSERT INTO public.factures_honoraires(id,mission_id,soignant_id,etablissement_id,type_document,statut,montant_ttc,est_facture_finale_mission,periode_fin)
VALUES('{H2}','{M}','{S}','{E}','FACTURE','EMISE',60,false,current_date-8);
INSERT INTO public.factures(id,mission_id,etablissement_id,facture_honoraire_id,type_document,statut) VALUES('{F2}','{M}','{E}','{H2}','FACTURE','EMISE');""")
assert json.loads(sql(CTX+INVOICE).splitlines()[-1])['acquired'] is True
second=f"SELECT public.fn_stripe_payment_flow_claim_connect_v1('CONNECT_INVOICE','connect-invoice:{H2}','{F2}',NULL);"
assert json.loads(sql(CTX+second).splitlines()[-1])['acquired'] is True
assert sql('SELECT count(*) FROM public.stripe_payment_flow_claims')=='2'
print('DEUX_PIECES_DISTINCTES_SANS_CONFLIT',flush=True)
# Vrai trigger de propagation : deux FH distinctes, aucun choix historique.
pi = re.search(r'CREATE OR REPLACE FUNCTION public\.fn_propage_stripe_payment_intent_trg\(\).*?\$function\$;', migration, re.S)[0]
pi_trigger = re.search(r'CREATE OR REPLACE TRIGGER "trg_propage_stripe_payment_intent"[^;]+;', snapshot)[0]
sql(pi+'\n'+pi_trigger)
sql(f"UPDATE public.factures_honoraires SET stripe_payment_intent_id='pi_F153premier' WHERE id='{H}';")
before_pi=sql(f"SELECT row_to_json(h) FROM public.factures_honoraires h WHERE id='{H}'")
sql(CTX+f"INSERT INTO public.stripe_transfers(mission_id,soignant_id,etablissement_id,facture_honoraire_id,stripe_payment_intent_id) VALUES('{M}','{S}','{E}','{H2}','pi_F153second');")
assert sql(f"SELECT stripe_payment_intent_id FROM public.factures_honoraires WHERE id='{H2}'")=='pi_F153second'
other_pi=sql(f"SELECT row_to_json(h) FROM public.factures_honoraires h WHERE id='{H2}'")
trace=sql(CTX+f"INSERT INTO public.stripe_transfers(mission_id,soignant_id,etablissement_id,stripe_payment_intent_id) VALUES('{M}','{S}','{E}','pi_F153premier') RETURNING id;").splitlines()[-1]
sql(CTX+f"UPDATE public.stripe_transfers SET facture_honoraire_id='{H}' WHERE id='{trace}'; UPDATE public.stripe_transfers SET stripe_charge_id='ch_F153' WHERE id='{trace}'; UPDATE public.stripe_transfers SET stripe_payment_intent_id=NULL WHERE id='{trace}'; UPDATE public.stripe_transfers SET stripe_payment_intent_id='pi_F153premier' WHERE id='{trace}';")
for change in ["stripe_payment_intent_id='pi_F153contradiction'",f"stripe_payment_intent_id='pi_F153premier',soignant_id='{E}'"]:
    r=subprocess.run(PSQL,input=CTX+f"UPDATE public.stripe_transfers SET {change} WHERE id='{trace}';",text=True,capture_output=True,timeout=20)
    assert r.returncode!=0 and '23514' in r.stderr and 'Trace Stripe incohérente avec la facture explicite' in r.stderr,r.stderr
assert sql(f"SELECT row_to_json(h) FROM public.factures_honoraires h WHERE id='{H}'")==before_pi
assert sql(f"SELECT row_to_json(h) FROM public.factures_honoraires h WHERE id='{H2}'")==other_pi
print('PI_DEUX_FACTURES_ISOLEES_REPARATIONS_ET_CONTRADICTIONS',flush=True)
sql('TRUNCATE public.stripe_payment_flow_claims,public.stripe_transfers,public.paiements_soignant,public.factures,public.factures_honoraires,public.missions,public.journaux_audit;')
assert sql("SELECT (SELECT count(*) FROM public.missions)+(SELECT count(*) FROM public.paiements_soignant)+(SELECT count(*) FROM public.stripe_payment_flow_claims)")=='0'
print('PAIEMENTS_CONCURRENCE_PG17_OK : zéro fixture restante dans la base éphémère',flush=True)
