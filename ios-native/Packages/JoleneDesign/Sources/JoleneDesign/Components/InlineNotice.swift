import SwiftUI

/// Encart d'information en ligne, port de `src/components/ui/alert.tsx` (`role="alert"`) avec
/// les tons de `BadgeY2K`. Le ton est porté par l'icône et un préfixe vocalisé, jamais par la
/// couleur seule. Le message serveur est affiché verbatim (PRINCIPES §3).
public struct InlineNotice: View {
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

        var foreground: Color {
            switch self {
            case .info: return JoleneColor.mauve700
            case .success: return JoleneColor.cyan700
            case .warning: return JoleneColor.butter700
            case .error: return JoleneColor.rose700
            }
        }

        var background: Color {
            switch self {
            case .info: return JoleneColor.mauve100
            case .success: return JoleneColor.cyan.opacity(0.18)
            case .warning: return JoleneColor.butter100
            case .error: return JoleneColor.rose100
            }
        }
    }

    /// Libellé vocalisé : « Erreur : message » ou « Attention : titre. message ».
    nonisolated public static func accessibilityLabel(tone: Tone, title: String?, message: String) -> String {
        let corps = [title, message].compactMap { $0 }.joined(separator: ". ")
        return "\(tone.accessibilityPrefix) : \(corps)"
    }

    private let message: String
    private let title: String?
    private let tone: Tone
    private let identifier: String?

    public init(_ message: String, title: String? = nil, tone: Tone = .info, identifier: String? = nil) {
        self.message = message; self.title = title; self.tone = tone; self.identifier = identifier
    }

    public var body: some View {
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
    }
}
