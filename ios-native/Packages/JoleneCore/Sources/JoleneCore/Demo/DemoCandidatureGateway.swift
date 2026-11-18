import Foundation

/// Candidature du monde démo (lot 1, T6a, `LOT1_PLAN.md` §2.7) : aucun réseau, horloge fixée, état en
/// mémoire pour la session démo (rien n'est persisté entre deux lancements). Mêmes contrôles et mêmes
/// textes que `fn_confirmer_action_planning_v1` et ses délégués, dans le même ordre (mission ouverte,
/// planning confirmé identique au planning live, puis l'action) ; chaque mutation est relue dans l'acteur
/// avant d'annoncer un succès, comme la gateway Supabase relit le serveur.
///
/// - POSTULER → candidature `EN_ATTENTE` de session, visible dans Mes missions (`candidaturesDeSession`,
///   point de fusion de `DemoMesMissionsGateway`) ; une seconde candidature sur la même mission est
///   refusée (« Vous avez déjà postulé à cette mission », comme le serveur) ;
/// - ACCEPTER → mission attribuée au profil fictif et contrat démo ; refusé en mode candidature ;
/// - PROPOSITION → proposition `PROPOSEE` de moins de 2 h acceptée (`ACCEPTEE`) et mission attribuée ;
///   refus par `refuserProposition` (`REFUSEE`), expiration à 2 h comme `fn_repondre_proposition` ;
/// - mission `TOUS` sans choix pour un profil `MIXTE` → `choixRequis` avec les options du serveur.
///
/// Les annulations restent verrouillées jusqu'à T7 (aucun état démo inventé). Refuse tout contexte qui
/// n'est pas celui du profil fictif (`.demoOnly`).
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
        public static let choixContrat = [
            ChoixContratOption(value: "SALARIE", label: "Salarié (CDD / bulletin de paie)"),
            ChoixContratOption(value: "LIBERAL", label: "Libéral (note d'honoraires)"),
        ]
    }

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

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow),
                missions: @escaping @Sendable () throws -> [DemoFixtures.MissionFixture] = { try DemoFixtures.loadMissions().missions },
                candidaturesInitiales: @escaping @Sendable () throws -> [CandidatureRecord] = DemoCandidatureGateway.candidaturesDesFixtures) {
        self.clock = clock
        self.missions = missions
        self.candidaturesInitiales = candidaturesInitiales
    }

    /// Candidatures en attente de `demo-mes-missions.json` et proposition de l'Accueil (`demo-dashboard.json`).
    public static let candidaturesDesFixtures: @Sendable () throws -> [CandidatureRecord] = {
        let attente = try DemoFixtures.loadMesMissions().candidatures
        let propositions = try DemoFixtures.loadDashboard().dashboard.propositions.map {
            CandidatureRecord(id: $0.id, missionId: $0.missionId, statut: CandidatureRules.statutProposee, message: nil,
                              typeContratChoisi: $0.typeContratChoisi, creeLe: $0.creeLe)
        }
        return attente + propositions
    }

    /// Candidatures de la session démo, lues par `DemoMesMissionsGateway` (point de fusion de T5).
    public func candidaturesDeSession() -> [CandidatureRecord] { session }

    /// Mission attribuée au profil fictif pendant la session (relecture des tests et des écrans).
    public func contratAttribue(missionId: String) -> String? { attributions[missionId] }

    // MARK: - CandidaturePort

    public func confirmer(action: ActionPlanning, missionId: String, creneaux: [CreneauConfirmePayload], message: String?,
                          choixContrat: String?, candidatureId: String?, context: MissionReadContext) async throws -> CandidatureOutcome {
        try Self.verifier(context)
        guard action == .postuler || action == .accepter || action == .proposition else {
            throw JoleneError(.contract, "Action \(action.rawValue) non servie au lot 1.")
        }
        guard let fixture = try missions().first(where: { $0.record.id == missionId }),
              fixture.record.statut == "OUVERTE", attributions[missionId] == nil else {
            return .refusee(code: nil, message: Textes.missionIndisponible, documentsRequisPour: nil)
        }
        let attendus = CreneauxConfirmes.pourAction(PlanningCandidatInput(record: fixture.record, creneaux: fixture.creneaux))
        guard let attendus, !attendus.isEmpty, attendus.count == creneaux.count, Set(attendus) == Set(creneaux) else {
            return .planningAReconfirmer(code: Self.codePlanningModifie, message: Textes.planningModifie)
        }
        if action == .proposition {
            return try accepterProposition(candidatureId: candidatureId, missionId: missionId)
        }
        if action == .accepter, fixture.record.modeAttribution == CandidatureRules.modeCandidature {
            throw JoleneError(.unknown, Textes.candidatureRequise)
        }
        if action == .postuler, try toutes().contains(where: { $0.missionId == missionId }) {
            throw JoleneError(.unknown, Textes.dejaPostule)
        }
        if fixture.record.typeContratRecherche == "TOUS", context.profile.typeExercice == "MIXTE",
           (choixContrat ?? "").isEmpty {
            return .choixRequis(Textes.choixContrat)
        }
        if action == .postuler {
            compteur += 1
            let id = "demo-candidature-session-\(compteur)"
            session.insert(CandidatureRecord(id: id, missionId: missionId, statut: "EN_ATTENTE", message: message,
                                             typeContratChoisi: choixContrat, creeLe: DateHeureParis.isoUTC(clock.now())), at: 0)
            guard CandidatureRules.candidaturePoseeRelue(try candidatureCourante(missionId: missionId), id: id, missionId: missionId) else {
                throw JoleneError(.contract, Self.messageRelecture)
            }
            return .confirmed(candidatureId: id, contratId: nil)
        }
        let contrat = attribuer(missionId)
        return .confirmed(candidatureId: nil, contratId: contrat)
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

    public func annulerCandidature(id: String, motif: String, texte: String, justificatifPath: String?,
                                   context: MissionReadContext) async throws -> AnnulationOutcome {
        throw UnwiredPorts.erreur(port: "annulation", tranche: "T7")
    }

    public func annulerMission(id: String, motif: String?, context: MissionReadContext) async throws -> AnnulationOutcome {
        throw UnwiredPorts.erreur(port: "annulation", tranche: "T7")
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
        return (session + (try candidaturesInitiales())).filter { vues.insert($0.id).inserted }
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

    private func accepterProposition(candidatureId: String?, missionId: String) throws -> CandidatureOutcome {
        guard let candidatureId, let proposition = try toutes().first(where: { $0.id == candidatureId }),
              proposition.missionId == missionId, proposition.statut == CandidatureRules.statutProposee else {
            return .refusee(code: nil, message: Textes.propositionIntrouvable, documentsRequisPour: nil)
        }
        _ = try propositionOuverte(candidatureId)
        remplacer(proposition, statut: "ACCEPTEE")
        return .confirmed(candidatureId: candidatureId, contratId: attribuer(missionId))
    }

    private func remplacer(_ candidature: CandidatureRecord, statut: String) {
        var modifiee = candidature
        modifiee.statut = statut
        session.removeAll { $0.id == candidature.id }
        session.insert(modifiee, at: 0)
    }

    private func attribuer(_ missionId: String) -> String {
        let contrat = "demo-contrat-\(missionId)"
        attributions[missionId] = contrat
        return contrat
    }
}
