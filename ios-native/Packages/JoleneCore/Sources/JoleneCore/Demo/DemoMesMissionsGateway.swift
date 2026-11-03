import Foundation

extension DemoFixtures {
    /// Mission passée telle qu'exportée : la ligne `missions` (avec ses créneaux) et ses colonnes
    /// financières (`net_estime`, `type_contrat_applique`…), lues du même objet JSON.
    public struct MissionPasseeFixture: Decodable, Equatable, Sendable {
        public var mission: MissionFixture
        public var finance: MissionGainLigne

        public init(from decoder: Decoder) throws {
            mission = try MissionFixture(from: decoder)
            finance = try MissionGainLigne(from: decoder)
        }
    }

    /// `demo-mes-missions.json` (lot 1, T5) : candidatures EN_ATTENTE du profil fictif (sur des
    /// missions de `demo-missions.json`) et missions passées. Les missions « À venir » sont les
    /// missions ASSIGNEE de `demo-dashboard.json` (`missions_assignees`) : une seule source, celle de
    /// l'Accueil, jamais une copie.
    public struct MesMissionsFile: Decodable, Sendable {
        public var fixedNow: String
        public var candidatures: [CandidatureRecord]
        public var passees: [MissionPasseeFixture]

        enum CodingKeys: String, CodingKey {
            case fixedNow = "fixed_now"
            case candidatures, passees
        }
    }

    public static func loadMesMissions() throws -> MesMissionsFile { try load("demo-mes-missions") }
}

/// Garde commune des ports « Mes missions » démo : contexte cohérent et profil fictif seulement.
private func verifierContexteDemo(_ context: MissionReadContext) throws {
    try MissionBusiness.validateContext(context)
    guard context.userId == DemoWorld.context.userId else {
        throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
    }
}

