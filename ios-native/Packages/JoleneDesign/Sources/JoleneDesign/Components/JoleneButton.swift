import SwiftUI

/// Bouton Jolene : primaire (dégradé rose → mauve, texte blanc) ou secondaire (bordure rose).
/// Calqué sur `BoutonY2K` web ; la couleur seule ne porte jamais l'information (libellé explicite).
public struct JoleneButton: View {
    public enum Style: Sendable { case primary, secondary }

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
                if isLoading { ProgressView().tint(style == .primary ? .white : JoleneColor.rose700) }
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
            .foregroundStyle(style == .primary ? Color.white : JoleneColor.rose700)
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
        if style == .primary { JoleneColor.heroGradient } else { JoleneColor.cloud }
    }
}
