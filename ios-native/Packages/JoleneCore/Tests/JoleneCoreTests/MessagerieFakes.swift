import Foundation
import XCTest
@testable import JoleneCore

// Doubles de la messagerie du lot 4 (T7a), partagés par `FilModelTests`, `ConversationsModelTests` et
// `RealtimeLifecycleTests` : un journal commun donne l'ordre global des appels entre le port de messagerie et le port
// Realtime (« flux déclarés → abonnement → battement de présence »).

/// Journal d'appels partagé entre plusieurs doubles (ordre global).
final class JournalAppels: @unchecked Sendable {
    private let verrou = NSLock()
    private var entrees: [String] = []

    func noter(_ entree: String) { verrou.withLock { entrees.append(entree) } }
    var appels: [String] { verrou.withLock { entrees } }
    func nombre(_ prefixe: String) -> Int { appels.filter { $0.hasPrefix(prefixe) }.count }
    func index(_ prefixe: String) -> Int? { appels.firstIndex { $0.hasPrefix(prefixe) } }
    func dernierIndex(_ prefixe: String) -> Int? { appels.lastIndex { $0.hasPrefix(prefixe) } }
    func vider() { verrou.withLock { entrees.removeAll() } }
}

/// Port Realtime factice : un canal par sujet (`liste`, ou l'identifiant de la conversation), émissions commandées par
/// le test. `fermerTout()` termine tous les flux, comme `removeAllChannels()`.
final class RealtimeFactice: RealtimePort, @unchecked Sendable {
    static let liste = "liste"

    let journal: JournalAppels
    /// Vrai : le canal d'un flux de messages demandé est abonné aussitôt (`.rejoint`) ; faux : le test l'abonne.
    var rejointImmediat = true
    private let verrou = NSLock()
    private var entrants: [String: DiffusionEvenements<MessageChat>] = [:]
    private var saisiesParFil: [String: DiffusionEvenements<EtatSaisie>] = [:]
    private var presences: [String: DiffusionEvenements<EtatPresence>] = [:]
    private var etats: [String: DiffusionDernierEtat<EtatCanal>] = [:]
    private var etatsGlobaux = DiffusionEvenements<EtatCanal>()

    init(journal: JournalAppels = JournalAppels()) { self.journal = journal }

    private func diffusion<V>(_ registre: inout [String: DiffusionEvenements<V>], _ cle: String) -> DiffusionEvenements<V> {
        if let existante = registre[cle] { return existante }
        let nouvelle = DiffusionEvenements<V>()
        registre[cle] = nouvelle
        return nouvelle
    }

    private func diffusionEtat(_ cle: String) -> DiffusionDernierEtat<EtatCanal> {
        verrou.withLock {
            if let existante = etats[cle] { return existante }
            let nouvelle = DiffusionDernierEtat<EtatCanal>()
            etats[cle] = nouvelle
            return nouvelle
        }
    }

    // MARK: - RealtimePort

    func messagesEntrants(conversationId: String?) -> AsyncStream<MessageChat> {
        let cle = conversationId ?? Self.liste
        journal.noter("flux messages \(cle)")
        let flux = verrou.withLock { diffusion(&entrants, cle) }.flux()
        if rejointImmediat { etatCanal(.rejoint, conversationId: conversationId) }
        return flux
    }

    func saisies(conversationId: String) -> AsyncStream<EtatSaisie> {
        journal.noter("flux saisies \(conversationId)")
        return verrou.withLock { diffusion(&saisiesParFil, conversationId) }.flux()
    }

    func presence(userId: String) -> AsyncStream<EtatPresence> {
        journal.noter("flux presence \(userId)")
        return verrou.withLock { diffusion(&presences, userId) }.flux()
    }

    func etat() -> AsyncStream<EtatCanal> { verrou.withLock { etatsGlobaux }.flux() }

    func etat(conversationId: String?) -> AsyncStream<EtatCanal> {
        diffusionEtat(conversationId ?? Self.liste).flux()
    }

