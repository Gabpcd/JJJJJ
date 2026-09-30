import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const path = 'supabase/migrations/20260930091209_garder_resolveur_litige_avant_lecture.sql';
const migration = read(path);
const md5 = value => createHash('md5').update(value).digest('hex');
const body = migration.split('AS $function$')[1].split('$function$')[0];
const guard = "  IF auth.uid() IS NULL OR public.est_admin() IS NOT TRUE THEN\n    RETURN jsonb_build_object('success', false, 'error', 'Administrateur requis.');\n  END IF;\n\n";

test('un seul delta depuis le corps LIVE : identité/admin avant lecture et routage', () => {
  assert.equal(md5(body), '5a13493bf67426d968d0d75aad16b86c');
  assert.ok(body.includes(`\nBEGIN\n${guard}`));
  assert.equal(md5(body.replace(guard, '')), '1d1a6d0593e1899ff2c58c48a38f3a4d');
  assert.ok(body.indexOf(guard) < body.indexOf('IF v_action'));
  assert.ok(body.indexOf(guard) < body.indexOf('FROM public.litiges'));
  assert.equal([...migration.matchAll(/CREATE OR REPLACE FUNCTION/g)].length, 1);
  assert.doesNotMatch(migration, /\b(?:GRANT|REVOKE|ALTER FUNCTION)\b/);
});

test('empreinte LIVE reconstruite depuis les deux migrations main, aucun contournement financier', () => {
  const source = read('supabase/migrations/20260808150856_aligner_mandat_facturation_tva_et_periodes.sql');
  const fn = source.slice(source.indexOf('CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_litige_intelligent('));
  const original = fn.split('AS $body$')[1].split('$body$')[0];
  const routing = read('supabase/migrations/20260903203000_resoudre_litiges_paie_salariee.sql');
  const marker = routing.split('$marker$')[1];
  const injection = routing.split('$injection$')[1];
  const live = original.replace(marker, injection);
  assert.equal(md5(live), '1d1a6d0593e1899ff2c58c48a38f3a4d');
  assert.equal(body.replace(guard, ''), live);
});

test('SQL matrice réelle de refus, chemins admin interrompus avant toute résolution', () => {
  const sql = read('tests/security/litige-resolveur-garde-initiale.test.sql');
  assert.match(sql, /SET LOCAL ROLE authenticated/);
  assert.match(sql, /FOR acteur IN 0\.\.4 LOOP/);
  assert.match(sql, /FOR n IN 1\.\.7 LOOP/);
  assert.match(sql, /'SALARIE' ELSE 'LIBERAL'/);
  assert.match(sql, /'OUVERT'.*'REVUE_ADMIN'.*'RESOLU_ADMIN'/);
  assert.match(sql, /'AUCUNE','AUTO','COMPLEMENT','INVALIDE'/);
  assert.match(sql, /'court','NEUTRE',NULL,NULL,'AUCUNE'/);
  assert.match(sql, /ROLLBACK;\s*$/);
  assert.ok(read('.github/workflows/validate-pr.yml').includes('tests/security/litige-resolveur-garde-initiale.test.sql'));
});
