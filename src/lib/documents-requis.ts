import { PROFESSIONS_SANS_RPPS } from '@/lib/constantes';
import {
  TYPES_DOCUMENTS_EXCLUS_UPLOAD,
  diplomeCompatibleProfession,
  rppsDispenseDiplome,
} from '@/lib/documents';

/**
 * Exigences documentaires du soignant, extraites de `DocumentsSoignant.tsx`
 * pour être partagées avec le port natif (vecteurs golden iOS, lot 2 W1).
 * Règle pure : aucun accès réseau, horloge toujours explicite.
 */

/** Ligne de `documents_requis_par_profession` (table paramétrée). */
export interface RegleDocumentRequis {
  profession: string;
  type_document: string;
  type_exercice_requis?: string | null;
  est_critique?: boolean | null;
}

/** Profil du soignant tel que lu par la page Documents. */
export interface SoignantExigencesDocuments {
  profession: string | null;
  type_exercice: string | null;
  rpps_verifie?: boolean | null;
  adeli_verifie?: boolean | null;
}

/** Pièce de `documents_soignants` comparée à une exigence. */
export interface DocumentSoignantExigence {
  type_document: string;
  statut_verification: string;
  valide_jusqua?: string | null;
  profession_certifiee?: unknown;
}

/**
 * Filtrage par profession ET type_exercice :
 * LIBERAL/MIXTE → inclut les documents LIBERAL_ONLY (RCP/RIB/URSSAF)
 * Un régime salarié renseigné ou MIXTE → inclut SALARIE_ONLY
 * → un MIXTE cumule LES DEUX (obligations salariées + libérales).
 */
export function filtrerDocumentsRequis<T extends RegleDocumentRequis>(
  regles: T[] | null | undefined,
  sg: SoignantExigencesDocuments,
): T[] {
  const estLiberal = sg.type_exercice === 'LIBERAL' || sg.type_exercice === 'MIXTE';
  const estSalarie = !!sg.type_exercice && sg.type_exercice !== 'LIBERAL';
  const professionAvecRpps = !PROFESSIONS_SANS_RPPS.includes(sg.profession);
  const rppsVerifie = professionAvecRpps && !!sg.rpps_verifie;
  const adeliVerifie = !!sg.adeli_verifie;
  const registreProfessionnelVerifie = rppsVerifie || adeliVerifie;
  return (regles || []).filter((d) => {
    if (d.profession !== sg.profession) return false;
    if (TYPES_DOCUMENTS_EXCLUS_UPLOAD.includes(d.type_document)) return false;
    // Le RPPS ne dispense pas du diplôme spécialisé IADE/IBODE.
    // Un ADELI seul ne donne pas de dispense de diplôme.
    if (rppsDispenseDiplome(sg.profession, sg.rpps_verifie) && d.type_document === 'DIPLOME') return false;
    if (registreProfessionnelVerifie && d.type_document === 'RPPS_ADELI') return false;
    // Une autorisation d'exercice reste une preuve distincte du diplôme.
    // Elle n'est masquée que lorsque le registre officiel est déjà validé.
    if (registreProfessionnelVerifie && d.type_document === 'AUTORISATION_EXERCICE') return false;
    const exReq = d.type_exercice_requis || 'TOUS';
    if (exReq === 'LIBERAL_ONLY') return estLiberal;
    if (exReq === 'SALARIE_ONLY') return estSalarie;
    return true; // TOUS
  });
}

/**
 * Une pièce satisfait une exigence si elle est du même type, vérifiée, non
 * expirée à `maintenant` et, pour un diplôme, certifiée pour la spécialité
 * exacte quand la profession l'exige (IADE/IBODE).
 */
export function documentValidePourExigence(
  d: DocumentSoignantExigence,
  exigence: { type_document: string },
  profession: string | null | undefined,
  maintenant: Date,
): boolean {
  return d.type_document === exigence.type_document
    && d.statut_verification === 'VERIFIE'
    && (exigence.type_document !== 'DIPLOME' || diplomeCompatibleProfession(profession, d.profession_certifiee))
    && (!d.valide_jusqua || new Date(d.valide_jusqua) > maintenant);
}
