import SwiftUI
import JoleneCore
import JoleneDesign

@main
struct JoleneApp: App {
    /// Lot 3, T4 : délégué d'application qui remet le token APNs à `PushRegistrar`.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    @StateObject private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundedAt: Date?

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .onChange(of: scenePhase) { phase in handleScenePhase(phase) }
        }
    }

    /// Cycle de vie de scène (plan §4.1) : après plus de 30 minutes en arrière-plan
    /// (`ResumePolicy`, règle de `src/lib/nativeResume.ts`), la session est ré-exécutée.
    /// Lot 3, T4 : à chaque retour au premier plan d'un espace prêt, `PushCoordinator.surActive`
    /// (autorisation relue, rotation du token, enregistrement échoué retenté ; web `AuthContext.tsx` l.151-160).
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = container.clock.now()
        case .active:
            defer { backgroundedAt = nil }
            if let push = container.push, let snapshot = container.session?.state.snapshot {
                Task { await push.surActive(snapshot) }
            }
            guard let since = backgroundedAt, let session = container.session,
                  ResumePolicy.shouldRestart(backgroundedAt: since, now: container.clock.now()) else { return }
            Task { await session.start() }
        default:
            break
        }
    }
}
