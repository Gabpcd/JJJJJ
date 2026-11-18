import Foundation
import XCTest
@testable import JoleneCore

/// Candidature du monde démo (lot 1, T6a) : mêmes contrôles et mêmes textes que le serveur, relecture dans
/// l'acteur, candidatures de session visibles dans Mes missions, annulations verrouillées jusqu'à T7.
final class DemoCandidatureGatewayTests: XCTestCase {
    private let context = DemoWorld.context

    private func fixture(_ id: String) throws -> DemoFixtures.MissionFixture {
        try XCTUnwrap(try DemoFixtures.loadMissions().missions.first { $0.record.id == id }, id)
    }

    private func creneaux(_ id: String) throws -> [CreneauConfirme] {
        let mission = try fixture(id)
        return try XCTUnwrap(CreneauxConfirmes.pourAction(PlanningCandidatInput(record: mission.record, creneaux: mission.creneaux)))
    }

    private func erreur(_ operation: () async throws -> Void) async -> JoleneError? {
        do {
            try await operation()
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("erreur inattendue : \(error)")
            return nil
        }
    }

    func testFixturesPortentLeModeDAttribution() throws {
        XCTAssertEqual(try fixture("demo-mission-004").record.modeAttribution, "CANDIDATURE")
        XCTAssertEqual(try fixture("demo-mission-001").record.modeAttribution, "PREMIER_ARRIVE")
        XCTAssertEqual(CandidatureRules.action(pour: try fixture("demo-mission-014").record), .postuler)
        // Les candidatures en attente de Mes missions portent sur des missions en mode candidature.
        for candidature in try DemoFixtures.loadMesMissions().candidatures {
            XCTAssertEqual(try fixture(candidature.missionId).record.modeAttribution, "CANDIDATURE", candidature.id)
        }
    }

    func testPostulerCreeUneCandidatureRelueVisibleDansMesMissions() async throws {
        let gateways = DemoWorld.gateways()
        let issue = try await gateways.candidature.confirmer(action: .postuler, missionId: "demo-mission-014",
                                                             creneaux: try creneaux("demo-mission-014"), message: "Disponible",
                                                             choixContrat: nil, candidatureId: nil, context: context)
        guard case let .confirmed(candidatureId?, nil) = issue else { return XCTFail("issue : \(issue)") }
        let relue = try await gateways.candidature.candidature(missionId: "demo-mission-014", context: context)
        XCTAssertEqual(relue?.id, candidatureId)
        XCTAssertEqual(relue?.statut, "EN_ATTENTE")
        XCTAssertEqual(relue?.message, "Disponible")
        XCTAssertEqual(relue?.creeLe, "2026-11-02T00:00:00.000Z", "horloge fixée")
        let mesMissions = try await gateways.mesMissions.candidatures(context: context)
        XCTAssertEqual(mesMissions.first?.id, candidatureId, "la plus récente en tête de l'onglet Candidatures")
        XCTAssertEqual(mesMissions.count, 3, "deux candidatures des fixtures + celle de la session")

        let seconde = await erreur {
            _ = try await gateways.candidature.confirmer(action: .postuler, missionId: "demo-mission-014",
                                                         creneaux: try self.creneaux("demo-mission-014"), message: nil,
                                                         choixContrat: nil, candidatureId: nil, context: self.context)
        }
        XCTAssertEqual(seconde, JoleneError(.unknown, "Vous avez déjà postulé à cette mission"))
    }

    func testPlanningDifferentAReconfirmerSansRienEcrire() async throws {
        let gateway = DemoCandidatureGateway()
        var modifie = try creneaux("demo-mission-014")
        modifie[0].fin = "2026-11-16T16:00:00Z"
        let issue = try await gateway.confirmer(action: .postuler, missionId: "demo-mission-014", creneaux: modifie, message: nil,
                                                choixContrat: nil, candidatureId: nil, context: context)
        XCTAssertEqual(issue, .planningAReconfirmer(code: "PLANNING_MODIFIE_RECONFIRMER",
                                                    message: "Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires."))
        let vide = try await gateway.confirmer(action: .accepter, missionId: "demo-mission-001", creneaux: [], message: nil,
                                               choixContrat: nil, candidatureId: nil, context: context)
        XCTAssertEqual(vide, .planningAReconfirmer(code: "PLANNING_MODIFIE_RECONFIRMER", message: DemoCandidatureGateway.Textes.planningModifie))
        let sessions = await gateway.candidaturesDeSession()
        XCTAssertTrue(sessions.isEmpty)
        let contrat = await gateway.contratAttribue(missionId: "demo-mission-001")
        XCTAssertNil(contrat)
    }

    func testAccepterAttribueLaMissionPuisLaRendIndisponible() async throws {
        let gateway = DemoCandidatureGateway()
        let issue = try await gateway.confirmer(action: .accepter, missionId: "demo-mission-001",
                                                creneaux: try creneaux("demo-mission-001"), message: nil, choixContrat: nil,
                                                candidatureId: nil, context: context)
        XCTAssertEqual(issue, .confirmed(candidatureId: nil, contratId: "demo-contrat-demo-mission-001"))
        let contrat = await gateway.contratAttribue(missionId: "demo-mission-001")
        XCTAssertEqual(contrat, "demo-contrat-demo-mission-001")
        let encore = try await gateway.confirmer(action: .accepter, missionId: "demo-mission-001",
                                                 creneaux: try creneaux("demo-mission-001"), message: nil, choixContrat: nil,
                                                 candidatureId: nil, context: context)
        XCTAssertEqual(encore, .refusee(code: nil, message: "Cette mission n'est plus disponible.", documentsRequisPour: nil))
    }

