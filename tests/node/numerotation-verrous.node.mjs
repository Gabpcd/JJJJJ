import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';

const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const md5 = s => createHash('md5').update(s).digest('hex');
const migration = read('supabase/migrations/20261001160404_ordonner_verrous_commissions_honoraires.sql');
const history = read('tests/fixtures/numerotation-commissions-historique.sql');
const snapshot = read('supabase/schema/public.sql');
const bodies = s => new Map([...s.matchAll(/CREATE OR REPLACE FUNCTION "public"\."(fn_preparer_\w+)"\("(\w+)" "uuid"\)[\s\S]*?AS \$\$([\s\S]*?)\$\$;/g)].map(m => [m[1], { argument: m[2], body: m[3] }]));
const originals = bodies(history), candidates = bodies(migration), snapshots = bodies(snapshot);
const expected = [
  ['fn_preparer_facture_commission_periode', '8030a296741d5bfe6dad70edd4d8f20d', 'fe01d207db4766c4246f641ba171a3e7'],
  ['fn_preparer_commission_complement_honoraires', '4f8b01ff648de99644464ba700e11d00', 'b4e7b07193aa270a24a66a10709a87d8'],
  ['fn_preparer_commission_remplacement_honoraires', 'c8b2603eda031d12d75a294ffb87d522', 'c793ac81eaef0fe18fb5920c9264c675'],
  ['fn_preparer_avoir_commission_honoraires', '9af2c8bd25c4db563c2d935ba99effd8', 'a65bb72885271a63de5b2dbcdbb7a6be'],
];
const canonical = (name, { argument, body }) => `CREATE OR REPLACE FUNCTION public.${name}(${argument} uuid)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public', 'pg_temp'\nAS $function$${body}$function$\n`;

for (const [name, oldBody, oldDefinition] of expected) test(`${name} : seul l’ordre mission → pièce change`, () => {
  const previous = originals.get(name), next = candidates.get(name);
  assert.equal(md5(previous.body), oldBody);
  assert.equal(md5(canonical(name, previous)), oldDefinition);
  const prefix = `  -- Même ordre que réservation, acquisition et résolution : mission avant pièce.\n  -- La seconde lecture refuse une réaffectation concurrente, sans réécrire la pièce.\n  SELECT mission_id INTO v_mission_verrou FROM public.factures_honoraires WHERE id=${next.argument};\n  PERFORM 1 FROM public.missions WHERE id=v_mission_verrou FOR UPDATE;\n\n`;
  assert.equal(next.body.split(prefix).length, 2);
  const restored = next.body.replace('  v_mission_verrou uuid;\n', '').replace(prefix, '').replace('    AND mission_id IS NOT DISTINCT FROM v_mission_verrou\n', '');
  assert.equal(restored, previous.body, 'calculs, conditions, écritures et retours historiques byte-identiques');
  assert.equal(next.body, snapshots.get(name).body);
  assert(migration.includes(`'${md5(next.body)}','${md5(canonical(name, next))}'`));
  const firstLock = next.body.indexOf('FOR UPDATE');
  assert(next.body.slice(0, firstLock).endsWith('public.missions WHERE id=v_mission_verrou '));
});

test('le rejeu inventaire annule quatre anciens corps avant la matrice métier', () => {
  const sql = read('tests/security/facturation-commissions-pieces-matrice-f1.test.sql');
  const historical = read('supabase/migrations/20261001102511_aligner_commissions_pieces_et_estimation.sql');
  for (const name of ['preflight', 'inventory']) {
    assert.equal(sql.split(`AS $replay_${name}$`)[1].split(`$replay_${name}$;`)[0], historical.split(`DO $${name}$`)[1].split(`$${name}$;`)[0]);
  }
  const wrapper = sql.split('DO $inventory_successor$')[1].split('$inventory_successor$;')[0];
  for (const [name] of expected) {
    assert(wrapper.includes(md5(candidates.get(name).body)));
    assert(wrapper.includes(md5(canonical(name, candidates.get(name)))));
    assert(wrapper.includes(md5(originals.get(name).body)));
    assert(wrapper.includes(md5(canonical(name, originals.get(name)))));
  }
  assert(wrapper.includes('md5(v_previous) IS DISTINCT FROM r.ancien_corps'));
  assert(wrapper.includes('md5(pg_get_functiondef(v_proc.oid)) IS DISTINCT FROM r.ancienne_definition'));
  assert(wrapper.includes('r record; v_proc record;'));
  assert(!wrapper.includes('r record; p record;'));
  assert(wrapper.indexOf('PERFORM pg_temp.f1_inventory_test()') < wrapper.indexOf("USING ERRCODE='JF174'"));
  assert(wrapper.includes('v_after IS DISTINCT FROM v_before'));
  assert(sql.indexOf('$inventory_successor$;') < sql.indexOf('DO $f1$'));
});

