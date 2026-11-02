import SwiftUI

/// En-tête de section (Accueil, Mes missions) : titre + action secondaire optionnelle
/// (« Tout voir »). Identifiants `<identifier>-title` et `<identifier>-action`.
public struct SectionHeader: View {
    nonisolated public static func titleIdentifier(for identifier: String) -> String { "\(identifier)-title" }
    nonisolated public static func actionIdentifier(for identifier: String) -> String { "\(identifier)-action" }

    private let title: String
    private let identifier: String
    private let action: (title: String, run: () -> Void)?

    public init(_ title: String, identifier: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title; self.identifier = identifier
        if let actionTitle, let action { self.action = (actionTitle, action) } else { self.action = nil }
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
            Text(title)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(Self.titleIdentifier(for: identifier))
            Spacer(minLength: 0)
            if let action {
                Button(action.title, action: action.run)
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.rose700)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(Self.actionIdentifier(for: identifier))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
