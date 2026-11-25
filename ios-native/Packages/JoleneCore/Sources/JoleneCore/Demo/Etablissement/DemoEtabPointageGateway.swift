import Foundation

/// Lectures de l'état du pointage servies pendant la session démo, par mission (rang de la prochaine lecture).
public actor DemoEtabLecturesPointage {
    private var lectures: [String: Int] = [:]

    public init() {}

    func suivante(_ missionId: String) -> Int {
        let rang = lectures[missionId, default: 0]
        lectures[missionId] = rang + 1
        return rang
    }
}

/// `EtabPointagePort` du monde démo (lot 5, T7) : réponses de `fn_etat_pointage_mission` **enregistrées** dans
/// `demo-etab-pointage.json` (générée par `scripts/mobile/demo-etab-pointage.mjs`) et rejouées dans l'ordre, mission par
/// mission ; planning et statut lus dans `demo-etab-missions.json` (décisions de la session T6 comprises). Aucun réseau,
/// aucun code calculé : M4 sert `123456` deux lectures puis l'état relu après le scan d'arrivée (`100002`), M5 n'a pas de
/// contrat signé, M6 attend son second créneau.
///
/// Mêmes règles que le serveur : contexte cohérent et compte fictif seulement (`.demoOnly`), mission de l'établissement
/// confirmé sinon `{error}` verbatim (`Mission introuvable`, `Accès interdit`, l.35692 et l.35701), code servi aux seuls
/// membres habilités au pointage (B5b, l.35617-35620) ; signature lue seulement avec cette permission (le serveur lève
/// alors 42501, que la gateway Supabase rend `false`).
public struct DemoEtabPointageGateway: EtabPointagePort {
    // source: supabase/schema/public.sql l.35692 (fn_etat_pointage_mission)
    static let erreurMissionIntrouvable = "Mission introuvable"
    // source: supabase/schema/public.sql l.35701 (fn_etat_pointage_mission)
    static let erreurAccesInterdit = "Accès interdit"
    static let planningIllisible = "Le planning de cette mission n'a pas pu être relu."

    private let pointage: DemoFixtures.EtabPointageFile?
    private let missions: DemoFixtures.EtabMissionsFile?
    private let decisions: DemoEtabEtatCandidatures?
    private let lectures: DemoEtabLecturesPointage
    public let cadenceLecture: TimeInterval

    /// `cadence` : `-JOLENE_POLL_INTERVAL` (DEBUG) ; `nil` = cadence nominale (D23).
    public init(decisions: DemoEtabEtatCandidatures? = nil, cadence: TimeInterval? = nil,
                lectures: DemoEtabLecturesPointage = DemoEtabLecturesPointage()) {
        pointage = try? DemoFixtures.loadEtabPointage()
        missions = try? DemoFixtures.loadEtabMissions()
        self.decisions = decisions
        self.lectures = lectures
        cadenceLecture = cadence ?? CodeRotatifModel.cadenceNominale
    }

    private func donnees(_ context: EtablissementReadContext) async throws -> (DemoFixtures.EtabPointageFile, DemoFixtures.EtabMissionsFile) {
        try DemoEtablissementWorld.verifier(context)
        guard let pointage, let missions else { throw JoleneError(.contract, "Fixture démo du pointage établissement illisible.") }
        guard let decisions else { return (pointage, missions) }
        return (pointage, missions.appliquant(await decisions.surcouche()))
    }

    public func etat(missionId: String, context: EtablissementReadContext) async throws -> EtatPointageEtab {
        let (pointage, missions) = try await donnees(context)
        guard let mission = missions.missions.first(where: { $0.id == missionId }) else {
            return EtatPointageEtab(statut: nil, prochainTypeScan: nil, segmentOuvert: false, segments: [],
                                    codePointageActif: nil, erreur: Self.erreurMissionIntrouvable)
        }
        guard mission.etablissementId == context.etablissementId else {
            return EtatPointageEtab(statut: nil, prochainTypeScan: nil, segmentOuvert: false, segments: [],
                                    codePointageActif: nil, erreur: Self.erreurAccesInterdit)
        }
        let rang = await lectures.suivante(missionId)
        var etat = pointage.scenarios.first(where: { $0.missionId == missionId })?.etat(rang: rang)
            ?? EtatPointageEtab(statut: mission.statut, prochainTypeScan: "OUVERTURE", segmentOuvert: false, segments: [],
                                codePointageActif: nil)
        if !context.permissions.pointage { etat.codePointageActif = nil }
        return etat
    }

    public func contratSigne(missionId: String, context: EtablissementReadContext) async throws -> Bool {
        let (pointage, missions) = try await donnees(context)
        guard context.permissions.pointage,
              missions.missions.contains(where: { $0.id == missionId && $0.etablissementId == context.etablissementId }) else {
            return false
        }
        return pointage.contratsSignes.contains(missionId)
    }

    public func planning(missionId: String, context: EtablissementReadContext) async throws -> PlanningMission {
        let (_, missions) = try await donnees(context)
        guard let mission = missions.missions.first(where: { $0.id == missionId && $0.etablissementId == context.etablissementId }) else {
            throw JoleneError(.contract, Self.planningIllisible)
        }
        let creneaux = missions.creneaux
            .filter { $0.missionId == missionId && $0.typeCreneau == "PREVISIONNEL" && !$0.estPause }
            .sorted { ($0.debut, $0.id ?? "") < ($1.debut, $1.id ?? "") }
        return PlanningMission(mission: mission.planningAttendu, creneaux: creneaux)
    }
}

// MARK: - Fixture

public extension DemoFixtures {
    /// Réponse enregistrée de `fn_etat_pointage_mission`, servie `lectures` fois (`nil` : servie ensuite sans fin).
    struct EtatPointageEtabDemo: Decodable, Sendable {
        public var lectures: Int?
        public var etat: EtatPointageEtab
    }

    struct ScenarioPointageEtabDemo: Decodable, Sendable {
        public var missionId: String
        public var etats: [EtatPointageEtabDemo]
        enum CodingKeys: String, CodingKey { case missionId = "mission_id", etats }

        /// Réponse de la lecture de rang `rang` (à partir de 0) : les états se succèdent, le dernier reste servi.
        func etat(rang: Int) -> EtatPointageEtab? {
            var restant = rang
            for (index, enregistre) in etats.enumerated() {
                guard let lectures = enregistre.lectures, index < etats.count - 1 else { return enregistre.etat }
                if restant < lectures { return enregistre.etat }
                restant -= lectures
            }
            return etats.last?.etat
        }
    }

    /// `demo-etab-pointage.json`.
    struct EtabPointageFile: Decodable, Sendable {
        public var fixedNow: String
        public var contratsSignes: [String]
        public var scenarios: [ScenarioPointageEtabDemo]
        enum CodingKeys: String, CodingKey {
            case fixedNow = "fixed_now", contratsSignes = "contrats_signes", scenarios
        }
    }

    static func loadEtabPointage() throws -> EtabPointageFile { try load("demo-etab-pointage") }
}