    func testAccepterUneMissionEnModeCandidatureRefuseVerbatim() async throws {
        let gateway = DemoCandidatureGateway()
        let refus = await erreur {
            _ = try await gateway.confirmer(action: .accepter, missionId: "demo-mission-014",
                                            creneaux: try self.creneaux("demo-mission-014"), message: nil, choixContrat: nil,
                                            candidatureId: nil, context: self.context)
        }
        XCTAssertEqual(refus, JoleneError(.unknown, "Cette mission nécessite une candidature"))
    }

    func testPropositionDeLAccueilAccepteePuisRelue() async throws {
        let gateway = DemoCandidatureGateway()
        let avant = try await gateway.candidature(missionId: "demo-mission-011", context: context)
        XCTAssertEqual(avant?.id, "demo-proposition-001")
        XCTAssertEqual(avant?.statut, "PROPOSEE")
        let issue = try await gateway.confirmer(action: .proposition, missionId: "demo-mission-011",
                                                creneaux: try creneaux("demo-mission-011"), message: nil, choixContrat: nil,
                                                candidatureId: "demo-proposition-001", context: context)
        XCTAssertEqual(issue, .confirmed(candidatureId: "demo-proposition-001", contratId: "demo-contrat-demo-mission-011"))
        let apres = try await gateway.candidature(missionId: "demo-mission-011", context: context)
        XCTAssertEqual(apres?.statut, "ACCEPTEE")
        let autre = try await DemoCandidatureGateway().confirmer(action: .proposition, missionId: "demo-mission-011",
                                                                 creneaux: try creneaux("demo-mission-011"), message: nil,
                                                                 choixContrat: nil, candidatureId: "demo-candidature-001",
                                                                 context: context)
        XCTAssertEqual(autre, .refusee(code: nil, message: "Proposition introuvable.", documentsRequisPour: nil))
    }

    func testPropositionRefuseePuisExpireeApresDeuxHeures() async throws {
        let gateway = DemoCandidatureGateway()
        try await gateway.refuserProposition(candidatureId: "demo-proposition-001", context: context)
        let refusee = try await gateway.candidature(missionId: "demo-mission-011", context: context)
        XCTAssertEqual(refusee?.statut, "REFUSEE")
        let plusEnAttente = await erreur { try await gateway.refuserProposition(candidatureId: "demo-proposition-001", context: self.context) }
        XCTAssertEqual(plusEnAttente, JoleneError(.unknown, "Cette proposition n’est plus en attente"))

        let tard = DemoCandidatureGateway(clock: FixedClock(DemoWorld.fixedNow.addingTimeInterval(3 * 3600)))
        let expiree = await erreur { try await tard.refuserProposition(candidatureId: "demo-proposition-001", context: self.context) }
        XCTAssertEqual(expiree, JoleneError(.unknown, "Cette proposition a expiré"))
        let relue = try await tard.candidature(missionId: "demo-mission-011", context: context)
        XCTAssertEqual(relue?.statut, "EXPIREE", "le serveur pose EXPIREE lui-même")
    }

    func testMissionTousPourUnProfilMixteDemandeLeChoixPuisRejoue() async throws {
        var mission = try fixture("demo-mission-001")
        mission.record.typeContratRecherche = "TOUS"
        let source = mission
        let gateway = DemoCandidatureGateway(missions: { [source] }, candidaturesInitiales: { [] })
        let creneaux = try creneaux("demo-mission-001")
        let choix = try await gateway.confirmer(action: .accepter, missionId: "demo-mission-001", creneaux: creneaux, message: nil,
                                                choixContrat: nil, candidatureId: nil, context: context)
        XCTAssertEqual(choix, .choixRequis([ChoixContratOption(value: "SALARIE", label: "Salarié (CDD / bulletin de paie)"),
                                            ChoixContratOption(value: "LIBERAL", label: "Libéral (note d'honoraires)")]))
        let rejoue = try await gateway.confirmer(action: .accepter, missionId: "demo-mission-001", creneaux: creneaux, message: nil,
                                                 choixContrat: "SALARIE", candidatureId: nil, context: context)
        XCTAssertEqual(rejoue, .confirmed(candidatureId: nil, contratId: "demo-contrat-demo-mission-001"))
    }

    func testAutreUtilisateurRefuseEtAnnulationsVerrouilleesJusquaT7() async throws {
        let gateway = DemoCandidatureGateway()
        var autre = context
        autre.userId = "autre"
        autre.profile.id = "autre"
        let demo = await erreur { _ = try await gateway.candidature(missionId: "demo-mission-011", context: autre) }
        XCTAssertEqual(demo?.kind, .demoOnly)
        let annulation = await erreur {
            _ = try await gateway.annulerCandidature(id: "demo-candidature-001", motif: "AUTRE", texte: String(repeating: "x", count: 20),
                                                     justificatifPath: nil, context: self.context)
        }
        XCTAssertEqual(annulation?.kind, .contract)
        XCTAssertTrue(annulation?.message.contains("T7") == true, annulation?.message ?? "")
    }
}
