"""Candidat de témoin PostgreSQL 17, jamais staging/prod ni fournisseur.

Tables/types/dépendances tirés des sources versionnées ; migration entière.
Les sept routines Auth/RBAC et leurs ACL sont les sources relevées en lecture seule.
Auth.users reste une table annexe réduite ; auth.jwt est un adaptateur local.
Ceci ne prouve ni Auth Supabase, ni RLS du graphe complet, ni Stripe TEST.
Les valeurs de classification des lignes de banc ne créent aucun compte.
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
if (os.environ.get('JOLENE_CONNECT_WITNESS') != 'CI_EPHEMERE'
        or os.environ.get('PGHOST') != '127.0.0.1'
        or os.environ.get('PGPORT') != '54329'
        or os.environ.get('PGDATABASE') != 'connect_pretransfer_temoin'
        or os.environ.get('PGUSER') != 'postgres'
        or any(os.environ.get(k) for k in ['PGSERVICE', 'PGSERVICEFILE', 'PGHOSTADDR', 'PGOPTIONS'])):
    raise SystemExit('CONNECT_WITNESS_DESTINATION_REFUSED')
ENV = {k: os.environ[k] for k in ['PATH', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD'] if k in os.environ}
PSQL = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
CTX = "SET statement_timeout='12s'; SET lock_timeout='8s'; SET TIME ZONE 'UTC'; SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',false); SELECT set_config('request.jwt.claim.role','service_role',false);"


def run(source):
    return subprocess.run(PSQL, input=source, env=ENV, text=True, capture_output=True, timeout=20)


def sql(source):
    result = run(source)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def value(source):
    return json.loads(sql(CTX+source).splitlines()[-1])


def refused(source, code):
    result = run(CTX+source)
    assert result.returncode != 0 and code in result.stderr, result.stderr


def literal(value):
    return "'"+str(value).replace("'", "''")+"'"


def exact(pattern, source):
    matches = re.findall(pattern, source, re.S)
    assert len(matches) == 1, (pattern, len(matches))
    return matches[0]


assert sql("SELECT current_setting('server_version_num')::int/10000") == '17'
assert sql("SELECT count(*) FROM pg_class WHERE relnamespace='public'::regnamespace") == '0'
assert sql("SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace") == '0'
assert sql("SELECT count(*) FROM pg_namespace WHERE nspname IN('auth','private','extensions')") == '0'
assert sql("SELECT count(*) FROM pg_roles WHERE rolname IN('anon','authenticated','service_role','supabase_auth_admin','dashboard_user')") == '0'
snapshot = (ROOT/'supabase/schema/public.sql').read_text()
schema = (ROOT/'tests/fixtures/connect-pretransfer-schema-candidate.sql').read_text()
migration = (ROOT/'supabase/migrations/20261001201055_reserver_remboursement_connect_avant_transfert.sql').read_text()
assert schema[schema.index('CREATE TABLE'):] in migration, 'CONNECT_MIGRATION_CORE_CHANGED'
sql("CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; CREATE ROLE service_role NOLOGIN;"
    "CREATE ROLE supabase_auth_admin NOLOGIN; CREATE ROLE dashboard_user NOLOGIN;"
    "CREATE SCHEMA auth; CREATE SCHEMA private; CREATE SCHEMA extensions;"
    "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\" WITH SCHEMA extensions;"
    "CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;"
    "GRANT USAGE ON SCHEMA auth,public TO anon,authenticated,service_role,supabase_auth_admin,dashboard_user;")
for definition in re.findall(r'CREATE TYPE "public"\."[^"]+" AS ENUM \(.*?\n\);', snapshot, re.S):
    sql(definition)
TABLES = ['missions','soignants','etablissements','factures','factures_honoraires','stripe_transfers',
          'litiges','stripe_connect_onboarding','paiements_soignant','paiements_escrow','stripe_payment_flow_claims','journaux_audit',
          'stripe_refunds_queue','stripe_webhook_events','equipe_admin','membres_etablissement']
for name in TABLES:
    definition = exact(r'CREATE TABLE IF NOT EXISTS "public"\."'+name+r'" \(.*?\n\);', snapshot)
    sql(definition)
    sql(exact(r'ALTER TABLE ONLY "public"\."'+name+r'"\n    ADD CONSTRAINT "[^"]+" PRIMARY KEY [^;]+;', snapshot))
    print(json.dumps({'table_source': name, 'sha256': hashlib.sha256(definition.encode()).hexdigest()}), flush=True)
sql("CREATE TABLE private.security_definer_inventory(signature text PRIMARY KEY,categorie text NOT NULL,definition_md5 text NOT NULL,justification text NOT NULL,recense_le timestamptz NOT NULL);")
# Sept routines réelles et six registres acquis en lecture seule ; aucune
# attente du préflight n'est utilisée pour inventer une définition ou un droit.
# La table Auth réduite est la seule annexe nouvelle : aucun signup ni hook.
sql("CREATE TABLE auth.users(id uuid PRIMARY KEY, raw_app_meta_data jsonb, deleted_at timestamptz, banned_until timestamptz, email_confirmed_at timestamptz);")
auth_source=(ROOT/'tests/fixtures/connect-pretransfer-auth-dependencies.json').read_bytes()
assert hashlib.sha256(auth_source).hexdigest()=='9657f7b291bc0a00117a64123b790264b11db4b99f6bd58e3d3f87c821f7ddea'
auth_rows={r['signature']:r for r in json.loads(auth_source)['routines']}
for signature in ['auth.uid()','public.est_admin_valide()','public.est_admin()',
    'public.fn_compte_auth_actif()','public.fn_role_etablissement_courant(uuid)',
    'public.fn_a_permission_etablissement(text,uuid)','public.mon_etablissement_id()']:
    row=auth_rows[signature]
    sql(row['definition']+';'+f"ALTER FUNCTION {signature} OWNER TO {row['owner']};"
        +(f"REVOKE ALL ON FUNCTION {signature} FROM PUBLIC;" if signature!='auth.uid()' else ''))
    for acl in row['acl'].strip('{}').split(','):
        grantee,grantor=acl.split('=X/')
        assert grantor==row['owner']
        sql(f"SET ROLE {grantor}; GRANT EXECUTE ON FUNCTION {signature} TO {grantee or 'PUBLIC'};")
    if row['inventory']:
        inv=row['inventory']
        sql("INSERT INTO private.security_definer_inventory VALUES("+','.join(literal(inv[k]) for k in ['signature','category','body_md5'])+",'Registre constaté RO, sans contenu métier',now());")
    print(json.dumps({'auth_dependency':signature,'definition_sha256':hashlib.sha256(row['definition'].encode()).hexdigest()}),flush=True)

# Corps et ACL du snapshot de l'union, jamais synthétisés depuis les attendus
# du préflight testé. Un ancien snapshot est refusé par la vraie migration.
dependencies = ['fn_ecrire_audit_safe','fn_protect_stripe_transfer','fn_stripe_payment_flow_claim',
    'fn_stripe_refunds_reels_a_traiter','fn_stripe_webhook_event_claim','fn_propage_stripe_payment_intent_trg',
    'fn_preparer_facture_commission_periode','fn_preparer_commission_complement_honoraires',
    'fn_preparer_commission_remplacement_honoraires','fn_preparer_avoir_commission_honoraires',
    'fn_stripe_connect_rapprocher_local','fn_mirror_teleportation_alerte_systeme']
claims_before=(ROOT/'tests/fixtures/connect-pretransfer-claims-before.sql').read_text()
assert hashlib.sha256(claims_before.encode()).hexdigest()=='23bb972d520144643c2658b0225112adc2386e2f507c733a5a26a84638ffbb39'
for name in dependencies:
    routine_source=claims_before if name in ['fn_stripe_payment_flow_claim','fn_stripe_webhook_event_claim'] else snapshot
    definition=exact(r'CREATE OR REPLACE FUNCTION "public"\."'+name+r'"\(.*?\nALTER FUNCTION "public"\."'+name+r'"[^;]+;',routine_source)
    acl=re.findall(r'(?:REVOKE|GRANT) [^\n]* ON FUNCTION "public"\."'+name+r'"[^\n]*;',routine_source)
    assert len(acl)>=2,(name,'ACL_SOURCE_MISSING')
    sql(definition+'\n'+'\n'.join(acl))
    print(json.dumps({'routine_source':name,'sha256':hashlib.sha256((definition+'\n'+'\n'.join(acl)).encode()).hexdigest()}),flush=True)
payment = (ROOT/'supabase/migrations/20261001122318_lier_paiements_liberaux_aux_factures.sql').read_text()
for name,delimiter in [('fn_garder_paiement_liberal_facture','garde'),('fn_garder_reservation_connect','claim')]:
    sql(exact(r'CREATE OR REPLACE FUNCTION private\.'+name+r'\(\).*?\$'+delimiter+r'\$;\nALTER FUNCTION private\.'+name+r'[^;]+;\nREVOKE[^;]+;',payment))
for name in ['trg_paiement_liberal_facture','trg_reservation_connect_paiement']:
    sql(exact(r'CREATE TRIGGER '+name+r'\b[^;]+;',payment))
for name in ['trg_propage_stripe_payment_intent','trg_protect_stripe_transfer','trg_mirror_teleportation_alerte_systeme']:
    sql(exact(r'CREATE OR REPLACE TRIGGER "'+name+r'"[^;]+;', snapshot))

# Le registre de ces six dépendances est la projection du postflight des deux
# migrations préalables, distinctes de celle testée. Aucun droit dérivé de sa
# liste d'attendus : les GRANT précédents viennent du snapshot versionné.
locks=(ROOT/'supabase/migrations/20261001160404_ordonner_verrous_commissions_honoraires.sql').read_text()
registered=dependencies[6:10]+['fn_propage_stripe_payment_intent_trg','fn_stripe_connect_rapprocher_local']
for name in registered:
    prior_source=locks if name in dependencies[6:10] else payment
    assert 'SERVICE_ONLY_REVOQUE' in prior_source and re.search(r"'"+name+r"\([^']*\)'",prior_source)
    sql("INSERT INTO private.security_definer_inventory SELECT p.oid::regprocedure::text,'SERVICE_ONLY_REVOQUE',md5(p.prosrc),'Projection du registre versionné préalable',now() FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname="+literal(name))

dependency_fingerprint="""SET TIME ZONE 'UTC'; SELECT md5(jsonb_build_object(
 'routines',(SELECT jsonb_agg(jsonb_build_array(p.oid::regprocedure::text,md5(pg_get_functiondef(p.oid)),p.proacl,p.proowner) ORDER BY p.oid::regprocedure::text)
 FROM pg_proc p WHERE p.pronamespace IN('public'::regnamespace,'private'::regnamespace,'auth'::regnamespace)),
 'inventory',(SELECT jsonb_agg(to_jsonb(i) ORDER BY signature) FROM private.security_definer_inventory i))::text);"""
before=sql(dependency_fingerprint)
# Les refus s'exécutent avec le corps exact de la migration sous enveloppe
# ROLLBACK. Les seuls BEGIN/COMMIT du fichier sont retirés pour cette enveloppe.
assert migration.count('\nBEGIN;\n')==1 and migration.endswith('COMMIT;\n')
transaction_body=migration.replace('\nBEGIN;\n','\n',1).removesuffix('COMMIT;\n')
for label,mutation,code in [
    ('corps',"CREATE OR REPLACE FUNCTION public.fn_protect_stripe_transfer() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$ BEGIN RETURN NEW; END $$;",'CONNECT_MIGRATION_DEPENDENCY'),
    ('acl',"GRANT EXECUTE ON FUNCTION public.fn_protect_stripe_transfer() TO authenticated;",'CONNECT_MIGRATION_DEPENDENCY'),
    ('auth-corps',"CREATE OR REPLACE FUNCTION public.est_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $$ SELECT false $$;",'SUIVI_DEPENDANCE_INATTENDUE'),
    ('auth-acl',"GRANT EXECUTE ON FUNCTION public.fn_compte_auth_actif() TO anon;",'SUIVI_DEPENDANCE_INATTENDUE'),
    ('auth-registre',"UPDATE private.security_definer_inventory SET definition_md5=repeat('0',32) WHERE signature='fn_compte_auth_actif()';",'SUIVI_DEPENDANCE_INVENTAIRE'),
    ('registre',"UPDATE private.security_definer_inventory SET definition_md5=repeat('0',32) WHERE signature='fn_preparer_facture_commission_periode(uuid)';",'CONNECT_MIGRATION_DEPENDENCY_INVENTORY'),
]:
    refused('BEGIN;'+mutation+transaction_body+'ROLLBACK;',code)
    assert sql("SELECT to_regclass('private.stripe_connect_avant_transfert') IS NULL AND to_regclass('private.stripe_connect_release_gate') IS NULL")=='t'
    assert sql("SELECT count(*) FROM pg_proc WHERE pronamespace IN('public'::regnamespace,'private'::regnamespace) AND (proname LIKE 'fn_connect_%' OR proname IN('fn_stripe_payment_flow_claim_connect_v1','fn_stripe_webhook_event_claim_connect_v1','fn_suivi_remboursements_connect_facture'))")=='0'
    assert sql(dependency_fingerprint)==before
    print(json.dumps({'preflight_refus':label,'dependances_restaurees':True,'nouveaux_objets':0}),flush=True)
sql(migration)
print(json.dumps({'migration_sha256': hashlib.sha256(migration.encode()).hexdigest(), 'scope': 'PG17_EPHEMERE_SANS_FOURNISSEUR'}), flush=True)
assert sql("SELECT count(*) FROM private.security_definer_inventory WHERE signature LIKE 'fn_connect_%'") == '9'
assert sql("SELECT relrowsecurity FROM pg_class WHERE oid='private.stripe_connect_avant_transfert'::regclass") == 't'
for role in ['anon','authenticated','service_role']:
    assert sql(f"SELECT has_table_privilege('{role}','private.stripe_connect_avant_transfert','SELECT,INSERT,UPDATE,DELETE')") == 'f'
for role in ['anon','authenticated']:
    refused(f"SET ROLE {role}; SELECT public.fn_connect_avant_transfert_lire('cs_temoin');", '42501')
refused("SELECT set_config('request.jwt.claims','{}',false); SELECT public.fn_connect_avant_transfert_lire('cs_temoin');", 'CONNECT_SERVICE_REQUIRED')

# La migration livrée crée une barrière FERMÉE. Aucun nouveau claim Connect
# ne peut franchir ce point, et les anciens resteront refusés après ouverture.
assert sql("SELECT private.fn_connect_protocole_ouvert()")=='f'
assert sql("BEGIN; DROP TABLE private.stripe_connect_release_gate; SELECT private.fn_connect_protocole_ouvert(); ROLLBACK;")=='f'
assert sql("SELECT count(*) FROM private.stripe_connect_release_gate WHERE enabled IS FALSE")=='1'
for role in ['anon','authenticated','service_role']:
    assert sql(f"SELECT has_table_privilege('{role}','private.stripe_connect_release_gate','SELECT,INSERT,UPDATE,DELETE')")=='f'
connect_payload=literal(json.dumps({'object':{'metadata':{'type':'CONNECT_MISSION_PAYMENT'}}}))+'::jsonb'
for flow in ['CONNECT_MISSION','CONNECT_INVOICE']:
    refused(f"SELECT public.fn_stripe_payment_flow_claim('{flow}','fixture',NULL,NULL);",'CONNECT_CLIENT_VERSION_REQUIRED')
    refused(f"SELECT public.fn_stripe_payment_flow_claim_connect_v1('{flow}','fixture',NULL,NULL);",'CONNECT_RELEASE_CLOSED')
refused("SELECT public.fn_stripe_webhook_event_claim('evt_closed','checkout.session.completed',"+connect_payload+",'PLATFORM',false);",'CONNECT_CLIENT_VERSION_REQUIRED')
refused("SELECT public.fn_stripe_webhook_event_claim_connect_v1('evt_closed','checkout.session.completed',"+connect_payload+",'PLATFORM',false);",'CONNECT_RELEASE_CLOSED')
assert sql('SELECT count(*) FROM public.stripe_webhook_events')=='0'
assert sql('SELECT count(*) FROM public.stripe_payment_flow_claims')=='0'
# Contrat non Connect toujours utilisable à barrière fermée, sous rollback.
assert sql(CTX+"BEGIN; SELECT public.fn_stripe_webhook_event_claim('evt_ordinary','invoice.paid','{}','PLATFORM',false); ROLLBACK;").splitlines()[-1]=='CLAIMED'
assert sql('SELECT count(*) FROM public.stripe_webhook_events')=='0'
print('BARRIERE_ABSENTE_OU_FERMEE_ANCIENS_CONNECT_REFUSES_AUTRES_EVENTS_PRESERVES',flush=True)
# Ouverture EXCLUSIVEMENT dans cette base locale neuve contrôlée en tête du
# runner. Aucun mécanisme d'activation n'est livré aux clients ou au workflow cloud.
sql("UPDATE private.stripe_connect_release_gate SET enabled=true WHERE protocol='CONNECT_PRETRANSFER_V1';")

S,E,M,H,C,T,L,OWNER = [f'f1560000-0000-4000-8000-{n:012d}' for n in range(1,9)]


def seed():
    sql('TRUNCATE auth.users,private.stripe_connect_avant_transfert,'+','.join('public.'+n for n in TABLES)+';')
    sql(CTX+f"""
    INSERT INTO public.soignants(id,prenom,nom,email,est_compte_test) VALUES('{S}','Banc','Local','local@example.invalid',false);
    INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test,stripe_customer_id)
      VALUES('{E}','Banc local','99156000000018','EHPAD','Fixture','Fixture','75001','local@example.invalid',false,'cus_temoin');
    INSERT INTO public.missions(id,etablissement_id,soignant_assigne_id,intitule,profession_requise,debut_le,fin_le,taux_horaire_base,statut,type_contrat_applique)
      VALUES('{M}','{E}','{S}','Banc sans prestation','IDE',now()-interval '14 days',now()-interval '7 days',20,'EN_COURS','LIBERAL');
    INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,montant_ht,montant_ttc,statut,periode_debut,periode_fin,est_facture_finale_mission)
      VALUES('{H}','TEMOIN-H','{S}','{E}','{M}',80,80,'EMISE',current_date-14,current_date-8,false);
    INSERT INTO public.factures(id,numero_facture,etablissement_id,mission_id,facture_honoraire_id,montant_ht,montant_tva,montant_ttc,statut,type_document)
      VALUES('{C}','TEMOIN-C','{E}','{M}','{H}',12,2.4,14.4,'EMISE','FACTURE');
    INSERT INTO public.stripe_connect_onboarding(soignant_id,stripe_account_id,statut) VALUES('{S}','acct_temoin','COMPLET');
    INSERT INTO public.stripe_payment_flow_claims(resource_key,flow,owner_token,stripe_checkout_session_id)
      VALUES('FACTURE:{C}','CONNECT_INVOICE','connect-invoice:{H}','cs_temoin');
    INSERT INTO public.stripe_transfers(id,mission_id,soignant_id,etablissement_id,facture_id,facture_honoraire_id,montant_total,montant_commission,montant_soignant,stripe_checkout_session_id,statut)
      VALUES('{T}','{M}','{S}','{E}','{C}','{H}',94.4,14.4,80,'cs_temoin','EN_ATTENTE');
    """)
    op = value(f"SELECT public.fn_connect_checkout_preparer('{H}','{C}','attempt_temoin');")['operation_id']
    assert value(f"SELECT public.fn_connect_checkout_lier('{op}','cs_temoin');")['bound'] is True
    return op


def dispute():
    sql(f"INSERT INTO public.litiges(id,mission_id,soignant_id,etablissement_id,initie_par,motif,facture_id,statut) VALUES('{L}','{M}','{S}','{E}','ETABLISSEMENT','Banc sans prestation','{H}','OUVERT');")


SOURCE = dict(session_id='cs_temoin',payment_intent_id='pi_temoin',charge_id='ch_temoin',mission_id=M,
              etablissement_id=E,soignant_id=S,facture_honoraire_id=H,facture_commission_id=C,
              customer_id='cus_temoin',destination_id='acct_temoin',soignant_cents=8000,commission_cents=1440,total_cents=9440,livemode=False)


def arbitrate(op):
    return f"SELECT public.fn_connect_avant_transfert_arbitrer('{op}','{T}',{literal(json.dumps(SOURCE))}::jsonb);"


def lease(op):
    return value(f"SELECT public.fn_connect_remboursement_prendre('{op}','{OWNER}');")


def start(op):
    return value(f"SELECT public.fn_connect_remboursement_demarrer('{op}','{OWNER}');")


def receipt(op, status, failure=None, owner=OWNER):
    body = dict(id='re_temoin',payment_intent_id='pi_temoin',charge_id='ch_temoin',amount=9440,currency='eur',status=status,failure_balance_transaction_id=failure)
    return f"SELECT public.fn_connect_remboursement_constater('{op}','{owner}',{literal(json.dumps(body))}::jsonb);"


# Même ensemble de données : vieux client toujours refusé après ouverture,
# nouveau claim idempotent ; non Connect conserve la même sélection historique.
op=seed()
for flow in ['CONNECT_MISSION','CONNECT_INVOICE']:
    refused(f"SELECT public.fn_stripe_payment_flow_claim('{flow}','fixture','{C}',NULL);",'CONNECT_CLIENT_VERSION_REQUIRED')
assert value(f"SELECT public.fn_stripe_payment_flow_claim_connect_v1('CONNECT_INVOICE','connect-invoice:{H}','{C}',NULL);")['acquired'] is True
for flow in ['CHECKOUT_INVOICE','SEPA_INVOICE']:
    assert value(f"BEGIN; DELETE FROM public.stripe_payment_flow_claims; SELECT public.fn_stripe_payment_flow_claim('{flow}','fixture','{C}',NULL); ROLLBACK;")['acquired'] is True
refused("SELECT public.fn_stripe_webhook_event_claim('evt_open','checkout.session.completed',"+connect_payload+",'PLATFORM',false);",'CONNECT_CLIENT_VERSION_REQUIRED')
assert sql(CTX+"BEGIN; SELECT public.fn_stripe_webhook_event_claim_connect_v1('evt_open','checkout.session.completed',"+connect_payload+",'PLATFORM',false); ROLLBACK;").splitlines()[-1]=='CLAIMED'

# Refermeture après bail : ne crée pas, même si can_create était vrai. Une
# opération déjà identifiée continue ses GET/constats, sans nouvelle autorisation.
op=seed();dispute();value(arbitrate(op));assert lease(op)['can_create'] is True
sql("UPDATE private.stripe_connect_release_gate SET enabled=false;")
refused(f"SELECT public.fn_connect_remboursement_demarrer('{op}','{OWNER}');",'CONNECT_ACCOUNT_NOT_OPERATIONAL')
assert sql('SELECT first_attempt_at IS NULL FROM private.stripe_connect_avant_transfert')=='t'
assert lease(op)['can_create'] is False
sql("UPDATE private.stripe_connect_release_gate SET enabled=true;")
start(op);value(receipt(op,'pending'))
sql("UPDATE private.stripe_connect_release_gate SET enabled=false;")
assert lease(op)['can_create'] is False
assert value(receipt(op,'succeeded'))['status']=='SUCCEEDED'
assert sql(f"SELECT stripe_transfer_id IS NULL AND statut='REMBOURSE' FROM public.stripe_transfers WHERE id='{T}'")=='t'
sql("UPDATE private.stripe_connect_release_gate SET enabled=true;")
print('REFERMETURE_BAIL_POST_REFUSE_OBJET_EXISTANT_CONSTATE',flush=True)

for status in ['pending','requires_action','failed','canceled','succeeded']:
    op=seed(); dispute(); assert value(arbitrate(op))['orientation']=='REFUND'
    assert lease(op)['can_create'] is True; assert start(op)['create_allowed'] is True
    before=sql(f"SELECT jsonb_build_array((SELECT to_jsonb(h) FROM public.factures_honoraires h WHERE id='{H}'),(SELECT to_jsonb(c) FROM public.factures c WHERE id='{C}'))")
    assert value(receipt(op,status))['status']==status.upper()
    expected='REMBOURSE' if status=='succeeded' else 'ECHOUE' if status in ['failed','canceled'] else 'EN_ATTENTE'
    assert sql(f"SELECT statut FROM public.stripe_transfers WHERE id='{T}'")==expected
    assert sql(f"SELECT jsonb_build_array((SELECT to_jsonb(h) FROM public.factures_honoraires h WHERE id='{H}'),(SELECT to_jsonb(c) FROM public.factures c WHERE id='{C}'))")==before
    assert sql('SELECT count(*) FROM public.paiements_soignant')=='0'
    refused(f"UPDATE public.stripe_transfers SET stripe_transfer_id='tr_interdit',statut='TRANSFERE' WHERE id='{T}';",'CONNECT_REFUND_ORIENTATION_LOCKED')
    print(json.dumps({'transition': status,'trace':expected,'documents_identiques':True}),flush=True)

# Témoin ancien moteur : seule la définition v5 figée est substituée, dans
# une transaction annulée. Le code de refus atteste la violation de l'invariant,
# pas une réussite financière. La migration produit ne charge jamais ce fichier.
old_constater=(ROOT/'tests/fixtures/connect-pretransfer-constater-v5.sql').read_text()
assert hashlib.sha256(old_constater.encode()).hexdigest()=='050544f34ee1e2dcbaac5918d035dd0ce670eca9d5bbd7e3cd25015a3dd4e8a5'
old_constater=old_constater.replace('CREATE FUNCTION public.fn_connect_remboursement_constater(',
    'CREATE OR REPLACE FUNCTION public.fn_connect_remboursement_constater(',1)
state_fingerprint="""SELECT md5(jsonb_build_array(
 (SELECT to_jsonb(o) FROM private.stripe_connect_avant_transfert o),
 (SELECT to_jsonb(t) FROM public.stripe_transfers t),
 (SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM public.journaux_audit a),
 md5(pg_get_functiondef('public.fn_connect_remboursement_constater(uuid,uuid,jsonb)'::regprocedure)))::text);"""
for prior in ['failed','canceled']:
    op=seed();dispute();value(arbitrate(op));lease(op);start(op);value(receipt(op,prior));lease(op)
    before=sql(state_fingerprint)
    # L'ancien moteur confirme à tort et conserve l'ancien code d'incident.
    red="""DO $negative$ BEGIN
      IF NOT EXISTS(SELECT 1 FROM private.stripe_connect_avant_transfert
        WHERE refund_status='SUCCEEDED' AND review_code IN('REFUND_FAILED','REFUND_CANCELED')) THEN
        RAISE EXCEPTION 'ANCIEN_TEMOIN_INATTENDU';
      END IF;
      RAISE EXCEPTION 'ANCIEN_MOTEUR_SUCCES_CONTRADICTOIRE';
    END $negative$;"""
    refused('BEGIN;'+old_constater+receipt(op,'succeeded')+red+'ROLLBACK;',
        'ANCIEN_MOTEUR_SUCCES_CONTRADICTOIRE')
    assert sql(state_fingerprint)==before
    result=value(receipt(op,'succeeded'))
    assert result['status']=='REVIEW' and result['review_code']=='REFUND_STATUS_CONTRADICTORY'
    assert sql("SELECT succeeded_at IS NULL FROM private.stripe_connect_avant_transfert")=='t'
    assert sql(f"SELECT statut='ECHOUE' AND stripe_transfer_id IS NULL FROM public.stripe_transfers WHERE id='{T}'")=='t'
    assert sql("SELECT count(*) FROM public.journaux_audit WHERE details::text LIKE '%CONNECT_REMBOURSE_AVANT_TRANSFERT_POUR_LITIGE%'")=='0'
    assert sql('SELECT count(*) FROM public.journaux_audit')=='2'
    assert sql('SELECT count(*) FROM public.paiements_soignant')=='0'
    lease(op);assert value(receipt(op,'succeeded'))['status']=='REVIEW'
    assert sql('SELECT count(*) FROM public.journaux_audit')=='2'
    print(json.dumps({'ancien_moteur_rouge':prior,'candidat':'REVIEW','success_audit':0,'rollback_ancien_exact':True}),flush=True)

op=seed(); dispute(); value(arbitrate(op)); lease(op); start(op)
sql("CREATE FUNCTION public.refuser_constat_temoin() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.statut='REMBOURSE' THEN RAISE EXCEPTION 'SQL_REFUSE_TEMOIN'; END IF; RETURN NEW; END $$; CREATE TRIGGER zz_refus_temoin BEFORE UPDATE ON public.stripe_transfers FOR EACH ROW EXECUTE FUNCTION public.refuser_constat_temoin();")
refused(receipt(op,'succeeded'),'SQL_REFUSE_TEMOIN')
assert sql("SELECT refund_id IS NULL AND refund_status='READY' FROM private.stripe_connect_avant_transfert")=='t'
assert sql('SELECT count(*) FROM public.journaux_audit')=='0'
sql('DROP TRIGGER zz_refus_temoin ON public.stripe_transfers; DROP FUNCTION public.refuser_constat_temoin();')
assert value(receipt(op,'succeeded'))['status']=='SUCCEEDED'
prior=sql('SELECT succeeded_at FROM private.stripe_connect_avant_transfert');lease(op)
assert value(receipt(op,'pending'))['status']=='SUCCEEDED';lease(op)
refused(receipt(op,'failed'),'CONNECT_REFUND_RETURN_NOT_PROVEN')
assert value(receipt(op,'failed','txn_retour'))['status']=='REVIEW'
assert sql('SELECT succeeded_at FROM private.stripe_connect_avant_transfert')==prior
assert sql('SELECT count(*) FROM public.journaux_audit')=='2'
assert sql(f"SELECT statut FROM public.stripe_transfers WHERE id='{T}'")=='ECHOUE'
print('ATOMICITE_REFUS_SQL_REPRISE_INCIDENT_ET_SUCCES_HISTORIQUE',flush=True)

for closure in ['anonymisation','suspension']:
    op=seed();dispute();value(arbitrate(op));lease(op);start(op);value(receipt(op,'pending'))
    mutation = "supprime_le=now(),prenom='Anonyme',nom='Anonyme'" if closure=='anonymisation' else "statut_compte='SUSPENDU'"
    sql(f"UPDATE public.soignants SET {mutation} WHERE id='{S}';")
    assert lease(op)['can_create'] is False
    assert value(receipt(op,'succeeded'))['status']=='SUCCEEDED'
    print(json.dumps({'fermeture':closure,'constat_seul':True}),flush=True)

# Le bail A est expiré après sa première intention ; B le reprend dans une
# autre transaction. Le constat tardif de A ne doit écrire ni trace ni audit.
op=seed();dispute();value(arbitrate(op));lease(op);start(op)
other='f1560000-0000-4000-8000-000000000009'
sql("UPDATE private.stripe_connect_avant_transfert SET lease_until=clock_timestamp()-interval '1 second';")
assert value(f"SELECT public.fn_connect_remboursement_prendre('{op}','{other}');")['acquired'] is True
refused(receipt(op,'succeeded'),'CONNECT_REFUND_RECEIPT')
assert sql("SELECT refund_id IS NULL AND refund_status='READY' FROM private.stripe_connect_avant_transfert")=='t'
assert sql('SELECT count(*) FROM public.journaux_audit')=='0'
assert value(receipt(op,'succeeded',owner=other))['status']=='SUCCEEDED'
assert sql('SELECT count(*) FROM public.journaux_audit')=='1'
print('BAIL_EXPIRE_REPRIS_CONSTAT_ANCIEN_TOKEN_REFUSE',flush=True)

# Trois sessions : A tient ST seule ; B doit attendre ST AVANT de prendre FH.
# A répare ensuite le PI (vrai trigger ST→FH), ce qui révèle une inversion FH→ST.
def session(statement):
    p=subprocess.Popen(PSQL,env=ENV,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
    p.stdin.write('BEGIN;'+CTX+"SELECT 'PID:'||pg_backend_pid();"+statement+"SELECT 'PRET';\n");p.stdin.flush()
    p.buffer='';os.set_blocking(p.stdout.fileno(),False);return p


def line(p, prefix):
    deadline=time.monotonic()+12
    sel=selectors.DefaultSelector();sel.register(p.stdout,selectors.EVENT_READ)
    try:
        while time.monotonic()<deadline:
            while '\n' in p.buffer:
                item,p.buffer=p.buffer.split('\n',1)
                if item.startswith(prefix):return item
            if sel.select(timeout=.2):
                p.buffer+=os.read(p.stdout.fileno(),65536).decode()
            if p.poll() is not None:raise AssertionError(p.stderr.read())
        raise AssertionError('CONNECT_SESSION_TIMEOUT')
    finally:sel.close()


op=seed();a=b=None
try:
    a=session(f"SELECT id FROM public.stripe_transfers WHERE id='{T}' FOR UPDATE;")
    pid_a=int(line(a,'PID:')[4:]);line(a,'PRET')
    b=session(f"SELECT public.fn_connect_checkout_verifier('{op}','cs_temoin');")
    pid_b=int(line(b,'PID:')[4:]);deadline=time.monotonic()+5;blocked=False
    while time.monotonic()<deadline:
        blocked=sql(f"SELECT wait_event_type='Lock' AND {pid_a}=ANY(pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid={pid_b}")=='t'
        if blocked:break
        time.sleep(.05)
    assert blocked,'CONNECT_LOCK_NOT_OBSERVED'
    a.stdin.write(f"UPDATE public.stripe_transfers SET stripe_payment_intent_id='pi_temoin' WHERE id='{T}'; COMMIT;\n");a.stdin.close();a.wait(timeout=12)
    assert a.returncode==0,a.stderr.read()
    line(b,'PRET');b.stdin.write('COMMIT;\n');b.stdin.close();b.wait(timeout=12)
    assert b.returncode==0,b.stderr.read()
    assert sql(f"SELECT stripe_payment_intent_id FROM public.factures_honoraires WHERE id='{H}'")=='pi_temoin'
    print('REPARATION_PI_DIRECTE_ST_FH_VS_REPRISE_MISSION_ST_FH_SANS_CYCLE',flush=True)
finally:
    for process in [a,b]:
        if process is not None and process.poll() is None:process.kill();process.wait(timeout=5)

# Deux arbitres simultanés : une seule orientation durable, deux reçus liés
# au même objet. Le second attend réellement la mission tenue par le premier.
op=seed();dispute();a=b=None
try:
    a=session(arbitrate(op));pid_a=int(line(a,'PID:')[4:])
    first=json.loads(line(a,'{'));assert first['id']==op and first['orientation']=='REFUND';line(a,'PRET')
    b=session(arbitrate(op));pid_b=int(line(b,'PID:')[4:]);deadline=time.monotonic()+5;blocked=False
    while time.monotonic()<deadline:
        blocked=sql(f"SELECT wait_event_type='Lock' AND {pid_a}=ANY(pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid={pid_b}")=='t'
        if blocked:break
        time.sleep(.05)
    assert blocked,'CONNECT_ARBITRATION_LOCK_NOT_OBSERVED'
    a.stdin.write('COMMIT;\n');a.stdin.close();a.wait(timeout=12);assert a.returncode==0,a.stderr.read()
    second=json.loads(line(b,'{'));assert second['id']==op and second['orientation']=='REFUND';line(b,'PRET')
    b.stdin.write('COMMIT;\n');b.stdin.close();b.wait(timeout=12);assert b.returncode==0,b.stderr.read()
    assert sql("SELECT count(*)=1 AND bool_and(orientation='REFUND') FROM private.stripe_connect_avant_transfert")=='t'
    assert sql('SELECT count(*) FROM public.paiements_soignant')=='0'
    assert sql('SELECT count(*) FROM public.journaux_audit')=='0'
    print('DEUX_ARBITRES_MEME_ORIENTATION_APRES_ATTENTE_REELLE',flush=True)
finally:
    for process in [a,b]:
        if process is not None and process.poll() is None:process.kill();process.wait(timeout=5)

# Projection publique réelle avec les sept routines d'autorisation réelles.
# Auth.users réduit et claims GUC synthétiques : aucun login Supabase ni RLS
# complet n'est revendiqué. Les fixtures ne franchissent aucun fournisseur.
member,admin,foreign=[f'f1560000-0000-4000-8000-{n:012d}' for n in range(90,93)]
def user_context(uid):
    claims=literal(json.dumps({'sub':uid,'role':'authenticated'}))
    return f"SELECT set_config('request.jwt.claim.sub','{uid}',false); SELECT set_config('request.jwt.claims',{claims},false); SET ROLE authenticated;"

def projection(uid,session='cs_temoin'):
    session_sql='NULL' if session is None else literal(session)
    return value(user_context(uid)+f"SELECT public.fn_suivi_remboursements_connect_facture('{H}',{session_sql});")

for expected_status in ['READY','PENDING','REQUIRES_ACTION','SUCCEEDED','FAILED','CANCELED','REVIEW']:
    op=seed();dispute();value(arbitrate(op))
    if expected_status!='READY':
        lease(op);start(op)
        value(receipt(op,'failed' if expected_status=='REVIEW' else expected_status.lower()))
        if expected_status=='REVIEW':
            lease(op);value(receipt(op,'succeeded'))
    for actor,role in [(S,'SOIGNANT'),(E,'ETABLISSEMENT'),(member,'MEMBRE_ETABLISSEMENT'),(admin,'ADMIN_PLATEFORME'),(foreign,'SOIGNANT')]:
        sql(f"INSERT INTO auth.users VALUES('{actor}',{literal(json.dumps({'role':role}))}::jsonb,NULL,NULL,now());")
    sql(f"INSERT INTO public.membres_etablissement(etablissement_id,user_id,role) VALUES('{E}','{member}','LECTURE_SEULE');")
    sql(f"INSERT INTO public.equipe_admin(user_id,nom,prenom,email,acces_groupes) VALUES('{admin}','Banc','Admin','admin@example.invalid',ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']);")
    before=sql(state_fingerprint)
    for actor in [S,E,member,admin]:
        result=projection(actor)
        assert result['lecture_complete'] is True and len(result['operations'])==1
        operation=result['operations'][0]
        assert operation['id']==op and operation['statut']==expected_status
        assert operation['montant_honoraires_centimes']==8000
        assert operation['montant_commission_centimes']==(None if actor==S else 1440)
        assert operation['montant_total_centimes']==(None if actor==S else 9440)
        assert not any(secret in json.dumps(result) for secret in ['pi_temoin','ch_temoin','cus_temoin','acct_temoin','re_temoin','attempt_temoin'])
        assert (operation['succeeded_at'] is not None)==(expected_status=='SUCCEEDED')
        assert result['paiement_statut']==('REMBOURSE' if expected_status=='SUCCEEDED' else 'ECHOUE' if expected_status in ['FAILED','CANCELED','REVIEW'] else 'EN_ATTENTE')
    assert projection(E,None)['paiement_statut'] is None
    assert projection(E,'cs_etrangere')['operations']==[]
    assert projection(E,'cs_etrangere')['paiement_statut'] is None
    refused(user_context(foreign)+f"SELECT public.fn_suivi_remboursements_connect_facture('{H}');",'42501')
    sql(f"UPDATE public.membres_etablissement SET role='RH' WHERE user_id='{member}';")
    refused(user_context(member)+f"SELECT public.fn_suivi_remboursements_connect_facture('{H}');",'42501')
    sql(f"UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id='{E}';")
    refused(user_context(E)+f"SELECT public.fn_suivi_remboursements_connect_facture('{H}');",'42501')
    for actor_role in ['anon','service_role']:
        refused(f"SET ROLE {actor_role}; SELECT public.fn_suivi_remboursements_connect_facture('{H}');",'42501')
    assert sql(state_fingerprint)==before
    print(json.dumps({'projection_reelle':expected_status,'roles_lus':4,'tenant_role_compte_inactif_refuses':True,'aucun_effet_financier':True}),flush=True)

print('CONNECT_CANDIDATE_PG17_OK_LIMITES_AUTH_RLS_FOURNISSEUR_NON_PROUVES',flush=True)
