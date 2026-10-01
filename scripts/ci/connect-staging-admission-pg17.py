"""Témoin staging TEST en PostgreSQL 17 éphémère, aucun fournisseur.
Réutilise les vraies dépendances et la vraie migration du témoin Connect.
Il ne peut cibler aucune base Supabase distante. Le scénario SQL ne prouve
pas le Checkout dans le navigateur, ni un paiement ou Refund chez Stripe.
"""
from pathlib import Path
import json
import subprocess
import hashlib

ROOT = Path(__file__).resolve().parents[2]
base = (ROOT/'scripts/ci/connect-pretransfer-pg17.py').read_text()
marker = '# Ouverture EXCLUSIVEMENT dans cette base locale neuve contrôlée en tête du'
assert base.count(marker)==1
# Le prélude refuse host/port/base/roles étrangers avant la première requête.
# Il installe les vraies sources, teste leurs refus et laisse la gate fermée.
exec(compile(base.split(marker)[0], str(ROOT/'scripts/ci/connect-pretransfer-pg17.py'), 'exec'))
assert sql('SELECT private.fn_connect_protocole_ouvert()')=='f'
capacity=(ROOT/'scripts/ci/connect-staging-test-capacity.sql').read_text()
render=subprocess.run(['node','--input-type=module','-e',
 "import{readFileSync as r}from'node:fs';import{renderStagingAdmission as f}from'./scripts/ci/connect-staging-admission-render.mjs';process.stdout.write(f(r('supabase/migrations/20261001201055_reserver_remboursement_connect_avant_transfert.sql','utf8'),r('scripts/ci/connect-staging-admission.sql','utf8')));"],
 cwd=ROOT,capture_output=True,text=True,check=True,timeout=15).stdout
before=sql(dependency_fingerprint)
sql('BEGIN;'+capacity+render+'ROLLBACK;')
assert sql(dependency_fingerprint)==before
assert sql("SELECT to_regclass('private.stripe_connect_test_capacities') IS NULL")=='t'
sql('BEGIN;'+capacity+render+'COMMIT;')
print(json.dumps({'supplement_sha256':hashlib.sha256(render.encode()).hexdigest(),'rollback_exact':True,'gate_generale':False,'fournisseur':False}),flush=True)
S,E,M,H,C,T,L,OWNER,CAP,FOREIGN=[f'f1561000-0000-4000-8000-{n:012d}' for n in range(1,11)]
for role in ['anon','authenticated','service_role']:
 assert sql(f"SELECT has_table_privilege('{role}','private.stripe_connect_test_capacities','SELECT,INSERT,UPDATE,DELETE')")=='f'
for role in ['anon','authenticated']:
 refused(f"SET ROLE {role}; SELECT public.fn_connect_test_capacite_lire('{H}');",'42501')
refused(f"SELECT set_config('request.jwt.claims','{{}}',false); SELECT set_config('request.jwt.claim.role','',false); SELECT public.fn_connect_test_capacite_lire('{H}');",'CONNECT_SERVICE_REQUIRED')
sql(f"""
INSERT INTO public.soignants(id,prenom,nom,email,est_compte_test) VALUES('{S}','Recette','TEST','test@example.invalid',true);
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test,stripe_customer_id)
 VALUES('{E}','Recette TEST','99156000000018','EHPAD','Fixture','Fixture','75001','test@example.invalid',true,'cus_Temoin');
INSERT INTO public.missions(id,etablissement_id,soignant_assigne_id,intitule,profession_requise,debut_le,fin_le,taux_horaire_base,statut,type_contrat_applique)
 VALUES('{M}','{E}','{S}','Recette sans prestation','IDE',now()-interval '14 days',now()-interval '7 days',20,'EN_COURS','LIBERAL');
INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,montant_ht,montant_ttc,statut,periode_debut,periode_fin,est_facture_finale_mission)
 VALUES('{H}','TEMOIN-TEST-H','{S}','{E}','{M}',80,80,'EMISE',current_date-14,current_date-8,false);
INSERT INTO public.factures(id,numero_facture,etablissement_id,mission_id,facture_honoraire_id,montant_ht,montant_tva,montant_ttc,statut,type_document)
 VALUES('{C}','TEMOIN-TEST-C','{E}','{M}','{H}',12,2.4,14.4,'EMISE','FACTURE');
INSERT INTO public.stripe_connect_onboarding(soignant_id,stripe_account_id,statut) VALUES('{S}','acct_Temoin','COMPLET');
""")
claim=f"SELECT public.fn_stripe_payment_flow_claim_connect_test_v1('CONNECT_INVOICE','connect-invoice:{H}','{C}',NULL);"
refused(claim,'P0002')
sql(f"""INSERT INTO private.stripe_connect_test_capacities(id,protocol,project_ref,run_id,server_sha,ui_sha,source_manifest_sha256,expires_at,
 etablissement_id,soignant_id,mission_id,facture_honoraire_id,facture_commission_id,platform_account_id,customer_id,destination_id,
 soignant_cents,commission_cents,total_cents)
 VALUES('{CAP}','CONNECT_STAGING_TEST_V1','mejpriaetwgtcstbgfid','f1-temoin',repeat('a',40),repeat('b',40),repeat('c',64),now()+interval '1 hour',
 '{E}','{S}','{M}','{H}','{C}','acct_Platform','cus_Temoin','acct_Temoin',8000,1440,9440);""")
