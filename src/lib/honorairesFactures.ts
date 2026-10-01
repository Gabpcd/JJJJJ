import { supabase } from '@/integrations/supabase/client';
import {
  factureCompteDansTotal,
  montantTtcSigneFacture,
  statutFactureConnu,
  type FactureHonorairesPourUi,
} from './factureHonorairesUi';

export interface HonorairesFactures extends FactureHonorairesPourUi {
  id: string;
  soignant_id: string;
  mission_id: string | null;
  type_document: 'FACTURE' | 'AVOIR';
  statut: string;
  montant_ttc: number;
  date_emission: string;
}

function montantDocumentValide(valeur: unknown): boolean {
  return (typeof valeur === 'number' || (typeof valeur === 'string' && valeur.trim() !== ''))
    && Number.isFinite(Number(valeur)) && Number(valeur) >= 0;
}

/** Lecture RLS exhaustive : le plafond PostgREST ne devient pas un total partiel. */
export async function chargerHonorairesFactures(soignantId: string): Promise<HonorairesFactures[]> {
  const documents = new Map<string, HonorairesFactures>();
  let total: number | null = null;
  let offset = 0;
  while (total === null || offset < total) {
    const { data, count, error } = await supabase.from('factures_honoraires')
      .select('id, soignant_id, mission_id, numero_facture, type_document, montant_signe, statut, montant_ttc, date_emission, cree_le', { count: 'exact' })
      .eq('soignant_id', soignantId)
      .order('id', { ascending: true })
      .range(offset, offset + 499);
    if (error) throw error;
    if (count === null || !Number.isSafeInteger(count) || count < 0
        || (total !== null && count !== total) || !Array.isArray(data)) {
      throw new Error('Le total des documents ne peut pas être vérifié. Rechargez la page.');
    }
    total = count;
    if (data.length === 0 && offset < total) {
      throw new Error('Le chargement des documents est incomplet. Rechargez la page.');
    }
    for (const document of data) {
      if (!document.id || documents.has(document.id) || document.soignant_id !== soignantId
          || !['FACTURE', 'AVOIR'].includes(document.type_document)
          || !statutFactureConnu(document.statut)
          || !montantDocumentValide(document.montant_ttc)
          || !/^\d{4}-\d{2}-\d{2}$/.test(document.date_emission)
          || !Number.isFinite(Date.parse(`${document.date_emission}T12:00:00Z`))
          || new Date(`${document.date_emission}T12:00:00Z`).toISOString().slice(0, 10) !== document.date_emission) {
        throw new Error('Un document financier est incomplet ou incohérent. Rechargez la page.');
      }
      documents.set(document.id, { ...document, montant_ttc: Number(document.montant_ttc) } as HonorairesFactures);
    }
    offset += data.length;
  }
  if (documents.size !== total) throw new Error('Le chargement des documents est incomplet. Rechargez la page.');
  return [...documents.values()];
}

/** Période d'émission de la pièce : aucune ventilation selon le planning mission. */
export function resumerHonorairesFactures(documents: FactureHonorairesPourUi[], mois: string | null = null) {
  const actifs = documents.filter(document => factureCompteDansTotal(document)
    && (mois === null || document.date_emission?.slice(0, 7) === mois));
  const centimes = actifs.reduce((total, document) => total + Math.round(montantTtcSigneFacture(document) * 100), 0);
  return { montant: centimes / 100, nombre: actifs.length };
}
