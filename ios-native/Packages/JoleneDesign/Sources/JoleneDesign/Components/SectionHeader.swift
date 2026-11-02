import SwiftUI

/// En-tête de section (Accueil, Mes missions) : titre + action secondaire optionnelle
/// (« Tout voir »). Identifiants `<identifier>-title` et `<identifier>-action`.
///
/// Sans fond propre : le texte hérite de la surface de l'écran (carte `cloud`, écran `lavender`,
/// bas du `softGradient` `rose100`). Encres choisies pour 4,5:1 sur chacune, en clair et en sombre
/// (`JoleneColor.inheritedSurfacesHSL`, test) : titre `midnight`, action `rose800`. Cible tactile de
/// l'action : 44 pt minimum, posée dans le label du bouton (zone de tap réelle).
public struct SectionHeader: View {
    nonisolated public static func titleIdentifier(for identifier: String) -> String { "\(identifier)-title" }
    nonisolated public static func actionIdentifier(for identifier: String) -> String { "\(identifier)-action" }

    nonisolated public static let titleInkHSL = JoleneColor.midnightHSL
    nonisolated public static let actionInkHSL = JoleneColor.rose800HSL
    /// Hauteur et largeur minimales de la zone de tap de l'action (HIG, `min-h-[44px]` web).
    nonisolated public static let minimumTapTarget: CGFloat = 44

    private let title: String
    private let identifier: String
    private let action: (title: String, run: () -> Void)?

    public init(_ title: String, identifier: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title; self.identifier = identifier
        if let actionTitle, let action { self.action = (actionTitle, action) } else { self.action = nil }
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
            Text(title)
                .font(JoleneFont.headline)
                .foregroundStyle(Color(Self.titleInkHSL))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(Self.titleIdentifier(for: identifier))
            Spacer(minLength: 0)
            if let action {
                Button(action: action.run) {
                    // Cadre et forme de tap DANS le label : la zone touchable fait 44 pt, pas le seul texte.
                    Text(action.title)
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(Color(Self.actionInkHSL))
                        .frame(minWidth: Self.minimumTapTarget, minHeight: Self.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(Self.actionIdentifier(for: identifier))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
