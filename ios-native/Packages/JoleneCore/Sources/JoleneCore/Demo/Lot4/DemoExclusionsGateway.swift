import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « exclusions » (`Gateways.exclusions`), câblée par L4-T11.
    static func exclusions() -> ExclusionsPort { DemoExclusionsGateway() }
}

extension DemoFixtures {
    /// `demo-exclusions.json` (L4-T11, `scripts/mobile/demo-fixtures/exclusions.mjs`) : une exclusion envoyée (ligne
    /// PostgREST `exclusions`, nom de l'établissement dans `noms`, comme `fn_etablissements_safe`) et une exclusion reçue
    /// (format de `fn_mes_exclusions_recues`).
    public struct ExclusionsFile: Decodable, Sendable {
        public var fixedNow: String
        public var envoyees: [LigneExclusionEnvoyee]
        public var recues: [LigneExclusionRecue]
        public var noms: [String: String]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", envoyees, recues, noms }
    }

    public static func loadExclusions() throws -> ExclusionsFile { try load("demo-exclusions") }
}

/// Exclusions du monde démo (L4-T11) : initialisées depuis la fixture au premier accès, en mémoire ensuite, perdues au
/// relancement, jamais envoyées. Mêmes contrôles, même ordre et mêmes textes que `fn_exclure_utilisateur` (soi-même,
/// doublon) et `fn_retirer_exclusion` (introuvable) ; chaque mutation rend les exclusions envoyées relues. Noms des
/// établissements de la démo par `demo-etablissements.json`, puis `noms` de la fixture.
public actor DemoExclusionsGateway: ExclusionsPort {
    /// Textes serveur repris à l'identique (`supabase/schema/public.sql` l.36094-36138, l.55429-55463).
    public enum Textes {
        public static let soiMeme = "Impossible de s'exclure soi-même"
        public static let dejaExistante = "Exclusion déjà existante"
        public static let introuvable = "Exclusion introuvable"
    }

    private let clock: any ClockPort
    private let fichier: @Sendable () throws -> DemoFixtures.ExclusionsFile
    private var lignes: [LigneExclusionEnvoyee]?
    private var numero = 0

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow),
                fichier: @escaping @Sendable () throws -> DemoFixtures.ExclusionsFile = { try DemoFixtures.loadExclusions() }) {
        self.clock = clock
        self.fichier = fichier
    }

    public func envoyees(context: MissionReadContext) async throws -> [Exclusion] {
        try Self.verifier(context)
        let noms = try nomsConnus()
        return try courantes().sorted { ($0.creeLe ?? "") > ($1.creeLe ?? "") }.map { $0.exclusion(nom: noms[$0.excluId]) }
    }

    public func recues(context: MissionReadContext) async throws -> [Exclusion] {
        try Self.verifier(context)
        return try fichier().recues.map(\.exclusion)
    }

    public func retirer(excluId: String, context: MissionReadContext) async throws -> IssueExclusion {
        try Self.verifier(context)
        var actuelles = try courantes()
        guard actuelles.contains(where: { $0.excluId == excluId }) else { return .refusee(message: Textes.introuvable) }
        actuelles.removeAll { $0.excluId == excluId }
        lignes = actuelles
        return .relues(try await envoyees(context: context))
    }

    public func exclure(etablissementId: String, motif: String, context: MissionReadContext) async throws -> IssueExclusion {
        try Self.verifier(context)
        guard etablissementId != context.userId else { return .refusee(message: Textes.soiMeme) }
        var actuelles = try courantes()
        guard !actuelles.contains(where: { $0.excluId == etablissementId }) else { return .refusee(message: Textes.dejaExistante) }
        numero += 1
        actuelles.append(LigneExclusionEnvoyee(id: "demo-exclusion-session-\(numero)", excluId: etablissementId,
                                               excluPar: context.userId, motif: ExclusionsRegles.motifEnvoye(motif),
                                               typeExcluPar: ExclusionsRegles.typeAuteur,
                                               creeLe: DateHeureParis.isoUTC(clock.now().addingTimeInterval(Double(numero)))))
        lignes = actuelles
        return .relues(try await envoyees(context: context))
    }

    private func courantes() throws -> [LigneExclusionEnvoyee] {
        if let lignes { return lignes }
        let initiales = try fichier().envoyees
        lignes = initiales
        return initiales
    }

    private func nomsConnus() throws -> [String: String] {
        var noms = try fichier().noms
        for etablissement in (try? DemoFixtures.loadEtablissements().etablissements) ?? [] { noms[etablissement.id] = etablissement.nom }
        return noms
    }

    private static func verifier(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}
