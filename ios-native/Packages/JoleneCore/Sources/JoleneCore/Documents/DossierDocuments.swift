import Foundation

/// État d'une exigence affichée, dans l'ordre de `DocumentsSoignant.tsx` l.656-664 : REJETE prime sur la date (un
/// document rejeté reste rejeté même si l'IA a lu une date passée sur le mauvais fichier), puis l'expiration, puis la
/// pièce présente (vérifiée, en attente, en revue…). La pièce retenue est la plus récente du type (`mesDocuments.find`).
public enum EtatExigence: Equatable, Sendable {
    case manquante
    case rejetee(DocumentSoignant)
    /// `valide_jusqua` strictement passée (statut autre que REJETE).
    case expiree(DocumentSoignant)
    /// Pièce présente ; `diplomeSpecialiseAConfirmer` : diplôme vérifié qui ne certifie pas la spécialité exigée
    /// (IADE, IBODE ; l.655-658).
    case presente(DocumentSoignant, diplomeSpecialiseAConfirmer: Bool)
}

/// Bandeau RCP de l'exercice libéral ou mixte (`DocumentsSoignant.tsx` l.611-640).
public enum AlerteRcp: Equatable, Sendable {
    /// `valide_jusqua` passée, quel que soit le statut (l.616).
    case expiree
    /// Aucune RCP, ou RCP non vérifiée (l.617).
    case manquante
}

/// Règles d'affichage du dossier documentaire (lot 2 T6), portées de `src/pages/DocumentsSoignant.tsx`. État dérivé,
/// jamais stocké : tout se recalcule depuis les lignes serveur à l'horloge passée par l'appelant. Aucune exigence en
/// dur : seule la table `documents_requis_par_profession` dit ce qui est requis (filtre golden de T2b).
extension DossierDocuments {
    /// Lignes serveur → dossier : exigences filtrées par profession et `type_exercice`
    /// (`ExigencesDocuments.filtrerDocumentsRequis`, l.205). Sans profil, aucune pièce n'est chargée (l.186-191).
    public static func assembler(profil: SoignantExigencesDocuments?, regles: [ExigenceDocument], documents: [DocumentSoignant],
                                 attestationSanteSigneeLe: String?) -> DossierDocuments {
        guard let profil else { return DossierDocuments() }
        let retenues = ExigencesDocuments.filtrerDocumentsRequis(regles.map(RegleExigence.init), soignant: profil).map(\.exigence)
        return DossierDocuments(exigences: retenues, documents: documents, attestationSanteSigneeLe: attestationSanteSigneeLe,
                                profil: profil)
    }

    /// `docsRequis` (l.236) : exigences critiques, dans l'ordre reçu.
    public var exigencesCritiques: [ExigenceDocument] { exigences.filter { $0.estCritique == true } }

    /// `typesOrdonnes` (l.521-524) : critiques puis optionnelles.
    public var exigencesOrdonnees: [ExigenceDocument] { exigencesCritiques + exigences.filter { $0.estCritique != true } }

    /// Seul un type proposé par un bouton du web peut recevoir un envoi (correction 21 : un envoi `AUTRE` est impossible
    /// par l'interface) : une exigence affichée (l.656-838), un document complémentaire étudiant / interne visible
    /// (l.851-900) ou une pièce du bandeau « expire bientôt » (« Mettre à jour → », l.600-608). Les pièces de santé n'y
    /// figurent jamais (`typesDocumentsExclusUpload`).
    public func peutEnvoyer(typeDocument: String, maintenant: Date) -> Bool {
        guard !ExigencesDocuments.typesDocumentsExclusUpload.contains(typeDocument) else { return false }
        return exigences.contains { $0.typeDocument == typeDocument }
            || typesComplementaires.contains(typeDocument)
            || expirantBientot(maintenant: maintenant).contains { $0.typeDocument == typeDocument }
    }

    /// Documents complémentaires proposés à l'envoi, dans l'ordre du web ; aucun sans dossier professionnel (la page web
    /// s'arrête avant, l.505-518).
    public var typesComplementaires: [String] {
        guard let profil else { return [] }
        return ComplementairesVisibles(profil: profil).types
    }