/// Mes missions du monde démo : fixtures embarquées, aucun réseau, horloge fixée. Mêmes filtres et
/// ordres que les requêtes du web (`MesMissionsPresentation.statuts*`, départage par `id` comme la
/// gateway Supabase), lecture cumulative des pages comme le web (« M1 »), missions enrichies par
/// `MissionBusiness.enrich` comme Explorer. Refuse tout contexte qui n'est pas celui du profil fictif.
///
/// Point de fusion T6a/T6b : `candidaturesDeSession` rend les candidatures posées pendant la session
/// démo (actor de `DemoCandidatureGateway`) ; elles précèdent celles des fixtures, comme un `cree_le`
/// plus récent. Le serveur n'admet qu'une candidature par mission et par soignant (`UNIQUE
/// candidatures_mission_id_soignant_id_key`) : une candidature de session **remplace** celle des
/// fixtures sur la même mission, avant le filtre de statut (une annulation en session la retire).
/// Défaut : aucune.
///
/// `taillePage` : `MissionsPage.taille` (50) ; la surcharge DEBUG `JOLENE_DEMO_MES_MISSIONS_PAGE`
/// la réduit pour la recette de « Charger plus » dans l'interface (`DemoMesMissionsSurcharges`).
public struct DemoMesMissionsGateway: MesMissionsPort {
    private let clock: any ClockPort
    private let taillePage: Int
    private let candidaturesDeSession: @Sendable () async -> [CandidatureRecord]

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), taillePage: Int = MissionsPage.taille,
                candidaturesDeSession: @escaping @Sendable () async -> [CandidatureRecord] = { [] }) {
        self.clock = clock
        self.taillePage = max(1, taillePage)
        self.candidaturesDeSession = candidaturesDeSession
    }

    public func candidatures(context: MissionReadContext) async throws -> [CandidatureRecord] {
        try verifierContexteDemo(context)
        let missions = try DemoFixtures.loadMissions().missions
        let etablissements = try chargerEtablissements()
        let lignes = Self.uneParMission(await candidaturesDeSession() + (try DemoFixtures.loadMesMissions().candidatures))
        return lignes
            .filter { MesMissionsPresentation.statutsCandidatures.contains($0.statut ?? "") }
            .sorted { Self.instant($0.creeLe) > Self.instant($1.creeLe) } // `order('cree_le', desc)`
            .compactMap { ligne -> CandidatureRecord? in
                // Mission masquée (web : `c.missions` nul, l.188) : la candidature est écartée.
                guard let fixture = missions.first(where: { $0.record.id == ligne.missionId }) else { return nil }
                var candidature = ligne
                candidature.mission = enrich(fixture, context: context, etablissements: etablissements)
                return candidature
            }
    }

    public func aVenir(context: MissionReadContext, page: Int) async throws -> MissionsPage {
        try verifierContexteDemo(context)
        let maintenant = clock.now()
        let etablissements = try chargerEtablissements()
        let missions = try DemoFixtures.loadDashboard().missionsAssignees
            .filter { MesMissionsPresentation.statutsAVenir.contains($0.record.statut) }
            .filter { Self.instant($0.record.finLe) >= maintenant } // `gte('fin_le', maintenant)`
            .sorted { Self.avant($0.record, $1.record, croissant: true) }
            .map { enrich($0, context: context, etablissements: etablissements) }
        return Self.page(missions, page: page, taille: taillePage)
    }

    public func passees(context: MissionReadContext, page: Int) async throws -> MissionsPage {
        try verifierContexteDemo(context)
        let etablissements = try chargerEtablissements()
        let passees = try DemoFixtures.loadMesMissions().passees
            .filter { MesMissionsPresentation.statutsPassees.contains($0.mission.record.statut) }
            .sorted { Self.avant($0.mission.record, $1.mission.record, croissant: false) }
        var lue = Self.page(passees.map { enrich($0.mission, context: context, etablissements: etablissements) },
                            page: page, taille: taillePage)
        let ids = Set(lue.missions.map(\.id))
        lue.finances = Dictionary(passees.map(\.finance).filter { ids.contains($0.id) }.map { ($0.id, $0) },
                                  uniquingKeysWith: { premiere, _ in premiere })
        return lue
    }

    // MARK: - Interne

    /// Instant d'une borne ISO 8601 ; une valeur absente ou illisible se range en dernier (`distantPast`).
    static func instant(_ iso: String?) -> Date {
        iso.flatMap(PlanningHorlogeParis.instant) ?? .distantPast
    }

    /// Ordre `debut_le` (croissant ou décroissant), puis `id` croissant (départage de la gateway Supabase).
    static func avant(_ gauche: MissionRecord, _ droite: MissionRecord, croissant: Bool) -> Bool {
        let (a, b) = (instant(gauche.debutLe), instant(droite.debutLe))
        if a != b { return croissant ? a < b : a > b }
        return gauche.id < droite.id
    }

    /// Lecture cumulative des pages 0…`page` de `taille` missions (web « M1 ») ; « page suivante »
    /// proposée si la lecture est pleine (`(page + 1) * taille` missions).
    static func page(_ missions: [Mission], page: Int, taille: Int = MissionsPage.taille) -> MissionsPage {
        let attendu = (max(0, page) + 1) * max(1, taille)
        let lues = Array(missions.prefix(attendu))
        return MissionsPage(missions: lues, page: max(0, page), aSuivre: lues.count == attendu)
    }

    /// Une candidature par mission, la première rencontrée gagnant (celles de la session précèdent).
    static func uneParMission(_ candidatures: [CandidatureRecord]) -> [CandidatureRecord] {
        var vues = Set<String>()
        return candidatures.filter { vues.insert($0.missionId).inserted }
    }

    private func chargerEtablissements() throws -> [EtablissementSummary] {
        try DemoFixtures.loadEtablissements().etablissements
    }

    private func enrich(_ fixture: DemoFixtures.MissionFixture, context: MissionReadContext,
                        etablissements: [EtablissementSummary]) -> Mission {
        let etablissement = etablissements.first { $0.id == fixture.record.etablissementId }
        return MissionBusiness.enrich(record: fixture.record, context: context, etablissement: etablissement, slots: fixture.creneaux)
    }
}

// MARK: - Recette des états dans l'interface (DEBUG, revue B8 de T5)

