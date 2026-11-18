import Foundation

/// Candidature du monde démo (lot 1, T6a, `LOT1_PLAN.md` §2.7) : aucun réseau, horloge fixée, état en
/// mémoire pour la session démo (rien n'est persisté entre deux lancements). Mêmes contrôles et mêmes
/// textes que `fn_confirmer_action_planning_v1` et ses délégués, dans le même ordre (mission ouverte,
/// planning confirmé identique au planning live, puis l'action, dans l'ordre des délégués) ; chaque mutation
/// (candidature, attribution, proposition) est relue dans l'acteur avant d'annoncer un succès, comme la gateway
/// Supabase relit le serveur.
///
/// - POSTULER → candidature `EN_ATTENTE` de session, visible dans Mes missions (`candidaturesDeSession`,
///   point de fusion de `DemoMesMissionsGateway`) ; une seconde candidature sur la même mission est
///   refusée (« Vous avez déjà postulé à cette mission », comme le serveur) ;
/// - ACCEPTER → mission attribuée au profil fictif et contrat démo ; refusé en mode candidature ;
/// - PROPOSITION → verrouillée hors `LIBERAL` (`CandidatureVerrou.renvoiWeb`, attestation hebdomadaire non
///   portée, revue B8 de T6a M1) ; libérale : proposition `PROPOSEE` de moins de 2 h acceptée (`ACCEPTEE`) et
///   mission attribuée ; refus par `refuserProposition` (`REFUSEE`), expiration à 2 h comme `fn_repondre_proposition` ;
/// - mission attribuée pendant la session → servie `ASSIGNEE` par `DemoMissionsGateway` et retirée d'Explorer ;
/// - mission `TOUS` sans choix pour un profil `MIXTE` → `choixRequis` avec les options du serveur ;
/// - SWIPE_LIKE (lot 4, T3a) → ordre de `fn_enregistrer_swipe` : candidature existante (« Vous avez déjà candidaté à
///   cette mission »), choix de contrat, ligne `swipes` déjà posée (`mission_deja_swipee`, libellé `SwipeRefus`), puis
///   candidature `EN_ATTENTE` de session relue et ligne `swipes` LIKE consignée (`missionsLikees`, lue par
///   `DemoSwipeGateway`) ; le retrait (`retirerCandidature`) supprime la candidature `EN_ATTENTE` comme
///   `fn_retirer_candidature`, la ligne `swipes` reste (correction 12). URGENCE reste refusée (T11).
///
/// Annulations (T7) : mêmes contrôles, même ordre et mêmes textes que `fn_annuler_candidature_soignant`
/// (motif, texte de 10 caractères, candidature, statut) et `fn_annuler_mission_soignant` (mission, attribution,
/// statut) ; la candidature retenue de la mission assignée 3 (`candidatureRetenue`) ouvre la modale de candidature.
/// Conséquences simulées : toutes les missions assignées démarrent plus de 24 h après l'horloge fixée
/// (`DemoCandidatureGatewayTests`), si bien que le serveur rendrait 0 point (`neutre_delai_long`, pénalité de mission
/// nulle) : aucun barème n'est simulé. Refuse tout contexte qui n'est pas celui du profil fictif (`.demoOnly`).
public actor DemoCandidatureGateway: CandidaturePort {
    /// Textes serveur repris à l'identique (`supabase/schema/public.sql`).
    public enum Textes {
        public static let missionIndisponible = "Cette mission n'est plus disponible."
        public static let planningModifie = "Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires."
        public static let dejaPostule = "Vous avez déjà postulé à cette mission"
        public static let candidatureRequise = "Cette mission nécessite une candidature"
        public static let propositionIntrouvable = "Proposition introuvable."
        public static let propositionExpiree = "Cette proposition a expiré"
        public static let propositionPlusEnAttente = "Cette proposition n’est plus en attente"
        /// `fn_enregistrer_swipe` (LIKE) et `fn_retirer_candidature` (T3a).
        public static let dejaCandidate = "Vous avez déjà candidaté à cette mission"
        public static let retraitIntrouvable = "Candidature introuvable"
        public static let retraitDejaTraitee = "La candidature a déjà été traitée et ne peut plus être retirée ici."
        public static let choixContrat = [
            ChoixContratOption(value: "SALARIE", label: "Salarié (CDD / bulletin de paie)"),
            ChoixContratOption(value: "LIBERAL", label: "Libéral (note d'honoraires)"),
        ]
        // `fn_annuler_candidature_soignant` (T7).
        public static let motifInvalide = "Motif requis (URGENCE_PERSONNELLE, URGENCE_MEDICALE, DEUIL, PROBLEME_TRANSPORT, CHANGEMENT_AVIS, AUTRE)"
        public static let texteRequis = "Texte libre obligatoire (min 10 caractères)"
        public static let candidatureIntrouvable = "Candidature introuvable"
        public static func statutInvalide(_ statut: String) -> String {
            "Candidature pas dans un état annulable (statut : \(statut))"
        }
        // `fn_annuler_mission_soignant` (T7).
        public static let missionIntrouvable = "Mission introuvable"
        public static let missionNonAssignee = "Cette mission ne vous est pas assignée"
        public static let annulationImpossible = "Annulation impossible dans cet état. Si la mission est en cours, ouvrez un litige."
    }

    /// Candidature retenue (`ACCEPTEE`) de la mission assignée 3 : la seule mission démo dont l'annulation ouvre la
    /// modale de candidature (les autres, attribuées sans candidature, ouvrent la confirmation simple).
    public static let candidatureRetenue = CandidatureRecord(id: "demo-candidature-retenue-003", missionId: "demo-assignee-003",
                                                              statut: AnnulationRules.statutAcceptee, message: nil,
                                                              typeContratChoisi: nil, creeLe: "2026-10-30T09:00:00.000Z")

    public static let codePlanningModifie = "PLANNING_MODIFIE_RECONFIRMER"
    public static let messageRelecture = "La candidature n'a pas pu être relue dans le monde de démonstration."

    private let clock: any ClockPort
    private let missions: @Sendable () throws -> [DemoFixtures.MissionFixture]
    private let candidaturesInitiales: @Sendable () throws -> [CandidatureRecord]
    /// Candidatures créées ou modifiées pendant la session démo, la plus récente en tête.
    private var session: [CandidatureRecord] = []
    /// Missions attribuées au profil fictif pendant la session : contrat démo par mission.
    private var attributions: [String: String] = [:]
    private var compteur = 0
    /// T3a : missions likées pendant la session (lignes `swipes` LIKE, immuables) et candidatures retirées (supprimées).
    private var likes: Set<String> = []
    private var supprimees: Set<String> = []
    /// T7 : missions assignées (`demo-dashboard.json`), missions annulées et justificatifs transmis pendant la session.
    private let missionsAssignees: @Sendable () throws -> [DemoFixtures.MissionFixture]
    private var annulees: Set<String> = []
    private var justificatifs: [String: String] = [:]

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow),
                missions: @escaping @Sendable () throws -> [DemoFixtures.MissionFixture] = { try DemoFixtures.loadMissions().missions },
                candidaturesInitiales: @escaping @Sendable () throws -> [CandidatureRecord] = DemoCandidatureGateway.candidaturesDesFixtures,
                missionsAssignees: @escaping @Sendable () throws -> [DemoFixtures.MissionFixture] = {
                    try DemoFixtures.loadDashboard().missionsAssignees
                }) {
        self.clock = clock
        self.missions = missions
        self.candidaturesInitiales = candidaturesInitiales
        self.missionsAssignees = missionsAssignees
    }

    /// Chemin du justificatif transmis avec l'annulation de cette candidature (relecture des tests).
    public func justificatifTransmis(candidatureId: String) -> String? { justificatifs[candidatureId] }

    /// Mission annulée par le profil fictif pendant la session.
    public func missionAnnulee(_ missionId: String) -> Bool { annulees.contains(missionId) }

    /// Missions annulées par le profil fictif pendant la session, relues par `DemoMissionsGateway` (servies `OUVERTE`,
    /// non attribuées, comme la remise en ligne du serveur) et par Mes missions (hors « À venir ») : revue B8 de #1156, M1.
    public func missionsAnnulees() -> Set<String> { annulees }

    /// Candidatures en attente de `demo-mes-missions.json` et proposition de l'Accueil (`demo-dashboard.json`).
    public static let candidaturesDesFixtures: @Sendable () throws -> [CandidatureRecord] = {
        let attente = try DemoFixtures.loadMesMissions().candidatures
        let propositions = try DemoFixtures.loadDashboard().dashboard.propositions.map {
            CandidatureRecord(id: $0.id, missionId: $0.missionId, statut: CandidatureRules.statutProposee, message: nil,
                              typeContratChoisi: $0.typeContratChoisi, creeLe: $0.creeLe)
        }
        return attente + propositions + [DemoCandidatureGateway.candidatureRetenue]
    }

    /// Candidatures de la session démo, lues par `DemoMesMissionsGateway` (point de fusion de T5).
    public func candidaturesDeSession() -> [CandidatureRecord] { session }

    /// Mission attribuée au profil fictif pendant la session (relecture des tests et des écrans).
    public func contratAttribue(missionId: String) -> String? { attributions[missionId] }

    /// Missions attribuées pendant la session, relues par `DemoMissionsGateway` (détail `ASSIGNEE`, hors d'Explorer).
    public func missionsAttribuees() -> Set<String> { Set(attributions.keys) }

    /// T3a : missions likées pendant la session (lignes `swipes` LIKE), exclues du paquet par `DemoSwipeGateway`.
    public func missionsLikees() -> Set<String> { likes }

    /// T3a : `fn_retirer_candidature` (contrôles dans l'ordre du serveur), puis absence relue dans l'acteur. La ligne
    /// `swipes` LIKE reste : la mission ne revient jamais au paquet (correction 12).
    public func retirerCandidature(id: String, context: MissionReadContext) throws -> RetraitOutcome {
        try Self.verifier(context)
        guard let candidature = try toutes().first(where: { $0.id == id }) else {
            return .refuse(message: Textes.retraitIntrouvable)
        }
        guard candidature.statut == "EN_ATTENTE" else { return .refuse(message: Textes.retraitDejaTraitee) }
        supprimees.insert(id)
        session.removeAll { $0.id == id }
        guard try !toutes().contains(where: { $0.id == id }) else { throw JoleneError(.contract, Self.messageRelecture) }
        return .retiree
    }

    // MARK: - CandidaturePort

    public func confirmer(action: ActionPlanning, missionId: String, creneaux: [CreneauConfirmePayload], message: String?,
                          choixContrat: String?, candidatureId: String?, context: MissionReadContext) async throws -> CandidatureOutcome {
        try Self.verifier(context)
        guard action == .postuler || action == .accepter || action == .proposition || action == .swipeLike else {
            throw CandidatureRules.actionHorsLot1(action)
        }
        if action == .proposition {
            // Verrou de l'attestation hebdomadaire (revue B8 de T6a, M1) : contrat déclaré, puis relu dans les fixtures.
            guard !CandidatureRules.propositionVerrouillee(contrat: choixContrat) else {
                throw CandidatureVerrou.renvoiWeb(chemin: CandidatureVerrou.cheminProposition)
            }
        }
        guard let fixture = try missions().first(where: { $0.record.id == missionId }),
              fixture.record.statut == "OUVERTE", attributions[missionId] == nil else {
            return .missionDejaAttribuee(message: Textes.missionIndisponible)
        }
        let attendus = CreneauxConfirmes.pourAction(PlanningCandidatInput(record: fixture.record, creneaux: fixture.creneaux))
        guard let attendus, !attendus.isEmpty, attendus.count == creneaux.count, Set(attendus) == Set(creneaux) else {
            return .planningAReconfirmer(code: Self.codePlanningModifie, message: Textes.planningModifie)
        }
        if action == .proposition {
            return try accepterProposition(candidatureId: candidatureId, mission: fixture.record)
        }
        if action == .swipeLike {
            return try aimer(fixture.record, choixContrat: choixContrat, context: context)
        }
        // Ordre des délégués : `fn_accepter_mission` refuse le mode candidature avant de résoudre le contrat ;
        // `fn_postuler_mission` résout le contrat (`choix_requis`) avant de chercher un doublon.
        if action == .accepter, fixture.record.modeAttribution == CandidatureRules.modeCandidature {
            throw JoleneError(.unknown, Textes.candidatureRequise)
        }
        if fixture.record.typeContratRecherche == "TOUS", context.profile.typeExercice == "MIXTE",
           (choixContrat ?? "").isEmpty {
            return .choixRequis(Textes.choixContrat)
        }
        if action == .postuler {
            if try toutes().contains(where: { $0.missionId == missionId }) {
                throw JoleneError(.unknown, Textes.dejaPostule)
            }
            compteur += 1
            let id = "demo-candidature-session-\(compteur)"
            session.insert(CandidatureRecord(id: id, missionId: missionId, statut: "EN_ATTENTE", message: message,
                                             typeContratChoisi: choixContrat, creeLe: DateHeureParis.isoUTC(clock.now())), at: 0)
            guard CandidatureRules.candidaturePoseeRelue(try candidatureCourante(missionId: missionId), id: id, missionId: missionId) else {
                throw JoleneError(.contract, Self.messageRelecture)
            }
            return .confirmed(candidatureId: id, contratId: nil)
        }
        return .confirmed(candidatureId: nil, contratId: try attribuerPuisRelire(missionId))
    }

    public func refuserProposition(candidatureId: String, context: MissionReadContext) async throws {
        try Self.verifier(context)
        let proposition = try propositionOuverte(candidatureId)
        remplacer(proposition, statut: CandidatureRules.statutRefusee)
        guard CandidatureRules.refusRelu(try toutes().first(where: { $0.id == candidatureId }), id: candidatureId) else {
            throw JoleneError(.contract, Self.messageRelecture)
        }
    }

    public func candidature(missionId: String, context: MissionReadContext) async throws -> CandidatureRecord? {
        try Self.verifier(context)
        return try candidatureCourante(missionId: missionId)
    }

    /// `fn_annuler_candidature_soignant` : contrôles dans l'ordre du serveur, puis `ANNULEE` relue dans l'acteur.
    public func annulerCandidature(id: String, motif: String, texte: String, justificatifPath: String?,
                                   context: MissionReadContext) async throws -> AnnulationOutcome {
        try Self.verifier(context)
        guard AnnulationRules.motifsServeur.contains(motif) else {
            return .refusee(code: "MOTIF_INVALIDE", message: Textes.motifInvalide)
        }
        guard texte.trimmingCharacters(in: CharacterSet(charactersIn: " ")).count >= AnnulationRules.texteMinimumServeur else {
            return .refusee(code: "TEXTE_REQUIS", message: Textes.texteRequis)
        }
        guard let candidature = try toutes().first(where: { $0.id == id }) else {
            return .refusee(code: "CANDIDATURE_INTROUVABLE", message: Textes.candidatureIntrouvable)
        }
        let statut = candidature.statut ?? ""
        guard statut == AnnulationRules.statutAcceptee || statut == "EN_ATTENTE" else {
            return .refusee(code: AnnulationRules.codeStatutInvalide, message: Textes.statutInvalide(statut))
        }
        remplacer(candidature, statut: AnnulationRules.statutAnnulee)
        if statut == AnnulationRules.statutAcceptee {
            annulees.insert(candidature.missionId)
            attributions[candidature.missionId] = nil
            if let justificatifPath { justificatifs[id] = justificatifPath }
        }
        guard AnnulationRules.candidatureAnnuleeRelue(try toutes().first(where: { $0.id == id }), id: id) else {
            throw JoleneError(.contract, Self.messageRelecture)
        }
        // EN_ATTENTE : `{libre:true, points:0}` sans `contestable` ; ACCEPTEE à plus de 24 h : 0 point, libre.
        return statut == AnnulationRules.statutAcceptee
            ? .annulee(points: 0, libre: true, contestable: false)
            : .annulee(points: 0, libre: true, contestable: nil)
    }

    /// `fn_annuler_mission_soignant` : mission assignée au profil fictif et `ASSIGNEE`, remise en ligne dans l'acteur.
    public func annulerMission(id: String, motif: String?, context: MissionReadContext) async throws -> AnnulationOutcome {
        try Self.verifier(context)
        guard let fixture = try (missionsAssignees() + missions()).first(where: { $0.record.id == id }) else {
            return .refusee(code: nil, message: Textes.missionIntrouvable)
        }
        let assignee = !annulees.contains(id)
            && (attributions[id] != nil || fixture.record.soignantAssigneId == context.userId)
        guard assignee else { return .refusee(code: nil, message: Textes.missionNonAssignee) }
        guard attributions[id] != nil || fixture.record.statut == AnnulationRules.statutAssignee else {
            return .refusee(code: nil, message: Textes.annulationImpossible)
        }
        annulees.insert(id)
        attributions[id] = nil
        return .annulee(points: 0, libre: nil, contestable: nil)
    }

    // MARK: - Interne

    private static func verifier(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }

    /// Candidatures de session puis des fixtures, une seule ligne par candidature (la version de session
    /// d'abord : une proposition acceptée ou refusée remplace sa ligne de fixture). POSTULER refuse une
    /// seconde candidature sur la même mission, comme la contrainte `UNIQUE (mission_id, soignant_id)`.
    private func toutes() throws -> [CandidatureRecord] {
        var vues = Set<String>()
        return (session + (try candidaturesInitiales())).filter { !supprimees.contains($0.id) && vues.insert($0.id).inserted }
    }

    /// SWIPE_LIKE dans l'ordre de `fn_enregistrer_swipe` (après les contrôles de planning du wrapper), relu dans l'acteur.
    private func aimer(_ mission: MissionRecord, choixContrat: String?, context: MissionReadContext) throws -> CandidatureOutcome {
        if try toutes().contains(where: { $0.missionId == mission.id }) {
            return .refusee(code: nil, message: Textes.dejaCandidate, documentsRequisPour: nil)
        }
        if mission.typeContratRecherche == "TOUS", context.profile.typeExercice == "MIXTE", (choixContrat ?? "").isEmpty {
            return .choixRequis(Textes.choixContrat)
        }
        guard !likes.contains(mission.id) else {
            let refus = SwipeRefus.traduire("mission_deja_swipee")
            return .refusee(code: refus.code, message: refus.message, documentsRequisPour: nil)
        }
        likes.insert(mission.id)
        compteur += 1
        let id = "demo-candidature-swipe-\(compteur)"
        session.insert(CandidatureRecord(id: id, missionId: mission.id, statut: "EN_ATTENTE", message: nil,
                                         typeContratChoisi: choixContrat, creeLe: DateHeureParis.isoUTC(clock.now())), at: 0)
        guard CandidatureRules.candidaturePoseeRelue(try candidatureCourante(missionId: mission.id), id: id, missionId: mission.id) else {
            throw JoleneError(.contract, Self.messageRelecture)
        }
        return .confirmed(candidatureId: id, contratId: nil)
    }

    private func candidatureCourante(missionId: String) throws -> CandidatureRecord? {
        try toutes().first { $0.missionId == missionId }
    }

    private func propositionOuverte(_ candidatureId: String?) throws -> CandidatureRecord {
        guard let candidatureId, let proposition = try toutes().first(where: { $0.id == candidatureId }) else {
            throw JoleneError(.unknown, Textes.propositionIntrouvable)
        }
        guard proposition.statut == CandidatureRules.statutProposee else { throw JoleneError(.unknown, Textes.propositionPlusEnAttente) }
        guard CandidatureRules.propositionOuverte(proposition, maintenant: clock.now()) else {
            remplacer(proposition, statut: "EXPIREE")
            throw JoleneError(.unknown, Textes.propositionExpiree)
        }
        return proposition
    }

    private func accepterProposition(candidatureId: String?, mission: MissionRecord) throws -> CandidatureOutcome {
        guard let candidatureId, let proposition = try toutes().first(where: { $0.id == candidatureId }),
              proposition.missionId == mission.id, proposition.statut == CandidatureRules.statutProposee else {
            return .refusee(code: nil, message: Textes.propositionIntrouvable, documentsRequisPour: nil)
        }
        // Contrat relu (`type_contrat_choisi ?? type_contrat_recherche`) : un contrat déclaré LIBERAL à tort reste verrouillé.
        let contrat = CandidatureRules.contratProposition(typeContratChoisi: proposition.typeContratChoisi,
                                                          typeContratRecherche: mission.typeContratRecherche)
        guard !CandidatureRules.propositionVerrouillee(contrat: contrat) else {
            throw CandidatureVerrou.renvoiWeb(chemin: CandidatureVerrou.cheminProposition)
        }
        _ = try propositionOuverte(candidatureId)
        remplacer(proposition, statut: "ACCEPTEE")
        let contratId = try attribuerPuisRelire(mission.id)
        guard try toutes().first(where: { $0.id == candidatureId })?.statut == "ACCEPTEE" else {
            throw JoleneError(.contract, Self.messageRelecture)
        }
        return .confirmed(candidatureId: candidatureId, contratId: contratId)
    }

    private func remplacer(_ candidature: CandidatureRecord, statut: String) {
        var modifiee = candidature
        modifiee.statut = statut
        session.removeAll { $0.id == candidature.id }
        session.insert(modifiee, at: 0)
    }

    /// Attribue la mission au profil fictif, puis la relit comme la gateway Supabase (`ASSIGNEE` au soignant de la
    /// session) : `DemoMissionsGateway` la sert désormais `ASSIGNEE` (`missionsAttribuees`).
    private func attribuerPuisRelire(_ missionId: String) throws -> String {
        let contrat = "demo-contrat-\(missionId)"
        attributions[missionId] = contrat
        annulees.remove(missionId) // une mission remise en ligne puis reprise n'est plus annulée
        guard attributions[missionId] == contrat else { throw JoleneError(.contract, Self.messageRelecture) }
        return contrat
    }
}