test('finaliseur : seul le verrou mission avant pièce/bail change', () => {
  const current = read('supabase/migrations/20261001144604_reserver_numeros_honoraires_atomiquement.sql').match(/CREATE OR REPLACE FUNCTION public.fn_terminer_generation_honoraires\([\s\S]*?\$terminer\$;/)[0];
  const previous = read('tests/fixtures/numerotation-finaliseur-historique.sql').match(/CREATE OR REPLACE FUNCTION public.fn_terminer_generation_honoraires\([\s\S]*?\$terminer\$;/)[0];
  const prefix = `  -- Le trigger de période d'un complément lit aussi l'origine : sérialiser\n  -- avec les résolveurs avant de prendre la pièce, le bail et cet advisory.\n  SELECT mission_id INTO v_m FROM public.factures_honoraires WHERE id=p_facture_id;\n  PERFORM 1 FROM public.missions WHERE id=v_m FOR UPDATE;\n  SELECT * INTO v_f FROM public.factures_honoraires\n    WHERE id=p_facture_id AND mission_id IS NOT DISTINCT FROM v_m FOR UPDATE;`;
  assert.equal(current.replace('v_m uuid; v_resultat jsonb;', 'v_resultat jsonb;').replace(prefix, '  SELECT * INTO v_f FROM public.factures_honoraires WHERE id=p_facture_id FOR UPDATE;'), previous);
  assert(snapshot.includes(current));
});

test('pré-catalogue F1 : une seule empreinte selon les deux bases Git, référence invalide refusée', () => {
  const workflow = read('.github/workflows/validate-pr.yml');
  const step = workflow.split('- name: F1 — catalogue et absence de résidus avant transaction')[1].split('- name:')[0];
  assert(step.includes('BASE_SHA: ${{ github.event.pull_request.base.sha }}'));
  assert(step.includes('--arg helper "$expected_f1_helper"'));
  assert(step.includes('.helper_remplacement_md5 == $helper'));
  const selection = step.match(/          git rev-parse --verify[\s\S]*?          fi\n/)[0].replace(/^          /gm, '');
  const directory = mkdtempSync(join(tmpdir(), 'jolene-numerotation-base-'));
  const git = (...args) => execFileSync('git', args, { cwd: directory, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  try {
    git('init', '-q');
    git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-q', '--allow-empty', '-m', 'base avant ordre');
    const before = git('rev-parse', 'HEAD');
    const migrationPath = join(directory, 'supabase/migrations/20261001160404_ordonner_verrous_commissions_honoraires.sql');
    mkdirSync(dirname(migrationPath), { recursive: true }); writeFileSync(migrationPath, '-- Fixture de présence de chemin, aucun SQL exécuté.\n');
    git('add', '.'); git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-q', '-m', 'base après ordre');
    const after = git('rev-parse', 'HEAD');
    const execute = base => execFileSync('bash', ['-euo', 'pipefail', '-c', selection + 'printf "%s\\n" "$expected_f1_helper"'], { cwd: directory, env: { ...process.env, BASE_SHA: base }, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
    // HEAD contient le successeur dans les deux appels ; seule BASE_SHA compte.
    assert.equal(execute(before), 'c793ac81eaef0fe18fb5920c9264c675');
    assert.equal(execute(after), 'c736c66d76001b64ba425484f77c6ea2');
    assert.throws(() => execute('0'.repeat(40)));
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
