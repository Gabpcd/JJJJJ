import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « recherches sauvegardées » (`Gateways.filtres`), câblée par L4-T4.
    static func filtres() -> FiltresSauvegardesPort { DemoFiltresGateway() }
}

extension DemoFixtures {
    /// `demo-filtres.json` (L4-T4, `scripts/mobile/demo-fixtures/filtres.mjs`) : deux recherches du compte démo, au
    /// format de `fn_lister_mes_filtres_sauvegardes` (une en alerte toutes les heures, une sans alerte).
    public struct FiltresFile: Decodable, Sendable {
        public var fixedNow: String
        public var filtresSauvegardes: ValeurJSON
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", filtresSauvegardes = "filtres_sauvegardes" }
    }

    public static func loadFiltres() throws -> FiltresFile { try load("demo-filtres") }
}

/// Recherches du compte démo : initialisées depuis la fixture au premier accès, en mémoire ensuite, perdues au
/// relancement, jamais envoyées. Ordre de lecture : `mis_a_jour_le` décroissant (trigger `trg_fs_updated_at`).
actor DemoFiltresStore {
    struct Ligne {
        var recherche: FiltreSauvegarde
        var misAJour: Int
    }

    private var lignes: [Ligne]?
    private var horloge = 0
    private var numero = 0

    var estInitialise: Bool { lignes != nil }

    func initialiser(_ recherches: [FiltreSauvegarde]) {
        guard lignes == nil else { return }
        // Fixture déjà triée comme la RPC : la première ligne est la plus récente.
        lignes = recherches.enumerated().map { Ligne(recherche: $0.element, misAJour: -$0.offset) }
    }

    func liste() -> [FiltreSauvegarde] {
        (lignes ?? []).sorted { $0.misAJour > $1.misAJour }.map(\.recherche)
    }

    func nombre() -> Int { lignes?.count ?? 0 }

    func contient(nom: String, sauf id: String? = nil) -> Bool {
        (lignes ?? []).contains { $0.recherche.nom == nom && $0.recherche.id != id }
    }

    func existe(_ id: String) -> Bool { (lignes ?? []).contains { $0.recherche.id == id } }

    func ajouter(nom: String, filtres: ValeurJSON, alerte: Bool, frequence: FrequenceAlerte, dernierCheck: String) {
        numero += 1
        horloge += 1
        lignes = (lignes ?? []) + [Ligne(recherche: FiltreSauvegarde(id: "demo-recherche-ajout-\(numero)", nom: nom,
                                                                     filtres: filtres, alerteActive: alerte,
                                                                     frequence: frequence, dernierCheckLe: dernierCheck),
                                         misAJour: horloge)]
    }

    func modifier(id: String, nom: String, alerte: Bool, frequence: FrequenceAlerte) {
        horloge += 1
        let maintenant = horloge
        lignes = (lignes ?? []).map { ligne in
            guard ligne.recherche.id == id else { return ligne }
            var modifiee = ligne
            modifiee.recherche.nom = nom
            modifiee.recherche.alerteActive = alerte
            modifiee.recherche.frequence = frequence
            modifiee.misAJour = maintenant
            return modifiee
        }
    }

    func supprimer(id: String) {
        lignes = (lignes ?? []).filter { $0.recherche.id != id }
    }
}

/// Recherches sauvegardées du monde démo (L4-T4) : aucun réseau, chaque mutation est consignée dans l'acteur puis
/// relue (aucun succès fabriqué). Mêmes refus que les RPC (`public.sql` l.26893-26954, l.43535-43603, l.60459-60483),
/// messages verbatim ; refuse tout contexte qui n'est pas celui du profil fictif.
public struct DemoFiltresGateway: FiltresSauvegardesPort {
    public static let nomInvalide = "Nom invalide (1-100 caractères)"
    public static let criteresInvalides = "Compte ou critères de recherche invalides."
    public static let limiteAtteinte = "Limite de 20 recherches sauvegardées atteinte. Supprimez-en une avant d'en créer une nouvelle."
    public static let nomEnDouble = "Un filtre avec ce nom existe déjà"
    public static let introuvable = "Filtre introuvable"

    private let store = DemoFiltresStore()
    private let clock: any ClockPort
    private let initiales: [FiltreSauvegarde]?

    /// `initiales` : recherches de départ (tests) ; `nil` = fixture `demo-filtres.json`.
    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), initiales: [FiltreSauvegarde]? = nil) {
        self.clock = clock
        self.initiales = initiales
    }

    public func lister(context: MissionReadContext) async throws -> [FiltreSauvegarde] {
        try check(context)
        try await initialiser()
        return await store.liste()
    }

    public func creer(nom: String, filtres: FiltresAlerte, alerte: Bool, frequence: FrequenceAlerte,
                      context: MissionReadContext) async throws -> IssueFiltre {
        try check(context)
        try await initialiser()
        guard Self.nomValide(nom) else { return .refusee(message: Self.nomInvalide) }
        let valeur = FiltresSauvegardesEncodage.valeur(filtres)
        guard FiltresSauvegardesEncodage.estValide(valeur) else { return .refusee(message: Self.criteresInvalides) }
        guard await store.nombre() < FiltresSauvegardesEncodage.nombreMax else { return .refusee(message: Self.limiteAtteinte) }
        guard await !store.contient(nom: nom) else { return .refusee(message: Self.nomEnDouble) }
        await store.ajouter(nom: nom, filtres: valeur, alerte: alerte, frequence: frequence,
                            dernierCheck: DateHeureParis.isoUTC(clock.now()))
        return .relue(try await lister(context: context))
    }

    public func modifier(id: String, nom: String, alerte: Bool, frequence: FrequenceAlerte,
                         context: MissionReadContext) async throws -> IssueFiltre {
        try check(context)
        try await initialiser()
        guard await store.existe(id) else { return .refusee(message: Self.introuvable) }
        guard Self.nomValide(nom) else { return .refusee(message: Self.nomInvalide) }
        if alerte, let ligne = await store.liste().first(where: { $0.id == id }),
           !FiltresSauvegardesEncodage.estValide(ligne.filtres) {
            return .refusee(message: Self.criteresInvalides)
        }
        guard await !store.contient(nom: nom, sauf: id) else { return .refusee(message: Self.nomEnDouble) }
        await store.modifier(id: id, nom: nom, alerte: alerte, frequence: frequence)
        return .relue(try await lister(context: context))
    }

    public func supprimer(id: String, context: MissionReadContext) async throws -> IssueFiltre {
        try check(context)
        try await initialiser()
        guard await store.existe(id) else { return .refusee(message: Self.introuvable) }
        await store.supprimer(id: id)
        return .relue(try await lister(context: context))
    }

    // MARK: - Interne

    /// `length(p_nom)` de PostgreSQL : caractères (points de code), 1 à 100.
    static func nomValide(_ nom: String) -> Bool {
        (1...FiltresSauvegardesEncodage.longueurNomMax).contains(nom.unicodeScalars.count)
    }

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
        guard let recherches = FiltresSauvegardesEncodage.liste(try DemoFixtures.loadFiltres().filtresSauvegardes) else {
            throw JoleneError(.contract, "Fixture démo illisible : demo-filtres.json.")
        }
        await store.initialiser(recherches)
    }
}
