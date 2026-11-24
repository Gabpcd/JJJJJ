import Foundation
import Combine

/// Repli des messages d'erreur de la messagerie. T7a ne crée aucun texte : les messages du serveur passent mot pour
/// mot, et le repli est le message générique du web (`src/lib/erreurs.ts`, repli de `messageErreurEdgeFn`) déjà porté
/// par le lot 2 (`MessagesDocuments.erreurGenerique`). Les libellés propres à l'écran (refus d'envoi par code,
/// conversation indisponible…) sont repris du web par T7b.
public enum MessagerieRepli {
    public static let message = MessagesDocuments.erreurGenerique
}

/// Cycle de vie Realtime de la messagerie et état partagé de la session (lot 4, T7a ; `LOT4_PLAN.md` §2.5 « Messagerie
/// Realtime », fiche « Realtime : tables, RLS, filtres, cycle de vie » de `CONTRATS_RPC_SOIGNANT.md`). Une instance par
/// lancement, tenue par `Jolene/Composition/RealtimeLifecycle.swift`, qui lui transmet les phases de scène ; elle suit
/// elle-même l'état de la session (`SessionStore.state`).
///
/// Règles :
/// - canaux ouverts seulement quand la scène est active ET qu'un espace (soignant, ou établissement depuis le lot 5 T11)
///   est prêt ; aucun `UIBackgroundModes` ;
/// - arrière-plan → `RealtimePort.fermerTout()` (tous les flux se terminent : les suivis des modèles s'arrêtent) ;
///   retour au premier plan → flux de la liste redemandé, badge relu, `generation` avancée (les écrans relancent leur
///   suivi par `.task(id: generation)`) ;
/// - epoch d'identité changé ou identité terminée → `fermerTout()` avant tout canal de la nouvelle session ; le badge
///   et le fil ouvert d'un compte ne suivent jamais le suivant ; une revalidation du même epoch ne touche à rien ;
/// - badge Messages = `fn_messages_non_lus()` (valeur serveur) relu au premier plan, à chaque INSERT entrant du canal de
///   la liste, après chaque `marquerLus`, et au « rejoint » qui suit une coupure ; une lecture en échec laisse la
///   dernière valeur lue (jamais un badge fabriqué) ;
/// - verrou m6 conservé : rien n'est ouvert ni lu tant que le port Realtime est un stub non câblé (`VerrousLot4`) ;
/// - gap verrouillé (T7a livre le cœur sans écran) : rien n'est ouvert ni lu tant que l'écran natif de la messagerie
///   n'est pas livré (`DestinationLien.ecranNatifLivre`, ligne que T7b passe à `true` : le cycle s'active alors de
///   lui-même) ; écran livré, son coupe-circuit `ios_natif_messagerie_actif` (D18) est lu avant tout canal — messagerie
///   coupée → ni Realtime ni badge, jusqu'au prochain passage au premier plan ou à la prochaine identité ;
/// - phases de scène et publications d'état traitées une à une, dans l'ordre reçu (file série).
@MainActor
public final class CycleRealtime: ObservableObject {
    /// `fn_messages_non_lus()` ; `nil` tant qu'aucune lecture n'a abouti pour l'identité courante.
    @Published public private(set) var nonLus: Int?
    /// Avancée à chaque ouverture des canaux (premier plan, nouvelle identité) : clé de relance des suivis d'écran.
    @Published public private(set) var generation = 0
    /// Conversation dont le fil est affiché : un message entrant n'y compte pas comme non-lu dans la liste.
    public private(set) var filOuvert: String?

