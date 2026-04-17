/**
 * CP-LITIGES-7a Bloc 4 (FIX 13) — Tests structurels templates email litiges
 *
 * Lit la source de `supabase/functions/send-email/index.ts` et vérifie pour
 * chaque template litige :
 *   1. Un `case 'TYPE':` est présent.
 *   2. Le block utilise `WRAPPER(` (cohérence layout).
 *   3. Aucun pattern `{variable}` non-interpolé n'apparaît dans le block
 *      (seules les interpolations `${...}` sont acceptées).
 *
 * Impossible d'importer renderTemplate directement : l'edge function utilise
 * `Deno.serve` et `Deno.env`, incompatibles avec vitest/node. On lit donc le
 * fichier en tant que texte (pattern déjà utilisé par mask-sensitive.test.ts).
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const SOURCE_PATH = join(
  __dirname,
  '..',
  '..',
  'supabase',
  'functions',
  'send-email',
  'index.ts',
);
const SOURCE = readFileSync(SOURCE_PATH, 'utf-8');

const LITIGE_TEMPLATES = [
  'LITIGE_OUVERTURE',
  'LITIGE_NOUVEAU_MESSAGE',
  'LITIGE_ESCALADE_ADMIN',
  'LITIGE_MEDIATION_PRIORITAIRE',
  'LITIGE_RESOLU_AJUSTE',
  'AVOIR_EMIS',
  'REMBOURSEMENT_CONFIRME',
  'LITIGE_RAPPEL_J1',
  'LITIGE_RAPPEL_J3',
  'LITIGE_RAPPEL_J5',
  'REGULARISATION_SOCIALE_REQUISE',
  'COMMISSION_AJUSTEE',
] as const;

/**
 * Extrait le block d'un `case 'TYPE':` jusqu'au prochain `case ` ou `default:`.
 * Renvoie null si le case n'est pas trouvé.
 */
function extractCaseBlock(source: string, caseName: string): string | null {
  const re = new RegExp(`case\\s+'${caseName}'\\s*:`, 'm');
  const match = re.exec(source);
  if (!match) return null;
  const start = match.index;
  const tail = source.slice(start + match[0].length);
  const nextCase = tail.search(/case\s+'[A-Z_]+'\s*:|^\s*default\s*:/m);
  return nextCase === -1 ? tail : tail.slice(0, nextCase);
}

describe('Templates email litiges — structure (FIX 13)', () => {
  it.each(LITIGE_TEMPLATES)('template %s possède un case dans le switch', (name) => {
    const block = extractCaseBlock(SOURCE, name);
    expect(block, `case '${name}': introuvable dans send-email/index.ts`).not.toBeNull();
  });

  it.each(LITIGE_TEMPLATES)('template %s utilise WRAPPER() pour le layout', (name) => {
    const block = extractCaseBlock(SOURCE, name);
    expect(block).not.toBeNull();
    expect(block!).toMatch(/WRAPPER\(/);
  });

  it.each(LITIGE_TEMPLATES)(
    'template %s ne contient aucun placeholder {variable} non-interpolé',
    (name) => {
      const block = extractCaseBlock(SOURCE, name);
      expect(block).not.toBeNull();
      // Retire d'abord les interpolations légitimes ${...} (équilibrées sur 1 niveau)
      const stripped = block!.replace(/\$\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/g, '');
      // Détecte un placeholder brut de type {motCle} ou {mot_cle} hors interpolation
      const rawPlaceholder = /(?<!\$)\{[a-zA-Z_][a-zA-Z0-9_]*\}/;
      expect(
        stripped.match(rawPlaceholder),
        `Placeholder non-interpolé dans ${name} : ${stripped.match(rawPlaceholder)?.[0]}`,
      ).toBeNull();
    },
  );

  it('tous les templates retournent un objet avec subject et html', () => {
    for (const name of LITIGE_TEMPLATES) {
      const block = extractCaseBlock(SOURCE, name);
      expect(block).not.toBeNull();
      expect(block!, `${name} doit retourner { subject, html }`).toMatch(/subject\s*:/);
      expect(block!, `${name} doit retourner { subject, html }`).toMatch(/html\s*:/);
    }
  });

  it('template AVOIR_EMIS déclare hasAttachment: true', () => {
    const block = extractCaseBlock(SOURCE, 'AVOIR_EMIS');
    expect(block).not.toBeNull();
    expect(block!).toMatch(/hasAttachment\s*:\s*true/);
  });
});
