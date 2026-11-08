import Foundation
import JoleneCore

/// `StockageAppareilPort` réel (lot 3, T5 ; blueprint §2.6) : `UserDefaults.standard`, par appareil, pour le
/// compteur de lancements à froid (`jolene.sessionCount`) et la marque du pré-prompt (`jolene.pushPrePrompt`).
/// Aucune donnée personnelle ni secret. `UserDefaults` est sûr entre fils d'exécution (documentation Apple).
struct UserDefaultsStockageAppareil: StockageAppareilPort, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lire(_ cle: String) -> String? {
        defaults.string(forKey: cle)
    }

    func ecrire(_ cle: String, _ valeur: String?) {
        if let valeur {
            defaults.set(valeur, forKey: cle)
        } else {
            defaults.removeObject(forKey: cle)
        }
    }
}
