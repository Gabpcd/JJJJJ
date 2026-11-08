import SwiftUI
import SafariServices
import JoleneCore
import JoleneDesign

/// Coordinateur des liens (lot 1 T10, reliquat lot 3 T3b ; `DECISIONS_LOT3.md`, section T3b) : point d'entrée
/// unique des liens universels (`onOpenURL`, `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`), de l'argument
/// DEBUG `-JOLENE_OPEN_URL` (`AppContainer`) et des taps push (`BoiteTapsPush`, relue par l'espace prêt).
///
/// La décision vit dans JoleneCore (`DeepLinkIntent`, `AiguillageLiens`, niveau 1 : `DeepLinkIntentTests`) ; le
/// coordinateur exécute ses actions :
/// - navigation dans l'espace prêt : `demande` (cible `CibleNotification` + epoch), exécutée par
///   `MainTabView.presenter` (onglet, retour à la racine, écran empilé) puis acquittée ; une demande d'un autre epoch
///   n'est jamais exécutée ;
/// - renvoi web : présentateur `.safari` de l'app (`PresentateurRenvoiWeb`, injecté à la racine par
///   `PointDEntreeLiens`) — `SFSafariViewController` en staging/production, double démo sans réseau
///   (`renvoi-web-demo`, URL lue dans `renvoi-web-url`) ; jamais `openURL` (les chemins `/soignant/*` reviendraient
///   dans l'app par lien universel) ;
/// - refus d'un lien de réinitialisation PKCE (option B, décision 7 du lot 1) : alerte au texte décidé.
///
/// DEBUG et démo seulement : libellé `deeplink-route` de la dernière route présentée (format de
/// `PushTapIntent.libelleDebug` : cas de route, identifiant ou URL canonique ; données de démonstration, jamais en
/// STAGING où elles seraient réelles, revue L3-T5 m8). Il remplace `push-tap-cible` de L3-T5 (consigne de T5).
///
/// Limite connue : la feuille du renvoi est présentée par la racine ; un lien entrant reçu pendant qu'une autre
/// feuille est ouverte (filtres d'Explorer) n'est pas présenté par-dessus (une seule feuille par niveau en SwiftUI).
@MainActor
final class DeepLinkCoordinator: ObservableObject, PresentateurRenvoiWeb {
    /// Navigation demandée à l'espace prêt de `epoch`.
    struct DemandeNavigation: Equatable {
        let numero: Int
        let epoch: Int
        let cible: CibleNotification
    }

    /// Renvoi web affiché (feuille `sheet(item:)`).
    struct RenvoiWeb: Identifiable, Equatable {
        let id: Int
        let url: URL
    }

    @Published private(set) var demande: DemandeNavigation?
    @Published var renvoiWeb: RenvoiWeb?
    @Published var refusReinitialisation = false
    /// Libellé DEBUG de la dernière route présentée (`deeplink-route`), démo seulement.
    @Published private(set) var derniereRoute: String?

    let estDemo: Bool
    private let aiguillage: AiguillageLiens
    private var numero = 0
    /// Lien reçu au lancement, avant que la racine ne soit affichée (`-JOLENE_OPEN_URL`, lu par `AppContainer.init`).
    private var lienAuLancement: URL?
    private var racineAffichee = false

    init(taps: BoiteTapsPush, estDemo: Bool) {
        self.estDemo = estDemo
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

    /// La demande a été exécutée par l'espace (une seule fois).
    func demandeTraitee(_ traitee: DemandeNavigation) {
        if demande == traitee { demande = nil }
    }

    // MARK: Présentateur `.safari`

    /// Présente `route` (`.safari`, `.etablissement`) dans une feuille ; sans effet pour une route native.
    func presenter(_ route: JoleneRoute) {
        guard let url = route.externalURL else { return }
        numero += 1
        renvoiWeb = RenvoiWeb(id: numero, url: url)
        aiguillage.renvoiWebPresente(route)
        noter(route)
    }

    /// Fin de présentation d'une feuille de renvoi (`onDismiss`). Une feuille remplacée par un nouveau renvoi garde
    /// l'anti-boucle du nouveau : seule une fermeture sans remplacement le lève.
    func renvoiWebFerme() {
        if renvoiWeb == nil { aiguillage.renvoiWebFerme() }
    }

    func fermerRenvoiWeb() {
        renvoiWeb = nil
    }

    // MARK: Exécution

    /// Exécute une action de l'aiguillage. Une navigation ou un refus ferment d'abord le renvoi web affiché : le
    /// dernier lien reçu doit être visible, jamais caché sous une feuille plus ancienne.
    private func executer(_ action: AiguillageLiens.Action?) {
        switch action {
        case let .naviguer(cible, route, epoch)?:
            fermerRenvoiWeb()
            numero += 1
            demande = DemandeNavigation(numero: numero, epoch: epoch, cible: cible)
            noter(route)
        case .renvoiWeb(let route)?:
            presenter(route)
        case .refusReinitialisation?:
            fermerRenvoiWeb()
            refusReinitialisation = true
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

/// Branchements de la racine (`JoleneApp`) : présentateur `.safari` dans l'environnement, entrées des liens
/// universels, feuille du renvoi web, alerte du refus de réinitialisation, libellé DEBUG `deeplink-route`.
struct PointDEntreeLiens: ViewModifier {
    @ObservedObject var coordinateur: DeepLinkCoordinator

    func body(content: Content) -> some View {
        content
            .environment(\.presentateurRenvoiWeb, coordinateur)
            .onAppear { coordinateur.racineVisible() }
            .onOpenURL { url in coordinateur.recevoir(url: url) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activite in
                guard let url = activite.webpageURL else { return }
                coordinateur.recevoir(url: url)
            }
            .sheet(item: $coordinateur.renvoiWeb, onDismiss: { coordinateur.renvoiWebFerme() }) { renvoi in
                if coordinateur.estDemo {
                    RenvoiWebDemoScreen(url: renvoi.url) { coordinateur.fermerRenvoiWeb() }
                } else {
                    RenvoiWebSafari(url: renvoi.url) { coordinateur.fermerRenvoiWeb() }
                        .ignoresSafeArea()
                }
            }
            .alert(DeepLinkIntent.Textes.reinitialisationRefusee, isPresented: $coordinateur.refusReinitialisation) {
                Button(DeepLinkIntent.Textes.fermer, role: .cancel) {}
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
/// XCUITest (`renvoi-web-url`), et « Fermer » (`renvoi-web-fermer`). Données de démonstration seulement.
private struct RenvoiWebDemoScreen: View {
    let url: URL
    let fermer: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                Text(url.absoluteString)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.midnight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("renvoi-web-url")
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
