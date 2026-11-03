import Foundation
import Combine

/// Modèle de l'onglet « Mes missions » (lot 1, T5), port de `MissionsSoignant.tsx` : trois listes lues
/// par `gateways.mesMissions` pour l'epoch de la session, chacune bornée à
/// `SessionController.resolutionTimeout` (décision 14). Mêmes règles d'état que `AccueilModel` :
/// - une annulation de tâche SwiftUI n'est jamais une erreur (l'état reste celui d'avant) ;
/// - une relecture d'une liste déjà affichée la conserve et n'expose qu'`erreurRafraichissement` ;
/// - `.unauthorized` lève `sessionExpired` (revalidation de session plutôt que « Réessayer ») ; toute
///   autre erreur le baisse ;
/// - une réponse reçue pour un epoch périmé, ou dépassée par une lecture plus récente du même
///   onglet, est abandonnée.
///
/// Pages : lecture **cumulative** du web (« M1 », `range(0, (page + 1) * 50 - 1)`, l.244-246) — le
/// port rend les pages 0…`page` d'un seul tenant et la liste est **remplacée** (aucun ajout local :
/// une mission terminée entre deux lectures ne fait sauter aucune ligne). Chaque sélection d'onglet
/// revient à la première page, comme le web (l.248 : `setPage(0)` au changement d'onglet) ; une
/// relecture (apparition de l'écran, tirer pour actualiser, « Réessayer ») garde les pages déjà
/// chargées, comme le `refreshTick` du web, liste conservée pendant la relecture. « Charger plus »
/// (À venir, Passées) relit une page de plus ; il n'est proposé que si la dernière lecture était
/// pleine (`aSuivre`, web l.623). Lecture seule.
@MainActor
public final class MesMissionsModel: ObservableObject {
    /// État d'une liste d'onglet.
    public struct Liste<Element: Equatable & Sendable & Identifiable>: Equatable, Sendable where Element.ID == String {
        public enum Contenu: Equatable, Sendable {
            case chargement
            case chargee([Element])
            case echec(String)
        }

        public internal(set) var contenu: Contenu = .chargement
        /// Dernière page lue (0 pour la première) : la liste contient les pages 0…`page`.
        public internal(set) var page = 0
        /// Vrai si la dernière lecture était pleine : « Charger plus » est proposé.
        public internal(set) var aSuivre = false
        public internal(set) var rafraichissement = false
        public internal(set) var erreurRafraichissement: String?
        public internal(set) var chargementSuite = false
        public internal(set) var erreurSuite: String?

        public init() {}

        public var elements: [Element] {
            if case let .chargee(elements) = contenu { return elements }
            return []
        }

        public var estChargee: Bool {
            if case .chargee = contenu { return true }
            return false
        }
    }

    public static let genericFailureMessage = "Les missions n'ont pas pu être chargées. Vérifiez votre connexion puis réessayez."

    @Published public private(set) var onglet: MesMissionsOnglet
    @Published public private(set) var candidatures = Liste<CandidatureRecord>()
    @Published public private(set) var aVenir = Liste<Mission>()
    @Published public private(set) var passees = Liste<Mission>()
    /// Colonnes financières des missions passées relues (`MissionsPage.finances`), par id de mission.
    @Published public private(set) var finances: [String: MissionGainLigne] = [:]
    @Published public private(set) var sessionExpired = false
    /// Horloge des gateways de la session (démo : horloge fixée) : prochain créneau des lignes.
    public private(set) var horloge: any ClockPort = SystemClock()

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    /// Numéro de la dernière lecture lancée, par onglet : seule celle-ci publie.
    private var generations: [MesMissionsOnglet: Int] = [:]

    public init(controller: SessionController, snapshot: SessionSnapshot, onglet: MesMissionsOnglet = .aVenir) {
        self.controller = controller
        self.snapshot = snapshot
        self.onglet = onglet
    }

    /// Mission déjà relue par l'un des onglets (valeur initiale du détail), si elle l'a été.
    public func mission(id: String) -> Mission? {
        aVenir.elements.first { $0.id == id }
            ?? passees.elements.first { $0.id == id }
            ?? candidatures.elements.lazy.compactMap(\.mission).first { $0.id == id }
    }

    /// Sélectionne un onglet et relit sa première page, comme le web (`setPage(0)`) ; liste conservée
    /// pendant la relecture si elle était déjà affichée.
    public func selectionner(_ onglet: MesMissionsOnglet) async {
        self.onglet = onglet
        await lire(onglet, page: 0, suite: false)
    }

    /// Relit l'onglet affiché avec les pages déjà chargées (apparition, tirer pour actualiser,
    /// « Réessayer », « Vérifier ma session ») ; première page si rien n'est encore affiché.
    public func charger() async {
        await lire(onglet, page: pageChargee(onglet), suite: false)
    }

    /// Une page de plus pour l'onglet affiché, si la dernière lecture était pleine (À venir, Passées).
    public func chargerPlus() async {
        let liste: Liste<Mission>
        switch onglet {
        case .candidatures: return
        case .aVenir: liste = aVenir
        case .passees: liste = passees
        }
        guard liste.estChargee, liste.aSuivre, !liste.chargementSuite, !liste.rafraichissement else { return }
        await lire(onglet, page: liste.page + 1, suite: true)
    }

