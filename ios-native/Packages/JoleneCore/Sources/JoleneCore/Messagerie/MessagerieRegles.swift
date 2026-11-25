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
    /// soignant ; sinon tout auteur qui n'est pas `moi` (web, rôle `SOIGNANT`). Pour l'établissement (lot 5, T11 ; web,
    /// rôle `ADMIN_ETABLISSEMENT`, `PageMessagerie.tsx` l.305-307) : dans une conversation rattachée à un soignant, le
    /// seul message entrant est celui du soignant (un message d'un collègue de l'équipe n'est pas un non-lu) ; sinon
    /// tout auteur qui n'est pas `moi`.
    public static func estEntrant(_ message: MessageChat, dans conversation: ConversationApercu, moi: String,
                                  etablissement: Bool = false) -> Bool {
        if etablissement, let soignant = conversation.soignantId, !soignant.isEmpty {
            return message.auteurId?.lowercased() == soignant.lowercased()
        }
        return FilMessages.estEntrant(message, moi: conversation.soignantId ?? moi)
    }

    /// Aperçu, date et non-lus de la conversation du message, puis liste retriée ; les non-lus n'augmentent que pour un
    /// message entrant d'un fil qui n'est pas ouvert. `nil` : conversation inconnue (la liste est à relire, il n'y a
    /// pas d'abonnement aux nouvelles conversations).
    public static func appliquer(_ message: MessageChat, a conversations: [ConversationApercu], moi: String,
                                 etablissement: Bool = false, filOuvert: String?) -> [ConversationApercu]? {
        guard let index = conversations.firstIndex(where: { $0.id == message.conversationId }) else { return nil }
        var liste = conversations
        var conversation = liste[index]
        conversation.dernierContenu = message.contenu
        if let creeLe = message.creeLe { conversation.dernierMessageLe = creeLe }
        if estEntrant(message, dans: conversation, moi: moi, etablissement: etablissement), filOuvert != conversation.id { conversation.nonLus += 1 }
        liste[index] = conversation
        return trier(liste)
    }
}

