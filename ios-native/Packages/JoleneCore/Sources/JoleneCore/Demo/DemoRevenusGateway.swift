import Foundation

extension DemoFixtures {
    /// `demo-revenus.json` : exercice du profil fictif (`soignants.type_exercice, statut_liberal`) et réponse de
    /// `fn_mes_revenus_connect()` (lot 3, T12).
    public struct RevenusFile: Decodable, Sendable {
        public var fixedNow: String
        public var exercice: ExerciceRevenus
        public var totaux: ValeurJSON
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", exercice, totaux }
    }

    /// `demo-escrow.json` : réponse de `fn_mes_paiements_escrow()` (les sept états, ordre serveur).
    public struct EscrowFile: Decodable, Sendable {
        public var fixedNow: String
        public var paiements: ValeurJSON
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", paiements }
    }

    /// `demo-missions-terminees.json` : lignes `missions` TERMINEE du profil fictif (toutes leurs colonnes, dont les
    /// colonnes Rist de la mission témoin, que le décodeur des colonnes de `MesGains.tsx` l.95 ignore) et lignes
    /// `paiements_soignant` (colonnes de l.102).
    public struct MissionsTermineesFile: Decodable, Sendable {
        public var fixedNow: String
        public var missions: [MissionTerminee]
        public var paiements: [PaiementSoignantLu]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", missions, paiements }
    }

    public static func loadRevenus() throws -> RevenusFile { try load("demo-revenus") }
    public static func loadEscrow() throws -> EscrowFile { try load("demo-escrow") }
    public static func loadMissionsTerminees() throws -> MissionsTermineesFile { try load("demo-missions-terminees") }
}

/// `RevenusPort` du monde démo (lot 3, T12), sans réseau : fixtures exportées par `scripts/mobile/export-demo-fixtures.mjs`
/// lues par les MÊMES décodeurs que le monde Supabase (`TotauxRevenus.lire`, `PaiementRapide.lireListe`,
/// `RevenusAssemblage`), même visibilité des totaux (`ExerciceRevenus.afficheTotaux`), même tri (`debut_le`
/// décroissant) et mêmes pages de 50. Noms d'établissement : `demo-etablissements.json` (rôle de
/// `fn_etablissements_safe`). Refuse tout contexte qui n'est pas celui du profil fictif (`.demoOnly`).
public struct DemoRevenusGateway: RevenusPort {
    public init() {}

    public func totaux(context: MissionReadContext) async throws -> TotauxRevenus? {
        try Self.verifier(context)
        let fichier = try DemoFixtures.loadRevenus()
        guard fichier.exercice.afficheTotaux else { return nil }
        guard let totaux = TotauxRevenus.lire(fichier.totaux) else {
            throw JoleneError(.unknown, RevenusTextes.totauxIndisponibles)
        }
        return totaux
    }

    public func paiementsRapides(context: MissionReadContext) async throws -> [PaiementRapide] {
        try Self.verifier(context)
        return try PaiementRapide.lireListe(try DemoFixtures.loadEscrow().paiements)
    }

    public func missionsTerminees(context: MissionReadContext, page: Int) async throws -> PageMissionsTerminees {
        try Self.verifier(context)
        guard page >= 0 else { throw JoleneError(.contract, RevenusLecture.contratMessage) }
        let fichier = try DemoFixtures.loadMissionsTerminees()
        // `.order('debut_le', { ascending: false })` : NULLS FIRST (défaut Postgres d'un DESC), puis identifiant.
        let triees = fichier.missions.sorted { a, b in
            switch (a.debutLe, b.debutLe) {
            case (nil, nil): return a.id < b.id
            case (nil, _): return true
            case (_, nil): return false
            case let (x?, y?):
                let ix = (try? DateHeureParis.instantJolene(x)) ?? .distantPast
                let iy = (try? DateHeureParis.instantJolene(y)) ?? .distantPast
                return ix == iy ? a.id < b.id : ix > iy
            }
        }
        let debut = page * RevenusAssemblage.taillePage
        let tranche = debut < triees.count ? Array(triees[debut..<min(debut + RevenusAssemblage.taillePage, triees.count)]) : []
        let noms = Dictionary(try DemoFixtures.loadEtablissements().etablissements.map { ($0.id, $0.nom) },
                              uniquingKeysWith: { premier, _ in premier })
        return RevenusAssemblage.page(tranche, paiements: fichier.paiements, etablissements: noms, page: page)
    }

    static func verifier(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}

/// Variante de recette DEBUG `JOLENE_FORCE_REVENUS_ECHEC=1` (`DemoRevenusTests.testErreurPuisReprise`) : la première
/// lecture des missions échoue (délai dépassé simulé), les suivantes et les autres sections sont celles du monde démo.
public actor DemoRevenusEchecGateway: RevenusPort {
    public static let variableEnvironnement = "JOLENE_FORCE_REVENUS_ECHEC"

    private let relais = DemoRevenusGateway()
    private var echecsRestants: Int

    public init(echecs: Int = 1) {
        echecsRestants = max(0, echecs)
    }

    public func totaux(context: MissionReadContext) async throws -> TotauxRevenus? {
        try await relais.totaux(context: context)
    }

    public func paiementsRapides(context: MissionReadContext) async throws -> [PaiementRapide] {
        try await relais.paiementsRapides(context: context)
    }

    public func missionsTerminees(context: MissionReadContext, page: Int) async throws -> PageMissionsTerminees {
        try DemoRevenusGateway.verifier(context)
        try Task.checkCancellation()
        if echecsRestants > 0 {
            echecsRestants -= 1
            throw JoleneError(.network, SessionController.timeoutMessage)
        }
        return try await relais.missionsTerminees(context: context, page: page)
    }
}
