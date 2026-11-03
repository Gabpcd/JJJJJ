import Foundation
import Combine

/// Façade `ObservableObject` du contrôleur de session pour SwiftUI. Chaque
/// opération délègue à l'acteur puis publie l'état renvoyé sur le main actor.
///
/// Lot 5 (T2a) : avant la publication d'un `.readyEtablissement`, les drapeaux d'écran établissement
/// (`ecransEtablissement`, D14) sont lus — un écran coupé n'est jamais monté — et relus à chaque
/// reprise ; `refreshEtablissementScope()` relit le périmètre après un refus de droit (D12). Aucune
/// activité soignant (`fn_maj_activite_soignant`) n'est jamais déclenchée pour un établissement
/// (correction 12).
@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var state: SessionState
    /// Vrai quand la dernière restauration a échoué de façon transitoire : l'écran de
    /// connexion propose « Réessayer » (`start()`), sans redemander le mot de passe.
    @Published public private(set) var canRetryRestore = false
    public let controller: SessionController
    /// Drapeaux `ios_natif_etab_<ecran>_actif` de la session établissement courante (lot 5, T2a).
    public let ecransEtablissement = EcransEtablissementModel()
    private var authEventsTask: Task<Void, Never>?

    public init(controller: SessionController) {
        self.controller = controller
        self.state = .idle
    }

    /// Démarre ou revalide la session. Une session déjà prête n'est pas démontée pendant
    /// la vérification (pas de `.loading` intermédiaire : reprise après 30 minutes).
    public func start() async {
        if !state.isReady { state = .loading }
        state = await preparerEtablissement(await controller.start(), relire: true)
        canRetryRestore = await controller.canRetryRestore
    }

    public func signIn(email: String, password: String) async {
        state = .loading
        canRetryRestore = false
        state = await preparerEtablissement(await controller.signIn(email: email, password: password), relire: true)
    }

    /// Relecture du périmètre établissement après un refus de droit (`accesRefuse`, lot 5 T2a) : une
    /// lecture par appel ; l'écran l'appelle une fois par refus. Sans effet hors espace établissement.
    public func refreshEtablissementScope() async {
        guard let snapshot = state.snapshotEtablissement else { return }
        state = await preparerEtablissement(await controller.refreshEtablissementScope(epoch: snapshot.epoch), relire: false)
    }

    /// Lot 5 (T2a) : avant la publication d'un `.readyEtablissement`, drapeaux lus pour son epoch
    /// (toujours à la connexion et à la reprise, sinon seulement pour un epoch encore jamais lu), puis
    /// état courant de l'acteur republié (il a pu changer pendant la lecture). Tout autre état passe tel quel.
    private func preparerEtablissement(_ resultat: SessionState, relire: Bool) async -> SessionState {
        guard case let .readyEtablissement(snapshot) = resultat else { return resultat }
        guard relire || ecransEtablissement.epochCharge != snapshot.epoch else { return resultat }
        await ecransEtablissement.charger(snapshot: snapshot, controller: controller)
        return await controller.state
    }

    public func signOut() async {
        canRetryRestore = false
        state = await controller.signOut()
    }

    /// Relit l'état courant de l'acteur sans déclencher d'opération.
    public func refresh() async {
        state = await controller.state
        canRetryRestore = await controller.canRetryRestore
    }

    /// Relie le flux `AuthPort.authEvents()` au contrôleur : une session effacée par le SDK
    /// (révocation, déconnexion globale, refresh refusé) bascule l'écran sans action de
    /// l'utilisateur. Idempotent ; le flux vide des ports démo se termine aussitôt.
    public func observeAuthEvents() {
        guard authEventsTask == nil else { return }
        let controller = self.controller
        authEventsTask = Task { [weak self] in
            for await event in controller.authEvents() {
                let state = await controller.handleAuthEvent(event)
                guard let self else { return }
                self.state = await self.preparerEtablissement(state, relire: false)
                self.canRetryRestore = await controller.canRetryRestore
            }
        }
    }

    /// Vrai tant que l'observation des événements d'auth est active.
    public var isObservingAuthEvents: Bool { authEventsTask != nil }
}
