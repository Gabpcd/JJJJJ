import Foundation

/// Verrous des branchements posés par L4-T1c avant leurs tranches (revue B8 de #1146, m6 ; `CLAUDE.md`, « un gap connu
/// reste verrouillé ») : la capture du code de parrainage (`ParrainageCapture`, stub de L4-T1, implémenté par T6) et
/// l'abonnement Realtime (`RealtimePort`, `UnwiredRealtimePort` jusqu'à T7a) sont appelés par l'app depuis L4-T1c
/// (`DeepLinkCoordinator` → `ParrainageApplicateur`, `JoleneApp` → `RealtimeLifecycle`), mais ne font rien tant que
/// leur tranche n'a pas livré. L'app ne passe que par ces deux entrées (garde node « m6 » de
/// `tests/node/check-rpc-contracts-lot4.node.mjs`) ; `VerrousLot4Tests` lie chaque verrou à l'état du port dans
/// `DemoWorldTests.portsEnAttenteLot4` : livrer la capture sans câbler le port (ou l'inverse) rougit la suite.
public enum VerrousLot4 {
    /// Capture et application du code de parrainage branchées : vrai seulement quand T6 a livré `ParrainageCapture`.
    public static var parrainageBranche: Bool { ParrainageCapture.estLivree }

    /// Code de parrainage à capturer sur un lien universel entrant (`?ref=`, `?parrain=`), ou `nil`. Seul chemin de
    /// capture de l'app : `nil` tant que T6 n'a pas livré, quel que soit le lien (jamais un code supposé).
    public static func codeParrainageACapturer(depuis url: URL) -> String? {
        guard parrainageBranche else { return nil }
        return ParrainageCapture.code(depuis: url)
    }

    /// Abonnement Realtime permis : faux tant que le port est un stub non câblé (`UnwiredPort`, entrée `realtime` de
    /// `Gateways.unwiredPorts`), donc jusqu'à T7a dans les deux mondes ; aucun canal, aucun flux, aucune présence.
    public static func abonnementRealtimePermis(_ realtime: RealtimePort) -> Bool {
        !(realtime is UnwiredPort)
    }
}
