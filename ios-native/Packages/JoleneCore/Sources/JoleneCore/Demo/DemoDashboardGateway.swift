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
///
/// Variante de recette (lot 3, T3b — revue B8, m4 : verrou T12 n°2 du lot 1) : `missionsOubliees` remplace le
/// compteur `missions_oubliees_count` de la fixture (0) pour prouver l'encart « Oubli de pointage ? » et son bouton
/// (natif depuis la fusion avec le lot 2 : page Présences ; ancien renvoi web `/soignant/presences`) ; installée
/// seulement par la surcharge DEBUG `JOLENE_FORCE_OUBLI_POINTAGE=1` (`AppContainer`), jamais en Release. Scénario
/// `accueil-pointage` (lot 2, T5a, `scenario`) : voir `ajouterPointageDuJour`.
public struct DemoDashboardGateway: DashboardPort {
    /// Variable d'environnement DEBUG de la variante « oubli de pointage » (`AppContainer`, `DemoAccueilTests`).
    public static let variableOubliPointage = "JOLENE_FORCE_OUBLI_POINTAGE"

    private let clock: any ClockPort
    private let scenario: ScenarioAccueilDemo
    private let missionsOubliees: Int?

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), scenario: ScenarioAccueilDemo = .normal,
                missionsOubliees: Int? = nil) {
        self.clock = clock
        self.scenario = scenario
        self.missionsOubliees = missionsOubliees
    }

    /// `delaiEcran` sans objet : fixtures embarquées, aucune lecture à sous-budgéter.
    public func dashboard(context: MissionReadContext, delaiEcran: TimeInterval) async throws -> DashboardSnapshot {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
        let fichier = try DemoFixtures.loadDashboard()
        let ouvertes = try DemoFixtures.loadMissions().missions
        let etablissements = try DemoFixtures.loadEtablissements().etablissements
        let demandes = Set(AccueilAssemblage.identifiantsMissions(fichier.dashboard, email: context.email))
        let relues = (fichier.missionsAssignees + ouvertes).filter { demandes.contains($0.record.id) }
        let parId = Dictionary(etablissements.map { ($0.id, $0) }, uniquingKeysWith: { premier, _ in premier })
        var corps = fichier.dashboard
        if let missionsOubliees { corps.missionsOublieesCount = missionsOubliees }
        var snapshot = try AccueilAssemblage.snapshot(
            corps: corps, context: context, maintenant: clock.now(),
            lecture: LectureMissionsAccueil(records: relues.map(\.record), creneaux: relues.flatMap(\.creneaux)),
            etablissements: parId,
            gains: fichier.gainsMissions)
        if scenario == .pointage {
            try Self.ajouterPointageDuJour(&snapshot, etablissements: parId, maintenant: clock.now())
        }
        return snapshot
    }

    /// Scénario `accueil-pointage` (lot 2, T5a) : la mission du jour de `demo-presences.json` (`demo-presence-a`, créneau
    /// de 01h05 à 09h05 à Paris, pointable dès 00h50) en tête des prochaines missions, et un départ oublié
    /// (`missions_oubliees_count = 1`) : recette du widget « Aller pointer » et du bandeau d'oubli de départ.
    static func ajouterPointageDuJour(_ snapshot: inout DashboardSnapshot, etablissements: [String: EtablissementSummary],
                                      maintenant: Date) throws {
        let presences = try DemoPointageGateway.Fixture.charger()
        guard let mission = presences.missions.first(where: { $0.id == Self.missionPointageDuJour }) else { return }
        let creneaux = presences.creneaux.filter { $0.missionId == mission.id }
        let prochain = DisponibilitePointage.prochainCreneauPointage(creneaux, maintenant: maintenant)
        let etablissement = mission.etablissementId.flatMap { etablissements[$0] }
        let ligne = DashboardMissionLigne(id: mission.id, intitule: mission.intitule ?? mission.id, service: mission.service,
                                          debutLe: mission.debutLe, finLe: mission.finLe, statut: mission.statut, estUrgente: false,
                                          tauxHoraireBase: nil, etablissementId: mission.etablissementId, etabNom: etablissement?.nom)
        let nombre = DisponibilitePointage.creneauxPrevisionnels(creneaux).count
        snapshot.prochaines.insert(AccueilMission(ligne: ligne, etablissementNom: AccueilAssemblage.nom(etablissement: etablissement, repli: nil),
                                                  etablissementVille: etablissement?.adresseVille,
                                                  planning: .planifie(prochain: prochain, rang: prochain == nil ? nil : 1, nombre: nombre),
                                                  mission: nil), at: 0)
        snapshot.missionsOublieesCount = 1
    }

    /// Mission du jour du scénario `accueil-pointage`.
    public static let missionPointageDuJour = "demo-presence-a"
}

/// Scénarios de l'Accueil démo (`-JOLENE_DEMO_SCENARIO`, DEBUG, lu par `AppContainer`) ; une valeur d'un autre domaine
/// (`upload-incertain`, `scan-incertain`, `otp-expire`) : `.normal`.
public enum ScenarioAccueilDemo: String, CaseIterable, Sendable {
    case normal
    /// Mission du jour à pointer et départ oublié (lot 2, T5a).
    case pointage = "accueil-pointage"

    public init(arguments: [String]) {
        self = ArgumentsDemo.valeur(ScenarioDocumentsDemo.argument, dans: arguments).flatMap(Self.init(rawValue:)) ?? .normal
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

    public func dashboard(context: MissionReadContext, delaiEcran: TimeInterval) async throws -> DashboardSnapshot {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
        try Task.checkCancellation()
        if echecsRestants > 0 {
            echecsRestants -= 1
            throw JoleneError(.network, SessionController.timeoutMessage)
        }
        return try await relais.dashboard(context: context, delaiEcran: delaiEcran)
    }
}