    /// Pages déjà affichées de l'onglet (les candidatures ne sont pas paginées, comme le web).
    private func pageChargee(_ onglet: MesMissionsOnglet) -> Int {
        switch onglet {
        case .candidatures: return 0
        case .aVenir: return aVenir.estChargee ? aVenir.page : 0
        case .passees: return passees.estChargee ? passees.page : 0
        }
    }

    /// « Vérifier ma session » : revalide la session, puis relit l'onglet si elle est toujours prête
    /// pour l'epoch de cet écran (même règle que `AccueilModel.verifierSession`).
    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await charger()
    }

    // MARK: - Lecture

    /// Page lue par un port, ramenée à une forme commune aux trois onglets.
    private struct PageLue<Element: Sendable>: Sendable {
        var elements: [Element]
        var aSuivre: Bool
        var finances: [String: MissionGainLigne]
    }

    /// Lit les pages 0…`page` de l'onglet. `suite` : « Charger plus » (indicateur et erreur propres au
    /// bouton) ; sinon première lecture ou relecture de la liste affichée.
    private func lire(_ onglet: MesMissionsOnglet, page: Int, suite: Bool) async {
        switch onglet {
        case .candidatures:
            await lire(\.candidatures, onglet: onglet, page: 0, suite: false) { port, context in
                PageLue(elements: try await port.candidatures(context: context), aSuivre: false, finances: [:])
            }
        case .aVenir:
            await lire(\.aVenir, onglet: onglet, page: page, suite: suite) { port, context in
                let lue = try await port.aVenir(context: context, page: page)
                return PageLue(elements: lue.missions, aSuivre: lue.aSuivre, finances: [:])
            }
        case .passees:
            await lire(\.passees, onglet: onglet, page: page, suite: suite) { port, context in
                let lue = try await port.passees(context: context, page: page)
                return PageLue(elements: lue.missions, aSuivre: lue.aSuivre, finances: lue.finances)
            }
        }
    }

    private func lire<Element: Equatable & Sendable & Identifiable>(
        _ cle: ReferenceWritableKeyPath<MesMissionsModel, Liste<Element>>,
        onglet: MesMissionsOnglet,
        page: Int,
        suite: Bool,
        requete: @escaping @Sendable (any MesMissionsPort, MissionReadContext) async throws -> PageLue<Element>
    ) async where Element.ID == String {
        let courant = (generations[onglet] ?? 0) + 1
        generations[onglet] = courant
        let conserver = self[keyPath: cle].estChargee
        if suite {
            self[keyPath: cle].chargementSuite = true
            self[keyPath: cle].erreurSuite = nil
        } else {
            // Une lecture de la liste remplace toute lecture en vol de l'onglet, « Charger plus » compris.
            self[keyPath: cle].chargementSuite = false
            self[keyPath: cle].erreurSuite = nil
            self[keyPath: cle].erreurRafraichissement = nil
            if conserver { self[keyPath: cle].rafraichissement = true } else { self[keyPath: cle].contenu = .chargement }
        }
        // Une lecture dépassée n'éteint pas les indicateurs de la lecture qui l'a remplacée.
        defer {
            if generations[onglet] == courant {
                self[keyPath: cle].rafraichissement = false
                self[keyPath: cle].chargementSuite = false
            }
        }

        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        guard generations[onglet] == courant, !Task.isCancelled else { return }
        horloge = gateways.clock
        let port = gateways.mesMissions
        let context = snapshot.context
        do {
            let lue = try await bounded(timeout: controller.resolutionTimeout) { try await requete(port, context) }
            guard await controller.epoch == snapshot.epoch, generations[onglet] == courant else { return }
            sessionExpired = false
            var liste = self[keyPath: cle]
            // Lecture cumulative : la liste est remplacée, jamais complétée localement. Un identifiant
            // répété (impossible sous la contrainte serveur, défensif pour `ForEach`) garde sa première ligne.
            var vus = Set<String>()
            liste.contenu = .chargee(lue.elements.filter { vus.insert($0.id).inserted })
            liste.page = page
            liste.aSuivre = lue.aSuivre
            self[keyPath: cle] = liste
            if onglet == .passees { finances = lue.finances }
        } catch {
            guard await controller.epoch == snapshot.epoch, generations[onglet] == courant, !Task.isCancelled else { return }
            let message: String
            if let jolene = error as? JoleneError {
                if jolene.kind == .cancelled { return }
                sessionExpired = jolene.kind == .unauthorized
                message = jolene.message
            } else if error is CancellationError {
                return
            } else {
                // Une panne quelconque n'est pas une session expirée (revue B8 de T5).
                sessionExpired = false
                message = Self.genericFailureMessage
            }
            if suite {
                self[keyPath: cle].erreurSuite = message
            } else if conserver {
                self[keyPath: cle].erreurRafraichissement = message
            } else {
                self[keyPath: cle].contenu = .echec(message)
            }
        }
    }
}
