import SwiftUI
import SafariServices
import JoleneCore
import JoleneDesign

/// Coordinateur des liens (lot 1 T10, reliquat lot 3 T3b ; `DECISIONS_LOT3.md`, section T3b) : point d'entrée
/// unique des liens universels (`onOpenURL`, `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`), de l'argument
/// DEBUG `-JOLENE_OPEN_URL` (`AppContainer`) et des taps push (`BoiteTapsPush`, relue par l'espace prêt).
///
/// La décision vit dans JoleneCore (`DeepLinkIntent`, `AiguillageLiens`, `PresentationsRacine`, niveau 1 :
/// `DeepLinkIntentTests`, `PresentationsRacineTests`) ; le coordinateur exécute ses actions :
/// - navigation dans l'espace prêt : `demande` (cible `CibleNotification` + epoch), exécutée par
///   `MainTabView.presenter` (onglet, retour à la racine, écran empilé) puis acquittée ; une demande d'un autre epoch
///   n'est jamais exécutée ;
/// - renvoi web : présentateur `.safari` de l'app (`PresentateurRenvoiWeb`, injecté à la racine par
///   `PointDEntreeLiens`) — `SFSafariViewController` en staging/production, double démo sans réseau
///   (`renvoi-web-demo`, URL lue dans `renvoi-web-url`) ; jamais `openURL` (les chemins `/soignant/*` reviendraient
///   dans l'app par lien universel) ;
/// - refus d'un lien de réinitialisation PKCE (option B, décision 7 du lot 1) : alerte au texte décidé, présentée
///   après la fermeture d'un renvoi affiché, un item numéroté par refus (revue B8 de T3b, m1) ;
/// - (intégration de T7) confirmation d'inscription et pages `/inscription/soignant` / `reprendre` : déposées dans
///   `BoiteLiensInscription`, présentées hors de l'espace par `RootView` (confirmation au-dessus de tout état, compte
///   rapide sur l'écran de connexion une fois la session résolue) ;
/// - fin d'identité native (`FinIdentiteWebPort`, appelé par `SessionStore` ; revue B8 de T3b, M1) : le renvoi affiché
///   est fermé, puis, hors démo, le magasin de données du navigateur intégré est effacé
///   (`SFSafariViewController.DataStore.default.clearWebsiteData`, iOS 16) ; un renvoi demandé pendant l'effacement
///   est différé jusqu'à sa fin. En démo, aucun effacement (le double n'a ni réseau ni données).
///
/// L'anti-boucle (« un `.safari` issu de l'app n'est jamais rejoué comme lien universel ») et le libellé DEBUG
/// `deeplink-route` ne sont posés qu'à la présentation effective (revue B8 de T3b, m1 et m7) : apparition du contenu
/// de la feuille pour un renvoi, exécution par l'espace (`demandeTraitee`) pour une navigation.
///
/// DEBUG et démo seulement : libellé `deeplink-route` de la dernière route présentée (format de
/// `PushTapIntent.libelleDebug` : cas de route, identifiant ou URL canonique ; données de démonstration, jamais en
/// STAGING où elles seraient réelles, revue L3-T5 m8). Il remplace `push-tap-cible` de L3-T5 (consigne de T5) ; et
/// `-JOLENE_OPEN_URL_SUIVANT` (lien remis par le double du renvoi, `renvoi-web-lien-suivant`, revue B8 de T3b, m1).
///
/// Limite connue : la feuille et l'alerte sont présentées par la racine ; tant qu'une autre feuille est ouverte (filtres
/// d'Explorer), elles ne s'affichent pas par-dessus (une seule feuille par niveau en SwiftUI). Aucun état ne reste
/// collé : le même lien est redemandé sous un nouvel item, un refus suivant est un nouvel item (`PresentationsRacine`).
@MainActor
final class DeepLinkCoordinator: ObservableObject, PresentateurRenvoiWeb, FinIdentiteWebPort {
    /// Navigation demandée à l'espace prêt de `epoch`.
    struct DemandeNavigation: Equatable {
        let numero: Int
        let epoch: Int
        let cible: CibleNotification
        /// Destination effective (libellé DEBUG `deeplink-route`, posé quand l'espace exécute la demande).
        let route: JoleneRoute
    }

    @Published private(set) var demande: DemandeNavigation?
    /// Feuille du renvoi web et alerte du refus (`PresentationsRacine`, niveau 1).
    @Published private(set) var presentations = PresentationsRacine()
    /// Libellé DEBUG de la dernière route présentée (`deeplink-route`), démo seulement.
    @Published private(set) var derniereRoute: String?
    /// `-JOLENE_OPEN_URL_SUIVANT` (DEBUG, démo) : lien remis par le double du renvoi web (`renvoi-web-lien-suivant`).
    @Published private(set) var lienSuivantDemo: URL?

