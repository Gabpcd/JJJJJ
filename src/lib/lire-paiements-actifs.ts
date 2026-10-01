// Lecture bornée aux missions présentes dans les obligations de l’établissement.
// Le backend reste seul responsable de l’autorisation et de l’écriture de paiement.
export type PaiementActif = {
  id: string;
  mission_id: string;
  facture_honoraire_id: string | null;
  statut: 'DECLARE' | 'CONFIRME' | 'CONTESTE' | 'RESOLU';
};
type PagePaiements = { data: unknown; error: unknown; count: number | null };
const texte = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
const refuse = () => { throw new Error('Historique des paiements incomplet ou incohérent'); };

export async function lirePaiementsActifs(
  obligations: unknown,
  lirePage: (missions: string[], debut: number, fin: number) => PromiseLike<PagePaiements>,
): Promise<PaiementActif[]> {
  if (!Array.isArray(obligations) || obligations.some(m => !m || !texte(m.mission_id))) return refuse();
  const missions = [...new Set<string>(obligations.map(m => m.mission_id))];
  if (missions.length > 1000) return refuse();
  const resultat: PaiementActif[] = [], ids = new Set<string>();
  for (let lot = 0; lot < missions.length; lot += 100) {
    const scope = missions.slice(lot, lot + 100);
    const capaciteRestante = 10000 - resultat.length;
    let offset = 0, total: number | null = null;
    do {
      const page = await lirePage(scope, offset, offset + 199);
      if (page.error) throw page.error;
      if (!Array.isArray(page.data) || !Number.isSafeInteger(page.count) || page.count! < 0
        || page.count! > capaciteRestante
        || (total !== null && total !== page.count)) return refuse();
      total = page.count;
      if (page.data.length > 200 || offset + page.data.length > total!
        || (page.data.length === 0 && offset < total!)) return refuse();
      for (const row of page.data) {
        if (!row || typeof row !== 'object' || Array.isArray(row)
          || Object.keys(row).sort().join(',') !== 'facture_honoraire_id,id,mission_id,statut'
          || !texte(row.id) || ids.has(row.id) || !scope.includes(row.mission_id)
          || !(row.facture_honoraire_id === null || texte(row.facture_honoraire_id))
          || !['DECLARE','CONFIRME','CONTESTE','RESOLU'].includes(row.statut)) return refuse();
        ids.add(row.id); resultat.push(row as PaiementActif);
      }
      offset += page.data.length;
    } while (offset < total!);
  }
  return resultat;
}
