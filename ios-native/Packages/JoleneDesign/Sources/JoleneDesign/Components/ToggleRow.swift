import SwiftUI

/// Ligne d'interrupteur, port de `ToggleCanal` (`src/pages/PageParametresNotifications.tsx` l.442-461 :
/// icône, libellé, `role="switch"`, `opacity-50` et clic ignoré quand le canal est bloqué) et des
/// interrupteurs de la matrice par événement (l.402-413 : raison du blocage dans `title`). Interrupteur
/// natif (`Toggle`, style `.switch`) : VoiceOver annonce « interrupteur, activé / désactivé », un XCUITest
/// l'atteint par `app.switches[identifier]`. Aucune règle métier : l'écran décide si la ligne est bloquée
/// (canal global coupé) et ne déclare un enregistrement réussi qu'après relecture serveur (T6).
///
/// - Libellé vocalisé : le titre, suivi de la raison du blocage quand la ligne est bloquée (comme l'`aria-label`
///   de la matrice web, l.410 : « canal global désactivé »), donc entendue même quand les indices VoiceOver
///   sont coupés ; la description est lue en indice. La raison est aussi affichée (pas d'infobulle sur iOS),
///   **hors du voile** d'opacité, en encre pleine (`reasonInkHSL`, ≥ 4,5:1) : le voile ne couvre que
///   l'interrupteur, l'icône, le titre et la description (contrôle inactif). Textes fournis verbatim par l'écran.
/// - Cible tactile : ligne d'au moins 44 pt (recommandation Apple ; `ToggleCanal` n'a pas de hauteur
///   minimale) ; un tap sur le libellé bascule aussi l'interrupteur (le
///   `Toggle` SwiftUI ne le fait pas seul), jamais quand la ligne est bloquée.
/// - Teinte `rose-700` : ≥ 3:1 (WCAG 1.4.11) sur carte, écran et softGradient, là où le rose de marque
///   (`bg-primary` du web) tombe à 2,51:1 sur `cloud`.
public struct ToggleRow: View {
    nonisolated public static let minimumHeight: CGFloat = 44
    nonisolated public static let tintHSL = JoleneColor.rose700HSL
    nonisolated public static let iconInkHSL = JoleneColor.rose700HSL
    nonisolated public static let titleInkHSL = JoleneColor.midnightHSL
    nonisolated public static let secondaryInkHSL = JoleneColor.bubblegumHSL
    /// Raison du blocage, dessinée hors du voile : information, pas partie du contrôle inactif.
    nonisolated public static let reasonInkHSL = JoleneColor.bubblegumHSL
    /// `opacity-50` de `ToggleCanal` quand `disabled` (interrupteur, icône, titre, description).
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
            // Raison verbatim, seulement si la ligne est bloquée et que le texte n'est pas vide.
            let raison = isDisabled ? disabledReason.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } : nil
            let indice = description.flatMap { $0.isEmpty ? nil : $0 }
            return Presentation(accessibilityLabel: [title, raison].compactMap { $0 }.joined(separator: ", "),
                                accessibilityHint: indice, visibleReason: raison,
                                opacity: isDisabled ? ToggleRow.disabledOpacity : 1, allowsToggle: !isDisabled)
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
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $isOn) {
                label
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
            .accessibilityLabel(presentation.accessibilityLabel)
            .accessibilityHint(presentation.accessibilityHint ?? "")
            .accessibilityIdentifier(identifier)
            if let raison = presentation.visibleReason {
                reason(raison)
            }
        }
        .padding(.horizontal, isBordered ? JoleneSpacing.md : 0)
        .padding(.vertical, isBordered ? JoleneSpacing.xs : 0)
        .background(isBordered ? JoleneColor.cloud : Color.clear)
        .overlay {
            if isBordered {
                RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(JoleneColor.rose100, lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isBordered ? JoleneRadius.field : 0))
    }

    private var label: some View {
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
            }
        }
        .padding(.vertical, JoleneSpacing.xs)
    }

    /// Raison du blocage sous l'interrupteur, alignée sur le titre (icône masquée gardée pour la marge), hors
    /// du voile d'opacité ; masquée à VoiceOver, car déjà dans le libellé de l'interrupteur.
    private func reason(_ raison: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
            if let systemImage {
                Image(systemName: systemImage).font(JoleneFont.callout).hidden()
            }
            Text(raison)
                .font(JoleneFont.caption)
                .foregroundStyle(Color(Self.reasonInkHSL))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, JoleneSpacing.xs)
        .accessibilityHidden(true)
    }
}
