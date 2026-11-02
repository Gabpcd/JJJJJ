import SwiftUI
import JoleneCore
import JoleneDesign

@main
struct JoleneApp: App {
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
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = container.clock.now()
        case .active:
            defer { backgroundedAt = nil }
            guard let since = backgroundedAt, let session = container.session,
                  ResumePolicy.shouldRestart(backgroundedAt: since, now: container.clock.now()) else { return }
            Task { await session.start() }
        default:
            break
        }
    }
}
