import SwiftUI
import JoleneCore

/// Point d'extension provisoire (lot 2, T9a) : entrée « Mes contrats » du Profil (`profil-contrats`), en attendant la
/// section « Mon espace » de T4a (`Screens/Profil/EspaceSoignantSection.swift`, lignes `profil-presences`,
/// `profil-documents`, `profil-contrats`), absente de la base de T9a. À l'intégration de T4a : supprimer ce fichier et
/// la ligne qui le monte dans `ProfileScreen`, puis faire pointer la ligne `profil-contrats` de T4a sur
/// `ContratsDestination.liste(session:snapshot:)` (consigne T9a de `DECISIONS_LOT2.md`). Même identifiant que T4a :
/// `DemoContratsTests` passe par `profil-contrats` et reste valable après la bascule.
struct ContratsEntreeProfil: View {
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot

    var body: some View {
        Section {
            NavigationLink {
                ContratsDestination.liste(session: session, snapshot: snapshot)
            } label: {
                Label(LibellesWeb.Contrats.titre, systemImage: "doc.text")
            }
            .accessibilityIdentifier("profil-contrats")
        }
    }
}
