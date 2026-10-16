"""V2 staging : moteur SQL réel dans le cluster PG17 éphémère du témoin V1.

Exécute d'abord V1 sans modification, puis son évolution fermée V2. Aucun SDK,
aucun objet fournisseur, aucune base distante. Les reçus ci-dessous sont des
valeurs synthétiques SQL ; ils ne prouvent ni Checkout ni virement bancaire.
"""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
v1 = ROOT/'scripts/ci/connect-staging-admission-pg17.py'
# Le vrai témoin V1 refuse d'abord tout cluster qui n'est pas neuf/local/PG17,
# et finit avec une seule capacité V1 terminale, révoquée, sans transfert.
exec(compile(v1.read_text(), str(v1), 'exec'))
old_capacity = sql('SELECT to_jsonb(c)::text FROM private.stripe_connect_test_capacities c')
old_operation = sql('SELECT to_jsonb(o)::text FROM private.stripe_connect_avant_transfert o')
old_cap = CAP

# Seule adaptation de métadonnées du banc : le registre PG17 minimal V1 n'a
# pas le DEFAULT de production. Aucune routine métier n'est remplacée.
sql('ALTER TABLE private.security_definer_inventory ALTER COLUMN recense_le SET DEFAULT clock_timestamp();')
payout = (ROOT/'supabase/migrations/20261016125516_securiser_beneficiaire_connect_et_versements_standard.sql').read_text()
sql(payout)
live_before = sql("SELECT md5(pg_get_functiondef('public.fn_connect_payout_demarrer(uuid,uuid)'::regprocedure))")
v2 = subprocess.run(['node','--input-type=module','-e',
 "import{readFileSync as r}from'node:fs';import{renderStagingAdmission as a}from'./scripts/ci/connect-staging-admission-render.mjs';import{renderStagingStandardV2 as b}from'./scripts/ci/connect-staging-standard-v2-render.mjs';process.stdout.write(b(a(r('supabase/migrations/20261001201055_reserver_remboursement_connect_avant_transfert.sql','utf8'),r('scripts/ci/connect-staging-admission.sql','utf8')),r('scripts/ci/connect-staging-standard-v2.sql','utf8'),r('supabase/migrations/20261016125516_securiser_beneficiaire_connect_et_versements_standard.sql','utf8')));"],
 cwd=ROOT,capture_output=True,text=True,check=True,timeout=15).stdout
scope = "SET LOCAL jolene.connect_test_project_ref='mejpriaetwgtcstbgfid';"
before = sql(dependency_fingerprint)
refused('BEGIN;'+v2+'ROLLBACK;', 'CONNECT_TEST_V2_INSTALLATION_REFUSED')
refused('BEGIN;'+scope+f"UPDATE private.stripe_connect_test_capacities SET enabled=true,revoked_at=NULL WHERE id='{old_cap}';"+v2+'ROLLBACK;', 'CONNECT_TEST_V2_INSTALLATION_REFUSED')
assert sql(dependency_fingerprint) == before
sql('BEGIN;'+scope+v2+'ROLLBACK;')
assert sql(dependency_fingerprint) == before
assert sql("SELECT count(*) FROM pg_attribute WHERE attrelid='private.stripe_connect_test_capacities'::regclass AND attname='payouts_allowed'") == '0'
sql('BEGIN;'+scope+v2+'COMMIT;')
assert sql("SELECT md5(pg_get_functiondef('public.fn_connect_payout_demarrer(uuid,uuid)'::regprocedure))") == live_before
assert sql("SELECT (to_jsonb(c)-ARRAY['payouts_allowed','max_transfers','max_payouts','transfer_reserved_at','transfer_id','payout_reserved_at','payout_id'])::text FROM private.stripe_connect_test_capacities c") == old_capacity
assert sql('SELECT to_jsonb(o)::text FROM private.stripe_connect_avant_transfert o') == old_operation
assert sql('SELECT private.fn_connect_protocole_ouvert()') == 'f'
print(json.dumps({'v2_sha256':hashlib.sha256(v2.encode()).hexdigest(),'rollback_exact':True,
 'live_start_unchanged':True,'v1_receipt_preserved':True,'provider':False}),flush=True)

public_rpcs = [
 'fn_connect_test_transfer_autoriser(uuid,text,text)',
 'fn_connect_test_payout_autoriser(uuid,text,integer,text,text)',
 'fn_connect_payouts_test_a_traiter(integer,uuid)',
 'fn_connect_test_capacite_par_trace(uuid)',
 'fn_connect_payout_demarrer_test(uuid,uuid,uuid)',
]
for signature in public_rpcs:
 for role in ['anon','authenticated']:
  assert sql(f"SELECT has_function_privilege('{role}','public.{signature}','EXECUTE')") == 'f'
 assert sql(f"SELECT has_function_privilege('service_role','public.{signature}','EXECUTE')") == 't'
 assert sql(f"SELECT count(*)=1 AND bool_and(definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.{signature}'::regprocedure)) FROM private.security_definer_inventory WHERE signature='{signature}'") == 't'
