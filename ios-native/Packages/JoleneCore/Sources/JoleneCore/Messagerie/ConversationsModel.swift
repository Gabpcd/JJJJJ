import Foundation
import Combine

/// Conversation de la liste : la ligne servie et son interlocuteur (`fn_interlocuteurs_conversations`).
public struct ConversationAffichee: Equatable, Sendable, Identifiable {
    public var apercu: ConversationApercu
    /// Ligne de l'interlocuteur (`autre_id`) ; `nil` s'il n'en existe pas pour cette conversation.
    public var interlocuteur: Interlocuteur?
    /// Faux quand les interlocuteurs n'ont pas pu être lus : rien n'est alors déduit de l'absence de ligne.
    public var interlocuteursLus: Bool

    public init(apercu: ConversationApercu, interlocuteur: Interlocuteur?, interlocuteursLus: Bool = true) {
        self.apercu = apercu; self.interlocuteur = interlocuteur; self.interlocuteursLus = interlocuteursLus
    }

    public var id: String { apercu.id }

    /// Conversation avec la plateforme : `est_jolene` de la ligne, et, comme le web (`info?.est_jolene ?? true`), toute
    /// conversation sans ligne d'interlocuteur — sauf si les interlocuteurs n'ont pas été lus.
    public var estJolene: Bool { interlocuteursLus && (interlocuteur?.estJolene ?? true) }

    /// Avatar servi ; jamais pour la plateforme (web : `isJolene ? null : info.avatar_url`).
    public var avatarUrl: String? { estJolene ? nil : interlocuteur?.avatarUrl }
}

