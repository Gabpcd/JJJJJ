// Admission temporaire du transport de trois reçus canoniques de deux pièces.
// Les comptes, la mission et les factures restent TEST ; aucun paiement.
const STAGE = 'https://mejpriaetwgtcstbgfid.supabase.co';
const ETABLISSEMENT = 'fcaa6c97-46c1-4da9-8f74-1395aed616c5';
const SOIGNANT = 'abba3c93-5408-47bf-96e3-0864c7de3cb7';
const OWNER = 'connect-test-ci-36975875132-1:c3e2db2cb986c81a58e4c39010c33b487dc14915';
const RECIPIENT = 'gabrielle@jolene.app';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
type Row = Record<string, any>;
type Client = { from(table: string): any; auth: { admin: { getUserById(id: string): PromiseLike<any> } } };
type Event = {
  family: 'HONORAIRES' | 'COMMISSION'; recipientRole: 'SOIGNANT' | 'ETABLISSEMENT';
  emailId: string; bodySha256: string;
};
export type InvoiceEmailStagingConfig = {
  serverSha: string; manifestSha256: string; missionId: string;
  honorairesId: string; commissionId: string; createdAt: string; expiresAt: string;
  events: [Event, Event, Event];
};
const SCOPES = [
  ['HONORAIRES', 'SOIGNANT', SOIGNANT],
  ['HONORAIRES', 'ETABLISSEMENT', ETABLISSEMENT],
  ['COMMISSION', 'ETABLISSEMENT', ETABLISSEMENT],
] as const;
const refuse = (): never => { throw new Error('INVOICE_EMAIL_STAGING_REFUSED'); };
const must = (value: unknown): void => { if (!value) refuse(); };
function exactKeys(value: unknown, keys: string[]): value is Row {
  return !!value && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
}

/** Les SHA sont des références de revue, jamais une attestation de déploiement. */
export function invoiceEmailStagingConfig(
  get: (key: string) => string | undefined, now = Date.now(),
): InvoiceEmailStagingConfig | null {
  const raw = get('INVOICE_EMAIL_STAGING_TEST_RUN');
  if (!raw) return null;
  must(get('SUPABASE_URL') === STAGE && get('APP_URL') === 'http://127.0.0.1:8085'
    && [undefined, 'staging', 'test'].includes(get('SUPABASE_ENV')));
  for (const name of ['INVOICE_STAGING_TEST_RUN', 'CONNECT_STAGING_TEST_RUN', 'HONORAIRES_STAGING_TEST_RUN', 'SIGNATURE_SMS_STAGING_TEST_RUN']) {
    must(!get(name));
  }
  let c: unknown; try { c = JSON.parse(raw); } catch { return refuse(); }
  must(exactKeys(c, ['serverSha', 'manifestSha256', 'missionId', 'honorairesId', 'commissionId', 'createdAt', 'expiresAt', 'events']));
  const config = c as Row;
  must(typeof config.serverSha === 'string' && /^[a-f0-9]{40}$/.test(config.serverSha)
    && typeof config.manifestSha256 === 'string' && /^[a-f0-9]{64}$/.test(config.manifestSha256)
    && [config.missionId, config.honorairesId, config.commissionId].every(id => typeof id === 'string' && UUID.test(id))
    && new Set([config.missionId, config.honorairesId, config.commissionId]).size === 3
    && typeof config.createdAt === 'string' && typeof config.expiresAt === 'string');
  const created = Date.parse(config.createdAt), expires = Date.parse(config.expiresAt);
  must(Number.isFinite(created) && Number.isFinite(expires) && created <= now && now < expires
    && expires > created && expires - created <= 60 * 60_000);
  must(Array.isArray(config.events) && config.events.length === SCOPES.length);
  for (const [index, event] of config.events.entries()) {
    must(exactKeys(event, ['family', 'recipientRole', 'emailId', 'bodySha256'])
      && event.family === SCOPES[index][0] && event.recipientRole === SCOPES[index][1]
      && typeof event.emailId === 'string' && UUID.test(event.emailId)
      && typeof event.bodySha256 === 'string' && /^[a-f0-9]{64}$/.test(event.bodySha256));
  }
  must(new Set(config.events.map((event: Event) => event.emailId)).size === SCOPES.length);
  return Object.freeze(config) as InvoiceEmailStagingConfig;
}

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === 'object') {
    const row = value as Row;
    return Object.fromEntries(Object.keys(row).sort().map(key => [key, canonical(row[key])]));
  }
  return value;
}
export async function invoiceEmailBodySha256(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(canonical(value)));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), n => n.toString(16).padStart(2, '0')).join('');
}

