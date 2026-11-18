import XCTest
@testable import JoleneCore

/// Pointage de l'établissement démo (lot 5, T7) : réponses enregistrées rejouées dans l'ordre (M4 : `123456` deux
/// lectures puis l'état relu après le scan d'arrivée, `100002`), code servi aux seuls membres habilités, signature et
/// planning de la fixture des missions, affichage rendu par `CodeRotatifRules` à l'horloge fixée (M4 code, M5 contrat
/// non signé, M6 hors créneau), cadence `-JOLENE_POLL_INTERVAL` bornée.
final class DemoEtabPointageGatewayTests: XCTestCase {
    private func contexte(_ role: RoleEtab = .proprietaire) throws -> EtablissementReadContext {
        let permissions = try XCTUnwrap(try DemoFixtures.loadPermissionsEtab().roles[role.brut])
        return EtablissementReadContext(userId: DemoEtablissementWorld.userId, etablissementId: "demo-etab-1", roleEtab: role,
                                        permissions: permissions, epoch: 1)
    }

    private func affichage(_ gateway: DemoEtabPointageGateway, _ missionId: String,
                           _ context: EtablissementReadContext) async throws -> CodeRotatifRules.Affichage {
        let etat = try await gateway.etat(missionId: missionId, context: context)
        let lu = try await gateway.planning(missionId: missionId, context: context)
        let signe = try await gateway.contratSigne(missionId: missionId, context: context)
        return CodeRotatifRules.affichage(etat: etat, planning: .depuis(mission: lu.mission, creneaux: lu.creneaux, contratSigne: signe),
                                          autoriseAuPointage: context.permissions.pointage, maintenant: DemoWorld.fixedNow)
    }

    func testM4RejoueLeCodePuisLEtatReluApresLeScan() async throws {
        let gateway = DemoEtabPointageGateway()
        let context = try contexte()
        let premiere = try await affichage(gateway, "demo-etab-m04", context)
        XCTAssertEqual(premiere.codeVisible, CodeRotatifRules.CodeVisible(valeur: "123456", chiffres: "123 456",
                                                                          prochainPointage: "Arrivée", segmentEnCours: false))
        XCTAssertEqual(premiere.creneauActif?.libelle, "Créneau 1/1 · lundi 2 novembre 2026 à 00:00 → 08:00")
        let seconde = try await gateway.etat(missionId: "demo-etab-m04", context: context)
        XCTAssertEqual(seconde.codePointageActif, "123456", "servi deux lectures")
        let apresScan = try await affichage(gateway, "demo-etab-m04", context)
        XCTAssertEqual(apresScan.codeVisible, CodeRotatifRules.CodeVisible(valeur: "100002", chiffres: "100 002",
                                                                           prochainPointage: "Départ ou pause", segmentEnCours: true))
        let ensuite = try await gateway.etat(missionId: "demo-etab-m04", context: context)
        XCTAssertEqual(ensuite.codePointageActif, "100002", "le dernier état enregistré reste servi")
        XCTAssertEqual(ensuite.statut, "EN_COURS")
    }

    func testM5ContratNonSigneEtM6HorsCreneau() async throws {
        let gateway = DemoEtabPointageGateway()
        let context = try contexte()
        let m5 = try await affichage(gateway, "demo-etab-m05", context)
        XCTAssertEqual(m5.bloc, .masque(titre: CodeRotatifRules.titreMasqueContrat, detail: CodeRotatifRules.detailContratNonSigne))
        let m6 = try await affichage(gateway, "demo-etab-m06", context)
        XCTAssertEqual(m6.bloc, .masque(titre: CodeRotatifRules.titreMasqueHorsCreneau,
                                        detail: "Le code sera affiché 15 minutes avant le créneau 2/2, le mardi 3 novembre 2026 à 07:00."))
        let segments = try await gateway.etat(missionId: "demo-etab-m06", context: context).segments
        XCTAssertEqual(CodeRotatifRules.lignesSegments(segments, maintenant: DemoWorld.fixedNow).map(\.libelle),
                       ["Segment 1 · 01/11/2026 07h02 → 01/11/2026 15h01"])
        let planning = try await gateway.planning(missionId: "demo-etab-m06", context: context)
        XCTAssertEqual(planning.creneaux.map(\.id), ["demo-etab-m06-slot-1", "demo-etab-m06-slot-2"])
        XCTAssertEqual(planning.mission.nbCreneaux, 2)
    }

    func testCodeServiAuxSeulsMembresHabilitesEtRefusVerbatim() async throws {
        let gateway = DemoEtabPointageGateway()
        let lecture = try contexte(.lectureSeule)
        let etat = try await gateway.etat(missionId: "demo-etab-m04", context: lecture)
        XCTAssertNil(etat.codePointageActif, "B5b : l'état sans le code pour LECTURE_SEULE")
        XCTAssertEqual(etat.statut, "ASSIGNEE")
        let signe = try await gateway.contratSigne(missionId: "demo-etab-m04", context: lecture)
        XCTAssertFalse(signe, "42501 serveur, rendu false par la gateway")
        let pointageSeul = try await gateway.etat(missionId: "demo-etab-m04", context: try contexte(.pointageOnly))
        XCTAssertEqual(pointageSeul.codePointageActif, "123456", "POINTAGE_ONLY voit le code")

        let inconnue = try await gateway.etat(missionId: "mission-inconnue", context: try contexte())
        XCTAssertEqual(inconnue.erreur, "Mission introuvable")
        XCTAssertNil(inconnue.codePointageActif)
        var autre = try contexte()
        autre.userId = "autre-compte"
        do {
            _ = try await gateway.etat(missionId: "demo-etab-m04", context: autre)
            XCTFail("compte fictif seulement")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
    }

    func testCadenceDuLancementBornee() {
        func cadence(_ valeur: String) -> TimeInterval? {
            guard case let .etablissement(configuration) = DemoEspaceLancement.espace(arguments: [
                "-JOLENE_DEMO_ESPACE", "etablissement", "-JOLENE_POLL_INTERVAL", valeur]) else { return -1 }
            return configuration.cadencePointage
        }
        XCTAssertEqual(cadence("4"), 4)
        XCTAssertEqual(cadence("1"), 1)
        for refusee in ["0.5", "5", "10", "abc", "inf", "nan", ""] { XCTAssertNil(cadence(refusee), refusee) }
        XCTAssertEqual(DemoEtabPointageGateway().cadenceLecture, CodeRotatifModel.cadenceNominale)
        XCTAssertEqual(DemoEtabPointageGateway(cadence: 4).cadenceLecture, 4)
        XCTAssertEqual(UnwiredEtabPointagePort().cadenceLecture, 5, "D23 : 5 s par défaut")
    }

    func testFixtureDeriveeDesMissionsDemo() throws {
        let pointage = try DemoFixtures.loadEtabPointage()
        let missions = try DemoFixtures.loadEtabMissions()
        XCTAssertEqual(pointage.fixedNow, missions.fixedNow)
        for scenario in pointage.scenarios {
            let mission = try XCTUnwrap(missions.missions.first { $0.id == scenario.missionId }, scenario.missionId)
            XCTAssertTrue(["ASSIGNEE", "EN_COURS"].contains(mission.statut ?? ""), scenario.missionId)
            for enregistre in scenario.etats {
                if let code = enregistre.etat.codePointageActif { XCTAssertEqual(PayloadQR.codePointage(depuis: code), code) }
            }
        }
        XCTAssertEqual(pointage.contratsSignes, ["demo-etab-m04", "demo-etab-m06"])
    }
}
