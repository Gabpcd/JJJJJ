import SwiftUI
import JoleneCore

/// Racine de l'onglet Compte de l'espace établissement, posée par T2a, remplie par T12 : identité servie, renvois web,
/// déconnexion, version (`EtabCompteScreen`). Aucune action n'exige de permission : la déconnexion et le lien de
/// suppression du compte (D17) restent toujours atteignables.
struct EtabCompteRoot: View {
    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot

    var body: some View {
        EtabCompteScreen(container: container, session: session, snapshot: snapshot)
    }
}
