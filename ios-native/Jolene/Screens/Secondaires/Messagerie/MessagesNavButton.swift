import SwiftUI
import JoleneCore
import JoleneDesign

extension View {
    /// Bouton Messages de la barre de navigation (en-tête mobile web, `src/components/BarreNavigation.tsx` l.338-347),
    /// posé une fois par L4-T1c sur la racine de chaque onglet (`MainTabView`).
    func boutonMessages() -> some View {
        modifier(BoutonMessagesBarre())
    }
}

/// Bouton Messages (L4-T7b, remplace le stub de T1c sans retoucher `MainTabView.swift`) : icône, libellé vocalisé
/// « Messages » (`aria-label` du web, l.401) et badge `fn_messages_non_lus()` (correction 19) lu par `CycleRealtime` —
/// `9+` au-delà de 9, rien à zéro ou tant qu'aucune lecture n'a abouti (jamais un badge fabriqué). Ouvre
/// `.secondaire(.messagerie(conversationId: nil))` par `contexteSecondaire.ouvrir`. Rien n'est rendu si l'écran n'est pas
/// livré ou hors de l'espace prêt.
///
/// Identifiants : `nav-messages` (valeur = badge affiché), `nav-messages-badge`.
struct BoutonMessagesBarre: ViewModifier {
    @Environment(\.contexteSecondaire) private var contexte

    @ViewBuilder
    func body(content: Content) -> some View {
        if let contexte, EcranSecondaire.messagerie(conversationId: nil).estLivre, let cycle = contexte.container.cycleMessagerie {
            content.toolbar {
                ToolbarItem(placement: .primaryAction) {
                    BoutonMessages(cycle: cycle) { contexte.ouvrir(.secondaire(.messagerie(conversationId: nil))) }
                }
            }
        } else {
            content
        }
    }
}

private struct BoutonMessages: View {
    @ObservedObject var cycle: CycleRealtime
    let ouvrir: () -> Void

    var body: some View {
        let badge = MessageriePresentation.badge(cycle.nonLus)
        Button(action: ouvrir) {
            Image(systemName: "message")
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .frame(minWidth: 44, minHeight: 44)
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(JoleneColor.rose700)
                            .clipShape(Capsule())
                            .offset(x: -2, y: 4)
                            .accessibilityIdentifier("nav-messages-badge")
                    }
                }
        }
        .accessibilityLabel(MessagerieTextes.boutonMessages)
        .accessibilityValue(badge ?? "")
        .accessibilityIdentifier("nav-messages")
    }
}
