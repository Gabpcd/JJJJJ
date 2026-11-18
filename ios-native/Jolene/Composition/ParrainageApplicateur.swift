import Foundation
import JoleneCore

/// Capture et application du code de parrainage (L4-T1c, `docs/mobile-swift/LOT4_PLAN.md` §2.5 et §3 T1c, T6).
///
/// **Stub de L4-T1c, verrouillé** (revue B8 de #1146, m6) : les deux appels sont posés une fois dans le coordinateur
/// des liens — `capturer(depuis:)` sur **tout** lien universel entrant (le web capte depuis n'importe quelle page,
/// `src/lib/attribution.ts` l.35-46), `appliquerSiCapture(_:)` à l'ouverture de l'espace prêt (`.ready`) — mais ne font
/// rien tant que T6 n'a pas livré `ParrainageCapture` (`VerrousLot4.parrainageBranche` faux,
/// `VerrousLot4.codeParrainageACapturer` toujours `nil`) : aucune capture, aucun stockage, aucun appel de
/// `fn_appliquer_parrainage`. T6 implémente ce fichier seul, sans modifier `DeepLinkCoordinator` ni `SessionController` :
/// mémorisation `{code, captured_at}` dans `stockage` (par appareil ; mémoire vive en démo), application au premier
/// `.ready` qui suit, au plus 30 jours après la capture (`ParrainageCapture.fenetreJours`), par le port `parrainage` des
/// gateways de l'epoch (`controleur`, posé par `AppContainer`), marqueur « appliqué » par userId + code.
@MainActor
final class ParrainageApplicateur {
    /// Stockage de la capture (T6) : `UserDefaults` en staging et production, mémoire vive en démo.
    let stockage: StockageAppareilPort
    /// Contrôleur de session, posé par `AppContainer` après sa construction (nil si l'environnement est refusé) : T6 y
    /// lit les gateways de l'epoch prêt (`gateways(for:)`) pour appliquer le code.
    var controleur: SessionController?

    init(stockage: StockageAppareilPort) {
        self.stockage = stockage
    }

    /// Lien universel entrant (`DeepLinkCoordinator.recevoir(url:)`), avant son aiguillage. Verrouillé jusqu'à T6.
    func capturer(depuis url: URL) {
        guard VerrousLot4.codeParrainageACapturer(depuis: url) != nil else { return }
        // T6 : mémorisation de la capture (`ParrainageCapture.Capture`) dans `stockage`.
    }

    /// Ouverture de l'espace prêt de `snapshot` (`DeepLinkCoordinator.espaceOuvert(_:)`). Verrouillé jusqu'à T6.
    func appliquerSiCapture(_ snapshot: SessionSnapshot) {
        guard VerrousLot4.parrainageBranche else { return }
        // T6 : application de la capture encore applicable (`ParrainageCapture.estApplicable`) pour `snapshot.user.id`.
    }
}
