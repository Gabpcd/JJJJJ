"""Banc PostgreSQL 17 isolé — lot 2 B1 (B9) : fn_scanner_code_pointage ne renvoie
plus au soignant le code de pointage suivant (`nouveau_code`) ni son HMAC
(`nouveau_hmac`).

Phase statique (sans base) : la migration B1 est unique, postérieure à
20261102150000, sans BEGIN/COMMIT ni `$$` nu, sans GRANT/REVOKE/ALTER/DROP, et
son corps est exactement le corps LIVE (prosrc MD5 a2af098e…, identique à
20261017165819 et au dump re-baseliné) moins les deux clés ; le dump est aligné ;
aucun client web, mock e2e ni edge function ne lit `nouveau_code`.

Phase PostgreSQL 17 (base éphémère vide) : vraie chaîne de migrations du scanner
(20260903194000 → 20261017165819 : MD5, ACL et inventaire égaux au LIVE relu le
02/11/2026), témoin du défaut, puis migration B1 entière : réponse réduite aux
sept clés de corrélation, rotation et HMAC stocké conservés, code relu par
l'établissement via fn_etat_pointage_mission (définition du dump), exceptions
inchangées, ACL et inventaire préservés, rejeu refusé.

Tables minimales, `est_admin_valide()` simplifié (aucun administrateur) : ne
prouve ni STAGING, ni la production, ni les triggers métier de `presences`, ni
l'interface web ou native, ni un appareil physique.

Usage : python3 scripts/ci/scanner-code-sans-code-suivant-pg17.py [--statique]
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / 'supabase/migrations'
LIVE_MD5 = 'a2af098e60488cbef102c80594b74d10'
ATTENDU_MD5 = '4568c8a01be5be24587cffa9bdd9c1c3'
DERNIERE_VERSION_DISTANTE = '20261102150000'
RETIRE = "    'nouveau_code', v_new_code,\n    'nouveau_hmac', v_new_hmac,\n"
CLES_REPONSE = {'type_scan_effectue', 'prochain_type_scan', 'creneau_effectif_id', 'horodatage_effectif',
                'horodatage_arrondi', 'numero_scan', 'validation_etab_requise'}
EN_TETE = 'CREATE OR REPLACE FUNCTION public.fn_scanner_code_pointage('


def md5(texte):
    return hashlib.md5(texte.encode()).hexdigest()


def corps(sql, debut, etiquette):
    i = sql.index(debut)
    ouverture = f'AS {etiquette}'
    j = sql.index(ouverture, i) + len(ouverture)
    return sql[j:sql.index(etiquette, j)]


def en_tete(sql):
    i = sql.index(EN_TETE)
    return sql[i:sql.index('AS $function$', i)]


# ---------------------------------------------------------------- phase statique
candidates = sorted(p for p in MIGRATIONS.iterdir() if re.fullmatch(r'\d{14}_scanner_code_sans_code_suivant\.sql', p.name))
assert len(candidates) == 1, f'MIGRATION_B1_ABSENTE_OU_DUPLIQUEE : {[p.name for p in candidates]}'
MIGRATION_PATH = candidates[0]
MIGRATION = MIGRATION_PATH.read_text(encoding='utf-8')
assert MIGRATION_PATH.name[:14] > DERNIERE_VERSION_DISTANTE, 'MIGRATION_B1_HORODATAGE_NON_POSTERIEUR'
assert not re.search(r'(?im)^\s*(BEGIN|COMMIT|ROLLBACK)\s*;', MIGRATION), 'MIGRATION_B1_TRANSACTION_INTERNE'
assert '$$' not in MIGRATION, 'MIGRATION_B1_DOLLAR_QUOTING_NU'
assert not re.search(r'(?im)^\s*(GRANT|REVOKE|ALTER\s+FUNCTION|DROP)\b', MIGRATION), 'MIGRATION_B1_ACL_OU_DDL_HORS_PERIMETRE'
assert MIGRATION.count('CREATE OR REPLACE FUNCTION') == 1 and MIGRATION.count(EN_TETE) == 1, 'MIGRATION_B1_PERIMETRE'

ROTATION = (MIGRATIONS / '20261017165819_garantir_rotation_code_pointage.sql').read_text(encoding='utf-8')
CORPS_LIVE = corps(ROTATION, EN_TETE, '$function$')
assert md5(CORPS_LIVE) == LIVE_MD5, 'SOURCE_20261017165819_DIFFERENTE_DU_LIVE'
CORPS_B1 = corps(MIGRATION, EN_TETE, '$function$')
assert en_tete(MIGRATION) == en_tete(ROTATION), 'MIGRATION_B1_SIGNATURE_OU_QUALIFICATEURS_MODIFIES'
assert CORPS_LIVE.count(RETIRE) == 1 and CORPS_B1 == CORPS_LIVE.replace(RETIRE, ''), 'MIGRATION_B1_DIFF_AUTRE_QUE_LES_DEUX_CLES'
assert md5(CORPS_B1) == ATTENDU_MD5, 'MIGRATION_B1_MD5_INATTENDU'
assert 'nouveau_code' not in CORPS_B1 and 'nouveau_hmac' not in CORPS_B1
assert MIGRATION.count(f"'{LIVE_MD5}'") >= 2 and MIGRATION.count(f"'{ATTENDU_MD5}'") >= 1, 'MIGRATION_B1_GARDES_MD5_ABSENTES'

DUMP = (ROOT / 'supabase/schema/public.sql').read_text(encoding='utf-8')
assert md5(corps(DUMP, 'CREATE OR REPLACE FUNCTION "public"."fn_scanner_code_pointage"(', '$$')) == ATTENDU_MD5, 'DUMP_NON_ALIGNE'

lecteurs = []
for dossier in ['src', 'e2e', 'supabase/functions']:
    for fichier in (ROOT / dossier).rglob('*'):
        if fichier.is_file() and fichier.suffix in {'.ts', '.tsx', '.js', '.mjs', '.json'}:
            texte = fichier.read_text(encoding='utf-8', errors='replace')
            if 'nouveau_code' in texte or 'nouveau_hmac' in texte:
                lecteurs.append(str(fichier.relative_to(ROOT)))
assert lecteurs == [], f'LECTEURS_DU_CODE_SUIVANT : {lecteurs}'

statique = {'migration': MIGRATION_PATH.name, 'migration_sha256': hashlib.sha256(MIGRATION.encode()).hexdigest(),
            'live_md5': LIVE_MD5, 'b1_md5': ATTENDU_MD5, 'cles_retirees': ['nouveau_code', 'nouveau_hmac']}
if sys.argv[1:] == ['--statique']:
    print(json.dumps(statique))
    print('SCANNER_SANS_CODE_SUIVANT_STATIQUE_OK')
    raise SystemExit(0)
assert sys.argv[1:] == [], 'ARGUMENTS_REFUSES'

# ------------------------------------------------------------ phase PostgreSQL 17
if (os.environ.get('JOLENE_SCANNER_WITNESS') != 'LOCAL_EPHEMERE'
        or os.environ.get('PGHOST') != '127.0.0.1'
        or os.environ.get('PGPORT') not in {'5432', '54329'}
        or os.environ.get('PGDATABASE') != 'scanner_sans_code_suivant'
        or os.environ.get('PGUSER') != 'postgres'
        or any(os.environ.get(k) for k in ['PGSERVICE', 'PGSERVICEFILE', 'PGHOSTADDR', 'PGOPTIONS'])):
    raise SystemExit('SCANNER_WITNESS_DESTINATION_REFUSED')
ENV = {k: os.environ[k] for k in ['PATH', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD'] if k in os.environ}
CMD = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']


def run(source):
    return subprocess.run(CMD, input="SET statement_timeout='8s'; SET lock_timeout='3s';" + source,
                          env=ENV, text=True, capture_output=True, timeout=30)


def sql(source):
    result = run(source)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def refused(source, *fragments):
    result = run(source)
    assert result.returncode != 0 and all(f in result.stderr for f in fragments), (result.stdout, result.stderr)


def as_user(user, query, role='authenticated'):
    return f"SET ROLE {role}; SET request.jwt.claim.sub='{user}';" + query


def ddl_dump(nom):
    debut = DUMP.index(f'CREATE OR REPLACE FUNCTION "public"."{nom}"(')
    return DUMP[debut:DUMP.index('\n$$;\n', debut) + len('\n$$;\n')]


assert sql("SELECT current_setting('server_version_num')::int/10000") == '17'
assert sql("SELECT current_database()") == 'scanner_sans_code_suivant'
assert sql("SELECT count(*) FROM pg_class WHERE relnamespace='public'::regnamespace") == '0'
assert sql("SELECT to_regnamespace('auth') IS NULL") == 't'

S = 'b1000000-0000-4000-8000-000000000001'      # soignant assigné
O = 'b1000000-0000-4000-8000-000000000002'      # autre soignant
M = 'b1000000-0000-4000-8000-000000000003'      # membre actif de l'établissement
E = 'b1000000-0000-4000-8000-000000000004'      # établissement
P = 'b1000000-0000-4000-8000-000000000005'      # mission
C0 = '246810'
SCANNER = 'public.fn_scanner_code_pointage(text,jsonb)'

sql("""
DO $roles$ BEGIN
  IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $roles$;
