import Foundation

extension DemoFixtures {
    /// `demo-dashboard.json` (lot 1, T3) : corps de `fn_dashboard_soignant_complet` du profil
    /// fictif, fiches et créneaux des deux missions ASSIGNEE (`missions_assignees`, lisibles en
    /// détail, jamais listées dans Explorer) et missions TERMINEE du mois relues pour les gains
    /// (`gains_missions`). Les missions ouvertes et proposées sont celles de `demo-missions.json`.
    public struct DashboardFile: Decodable, Sendable {
        public var fixedNow: String
        public var dashboard: DashboardCorps
        public var missionsAssignees: [MissionFixture]
        public var gainsMissions: [MissionGainLigne]

        enum CodingKeys: String, CodingKey {
            case fixedNow = "fixed_now"
            case dashboard
            case missionsAssignees = "missions_assignees"
            case gainsMissions = "gains_missions"
        }
    }

    public static func loadDashboard() throws -> DashboardFile { try load("demo-dashboard") }
}

/// Tableau de bord démo : fixtures embarquées, aucun réseau, horloge fixée. Assemblé par
/// `AccueilAssemblage`, comme le monde Supabase (fiches et créneaux relus, établissements par
/// id, gains relus). Refuse tout contexte qui n'est pas celui du profil fictif.
public struct DemoDashboardGateway: DashboardPort {
    private let clock: any ClockPort

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow)) {
        self.clock = clock
    }

    public func dashboard(context: MissionReadContext) async throws -> DashboardSnapshot {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
        let fichier = try DemoFixtures.loadDashboard()
        let ouvertes = try DemoFixtures.loadMissions().missions
        let etablissements = try DemoFixtures.loadEtablissements().etablissements
        let demandes = Set(AccueilAssemblage.identifiantsMissions(fichier.dashboard, email: context.email))
        let relues = (fichier.missionsAssignees + ouvertes).filter { demandes.contains($0.record.id) }
        return try AccueilAssemblage.snapshot(
            corps: fichier.dashboard, context: context, maintenant: clock.now(),
            lecture: LectureMissionsAccueil(records: relues.map(\.record), creneaux: relues.flatMap(\.creneaux)),
            etablissements: Dictionary(etablissements.map { ($0.id, $0) }, uniquingKeysWith: { premier, _ in premier }),
            gains: fichier.gainsMissions)
    }
}

/// Tableau de bord démo en échec forcé, pour la recette de l'état d'erreur dans l'interface
/// (`DemoAccueilTests.testAccueilErreurPuisReprise`) : installé seulement par la surcharge DEBUG
/// `JOLENE_FORCE_ACCUEIL_ECHEC` de `AppContainer`, jamais en Release. Les `echecs` premiers
/// chargements non annulés échouent comme un délai dépassé (`SessionController.timeoutMessage`) ;
/// les suivants délèguent au port démo. Une tâche annulée avant l'appel ne consomme pas d'échec.
/// Même refus que le port démo pour tout autre utilisateur.
public actor DemoDashboardEchecGateway: DashboardPort {
    private let relais: DemoDashboardGateway
    private var echecsRestants: Int

    public init(echecs: Int = 1, relais: DemoDashboardGateway = DemoDashboardGateway()) {
        self.echecsRestants = max(0, echecs)
        self.relais = relais
    }

    public func dashboard(context: MissionReadContext) async throws -> DashboardSnapshot {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
        try Task.checkCancellation()
        if echecsRestants > 0 {
            echecsRestants -= 1
            throw JoleneError(.network, SessionController.timeoutMessage)
        }
        return try await relais.dashboard(context: context)
    }
}
