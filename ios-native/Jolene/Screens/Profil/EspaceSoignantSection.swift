import SwiftUI
import JoleneCore
import JoleneDesign

/// Section « Mon espace » du Profil (décision 24 du lot 2 : pas de sixième onglet) : Mes présences, Mes documents,
/// Mes contrats. Titres des pages web (`LibellesWeb.ListePresences.titre`, `LibellesWeb.EspaceSoignant`) ; titre de la
/// section : texte opérationnel inventorié (`LibellesPresences.EspaceSoignant.titreSection`, même texte que
/// `LibellesJustificatifs.monEspace` de T7). Une ligne par tranche : T4a (`profil-presences`), T7 (`profil-documents`,
/// `MesDocumentsScreen`), T9a (`profil-contrats`) ; T4b y ajoute le consentement GPS (`profil-gps-consentement`).
///
/// « Mes contrats » ouvre un écran provisoire honnête jusqu'à T9a (`placeholder-contrats`), qui le remplace et migre
/// les identifiants de `DemoPresencesTests`.
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
                PlaceholderScreen(titre: LibellesWeb.EspaceSoignant.mesContrats, identifier: "placeholder-contrats",
                                  description: LibellesPresences.Provisoire.contrats, etat: LibellesPresences.Provisoire.etat)
            } label: {
                Label(LibellesWeb.EspaceSoignant.mesContrats, systemImage: "signature")
            }
            .accessibilityIdentifier("profil-contrats")
        } header: {
            Text(LibellesPresences.EspaceSoignant.titreSection)
                .accessibilityIdentifier("profil-espace")
        }
    }
}