CREATE SCHEMA auth; CREATE SCHEMA private; CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA auth, public TO anon, authenticated, service_role;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $uid$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$uid$;
CREATE TABLE auth.users(id uuid PRIMARY KEY, raw_app_meta_data jsonb, deleted_at timestamptz, banned_until timestamptz);
CREATE TABLE public.etablissements(id uuid PRIMARY KEY, supprime_le timestamptz);
CREATE TABLE public.membres_etablissement(user_id uuid, etablissement_id uuid, role text, actif boolean);
CREATE TABLE public.missions(
  id uuid PRIMARY KEY, etablissement_id uuid, soignant_assigne_id uuid, statut text, intitule text,
  code_pointage_actif text, code_pointage_hmac text, prochain_type_scan text, nb_scans smallint, modifie_le timestamptz
);
CREATE TABLE public.contrats_mission(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mission_id uuid, statut text);
CREATE TABLE public.mission_creneaux(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mission_id uuid, debut timestamptz, fin timestamptz,
  est_pause boolean DEFAULT false, ordre integer, type_creneau text
);
CREATE TABLE public.scans_pointage(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mission_id uuid, soignant_id uuid, code_saisi text,
  numero_scan smallint, type_scan text, scanne_le timestamptz, horodatage_arrondi timestamptz,
  creneau_effectif_id uuid, est_en_avance boolean, validation_etab_requise boolean,
  latitude numeric, longitude numeric, precision_gps_m numeric, id_terminal text, ip_address inet
);
CREATE TABLE public.presences(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mission_id uuid, soignant_id uuid,
  pointage_arrivee_le timestamptz, pointage_depart_le timestamptz,
  arrivee_lat numeric, arrivee_lng numeric, arrivee_precision_gps_m numeric, arrivee_id_terminal text,
  methode_pointage_arrivee text, depart_lat numeric, depart_lng numeric, depart_precision_gps_m numeric,
  methode_pointage_depart text, heures_reelles numeric, modifie_le timestamptz
);
CREATE TABLE private.security_definer_inventory(
  signature text PRIMARY KEY, categorie text, definition_md5 text, justification text, recense_le timestamptz
);
-- Simplification assumée : aucun administrateur plateforme dans ce banc.
CREATE FUNCTION public.est_admin_valide() RETURNS boolean LANGUAGE sql STABLE AS $admin$ SELECT false $admin$;
""")
# Définitions du dump (re-baseliné #1097), jamais recopiées à la main.
for nom in ['fn_arrondir_quart_heure', 'est_admin', 'mon_etablissement_id', 'fn_etat_pointage_mission']:
    sql(ddl_dump(nom))
sql("""
REVOKE ALL ON FUNCTION public.fn_etat_pointage_mission(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_etat_pointage_mission(uuid) TO authenticated, service_role;
""")
# Vraie chaîne du scanner, puis preuve que le banc part bien de l'état LIVE.
for nom in ['20260903194000_preserver_heures_reelles_pointage.sql', '20261017165819_garantir_rotation_code_pointage.sql']:
    sql((MIGRATIONS / nom).read_text(encoding='utf-8'))

ETAT_SECURITE = f"""
SELECT jsonb_build_object(
  'md5', md5(p.prosrc), 'owner', pg_get_userbyid(p.proowner), 'secdef', p.prosecdef,
  'volatilite', p.provolatile, 'config', p.proconfig,
  'acl', (SELECT jsonb_agg(jsonb_build_array(x.grantee, x.droit) ORDER BY x.grantee, x.droit) FROM (
            SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee)::text END AS grantee,
                   a.privilege_type AS droit
            FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) x),
  'inventaire', (SELECT jsonb_agg(jsonb_build_array(i.signature, i.categorie, i.definition_md5, i.justification))
                 FROM private.security_definer_inventory i WHERE i.signature LIKE '%fn_scanner_code_pointage%')
)::text FROM pg_proc p WHERE p.oid = '{SCANNER}'::regprocedure;
"""
avant = json.loads(sql(ETAT_SECURITE))
assert avant['md5'] == LIVE_MD5 and avant['owner'] == 'postgres' and avant['secdef'] is True
assert avant['volatilite'] == 'v' and avant['config'] == ['search_path=public']
# ACL LIVE relue : {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}.
assert sorted(map(tuple, avant['acl'])) == [('authenticated', 'EXECUTE'), ('postgres', 'EXECUTE'), ('service_role', 'EXECUTE')]
assert len(avant['inventaire']) == 1 and avant['inventaire'][0][:3] == [
    'fn_scanner_code_pointage(text,jsonb)', 'RPC_UTILISATEUR_AUTH_INTERNE', LIVE_MD5]

sql(f"""
INSERT INTO auth.users VALUES ('{S}', '{{"role":"SOIGNANT"}}', NULL, NULL), ('{O}', '{{"role":"SOIGNANT"}}', NULL, NULL),
  ('{M}', '{{"role":"ETABLISSEMENT"}}', NULL, NULL);
