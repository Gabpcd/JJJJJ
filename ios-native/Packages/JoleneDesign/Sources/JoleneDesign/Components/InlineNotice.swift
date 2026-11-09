import SwiftUI
import UIKit

/// Encart d'information en ligne, port de `src/components/ui/alert.tsx` (`role="alert"`) avec
/// les tons de `BadgeY2K` (fond `-100`, encre `-800`/`-900`). Le ton est porté par l'icône et un
/// préfixe vocalisé, jamais par la couleur seule ; l'icône atteint 3:1 sur son fond (WCAG 1.4.11),
/// le texte 4,5:1, en clair comme en sombre. Le message serveur est affiché verbatim (PRINCIPES §3).
///
/// Annonce VoiceOver : `role="alert"` est lu à l'apparition sur le web, pas sur iOS. Un écran qui
/// affiche l'encart **après une action** (erreur serveur, refus, planning bloqué — via
/// `SlotList(…, announcesBlocked:)`) passe `announcesOnAppear: true` ; un encart présent dès le
/// chargement de l'écran reste lu dans l'ordre de lecture, sans annonce (pas de double lecture).
///
/// Une annonce est identifiée par son texte ET par `announcementID`, jeton fourni par l'écran
/// (ex. numéro de tentative) : une même erreur qui revient alors que l'encart reste affiché n'est
/// réannoncée que si l'écran change le jeton. Une clé déjà annoncée par cette vue ne l'est plus,
/// y compris quand l'encart réapparaît dans un conteneur paresseux (`List`, `LazyVStack`) tant que
/// SwiftUI conserve son identité ; un encart recréé avec une nouvelle identité (`.id(…)`) repart de zéro.
public struct InlineNotice: View {
    /// Annonce à émettre : texte vocalisé + jeton de l'appelant.
    public struct AnnouncementKey: Equatable, Sendable {
        public var text: String
        public var id: Int

        public init(text: String, id: Int) { self.text = text; self.id = id }
    }

    public enum Tone: CaseIterable, Sendable {
        case info, success, warning, error

