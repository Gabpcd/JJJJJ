import SwiftUI

/// État vide / informatif, calqué sur `EmptyState` web : icône, titre, message, action optionnelle.
public struct EmptyState: View {
    private let systemImage: String
    private let title: String
    private let message: String
    private let identifier: String?
    private let action: (title: String, identifier: String, run: () -> Void)?

    public init(systemImage: String, title: String, message: String, identifier: String? = nil,
                actionTitle: String? = nil, actionIdentifier: String = "", action: (() -> Void)? = nil) {
        self.systemImage = systemImage; self.title = title; self.message = message; self.identifier = identifier
        if let actionTitle, let action { self.action = (actionTitle, actionIdentifier, action) } else { self.action = nil }
    }

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
            if let action {
                JoleneButton(action.title, style: .secondary, action: action.run)
                    .accessibilityIdentifier(action.identifier)
                    .frame(maxWidth: 320)
            }
        }
        .padding(JoleneSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "")
    }
}
