import Foundation
import Combine

/// Façade `ObservableObject` du contrôleur de session pour SwiftUI. Chaque
/// opération délègue à l'acteur puis publie l'état renvoyé sur le main actor.
///
/// Lot 3, T4 (blueprint `LOT3_PLAN.md` §2.5, correction 11, D2-D3) — crochets du coordinateur push,
/// optionnel (nil : comportement du lot 1 inchangé) :
/// - `.ready` d'un **nouvel** epoch publié, quel que soit le chemin (lancement, connexion, événement du
///   SDK) → `push.surReady` (tâche non attendue, `pushEnCours`) ; une revalidation du même epoch ne
///   relance rien (le retour au premier plan relève de `surActive`, appelé par l'app) ;
/// - `signOut` → `push.avantDeconnexion` (désactivation du token, JWT encore valide, bornée à 2,5 s,
///   puis désinscription locale) AVANT `controller.signOut()`, qui avance l'epoch avant le réseau ;
/// - `.signedOut` subi (événement du SDK traité par le contrôleur) et suppression de compte
///   (`signOutLocally`) → `push.surDeconnexionSubie` : désinscription locale seule, sans RPC.
/// Point d'extension laissé à L1-T9 (audit `DECONNEXION`, absent de cette base) : D3 le lance en
/// parallèle de la désactivation (`async let`), avant `controller.signOut()`.
@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var state: SessionState {
        didSet { signalerEspaceOuvert(depuis: oldValue) }
    }
    /// Vrai quand la dernière restauration a échoué de façon transitoire : l'écran de
    /// connexion propose « Réessayer » (`start()`), sans redemander le mot de passe.
    @Published public private(set) var canRetryRestore = false
    public let controller: SessionController
    /// Lot 3, T4 : coordinateur push (nil sans push, doubles de test du lot 1).
    public let push: PushCoordinator?
    /// Lot 3, T4 : enregistrement push lancé par le dernier `.ready` d'un nouvel epoch (preuves des tests).
    private(set) var pushEnCours: Task<Void, Never>?
    private var authEventsTask: Task<Void, Never>?

    public init(controller: SessionController, push: PushCoordinator? = nil) {
        self.controller = controller
        self.push = push
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
        // Lot 3, T4 : le token de cet appareil est désactivé tant que le JWT est valide (correction 11).
        await desactiverPushAvantDeconnexion()
        state = await controller.signOut()
    }

    /// Lot 3, T4 : fin de session locale après la suppression du compte (lot 1, T8, `LocalSignOut`) —
    /// désinscription push locale (aucune RPC : l'edge `delete-account` a révoqué le JWT), puis
    /// `controller.signOutLocally()` et relecture de l'état (comportement du lot 1 inchangé).
    public func signOutLocally() async {
        canRetryRestore = false
        await push?.surDeconnexionSubie()
        _ = await controller.signOutLocally()
        await refresh()
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
                let epochAvant = await controller.epoch
                let state = await controller.handleAuthEvent(event)
                guard let self else { return }
                // Lot 3, T4 : session effacée par le SDK et traitée par le contrôleur (epoch avancé) →
                // désinscription push locale, sans RPC (JWT absent). Ignoré après une déconnexion
                // volontaire (aucune identité active : epoch inchangé), déjà désinscrite.
                if event == .signedOut, case .signedOut = state, await controller.epoch != epochAvant {
                    await self.push?.surDeconnexionSubie()
                }
                self.state = state
                self.canRetryRestore = await controller.canRetryRestore
            }
        }
    }

    /// Vrai tant que l'observation des événements d'auth est active.
    public var isObservingAuthEvents: Bool { authEventsTask != nil }

    // MARK: - Lot 3, T4 (push)

    /// Nouvel espace prêt (epoch différent du précédent état publié) → enregistrement du token.
    private func signalerEspaceOuvert(depuis ancien: SessionState) {
        guard let push, case let .ready(snapshot) = state, snapshot.epoch != ancien.snapshot?.epoch else { return }
        pushEnCours = Task { await push.surReady(snapshot) }
    }

    /// Epoch de l'identité qui part (espace prêt ou bloqué : JWT présent), nil sans identité.
    private func desactiverPushAvantDeconnexion() async {
        guard let push else { return }
        let epoch: Int?
        switch state {
        case let .ready(snapshot): epoch = snapshot.epoch
        case .blocked: epoch = await controller.epoch
        case .idle, .loading, .signedOut: epoch = nil
        }
        await push.avantDeconnexion(epoch: epoch)
    }
}
