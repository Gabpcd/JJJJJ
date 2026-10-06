"""Reproduction bornée bf1 : PG17 CI éphémère, aucun fournisseur ni schéma distant.

Une régression reproduite écrit son reçu puis sort en échec (exit 1).
Préparation sans DB : python3 ...py --prepare-only --output /tmp/recette107-finances
Exécution CI : JOLENE_FINANCES_WITNESS=CI_EPHEMERE PGHOST=127.0.0.1 PGPORT=54329
 PGDATABASE=recette107_finances PGUSER=postgres PGPASSWORD=<secret CI> python3 ...py
Le port doit être celui du service PG17 jetable ; aucune URL DSN n'est acceptée.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PRODUCT = Path(os.environ.get('RECETTE_PRODUCT_DIR', str(ROOT))).resolve()
PIN = 'bf1c0ebf771533bb1666ae5f2bfd09560e4b0c84'
NAMES = ['fn_calculer_montant_periode', 'fn_anti_seed_facture_honoraire',
         'fn_verrouiller_periode_facture_honoraires', 'fn_no_overlap_creneaux',
         'fn_preparer_facture_commission_periode', 'fn_lister_missions_a_facturer']


def git(*args):
    return subprocess.check_output(['git', *args], cwd=PRODUCT, text=True)


def prepare(output):
    candidate = git('rev-parse', 'HEAD').strip()
    if os.environ.get('CI') == 'true' and (candidate != os.environ.get('GITHUB_SHA') or git('diff', 'HEAD', '--', 'supabase').strip()):
        raise RuntimeError('FINANCES_PRODUCT_SHA_OR_DIRTY_REFUSED')
    files = sorted(git('ls-tree', '-r', '--name-only', PIN, 'supabase/migrations').splitlines())
    latest = {}
    for path in files:
        if not path.endswith('.sql'):
            continue
        source = git('show', f'{PIN}:{path}')
        for name in NAMES:
            pattern = r'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+"?public"?\."?' + name + r'"?\s*\('
            for match in re.finditer(pattern, source, re.I):
                tail = source[match.start():]
                opening = re.search(r'\bAS\s+(\$[A-Za-z0-9_]*\$)', tail, re.I)
                if not opening:
                    raise RuntimeError('FUNCTION_BODY_MISSING')
                delimiter = opening.group(1)
                close = tail.index(delimiter, opening.end())
                end = tail.index(';', close + len(delimiter)) + 1
                body = tail[opening.end():close]
                latest[name] = {'sql': tail[:end], 'body': body, 'file': path,
                                'line': source[:match.start()].count('\n') + 1}
    if set(latest) != set(NAMES):
        raise RuntimeError('SOURCE_FUNCTION_MISSING')
    fixture = (ROOT / 'scripts/ci/recette107-finances-frontiere.sql').read_text()
    marker = '-- SOURCE_FUNCTIONS_EXACTES'
    if fixture.count(marker) != 1:
        raise RuntimeError('FIXTURE_MARKER')
    migration = (PRODUCT / 'supabase/migrations/20261006144619_repartir_creneaux_facturation_par_periode.sql').read_text()
    sql = fixture.replace(marker, '\n'.join(latest[name]['sql'] for name in NAMES) + '\n' + migration)
    baseline_calculator = latest['fn_calculer_montant_periode']['sql']
    for name in ['fn_calculer_montant_periode', 'fn_lister_missions_a_facturer']:
        definition = re.search(r'CREATE OR REPLACE FUNCTION public\.' + name + r'\(.*?AS \$function\$(.*?)\$function\$;', migration, re.S)
        latest[name] = {'body':definition.group(1), 'sql':definition.group(0), 'file':'supabase/migrations/20261006144619_repartir_creneaux_facturation_par_periode.sql','line':migration[:definition.start()].count('\n')+1}
    sql = sql.replace('-- BASELINE_CALCULATOR_FOR_HISTORY', 'EXECUTE $historical$' + baseline_calculator + '$historical$;')
    sql = sql.replace('-- CANDIDATE_CALCULATOR_AFTER_HISTORY', 'EXECUTE $candidate$' + latest['fn_calculer_montant_periode']['sql'] + '$candidate$;')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'assembled.sql').write_text(sql)
    manifest = {'sourceSha': candidate, 'baselineSha': PIN, 'version': '1.0.7', 'build': 24,
                'scope': 'real calculation, anti-seed, period guard and commission functions; reduced tables/auth doubles; no PDF/Edge/full RLS/Stripe',
                'functions': {name: {'file': d['file'], 'line': d['line'],
                   'bodyMd5': hashlib.md5(d['body'].encode()).hexdigest(),
                   'bodySha256': hashlib.sha256(d['body'].encode()).hexdigest()}
                   for name, d in latest.items()},
                'assembledSqlSha256': hashlib.sha256(sql.encode()).hexdigest()}
    (output / 'source-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return sql, manifest


def guard():
    expected = {'CI': 'true', 'JOLENE_FINANCES_WITNESS': 'CI_EPHEMERE', 'PGHOST': '127.0.0.1',
                'PGPORT': '54329', 'PGDATABASE': 'recette107_finances', 'PGUSER': 'postgres'}
    if any(os.environ.get(k) != v for k, v in expected.items()) or any(os.environ.get(k) for k in
            ['PGSERVICE', 'PGSERVICEFILE', 'PGHOSTADDR', 'PGOPTIONS']):
        raise RuntimeError('FINANCES_WITNESS_DESTINATION_REFUSED')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--output', type=Path, default=Path(os.environ.get(
        'RECETTE_PROOFS_DIR', str(ROOT / 'test-results/recette107-finances'))))
    args = parser.parse_args()
    sql, manifest = prepare(args.output)
    if args.prepare_only:
        print(json.dumps({'prepared': True, 'executed': False, 'sourceSha': manifest['sourceSha'], 'functionCount': len(NAMES)}))
        return 0
    guard()
    env = {k: os.environ[k] for k in ['PATH', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD'] if k in os.environ}

    def run(text):
        result = subprocess.run(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'], input=text,
                                env=env, capture_output=True, text=True, timeout=60)
        if result.returncode:
            # Script et tables synthétiques uniquement ; pas de DSN ni JWT.
            (args.output / 'sql-error.txt').write_text(result.stderr)
            raise RuntimeError('FINANCES_PG17_SQL_FAILED')
        return result.stdout.strip()

    empty = "SELECT (SELECT count(*) FROM pg_class WHERE relnamespace='public'::regnamespace)=0 AND (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace)=0 AND (SELECT count(*) FROM pg_namespace WHERE nspname IN('auth','extensions','private'))=0"
    if run("SELECT current_setting('server_version_num')::int/10000") != '17' or run(empty) != 't':
        raise RuntimeError('FINANCES_PG17_EMPTY_DATABASE_REQUIRED')
    report = json.loads(run(sql).splitlines()[-1])
    if run(empty) != 't':
        raise RuntimeError('FINANCES_ROLLBACK_FAILED')
    if report.get('qualification') != 'FIX_VERIFIED' or report.get('invoicedHt') != 480:
        raise RuntimeError('FINANCES_CORRECTION_NOT_VERIFIED')
    if report.get('routineBodyMd5') != {n: f['bodyMd5'] for n, f in manifest['functions'].items()}:
        raise RuntimeError('FINANCES_INSTALLED_FUNCTION_MISMATCH')
    report.update(sourceSha=manifest['sourceSha'], baselineSha=PIN, postgresMajor=17, rollbackVerified=True, functions=manifest['functions'])
    (args.output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({'completed': False, 'error': str(error) if isinstance(error, RuntimeError) else 'FINANCES_WITNESS_FAILED'}))
        raise SystemExit(1)
