import Foundation

/// Ligne de `documents_requis_par_profession` (table paramétrée) telle que le filtre la lit.
/// Le filtre est générique pour rendre les lignes reçues, avec toutes leurs colonnes (T6).
public protocol RegleDocumentRequisRepresentable {
    /// `profession` (NOT NULL, `public.sql` l.69059).
    var profession: String { get }
    /// `type_document` (NOT NULL, l.69060).
    var typeDocument: String { get }
    /// `type_exercice_requis` : `TOUS`, `SALARIE_ONLY` ou `LIBERAL_ONLY` (CHECK l.69066) ; nul, vide
    /// ou inconnu vaut `TOUS`, comme le repli du web.
    var typeExerciceRequis: String? { get }
}

/// Ligne de `documents_requis_par_profession` (port de `RegleDocumentRequis`).
public struct RegleDocumentRequis: Codable, Equatable, Sendable, RegleDocumentRequisRepresentable {
    public var id: String?
    public var profession: String
    public var typeDocument: String
    public var typeExerciceRequis: String?
    public var estCritique: Bool?

    public init(id: String? = nil, profession: String, typeDocument: String, typeExerciceRequis: String? = nil, estCritique: Bool? = nil) {
        self.id = id; self.profession = profession; self.typeDocument = typeDocument
        self.typeExerciceRequis = typeExerciceRequis; self.estCritique = estCritique
    }

    enum CodingKeys: String, CodingKey {
        case id, profession
        case typeDocument = "type_document"
        case typeExerciceRequis = "type_exercice_requis"
        case estCritique = "est_critique"
    }
}

/// Profil du soignant tel que lu par la page Documents (port de `SoignantExigencesDocuments`).
public struct SoignantExigencesDocuments: Codable, Equatable, Sendable {
    public var profession: String?
    public var typeExercice: String?
    public var rppsVerifie: Bool?
    public var adeliVerifie: Bool?

    public init(profession: String?, typeExercice: String?, rppsVerifie: Bool?, adeliVerifie: Bool?) {
        self.profession = profession; self.typeExercice = typeExercice
        self.rppsVerifie = rppsVerifie; self.adeliVerifie = adeliVerifie
    }

    enum CodingKeys: String, CodingKey {
        case profession
        case typeExercice = "type_exercice"
        case rppsVerifie = "rpps_verifie"
        case adeliVerifie = "adeli_verifie"
    }
}

/// Pièce de `documents_soignants` comparée à une exigence (port de `DocumentSoignantExigence`).
public struct DocumentSoignantExigence: Codable, Equatable, Sendable {
    public var typeDocument: String
    public var statutVerification: String
    /// `valide_jusqua` (colonne `date`) : jamais écrite par le client.
    public var valideJusqua: String?
    /// `resultat_ia->>profession_certifiee` (`DocumentsSoignant.tsx` l.199) : texte ou nul.
    public var professionCertifiee: String?

    public init(typeDocument: String, statutVerification: String, valideJusqua: String?, professionCertifiee: String?) {
        self.typeDocument = typeDocument; self.statutVerification = statutVerification
        self.valideJusqua = valideJusqua; self.professionCertifiee = professionCertifiee
    }

    enum CodingKeys: String, CodingKey {
        case typeDocument = "type_document"
        case statutVerification = "statut_verification"
        case valideJusqua = "valide_jusqua"
        case professionCertifiee = "profession_certifiee"
    }
}

/// Règles d'exigences documentaires portées du web.
///
/// Lot 2, T2 : dispense et compatibilité du diplôme (`src/lib/documents.ts`), miroirs du contrôle
/// SQL `fn_documents_ok_pour_mission`. Lot 2, T2b : `filtrerDocumentsRequis` et
/// `documentValidePourExigence` (`src/lib/documents-requis.ts`, extraits de `DocumentsSoignant.tsx`
/// par la PR web W1, #1112), avec leurs vecteurs golden (`documents-requis.json`).
/// Aucune exigence n'est codée ici : seule la table serveur dit quels documents sont requis.
public enum ExigencesDocuments {
    /// `PROFESSIONS_SANS_RPPS` (`src/lib/constantes.ts` l.55), même ordre ; gardé par un vecteur.
    public static let professionsSansRpps = ["AS", "AES", "AUXILIAIRE_PUERICULTURE"]

