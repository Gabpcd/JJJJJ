import SwiftUI

/// Ligne d'interrupteur, port de `ToggleCanal` (`src/pages/PageParametresNotifications.tsx` l.442-461 :
/// icône, libellé, `role="switch"`, `opacity-50` et clic ignoré quand le canal est bloqué) et des
/// interrupteurs de la matrice par événement (l.402-413 : raison du blocage dans `title`). Interrupteur
/// natif (`Toggle`, style `.switch`) : VoiceOver annonce « interrupteur, activé / désactivé », un XCUITest
/// l'atteint par `app.switches[identifier]`. Aucune règle métier : l'écran décide si la ligne est bloquée
/// (canal global coupé) et ne déclare un enregistrement réussi qu'après relecture serveur (T6).
///
/// - Libellé vocalisé court (le titre) ; la description, et la raison du blocage avant elle, sont lues en
///   indice. La raison est aussi affichée (pas d'infobulle sur iOS) ; textes fournis verbatim par l'écran.
/// - Cible tactile : ligne d'au moins 44 pt ; un tap sur le libellé bascule aussi l'interrupteur (le
///   `Toggle` SwiftUI ne le fait pas seul), jamais quand la ligne est bloquée.
/// - Teinte `rose-700` : ≥ 3:1 (WCAG 1.4.11) sur carte, écran et softGradient, là où le rose de marque
///   (`bg-primary` du web) tombe à 2,51:1 sur `cloud`.
public struct ToggleRow: View {
    nonisolated public static let minimumHeight: CGFloat = 44
    nonisolated public static let tintHSL = JoleneColor.rose700HSL
    nonisolated public static let iconInkHSL = JoleneColor.rose700HSL
    nonisolated public static let titleInkHSL = JoleneColor.midnightHSL
    nonisolated public static let secondaryInkHSL = JoleneColor.bubblegumHSL
    /// `opacity-50` de `ToggleCanal` quand `disabled`.
    nonisolated public static let disabledOpacity: Double = 0.5

    /// Partie calculable de la ligne selon son état.
    public struct Presentation: Equatable, Sendable {
        public var accessibilityLabel: String
        public var accessibilityHint: String?
        /// Raison affichée sous la description, seulement quand la ligne est bloquée.
        public var visibleReason: String?
        public var opacity: Double
        public var allowsToggle: Bool

        public static func resolve(title: String, description: String?, isDisabled: Bool, disabledReason: String?) -> Presentation {
            let raison = isDisabled ? disabledReason : nil
            let indice = [raison, description].compactMap { $0 }.joined(separator: ". ")
            return Presentation(accessibilityLabel: title, accessibilityHint: indice.isEmpty ? nil : indice,
                                visibleReason: raison, opacity: isDisabled ? ToggleRow.disabledOpacity : 1,
                                allowsToggle: !isDisabled)
        }
    }

    /// Valeur après un tap sur le libellé : inchangée si la ligne est bloquée (web : `!disabled && onChange(!actif)`).
    nonisolated static func toggled(_ value: Bool, allowsToggle: Bool) -> Bool { allowsToggle ? !value : value }

    private let title: String
    private let description: String?
    private let systemImage: String?
    @Binding private var isOn: Bool
    private let isDisabled: Bool
    private let disabledReason: String?
    private let isBordered: Bool
    private let identifier: String

    /// - Parameter isBordered: cadre arrondi de `ToggleCanal` (`rounded-lg border p-3`) ; `false` dans une
    ///   liste qui dessine déjà ses rangées.
    public init(_ title: String, description: String? = nil, systemImage: String? = nil, isOn: Binding<Bool>,
                isDisabled: Bool = false, disabledReason: String? = nil, isBordered: Bool = true, identifier: String) {
        self.title = title; self.description = description; self.systemImage = systemImage; self._isOn = isOn
        self.isDisabled = isDisabled; self.disabledReason = disabledReason; self.isBordered = isBordered
        self.identifier = identifier
    }

    public var body: some View {
        let presentation = Presentation.resolve(title: title, description: description, isDisabled: isDisabled,
                                                disabledReason: disabledReason)
        Toggle(isOn: $isOn) {
            label(presentation)
                .frame(maxWidth: .infinity, minHeight: Self.minimumHeight, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Double garde : la ligne bloquée est déjà `.disabled`, la règle est revérifiée au tap.
                    isOn = Self.toggled(isOn, allowsToggle: presentation.allowsToggle)
                }
        }
        .toggleStyle(.switch)
        .tint(Color(Self.tintHSL))
        .disabled(isDisabled)
        .opacity(presentation.opacity)
        .padding(.horizontal, isBordered ? JoleneSpacing.md : 0)
        .padding(.vertical, isBordered ? JoleneSpacing.xs : 0)
        .background(isBordered ? JoleneColor.cloud : Color.clear)
        .overlay {
            if isBordered {
                RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(JoleneColor.rose100, lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isBordered ? JoleneRadius.field : 0))
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint(presentation.accessibilityHint ?? "")
        .accessibilityIdentifier(identifier)
    }

    private func label(_ presentation: Presentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(JoleneFont.callout)
                    .foregroundStyle(Color(Self.iconInkHSL))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(JoleneFont.callout)
                    .foregroundStyle(Color(Self.titleInkHSL))
                    .fixedSize(horizontal: false, vertical: true)
                if let description {
                    Text(description)
                        .font(JoleneFont.caption)
                        .foregroundStyle(Color(Self.secondaryInkHSL))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let raison = presentation.visibleReason {
                    Text(raison)
                        .font(JoleneFont.caption)
                        .foregroundStyle(Color(Self.secondaryInkHSL))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, JoleneSpacing.xs)
    }
}
