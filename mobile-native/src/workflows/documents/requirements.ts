import { PROFESSIONS_SANS_RPPS } from '../../../../src/lib/constantes';
import { rppsDispenseDiplome, TYPES_DOCUMENTS_EXCLUS_UPLOAD } from '../../../../src/lib/documents';
import type { DocumentProfile, DocumentRequirement } from './types';

/** Same presentation filters as DocumentsSoignant.tsx; eligibility remains a server decision. */
export function visibleDocumentRequirements(profile: DocumentProfile, rules: DocumentRequirement[]): DocumentRequirement[] {
  const liberal = profile.type_exercice === 'LIBERAL' || profile.type_exercice === 'MIXTE';
  const salarie = !!profile.type_exercice && profile.type_exercice !== 'LIBERAL';
  const registreVerifie = (!!profile.profession && !PROFESSIONS_SANS_RPPS.includes(profile.profession)
    && profile.rpps_verifie === true) || profile.adeli_verifie === true;
  return rules.filter(rule => {
    if (rule.profession !== profile.profession || TYPES_DOCUMENTS_EXCLUS_UPLOAD.includes(rule.type_document)) return false;
    if (rule.type_document === 'DIPLOME' && rppsDispenseDiplome(profile.profession, profile.rpps_verifie)) return false;
    if (registreVerifie && ['RPPS_ADELI', 'AUTORISATION_EXERCICE'].includes(rule.type_document)) return false;
    if (rule.type_exercice_requis === 'LIBERAL_ONLY') return liberal;
    if (rule.type_exercice_requis === 'SALARIE_ONLY') return salarie;
    return true;
  });
}
