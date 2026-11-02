"""Banc PostgreSQL 17 isolé — lot 2 B1 (B9) : ni fn_scanner_code_pointage ni
fn_declarer_fin_retroactive ne renvoient plus le code de pointage suivant
(`nouveau_code`) ni son HMAC (`nouveau_hmac`).

Phase statique (sans base) : la migration B1 est unique, sans BEGIN/COMMIT ni
`$$` nu, sans GRANT/REVOKE/ALTER/DROP ; elle redéfinit exactement ces deux RPC,
chacune avec le corps LIVE (prosrc MD5 relu le 02/11/2026 en lecture seule,
identique à la dernière migration du dépôt et au dump re-baseliné) moins les
deux clés ; ses gardes refusent toute dérive avant la première redéfinition ;
le dump est aligné ; aucun client web, mock e2e, edge function, script, test
SQL/Node ou source Swift ne lit `nouveau_code` ni `nouveau_hmac`.

Phase PostgreSQL 17 (base éphémère vide) : vraie chaîne de migrations des deux
RPC (20260903194000 → 20261017165819 : MD5, ACL et inventaire égaux au LIVE),
témoins du défaut sur les deux RPC, refus atomique si une seule source a dérivé,
puis migration B1 entière : réponses réduites aux clés de corrélation, rotation
et HMAC stocké conservés, code relu par l'établissement seul via
fn_etat_pointage_mission (définition du dump), exceptions inchangées, journal
d'audit de la fin rétroactive inchangé, ACL et inventaire préservés, rejeu
refusé.

Verrou d'autorisation de la fin rétroactive (seconde différence de son corps) :
la condition LIVE `NOT (soignant OR admin_etab OR est_admin())` vaut NULL pour
un compte authentifié sans lien avec la mission (est_admin_etablissement() et
mon_etablissement_id() NULL) et un IF NULL ne lève pas : témoin LIVE annulé
(un autre soignant ferme le segment, reçoit le code suivant, audit classé
ADMIN_PLATEFORME), refus 42501 après B1, contexte système inchangé.

Hors périmètre, gap connu nommé dans l'en-tête de la migration : la colonne
`missions.code_pointage_actif` reste lisible par le soignant assigné en
PostgREST direct (GRANT SELECT de table + RLS pol_mission_select) ; fermeture
proposée en PR B9 séparée « B1-ter » (docs/POINTAGE_CODE_ROTATIF_VISIBILITE.md).

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
SCANNER_LIVE_MD5 = 'a2af098e60488cbef102c80594b74d10'
SCANNER_B1_MD5 = '4568c8a01be5be24587cffa9bdd9c1c3'
FIN_LIVE_MD5 = '845c6a3fd6dd3aa4ef7b2fcd19108d88'
FIN_B1_MD5 = '2e238a0d6cea02bce6802c77835defe2'
# Plancher statique : dernière version du registre distant relue le 02/11/2026
# (list_migrations, lecture seule). Il ne prouve pas l'ordre réel de la file de
# merge : avant le merge, relire list_migrations (CLAUDE.md, règles migrations
# n° 2). Les migrations B9 en attente ci-dessous sont antérieures à B1 : si B1
# passe avant elles, ce sont elles qu'il faudra renommer.
DERNIERE_VERSION_DISTANTE = '20261102150000'
B9_EN_ATTENTE_ANTERIEURES = ['20261102204450', '20261102204820']
RETIRE = "    'nouveau_code', v_new_code,\n    'nouveau_hmac', v_new_hmac,\n"
# Verrou d'autorisation de la fin rétroactive (seconde et dernière différence
# de son corps) : la condition LIVE vaut NULL pour un compte authentifié sans
# lien avec la mission, et un IF NULL ne lève pas.
IF_FIN_LIVE = "  IF NOT (v_caller_is_soignant OR v_caller_is_etab_admin OR est_admin()) THEN\n"
IF_FIN_B1 = (
    "  -- Logique ternaire : pour un compte authentifié sans lien avec la mission\n"
    "  -- (soignant non assigné, compte sans établissement), est_admin_etablissement()\n"
    "  -- et mon_etablissement_id() valent NULL ; NOT (false OR NULL OR false) vaut\n"
    "  -- NULL et ce IF laissait passer l'appel. Le contexte système (auth.uid() NULL :\n"
    "  -- service_role, tests SQL) reste inchangé.\n"
    "  IF auth.uid() IS NOT NULL\n"
    "     AND NOT (COALESCE(v_caller_is_soignant, false)\n"
    "              OR COALESCE(v_caller_is_etab_admin, false)\n"
    "              OR COALESCE(est_admin(), false)) THEN\n")
CLES_SCANNER = {'type_scan_effectue', 'prochain_type_scan', 'creneau_effectif_id', 'horodatage_effectif',
                'horodatage_arrondi', 'numero_scan', 'validation_etab_requise'}
CLES_FIN = {'creneau_effectif_id', 'debut_creneau', 'fin_declaree', 'horodatage_arrondi',
            'validation_etab_requise', 'prochain_type_scan', 'numero_scan'}
EN_TETE_SCANNER = 'CREATE OR REPLACE FUNCTION public.fn_scanner_code_pointage('
EN_TETE_FIN = 'CREATE OR REPLACE FUNCTION public.fn_declarer_fin_retroactive('
FIN_ARGS_LIVE = "p_mission_id uuid, p_heure_fin timestamp with time zone, p_raison text DEFAULT 'Oubli de scan'::text"
SCANNER_ARGS_LIVE = 'p_code text, p_metadata jsonb DEFAULT NULL::jsonb'
# Gardes de contrat (elles vérifient l'absence ou la présence des clés dans le
# dump), pas des lecteurs : seules exceptions du balayage des lecteurs.
GARDES_NON_LECTRICES = {'scripts/ci/scanner-code-sans-code-suivant-pg17.py', 'tests/node/check-rpc-contracts.node.mjs'}


def md5(texte):
    return hashlib.md5(texte.encode()).hexdigest()


def corps(sql, debut, etiquette):
    i = sql.index(debut)
    ouverture = f'AS {etiquette}'
    j = sql.index(ouverture, i) + len(ouverture)
    return sql[j:sql.index(etiquette, j)]


def en_tete(sql, debut):
    i = sql.index(debut)
    return sql[i:sql.index('AS $function$', i)]


# ---------------------------------------------------------------- phase statique
candidates = sorted(p for p in MIGRATIONS.iterdir() if re.fullmatch(r'\d{14}_scanner_code_sans_code_suivant\.sql', p.name))
assert len(candidates) == 1, f'MIGRATION_B1_ABSENTE_OU_DUPLIQUEE : {[p.name for p in candidates]}'
MIGRATION_PATH = candidates[0]
MIGRATION = MIGRATION_PATH.read_text(encoding='utf-8')
VERSION_B1 = MIGRATION_PATH.name[:14]
assert VERSION_B1 > DERNIERE_VERSION_DISTANTE, 'MIGRATION_B1_HORODATAGE_NON_POSTERIEUR'
assert all(VERSION_B1 > v for v in B9_EN_ATTENTE_ANTERIEURES), 'MIGRATION_B1_ORDRE_FILE_B9_A_REVOIR'
assert not re.search(r'(?im)^\s*(BEGIN|COMMIT|ROLLBACK)\s*;', MIGRATION), 'MIGRATION_B1_TRANSACTION_INTERNE'
assert '$$' not in MIGRATION, 'MIGRATION_B1_DOLLAR_QUOTING_NU'
assert not re.search(r'(?im)^\s*(GRANT|REVOKE|ALTER\s+FUNCTION|DROP)\b', MIGRATION), 'MIGRATION_B1_ACL_OU_DDL_HORS_PERIMETRE'
assert MIGRATION.count('CREATE OR REPLACE FUNCTION') == 2, 'MIGRATION_B1_PERIMETRE'
assert MIGRATION.count(EN_TETE_SCANNER) == 1 and MIGRATION.count(EN_TETE_FIN) == 1, 'MIGRATION_B1_PERIMETRE'
# Toutes les gardes « avant » précèdent la première redéfinition : une seule
# source divergente refuse la migration entière, sans redéfinition partielle.
premiere_redefinition = MIGRATION.index('CREATE OR REPLACE FUNCTION')
for garde in ['POINTAGE_SANS_CODE_SUIVANT_SOURCE_AVANT_OU_INVENTAIRE_DIVERGENT',
              'POINTAGE_SANS_CODE_SUIVANT_ACL_AVANT_DIVERGENTE',
              'FIN_RETROACTIVE_SANS_CODE_SUIVANT_SOURCE_AVANT_OU_INVENTAIRE_DIVERGENT',
              'FIN_RETROACTIVE_SANS_CODE_SUIVANT_ACL_AVANT_DIVERGENTE']:
    assert MIGRATION.count(garde) == 1 and MIGRATION.index(garde) < premiere_redefinition, f'GARDE_AVANT_ABSENTE : {garde}'

# Aucune redéfinition intermédiaire non relue : la chaîne du dépôt est exactement
# baseline → sources relues → B1.
definitions = {}
for fichier in sorted(MIGRATIONS.glob('*.sql')):
    texte = fichier.read_text(encoding='utf-8', errors='replace')
    for nom in ['fn_scanner_code_pointage', 'fn_declarer_fin_retroactive']:
        if re.search(rf'(?i)create\s+(or\s+replace\s+)?function\s+("?public"?\.)?"?{nom}"?\s*\(', texte):
            definitions.setdefault(nom, []).append(fichier.name[:14])
assert definitions == {
    'fn_scanner_code_pointage': ['00000000000000', '20260903194000', '20261017165819', VERSION_B1],
    'fn_declarer_fin_retroactive': ['00000000000000', '20260903194000', VERSION_B1],
}, f'CHAINE_DE_DEFINITIONS_INATTENDUE : {definitions}'

ROTATION = (MIGRATIONS / '20261017165819_garantir_rotation_code_pointage.sql').read_text(encoding='utf-8')
HEURES = (MIGRATIONS / '20260903194000_preserver_heures_reelles_pointage.sql').read_text(encoding='utf-8')
DUMP = (ROOT / 'supabase/schema/public.sql').read_text(encoding='utf-8')
for nom, source, en_tete_fn, live, attendu, remplacements in [
        ('fn_scanner_code_pointage', ROTATION, EN_TETE_SCANNER, SCANNER_LIVE_MD5, SCANNER_B1_MD5, [(RETIRE, '')]),
        ('fn_declarer_fin_retroactive', HEURES, EN_TETE_FIN, FIN_LIVE_MD5, FIN_B1_MD5,
         [(RETIRE, ''), (IF_FIN_LIVE, IF_FIN_B1)])]:
    corps_live = corps(source, en_tete_fn, '$function$')
    assert md5(corps_live) == live, f'SOURCE_DU_DEPOT_DIFFERENTE_DU_LIVE : {nom}'
    corps_b1 = corps(MIGRATION, en_tete_fn, '$function$')
    assert en_tete(MIGRATION, en_tete_fn) == en_tete(source, en_tete_fn), f'SIGNATURE_OU_QUALIFICATEURS_MODIFIES : {nom}'
    attendu_corps = corps_live
    for avant_texte, apres_texte in remplacements:
        assert attendu_corps.count(avant_texte) == 1, f'SOURCE_SANS_LE_FRAGMENT_ATTENDU : {nom}'
        attendu_corps = attendu_corps.replace(avant_texte, apres_texte)
    assert corps_b1 == attendu_corps, f'DIFF_AUTRE_QUE_CELLES_DECLAREES : {nom}'
    assert md5(corps_b1) == attendu, f'MD5_B1_INATTENDU : {nom}'
    assert 'nouveau_code' not in corps_b1 and 'nouveau_hmac' not in corps_b1, nom
    assert MIGRATION.count(f"'{live}'") >= 2 and MIGRATION.count(f"'{attendu}'") >= 1, f'GARDES_MD5_ABSENTES : {nom}'
    assert md5(corps(DUMP, f'CREATE OR REPLACE FUNCTION "public"."{nom}"(', '$$')) == attendu, f'DUMP_NON_ALIGNE : {nom}'

# Aucun lecteur du code suivant, client, mock, edge, script, test ou source Swift
# (les tests Swift peuvent nommer les clés pour prouver leur absence).
# mobile-native/ (pilote React Native, legacy) est hors balayage : il écarte déjà
# ces clés en liste blanche (supabaseGateway.ts l.395).
SUFFIXES = {'.ts', '.tsx', '.js', '.mjs', '.cjs', '.json', '.py', '.sql', '.sh', '.swift', '.yml', '.yaml'}
lecteurs = []
for dossier in ['src', 'e2e', 'supabase/functions', 'scripts', 'tests', 'ios-native', '.github']:
    for fichier in (ROOT / dossier).rglob('*'):
        relatif = str(fichier.relative_to(ROOT))
        if (not fichier.is_file() or fichier.suffix not in SUFFIXES or relatif in GARDES_NON_LECTRICES
                or '/.build/' in relatif or '/node_modules/' in relatif
                or (relatif.startswith('ios-native/') and '/Tests/' in relatif)):
            continue
        texte = fichier.read_text(encoding='utf-8', errors='replace')
        if 'nouveau_code' in texte or 'nouveau_hmac' in texte:
            lecteurs.append(relatif)
assert lecteurs == [], f'LECTEURS_DU_CODE_SUIVANT : {lecteurs}'

statique = {'migration': MIGRATION_PATH.name, 'migration_sha256': hashlib.sha256(MIGRATION.encode()).hexdigest(),
            'rpc': {'fn_scanner_code_pointage': {'live_md5': SCANNER_LIVE_MD5, 'b1_md5': SCANNER_B1_MD5},
                    'fn_declarer_fin_retroactive': {'live_md5': FIN_LIVE_MD5, 'b1_md5': FIN_B1_MD5}},
            'cles_retirees': ['nouveau_code', 'nouveau_hmac'],
            'gap_connu_hors_perimetre': 'missions.code_pointage_actif lisible en SELECT de colonne (B1-ter)'}
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
M = 'b1000000-0000-4000-8000-000000000003'      # membre actif de l'établissement (POINTAGE_ONLY)
E = 'b1000000-0000-4000-8000-000000000004'      # établissement
P = 'b1000000-0000-4000-8000-000000000005'      # mission
A = 'b1000000-0000-4000-8000-000000000006'      # propriétaire de l'établissement
INCONNUE = 'b1000000-0000-4000-8000-0000000000ff'
C0 = '246810'
SCANNER = 'public.fn_scanner_code_pointage(text,jsonb)'
FIN = 'public.fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)'
FIN_INVENTAIRE = 'fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)'

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
CREATE TABLE public.soignants(id uuid PRIMARY KEY, supprime_le timestamptz);
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
-- Sous-ensemble des CHECK de production (journaux_audit_action_check et
-- journaux_audit_type_acteur_check) : les valeurs écrites par la fin rétroactive.
CREATE TABLE public.journaux_audit(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), acteur_id uuid, type_acteur text NOT NULL, action text NOT NULL,
  type_ressource text, id_ressource uuid, details jsonb, cree_le timestamptz DEFAULT now(),
  CHECK (action IN ('POINTAGE')), CHECK (type_acteur IN ('SOIGNANT', 'ADMIN_ETABLISSEMENT', 'ADMIN_PLATEFORME'))
);
CREATE TABLE private.security_definer_inventory(
  signature text PRIMARY KEY, categorie text, definition_md5 text, justification text, recense_le timestamptz
);
-- Simplification assumée : aucun administrateur plateforme dans ce banc.
CREATE FUNCTION public.est_admin_valide() RETURNS boolean LANGUAGE sql STABLE AS $admin$ SELECT false $admin$;
""")
# Définitions du dump (re-baseliné #1097), jamais recopiées à la main.
for nom in ['fn_arrondir_quart_heure', 'est_admin', 'mon_etablissement_id', 'fn_compte_auth_actif',
            'fn_role_etablissement_courant', 'est_admin_etablissement', 'fn_etat_pointage_mission']:
    sql(ddl_dump(nom))