async function requireLiberalDocuments(sb: Client, config: InvoiceEmailStagingConfig): Promise<void> {
  for (const [id, role, table] of [
    [ETABLISSEMENT, 'ADMIN_ETABLISSEMENT', 'etablissements'], [SOIGNANT, 'SOIGNANT', 'soignants'],
  ]) {
    const auth = await sb.auth.admin.getUserById(id);
    const user = auth.data?.user, metadata = user?.app_metadata;
    must(!auth.error && user?.id === id && metadata?.role === role && metadata?.est_compte_test === true
      && metadata.jolene_connect_fixture_owner === OWNER && !user.deleted_at && !!user.email_confirmed_at
      && (!user.banned_until || Date.parse(user.banned_until) <= Date.now())
      && (id !== ETABLISSEMENT || metadata.etablissement_id === ETABLISSEMENT));
    const profile = await sb.from(table).select('id,est_compte_test,supprime_le').eq('id', id).single();
    must(!profile.error && profile.data?.id === id && profile.data.est_compte_test === true && profile.data.supprime_le === null);
  }
  const mission = await sb.from('missions')
    .select('id,etablissement_id,soignant_assigne_id,type_contrat_applique,statut')
    .eq('id', config.missionId).single();
  must(!mission.error && mission.data?.id === config.missionId
    && mission.data.etablissement_id === ETABLISSEMENT && mission.data.soignant_assigne_id === SOIGNANT
    && mission.data.type_contrat_applique === 'LIBERAL' && mission.data.statut === 'TERMINEE');
  const honoraires = await sb.from('factures_honoraires')
    .select('id,mission_id,etablissement_id,soignant_id,type_document,nature_correction,statut,est_facture_finale_mission,pdf_s3_key,facturx_xml_url,emise_le,stripe_payment_intent_id,date_paiement')
    .eq('id', config.honorairesId).single();
  must(!honoraires.error && honoraires.data?.id === config.honorairesId
    && honoraires.data.mission_id === config.missionId && honoraires.data.etablissement_id === ETABLISSEMENT
    && honoraires.data.soignant_id === SOIGNANT && honoraires.data.type_document === 'FACTURE'
    && honoraires.data.nature_correction === 'ORIGINALE' && honoraires.data.statut === 'EMISE'
    && honoraires.data.est_facture_finale_mission === true && !!honoraires.data.pdf_s3_key
    && !!honoraires.data.facturx_xml_url && !!honoraires.data.emise_le
    && honoraires.data.stripe_payment_intent_id === null && honoraires.data.date_paiement === null);
  const commission = await sb.from('factures')
    .select('id,mission_id,etablissement_id,facture_honoraire_id,type_document,statut,stripe_payment_intent_id,date_paiement')
    .eq('id', config.commissionId).single();
  must(!commission.error && commission.data?.id === config.commissionId
    && commission.data.mission_id === config.missionId && commission.data.etablissement_id === ETABLISSEMENT
    && commission.data.facture_honoraire_id === config.honorairesId && commission.data.type_document === 'FACTURE'
    && commission.data.statut === 'EMISE' && commission.data.stripe_payment_intent_id === null
    && commission.data.date_paiement === null);
}

