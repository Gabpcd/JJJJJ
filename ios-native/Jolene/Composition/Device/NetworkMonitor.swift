import Foundation
import JoleneCore
import Network

/// État du réseau réel (`NetworkPathPort`, blueprint lot 2 §2.2 ; décision 2), sur `NWPathMonitor` : le module `Network`
/// reste hors de JoleneCore (`DemoNoNetworkTests`). Hors ligne, aucun scan n'est envoyé ni mis en file ; l'écran
/// désactive le bouton et affiche le bandeau. Le moniteur démarre à la construction (une instance par processus, posée
/// par `AppContainer`) ; tant que le premier état n'est pas connu, `estEnLigne()` l'attend au plus 2 s puis suppose la
/// connexion présente (le refus éventuel vient alors du transport, jamais d'un scan mis de côté).
///
/// `@unchecked Sendable` : tout l'état mutable (dernier état, abonnés) est protégé par `verrou`, dans des sections
/// synchrones ; le moniteur rappelle sur sa propre file série.
final class NetworkMonitor: NetworkPathPort, @unchecked Sendable {
    private static let attentePremierEtat: TimeInterval = 2
    private static let pas: UInt64 = 100_000_000

    private let moniteur = NWPathMonitor()
    private let file = DispatchQueue(label: "app.jolene.reseau")
    private let verrou = NSLock()
    private var dernier: Bool?
    private var abonnes: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init() {
        moniteur.pathUpdateHandler = { [weak self] chemin in
            self?.recevoir(chemin.status == .satisfied)
        }
        moniteur.start(queue: file)
    }

    deinit {
        moniteur.cancel()
    }

    func estEnLigne() async -> Bool {
        var attente: TimeInterval = 0
        while attente < Self.attentePremierEtat {
            if let valeur = lire() { return valeur }
            try? await Task.sleep(nanoseconds: Self.pas)
            attente += Double(Self.pas) / 1_000_000_000
        }
        return lire() ?? true
    }

    func changements() -> AsyncStream<Bool> {
        AsyncStream { suite in
            let id = UUID()
            if let valeur = abonner(id, suite) { suite.yield(valeur) }
            suite.onTermination = { [weak self] _ in self?.desabonner(id) }
        }
    }

    // MARK: - Sections critiques (synchrones)

    private func lire() -> Bool? {
        verrou.lock(); defer { verrou.unlock() }
        return dernier
    }

    private func recevoir(_ enLigne: Bool) {
        verrou.lock()
        let change = dernier != enLigne
        dernier = enLigne
        let suites = Array(abonnes.values)
        verrou.unlock()
        guard change else { return }
        suites.forEach { $0.yield(enLigne) }
    }

    private func abonner(_ id: UUID, _ suite: AsyncStream<Bool>.Continuation) -> Bool? {
        verrou.lock(); defer { verrou.unlock() }
        abonnes[id] = suite
        return dernier
    }

    private func desabonner(_ id: UUID) {
        verrou.lock(); defer { verrou.unlock() }
        abonnes[id] = nil
    }
}
