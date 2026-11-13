import Foundation
import JoleneCore
import Network

/// État du réseau réel (`NetworkPathPort`, blueprint lot 2 §2.2 ; décision 2), sur `NWPathMonitor` : le module `Network`
/// reste hors de JoleneCore (`DemoNoNetworkTests`). Hors ligne, aucun scan n'est envoyé ni mis en file ; l'écran
/// désactive le bouton et affiche le bandeau. Le moniteur démarre à la construction (une instance par processus, posée
/// par `AppContainer`) ; tant que le premier état n'est pas connu, `estEnLigne()` l'attend au plus 2 s puis suppose la
/// connexion présente (le refus éventuel vient alors du transport, jamais d'un scan mis de côté).
///
/// Dernier état et abonnés : `DiffusionDernierEtat` (JoleneCore, testée par `PointageSaisieTests`) ; le premier envoi d'un
/// abonnement se fait sous son verrou, un changement concurrent ne le devance jamais (revue fraîche de T4b, m5). Le
/// moniteur rappelle sur sa propre file série.
final class NetworkMonitor: NetworkPathPort, @unchecked Sendable {
    private static let attentePremierEtat: TimeInterval = 2
    private static let pas: UInt64 = 100_000_000

    private let moniteur = NWPathMonitor()
    private let file = DispatchQueue(label: "app.jolene.reseau")
    private let diffusion = DiffusionDernierEtat<Bool>()

    init() {
        let diffusion = diffusion
        moniteur.pathUpdateHandler = { chemin in
            diffusion.recevoir(chemin.status == .satisfied)
        }
        moniteur.start(queue: file)
    }

    deinit {
        moniteur.cancel()
        diffusion.terminer()
    }

    func estEnLigne() async -> Bool {
        var attente: TimeInterval = 0
        while attente < Self.attentePremierEtat {
            if let valeur = diffusion.lire() { return valeur }
            try? await Task.sleep(nanoseconds: Self.pas)
            attente += Double(Self.pas) / 1_000_000_000
        }
        return diffusion.lire() ?? true
    }

    func changements() -> AsyncStream<Bool> {
        diffusion.flux()
    }
}
