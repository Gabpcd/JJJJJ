import SwiftUI

/// Pastille du score de matching d'une mission, port du `BadgeY2K` de `src/components/swipe/CardMissionSwipe.tsx`
/// (`{mission.score}/100`, `variant={scoreEleve ? 'premium' : 'info'}`, icône `Sparkles`, taille `md`) et de
/// `ModalDetailMissionSwipe.tsx` (`Match {mission.score}/100`, taille `sm`). Le score est la **valeur serveur**
/// (`Int?`, correction 13 du lot 4) : sans score, aucune pastille (jamais un « 0/100 » fabriqué, comme
/// `MissionScore.test.tsx`) ; un vrai 0 reste affiché. `premium` (≥ 80) : `.bg-gradient-celebrate` et encre
/// `#2B183D` (règle CSS du web, déclarée hors couche : elle l'emporte sur `text-white`), `info` : couleurs de
/// `StatusPill` info (mauve-800 sur mauve-100). VoiceOver : « Score 85 sur 100 » / « Match 85 sur 100 ».
public struct ScoreBadge: View {
    public enum Style: CaseIterable, Sendable { case carte, detail }

    /// `scoreEleve = mission.score >= 80`.
    nonisolated public static let seuilEleve = 80
    nonisolated public static let systemImage = "sparkles"
    nonisolated public static let premiumStops = JoleneColor.celebrateGradientStops
    nonisolated public static let premiumInkHex = JoleneColor.onGradientHex
    nonisolated public static let infoTone: StatusPill.Tone = .info

    nonisolated public static func estEleve(_ score: Int) -> Bool { score >= seuilEleve }

    /// « 85/100 » (carte) ou « Match 85/100 » (détail) ; `nil` sans score.
    nonisolated public static func texte(_ score: Int?, style: Style) -> String? {
        guard let score else { return nil }
        return style == .carte ? "\(score)/100" : "Match \(score)/100"
    }

    /// « Score 85 sur 100 » ou « Match 85 sur 100 » (fragment `score ${mission.score} sur 100` du web) ; `nil` sans score.
    nonisolated public static func accessibilityLabel(_ score: Int?, style: Style) -> String? {
        guard let score else { return nil }
        return style == .carte ? "Score \(score) sur 100" : "Match \(score) sur 100"
    }

    private let score: Int?
    private let style: Style
    private let identifier: String?

    public init(score: Int?, style: Style = .carte, identifier: String? = nil) {
        self.score = score; self.style = style; self.identifier = identifier
    }

    public var body: some View {
        if let score, let texte = Self.texte(score, style: style) {
            let eleve = Self.estEleve(score)
            let taille = style == .carte ? StatusPill.Size.md : StatusPill.Size.sm
            HStack(spacing: JoleneSpacing.xs) {
                Image(systemName: Self.systemImage)
                    .accessibilityHidden(true)
                Text(texte)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(style == .carte ? JoleneFont.caption.weight(eleve ? .semibold : .medium)
                                  : Font.system(.caption2).weight(eleve ? .semibold : .medium))
            .foregroundStyle(eleve ? JoleneColor.onGradient : Color(Self.infoTone.labelInkHSL))
            .padding(.horizontal, taille.horizontalPadding)
            .padding(.vertical, taille.verticalPadding)
            .background(fond(eleve: eleve))
            .overlay(Capsule().strokeBorder(eleve ? Color.white.opacity(0.3) : Color(Self.infoTone.iconInkHSL).opacity(0.35),
                                            lineWidth: 1))
            .clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityLabel(score, style: style) ?? texte)
            .accessibilityIdentifier(identifier ?? "")
        }
    }

    @ViewBuilder private func fond(eleve: Bool) -> some View {
        if eleve { JoleneColor.celebrateGradient } else { Color(Self.infoTone.backgroundHSL) }
    }
}