INSERT INTO public.etablissements VALUES ('{E}', NULL);
INSERT INTO public.membres_etablissement VALUES ('{M}', '{E}', 'POINTAGE_ONLY', true);
INSERT INTO public.missions(id, etablissement_id, soignant_assigne_id, statut, intitule, code_pointage_actif,
  prochain_type_scan, nb_scans)
VALUES ('{P}', '{E}', '{S}', 'ASSIGNEE', 'Mission témoin B1', '{C0}', 'OUVERTURE', 0);
INSERT INTO public.contrats_mission(mission_id, statut) VALUES ('{P}', 'SIGNE_COMPLET');
INSERT INTO public.mission_creneaux(mission_id, debut, fin, ordre, type_creneau)
VALUES ('{P}', now() - interval '30 minutes', now() + interval '8 hours', 1, 'PREVISIONNEL');
""")
SECRET_HMAC = "DO $hmac$ BEGIN PERFORM set_config('app.settings.hmac_secret', md5(random()::text), false); END $hmac$;"
CODE_ET_HMAC = f"""RESET ROLE;
SELECT jsonb_build_object('code', m.code_pointage_actif, 'hmac', m.code_pointage_hmac,
  'hmac_ok', m.code_pointage_hmac = encode(extensions.hmac(m.id::text || ':' || m.code_pointage_actif,
                                                            current_setting('app.settings.hmac_secret'), 'sha256'), 'hex'))::text
