/** Server projection only; a declaration never becomes a verified credential here. */
export interface InternatServeur {
  statut: 'A_VERIFIER' | 'VERIFIE' | 'EXPIRE' | 'NON_CONCERNE';
  specialite_code: string | null;
  specialite_label: string | null;
  valide_jusqua: string | null;
  qualification_confirmee?: boolean;
}
export interface PresentationInternat {
  label: string; detail: string; tone: 'pending' | 'verified' | 'expired';
  specialite: string | null; validite: string | null;
}

const nonempty = (value: unknown): value is string => typeof value === 'string' && value.trim().length > 0;
const isoDate = (value: unknown): value is string => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
  && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;

/** Presentation is not an eligibility verdict. The server rechecks mission, proof and dates. */
export function presentationInternat(value: unknown, declaredStudent = false, profession?: string | null): PresentationInternat | null {
  const raw = value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null;
  if (raw?.statut === 'NON_CONCERNE' && raw.qualification_confirmee === true && nonempty(raw.specialite_label)) return {
    label: 'Médecin · qualification vérifiée', tone: 'verified', specialite: raw.specialite_label,
    validite: null, detail: 'L’inscription à l’Ordre et la qualification ont été contrôlées après l’internat.' };
  if (raw?.statut === 'NON_CONCERNE') return null;
  if (raw?.statut === 'VERIFIE' && nonempty(raw.specialite_code) && nonempty(raw.specialite_label) && isoDate(raw.valide_jusqua)) {
    return { label: 'Interne · licence vérifiée', tone: 'verified', specialite: raw.specialite_label,
      validite: raw.valide_jusqua, detail: 'La spécialité autorisée et la validité de la licence seront contrôlées à nouveau lors de l’acceptation.' };
  }
  if (raw?.statut === 'EXPIRE') return { label: 'Interne · licence expirée', tone: 'expired',
    specialite: nonempty(raw.specialite_label) ? raw.specialite_label : null,
    validite: isoDate(raw.valide_jusqua) ? raw.valide_jusqua : null,
    detail: 'Une preuve de remplacement valide est nécessaire avant l’acceptation.' };
  if (raw?.statut === 'A_VERIFIER' || raw?.statut === 'VERIFIE') return {
    label: 'Parcours médical · vérification requise', tone: 'pending', specialite: null, validite: null,
    detail: 'La spécialité et le droit au remplacement ne sont pas confirmés.' };
  if (profession === 'MEDECIN' && declaredStudent) return {
    label: 'Étudiant en médecine · statut à vérifier', tone: 'pending', specialite: null, validite: null,
    detail: 'La déclaration d’études ne confirme ni un internat vérifié ni un droit au remplacement.' };
  return null;
}

/** Form validation only. The backend owns canonical reference checks and admission. */
export function erreurChoixInternes(profession: string, accepteInternes: boolean, specialty: string | null): string | null {
  if (!accepteInternes) return null;
  if (profession !== 'MEDECIN') return 'L’accueil des internes concerne uniquement une mission de médecin.';
  if (!specialty?.trim()) return 'Choisissez la spécialité de la mission avant d’accepter des internes.';
  return null;
}
