import { timingSafeSecretEqual } from './cron-service-auth.ts';

const STAGE = 'https://mejpriaetwgtcstbgfid.supabase.co';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const isUuid = (value: unknown): value is string => typeof value === 'string' && UUID.test(value);
type Config = { capabilityId: string; missionId: string; sourceSha: string; manifestSha256: string; createdAt: string; expiresAt: string };
const fail = (): never => { throw new Error('HONORAIRES_STAGING_TEST_REFUSED'); };
const must = (value: unknown): void => { if (!value) fail(); };

// No client or SQL access before the exact project and service credential match.
// A cron automation secret is deliberately insufficient for this explicit mode.
export async function traiterHonorairesStagingTest(req: Request, body: unknown,
  get: (key: string) => string | undefined, create: (url: string, key: string) => any): Promise<Response> {
  const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
  try {
    must(get('SUPABASE_URL') === STAGE && [undefined, 'staging', 'test'].includes(get('SUPABASE_ENV')));
    must(req.method === 'POST' && body && typeof body === 'object' && !Array.isArray(body)
      && Object.keys(body).join(',') === 'mode' && (body as { mode: unknown }).mode === 'demandes-test');
    const key = get('SUPABASE_SERVICE_ROLE_KEY');
    const bearer = /^Bearer (\S+)$/.exec(req.headers.get('authorization') || '')?.[1];
    must(key && bearer && await timingSafeSecretEqual(bearer, key));
    // These independent admissions must remain absent throughout this campaign.
    for (const variable of ['CONNECT_STAGING_TEST_RUN', 'INVOICE_STAGING_TEST_RUN',
      'SIGNATURE_SMS_STAGING_TEST_RUN', 'INVOICE_EMAIL_STAGING_TEST_RUN']) must(!get(variable));
    const raw = get('HONORAIRES_STAGING_TEST_RUN');
    must(raw);
    const c: Config = JSON.parse(raw!);
    must(c && typeof c === 'object' && !Array.isArray(c)
      && Object.keys(c).sort().join(',') === 'capabilityId,createdAt,expiresAt,manifestSha256,missionId,sourceSha'
      && Object.values(c).every(value => typeof value === 'string')
      && isUuid(c.capabilityId) && isUuid(c.missionId)
      && /^[a-f0-9]{40}$/.test(c.sourceSha) && /^[a-f0-9]{64}$/.test(c.manifestSha256));
    const created = Date.parse(c.createdAt), expires = Date.parse(c.expiresAt);
    const active = () => Number.isFinite(created) && Number.isFinite(expires)
      && created <= Date.now() && expires > Date.now() && expires > created && expires - created <= 3600_000;
    must(active());
    const sb = create(STAGE, key!);
    const args = { p_capacity_id: c.capabilityId, p_mission_id: c.missionId,
      p_source_sha: c.sourceSha, p_manifest_sha256: c.manifestSha256,
      p_created_at: c.createdAt, p_expires_at: c.expiresAt };
    const call = async (action: string, token: string | null = null) => {
      must(active());
      const r = await sb.rpc('fn_demande_honoraires_recette', { ...args, p_action: action, p_token: token });
      must(!r.error && r.data && typeof r.data === 'object' && !Array.isArray(r.data)
        && r.data.mission_id === c.missionId);
      return r.data;
    };
    const taken = await call('PRENDRE');
    if (taken.state === 'TERMINEE') {
      must(isUuid(taken.facture_id) && isUuid(taken.facture_commission_id));
      return new Response(JSON.stringify({ success: true, replay: true, mission_id: c.missionId,
        facture_id: taken.facture_id, facture_commission_id: taken.facture_commission_id }), { headers });
    }
    if (taken.state === 'OCCUPEE') return new Response(JSON.stringify({ success: false, reason: 'BAIL_OU_DELAI_ACTIF' }), { status: 409, headers });
    must(taken.state === 'PRISE' && isUuid(taken.token) && typeof taken.invoke === 'boolean');
    if (taken.invoke) {
      // Keep the canonical classification false. Positive admission is distinct.
      const classification = await sb.rpc('fn_mission_est_reelle_pour_service', { p_mission_id: c.missionId });
      must(!classification.error && classification.data === false);
      const admitted = await call('INVOQUER', taken.token);
      must(admitted.state === 'AUTORISEE' && active());
      try {
        // Budget was consumed durably before this unique call. No HTTP retry.
        await sb.functions.invoke('generate-invoice', {
          body: { mission_id: c.missionId, service_role_reason: `ops_test_honoraires_${c.capabilityId}` },
        });
      } catch { /* Only the canonical SQL acknowledgement proves completion. */ }
    }
    must(active());
    const observed = await sb.rpc('fn_constater_demande_facturation_honoraires', {
      p_mission_id: c.missionId, p_token: taken.token,
    });
    const success = !observed.error && observed.data?.success === true
      && isUuid(observed.data.facture_id) && isUuid(observed.data.facture_commission_id);
    return new Response(JSON.stringify({ success, replay: !taken.invoke, mission_id: c.missionId,
      ...(success ? { facture_id: observed.data.facture_id, facture_commission_id: observed.data.facture_commission_id }
        : { reason: 'GENERATION_NON_CONSTATEE_AUCUN_REESSAI_GENERATEUR' }) }), { status: success ? 200 : 409, headers });
  } catch {
    return new Response(JSON.stringify({ error: 'HONORAIRES_STAGING_TEST_REFUSED' }), { status: 403, headers });
  }
}