    /// `docsValides` (l.237-239) : critiques satisfaites par une pièce valide à `maintenant`.
    public func exigencesValidees(maintenant: Date) -> [ExigenceDocument] {
        exigencesCritiques.filter { exigence in
            documents.contains { ExigencesDocuments.documentValidePourExigence(Self.exigible($0), typeDocumentExige: exigence.typeDocument,
                                                                              profession: profil?.profession, maintenant: maintenant) }
        }
    }

    /// `docsManquants` (l.241).
    public func nombreManquants(maintenant: Date) -> Int {
        exigencesCritiques.count - exigencesValidees(maintenant: maintenant).count
    }

    /// `prochainDocRequis` (l.243-246) : première critique sans pièce valide.
    public func prochaineExigence(maintenant: Date) -> ExigenceDocument? {
        let validees = Set(exigencesValidees(maintenant: maintenant).map(\.typeDocument))
        return exigencesCritiques.first { !validees.contains($0.typeDocument) }
    }

    /// Pièce la plus récente du type (le serveur trie par `televerse_le` décroissant).
    public func document(pour typeDocument: String) -> DocumentSoignant? {
        documents.first { $0.typeDocument == typeDocument }
    }

    public func etat(de exigence: ExigenceDocument, maintenant: Date) -> EtatExigence {
        guard let document = document(pour: exigence.typeDocument) else { return .manquante }
        if document.statutVerification == "REJETE" { return .rejetee(document) }
        // `new Date(valide_jusqua) < new Date()` : une date illisible n'est jamais dépassée (NaN).
        if let fin = document.valideJusqua, !fin.isEmpty,
           DisponibilitePointage.temps(fin) < DisponibilitePointage.temps(maintenant) {
            return .expiree(document)
        }
        let aConfirmer = exigence.typeDocument == "DIPLOME" && document.statutVerification == "VERIFIE"
            && !ExigencesDocuments.diplomeCompatibleProfession(profession: profil?.profession,
                                                                professionCertifiee: document.professionCertifiee)
        return .presente(document, diplomeSpecialiseAConfirmer: aConfirmer)
    }

    /// `documentsExpirantBientot` (l.279-283) : pièces VERIFIE encore valides qui expirent dans moins de 30 jours pleins.
    public func expirantBientot(maintenant: Date) -> [DocumentSoignant] {
        documents.filter { document in
            guard document.statutVerification == "VERIFIE", let jours = Self.joursRestants(document, maintenant: maintenant) else {
                return false
            }
            return jours < 30
        }
    }

    /// Jours pleins jusqu'à `valide_jusqua` (`differenceInDays`, tronqué), nil sans date lisible ou si la date est
    /// passée. Écart assumé : date-fns compte en jours civils locaux, ici par tranches de 24 h (une heure d'écart au
    /// plus, aux changements d'heure).
    public static func joursRestants(_ document: DocumentSoignant, maintenant: Date) -> Int? {
        guard let fin = document.valideJusqua, !fin.isEmpty else { return nil }
        let ecartMs = DisponibilitePointage.temps(fin) - DisponibilitePointage.temps(maintenant)
        guard ecartMs.isFinite, ecartMs > 0 else { return nil }
        return Int((ecartMs / 86_400_000).rounded(.towardZero))
    }

    /// Bandeau RCP : seulement en libéral ou mixte (l.612-613).
    public func alerteRcp(maintenant: Date) -> AlerteRcp? {
        guard let exercice = profil?.typeExercice, exercice == "LIBERAL" || exercice == "MIXTE" else { return nil }
        guard let rcp = document(pour: "RCP_ASSURANCE") else { return .manquante }
        if let fin = rcp.valideJusqua, !fin.isEmpty, DisponibilitePointage.temps(fin) < DisponibilitePointage.temps(maintenant) {
            return .expiree
        }
        return rcp.statutVerification == "VERIFIE" ? nil : .manquante
    }

    static func exigible(_ document: DocumentSoignant) -> DocumentSoignantExigence {
        DocumentSoignantExigence(typeDocument: document.typeDocument, statutVerification: document.statutVerification,
                                 valideJusqua: document.valideJusqua, professionCertifiee: document.professionCertifiee)
    }
}

