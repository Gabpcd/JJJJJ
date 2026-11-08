import SwiftUI

/// Écran bloquant plein écran : message serveur ou garde d'environnement, bouton
/// « Ouvrir jolene.app » (Safari) et action secondaire optionnelle (ex. déconnexion). Lot 3, T4 :
/// `secondaryIsLoading` montre l'attente sur l'action secondaire et la désactive (déconnexion jusqu'à 2,5 s
/// de désactivation du token : pas de second tap).
public struct BlockingScreen: View {
    public static let siteURL = URL(string: "https://jolene.app")!

    /// Action secondaire bloquée pendant l'appel en cours (pas de double envoi).
    nonisolated public static func isSecondaryEnabled(isLoading: Bool) -> Bool { !isLoading }

    private let title: String
    private let message: String
    private let identifier: String
    private let secondary: (title: String, identifier: String, run: () -> Void)?
    private let secondaryIsLoading: Bool

    public init(title: String, message: String, identifier: String,
                secondaryTitle: String? = nil, secondaryIdentifier: String = "", secondaryAction: (() -> Void)? = nil,
                secondaryIsLoading: Bool = false) {
        self.title = title; self.message = message; self.identifier = identifier
        self.secondaryIsLoading = secondaryIsLoading
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
                    JoleneButton(secondary.title, style: .secondary, isLoading: secondaryIsLoading) {
                        guard Self.isSecondaryEnabled(isLoading: secondaryIsLoading) else { return }
                        secondary.run()
                    }
                    .disabled(!Self.isSecondaryEnabled(isLoading: secondaryIsLoading))
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
