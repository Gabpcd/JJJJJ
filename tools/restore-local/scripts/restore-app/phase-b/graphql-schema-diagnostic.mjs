// Pure, bounded diagnostics. Private role identities are compared BEFORE redaction.
// This module never grants, revokes, normalizes defaults or changes the parity gate.
export const GRAPHQL_SCHEMA_GRANT_BOUND = 128;
const plain = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const keys = (v, expected) => plain(v) && Object.keys(v).length === expected.length && expected.every(k => Object.hasOwn(v, k));
const name = v => typeof v === 'string' && v.length > 0 && !v.includes('\0') && Buffer.byteLength(v, 'utf8') <= 63;
const privileges = ['CREATE', 'USAGE'];
export function validGraphqlSchemaDetails(v) {
  return keys(v, ['owner', 'isNull', 'grants']) && name(v.owner) && typeof v.isNull === 'boolean'
    && Array.isArray(v.grants) && v.grants.length <= GRAPHQL_SCHEMA_GRANT_BOUND
    && (!v.isNull || v.grants.length === 0)
    && v.grants.every(row => Array.isArray(row) && row.length === 5
      && ((row[0] === 'PUBLIC' && row[1] === null) || (row[0] === 'ROLE' && name(row[1])))
      && name(row[2]) && privileges.includes(row[3]) && typeof row[4] === 'boolean');
}
export function freezeGraphqlSchemaDetails(v) {
  return Object.freeze({ owner: v.owner, isNull: v.isNull,
    grants: Object.freeze(v.grants.map(row => Object.freeze([...row]))) });
}
const multiset = rows => {
  const counts = new Map();
  for (const row of rows) { const key = JSON.stringify(row); counts.set(key, (counts.get(key) ?? 0) + 1); }
  return counts;
};
const role = (v, roles) => roles.includes(v) ? v : 'UNKNOWN';
export function graphqlSchemaDelta(source, target, roles) {
  if (!validGraphqlSchemaDetails(source) || !validGraphqlSchemaDetails(target)) return { schemaVersion: 1, status: 'INVALID_SHAPE' };
  const a = multiset(source.grants), b = multiset(target.grants), projected = new Map();
  let matchedCount = 0, sourceOnlyCount = 0, targetOnlyCount = 0;
  for (const key of new Set([...a.keys(), ...b.keys()])) {
    const ca = a.get(key) ?? 0, cb = b.get(key) ?? 0;
    matchedCount += Math.min(ca, cb);
    if (ca === cb) continue;
    const [type, grantee, grantor, privilege, grantOption] = JSON.parse(key);
    const side = ca > cb ? 'SOURCE_ONLY' : 'TARGET_ONLY', count = Math.abs(ca - cb);
    if (ca > cb) sourceOnlyCount += count; else targetOnlyCount += count;
    const entry = { side, granteeType: type === 'PUBLIC' ? 'PUBLIC' : roles.includes(grantee) ? 'ROLE' : 'UNKNOWN',
      grantee: type === 'PUBLIC' ? 'PUBLIC' : role(grantee, roles), grantor: role(grantor, roles), privilege, grantOption };
    // Group only AFTER exact private subtraction; opposite sides never cancel
    // when different private identities both project to UNKNOWN.
    const publicKey = JSON.stringify(entry), previous = projected.get(publicKey);
    projected.set(publicKey, { ...entry, count: (previous?.count ?? 0) + count });
  }
  return { schemaVersion: 1, status: 'COMPLETE',
    owner: { equal: source.owner === target.owner, source: role(source.owner, roles), target: role(target.owner, roles) },
    aclNull: { equal: source.isNull === target.isNull, source: source.isNull, target: target.isNull },
    tuples: { equal: sourceOnlyCount === 0 && targetOnlyCount === 0,
      sourceCount: source.grants.length, targetCount: target.grants.length, matchedCount, sourceOnlyCount, targetOnlyCount,
      delta: [...projected.values()].sort((x, y) => { const a = JSON.stringify(x), b = JSON.stringify(y); return a < b ? -1 : a > b ? 1 : 0; }) } };
}
// Revalidate on the public boundary. An invalid diagnostic never becomes a pass
// or emits part of a malformed object; it gets a constant INVALID_SHAPE marker.
export function projectGraphqlSchemaDelta(v, roles) {
  const invalid = () => ({ schemaVersion: 1, status: 'INVALID_SHAPE' });
  const counter = n => Number.isSafeInteger(n) && n >= 0 && n <= GRAPHQL_SCHEMA_GRANT_BOUND;
  const roleValue = v => roles.includes(v) || v === 'UNKNOWN';
  const pair = v => keys(v, ['equal', 'source', 'target']) && typeof v.equal === 'boolean';
  if (!keys(v, ['schemaVersion', 'status', 'owner', 'aclNull', 'tuples']) || v.schemaVersion !== 1 || v.status !== 'COMPLETE'
    || !pair(v.owner) || !roleValue(v.owner.source) || !roleValue(v.owner.target)
    || (v.owner.source !== 'UNKNOWN' && v.owner.target !== 'UNKNOWN' && v.owner.equal !== (v.owner.source === v.owner.target))
    || (v.owner.equal && v.owner.source !== v.owner.target)
    || !pair(v.aclNull) || typeof v.aclNull.source !== 'boolean' || typeof v.aclNull.target !== 'boolean'
    || v.aclNull.equal !== (v.aclNull.source === v.aclNull.target)) return invalid();
  const t = v.tuples;
  if (!keys(t, ['equal', 'sourceCount', 'targetCount', 'matchedCount', 'sourceOnlyCount', 'targetOnlyCount', 'delta'])
    || typeof t.equal !== 'boolean' || !['sourceCount', 'targetCount', 'matchedCount', 'sourceOnlyCount', 'targetOnlyCount'].every(k => counter(t[k]))
    || t.sourceCount !== t.matchedCount + t.sourceOnlyCount || t.targetCount !== t.matchedCount + t.targetOnlyCount
    || (v.aclNull.source && t.sourceCount !== 0) || (v.aclNull.target && t.targetCount !== 0)
    || t.equal !== (t.sourceOnlyCount === 0 && t.targetOnlyCount === 0)
    || !Array.isArray(t.delta) || t.delta.length > GRAPHQL_SCHEMA_GRANT_BOUND * 2) return invalid();
  const seen = new Set(), delta = []; let sourceOnly = 0, targetOnly = 0;
  for (const d of t.delta) {
    if (!keys(d, ['side', 'granteeType', 'grantee', 'grantor', 'privilege', 'grantOption', 'count'])
      || !['SOURCE_ONLY', 'TARGET_ONLY'].includes(d.side)
      || !((d.granteeType === 'PUBLIC' && d.grantee === 'PUBLIC') || (d.granteeType === 'ROLE' && roles.includes(d.grantee))
        || (d.granteeType === 'UNKNOWN' && d.grantee === 'UNKNOWN'))
      || !roleValue(d.grantor) || !privileges.includes(d.privilege) || typeof d.grantOption !== 'boolean'
      || !counter(d.count) || d.count === 0) return invalid();
    const row = { side: d.side, granteeType: d.granteeType, grantee: d.grantee, grantor: d.grantor,
      privilege: d.privilege, grantOption: d.grantOption, count: d.count };
    const { count, ...tuple } = row, key = JSON.stringify(tuple);
    if (seen.has(key)) return invalid(); seen.add(key);
    if (d.side === 'SOURCE_ONLY') sourceOnly += d.count; else targetOnly += d.count;
    delta.push(row);
  }
  if (sourceOnly !== t.sourceOnlyCount || targetOnly !== t.targetOnlyCount) return invalid();
  return { schemaVersion: 1, status: 'COMPLETE', owner: { equal: v.owner.equal, source: v.owner.source, target: v.owner.target },
    aclNull: { equal: v.aclNull.equal, source: v.aclNull.source, target: v.aclNull.target },
    tuples: { equal: t.equal, sourceCount: t.sourceCount, targetCount: t.targetCount, matchedCount: t.matchedCount,
      sourceOnlyCount: t.sourceOnlyCount, targetOnlyCount: t.targetOnlyCount, delta } };
}
