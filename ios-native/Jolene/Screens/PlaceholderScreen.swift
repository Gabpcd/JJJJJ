import SwiftUI
import JoleneDesign

/// Onglet non encore porté : état honnête « Disponible au lot N », jamais une maquette.
/// `etat` (ajout additif du lot 5, T2a) vaut « Disponible au lot 1 » par défaut.
struct PlaceholderScreen: View {
    let titre: String
    let identifier: String
    let description: String
    var etat: String = "Disponible au lot 1"

    var body: some View {
        ZStack {
            JoleneColor.lavender.ignoresSafeArea()
            EmptyState(systemImage: "hourglass", title: etat, message: description, identifier: identifier)
        }
        .navigationTitle(titre)
    }
}
