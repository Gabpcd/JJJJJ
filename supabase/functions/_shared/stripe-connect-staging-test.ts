// Admission de la seule recette Connect explicitement allouée sur staging.
// Ce module ne crée aucun objet Stripe ni capacité. Absent en configuration,
// il ne fait aucune lecture et ne modifie aucun comportement de production.
type Dict = Record<string, unknown>;
type Client = { rpc(name: string, args: Dict): PromiseLike<{data: unknown; error: unknown}> };
type StripeIdentity = { accounts: {retrieve(): PromiseLike<unknown>}; balance: {retrieve(): PromiseLike<unknown>} };
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const sha = /^[a-f0-9]{40}$/;
const fail = (): never => { throw new Error('CONNECT_STAGING_TEST_REFUSED'); };
const obj = (v: unknown): Dict => v && typeof v==='object' && !Array.isArray(v) ? v as Dict : fail();
export type StagingConnectConfig = { serverSha: string; uiSha: string; manifestSha256: string; platformAccountId: string; capabilityId: string; returnOrigin: string };
export type StagingConnectCapacity = { id: string; missionId: string; etablissementId: string; soignantId: string;
  factureHonoraireId: string; factureCommissionId: string; customerId: string; destinationId: string;
  soignantCents: number; commissionCents: number; totalCents: number; operationId: string | null; sessionId: string | null; traceId: string | null; claimReservedAt: string | null; expiresAt: number; active: boolean };
