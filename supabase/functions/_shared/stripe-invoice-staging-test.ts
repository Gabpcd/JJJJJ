// Admission temporaire de la seule facture salariée de la cohorte TEST existante.
// Aucun nouveau compte, Customer, transfert, payout ou mécanisme SQL parallèle.
type Row = Record<string, any>;
type Client = { from(table: string): any; auth: { admin: { getUserById(id: string): PromiseLike<any> } } };
type StripeRead = { accounts: { retrieve(): PromiseLike<any> }; balance: { retrieve(): PromiseLike<any> };
  customers: { retrieve(id: string): PromiseLike<any> }; checkout: { sessions: { retrieve(id: string): PromiseLike<any> } } };
const STAGE = 'https://mejpriaetwgtcstbgfid.supabase.co';
const E = 'fcaa6c97-46c1-4da9-8f74-1395aed616c5';
const S = 'abba3c93-5408-47bf-96e3-0864c7de3cb7';
const ACCOUNT = 'acct_1UM0NlI8RIUZoi0j';
const CUSTOMER = 'cus_VMjraPs5wJ1GBO';
const PLATFORM = 'acct_1T9pt0EVhQ7cb53W';
const OWNER = 'connect-test-ci-36975875132-1:c3e2db2cb986c81a58e4c39010c33b487dc14915';
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const fail = (): never => { throw new Error('INVOICE_STAGING_TEST_REFUSED'); };
const must = (v: unknown): void => { if (!v) fail(); };
export type StagingInvoiceConfig = { serverSha: string; uiSha: string; manifestSha256: string;
  missionId: string; factureId: string; amountCents: number; createdAt: string; expiresAt: string; returnOrigin: string };
