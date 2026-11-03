import SwiftUI

/// Une semaine de la grille des disponibilités, port de `src/pages/MesDisponibilites.tsx` (l.147-203) : en-tête
/// « Semaine du … », sept lignes (jour + « aujourd'hui »), deux bascules par jour, « Jour » (`JOURNEE`, soleil) et
/// « Nuit » (`NUIT`, lune). Jours passés atténués et désactivés (`disabled={passe}`, `opacity-40`) ; pendant l'appel
/// de `fn_definir_disponibilite`, seul le créneau concerné est bloqué (`enCours.has(cle)`), avec un indicateur.
///
/// État dérivé (CLAUDE.md) : les jours, leurs libellés, `isToday` et `isPast` arrivent calculés par le cœur
/// (lot 4 T2, `SemainesDisponibilites`, lundi Europe/Paris) et l'état déclaré vient du serveur ; la grille ne
/// calcule aucune date et ne pré-remplit rien. L'écran (T5) empile les quatre semaines et affiche le compteur.
///
/// Accessibilité : chaque bascule est vocalisée « <jour>, <créneau> » avec le trait « sélectionné » ; un créneau
/// déclaré passe aussi à l'icône pleine (l'état ne repose pas sur la seule couleur). Cibles de 44 pt (36 px sur
/// le web). Aux tailles Dynamic Type d'accessibilité, libellé au-dessus et bascules dessous (repli en colonne
/// si elles ne tiennent pas côte à côte), jamais tronqués.
public struct AvailabilityWeekGrid: View {
    public enum Creneau: String, CaseIterable, Sendable {
        case journee = "JOURNEE", nuit = "NUIT"

        /// Libellés verbatim des boutons du web (`<Sun … />Jour`, `<Moon … />Nuit`).
        public var label: String { self == .journee ? "Jour" : "Nuit" }

        public func systemImage(isSelected: Bool) -> String {
            switch self {
            case .journee: return isSelected ? "sun.max.fill" : "sun.max"
            case .nuit: return isSelected ? "moon.fill" : "moon"
            }
        }

        /// Fond d'un créneau déclaré : Jour = dégradé hero (`bg-primary` rose du web), Nuit = `midnight`
        /// (`bg-jolene-midnight`, qui s'éclaircit en sombre).
        public var selectedFillHSL: [JoleneDynamicHSL] {
            self == .journee ? JoleneColor.heroGradientStops : [JoleneColor.midnightHSL]
        }

        /// Encre d'un créneau déclaré ; `nil` = encre fixe `onGradient` du dégradé.
        public var selectedInkHSL: JoleneDynamicHSL? { self == .journee ? nil : JoleneColor.cloudHSL }

        var identifierSuffix: String { rawValue.lowercased() }
    }

    public struct SlotState: Equatable, Sendable {
        public var isAvailable: Bool
        public var isPending: Bool

        public init(isAvailable: Bool = false, isPending: Bool = false) {
            self.isAvailable = isAvailable; self.isPending = isPending
        }
    }

    public struct Day: Identifiable, Equatable, Sendable {
        /// Jour `yyyy-MM-dd` (clé serveur `p_jour`).
        public var id: String
        /// Libellé déjà formaté par le cœur (ex. « Lundi 2 Nov. »).
        public var label: String
        public var isToday: Bool
        public var isPast: Bool
        public var journee: SlotState
        public var nuit: SlotState

        public init(id: String, label: String, isToday: Bool = false, isPast: Bool = false, journee: SlotState = .init(),
                    nuit: SlotState = .init()) {
            self.id = id; self.label = label; self.isToday = isToday; self.isPast = isPast
            self.journee = journee; self.nuit = nuit
        }

        public func state(_ creneau: Creneau) -> SlotState { creneau == .journee ? journee : nuit }
    }

    public enum Layout: Equatable, Sendable { case horizontal, vertical }

    nonisolated public static let todayText = "aujourd'hui"
    nonisolated public static let minimumTapTarget: CGFloat = 44
    nonisolated public static let pastOpacity: Double = 0.4
    nonisolated public static let unselectedInkHSL = JoleneColor.bubblegumHSL
    nonisolated public static let dayLabelInkHSL = JoleneColor.midnightHSL
    /// « aujourd'hui » : `text-primary` du web, rendu en rose-800 (AA sur la carte).
    nonisolated public static let todayInkHSL = JoleneColor.rose800HSL

    /// Bascule active hors jour passé et hors appel en cours sur ce créneau.
    nonisolated public static func isToggleEnabled(_ state: SlotState, isPast: Bool) -> Bool { !isPast && !state.isPending }

    nonisolated public static func identifier(prefix: String, dayID: String, creneau: Creneau) -> String {
        "\(prefix)-\(dayID)-\(creneau.identifierSuffix)"
    }

    nonisolated public static func rowIdentifier(prefix: String, dayID: String) -> String { "\(prefix)-\(dayID)" }
    nonisolated public static func titleIdentifier(prefix: String) -> String { "\(prefix)-title" }

    nonisolated public static func accessibilityLabel(day: Day, creneau: Creneau) -> String {
        "\(day.label)\(day.isToday ? ", \(todayText)" : ""), \(creneau.label)"
    }

    /// Compteur du web sans sa phrase de fin : « 1 créneau déclaré. », « 3 créneaux déclarés. », rien à zéro.
    nonisolated public static func resume(count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 1 ? "\(count) créneaux déclarés." : "\(count) créneau déclaré."
    }

    /// Tailles d'accessibilité : toujours en colonne ; sinon en ligne si tout tient (`ViewThatFits`).
    nonisolated public static func layout(for size: DynamicTypeSize) -> Layout { size.isAccessibilitySize ? .vertical : .horizontal }

