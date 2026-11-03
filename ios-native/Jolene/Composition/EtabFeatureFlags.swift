import SwiftUI
import JoleneCore

/// Pilotage d'un écran de l'espace établissement (lot 5, T2a ; §2.7, D14), dans cet ordre :
/// 1. permission servie (`fn_mes_permissions_etab`) : sans elle, `EtabAccesRefuseScreen` (fail-closed) ;
/// 2. drapeau `ios_natif_etab_<ecran>_actif` : coupé, `RenvoiWebEtabScreen` — l'écran natif n'est
///    jamais monté. Les valeurs sont lues par `SessionStore` (`EcransEtablissementModel`) avant la
///    publication de `.readyEtablissement` et à chaque reprise ; défaut fail-open.
///
/// Appliqué à la `NavigationStack` de chaque onglet, avant `.tabItem` / `.tag` (le bouton d'onglet,
/// son symbole et son identifiant `tab-etab-*` restent ceux de la coquille). Le refus et le renvoi
/// ont leur propre pile.
private struct EcranEtablissementPilote: ViewModifier {
    let ecran: EcranNatifEtablissement
    let snapshot: EtablissementSessionSnapshot
    @ObservedObject var session: SessionStore
    @ObservedObject var ecrans: EcransEtablissementModel
    /// Déconnexion offerte par le renvoi de l'onglet Compte, seul porteur du bouton « Se déconnecter ».
    let deconnexion: (() -> Void)?

    func body(content: Content) -> some View {
        if let permission = ecran.permissionRequise, !snapshot.context.permissions[permission] {
            NavigationStack {
                EtabAccesRefuseScreen(session: session, titre: ecran.titre)
            }
        } else if !ecrans.estActif(ecran, epoch: snapshot.epoch) {
            NavigationStack {
                RenvoiWebEtabScreen(ecran: ecran, deconnexion: deconnexion)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Pilote l'onglet par sa permission puis par son drapeau `ios_natif_etab_<ecran>_actif`.
    func ecranEtablissement(_ ecran: EcranNatifEtablissement, snapshot: EtablissementSessionSnapshot, session: SessionStore,
                            deconnexion: (() -> Void)? = nil) -> some View {
        modifier(EcranEtablissementPilote(ecran: ecran, snapshot: snapshot, session: session,
                                          ecrans: session.ecransEtablissement, deconnexion: deconnexion))
    }
}
