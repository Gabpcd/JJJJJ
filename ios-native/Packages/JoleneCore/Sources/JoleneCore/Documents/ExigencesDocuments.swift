import Foundation

/// Règles d'exigences documentaires portées du web.
///
/// Lot 2, T2 : dispense et compatibilité du diplôme (`src/lib/documents.ts`), miroirs du contrôle
/// SQL `fn_documents_ok_pour_mission`. La tranche T2b ajoutera, après la PR web W1 qui les extrait
/// de `DocumentsSoignant.tsx` l.211-269 vers `src/lib/documents-requis.ts`, `filtrerDocumentsRequis`
/// (exigences par profession et `type_exercice`, lues dans la table paramétrée
/// `documents_requis_par_profession`) et `documentValidePourExigence`, avec leurs vecteurs golden.
/// Aucune exigence n'est codée ici : seule la table serveur dit quels documents sont requis.
public enum ExigencesDocuments {
    /// `PROFESSIONS_SANS_RPPS` (`src/lib/constantes.ts` l.55), même ordre ; gardé par un vecteur.
    public static let professionsSansRpps = ["AS", "AES", "AUXILIAIRE_PUERICULTURE"]

    /// Un RPPS vérifié dispense du DIPLOME, sauf pour une profession sans RPPS et pour une
    /// spécialité qui exige le diplôme exact (IADE, IBODE).
    public static func rppsDispenseDiplome(profession: String?, rppsVerifie: Bool?) -> Bool {
        guard rppsVerifie == true, let profession, !profession.isEmpty else { return false }
        return !professionsSansRpps.contains(profession)
            && !ProfessionHierarchy.exigeSpecialisationExacte(professionRequise: profession)
    }

    /// Même correspondance exacte que `profession_certifiee` dans le contrôle SQL : pour IADE et
    /// IBODE, le diplôme doit certifier cette profession (casse indifférente) ; sinon tout diplôme convient.
    public static func diplomeCompatibleProfession(profession: String?, professionCertifiee: String?) -> Bool {
        guard ProfessionHierarchy.exigeSpecialisationExacte(professionRequise: profession) else { return true }
        guard let professionCertifiee else { return false }
        return professionCertifiee.uppercased() == profession
    }
}