/// « Mes missions » démo en échec forcé, pour la recette de l'état d'erreur, de la reprise et de la
/// session expirée dans l'interface (`DemoMesMissionsTests` XCUITest) : installé seulement par la
/// surcharge DEBUG `JOLENE_FORCE_MES_MISSIONS_ECHEC` d'`AppContainer`, jamais en Release. Les
/// `echecsParOnglet` premières lectures non annulées **de chaque onglet** échouent (panne réseau
/// simulée comme un délai dépassé, ou session expirée) ; les suivantes délèguent au relais. Une tâche
/// annulée avant l'appel ne consomme pas d'échec. Même refus que le port démo pour tout autre utilisateur.
public actor DemoMesMissionsEchecGateway: MesMissionsPort {
    public enum Panne: Equatable, Sendable {
        /// `SessionController.timeoutMessage`, comme `DemoDashboardEchecGateway` : « Réessayer ».
        case reseau
        /// `.unauthorized` : « Session à vérifier », puis « Vérifier ma session ».
        case sessionExpiree

        var erreur: JoleneError {
            switch self {
            case .reseau: return JoleneError(.network, SessionController.timeoutMessage)
            case .sessionExpiree: return JoleneError(.unauthorized, SessionController.sessionExpiredMessage)
            }
        }
    }

    private let relais: any MesMissionsPort
    private let panne: Panne
    private var echecsRestants: [MesMissionsOnglet: Int]

    public init(panne: Panne = .reseau, echecsParOnglet: Int = 1, relais: any MesMissionsPort = DemoMesMissionsGateway()) {
        self.panne = panne
        self.relais = relais
        self.echecsRestants = Dictionary(uniqueKeysWithValues: MesMissionsOnglet.allCases.map { ($0, max(0, echecsParOnglet)) })
    }

    public func candidatures(context: MissionReadContext) async throws -> [CandidatureRecord] {
        try echouerSiDu(.candidatures, context: context)
        return try await relais.candidatures(context: context)
    }

    public func aVenir(context: MissionReadContext, page: Int) async throws -> MissionsPage {
        try echouerSiDu(.aVenir, context: context)
        return try await relais.aVenir(context: context, page: page)
    }

    public func passees(context: MissionReadContext, page: Int) async throws -> MissionsPage {
        try echouerSiDu(.passees, context: context)
        return try await relais.passees(context: context, page: page)
    }

    private func echouerSiDu(_ onglet: MesMissionsOnglet, context: MissionReadContext) throws {
        try verifierContexteDemo(context)
        try Task.checkCancellation()
        guard let restants = echecsRestants[onglet], restants > 0 else { return }
        echecsRestants[onglet] = restants - 1
        throw panne.erreur
    }
}

/// « Mes missions » démo sans aucune ligne, pour la recette des trois états vides et de leur renvoi
/// vers Explorer (surcharge DEBUG `JOLENE_FORCE_MES_MISSIONS_VIDE`). Même refus que le port démo.
public struct DemoMesMissionsVideGateway: MesMissionsPort {
    public init() {}

    public func candidatures(context: MissionReadContext) async throws -> [CandidatureRecord] {
        try verifierContexteDemo(context)
        return []
    }

    public func aVenir(context: MissionReadContext, page: Int) async throws -> MissionsPage {
        try verifierContexteDemo(context)
        return MissionsPage(missions: [], page: max(0, page), aSuivre: false)
    }

    public func passees(context: MissionReadContext, page: Int) async throws -> MissionsPage {
        try verifierContexteDemo(context)
        return MissionsPage(missions: [], page: max(0, page), aSuivre: false)
    }
}

/// Surcharges DEBUG de « Mes missions » démo, lues par `AppContainer` dans l'environnement du
/// processus (liste centralisée des surcharges, comme `JOLENE_FORCE_ACCUEIL_ECHEC`) ; jamais lues en
/// Release. Composition : liste vide **ou** fixtures (taille de page éventuelle), enveloppée par
/// l'échec forcé s'il est demandé. Valeur absente ou invalide : port démo par défaut (`nil`).
/// - `JOLENE_FORCE_MES_MISSIONS_ECHEC` : `1` (panne réseau) ou `session` (session expirée), première
///   lecture de chaque onglet ;
/// - `JOLENE_FORCE_MES_MISSIONS_VIDE` : `1`, aucune ligne sur les trois onglets ;
/// - `JOLENE_DEMO_MES_MISSIONS_PAGE` : taille de page de 1 à `MissionsPage.taille`.
public enum DemoMesMissionsSurcharges {
    public static let variableEchec = "JOLENE_FORCE_MES_MISSIONS_ECHEC"
    public static let variableVide = "JOLENE_FORCE_MES_MISSIONS_VIDE"
    public static let variableTaillePage = "JOLENE_DEMO_MES_MISSIONS_PAGE"

    public static func port(environment: [String: String], clock: any ClockPort) -> (any MesMissionsPort)? {
        let panne: DemoMesMissionsEchecGateway.Panne?
        switch environment[variableEchec] {
        case "1": panne = .reseau
        case "session": panne = .sessionExpiree
        default: panne = nil
        }
        let vide = environment[variableVide] == "1"
        let taille = environment[variableTaillePage].flatMap(Int.init).flatMap { (1...MissionsPage.taille).contains($0) ? $0 : nil }
        guard panne != nil || vide || taille != nil else { return nil }
        let base: any MesMissionsPort = vide
            ? DemoMesMissionsVideGateway()
            : DemoMesMissionsGateway(clock: clock, taillePage: taille ?? MissionsPage.taille)
        guard let panne else { return base }
        return DemoMesMissionsEchecGateway(panne: panne, relais: base)
    }
}