refused(claim,'CONNECT_TEST_CAPACITY_CLOSED')
assert sql('SELECT count(*) FROM public.stripe_payment_flow_claims')=='0'
sql(f"UPDATE private.stripe_connect_test_capacities SET enabled=true WHERE id='{CAP}';")
# L'autorisation de la seule capacité n'ouvre aucun ancien/général client.
refused(f"SELECT public.fn_stripe_payment_flow_claim_connect_v1('CONNECT_INVOICE','connect-invoice:{H}','{C}',NULL);",'CONNECT_RELEASE_CLOSED')
refused(f"SELECT public.fn_stripe_payment_flow_claim('CONNECT_INVOICE','connect-invoice:{H}','{C}',NULL);",'CONNECT_CLIENT_VERSION_REQUIRED')
# Une réservation historique, même même owner et sans Session, n'est pas adoptée.
sql(f"INSERT INTO public.stripe_payment_flow_claims(resource_key,flow,owner_token) VALUES('FACTURE:{C}','CONNECT_INVOICE','connect-invoice:{H}');")
refused(claim,'CONNECT_TEST_NO_HISTORICAL_CLAIM')
assert sql('SELECT count(*) FROM private.stripe_connect_avant_transfert')=='0'
# Nettoyage de cette seule fixture synthétique dans la base PG17 éphémère.
sql(f"DELETE FROM public.stripe_payment_flow_claims WHERE resource_key='FACTURE:{C}';")
assert value(claim)['acquired'] is True
claim_origin=sql('SELECT claim_reserved_at::text FROM private.stripe_connect_test_capacities')
assert claim_origin
# Réponse perdue après COMMIT : le même claim est repris avant toute opération.
assert value(claim)['acquired'] is True
assert sql('SELECT claim_reserved_at::text FROM private.stripe_connect_test_capacities')==claim_origin
op=value(f"SELECT public.fn_connect_checkout_preparer('{H}','{C}','test_attempt');")['operation_id']
assert value(f"SELECT public.fn_connect_test_checkout_autoriser('{op}',repeat('a',40),repeat('c',64));")['allowed'] is True
refused(f"SELECT public.fn_connect_test_checkout_autoriser('{op}',repeat('d',40),repeat('c',64));",'CONNECT_TEST_CHECKOUT_CLOSED')
refused(f"SELECT public.fn_connect_checkout_preparer('{H}','{C}','test_attempt_2');",'CONNECT_TEST_CHECKOUT_BUDGET')
assert sql('SELECT count(*) FROM private.stripe_connect_avant_transfert')=='1'
assert value(f"SELECT public.fn_connect_checkout_preparer('{H}','{C}','test_attempt');")['operation_id']==op
sql(CTX+f"""UPDATE public.stripe_payment_flow_claims SET stripe_checkout_session_id='cs_test_Temoin' WHERE resource_key='FACTURE:{C}';
INSERT INTO public.stripe_transfers(id,mission_id,soignant_id,etablissement_id,facture_id,facture_honoraire_id,montant_total,montant_commission,montant_soignant,stripe_checkout_session_id,statut)
 VALUES('{T}','{M}','{S}','{E}','{C}','{H}',94.4,14.4,80,'cs_test_Temoin','EN_ATTENTE');""")
