import SwiftUI
import JoleneCore

/// Racine de l'onglet Messages de l'espace établissement, posée par T2a avec un contenu provisoire ;
/// remplie par T11 seule (messagerie du lot 4 en contexte établissement). Identifiant provisoire :
/// `placeholder-etab-messages` (T11 migre les assertions de `DemoEtabSessionTests`).
struct EtabMessagesRoot: View {
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot

    var body: some View {
        PlaceholderScreen(titre: "Messages", identifier: "placeholder-etab-messages",
                          description: "La messagerie de votre établissement arrive dans une prochaine version de l'application.",
                          etat: "Disponible au lot 5")
    }
}
