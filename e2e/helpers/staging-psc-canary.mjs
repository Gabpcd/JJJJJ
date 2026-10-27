import { randomUUID } from 'node:crypto';

const fail = code => { throw new Error(`PSC_CANARY_${code}`); };

// Valeurs fictives générées ici : aucun appel authorize/ANS, aucun jeton PSC.
// Ne jamais charger les autres sessions, même pour les compter.
export async function withPreservedPscCanary(admin, verifyDeployment, action, { uuid = randomUUID, now = Date.now } = {}) {
  await verifyDeployment();
  const created = now();
  const row = { state: `jolene-e2e-preservation:${uuid()}`, nonce: `fictif:${uuid()}`,
    code_verifier: `fictif-inutilisable:${uuid()}`, intention: 'login',
    cree_le: new Date(created).toISOString(), expire_le: new Date(created + 60 * 60_000).toISOString() };
  // Tous les marqueurs sont connus AVANT l'unique INSERT. Le nettoyage borné
  // reste possible si la réponse se perd après insertion ; jamais d'upsert.
  const own = () => admin.from('psc_auth_sessions').select('state,nonce,code_verifier,intention,cree_le,expire_le').eq('state', row.state).maybeSingle();
  const same = value => value && ['state', 'nonce', 'code_verifier', 'intention'].every(key => value[key] === row[key])
    && ['cree_le', 'expire_le'].every(key => Date.parse(value[key]) === Date.parse(row[key]));
  const preserved = async () => {
    const result = await own();
    if (result.error || !same(result.data)) fail('NOT_PRESERVED');
  };
  let attempted = false, result, failure;
  try {
    attempted = true;
    const inserted = await admin.from('psc_auth_sessions').insert(row);
    // Un conflit de clé certain ne donne aucune propriété sur la ligne.
    if (inserted.error?.code === '23505') attempted = false;
    if (inserted.error) fail('INSERT_UNCONFIRMED');
    await preserved();
    // Dernier garde avant l'action réelle. Pas de retry si un état change.
    await verifyDeployment();
    try { result = await action(); } finally { await preserved(); }
  } catch (error) { failure = error; }
  finally {
    if (attempted) {
      try {
        // CAS sur le tuple fictif complet : une ligne différente n'est jamais
        // supprimée. L'absence après échec d'insertion est acceptable ici.
        const removed = await admin.from('psc_auth_sessions').delete().match(row).select('state');
        if (removed.error || !Array.isArray(removed.data) || removed.data.length > 1) fail('CLEANUP_UNCONFIRMED');
        const after = await own();
        if (after.error || after.data !== null) fail('CLEANUP_UNCONFIRMED');
      } catch { failure = new Error('PSC_CANARY_CLEANUP_UNCONFIRMED'); }
    }
  }
  if (failure) throw failure;
  return result;
}
