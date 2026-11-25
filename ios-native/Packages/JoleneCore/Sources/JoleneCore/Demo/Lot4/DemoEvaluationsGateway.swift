import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « évaluations reçues » (`Gateways.evaluationsRecues`), câblée par L4-T9.
    static func evaluationsRecues() -> EvaluationsPort { DemoEvaluationsGateway() }
}

extension DemoFixtures {
    /// `demo-evaluations.json` (L4-T9, `scripts/mobile/demo-fixtures/evaluations.mjs`) : réponse de
    /// `fn_mes_notations_recues_avec_stats` du compte démo, sans filtre — quatre notations publiées, statistiques,
    /// évolution et établissements calculés par l'exporteur (qui joue le serveur).
    public struct EvaluationsFile: Decodable, Sendable {
        public var fixedNow: String
        public var reponse: ValeurJSON
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", reponse }
    }

    public static func loadEvaluations() throws -> EvaluationsFile { try load("demo-evaluations") }

    /// Page de la fixture, lue par le décodeur des gateways (`EvaluationsDecodage.page`).
    static func pageEvaluations() throws -> PageEvaluations {
        guard let page = EvaluationsDecodage.page(try loadEvaluations().reponse) else {
            throw JoleneError(.contract, "Fixture démo illisible : demo-evaluations.json.")
        }
        return page
    }
}

/// Signalements du compte démo : en mémoire, perdus au relancement, jamais envoyés.
actor DemoEvaluationsStore {
    private var signalees: Set<String> = []

    func estSignalee(_ id: String) -> Bool { signalees.contains(id) }
    func signaler(_ id: String) { signalees.insert(id) }
    func toutes() -> Set<String> { signalees }
}

/// Évaluations reçues du monde démo (L4-T9) : aucun réseau. Joue `fn_mes_notations_recues_avec_stats` sur la fixture —
/// filtres de période, de note minimale et d'établissement, pages de `p_limit`, `total` filtré — et
/// `fn_signaler_notation` (refus verbatim de `public.sql`). Les statistiques, l'évolution et la liste des
/// établissements sont celles de la fixture, **jamais recalculées** : comme la RPC, elles ne dépendent d'aucun filtre.
/// Refuse tout contexte qui n'est pas celui du profil fictif.
public struct DemoEvaluationsGateway: EvaluationsPort {
    public static let nonConcerne = "Vous ne pouvez signaler que les notations vous concernant"
    public static let dejaSignalee = "Notation déjà signalée"

    private let store = DemoEvaluationsStore()
    private let clock: any ClockPort
    private let initiale: PageEvaluations?

    /// `initiale` : page de départ (tests) ; `nil` = fixture `demo-evaluations.json`.
    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), initiale: PageEvaluations? = nil) {
        self.clock = clock
        self.initiale = initiale
    }

    public func recues(filtre: FiltreEvaluations, page: Int, context: MissionReadContext) async throws -> PageEvaluations {
        try check(context)
        var base = try initiale ?? DemoFixtures.pageEvaluations()
        let signalees = await store.toutes()
        let seuil = Self.seuil(filtre.periode, maintenant: clock.now())
        let filtrees = base.notations.filter { notation in
            if let seuil {
                guard let cree = notation.creeLe.flatMap({ try? DateHeureParis.instantJolene($0) }), cree > seuil else { return false }
            }
            if let noteMin = filtre.noteMin {
                guard let note = notation.noteMoyenne, note >= Double(noteMin) else { return false }
            }
            if let etablissement = filtre.etablissementId, notation.etablissementId != etablissement { return false }
            return true
        }
        let debut = min(max(0, page) * EvaluationsDecodage.parPage, filtrees.count)
        let fin = min(debut + EvaluationsDecodage.parPage, filtrees.count)
        base.total = filtrees.count
        base.notations = filtrees[debut..<fin].map { notation in
            var servie = notation
            if signalees.contains(notation.id) { servie.signale = true }
            return servie
        }
        return base
    }

    public func signaler(notationId: String, motif: String, context: MissionReadContext) async throws -> IssueSignalement {
        try check(context)
        let base = try initiale ?? DemoFixtures.pageEvaluations()
        guard let notation = base.notations.first(where: { $0.id == notationId }) else { return .refuse(message: Self.nonConcerne) }
        if notation.signale == true { return .refuse(message: Self.dejaSignalee) }
        if await store.estSignalee(notationId) { return .refuse(message: Self.dejaSignalee) }
        await store.signaler(notationId)
        return .signale
    }

    // MARK: - Interne

    /// `now() - INTERVAL 'n months'` de la RPC ; `nil` pour « Toutes périodes ».
    static func seuil(_ periode: PeriodeEvaluations, maintenant: Date) -> Date? {
        let mois: Int
        switch periode {
        case .tout: return nil
        case .troisMois: mois = 3
        case .sixMois: mois = 6
        case .douzeMois: mois = 12
        }
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "UTC") ?? calendrier.timeZone
        return calendrier.date(byAdding: .month, value: -mois, to: maintenant)
    }

    private func check(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}
