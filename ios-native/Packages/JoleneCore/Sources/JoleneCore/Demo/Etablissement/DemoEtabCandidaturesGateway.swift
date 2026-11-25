import Foundation

/// Décisions de la session démo sur les candidatures (lot 5, T6), partagées par les gateways démo des missions et des
/// candidatures : une seule source pour la mission acceptée et les statuts relus (état dérivé). Remis à zéro à chaque
/// lancement (aucun stockage).
public actor DemoEtabEtatCandidatures {
    /// Statuts décidés et missions attribuées pendant la session.
    public struct Surcouche: Equatable, Sendable {
        public var statuts: [String: String] = [:]
        public var assignations: [String: String] = [:]
    }

    private var surcoucheCourante = Surcouche()
    /// `-JOLENE_DEMO_PLANNING_MODIFIE 1` : la première acceptation répond `PLANNING_MODIFIE_RECONFIRMER`.
    private var planningModifieEnAttente: Bool

    public init(planningModifie: Bool = false) {
        planningModifieEnAttente = planningModifie
    }

    public func surcouche() -> Surcouche { surcoucheCourante }

    func consommerPlanningModifie() -> Bool {
        defer { planningModifieEnAttente = false }
        return planningModifieEnAttente
    }

    /// Acceptation (`fn_traiter_candidature`, l.62368-62378) : candidature acceptée, autres candidatures en attente de
    /// la mission refusées, mission attribuée.
    func accepter(candidatureId: String, missionId: String, soignantId: String, autresEnAttente: [String]) {
        surcoucheCourante.statuts[candidatureId] = CandidaturesEtabRules.statutAcceptee
        for autre in autresEnAttente where autre != candidatureId {
            surcoucheCourante.statuts[autre] = CandidaturesEtabRules.statutRefusee
        }
        surcoucheCourante.assignations[missionId] = soignantId
    }

    func refuser(candidatureId: String) {
        surcoucheCourante.statuts[candidatureId] = CandidaturesEtabRules.statutRefusee
    }
}

/// `EtabCandidaturesPort` du monde démo (lot 5, T6) : candidatures de `demo-etab-missions.json` (M1 : trois candidats
/// dont une étudiante aide-soignante ; M3 : planning incomplet ; M9 `TOUS` et M10 `MEDECIN` : acceptation renvoyée au
/// web), aucun réseau. Mêmes règles que la gateway Supabase : contexte cohérent et compte fictif seulement
/// (`.demoOnly`), lecture refusée sans la permission `candidatures` ou hors de l'établissement (message serveur de
/// `fn_lire_candidatures_mission_habilitee`), aiguillage D25 avant tout traitement, planning confirmé comparé au
/// planning de la fixture, issue jamais relue par la gateway (l'écran relit la lecture).
public struct DemoEtabCandidaturesGateway: EtabCandidaturesPort {
    /// `fn_lire_candidatures_mission_habilitee` (l.40067, l.40076, l.40087), texte serveur.
    static let accesRefuse = "Mission indisponible ou accès refusé"
    /// `fn_traiter_candidature_planning_v1_internal_20260810` (l.62560), texte serveur.
    static let candidatureIntrouvable = "Candidature introuvable."
    /// `fn_traiter_candidature` (l.62310), texte serveur.
    static let dejaTraitee = "Cette candidature a déjà été traitée."
    /// `fn_traiter_candidature_planning_v1_internal_20260810` (l.62647), texte serveur.
    static let planningModifie = "Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires."
    static let codePlanningModifie = "PLANNING_MODIFIE_RECONFIRMER"

    private let fixture: DemoFixtures.EtabMissionsFile?
    private let etat: DemoEtabEtatCandidatures
    /// T9 : missions publiées pendant la session, lues ici comme par la gateway des missions (aucune candidature).
    private let publications: DemoEtabEtatPublication?

    public init(etat: DemoEtabEtatCandidatures, publications: DemoEtabEtatPublication? = nil) {
        fixture = try? DemoFixtures.loadEtabMissions()
        self.etat = etat
        self.publications = publications
    }

    private func donnees(_ context: EtablissementReadContext) async throws -> DemoFixtures.EtabMissionsFile {
        try DemoEtablissementWorld.verifier(context)
        guard let fixture else { throw JoleneError(.contract, "Fixture démo des missions établissement illisible.") }
        let lues = fixture.appliquant(await etat.surcouche())
        guard let publications else { return lues }
        return lues.completant(await publications.surcouche())
    }

