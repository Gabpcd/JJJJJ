import SwiftUI

/// Barre d'action collante, port de la barre « checkout » mobile de
/// `src/pages/DetailMissionSoignant.tsx` (l.1568-1611) : montant à gauche (rétrocession, net
/// estimé ou taux horaire) avec sa précision (« avant cotisations libérales », « estimation
/// figée à l'acceptation »), CTA à droite, toujours visibles. Les chaînes arrivent déjà
/// formatées par le cœur (`MissionPresentation`) : valeurs serveur, jamais recalculées ici.
/// À monter avec `.stickyActionBar(…)` (`safeAreaInset`) pour ne pas masquer le bas de page,
/// équivalent de l'espaceur `h-16` du web. Le montant n'est jamais tronqué : en ligne quand tout
/// tient, sinon (et toujours aux tailles Dynamic Type d'accessibilité) montant au-dessus et CTA
/// pleine largeur.
public struct StickyActionBar: View {
    /// Disposition imposée par la taille de texte ; `.horizontal` reste soumis à `ViewThatFits`
    /// (repli en colonne si le montant et le CTA ne tiennent pas sur une ligne).
    public enum Layout: Equatable, Sendable { case horizontal, vertical }

    public struct Content: Equatable, Sendable {
        public var montant: String
        public var precision: String?
        public var actionTitle: String
        /// Identifiant racine ; le résumé reçoit `-montant`, le CTA `-action` sauf identifiant imposé.
        public var identifier: String
        private var customActionIdentifier: String?

        public init(montant: String, precision: String?, actionTitle: String, identifier: String,
                    actionIdentifier: String? = nil) {
            self.montant = montant; self.precision = precision; self.actionTitle = actionTitle
            self.identifier = identifier; self.customActionIdentifier = actionIdentifier
        }

        public var accessibilitySummary: String { [montant, precision].compactMap { $0 }.joined(separator: ", ") }
        /// Porté par l'élément combiné montant + précision (les enfants combinés ne sont pas exposés).
        public var montantIdentifier: String { "\(identifier)-montant" }
        public var actionIdentifier: String { customActionIdentifier ?? "\(identifier)-action" }
    }

    /// Largeur utile maximale (iPad), alignée sur le détail mission (`MissionDetailScreen`, 640 pt).
    nonisolated public static let maximumContentWidth: CGFloat = 640

    /// Web : `loading={…}` et `disabled={!conformiteOk || !planningCandidat.exact}` bloquent le CTA.
    nonisolated public static func isActionEnabled(isLoading: Bool, isDisabled: Bool) -> Bool { !isLoading && !isDisabled }

    /// Tailles d'accessibilité (`accessibility1` à `accessibility5`) : toujours en colonne.
    nonisolated public static func layout(for size: DynamicTypeSize) -> Layout {
        size.isAccessibilitySize ? .vertical : .horizontal
    }

    /// Aucune limite de lignes sur le montant serveur (il passe à la ligne, jamais « … »).
    nonisolated public static let montantLineLimit: Int? = nil

    private let content: Content
    private let isLoading: Bool
    private let isDisabled: Bool
    private let action: () -> Void

    public init(_ content: Content, isLoading: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.content = content; self.isLoading = isLoading; self.isDisabled = isDisabled; self.action = action
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        .frame(maxWidth: Self.maximumContentWidth)
        .padding(.horizontal, JoleneSpacing.lg)
        .padding(.vertical, JoleneSpacing.md)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(JoleneColor.rose100).frame(height: 1) }
        .shadow(color: JoleneColor.midnight.opacity(0.12), radius: 12, x: 0, y: -4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(content.identifier)
    }

    private var horizontal: some View {
        HStack(alignment: .center, spacing: JoleneSpacing.md) {
            // Priorité au montant : `ViewThatFits` a vérifié que le CTA tient dans le reste.
            summary.layoutPriority(1)
            Spacer(minLength: JoleneSpacing.sm)
            actionButton.frame(maxWidth: 200)
        }
    }

    private var vertical: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            summary.frame(maxWidth: .infinity, alignment: .leading)
            actionButton
        }
    }

    /// Montant + précision : un seul élément vocalisé, jamais tronqué.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.montant)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .lineLimit(Self.montantLineLimit)
                .fixedSize(horizontal: false, vertical: true)
            if let precision = content.precision {
                Text(precision)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(content.accessibilitySummary)
        .accessibilityIdentifier(content.montantIdentifier)
    }

    private var actionButton: some View {
        JoleneButton(content.actionTitle, style: .primary, isLoading: isLoading, action: action)
            .disabled(!Self.isActionEnabled(isLoading: isLoading, isDisabled: isDisabled))
            .accessibilityIdentifier(content.actionIdentifier)
    }
}

public extension View {
    /// Monte une `StickyActionBar` au-dessus du bord inférieur (`safeAreaInset`) : le contenu
    /// défilant n'est jamais masqué. `isPresented` reprend les conditions d'affichage de l'écran
    /// (web : mission ouverte, candidature possible, pas encore envoyée).
    func stickyActionBar(isPresented: Bool, _ content: StickyActionBar.Content, isLoading: Bool = false,
                         isDisabled: Bool = false, action: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if isPresented {
                StickyActionBar(content, isLoading: isLoading, isDisabled: isDisabled, action: action)
            }
        }
    }
}
