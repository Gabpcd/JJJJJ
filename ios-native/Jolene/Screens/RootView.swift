import SwiftUI
import JoleneCore
import JoleneDesign

/// Aiguillage racine : garde d'environnement puis état de session.
///
/// Lot 1 (T4a, revue) : le fond de carte (`carteTuiles`) est injecté ICI, depuis le mode de
/// l'environnement, pour que toute surface de la fenêtre en hérite (onglets, feuilles, futur
/// coordinateur de liens T10). Aucune tuile Apple Plans en démonstration (aucune requête réseau).
struct RootView: View {
    @ObservedObject var container: AppContainer

    var body: some View {
        aiguillage
            .environment(\.carteTuiles, CarteTuiles.pour(modeDemo: container.isDemo))
            // Lot 2 T5a : mémoire « note déjà proposée » (en mémoire en démo, `UserDefaults` sinon).
            .environment(\.memoireNotation, container.memoireNotation)
    }

    @ViewBuilder private var aiguillage: some View {
        if let error = container.environmentError {
            EnvironmentBlockedScreen(error: error, mode: container.environment.mode,
                                     unknownModeRaw: container.environment.unknownModeRaw)
        } else if let session = container.session {
            SessionRootView(container: container, session: session, finDeCompte: container.finDeCompte,
                            liens: container.liensInscription)
        } else {
            EnvironmentBlockedScreen(error: JoleneError(.environment, "Configuration de l'application invalide."),
                                     mode: container.environment.mode)
        }
    }
}