/// Section « Étudiant / interne en santé » du web (`documentsComplementairesVisibles`, `src/lib/documents-complementaires.ts`,
/// affichage seul : ne vérifie aucun document et n'ouvre aucune éligibilité). Un RPPS ou un ADELI vérifié masque la
/// scolarité, jamais la licence de remplacement d'un médecin ; la qualification à l'Ordre est réservée aux médecins.
public struct ComplementairesVisibles: Equatable, Sendable {
    public var scolarite: Bool
    public var licence: Bool
    public var qualification: Bool

    public init(scolarite: Bool, licence: Bool, qualification: Bool) {
        self.scolarite = scolarite; self.licence = licence; self.qualification = qualification
    }

    public init(profil: SoignantExigencesDocuments?) {
        let registreVerifie = profil?.rppsVerifie == true || profil?.adeliVerifie == true
        let medecin = profil?.profession == "MEDECIN"
        self.init(scolarite: !registreVerifie, licence: !registreVerifie || medecin, qualification: medecin)
    }

    /// Types de document des cartes visibles, dans l'ordre du web (l.866-898).
    public var types: [String] {
        var types: [String] = []
        if scolarite { types.append("ATTESTATION_SCOLARITE") }
        if licence { types.append("LICENCE_REMPLACEMENT") }
        if qualification { types.append("CARTE_ORDRE") }
        return types
    }
}

/// Ligne de règle lue pour le filtre : `profession` est NOT NULL côté serveur (une ligne sans profession ne
/// correspond à aucun profil).
private struct RegleExigence: RegleDocumentRequisRepresentable {
    let exigence: ExigenceDocument
    var profession: String { exigence.profession ?? "" }
    var typeDocument: String { exigence.typeDocument }
    var typeExerciceRequis: String? { exigence.typeExerciceRequis }
}

/// Preuve d'enregistrement d'un justificatif relue par `s3_cle` (réconciliation,
/// blueprint §2.5). Projection minimale : `resultat_ia` n'est jamais lu (données d'identité extraites par l'IA) ;
/// la présence de la ligne suffit à interdire toute vérification automatique (décision 14).
public struct PreuveDocument: Codable, Equatable, Sendable {
    public static let selection = "id,s3_cle,statut_verification,verification_attempt_id"

    public var id: String
    public var s3Cle: String
    public var statutVerification: String?
    public var verificationAttemptId: String?

    public init(id: String, s3Cle: String, statutVerification: String?, verificationAttemptId: String?) {
        self.id = id; self.s3Cle = s3Cle; self.statutVerification = statutVerification
        self.verificationAttemptId = verificationAttemptId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case s3Cle = "s3_cle"
        case statutVerification = "statut_verification"
        case verificationAttemptId = "verification_attempt_id"
    }

    /// Vérification déjà engagée : statut sorti d'`EN_ATTENTE` (verdict, revue) ou tentative en cours
    /// (`verify-document` pose `verification_attempt_id` dès son début, `index.ts` l.154-183). Un statut nul n'est pas
    /// une preuve.
    public var verificationEngagee: Bool {
        if let statut = statutVerification, statut != "EN_ATTENTE" { return true }
        return verificationAttemptId != nil
    }

    /// Issue d'une ligne relue, dérivée du statut relu (revue fraîche de T6, m-c) : tentative en cours sans verdict →
    /// suivi du verdict ; revue manuelle, ou aucune tentative → « vérification manuelle en attente » (l.416-419), jamais
    /// de vérification automatique ; verdict déjà rendu (`VERIFIE`, `REJETE`, `EXPIRE`…) → `.verdictRendu`, sans suivi :
    /// jamais « vérification en cours » pour une pièce déjà jugée.
    public var issue: IssueEnvoiDocument {
        switch statutVerification {
        case nil, VerdictDocument.enAttente.rawValue?:
            return verificationAttemptId != nil ? .verificationDemandee(documentId: id) : .enregistre(documentId: id)
        case VerdictDocument.revueManuelleRequise.rawValue?:
            return .enregistre(documentId: id)
        default:
            return .verdictRendu(documentId: id)
        }
    }
}
