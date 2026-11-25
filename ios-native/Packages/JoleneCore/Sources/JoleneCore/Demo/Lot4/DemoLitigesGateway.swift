import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « litiges » (`Gateways.litiges`), câblée par L4-T8.
    static func litiges() -> LitigesPort { DemoLitigesGateway() }
}

extension DemoFixtures {
    /// `demo-litiges.json` (L4-T8, `scripts/mobile/demo-fixtures/litiges.mjs`) : trois litiges du compte démo, au
    /// format de la lecture PostgREST (`litiges` par colonnes explicites, mission jointe), `cree_le` décroissant.
    public struct LitigesFile: Decodable, Sendable {
        public var fixedNow: String
        public var litiges: [Litige]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", litiges }
    }

    /// `demo-litige-fil.json` : messages des litiges démo (`messages_litige`), ordre chronologique.
    public struct LitigeFilFile: Decodable, Sendable {
        public var fixedNow: String
        public var messages: [MessageLitige]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", messages }
    }

    public static func loadLitiges() throws -> LitigesFile { try load("demo-litiges") }
    public static func loadLitigeFil() throws -> LitigeFilFile { try load("demo-litige-fil") }
}

/// Litiges du compte démo : initialisés depuis les fixtures au premier accès, en mémoire ensuite, perdus au
/// relancement, jamais envoyés.
actor DemoLitigesStore {
    private var litiges: [(ligne: Litige, ordre: Int)]?
    private var messages: [(ligne: MessageLitige, ordre: Int)] = []
    private var compteur = 0

    var estInitialise: Bool { litiges != nil }

    func initialiser(litiges lignes: [Litige], messages fil: [MessageLitige]) {
        guard litiges == nil else { return }
        // Fixture déjà triée comme la lecture (`cree_le` décroissant) : la première ligne est la plus récente.
        litiges = lignes.enumerated().map { ($0.element, -$0.offset) }
        messages = fil.enumerated().map { ($0.element, $0.offset - fil.count) }
    }

    /// `order=cree_le.desc` ; à date égale, la ligne posée en dernier d'abord.
    func liste() -> [Litige] {
        (litiges ?? []).sorted { a, b in
            let da = a.ligne.creeLe ?? "", db = b.ligne.creeLe ?? ""
            return da == db ? a.ordre > b.ordre : da > db
        }.map(\.ligne)
    }

    func litige(_ id: String) -> Litige? { (litiges ?? []).first { $0.ligne.id == id }?.ligne }

    /// `order=cree_le.asc` du fil d'un litige.
    func fil(_ litigeId: String) -> [MessageLitige] {
        messages.filter { $0.ligne.litigeId == litigeId }.sorted { a, b in
            let da = a.ligne.creeLe ?? "", db = b.ligne.creeLe ?? ""
            return da == db ? a.ordre < b.ordre : da < db
        }.map(\.ligne)
    }

    func ajouter(_ fabrique: @Sendable (Int) -> Litige) -> Litige {
        compteur += 1
        let ligne = fabrique(compteur)
        litiges = (litiges ?? []) + [(ligne, compteur)]
        return ligne
    }

    func ajouter(message fabrique: @Sendable (Int) -> MessageLitige) {
        compteur += 1
        messages.append((fabrique(compteur), compteur))
    }
}

/// Litiges du monde démo (L4-T8) : aucun réseau, chaque écriture est consignée dans l'acteur puis relue (aucun succès
/// fabriqué). Mêmes refus, dans le même ordre, que `fn_ouvrir_litige_rate_limited` (3 arguments, type `AUTRE`) et
/// `fn_ajouter_message_litige`, messages mot pour mot (`MessagesLitigesServeur`). Missions proposées : les missions
/// passées `EN_COURS` / `TERMINEE` du monde démo (`demo-mes-missions.json`, une seule source), sans celles qui ont déjà
/// un litige. Refuse tout contexte qui n'est pas celui du profil fictif.
public struct DemoLitigesGateway: LitigesPort {
    /// Statuts qui acceptent un message (`fn_ajouter_message_litige`) et bloquent un second litige du même type.
    static let statutsOuverts: Set<String> = ["OUVERT", "EN_DISCUSSION", "EN_MEDIATION", "MEDIATION_EN_COURS", "REVUE_ADMIN"]
    /// Statuts des missions proposées (`LitigesSoignant.tsx` l.137).
    static let statutsContestables: Set<String> = ["TERMINEE", "EN_COURS"]
    /// `rate_limit_litiges_par_heure`, valeur par défaut du serveur.
    static let plafondParHeure = 3
    static let typeLitige = "AUTRE"

    private let store = DemoLitigesStore()
    private let clock: any ClockPort
    private let initiaux: [Litige]?