sql("""
REVOKE ALL ON FUNCTION public.fn_etat_pointage_mission(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_etat_pointage_mission(uuid) TO authenticated, service_role;
""")
# Vraie chaîne des deux RPC, puis preuve que le banc part bien de l'état LIVE.
for nom in ['20260903194000_preserver_heures_reelles_pointage.sql', '20261017165819_garantir_rotation_code_pointage.sql']:
    sql((MIGRATIONS / nom).read_text(encoding='utf-8'))


def etat_securite(signature, motif):
    return f"""
SELECT jsonb_build_object(
  'md5', md5(p.prosrc), 'owner', pg_get_userbyid(p.proowner), 'secdef', p.prosecdef,
  'volatilite', p.provolatile, 'config', p.proconfig,
  'args', pg_get_function_arguments(p.oid), 'resultat', pg_get_function_result(p.oid),
  'acl', (SELECT jsonb_agg(jsonb_build_array(x.grantee, x.droit) ORDER BY x.grantee, x.droit) FROM (
            SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee)::text END AS grantee,
                   a.privilege_type AS droit
            FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) x),
  'inventaire', (SELECT jsonb_agg(jsonb_build_array(i.signature, i.categorie, i.definition_md5, i.justification))
                 FROM private.security_definer_inventory i WHERE i.signature LIKE '%{motif}%')
)::text FROM pg_proc p WHERE p.oid = '{signature}'::regprocedure;
"""


