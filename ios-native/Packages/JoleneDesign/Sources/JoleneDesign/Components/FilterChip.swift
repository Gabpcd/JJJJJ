import SwiftUI

/// Pastille de filtre à bascule, port des chips de `src/pages/RechercheMissions.tsx`
/// (« Urgentes », « Week-end », « Nuit », « Jour ») : `aria-pressed` → trait « sélectionné »
/// + valeur vocalisée, cible tactile 44 pt, dégradé hero quand le filtre est actif.
/// Le filtrage lui-même reste serveur (PostgREST) ; la pastille ne porte que l'état.
public struct FilterChip: View {
    /// `min-h-[44px]` du web : cible tactile minimale.
    nonisolated public static let minimumHeight: CGFloat = 44

    /// Apparence calculable d'une pastille selon son état.
    public struct Appearance: Equatable, Sendable {
        public var usesGradient: Bool
        public var accessibilityValue: String

        public static func resolve(isSelected: Bool) -> Appearance {
            Appearance(usesGradient: isSelected, accessibilityValue: isSelected ? "activé" : "désactivé")
        }
    }

    private let title: String
    private let isSelected: Bool
    private let identifier: String?
    private let action: () -> Void

    public init(_ title: String, isSelected: Bool, identifier: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.isSelected = isSelected; self.identifier = identifier; self.action = action
    }

    public var body: some View {
        let appearance = Appearance.resolve(isSelected: isSelected)
        Button(action: action) {
            Text(title)
                .font(JoleneFont.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, JoleneSpacing.md)
                .frame(minHeight: Self.minimumHeight)
        }
        .buttonStyle(FilterChipStyle(appearance: appearance))
        .accessibilityValue(appearance.accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Retire ce filtre" : "Applique ce filtre")
        .accessibilityIdentifier(identifier ?? "")
    }
}

struct FilterChipStyle: ButtonStyle {
    let appearance: FilterChip.Appearance

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(appearance.usesGradient ? Color.white : JoleneColor.bubblegum)
            .background(background)
            .overlay(Capsule().strokeBorder(appearance.usesGradient ? Color.clear : JoleneColor.rose100, lineWidth: 1))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder private var background: some View {
        if appearance.usesGradient { JoleneColor.heroGradient } else { JoleneColor.cloud }
    }
}

/// Rangée horizontale défilante de pastilles (`overflow-x-auto` du web), sans barre de défilement.
public struct FilterChipRow<Content: View>: View {
    private let identifier: String?
    private let content: Content

    public init(identifier: String? = nil, @ViewBuilder content: () -> Content) {
        self.identifier = identifier; self.content = content()
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JoleneSpacing.sm) { content }
                .padding(.horizontal, JoleneSpacing.lg)
                .padding(.vertical, JoleneSpacing.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "")
    }
}
