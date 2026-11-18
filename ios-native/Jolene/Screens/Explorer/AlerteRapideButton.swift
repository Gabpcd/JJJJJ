import SwiftUI
import JoleneCore

extension View {
    /// « Créer une alerte » en un toucher depuis Explorer (L4-T1c, `LOT4_PLAN.md` §1.1 « Filtres sauvegardés »), posé une
    /// fois sur `MissionsListScreen`.
    func alerteRapide(model: MissionsListModel) -> some View {
        modifier(AlerteRapideExplorer(model: model))
    }
}

/// **Stub de L4-T1c**, remplacé par T4 sans retoucher `MissionsListScreen.swift` : alerte sur les filtres courants
/// (`RechercheMissions.tsx` l.175-226, réactivation d'une recherche strictement identique). Tant que les recherches
/// sauvegardées ne sont pas livrées, Explorer reste inchangé.
struct AlerteRapideExplorer: ViewModifier {
    @ObservedObject var model: MissionsListModel
    @Environment(\.contexteSecondaire) private var contexte

    func body(content: Content) -> some View {
        content
    }
}