    let estDemo: Bool
    private let aiguillage: AiguillageLiens
    /// Liens d'inscription consommés hors de l'espace (intégration de T7) : déposés ici, présentés par `RootView`.
    private let inscription: BoiteLiensInscription
    /// Effacement du magasin du navigateur intégré (nil en démo : aucun effet).
    private let effaceur: EffaceurDonneesWeb?
    private var numero = 0
    /// Lien reçu au lancement, avant que la racine ne soit affichée (`-JOLENE_OPEN_URL`, lu par `AppContainer.init`).
    private var lienAuLancement: URL?
    private var racineAffichee = false

    init(taps: BoiteTapsPush, inscription: BoiteLiensInscription, estDemo: Bool, effaceur: EffaceurDonneesWeb?) {
        self.estDemo = estDemo
        self.inscription = inscription
        self.effaceur = estDemo ? nil : effaceur
        aiguillage = AiguillageLiens(taps: taps)
    }

    // MARK: Points d'entrée

    /// Lien universel (`onOpenURL`, `onContinueUserActivity`).
    func recevoir(url: URL) {
        executer(aiguillage.recevoir(url: url))
    }

    /// Lien universel simulé à froid (`-JOLENE_OPEN_URL`, DEBUG) : reçu dès que la racine est affichée, pour qu'un
    /// renvoi web présenté aussitôt ait une fenêtre où s'afficher (un lien de l'espace est de toute façon mémorisé).
    func recevoirAuLancement(url: URL) {
        if racineAffichee { recevoir(url: url) } else { lienAuLancement = url }
    }

    /// `-JOLENE_OPEN_URL_SUIVANT` (DEBUG, démo seulement) : lien remis par le double du renvoi web.
    func preparerLienSuivantDemo(_ url: URL) {
        guard estDemo else { return }
        lienSuivantDemo = url
    }

    /// Bouton `renvoi-web-lien-suivant` du double démo : le lien est reçu comme un lien universel, une seule fois.
    func remettreLienSuivantDemo() {
        guard estDemo, let url = lienSuivantDemo else { return }
        lienSuivantDemo = nil
        recevoir(url: url)
    }

    /// Apparition de la racine de la fenêtre (`PointDEntreeLiens`).
    func racineVisible() {
        racineAffichee = true
        guard let url = lienAuLancement else { return }
        lienAuLancement = nil
        recevoir(url: url)
    }

    /// La boîte des taps a avancé (`BoiteTapsPush.tapsRecus`, observé par l'espace prêt).
    func tapRecu() {
        executer(aiguillage.tapRecu())
    }

    /// Apparition de l'espace prêt : rejoue l'intention en attente (lien ou tap) pour cet epoch.
    func espaceOuvert(_ snapshot: SessionSnapshot) {
        executer(aiguillage.ouvrirEspace(snapshot))
    }

    /// Disparition de l'espace de cet epoch : une demande non exécutée est abandonnée.
    func espaceFerme(epoch: Int) {
        aiguillage.fermerEspace(epoch: epoch)
        if demande?.epoch == epoch { demande = nil }
    }

    /// La demande a été exécutée par l'espace (une seule fois) : sa route est alors effectivement présentée.
    func demandeTraitee(_ traitee: DemandeNavigation) {
        guard demande == traitee else { return }
        demande = nil
        noter(traitee.route)
    }

    // MARK: Présentateur `.safari`

    /// Présente `route` (`.safari`, `.etablissement`) dans une feuille ; sans effet pour une route native.
    func presenter(_ route: JoleneRoute) {
        presentations.demanderRenvoi(route)
    }

    func fermerRenvoiWeb() {
        presentations.fermerRenvoi()
    }

    /// Contenu de la feuille `id` apparu : anti-boucle et libellé DEBUG posés ici, jamais à la demande.
    func renvoiApparu(_ id: Int) {
        guard let route = presentations.apparition(id) else { return }
        aiguillage.renvoiWebPresente(route)
        noter(route)
    }

    /// Contenu de la feuille `id` disparu : l'anti-boucle est levé s'il s'agissait du renvoi affiché.
    func renvoiDisparu(_ id: Int) {
        if presentations.disparition(id) { aiguillage.renvoiWebFerme() }
    }

    /// Fin de la présentation de la feuille (`onDismiss`) : un refus en attente est présenté.
    func renvoiCongedie() {
        presentations.congediement()
    }

