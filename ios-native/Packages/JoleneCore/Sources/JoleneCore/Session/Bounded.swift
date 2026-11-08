import Foundation

/// Borne un appel de port à `timeout` secondes (plan §4.1 ; blueprint lot 1 §2.3).
///
/// Extrait de `SessionController` au lot 1 pour que les modèles d'écran bornent chaque lecture
/// et chaque mutation au même délai que la résolution de session
/// (`SessionController.resolutionTimeout`, 15 s par défaut, décision 14).
///
/// Le premier des deux (réponse ou délai) gagne ; le perdant est annulé sans être attendu : un
/// port qui ignorerait l'annulation ne peut pas retenir l'appelant (un groupe de tâches
/// structuré attendrait ses enfants). Le dépassement est une erreur réseau générique
/// (`SessionController.timeoutMessage`).
///
/// L'annulation de l'appelant (le `.task` d'une vue qui disparaît) n'est pas un dépassement :
/// le travail en vol est annulé et `CancellationError` est levée sans attendre le délai, jamais
/// « Le service ne répond pas ».
///
/// Un délai dépassé sur une mutation ne prouve pas que le serveur n'a pas agi : l'appelant relit
/// l'objet avant d'annoncer quoi que ce soit et ne renvoie jamais la mutation automatiquement
/// (PRINCIPES §3-§4).
///
/// Tout `timeout` est accepté : négatif, nul ou NaN vaut un délai immédiat ; au-delà de
/// `plafondDelaiNanosecondes` (≈ 292 ans, `.infinity` compris) le délai est plafonné.
public func bounded<T: Sendable>(
    timeout: TimeInterval,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let nanoseconds = delaiEnNanosecondes(timeout)
    let race = AsyncThrowingStream<T, Error> { continuation in
        let work = Task {
            do {
                continuation.yield(try await operation())
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        let timer = Task {
            try await Task.sleep(nanoseconds: nanoseconds)
            continuation.finish(throwing: JoleneError(.network, SessionController.timeoutMessage))
        }
        continuation.onTermination = { _ in
            work.cancel()
            timer.cancel()
        }
    }
    for try await value in race {
        return value
    }
    // Flux terminé sans valeur ni erreur : seule l'annulation de l'appelant y mène (le travail
    // rend une valeur ou lève, le délai lève) ; `onTermination` a déjà annulé les deux tâches.
    try Task.checkCancellation()
    throw JoleneError(.network, SessionController.timeoutMessage)
}

/// Plafond du délai de `bounded` : `UInt64.max / 2` ns (≈ 292 ans), jamais atteint en pratique,
/// et strictement représentable (`Double(UInt64.max)` arrondit à 2^64, hors de `UInt64`).
let plafondDelaiNanosecondes: UInt64 = UInt64.max / 2

/// Conversion bornée avant `UInt64(_:)`, qui piège sur `.infinity`, NaN ou une valeur hors
/// plage : `timeout` ≤ 0 ou NaN → 0 ; au-delà du plafond → `plafondDelaiNanosecondes`.
func delaiEnNanosecondes(_ timeout: TimeInterval) -> UInt64 {
    guard timeout > 0 else { return 0 } // NaN compris : toute comparaison est fausse
    let nanosecondes = timeout * 1_000_000_000
    guard nanosecondes < Double(plafondDelaiNanosecondes) else { return plafondDelaiNanosecondes }
    return UInt64(nanosecondes)
}
