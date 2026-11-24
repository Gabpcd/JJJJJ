import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « Realtime » (`Gateways.realtime`), T7a : les flux du monde démo sont ceux de la
    /// messagerie démo du même monde (`DemoMessagerieGateway.diffusion`), si bien qu'un envoi relu fait arriver la
    /// réponse de l'établissement démo sur le flux entrant. Sans messagerie démo (monde partiel) : flux muets.
    static func realtime(_ gateways: Gateways) -> RealtimePort {
        DemoRealtimeGateway(diffusion: (gateways.messagerie as? DemoMessagerieGateway)?.diffusion ?? DemoDiffusionMessagerie())
    }
}

/// Canaux Realtime simulés du monde démo : un sujet par conversation et un pour la liste, comme les canaux
/// `chat-conv-<id>` et `messagerie-liste-<uid>`. Aucun réseau : un canal demandé est abonné aussitôt (`.rejoint`).
/// `fermerTout()` termine tous les flux ; les suivants repartent de canaux neufs.
///
/// `@unchecked Sendable` : tout l'état mutable est protégé par `verrou`, dans des sections synchrones.
public final class DemoDiffusionMessagerie: @unchecked Sendable {
    static let liste = "liste"

    private let verrou = NSLock()
    private var messages: [String: DiffusionEvenements<MessageChat>] = [:]
    private var saisies: [String: DiffusionEvenements<EtatSaisie>] = [:]
    private var presences: [String: DiffusionEtat<EtatPresence>] = [:]
    /// Dernière présence de chaque interlocuteur, gardée d'un canal au suivant.
    private var presencesConnues: [String: EtatPresence] = [:]
    private var etats: [String: DiffusionEtat<EtatCanal>] = [:]
    private var etatsGlobaux = DiffusionEvenements<EtatCanal>()

    public init() {}

    private func dans<Diffusion>(_ registre: inout [String: Diffusion], _ cle: String, _ creer: () -> Diffusion) -> Diffusion {
        if let existante = registre[cle] { return existante }
        let nouvelle = creer()
        registre[cle] = nouvelle
        return nouvelle
    }

    // MARK: - Lecteurs (port Realtime)

    func fluxMessages(_ conversationId: String?) -> AsyncStream<MessageChat> {
        let cle = conversationId ?? Self.liste
        let (flux, etat, globaux) = verrou.withLock {
            (dans(&messages, cle) { DiffusionEvenements() }.flux(), dans(&etats, cle) { DiffusionEtat() }, etatsGlobaux)
        }
        // Canal simulé : abonné sans délai, une fois par canal (un second lecteur le trouve déjà abonné).
        if etat.lire() != .rejoint {
            etat.recevoir(.connexion)
            etat.recevoir(.rejoint)
            globaux.emettre(.rejoint)
        }
        return flux
    }

    func fluxSaisies(_ conversationId: String) -> AsyncStream<EtatSaisie> {
        verrou.withLock { dans(&saisies, conversationId) { DiffusionEvenements() } }.flux()
    }

    func fluxPresence(_ userId: String) -> AsyncStream<EtatPresence> {
        let (diffusion, connue) = verrou.withLock { (dans(&presences, userId) { DiffusionEtat() }, presencesConnues[userId]) }
        // Dernière présence connue servie d'abord (lecture initiale de `presence_status` du web), même après `fermerTout()`.
        if let connue { diffusion.recevoir(connue) }
        return diffusion.flux()
    }

    func fluxEtat(_ conversationId: String?) -> AsyncStream<EtatCanal> {
        verrou.withLock { dans(&etats, conversationId ?? Self.liste) { DiffusionEtat() } }.flux()
    }

    func fluxEtats() -> AsyncStream<EtatCanal> { verrou.withLock { etatsGlobaux }.flux() }

    func fermerTout() {
        let (a, b, c, d, e) = verrou.withLock {
            let tout = (Array(messages.values), Array(saisies.values), Array(presences.values), Array(etats.values), etatsGlobaux)
            messages = [:]; saisies = [:]; presences = [:]; etats = [:]
            etatsGlobaux = DiffusionEvenements()
            return tout
        }
        a.forEach { $0.terminer() }
        b.forEach { $0.terminer() }
        c.forEach { $0.terminer() }
        d.forEach { $0.recevoir(.ferme); $0.terminer() }
        e.terminer()
    }

    // MARK: - Émetteur (messagerie démo)

    /// INSERT `messages_chat` simulé : reçu par le canal du fil et par celui de la liste.
    func emettre(_ message: MessageChat) {
        let (fil, liste) = verrou.withLock { (messages[message.conversationId], messages[Self.liste]) }
        fil?.emettre(message)
        liste?.emettre(message)
    }

    func emettre(saisie: EtatSaisie, conversationId: String) {
        verrou.withLock { saisies[conversationId] }?.emettre(saisie)
    }

    /// Présence d'un interlocuteur : dernier état gardé pour les abonnés à venir (lecture initiale du web).
    func emettre(presence: EtatPresence) {
        let diffusion = verrou.withLock { () -> DiffusionEtat<EtatPresence>? in
            presencesConnues[presence.userId] = presence
            return presences[presence.userId]
        }
        diffusion?.recevoir(presence)
    }
}

/// `RealtimePort` du monde démo (lot 4, T7a ; `LOT4_PLAN.md` §2.7) : aucun réseau, flux alimentés par la messagerie
/// démo. Un flux n'est jamais une preuve d'envoi : la bulle d'un message envoyé vient de sa relecture, et seule la
/// réponse de l'établissement démo arrive par le flux entrant.
public struct DemoRealtimeGateway: RealtimePort {
    private let diffusion: DemoDiffusionMessagerie

    public init(diffusion: DemoDiffusionMessagerie) { self.diffusion = diffusion }

    public func messagesEntrants(conversationId: String?) -> AsyncStream<MessageChat> { diffusion.fluxMessages(conversationId) }
    public func saisies(conversationId: String) -> AsyncStream<EtatSaisie> { diffusion.fluxSaisies(conversationId) }
    public func presence(userId: String) -> AsyncStream<EtatPresence> { diffusion.fluxPresence(userId) }
    public func etat() -> AsyncStream<EtatCanal> { diffusion.fluxEtats() }
    public func etat(conversationId: String?) -> AsyncStream<EtatCanal> { diffusion.fluxEtat(conversationId) }
    public func fermerTout() async { diffusion.fermerTout() }
}
