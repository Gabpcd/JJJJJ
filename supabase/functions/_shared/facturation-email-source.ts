import type { SupabaseClient } from 'npm:@supabase/supabase-js@2.99.2';
import { resolveOperationalTestAccount, type OperationalTestAccountResult } from './test-account.ts';

const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const validId = (value: unknown): value is string => typeof value === 'string' && UUID.test(value);
const absentId = (value: unknown) => value === null || value === undefined;
const refused = (): OperationalTestAccountResult => ({ ok: false, error: 'source documentaire indisponible ou incohérente' });

type Document = {
  id: string; etablissement_id: string; mission_id: string | null;
  soignant_id?: string; facture_honoraire_id?: string | null; nombre_missions?: number;
};

/** Classify real document parties, including old payloads and grouped invoices.
 * Never rewrites the durable body/key and never infers parties from a recipient.
 */
export async function resolveFacturationEmailSource(
  client: SupabaseClient, rawPayload: unknown, recipientId: unknown,
): Promise<OperationalTestAccountResult> {
  if (!rawPayload || typeof rawPayload !== 'object' || Array.isArray(rawPayload) || !validId(recipientId)) return refused();
  const payload = rawPayload as Record<string, unknown>;
  if (!validId(payload.facture_id)) return refused();
  const family = payload.famille_document;
  if (family !== undefined && family !== null && family !== 'HONORAIRES' && family !== 'COMMISSION') return refused();
  const columns = {
    HONORAIRES: 'id,etablissement_id,soignant_id,mission_id',
    COMMISSION: 'id,etablissement_id,mission_id,facture_honoraire_id,nombre_missions',
  };
  const readDocument = async (kind: keyof typeof columns, id: string) => client
    .from(kind === 'HONORAIRES' ? 'factures_honoraires' : 'factures')
    .select(columns[kind]).eq('id', id).maybeSingle();
  // Old direct-emission bodies did not contain famille_document. Ambiguity or a
  // read error refuses delivery; a unique existing document remains compatible.
  const kinds = family ? [family as keyof typeof columns] : ['HONORAIRES', 'COMMISSION'] as const;
  const documents: Array<{ kind: keyof typeof columns; row: Document }> = [];
  for (const kind of kinds) {
    const { data, error } = await readDocument(kind, payload.facture_id);
    if (error) return refused();
    if (data) documents.push({ kind, row: data as Document });
  }
  if (documents.length !== 1) return refused();
  const { kind, row: document } = documents[0];
  if (document.id !== payload.facture_id || !validId(document.etablissement_id)
    || (document.mission_id !== null && !validId(document.mission_id))) return refused();
  if (recipientId !== document.etablissement_id && (kind !== 'HONORAIRES' || recipientId !== document.soignant_id)) return refused();
  const accounts = new Set<string>([document.etablissement_id]);
  const missions = new Set<string>();
  let documentCaregiverKnown = false;
  if (document.mission_id) missions.add(document.mission_id);
  if (kind === 'HONORAIRES') {
    if (!validId(document.soignant_id)) return refused();
    accounts.add(document.soignant_id);
    documentCaregiverKnown = true;
  } else {
    if (!Object.hasOwn(document, 'facture_honoraire_id')) return refused();
    if (!absentId(document.facture_honoraire_id)) {
      if (!validId(document.facture_honoraire_id)) return refused();
      const { data, error } = await readDocument('HONORAIRES', document.facture_honoraire_id);
      const fee = data as Document | null;
      if (error || !fee || fee.id !== document.facture_honoraire_id || !validId(fee.soignant_id)
        || fee.etablissement_id !== document.etablissement_id
        || (fee.mission_id !== null && !validId(fee.mission_id))
        || (document.mission_id !== null && fee.mission_id !== document.mission_id)) return refused();
      // The billed caregiver is immutable even if the mission assignment changes.
      accounts.add(fee.soignant_id);
      documentCaregiverKnown = true;
      if (fee.mission_id) missions.add(fee.mission_id);
    }
    const { data, error, count } = await client.from('missions')
      .select('id,etablissement_id,soignant_assigne_id', { count: 'exact' })
      .eq('facture_id', document.id).limit(1000);
    if (error || !Array.isArray(data) || !Number.isInteger(count) || count !== data.length) return refused();
    if (!document.mission_id && !document.facture_honoraire_id
      && (!Number.isInteger(document.nombre_missions) || document.nombre_missions! < 0 || document.nombre_missions !== count)) return refused();
    for (const mission of data) {
      if (!validId(mission.id) || mission.etablissement_id !== document.etablissement_id
        || !validId(mission.soignant_assigne_id)) return refused();
      accounts.add(mission.soignant_assigne_id);
    }
  }
  for (const id of missions) {
    const { data, error } = await client.from('missions')
      .select('etablissement_id,soignant_assigne_id').eq('id', id).maybeSingle();
    if (error || !data || data.etablissement_id !== document.etablissement_id
      || (!validId(data.soignant_assigne_id)
        && !(data.soignant_assigne_id === null && documentCaregiverKnown))) return refused();
    if (data.soignant_assigne_id) accounts.add(data.soignant_assigne_id);
  }
  // Sequential bounded batches keep a monthly group from issuing hundreds of
  // concurrent requests. Missing/unknown classifications never become real.
  const ids = [...accounts];
  for (let start = 0; start < ids.length; start += 8) {
    const results = await Promise.all(ids.slice(start, start + 8).map(id => resolveOperationalTestAccount(client, id)));
    const failure = results.find(result => !result.ok);
    if (failure) return failure;
    if (results.some(result => result.ok && result.isTest)) return { ok: true, isTest: true };
  }
  return { ok: true, isTest: false };
}
