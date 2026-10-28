import { rendreCddEmployeur } from '../../../supabase/functions/_shared/cdd-employeur';

export const DEMO_CONTRACT_ID = '00000000-0000-4000-8000-000000000021';
export const DEMO_CONTRACT_CODE = '000000';
export const DEMO_CONTRACT_LAST_LINE = "Dernière ligne : l’employeur fictif dit 'oui'.";

/** Uses the actual employer-text renderer with synthetic values, never a legal model from memory. */
export function demoContractHtml(): string {
  const body = rendreCddEmployeur({ numero_contrat: 'DEMO-CONTRAT-001', intitule_mission: 'Mission de démonstration',
    debut_le: '27/10/2026 à 08:00', fin_le: '27/10/2026 à 16:00', etablissement_nom: 'Établissement fictif',
    etablissement_siret: '00000000000000', etablissement_adresse: 'Adresse fictive', soignant_prenom: 'Camille',
    soignant_nom: 'Démonstration', soignant_adresse: 'Adresse fictive' }, {
    cadre: 'TEXTE_EMPLOYEUR', confirme: true, representant_nom: 'Représentant fictif', representant_qualite: 'Direction fictive',
    cadre_declare: 'Simulation d’interface sans engagement réel',
    texte_employeur: `DOCUMENT FICTIF — AUCUN ENGAGEMENT RÉEL\n\nCette page sert uniquement à vérifier le lecteur natif.\nLes personnes, la mission et les données sont fictives.\nAucun SMS n’est envoyé ; aucun contrat réel n’est signé.\n\nExemple de caractères conservés : A & B < C.\n  Deux espaces avant cette ligne.\n\n${DEMO_CONTRACT_LAST_LINE}`,
  }, 'acteur-fictif', '2026-10-27T10:00:00.000Z');
  // Exact wrapInDocument stylesheet. A pure test compares it to the versioned
  // generator; changes must update this fixture explicitly, never relax the reader.
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8" /><title>Contrat fictif DEMO-CONTRAT-001</title><style>
  body { font-family: 'Helvetica Neue', Arial, sans-serif; color: #0f172a; line-height: 1.6; padding: 40px; max-width: 900px; margin: 0 auto; }
  h1 { color: #d6336c; font-size: 22px; border-bottom: 2px solid #fce7f3; padding-bottom: 8px; }
  h2 { color: #4b1d3a; font-size: 16px; margin-top: 24px; }
  p { margin: 8px 0; }
  strong { color: #1e293b; }
  em { color: #64748b; font-size: 12px; }
  .header-mention { background: #fef3f7; border-left: 4px solid #d6336c; padding: 12px 16px; margin-bottom: 24px; font-size: 13px; }
  </style></head><body>${body}</body></html>`;
}
