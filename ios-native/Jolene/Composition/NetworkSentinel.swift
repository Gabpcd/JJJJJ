#if DEBUG
import Foundation
import Combine

/// Sentinelle réseau du mode démonstration (plan §4.6 : « un test prouve qu'aucune
/// requête réseau ne part en mode démo »). Enregistrée uniquement en DEBUG et en démo :
/// toute requête passant par `URLSession.shared` (ou une configuration par défaut créée
/// après l'enregistrement) échoue immédiatement et incrémente un compteur que l'écran
/// Profil expose sous l'identifiant `network-sentinel`.
///
/// Tout le fichier est sous `#if DEBUG` : la classe n'existe pas dans le binaire Release,
/// et toute référence hors d'un bloc DEBUG fait échouer la compilation Release.
final class NetworkSentinel: URLProtocol {
    /// Compteur partagé, protégé par verrou (les appels URLProtocol arrivent hors main actor).
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func increment() -> Int {
            lock.lock(); defer { lock.unlock() }
            count += 1
            return count
        }

        var value: Int {
            lock.lock(); defer { lock.unlock() }
            return count
        }
    }

    /// Observable SwiftUI, mis à jour sur le main actor après chaque interception.
    @MainActor
    final class Monitor: ObservableObject {
        static let shared = Monitor()
        @Published private(set) var requests = 0
        @Published private(set) var installed = false

        fileprivate func markInstalled() { installed = true }
        fileprivate func update(_ value: Int) { requests = value }

        /// Libellé exposé à l'interface et aux tests UI : « 0 requête », « 2 requêtes ».
        var label: String { "\(requests) requête\(requests > 1 ? "s" : "")" }
    }

    static let counter = Counter()

    /// Idempotent : un seul enregistrement par processus.
    @MainActor
    static func install() {
        guard !Monitor.shared.installed else { return }
        URLProtocol.registerClass(NetworkSentinel.self)
        Monitor.shared.markInstalled()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let total = Self.counter.increment()
        Task { @MainActor in Monitor.shared.update(total) }
        // Aucune URL ni corps n'est journalisé : seule l'existence de la requête compte.
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
#endif
