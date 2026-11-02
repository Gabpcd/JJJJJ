import Foundation
import Combine

/// Façade `ObservableObject` du contrôleur de session pour SwiftUI. Chaque
/// opération délègue à l'acteur puis publie l'état renvoyé sur le main actor.
@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var state: SessionState
    /// Vrai quand la dernière restauration a échoué de façon transitoire : l'écran de
    /// connexion propose « Réessayer » (`start()`), sans redemander le mot de passe.
    @Published public private(set) var canRetryRestore = false
    public let controller: SessionController
    private var authEventsTask: Task<Void, Never>?

    public init(controller: SessionController) {
        self.controller = controller
        self.state = .idle
    }

    /// Démarre ou revalide la session. Une session déjà prête n'est pas démontée pendant
    /// la vérification (pas de `.loading` intermédiaire : reprise après 30 minutes).
    public func start() async {
        if !state.isReady { state = .loading }
        state = await controller.start()
        canRetryRestore = await controller.canRetryRestore
    }

    public func signIn(email: String, password: String) async {
        state = .loading
        canRetryRestore = false
        state = await controller.signIn(email: email, password: password)
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
                self.state = state
                self.canRetryRestore = await controller.canRetryRestore
            }
        }
    }

    /// Vrai tant que l'observation des événements d'auth est active.
    public var isObservingAuthEvents: Bool { authEventsTask != nil }
}
