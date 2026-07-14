/** Encode une cellule CSV pour tableurs, y compris contre l’injection de formule. */
export function encoderCelluleCsv(value: unknown): string {
  const normalisee = String(value ?? '').replace(/[\r\n]+/g, ' ');
  const protegee = /^\s*[=+\-@]/.test(normalisee)
    ? `'${normalisee}`
    : normalisee;
  return `"${protegee.replace(/"/g, '""')}"`;
}
