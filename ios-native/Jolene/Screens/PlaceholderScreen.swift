import SwiftUI
import JoleneDesign

/// Onglet ou écran non encore porté : état honnête « Disponible au lot N », jamais une maquette. `etat` : titre de
/// l'état (lot 0 : « Disponible au lot 1 » ; les écrans provisoires du lot 2 de T4a, `LibellesPresences.Provisoire`, ont
/// été remplacés par T4b, T7 et T9a).
struct PlaceholderScreen: View {
    let titre: String
    let identifier: String
    let description: String
    var etat = "Disponible au lot 1"

    var body: some View {
        ZStack {
            JoleneColor.lavender.ignoresSafeArea()
            EmptyState(systemImage: "hourglass", title: etat, message: description, identifier: identifier)
        }
        .navigationTitle(titre)
    }
}
