import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « pool urgence » (`Gateways.poolUrgence`), câblée par L4-T11 : l'état des candidatures est
    /// celui de la gateway de candidature du même monde (acceptation rapide par `CandidaturePort.confirmer(.urgence)`).
    static func poolUrgence(_ gateways: Gateways) -> PoolUrgencePort {
        DemoPoolUrgenceGateway(candidature: gateways.candidature as? DemoCandidatureGateway)
    }
}

extension DemoFixtures {
    /// `demo-pool-urgence.json` (L4-T11, `scripts/mobile/demo-fixtures/pool-urgence.mjs`) : état initial du pool (inactif,
    /// rayon 30, SMS refusés), missions urgentes servies (identifiant et distance ; ligne `missions` et créneaux lus dans
    /// `demo-missions.json`, ou dans `missions_supplementaires` pour la mission `TOUS` propre au pool).
    public struct PoolUrgenceFile: Decodable, Sendable {
        public struct Etat: Decodable, Sendable {
            public var poolActif: Bool
            public var rayonKm: Int
            public var smsOptIn: Bool
            enum CodingKeys: String, CodingKey { case poolActif = "pool_actif", rayonKm = "rayon_km", smsOptIn = "sms_opt_in" }
        }

        public struct Servie: Decodable, Sendable {
            public var missionId: String
            public var distanceKm: Double?
            enum CodingKeys: String, CodingKey { case missionId = "mission_id", distanceKm = "distance_km" }
        }

        public var fixedNow: String
        public var etat: Etat
        public var missions: [Servie]
        public var missionsSupplementaires: [MissionFixture]

        enum CodingKeys: String, CodingKey {
            case fixedNow = "fixed_now", etat, missions
            case missionsSupplementaires = "missions_supplementaires"
        }
    }

    public static func loadPoolUrgence() throws -> PoolUrgenceFile { try load("demo-pool-urgence") }
}

/// Pool urgence du monde démo (L4-T11, `LOT4_PLAN.md` §2.7) : aucun réseau, horloge fixée, état en mémoire pour la session
/// démo. Mêmes contrôles et même ordre que les RPC :
/// - état : missions servies encore `OUVERTE`, urgentes, à venir, non attribuées, dans le rayon (distance ≤ rayon, comme
///   `fn_pool_urgence_missions_pour_soignant`), statut de candidature relu dans `DemoCandidatureGateway` ;
/// - bascule : rayon hors 1-200 → refus verbatim de `fn_toggle_pool_urgence` ; documents du profil fictif réputés validés ;
/// - SMS : `pool_urgence_sms_opt_in` posé puis relu.
/// Chaque bascule rend l'état relu (`IssuePool.relu`). Refuse tout contexte qui n'est pas celui du profil fictif.
public actor DemoPoolUrgenceGateway: PoolUrgencePort {
    private let clock: any ClockPort
    private let candidature: DemoCandidatureGateway?
    private let fichier: @Sendable () throws -> DemoFixtures.PoolUrgenceFile
    private let missions: @Sendable () throws -> [DemoFixtures.MissionFixture]
    private var actif: Bool?
    private var rayon: Int?
    private var sms: Bool?

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), candidature: DemoCandidatureGateway?,
                fichier: @escaping @Sendable () throws -> DemoFixtures.PoolUrgenceFile = { try DemoFixtures.loadPoolUrgence() },
                missions: @escaping @Sendable () throws -> [DemoFixtures.MissionFixture] = DemoCandidatureGateway.missionsDesFixtures) {
        self.clock = clock
        self.candidature = candidature
        self.fichier = fichier
        self.missions = missions
    }

    public func etat(context: MissionReadContext) async throws -> EtatPool {
        try Self.verifier(context)
        let donnees = try fichier()
        let actif = self.actif ?? donnees.etat.poolActif
        let rayon = self.rayon ?? donnees.etat.rayonKm
        let sms = self.sms ?? donnees.etat.smsOptIn
        let fixtures = try missions()
        let etablissements = (try? DemoFixtures.loadEtablissements().etablissements) ?? []
        let attribuees = await candidature?.missionsAttribuees() ?? []
        let maintenant = clock.now()
        var servies: [MissionUrgente] = []
        for servie in donnees.missions {
            guard let fixture = fixtures.first(where: { $0.record.id == servie.missionId }),
                  fixture.record.statut == "OUVERTE", fixture.record.estUrgente, !attribuees.contains(servie.missionId),
                  let debut = PlanningHorlogeParis.instant(fixture.record.debutLe), debut > maintenant,
                  (servie.distanceKm ?? 0) <= Double(rayon) else { continue }
            let etablissement = etablissements.first { $0.id == fixture.record.etablissementId }
            let candidatureCourante = try await candidature?.candidatureDeMission(servie.missionId)
            let ligne = LignePoolUrgence(id: fixture.record.id, intitule: fixture.record.intitule,
                                         professionRequise: fixture.record.professionRequise,
                                         specialiteMedicaleRequise: fixture.record.specialiteMedicaleRequise,
                                         typeContratRecherche: fixture.record.typeContratRecherche,
                                         tauxHoraireBase: fixture.record.tauxHoraireBase, debutLe: fixture.record.debutLe,
                                         finLe: fixture.record.finLe, service: fixture.record.service,
                                         etablissementNom: etablissement?.nom, etablissementVille: etablissement?.adresseVille,
                                         distanceKm: servie.distanceKm, dejaCandidate: candidatureCourante != nil,
                                         statutCandidature: candidatureCourante?.statut)
            servies.append(ligne.missionUrgente(nbCreneaux: fixture.record.nbCreneaux, dureeHeures: fixture.record.dureeHeures,
                                                creneaux: fixture.creneaux))
        }
        // `ORDER BY m.debut_le`.
        servies.sort { $0.mission.record.debutLe < $1.mission.record.debutLe }
        return EtatPool(actif: actif, rayonKm: rayon, smsOptIn: sms, missions: servies)
    }

    public func basculer(actif: Bool, rayonKm: Int, context: MissionReadContext) async throws -> IssuePool {
        try Self.verifier(context)
        guard PoolUrgenceRegles.rayonServeur.contains(rayonKm) else { return .refuse(message: PoolUrgenceRegles.refusRayon) }
        self.actif = actif
        self.rayon = rayonKm
        return .relu(try await etat(context: context))
    }

    public func basculerSMS(_ actif: Bool, context: MissionReadContext) async throws -> IssuePool {
        try Self.verifier(context)
        sms = actif
        return .relu(try await etat(context: context))
    }

    private static func verifier(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}