    /// `TYPES_DOCUMENTS_EXCLUS_UPLOAD` (`src/lib/documents.ts` l.26), même ordre ; gardé par un vecteur.
    /// Ces pièces sont remplacées par l'attestation sur l'honneur : jamais proposées à l'envoi.
    public static let typesDocumentsExclusUpload = ["VACCINATIONS", "MEDECINE_TRAVAIL"]

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

    /// Exigences du soignant, par profession ET `type_exercice` (port de `filtrerDocumentsRequis`).
    /// LIBERAL ou MIXTE inclut les `LIBERAL_ONLY` ; un régime salarié renseigné ou MIXTE inclut les
    /// `SALARIE_ONLY` : un MIXTE cumule les deux. Les lignes retenues sont rendues dans leur ordre.
    public static func filtrerDocumentsRequis<Regle: RegleDocumentRequisRepresentable>(
        _ regles: [Regle]?, soignant: SoignantExigencesDocuments
    ) -> [Regle] {
        let typeExercice = soignant.typeExercice ?? ""
        let estLiberal = typeExercice == "LIBERAL" || typeExercice == "MIXTE"
        let estSalarie = !typeExercice.isEmpty && typeExercice != "LIBERAL"
        let professionAvecRpps = !(soignant.profession.map { professionsSansRpps.contains($0) } ?? false)
        let rppsVerifie = professionAvecRpps && soignant.rppsVerifie == true
        let registreProfessionnelVerifie = rppsVerifie || soignant.adeliVerifie == true
        let dispenseDiplome = rppsDispenseDiplome(profession: soignant.profession, rppsVerifie: soignant.rppsVerifie)
        return (regles ?? []).filter { regle in
            guard regle.profession == soignant.profession else { return false }
            if typesDocumentsExclusUpload.contains(regle.typeDocument) { return false }
            // Le RPPS ne dispense pas du diplôme spécialisé IADE/IBODE ; un ADELI seul ne dispense pas du diplôme.
            if dispenseDiplome && regle.typeDocument == "DIPLOME" { return false }
            if registreProfessionnelVerifie && regle.typeDocument == "RPPS_ADELI" { return false }
            // Une autorisation d'exercice reste une preuve distincte du diplôme : masquée seulement
            // lorsque le registre officiel est déjà validé.
            if registreProfessionnelVerifie && regle.typeDocument == "AUTORISATION_EXERCICE" { return false }
            switch regle.typeExerciceRequis ?? "" {
            case "LIBERAL_ONLY": return estLiberal
            case "SALARIE_ONLY": return estSalarie
            default: return true // TOUS, nul, vide ou inconnu
            }
        }
    }

    /// Une pièce satisfait une exigence si elle est du même type, `VERIFIE`, non expirée à
    /// `maintenant` et, pour un diplôme, certifiée pour la spécialité exacte quand la profession
    /// l'exige (port de `documentValidePourExigence`). Une fin de validité illisible n'est jamais
    /// dépassée côté web (`new Date` invalide) : la pièce n'est alors pas valide (échec fermé).
    public static func documentValidePourExigence(_ document: DocumentSoignantExigence, typeDocumentExige: String,
                                                  profession: String?, maintenant: Date) -> Bool {
        guard document.typeDocument == typeDocumentExige, document.statutVerification == "VERIFIE" else { return false }
        if typeDocumentExige == "DIPLOME",
           !diplomeCompatibleProfession(profession: profession, professionCertifiee: document.professionCertifiee) {
            return false
        }
        guard let valideJusqua = document.valideJusqua, !valideJusqua.isEmpty else { return true }
        // `new Date(valide_jusqua) > maintenant` : une date seule vaut minuit UTC (colonne `date`).
        return DisponibilitePointage.temps(valideJusqua) > DisponibilitePointage.temps(maintenant)
    }
}