/// Diffusion d'événements à plusieurs abonnés `AsyncStream`, sans rejeu (un abonné ne reçoit que ce qui suit son
/// abonnement). `terminer()` ferme tous les flux, présents et à venir. Sert au monde démo (`DemoRealtimeGateway`) et au
/// partage d'un canal Realtime entre plusieurs lecteurs (`SupabaseRealtimeGateway`).
///
/// Deux verrous, pour qu'une émission ne puisse jamais s'interbloquer avec l'annulation d'un lecteur : `yield` reprend
/// la tâche qui attend le flux et prend pour cela le verrou d'état de cette tâche, que son annulation tient déjà quand
/// elle appelle `onTermination`. `verrou` protège la liste des abonnés et est le seul que prend `onTermination` ;
/// `emission` sérialise les émissions (ordre conservé) et n'est jamais pris par `onTermination` : les `yield` et les
/// `finish` se font sous `emission` seul, `verrou` relâché.
///
/// `@unchecked Sendable` : tout l'état mutable est protégé par `verrou`, dans des sections synchrones.
public final class DiffusionEvenements<Valeur: Sendable>: @unchecked Sendable {
    private let verrou = NSLock()
    private let emission = NSLock()
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
        emission.lock(); defer { emission.unlock() }
        for suite in suites() { suite.yield(valeur) }
    }

    public func terminer() {
        emission.lock(); defer { emission.unlock() }
        verrou.lock()
        termine = true
        let aFinir = Array(abonnes.values)
        abonnes.removeAll()
        verrou.unlock()
        // `finish()` appelle aussitôt `onTermination`, qui reprend `verrou`.
        aFinir.forEach { $0.finish() }
    }

    /// Abonnés en cours.
    public var nombreAbonnes: Int {
        verrou.lock(); defer { verrou.unlock() }
        return abonnes.count
    }

    private func suites() -> [AsyncStream<Valeur>.Continuation] {
        verrou.lock(); defer { verrou.unlock() }
        return Array(abonnes.values)
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

/// Dernier état connu et ses changements, diffusés à plusieurs abonnés `AsyncStream` : un abonné reçoit d'abord l'état
/// courant s'il est connu, puis chaque changement (un doublon n'est pas rediffusé). Mêmes deux verrous que
/// `DiffusionEvenements` : les états du canal Realtime sont émis pendant que des lecteurs sont annulés (fil masqué,
/// `fermerTout()`), ce qui interbloquerait une diffusion faite sous le verrou que prend `onTermination`.
///
/// Le rejeu à l'abonnement se fait sous `verrou` : le flux n'a pas encore de lecteur (il n'est pas rendu), `yield` ne
/// fait que mettre en tampon, et un changement concurrent ne peut pas être livré avant l'état qu'il remplace.
public final class DiffusionEtat<Valeur: Sendable & Equatable>: @unchecked Sendable {
    private let verrou = NSLock()
    private let emission = NSLock()
    private var dernier: Valeur?
    private var abonnes: [UUID: AsyncStream<Valeur>.Continuation] = [:]
    private var termine = false

    public init() {}

    /// Dernier état reçu, nil tant qu'aucun ne l'a été.
    public func lire() -> Valeur? {
        verrou.lock(); defer { verrou.unlock() }
        return dernier
    }

    /// Nouvel état : diffusé à chaque abonné s'il change.
    public func recevoir(_ valeur: Valeur) {
        emission.lock(); defer { emission.unlock() }
        verrou.lock()
        guard dernier != valeur else {
            verrou.unlock()
            return
        }
        dernier = valeur
        let suites = Array(abonnes.values)
        verrou.unlock()
        for suite in suites { suite.yield(valeur) }
    }

    public func flux() -> AsyncStream<Valeur> {
        AsyncStream { suite in
            let id = UUID()
            suite.onTermination = { [weak self] _ in self?.desabonner(id) }
            if !abonner(id, suite) { suite.finish() }
        }
    }

    /// Termine tous les flux, présents et à venir.
    public func terminer() {
        emission.lock(); defer { emission.unlock() }
        verrou.lock()
        termine = true
        let aFinir = Array(abonnes.values)
        abonnes.removeAll()
        verrou.unlock()
        aFinir.forEach { $0.finish() }
    }

    private func abonner(_ id: UUID, _ suite: AsyncStream<Valeur>.Continuation) -> Bool {
        verrou.lock(); defer { verrou.unlock() }
        guard !termine else { return false }
        abonnes[id] = suite
        if let dernier { suite.yield(dernier) }
        return true
    }

    private func desabonner(_ id: UUID) {
        verrou.lock(); defer { verrou.unlock() }
        abonnes[id] = nil
    }
}

/// Horloge d'interface monotone (secondes depuis le démarrage de l'appareil) : mesure les fenêtres de l'interface,
/// distincte de l'horloge métier (`contexte.maintenant()`), figée en démo (`FixedClock(DemoWorld.fixedNow)`). Injectable
/// pour les tests (revue du delta de la PR #1185, majeur 1).
public struct HorlogeInterface: Sendable {
    public let maintenant: @Sendable () -> TimeInterval

    public init(maintenant: @escaping @Sendable () -> TimeInterval) {
        self.maintenant = maintenant
    }

    /// `ProcessInfo.systemUptime` : monotone, insensible aux changements d'heure, jamais figé en démo.
    public static let systeme = HorlogeInterface { ProcessInfo.processInfo.systemUptime }
}

/// Suivi de la fin d'un fil de messages (`ConversationScreen`) quand la hauteur visible du fil change (clavier, rotation,
/// Split View, taille du texte, composeur qui grandit) : le fil n'est ramené en bas que si sa fin était visible juste
/// avant le changement, ou juste après un envoi de l'utilisateur. Un utilisateur qui relit l'historique garde sa position
/// (revue fraîche de la PR #1185, mineur 1). L'insertion d'un message, elle, ramène toujours en bas.
///
/// État tenu ici, pas dans la vue (revue du delta, majeur 2) : la position du repère de fin et la hauteur visible sont
/// mémorisées, et la visibilité de la fin est recalculée de ces deux valeurs à chaque décision. Elle ne dépend donc ni de
/// l'ordre des `onAppear`, ni d'un déplacement du repère (fil court qui tient dans la zone). Le dernier envoi est daté sur
/// l'horloge d'interface (`HorlogeInterface`), jamais sur l'horloge métier, figée en démo (majeur 1).
public struct SuiviFinDuFil: Equatable, Sendable {
    /// Marge (pt) sous le bas visible dans laquelle la fin du fil compte encore comme visible.
    public static let tolerance: Double = 24
    /// Fenêtre (s, horloge d'interface) après un envoi pendant laquelle un changement de hauteur suit la fin du fil : à
    /// l'envoi, le clavier se ferme puis se rouvre (iPad paysage, simulateur iOS 18.6 : 83,5 → 480,5 → 83,5 pt en 0,1 s).
    public static let fenetreApresEnvoi: TimeInterval = 2

    /// Haut du repère de fin dans le repère de la zone de défilement ; nil tant qu'il n'est pas mesuré.
    public private(set) var hautDuRepere: Double?
    /// Hauteur visible de la zone ; 0 tant qu'elle n'est pas mesurée.
    public private(set) var hauteurVisible: Double = 0
    /// Dernier envoi de l'utilisateur, sur l'horloge d'interface.
    public private(set) var dernierEnvoi: TimeInterval?

    public init() {}

    /// La fin du fil est visible : le haut du repère de fin est au-dessus du bas visible (tolérance comprise). Valeur
    /// inconnue (repère non mesuré, hauteur 0) : non visible.
    public static func finVisible(hautDuRepere: Double, hauteurVisible: Double) -> Bool {
        hauteurVisible > 0 && hautDuRepere <= hauteurVisible + tolerance
    }

    /// Visibilité de la fin, recalculée des deux valeurs mémorisées.
    public var finVisible: Bool {
        guard let hautDuRepere else { return false }
        return Self.finVisible(hautDuRepere: hautDuRepere, hauteurVisible: hauteurVisible)
    }

    /// Un envoi a eu lieu dans la fenêtre, à l'instant `instant` de l'horloge d'interface.
    public func envoiRecent(a instant: TimeInterval) -> Bool {
        guard let dernierEnvoi else { return false }
        let ecart = instant - dernierEnvoi
        return ecart >= 0 && ecart < Self.fenetreApresEnvoi
    }

    /// Le repère de fin a été mesuré (apparition ou déplacement).
    public mutating func repere(_ haut: Double) { hautDuRepere = haut }

    /// Première mesure de la hauteur visible : aucune décision.
    public mutating func hauteurMesuree(_ hauteur: Double) { hauteurVisible = hauteur }

    /// L'utilisateur envoie un message à l'instant `instant` de l'horloge d'interface.
    public mutating func envoi(a instant: TimeInterval) { dernierEnvoi = instant }

    /// La hauteur visible change : décide du suivi avec l'état d'AVANT le changement (fin visible avec l'ancienne hauteur,
    /// ou envoi récent), puis retient la nouvelle hauteur. Hauteur encore inconnue : retenue sans décision.
    public mutating func hauteurChangee(_ nouvelle: Double, a instant: TimeInterval) -> Bool {
        let suivre = hauteurVisible > 0 && (finVisible || envoiRecent(a: instant))
        hauteurVisible = nouvelle
        return suivre
    }
}
