export interface MedicalSpecialty { code: string; label: string }

const normalizeLabel = (value: string) => value.trim().replace(/\s+/gu, ' ').toLocaleLowerCase('fr');

/** Aucun rapprochement flou : une variante non reconnue part en modération. */
export function resolveLicenseSpecialty(raw: unknown, rows: unknown): string | null {
  if (typeof raw !== 'string' || !raw.trim() || !Array.isArray(rows)) return null;
  const valid = rows.filter((row): row is MedicalSpecialty => !!row && typeof row === 'object'
    && typeof row.code === 'string' && /^SM\d+$/.test(row.code)
    && typeof row.label === 'string');
  const candidates = valid.filter(row => row.code === raw.trim().toUpperCase()
    || normalizeLabel(row.label) === normalizeLabel(raw));
  return candidates.length === 1 ? candidates[0].code : null;
}
