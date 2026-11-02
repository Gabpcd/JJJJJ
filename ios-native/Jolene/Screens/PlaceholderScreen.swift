import SwiftUI
import JoleneDesign

/// Onglet non encore porté : état honnête « Disponible au lot 1 », jamais une maquette.
struct PlaceholderScreen: View {
    let titre: String
    let identifier: String
    let description: String

    var body: some View {
        ZStack {
            JoleneColor.lavender.ignoresSafeArea()
            EmptyState(systemImage: "hourglass", title: "Disponible au lot 1", message: description, identifier: identifier)
        }
        .navigationTitle(titre)
    }
}
