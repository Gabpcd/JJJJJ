import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « score » (`Gateways.score`), câblée par L4-T9.
    static func score() -> ScorePort { DemoScoreGateway() }
}

extension DemoFixtures {
    /// `demo-score.json` (L4-T9, `scripts/mobile/demo-fixtures/score.mjs`), aux formats du serveur : ligne
    /// `scoring_breakdown`, colonnes du profil, tableau de `fn_evolution_score_soignant`, réponse de
    /// `fn_mes_evenements_score` (sous la clé `events`).
    public struct ScoreFile: Decodable, Sendable {
        public var fixedNow: String
        public var breakdown: ValeurJSON
        public var soignant: ValeurJSON
        public var evolution: ValeurJSON
        public var evenements: ValeurJSON
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", breakdown, soignant, evolution, evenements }
    }

    public static func loadScore() throws -> ScoreFile { try load("demo-score") }
}

/// Réclamations du compte démo : en mémoire, perdues au relancement, jamais envoyées.
actor DemoScoreStore {
    private var reclamations: [String: String] = [:]

    func reclamation(_ evenementId: String) -> String? { reclamations[evenementId] }
    func contestes() -> Set<String> { Set(reclamations.keys) }

    func ouvrir(_ evenementId: String) -> String {
        let id = "demo-reclamation-\(reclamations.count + 1)"
        reclamations[evenementId] = id
        return id
    }
}

/// « Mon score » du monde démo (L4-T9) : aucun réseau, fixtures lues par les décodeurs des gateways (`ScoreDecodage`).
/// Joue `fn_creer_reclamation_score` : mêmes contrôles et mêmes messages que `public.sql` (motif, texte de vingt
/// caractères, événement introuvable, non contestable, déjà traité, réclamation en cours) ; un événement contesté est
/// ensuite servi `contestable: false`, comme le calcule `fn_mes_evenements_score`. Les notations reçues sont celles de
/// `demo-evaluations.json`, servies sans `signale` (comme `fn_lister_notations_recues`). Refuse tout contexte qui n'est
/// pas celui du profil fictif.
public struct DemoScoreGateway: ScorePort {
    public static let motifInvalide = "Motif catégorie invalide"
    public static let texteRequis = "Texte libre obligatoire (min 20 caractères)"
    public static let introuvable = "Événement de score introuvable"
    public static let nonContestable = "Cet événement n'est pas contestable"
    public static let dejaTraite = "Cet événement a déjà été traité par un admin"
    public static let reclamationEnCours = "Une réclamation est déjà ouverte pour cet événement"

    private let store = DemoScoreStore()

    public init() {}

    public func breakdown(context: MissionReadContext) async throws -> BreakdownScore {
        try check(context)
        let fichier = try DemoFixtures.loadScore()
        guard let breakdown = ScoreDecodage.breakdown(calcul: fichier.breakdown, profil: fichier.soignant) else { throw Self.illisible }
        return breakdown
    }

    public func evolution(mois: Int, context: MissionReadContext) async throws -> [PointEvolutionScore] {
        try check(context)
        guard let points = ScoreDecodage.evolution(try DemoFixtures.loadScore().evolution) else { throw Self.illisible }
        return Array(points.suffix(max(1, mois)))
    }

    public func evenements(limite: Int, context: MissionReadContext) async throws -> [EvenementScore] {
        try check(context)
        let contestes = await store.contestes()
        return try lus().prefix(max(0, limite)).map { evenement in
            var servi = evenement
            if contestes.contains(evenement.id) { servi.contestable = false }
            return servi
        }
    }

    public func notationsRecues(limite: Int, context: MissionReadContext) async throws -> [NotationRecue] {
        try check(context)
        // Le `LIMIT` de la RPC n'a pas d'effet (appliqué après `jsonb_agg`) : la liste entière, que l'app tronque.
        return try DemoFixtures.pageEvaluations().notations.map { notation in
            var servie = notation
            servie.signale = nil
            servie.etablissementId = nil
            servie.etablissementNom = nil
            return servie
        }
    }

    public func contester(evenementId: String, motif: String, texte: String,
                          context: MissionReadContext) async throws -> ReclamationScoreOutcome {
        try check(context)
        guard MotifContestationScore(rawValue: motif) != nil else {
            return .refusee(code: "MOTIF_INVALIDE", message: Self.motifInvalide)
        }
        guard texte.trimmingCharacters(in: .whitespacesAndNewlines).count >= ScorePresentation.longueurTexteMin else {
            return .refusee(code: "TEXTE_REQUIS", message: Self.texteRequis)
        }
        guard let evenement = try lus().first(where: { $0.id == evenementId }) else {
            return .refusee(code: "EVENT_INTROUVABLE", message: Self.introuvable)
        }
        // Ordre du serveur : `contestable` de la ligne, décision de l'admin, réclamation en cours. La fixture ne sert
        // que la valeur calculée : un événement décidé est rendu « déjà traité », les autres « non contestable ».
        if await store.reclamation(evenementId) != nil {
            return .refusee(code: "RECLAMATION_EN_COURS", message: Self.reclamationEnCours)
        }
        if !(evenement.decisionAdmin ?? "").isEmpty { return .refusee(code: "DEJA_TRAITE", message: Self.dejaTraite) }
        guard evenement.contestable else { return .refusee(code: "NON_CONTESTABLE", message: Self.nonContestable) }
        return .enregistree(reclamationId: await store.ouvrir(evenementId))
    }

    // MARK: - Interne

    private static let illisible = JoleneError(.contract, "Fixture démo illisible : demo-score.json.")

    private func lus() throws -> [EvenementScore] {
        guard let evenements = ScoreDecodage.evenements(try DemoFixtures.loadScore().evenements) else { throw Self.illisible }
        return evenements
    }

    private func check(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}