FROM public.missions m WHERE m.id = '{P}';"""
META = '{"id_terminal":"TERM_IOS_TEMOINB1","latitude":48.8566,"longitude":2.3522,"precision_gps_m":12}'
ETAT_TABLES = """SELECT md5(jsonb_build_object(
  'missions', (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.missions x),
  'scans', (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.scans_pointage x),
  'creneaux', (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.mission_creneaux x),
  'presences', (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.presences x))::text);"""

# Témoin du défaut LIVE, annulé : la réponse au soignant porte le code suivant.
temoin = sql("BEGIN;" + SECRET_HMAC + as_user(S, f"SELECT public.fn_scanner_code_pointage('{C0}', NULL)::text;")
             + CODE_ET_HMAC + "ROLLBACK;").splitlines()
reponse_live, etat_live = json.loads(temoin[0]), json.loads(temoin[1])
assert reponse_live['nouveau_code'] == etat_live['code'] != C0 and reponse_live['nouveau_hmac'] == etat_live['hmac']
assert set(reponse_live) == CLES_REPONSE | {'nouveau_code', 'nouveau_hmac'}, 'TEMOIN_DEFAUT_NON_REPRODUIT'
assert sql("SELECT count(*) FROM public.scans_pointage") == '0'

# La migration B1 entière, jamais une recopie.
sql(MIGRATION)
apres = json.loads(sql(ETAT_SECURITE))
assert apres['md5'] == ATTENDU_MD5
assert {k: v for k, v in apres.items() if k not in {'md5', 'inventaire'}} == {k: v for k, v in avant.items() if k not in {'md5', 'inventaire'}}
assert apres['inventaire'] == [avant['inventaire'][0][:2] + [ATTENDU_MD5] + avant['inventaire'][0][3:]], 'INVENTAIRE_NON_SUCCEDE'


def scanner(user, code, meta='NULL', avant=''):
    # Une seule transaction : `avant` et le scan partagent le même now().
    lignes = sql("BEGIN;" + avant + SECRET_HMAC
                 + as_user(user, f"SELECT public.fn_scanner_code_pointage('{code}', {meta})::text;")
                 + CODE_ET_HMAC + "COMMIT;").splitlines()
    return json.loads(lignes[0]), json.loads(lignes[1])


def lire_etat(user):
    return json.loads(sql(as_user(user, f"SELECT public.fn_etat_pointage_mission('{P}')::text;")))


def reponse_sans_code(reponse, etat):
    assert set(reponse) == CLES_REPONSE, f'CLES_INATTENDUES : {sorted(reponse)}'
    assert re.fullmatch(r'\d{6}', etat['code']) and etat['hmac_ok'] is True
    valeurs = {json.dumps(v) for v in reponse.values()} | {str(v) for v in reponse.values()}
    assert etat['code'] not in valeurs and json.dumps(etat['code']) not in valeurs and etat['hmac'] not in valeurs


# OUVERTURE : réponse réduite, rotation et HMAC stocké conservés.
r1, e1 = scanner(S, C0, f"'{META}'::jsonb")
reponse_sans_code(r1, e1)
C1 = e1['code']
assert C1 != C0
assert (r1['type_scan_effectue'], r1['prochain_type_scan'], r1['numero_scan'], r1['validation_etab_requise']) == (
    'OUVERTURE', 'FERMETURE', 1, False)
assert sql(f"SELECT statut || '|' || prochain_type_scan || '|' || nb_scans FROM public.missions WHERE id='{P}'") == 'EN_COURS|FERMETURE|1'
assert sql("SELECT string_agg(type_scan || '|' || code_saisi || '|' || id_terminal || '|' || precision_gps_m, ',') "
           "FROM public.scans_pointage") == f'OUVERTURE|{C0}|TERM_IOS_TEMOINB1|12'
assert sql(f"SELECT count(*) FROM public.mission_creneaux WHERE type_creneau='EFFECTIF' AND fin IS NULL "
           f"AND id='{r1['creneau_effectif_id']}'") == '1'
assert sql("SELECT count(*) FROM public.presences WHERE arrivee_id_terminal='TERM_IOS_TEMOINB1'") == '1'

# L'établissement relit le code courant ; le soignant ne l'obtient par aucune des deux RPC.
etab = lire_etat(M)
assert etab['est_etab'] is True and etab['code_pointage_actif'] == C1 and etab['prochain_type_scan'] == 'FERMETURE'
soignant = lire_etat(S)
assert soignant['est_etab'] is not True and soignant['code_pointage_actif'] is None and soignant['segment_ouvert'] is True

# Refus inchangés, sans mutation.
empreinte = sql(ETAT_TABLES)
refused(as_user(S, f"SELECT public.fn_scanner_code_pointage('{C0}', NULL);"), 'P0002', 'Code de pointage invalide ou expiré.')
refused(as_user(O, f"SELECT public.fn_scanner_code_pointage('{C1}', NULL);"), '42501', 'assigné(e) à cette mission.')
refused(as_user(S, f"SELECT public.fn_scanner_code_pointage('{C1}', NULL);"), '23514', 'Scan déjà pris en compte.')
refused(as_user(S, f"SELECT public.fn_scanner_code_pointage('{C1}', NULL);", 'anon'), '42501', 'permission denied for function fn_scanner_code_pointage')
assert sql(ETAT_TABLES) == empreinte

# FERMETURE 15 minutes plus tard : même contrat de réponse, nouveau code relu par l'établissement.
RECULER_15_MIN = """
UPDATE public.scans_pointage SET scanne_le = now() - interval '15 minutes';
UPDATE public.mission_creneaux SET debut = now() - interval '15 minutes' WHERE type_creneau = 'EFFECTIF';
UPDATE public.presences SET pointage_arrivee_le = now() - interval '15 minutes';
"""
r2, e2 = scanner(S, C1, avant=RECULER_15_MIN)
reponse_sans_code(r2, e2)
C2 = e2['code']
assert len({C0, C1, C2}) == 3
assert (r2['type_scan_effectue'], r2['prochain_type_scan'], r2['numero_scan']) == ('FERMETURE', 'OUVERTURE', 2)
assert r2['creneau_effectif_id'] == r1['creneau_effectif_id']
assert sql("SELECT count(*) FROM public.presences WHERE pointage_depart_le IS NOT NULL AND heures_reelles = 0.25") == '1'
assert lire_etat(M)['code_pointage_actif'] == C2 and lire_etat(S)['code_pointage_actif'] is None

# ACL et classement préservés ; le rejeu de B1 est refusé avant toute redéfinition.
assert json.loads(sql(ETAT_SECURITE)) == apres
refused(MIGRATION, 'POINTAGE_SANS_CODE_SUIVANT_SOURCE_AVANT_OU_INVENTAIRE_DIVERGENT')
assert json.loads(sql(ETAT_SECURITE)) == apres

print(json.dumps({**statique, 'postgres': 17, 'chaine_reelle': ['20260903194000', '20261017165819', MIGRATION_PATH.name[:14]],
                  'defaut_live_reproduit': True, 'cles_reponse': sorted(CLES_REPONSE), 'rotation_conservee': True,
                  'hmac_stocke_non_renvoye': True, 'code_relu_par_etablissement': True, 'code_jamais_lu_par_soignant': True,
                  'refus_inchanges': ['P0002', '42501', '23514', 'anon 42501'], 'acl_et_inventaire_preserves': True,
                  'rejeu_refuse': True}))
print('SCANNER_SANS_CODE_SUIVANT_PG17_OK')
