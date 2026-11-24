import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « parrainage » (`Gateways.parrainage`), câblée par L4-T6.
    static func parrainage() -> ParrainagePort { DemoParrainageGateway() }
}

extension DemoFixtures {
    /// `demo-parrainage.json` (L4-T6, `scripts/mobile/demo-fixtures/parrainage.mjs`) : ligne `soignants` du compte démo,
    /// réponse de `fn_obtenir_mes_parrainages` (trois filleuls, sans parrain) et codes de parrains fictifs acceptés.
    public struct ParrainageFile: Decodable, Sendable {
        public var fixedNow: String
        public var soignant: ValeurJSON
        public var mesParrainages: ValeurJSON
        public var parrains: [String: String]
        enum CodingKeys: String, CodingKey {
            case fixedNow = "fixed_now", soignant, mesParrainages = "mes_parrainages", parrains
        }
    }

    public static func loadParrainage() throws -> ParrainageFile { try load("demo-parrainage") }
}

/// Parrainage du compte démo (L4-T6) : aucun réseau ; l'application d'un code est consignée dans l'acteur puis relue,
/// comme sur Supabase (aucun succès fabriqué). Mêmes refus que `fn_appliquer_parrainage` (`public.sql`), messages
/// verbatim, sur une liste fermée de parrains fictifs (`parrains` : code → prénom). Le message serveur de succès n'existe
/// pas ici : il n'est jamais affiché. Refuse tout contexte qui n'est pas celui du profil fictif.
public struct DemoParrainageGateway: ParrainagePort {
    public static let codeInvalide = "Code de parrainage invalide"
    public static let soiMeme = "Vous ne pouvez pas vous parrainer vous-même"
    public static let dejaApplique = "Vous avez déjà appliqué un code de parrainage"

    private let store = Store()

    public init() {}

    actor Store {
        var monParrain: ValeurJSON?
        func poser(_ valeur: ValeurJSON) { monParrain = valeur }
    }

    public func etat(context: MissionReadContext) async throws -> EtatParrainage {
        try check(context)
        let fixture = try DemoFixtures.loadParrainage()
        var reponse = fixture.mesParrainages
        if let parrain = await store.monParrain, case var .objet(objet) = reponse {
            objet["mon_parrain"] = parrain
            reponse = .objet(objet)
        }
        guard let etat = ParrainageDecodage.etat(profil: fixture.soignant, reponse: reponse) else {
            throw JoleneError(.contract, "Fixture démo illisible : demo-parrainage.json.")
        }
        return etat
    }

    public func appliquer(code: String, context: MissionReadContext) async throws -> ApplicationParrainage {
        try check(context)
        guard let normalise = ParrainageCapture.normaliser(code) else {
            throw JoleneError(.contract, "Code de parrainage hors forme : jamais envoyé.")
        }
        let fixture = try DemoFixtures.loadParrainage()
        // Ordre de la RPC : code inconnu, soi-même, déjà appliqué.
        let propre = ParrainageDecodage.etat(profil: fixture.soignant, reponse: fixture.mesParrainages)?.code
        guard normalise == propre || fixture.parrains[normalise] != nil else { return .refusDefinitif(message: Self.codeInvalide) }
        guard normalise != propre else { return .refusDefinitif(message: Self.soiMeme) }
        guard await store.monParrain == nil else { return .refusDefinitif(message: Self.dejaApplique) }
        await store.poser(.objet(["parrain_prenom": .chaine(fixture.parrains[normalise] ?? ""), "statut": .chaine("EN_ATTENTE"),
                                  "prime_versee_le": .null]))
        // Relecture, comme la gateway Supabase : le succès n'est rendu que si `mon_parrain` est posé.
        return try await etat(context: context).monParrain == nil ? .aReessayer : .appliquee
    }

    private func check(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}
