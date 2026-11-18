import Foundation
import Combine

/// Modèle de l'onglet Accueil de l'espace établissement (lot 5, T4) : tableau de bord lu par
/// `gateways.etablissement.dashboard` pour l'epoch de la session, borné à `SessionController.resolutionTimeout`.
/// Mêmes règles d'état que `AccueilModel` (lot 1, T3) :
/// - une annulation de tâche SwiftUI n'est jamais une erreur ;
/// - un rafraîchissement garde le tableau affiché et n'expose qu'un `refreshError` ;
/// - `.unauthorized` lève `sessionExpired` (revalidation de session plutôt que « Réessayer ») ;
/// - une réponse reçue pour un epoch périmé, ou par un chargement dépassé, est abandonnée.
/// Relecture à l'apparition au-delà de `delaiRelecture` (web : `staleTime: 60_000`, l.449) et par pull-to-refresh.
///
/// Audit (D19) : chaque lecture réussie écrit `DONNEES_PERSO_CONSULTATION` (`fn_ecrire_audit_safe`, comme le web
/// l.421-426), best-effort par `EtabAuditPort` : jamais bloquant, jamais affiché, aucun doublon d'un audit serveur.
///
/// Les actions prioritaires ne sont pas calculées ici : la vue les dérive de l'instantané de session **courant**
/// (`PrioriteActions.liste`), si bien qu'une relecture des permissions à epoch constant re-filtre l'Accueil sans
/// relire le tableau de bord.
@MainActor
public final class EtabAccueilModel: ObservableObject {
    public enum State: Equatable, Sendable {
        case loading
        case loaded(EtabDashboardSnapshot)
        case failed(String)
    }

    public static let genericFailureMessage = "Le tableau de bord de votre établissement n'a pas pu être chargé. Vérifiez votre connexion puis réessayez."
    public static let delaiRelecture: TimeInterval = 60

    @Published public private(set) var state: State = .loading
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var refreshError: String?
    @Published public private(set) var sessionExpired = false
    public private(set) var chargeLe: Date?
    // Pas de propriété `horloge` (intégration de la vague C, revue B8 de #1160, m5) : aucune vue ne la lisait et les
    // formats du planning ne dépendent pas de maintenant ; l'horloge des gateways sert seulement à `chargeLe`.
    /// Dernière écriture d'audit lancée (preuve des tests ; jamais attendue par l'écran).
    public private(set) var dernierAudit: Task<Void, Never>?

    private let controller: SessionController
    private let snapshot: EtablissementSessionSnapshot
    private var generation = 0

    public init(controller: SessionController, snapshot: EtablissementSessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    public var tableau: EtabDashboardSnapshot? {
        if case let .loaded(tableau) = state { return tableau }
        return nil
    }

    public func load() async {
        generation += 1
        let courant = generation
        let refreshing: Bool
        if case .loaded = state { refreshing = true } else { refreshing = false }
        if refreshing { isRefreshing = true } else { state = .loading }
        refreshError = nil
        defer { if generation == courant { isRefreshing = false } }

        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        guard generation == courant else { return }
        let port = gateways.etablissement.dashboard
        let audit = gateways.etablissement.audit
        let context = snapshot.context
        let delai = controller.resolutionTimeout
        do {
            let tableau = try await bounded(timeout: delai) {
                try await port.tableauDeBord(context: context)
            }
            guard await controller.epoch == snapshot.epoch, generation == courant else { return }
            sessionExpired = false
            chargeLe = gateways.clock.now()
            state = .loaded(tableau)
            dernierAudit = Task {
                _ = try? await bounded(timeout: delai) {
                    try await audit.consultation(page: .tableauDeBord, context: context)
                }
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, generation == courant, !Task.isCancelled else { return }
            let message: String
            if let jolene = error as? JoleneError {
                if jolene.kind == .cancelled { return }
                sessionExpired = jolene.kind == .unauthorized
                message = jolene.message
            } else if error is CancellationError {
                return
            } else {
                message = Self.genericFailureMessage
            }
            if refreshing { refreshError = message } else { state = .failed(message) }
        }
    }

    /// « Vérifier ma session » : revalide la session, puis relit le tableau si elle reste prête pour cet epoch.
    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard case let .readyEtablissement(courant) = session.state, courant.epoch == snapshot.epoch else { return }
        await load()
    }

    /// Apparition de l'onglet : premier chargement (ou relance après une tâche annulée), ou relecture au-delà de
    /// `delaiRelecture`. Après un échec, seule l'action « Réessayer » relance (jamais de boucle à l'apparition).
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
