import SwiftUI
import JoleneCore

/// Arrêt d'urgence par onglet (lot 1, T9, décision 15) : un onglet dont le drapeau
/// `ios_natif_<ecran>_actif` vaut `false` affiche `RenvoiWebScreen` au lieu de son écran natif, qui
/// n'est alors jamais monté. Les valeurs sont lues par `SessionStore` (`EcransNatifsModel`) avant la
/// publication de `.ready` et à chaque reprise ; défaut fail-open `true` (B0 absente, erreur, délai).
///
/// Appliqué à la `NavigationStack` de chaque onglet, avant `.tabItem` / `.tag` (le bouton d'onglet,
/// son symbole et son identifiant `tab-*` restent ceux du socle). Le renvoi a sa propre pile.
private struct EcranNatifPilote: ViewModifier {
    let ecran: EcranNatif
    @ObservedObject var ecrans: EcransNatifsModel
    /// Déconnexion offerte par le renvoi de l'onglet Profil, seul porteur du bouton « Se déconnecter ».
    let deconnexion: (() -> Void)?

    func body(content: Content) -> some View {
        if ecrans.estActif(ecran) {
            content
        } else {
            NavigationStack {
                RenvoiWebScreen(ecran: ecran, deconnexion: deconnexion)
            }
        }
    }
}

extension View {
    /// Pilote l'onglet par son drapeau `ios_natif_<ecran>_actif`.
    func ecranNatif(_ ecran: EcranNatif, ecrans: EcransNatifsModel, deconnexion: (() -> Void)? = nil) -> some View {
        modifier(EcranNatifPilote(ecran: ecran, ecrans: ecrans, deconnexion: deconnexion))
    }
}
