import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { validGraphqlSchemaDetails, graphqlSchemaDelta, projectGraphqlSchemaDelta, GRAPHQL_SCHEMA_GRANT_BOUND } from '../graphql-schema-diagnostic.mjs';
import { PG_RESTORE_ROLES, projectGraphqlDiagnostic, closedFailure } from '../contract.mjs';
import { assertGraphqlRestored, assertGraphqlWitness, partitionGraphqlRestore } from '../graphql-restore-plan.mjs';
import { witness, input } from './graphql-test-fixture.mjs';
const tuple = () => ['ROLE', 'postgres', 'supabase_admin', 'USAGE', true];
const details = (grants = [tuple()], owner = 'supabase_admin', isNull = false) => ({ owner, isNull, grants });
const delta = (a, b) => graphqlSchemaDelta(a, b, PG_RESTORE_ROLES);
const project = v => projectGraphqlSchemaDelta(v, PG_RESTORE_ROLES);
const canary = 'PRIVATE_USER_ROLE_NO_EXPORT';
const refused = (a, b) => {
 const source = witness(), target = witness(); source.wrapperSchemaDetails = a; target.wrapperSchemaDetails = b;
 target.fingerprint = 'b'.repeat(64); target.components.schema_graphql_public = 'b'.repeat(64);
 try { assertGraphqlRestored(source, target); } catch (e) { assert.equal(e.graphql.reason, 'PARITY_FINGERPRINT'); return closedFailure(e, 'restore'); }
 assert.fail('parity must refuse');
};
test('one refusal reports a complete bounded owner, NULL and ACL delta', () => {
 const a = details([tuple(), tuple(), ['PUBLIC', null, 'postgres', 'CREATE', false]], 'postgres');
 const b = details([['ROLE', 'anon', 'supabase_admin', 'USAGE', false]]);
 const p = refused(a, b); assert.equal(p.restored, false); assert.equal(p.appVerified, false);
 const d = p.graphql.wrapperSchemaDelta;
 assert.deepEqual(d.owner, { equal: false, source: 'postgres', target: 'supabase_admin' });
 assert.deepEqual(d.aclNull, { equal: true, source: false, target: false });
 assert.deepEqual(d.tuples, { equal: false, sourceCount: 3, targetCount: 1, matchedCount: 0, sourceOnlyCount: 3, targetOnlyCount: 1,
  delta: [
   { side: 'SOURCE_ONLY', granteeType: 'PUBLIC', grantee: 'PUBLIC', grantor: 'postgres', privilege: 'CREATE', grantOption: false, count: 1 },
   { side: 'SOURCE_ONLY', granteeType: 'ROLE', grantee: 'postgres', grantor: 'supabase_admin', privilege: 'USAGE', grantOption: true, count: 2 },
   { side: 'TARGET_ONLY', granteeType: 'ROLE', grantee: 'anon', grantor: 'supabase_admin', privilege: 'USAGE', grantOption: false, count: 1 },
  ] });
 assert.deepEqual(projectGraphqlDiagnostic(p.graphql), p.graphql);
 const n = delta(details([], 'supabase_admin', true), details([]));
 assert.deepEqual(n.aclNull, { equal: false, source: true, target: false }); assert.equal(n.tuples.equal, true);
});
test('permutation preserves private tuples and multiplicities; additional duplicates remain visible', () => {
 const rows = [tuple(), ['ROLE', 'anon', 'postgres', 'CREATE', false], tuple()];
 const a = details(rows), b = details([...rows].reverse()); const d = delta(a, b);
 assert.equal(d.tuples.equal, true); assert.deepEqual(d.tuples.delta, []); assert.equal(d.tuples.matchedCount, 3);
 b.grants.push(tuple()); const extra = delta(a, b);
 assert.equal(extra.tuples.targetOnlyCount, 1); assert.equal(extra.tuples.delta[0].count, 1);
 assert.equal(extra.tuples.delta[0].side, 'TARGET_ONLY'); assert.deepEqual(project(extra), extra);
});
test('each grantee, grantor, privilege and grant option change has both exact delta sides', () => {
 for (const [index, value, field] of [[1, 'anon', 'grantee'], [2, 'postgres', 'grantor'], [3, 'CREATE', 'privilege'], [4, false, 'grantOption']]) {
  const changed = tuple(); changed[index] = value; const d = delta(details(), details([changed]));
  assert.equal(d.tuples.equal, false); assert.equal(d.tuples.matchedCount, 0); assert.equal(d.tuples.delta.length, 2);
  assert.equal(d.tuples.delta.find(row => row.side === 'TARGET_ONLY')[field], value);
  assert.equal(refused(details(), details([changed])).restored, false);
 }
});
test('every pinned standard role is preserved, PUBLIC remains distinct from a role literally named PUBLIC', () => {
 for (const r of PG_RESTORE_ROLES) {
  const d = delta(details([]), details([['ROLE', r, r, 'CREATE', false]], r));
  assert.equal(d.owner.target, r); assert.equal(d.tuples.delta[0].granteeType, 'ROLE');
  assert.equal(d.tuples.delta[0].grantee, r); assert.equal(d.tuples.delta[0].grantor, r);
 }
 const d = delta(details([['PUBLIC', null, 'supabase_admin', 'USAGE', false]]), details([['ROLE', 'PUBLIC', 'supabase_admin', 'USAGE', false]]));
 assert.deepEqual(d.tuples.delta.map(row => row.granteeType), ['PUBLIC', 'UNKNOWN']); assert.equal(d.tuples.equal, false);
});
test('unknown identities are compared privately before masking without opposite-side cancellation', () => {
 const a = details([['ROLE', canary + '_A', canary + '_G', 'USAGE', false]], canary + '_O');
 const b = details([['ROLE', canary + '_B', canary + '_H', 'USAGE', false]], canary + '_P');
 const d = delta(a, b), publicFailure = refused(a, b);
 assert.equal(d.owner.equal, false); assert.equal(d.owner.source, 'UNKNOWN'); assert.equal(d.owner.target, 'UNKNOWN');
 assert.equal(d.tuples.equal, false); assert.equal(d.tuples.delta.length, 2);
 for (const row of d.tuples.delta) { assert.equal(row.granteeType, 'UNKNOWN'); assert.equal(row.grantee, 'UNKNOWN'); assert.equal(row.grantor, 'UNKNOWN'); }
 assert.ok(!JSON.stringify(publicFailure).includes(canary)); assert.ok(!JSON.stringify(d).includes(canary)); assert.deepEqual(project(d), d);
 assert.equal(delta(a, structuredClone(a)).tuples.equal, true);
 const allUnknown = delta(details([]), details([...a.grants, ...b.grants]));
 assert.equal(allUnknown.tuples.delta.length, 1); assert.equal(allUnknown.tuples.delta[0].count, 2);
});
test('private details reject malformed shape, NULL with tuples, excess rows and invalid native schema privileges', () => {
 const bad = [null, {}, { ...details(), extra: canary }, { ...details(), owner: '' }, { ...details(), owner: 'é'.repeat(32) },
  { ...details(), isNull: 'false' }, details([tuple()], 'postgres', true), details(Array(GRAPHQL_SCHEMA_GRANT_BOUND + 1).fill(tuple())),
  details([['PUBLIC', 'PUBLIC', 'postgres', 'USAGE', false]]), details([['ROLE', null, 'postgres', 'USAGE', false]]),
  details([['ROLE', 'anon', 'postgres', 'SELECT', false]]), details([['ROLE', 'anon', 'postgres', 'USAGE', 1]]), details([[...tuple(), canary]])];
 for (const d of bad) {
  assert.equal(validGraphqlSchemaDetails(d), false); assert.deepEqual(delta(d, details()), { schemaVersion: 1, status: 'INVALID_SHAPE' });
  assert.throws(() => assertGraphqlWitness({ ...witness(), wrapperSchemaDetails: d }, 'TARGET_RESTORED'), e =>
   e.graphql.context === 'TARGET_RESTORED' && e.graphql.reason === 'WITNESS_SCHEMA_DETAILS' && !JSON.stringify(e.graphql).includes(canary));
 }
 assert.equal(validGraphqlSchemaDetails(details(Array(GRAPHQL_SCHEMA_GRANT_BOUND).fill(tuple()))), true);
});
test('public projection refuses injected values, malformed counts, inconsistent fields and duplicates', () => {
 const good = delta(details(), details([]));
 const edits = [v => v.owner.source = canary, v => v.owner.extra = canary, v => v.owner.equal = false,
  v => v.aclNull.equal = false, v => v.aclNull.source = canary, v => v.tuples.sourceCount++, v => v.tuples.equal = true,
  v => v.tuples.delta[0].count = -1, v => v.tuples.delta[0].count = 129, v => v.tuples.delta[0].count = 1.5,
  v => v.tuples.delta[0].grantor = canary, v => v.tuples.delta[0].grantee = canary,
  v => v.tuples.delta[0].privilege = canary, v => v.tuples.delta[0].grantOption = canary,
  v => v.tuples.delta[0].granteeType = canary, v => v.tuples.delta[0].extra = canary,
  v => v.tuples.delta.push(structuredClone(v.tuples.delta[0])), v => v.tuples.delta = Array(257).fill(v.tuples.delta[0]),
  v => v.extra = canary];
 for (const edit of edits) { const v = structuredClone(good); edit(v); assert.deepEqual(project(v), { schemaVersion: 1, status: 'INVALID_SHAPE' }); }
 const p = projectGraphqlDiagnostic({ reason: 'PARITY_FINGERPRINT', context: 'TARGET_COMPARE', wrapperSchemaDelta: { ...good, secret: canary } });
 assert.deepEqual(p.wrapperSchemaDelta, { schemaVersion: 1, status: 'INVALID_SHAPE' }); assert.ok(!JSON.stringify(p).includes(canary));
 assert.deepEqual(projectGraphqlDiagnostic(p), p);
 for (const patch of [{ reason: 'REVIEW' }, { context: 'PARTITION' }])
  assert.equal(projectGraphqlDiagnostic({ reason: 'PARITY_FINGERPRINT', context: 'TARGET_COMPARE', wrapperSchemaDelta: good, ...patch }).wrapperSchemaDelta, undefined);
});
test('maximum-size private delta remains complete and public counters are bounded', () => {
 const a = details(Array.from({ length: 128 }, (_, i) => ['ROLE', 'private_' + i, 'supabase_admin', 'CREATE', false]));
 const b = details(Array.from({ length: 128 }, (_, i) => ['ROLE', 'other_' + i, 'supabase_admin', 'USAGE', true]));
 const d = delta(a, b); assert.equal(d.tuples.sourceOnlyCount, 128); assert.equal(d.tuples.targetOnlyCount, 128);
 assert.equal(d.tuples.delta.length, 2); assert.deepEqual(project(d), d); assert.ok(!JSON.stringify(d).includes('private_'));
});
test('diagnostic details are deep copied and frozen before exporter access', () => {
 const v = input(); const plan = partitionGraphqlRestore(v);
 v.witness.wrapperSchemaDetails.owner = canary; v.witness.wrapperSchemaDetails.grants[0][1] = canary;
 assert.equal(plan.sourceWitness.wrapperSchemaDetails.owner, 'supabase_admin'); assert.equal(plan.sourceWitness.wrapperSchemaDetails.grants[0][1], 'supabase_admin');
 assert.ok(Object.isFrozen(plan.sourceWitness.wrapperSchemaDetails)); assert.ok(Object.isFrozen(plan.sourceWitness.wrapperSchemaDetails.grants));
 assert.ok(Object.isFrozen(plan.sourceWitness.wrapperSchemaDetails.grants[0])); assert.ok(!JSON.stringify(plan.proof).includes('wrapperSchemaDetails'));
});
test('SQL details reuse the same private tuple CTE without changing the canonical facts or emitting SQL', () => {
 const sql = readFileSync(new URL('../graphql-native-witness.sql', import.meta.url), 'utf8');
 assert.match(sql, /'schemaVersion',5/); assert.match(sql, /'wrapperSchemaDetails',\(SELECT jsonb_build_object\('owner',pg_get_userbyid\(n.nspowner\),'isNull',n.nspacl IS NULL/);
 assert.match(sql, /'grants',COALESCE\(\(SELECT jsonb_agg\(grant_tuple ORDER BY grant_tuple::text COLLATE "C"\) FROM wrapper_schema_acl\),'\[\]'::jsonb\)\) FROM wrapper_schema n\)/);
 assert.ok(!/\b(?:GRANT|REVOKE|UPDATE|DELETE|INSERT|ALTER)\b/.test(sql));
});
