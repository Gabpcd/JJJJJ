import SwiftUI
import JoleneCore
import JoleneDesign

/// Section « Mon espace » du Profil (décision 24 du lot 2 : pas de sixième onglet) : Mes présences, Mes documents,
/// Mes contrats. Titres des pages web (`LibellesWeb.ListePresences.titre`, `LibellesWeb.EspaceSoignant.mesDocuments`,
/// `LibellesWeb.Contrats.titre`) ; titre de la
/// section : texte opérationnel inventorié (`LibellesPresences.EspaceSoignant.titreSection`, même texte que
/// `LibellesJustificatifs.monEspace` de T7). Une ligne par tranche : T4a (`profil-presences`), T7 (`profil-documents`,
/// `MesDocumentsScreen`), T9a (`profil-contrats`, `ContratsDestination.liste`, qui remplace l'écran provisoire et
/// l'entrée `ContratsEntreeProfil` de T9a à l'intégration) ; T4b : consentement GPS (`ConsentementGpsRow`,
/// `profil-gps-consentement`), retrait et réactivation promis par le texte de consentement (correction 15).
struct EspaceSoignantSection: View {
    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot
    let ouvrirOnglet: (MainTabView.Tab) -> Void

    var body: some View {
        Section {
            NavigationLink {
                PresencesScreen(session: session, snapshot: snapshot, ouvrirOnglet: ouvrirOnglet)
            } label: {
                Label(LibellesWeb.ListePresences.titre, systemImage: "clock")
            }
            .accessibilityIdentifier("profil-presences")

            NavigationLink {
                MesDocumentsScreen(container: container, session: session, snapshot: snapshot)
            } label: {
                Label(LibellesWeb.EspaceSoignant.mesDocuments, systemImage: "folder")
            }
            .accessibilityIdentifier("profil-documents")

            NavigationLink {
                ContratsDestination.liste(session: session, snapshot: snapshot)
            } label: {
                Label(LibellesWeb.Contrats.titre, systemImage: "signature")
            }
            .accessibilityIdentifier("profil-contrats")

            ConsentementGpsRow(session: session, snapshot: snapshot)
        } header: {
            Text(LibellesPresences.EspaceSoignant.titreSection)
                .accessibilityIdentifier("profil-espace")
        }
    }
}
