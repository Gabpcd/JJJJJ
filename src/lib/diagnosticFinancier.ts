export const ERREUR_DIAGNOSTIC_FINANCIER = 'Le diagnostic financier est indisponible pour le moment. Réessayez dans quelques instants.';

export const MOTIFS_DOCUMENT_NON_VERIFIABLE = {
  CORRECTION_MONETAIRE: 'Avoir ou complément : le montant ne se déduit pas des heures et du taux.',
  SNAPSHOTS_INDISPONIBLES: 'Les heures ou le taux figés sur cette pièce sont manquants.',
  SNAPSHOTS_INVALIDES: 'Les heures ou le taux figés sur cette pièce ne permettent pas le contrôle.',
  MONTANT_INVALIDE: 'Le montant de cette pièce ne permet pas le contrôle.',
} as const;

type Groupe<T> = { count: number; echantillon: T[] };
export interface DiagnosticFinancier {
  success: true;
  controle_documentaire_version: 2;
  genere_le: string;
  factures_verifiees: number;
  missions_incoherentes: Groupe<{ id: string; intitule: string; total_brut: number; attendu: number; ecart: number }>;
  factures_ecart_mission: Groupe<{ facture_id: string; numero_facture: string; mission_id: string | null; montant_ht: number; attendu_ht: number; ecart: number }>;
  stripe_transfers_orphelins: Groupe<{ transfer_id: string; mission_id: string; montant_total: number }>;
  factures_non_verifiables: Groupe<{ facture_id: string; numero_facture: string; mission_id: string | null; motif: keyof typeof MOTIFS_DOCUMENT_NON_VERIFIABLE }>;
}

const objet = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === 'object' && !Array.isArray(value);
const texte = (value: unknown): value is string => typeof value === 'string';
const nombre = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value);
const compteur = (value: unknown): value is number => nombre(value) && Number.isSafeInteger(value) && value >= 0;
const mission = (value: unknown) => value === null || texte(value);

function groupe(value: unknown, ligne: (row: Record<string, unknown>) => boolean): boolean {
  return objet(value) && compteur(value.count) && Array.isArray(value.echantillon)
    && value.echantillon.length <= Math.min(value.count, 10)
    && (value.count === 0 || value.echantillon.length > 0)
    && value.echantillon.every(row => objet(row) && ligne(row));
}

/** Un ancien résultat ou une réponse incomplète ne prouve pas la cohérence. */
export function lireDiagnosticFinancier(value: unknown): DiagnosticFinancier {
  if (!objet(value) || value.success !== true || value.controle_documentaire_version !== 2
    || !texte(value.genere_le) || !Number.isFinite(Date.parse(value.genere_le))
    || !compteur(value.factures_verifiees)
    || !groupe(value.missions_incoherentes, row => texte(row.id) && texte(row.intitule)
      && nombre(row.total_brut) && nombre(row.attendu) && nombre(row.ecart))
    || !groupe(value.factures_ecart_mission, row => texte(row.facture_id) && texte(row.numero_facture)
      && mission(row.mission_id) && nombre(row.montant_ht) && nombre(row.attendu_ht) && nombre(row.ecart))
    || !groupe(value.stripe_transfers_orphelins, row => texte(row.transfer_id) && texte(row.mission_id) && nombre(row.montant_total))
    || !groupe(value.factures_non_verifiables, row => texte(row.facture_id) && texte(row.numero_facture)
      && mission(row.mission_id) && texte(row.motif) && Object.prototype.hasOwnProperty.call(MOTIFS_DOCUMENT_NON_VERIFIABLE, row.motif))
    || (value.factures_ecart_mission as { count: number }).count > value.factures_verifiees) {
    throw new Error(ERREUR_DIAGNOSTIC_FINANCIER);
  }
  return value as unknown as DiagnosticFinancier;
}
