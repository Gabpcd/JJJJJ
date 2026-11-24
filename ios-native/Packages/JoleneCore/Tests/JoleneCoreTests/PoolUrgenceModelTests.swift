import XCTest
@testable import JoleneCore

/// Pool urgence et exclusions (L4-T11) sur le monde démo (`DemoPoolUrgenceGateway`, `DemoExclusionsGateway`,
/// `DemoCandidatureGateway`, fixtures `demo-pool-urgence.json` et `demo-exclusions.json`) et sur des ports témoins :
/// succès confirmés par relecture (PRINCIPES §3), refus verbatim, planning exact obligatoire, `choixRequis` jamais rejoué.
@MainActor
final class PoolUrgenceModelTests: XCTestCase {
    private enum Ids {
        static let proche = "demo-mission-001"
        static let tous = "demo-mission-urgence-tous"
        static let moyenne = "demo-mission-016"
        static let lointaine = "demo-mission-021"
    }

    /// Port témoin : lecture réelle du monde démo, bascule remplacée.
    private struct PoolTemoin: PoolUrgencePort {
        let demo: DemoPoolUrgenceGateway
        let bascule: @Sendable () throws -> IssuePool
        func etat(context: MissionReadContext) async throws -> EtatPool { try await demo.etat(context: context) }
        func basculer(actif: Bool, rayonKm: Int, context: MissionReadContext) async throws -> IssuePool { try bascule() }
        func basculerSMS(_ actif: Bool, context: MissionReadContext) async throws -> IssuePool { try bascule() }
    }

    private func session(pool: (any PoolUrgencePort)? = nil) async throws -> (SessionController, SessionSnapshot, Gateways) {
        var gateways = DemoWorld.gateways()
        if let pool { gateways.poolUrgence = pool }
        let controller = SessionController(gateways: gateways)
        let state = await controller.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        return (controller, try XCTUnwrap(state.snapshot, "session démo prête attendue, obtenu \(state)"), gateways)
    }

    private func modele(pool: (any PoolUrgencePort)? = nil) async throws -> PoolUrgenceModel {
        let (controller, snapshot, _) = try await session(pool: pool)
        let model = PoolUrgenceModel(controller: controller, snapshot: snapshot)
        await model.charger()
        return model
    }

    // MARK: - Pool

    func testActiverPuisRayon15ReluEtMissionsFiltrees() async throws {
        let model = try await modele()
        let initial = try XCTUnwrap(model.ecran.etat)
        XCTAssertFalse(initial.actif, "fixture : pool inactif")
        XCTAssertEqual(initial.rayonKm, 30)
        XCTAssertEqual(initial.missions.map(\.id), [Ids.proche, Ids.tous, Ids.moyenne, Ids.lointaine], "ordre debut_le")

        await model.basculer(actif: true)
        XCTAssertEqual(model.confirmation, PoolUrgenceTextes.active)
        XCTAssertEqual(model.ecran.etat?.actif, true)
        XCTAssertEqual(model.ecran.etat?.rayonKm, 30, "rayon courant conservé à l'activation")

        await model.validerRayon(15)
        XCTAssertEqual(model.confirmation, PoolUrgenceTextes.active)
        XCTAssertEqual(model.ecran.etat?.rayonKm, 15, "rayon relu")
        XCTAssertEqual(model.ecran.etat?.missions.map(\.id), [Ids.proche, Ids.tous, Ids.moyenne], "22 km : hors du rayon")

        await model.basculerSMS(true)
        XCTAssertEqual(model.confirmation, PoolUrgenceTextes.smsActives)
        XCTAssertEqual(model.ecran.etat?.smsOptIn, true)
    }

    func testRefusDocumentsVerbatimEtInterrupteurALEtatRelu() async throws {
        let demo = DemoPoolUrgenceGateway(candidature: nil)
        let model = try await modele(pool: PoolTemoin(demo: demo) { .refuse(message: PoolUrgenceRegles.refusDocuments) })
        await model.basculer(actif: true)
        XCTAssertEqual(model.erreur, PoolUrgenceRegles.refusDocuments, "refus serveur verbatim")
        XCTAssertTrue(model.documentsManquants, "lien vers les documents")
        XCTAssertEqual(model.ecran.etat?.actif, false, "l'interrupteur reste à l'état serveur")
        XCTAssertNil(model.confirmation)
    }

    func testRelectureQuiNeConfirmePasJamaisUnSucces() async throws {
        let demo = DemoPoolUrgenceGateway(candidature: nil)
        let inactif = EtatPool(actif: false, rayonKm: 30, smsOptIn: false, missions: [])
        let model = try await modele(pool: PoolTemoin(demo: demo) { .relu(inactif) })
        await model.basculer(actif: true)
        XCTAssertEqual(model.erreur, PoolUrgenceTextes.nonConfirmee)
        XCTAssertNil(model.confirmation)
    }

    func testRayonHorsBornesServeurRefuseVerbatimEnDemo() async throws {
        let demo = DemoPoolUrgenceGateway(candidature: nil)
        let issue = try await demo.basculer(actif: true, rayonKm: 0, context: DemoWorld.context)
        XCTAssertEqual(issue, .refuse(message: "Le rayon doit être compris entre 1 et 200 km."))
        XCTAssertEqual(PoolUrgenceRegles.rayonCurseur(nil), 15)
        XCTAssertEqual(PoolUrgenceRegles.rayonCurseur(120), 50)
        XCTAssertEqual(PoolUrgenceRegles.rayonCurseur(1), 5)
    }

    // MARK: - Acceptation rapide

