import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « disponibilités » (`Gateways.disponibilites`), câblée par L4-T5.
    static func disponibilites() -> DisponibilitesPort { DemoDisponibilitesGateway() }
}

extension DemoFixtures {
    /// `demo-disponibilites.json` (L4-T5, `scripts/mobile/demo-fixtures/disponibilites.mjs`) : trois créneaux posés par
    /// le compte démo, au format des lignes PostgREST de `disponibilites_soignant` (`select=jour,creneau`).
    public struct DisponibilitesFile: Decodable, Sendable {
        public var fixedNow: String
        public var disponibilites: [LigneDisponibilite]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", disponibilites = "disponibilites_soignant" }
    }

    public static func loadDisponibilites() throws -> DisponibilitesFile { try load("demo-disponibilites") }
}

/// Créneaux du compte démo : initialisés depuis la fixture au premier accès, en mémoire ensuite, perdus au relancement,
/// jamais envoyés.
actor DemoDisponibilitesStore {
    private var cles: Set<DispoCle>?

    var estInitialise: Bool { cles != nil }

    func initialiser(_ initiales: Set<DispoCle>) {
        guard cles == nil else { return }
        cles = initiales
    }

    /// `jour >= depuis`, comme la lecture du web.
    func depuis(_ jour: JourParis) -> Set<DispoCle> { (cles ?? []).filter { $0.jour >= jour } }

    func dans(_ jours: ClosedRange<JourParis>) -> Set<DispoCle> { (cles ?? []).filter { jours.contains($0.jour) } }

    /// `INSERT … ON CONFLICT DO NOTHING` ou `DELETE` : idempotent.
    func definir(_ cle: DispoCle, disponible: Bool) {
        var courantes = cles ?? []
        if disponible { courantes.insert(cle) } else { courantes.remove(cle) }
        cles = courantes
    }
}

/// Disponibilités du monde démo (L4-T5) : aucun réseau, chaque bascule est consignée dans l'acteur puis la semaine est
/// relue (aucun succès fabriqué). Mêmes bornes et même refus que `fn_definir_disponibilite` (`supabase/schema/public.sql`),
/// message verbatim ; refuse tout contexte qui n'est pas celui du profil fictif.
public struct DemoDisponibilitesGateway: DisponibilitesPort {
    /// `CURRENT_DATE + 90` de la RPC.
    public static let joursMax = 90
    static let jourIllisible = "Jour de disponibilité illisible."

    private let store = DemoDisponibilitesStore()
    private let clock: any ClockPort
    private let initiales: Set<DispoCle>?

    /// `initiales` : créneaux de départ (tests) ; `nil` = fixture `demo-disponibilites.json`.
    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), initiales: Set<DispoCle>? = nil) {
        self.clock = clock
        self.initiales = initiales
    }

    public func lister(depuis: JourParis, context: MissionReadContext) async throws -> Set<DispoCle> {
        try check(context)
        guard depuis.estValide else { throw JoleneError(.contract, Self.jourIllisible) }
        try await initialiser()
        return await store.depuis(depuis)
    }

    public func definir(jour: JourParis, creneau: CreneauDispo, disponible: Bool,
                        context: MissionReadContext) async throws -> IssueDisponibilite {
        try check(context)
        guard let semaine = jour.semaine else { throw JoleneError(.contract, Self.jourIllisible) }
        try await initialiser()
        // `p_jour < CURRENT_DATE OR p_jour > CURRENT_DATE + 90` : la date du serveur fait foi, pas le jour Paris de
        // l'appareil. Le monde démo prend le jour UTC de son horloge (fuseau par défaut d'une session Supabase ; celui de
        // la base réelle n'a pas été relu).
        let aujourdhui = JourParis(iso: String(DateHeureParis.isoUTC(clock.now()).prefix(10)))
        guard let limite = aujourdhui.decale(de: Self.joursMax), jour >= aujourdhui, jour <= limite else {
            return .refusee(message: DisponibilitesTextes.horsFenetre)
        }
        await store.definir(DispoCle(jour: jour, creneau: creneau), disponible: disponible)
        return .relue(await store.dans(semaine))
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
        if let initiales {
            await store.initialiser(initiales)
            return
        }
        guard let cles = DisponibilitesLecture.cles(try DemoFixtures.loadDisponibilites().disponibilites) else {
            throw JoleneError(.contract, "Fixture démo illisible : demo-disponibilites.json.")
        }
        await store.initialiser(cles)
    }
}