    /// Alerte du refus fermée par l'utilisateur.
    func refusAcquitte(_ id: Int) {
        presentations.refusAcquitte(id)
    }

    // MARK: Fin d'identité (revue B8 de T3b, M1)

    func identiteTerminee() {
        fermerRenvoiWeb()
        guard let effaceur else { return }
        presentations.debutEffacement()
        effaceur.effacer { [weak self] in self?.presentations.finEffacement() }
    }

    // MARK: Exécution

    /// Exécute une action de l'aiguillage. Une navigation ou un refus ferment d'abord le renvoi web affiché : le
    /// dernier lien reçu doit être visible, jamais caché sous une feuille plus ancienne.
    private func executer(_ action: AiguillageLiens.Action?) {
        switch action {
        case let .naviguer(cible, route, epoch)?:
            fermerRenvoiWeb()
            numero += 1
            demande = DemandeNavigation(numero: numero, epoch: epoch, cible: cible, route: route)
        case .renvoiWeb(let route)?:
            presenter(route)
        case .refusReinitialisation?:
            presentations.refuser()
        case .inscription(let lien)?:
            // Intégration de T7 : confirmation ou page d'inscription, présentée hors de l'espace par `RootView`
            // (`BoiteLiensInscription`) ; le renvoi affiché est fermé d'abord, comme pour une navigation.
            fermerRenvoiWeb()
            inscription.recevoir(lien)
        case nil:
            break
        }
    }

    private func noter(_ route: JoleneRoute) {
        #if DEBUG
        if estDemo { derniereRoute = PushTapIntent.libelleDebug(route) }
        #endif
    }
}

/// Effacement du magasin de données du navigateur intégré (revue B8 de T3b, M1), injecté hors démo.
@MainActor
protocol EffaceurDonneesWeb: AnyObject {
    /// Efface cookies, cache et stockage local accumulés par les `SFSafariViewController` de l'app, puis appelle `fin`
    /// sur le main actor.
    func effacer(puis fin: @escaping @MainActor @Sendable () -> Void)
}

/// `SFSafariViewController.DataStore.default` (iOS 16.0, cible de déploiement de l'app) : « website data accrued from
/// browsing activity within your app », stockage local, ressources en cache et cookies compris
/// (`SFSafariViewControllerDataStore.h`).
@MainActor
final class EffaceurDonneesSafari: EffaceurDonneesWeb {
    func effacer(puis fin: @escaping @MainActor @Sendable () -> Void) {
        SFSafariViewController.DataStore.default.clearWebsiteData {
            Task { @MainActor in fin() }
        }
    }
}

/// Branchements de la racine (`JoleneApp`) : présentateur `.safari` dans l'environnement, entrées des liens
/// universels, feuille du renvoi web, alerte du refus de réinitialisation, libellé DEBUG `deeplink-route`.
struct PointDEntreeLiens: ViewModifier {
    @ObservedObject var coordinateur: DeepLinkCoordinator

    func body(content: Content) -> some View {
        content
            .environment(\.presentateurRenvoiWeb, coordinateur)
            .environment(\.presentationPageWeb, coordinateur.estDemo ? .doubleDemo : .safari) // L3-TJ (TJ3)
            .onAppear { coordinateur.racineVisible() }
            .onOpenURL { url in coordinateur.recevoir(url: url) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activite in
                guard let url = activite.webpageURL else { return }
                coordinateur.recevoir(url: url)
            }
            .sheet(item: liaisonRenvoi, onDismiss: { coordinateur.renvoiCongedie() }) { renvoi in
                contenuRenvoi(renvoi)
                    .onAppear { coordinateur.renvoiApparu(renvoi.id) }
                    .onDisappear { coordinateur.renvoiDisparu(renvoi.id) }
            }
            // Un hôte par refus (`.id`) : un refus jamais affiché (feuille ouverte ailleurs) ne fait pas taire le suivant.
            .background {
                HoteRefusReinitialisation(refus: coordinateur.presentations.refus) { coordinateur.refusAcquitte($0) }
                    .id(coordinateur.presentations.refus?.id ?? 0)
            }
            #if DEBUG
            .overlay(alignment: .topLeading) {
                if coordinateur.estDemo, let route = coordinateur.derniereRoute {
                    Text(route)
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("deeplink-route")
                }
            }
            #endif
    }

    /// Item de la feuille : `PresentationsRacine.renvoi` ; une fermeture par l'utilisateur (balayage) le retire.
    private var liaisonRenvoi: Binding<PresentationsRacine.Renvoi?> {
        Binding(get: { coordinateur.presentations.renvoi },
                set: { nouveau in if nouveau == nil { coordinateur.fermerRenvoiWeb() } })
    }

