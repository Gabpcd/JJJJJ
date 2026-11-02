import SwiftUI
import JoleneCore

/// Liste de créneaux (détail mission, récapitulatif de candidature, confirmation de présence).
/// Les libellés sont produits par le cœur (`MissionPresentation.creneau`) : le composant ne
/// lit ni ne reformate les dates. Identifiants `<prefix>-creneau-<n>` (convention du lot 0,
/// `MissionDetailScreen`), pauses distinguées par l'icône ET le préfixe vocalisé.
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

    /// Identifiant d'un créneau à partir de son index (base 1 comme le lot 0).
    nonisolated public static func identifier(prefix: String, index: Int) -> String { "\(prefix)-creneau-\(index + 1)" }

    /// Résumé accordé : « Aucun créneau », « 1 créneau », « 3 créneaux ».
    nonisolated public static func resume(count: Int) -> String {
        switch count {
        case ..<1: return "Aucun créneau"
        case 1: return "1 créneau"
        default: return "\(count) créneaux"
        }
    }

    /// Conversion des créneaux serveur par le cœur ; l'identifiant est positionnel, donc stable
    /// même quand deux créneaux ont le même libellé ou aucun `id` serveur.
    nonisolated public static func items(_ slots: [MissionSlot]) -> [Item] {
        slots.enumerated().map { index, slot in
            Item(id: "creneau-\(index + 1)", label: MissionPresentation.creneau(slot), isPause: slot.estPause)
        }
    }

    private let items: [Item]
    private let identifier: String
    private let emptyMessage: String
    private let showsResume: Bool

    public init(items: [Item], identifier: String, emptyMessage: String = "Aucun créneau communiqué.", showsResume: Bool = false) {
        self.items = items; self.identifier = identifier; self.emptyMessage = emptyMessage; self.showsResume = showsResume
    }

    public init(slots: [MissionSlot], identifier: String, emptyMessage: String = "Aucun créneau communiqué.", showsResume: Bool = false) {
        self.init(items: Self.items(slots), identifier: identifier, emptyMessage: emptyMessage, showsResume: showsResume)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            if showsResume {
                Text(Self.resume(count: items.count))
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("\(identifier)-resume")
            }
            if items.isEmpty {
                Text(emptyMessage)
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("\(identifier)-empty")
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
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
                    .accessibilityIdentifier(Self.identifier(prefix: identifier, index: index))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
