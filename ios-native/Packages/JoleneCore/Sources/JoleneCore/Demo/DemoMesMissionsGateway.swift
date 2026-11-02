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

/// Mes missions du monde démo : fixtures embarquées, aucun réseau, horloge fixée. Mêmes filtres et
/// ordres que les requêtes du web (`MesMissionsPresentation.statuts*`), missions enrichies par
/// `MissionBusiness.enrich` comme Explorer. Refuse tout contexte qui n'est pas celui du profil fictif.
///
/// Point de fusion T6a/T6b : `candidaturesDeSession` rend les candidatures posées pendant la session
/// démo (actor de `DemoCandidatureGateway`) ; elles précèdent celles des fixtures, comme un `cree_le`
/// plus récent. Défaut : aucune.
public struct DemoMesMissionsGateway: MesMissionsPort {
    private let clock: any ClockPort
    private let candidaturesDeSession: @Sendable () async -> [CandidatureRecord]

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow),
                candidaturesDeSession: @escaping @Sendable () async -> [CandidatureRecord] = { [] }) {
        self.clock = clock
        self.candidaturesDeSession = candidaturesDeSession
    }

    public func candidatures(context: MissionReadContext) async throws -> [CandidatureRecord] {
        try check(context)
        let missions = try DemoFixtures.loadMissions().missions
        let etablissements = try chargerEtablissements()
        let lignes = await candidaturesDeSession() + (try DemoFixtures.loadMesMissions().candidatures)
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
        try check(context)
        let maintenant = clock.now()
        let etablissements = try chargerEtablissements()
        let missions = try DemoFixtures.loadDashboard().missionsAssignees
            .filter { MesMissionsPresentation.statutsAVenir.contains($0.record.statut) }
            .filter { Self.instant($0.record.finLe) >= maintenant } // `gte('fin_le', maintenant)`
            .sorted { Self.instant($0.record.debutLe) < Self.instant($1.record.debutLe) }
            .map { enrich($0, context: context, etablissements: etablissements) }
        return Self.page(missions, page: page)
    }

    public func passees(context: MissionReadContext, page: Int) async throws -> MissionsPage {
        try check(context)
        let etablissements = try chargerEtablissements()
        let passees = try DemoFixtures.loadMesMissions().passees
            .filter { MesMissionsPresentation.statutsPassees.contains($0.mission.record.statut) }
            .sorted { Self.instant($0.mission.record.debutLe) > Self.instant($1.mission.record.debutLe) }
        var lue = Self.page(passees.map { enrich($0.mission, context: context, etablissements: etablissements) }, page: page)
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

    /// Page `page` (0, 1, …) de `MissionsPage.taille` missions ; « page suivante » si celle-ci est pleine.
    static func page(_ missions: [Mission], page: Int) -> MissionsPage {
        let debut = max(0, page) * MissionsPage.taille
        guard debut < missions.count else { return MissionsPage(missions: [], page: page, aSuivre: false) }
        let tranche = Array(missions[debut..<min(debut + MissionsPage.taille, missions.count)])
        return MissionsPage(missions: tranche, page: page, aSuivre: tranche.count == MissionsPage.taille)
    }

    private func check(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
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
