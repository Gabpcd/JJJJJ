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
# Les trois fonctions redéfinies doivent mettre à jour leur ligne canonique,
# sans en insérer une seconde avec des espaces ajoutés entre les arguments.
for signature in ['fn_connect_checkout_preparer(uuid,uuid,text)',
                  'fn_connect_avant_transfert_arbitrer(uuid,uuid,jsonb)',
                  'fn_connect_remboursement_demarrer(uuid,uuid)']:
 assert sql(f"""SELECT count(*)=1 AND bool_and(i.signature='{signature}'
   AND i.definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.{signature}')))
 FROM private.security_definer_inventory i
 WHERE regexp_replace(i.signature,'[[:space:]]','','g') IN ('{signature}','public.{signature}')""")=='t',signature
print(json.dumps({'supplement_sha256':hashlib.sha256(render.encode()).hexdigest(),'rollback_exact':True,'gate_generale':False,'fournisseur':False}),flush=True)
# Export optionnel du seul delta fermé, AVANT la création des fixtures métier.
# Le job suivant ne recevra que des empreintes, pas le catalogue ou des lignes.
reference_path=os.environ.get('JOLENE_CONNECT_CATALOGUE_REFERENCE')
if reference_path:
 reference_file=Path(reference_path)
 runner_temp=Path(os.environ.get('RUNNER_TEMP',''))
 assert runner_temp.is_absolute() and reference_file.is_absolute() and reference_file.is_relative_to(runner_temp)
 query=subprocess.run(['node','scripts/ci/connect-staging-catalogue-proof.mjs','reference-sql'],
  cwd=ROOT,capture_output=True,text=True,check=True,timeout=15).stdout
 detector=subprocess.run(['node','scripts/ci/connect-staging-catalogue-proof.mjs','detector-sql'],
  cwd=ROOT,capture_output=True,text=True,check=True,timeout=15).stdout
 def measure(mutation=''):
  return json.loads(sql('BEGIN;'+mutation+detector+'ROLLBACK;'))
 original=measure()
 # Ces changements restent eux-mêmes annulés. Le même SQL de partition que la
 # preuve distante doit les détecter ; aucune capture de leurs nouveaux hashes
 # n'est acceptée comme référence.
 for mutation,changed in [
  ('GRANT EXECUTE ON FUNCTION private.fn_connect_exiger_service() TO anon;','allowed'),
  ('ALTER FUNCTION private.fn_connect_exiger_service() SECURITY DEFINER;','allowed'),
  ("CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;",'outside'),
  ('CREATE TABLE private.connect_objet_etranger(id integer);','outside'),
  ("INSERT INTO auth.users(id) VALUES('f1561000-0000-4000-8000-000000000099');",'rows'),
 ]:
  assert measure(mutation)[changed]!=original[changed]
  assert measure()==original
 print('CONNECT_CATALOGUE_DETECTE_MUTATIONS_ACL_CORPS_HORS_PERIMETRE_ET_DONNEES',flush=True)
 # La vue existe dans les deux constats comparés : sa seule création ne doit
 # pas masquer un détecteur qui oublierait les options de sécurité de relation.
 view="CREATE VIEW private.connect_vue_temoin WITH(security_invoker=true,security_barrier=true) AS SELECT id FROM auth.users;"
 view_reference=measure(view)
 assert measure()==original
 for option in ['security_invoker','security_barrier']:
  weakened=measure(view+f'ALTER VIEW private.connect_vue_temoin SET({option}=false);')
  assert weakened['outside']!=view_reference['outside'],option
  assert weakened['allowed']==view_reference['allowed'] and weakened['rows']==view_reference['rows']
  assert measure()==original
 # Un ordre différent des mêmes options n'est pas une modification des droits.
 assert measure(view.replace('security_invoker=true,security_barrier=true','security_barrier=true,security_invoker=true'))==view_reference
 assert measure()==original
 print('CONNECT_CATALOGUE_DETECTE_OPTIONS_SECURITE_VUE_ET_ROLLBACK',flush=True)
 reference=json.loads(sql(query))
 print(json.dumps({'reference_counts':reference['counts']}),flush=True)
 assert reference['counts']['routines']==34 and reference['counts']['relations']==3
 assert reference['counts']['triggers']==2 and reference['counts']['inventory']==19
 with reference_file.open('x') as handle:
  reference_file.chmod(0o600)
  json.dump(reference,handle)
 print('CONNECT_CATALOGUE_REFERENCE_PG17_EXPORTÉE',flush=True)
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
sql(CTX+f"INSERT INTO public.stripe_payment_flow_claims(resource_key,flow,owner_token) VALUES('FACTURE:{C}','CONNECT_INVOICE','connect-invoice:{H}');")
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

