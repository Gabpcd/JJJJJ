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
/// - `neutral` (`text-muted-foreground bg-muted` de `PaiementsEscrowAVenir.tsx`) : `bubblegum` sur `lavender` ;
/// - retour à la ligne : BadgeY2K reste sur une ligne (`whitespace-nowrap`, `rounded-full`). Le natif ne
///   tronque jamais un libellé serveur : capsule tant qu'il tient sur une ligne (`ViewThatFits`), sinon
///   passage à la ligne dans un rectangle arrondi à rayon fixe (`multilineCornerRadius`, ≤ marge horizontale) —
///   une capsule, dont le rayon vaut la demi-hauteur, rognerait les lettres des lignes extrêmes aux tailles
///   d'accessibilité.
///
/// Doublon connu : `JoleneBadge` (`MissionCard.swift`, lot 0/1) est un premier port de BadgeY2K, à quatre tons
/// et encres `-700` (`cyan700`, `butter700`, sous AA en clair : mineur 5 de la revue du lot 1). Deux pastilles
/// d'état coexistent donc, avec des contrastes différents. Plan de convergence : `JoleneBadge` délègue à
/// `StatusPill` (`success`/`warning`/`error`/`info` → mêmes tons, taille `md`), call sites inchangés, dans une
/// tranche qui a `MissionCard.swift` et ses tests dans son périmètre ; d'ici là, tout nouveau statut utilise
/// `StatusPill`.
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

    /// Contour de la pastille selon le nombre de lignes du libellé.
    public enum Outline: Equatable, Sendable {
        case capsule
        case rounded(cornerRadius: CGFloat)
    }

    /// Rayon des coins quand le libellé passe à la ligne. Un coin de rayon r ne découpe que la zone à moins de
    /// r des deux bords : r ≤ la plus petite marge horizontale (`sm`, 8 pt), aucun glyphe n'est rogné.
    nonisolated public static let multilineCornerRadius: CGFloat = 8

    nonisolated public static func outline(isMultiline: Bool) -> Outline {
        isMultiline ? .rounded(cornerRadius: multilineCornerRadius) : .capsule
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
        // Une ligne si elle tient (capsule), sinon passage à la ligne (rectangle arrondi) : jamais de « … ».
        ViewThatFits(in: .horizontal) {
            pill(isMultiline: false)
            pill(isMultiline: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier(presentation.identifier ?? "")
    }

    @ViewBuilder
    private func pill(isMultiline: Bool) -> some View {
        switch Self.outline(isMultiline: isMultiline) {
        case .capsule:
            contenu(isMultiline: isMultiline)
                .overlay(Capsule().strokeBorder(Color(tone.iconInkHSL).opacity(0.35), lineWidth: 1))
                .clipShape(Capsule())
        case .rounded(let rayon):
            contenu(isMultiline: isMultiline)
                .overlay(RoundedRectangle(cornerRadius: rayon).strokeBorder(Color(tone.iconInkHSL).opacity(0.35), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: rayon))
        }
    }

    private func contenu(isMultiline: Bool) -> some View {
        HStack(alignment: isMultiline ? .firstTextBaseline : .center, spacing: JoleneSpacing.xs) {
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
                .lineLimit(isMultiline ? nil : 1)
                .fixedSize(horizontal: !isMultiline, vertical: true)
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(Color(tone.backgroundHSL))
    }
}
