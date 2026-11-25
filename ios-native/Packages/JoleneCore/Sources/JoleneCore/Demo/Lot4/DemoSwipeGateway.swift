import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « swipe » (`Gateways.swipe`), T3a : la gateway démo partage l'état des favoris (⭐ écrit
    /// dans `missions_sauvegardees`, comme `fn_enregistrer_swipe`) et de la candidature (❤️ passe par
    /// `CandidaturePort.confirmer(.swipeLike)`, retrait par `DemoCandidatureGateway.retirerCandidature`) du même monde.
    static func swipe(_ gateways: Gateways) -> SwipePort {
        DemoSwipeGateway(favoris: gateways.favoris, candidature: gateways.candidature as? DemoCandidatureGateway)
    }
}

extension DemoFixtures {
    /// `demo-swipe.json` (`scripts/mobile/demo-fixtures/swipe.mjs`, `buildDemoSwipe`) : corps de
    /// `fn_obtenir_missions_swipe` pour douze cartes : dix missions ouvertes de `demo-missions.json`, dont le planning
    /// reste celui de `demo-missions.json` (même source que la validation de `DemoCandidatureGateway`), et deux missions
    /// de recette du paquet (T3b, `missions_recette`, servies avec leurs créneaux) : `demo-swipe-choix` (contrat `TOUS`,
    /// le ❤️ du profil `MIXTE` demande un choix) et `demo-swipe-deja` (`deja_swipees` : déjà swipée ailleurs, servie par
    /// un paquet lu avant).
    public struct SwipeFile: Decodable, Sendable {
        public var fixedNow: String
        public var paquet: PaquetSwipe
        /// Missions qui n'existent que pour le swipe, jamais listées par Explorer.
        public var missionsRecette: [MissionFixture]
        /// Missions dont la ligne `swipes` existe déjà : toute réponse y est refusée (`mission_deja_swipee`).
        public var dejaSwipees: [String]

        enum CodingKeys: String, CodingKey {
            case fixedNow = "fixed_now", missionsRecette = "missions_recette", dejaSwipees = "deja_swipees"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fixedNow = try c.decode(String.self, forKey: .fixedNow)
            missionsRecette = try c.decodeIfPresent([MissionFixture].self, forKey: .missionsRecette) ?? []
            dejaSwipees = try c.decodeIfPresent([String].self, forKey: .dejaSwipees) ?? []
            paquet = try PaquetSwipe(from: decoder)
        }
    }

    public static func loadSwipe() throws -> SwipeFile { try load("demo-swipe") }

    /// Missions de recette du paquet de swipe (T3b) : ouvertes, hors d'Explorer, comme la mission de recette de la
    /// confirmation de présence (`DemoPresenceGateway.missionJ1`, ouverte par lien seulement). Les mondes démo qui
    /// relisent une mission par son identifiant (candidature, favoris, Mes missions, détail) les connaissent par ici,
    /// si bien qu'une carte sauvegardée ou candidatée depuis le paquet se retrouve partout où le web la montrerait.
    public static func missionsRecetteSwipe() throws -> [MissionFixture] { try loadSwipe().missionsRecette }

    /// Lignes `swipes` posées hors de la session démo (`deja_swipees`) : refus `mission_deja_swipee` de ✕, ⭐ et ❤️.
    public static func swipesAnterieurs() throws -> Set<String> { Set(try loadSwipe().dejaSwipees) }
}

extension DemoCandidatureGateway: CandidatureSwipePort {
    /// ❤️ du monde démo et ses avis (T3b) : même issue que `confirmer(.swipeLike)` ; `docs_a_completer` comme le serveur
    /// (`NOT fn_documents_ok_pour_mission`), vrai tant que les documents du profil fictif ne sont pas tous valides ;
    /// aucun avertissement de planning (le monde démo ne simule pas les missions adjacentes).
    public func confirmerSwipeLike(missionId: String, creneaux: [CreneauConfirmePayload], choixContrat: String?,
                                   context: MissionReadContext) async throws -> IssueSwipeLike {
        let issue = try await confirmer(action: .swipeLike, missionId: missionId, creneaux: creneaux, message: nil,
                                        choixContrat: choixContrat, candidatureId: nil, context: context)
        guard case .confirmed = issue else { return IssueSwipeLike(issue: issue) }
        return IssueSwipeLike(issue: issue, avis: AvisSwipeLike(documentsACompleter: !context.profile.tousDocumentsValides))
    }
}

