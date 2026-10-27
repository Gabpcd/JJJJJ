import type { SupabaseClient } from '@supabase/supabase-js';
import type { AcceptanceEmailReceipt, ApplicationSnapshot } from './types';

interface EmailJob { recipient: AcceptanceEmailReceipt['recipient']; body: Record<string, unknown>; receipt: AcceptanceEmailReceipt }
/** Bodies are frozen once so a retry uses the existing server idempotency fingerprint. */
export function acceptanceEmailJobs(snapshot: ApplicationSnapshot, contractId?: string): EmailJob[] {
  const mission = snapshot.mission;
  const date = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Europe/Paris' }).format(new Date(mission.debut_le));
  const time = (value: string) => new Intl.DateTimeFormat('fr-FR', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Paris' }).format(new Date(value));
  const revisionTime = snapshot.assignmentRevision ? Date.parse(snapshot.assignmentRevision) : NaN;
  const occurrence = contractId || (Number.isFinite(revisionTime) ? new Date(revisionTime).toISOString() : null);
  if (!occurrence || !/^[A-Za-z0-9._:-]+$/.test(occurrence)) throw new Error('La référence de l’attribution ne peut pas être vérifiée pour les emails.');
  const key = `native-acceptance:${mission.id}:${snapshot.userId}:${occurrence}`;
  return [
    { recipient: 'soignant', receipt: { recipient: 'soignant', state: 'pending' }, body: {
      type: 'MISSION_ACCEPTEE_SOIGNANT', destinataire_id: snapshot.userId, idempotency_key: `${key}:soignant`,
      data: { prenom: snapshot.caregiver.firstName, mission: mission.intitule, etablissement: mission.etablissements?.nom ?? '',
        date, heure_debut: time(mission.debut_le), heure_fin: time(mission.fin_le), taux_horaire: mission.taux_horaire_base, mission_id: mission.id },
    } },
    { recipient: 'etablissement', receipt: { recipient: 'etablissement', state: 'pending' }, body: {
      type: 'MISSION_ACCEPTEE_ETABLISSEMENT', destinataire_id: mission.etablissement_id, idempotency_key: `${key}:etablissement`,
      data: { soignant_nom: `${snapshot.caregiver.firstName} ${snapshot.caregiver.lastName}`.trim(), profession: snapshot.caregiver.profession,
        mission: mission.intitule, date, mission_id: mission.id },
    } },
  ];
}

export async function sendAcceptanceEmails(client: SupabaseClient, token: string, jobs: EmailJob[], signal?: AbortSignal): Promise<AcceptanceEmailReceipt[]> {
  await Promise.all(jobs.map(async job => {
    if (job.receipt.state === 'sent' || job.receipt.state === 'skipped') return;
    if (signal?.aborted) { job.receipt = { recipient: job.recipient, state: 'failed' }; return; }
    try {
      const { data, error } = await client.functions.invoke('send-email', { body: job.body, headers: { Authorization: `Bearer ${token}` }, signal });
      if (error || data?.success !== true) job.receipt = { recipient: job.recipient, state: 'failed' };
      else if (data.pending === true) job.receipt = { recipient: job.recipient, state: 'pending' };
      else if (data.skipped === true) job.receipt = { recipient: job.recipient,
        state: data.reason === 'idempotency_already_sent' ? 'sent' : 'skipped', reason: String(data.reason ?? 'unknown') };
      else job.receipt = { recipient: job.recipient, state: 'sent' };
    } catch { job.receipt = { recipient: job.recipient, state: 'failed' }; }
  }));
  return jobs.map(job => ({ ...job.receipt }));
}