    private let session: SessionStore
    private var suiviSession: AnyCancellable?
    private var file: Task<Void, Never>?
    private var auPremierPlan = false
    /// Espace prêt (soignant ou établissement, lot 5 T11) ; `nil` : aucune session prête.
    private var instantane: ContexteMessagerie?
    /// Port dont des canaux sont ouverts ; `nil` : rien n'est ouvert.
    private var portOuvert: RealtimePort?
    private var ecouteMessages: Task<Void, Never>?
    private var ecouteCanal: Task<Void, Never>?
    private var badgeEnLecture = false
    private var badgeARelire = false
    private weak var liste: ConversationsModel?
    /// Écran natif de la messagerie livré (lu une fois : la valeur est figée à la compilation).
    private let ecranLivre: Bool
    /// Lot 5 (T11) : messagerie de l'espace établissement livrée (`EtabDestination.conversation.ecranLivre`).
    private let ecranLivreEtablissement: Bool

    public convenience init(session: SessionStore) {
        self.init(session: session, ecranLivre: EcranSecondaire.messagerie(conversationId: nil).estLivre,
                  ecranLivreEtablissement: EtabDestination.conversation(id: "").ecranLivre)
    }

    /// `ecranLivre` : imposé par les tests du cycle, que l'écran soit livré ou non (les deux espaces).
    init(session: SessionStore, ecranLivre: Bool, ecranLivreEtablissement: Bool? = nil) {
        self.session = session
        self.ecranLivre = ecranLivre
        self.ecranLivreEtablissement = ecranLivreEtablissement ?? ecranLivre
        // `@Published` publie la nouvelle valeur avant de l'affecter : l'état reçu est celui qui entre en vigueur.
        suiviSession = session.$state.sink { [weak self] etat in self?.etatPublie(etat) }
    }

    private var controller: SessionController { session.controller }

    // MARK: - Phases de scène (appelées par l'app)

    /// Scène active : ouvre les canaux d'un espace soignant prêt, ou relit le badge s'ils sont déjà ouverts.
    public func premierPlan() async {
        await enfiler { await $0.passerAuPremierPlan() }.value
    }

    /// Scène en arrière-plan : tous les canaux sont retirés.
    public func arrierePlan() async {
        await enfiler { await $0.passerEnArrierePlan() }.value
    }

    /// Ports de la session courante (verrou de l'app) ; `nil` si l'identité change pendant la lecture.
    public func gateways() async -> Gateways? {
        for _ in 0..<3 {
            let epoch = await controller.epoch
            if let ports = await controller.gateways(for: epoch) { return ports }
        }
        return nil
    }

    // MARK: - État partagé avec les modèles d'écran

    /// Fil affiché (`FilModel.suivre`).
    public func ouvrirFil(_ conversationId: String) { filOuvert = conversationId }

    /// Fil masqué ; sans effet si un autre fil a été ouvert entre-temps.
    public func fermerFil(_ conversationId: String) {
        if filOuvert == conversationId { filOuvert = nil }
    }

    /// `fn_marquer_messages_lus` a abouti pour ce fil : non-lus de la conversation à 0 dans la liste (comme le web),
    /// puis badge relu.
    public func conversationLue(_ conversationId: String) async {
        liste?.marquerLue(conversationId)
        await relireNonLus()
    }

    /// Envoi confirmé, conversation archivée ou accès refusé : la liste affichée se relit.
    public func listeARelire() {
        guard let liste else { return }
        Task { await liste.charger() }
    }

    /// Relit `fn_messages_non_lus()`. Des demandes qui se chevauchent sont regroupées : une lecture en vol est suivie
    /// d'une seule relecture.
    public func relireNonLus() async {
        if badgeEnLecture {
            badgeARelire = true
            return
        }
        badgeEnLecture = true
        defer { badgeEnLecture = false }
        repeat {
            badgeARelire = false
            await lireBadge()
        } while badgeARelire
    }

    func attacher(_ liste: ConversationsModel) { self.liste = liste }

    /// Attend que les phases et publications en file soient traitées (tests).
    func repos() async {
        while let courante = file {
            await courante.value
            if file == courante { break }
        }
    }

    // MARK: - File série

    @discardableResult
    private func enfiler(_ operation: @escaping @MainActor (CycleRealtime) async -> Void) -> Task<Void, Never> {
        let precedente = file
        let tache = Task { [weak self] in
            await precedente?.value
            guard let self else { return }
            await operation(self)
        }
        file = tache
        return tache
    }

