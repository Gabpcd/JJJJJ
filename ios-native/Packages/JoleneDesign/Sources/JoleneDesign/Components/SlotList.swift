import Foundation
import SwiftUI
import JoleneCore

/// Liste de créneaux (détail mission, récapitulatif de candidature, confirmation de présence).
///
/// Reprend de `src/components/planning/PlanningMissionCandidat.tsx` la **structure** : encart
/// « Planning exact à confirmer », résumé « N créneaux · X h au total », limite et « + N autres
/// créneaux… », mention des jours non travaillés. Le **format des lignes** n'est PAS porté :
/// - variante créneaux (`init(slots:)`, `items(_:)`) : format du détail lot 0,
///   `MissionPresentation.creneau` (« Mardi 3 novembre · 08:00–12:00 ») ;
/// - le web affiche l'année, « 08h00 → 12h00 », la date de fin suivie de « (lendemain) » pour un
///   créneau qui passe minuit, et la durée « · X h » par créneau. Écart connu du format lot 0 : un
///   créneau 08:00 → 08:00 le lendemain s'y lit « 08:00–08:00 ».
///
/// Verrou de l'écart : la variante planning (`init(planning:libelle:)`, `Presentation.planning`)
/// exige le formateur de ligne, sans défaut. Le récapitulatif de candidature (T6b) y branche le
/// formateur web porté dans le cœur (T2/T6a, vecteurs golden) ; à défaut, il choisit
/// `MissionPresentation.creneau` en connaissance de cause. Le composant ne lit ni ne reformate
/// jamais une date lui-même.
///
/// Identifiants : conteneur `<identifier>`, lignes `<prefix>-creneau-<n>` (convention du lot 0,
/// `MissionDetailScreen` : `mission-detail-creneaux` / `mission-detail-creneau-1`), positionnels
/// (un `Item.id` fourni en double par l'appelant ne perturbe ni le rendu ni les identifiants) ;
/// pauses distinguées par l'icône ET le préfixe vocalisé.
public struct SlotList: View {
    public struct Item: Equatable, Sendable, Identifiable {
        public var id: String
        public var label: String
        public var isPause: Bool

        public init(id: String, label: String, isPause: Bool) {
            self.id = id; self.label = label; self.isPause = isPause
        }

        public var systemImage: String { isPause ? "cup.and.saucer" : "clock" }
        public var accessibilityLabel: String { "\(isPause ? "Pause" : "Créneau") : \(label)" }
    }

    /// Ce que la liste affiche, calculé hors de la vue (testable).
    public struct Presentation: Equatable, Sendable {
        /// Planning non exact : encart d'avertissement à la place des lignes (`role="alert"` web).
        public struct Blocked: Equatable, Sendable {
            public var title: String
            public var message: String

            public init(title: String, message: String) { self.title = title; self.message = message }
        }

        public var items: [Item]
        /// `limite` web (`slice(0, limite)`) ; `nil` = tout, une valeur négative vaut zéro.
        public var limit: Int?
        public var resume: String?
        public var footnote: String?
        public var blocked: Blocked?

        public init(items: [Item], limit: Int? = nil, resume: String? = nil, footnote: String? = nil, blocked: Blocked? = nil) {
            self.items = items; self.limit = limit; self.resume = resume; self.footnote = footnote; self.blocked = blocked
        }

        public var visibleItems: [Item] {
            guard let limit else { return items }
            return Array(items.prefix(max(0, limit)))
        }

        public var hiddenCount: Int { items.count - visibleItems.count }
        public var remainingText: String? { SlotList.remaining(hidden: hiddenCount) }
        /// Résumé réellement affiché : aucun sur une liste vide (le message vide suffit, sinon
        /// « Aucun créneau » puis « Aucun créneau communiqué. »).
        public var displayedResume: String? { items.isEmpty ? nil : resume }

