import SwiftUI
import JoleneCore
import JoleneDesign

extension View {
    /// Bouton Messages de la barre de navigation (en-tête mobile web, `src/components/BarreNavigation.tsx` l.338-347),
    /// posé une fois par L4-T1c sur la racine de chaque onglet (`MainTabView`).
    ///
    /// `explorer` (racine de l'onglet Explorer) : en largeur régulière, le bouton n'est pas posé dans la barre mais en
    /// tête de la rangée de chips d'Explorer (`BoutonMessagesRangee`, comme « Mes favoris », `ExplorerActions`). Sous
    /// iOS 26.2, iPad portrait (run 45446351274), la droite de la barre, réduite par la barre d'onglets du haut, ne tenait
    /// que le bouton Messages : « Filtres » passait dans le menu « Plus », hors d'atteinte (`explorer-filtres-ouvrir`
    /// absent de l'écran, cinq échecs de `DemoExplorerTests`). « Filtres » reste ainsi seul à droite sur tous les formats.
    func boutonMessages(explorer: Bool = false) -> some View {
        modifier(BoutonMessagesBarre(explorer: explorer))
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
    /// Racine d'Explorer : en largeur régulière, le bouton est dans la rangée de chips (`BoutonMessagesRangee`).
    var explorer = false
    @Environment(\.contexteSecondaire) private var contexte
    @Environment(\.horizontalSizeClass) private var classeLargeur

    @ViewBuilder
    func body(content: Content) -> some View {
        if explorer, ExplorerActions.dansLaRangeeDeChips(classeLargeur) {
            content
        } else if let contexte, EcranSecondaire.messagerie(conversationId: nil).estLivre, let cycle = contexte.container.cycleMessagerie {
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

/// Bouton Messages en tête de la rangée de chips d'Explorer, en largeur régulière seulement (voir `boutonMessages(explorer:)`),
/// même bouton, mêmes identifiants et même ouverture que dans la barre. Rien n'est rendu en largeur compacte (le bouton
/// est alors dans la barre), si l'écran n'est pas livré ou hors de l'espace prêt.
struct BoutonMessagesRangee: View {
    @Environment(\.contexteSecondaire) private var contexte
    @Environment(\.horizontalSizeClass) private var classeLargeur

    var body: some View {
        if ExplorerActions.dansLaRangeeDeChips(classeLargeur), let contexte,
           EcranSecondaire.messagerie(conversationId: nil).estLivre, let cycle = contexte.container.cycleMessagerie {
            BoutonMessages(cycle: cycle) { contexte.ouvrir(.secondaire(.messagerie(conversationId: nil))) }
                .buttonStyle(.plain)
                .modifier(ExplorerActions.Pastille())
                .padding(.leading, JoleneSpacing.xs)
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
