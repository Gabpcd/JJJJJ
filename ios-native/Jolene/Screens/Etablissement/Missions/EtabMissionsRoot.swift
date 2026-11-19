import SwiftUI
import JoleneCore
import JoleneDesign

/// Racine de l'onglet Missions de l'espace établissement, posée par T2a, remplie par T5 : liste des missions
/// (`EtabMissionsScreen`) ; le détail est la destination `.detailMission` du registre (`EtabDestinations.swift`).
/// La coquille porte le bouton « Publier » de la barre de Missions (D13), masqué sans la permission `missions`
/// (§2.7) ; il pousse la destination `.publication` du registre (T9). Identifiants : `etab-missions-screen`
/// (T5, remplace `placeholder-etab-missions`), `etab-missions-publier`.
struct EtabMissionsRoot: View {
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot
    /// Lot 5, T5 : filtre `?statut=` porté par un lien vers la liste (T2b).
    var demande = DemandeFiltreMissions()

    var body: some View {
        EtabMissionsScreen(session: session, snapshot: snapshot, demande: demande)
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