    func testAccepterAfficheEnAttenteSeulementApresRelecture() async throws {
        let model = try await modele()
        await model.basculer(actif: true)
        let mission = try XCTUnwrap(model.ecran.etat?.missions.first { $0.id == Ids.proche })
        XCTAssertTrue(PoolUrgenceRegles.acceptable(mission), "planning exact, aucune candidature")
        XCTAssertNil(PoolUrgenceRegles.libelleStatut(mission))

        await model.accepter(mission)
        XCTAssertEqual(model.confirmation, PoolUrgenceTextes.acceptationEnregistree)
        let relue = try XCTUnwrap(model.ecran.etat?.missions.first { $0.id == Ids.proche })
        XCTAssertEqual(relue.statutCandidature, PoolUrgenceRegles.statutEnAttenteValidation)
        XCTAssertEqual(PoolUrgenceRegles.libelleStatut(relue), "En attente de validation étab")
        XCTAssertFalse(PoolUrgenceRegles.acceptable(relue), "aucune seconde acceptation")

        await model.accepter(relue)
        XCTAssertEqual(model.erreur, DemoCandidatureGateway.Textes.dejaCandidate, "refus serveur verbatim")
    }

    func testChoixDeContratRequisRenvoieAuDetailSansRejouer() async throws {
        let model = try await modele()
        await model.basculer(actif: true)
        let mission = try XCTUnwrap(model.ecran.etat?.missions.first { $0.id == Ids.tous })
        await model.accepter(mission)
        XCTAssertEqual(model.erreur, "Choisissez votre mode de contrat.")
        XCTAssertTrue(model.choixRequis.contains(Ids.tous), "lien vers le détail de la mission (lot 1)")
        XCTAssertNil(model.ecran.etat?.missions.first { $0.id == Ids.tous }?.statutCandidature, "aucune candidature posée")
    }

    func testPlanningNonExactJamaisEnvoye() async throws {
        let model = try await modele()
        let ligne = LignePoolUrgence(id: Ids.proche, intitule: "x", professionRequise: "IDE", typeContratRecherche: "SALARIE",
                                     tauxHoraireBase: 20, debutLe: "2026-11-03T07:00:00.000Z", finLe: "2026-11-03T15:00:00.000Z",
                                     service: nil, etablissementNom: nil, etablissementVille: nil, distanceKm: nil,
                                     dejaCandidate: false, statutCandidature: nil)
        let nonExacte = ligne.missionUrgente(nbCreneaux: 2, dureeHeures: 8, creneaux: [])
        XCTAssertFalse(nonExacte.mission.planningExact, "deux créneaux attendus, aucun lu")
        await model.accepter(nonExacte)
        XCTAssertEqual(model.erreur, "Le planning exact doit être rechargé avant d’accepter.")
        XCTAssertNil(model.ecran.etat?.missions.first { $0.id == Ids.proche }?.statutCandidature, "aucun envoi")
    }

    // MARK: - Exclusions

    func testExclusionsListeesPuisExclureEtRetirerConfirmesParRelecture() async throws {
        let (controller, snapshot, _) = try await session()
        let model = ExclusionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        let listes = try XCTUnwrap(model.ecran.listes)
        XCTAssertEqual(listes.envoyees.map(\.excluId), ["demo-etab-ancien"])
        XCTAssertEqual(listes.envoyees.first?.etablissementNom, "Résidence fictive des Acacias")
        XCTAssertEqual(listes.recues.map(\.id), ["demo-exclusion-recue-001"])
        XCTAssertEqual(listes.recues.first?.etablissementNom, "Clinique fictive des Tilleuls")

        let exclue = await model.exclure(etablissementId: "demo-etab-2", motif: "  Trop loin  ")
        XCTAssertTrue(exclue)
        XCTAssertEqual(model.confirmation, "Exclusion enregistrée. Les missions ne seront plus visibles.")
        XCTAssertEqual(model.ecran.listes?.envoyees.first?.excluId, "demo-etab-2", "la plus récente en tête")
        XCTAssertEqual(model.ecran.listes?.envoyees.first?.motif, "Trop loin")
        XCTAssertEqual(model.ecran.listes?.envoyees.first?.etablissementNom, "Établissement fictif des Lilas")

        let doublon = await model.exclure(etablissementId: "demo-etab-2", motif: "")
        XCTAssertFalse(doublon)
        XCTAssertEqual(model.erreur, "Exclusion déjà existante")

        let cible = try XCTUnwrap(model.ecran.listes?.envoyees.first)
        let retiree = await model.retirer(cible)
        XCTAssertTrue(retiree)
        XCTAssertEqual(model.confirmation, ExclusionsTextes.supprimee)
        XCTAssertEqual(model.ecran.listes?.envoyees.map(\.excluId), ["demo-etab-ancien"])
        let absente = await model.retirer(cible)
        XCTAssertFalse(absente)
        XCTAssertEqual(model.erreur, "Exclusion introuvable")
        XCTAssertEqual(ExclusionsRegles.motifEnvoye("   "), nil)
        XCTAssertEqual(ExclusionsRegles.depuis(ExclusionsRegles.date("2026-10-13T00:00:00.000Z")), "Depuis le 13 oct. 2026")
    }

    // MARK: - Câblage

    func testPortsCablesDansLeMondeDemo() {
        let gateways = DemoWorld.gateways()
        XCTAssertFalse(gateways.poolUrgence is UnwiredPort)
        XCTAssertFalse(gateways.exclusions is UnwiredPort)
        XCTAssertTrue(EcranSecondaire.poolUrgence.estLivre)
        XCTAssertTrue(EcranSecondaire.exclusions.estLivre)
    }
}
