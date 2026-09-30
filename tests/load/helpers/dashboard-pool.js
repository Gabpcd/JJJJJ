// Contrat pur partagé entre préparation Node et moteur k6. Dix profils seulement.
export const NOMBRE_PROFILS_DASHBOARD = 10;

export function runDashboardMembre(runId, slot) {
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,74}$/.test(runId || '')
    || !Number.isInteger(slot) || slot < 0 || slot >= NOMBRE_PROFILS_DASHBOARD) {
    throw new Error('Run ou slot du pool dashboard invalide.');
  }
  return `${runId}-d${String(slot).padStart(2, '0')}`;
}

export function lirePoolDashboard(raw, runId) {
  runDashboardMembre(runId, 0);
  let pool;
  try { pool = JSON.parse(raw); } catch { throw new Error('Pool dashboard privé invalide.'); }
  if (!Array.isArray(pool) || pool.length !== NOMBRE_PROFILS_DASHBOARD) throw new Error('Dix identités dashboard requises.');
  const ids = new Set(), emails = new Set();
  for (const [slot, p] of pool.entries()) {
    if (!p || Object.keys(p).sort().join(',') !== 'email,password,runId,slot,userId'
      || p.slot !== slot || p.runId !== runDashboardMembre(runId, slot)
      || !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-a[a-f0-9]{3}-[a-f0-9]{12}$/.test(p.userId || '')
      || p.email !== `recette-dashboard-${p.userId}@example.invalid`
      || typeof p.password !== 'string' || p.password.length < 32 || /[\r\n]/.test(p.password)
      || ids.has(p.userId) || emails.has(p.email)) throw new Error('Identité du pool dashboard incohérente.');
    ids.add(p.userId); emails.add(p.email);
  }
  return pool;
}

export function slotDashboard(vu) {
  if (!Number.isInteger(vu) || vu < 1) throw new Error('VU dashboard invalide.');
  return (vu - 1) % NOMBRE_PROFILS_DASHBOARD;
}
