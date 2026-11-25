import Foundation

/// Dernier état connu et ses changements, diffusés à des abonnés `AsyncStream` (revue fraîche de T4b, m5) : mécanique de
/// `NetworkMonitor` (cible app, `NWPathMonitor` ; le module `Network` reste hors de JoleneCore), extraite pour être
/// testée (`PointageSaisieTests`, `DiffusionDernierEtatTests`). Un abonné reçoit l'état courant s'il est connu, puis
/// chaque changement (un doublon n'est pas rediffusé). Un changement concurrent d'un abonnement n'est jamais livré à ce
/// nouvel abonné avant l'état qu'il remplace (sinon le bandeau hors ligne resterait faux jusqu'au changement suivant).
///
/// Deux verrous, et aucun `yield`, `finish` ni code externe sous `verrou` (gel du 24/11/2026, reproduit par
/// `DiffusionDernierEtatTests`) : l'annulation d'une tâche qui lit un flux exécute `onTermination` (→ `desabonner`, qui
/// prend `verrou`) en tenant le verrou d'état de cette tâche, et `yield` reprend la tâche qui attend le flux en prenant
/// ce même verrou d'état ; un `yield` fait sous `verrou` figeait donc les deux fils.
/// - `verrou` protège `dernier` et `abonnes`, en sections courtes sans appel externe ; c'est le seul que prend
///   `onTermination`.
/// - `emission` sérialise les envois : le premier envoi d'un abonnement (`abonner`), la diffusion d'un changement
///   (`recevoir`) et la fin des flux (`terminer`). Les `yield` et `finish` se font sous `emission` seul, `verrou`
///   relâché ; `onTermination` ne prend jamais `emission`. Ordre de prise : `emission` puis `verrou`, jamais l'inverse.
/// Garantie d'ordre : l'inscription d'un abonné et la lecture de l'état qu'il recevra d'abord se font dans une même
/// section `verrou`, sous `emission`. Un changement soit précède cette section (l'abonné lit le nouvel état et ne figure
/// pas dans la diffusion), soit la suit (sa diffusion attend `emission`, donc l'envoi de l'état courant à l'abonné).
///
/// `@unchecked Sendable` : tout l'état mutable est protégé par `verrou`, dans des sections synchrones.
public final class DiffusionDernierEtat<Valeur: Sendable & Equatable>: @unchecked Sendable {
    private let verrou = NSLock()
    private let emission = NSLock()
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
        emission.lock(); defer { emission.unlock() }
        verrou.lock()
        guard dernier != valeur else {
            verrou.unlock()
            return
        }
        dernier = valeur
        let suites = Array(abonnes.values)
        verrou.unlock()
        for suite in suites { suite.yield(valeur) }
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
        emission.lock(); defer { emission.unlock() }
        verrou.lock()
        let suites = Array(abonnes.values)
        abonnes.removeAll()
        verrou.unlock()
        // `finish()` appelle aussitôt `onTermination`, qui reprend `verrou` (relâché ici).
        suites.forEach { $0.finish() }
    }

    /// Abonnés en cours (tests).
    var nombreAbonnes: Int {
        verrou.lock(); defer { verrou.unlock() }
        return abonnes.count
    }

    private func abonner(_ id: UUID, _ suite: AsyncStream<Valeur>.Continuation) {
        emission.lock(); defer { emission.unlock() }
        verrou.lock()
        abonnes[id] = suite
        let courant = dernier
        verrou.unlock()
        if let courant { suite.yield(courant) }
    }

    private func desabonner(_ id: UUID) {
        verrou.lock(); defer { verrou.unlock() }
        abonnes[id] = nil
    }
}