        /// Structure de `PlanningMissionCandidat` : non exact → encart « Planning exact à confirmer » avec
        /// le message de blocage du cœur ; exact → résumé « N créneaux · X h au total », lignes, et mention
        /// des jours non travaillés quand la période s'étend sur plusieurs jours.
        /// - Parameter libelle: formateur de ligne, obligatoire (voir l'écart de format documenté sur `SlotList`).
        public static func planning(_ planning: PlanningCandidat, libelle: (MissionSlot) -> String, limit: Int? = nil,
                                    mentionJoursNonTravailles: Bool = true) -> Presentation {
            guard planning.exact else {
                let message = planning.messageBlocage ?? PlanningCandidatRules.messagePlanningIncomplet
                return Presentation(items: [], blocked: Blocked(title: SlotList.titrePlanningNonExact, message: message))
            }
            return Presentation(items: SlotList.items(planning.creneaux, libelle: libelle), limit: limit,
                                resume: SlotList.resume(count: planning.creneaux.count, totalHeures: planning.totalHeures),
                                footnote: mentionJoursNonTravailles && planning.periodeEtendue ? SlotList.mentionJoursNonTravailles : nil)
        }
    }

    /// Libellés verbatim de `PlanningMissionCandidat.tsx`.
    nonisolated public static let titrePlanningNonExact = "Planning exact à confirmer"
    nonisolated public static let mentionJoursNonTravailles = "Seuls les créneaux listés sont travaillés. Les autres jours de la période ne sont pas travaillés."

    /// Identifiant d'un créneau à partir de son index (base 1 comme le lot 0).
    nonisolated public static func identifier(prefix: String, index: Int) -> String { "\(prefix)-creneau-\(index + 1)" }

    /// Préfixe des lignes par défaut : l'identifiant du conteneur sans son suffixe « -creneaux »
    /// (`mission-detail-creneaux` → `mission-detail`), sinon l'identifiant tel quel.
    nonisolated public static func itemPrefix(for identifier: String) -> String {
        let suffixe = "-creneaux"
        guard identifier.hasSuffix(suffixe), identifier.count > suffixe.count else { return identifier }
        return String(identifier.dropLast(suffixe.count))
    }

    /// Résumé accordé : « Aucun créneau », « 1 créneau », « 3 créneaux ».
    nonisolated public static func resume(count: Int) -> String {
        switch count {
        case ..<1: return "Aucun créneau"
        case 1: return "1 créneau"
        default: return "\(count) créneaux"
        }
    }

    /// Résumé du planning exact : « 3 créneaux · 21 h au total ».
    nonisolated public static func resume(count: Int, totalHeures: Double) -> String {
        "\(resume(count: count)) · \(heures(totalHeures)) h au total"
    }