export function stagingConnectConfig(getEnv: (name: string)=>string|undefined): StagingConnectConfig | null {
  const raw=getEnv('CONNECT_STAGING_TEST_RUN');
  if(!raw) return null;
  if(getEnv('SUPABASE_URL')!=='https://mejpriaetwgtcstbgfid.supabase.co'
    || !['staging','test'].includes(getEnv('SUPABASE_ENV') || '')
    || !/^(sk|rk)_test_[A-Za-z0-9]+$/.test(getEnv('STRIPE_SECRET_KEY') || '')) fail();
  let c: Dict;try{c=obj(JSON.parse(raw));}catch{fail();}
  const keys=['serverSha','uiSha','manifestSha256','platformAccountId','capabilityId','returnOrigin'];
  if(Object.keys(c!).length!==keys.length || keys.some(k=>typeof c![k]!=='string')
    || !sha.test(c!.serverSha as string) || !sha.test(c!.uiSha as string)
    || !/^[a-f0-9]{64}$/.test(c!.manifestSha256 as string)
    || !/^acct_[A-Za-z0-9]+$/.test(c!.platformAccountId as string) || !uuid.test(c!.capabilityId as string)) fail();
  // Une origine figée par opérateur : aucun return_url arbitraire du client.
  const origin=new URL(c!.returnOrigin as string);
  if(origin.origin!==c!.returnOrigin || !(origin.hostname==='127.0.0.1' && origin.protocol==='http:'
    || origin.hostname==='localhost' && origin.protocol==='http:'
    || origin.hostname.endsWith('-gabpcd.vercel.app') && origin.protocol==='https:')) fail();
  return Object.freeze(c!) as StagingConnectConfig;
}
export async function verifyStagingStripeIdentity(stripe: StripeIdentity,c: StagingConnectConfig): Promise<void> {
  const [account,balance]=await Promise.all([stripe.accounts.retrieve(),stripe.balance.retrieve()]);
  if(obj(account).id!==c.platformAccountId || obj(balance).livemode!==false) fail();
}
export function parseStagingConnectCapacity(value: unknown,c: StagingConnectConfig,now=Date.now()): StagingConnectCapacity {
  const r=obj(value);
  if(r.id!==c.capabilityId || r.protocol!=='CONNECT_STAGING_TEST_V1' || r.project_ref!=='mejpriaetwgtcstbgfid'
    || r.server_sha!==c.serverSha || r.ui_sha!==c.uiSha || r.source_manifest_sha256!==c.manifestSha256
    || r.platform_account_id!==c.platformAccountId || r.livemode!==false || r.transfers_allowed!==false
    || r.max_checkouts!==1 || r.max_refunds!==1 || typeof r.enabled!=='boolean'
    || typeof r.expires_at!=='string' || !Number.isFinite(Date.parse(r.expires_at))
    || !Number.isSafeInteger(now)) fail();
  for(const k of ['id','mission_id','etablissement_id','soignant_id','facture_honoraire_id','facture_commission_id'])
    if(typeof r[k]!=='string'||!uuid.test(r[k] as string))fail();
  if(r.etablissement_id===r.soignant_id || r.facture_honoraire_id===r.facture_commission_id
    || typeof r.customer_id!=='string' || !/^cus_[A-Za-z0-9]+$/.test(r.customer_id)
    || typeof r.destination_id!=='string' || !/^acct_[A-Za-z0-9]+$/.test(r.destination_id)) fail();
  for(const k of ['soignant_cents','commission_cents','total_cents']) if(!Number.isSafeInteger(r[k]) || (r[k] as number)<=0)fail();
  if((r.soignant_cents as number)+(r.commission_cents as number)!==r.total_cents
    || r.operation_id!==null && (typeof r.operation_id!=='string'||!uuid.test(r.operation_id))
    || r.session_id!==null && (typeof r.session_id!=='string'||!/^cs_test_[A-Za-z0-9]+$/.test(r.session_id))
    || r.trace_id!==null && (typeof r.trace_id!=='string'||!uuid.test(r.trace_id))
    || (r.session_id===null)!==(r.trace_id===null) || r.operation_id===null && r.session_id!==null
    || r.claim_reserved_at!==null && (typeof r.claim_reserved_at!=='string'||!Number.isFinite(Date.parse(r.claim_reserved_at)))) fail();
  return Object.freeze({id:r.id,missionId:r.mission_id,etablissementId:r.etablissement_id,soignantId:r.soignant_id,
    factureHonoraireId:r.facture_honoraire_id,factureCommissionId:r.facture_commission_id,
    customerId:r.customer_id,destinationId:r.destination_id,soignantCents:r.soignant_cents,commissionCents:r.commission_cents,
    totalCents:r.total_cents,operationId:r.operation_id,sessionId:r.session_id,traceId:r.trace_id,claimReservedAt:r.claim_reserved_at,
    expiresAt:Date.parse(r.expires_at as string),active:r.enabled && r.revoked_at===null && Date.parse(r.expires_at as string)>now}) as StagingConnectCapacity;
}
export function stagingCheckoutExpiresAt(cap: StagingConnectCapacity,now=Date.now()): number {
  const expiresAt=Math.floor(cap.expiresAt/1000);
  // Stripe exige au moins 30 min ; garder 1 min de marge de transport.
  // Une Session déjà remise ne doit pas rester payable après la capacité TEST.
  if(!cap.active || !Number.isSafeInteger(expiresAt) || expiresAt*1000-now<31*60_000
    || expiresAt*1000-now>24*60*60_000) fail();
  return expiresAt;
}
export async function readStagingConnectCapacity(sb: Client,c: StagingConnectConfig,honoraireId: string,active=false): Promise<StagingConnectCapacity> {
  if(!uuid.test(honoraireId)) fail();
  const {data,error}=await sb.rpc('fn_connect_test_capacite_lire',{p_facture_honoraire_id:honoraireId});
  if(error)fail();
  const cap=parseStagingConnectCapacity(data,c);
  if(cap.factureHonoraireId!==honoraireId || active && !cap.active)fail();
  return cap;
}
export async function authorizeStagingCheckout(sb: Client,stripe: StripeIdentity,c: StagingConnectConfig,operationId: string): Promise<void> {
  await verifyStagingStripeIdentity(stripe,c);
  const {data,error}=await sb.rpc('fn_connect_test_checkout_autoriser',{p_operation_id:operationId,p_server_sha:c.serverSha,p_manifest_sha256:c.manifestSha256});
  if(error||obj(data).operation_id!==operationId||obj(data).allowed!==true)fail();
}
export async function requireStagingRefundScope(sb: Client,c: StagingConnectConfig,op: {
  id:string;facture_honoraire_id:string;session_id:string;livemode:boolean;orientation:string;
}): Promise<void> {
  const cap=await readStagingConnectCapacity(sb,c,op.facture_honoraire_id,true);
  if(cap.operationId!==op.id||cap.sessionId!==op.session_id||op.livemode!==false||op.orientation!=='REFUND')fail();
}