/// Liste des conversations de la messagerie (lot 4, T7a ; `LOT4_PLAN.md` §2.4-§2.5), port de la liste de
/// `src/pages/PageMessagerie.tsx` (l.156-290, l.293-326). L'écran (T7b) ne lit que ce modèle ; le modèle ne lit que les
/// ports.
///
/// Règles :
/// - pagination keyset comme le web : pages de 100 (`fn_lister_conversations_messagerie`), dédoublonnage par id, arrêt
///   quand la page ne rend plus de curseur, quand le curseur ne change pas, et à cent pages ; ordre serveur conservé ;
/// - interlocuteurs par lots de 100 identifiants ; un refus métier de cette lecture (`Compte inactif`) laisse la liste
///   sans noms et expose le message serveur, sans rien déduire de l'absence de ligne ;
/// - lectures bornées à `SessionController.resolutionTimeout` ; réponse d'un epoch périmé ignorée ; deux lectures qui
///   se chevauchent : seule la dernière demandée publie ; première lecture en échec → `.echec` (jamais une liste vide
///   plausible), relecture en échec → liste gardée et message ;
/// - `suivre()` : flux du canal de la liste déclaré avant la lecture ; INSERT `messages_chat` → aperçu, date et
///   non-lus mis à jour comme le web (pas de non-lu pour le fil ouvert ni pour mes messages ; un même INSERT n'est
///   appliqué qu'une fois) ; conversation inconnue → liste relue (aucun abonnement `conversations`, absente de la
///   publication) ; « rejoint » après coupure → liste relue ; flux fermé (arrière-plan, identité) → fin du suivi ;
/// - onglets dérivés de `archived_at` ; non-lus par conversation = affichage seulement (le badge est
///   `CycleRealtime.nonLus`).
@MainActor
public final class ConversationsModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case pret
        /// Première lecture en échec : message de l'erreur.
        case echec(String)
    }

    @Published public private(set) var etat: Etat = .chargement
    /// Toutes les conversations, ordre serveur (dernier message décroissant).
    @Published public private(set) var conversations: [ConversationAffichee] = []
    /// Dernière erreur d'une relecture, ou refus de la lecture des interlocuteurs, verbatim.
    @Published public private(set) var message: String?
    @Published public private(set) var sessionExpiree = false

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private let cycle: CycleRealtime?
    private var jeton = 0
    private var interlocuteurs: [String: Interlocuteur] = [:]
    private var interlocuteursLus = true
    /// INSERT déjà appliqués à la liste (un message reçu deux fois n'est compté qu'une fois).
    private var messagesAppliques: Set<String> = []

    public init(controller: SessionController, snapshot: SessionSnapshot, cycle: CycleRealtime? = nil) {
        self.controller = controller
        self.snapshot = snapshot
        self.cycle = cycle
        cycle?.attacher(self)
    }

    public var actives: [ConversationAffichee] { conversations.filter { !$0.apercu.archivee } }

    public var archivees: [ConversationAffichee] { conversations.filter { $0.apercu.archivee } }

    public func conversation(_ id: String) -> ConversationAffichee? { conversations.first { $0.id == id } }

    // MARK: - Lecture

    public func charger() async {
        jeton += 1
        let numero = jeton
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.messagerie
        let context = snapshot.context
        let delai = controller.resolutionTimeout
        do {
            var lues: [ConversationApercu] = []
            var vues: Set<String> = []
            var avant: CurseurConversations?
            for _ in 0..<PageConversations.pagesMax {
                let curseur = avant
                let page = try await bounded(timeout: delai) { try await port.conversations(avant: curseur, context: context) }
                guard await courant(), numero == jeton else { return }
                for conversation in page.conversations where vues.insert(conversation.id).inserted { lues.append(conversation) }
                guard let suivant = page.suivant, suivant != avant else { break }
                avant = suivant
            }
            var index: [String: Interlocuteur] = [:]
            var refus: String?
            do {
                let ids = lues.map(\.id)
                for debut in stride(from: 0, to: ids.count, by: Interlocuteur.lotMax) {
                    let lot = Array(ids[debut..<min(debut + Interlocuteur.lotMax, ids.count)])
                    let lignes = try await bounded(timeout: delai) { try await port.interlocuteurs(ids: lot, context: context) }
                    guard await courant(), numero == jeton else { return }
                    for ligne in lignes { index[ligne.id] = ligne }
                }
            } catch let erreur as JoleneError where erreur.kind == .unknown {
                guard await courant(), numero == jeton else { return }
                index = [:]
                refus = erreur.message
            }
            interlocuteurs = index
            interlocuteursLus = refus == nil
            publier(lues)
            etat = .pret
            message = refus
            sessionExpiree = false
        } catch {
            guard await courant(), numero == jeton, let texte = texte(error) else { return }
            if etat == .pret { message = texte } else { etat = .echec(texte) }
        }
    }

    // MARK: - Suivi Realtime

    /// Lit la liste puis la suit jusqu'à la fermeture du flux (arrière-plan, changement d'identité) ou l'annulation de
    /// l'appelant. L'écran le relance à chaque `CycleRealtime.generation`.
    public func suivre() async {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let realtime = gateways.realtime
        // Flux déclarés avant la lecture : un message reçu pendant qu'elle est en vol n'est pas perdu.
        let entrants = realtime.messagesEntrants(conversationId: nil)
        let etats = realtime.etat(conversationId: nil)
        await withTaskGroup(of: Bool.self) { groupe in
            groupe.addTask { await self.ecouter(entrants); return true }
            groupe.addTask { await self.suivreCanal(etats); return false }
            groupe.addTask { await self.charger(); return false }
            while let fluxFerme = await groupe.next() {
                if fluxFerme { groupe.cancelAll() }
            }
        }
    }

    /// Non-lus de la conversation à 0 après un `marquerLus` abouti (web : `non_lus: 0` pour le fil sélectionné).
    func marquerLue(_ conversationId: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[index].apercu.nonLus = 0
    }

    private func ecouter(_ entrants: AsyncStream<MessageChat>) async {
        for await recu in entrants {
            guard await courant() else { return }
            await recevoir(recu)
        }
    }

    private func recevoir(_ recu: MessageChat) async {
        // Liste pas encore lue : la lecture en vol portera ce message.
        guard etat == .pret, messagesAppliques.insert(recu.id).inserted else { return }
        guard let liste = ListeConversations.appliquer(recu, a: conversations.map(\.apercu), moi: snapshot.user.id,
                                                       filOuvert: cycle?.filOuvert) else {
            await charger() // conversation inconnue
            return
        }
        publier(liste)
    }

    private func suivreCanal(_ etats: AsyncStream<EtatCanal>) async {
        var coupe = false
        for await nouvel in etats {
            guard await courant() else { return }
            switch nouvel {
            case .coupe: coupe = true
            case .rejoint where coupe:
                coupe = false
                await charger() // messages et conversations manqués pendant la coupure
            default: break
            }
        }
    }

    // MARK: - Interne

    private func publier(_ apercus: [ConversationApercu]) {
        conversations = apercus.map { apercu in
            let ligne = apercu.autreId.flatMap { interlocuteurs[Interlocuteur.cle(conversationId: apercu.id, participantId: $0)] }
            return ConversationAffichee(apercu: apercu, interlocuteur: ligne, interlocuteursLus: interlocuteursLus)
        }
    }

    private func courant() async -> Bool { await controller.epoch == snapshot.epoch }

    /// Message d'une erreur (`nil` : annulation, rien à montrer) ; session expirée signalée.
    private func texte(_ error: Error) -> String? {
        if let jolene = error as? JoleneError {
            if jolene.kind == .cancelled { return nil }
            if jolene.kind == .unauthorized { sessionExpiree = true }
            return jolene.message
        }
        if error is CancellationError { return nil }
        return MessagerieRepli.message
    }
}
