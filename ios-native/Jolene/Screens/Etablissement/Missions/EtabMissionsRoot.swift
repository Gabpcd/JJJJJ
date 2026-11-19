import SwiftUI
import JoleneCore
import JoleneDesign

/// Racine de l'onglet Missions de l'espace établissement, posée par T2a avec un contenu provisoire ;
/// remplie par T5 seule (liste et détail, `EtabMissionsScreen`). La coquille porte dès T2a le bouton
/// « Publier » de la barre de Missions (D13), masqué sans la permission `missions` (§2.7) ; il pousse la
/// destination `.publication` du registre (T9). Identifiants : `placeholder-etab-missions` (provisoire,
/// migré par T5), `etab-missions-publier`.
struct EtabMissionsRoot: View {
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot

    var body: some View {
        PlaceholderScreen(titre: "Missions", identifier: "placeholder-etab-missions",
                          description: "Les missions de votre établissement arrivent dans une prochaine version de l'application.",
                          etat: "Disponible au lot 5")
            .toolbar {
                if snapshot.context.permissions.missions {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink(value: EtabDestination.publication) {
                            Label("Publier", systemImage: "plus.circle.fill")
                        }
                        .tint(JoleneColor.rose700)
                        .accessibilityIdentifier("etab-missions-publier")
                    }
                }
            }
    }
}
