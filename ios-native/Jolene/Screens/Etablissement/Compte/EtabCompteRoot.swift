import SwiftUI
import JoleneCore
import JoleneDesign

/// Racine de l'onglet Compte de l'espace établissement, posée par T2a avec un contenu provisoire minimal
/// — établissement servi, rôle d'équipe, email, déconnexion, version, sentinelle réseau démo — ; remplie
/// par T12 seule (logo, renvois web, suppression du compte D17), qui migre les identifiants utilisés par
/// `DemoEtabSessionTests` : `etab-compte-list`, `etab-compte-{nom|role|email|version}`, `logout-button`,
/// `network-sentinel`. Aucune action n'exige de permission : la déconnexion reste toujours possible.
struct EtabCompteRoot: View {
    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot
    @State private var deconnexionEnCours = false

    var body: some View {
        List {
            Section("Établissement") {
                ligne("Établissement", snapshot.etablissement.nom, identifiant: "etab-compte-nom")
                ligne("Rôle", snapshot.context.roleEtab.libelle, identifiant: "etab-compte-role")
                ligne("Email", snapshot.user.email ?? "—", identifiant: "etab-compte-email")
            }
            Section {
                JoleneButton("Se déconnecter", style: .secondary, isLoading: deconnexionEnCours) {
                    deconnexionEnCours = true
                    Task { await session.signOut() }
                }
                .accessibilityIdentifier("logout-button")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section("Application") {
                ligne("Version", "\(JoleneCore.version) · \(container.environment.mode.rawValue)", identifiant: "etab-compte-version")
                #if DEBUG
                if let monitor = container.networkSentinel {
                    NetworkSentinelRow(monitor: monitor)
                }
                #endif
            }
        }
        .accessibilityIdentifier("etab-compte-list")
        .scrollContentBackground(.hidden)
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle("Compte")
    }

    /// Libellé et valeur ; l'identifiant désigne la seule valeur (assertion exacte en XCUITest).
    private func ligne(_ titre: String, _ valeur: String, identifiant: String) -> some View {
        HStack {
            Text(titre)
            Spacer()
            Text(valeur)
                .foregroundStyle(JoleneColor.bubblegum)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(identifiant)
        }
    }
}
