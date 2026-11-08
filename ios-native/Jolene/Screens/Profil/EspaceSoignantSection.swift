import SwiftUI
import JoleneCore
import JoleneDesign

/// Section « Mon espace » du Profil (blueprint `LOT2_PLAN.md` §7 Q24 : pas de sixième onglet). Lot 2 T7 : « Mes documents »
/// (`profil-documents`). T4a y ajoute « Mes présences » (`profil-presences`) et « Mes contrats » (`profil-contrats`), T4b
/// l'interrupteur du consentement GPS (`profil-gps-consentement`) : une ligne par tranche.
struct EspaceSoignantSection: View {
    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot

    var body: some View {
        Section(LibellesJustificatifs.monEspace) {
            NavigationLink {
                MesDocumentsScreen(container: container, session: session, snapshot: snapshot)
            } label: {
                Label(LibellesJustificatifs.titre, systemImage: "folder")
                    .foregroundStyle(JoleneColor.midnight)
            }
            .accessibilityIdentifier("profil-documents")
        }
    }
}
