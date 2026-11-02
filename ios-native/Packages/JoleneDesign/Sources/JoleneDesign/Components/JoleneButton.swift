import SwiftUI

/// Bouton Jolene : primaire (dégradé rose → mauve), secondaire (bordure rose) ou destructif
/// (dégradé rouge → rose `#FF4D6B → #FF6BBE`, actions irréversibles). Calqué sur `BoutonY2K`
/// web : tout style plein porte l'encre sombre `#2B183D` (`text-[#2b183d]`), seule à atteindre
/// 4,5:1 sur les dégradés clairs ; la couleur seule ne porte jamais l'information (libellé explicite).
public struct JoleneButton: View {
    public enum Style: CaseIterable, Sendable {
        case primary, secondary, destructive

        /// Fond plein (dégradé) ; `false` pour le secondaire (surface claire, bordure rose).
        public var isFilled: Bool { self != .secondary }

        /// Encre sombre `JoleneColor.onGradient` sur tout fond plein : `BoutonY2K` primary et destructive
        /// (`text-[#2b183d]`), `.bg-gradient-hero { color: #2b183d }`. Le texte blanc du lot 0 ne faisait que
        /// 2,59:1 sur le rose et 2,78:1 sur le mauve (revue B8).
        public var usesDarkTextOnFill: Bool { isFilled }

        /// Arrêts du dégradé de fond (clair et sombre), vérifiés à ≥ 4,5:1 avec l'encre sombre par les
        /// tests ; vide pour le secondaire.
        public var fillStops: [JoleneHex] {
            switch self {
            case .primary: return JoleneColor.heroGradientStops.flatMap(\.variants)
            case .destructive: return JoleneColor.destructiveGradientHex.compactMap(JoleneHex.parse)
            case .secondary: return []
            }
        }

        /// Couleur du libellé et de l'indicateur de chargement.
        var foreground: Color { usesDarkTextOnFill ? JoleneColor.onGradient : JoleneColor.rose700 }
    }

    private let title: String
    private let style: Style
    private let isLoading: Bool
    private let action: () -> Void

    public init(_ title: String, style: Style = .primary, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.style = style; self.isLoading = isLoading; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: JoleneSpacing.sm) {
                if isLoading { ProgressView().tint(style.foreground) }
                Text(title).font(JoleneFont.button)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, JoleneSpacing.lg)
        }
        .buttonStyle(JoleneButtonStyle(style: style))
        .disabled(isLoading)
    }
}

struct JoleneButtonStyle: ButtonStyle {
    let style: JoleneButton.Style
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(style.foreground)
            .background(background)
            .overlay(
                Capsule().strokeBorder(style == .secondary ? JoleneColor.rose : Color.clear, lineWidth: 1.5)
            )
            .clipShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .primary: JoleneColor.heroGradient
        case .destructive: JoleneColor.destructiveGradient
        case .secondary: JoleneColor.cloud
        }
    }
}
