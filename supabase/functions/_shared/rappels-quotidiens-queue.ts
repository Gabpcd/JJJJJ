/** Livraisons daily durables : payload et identité relus exclusivement côté serveur. */
export const TYPES_RAPPELS_QUOTIDIENS = [
  'CRON_DAILY_MISSION_EMAIL', 'CRON_DAILY_MISSION_SMS',
  'CRON_DAILY_CONTRAT_ETAB', 'CRON_DAILY_CONTRAT_SOIGNANT',
];
export interface RappelQuotidien {
  valide: boolean;
  canal: 'EMAIL' | 'SMS';
  scope: string;
  identite: Record<string, unknown>;
  corps: Record<string, unknown>;
}
export async function traiterRappelQuotidien(
  sb: any, emailId: string,
  envoyer: (rappel: RappelQuotidien) => Promise<'sent' | 'skipped' | 'pending'>,
): Promise<'email' | 'sms' | 'annule' | 'pending' | 'erreur'> {
  const { data: rappel, error } = await sb.rpc('fn_lire_rappel_quotidien', { p_email_id: emailId });
  if (error || typeof rappel?.valide !== 'boolean') throw new Error('Validation du rappel indisponible');
  const acquitter = async (resultat: string) => {
    const { error } = await sb.rpc('fn_acquitter_rappel_quotidien', { p_email_id: emailId, p_resultat: resultat });
    if (error) throw new Error('Acquittement du rappel non confirmé ; reprise avec la même identité');
  };
  if (!rappel.valide) { await acquitter('ANNULE'); return 'annule'; }
  if (!['EMAIL','SMS'].includes(rappel.canal) || !rappel.corps || !rappel.identite || !rappel.scope) {
    throw new Error('Contrat du rappel invalide');
  }
  let outcome: 'sent' | 'skipped' | 'pending';
  try { outcome = await envoyer(rappel); }
  catch { await acquitter('ERREUR'); return 'erreur'; }
  if (outcome === 'pending') return 'pending';
  await acquitter(outcome === 'sent' ? 'ENVOYE' : 'ANNULE');
  return outcome === 'skipped' ? 'annule' : rappel.canal === 'SMS' ? 'sms' : 'email';
}