    @ViewBuilder
    private func contenuRenvoi(_ renvoi: PresentationsRacine.Renvoi) -> some View {
        if coordinateur.estDemo {
            RenvoiWebDemoScreen(url: renvoi.url, lienSuivant: coordinateur.lienSuivantDemo,
                                remettreLienSuivant: { coordinateur.remettreLienSuivantDemo() },
                                fermer: { coordinateur.fermerRenvoiWeb() })
        } else {
            RenvoiWebSafari(url: renvoi.url) { coordinateur.fermerRenvoiWeb() }
                .ignoresSafeArea()
        }
    }
}

/// Page web d'une **feuille locale** (L3-TJ, décision TJ3) : contenu identique au renvoi web du coordinateur —
/// `SFSafariViewController` (« Fermer » de Safari → `fermer`) en staging et production, double démo sans réseau
/// (`renvoi-web-demo`, `renvoi-web-url`, `renvoi-web-fermer`) en démo, selon `presentationPageWeb` posé à la racine.
/// Réservée aux écrans eux-mêmes présentés en feuille (pages `/cgu` et `/confidentialite` du consentement à
/// l'inscription, T7) ; partout ailleurs, une page web passe par le présentateur `.safari` du coordinateur.
struct PageWebLocale: View {
    let url: URL
    let fermer: () -> Void
    @Environment(\.presentationPageWeb) private var presentation

    var body: some View {
        switch presentation {
        case .doubleDemo:
            RenvoiWebDemoScreen(url: url, lienSuivant: nil, remettreLienSuivant: {}, fermer: fermer)
        case .safari:
            RenvoiWebSafari(url: url, fermer: fermer)
                .ignoresSafeArea()
        }
    }
}

/// Hôte de l'alerte du refus de réinitialisation (option B, décision 7 du lot 1), recréé pour chaque refus.
private struct HoteRefusReinitialisation: View {
    let refus: PresentationsRacine.Refus?
    let acquitter: (Int) -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .alert(DeepLinkIntent.Textes.reinitialisationRefusee, isPresented: affichee) {
                Button(DeepLinkIntent.Textes.fermer, role: .cancel) {}
            }
    }

    private var affichee: Binding<Bool> {
        Binding(get: { refus != nil },
                set: { visible in if !visible, let refus { acquitter(refus.id) } })
    }
}

/// Renvoi web réel : `SFSafariViewController` (ne déclenche pas le lien universel de l'URL chargée).
private struct RenvoiWebSafari: UIViewControllerRepresentable {
    let url: URL
    let fermer: () -> Void

    func makeCoordinator() -> Delegue { Delegue(fermer: fermer) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controleur = SFSafariViewController(url: url, configuration: configuration)
        controleur.dismissButtonStyle = .close
        controleur.delegate = context.coordinator
        return controleur
    }

    func updateUIViewController(_ controleur: SFSafariViewController, context: Context) {}

    @MainActor
    final class Delegue: NSObject, SFSafariViewControllerDelegate {
        private let fermer: () -> Void

        init(fermer: @escaping () -> Void) {
            self.fermer = fermer
        }

        nonisolated func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            MainActor.assumeIsolated { fermer() }
        }
    }
}

/// Double démo du renvoi web (aucune requête réseau, sentinelle « 0 requête ») : l'URL qui serait ouverte, lue par les
/// XCUITest (`renvoi-web-url`), et « Fermer » (`renvoi-web-fermer`). Données de démonstration seulement. DEBUG : le
/// lien de `-JOLENE_OPEN_URL_SUIVANT` (son URL pour libellé, `renvoi-web-lien-suivant`) est remis comme un lien
/// universel reçu pendant le renvoi (revue B8 de T3b, m1).
private struct RenvoiWebDemoScreen: View {
    let url: URL
    let lienSuivant: URL?
    let remettreLienSuivant: () -> Void
    let fermer: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                Text(url.absoluteString)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.midnight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("renvoi-web-url")
                #if DEBUG
                if let lienSuivant {
                    Button(lienSuivant.absoluteString, action: remettreLienSuivant)
                        .font(JoleneFont.caption)
                        .frame(minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("renvoi-web-lien-suivant")
                }
                #endif
                Spacer(minLength: 0)
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(JoleneColor.softGradient.ignoresSafeArea())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("renvoi-web-demo")
            .navigationTitle(url.host ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DeepLinkIntent.Textes.fermer, action: fermer)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("renvoi-web-fermer")
                }
            }
        }
    }
}
