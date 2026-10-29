/** Display-only: a verified RPPS does not replace a medical intern's licence.
 * This never verifies a document or grants eligibility for a mission. */
export function documentsComplementairesVisibles(profile: {
  profession?: string | null; rpps_verifie?: boolean | null; adeli_verifie?: boolean | null;
} | null | undefined) {
  const registreVerifie = !!(profile?.rpps_verifie || profile?.adeli_verifie);
  return {
    scolarite: !registreVerifie,
    licence: !registreVerifie || profile?.profession === 'MEDECIN',
    qualification: profile?.profession === 'MEDECIN',
  };
}