for role in ['anon','authenticated','service_role']:
 assert sql(f"SELECT has_table_privilege('{role}','private.stripe_connect_test_capacities','SELECT,INSERT,UPDATE,DELETE')") == 'f'
 assert sql(f"SELECT has_function_privilege('{role}','private.fn_connect_test_recevoir_mouvements()','EXECUTE')") == 'f'
refused("SET request.jwt.claims='{}'; SELECT public.fn_connect_payouts_test_a_traiter(1,'"+old_cap+"');",'CONNECT_SERVICE_REQUIRED')

def uid(n):
 return f'f1562000-0000-4000-8000-{n:012d}'

def prepare(n,protocol):
 """Deux nouvelles pièces et une intention, pour la même cohorte TEST V1."""
 m,h,c,t,cap,owner,other=[uid(n+i) for i in range(7)]
 session=f'cs_test_V2{n}'
 v2_profile=protocol=='CONNECT_STAGING_STANDARD_TEST_V2'
 sql(f"""
 INSERT INTO public.missions(id,etablissement_id,soignant_assigne_id,intitule,profession_requise,debut_le,fin_le,taux_horaire_base,statut,type_contrat_applique)
 VALUES('{m}','{E}','{S}','Recette V2 sans prestation','IDE',now()-interval '14 days',now()-interval '7 days',20,'EN_COURS','LIBERAL');
 INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,montant_ht,montant_ttc,statut,periode_debut,periode_fin,est_facture_finale_mission)
 VALUES('{h}','TEMOIN-V2-H-{n}','{S}','{E}','{m}',80,80,'EMISE',current_date-14,current_date-8,false);
 INSERT INTO public.factures(id,numero_facture,etablissement_id,mission_id,facture_honoraire_id,montant_ht,montant_tva,montant_ttc,statut,type_document)
 VALUES('{c}','TEMOIN-V2-C-{n}','{E}','{m}','{h}',12,2.4,14.4,'EMISE','FACTURE');
 INSERT INTO private.stripe_connect_test_capacities(id,protocol,project_ref,run_id,server_sha,ui_sha,source_manifest_sha256,expires_at,
 etablissement_id,soignant_id,mission_id,facture_honoraire_id,facture_commission_id,platform_account_id,customer_id,destination_id,
 soignant_cents,commission_cents,total_cents,enabled,transfers_allowed,payouts_allowed,max_transfers,max_payouts)
 VALUES('{cap}','{protocol}','mejpriaetwgtcstbgfid','f1-temoin-v2-{n}',repeat('a',40),repeat('b',40),repeat('c',64),now()+interval '1 hour',
 '{E}','{S}','{m}','{h}','{c}','acct_Platform','cus_Temoin','acct_Temoin',8000,1440,9440,true,
 {str(v2_profile).lower()},{str(v2_profile).lower()},{int(v2_profile)},{int(v2_profile)});
 """)
 claim=f"SELECT public.fn_stripe_payment_flow_claim_connect_test_v1('CONNECT_INVOICE','connect-invoice:{h}','{c}',NULL);"
 assert value(claim)['acquired'] is True
 op=value(f"SELECT public.fn_connect_checkout_preparer('{h}','{c}','v2_attempt_{n}');")['operation_id']
 assert value(f"SELECT public.fn_connect_test_checkout_autoriser('{op}',repeat('a',40),repeat('c',64));")['allowed'] is True
 sql(CTX+f"""UPDATE public.stripe_payment_flow_claims SET stripe_checkout_session_id='{session}' WHERE resource_key='FACTURE:{c}';
 INSERT INTO public.stripe_transfers(id,mission_id,soignant_id,etablissement_id,facture_id,facture_honoraire_id,montant_total,montant_commission,montant_soignant,stripe_checkout_session_id,statut)
 VALUES('{t}','{m}','{S}','{E}','{c}','{h}',94.4,14.4,80,'{session}','EN_ATTENTE');""")
 assert value(f"SELECT public.fn_connect_checkout_lier('{op}','{session}');")['bound'] is True
 source=dict(session_id=session,payment_intent_id=f'pi_V2{n}',charge_id=f'ch_V2{n}',mission_id=m,etablissement_id=E,soignant_id=S,
  facture_honoraire_id=h,facture_commission_id=c,customer_id='cus_Temoin',destination_id='acct_Temoin',soignant_cents=8000,commission_cents=1440,total_cents=9440,livemode=False)
 return dict(m=m,h=h,c=c,t=t,cap=cap,owner=owner,other=other,op=op,source=source,claim=claim)

