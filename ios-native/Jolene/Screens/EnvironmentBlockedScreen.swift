import SwiftUI
import JoleneCore
import JoleneDesign

/// Écran bloquant de la garde d'environnement (plan §4.2) : identifiant `env-blocked`.
/// Le message vient de `JoleneEnvironment.validate()` ; aucune clé n'est jamais affichée.
struct EnvironmentBlockedScreen: View {
    let error: JoleneError
    let mode: JoleneMode

    /// Mode inconnu refusé par la garde : la valeur brute est nommée, jamais « production ».
    var unknownModeRaw: String? = nil

    var body: some View {
        let nom = unknownModeRaw.map { $0.isEmpty ? "absent" : $0 } ?? mode.rawValue
        BlockingScreen(
            title: "Configuration refusée",
            message: "\(error.message)\n\nEnvironnement : \(nom). Utilisez le site jolene.app en attendant une version corrigée.",
            identifier: "env-blocked")
    }
}