    private func etatPublie(_ etat: SessionState) {
        enfiler { await $0.traiter(etat) }
    }

    // MARK: - Transitions

    private func traiter(_ etat: SessionState) async {
        let snapshot: ContexteMessagerie
        switch etat {
        case let .ready(soignant): snapshot = ContexteMessagerie(soignant)
        case let .readyEtablissement(etablissement): snapshot = ContexteMessagerie(etablissement) // lot 5, T11
        default:
            // Plus d'espace prêt (déconnexion, espace bloqué) : rien ne reste ouvert.
            instantane = nil
            await fermer()
            oublierIdentite()
            return
        }
        if let instantane, instantane.epoch == snapshot.epoch {
            self.instantane = snapshot // revalidation du même epoch : canaux, badge et fil inchangés
            return
        }
        await fermer() // avant tout canal de la nouvelle session
        oublierIdentite()
        instantane = snapshot
        if auPremierPlan { await ouvrir() }
    }

    private func passerAuPremierPlan() async {
        auPremierPlan = true
        guard instantane != nil else { return }
        if portOuvert != nil {
            await relireNonLus() // inactif → actif : les canaux sont restés ouverts
        } else {
            await ouvrir()
        }
    }

    private func passerEnArrierePlan() async {
        auPremierPlan = false
        await fermer()
    }

    private func oublierIdentite() {
        nonLus = nil
        filOuvert = nil
    }

    /// Flux de la liste déclaré, puis badge relu. Le canal `messagerie-liste-<uid>` est partagé avec la liste affichée.
    private func ouvrir() async {
        guard let instantane, instantane.estEtablissement ? ecranLivreEtablissement : ecranLivre,
              let gateways = await controller.gateways(for: instantane.epoch),
              VerrousLot4.abonnementRealtimePermis(gateways.realtime) else { return }
        // Coupe-circuit de l'écran lu avant tout canal (fail-open : absent ou illisible, la messagerie reste servie) :
        // `ios_natif_messagerie_actif` pour le soignant, `ios_natif_etab_messages_actif` pour l'établissement (D14).
        let actif = instantane.estEtablissement
            ? await gateways.flags.ecranEtablissementActif(.messages)
            : await PorteEcranNatif.lire(EcranSecondaire.messagerie(conversationId: nil), flags: gateways.flags) == .natif
        guard actif, self.instantane?.epoch == instantane.epoch, portOuvert == nil else { return }
        let realtime = gateways.realtime
        portOuvert = realtime
        let entrants = realtime.messagesEntrants(conversationId: nil)
        let etats = realtime.etat(conversationId: nil)
        let moi = instantane.moi
        ecouteMessages = Task { [weak self] in
            for await message in entrants where FilMessages.estEntrant(message, moi: moi) {
                await self?.relireNonLus()
            }
        }
        ecouteCanal = Task { [weak self] in
            var coupe = false
            for await etat in etats {
                switch etat {
                case .coupe: coupe = true
                case .rejoint where coupe:
                    coupe = false
                    await self?.relireNonLus() // messages manqués pendant la coupure
                default: break
                }
            }
        }
        generation += 1
        await relireNonLus()
    }

    private func fermer() async {
        ecouteMessages?.cancel()
        ecouteCanal?.cancel()
        ecouteMessages = nil
        ecouteCanal = nil
        guard let port = portOuvert else { return }
        portOuvert = nil
        await port.fermerTout()
    }

    private func lireBadge() async {
        guard let instantane, let gateways = await controller.gateways(for: instantane.epoch) else { return }
        let port = gateways.messagerie
        let contexte = instantane
        let epoch = instantane.epoch
        guard let valeur = try? await bounded(timeout: controller.resolutionTimeout, { try await port.nonLus(contexte: contexte) }),
              self.instantane?.epoch == epoch, await controller.epoch == epoch else { return }
        nonLus = max(0, valeur)
    }
}
