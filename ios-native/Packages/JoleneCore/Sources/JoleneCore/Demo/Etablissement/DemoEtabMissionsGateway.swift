import Foundation

/// `EtabMissionsPort` du monde démo (lot 5, T5) : `demo-etab-missions.json` (onze missions M1…M11 de
/// `LOT5_PLAN.md` §2.10, générées par `scripts/mobile/demo-etab-missions.mjs`), aucun réseau. Mêmes règles que la
/// gateway Supabase : contexte cohérent et compte fictif seulement (`.demoOnly`), lignes de l'établissement
/// confirmé seulement, ordre `debut_le` décroissant puis `id`, pages cumulatives de 50, compteurs et candidatures
/// en attente **dérivés** des lignes de la fixture (candidatures lues seulement avec la permission `candidatures`).
/// T6 : les décisions prises pendant la session démo (`DemoEtabEtatCandidatures`, partagé avec la gateway des
/// candidatures) sont appliquées aux lignes lues : une mission acceptée est relue `ASSIGNEE`, ses candidatures traitées.
public struct DemoEtabMissionsGateway: EtabMissionsPort {
    private let fixture: DemoFixtures.EtabMissionsFile?
    private let etat: DemoEtabEtatCandidatures?

    public init(etat: DemoEtabEtatCandidatures? = nil) {
        fixture = try? DemoFixtures.loadEtabMissions()
        self.etat = etat
    }

    private func donnees(_ context: EtablissementReadContext) async throws -> DemoFixtures.EtabMissionsFile {
        try DemoEtablissementWorld.verifier(context)
        guard let fixture else { throw JoleneError(.contract, "Fixture démo des missions établissement illisible.") }
        guard let etat else { return fixture }
        return fixture.appliquant(await etat.surcouche())
    }

    /// Lignes de l'établissement du contexte (jamais celles d'un autre identifiant).
    private func missionsDe(_ fixture: DemoFixtures.EtabMissionsFile, _ context: EtablissementReadContext) -> [EtabMissionResume] {
        fixture.missions
            .filter { $0.etablissementId == context.etablissementId }
            .sorted { ($0.debutLe ?? "", $1.id) > ($1.debutLe ?? "", $0.id) }
    }

    public func missions(context: EtablissementReadContext, statut: String?, page: Int) async throws -> EtabMissionsPage {
        let fixture = try await donnees(context)
        guard page >= 0 else { throw JoleneError(.contract, "Page de missions invalide.") }
        let toutes = missionsDe(fixture, context)
        let filtrees = statut.map { s in toutes.filter { $0.statut == s } } ?? toutes
        let limite = (page + 1) * EtabMissionsPage.taille
        let lues = Array(filtrees.prefix(limite))
        let ids = Set(lues.map(\.id))
        var creneaux: [String: [MissionSlot]] = [:]
        for creneau in fixture.creneaux where creneau.missionId.map(ids.contains) == true
            && creneau.typeCreneau == "PREVISIONNEL" && !creneau.estPause {
            creneaux[creneau.missionId ?? "", default: []].append(creneau)
        }
        var enAttente: [String: Int] = [:]
        if context.permissions.candidatures {
            let ouvertes = Set(lues.filter { $0.statut == "OUVERTE" }.map(\.id))
            for candidature in fixture.candidatures where candidature.statut == "EN_ATTENTE" && ouvertes.contains(candidature.missionId) {
                enAttente[candidature.missionId, default: 0] += 1
            }
        }
        return EtabMissionsPage(missions: lues, page: page, aSuivre: lues.count == limite,
                                compteurs: EtabMissionsCompteurs(statuts: toutes.map(\.statut)),
                                candidaturesEnAttente: enAttente, creneaux: creneaux)
    }

    public func mission(id: String, context: EtablissementReadContext) async throws -> EtabMissionDetail? {
        let fixture = try await donnees(context)
        guard let mission = missionsDe(fixture, context).first(where: { $0.id == id }) else { return nil }
        let creneaux = fixture.creneaux.filter { $0.missionId == id && $0.typeCreneau == "PREVISIONNEL" && !$0.estPause }
        var enAttente: Int?
        if context.permissions.candidatures, mission.statut == "OUVERTE", mission.modeAttribution == "CANDIDATURE" {
            enAttente = fixture.candidatures.filter { $0.missionId == id && $0.statut == "EN_ATTENTE" }.count
        }
        return EtabMissionDetail(mission: mission, creneaux: creneaux, soignantAssigneId: mission.soignantAssigneId,
                                 candidaturesEnAttente: enAttente)
    }

    /// Comme `fn_soignant_pour_etablissement` : `nil` pour un soignant inconnu (supprimé), jamais un profil vide.
    public func soignant(id: String, context: EtablissementReadContext) async throws -> SoignantPourEtab? {
        let fixture = try await donnees(context)
        return fixture.soignants.first { $0.id == id }
    }
}

// MARK: - Fixture

public extension DemoFixtures {
    /// Candidature de la fixture (T5 : liste et compteurs ; T6 : soignant et message de la lecture habilitée).
    struct CandidatureEtabDemo: Decodable, Equatable, Sendable {
        public var id: String
        public var missionId: String
        public var soignantId: String?
        public var message: String?
        public var statut: String
        public var creeLe: String?
        enum CodingKeys: String, CodingKey {
            case id, statut, message, missionId = "mission_id", soignantId = "soignant_id", creeLe = "cree_le"
        }
    }

    /// `demo-etab-missions.json`.
    struct EtabMissionsFile: Decodable, Sendable {
        public var fixedNow: String
        public var etablissementId: String
        public var missions: [EtabMissionResume]
        public var creneaux: [MissionSlot]
        public var candidatures: [CandidatureEtabDemo]
        public var soignants: [SoignantPourEtab]
        /// Les mêmes soignants vus par la lecture habilitée (nom à l'initiale), dérivés par le générateur (T6).
        public var candidats: [CandidatHabilite]
        enum CodingKeys: String, CodingKey {
            case fixedNow = "fixed_now", etablissementId = "etablissement_id", missions, creneaux, candidatures, soignants
            case candidats
        }

        /// Lignes relues après les décisions de la session démo : statuts de candidature décidés, mission acceptée
        /// `ASSIGNEE` à son soignant (comme `fn_finaliser_attribution_mission`).
        func appliquant(_ surcouche: DemoEtabEtatCandidatures.Surcouche) -> EtabMissionsFile {
            var copie = self
            copie.candidatures = candidatures.map { ligne in
                var relue = ligne
                if let statut = surcouche.statuts[ligne.id] { relue.statut = statut }
                return relue
            }
            copie.missions = missions.map { mission in
                guard let soignant = surcouche.assignations[mission.id] else { return mission }
                var relue = mission
                relue.statut = CandidaturesEtabRules.statutMissionAssignee
                relue.soignantAssigneId = soignant
                return relue
            }
            return copie
        }
    }

    static func loadEtabMissions() throws -> EtabMissionsFile { try load("demo-etab-missions") }
}
