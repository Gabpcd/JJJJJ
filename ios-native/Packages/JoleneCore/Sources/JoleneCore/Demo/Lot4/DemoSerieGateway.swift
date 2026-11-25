import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « série » (`Gateways.serie`), T12 : la gateway démo lit les missions du même monde
    /// (`MissionsPort`, attributions de session comprises) et accepte par la candidature du même monde
    /// (`CandidaturePort.confirmer(.accepter)`, lot 1), si bien qu'une mission acceptée dans la série est servie
    /// attribuée partout (détail, Mes missions, Explorer).
    static func serie(_ gateways: Gateways) -> SeriePort {
        DemoSerieGateway(missions: gateways.missions, candidature: gateways.candidature)
    }
}

extension DemoFixtures {
    /// `demo-serie.json` (`scripts/mobile/demo-fixtures/serie.mjs`) : séries démo, chacune une liste ordonnée de
    /// missions du monde démo (`demo-missions.json`, `demo-dashboard.json`) et, pour certaines, la réponse scriptée du
    /// serveur à leur acceptation.
    public struct SerieFile: Decodable, Sendable {
        public struct Serie: Decodable, Equatable, Sendable {
            public var serieId: String
            public var missions: [Ligne]
            enum CodingKeys: String, CodingKey { case serieId = "serie_id", missions }
        }

        public struct Ligne: Decodable, Equatable, Sendable {
            public var missionId: String
            /// Corps que rendrait `fn_confirmer_action_planning_v1` (ou le transport, pour l'exception d'un trigger) ;
            /// absent : acceptation par la candidature du monde démo.
            public var reponse: Reponse?
            enum CodingKeys: String, CodingKey { case missionId = "mission_id", reponse }
        }

        /// Refus scripté, mêmes clés que le corps jsonb du serveur (`code`, `error`, `choix_requis`, `options`).
        public struct Reponse: Decodable, Equatable, Sendable {
            public var code: String?
            public var error: String?
            public var choixRequis: Bool?
            public var options: [ChoixContratOption]?
            enum CodingKeys: String, CodingKey { case code, error, options, choixRequis = "choix_requis" }
        }

        public var fixedNow: String
        public var series: [Serie]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", series }
    }

    public static func loadSerie() throws -> SerieFile { try load("demo-serie") }
}

/// Série du monde démo (lot 4, T12 ; `LOT4_PLAN.md` §2.7) : aucun réseau, horloge fixée, état en mémoire du monde démo.
/// - Lecture : missions de la série dans l'ordre `debut_le` croissant, relues par le port des missions du monde (une
///   mission acceptée pendant la session est servie attribuée au profil fictif) ; série inconnue → `[]`.
/// - Acceptation : mêmes contrôles et même ordre que `fn_confirmer_action_planning_v1` (mission ouverte, planning
///   confirmé identique au planning servi), puis la réponse scriptée de `demo-serie.json` si la mission en a une
///   (conflit de planning, choix de contrat requis, refus d'un trigger de conformité tel que le transport le restitue),
///   sinon l'acceptation du monde démo (`DemoCandidatureGateway`, relue). Les textes de refus viennent de la fixture,
///   au format du serveur : aucun n'est écrit ici.
/// Refuse tout contexte qui n'est pas celui du profil fictif (`.demoOnly`).
public struct DemoSerieGateway: SeriePort {
    private let missions: any MissionsPort
    private let candidature: any CandidaturePort
    private let series: @Sendable () throws -> [DemoFixtures.SerieFile.Serie]

    public init(missions: any MissionsPort, candidature: any CandidaturePort,
                series: @escaping @Sendable () throws -> [DemoFixtures.SerieFile.Serie] = { try DemoFixtures.loadSerie().series }) {
        self.missions = missions
        self.candidature = candidature
        self.series = series
    }

    public func missions(serieId: String, context: MissionReadContext) async throws -> [Mission] {
        try Self.verifier(context)
        guard let serie = try series().first(where: { $0.serieId == serieId }) else { return [] }
        var lues: [Mission] = []
        for ligne in serie.missions {
            if let mission = try await missions.mission(id: ligne.missionId, context: context) { lues.append(mission) }
        }
        // Ordre du serveur (`order('debut_le', { ascending: true })`), départagé par la position dans la série.
        return lues.enumerated().sorted { a, b in
            let debutA = PlanningHorlogeParis.instant(a.element.record.debutLe) ?? .distantFuture
            let debutB = PlanningHorlogeParis.instant(b.element.record.debutLe) ?? .distantFuture
            return debutA != debutB ? debutA < debutB : a.offset < b.offset
        }.map(\.element)
    }

    public func accepter(missionId: String, creneaux: [CreneauConfirmePayload],
                         context: MissionReadContext) async throws -> CandidatureOutcome {
        try Self.verifier(context)
        guard let ligne = try series().flatMap(\.missions).first(where: { $0.missionId == missionId }),
              let reponse = ligne.reponse else {
            // Mission sans réponse scriptée (ou hors série) : acceptation du monde démo, mêmes contrôles que le serveur.
            return try await candidature.confirmer(action: .accepter, missionId: missionId, creneaux: creneaux, message: nil,
                                                   choixContrat: nil, candidatureId: nil, context: context)
        }
        guard let mission = try await missions.mission(id: missionId, context: context),
              mission.record.statut == SerieRegles.statutOuverte else {
            return .missionDejaAttribuee(message: DemoCandidatureGateway.Textes.missionIndisponible)
        }
        let attendus = CreneauxConfirmes.pourAction(PlanningCandidatInput(mission: mission))
        guard let attendus, !attendus.isEmpty, attendus.count == creneaux.count, Set(attendus) == Set(creneaux) else {
            return .planningAReconfirmer(code: DemoCandidatureGateway.codePlanningModifie,
                                         message: DemoCandidatureGateway.Textes.planningModifie)
        }
        if reponse.choixRequis == true {
            return .choixRequis(reponse.options ?? DemoCandidatureGateway.Textes.choixContrat)
        }
        guard let message = reponse.error, !message.isEmpty else {
            throw JoleneError(.contract, "Fixture démo illisible : demo-serie.json.")
        }
        return .refusee(code: reponse.code, message: message, documentsRequisPour: nil)
    }

    private static func verifier(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}
