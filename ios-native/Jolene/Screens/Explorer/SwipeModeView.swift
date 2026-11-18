import SwiftUI
import JoleneCore

extension View {
    /// Vue Swipe de l'onglet Explorer (L4-T1c, `LOT4_PLAN.md` §1.1 et §2.5), posée une fois sur le contenu de
    /// `MissionsListScreen`.
    func vueSwipe(model: MissionsListModel) -> some View {
        modifier(VueSwipeExplorer(model: model))
    }
}

/// **Stub de L4-T1c**, remplacé par T3b sans retoucher `MissionsListScreen.swift` : commande segmentée Swipe · Liste ·
/// Carte du web (`RechercheMissions.tsx` l.288-300 ; préférence locale par userId ; vue Carte du lot 1 T4a), paquet de
/// cartes, coupe-circuit `ios_natif_swipe_actif` (faux : vue Liste, bascule masquée). Tant que le swipe n'est pas
/// livré, Explorer reste inchangé : ni commande, ni vue Swipe (`/soignant/swipe-missions` ouvre Explorer, repli de
/// `EcranSecondaire.repliAvantLivraison`).
struct VueSwipeExplorer: ViewModifier {
    @ObservedObject var model: MissionsListModel
    @Environment(\.contexteSecondaire) private var contexte

    func body(content: Content) -> some View {
        content
    }
}