def arbitrate(x,source=None):
 return f"SELECT public.fn_connect_avant_transfert_arbitrer('{x['op']}','{x['t']}',{literal(json.dumps(source or x['source']))}::jsonb);"

x=prepare(100,'CONNECT_STAGING_STANDARD_TEST_V2')
refused(arbitrate(x,{**x['source'],'livemode':True}),'CONNECT_TEST_TRANSFER_FORBIDDEN')
assert value(arbitrate(x))['orientation']=='TRANSFER'
transfer_auth=f"SELECT public.fn_connect_test_transfer_autoriser('{x['op']}',repeat('a',40),repeat('c',64));"
refused(transfer_auth.replace("repeat('a',40)","repeat('d',40)"),'CONNECT_TEST_TRANSFER_CLOSED')
refused('BEGIN;'+f"UPDATE private.stripe_connect_test_capacities SET enabled=false,revoked_at=clock_timestamp() WHERE id='{x['cap']}';"+transfer_auth+'ROLLBACK;','CONNECT_TEST_CAPACITY_CLOSED')
refused(CTX+f"UPDATE public.stripe_transfers SET stripe_transfer_id='tr_V2' WHERE id='{x['t']}';",'CONNECT_TEST_TRANSFER_RECEIPT')
assert value(transfer_auth)['allowed'] is True
first=sql(f"SELECT transfer_reserved_at::text FROM private.stripe_connect_test_capacities WHERE id='{x['cap']}'")
assert value(transfer_auth)['allowed'] is True
assert sql(f"SELECT transfer_reserved_at::text FROM private.stripe_connect_test_capacities WHERE id='{x['cap']}'") == first
sql(CTX+f"UPDATE public.stripe_transfers SET stripe_payment_intent_id='{x['source']['payment_intent_id']}',stripe_charge_id='{x['source']['charge_id']}',stripe_transfer_id='tr_V2',statut='TRANSFERE' WHERE id='{x['t']}';")
assert sql(f"SELECT transfer_id='tr_V2' FROM private.stripe_connect_test_capacities WHERE id='{x['cap']}'") == 't'
assert sql(f"SELECT standard_payout_state='WAITING' FROM public.stripe_transfers WHERE id='{x['t']}'") == 't'
assert value(x['claim'])['acquired'] is True
assert value('SELECT public.fn_connect_payouts_a_traiter(5);') == []
assert value(f"SELECT public.fn_connect_payouts_test_a_traiter(1,'{x['cap']}');") == [{'id':x['t']}]
assert value(f"SELECT public.fn_connect_payout_prendre('{x['t']}','{x['owner']}');")['livemode'] is False
assert sql(CTX+f"SELECT public.fn_connect_payout_prendre('{x['t']}','{x['other']}') IS NULL;").splitlines()[-1] == 't'
def start(cap=None,owner=None):
 return f"SELECT public.fn_connect_payout_demarrer_test('{x['t']}','{owner or x['owner']}','{cap or x['cap']}');"
assert sql(CTX+f"SELECT public.fn_connect_payout_demarrer('{x['t']}','{x['owner']}');").splitlines()[-1] == 'f'
assert sql(CTX+start()).splitlines()[-1] == 'f'  # Before the TEST reservation.
payout_auth=f"SELECT public.fn_connect_test_payout_autoriser('{x['t']}','tr_V2',0,repeat('a',40),repeat('c',64));"
for bad in [payout_auth.replace("'tr_V2'","'tr_Other'"),payout_auth.replace(',0,',',1,'),payout_auth.replace("repeat('a',40)","repeat('d',40)")]:
 refused(bad,'CONNECT_TEST_PAYOUT_CLOSED')
assert value(payout_auth)['allowed'] is True
assert sql(CTX+start(cap=old_cap)).splitlines()[-1] == 'f'
assert sql(CTX+start(owner=x['other'])).splitlines()[-1] == 'f'
for mutation in [
 f"UPDATE private.stripe_connect_test_capacities SET enabled=false,revoked_at=clock_timestamp() WHERE id='{x['cap']}';",
 f"UPDATE private.stripe_connect_test_capacities SET installed_at=now()-interval '2 days',expires_at=now()-interval '1 day' WHERE id='{x['cap']}';",
 f"INSERT INTO public.paiements_escrow(id,mission_id,etablissement_id,soignant_id,montant_total_cents,commission_cents,honoraires_cents,statut) VALUES('{uid(90)}','{uid(91)}','{E}','{S}',11800,1800,10000,'DEBITE');",
]:
 assert sql(CTX+'BEGIN;'+mutation+start()+'ROLLBACK;').splitlines()[-1] == 'f'
