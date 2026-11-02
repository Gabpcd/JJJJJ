import Foundation
import Combine

/// Façade `ObservableObject` du contrôleur de session pour SwiftUI. Chaque
/// opération délègue à l'acteur puis publie l'état renvoyé sur le main actor.
///
/// Lot 1, T9 (session durcie, `LOT1_PLAN.md` §2.5) — ce que la façade ajoute autour de l'acteur,
/// sans jamais en dériver une autorisation :
/// - **verrou biométrique** (décision 1) : `BiometricGate` évalué avant chaque `start()` (lancement,
///   reprise après 30 minutes, « Réessayer sans mot de passe ») ; refus → `lockForBiometrics()` ;
/// - **drapeaux d'écran** (décision 15) : `ecrans` lu avec la session, AVANT la publication d'un
///   `.ready` (un onglet coupé n'est jamais monté), et relu à chaque reprise ;
/// - **audit** (décision 5, comme `AuthContext.tsx` l.169-210) : après une connexion explicite qui
///   ouvre une session Auth, `fn_audit_connexion('CONNEXION')` puis, pour un soignant servi,
///   `fn_maj_activite_soignant()`, sans retenir la connexion ; avant la révocation,
///   `fn_audit_connexion('DECONNEXION')`. Chaque appel est borné à `resolutionTimeout` et best-effort :
///   aucune erreur n'est affichée, aucun renvoi, et une restauration n'est jamais auditée.
@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var state: SessionState
    /// Vrai quand la dernière restauration a échoué de façon transitoire : l'écran de
    /// connexion propose « Réessayer » (`start()`), sans redemander le mot de passe.
    @Published public private(set) var canRetryRestore = false
    /// Vrai pendant l'invite biométrique : la racine masque l'espace (reprise après 30 minutes).
    @Published public private(set) var deverrouillageEnCours = false
    public let controller: SessionController
    /// Verrou biométrique et préférences (écran Profil › Sécurité).
    public let biometrie: BiometricGate
    /// Drapeaux `ios_natif_<ecran>_actif` de la session courante.
    public let ecrans: EcransNatifsModel
    private var authEventsTask: Task<Void, Never>?
    private var deconnexionEnCours = false
    /// Audit de la dernière connexion, lancé sans être attendu (preuves des tests).
    private(set) var auditEnCours: Task<Void, Never>?

    public init(controller: SessionController, biometrie: BiometricGate = .inactif) {
        self.controller = controller
        self.biometrie = biometrie
        self.ecrans = EcransNatifsModel()
        self.state = .idle
    }

    /// Démarre ou revalide la session. Une session déjà prête n'est pas démontée pendant
    /// la vérification (pas de `.loading` intermédiaire : reprise après 30 minutes).
    public func start() async {
        guard !deverrouillageEnCours else { return }
        if !state.isReady { state = .loading }
        if biometrie.verrouAttendu {
            deverrouillageEnCours = true
            let issue = await biometrie.verifier()
            deverrouillageEnCours = false
            if issue == .refuse {
                state = await controller.lockForBiometrics()
                canRetryRestore = await controller.canRetryRestore
                return
            }
        }
        let resultat = await controller.start()
        await preparer(resultat)
        await publier()
    }

    public func signIn(email: String, password: String) async {
        state = .loading
        canRetryRestore = false
        let resultat = await controller.signIn(email: email, password: password)
        let epoch = await controller.epoch
        await preparer(resultat)
        await publier()
        lancerAuditConnexion(apres: resultat, epoch: epoch)
    }

    public func signOut() async {
        guard !deconnexionEnCours else { return }
        deconnexionEnCours = true
        defer { deconnexionEnCours = false }
        canRetryRestore = false
        await auditerDeconnexion()
        state = await controller.signOut()
        canRetryRestore = await controller.canRetryRestore
        biometrie.oublierIdentite()
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
                if event == .signedOut, case .signedOut = state {
                    // Le SDK a effacé la session : plus rien à déverrouiller au prochain lancement.
                    self.biometrie.oublierIdentite()
                }
                if case let .ready(snapshot) = state, snapshot.epoch != self.state.snapshot?.epoch {
                    // Nouvelle identité ouverte par le SDK : drapeaux relus avant l'affichage.
                    await self.preparer(state)
                    await self.publier()
                } else {
                    self.state = state
                    self.canRetryRestore = await controller.canRetryRestore
                }
            }
        }
    }

    /// Vrai tant que l'observation des événements d'auth est active.
    public var isObservingAuthEvents: Bool { authEventsTask != nil }

    // MARK: - Lot 1, T9

    /// Avant la publication d'un `.ready` : identité mémorisée pour le verrou, drapeaux lus.
    private func preparer(_ resultat: SessionState) async {
        guard case let .ready(snapshot) = resultat else { return }
        biometrie.memoriser(identite: snapshot.user.id)
        await ecrans.charger(snapshot: snapshot, controller: controller)
    }

    /// Publie l'état courant de l'acteur (il a pu changer pendant la lecture des drapeaux).
    private func publier() async {
        state = await controller.state
        canRetryRestore = await controller.canRetryRestore
    }

    /// Connexion explicite ayant ouvert une session Auth (`.ready`, ou `.blocked` : le web journalise
    /// toute connexion réussie) : CONNEXION, puis l'activité pour un soignant servi (`.ready`, le web
    /// la réserve au rôle SOIGNANT). Tâche non attendue ; chaque appel vérifie l'epoch de la connexion.
    private func lancerAuditConnexion(apres resultat: SessionState, epoch: Int) {
        let soignantServi: Bool
        switch resultat {
        case .ready: soignantServi = true
        case .blocked: soignantServi = false
        case .idle, .loading, .signedOut: return
        }
        let controller = self.controller
        auditEnCours = Task {
            guard let audit = await controller.gateways(for: epoch)?.audit else { return }
            let delai = controller.resolutionTimeout
            _ = try? await bounded(timeout: delai) { try await audit.connexion() }
            guard soignantServi, await controller.gateways(for: epoch) != nil else { return }
            _ = try? await bounded(timeout: delai) { try await audit.activite() }
        }
    }

    /// DECONNEXION avec le jeton encore valide, avant la révocation (`AuthContext.tsx` l.202-208) ;
    /// seulement si une identité est ouverte (espace prêt ou bloqué). Borné ; un échec n'empêche rien.
    private func auditerDeconnexion() async {
        let epoch: Int
        switch state {
        case let .ready(snapshot): epoch = snapshot.epoch
        case .blocked: epoch = await controller.epoch
        case .idle, .loading, .signedOut: return
        }
        guard let audit = await controller.gateways(for: epoch)?.audit else { return }
        _ = try? await bounded(timeout: controller.resolutionTimeout) { try await audit.deconnexion() }
    }
}
