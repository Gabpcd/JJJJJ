import SwiftUI
import JoleneCore

/// Cycle de vie Realtime de la messagerie (L4-T1c, `docs/mobile-swift/LOT4_PLAN.md` §2.5 « Messagerie Realtime », T7a).
///
/// Adaptateur de l'app : il transmet les phases de scène au cycle de vie de JoleneCore (`CycleRealtime`, prouvé par
/// `RealtimeLifecycleTests`), qui porte toutes les règles — abonnement au premier plan seulement (`.active`), aucun
/// `UIBackgroundModes` ; arrière-plan → `fermerTout()` ; epoch d'identité changé → `fermerTout()` avant toute nouvelle
/// session (le cycle suit lui-même `SessionStore.state`) ; flux `postgresChange` déclarés avant `subscribeWithError()`
/// et canal fermé par le serveur remplacé (`SupabaseRealtimeGateway`) ; badge `fn_messages_non_lus()` relu.
///
/// Gap verrouillé : T7a livre le cœur sans écran, le cycle n'ouvre donc rien tant que l'écran natif de la messagerie
/// n'est pas livré (ligne `messagerie` de `DestinationLien.ecranNatifLivre`, passée à `true` par T7b), puis il lit le
/// coupe-circuit `ios_natif_messagerie_actif` avant tout canal (`DECISIONS_LOT4.md`, précision 13).
///
/// Verrou m6 conservé (revue B8 de #1146) : rien n'est transmis tant que le port `realtime` des gateways est un stub
/// non câblé (`VerrousLot4.abonnementRealtimePermis`). Seul point de l'app qui touche au Realtime (garde node « m6 » de
/// `tests/node/check-rpc-contracts-lot4.node.mjs`) : les écrans de la messagerie (T7b) lisent `cycle` et les modèles
/// de JoleneCore (`ConversationsModel`, `FilModel`), jamais le port.
@MainActor
final class RealtimeLifecycle {
    /// Session de l'app (nil si l'environnement est refusé).
    let session: SessionStore?
    /// Cycle de vie et état partagé de la messagerie (badge, fil ouvert, génération des suivis) ; nil sans session.
    let cycle: CycleRealtime?

    init(session: SessionStore?) {
        self.session = session
        self.cycle = session.map { CycleRealtime(session: $0) }
    }

    /// Dernière phase transmise : les phases sont appliquées une à une, dans l'ordre reçu.
    private var file: Task<Void, Never>?

    /// Changement de phase de la scène (`JoleneApp`).
    func scenePhase(_ phase: ScenePhase) {
        guard let cycle else { return }
        let precedente = file
        file = Task {
            await precedente?.value
            await self.appliquer(phase, cycle: cycle)
        }
    }

    private func appliquer(_ phase: ScenePhase, cycle: CycleRealtime) async {
        guard let gateways = await cycle.gateways(),
              VerrousLot4.abonnementRealtimePermis(gateways.realtime) else { return }
        switch phase {
        case .active:
            await cycle.premierPlan()
        case .background:
            await cycle.arrierePlan()
        default:
            break // `.inactive` : transitoire, les canaux restent en l'état
        }
    }
}
