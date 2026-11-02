import SwiftUI
import JoleneCore
import JoleneDesign

/// Aiguillage racine : garde d'environnement puis état de session.
struct RootView: View {
    @ObservedObject var container: AppContainer

    var body: some View {
        if let error = container.environmentError {
            EnvironmentBlockedScreen(error: error, mode: container.environment.mode,
                                     unknownModeRaw: container.environment.unknownModeRaw)
        } else if let session = container.session {
            SessionRootView(container: container, session: session, finDeCompte: container.finDeCompte)
        } else {
            EnvironmentBlockedScreen(error: JoleneError(.environment, "Configuration de l'application invalide."),
                                     mode: container.environment.mode)
        }
    }
}

private struct SessionRootView: View {
    let container: AppContainer
    @ObservedObject var session: SessionStore
    /// Lot 1, T8 : signalé avant que la suppression de compte ne retire la session ; tant qu'il n'est
    /// pas acquitté, l'écran de fin remplace la connexion (jamais « Votre session a expiré »).
    @ObservedObject var finDeCompte: AvisFinDeCompte
    @State private var loginEmail = ""

    var body: some View {
        Group {
            switch session.state {
            case .idle, .loading:
                ZStack {
                    JoleneColor.softGradient.ignoresSafeArea()
                    ProgressView("Chargement de votre espace")
                        .tint(JoleneColor.rose700)
                        .accessibilityIdentifier("session-loading")
                }
            case let .signedOut(message):
                if let fin = finDeCompte.issue {
                    CompteSupprimeScreen(fin: fin) { finDeCompte.acquitter() }
                } else {
                    LoginScreen(email: $loginEmail, errorMessage: message, isDemo: container.isDemo,
                                retryRestore: session.canRetryRestore ? { await session.start() } : nil) { email, password in
                        await session.signIn(email: email, password: password)
                    }
                }
            case let .blocked(access):
                BlockingScreen(
                    title: "Espace non disponible",
                    message: access.sessionMessage ?? "Cet espace n'est pas encore disponible dans l'application.",
                    identifier: "access-blocked",
                    secondaryTitle: "Se déconnecter",
                    secondaryIdentifier: "logout-button",
                    secondaryAction: { Task { await session.signOut() } })
            case let .ready(snapshot):
                MainTabView(container: container, session: session, snapshot: snapshot)
                    .id(snapshot.epoch)
            }
        }
        .task { if case .idle = session.state { await session.start() } }
    }
}