assert value(f"SELECT public.fn_connect_checkout_lier('{op}','cs_test_Temoin');")['bound'] is True
source=dict(session_id='cs_test_Temoin',payment_intent_id='pi_Temoin',charge_id='ch_Temoin',mission_id=M,etablissement_id=E,soignant_id=S,
 facture_honoraire_id=H,facture_commission_id=C,customer_id='cus_Temoin',destination_id='acct_Temoin',soignant_cents=8000,commission_cents=1440,total_cents=9440,livemode=False)
def arbitration(body):return f"SELECT public.fn_connect_avant_transfert_arbitrer('{op}','{T}',{literal(json.dumps(body))}::jsonb);"
refused(arbitration(source),'CONNECT_TEST_TRANSFER_FORBIDDEN')
assert sql('SELECT count(*) FROM private.stripe_connect_avant_transfert WHERE orientation IS NOT NULL')=='0'
sql(f"INSERT INTO public.litiges(id,mission_id,soignant_id,etablissement_id,initie_par,motif,facture_id,statut) VALUES('{L}','{M}','{S}','{E}','ETABLISSEMENT','Recette sans prestation','{H}','OUVERT');")
refused(arbitration({**source,'livemode':True}),'CONNECT_TEST_TRANSFER_FORBIDDEN')
assert value(arbitration(source))['orientation']=='REFUND'
assert value(f"SELECT public.fn_connect_remboursements_test_a_traiter(2,'{FOREIGN}');")==[]
assert len(value(f"SELECT public.fn_connect_remboursements_test_a_traiter(2,'{CAP}');"))==1
assert value('SELECT public.fn_connect_remboursements_a_traiter(2);')==[]
assert value(f"SELECT public.fn_connect_remboursement_prendre('{op}','{OWNER}');")['can_create'] is True
sql(f"UPDATE private.stripe_connect_test_capacities SET enabled=false,revoked_at=clock_timestamp() WHERE id='{CAP}';")
refused(f"SELECT public.fn_connect_remboursement_demarrer('{op}','{OWNER}');",'CONNECT_ACCOUNT_NOT_OPERATIONAL')
assert sql('SELECT count(*) FROM private.stripe_connect_test_capacities WHERE refund_reserved_at IS NOT NULL')=='0'
# Réactivation ici uniquement en base éphémère du témoin, jamais opérée cloud.
sql(f"UPDATE private.stripe_connect_test_capacities SET enabled=true,revoked_at=NULL WHERE id='{CAP}';")
assert value(f"SELECT public.fn_connect_remboursement_demarrer('{op}','{OWNER}');")['create_allowed'] is True
first=sql('SELECT refund_reserved_at::text FROM private.stripe_connect_test_capacities')
assert value(f"SELECT public.fn_connect_remboursement_demarrer('{op}','{OWNER}');")['create_allowed'] is True
assert sql('SELECT refund_reserved_at::text FROM private.stripe_connect_test_capacities')==first
receipt=dict(id='re_Temoin',payment_intent_id='pi_Temoin',charge_id='ch_Temoin',amount=9440,currency='eur',status='pending',failure_balance_transaction_id=None)
assert value(f"SELECT public.fn_connect_remboursement_constater('{op}','{OWNER}',{literal(json.dumps(receipt))}::jsonb);")['status']=='PENDING'
sql(f"UPDATE private.stripe_connect_test_capacities SET enabled=false,revoked_at=clock_timestamp() WHERE id='{CAP}';")
assert value(f"SELECT public.fn_connect_remboursement_prendre('{op}','{OWNER}');")['can_create'] is False
receipt['status']='succeeded'
assert value(f"SELECT public.fn_connect_remboursement_constater('{op}','{OWNER}',{literal(json.dumps(receipt))}::jsonb);")['status']=='SUCCEEDED'
assert sql('SELECT private.fn_connect_protocole_ouvert()')=='f'
assert sql("SELECT count(*) FROM public.stripe_transfers WHERE stripe_transfer_id IS NOT NULL")=='0'
assert sql("SELECT count(*) FROM public.soignants WHERE est_compte_test IS TRUE")=='1'
assert sql("SELECT count(*) FROM public.etablissements WHERE est_compte_test IS TRUE")=='1'
print('CONNECT_STAGING_TEST_PG17_SOURCE_OK_AUCUN_FOURNISSEUR',flush=True)
