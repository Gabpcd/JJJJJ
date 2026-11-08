import Foundation

extension DemoFixtures {
    /// `demo-documents.json` (lot 2 T6, blueprint §2.8) : profil documentaire du soignant fictif (IDE MIXTE), exigences
    /// fictives marquées « Exigence de démonstration » (une pièce de santé y figure pour prouver le filtre), pièces de
    /// démonstration (diplôme vérifié, pièce d'identité rejetée malgré une date passée, RCP qui expire dans 12 jours, RIB
    /// expiré). Produit par `scripts/mobile/export-demo-fixtures.mjs`.
    public struct DocumentsFile: Decodable, Sendable {
        public var fixedNow: String
        public var profil: SoignantExigencesDocuments
        public var attestationSanteSigneeLe: String?
        public var exigences: [ExigenceDocument]
        public var documents: [DocumentSoignant]

        enum CodingKeys: String, CodingKey {
            case fixedNow = "fixed_now"
            case profil, exigences, documents
            case attestationSanteSigneeLe = "attestation_sante_signee_le"
        }
    }

    public static func loadDocuments() throws -> DocumentsFile { try load("demo-documents") }
}

/// Valeurs de `-JOLENE_DEMO_SCENARIO` propres aux justificatifs (blueprint §2.8), lues par `AppContainer` (T7).
public enum ScenarioDocumentsDemo: String, CaseIterable, Sendable {
    case normal
    /// Réponse perdue APRÈS application (upload, enregistrement et vérification faits) : l'envoi rend `.incertain`,
    /// la réconciliation relit la ligne, sans second envoi.
    case uploadIncertain = "upload-incertain"
}

