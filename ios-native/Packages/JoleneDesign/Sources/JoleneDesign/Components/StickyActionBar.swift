import SwiftUI

/// Barre d'action collante, port de la barre « checkout » mobile de
/// `src/pages/DetailMissionSoignant.tsx` (l.1568-1611) : montant à gauche (rétrocession, net
/// estimé ou taux horaire) avec sa précision (« avant cotisations libérales », « estimation
/// figée à l'acceptation »), CTA à droite, toujours visibles. Les chaînes arrivent déjà
/// formatées par le cœur (`MissionPresentation`) : valeurs serveur, jamais recalculées ici.
/// À monter avec `.safeAreaInset(edge: .bottom)` pour ne pas masquer le bas de page.
public struct StickyActionBar: View {
    public struct Content: Equatable, Sendable {
        public var montant: String
        public var precision: String?
        public var actionTitle: String
        /// Identifiant racine ; les sous-éléments reçoivent `-montant`, `-precision`, `-action`.
        public var identifier: String

        public init(montant: String, precision: String?, actionTitle: String, identifier: String) {
            self.montant = montant; self.precision = precision; self.actionTitle = actionTitle; self.identifier = identifier
        }

        public var accessibilitySummary: String { [montant, precision].compactMap { $0 }.joined(separator: ", ") }
        public var montantIdentifier: String { "\(identifier)-montant" }
        public var precisionIdentifier: String { "\(identifier)-precision" }
        public var actionIdentifier: String { "\(identifier)-action" }
    }

    /// Web : `loading={…}` et `disabled={!conformiteOk || !planningCandidat.exact}` bloquent le CTA.
    nonisolated public static func isActionEnabled(isLoading: Bool, isDisabled: Bool) -> Bool { !isLoading && !isDisabled }

    private let content: Content
    private let isLoading: Bool
    private let isDisabled: Bool
    private let action: () -> Void

    public init(_ content: Content, isLoading: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.content = content; self.isLoading = isLoading; self.isDisabled = isDisabled; self.action = action
    }

    public var body: some View {
        HStack(alignment: .center, spacing: JoleneSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(content.montant)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .lineLimit(2)
                    .accessibilityIdentifier(content.montantIdentifier)
                if let precision = content.precision {
                    Text(precision)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .lineLimit(2)
                        .accessibilityIdentifier(content.precisionIdentifier)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(content.accessibilitySummary)
            Spacer(minLength: JoleneSpacing.sm)
            JoleneButton(content.actionTitle, style: .primary, isLoading: isLoading, action: action)
                .disabled(!Self.isActionEnabled(isLoading: isLoading, isDisabled: isDisabled))
                .frame(maxWidth: 200)
                .accessibilityIdentifier(content.actionIdentifier)
        }
        .padding(.horizontal, JoleneSpacing.lg)
        .padding(.vertical, JoleneSpacing.md)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(JoleneColor.rose100).frame(height: 1) }
        .shadow(color: JoleneColor.midnight.opacity(0.12), radius: 12, x: 0, y: -4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(content.identifier)
    }
}