    private let title: String
    private let days: [Day]
    private let identifier: String
    private let layoutOverride: Layout?
    private let onToggle: (Day, Creneau) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(title: String, days: [Day], identifier: String, onToggle: @escaping (Day, Creneau) -> Void) {
        self.init(title: title, days: days, identifier: identifier, layoutOverride: nil, onToggle: onToggle)
    }

    /// Disposition imposée, sans `ViewThatFits` : réservé aux tests (mesure de la bascule).
    init(title: String, days: [Day], identifier: String, layoutOverride: Layout?, onToggle: @escaping (Day, Creneau) -> Void) {
        self.title = title; self.days = days; self.identifier = identifier
        self.layoutOverride = layoutOverride; self.onToggle = onToggle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(Color(Self.unselectedInkHSL))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, JoleneSpacing.md)
                .padding(.vertical, JoleneSpacing.sm)
                .background(JoleneColor.lavender)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(Self.titleIdentifier(prefix: identifier))
            ForEach(days) { day in
                if day.id != days.first?.id { Divider() }
                ligne(day)
            }
        }
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.card).strokeBorder(JoleneColor.rose100, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private func ligne(_ day: Day) -> some View {
        Group {
            if let layoutOverride {
                switch layoutOverride {
                case .horizontal: enLigne(day)
                case .vertical: enColonne(day)
                }
            } else {
                switch Self.layout(for: dynamicTypeSize) {
                case .vertical:
                    enColonne(day)
                case .horizontal:
                    ViewThatFits(in: .horizontal) {
                        enLigne(day)
                        enColonne(day)
                    }
                }
            }
        }
        .padding(.horizontal, JoleneSpacing.md)
        .padding(.vertical, JoleneSpacing.sm)
        .opacity(day.isPast ? Self.pastOpacity : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.rowIdentifier(prefix: identifier, dayID: day.id))
    }

    private func enLigne(_ day: Day) -> some View {
        HStack(spacing: JoleneSpacing.sm) {
            libelle(day)
            Spacer(minLength: JoleneSpacing.sm)
            bascules(day)
        }
    }

    private func enColonne(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            libelle(day).frame(maxWidth: .infinity, alignment: .leading)
            ViewThatFits(in: .horizontal) {
                bascules(day)
                VStack(alignment: .leading, spacing: JoleneSpacing.sm) { boutons(day) }
            }
        }
    }

    private func libelle(_ day: Day) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(day.label)
                .font(JoleneFont.callout)
                .foregroundStyle(Color(Self.dayLabelInkHSL))
            if day.isToday {
                Text(Self.todayText)
                    .font(Font.system(.caption2).weight(.semibold))
                    .foregroundStyle(Color(Self.todayInkHSL))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHidden(true)
    }

    private func bascules(_ day: Day) -> some View {
        HStack(spacing: JoleneSpacing.sm) { boutons(day) }
    }

    @ViewBuilder private func boutons(_ day: Day) -> some View {
        ForEach(Creneau.allCases, id: \.self) { creneau in
            AvailabilityToggle(creneau: creneau, state: day.state(creneau), isPast: day.isPast,
                               accessibilityLabel: Self.accessibilityLabel(day: day, creneau: creneau),
                               identifier: Self.identifier(prefix: identifier, dayID: day.id, creneau: creneau)) {
                onToggle(day, creneau)
            }
        }
    }
}

/// Bascule « Jour » ou « Nuit » d'un jour : 44 pt au moins, icône pleine et fond plein quand le créneau est déclaré,
/// indicateur pendant l'appel serveur, inerte sur un jour passé.
struct AvailabilityToggle: View {
    let creneau: AvailabilityWeekGrid.Creneau
    let state: AvailabilityWeekGrid.SlotState
    let isPast: Bool
    let accessibilityLabel: String
    let identifier: String
    let action: () -> Void

    init(creneau: AvailabilityWeekGrid.Creneau, state: AvailabilityWeekGrid.SlotState, isPast: Bool, accessibilityLabel: String,
         identifier: String, action: @escaping () -> Void) {
        self.creneau = creneau; self.state = state; self.isPast = isPast
        self.accessibilityLabel = accessibilityLabel; self.identifier = identifier; self.action = action
    }

    var body: some View {
        let declare = state.isAvailable
        Button(action: action) {
            HStack(spacing: JoleneSpacing.xs) {
                if state.isPending {
                    ProgressView().tint(encre(declare: declare))
                } else {
                    Image(systemName: creneau.systemImage(isSelected: declare))
                }
                Text(creneau.label)
            }
            .font(JoleneFont.caption.weight(.semibold))
            .foregroundStyle(encre(declare: declare))
            .padding(.horizontal, JoleneSpacing.md)
            .frame(minWidth: AvailabilityWeekGrid.minimumTapTarget, minHeight: AvailabilityWeekGrid.minimumTapTarget)
            .background(fond(declare: declare))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(declare ? Color.clear : JoleneColor.rose100, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!AvailabilityWeekGrid.isToggleEnabled(state, isPast: isPast))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(declare ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func encre(declare: Bool) -> Color {
        guard declare else { return Color(AvailabilityWeekGrid.unselectedInkHSL) }
        return creneau.selectedInkHSL.map { Color($0) } ?? JoleneColor.onGradient
    }

    @ViewBuilder private func fond(declare: Bool) -> some View {
        if declare {
            if creneau == .journee { JoleneColor.heroGradient } else { JoleneColor.midnight }
        } else {
            JoleneColor.cloud
        }
    }
}