# Exercise the new read-only installed-state reader against the SAME terminal,
# revoked fixture above. Extra public tables use their real snapshot DDL;
# operational cron/net/registry tables are explicit local metadata adapters.
for name in ['paiements_mission','escrow_release_queue','externalisation_actions',
             'invoice_audit_log','notifications','email_queue']:
 definition=exact(r'CREATE TABLE IF NOT EXISTS "public"\."'+name+r'" \(.*?\n\);',snapshot)
 sql(definition)
sql("CREATE SCHEMA cron; CREATE SCHEMA net; CREATE SCHEMA supabase_migrations;"
    "CREATE TABLE cron.job(active boolean);"
    "CREATE TABLE cron.job_run_details(end_time timestamptz,status text);"
    "CREATE TABLE net.http_request_queue(id bigint);"
    "CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,name text,statements text[]);")
probe=subprocess.run(['node','scripts/ci/connect-staging-installed-proof.mjs','probe-sql'],
 cwd=ROOT,capture_output=True,text=True,check=True,timeout=15).stdout
assert probe.startswith('BEGIN READ ONLY;') and probe.endswith('ROLLBACK;')
probe_body=probe.replace('BEGIN READ ONLY;','',1).removesuffix('ROLLBACK;')
def installed_measure(mutation=''):
 return json.loads(sql('BEGIN;'+mutation+probe_body+'ROLLBACK;' if mutation else probe))
installed=installed_measure()
for field in ['gate_closed','capacity_revoked','operation_terminal','cohort_known','no_transfer','quiescent']:
 assert installed[field] is True,field
assert installed['capacity_count']==installed['operation_count']==1
assert installed['database_role']=='postgres' and installed['read_only'] is True
for mutation,changed in [
 ("ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON TABLES TO anon;",'default_acl_md5'),
 (f"UPDATE private.stripe_connect_test_capacities SET enabled=true,revoked_at=NULL WHERE id='{CAP}';",'connect_rows'),
 (f"UPDATE public.soignants SET prenom='Changed locally' WHERE id='{S}';",'all_rows'),
 ("UPDATE private.security_definer_inventory SET recense_le=clock_timestamp();",'all_rows'),
]:
 assert installed_measure(mutation)[changed]!=installed[changed],changed
 assert installed_measure()==installed
assert installed_measure(f"UPDATE private.stripe_connect_test_capacities SET enabled=true,revoked_at=NULL WHERE id='{CAP}';")['capacity_revoked'] is False
# Sequence increments intentionally survive rollback. Detect them; never reset
# a value. This sequence exists only in this disposable PostgreSQL witness.
sql('CREATE SEQUENCE private.connect_ci_sequence;')
seq_before=installed_measure()
seq_after=installed_measure("DO $seq$ BEGIN PERFORM nextval('private.connect_ci_sequence'); END $seq$;")
assert seq_after['sequences_md5']!=seq_before['sequences_md5']
assert installed_measure()['sequences_md5']==seq_after['sequences_md5']
print('CONNECT_INSTALLED_LECTURE_TERMINALE_ET_DETECTEURS_PG17_OK',flush=True)
