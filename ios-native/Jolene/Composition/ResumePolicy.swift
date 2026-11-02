import Foundation

/// Reprise après arrière-plan, portée de `src/lib/nativeResume.ts` :
/// `ABSENCE_LONGUE_MS = 30 * 60_000`. Au-delà de cette absence, la session est
/// ré-exécutée (`SessionStore.start()`) pour revalider identité, rôle et profil.
enum ResumePolicy {
    static let absenceLongue: TimeInterval = 30 * 60

    static func shouldRestart(backgroundedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(backgroundedAt) > absenceLongue
    }
}