/// Swipe du monde démo (lot 4, T3a ; `LOT4_PLAN.md` §2.7) : aucun réseau, horloge fixée, état en mémoire pour la session
/// démo (rien n'est persisté). Mêmes contrôles et même ordre que `fn_obtenir_missions_swipe` / `fn_enregistrer_swipe` :
/// - paquet = lignes de `demo-swipe.json` encore `OUVERTE` et à venir, jamais swipées (✕, ⭐ ou ❤️ de la session) ni
///   attribuées ; créneaux PREVISIONNEL hors pauses de `demo-missions.json` ou des missions de recette du paquet
///   (`DemoFixtures.missionsRecetteSwipe`, T3b) ; `nombreSwipes` = 0 au lancement (quiz) ;
/// - ✕ / ⭐ : mission inconnue ou fermée → `mission_indisponible` ; déjà swipée → `mission_deja_swipee` (libellés
///   `SwipeRefus`) ; ⭐ écrit la mission dans les favoris démo puis la relit (aucun succès fabriqué) ;
/// - carte déjà swipée ailleurs (`DemoFixtures.swipesAnterieurs`, T3b) : servie par le paquet tant qu'aucune réponse ne
///   lui a été refusée (paquet lu avant la ligne `swipes`), refusée par `mission_deja_swipee`, puis absente des paquets
///   relus, comme le serveur (`NOT EXISTS swipes`) ; elle ne compte pas dans `nombreSwipes` (quiz du premier contact) ;
/// - retrait après ❤️ : `DemoCandidatureGateway.retirerCandidature` (candidature supprimée, carte jamais remise) ;
/// - préférences du quiz : bornes [0, 1] du serveur, sinon « Préférences hors bornes [0,1] ».
/// Refuse tout contexte qui n'est pas celui du profil fictif (`.demoOnly`).
public actor DemoSwipeGateway: SwipePort {
    public static let horsBornes = "Préférences hors bornes [0,1]"
    public static let messageRelecture = "La sauvegarde de la mission n'a pas pu être relue dans le monde de démonstration."

    private let clock: any ClockPort
    private let favoris: any FavorisPort
    private let candidature: DemoCandidatureGateway?
    private let lignes: @Sendable () throws -> [LigneSwipe]
    private let missions: @Sendable () throws -> [DemoFixtures.MissionFixture]
    private let swipesAnterieurs: @Sendable () throws -> Set<String>
    /// Lignes `swipes` DISLIKE / FAVORI de la session (les LIKE sont consignés par la candidature).
    private var swipes: [String: DirectionSwipe] = [:]
    /// Cartes déjà swipées ailleurs dont une réponse a été refusée pendant la session : plus servies par le paquet.
    private var refusees: Set<String> = []
    public private(set) var preferences: PreferencesMatching?

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), favoris: any FavorisPort,
                candidature: DemoCandidatureGateway?,
                lignes: @escaping @Sendable () throws -> [LigneSwipe] = { try DemoFixtures.loadSwipe().paquet.missions },
                missions: @escaping @Sendable () throws -> [DemoFixtures.MissionFixture] = {
                    try DemoFixtures.loadMissions().missions + DemoFixtures.missionsRecetteSwipe()
                },
                swipesAnterieurs: @escaping @Sendable () throws -> Set<String> = { try DemoFixtures.swipesAnterieurs() }) {
        self.clock = clock
        self.favoris = favoris
        self.candidature = candidature
        self.lignes = lignes
        self.missions = missions
        self.swipesAnterieurs = swipesAnterieurs
    }

    // MARK: - SwipePort

    public func paquet(context: MissionReadContext) async throws -> [CarteSwipe] {
        try Self.verifier(context)
        let exclues = await dejaSwipees().union(await candidature?.missionsAttribuees() ?? []).union(refusees)
        let fixtures = try missions()
        let maintenant = clock.now()
        return try lignes().prefix(PaquetSwipe.taille).compactMap { ligne in
            guard !exclues.contains(ligne.missionId),
                  let fixture = fixtures.first(where: { $0.record.id == ligne.missionId }),
                  fixture.record.statut == LigneSwipe.statutServi,
                  let debut = PlanningHorlogeParis.instant(fixture.record.debutLe), debut > maintenant else { return nil }
            let creneaux = fixture.creneaux.filter { $0.typeCreneau == "PREVISIONNEL" && !$0.estPause }
            return CarteSwipe(ligne: ligne, creneaux: creneaux)
        }
    }

    public func enregistrer(missionId: String, direction: DirectionSwipe, context: MissionReadContext) async throws -> SwipeOutcome {
        try Self.verifier(context)
        let attribuees = await candidature?.missionsAttribuees() ?? []
        guard let fixture = try missions().first(where: { $0.record.id == missionId }),
              fixture.record.statut == LigneSwipe.statutServi, !attribuees.contains(missionId) else {
            return Self.refus("mission_indisponible")
        }
        // Ligne `swipes` posée ailleurs (`ON CONFLICT DO NOTHING` → `mission_deja_swipee`) : le paquet relu ne la sert plus.
        if try swipesAnterieurs().contains(missionId) {
            refusees.insert(missionId)
            return Self.refus("mission_deja_swipee")
        }
        guard await !dejaSwipees().contains(missionId) else { return Self.refus("mission_deja_swipee") }
        swipes[missionId] = direction
        guard direction == .favori else { return .enregistre }
        // `INSERT INTO missions_sauvegardees … ON CONFLICT DO NOTHING`, puis relecture de la ligne.
        let relues = try await favoris.sauvegarder(missionId: missionId, context: context)
        guard FavorisRegles.estSauvegardee(missionId, dans: relues) else { throw JoleneError(.contract, Self.messageRelecture) }
        return .enregistre
    }

    public func retirer(candidatureId: String, context: MissionReadContext) async throws -> RetraitOutcome {
        try Self.verifier(context)
        guard let candidature else { throw JoleneError(.contract, Self.messageRelecture) }
        return try await candidature.retirerCandidature(id: candidatureId, context: context)
    }

    public func nombreSwipes(context: MissionReadContext) async throws -> Int {
        try Self.verifier(context)
        return await dejaSwipees().count
    }

    public func initialiserPreferences(_ preferences: PreferencesMatching, context: MissionReadContext) async throws {
        try Self.verifier(context)
        guard preferences.dansLesBornes else { throw JoleneError(.unknown, Self.horsBornes) }
        self.preferences = preferences
    }

    // MARK: - Interne

    private func dejaSwipees() async -> Set<String> {
        Set(swipes.keys).union(await candidature?.missionsLikees() ?? [])
    }

    private static func refus(_ code: String) -> SwipeOutcome {
        let refus = SwipeRefus.traduire(code)
        return .refuse(code: refus.code, message: refus.message)
    }

    private static func verifier(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}