export function stagingInvoiceConfig(get: (key: string) => string | undefined, now = Date.now()): StagingInvoiceConfig | null {
  const raw = get('INVOICE_STAGING_TEST_RUN');
  if (!raw) return null;
  must(get('SUPABASE_URL') === STAGE && !get('CONNECT_STAGING_TEST_RUN')
    && [undefined, 'staging', 'test'].includes(get('SUPABASE_ENV'))
    && /^(sk|rk)_test_[A-Za-z0-9]+$/.test(get('STRIPE_SECRET_KEY') || ''));
  let c: Row; try { c = JSON.parse(raw); } catch { return fail(); }
  const keys = ['serverSha','uiSha','manifestSha256','missionId','factureId','amountCents','createdAt','expiresAt','returnOrigin'];
  must(c && !Array.isArray(c) && Object.keys(c).length === keys.length && keys.every(k => k in c)
    && /^[a-f0-9]{40}$/.test(c.serverSha) && /^[a-f0-9]{40}$/.test(c.uiSha)
    && /^[a-f0-9]{64}$/.test(c.manifestSha256) && uuid.test(c.missionId) && uuid.test(c.factureId)
    && c.missionId !== c.factureId && c.amountCents === 1742
    && c.returnOrigin === 'http://127.0.0.1:8085'
    && typeof c.createdAt === 'string' && typeof c.expiresAt === 'string');
  const created = Date.parse(c.createdAt), expires = Date.parse(c.expiresAt);
  must(Number.isFinite(created) && Number.isFinite(expires) && created <= now + 30_000
    && expires > created && expires - created <= 4 * 3600_000);
  // Un objet déjà lié peut encore être rapproché après expiration ; aucune
  // nouvelle Session n'est créée sans la fenêtre active vérifiée ci-dessous.
  return Object.freeze(c) as StagingInvoiceConfig;
}
export function stagingInvoiceCheckoutExpiry(c: StagingInvoiceConfig, now = Date.now()): number {
  const expires = Math.floor(Date.parse(c.expiresAt) / 1000);
  must(expires * 1000 - now >= 31 * 60_000 && expires * 1000 - now <= 4 * 3600_000);
  return expires;
}
export async function requireStagingInvoiceScope(sb: Client, c: StagingInvoiceConfig, factureId: string): Promise<void> {
  must(factureId === c.factureId);
  for (const [id, role, table, link, value] of [
    [E, 'ADMIN_ETABLISSEMENT', 'etablissements', 'stripe_customer_id', CUSTOMER],
    [S, 'SOIGNANT', 'soignants', 'stripe_account_id', ACCOUNT],
  ]) {
    const auth = await sb.auth.admin.getUserById(id);
    const u = auth.data?.user, meta = u?.app_metadata;
    must(!auth.error && u?.id === id && meta?.role === role && meta?.est_compte_test === true
      && meta?.jolene_connect_fixture_owner === OWNER && !u.deleted_at && !!u.email_confirmed_at
      && (!u.banned_until || Date.parse(u.banned_until) <= Date.now())
      && (id !== E || meta.etablissement_id === E));
    const p = await sb.from(table).select(`id,est_compte_test,supprime_le,${link}`).eq('id', id).single();
    must(!p.error && p.data?.id === id && p.data.est_compte_test === true
      && p.data.supprime_le === null && p.data[link] === value);
  }
  const f = await sb.from('factures').select('id,etablissement_id,mission_id,facture_honoraire_id,type_document,statut,montant_ttc,nombre_missions').eq('id', c.factureId).single();
  const m = await sb.from('missions').select('id,etablissement_id,soignant_assigne_id,type_contrat_applique,statut,facture_id').eq('id', c.missionId).single();
  must(!f.error && f.data?.id === c.factureId && f.data.etablissement_id === E && f.data.mission_id === c.missionId
    && f.data.facture_honoraire_id === null && f.data.type_document === 'FACTURE' && f.data.nombre_missions === 1
    && ['EMISE','EN_RETARD','PAYEE'].includes(f.data.statut) && Math.round(Number(f.data.montant_ttc) * 100) === c.amountCents
    && !m.error && m.data?.id === c.missionId && m.data.etablissement_id === E && m.data.soignant_assigne_id === S
    && m.data.type_contrat_applique === 'SALARIE' && m.data.statut === 'TERMINEE'
    && (m.data.facture_id === null || m.data.facture_id === c.factureId));
  const other = await sb.from('missions').select('id').eq('facture_id', c.factureId).neq('id', c.missionId).limit(1);
  const traces = await sb.from('stripe_transfers').select('id').eq('mission_id', c.missionId).limit(1);
  must(!other.error && Array.isArray(other.data) && other.data.length === 0
    && !traces.error && Array.isArray(traces.data) && traces.data.length === 0);
}
export async function stagingInvoiceCustomer(stripe: StripeRead): Promise<string> {
  const [account, balance, customer] = await Promise.all([
    stripe.accounts.retrieve(), stripe.balance.retrieve(), stripe.customers.retrieve(CUSTOMER),
  ]);
  must(account?.id === PLATFORM && balance?.livemode === false && customer?.id === CUSTOMER
    && customer.deleted !== true && customer.livemode === false && customer.metadata?.etablissement_id === E);
  return CUSTOMER;
}
export function assertStagingInvoiceObject(c: StagingInvoiceConfig, value: Row, session: boolean): void {
  must(value?.livemode === false && value.currency === 'eur' && value.customer === CUSTOMER
    && value.metadata?.facture_id === c.factureId && value.metadata?.etablissement_id === E
    && value[session ? 'amount_total' : 'amount'] === c.amountCents
    && (!session || value.client_reference_id === c.factureId
      && /^cs_test_[A-Za-z0-9]+$/.test(value.id) && value.mode === 'payment'
      && value.expires_at === Math.floor(Date.parse(c.expiresAt) / 1000)
      && value.created * 1000 >= Date.parse(c.createdAt) - 30_000));
}
export async function requireStagingInvoiceEvent(sb: Client, stripe: StripeRead, c: StagingInvoiceConfig,
  source: string, event: Row): Promise<boolean> {
  if (source !== 'PLATFORM' || event.livemode !== false
    || !['checkout.session.completed','payment_intent.succeeded'].includes(event.type)
    || event.data?.object?.metadata?.facture_id !== c.factureId) return false;
  await requireStagingInvoiceScope(sb, c, c.factureId);
  await stagingInvoiceCustomer(stripe);
  const claims = await sb.from('stripe_payment_flow_claims').select('resource_key,flow,owner_token,stripe_checkout_session_id,stripe_payment_intent_id')
    .in('resource_key', [`FACTURE:${c.factureId}`, `MISSION:${c.missionId}`]);
  must(!claims.error && Array.isArray(claims.data) && claims.data.length === 2
    && new Set(claims.data.map((r: Row) => r.resource_key)).size === 2
    && claims.data.every((r: Row) => r.flow === 'CHECKOUT_INVOICE' && r.owner_token === `invoice:${c.factureId}`
      && typeof r.stripe_checkout_session_id === 'string' && /^cs_test_[A-Za-z0-9]+$/.test(r.stripe_checkout_session_id))
    && new Set(claims.data.map((r: Row) => r.stripe_checkout_session_id)).size === 1);
  const session = await stripe.checkout.sessions.retrieve(claims.data[0].stripe_checkout_session_id);
  assertStagingInvoiceObject(c, session, true);
  const object = event.data.object;
  const intentId = typeof session.payment_intent === 'string' ? session.payment_intent : session.payment_intent?.id;
  must(typeof intentId === 'string' && /^pi_[A-Za-z0-9]+$/.test(intentId)
    && claims.data.every((r: Row) => r.stripe_payment_intent_id === null || r.stripe_payment_intent_id === intentId));
  if (event.type === 'checkout.session.completed') must(object.id === session.id);
  else must(object.id === intentId);
  assertStagingInvoiceObject(c, object, event.type === 'checkout.session.completed');
  return true;
}
