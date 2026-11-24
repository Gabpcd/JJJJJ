import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « réclamations » (`Gateways.reclamations`), câblée par L4-T8.
    static func reclamations() -> ReclamationsPort { DemoReclamationsGateway() }
}

extension DemoFixtures {
    /// `demo-reclamations.json` (L4-T8, `scripts/mobile/demo-fixtures/reclamations.mjs`) : réclamations du compte démo,
    /// aux colonnes lues par le web (`MesReclamations.tsx` l.78), `cree_le` décroissant.
    public struct ReclamationsFile: Decodable, Sendable {
        public var fixedNow: String
        public var reclamations: [Reclamation]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", reclamations }
    }

    public static func loadReclamations() throws -> ReclamationsFile { try load("demo-reclamations") }
}

/// Réclamations du compte démo : fixture au premier accès, en mémoire ensuite, perdues au relancement.
actor DemoReclamationsStore {
    private var lignes: [(ligne: Reclamation, ordre: Int)]?
    private var compteur = 0

    var estInitialise: Bool { lignes != nil }

    func initialiser(_ reclamations: [Reclamation]) {
        guard lignes == nil else { return }
        lignes = reclamations.enumerated().map { ($0.element, -$0.offset) }
    }

    /// `order=cree_le.desc` ; à date égale, la ligne posée en dernier d'abord.
    func liste() -> [Reclamation] {
        (lignes ?? []).sorted { a, b in
            let da = a.ligne.creeLe ?? "", db = b.ligne.creeLe ?? ""
            return da == db ? a.ordre > b.ordre : da > db
        }.map(\.ligne)
    }

    func ajouter(_ fabrique: @Sendable (Int) -> Reclamation) -> Reclamation {
        compteur += 1
        let ligne = fabrique(compteur)
        lignes = (lignes ?? []) + [(ligne, compteur)]
        return ligne
    }
}

/// Réclamations générales du monde démo (L4-T8) : aucun réseau, la réclamation soumise est consignée dans l'acteur puis
/// relue par son identifiant (aucun succès fabriqué), au statut `EN_ATTENTE` que pose `fn_soumettre_reclamation`. Le
/// profil fictif est un soignant : le refus « Rôle non autorisé » n'y est pas atteignable. Refuse tout autre contexte.
public struct DemoReclamationsGateway: ReclamationsPort {
    private let store = DemoReclamationsStore()
    private let clock: any ClockPort
    private let initiales: [Reclamation]?

    /// `initiales` : réclamations de départ (tests) ; `nil` = fixture `demo-reclamations.json`.
    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), initiales: [Reclamation]? = nil) {
        self.clock = clock
        self.initiales = initiales
    }

    public func lister(context: MissionReadContext) async throws -> [Reclamation] {
        try check(context)
        try await initialiser()
        return await store.liste()
    }

    public func soumettre(categorie: CategorieReclamation, sujet: String, details: String,
                          context: MissionReadContext) async throws -> IssueReclamation {
        try check(context)
        try await initialiser()
        let maintenant = DateHeureParis.isoUTC(clock.now())
        let creee = await store.ajouter { numero in
            Reclamation(id: "demo-reclamation-ajout-\(numero)", categorie: categorie.rawValue, sujet: sujet, details: details,
                        statut: "EN_ATTENTE", creeLe: maintenant)
        }
        guard let relue = await store.liste().first(where: { $0.id == creee.id }) else {
            throw JoleneError(.contract, "Réclamation démo introuvable après son envoi.")
        }
        return .soumise(relue)
    }

    // MARK: - Interne

    private func check(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }

    private func initialiser() async throws {
        guard await !store.estInitialise else { return }
        await store.initialiser(try initiales ?? DemoFixtures.loadReclamations().reclamations)
    }
}
