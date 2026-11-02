import Foundation
import JoleneCore

/// Accumulateur pur de la pagination des créneaux (`mission_creneaux`), avec les MÊMES
/// vérifications d'intégrité que le pilote (`SupabaseMissionGateway.slots`) :
/// compte exact obligatoire, compte stable entre pages, page vide interdite tant que le
/// compte n'est pas atteint, créneaux hors lot / hors type / en pause / doublons refusés,
/// total final égal au compte. Un planning tronqué n'est jamais présenté comme exact.
public struct MissionSlotPager: Sendable {
    public static let countUnavailable = JoleneError(.unknown, "Le nombre de créneaux ne peut pas être vérifié.")
    public static let planningChanged = JoleneError(.unknown, "Le planning a changé pendant son chargement. Réessayez.")
    public static let planningIncomplete = JoleneError(.unknown, "Le planning détaillé est incomplet.")
    public static let planningInconsistent = JoleneError(.contract, "Le planning détaillé contient des créneaux incohérents.")

    public let batch: [String]
    public private(set) var expected: Int?
    public private(set) var offset: Int = 0
    private var found: [String: MissionSlot] = [:]
    private var order: [String] = []

    public init(batch: [String]) {
        self.batch = batch
    }

    /// Vrai tant qu'une page supplémentaire doit être demandée.
    public var needsMore: Bool {
        guard let expected else { return true }
        return offset < expected
    }

    /// Intègre une page et son compte `Content-Range`. Lève l'erreur d'intégrité adéquate.
    public mutating func ingest(page: [MissionSlot], count: Int?) throws {
        guard let count, count >= 0 else { throw Self.countUnavailable }
        if let expected, count != expected { throw Self.planningChanged }
        expected = count
        if page.isEmpty, offset < count { throw Self.planningIncomplete }
        for slot in page {
            guard let id = slot.id, !id.isEmpty,
                  let missionId = slot.missionId, batch.contains(missionId),
                  slot.typeCreneau == MissionQuery.forecastSlotType,
                  !slot.estPause,
                  found[id] == nil
            else { throw Self.planningInconsistent }
            found[id] = slot
            order.append(id)
        }
        offset += page.count
        if offset > count { throw Self.planningInconsistent }
    }

    /// Créneaux collectés, dans l'ordre serveur. Lève si le total ne vaut pas le compte annoncé.
    public func finish() throws -> [MissionSlot] {
        guard let expected, found.count == expected else { throw Self.planningIncomplete }
        return order.compactMap { found[$0] }
    }

    /// Découpe des identifiants en lots de `size`, dédoublonnés en conservant l'ordre.
    public static func batches(_ ids: [String], size: Int = MissionQuery.slotBatchSize) -> [[String]] {
        var seen = Set<String>()
        let unique = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
        return stride(from: 0, to: unique.count, by: size).map { Array(unique[$0..<min($0 + size, unique.count)]) }
    }
}