    func fermerTout() async {
        journal.noter("fermerTout")
        let (a, b, c, d, e) = verrou.withLock {
            let tout = (Array(entrants.values), Array(saisiesParFil.values), Array(presences.values), Array(etats.values), etatsGlobaux)
            entrants = [:]; saisiesParFil = [:]; presences = [:]; etats = [:]; etatsGlobaux = DiffusionEvenements<EtatCanal>()
            return tout
        }
        a.forEach { $0.terminer() }; b.forEach { $0.terminer() }; c.forEach { $0.terminer() }; d.forEach { $0.terminer() }
        e.terminer()
    }

    // MARK: - Commandes du test

    /// INSERT `messages_chat` : reçu par le canal du fil et par celui de la liste.
    func emettre(_ message: MessageChat) {
        let (fil, liste) = verrou.withLock { (entrants[message.conversationId], entrants[Self.liste]) }
        fil?.emettre(message)
        liste?.emettre(message)
    }

    func etatCanal(_ etat: EtatCanal, conversationId: String?) {
        let cle = conversationId ?? Self.liste
        journal.noter("canal \(cle) \(etat)")
        diffusionEtat(cle).recevoir(etat)
        verrou.withLock { etatsGlobaux }.emettre(etat)
    }

    func emettre(saisie: EtatSaisie, conversationId: String) {
        verrou.withLock { saisiesParFil[conversationId] }?.emettre(saisie)
    }

    func emettre(presence: EtatPresence) {
        verrou.withLock { presences[presence.userId] }?.emettre(presence)
    }

    /// Lecteurs du flux de messages d'un sujet (preuve qu'un modèle écoute, ou qu'il a cessé).
    func lecteurs(_ conversationId: String?) -> Int {
        verrou.withLock { entrants[conversationId ?? Self.liste] }?.nombreAbonnes ?? 0
    }
}

/// Port de messagerie factice, scripté par le test ; chaque appel est journalisé (sans le contenu des messages).
final class MessagerieFactice: MessageriePort, @unchecked Sendable {
    let journal: JournalAppels
    private let verrou = NSLock()
    private var pagesServies: [PageConversations] = []
    private var filServi: [MessageChat] = []
    private var nonLusServis: [Int] = [0]
    var interlocuteursServis: [Interlocuteur] = []
    var envoi: @Sendable (String) async throws -> EnvoiOutcome = { _ in .nonConfirme }
    var lecture: @Sendable () async throws -> IssueLecture = { .lus }
    /// Appelé avant de rendre une page de conversations (erreur ou barrière).
    var avantPage: @Sendable () async throws -> Void = {}
    /// Page calculée depuis le curseur reçu (remplace `pages`).
    var servirPage: (@Sendable (CurseurConversations?) -> PageConversations)?
    /// Appelé avant de rendre le fil (erreur ou barrière).
    var avantFil: @Sendable () async throws -> Void = {}
    var avantInterlocuteurs: @Sendable () async throws -> Void = {}
    var avantMessageParId: @Sendable () async throws -> Void = {}

    init(journal: JournalAppels = JournalAppels()) { self.journal = journal }

    var pages: [PageConversations] {
        get { verrou.withLock { pagesServies } }
        set { verrou.withLock { pagesServies = newValue } }
    }
    var fil: [MessageChat] {
        get { verrou.withLock { filServi } }
        set { verrou.withLock { filServi = newValue } }
    }
    /// Valeurs successives de `fn_messages_non_lus` ; la dernière est répétée.
    var nonLusSuccessifs: [Int] {
        get { verrou.withLock { nonLusServis } }
        set { verrou.withLock { nonLusServis = newValue } }
    }

    func conversations(avant: CurseurConversations?, context: MissionReadContext) async throws -> PageConversations {
        journal.noter("conversations \(avant.map { "\($0.ordreLe)|\($0.id)" } ?? "debut")")
        try await avantPage()
        if let servirPage { return servirPage(avant) }
        return verrou.withLock {
            guard !pagesServies.isEmpty else { return PageConversations(conversations: [], suivant: nil) }
            guard let avant else { return pagesServies[0] }
            let index = pagesServies.firstIndex { $0.suivant == avant }.map { $0 + 1 } ?? pagesServies.count
            return index < pagesServies.count ? pagesServies[index] : PageConversations(conversations: [], suivant: nil)
        }
    }

    func interlocuteurs(ids: [String], context: MissionReadContext) async throws -> [Interlocuteur] {
        journal.noter("interlocuteurs \(ids.count)")
        try await avantInterlocuteurs()
        return interlocuteursServis.filter { ids.contains($0.conversationId) }
    }

