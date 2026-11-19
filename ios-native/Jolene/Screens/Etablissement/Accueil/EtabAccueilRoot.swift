import SwiftUI
import JoleneCore

/// Racine de l'onglet Accueil de l'espace établissement, posée par T2a, remplie par T4 : actions prioritaires
/// (`EtabAccueilScreen`). `ouvrir` sélectionne un onglet de la coquille et y empile l'écran livré éventuel, comme
/// une demande du coordinateur des liens (`EtablissementTabView.ouvrir`).
struct EtabAccueilRoot: View {
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot
    let ouvrir: (CibleEtablissement) -> Void

    var body: some View {
        EtabAccueilScreen(session: session, snapshot: snapshot, ouvrir: ouvrir)
    }
}
