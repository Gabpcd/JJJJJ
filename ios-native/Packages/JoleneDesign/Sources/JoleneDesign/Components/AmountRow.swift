import SwiftUI

/// Ligne de montant, port de la colonne « montant + état » des missions de `src/pages/MesGains.tsx`
/// (l.736-751) : montant en `text-primary font-bold`, préfixé « ~ » quand il est approximatif (l.748),
/// tiret sans montant, libellé de nature dessous (« Net salarié estimé* », « Honoraires prévisionnels du
/// planning », `missionFinanceDisplay.ts`), lignes secondaires (« brut : … »). Les chaînes arrivent **déjà
/// formatées par le cœur** (`MontantMission`, golden T2) : valeurs serveur, jamais recalculées ni arrondies
/// ici (PRINCIPES §3) ; libellés et note de bas de page verbatim web (HARD STOP n°4, note « net estimé »).
///
/// Vocalisation : un seul élément ; « ~ » lu « environ », astérisque final du libellé de nature retiré
/// (VoiceOver lirait « tilde », « astérisque »), note de bas de page (texte fourni par l'écran) lue en indice
/// avec la même règle (`spokenText` : marques « * » de tête et de fin retirées, « ~ » lu « environ »). Seule
/// la vocalisation change : le texte affiché reste verbatim. Textes vocalisés sans équivalent web
/// (« environ », « Montant indisponible ») tranchés par délégation dans `DECISIONS_LOT3.md` (« Décisions déléguées
/// du 8 novembre 2026 », TJ5).
/// Le montant n'est jamais tronqué : en ligne quand tout tient (`ViewThatFits`), sinon (et toujours aux
/// tailles d'accessibilité) en colonne. Posée sur une carte ou un écran (texte secondaire `bubblegum`).
public struct AmountRow: View {
    public enum Layout: Equatable, Sendable { case horizontal, vertical }

    public struct Content: Equatable, Sendable {
        public var title: String
        public var subtitle: String?
        /// Montant formaté par le cœur (« 1 234,56 € »), `nil` si le serveur n'en fournit pas.
        public var montant: String?
        /// `MontantMissionAffiche.approximatif` : préfixe « ~ ».
        public var approximatif: Bool
        /// Libellé de nature verbatim (peut finir par l'astérisque d'une note).
        public var nature: String?
        public var details: [String]
        /// Note de bas de page verbatim (ex. « * Net salarié estimé après cotisations salariales (~22 %). »).
        public var footnote: String?
        public var identifier: String

        public init(title: String, subtitle: String? = nil, montant: String?, approximatif: Bool, nature: String? = nil,
                    details: [String] = [], footnote: String? = nil, identifier: String) {
            self.title = title; self.subtitle = subtitle; self.montant = montant; self.approximatif = approximatif
            self.nature = nature; self.details = details; self.footnote = footnote; self.identifier = identifier
        }

        private var montantServeur: String? {
            guard let montant, !montant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return montant
        }

        /// `${finance.approximatif ? '~' : ''}${fmt(finance.montant)}`, `'—'` sans montant.
        public var displayedAmount: String {
            guard let montant = montantServeur else { return AmountRow.unavailableAmount }
            return approximatif ? AmountRow.approximatePrefix + montant : montant
        }

        public var spokenAmount: String {
            guard let montant = montantServeur else { return "Montant indisponible" }
            return approximatif ? "environ \(montant)" : montant
        }

        public var hasFootnoteMarker: Bool {
            nature?.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("*") ?? false
        }

        /// Libellé de nature vocalisé (`spokenText` : sans l'astérisque de note) ; `nil` s'il ne reste rien.
        public var spokenNature: String? { AmountRow.spokenText(nature) }

        public var accessibilityLabel: String {
            ([title, subtitle, spokenAmount, spokenNature].compactMap { $0 } + details).joined(separator: ", ")
        }

        /// Note de bas de page vocalisée sans « * » ni « ~ » (affichée verbatim).
        public var accessibilityHint: String? { AmountRow.spokenText(footnote) }
    }

    /// Texte à vocaliser : marques de note « * » de tête et de fin retirées, « ~ » lu « environ » ; `nil` s'il
    /// ne reste rien. N'agit que sur la vocalisation, jamais sur le texte affiché.
    nonisolated public static func spokenText(_ texte: String?) -> String? {
        guard var sortie = texte?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        while sortie.hasPrefix("*") || sortie.hasSuffix("*") {
            if sortie.hasPrefix("*") { sortie.removeFirst() }
            if sortie.hasSuffix("*") { sortie.removeLast() }
            sortie = sortie.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        sortie = sortie.replacingOccurrences(of: #"~\s*"#, with: "environ ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sortie.isEmpty ? nil : sortie
    }

    nonisolated public static let approximatePrefix = "~"
    nonisolated public static let unavailableAmount = "—"
    /// `text-primary` : rose-800, ≥ 4,5:1 sur carte, écran et softGradient (rose-700 tombe à 3,54:1).
    nonisolated public static let amountInkHSL = JoleneColor.rose800HSL
    nonisolated public static let titleInkHSL = JoleneColor.midnightHSL
    nonisolated public static let secondaryInkHSL = JoleneColor.bubblegumHSL
    /// Aucune limite de lignes sur le montant serveur (il passe à la ligne, jamais « … »).
    nonisolated public static let amountLineLimit: Int? = nil

    /// Tailles d'accessibilité : toujours en colonne.
    nonisolated public static func layout(for size: DynamicTypeSize) -> Layout { size.isAccessibilitySize ? .vertical : .horizontal }

    private let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ content: Content) { self.content = content }

    public var body: some View {
        Group {
            switch Self.layout(for: dynamicTypeSize) {
            case .vertical:
                vertical
            case .horizontal:
                ViewThatFits(in: .horizontal) {
                    horizontal
                    vertical
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityHint(content.accessibilityHint ?? "")
        .accessibilityIdentifier(content.identifier)
    }

    private var horizontal: some View {
        HStack(alignment: .top, spacing: JoleneSpacing.md) {
            heading.layoutPriority(1)
            Spacer(minLength: JoleneSpacing.sm)
            amount(alignment: .trailing)
        }
    }

    private var vertical: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            heading
            amount(alignment: .leading)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.title)
                .font(JoleneFont.callout.weight(.medium))
                .foregroundStyle(Color(Self.titleInkHSL))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = content.subtitle {
                Text(subtitle)
                    .font(JoleneFont.caption)
                    .foregroundStyle(Color(Self.secondaryInkHSL))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func amount(alignment: HorizontalAlignment) -> some View {
        let texte: TextAlignment = alignment == .trailing ? .trailing : .leading
        return VStack(alignment: alignment, spacing: 2) {
            Text(content.displayedAmount)
                .font(JoleneFont.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color(Self.amountInkHSL))
                .lineLimit(Self.amountLineLimit)
                .multilineTextAlignment(texte)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(([content.nature].compactMap { $0 } + content.details).enumerated()), id: \.offset) { _, ligne in
                Text(ligne)
                    .font(JoleneFont.caption)
                    .foregroundStyle(Color(Self.secondaryInkHSL))
                    .multilineTextAlignment(texte)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