assert sql(CTX+start()).splitlines()[-1] == 't'
assert sql(CTX+start()).splitlines()[-1] == 't'  # Same attempt/idempotency key only.
refused(f"SELECT public.fn_connect_remboursement_prendre('{x['op']}','{x['owner']}');",'CONNECT_REFUND_ORIENTATION')
refused(transfer_auth,'CONNECT_TEST_TRANSFER_CLOSED')

def observe(status,live=False):
 receipt=dict(id='po_V2',status=status,amount=8000,currency='eur',livemode=live,automatic=False,
  metadata=dict(type='CONNECT_STANDARD_PAYOUT',trace_id=x['t'],transfer_id='tr_V2',mission_id=x['m'],soignant_id=S,attempt='0'))
 return f"SELECT public.fn_connect_payout_constater('{x['t']}','acct_Temoin',{literal(json.dumps(receipt))}::jsonb);"
refused(observe('pending',True),'CONNECT_PAYOUT_MODE')
assert value(observe('pending'))['recorded'] is True
assert sql(f"SELECT payout_id='po_V2' FROM private.stripe_connect_test_capacities WHERE id='{x['cap']}'") == 't'
sql(f"UPDATE private.stripe_connect_test_capacities SET enabled=false,revoked_at=clock_timestamp() WHERE id='{x['cap']}';")
assert value(observe('paid'))['recorded'] is True
assert value(observe('pending')) == {'ignored':True}
assert sql(f"SELECT standard_payout_state='PAID' AND statut='PAYE' FROM public.stripe_transfers WHERE id='{x['t']}'") == 't'
assert value(f"SELECT public.fn_connect_test_capacite_par_trace('{x['t']}');")['payout_id']=='po_V2'
assert sql(f"SELECT count(*) FROM public.journaux_audit WHERE action='FINANCE_PAYOUT_PAID' AND id_ressource='{x['m']}'") == '1'
print('CONNECT_V2_TRANSFER_PAYOUT_RESERVATIONS_CAS_RECEIPTS_REVOKED_READBACK_OK',flush=True)

# La branche remboursement V1 reste disponible sur une AUTRE pièce, jamais
# sur celle dont l'orientation TRANSFER a déjà été figée.
y=prepare(200,'CONNECT_STAGING_TEST_V1')
refused(arbitrate(y),'CONNECT_TEST_TRANSFER_FORBIDDEN')
sql(f"INSERT INTO public.litiges(id,mission_id,soignant_id,etablissement_id,initie_par,motif,facture_id,statut) VALUES('{uid(250)}','{y['m']}','{S}','{E}','ETABLISSEMENT','Recette sans prestation','{y['h']}','OUVERT');")
assert value(arbitrate(y))['orientation']=='REFUND'
refused(f"SELECT public.fn_connect_test_transfer_autoriser('{y['op']}',repeat('a',40),repeat('c',64));",'CONNECT_TEST_TRANSFER_CLOSED')
assert value(f"SELECT public.fn_connect_remboursement_prendre('{y['op']}','{y['owner']}');")['can_create'] is True
assert value(f"SELECT public.fn_connect_remboursement_demarrer('{y['op']}','{y['owner']}');")['create_allowed'] is True
receipt=dict(id='re_V2Separate',payment_intent_id=y['source']['payment_intent_id'],charge_id=y['source']['charge_id'],amount=9440,currency='eur',status='succeeded',failure_balance_transaction_id=None)
assert value(f"SELECT public.fn_connect_remboursement_constater('{y['op']}','{y['owner']}',{literal(json.dumps(receipt))}::jsonb);")['status']=='SUCCEEDED'
assert sql(f"SELECT stripe_transfer_id IS NULL AND stripe_payout_id IS NULL AND standard_payout_state IS NULL FROM public.stripe_transfers WHERE id='{y['t']}'") == 't'
assert sql('SELECT private.fn_connect_protocole_ouvert()') == 'f'
assert sql('SELECT count(*) FROM public.soignants WHERE est_compte_test IS TRUE') == '1'
assert sql('SELECT count(*) FROM public.etablissements WHERE est_compte_test IS TRUE') == '1'
print('CONNECT_V2_PG17_SOURCE_PASS_TRANSFERT_PAYOUT_ET_REMBOURSEMENT_DISTINCT_SANS_FOURNISSEUR',flush=True)
