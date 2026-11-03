import SwiftUI
import JoleneCore

/// Racine de l'onglet Accueil de l'espace établissement, posée par T2a avec un contenu provisoire ;
/// remplie par T4 seule (actions prioritaires, `EtabAccueilScreen`). Identifiant provisoire :
/// `placeholder-etab-accueil` (T4 migre les assertions de `DemoEtabSessionTests`).
struct EtabAccueilRoot: View {
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot

    var body: some View {
        PlaceholderScreen(titre: "Accueil", identifier: "placeholder-etab-accueil",
                          description: "Les actions prioritaires de votre établissement arrivent dans une prochaine version de l'application.",
                          etat: "Disponible au lot 5")
    }
}
