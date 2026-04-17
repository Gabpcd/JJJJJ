/**
 * CP-LITIGES-7b-3 — Export CSV des litiges filtrés (pas de lib externe).
 *
 * Échappe RFC 4180 : toute valeur contenant `,`, `"`, `\n` ou `\r` est
 * entourée de guillemets, et les guillemets internes sont doublés.
 */

import type { LitigeEnrichi } from './types';

const COLONNES = [
  'id',
  'type_litige',
  'categorie_litige',
  'statut',
  'initie_par',
  'soignant_nom',
  'etablissement_nom',
  'mission_intitule',
  'motif',
  'cree_le',
  'resolu_le',
  'montant_tresorerie_bloquee',
  'en_faveur_de',
] as const;

type Colonne = (typeof COLONNES)[number];

export function enFaveurDeDepuisStatut(statut: string): string {
  switch (statut) {
    case 'RESOLU_SOIGNANT':
      return 'SOIGNANT';
    case 'RESOLU_ETABLISSEMENT':
      return 'ETABLISSEMENT';
    case 'RESOLU_ADMIN':
      return 'PARTAGE';
    default:
      return '';
  }
}

function escapeCsv(v: unknown): string {
  if (v == null) return '';
  const s = String(v);
  if (/[",\n\r]/.test(s)) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

export function litigeToRow(l: LitigeEnrichi): Record<Colonne, string> {
  const soignantNom = l.soignant
    ? `${l.soignant.prenom ?? ''} ${l.soignant.nom ?? ''}`.trim()
    : '';
  return {
    id: l.id,
    type_litige: l.type_litige ?? '',
    categorie_litige: l.categorie_litige ?? '',
    statut: l.statut,
    initie_par: l.initie_par,
    soignant_nom: soignantNom,
    etablissement_nom: l.etablissement?.nom ?? '',
    mission_intitule: l.mission?.intitule ?? '',
    motif: l.motif ?? '',
    cree_le: l.cree_le ?? '',
    resolu_le: l.resolu_le ?? '',
    montant_tresorerie_bloquee: String(l.montant_tresorerie_bloquee ?? ''),
    en_faveur_de: enFaveurDeDepuisStatut(l.statut),
  };
}

export function toCsv(litiges: LitigeEnrichi[]): string {
  const lignes: string[] = [];
  lignes.push(COLONNES.join(','));
  for (const l of litiges) {
    const row = litigeToRow(l);
    lignes.push(COLONNES.map((c) => escapeCsv(row[c])).join(','));
  }
  return lignes.join('\r\n');
}

export function nomFichierCsv(d: Date = new Date()): string {
  const iso = d.toISOString().slice(0, 10);
  return `litiges-${iso}.csv`;
}

export function telechargerCsv(litiges: LitigeEnrichi[]): void {
  const csv = toCsv(litiges);
  // BOM UTF-8 pour Excel FR.
  const blob = new Blob([`\uFEFF${csv}`], {
    type: 'text/csv;charset=utf-8;',
  });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = nomFichierCsv();
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
