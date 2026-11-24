import Foundation

// Règles pures de la messagerie (lot 4, T7a ; `LOT4_PLAN.md` §2.5 « Messagerie Realtime »), portées de
// `src/pages/PageMessagerie.tsx` : fusion du fil par id, ordre par `cree_le`, aperçu de la liste après un INSERT reçu.
// Aucun texte, aucun appel : les modèles (`FilModel`, `ConversationsModel`) les appliquent aux réponses des ports.

/// Fil d'une conversation : fusion par id et ordre (web : `Map` par id puis tri par `cree_le`).
public enum FilMessages {
    /// Messages lus à l'ouverture d'un fil, comme le web (`.order('cree_le', desc).limit(500)`).
    public static let limite = 500

    /// Ordre du fil : `cree_le` croissant (instant, puis valeur servie pour départager une même milliseconde), puis
    /// id ; un message sans date lisible passe en fin de fil.
    public static func avant(_ a: MessageChat, _ b: MessageChat) -> Bool {
        switch (a.instant, b.instant) {
        case let (x?, y?) where x != y: return x < y
        case (nil, _?): return false
        case (_?, nil): return true
        default: break
        }
        if let ca = a.creeLe, let cb = b.creeLe, ca != cb { return ca < cb }
        return a.id < b.id
    }

    /// Fusion par id : un message reçu ou relu remplace celui du même id, jamais un doublon ; les messages d'une autre
    /// conversation sont écartés ; résultat dans l'ordre du fil.
    public static func fusionner(_ courants: [MessageChat], _ nouveaux: [MessageChat], conversationId: String) -> [MessageChat] {
        var parId: [String: MessageChat] = [:]
        for message in courants + nouveaux where message.conversationId == conversationId { parId[message.id] = message }
        return parId.values.sorted(by: avant)
    }

    /// `cree_le` (valeur servie) du dernier message daté du fil : point de départ de la relecture après « rejoint ».
    public static func dernierCreeLe(_ messages: [MessageChat]) -> String? {
        messages.filter { $0.instant != nil }.max { avant($0, $1) }?.creeLe
    }

    /// Vrai si le message n'est pas antérieur à `depuis` (même milliseconde comprise : la fusion par id dédoublonne).
    /// Un message ou une borne sans date lisible n'est jamais écarté.
    public static func pasAvant(_ message: MessageChat, _ depuis: String) -> Bool {
        guard let instant = message.instant, let borne = PlanningHorlogeParis.instant(depuis) else { return true }
        return instant >= borne
    }

    /// Message d'un autre participant que `moi` (identifiants comparés sans casse).
    public static func estEntrant(_ message: MessageChat, moi: String) -> Bool {
        message.auteurId?.lowercased() != moi.lowercased()
    }
}

/// Liste des conversations : ordre et mise à jour d'un aperçu sur INSERT `messages_chat` (web l.293-326).
public enum ListeConversations {
    /// Ordre de la liste : date du dernier message (ou de création) décroissante, puis id décroissant, comme le serveur.
    public static func trier(_ conversations: [ConversationApercu]) -> [ConversationApercu] {
        conversations.sorted { a, b in
            switch (a.triLe.flatMap(PlanningHorlogeParis.instant), b.triLe.flatMap(PlanningHorlogeParis.instant)) {
            case let (x?, y?) where x != y: return x > y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.id > b.id
            }
        }
    }

    /// Message entrant pour le soignant : dans une conversation rattachée à un soignant, tout auteur qui n'est pas ce
    /// soignant ; sinon tout auteur qui n'est pas `moi` (web, rôle `SOIGNANT`).
    public static func estEntrant(_ message: MessageChat, dans conversation: ConversationApercu, moi: String) -> Bool {
        FilMessages.estEntrant(message, moi: conversation.soignantId ?? moi)
    }

    /// Aperçu, date et non-lus de la conversation du message, puis liste retriée ; les non-lus n'augmentent que pour un
    /// message entrant d'un fil qui n'est pas ouvert. `nil` : conversation inconnue (la liste est à relire, il n'y a
    /// pas d'abonnement aux nouvelles conversations).
    public static func appliquer(_ message: MessageChat, a conversations: [ConversationApercu], moi: String,
                                 filOuvert: String?) -> [ConversationApercu]? {
        guard let index = conversations.firstIndex(where: { $0.id == message.conversationId }) else { return nil }
        var liste = conversations
        var conversation = liste[index]
        conversation.dernierContenu = message.contenu
        if let creeLe = message.creeLe { conversation.dernierMessageLe = creeLe }
        if estEntrant(message, dans: conversation, moi: moi), filOuvert != conversation.id { conversation.nonLus += 1 }
        liste[index] = conversation
        return trier(liste)
    }
}

/// Diffusion d'événements à plusieurs abonnés `AsyncStream`, sans rejeu (un abonné ne reçoit que ce qui suit son
/// abonnement). `terminer()` ferme tous les flux, présents et à venir. Sert au monde démo (`DemoRealtimeGateway`) et au
/// partage d'un canal Realtime entre plusieurs lecteurs (`SupabaseRealtimeGateway`).
///
/// `@unchecked Sendable` : tout l'état mutable est protégé par `verrou`, dans des sections synchrones ; `yield` ne fait
/// que mettre la valeur en tampon.
public final class DiffusionEvenements<Valeur: Sendable>: @unchecked Sendable {
    private let verrou = NSLock()
    private var abonnes: [UUID: AsyncStream<Valeur>.Continuation] = [:]
    private var termine = false

    public init() {}

    public func flux() -> AsyncStream<Valeur> {
        AsyncStream { suite in
            let id = UUID()
            suite.onTermination = { [weak self] _ in self?.desabonner(id) }
            if !abonner(id, suite) { suite.finish() }
        }
    }

    public func emettre(_ valeur: Valeur) {
        verrou.lock(); defer { verrou.unlock() }
        for suite in abonnes.values { suite.yield(valeur) }
    }

    public func terminer() {
        verrou.lock()
        termine = true
        let suites = Array(abonnes.values)
        abonnes.removeAll()
        verrou.unlock()
        // Hors du verrou : `finish()` appelle aussitôt `onTermination`, qui le reprend.
        suites.forEach { $0.finish() }
    }

    /// Abonnés en cours.
    public var nombreAbonnes: Int {
        verrou.lock(); defer { verrou.unlock() }
        return abonnes.count
    }

    private func abonner(_ id: UUID, _ suite: AsyncStream<Valeur>.Continuation) -> Bool {
        verrou.lock(); defer { verrou.unlock() }
        guard !termine else { return false }
        abonnes[id] = suite
        return true
    }

    private func desabonner(_ id: UUID) {
        verrou.lock(); defer { verrou.unlock() }
        abonnes[id] = nil
    }
}