    public func lecture(missionId: String, context: EtablissementReadContext) async throws -> LectureCandidaturesHabilitee {
        let fixture = try await donnees(context)
        guard context.permissions.candidatures,
              let mission = fixture.missions.first(where: { $0.id == missionId && $0.etablissementId == context.etablissementId }) else {
            throw RefusAccesEtablissement(message: Self.accesRefuse)
        }
        let creneaux = fixture.creneaux
            .filter { $0.missionId == missionId && $0.typeCreneau == "PREVISIONNEL" && !$0.estPause }
            .sorted { ($0.debut, $0.id ?? "") < ($1.debut, $1.id ?? "") }
        let candidatures = fixture.candidatures
            .filter { $0.missionId == missionId }
            .sorted { ($0.creeLe ?? "", $0.id) < ($1.creeLe ?? "", $1.id) }
            .map { ligne in
                CandidatureHabilitee(id: ligne.id, soignantId: ligne.soignantId, statut: ligne.statut, creeLe: ligne.creeLe,
                                     message: ligne.message, soignant: fixture.candidats.first { $0.id == ligne.soignantId })
            }
        return LectureCandidaturesHabilitee(missionId: mission.id, statutMission: mission.statut, nbCreneaux: mission.nbCreneaux,
                                            creneaux: creneaux, candidatures: candidatures, intitule: mission.intitule,
                                            etablissementId: mission.etablissementId, modeAttribution: mission.modeAttribution,
                                            professionRequise: mission.professionRequise)
    }

    public func accepter(candidatureId: String, creneauxConfirmes: [CreneauConfirmePayload],
                         context: EtablissementReadContext) async throws -> TraitementCandidatureOutcome {
        let fixture = try await donnees(context)
        guard context.permissions.candidatures else { return .accesRefuse(message: Self.accesRefuse) }
        guard let candidature = fixture.candidatures.first(where: { $0.id == candidatureId }),
              let mission = fixture.missions.first(where: { $0.id == candidature.missionId && $0.etablissementId == context.etablissementId }) else {
            return .refusee(code: nil, message: Self.candidatureIntrouvable, documentsRequisPour: nil)
        }
        // D25 avant tout traitement, comme la gateway Supabase ; l'étudiant aide-soignant est aiguillé par l'écran (le
        // serveur répondrait `CADRE_ETUDIANT_A_CONFIRMER`, que le natif renvoie aussi au web).
        let candidat = fixture.candidats.first { $0.id == candidature.soignantId }
        if let motif = CandidaturesEtabRules.motifRenvoiWeb(typeContratRecherche: mission.typeContratRecherche,
                                                            professionRequise: mission.professionRequise, candidat: candidat) {
            return .renvoiWeb(motif: motif)
        }
        guard candidature.statut == CandidaturesEtabRules.statutEnAttente else { throw JoleneError(.unknown, Self.dejaTraitee) }
        let attendus = fixture.creneaux
            .filter { $0.missionId == mission.id && $0.typeCreneau == "PREVISIONNEL" && !$0.estPause }
            .compactMap { creneau in creneau.finRenseignee.map { CreneauConfirme(debut: creneau.debut, fin: $0) } }
        if await etat.consommerPlanningModifie() || attendus.count != (mission.nbCreneaux ?? 0)
            || attendus.sorted(by: Self.ordre) != creneauxConfirmes.sorted(by: Self.ordre) {
            return .planningAReconfirmer(code: Self.codePlanningModifie, message: Self.planningModifie)
        }
        guard let soignant = candidature.soignantId else {
            return .refusee(code: nil, message: Self.candidatureIntrouvable, documentsRequisPour: nil)
        }
        let autres = fixture.candidatures
            .filter { $0.missionId == mission.id && $0.statut == CandidaturesEtabRules.statutEnAttente }
            .map(\.id)
        await etat.accepter(candidatureId: candidatureId, missionId: mission.id, soignantId: soignant, autresEnAttente: autres)
        return .acceptee(contratId: nil)
    }

    public func refuser(candidatureId: String, context: EtablissementReadContext) async throws -> TraitementCandidatureOutcome {
        let fixture = try await donnees(context)
        guard context.permissions.candidatures else { return .accesRefuse(message: Self.accesRefuse) }
        guard let candidature = fixture.candidatures.first(where: { $0.id == candidatureId }),
              fixture.missions.contains(where: { $0.id == candidature.missionId && $0.etablissementId == context.etablissementId }) else {
            return .refusee(code: nil, message: Self.candidatureIntrouvable, documentsRequisPour: nil)
        }
        guard candidature.statut == CandidaturesEtabRules.statutEnAttente else { throw JoleneError(.unknown, Self.dejaTraitee) }
        await etat.refuser(candidatureId: candidatureId)
        return .refusEnregistre
    }

    private static func ordre(_ a: CreneauConfirme, _ b: CreneauConfirme) -> Bool { (a.debut, a.fin) < (b.debut, b.fin) }
}
