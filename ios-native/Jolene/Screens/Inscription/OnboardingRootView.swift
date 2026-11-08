import SwiftUI
import JoleneCore
import JoleneDesign

/// Aiguillage d'onboarding (lot 3, T7) d'une identité sans espace soignant (`OnboardingResolution.concerne`) : port
/// de `src/pages/ParcoursInscription.tsx`. Pas d'exploration des missions avant le profil complet (D9) : chaque
/// état offre « Se déconnecter » (`logout-button`, attente visible de la désactivation push, consigne de T4).
/// - parcours soignant → complétion : **point d'extension de T8** (`CompletionProfilScreen`, `register-soignant`) ;
///   d'ici là, l'écran bloquant et le message existants du lot 0 pour un profil incomplet ;
/// - établissement → renvoi web (message existant du lot 0) ;
/// - ni parcours ni intention → « Choisissez votre espace… » ; « Je suis soignant » ouvre le compte rapide en mode
///   session ouverte (profession et consentement → `fn_demarrer_inscription`) ; « Je représente un établissement »
///   n'existe qu'avec le présentateur `.safari` du coordinateur des liens, L3-T3b (jamais un bouton sans effet) ;
/// - échec → texte web l.80 et « Réessayer ».
///
/// Identifiants : `onboarding-chargement`, `onboarding-completion`, `onboarding-etablissement`, `onboarding-screen`,
/// `onboarding-soignant`, `onboarding-etablissement-web`, `onboarding-erreur`, `onboarding-reessayer`, `logout-button`.
struct OnboardingRootView: View {
    @ObservedObject var session: SessionStore
    @StateObject private var model: OnboardingModel
    @State private var formulaireSoignant = false
    @Environment(\.presentateurRenvoiWeb) private var presentateur

    /// Inscription établissement, servie par le web (§1.2).
    private static let inscriptionEtablissement = URL(string: "https://jolene.app/inscription/etablissement")!

    init(session: SessionStore) {
        self.session = session
        _model = StateObject(wrappedValue: OnboardingModel(controller: session.controller))
    }

    private typealias T = InscriptionTextes

    var body: some View {
        contenu
            .task { await model.chargerSiNecessaire() }
            // Un `.blocked` d'une autre identité peut succéder à celui-ci sans démonter la vue : relecture.
            .onChange(of: session.state) { _ in Task { await model.chargerSiNecessaire() } }
    }

    @ViewBuilder private var contenu: some View {
        switch model.etat {
        case .chargement:
            ZStack {
                JoleneColor.softGradient.ignoresSafeArea()
                ProgressView("Chargement de votre espace")
                    .tint(JoleneColor.rose700)
                    .accessibilityIdentifier("onboarding-chargement")
            }
        case .completerSoignant:
            // Point d'extension T8 : complétion du profil puis `register-soignant`.
            ecranBloquant(acces: .unsupportedRole(SessionState.profilIncompletCode), identifiant: "onboarding-completion")
        case .espaceEtablissement:
            ecranBloquant(acces: .unsupportedRole(nil), identifiant: "onboarding-etablissement")
        case .choixEspace(let email):
            carte {
                Text(T.choisirEspace)
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                JoleneButton(T.jeSuisSoignant) { formulaireSoignant = true }
                    .accessibilityIdentifier("onboarding-soignant")
                if let presentateur {
                    JoleneButton(T.jeRepresenteEtablissement, style: .secondary) {
                        presentateur.presenter(.safari(Self.inscriptionEtablissement))
                    }
                    .accessibilityIdentifier("onboarding-etablissement-web")
                }
            }
            .sheet(isPresented: $formulaireSoignant) {
                InscriptionRapideScreen(controller: session.controller, mode: .sessionOuverte(email: email)) { _ in
                    formulaireSoignant = false
                    Task { await model.charger() }
                }
            }
        case .erreur:
            carte {
                InlineNotice(T.espaceIndisponible, tone: .error, identifier: "onboarding-erreur", announcesOnAppear: true)
                JoleneButton(T.reessayer) { Task { await model.charger() } }
                    .accessibilityIdentifier("onboarding-reessayer")
            }
        }
    }

    /// « Reprendre votre inscription » + contenu + « Se déconnecter » (l.95-128).
    private func carte<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        ZStack {
            JoleneColor.softGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                    Text(T.reprendreInscription)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    contenu()
                    JoleneButton(T.seDeconnecter, style: .secondary, isLoading: session.deconnexionEnCours) {
                        seDeconnecter()
                    }
                    .disabled(session.deconnexionEnCours)
                    .accessibilityIdentifier("logout-button")
                }
                .padding(JoleneSpacing.xl)
                .padding(.top, JoleneSpacing.xl)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("onboarding-screen")
        }
    }

    /// Écran bloquant du lot 0 (titre et messages existants) avec « Se déconnecter ».
    private func ecranBloquant(acces: MobileAccess, identifiant: String) -> some View {
        BlockingScreen(
            title: "Espace non disponible",
            message: acces.sessionMessage ?? "Cet espace n'est pas encore disponible dans l'application.",
            identifier: identifiant,
            secondaryTitle: T.seDeconnecter,
            secondaryIdentifier: "logout-button",
            secondaryAction: { seDeconnecter() },
            secondaryIsLoading: session.deconnexionEnCours)
    }

    private func seDeconnecter() {
        guard !session.deconnexionEnCours else { return }
        Task { await session.signOut() }
    }
}
