import Combine
import Foundation

/// Modèle de la page Présences (blueprint lot 2 §3 T4a ; parité `src/pages/PresencesSoignant.tsx`) : instantané lu par
/// `gateways.pointage.presences(context:)` pour l'epoch de la session, borné à `SessionController.resolutionTimeout`.
/// Aucun texte ici : l'écran associe chaque état à son libellé web ; un échec porte le message levé par le port
/// (`JoleneError.message`, repli inventorié de `PointageQuery`), ou aucun.
///
/// État dérivé (une seule source, l'instantané) :
/// - onglets Aujourd'hui, À venir et Actives par `InstantanePresences.listes(maintenant:)` sur l'horloge figée au début
///   du chargement (`chargeLe`, l.107) ; historique par `lignesHistorique(soignantId:)`, filtré par `?filtre=a_valider`
///   (`PointageRules.historiqueAffiche`, l.279-288) ;
/// - onglet initial (`PointageRules.ongletInitial`, l.276-278) posé au PREMIER chargement réussi, comme le `defaultValue`
///   des onglets du web (montés après le chargement) : une relecture ne change jamais l'onglet choisi.
///
/// Règles d'état du lot 1 (`AccueilModel`) : une annulation n'est jamais une erreur (l'état reste `.loading`) ; un
/// rafraîchissement conserve l'instantané affiché et n'expose qu'`echecRafraichissement` ; `.unauthorized` lève
/// `sessionExpired` ; une réponse reçue pour un epoch périmé, ou d'un chargement dépassé, est abandonnée. Relecture à
/// l'apparition au-delà de `delaiRelecture` (`staleTime: 60_000`, l.262), au tirer-pour-rafraîchir et au retour au
/// premier plan ; après un échec, seule l'action « Réessayer » relance.
@MainActor
public final class PresencesModel: ObservableObject {
    /// Échec d'une lecture : message du port, ou nil quand l'erreur n'en porte aucun de lisible.
    public struct Echec: Equatable, Sendable {
        public let message: String?

        public init(message: String?) { self.message = message }
    }

    public enum State: Equatable, Sendable {
        case loading
        case loaded(InstantanePresences)
        case failed(Echec)
    }

    /// `staleTime: 60_000` du web (l.262) : au-delà, une nouvelle apparition relit l'instantané.
    public static let delaiRelecture: TimeInterval = 60

    @Published public private(set) var state: State = .loading
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var echecRafraichissement: Echec?
    @Published public private(set) var sessionExpired = false
    /// Onglet affiché ; nil avant le premier chargement réussi.
    @Published public private(set) var onglet: PointageRules.OngletPresences?
    /// Instant (horloge des gateways) du dernier chargement réussi.
    public private(set) var chargeLe: Date?
    /// Horloge des gateways de la session (démo : horloge fixée) : évaluation des blocs de pointage toutes les 30 s.
    public private(set) var horloge: any ClockPort = SystemClock()

    /// `?tab=` du lien (route de T10), valeurs exactes du web ; une valeur inconnue retombe sur l'onglet dérivé.
    public let parametreOnglet: String?
    /// `?filtre=a_valider` du lien (route de T10).
    public let aValider: Bool

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    /// Numéro du dernier chargement lancé : seul ce chargement publie (main actor, donc sans course).
    private var generation = 0

    public init(controller: SessionController, snapshot: SessionSnapshot, parametreOnglet: String? = nil,
                parametreFiltre: String? = nil) {
        self.controller = controller
        self.snapshot = snapshot
        self.parametreOnglet = parametreOnglet
        self.aValider = PointageRules.filtreAValider(parametreFiltre)
    }

    public var instantane: InstantanePresences? {
        if case let .loaded(instantane) = state { return instantane }
        return nil
    }

    /// Onglets Aujourd'hui, À venir et Actives, et contrat de pointage par mission.
    public var listes: ListesPresencesSoignant<MissionPresenceLue, EtablissementSummary>? {
        guard let instantane else { return nil }
        return instantane.listes(maintenant: instantane.chargeLe ?? chargeLe ?? horloge.now())
    }

    /// Onglet Historique, filtré par `?filtre=a_valider`.
    public var historique: [LigneHistoriquePresence] {
        guard let instantane else { return [] }
        return PointageRules.historiqueAffiche(instantane.lignesHistorique(soignantId: snapshot.context.userId), aValider: aValider)
    }

    /// Section « Présences validées récemment » de l'onglet Aujourd'hui (7 jours, l.123-133).
    public var presencesValidees: [PresenceLue] { instantane?.presencesValidees ?? [] }

    public func choisir(_ onglet: PointageRules.OngletPresences) {
        self.onglet = onglet
    }

    public func load() async {
        generation += 1
        let courant = generation
        let refreshing: Bool
        if case .loaded = state { refreshing = true } else { refreshing = false }
        if refreshing { isRefreshing = true } else { state = .loading }
        echecRafraichissement = nil
        // Un chargement dépassé n'éteint pas l'indicateur du chargement qui l'a remplacé.
        defer { if generation == courant { isRefreshing = false } }

        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        guard generation == courant else { return }
        horloge = gateways.clock
        let port = gateways.pointage
        let context = snapshot.context
        do {
            let instantane = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.presences(context: context)
            }
            guard await controller.epoch == snapshot.epoch, generation == courant else { return }
            sessionExpired = false
            chargeLe = gateways.clock.now()
            state = .loaded(instantane)
            if onglet == nil, let listes {
                onglet = PointageRules.ongletInitial(parametre: parametreOnglet, missionsAujourdhui: listes.missionsAujourdhui.count,
                                                     missionsEnCours: listes.missionsEnCours.count)
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, generation == courant, !Task.isCancelled else { return }
            let message: String?
            if let jolene = error as? JoleneError {
                if jolene.kind == .cancelled { return }
                sessionExpired = jolene.kind == .unauthorized
                message = jolene.message
            } else if error is CancellationError {
                return
            } else {
                message = nil
            }
            if refreshing { echecRafraichissement = Echec(message: message) } else { state = .failed(Echec(message: message)) }
        }
    }

    /// « Vérifier ma session » : revalide la session, puis relit l'instantané si elle est toujours prête pour l'epoch
    /// de cet écran (même règle que `AccueilModel.verifierSession`).
    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await load()
    }

    /// Apparition de l'écran ou retour au premier plan : premier chargement (ou relance après une tâche annulée), ou
    /// relecture au-delà de `delaiRelecture`. Après un échec, seule l'action « Réessayer » relance.
    public func loadIfStale() async {
        switch state {
        case .loading:
            await load()
        case .failed:
            return
        case .loaded:
            guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
            guard let chargeLe, gateways.clock.now().timeIntervalSince(chargeLe) <= Self.delaiRelecture else {
                await load()
                return
            }
        }
    }
}