    func messages(conversationId: String, context: MissionReadContext) async throws -> [MessageChat] {
        journal.noter("messages \(conversationId)")
        try await avantFil()
        return fil.filter { $0.conversationId == conversationId }
    }

    func messages(conversationId: String, depuis: String, context: MissionReadContext) async throws -> [MessageChat] {
        journal.noter("messages \(conversationId) depuis \(depuis)")
        try await avantFil()
        return fil.filter { $0.conversationId == conversationId && FilMessages.pasAvant($0, depuis) }
    }

    func envoyer(conversationId: String, contenu: String, context: MissionReadContext) async throws -> EnvoiOutcome {
        journal.noter("envoyer \(conversationId)")
        return try await envoi(contenu)
    }

    func message(id: String, conversationId: String, context: MissionReadContext) async throws -> MessageChat? {
        journal.noter("message \(id)")
        try await avantMessageParId()
        return fil.first { $0.id == id && $0.conversationId == conversationId }
    }

    func marquerLus(conversationId: String, context: MissionReadContext) async throws -> IssueLecture {
        journal.noter("marquerLus \(conversationId)")
        return try await lecture()
    }

    func saisie(debut: Bool, conversationId: String, context: MissionReadContext) async throws {
        journal.noter("saisie \(debut ? "debut" : "fin") \(conversationId)")
    }

    func presence(context: MissionReadContext) async throws { journal.noter("presence") }

    func bloque(cibleId: String, context: MissionReadContext) async throws -> Bool { false }

    func basculerBlocage(cibleId: String, bloquer: Bool, context: MissionReadContext) async throws -> Bool { bloquer }

    func signaler(cibleId: String, type: TypeCibleSignalement, categorie: String, motif: String, missionId: String?,
                  context: MissionReadContext) async throws -> IssueSignalement { .signale }

    func nonLus(context: MissionReadContext) async throws -> Int {
        journal.noter("nonLus")
        return verrou.withLock {
            let valeur = nonLusServis.first ?? 0
            if nonLusServis.count > 1 { nonLusServis.removeFirst() }
            return valeur
        }
    }

    func conversationPourMission(missionId: String, etablissementId: String,
                                 context: MissionReadContext) async throws -> IssueConversationMission {
        .conversation(id: "c-\(missionId)")
    }
}

/// Session soignant prête pour les modèles de la messagerie (identité `u-1`).
enum SessionMessagerie {
    static let moi = "u-1"

    struct AuthPrete: AuthPort {
        var presente: @Sendable () async -> Bool = { true }
        var userId = SessionMessagerie.moi
        func restoreSession() async throws -> AuthenticatedUser? {
            guard await presente() else { return nil }
            return AuthenticatedUser(id: userId, email: "\(userId)@example.invalid",
                                     emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000), appMetadataRole: "SOIGNANT")
        }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser {
            AuthenticatedUser(id: userId, email: email, emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                              appMetadataRole: "SOIGNANT")
        }
        func signOut() async throws {}
    }

    struct Missions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    static func gateways(messagerie: MessageriePort, realtime: RealtimePort) -> Gateways {
        var gateways = Lot1Fakes.gateways(clock: FixedClock(DemoWorld.fixedNow))
        gateways.auth = AuthPrete()
        gateways.missions = Missions()
        gateways.messagerie = messagerie
        gateways.realtime = realtime
        return gateways
    }

    /// Contrôleur démarré et instantané de la session prête.
    static func prete(messagerie: MessageriePort, realtime: RealtimePort,
                      timeout: TimeInterval = SessionController.defaultResolutionTimeout,
                      file: StaticString = #filePath, line: UInt = #line) async throws -> (SessionController, SessionSnapshot) {
        let controller = SessionController(gateways: gateways(messagerie: messagerie, realtime: realtime), resolutionTimeout: timeout)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)", file: file, line: line)
        return (controller, snapshot)
    }

    static func message(_ id: String, conversation: String = "c-1", auteur: String = "etab-user", contenu: String = "Bonjour",
                        creeLe: String = "2026-11-02T10:00:00.000000+00:00") -> MessageChat {
        MessageChat(id: id, conversationId: conversation, auteurId: auteur, contenu: contenu, creeLe: creeLe)
    }
}