ETAT_SCANNER = etat_securite(SCANNER, 'fn_scanner_code_pointage')
ETAT_FIN = etat_securite(FIN, 'fn_declarer_fin_retroactive')
ACL_LIVE = [('authenticated', 'EXECUTE'), ('postgres', 'EXECUTE'), ('service_role', 'EXECUTE')]
avant = json.loads(sql(ETAT_SCANNER))
assert avant['md5'] == SCANNER_LIVE_MD5 and avant['owner'] == 'postgres' and avant['secdef'] is True
assert avant['volatilite'] == 'v' and avant['config'] == ['search_path=public']
assert avant['args'] == SCANNER_ARGS_LIVE and avant['resultat'] == 'jsonb'
# ACL LIVE relue : {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}.
assert sorted(map(tuple, avant['acl'])) == ACL_LIVE
assert len(avant['inventaire']) == 1 and avant['inventaire'][0][:3] == [
    'fn_scanner_code_pointage(text,jsonb)', 'RPC_UTILISATEUR_AUTH_INTERNE', SCANNER_LIVE_MD5]
avant_fin = json.loads(sql(ETAT_FIN))
assert avant_fin['md5'] == FIN_LIVE_MD5 and avant_fin['owner'] == 'postgres' and avant_fin['secdef'] is True
assert avant_fin['volatilite'] == 'v' and avant_fin['config'] == ['search_path=public']
assert avant_fin['args'] == FIN_ARGS_LIVE and avant_fin['resultat'] == 'jsonb'
# ACL LIVE relue : {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}.
assert sorted(map(tuple, avant_fin['acl'])) == ACL_LIVE
assert len(avant_fin['inventaire']) == 1 and avant_fin['inventaire'][0][:3] == [
    FIN_INVENTAIRE, 'MIXTE_TENANT_ADMIN', FIN_LIVE_MD5]

