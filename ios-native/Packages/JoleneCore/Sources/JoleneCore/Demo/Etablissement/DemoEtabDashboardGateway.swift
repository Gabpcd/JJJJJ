import Foundation

/// Accueil établissement démo (lot 5, T4) : rejoue `fn_stats_dashboard_etablissement` et les lectures PostgREST du
/// planning à venir depuis `demo-etab-dashboard.json` (généré par `export-demo-fixtures.mjs`, clés lues dans le dump),
/// avec les filtres du serveur (statuts, fenêtre de 31 jours) et la même dérivation que le monde Supabase
/// (`EtabPlanningAccueil.construire`). Refuse un contexte incohérent puis tout autre compte que le compte fictif.
/// `planningIndisponible` (tests) : la lecture secondaire échoue, l'Accueil s'affiche avec le bandeau « partiel ».
public struct DemoEtabDashboardGateway: EtabDashboardPort {
    private let clock: any ClockPort
    private let planningIndisponible: Bool
    /// Lot 5 (T11) : non-lus relus de la messagerie démo du même monde (le serveur compte `messages_chat`) ; `nil` :
    /// valeur de la fixture.
    private let messagesNonLus: (@Sendable (EtablissementReadContext) async -> Int?)?

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), planningIndisponible: Bool = false,
                messagesNonLus: (@Sendable (EtablissementReadContext) async -> Int?)? = nil) {
        self.clock = clock
        self.planningIndisponible = planningIndisponible
        self.messagesNonLus = messagesNonLus
    }

    public func tableauDeBord(context: EtablissementReadContext) async throws -> EtabDashboardSnapshot {
        try DemoEtablissementWorld.verifier(context)
        var fichier = try DemoFixtures.loadEtabDashboard()
        if let messagesNonLus, let relus = await messagesNonLus(context) { fichier.stats.messagesNonLus = relus }
        guard !planningIndisponible else { return EtabDashboardSnapshot(stats: fichier.stats, planning: nil) }
        let maintenant = clock.now()
        let finFenetre = EtabPlanningAccueil.finFenetre(maintenant)
        // Filtres de la requête serveur (`DashboardEtablissement.tsx` l.293-299) : fin ≥ maintenant, début ≤ fin de fenêtre.
        let missions = fichier.missions.filter { mission in
            EtabPlanningAccueil.statuts.contains(mission.statut)
                && DisponibilitePointage.temps(mission.finLe) >= DisponibilitePointage.temps(maintenant)
                && DisponibilitePointage.temps(mission.debutLe) <= DisponibilitePointage.temps(finFenetre)
        }
        let ids = Set(missions.map(\.id))
        let creneaux = fichier.creneaux.filter { $0.missionId.map(ids.contains) ?? false }
        return EtabDashboardSnapshot(stats: fichier.stats,
                                     planning: EtabPlanningAccueil.construire(missions: missions, creneaux: creneaux, maintenant: maintenant))
    }
}

public extension DemoFixtures {
    /// `demo-etab-dashboard.json`.
    struct EtabDashboardFile: Decodable, Sendable {
        public var fixedNow: String
        public var stats: EtabDashboardStats
        public var missions: [EtabMissionPlanifiee]
        public var creneaux: [MissionSlot]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", stats, missions, creneaux }
    }

    static func loadEtabDashboard() throws -> EtabDashboardFile { try load("demo-etab-dashboard") }
}
