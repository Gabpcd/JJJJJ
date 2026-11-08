import Combine
import Foundation

/// Modèle des justificatifs (lot 2 T6, blueprint §2.5 « Justificatif », décision 14). Données et pipeline d'envoi ;
/// l'écran (T7) ne fait que lire ces états et traduire les issues en textes.
///
/// - Lecture : dossier relu sous l'epoch de la session, borné à `SessionController.resolutionTimeout` ; cohérence des
///   noms en best-effort (le web avale l'erreur) ; un reçu laissé par un essai précédent est réconcilié AVANT la lecture.
/// - Envoi, un seul à la fois : reçu `prepared` puis `started` journalisés (`ReceiptJournal<RecuDocument>`, domaine
///   `document`) AVANT l'unique upload ; issue relue par la gateway ; reçu effacé après un succès, un refus ou un
///   « non envoyé » ; gardé `started` sur une issue incertaine, réconciliée aussitôt puis à chaque chargement — jamais
///   de renvoi, ni de l'upload ni de `verify-document`. Aucun octet n'est conservé.
/// - Verdict en ligne : relecture du dossier toutes les 5 s pendant 60 s au plus (`DocumentsSoignant.tsx` l.250-255),
///   arrêtée dès que la pièce quitte `EN_ATTENTE` ; un verdict `VERIFIE` enchaîne sur la prochaine exigence critique
///   (`exigenceSuivante`) ou signale un dossier complet (l.258-276).
/// - Journal illisible (`RecuErreur.illisible`) : envoi bloqué, reçu jamais réécrit ni effacé, renvoi web
///   `renvoiWeb` (consigne T6 de `docs/mobile-swift/DECISIONS_LOT2.md`).
@MainActor
public final class DocumentsModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case charge(DossierDocuments)
        case echec(String)
    }

    public enum EtatEnvoi: Equatable, Sendable {
        case inactif
        case enCours(typeDocument: String)
        /// Issue relue (T7 la traduit avec les messages du web).
        case termine(IssueEnvoiDocument)
        /// Refusé avant tout reçu et tout envoi (fichier, type non proposé).
        case refuseAvantEnvoi(message: String)
        /// Un reçu d'un autre essai reste à réconcilier : aucun nouvel envoi.
        case recuEnCours
        /// Journal de reçus illisible : envoi bloqué, renvoi web (`renvoiWeb`).
        case suiviIllisible
        /// Erreur de transport ou de session avant l'issue ; le reçu `started` éventuel reste journalisé.
        case erreur(String)
    }

    public static let intervalleSuivi: TimeInterval = 5
    public static let dureeSuivi: TimeInterval = 60
    /// Voie de récupération d'un journal illisible : l'envoi web n'utilise pas ce journal.
    public static let renvoiWeb = "/soignant/mes-documents?tab=justificatifs"
    /// Code de refus restitué pour un nom ou un libellé hors bornes (message du web, `DocumentsSoignant.tsx` l.400-402).
    public static let codeMetadonneesInvalides = "METADONNEES_DOCUMENT_INVALIDES"

    @Published public private(set) var etat: Etat = .chargement
    @Published public private(set) var envoi: EtatEnvoi = .inactif
    /// Pièces dont le verdict est attendu en ligne.
    @Published public private(set) var enVerification: Set<String> = []
    @Published public private(set) var coherence: CoherenceDocuments?
    /// Exigence à proposer après un verdict `VERIFIE` (l.272-274) ; l'écran l'oublie quand il l'ouvre.
    @Published public private(set) var exigenceSuivante: String?
    /// Toutes les pièces critiques sont valides après un verdict (l.266-270).
    @Published public private(set) var dossierComplet = false
    @Published public private(set) var sessionExpired = false
    /// Pièce visée par une action en cours (revérification, revue, consultation) ; « attestation » pour la signature.
    @Published public private(set) var actionEnCours: String?
    /// Dernier refus d'une action (message du web ou du serveur).
    @Published public private(set) var messageAction: String?

    /// Horloge des gateways de la session (démo : horloge fixée).
    public private(set) var horloge: any ClockPort = SystemClock()

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private let journal: ReceiptJournal<RecuDocument>
    private let attendre: @Sendable (TimeInterval) async throws -> Void
    private var generation = 0
    private var suivi: Task<Void, Never>?

    public init(controller: SessionController, snapshot: SessionSnapshot, recus: any ReceiptStorePort,
                attendre: @escaping @Sendable (TimeInterval) async throws -> Void = { try await DocumentsModel.attendreParDefaut($0) }) {
        self.controller = controller
        self.snapshot = snapshot
        self.journal = ReceiptJournal<RecuDocument>(store: recus)
        self.attendre = attendre
    }

    public nonisolated static func attendreParDefaut(_ secondes: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, secondes) * 1_000_000_000))
    }

    public var dossier: DossierDocuments? {
        if case let .charge(dossier) = etat { return dossier }
        return nil
    }

    // MARK: - Chargement

    public func charger() async {
        guard let gateways = await gatewaysCourantes() else { return }
        horloge = gateways.clock
        if dossier == nil { etat = .chargement }
        await reconcilierEnAttente(gateways)
        await relireDossier(gateways, signalerEchec: true)
        guard let dossier, !dossier.documents.isEmpty else { return }
        let port = gateways.documents
        let context = snapshot.context
        let lue = try? await bounded(timeout: controller.resolutionTimeout) { try await port.coherence(context: context) }
        guard await controller.epoch == snapshot.epoch else { return }
        coherence = lue
    }

    // MARK: - Envoi

    /// Envoie un fichier préparé (`FichierDocument.preparer`) pour une exigence affichée. Un seul envoi à la fois : un
    /// geste pendant un envoi est ignoré.
    public func envoyer(typeDocument: String, fichier: FichierPret, libelle: String?) async {
        if case .enCours = envoi { return }
        if envoi == .suiviIllisible { return }
        guard let dossier, dossier.peutEnvoyer(typeDocument: typeDocument) else {
            envoi = .refuseAvantEnvoi(message: MessagesDocuments.enregistrementImpossible)
            return
        }
        envoi = .enCours(typeDocument: typeDocument)
        guard let gateways = await gatewaysCourantes() else { envoi = .inactif; return }
        let port = gateways.documents
        let context = snapshot.context
        let delai = controller.resolutionTimeout

        // 1. Un reçu d'un essai précédent est réconcilié d'abord ; tant qu'il reste en vol, aucun nouvel envoi.
        guard await reconcilierEnAttente(gateways) else {
            if envoi != .suiviIllisible { envoi = .recuEnCours }
            return
        }
        envoi = .enCours(typeDocument: typeDocument)

        // 2. Reçu `prepared` à la clé déterministe, daté de l'epoch de cet écran.
        let libelleSaisi = libelle.flatMap { $0.isEmpty ? nil : $0 }
        var recu: RecuDocument
        do {
            recu = try await bounded(timeout: delai) {
                try await port.preparerEnvoi(type: typeDocument, fichier: fichier.fichier, libelle: libelleSaisi, context: context)
            }
            recu.epoch = snapshot.epoch
            try recu.valider()
        } catch let erreur as RecuErreur {
            envoi = erreur == .illisible ? .suiviIllisible : .termine(.refuse(code: Self.codeMetadonneesInvalides))
            return
        } catch {
            envoi = .erreur(message(de: error))
            return
        }
        guard await controller.epoch == snapshot.epoch else { envoi = .inactif; return }

        // 3. Journal AVANT l'upload : `prepared`, puis `started` juste avant l'unique requête.
        do {
            try await journal.ecrire(recu)
            recu = try recu.demarrer()
            try await journal.ecrire(recu)
        } catch RecuErreur.recuEnCours {
            envoi = .recuEnCours
            return
        } catch {
            envoi = .suiviIllisible
            return
        }

        // 4. Une seule requête d'envoi ; transport incertain → réconciliation immédiate par relecture.
        var issue: IssueEnvoiDocument
        do {
            let demarre = recu
            issue = try await bounded(timeout: delai) { try await port.envoyer(recu: demarre, octets: fichier.octets, context: context) }
        } catch let erreur as JoleneError where erreur.kind == .unauthorized {
            sessionExpired = true
            envoi = .erreur(erreur.message)
            return
        } catch {
            // Délai, transport, reçu refusé par les contrôles de la gateway : rien ne prouve l'absence d'effet.
            issue = .incertain
        }
        if issue == .incertain {
            issue = await reconcilier(recu, gateways: gateways) ?? .incertain
        }
        await terminer(recu, issue: issue, gateways: gateways)
    }

    /// Attend la fin du suivi de vérification en cours (tests, fermeture de l'écran).
    public func attendreFinDuSuivi() async {
        await suivi?.value
    }

    public func oublierExigenceSuivante() {
        exigenceSuivante = nil
    }

    // MARK: - Actions sur une pièce

    /// « Revérifier » : geste manuel seulement (jamais automatique, l.297-332), puis relecture du dossier.
    public func reverifier(documentId: String) async -> VerdictDocument? {
        await action(documentId) { port, context in
            try await port.reverifier(documentId: documentId, context: context)
        }
    }

    /// « Demander une revue humaine » (l.336-358), puis relecture.
    public func demanderRevue(documentId: String) async -> Bool {
        await action(documentId) { port, context in
            try await port.demanderRevue(documentId: documentId, context: context)
        } != nil
    }

    /// Signature de l'attestation santé : valeur serveur relue par la gateway, puis relecture du dossier.
    public func signerAttestation() async -> Bool {
        await action("attestation") { port, context in
            _ = try await port.signerAttestationSante(context: context)
        } != nil
    }

    /// Copie temporaire protégée de la pièce (QuickLook, T7) ; jamais une URL distante.
    public func consulter(_ document: DocumentSoignant) async -> URL? {
        await action(document.id, relire: false) { port, context in
            try await port.consulter(document: document, context: context)
        }
    }

    // MARK: - Interne

    private func gatewaysCourantes() async -> Gateways? {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return nil }
        guard await controller.epoch == snapshot.epoch else { return nil }
        return gateways
    }

    /// Relit le dossier ; un échec n'efface jamais un dossier déjà affiché (seul le premier chargement échoue).
    private func relireDossier(_ gateways: Gateways, signalerEchec: Bool) async {
        generation += 1
        let courant = generation
        let port = gateways.documents
        let context = snapshot.context
        do {
            let lu = try await bounded(timeout: controller.resolutionTimeout) { try await port.dossier(context: context) }
            guard await controller.epoch == snapshot.epoch, generation == courant else { return }
            sessionExpired = false
            etat = .charge(lu)
        } catch {
            guard await controller.epoch == snapshot.epoch, generation == courant, !estAnnulation(error) else { return }
            if let jolene = error as? JoleneError, jolene.kind == .unauthorized { sessionExpired = true }
            if signalerEchec, dossier == nil { etat = .echec(message(de: error)) }
        }
    }

    /// Réconcilie le reçu en attente ; vrai si plus rien n'est en vol. `prepared` : rien n'est parti (sortie sûre
    /// `not_sent`, aucun appel) ; terminé : effacé ; sinon relecture serveur, jamais de renvoi.
    @discardableResult
    private func reconcilierEnAttente(_ gateways: Gateways) async -> Bool {
        let enAttente: RecuDocument?
        do {
            enAttente = try await journal.lire(userId: snapshot.context.userId)
        } catch {
            envoi = .suiviIllisible
            return false
        }
        guard let recu = enAttente else { return true }
        if recu.estTermine || recu.phase == .prepared {
            do {
                if recu.phase == .prepared { try await journal.ecrire(try recu.marquerNonEnvoye()) }
                try await journal.effacer(recu)
            } catch {
                envoi = .suiviIllisible
                return false
            }
            return true
        }
        guard let issue = await reconcilier(recu, gateways: gateways) else { return false }
        await terminer(recu, issue: issue, gateways: gateways)
        return issue != .incertain
    }

    /// Une relecture par la gateway ; nil si elle n'a pas pu avoir lieu (transport, délai).
    private func reconcilier(_ recu: RecuDocument, gateways: Gateways) async -> IssueEnvoiDocument? {
        let port = gateways.documents
        let context = snapshot.context
        do {
            return try await bounded(timeout: controller.resolutionTimeout) { try await port.reconcilier(recu: recu, context: context) }
        } catch let erreur as JoleneError where erreur.kind == .unauthorized {
            sessionExpired = true
            return nil
        } catch {
            return nil
        }
    }

    /// Issue relue : reçu effacé sauf issue incertaine (gardé `started`), dossier relu, suivi du verdict.
    private func terminer(_ recu: RecuDocument, issue: IssueEnvoiDocument, gateways: Gateways) async {
        if issue != .incertain {
            do {
                try await journal.effacer(recu)
            } catch {
                envoi = .suiviIllisible
                return
            }
        }
        guard await controller.epoch == snapshot.epoch else { return }
        envoi = .termine(issue)
        guard issue != .incertain else { return }
        await relireDossier(gateways, signalerEchec: false)
        if case let .verificationDemandee(documentId) = issue {
            suivre(documentId)
        }
    }

    private func suivre(_ documentId: String) {
        enVerification.insert(documentId)
        guard suivi == nil else { return }
        suivi = Task { [weak self] in
            await self?.boucleSuivi()
            self?.suivi = nil
        }
    }

    /// Relecture toutes les 5 s pendant 60 s au plus, tant qu'une pièce suivie est `EN_ATTENTE`.
    private func boucleSuivi() async {
        var ecoule: TimeInterval = 0
        while !enVerification.isEmpty, ecoule < Self.dureeSuivi {
            do { try await attendre(Self.intervalleSuivi) } catch { break }
            ecoule += Self.intervalleSuivi
            guard let gateways = await gatewaysCourantes() else { break }
            await relireDossier(gateways, signalerEchec: false)
            guard let dossier else { continue }
            let termines = dossier.documents.filter { enVerification.contains($0.id) && $0.statutVerification != "EN_ATTENTE" }
            guard !termines.isEmpty else { continue }
            enVerification.subtract(termines.map(\.id))
            if termines.contains(where: { $0.statutVerification == VerdictDocument.verifie.rawValue }) {
                if let prochaine = dossier.prochaineExigence(maintenant: horloge.now()) {
                    exigenceSuivante = exigenceSuivante ?? prochaine.typeDocument
                } else {
                    dossierComplet = true
                }
            }
        }
        enVerification = []
    }

    /// Action ponctuelle : une requête bornée, refus affiché (`messageAction`), relecture du dossier après succès.
    private func action<T: Sendable>(_ cible: String, relire: Bool = true,
                                     _ appel: @escaping @Sendable (any DocumentsPort, MissionReadContext) async throws -> T) async -> T? {
        guard actionEnCours == nil, let gateways = await gatewaysCourantes() else { return nil }
        actionEnCours = cible
        messageAction = nil
        defer { actionEnCours = nil }
        let port = gateways.documents
        let context = snapshot.context
        do {
            let resultat = try await bounded(timeout: controller.resolutionTimeout) { try await appel(port, context) }
            guard await controller.epoch == snapshot.epoch else { return nil }
            if relire { await relireDossier(gateways, signalerEchec: false) }
            return resultat
        } catch {
            guard await controller.epoch == snapshot.epoch, !estAnnulation(error) else { return nil }
            if let jolene = error as? JoleneError, jolene.kind == .unauthorized { sessionExpired = true }
            messageAction = message(de: error)
            return nil
        }
    }

    private func message(de error: Error) -> String {
        if let jolene = error as? JoleneError { return jolene.message }
        return MessagesDocuments.erreurGenerique
    }

    private func estAnnulation(_ error: Error) -> Bool {
        error is CancellationError || (error as? JoleneError)?.kind == .cancelled
    }
}
