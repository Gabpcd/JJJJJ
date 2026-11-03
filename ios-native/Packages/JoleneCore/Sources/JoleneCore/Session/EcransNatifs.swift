import Foundation

// Port anticipé (lot 5, T2a) de `DrapeauxLancement`, livré par la tranche T9 du lot 1
// (`origin/lot1/t9`, même chemin, même code) et pas encore intégré à `feat/ios-lot1` : l'espace
// établissement en a besoin pour la recette du renvoi web (`DemoEtabSessionTests`). À la fusion de T9,
// ce fichier est remplacé par celui de T9 (conflit d'ajout : garder la version de T9, sur-ensemble).

/// Surcharges de lancement `-JOLENE_FLAG_<cle> true|false` (DEBUG, monde démo seulement : lues par
/// `AppContainer` puis `DemoFlagsGateway`). Une valeur illisible ou absente est ignorée : jamais un
/// écran coupé par erreur de saisie.
public enum DrapeauxLancement {
    public static let prefixe = "-JOLENE_FLAG_"

    public static func surcharges(arguments: [String]) -> [String: Bool] {
        var surcharges: [String: Bool] = [:]
        for (index, argument) in arguments.enumerated() where argument.hasPrefix(prefixe) {
            let cle = String(argument.dropFirst(prefixe.count))
            guard !cle.isEmpty, index + 1 < arguments.count else { continue }
            switch arguments[index + 1].lowercased() {
            case "false", "0", "no": surcharges[cle] = false
            case "true", "1", "yes": surcharges[cle] = true
            default: continue
            }
        }
        return surcharges
    }
}