/** Contrôles complets de source, sans création d'ancre ni droit de transport. */
export async function stagingInvoiceEmailScope(
  sb: Client, body: Row, isServiceRole: boolean, get: (key: string) => string | undefined, now = Date.now(),
): Promise<{ recipient: string; recipientId: string; emailId: string; key: string; type: string } | null> {
  if (!isServiceRole || body.type !== 'FACTURE_EMISE' || !get('INVOICE_EMAIL_STAGING_TEST_RUN')) return null;
  const config = invoiceEmailStagingConfig(get, now)!;
  must(exactKeys(body, ['type', 'destinataire_id', 'data', 'idempotency_key'])
    && body.data && typeof body.data === 'object' && !Array.isArray(body.data));
  const index = SCOPES.findIndex(([family, role, id]) => body.data.famille_document === family
    && body.data.destinataire_role === role && body.destinataire_id === id);
  must(index >= 0);
  const [family, role, recipientId] = SCOPES[index];
  const documentId = family === 'HONORAIRES' ? config.honorairesId : config.commissionId;
  must(body.data.facture_id === documentId && body.data.mission_id === config.missionId
    && body.data.etablissement_id === ETABLISSEMENT && body.data.soignant_id === SOIGNANT);
  const key = family === 'HONORAIRES' ? `facture-emise-${role.toLowerCase()}:${documentId}`
    : `facture-emise-commission:${documentId}:${ETABLISSEMENT}`;
  must(body.idempotency_key === key);
  const event = config.events[index];
  const durableBody = { type: body.type, destinataire_id: body.destinataire_id, data: body.data };
  must(await invoiceEmailBodySha256(durableBody) === event.bodySha256);
  const queued = await sb.from('email_queue')
    .select('id,type,destinataire_id,data,statut').eq('id', event.emailId).single();
  must(!queued.error && queued.data?.id === event.emailId && queued.data.type === 'FACTURATION_DOCUMENT'
    && queued.data.destinataire_id === recipientId && ['EN_ATTENTE', 'ENVOYE'].includes(queued.data.statut)
    && await invoiceEmailBodySha256(queued.data.data) === event.bodySha256);
  await requireLiberalDocuments(sb, config);
  must(Date.now() < Date.parse(config.expiresAt));
  return { recipient: RECIPIENT, recipientId, emailId: event.emailId, key, type: body.type };
}

/**
 * L'opérateur crée l'ancre après preuve de l'absence de tentative antérieure.
 * Sa date serveur interdit qu'une capacité renouvelée rouvre une ambiguïté
 * après la fenêtre idempotente du fournisseur. Ce helper n'écrit rien.
 */
export async function admitStagingInvoiceEmail(
  sb: Client, body: Row, isServiceRole: boolean, get: (key: string) => string | undefined, now = Date.now(),
): Promise<{ recipient: string } | null> {
  const scope = await stagingInvoiceEmailScope(sb, body, isServiceRole, get, now);
  if (!scope) return null;
  const anchor = await sb.from('emails_envoyes')
    .select('idempotency_key,destinataire_id,destinataire_email,type,cree_le,statut,provider_id')
    .eq('idempotency_key', scope.key).single();
  must(!anchor.error && anchor.data?.idempotency_key === scope.key
    && anchor.data.destinataire_id === scope.recipientId && anchor.data.destinataire_email === RECIPIENT
    && anchor.data.type === scope.type && ['ERREUR', 'ENVOYE', 'DELIVRE', 'OUVERT'].includes(anchor.data.statut)
    && (anchor.data.provider_id === null || typeof anchor.data.provider_id === 'string')
    && typeof anchor.data.cree_le === 'string');
  const firstAttempt = Date.parse(anchor.data.cree_le);
  must(Number.isFinite(firstAttempt) && firstAttempt <= Date.now() + 30_000 && Date.now() - firstAttempt < 20 * 3600_000);
  return { recipient: scope.recipient };
}
