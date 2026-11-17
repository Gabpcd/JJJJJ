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
///
/// L2-T10 (revue B8 de la PR #1131, m3) : les trois entrées sont des liens **par valeur** (`MonEspaceRoute`, enregistrée
/// par `MainTabView` sur la pile du Profil), pour qu'un lien ou un tap push ramène la pile à sa racine avant d'empiler sa
/// cible, même quand un écran de « Mon espace » est affiché.
struct EspaceSoignantSection: View {
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot

    var body: some View {
        Section {
            NavigationLink(value: MonEspaceRoute.presences(onglet: nil, filtre: nil)) {
                Label(LibellesWeb.ListePresences.titre, systemImage: "clock")
            }
            .accessibilityIdentifier("profil-presences")

            NavigationLink(value: MonEspaceRoute.documents(onglet: .justificatifs)) {
                Label(LibellesWeb.EspaceSoignant.mesDocuments, systemImage: "folder")
            }
            .accessibilityIdentifier("profil-documents")

            NavigationLink(value: MonEspaceRoute.contrats) {
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