        public var systemImage: String {
            switch self {
            case .info: return "info.circle"
            case .success: return "checkmark.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }

        public var accessibilityPrefix: String {
            switch self {
            case .info: return "Information"
            case .success: return "Succès"
            case .warning: return "Attention"
            case .error: return "Erreur"
            }
        }

        /// Encre de l'icône et de la bordure (`BadgeY2K` : mauve-800, cyan-900, butter-800 ; erreur rose-700).
        public var inkHSL: JoleneDynamicHSL {
            switch self {
            case .info: return JoleneColor.mauve800HSL
            case .success: return JoleneColor.cyan900HSL
            case .warning: return JoleneColor.butter800HSL
            case .error: return JoleneColor.rose700HSL
            }
        }

        /// Fond plein (`BadgeY2K` : `bg-jolene-*-100`).
        public var backgroundHSL: JoleneDynamicHSL {
            switch self {
            case .info: return JoleneColor.mauve100HSL
            case .success: return JoleneColor.cyan100HSL
            case .warning: return JoleneColor.butter100HSL
            case .error: return JoleneColor.rose100HSL
            }
        }

        var foreground: Color { Color(inkHSL) }
        var background: Color { Color(backgroundHSL) }
    }

    /// Libellé vocalisé : « Erreur : message » ou « Attention : titre. message ».
    nonisolated public static func accessibilityLabel(tone: Tone, title: String?, message: String) -> String {
        let corps = [title, message].compactMap { $0 }.joined(separator: ". ")
        return "\(tone.accessibilityPrefix) : \(corps)"
    }

    /// Texte annoncé à l'apparition (et à chaque changement de contenu), `nil` sans annonce demandée.
    nonisolated public static func announcement(tone: Tone, title: String?, message: String, announcesOnAppear: Bool) -> String? {
        announcesOnAppear ? accessibilityLabel(tone: tone, title: title, message: message) : nil
    }

    /// Clé d'annonce (texte + jeton), `nil` sans annonce demandée.
    nonisolated public static func announcementKey(tone: Tone, title: String?, message: String, announcesOnAppear: Bool,
                                                   announcementID: Int = 0) -> AnnouncementKey? {
        announcement(tone: tone, title: title, message: message, announcesOnAppear: announcesOnAppear)
            .map { AnnouncementKey(text: $0, id: announcementID) }
    }

    /// Annoncer `key`, sauf si cette vue l'a déjà annoncée (réapparition, recalcul du corps).
    nonisolated public static func shouldAnnounce(_ key: AnnouncementKey?, lastAnnounced: AnnouncementKey?) -> Bool {
        guard let key else { return false }
        return key != lastAnnounced
    }

    /// Délai avant l'annonce : laisse VoiceOver terminer le changement d'écran ou de focus.
    nonisolated static let announcementDelayNanoseconds: UInt64 = 300_000_000

    private let message: String
    private let title: String?
    private let tone: Tone
    private let identifier: String?
    private let announcesOnAppear: Bool
    private let announcementID: Int
    @State private var lastAnnounced: AnnouncementKey?

    /// - Parameter announcementID: jeton de l'écran ; le changer réannonce un même texte (nouvelle tentative).
    public init(_ message: String, title: String? = nil, tone: Tone = .info, identifier: String? = nil,
                announcesOnAppear: Bool = false, announcementID: Int = 0) {
        self.message = message; self.title = title; self.tone = tone; self.identifier = identifier
        self.announcesOnAppear = announcesOnAppear; self.announcementID = announcementID
    }

    public var body: some View {
        let cle = Self.announcementKey(tone: tone, title: title, message: message, announcesOnAppear: announcesOnAppear,
                                       announcementID: announcementID)
        HStack(alignment: .top, spacing: JoleneSpacing.sm) {
            Image(systemName: tone.systemImage)
                .font(JoleneFont.headline)
                .foregroundStyle(tone.foreground)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                if let title {
                    Text(title)
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                }
                Text(message)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.background)
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(tone.foreground.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityLabel(tone: tone, title: title, message: message))
        .accessibilityIdentifier(identifier ?? "")
        .task(id: cle) {
            // Relancée à chaque nouvelle clé et à chaque réapparition ; annulée si l'encart disparaît
            // avant le délai. Une clé déjà annoncée par cette vue est ignorée.
            guard Self.shouldAnnounce(cle, lastAnnounced: lastAnnounced), let cle else { return }
            try? await Task.sleep(nanoseconds: Self.announcementDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                UIAccessibility.post(notification: .announcement, argument: cle.text)
                lastAnnounced = cle
            }
        }
    }
}

/// Annonce VoiceOver d'un état qui apparaît après une action sans être un encart (`role="status"` du web : confirmation de
/// signature, relecture en cours ; lot 2, T9b, revue fraîche m8). Même règle qu'`InlineNotice(announcesOnAppear: true)` :
/// une clé (texte + jeton) annoncée une fois par vue, après `InlineNotice.announcementDelayNanoseconds`, annulée si la vue
/// disparaît avant ; `nil` ou un texte vide n'annoncent rien.
public struct AnnonceALApparition: ViewModifier {
    /// Clé d'annonce, `nil` sans texte (aucune annonce).
    nonisolated public static func cle(_ texte: String?, jeton: Int = 0) -> InlineNotice.AnnouncementKey? {
        guard let texte, !texte.isEmpty else { return nil }
        return InlineNotice.AnnouncementKey(text: texte, id: jeton)
    }

    private let cle: InlineNotice.AnnouncementKey?
    @State private var derniere: InlineNotice.AnnouncementKey?

    public init(_ texte: String?, jeton: Int = 0) {
        self.cle = Self.cle(texte, jeton: jeton)
    }

    public func body(content: Content) -> some View {
        content.task(id: cle) {
            guard InlineNotice.shouldAnnounce(cle, lastAnnounced: derniere), let cle else { return }
            try? await Task.sleep(nanoseconds: InlineNotice.announcementDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                UIAccessibility.post(notification: .announcement, argument: cle.text)
                derniere = cle
            }
        }
    }
}

public extension View {
    /// Annonce `texte` à VoiceOver à l'apparition de la vue (voir `AnnonceALApparition`).
    func annonceALApparition(_ texte: String?, jeton: Int = 0) -> some View {
        modifier(AnnonceALApparition(texte, jeton: jeton))
    }
}
