import Foundation

/// Dernier état connu et ses changements, diffusés à des abonnés `AsyncStream` (revue fraîche de T4b, m5) : mécanique de
/// `NetworkMonitor` (cible app, `NWPathMonitor` ; le module `Network` reste hors de JoleneCore), extraite pour être
/// testée (`PointageSaisieTests`). Un abonné reçoit l'état courant s'il est connu, puis chaque changement (un doublon
/// n'est pas rediffusé). Le premier envoi d'un abonnement et la diffusion d'un changement se font SOUS le verrou : un
/// changement concurrent d'un abonnement ne peut pas être livré à ce nouvel abonné avant l'état qu'il remplace (sinon
/// le bandeau hors ligne resterait faux jusqu'au changement suivant).
///
/// `@unchecked Sendable` : tout l'état mutable est protégé par `verrou`, dans des sections synchrones ; `yield` ne fait
/// que mettre la valeur en tampon (aucun code d'abonné n'y est exécuté).
public final class DiffusionDernierEtat<Valeur: Sendable & Equatable>: @unchecked Sendable {
    private let verrou = NSLock()
    private var dernier: Valeur?
    private var abonnes: [UUID: AsyncStream<Valeur>.Continuation] = [:]

    public init() {}

    /// Dernier état reçu, nil tant qu'aucun ne l'a été.
    public func lire() -> Valeur? {
        verrou.lock(); defer { verrou.unlock() }
        return dernier
    }

    /// Nouvel état : diffusé à chaque abonné s'il change.
    public func recevoir(_ valeur: Valeur) {
        verrou.lock(); defer { verrou.unlock() }
        guard dernier != valeur else { return }
        dernier = valeur
        for suite in abonnes.values { suite.yield(valeur) }
    }

    /// État courant (s'il est connu) puis chaque changement, jusqu'à l'abandon du flux ou `terminer()`.
    public func flux() -> AsyncStream<Valeur> {
        AsyncStream { suite in
            let id = UUID()
            suite.onTermination = { [weak self] _ in self?.desabonner(id) }
            abonner(id, suite)
        }
    }

    /// Termine tous les flux (fin du moniteur).
    public func terminer() {
        verrou.lock()
        let suites = Array(abonnes.values)
        abonnes.removeAll()
        verrou.unlock()
        // Hors du verrou : `finish()` appelle aussitôt `onTermination`, qui le reprend.
        suites.forEach { $0.finish() }
    }

    /// Abonnés en cours (tests).
    var nombreAbonnes: Int {
        verrou.lock(); defer { verrou.unlock() }
        return abonnes.count
    }

    private func abonner(_ id: UUID, _ suite: AsyncStream<Valeur>.Continuation) {
        verrou.lock(); defer { verrou.unlock() }
        abonnes[id] = suite
        if let dernier { suite.yield(dernier) }
    }

    private func desabonner(_ id: UUID) {
        verrou.lock(); defer { verrou.unlock() }
        abonnes[id] = nil
    }
}