    /// `initiaux` : litiges de départ (tests) ; `nil` = fixtures `demo-litiges.json` et `demo-litige-fil.json`.
    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), initiaux: [Litige]? = nil) {
        self.clock = clock
        self.initiaux = initiaux
    }

    public func lister(context: MissionReadContext) async throws -> [Litige] {
        try check(context)
        try await initialiser()
        return await store.liste()
    }

    public func missionsContestables(context: MissionReadContext) async throws -> [MissionContestable] {
        try check(context)
        try await initialiser()
        let enLitige = Set(await store.liste().compactMap(\.missionId))
        return LitigesPresentation.contestables(try Self.missionsAssignees(), idsEnLitige: enLitige)
    }

    public func ouvrir(missionId: String, motif: String, context: MissionReadContext) async throws -> OuvertureLitigeOutcome {
        try check(context)
        try await initialiser()
        let texte = Self.rogner(motif)
        guard (10...2000).contains(texte.unicodeScalars.count) else { return .refuse(message: MessagesLitigesServeur.motifLongueur) }
        guard let mission = try Self.missionsAssignees().first(where: { $0.id == missionId }) else {
            return .refuse(message: MessagesLitigesServeur.missionIntrouvable)
        }
        let existants = await store.liste()
        if existants.contains(where: { $0.missionId == missionId && $0.typeLitige == Self.typeLitige && Self.statutsOuverts.contains($0.statut) }) {
            return .refuse(message: MessagesLitigesServeur.dejaOuvert)
        }
        let maintenant = clock.now()
        let recents = existants.filter { litige in
            guard let cree = litige.creeLe.flatMap({ try? DateHeureParis.instantJolene($0) }) else { return false }
            return cree > maintenant.addingTimeInterval(-3600)
        }
        guard recents.count < Self.plafondParHeure else { return .refuse(message: MessagesLitigesServeur.tropDeLitiges) }
        let cree = await store.ajouter { numero in
            Litige(id: "demo-litige-ajout-\(numero)", missionId: mission.id, etablissementId: mission.etablissementId,
                   statut: "OUVERT", typeLitige: Self.typeLitige, motif: texte, creeLe: DateHeureParis.isoUTC(maintenant),
                   missionIntitule: mission.intitule, missionDebutLe: mission.debutLe, etablissementNom: mission.etablissementNom)
        }
        // Relecture par identifiant, comme la gateway Supabase : `ouvert` n'est rendu qu'avec le litige relu.
        guard await store.litige(cree.id) != nil else {
            throw JoleneError(.contract, "Litige démo introuvable après son ouverture.")
        }
        return .ouvert(id: cree.id, informatif: false)
    }

    public func fil(litigeId: String, context: MissionReadContext) async throws -> [MessageLitige] {
        try check(context)
        try await initialiser()
        return await store.fil(litigeId)
    }

    public func ajouterMessage(litigeId: String, contenu: String, context: MissionReadContext) async throws -> IssueMessageLitige {
        try check(context)
        try await initialiser()
        guard let litige = await store.litige(litigeId) else { return .refuse(message: MessagesLitigesServeur.litigeIntrouvable) }
        guard Self.statutsOuverts.contains(litige.statut) else { return .refuse(message: MessagesLitigesServeur.litigeClotureServeur) }
        let texte = Self.rogner(contenu)
        guard (10...5000).contains(texte.unicodeScalars.count) else { return .refuse(message: MessagesLitigesServeur.messageLongueur) }
        let maintenant = clock.now()
        let auteur = context.userId
        await store.ajouter { numero in
            MessageLitige(id: "demo-litige-message-ajout-\(numero)", litigeId: litigeId, auteurId: auteur, typeAuteur: "SOIGNANT",
                          contenu: texte, creeLe: DateHeureParis.isoUTC(maintenant.addingTimeInterval(Double(numero))))
        }
        return .ajoute(await store.fil(litigeId))
    }

    // MARK: - Interne

    /// `trim` / `btrim` de PostgreSQL sans second argument : espaces (U+0020) de bord seulement.
    static func rogner(_ texte: String) -> String { texte.trimmingCharacters(in: CharacterSet(charactersIn: " ")) }

    /// Missions passées du profil démo aux statuts proposés, `fin_le` décroissant, nom de l'établissement fictif joint.
    static func missionsAssignees() throws -> [MissionContestable] {
        let noms = Dictionary(try DemoFixtures.loadEtablissements().etablissements.map { ($0.id, $0.nom) }) { premier, _ in premier }
        return try DemoFixtures.loadMesMissions().passees.map(\.mission.record)
            .filter { statutsContestables.contains($0.statut) }
            .sorted { $0.finLe > $1.finLe }
            .map { MissionContestable(id: $0.id, intitule: $0.intitule, debutLe: $0.debutLe, etablissementId: $0.etablissementId,
                                      etablissementNom: noms[$0.etablissementId]) }
    }

    private func check(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }

    private func initialiser() async throws {
        guard await !store.estInitialise else { return }
        if let initiaux {
            await store.initialiser(litiges: initiaux, messages: [])
            return
        }
        let noms = Dictionary(try DemoFixtures.loadEtablissements().etablissements.map { ($0.id, $0.nom) }) { premier, _ in premier }
        let litiges = try DemoFixtures.loadLitiges().litiges.map { ligne -> Litige in
            var litige = ligne
            if litige.etablissementNom == nil { litige.etablissementNom = ligne.etablissementId.flatMap { noms[$0] } }
            return litige
        }
        await store.initialiser(litiges: litiges, messages: try DemoFixtures.loadLitigeFil().messages)
    }
}