/// Justificatifs du monde démo (lot 2 T6) : état en mémoire (perdu au relancement), aucun réseau, horloge fixée, aucun
/// octet conservé (seule la taille d'un objet « stocké » est gardée). Comportement du serveur reproduit : clé contrôlée
/// comme `fn_remplacer_document_soignant`, nouvelle pièce `EN_ATTENTE` qui remplace la preuve active du même type
/// (`trg_10_remplacer_preuves_documentaires_actives`), puis `VERIFIE` à la seconde relecture du dossier ;
/// `verify-document` journalisé (`appelsVerification`). Refuse tout autre utilisateur que le profil fictif (`.demoOnly`).
public actor DemoDocumentsGateway: DocumentsPort {
    private let scenario: ScenarioDocumentsDemo
    private let clock: any ClockPort
    private var etat: EtatDemo?
    /// Clés « stockées » → taille (jamais les octets).
    private var objets: [String: Int] = [:]
    /// Document → relectures du dossier restantes avant le verdict `VERIFIE`.
    private var relecturesAvantVerdict: [String: Int] = [:]
    private var horodatagesDonnes: Int64 = 0
    private var numeroDocument = 0

    /// `document_id` passés à `verify-document`, dans l'ordre (preuve « une seule fois »).
    public private(set) var appelsVerification: [String] = []
    /// Uploads acceptés.
    public private(set) var envois = 0

    private struct EtatDemo {
        var profil: SoignantExigencesDocuments
        var attestation: String?
        var exigences: [ExigenceDocument]
        /// Pièces actives, les plus récentes d'abord.
        var documents: [DocumentSoignant]
    }

    public init(scenario: ScenarioDocumentsDemo = .normal, clock: any ClockPort = FixedClock(DemoWorld.fixedNow)) {
        self.scenario = scenario
        self.clock = clock
    }

    // MARK: - Lecture

    public func dossier(context: MissionReadContext) async throws -> DossierDocuments {
        var etat = try charger(context)
        for (id, restantes) in relecturesAvantVerdict {
            if restantes <= 1 {
                relecturesAvantVerdict[id] = nil
                if let index = etat.documents.firstIndex(where: { $0.id == id }) {
                    etat.documents[index].statutVerification = VerdictDocument.verifie.rawValue
                    etat.documents[index].motifRejet = nil
                }
            } else {
                relecturesAvantVerdict[id] = restantes - 1
            }
        }
        self.etat = etat
        return DossierDocuments.assembler(profil: etat.profil, regles: etat.exigences, documents: etat.documents,
                                          attestationSanteSigneeLe: etat.attestation)
    }

    // MARK: - Envoi

    public func preparerEnvoi(type: String, fichier: FichierChoisi, libelle: String?, context: MissionReadContext) async throws -> RecuDocument {
        _ = try charger(context)
        guard !ExigencesDocuments.typesDocumentsExclusUpload.contains(type) else { throw RecuErreur.champInvalide("typeDocument") }
        // Horloge fixée : une milliseconde de plus à chaque préparation, pour que deux envois n'aient jamais la même clé.
        horodatagesDonnes += 1
        let horodatage = Int64(clock.now().timeIntervalSince1970 * 1_000) + horodatagesDonnes
        return try RecuDocument.preparer(userId: context.userId, epoch: 0, typeDocument: type, fichier: fichier,
                                         libelle: libelle, horodatageMs: horodatage)
    }

    public func envoyer(recu: RecuDocument, octets: Data, context: MissionReadContext) async throws -> IssueEnvoiDocument {
        _ = try charger(context)
        try Self.verifierEnvoi(recu, octets: octets, context: context)
        guard objets[recu.s3Cle] == nil else { return .incertain } // `upsert: false` : la clé est déjà prise
        objets[recu.s3Cle] = octets.count
        envois += 1
        let issue = enregistrerPuisVerifier(recu)
        return scenario == .uploadIncertain ? .incertain : issue
    }

    public func reconcilier(recu: RecuDocument, context: MissionReadContext) async throws -> IssueEnvoiDocument {
        let etat = try charger(context)
        guard recu.userId == context.userId else { throw RecuErreur.utilisateurDifferent }
        guard recu.phase != .prepared else { return .nonEnvoye }
        if let ligne = etat.documents.first(where: { $0.s3Cle == recu.s3Cle }) {
            return PreuveDocument(id: ligne.id, s3Cle: recu.s3Cle, statutVerification: ligne.statutVerification,
                                  verificationAttemptId: ligne.verificationAttemptId).issue
        }
        guard objets[recu.s3Cle] != nil else { return .nonEnvoye }
        return enregistrerPuisVerifier(recu)
    }

    // MARK: - Actions sur une pièce

    public func reverifier(documentId: String, context: MissionReadContext) async throws -> VerdictDocument {
        var etat = try charger(context)
        guard let index = etat.documents.firstIndex(where: { $0.id == documentId }) else {
            throw JoleneError(.unknown, MessagesDocuments.verificationImpossible)
        }
        lancerVerification(&etat.documents[index])
        self.etat = etat
        return .enAttente
    }

    public func demanderRevue(documentId: String, context: MissionReadContext) async throws {
        var etat = try charger(context)
        guard let index = etat.documents.firstIndex(where: { $0.id == documentId }) else {
            throw JoleneError(.unknown, MessagesDocuments.revueDocumentIntrouvable)
        }
        // Effets de `fn_demander_revue_document` (l.30066-30076), message serveur repris tel quel.
        etat.documents[index].statutVerification = VerdictDocument.revueManuelleRequise.rawValue
        etat.documents[index].motifRejet = "Demande transmise — en attente d'attribution à un membre de l'équipe."
        etat.documents[index].verificationAttemptId = nil
        relecturesAvantVerdict[documentId] = nil
        self.etat = etat
    }

    public func consulter(document: DocumentSoignant, context: MissionReadContext) async throws -> URL {
        let etat = try charger(context)
        guard etat.documents.contains(where: { $0.id == document.id }) else {
            throw JoleneError(.unknown, MessagesDocuments.consultationImpossible)
        }
        return try ConsultationDocuments.ecrire(Self.pdfDemonstration, nomFichier: document.nomFichier)
    }

    public func signerAttestationSante(context: MissionReadContext) async throws -> Date {
        var etat = try charger(context)
        etat.attestation = Self.iso(clock.now())
        self.etat = etat
        // Relecture de la valeur stockée, jamais l'horloge supposée.
        guard let relue = self.etat?.attestation, let date = try? DateHeureParis.instantJolene(relue) else {
            throw JoleneError(.unknown, MessagesDocuments.signatureAttestationErreur)
        }
        return date
    }

    public func coherence(context: MissionReadContext) async throws -> CoherenceDocuments? {
        _ = try charger(context)
        return CoherenceDocuments(coherent: true, problemes: [])
    }

    // MARK: - Interne

    private func charger(_ context: MissionReadContext) throws -> EtatDemo {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
        if let etat { return etat }
        let fichier = try DemoFixtures.loadDocuments()
        let neuf = EtatDemo(profil: fichier.profil, attestation: fichier.attestationSanteSigneeLe, exigences: fichier.exigences,
                            documents: fichier.documents)
        etat = neuf
        return neuf
    }

    /// Mêmes contrôles que la gateway Supabase, avant tout « upload ».
    static func verifierEnvoi(_ recu: RecuDocument, octets: Data, context: MissionReadContext) throws {
        guard recu.userId == context.userId else { throw RecuErreur.utilisateurDifferent }
        guard recu.phase == .started else { throw RecuErreur.transitionInterdite(de: recu.phase.rawValue, vers: RecuDocument.Phase.stored.rawValue) }
        guard octets.count == recu.tailleOctets else { throw RecuErreur.champInvalide("tailleOctets") }
    }

    /// `fn_remplacer_document_soignant` (idempotente sur la clé) puis `verify-document` une fois.
    private func enregistrerPuisVerifier(_ recu: RecuDocument) -> IssueEnvoiDocument {
        guard var etat else { return .incertain }
        guard RecuDocument.cleValide(recu.s3Cle, userId: recu.userId, typeDocument: recu.typeDocument) else {
            objets[recu.s3Cle] = nil // cleanup_orphan
            return .refuse(code: "CHEMIN_DOCUMENT_INVALIDE")
        }
        if let existant = etat.documents.first(where: { $0.s3Cle == recu.s3Cle }) {
            return PreuveDocument(id: existant.id, s3Cle: recu.s3Cle, statutVerification: existant.statutVerification,
                                  verificationAttemptId: existant.verificationAttemptId).issue
        }
        numeroDocument += 1
        var ligne = DocumentSoignant(id: "demo-doc-envoi-\(numeroDocument)", typeDocument: recu.typeDocument, libelle: recu.libelle,
                                     s3Cle: recu.s3Cle, nomFichier: recu.nomFichier, typeMime: recu.mime.rawValue,
                                     tailleOctets: recu.tailleOctets, statutVerification: "EN_ATTENTE",
                                     televerseLe: Self.iso(clock.now()), estCritique: nil)
        lancerVerification(&ligne)
        // Remplacement de la preuve active du même type par le serveur.
        etat.documents.removeAll { $0.typeDocument == recu.typeDocument }
        etat.documents.insert(ligne, at: 0)
        self.etat = etat
        return .verificationDemandee(documentId: ligne.id)
    }

    private func lancerVerification(_ document: inout DocumentSoignant) {
        appelsVerification.append(document.id)
        document.statutVerification = VerdictDocument.enAttente.rawValue
        document.verificationAttemptId = "demo-tentative-\(appelsVerification.count)"
        relecturesAvantVerdict[document.id] = 2
    }

    static func iso(_ date: Date) -> String {
        let formateur = ISO8601DateFormatter()
        formateur.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formateur.timeZone = TimeZone(secondsFromGMT: 0)
        return formateur.string(from: date)
    }

    /// PDF d'une page vide, seul contenu servi par la démo à la consultation.
    static let pdfDemonstration = Data("%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 72 72]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n".utf8)
}