    /// `formatHeures` web : `toLocaleString('fr-FR', { maximumFractionDigits: 2 })` (virgule décimale,
    /// espace fine insécable U+202F pour les milliers, comme `MissionPresentation`). Affichage seul :
    /// le total vient de `PlanningCandidat.totalHeures`, jamais d'une heure facturée.
    nonisolated public static func heures(_ valeur: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.groupingSeparator = MissionPresentation.separateurMilliers
        formatter.decimalSeparator = ","
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: valeur)) ?? String(valeur)
    }

    /// « + 3 autres créneaux dans le récapitulatif complet », `nil` quand rien n'est masqué.
    nonisolated public static func remaining(hidden: Int) -> String? {
        guard hidden > 0 else { return nil }
        let pluriel = hidden > 1
        return "+ \(hidden) autre\(pluriel ? "s" : "") créneau\(pluriel ? "x" : "") dans le récapitulatif complet"
    }

    /// Conversion des créneaux serveur au format du détail lot 0 (`MissionPresentation.creneau`) ;
    /// l'identifiant est positionnel, donc stable même quand deux créneaux ont le même libellé ou
    /// aucun `id` serveur.
    nonisolated public static func items(_ slots: [MissionSlot]) -> [Item] {
        items(slots, libelle: MissionPresentation.creneau)
    }

    /// Conversion avec un formateur de ligne fourni par le cœur (aucun formatage de date ici).
    nonisolated public static func items(_ slots: [MissionSlot], libelle: (MissionSlot) -> String) -> [Item] {
        slots.enumerated().map { index, slot in
            Item(id: "creneau-\(index + 1)", label: libelle(slot), isPause: slot.estPause)
        }
    }

    private let presentation: Presentation
    private let identifier: String
    private let prefix: String
    private let emptyMessage: String

    /// - Parameter itemPrefix: préfixe des lignes ; par défaut `itemPrefix(for: identifier)`.
    public init(items: [Item], identifier: String, itemPrefix: String? = nil,
                emptyMessage: String = "Aucun créneau communiqué.", showsResume: Bool = false, limit: Int? = nil) {
        self.init(presentation: Presentation(items: items, limit: limit, resume: showsResume ? Self.resume(count: items.count) : nil),
                  identifier: identifier, itemPrefix: itemPrefix, emptyMessage: emptyMessage)
    }

    public init(slots: [MissionSlot], identifier: String, itemPrefix: String? = nil,
                emptyMessage: String = "Aucun créneau communiqué.", showsResume: Bool = false, limit: Int? = nil) {
        self.init(items: Self.items(slots), identifier: identifier, itemPrefix: itemPrefix,
                  emptyMessage: emptyMessage, showsResume: showsResume, limit: limit)
    }

    /// Planning candidat du cœur (récapitulatif de candidature, détail mission). `libelle` est
    /// obligatoire : voir l'écart de format documenté sur `SlotList`.
    public init(planning: PlanningCandidat, identifier: String, libelle: (MissionSlot) -> String,
                itemPrefix: String? = nil, limit: Int? = nil, mentionJoursNonTravailles: Bool = true) {
        self.init(presentation: .planning(planning, libelle: libelle, limit: limit,
                                          mentionJoursNonTravailles: mentionJoursNonTravailles),
                  identifier: identifier, itemPrefix: itemPrefix, emptyMessage: "Aucun créneau communiqué.")
    }

    public init(presentation: Presentation, identifier: String, itemPrefix: String? = nil,
                emptyMessage: String = "Aucun créneau communiqué.") {
        self.presentation = presentation; self.identifier = identifier
        self.prefix = itemPrefix ?? Self.itemPrefix(for: identifier); self.emptyMessage = emptyMessage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            if let blocked = presentation.blocked {
                InlineNotice(blocked.message, title: blocked.title, tone: .warning, identifier: "\(identifier)-bloque")
            } else {
                if let resume = presentation.displayedResume {
                    Text(resume)
                        .font(JoleneFont.caption.weight(.semibold))
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityIdentifier("\(identifier)-resume")
                }
                if presentation.items.isEmpty {
                    Text(emptyMessage)
                        .font(JoleneFont.body)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .accessibilityIdentifier("\(identifier)-empty")
                } else {
                    // Identité positionnelle, comme les identifiants : un `Item.id` en double ne casse pas le ForEach.
                    ForEach(Array(presentation.visibleItems.enumerated()), id: \.offset) { index, item in
                        row(item, index: index)
                    }
                }
                if let remaining = presentation.remainingText {
                    Text(remaining)
                        .font(JoleneFont.caption.weight(.medium))
                        .foregroundStyle(JoleneColor.rose700)
                        .accessibilityIdentifier("\(identifier)-reste")
                }
                if let footnote = presentation.footnote {
                    Text(footnote)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("\(identifier)-mention")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func row(_ item: Item, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
            Image(systemName: item.systemImage)
                .foregroundStyle(item.isPause ? JoleneColor.bubblegum : JoleneColor.mauve700)
                .accessibilityHidden(true)
            Text(item.label)
                .font(JoleneFont.body)
                .foregroundStyle(item.isPause ? JoleneColor.bubblegum : JoleneColor.midnight)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityIdentifier(Self.identifier(prefix: prefix, index: index))
    }
}
