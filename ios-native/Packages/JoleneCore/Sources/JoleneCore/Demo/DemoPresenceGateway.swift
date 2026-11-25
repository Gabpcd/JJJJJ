import Foundation

/// Confirmation de présence du monde démo (lot 1, T6c, `LOT1_PLAN.md` §2.7) : aucun réseau, horloge fixée, état en
/// mémoire pour la session. Mêmes contrôles et mêmes textes que `fn_confirmer_presence_mission`
/// (`supabase/schema/public.sql` l.25080-25100) : mission attribuée au profil fictif, statut `ASSIGNEE` ou `EN_COURS`,
/// puis `presence_confirmee_le` posé **dans l'acteur** (jamais par l'écran) et relu avant de répondre. Comme le serveur,
/// aucune idempotence : chaque appel réécrit l'instant (l'écran masque le bouton après relecture).
///
/// Mission de recette `demo-presence-j1` (`missionJ1`) : copie de `demo-assignee-001` (`demo-dashboard.json`) décalée à
/// `fixedNow + 20 h`, hors des listes (Accueil, Mes missions) pour ne rien changer à leurs fixtures ; ouverte par le
/// lien du push `RAPPEL_MISSION` (`/soignant/missions/demo-presence-j1`, `DemoConfirmationPresenceTests`).
public actor DemoPresenceGateway: PresencePort {
    public enum Textes {
        // Textes serveur repris à l'identique (`fn_confirmer_presence_mission`).
        public static let introuvable = "Mission introuvable"
        public static let plusActive = "Cette mission n'est plus active."
    }

    public static let idMissionJ1 = "demo-presence-j1"
    /// Début de la mission de recette, en secondes après l'horloge démo (dans la fenêtre de 48 h du bloc).
    public static let debutJ1: TimeInterval = 20 * 3600

    private let clock: any ClockPort
    private let mission: @Sendable (String) async throws -> MissionRecord?
    private var confirmations: [String: String] = [:]

    /// - Parameter mission: lecture de la mission telle que le monde démo la sert (surcouche de la candidature comprise).
    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow),
                mission: @escaping @Sendable (String) async throws -> MissionRecord?) {
        self.clock = clock
        self.mission = mission
    }

    public func confirmerPresence(missionId: String, context: MissionReadContext) async throws -> PresenceOutcome {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else { throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement) }
        guard let record = try await mission(missionId), record.soignantAssigneId == context.userId else {
            return .refusee(message: Textes.introuvable)
        }
        guard record.statut == "ASSIGNEE" || record.statut == "EN_COURS" else { return .refusee(message: Textes.plusActive) }
        confirmations[missionId] = DateHeureParis.isoUTC(clock.now())
        // Relecture dans l'acteur : jamais un succès sans `presence_confirmee_le` relu.
        guard let relue = surcouche(record).presenceConfirmeeLe else {
            throw JoleneError(.contract, "La confirmation n'a pas pu être relue dans le monde de démonstration.")
        }
        return .confirmee(presenceConfirmeeLe: relue)
    }

    /// Surcouche de lecture des missions démo (`DemoMissionsGateway`) : présence confirmée pendant la session.
    public func surcouche(_ record: MissionRecord) -> MissionRecord {
        guard let instant = confirmations[record.id] else { return record }
        var confirmee = record
        confirmee.presenceConfirmeeLe = instant
        return confirmee
    }

    /// `demo-presence-j1` : planning et établissement de `demo-assignee-001`, décalés pour démarrer à `fixedNow + 20 h`
    /// (même durée) ; `nil` si la fixture source est illisible.
    public static func missionJ1() throws -> DemoFixtures.MissionFixture? {
        guard let source = try DemoFixtures.loadDashboard().missionsAssignees.first(where: { $0.record.id == "demo-assignee-001" }),
              let debut = try? DateHeureParis.instantJolene(source.record.debutLe) else { return nil }
        let decalage = DemoWorld.fixedNow.addingTimeInterval(debutJ1).timeIntervalSince(debut)
        func decaler(_ iso: String?) -> String? {
            guard let iso, let instant = try? DateHeureParis.instantJolene(iso) else { return iso }
            return DateHeureParis.isoUTC(instant.addingTimeInterval(decalage))
        }
        var record = source.record
        record.id = idMissionJ1
        record.intitule = "Démonstration · Confirmation de présence"
        record.debutLe = decaler(record.debutLe) ?? record.debutLe
        record.finLe = decaler(record.finLe) ?? record.finLe
        record.presenceConfirmeeLe = nil
        let creneaux = source.creneaux.map { slot -> MissionSlot in
            var copie = slot
            copie.id = slot.id.map { $0.replacingOccurrences(of: "demo-assignee-001", with: idMissionJ1) }
            copie.missionId = idMissionJ1
            copie.debut = decaler(slot.debut) ?? slot.debut
            copie.fin = decaler(slot.fin)
            return copie
        }
        return DemoFixtures.MissionFixture(record: record, creneaux: creneaux)
    }
}
