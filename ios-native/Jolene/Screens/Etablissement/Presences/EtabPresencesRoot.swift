import SwiftUI
import JoleneCore

/// Racine de l'onglet Présences de l'espace établissement, posée par T2a avec un contenu provisoire ;
/// remplie par T8 seule (validation, note, lot, contestation, clôture). Identifiant provisoire :
/// `placeholder-etab-presences` (T8 migre les assertions de `DemoEtabSessionTests`).
struct EtabPresencesRoot: View {
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot

    var body: some View {
        PlaceholderScreen(titre: "Présences", identifier: "placeholder-etab-presences",
                          description: "La validation des présences arrive dans une prochaine version de l'application.",
                          etat: "Disponible au lot 5")
    }
}
