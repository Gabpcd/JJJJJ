import SwiftUI

/// Écran bloquant plein écran : message serveur ou garde d'environnement, bouton
/// « Ouvrir jolene.app » (Safari) et action secondaire optionnelle (ex. déconnexion).
public struct BlockingScreen: View {
    public static let siteURL = URL(string: "https://jolene.app")!

    private let title: String
    private let message: String
    private let identifier: String
    private let secondary: (title: String, identifier: String, run: () -> Void)?

    public init(title: String, message: String, identifier: String,
                secondaryTitle: String? = nil, secondaryIdentifier: String = "", secondaryAction: (() -> Void)? = nil) {
        self.title = title; self.message = message; self.identifier = identifier
        if let secondaryTitle, let secondaryAction {
            self.secondary = (secondaryTitle, secondaryIdentifier, secondaryAction)
        } else { self.secondary = nil }
    }

    public var body: some View {
        ZStack {
            JoleneColor.softGradient.ignoresSafeArea()
            VStack(spacing: JoleneSpacing.xl) {
                Spacer()
                Image(systemName: "lock.shield")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(JoleneColor.heroGradient)
                    .accessibilityHidden(true)
                Text(title)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.midnight)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("\(identifier)-message")
                Spacer()
                Link(destination: Self.siteURL) {
                    Text("Ouvrir jolene.app")
                        .font(JoleneFont.button)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(JoleneButtonStyle(style: .primary))
                .accessibilityIdentifier("\(identifier)-open-web")
                if let secondary {
                    JoleneButton(secondary.title, style: .secondary, action: secondary.run)
                        .accessibilityIdentifier(secondary.identifier)
                }
            }
            .padding(JoleneSpacing.xl)
            .frame(maxWidth: 480)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
