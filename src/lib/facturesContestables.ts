import { supabase } from '@/integrations/supabase/client';

export type FactureContestable = {
  id: string;
  numero_facture: string;
  periode_debut: string | null;
  periode_fin: string | null;
  montant_ttc: number;
  statut: string;
  nature_correction?: string | null;
};

export async function chargerFacturesContestables(
  missionId: string,
  factureId: string | undefined,
  signal: AbortSignal,
): Promise<FactureContestable[]> {
  const resultat: FactureContestable[] = [];
  const ids = new Set<string>();
  let total: number | null = null;
  const statuts = ['EMISE', 'EN_RETARD', 'PAYEE', 'FACTORISEE'];
  // Une revue ouverte depuis un brouillon garde sa pièce. Le serveur décide
  // ensuite quels motifs sont autorisés ; aucun élargissement de ses droits.
  if (factureId) statuts.push('BROUILLON');
  do {
    let query = supabase.from('factures_honoraires')
      .select('id, mission_id, numero_facture, periode_debut, periode_fin, montant_ttc, statut, nature_correction', { count: 'exact' })
      .eq('mission_id', missionId).eq('type_document', 'FACTURE').in('statut', statuts);
    if (factureId) query = query.eq('id', factureId);
    const { data, error, count } = await query.order('periode_debut', { ascending: false })
      .order('id', { ascending: true }).range(resultat.length, resultat.length + 499).abortSignal(signal);
    if (error) throw error;
    if (signal.aborted) throw new Error('Chargement annulé');
    if (!Number.isSafeInteger(count) || count === null || count < 0 || count > 10000
      || (total !== null && total !== count) || !Array.isArray(data)
      || (data.length === 0 && resultat.length < count) || resultat.length + data.length > count) {
      throw new Error('Liste de factures incomplète');
    }
    total = count;
    for (const row of data) {
      const montant: unknown = row?.montant_ttc;
      if (!row || typeof row.id !== 'string' || !row.id || ids.has(row.id)
        || row.mission_id !== missionId || (factureId && row.id !== factureId)
        || typeof row.numero_facture !== 'string' || !row.numero_facture
        || !statuts.includes(row.statut)
        || !['string', 'number'].includes(typeof montant) || montant === ''
        || !Number.isFinite(Number(montant)) || Number(montant) < 0) {
        throw new Error('Liste de factures incohérente');
      }
      ids.add(row.id);
      resultat.push({ ...row, montant_ttc: Number(row.montant_ttc) });
    }
  } while (resultat.length < total);
  if (factureId && resultat.length !== 1) throw new Error('Facture indisponible');
  return resultat;
}