/// Lot 3, T7 (propriétaire unique de ce fichier au lot 3) — inscription soignant :
/// - `.signedOut` : « Créer un compte soignant » (`login-create-account`) remplace la connexion par le compte rapide
///   (`InscriptionRapideScreen`) ; « Se connecter », « J’ai confirmé mon email » et « Se connecter et continuer »
///   ramènent à la connexion avec l'adresse saisie (la connexion par mot de passe passe par `SessionStore.signIn`) ;
/// - `.blocked` d'une identité sans espace soignant (rôle `INCONNU` ou profil incomplet,
///   `OnboardingResolution.concerne`) : aiguillage d'onboarding (`OnboardingRootView`) au lieu de l'écran bloquant ;
///   tout autre `.blocked` garde l'écran du lot 0 ; `SessionController` et `MobileAccess` sont inchangés ;
/// - liens d'inscription déposés par le coordinateur des liens (`BoiteLiensInscription`, L3-T3b, intégration du lot 3) :
///   confirmation présentée au-dessus de tout état, puis relecture de la session ; `/inscription/soignant` hors
///   session ouvre le compte rapide, profession du lien pré-remplie.
///
/// Lot 3, T8 (propriétaire de ce fichier dans sa vague) — complétion du profil : une finalisation en attente
/// (`register-soignant` 503 `ACCOUNT_FINALIZATION_PENDING`, ou session non rafraîchie) déconnecte localement ; son
/// message (verbatim serveur ou web) est affiché sur l'écran de connexion (`login-error`) jusqu'à la session suivante.
private struct SessionRootView: View {
    let container: AppContainer
    @ObservedObject var session: SessionStore
    /// Lot 1, T8 : signalé avant que la suppression de compte ne retire la session ; tant qu'il n'est
    /// pas acquitté, l'écran de fin remplace la connexion (jamais « Votre session a expiré »).
    @ObservedObject var finDeCompte: AvisFinDeCompte
    /// Lot 3, T7 : liens d'inscription reçus hors de l'espace prêt.
    @ObservedObject var liens: BoiteLiensInscription
    @State private var loginEmail = ""
    /// Lot 3, T7 : compte rapide affiché à la place de la connexion (page et query du lien éventuel).
    @State private var inscription: EtapeInscription?
    /// Lot 3, T8 : message de la déconnexion locale d'une finalisation en attente, affiché à la connexion.
    @State private var messageConnexion: String?

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
                } else if let etape = inscription {
                    InscriptionRapideScreen(controller: session.controller,
                                            profession: InscriptionRules.professionDepuisLien(etape),
                                            seConnecter: { email in
                                                loginEmail = email
                                                inscription = nil
                                            }, issue: suivre)
                } else {
                    LoginScreen(email: $loginEmail, errorMessage: message ?? messageConnexion, isDemo: container.isDemo,
                                retryRestore: session.canRetryRestore ? { await session.start() } : nil,
                                creerCompte: { inscription = EtapeInscription(page: .soignant, query: nil) }) { email, password in
                        await session.signIn(email: email, password: password)
                    }
                }
            case let .blocked(access) where OnboardingResolution.concerne(access):
                OnboardingRootView(session: session, annoncerDeconnexion: { messageConnexion = $0 })
            case let .blocked(access):
                BlockingScreen(
                    title: "Espace non disponible",
                    message: access.sessionMessage ?? "Cet espace n'est pas encore disponible dans l'application.",
                    identifier: "access-blocked",
                    secondaryTitle: "Se déconnecter",
                    secondaryIdentifier: "logout-button",
                    secondaryAction: { Task { await session.signOut() } },
                    // Lot 3, T4 : désactivation du token (jusqu'à 2,5 s) avant la révocation : attente visible,
                    // pas de second tap (`SessionStore.deconnexionEnCours`, qui ignore aussi un second appel).
                    secondaryIsLoading: session.deconnexionEnCours)
            case let .ready(snapshot):
                MainTabView(container: container, session: session, snapshot: snapshot)
                    .id(snapshot.epoch)
            }
        }
        .task { if case .idle = session.state { await session.start() } }
        .onAppear { consommer(liens.inscription) }
        .onChange(of: liens.inscription) { etape in consommer(etape) }
        // Intégration du lot 3 : un lien reçu au lancement (restauration en cours) attend l'issue de la session.
        .onChange(of: session.state) { etat in
            consommer(liens.inscription)
            // T8 : le message de la déconnexion locale ne vaut que pour l'écran de connexion qui la suit.
            if case .signedOut = etat {} else { messageConnexion = nil }
        }
        .fullScreenCover(item: confirmation) { demande in
            ConfirmationInscriptionScreen(controller: session.controller, credentials: demande.credentials) { confirme in
                liens.retirerConfirmation()
                // Intégration T7 × T3b (revue B8 de T3b, m4) : identité ouverte hors de `signIn`, le navigateur intégré
                // est vidé avant la relecture.
                if confirme { Task { await session.ouvrirIdentiteInscription() } }
            }
        }
    }

    /// Confirmation déposée par le coordinateur ; la fermer la retire de la boîte.
    private var confirmation: Binding<BoiteLiensInscription.Confirmation?> {
        Binding(get: { liens.confirmation }, set: { nouvelle in
            if nouvelle == nil { liens.retirerConfirmation() }
        })
    }

    /// Suite du compte rapide : connexion par mot de passe (aiguillage selon l'espace relu) ou relecture de la session
    /// après un parcours démarré.
    private func suivre(_ issue: InscriptionRapideModel.Issue) {
        inscription = nil
        switch issue {
        case let .connexion(email, motDePasse):
            loginEmail = email
            Task { await session.signIn(email: email, password: motDePasse) }
        case .parcoursDemarre:
            // Compte créé avec session (`signUp`) : identité ouverte hors de `signIn` (intégration T7 × T3b, revue B8
            // de T3b, m4), le navigateur intégré est vidé avant la relecture.
            Task { await session.ouvrirIdentiteInscription() }
        }
    }

    /// Lien `/inscription/soignant` ou `/inscription/reprendre` déposé par le coordinateur : hors session, la page
    /// soignant ouvre le compte rapide et la reprise la connexion (web : `Navigate to /connexion`) ; avec une identité,
    /// l'aiguillage d'onboarding (ou l'espace prêt) est déjà l'écran de la session. Intégration du lot 3 : un lien reçu
    /// pendant la restauration (lancement à froid, `-JOLENE_OPEN_URL`) reste dans la boîte jusqu'à l'issue de la
    /// session (`onChange(of: session.state)`), au lieu d'être écarté avant de savoir s'il y a une identité.
    private func consommer(_ etape: EtapeInscription?) {
        guard let etape else { return }
        switch session.state {
        case .idle, .loading:
            return
        case .signedOut:
            liens.retirerInscription()
            guard finDeCompte.issue == nil else { return }
            inscription = etape.page == .soignant ? etape : nil
        case .blocked, .ready:
            liens.retirerInscription()
        }
    }
}
