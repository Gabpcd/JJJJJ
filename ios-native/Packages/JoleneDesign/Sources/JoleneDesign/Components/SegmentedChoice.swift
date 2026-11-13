import SwiftUI

/// Choix exclusif entre quelques options (thème Système / Clair / Sombre de T11, D16 ; sections d'un
/// écran). Segments boutons plutôt que `Picker(.segmented)` : chaque option porte son identifiant
/// d'accessibilité (`<identifier>-<option.id>`, jamais déduit du libellé, PRINCIPES §6) et le trait
/// « Sélectionné » (seul mécanisme vocalisé de l'état, comme `FilterChip`). Segment choisi : dégradé hero
/// complet et encre `#2B183D` (jeton `.bg-gradient-hero`), autres segments `bubblegum` sur la piste
/// `lavender`. Cible tactile 44 pt posée dans le label de chaque bouton. Libellés fournis par l'écran.
///
/// Une sélection absente des options n'allume aucun segment (jamais le premier par défaut) ; les
/// identifiants d'option doivent être uniques. Aux tailles Dynamic Type d'accessibilité, ou si les
/// segments ne tiennent pas sur une ligne (`ViewThatFits`), ils passent en colonne.
public struct SegmentedChoice: View {
    public struct Option: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var systemImage: String?

        public init(id: String, title: String, systemImage: String? = nil) {
            self.id = id; self.title = title; self.systemImage = systemImage
        }
    }

    public enum Layout: Equatable, Sendable { case horizontal, vertical }

    /// Apparence calculable d'un segment selon son état.
    public struct Appearance: Equatable, Sendable {
        public var usesGradient: Bool
        public var announcesSelected: Bool
        /// Couleur fixe du libellé sur le dégradé ; `nil` = jeton dynamique `bubblegum`.
        public var foregroundHex: String?

        public static func resolve(isSelected: Bool) -> Appearance {
            Appearance(usesGradient: isSelected, announcesSelected: isSelected,
                       foregroundHex: isSelected ? JoleneColor.onGradientHex : nil)
        }
    }

    nonisolated public static let minimumHeight: CGFloat = 44
    nonisolated public static let activeGradientStops = JoleneColor.heroGradientFullStops
    nonisolated public static let trackHSL = JoleneColor.lavenderHSL
    nonisolated public static let inactiveInkHSL = JoleneColor.bubblegumHSL

    nonisolated public static func optionIdentifier(_ identifier: String, optionID: String) -> String { "\(identifier)-\(optionID)" }

    nonisolated public static func isSelected(_ option: Option, selection: String) -> Bool { option.id == selection }

    /// Tailles d'accessibilité (`accessibility1` à `accessibility5`) : toujours en colonne.
    nonisolated public static func layout(for size: DynamicTypeSize) -> Layout { size.isAccessibilitySize ? .vertical : .horizontal }

    private let title: String
    private let options: [Option]
    @Binding private var selection: String
    private let identifier: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameter title: libellé du groupe, vocalisé à l'entrée dans le contrôle (l'écran affiche son propre titre).
    public init(_ title: String, options: [Option], selection: Binding<String>, identifier: String) {
        self.title = title; self.options = options; self._selection = selection; self.identifier = identifier
    }

    public var body: some View {
        Group {
            switch Self.layout(for: dynamicTypeSize) {
            case .vertical:
                vertical
            case .horizontal:
                ViewThatFits(in: .horizontal) {
                    horizontal
                    vertical
                }
            }
        }
        .padding(JoleneSpacing.xs)
        .background(Color(Self.trackHSL))
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field + JoleneSpacing.xs))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private var horizontal: some View {
        HStack(spacing: JoleneSpacing.xs) { segments }
    }

    private var vertical: some View {
        VStack(spacing: JoleneSpacing.xs) { segments }
    }

    private var segments: some View {
        ForEach(options) { option in
            Segment(option: option, isSelected: Self.isSelected(option, selection: selection),
                    identifier: Self.optionIdentifier(identifier, optionID: option.id)) {
                selection = option.id
            }
        }
    }

    /// Un segment : bouton dont le label porte le cadre minimal (zone de tap réelle, mesurée par les tests).
    struct Segment: View {
        let option: Option
        let isSelected: Bool
        let identifier: String
        let action: () -> Void

        var body: some View {
            let appearance = Appearance.resolve(isSelected: isSelected)
            Button(action: action) {
                HStack(spacing: JoleneSpacing.xs) {
                    if let systemImage = option.systemImage {
                        Image(systemName: systemImage).accessibilityHidden(true)
                    }
                    Text(option.title)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(JoleneFont.callout.weight(.semibold))
                .padding(.horizontal, JoleneSpacing.md)
                .frame(maxWidth: .infinity, minHeight: SegmentedChoice.minimumHeight)
                .frame(minWidth: SegmentedChoice.minimumHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(SegmentStyle(appearance: appearance))
            .accessibilityAddTraits(appearance.announcesSelected ? .isSelected : [])
            .accessibilityIdentifier(identifier)
        }
    }
}

struct SegmentStyle: ButtonStyle {
    let appearance: SegmentedChoice.Appearance

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(appearance.foregroundHex.map { Color(hex: $0) } ?? Color(SegmentedChoice.inactiveInkHSL))
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder private var background: some View {
        if appearance.usesGradient { JoleneColor.heroGradientFull } else { Color.clear }
    }
}
