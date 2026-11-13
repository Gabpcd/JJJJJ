import SwiftUI

/// Pastille de statut (lot 2 T7 : justificatifs ; T9a : contrats), port de `BadgeY2K` (`size="sm"`) et des `badge-base`
/// de `DocumentsSoignant.tsx`. Le texte est celui de l'écran, jamais une valeur stockée ; le ton est porté par une icône
/// et la bordure, jamais par la couleur seule. Encre `midnight` sur les fonds de `InlineNotice.Tone` (≥ 4,5:1 en clair et
/// en sombre, prouvé par les tests de `InlineNotice`) ; neutre : surface `cloud`. Une vérification en cours ajoute un
/// indicateur animé (`progressIdentifier`), coupé avec « Réduire les animations » (indicateur système).
public struct StatusBadge: View {
    public enum Tone: CaseIterable, Sendable {
        case success, warning, error, info, neutral

        /// Ton d'encart correspondant (couleurs vérifiées) ; nil pour le neutre.
        public var noticeTone: InlineNotice.Tone? {
            switch self {
            case .success: return .success
            case .warning: return .warning
            case .error: return .error
            case .info: return .info
            case .neutral: return nil
            }
        }

        public var systemImage: String {
            noticeTone?.systemImage ?? "minus.circle"
        }

        /// Fond plein : celui de l'encart du même ton, `cloud` pour le neutre.
        public var backgroundHSL: JoleneDynamicHSL {
            noticeTone?.backgroundHSL ?? JoleneColor.cloudHSL
        }

        /// Icône et bordure : encre de l'encart du même ton, `bubblegum` pour le neutre.
        public var inkHSL: JoleneDynamicHSL {
            noticeTone?.inkHSL ?? JoleneColor.bubblegumHSL
        }
    }

    /// Encre du texte, sur chaque fond (4,5:1).
    nonisolated public static let textInkHSL = JoleneColor.midnightHSL

    private let text: String
    private let tone: Tone
    private let isInProgress: Bool
    private let identifier: String?
    private let progressIdentifier: String?

    public init(_ text: String, tone: Tone, isInProgress: Bool = false, identifier: String? = nil, progressIdentifier: String? = nil) {
        self.text = text; self.tone = tone; self.isInProgress = isInProgress
        self.identifier = identifier; self.progressIdentifier = progressIdentifier
    }

    public var body: some View {
        HStack(spacing: JoleneSpacing.xs) {
            if isInProgress {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Color(tone.inkHSL))
                    .accessibilityIdentifier(progressIdentifier ?? "")
            } else {
                Image(systemName: tone.systemImage)
                    .font(JoleneFont.caption)
                    .foregroundStyle(Color(tone.inkHSL))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(Color(Self.textInkHSL))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier ?? "")
        }
        .padding(.horizontal, JoleneSpacing.sm)
        .padding(.vertical, JoleneSpacing.xs)
        .background(Color(tone.backgroundHSL))
        .overlay(Capsule().strokeBorder(Color(tone.inkHSL).opacity(0.35), lineWidth: 1))
        .clipShape(Capsule())
    }
}
