import SwiftUI
import JoleneCore
import JoleneDesign

/// Section « Mon espace » du Profil (décision 24 du lot 2 : pas de sixième onglet) : Mes présences, Mes documents,
/// Mes contrats. Titres des pages web (`LibellesWeb.ListePresences.titre`, `LibellesWeb.EspaceSoignant`) ; titre de la
/// section : texte opérationnel inventorié (`LibellesPresences.EspaceSoignant.titreSection`).
///
/// « Mes documents » et « Mes contrats » ouvrent un écran provisoire honnête jusqu'aux tranches T7 et T9a
/// (`placeholder-documents`, `placeholder-contrats`), qui le remplacent et migrent les identifiants de
/// `DemoPresencesTests`. T4b ajoute ici une ligne (consentement GPS, `profil-gps-consentement`).
struct EspaceSoignantSection: View {
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
                PlaceholderScreen(titre: LibellesWeb.EspaceSoignant.mesDocuments, identifier: "placeholder-documents",
                                  description: LibellesPresences.Provisoire.documents, etat: LibellesPresences.Provisoire.etat)
            } label: {
                Label(LibellesWeb.EspaceSoignant.mesDocuments, systemImage: "doc.text")
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
