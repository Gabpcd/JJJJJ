import Foundation
import SwiftUI

/// Carte de renvoi vers jolene.app (lot 4 : écrans en « renvoi web assumé », `RenvoiWebScreen` de T1c, décision
/// D17 : `SFSafariViewController`, aucun jeton transmis). Titre, message et action sont fournis par l'écran ; la
/// carte affiche l'adresse ouverte (`jolene.app/…`, sans schéma ni fragment) pour que l'utilisateur sache où il
/// va, et ne présente rien elle-même : `action` appelle le présentateur Safari de l'app.
///
/// Aucun texte juridique ici (HARD STOP n°4) : le motif d'un renvoi (mandat, avances, etc.) reste sur le web.
/// Le libellé d'action passe à la ligne aux grandes tailles, jamais tronqué (bouton `JoleneButton`, mesuré).
public struct WebHandoffCard: View {
    /// Identifiants dérivés : `<id>-title`, `-message`, `-url`, `-action` (ou identifiant d'action imposé).
    public struct Identifiers: Equatable, Sendable {
        public var container: String
        private var customAction: String?

        public init(identifier: String, actionIdentifier: String? = nil) {
            self.container = identifier; self.customAction = actionIdentifier
        }

        public var title: String { "\(container)-title" }
        public var message: String { "\(container)-message" }
        public var url: String { "\(container)-url" }
        public var action: String { customAction ?? "\(container)-action" }
    }

    nonisolated public static let defaultActionTitle = "Ouvrir sur jolene.app"
    nonisolated public static let defaultSystemImage = "safari"
    nonisolated public static let actionHint = "Ouvre la page sur jolene.app"
    /// Aucune limite de lignes sur le libellé d'action.
    nonisolated public static let actionLineLimit: Int? = nil
    nonisolated public static let titleInkHSL = JoleneColor.midnightHSL
    nonisolated public static let messageInkHSL = JoleneColor.bubblegumHSL
    nonisolated public static let urlInkHSL = JoleneColor.bubblegumHSL
    nonisolated public static let iconInkHSL = JoleneColor.rose800HSL

    /// « jolene.app/soignant/premium », « jolene.app/soignant/mes-gains?tab=avances », « jolene.app » : hôte, chemin
    /// et requête, sans schéma ni fragment ; l'adresse complète si elle n'a pas d'hôte.
    nonisolated public static func displayURL(_ url: URL) -> String {
        guard let composants = URLComponents(url: url, resolvingAgainstBaseURL: false), let hote = composants.host,
              !hote.isEmpty else { return url.absoluteString }
        let chemin = composants.path == "/" ? "" : composants.path
        let requete = composants.query.map { "?\($0)" } ?? ""
        return hote + chemin + requete
    }

    private let title: String
    private let message: String
    private let url: URL
    private let actionTitle: String
    private let systemImage: String
    private let identifiers: Identifiers
    private let action: () -> Void

    public init(title: String, message: String, url: URL, actionTitle: String = WebHandoffCard.defaultActionTitle,
                systemImage: String = WebHandoffCard.defaultSystemImage, identifier: String, actionIdentifier: String? = nil,
                action: @escaping () -> Void) {
        self.title = title; self.message = message; self.url = url; self.actionTitle = actionTitle
        self.systemImage = systemImage; self.identifiers = Identifiers(identifier: identifier, actionIdentifier: actionIdentifier)
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            Image(systemName: systemImage)
                .font(JoleneFont.title)
                .foregroundStyle(Color(Self.iconInkHSL))
                .accessibilityHidden(true)
            Text(title)
                .font(JoleneFont.headline)
                .foregroundStyle(Color(Self.titleInkHSL))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifiers.title)
            Text(message)
                .font(JoleneFont.callout)
                .foregroundStyle(Color(Self.messageInkHSL))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifiers.message)
            Text(Self.displayURL(url))
                .font(JoleneFont.caption.monospaced())
                .foregroundStyle(Color(Self.urlInkHSL))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifiers.url)
            JoleneButton(actionTitle, style: .primary, action: action)
                .lineLimit(Self.actionLineLimit)
                .multilineTextAlignment(.center)
                .accessibilityHint(Self.actionHint)
                .accessibilityIdentifier(identifiers.action)
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.card).strokeBorder(JoleneColor.rose100, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifiers.container)
    }
}
