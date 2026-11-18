import SwiftUI
import JoleneCore

extension View {
    /// Bouton Messages de la barre de navigation (en-tête mobile web, `src/components/BarreNavigation.tsx` l.338-347),
    /// posé une fois par L4-T1c sur la racine de chaque onglet (`MainTabView`).
    func boutonMessages() -> some View {
        modifier(BoutonMessagesBarre())
    }
}

/// **Stub de L4-T1c**, remplacé par T7b sans retoucher `MainTabView.swift` : icône Messages et badge
/// `fn_messages_non_lus()` (correction 19), ouverture de `.secondaire(.messagerie(conversationId: nil))` par
/// `contexteSecondaire.ouvrir`. Tant que la messagerie n'est pas livrée, la barre reste inchangée.
struct BoutonMessagesBarre: ViewModifier {
    @Environment(\.contexteSecondaire) private var contexte

    func body(content: Content) -> some View {
        content
    }
}