sql(f"""
INSERT INTO auth.users VALUES ('{S}', '{{"role":"SOIGNANT"}}', NULL, NULL), ('{O}', '{{"role":"SOIGNANT"}}', NULL, NULL),
  ('{M}', '{{"role":"ETABLISSEMENT"}}', NULL, NULL), ('{A}', '{{"role":"ADMIN_ETABLISSEMENT"}}', NULL, NULL);
INSERT INTO public.soignants VALUES ('{S}', NULL), ('{O}', NULL);
INSERT INTO public.etablissements VALUES ('{E}', NULL);
INSERT INTO public.membres_etablissement VALUES ('{M}', '{E}', 'POINTAGE_ONLY', true), ('{A}', '{E}', 'PROPRIETAIRE', true);
INSERT INTO public.missions(id, etablissement_id, soignant_assigne_id, statut, intitule, code_pointage_actif,
  prochain_type_scan, nb_scans)
VALUES ('{P}', '{E}', '{S}', 'ASSIGNEE', 'Mission témoin B1', '{C0}', 'OUVERTURE', 0);
INSERT INTO public.contrats_mission(mission_id, statut) VALUES ('{P}', 'SIGNE_COMPLET');
INSERT INTO public.mission_creneaux(mission_id, debut, fin, ordre, type_creneau)
VALUES ('{P}', now() - interval '30 minutes', now() + interval '8 hours', 1, 'PREVISIONNEL');
""")
assert sql(as_user(A, "SELECT public.est_admin_etablissement()::text || '|' || public.mon_etablissement_id();")) == f'true|{E}'
assert sql(as_user(M, "SELECT public.est_admin_etablissement()::text || '|' || public.mon_etablissement_id();")) == f'false|{E}'
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
  'presences', (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.presences x),
  'audit', (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.journaux_audit x))::text);"""


def appel_fin(heure_fin, raison='Oubli de scan', mission=P):
    return f"SELECT public.fn_declarer_fin_retroactive('{mission}', {heure_fin}, '{raison}')::text;"


# Témoins du défaut LIVE, annulés : chaque réponse au soignant porte le code suivant.
temoin = sql("BEGIN;" + SECRET_HMAC + as_user(S, f"SELECT public.fn_scanner_code_pointage('{C0}', NULL)::text;")
             + CODE_ET_HMAC + "ROLLBACK;").splitlines()
reponse_live, etat_live = json.loads(temoin[0]), json.loads(temoin[1])
assert reponse_live['nouveau_code'] == etat_live['code'] != C0 and reponse_live['nouveau_hmac'] == etat_live['hmac']
assert set(reponse_live) == CLES_SCANNER | {'nouveau_code', 'nouveau_hmac'}, 'TEMOIN_DEFAUT_NON_REPRODUIT'
# Même transaction : ouverture, puis fin rétroactive déclarée par le soignant
# lui-même, depuis n'importe où (aucun code ni lieu exigé par la RPC).
temoin_fin = sql("BEGIN;" + SECRET_HMAC + as_user(S, f"SELECT public.fn_scanner_code_pointage('{C0}', NULL)::text;")
                 + as_user(S, appel_fin("now() + interval '10 minutes'", 'Témoin'))
                 + CODE_ET_HMAC + "ROLLBACK;").splitlines()
reponse_fin_live, etat_fin_live = json.loads(temoin_fin[1]), json.loads(temoin_fin[2])
assert reponse_fin_live['nouveau_code'] == etat_fin_live['code']
assert reponse_fin_live['nouveau_hmac'] == etat_fin_live['hmac'] and etat_fin_live['hmac_ok'] is True
assert set(reponse_fin_live) == CLES_FIN | {'nouveau_code', 'nouveau_hmac'}, 'TEMOIN_DEFAUT_FIN_NON_REPRODUIT'
# Témoin LIVE du contournement d'autorisation, annulé : un autre soignant, sans
# lien avec la mission, ferme le segment ouvert du soignant assigné à l'heure de
# son choix, reçoit le code suivant, et l'audit le classe ADMIN_PLATEFORME.
temoin_intrus = sql("BEGIN;" + SECRET_HMAC + as_user(S, f"SELECT public.fn_scanner_code_pointage('{C0}', NULL)::text;")
                    + as_user(O, appel_fin("now() + interval '10 hours'", 'Intrus'))
                    + "RESET ROLE; SELECT type_acteur || '|' || acteur_id FROM public.journaux_audit;"
                    + CODE_ET_HMAC + "ROLLBACK;").splitlines()
reponse_intrus = json.loads(temoin_intrus[1])
assert reponse_intrus['nouveau_code'] == json.loads(temoin_intrus[3])['code'], 'TEMOIN_CONTOURNEMENT_NON_REPRODUIT'
assert temoin_intrus[2] == f'ADMIN_PLATEFORME|{O}', 'TEMOIN_CONTOURNEMENT_AUDIT'
assert sql("SELECT count(*) FROM public.scans_pointage") == '0' and sql("SELECT count(*) FROM public.journaux_audit") == '0'

# Une seule source divergente (ici l'inventaire de la fin rétroactive) refuse la
# migration entière avant toute redéfinition : aucune des deux RPC ne change.
refused("BEGIN;" f"UPDATE private.security_definer_inventory SET definition_md5 = md5('derive') "
        f"WHERE signature = '{FIN_INVENTAIRE}';" + MIGRATION,
        'FIN_RETROACTIVE_SANS_CODE_SUIVANT_SOURCE_AVANT_OU_INVENTAIRE_DIVERGENT')
assert json.loads(sql(ETAT_SCANNER)) == avant and json.loads(sql(ETAT_FIN)) == avant_fin

# La migration B1 entière, jamais une recopie.
sql(MIGRATION)
apres = json.loads(sql(ETAT_SCANNER))
assert apres['md5'] == SCANNER_B1_MD5
assert {k: v for k, v in apres.items() if k not in {'md5', 'inventaire'}} == {k: v for k, v in avant.items() if k not in {'md5', 'inventaire'}}
assert apres['inventaire'] == [avant['inventaire'][0][:2] + [SCANNER_B1_MD5] + avant['inventaire'][0][3:]], 'INVENTAIRE_NON_SUCCEDE'
apres_fin = json.loads(sql(ETAT_FIN))
assert apres_fin['md5'] == FIN_B1_MD5
assert {k: v for k, v in apres_fin.items() if k not in {'md5', 'inventaire'}} == {k: v for k, v in avant_fin.items() if k not in {'md5', 'inventaire'}}
assert apres_fin['inventaire'] == [avant_fin['inventaire'][0][:2] + [FIN_B1_MD5] + avant_fin['inventaire'][0][3:]], 'INVENTAIRE_FIN_NON_SUCCEDE'


def transaction(user, appel, avant=''):
    # Une seule transaction : `avant` et l'appel partagent le même now().
    lignes = sql("BEGIN;" + avant + SECRET_HMAC + as_user(user, appel) + CODE_ET_HMAC + "COMMIT;").splitlines()
    return json.loads(lignes[0]), json.loads(lignes[1])


def scanner(user, code, meta='NULL', avant=''):
    return transaction(user, f"SELECT public.fn_scanner_code_pointage('{code}', {meta})::text;", avant)


def lire_etat(user):
    return json.loads(sql(as_user(user, f"SELECT public.fn_etat_pointage_mission('{P}')::text;")))


def reponse_sans_code(reponse, etat, cles):
    assert set(reponse) == cles, f'CLES_INATTENDUES : {sorted(reponse)}'
    assert re.fullmatch(r'\d{6}', etat['code']) and etat['hmac_ok'] is True
    valeurs = {json.dumps(v) for v in reponse.values()} | {str(v) for v in reponse.values()}
    assert etat['code'] not in valeurs and json.dumps(etat['code']) not in valeurs and etat['hmac'] not in valeurs


# OUVERTURE : réponse réduite, rotation et HMAC stocké conservés.
r1, e1 = scanner(S, C0, f"'{META}'::jsonb")
reponse_sans_code(r1, e1, CLES_SCANNER)
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

# L'établissement relit le code courant ; le soignant ne l'obtient par aucune des RPC.
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
reponse_sans_code(r2, e2, CLES_SCANNER)
C2 = e2['code']
assert len({C0, C1, C2}) == 3
assert (r2['type_scan_effectue'], r2['prochain_type_scan'], r2['numero_scan']) == ('FERMETURE', 'OUVERTURE', 2)
assert r2['creneau_effectif_id'] == r1['creneau_effectif_id']
assert sql("SELECT count(*) FROM public.presences WHERE pointage_depart_le IS NOT NULL AND heures_reelles = 0.25") == '1'
assert lire_etat(M)['code_pointage_actif'] == C2 and lire_etat(S)['code_pointage_actif'] is None

# Fin rétroactive : aucun segment ouvert → refus inchangé, sans mutation.
empreinte = sql(ETAT_TABLES)
refused(as_user(S, appel_fin('now()')), 'P0002', 'Aucun créneau effectif ouvert à fermer pour cette mission.')
assert sql(ETAT_TABLES) == empreinte

# Nouvelle OUVERTURE (scan 3) après la pause, puis oubli du scan de fin.
VIEILLIR_SCANS = "UPDATE public.scans_pointage SET scanne_le = scanne_le - interval '1 hour';"
r3, e3 = scanner(S, C2, avant=VIEILLIR_SCANS)
reponse_sans_code(r3, e3, CLES_SCANNER)
C3 = e3['code']
assert (r3['type_scan_effectue'], r3['numero_scan']) == ('OUVERTURE', 3) and len({C0, C1, C2, C3}) == 4

# Refus de la fin rétroactive inchangés, sans mutation.
empreinte = sql(ETAT_TABLES)
refused(as_user(O, appel_fin("now() + interval '10 hours'", 'Intrus')), '42501',
        'autorisé(e) à déclarer une fin rétroactive sur cette mission.')
refused(as_user(M, appel_fin('now()')), '42501', 'autorisé(e) à déclarer une fin rétroactive sur cette mission.')
refused(as_user(S, appel_fin("now() - interval '1 day'")), '23514', 'doit être postérieure au début du créneau')
refused(as_user(S, appel_fin('now()', mission=INCONNUE)), 'P0002', 'introuvable ou dans un statut incompatible.')
refused(as_user(S, appel_fin('now()'), 'anon'), '42501', 'permission denied for function fn_declarer_fin_retroactive')
assert sql(ETAT_TABLES) == empreinte

# Fin rétroactive déclarée par le soignant : réponse réduite, rotation, HMAC
# stocké, audit et présence conservés ; le code reste lisible par l'établissement seul.
RECULER_SEGMENT_OUVERT = ("UPDATE public.mission_creneaux SET debut = now() - interval '30 minutes' "
                          "WHERE type_creneau = 'EFFECTIF' AND fin IS NULL;")
r4, e4 = transaction(S, appel_fin("now() - interval '5 minutes'"), avant=RECULER_SEGMENT_OUVERT)
reponse_sans_code(r4, e4, CLES_FIN)
C4 = e4['code']
# La fin rétroactive LIVE ne tire qu'un code absent des autres missions actives
# (aucune exclusion de l'historique) : seule la rotation est exigée ici.
assert C4 != C3
assert (r4['prochain_type_scan'], r4['numero_scan'], r4['validation_etab_requise']) == ('OUVERTURE', 4, True)
assert r4['creneau_effectif_id'] == r3['creneau_effectif_id']
assert sql(f"SELECT prochain_type_scan || '|' || nb_scans FROM public.missions WHERE id='{P}'") == 'OUVERTURE|4'
assert sql("SELECT type_scan || '|' || code_saisi || '|' || validation_etab_requise FROM public.scans_pointage "
           "WHERE numero_scan = 4") == 'FERMETURE|RETROACTIF|true'
assert sql(f"SELECT count(*) FROM public.mission_creneaux WHERE id='{r3['creneau_effectif_id']}' "
           "AND fin = debut + interval '25 minutes'") == '1'
assert sql("SELECT count(*) FROM public.presences WHERE heures_reelles = 0.67 AND pointage_depart_le IS NOT NULL") == '1'
assert sql("SELECT string_agg(type_acteur || '|' || action || '|' || (details->>'sous_action') || '|' || (details->>'raison'), ',') "
           "FROM public.journaux_audit") == 'SOIGNANT|POINTAGE|FIN_RETROACTIVE|Oubli de scan'
assert sql("SELECT count(*) FROM public.journaux_audit WHERE details::text LIKE '%nouveau%'") == '0'
assert lire_etat(M)['code_pointage_actif'] == C4 and lire_etat(S)['code_pointage_actif'] is None

# Fin rétroactive déclarée par le propriétaire de l'établissement (bouton de
# AffichageCodeRotatifEtab, qui ne lit que `error` puis relit l'état) : même réponse
# réduite ; l'établissement relit le nouveau code par fn_etat_pointage_mission.
r5, e5 = scanner(S, C4, avant=VIEILLIR_SCANS)
reponse_sans_code(r5, e5, CLES_SCANNER)
C5 = e5['code']
assert (r5['type_scan_effectue'], r5['numero_scan']) == ('OUVERTURE', 5)
r6, e6 = transaction(A, appel_fin("now() - interval '5 minutes'", 'Oubli signalé par l établissement'),
                     avant=RECULER_SEGMENT_OUVERT)
reponse_sans_code(r6, e6, CLES_FIN)
C6 = e6['code']
assert C6 != C5 and (r6['numero_scan'], r6['prochain_type_scan']) == (6, 'OUVERTURE')
assert sql("SELECT count(*) FROM public.journaux_audit WHERE type_acteur = 'ADMIN_ETABLISSEMENT' "
           f"AND acteur_id = '{A}'") == '1'
assert lire_etat(A)['code_pointage_actif'] == C6 and lire_etat(S)['code_pointage_actif'] is None

# Contexte système (auth.uid() NULL, aucun rôle authenticated) : comportement
# inchangé par le verrou, l'appel passe et l'audit garde le classement LIVE.
r7, e7 = scanner(S, C6, avant=VIEILLIR_SCANS)
assert (r7['type_scan_effectue'], r7['numero_scan']) == ('OUVERTURE', 7)
lignes = sql("BEGIN;" + RECULER_SEGMENT_OUVERT + SECRET_HMAC + appel_fin("now() - interval '5 minutes'", 'Système')
             + CODE_ET_HMAC + "COMMIT;").splitlines()
r8, e8 = json.loads(lignes[0]), json.loads(lignes[1])
reponse_sans_code(r8, e8, CLES_FIN)
assert r8['numero_scan'] == 8
assert sql("SELECT count(*) FROM public.journaux_audit WHERE acteur_id IS NULL AND type_acteur = 'ADMIN_PLATEFORME' "
           "AND details->>'raison' = 'Système'") == '1'

# ACL et classement préservés ; le rejeu de B1 est refusé avant toute redéfinition.
assert json.loads(sql(ETAT_SCANNER)) == apres and json.loads(sql(ETAT_FIN)) == apres_fin
refused(MIGRATION, 'POINTAGE_SANS_CODE_SUIVANT_SOURCE_AVANT_OU_INVENTAIRE_DIVERGENT')
assert json.loads(sql(ETAT_SCANNER)) == apres and json.loads(sql(ETAT_FIN)) == apres_fin

print(json.dumps({**statique, 'postgres': 17,
                  'chaine_reelle': ['20260903194000', '20261017165819', VERSION_B1],
                  'defaut_live_reproduit': ['fn_scanner_code_pointage', 'fn_declarer_fin_retroactive'],
                  'refus_atomique_si_une_source_derive': True,
                  'contournement_autorisation_fin_retroactive': {'live': 'reproduit (témoin annulé)', 'b1': 'refusé 42501',
                                                                  'contexte_systeme': 'inchangé'},
                  'cles_reponse': {'fn_scanner_code_pointage': sorted(CLES_SCANNER),
                                   'fn_declarer_fin_retroactive': sorted(CLES_FIN)},
                  'rotation_conservee': True, 'hmac_stocke_non_renvoye': True,
                  'code_relu_par_etablissement': True, 'code_jamais_lu_par_soignant_via_rpc': True,
                  'audit_fin_retroactive_inchange': ['SOIGNANT', 'ADMIN_ETABLISSEMENT'],
                  'refus_inchanges': {'fn_scanner_code_pointage': ['P0002', '42501', '23514', 'anon 42501'],
                                      'fn_declarer_fin_retroactive': ['P0002 sans segment', '42501 autre soignant',
                                                                      '42501 membre POINTAGE_ONLY', '23514',
                                                                      'P0002 mission inconnue', 'anon 42501']},
                  'acl_et_inventaire_preserves': True, 'rejeu_refuse': True}))
print('SCANNER_SANS_CODE_SUIVANT_PG17_OK')
