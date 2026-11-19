import SwiftUI
import JoleneCore

/// Cycle de vie Realtime de la messagerie (L4-T1c, `docs/mobile-swift/LOT4_PLAN.md` §2.5 « Messagerie Realtime », T7a).
///
/// **Stub de L4-T1c, verrouillé** (revue B8 de #1146, m6) : l'appel unique `scenePhase(_:)` est posé dans
/// `JoleneApp.handleScenePhase`, mais rien n'est ouvert tant que le port `realtime` des gateways est un stub non câblé
/// (`VerrousLot4.abonnementRealtimePermis`, faux jusqu'à T7a dans les deux mondes) : aucun canal, aucun
/// `fn_update_presence`. Seul point de l'app qui touche au Realtime (garde node « m6 » de
/// `tests/node/check-rpc-contracts-lot4.node.mjs`).
///
/// T7a l'implémente sans retoucher `JoleneApp.swift` : abonnement au premier plan seulement (`.active`), aucun
/// `UIBackgroundModes` ; arrière-plan → `fermerTout()` ; epoch d'identité changé → `fermerTout()` avant toute nouvelle
/// session ; flux `postgresChange` créés avant `subscribeWithError()` ; canal fermé par le serveur → nouveau canal et
/// relecture.
@MainActor
final class RealtimeLifecycle {
    /// Session de l'app (nil si l'environnement est refusé) : T7a y lit l'espace prêt et ses gateways.
    let session: SessionStore?

    init(session: SessionStore?) {
        self.session = session
    }

    /// Changement de phase de la scène (`JoleneApp`). Verrouillé jusqu'à T7a.
    func scenePhase(_ phase: ScenePhase) {
        guard let session, let snapshot = session.state.snapshot else { return }
        Task { await self.appliquer(phase, controleur: session.controller, epoch: snapshot.epoch) }
    }

    private func appliquer(_ phase: ScenePhase, controleur: SessionController, epoch: Int) async {
        guard let gateways = await controleur.gateways(for: epoch),
              VerrousLot4.abonnementRealtimePermis(gateways.realtime) else { return }
        // T7a : abonnement (`.active`) ou `fermerTout()` (`.background`) par `gateways.realtime`.
    }
}
