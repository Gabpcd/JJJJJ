import Foundation
import SwiftUI
import JoleneCore
import JoleneDesign

/// Capture et application du code de parrainage (L4-T1c, `docs/mobile-swift/LOT4_PLAN.md` §2.5 et §3 T1c, T6 ; D14).
///
/// Les deux appels sont posés une fois dans le coordinateur des liens (L4-T1c, inchangé par T6) : `capturer(depuis:)`
/// sur **tout** lien universel entrant (le web capte depuis n'importe quelle page, `src/lib/attribution.ts` l.35-46),
/// `appliquerSiCapture(_:)` à l'ouverture de l'espace prêt (`.ready`). Implémentés par L4-T6, toujours derrière
/// `VerrousLot4` (garde node « m6 ») :
/// - capture : seul chemin `VerrousLot4.codeParrainageACapturer(depuis:)` (forme exacte du web, `ETB-` ignoré ; un code
///   hors forme est ignoré sans erreur visible), mémorisée `{code, captureLe}` dans `stockage` (par appareil ; mémoire
///   vive en démo) sur l'horloge des gateways (`horloge`, posée par `AppContainer`) ;
/// - application : au premier `.ready` qui suit, au plus 30 jours après la capture, une fois par userId et code
///   (`ParrainageApplication`, `ParrainageStockage`), par le port `parrainage` des gateways de l'epoch (`controleur`),
///   borné par `resolutionTimeout` ; une seule application à la fois ; réponse d'un epoch périmé ignorée ;
/// - avis : « Code de parrainage enregistré. » ou le report du web (`AvisParrainage`), jamais le message serveur.
@MainActor
final class ParrainageApplicateur: ObservableObject {
    /// Stockage de la capture : `UserDefaults` en staging et production, mémoire vive en démo.
    let stockage: StockageAppareilPort
    /// Contrôleur de session, posé par `AppContainer` après sa construction (nil si l'environnement est refusé) : les
    /// gateways de l'epoch prêt (`gateways(for:)`) appliquent le code.
    var controleur: SessionController?
    /// Horloge de la capture et de la fenêtre de 30 jours (celle des gateways, posée par `AppContainer`).
    var horloge: ClockPort = SystemClock()
    /// Durée d'affichage de l'avis (`DureeAvisParrainage`, 8 s ; surcharge démo et DEBUG posée par `AppContainer`).
    var dureeAvis: TimeInterval = DureeAvisParrainage.standard
    /// Dernier avis à afficher au-dessus de l'espace (`AvisParrainageVue`) ; `jeton` change à chaque avis.
    @Published private(set) var avis: AvisParrainage?
    @Published private(set) var jeton = 0
    private var enCours = false

    init(stockage: StockageAppareilPort) {
        self.stockage = stockage
    }

    /// Lien universel entrant (`DeepLinkCoordinator.recevoir(url:)`), avant son aiguillage.
    func capturer(depuis url: URL) {
        guard let code = VerrousLot4.codeParrainageACapturer(depuis: url) else { return }
        ParrainageStockage(stockage).capturer(code, le: horloge.now())
    }

    /// Ouverture de l'espace prêt de `snapshot` (`DeepLinkCoordinator.espaceOuvert(_:)`).
    func appliquerSiCapture(_ snapshot: SessionSnapshot) {
        guard VerrousLot4.parrainageBranche else { return }
        let memoire = ParrainageStockage(stockage)
        guard !enCours, let controleur,
              memoire.codeAAppliquer(userId: snapshot.user.id, maintenant: horloge.now()) != nil else { return }
        enCours = true
        let maintenant = horloge.now()
        Task { [weak self] in
            defer { self?.enCours = false }
            guard let gateways = await controleur.gateways(for: snapshot.epoch) else { return }
            let port = gateways.parrainage
            let context = snapshot.context
            let delai = controleur.resolutionTimeout
            let issue = await ParrainageApplication.appliquer(stockage: memoire, userId: snapshot.user.id,
                                                              maintenant: maintenant) { code in
                try await bounded(timeout: delai) { try await port.appliquer(code: code, context: context) }
            }
            guard let issue, await controleur.epoch == snapshot.epoch, let self else { return }
            self.avis = issue
            self.jeton += 1
        }
    }

    func fermerAvis() {
        avis = nil
    }
}

/// Avis d'application du parrainage (toast du web, `useAppliquerParrainage.ts` l.74 et l.89), en haut de l'espace
/// prêt ; refermable, retiré seul après `applicateur.dureeAvis` (8 s, `DureeAvisParrainage`). Identifiants : `parrainage-avis`, `parrainage-avis-fermer`.
struct AvisParrainageVue: View {
    @ObservedObject var applicateur: ParrainageApplicateur

    var body: some View {
        if let avis = applicateur.avis {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                InlineNotice(avis.texte, tone: avis == .enregistre ? .success : .warning, identifier: "parrainage-avis",
                             announcesOnAppear: true, announcementID: applicateur.jeton)
                Button { applicateur.fermerAvis() } label: {
                    Image(systemName: "xmark")
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer")
                .accessibilityIdentifier("parrainage-avis-fermer")
            }
            .padding(JoleneSpacing.sm)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            .shadow(radius: 4)
            .padding(.horizontal, JoleneSpacing.lg)
            .frame(maxWidth: 640)
            .task(id: applicateur.jeton) {
                try? await Task.sleep(nanoseconds: UInt64(max(1, applicateur.dureeAvis) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                applicateur.fermerAvis()
            }
        }
    }
}
