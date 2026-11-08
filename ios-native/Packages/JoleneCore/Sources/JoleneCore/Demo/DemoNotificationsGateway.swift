import Foundation

extension DemoFixtures {
    /// `demo-notifications.json` (lot 3, T5) : lignes `notifications` du profil fictif (clés PostgREST), deux non
    /// lues comme le compteur de `demo-dashboard.json` (`notifs_non_lues`).
    public struct NotificationsFile: Decodable, Sendable {
        public var fixedNow: String
        public var notifications: [NotificationJolene]

        enum CodingKeys: String, CodingKey {
            case fixedNow = "fixed_now"
            case notifications
        }
    }

    public static func loadNotifications() throws -> NotificationsFile { try load("demo-notifications") }
}

/// `NotificationsCenterPort` du monde démo (lot 3, T5 ; blueprint §2.7) : `demo-notifications.json` (généré par
/// `scripts/mobile/export-demo-fixtures.mjs`), acteur en mémoire, aucun réseau. Mêmes règles que la gateway
/// Supabase : seul le profil fictif (`DemoWorld.context`) lit ses notifications (la démo n'est jamais un repli pour
/// un compte réel), liste triée par `cree_le` décroissant et bornée à 200, « marquer lue » rend la ligne relue
/// (`lue_le` = horloge démo), un identifiant inconnu n'est jamais un succès.
public actor DemoNotificationsGateway: NotificationsCenterPort {
    public static let messageIntrouvable = "Notification introuvable."

    private var lignes: [NotificationJolene]?
    private let charger: @Sendable () throws -> [NotificationJolene]
    private let horloge: any ClockPort

    public init(horloge: any ClockPort = FixedClock(DemoWorld.fixedNow),
                charger: @escaping @Sendable () throws -> [NotificationJolene] = { try DemoFixtures.loadNotifications().notifications }) {
        self.horloge = horloge
        self.charger = charger
    }

    public func liste(context: MissionReadContext) async throws -> [NotificationJolene] {
        try verifier(context)
        let tri = try lire().sorted { ($0.creeLe ?? "") > ($1.creeLe ?? "") }
        return Array(tri.prefix(CentreNotificationsModel.limite))
    }

    public func marquerLue(id: String, context: MissionReadContext) async throws -> NotificationJolene {
        try verifier(context)
        var courantes = try lire()
        guard let index = courantes.firstIndex(where: { $0.id == id }) else {
            throw JoleneError(.unknown, Self.messageIntrouvable)
        }
        if !courantes[index].lue {
            courantes[index].lue = true
            courantes[index].lueLe = DateHeureParis.isoUTC(horloge.now())
        }
        lignes = courantes
        // Relecture après mutation : la ligne rendue est celle de l'acteur, jamais une copie supposée.
        guard let relue = lignes?.first(where: { $0.id == id }) else {
            throw JoleneError(.unknown, Self.messageIntrouvable)
        }
        return relue
    }

    private func lire() throws -> [NotificationJolene] {
        if let lignes { return lignes }
        let chargees = try charger()
        lignes = chargees
        return chargees
    }

    private func verifier(_ context: MissionReadContext) throws {
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}
