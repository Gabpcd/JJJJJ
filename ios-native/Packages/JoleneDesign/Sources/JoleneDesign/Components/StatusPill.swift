import SwiftUI

/// Pastille de statut, port de `BadgeY2K` web (`src/components/y2k/BadgeY2K.tsx` : `rounded-full`, fond
/// `-100`, bordure, icône optionnelle masquée à VoiceOver, défauts `info` / `md`) pour les états de paiement,
/// d'escrow et de Stripe Connect du lot 3, et pour tout statut serveur ultérieur (lot 4 : à réutiliser, pas à
/// redéclarer). Le libellé arrive **verbatim** de l'appelant (cœur, ex. libellés de
/// `PaiementsEscrowAVenir.tsx`, HARD STOP n°4) : la pastille ne décide d'aucun état et ne normalise rien.
/// Le ton n'est jamais porté par la couleur seule : le libellé est toujours affiché et vocalisé.
///
/// Encres vérifiées par les tests : libellé ≥ 4,5:1 sur le fond du ton, icône ≥ 3:1, en clair et en sombre.
/// Écarts au web assumés :
/// - `warning` : libellé `midnight` (le `text-jolene-butter-800` de BadgeY2K ne fait que 4,09:1 sur
///   `butter-100` en clair) ; icône `butter-800` (≥ 3:1) ;
/// - `error` : rose (`rose-800`, icône `rose-700`), choix d'`InlineNotice`, au lieu du rouge `destructive` ;
/// - `neutral` (`text-muted-foreground bg-muted` de `PaiementsEscrowAVenir.tsx`) : `bubblegum` sur `lavender`.
public struct StatusPill: View {
    public enum Tone: CaseIterable, Sendable {
        case info, success, warning, error, neutral

        /// Encre du libellé (≥ 4,5:1 sur `backgroundHSL`).
        public var labelInkHSL: JoleneDynamicHSL {
            switch self {
            case .info: return JoleneColor.mauve800HSL
            case .success: return JoleneColor.cyan900HSL
            case .warning: return JoleneColor.midnightHSL
            case .error: return JoleneColor.rose800HSL
            case .neutral: return JoleneColor.bubblegumHSL
            }
        }

        /// Encre de l'icône et de la bordure (≥ 3:1 sur `backgroundHSL`), mêmes valeurs qu'`InlineNotice`.
        public var iconInkHSL: JoleneDynamicHSL {
            switch self {
            case .info: return JoleneColor.mauve800HSL
            case .success: return JoleneColor.cyan900HSL
            case .warning: return JoleneColor.butter800HSL
            case .error: return JoleneColor.rose700HSL
            case .neutral: return JoleneColor.bubblegumHSL
            }
        }

        /// Fond plein (`bg-jolene-*-100`).
        public var backgroundHSL: JoleneDynamicHSL {
            switch self {
            case .info: return JoleneColor.mauve100HSL
            case .success: return JoleneColor.cyan100HSL
            case .warning: return JoleneColor.butter100HSL
            case .error: return JoleneColor.rose100HSL
            case .neutral: return JoleneColor.lavenderHSL
            }
        }
    }

    /// `TAILLES` de BadgeY2K : `sm` = `text-[10px] px-2 py-0.5`, `md` = `text-xs px-2.5 py-1`.
    public enum Size: CaseIterable, Sendable {
        case sm, md

        public var horizontalPadding: CGFloat { self == .sm ? 8 : 10 }
        public var verticalPadding: CGFloat { self == .sm ? 2 : 4 }
        /// Styles Dynamic Type les plus proches des 10 px et 12 px du web.
        var font: Font { self == .sm ? Font.system(.caption2).weight(.medium) : JoleneFont.caption.weight(.medium) }
    }

    /// Partie calculable : libellé vocalisé (le texte reçu, tel quel) et identifiant.
    public struct Presentation: Equatable, Sendable {
        public var label: String
        public var identifier: String?

        public init(label: String, identifier: String?) { self.label = label; self.identifier = identifier }

        public var accessibilityLabel: String { label }
    }

    nonisolated public static let defaultTone: Tone = .info
    nonisolated public static let defaultSize: Size = .md

    private let presentation: Presentation
    private let tone: Tone
    private let systemImage: String?
    private let size: Size

    public init(_ label: String, tone: Tone = StatusPill.defaultTone, systemImage: String? = nil, size: Size = StatusPill.defaultSize,
                identifier: String? = nil) {
        self.presentation = Presentation(label: label, identifier: identifier)
        self.tone = tone; self.systemImage = systemImage; self.size = size
    }

    public var body: some View {
        HStack(spacing: JoleneSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(size.font)
                    .foregroundStyle(Color(tone.iconInkHSL))
                    .accessibilityHidden(true)
            }
            Text(presentation.label)
                .font(size.font)
                .foregroundStyle(Color(tone.labelInkHSL))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(Color(tone.backgroundHSL))
        .overlay(Capsule().strokeBorder(Color(tone.iconInkHSL).opacity(0.35), lineWidth: 1))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier(presentation.identifier ?? "")
    }
}
