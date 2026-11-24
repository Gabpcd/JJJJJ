import Foundation

extension DemoFixtures {
    /// `demo-favoris.json` (lot 1, T4b) : une ligne `missions_sauvegardees` avec sa jointure `missions`
    /// (forme PostgREST de `SupabaseFavorisGateway.selectSauvegardees`) et un élément de
    /// `fn_mes_favoris_etablissements` (`nb_missions_ouvertes` calculé par l'exporteur comme le SQL).
    public struct FavorisFile: Decodable, Sendable {
        public var fixedNow: String
        public var missionsSauvegardees: [MissionSauvegardee]
        public var etablissementsFavoris: [EtablissementFavori]

        enum CodingKeys: String, CodingKey {
            case fixedNow = "fixed_now"
            case missionsSauvegardees = "missions_sauvegardees"
            case etablissementsFavoris = "etablissements_favoris"
        }
    }

    public static func loadFavoris() throws -> FavorisFile { try load("demo-favoris") }
}

/// Favoris du compte démo : initialisés depuis la fixture au premier accès, en mémoire ensuite, perdus
/// au relancement, jamais envoyés.
actor DemoFavorisStore {
    private var missions: [MissionSauvegardee]?
    private var etablissements: [EtablissementFavori] = []
    /// Favoris de l'inscription progressive (`parcours_inscription.donnees.missionsSauvegardees`, décision 8 du lot 1 amendée le 18/11/2026) :
    /// vides dans la fixture du compte démo ; posés par les tests de la gateway.
    private var inscription: [String] = []
    private var numero = 0

    func initialiser(_ fichier: DemoFixtures.FavorisFile, inscription: [String]) {
        guard missions == nil else { return }
        missions = fichier.missionsSauvegardees
        etablissements = fichier.etablissementsFavoris
        self.inscription = inscription
    }

    func favorisInscription() -> [String] { inscription }

    /// `fn_modifier_favori_inscription(p_actif := false)` : l'identifiant est retiré du magasin de l'inscription.
    func retirerDeLInscription(missionId: String) {
        inscription.removeAll { $0 == missionId }
    }

    var estInitialise: Bool { missions != nil }

    func lignes() -> [MissionSauvegardee] { missions ?? [] }

    func suivis() -> [EtablissementFavori] { etablissements }

    /// `INSERT … ` sous contrainte UNIQUE (soignant, mission) : sans effet si la ligne existe déjà.
    func ajouter(missionId: String, apercu: MissionSauvegardee.Apercu, creeLe: String) {
        var courantes = missions ?? []
        guard !courantes.contains(where: { $0.missionId == missionId }) else { return }
        numero += 1
        // `cree_le DESC` : la ligne la plus récente d'abord.
        courantes.insert(MissionSauvegardee(id: "demo-sauvegarde-ajout-\(numero)", missionId: missionId, creeLe: creeLe,
                                            mission: apercu), at: 0)
        missions = courantes
    }

    func retirer(missionId: String) {
        missions = (missions ?? []).filter { $0.missionId != missionId }
    }

    func retirerEtablissement(_ id: String) {
        etablissements.removeAll { $0.id == id }
    }
}

/// Favoris du monde démo (blueprint lot 1 §2.7) : aucun réseau, chaque mutation est consignée dans
/// l'acteur puis relue (aucun succès fabriqué). Refuse tout contexte qui n'est pas celui du profil
/// fictif ; refuse l'ajout d'un établissement favori avant toute écriture (décision 8).
public struct DemoFavorisGateway: FavorisPort {
    /// Équivalent démo d'une clé étrangère violée (mission inexistante), message générique.
    public static let sauvegardeImpossible = "La mission n'a pas pu être sauvegardée. Réessayez."
    /// Refus de `fn_toggle_favori_etablissement` pour un établissement inexistant (l.61959), verbatim.
    public static let etablissementIntrouvable = "Établissement introuvable"

    private let store = DemoFavorisStore()
    private let clock: any ClockPort
    private let inscriptionInitiale: [String]

    /// `favorisInscription` : favoris posés pendant l'inscription progressive (aucun pour le compte démo de l'app).
    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), favorisInscription: [String] = []) {
        self.clock = clock
        self.inscriptionInitiale = favorisInscription
    }

    /// Deux magasins fusionnés comme la gateway Supabase (`FavorisRegles.fusion`, décision 8 du lot 1 amendée le 18/11/2026) ; aperçus des
    /// favoris de l'inscription relus dans les missions démo.
    public func missionsSauvegardees(context: MissionReadContext) async throws -> [MissionSauvegardee] {
        try check(context)
        try await initialiser()
        let lignes = await store.lignes()
        let inscription = await store.favorisInscription()
        var apercus: [String: MissionSauvegardee.Apercu] = [:]
        for id in inscription {
            if let record = try Self.mission(id: id) { apercus[id] = MissionSauvegardee.Apercu(record) }
        }
        return FavorisRegles.fusion(sauvegardees: lignes, inscription: inscription, apercus: apercus)
    }

    public func sauvegarder(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee] {
        try check(context)
        try await initialiser()
        guard let record = try Self.mission(id: missionId) else {
            throw JoleneError(.unknown, Self.sauvegardeImpossible)
        }
        await store.ajouter(missionId: missionId, apercu: MissionSauvegardee.Apercu(record),
                            creeLe: DateHeureParis.isoUTC(clock.now()))
        // Relecture après mutation.
        return try await missionsSauvegardees(context: context)
    }

    /// Retrait des deux magasins, comme le web (`BoutonSauvegarderMission.tsx` l.61-64) : l'inscription d'abord
    /// (`fn_modifier_favori_inscription(false)`), puis la ligne `missions_sauvegardees`.
    public func retirer(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee] {
        try check(context)
        try await initialiser()
        await store.retirerDeLInscription(missionId: missionId)
        await store.retirer(missionId: missionId)
        return try await missionsSauvegardees(context: context)
    }

    public func etablissementsFavoris(context: MissionReadContext) async throws -> [EtablissementFavori] {
        try check(context)
        try await initialiser()
        return await store.suivis()
    }

    public func basculerEtablissement(id: String, actif: Bool, context: MissionReadContext) async throws -> [EtablissementFavori] {
        try check(context)
        guard !actif else { throw JoleneError(.contract, FavorisRegles.ajoutEtablissementNonPropose) }
        try await initialiser()
        guard try DemoFixtures.loadEtablissements().etablissements.contains(where: { $0.id == id }) else {
            throw JoleneError(.unknown, Self.etablissementIntrouvable)
        }
        await store.retirerEtablissement(id)
        return try await etablissementsFavoris(context: context)
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
        let fichier = try DemoFixtures.loadFavoris()
        await store.initialiser(fichier, inscription: inscriptionInitiale)
    }

    /// Missions démo connues : Explorer (`demo-missions.json`), missions de recette du paquet de swipe (L4-T3b : ⭐ sur
    /// l'une d'elles) et missions ASSIGNEE du tableau de bord.
    private static func mission(id: String) throws -> MissionRecord? {
        if let ouverte = try (DemoFixtures.loadMissions().missions + DemoFixtures.missionsRecetteSwipe()).first(where: { $0.record.id == id }) {
            return ouverte.record
        }
        return try DemoFixtures.loadDashboard().missionsAssignees.first { $0.record.id == id }?.record
    }
}
