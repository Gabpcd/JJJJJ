import SwiftUI

/// État vide / informatif, calqué sur `EmptyState` web : icône, titre, message, jusqu'à deux
/// actions (lot 1, revue T4a : l'état vide d'Explorer garde « Actualiser » à côté de l'action
/// secondaire du web). Les actions sont empilées dans l'ordre reçu, même style secondaire.
public struct EmptyState: View {
    private typealias Action = (title: String, identifier: String, run: () -> Void)

    private let systemImage: String
    private let title: String
    private let message: String
    private let identifier: String?
    private let actions: [Action]

    /// Init du lot 0 : une action optionnelle.
    public init(systemImage: String, title: String, message: String, identifier: String? = nil,
                actionTitle: String? = nil, actionIdentifier: String = "", action: (() -> Void)? = nil) {
        self.systemImage = systemImage; self.title = title; self.message = message; self.identifier = identifier
        if let actionTitle, let action { self.actions = [(actionTitle, actionIdentifier, action)] } else { self.actions = [] }
    }

    /// Deux actions, toutes deux affichées : `action` d'abord, puis `secondaryAction`.
    public init(systemImage: String, title: String, message: String, identifier: String? = nil,
                actionTitle: String, actionIdentifier: String, action: @escaping () -> Void,
                secondaryActionTitle: String, secondaryActionIdentifier: String, secondaryAction: @escaping () -> Void) {
        self.systemImage = systemImage; self.title = title; self.message = message; self.identifier = identifier
        self.actions = [(actionTitle, actionIdentifier, action), (secondaryActionTitle, secondaryActionIdentifier, secondaryAction)]
    }

    /// Identifiants d'accessibilité des actions, dans l'ordre d'affichage.
    var actionIdentifiers: [String] { actions.map(\.identifier) }

    public var body: some View {
        VStack(spacing: JoleneSpacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(JoleneColor.heroGradient)
                .accessibilityHidden(true)
            Text(title)
                .font(JoleneFont.title)
                .foregroundStyle(JoleneColor.midnight)
                .multilineTextAlignment(.center)
            Text(message)
                .font(JoleneFont.body)
                .foregroundStyle(JoleneColor.bubblegum)
                .multilineTextAlignment(.center)
            if !actions.isEmpty {
                VStack(spacing: JoleneSpacing.md) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        JoleneButton(action.title, style: .secondary, action: action.run)
                            .accessibilityIdentifier(action.identifier)
                    }
                }
                .frame(maxWidth: 320)
            }
        }
        .padding(JoleneSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "")
    }
}
