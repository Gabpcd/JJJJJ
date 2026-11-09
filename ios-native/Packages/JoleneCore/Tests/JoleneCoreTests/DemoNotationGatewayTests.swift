import XCTest
@testable import JoleneCore

/// Monde démo de la tranche T5a : notation (`DemoNotationGateway`), fiche du détail des présences
/// (`DemoPointageGateway.ficheDetail`) et scénario `accueil-pointage` de l'Accueil (`DemoDashboardGateway`). Aucun
/// réseau, profil fictif seulement.
final class DemoNotationGatewayTests: XCTestCase {
    private var autre: MissionReadContext {
        MissionReadContext(userId: "intrus", email: nil, profile: SoignantProfile(id: "intrus", profession: "IDE"))
    }

    func testNotationEnregistreePuisDejaNoteeSansLectureDeNote() async throws {
        let gateway = DemoNotationGateway()
        let premiere = try await gateway.noter(missionId: "demo-presence-b", note: 4, criteres: nil, context: DemoWorld.context)
        XCTAssertEqual(premiere, .enregistree)
        let notes = await gateway.notes
        XCTAssertEqual(notes["demo-presence-b"], CriteresNotation.repliques(note: 4), "note globale répliquée")
        let seconde = try await gateway.noter(missionId: "demo-presence-b", note: 2, criteres: CriteresNotation(2, 2, 2, 2),
                                              context: DemoWorld.context)
        XCTAssertEqual(seconde, .dejaNotee, "`ON CONFLICT (mission_id, sens) DO NOTHING`")
        let invalide = try await gateway.noter(missionId: "demo-presence-a", note: 3, criteres: CriteresNotation(3, 0, 3, 3),
                                               context: DemoWorld.context)
        XCTAssertEqual(invalide, .refusee(message: "Critères doivent être entre 1 et 5"))
        do {
            _ = try await gateway.noter(missionId: "demo-presence-a", note: 3, criteres: nil, context: autre)
            XCTFail("profil fictif seulement")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
    }

    func testFinPrevueLueDansLaFixture() async throws {
        let gateway = DemoNotationGateway()
        let finB = try await gateway.finPrevue(missionId: "demo-presence-b", context: DemoWorld.context)
        XCTAssertEqual(finB, "2026-11-02T06:00:00.000Z")
        let finH1 = try await gateway.finPrevue(missionId: "demo-presence-h1", context: DemoWorld.context)
        XCTAssertEqual(finH1, "2026-10-31T15:00:00.000Z", "missions de l'historique comprises")
        let inconnue = try await gateway.finPrevue(missionId: "inconnue", context: DemoWorld.context)
        XCTAssertNil(inconnue)
    }

    func testFicheDuDetailDesPresencesDemo() async throws {
        let gateway = DemoPointageGateway()
        let aValider = try await gateway.ficheDetail(missionId: "demo-presence-h2", context: DemoWorld.context)
        XCTAssertEqual(aValider.mission?.statut, "TERMINEE")
        XCTAssertEqual(aValider.presence, PresenceControlee(id: "demo-presence-h2-presence", pointageArriveeLe: "2026-10-30T07:00:00.000Z",
                                                            valideParEtablissement: false))
        let validee = try await gateway.ficheDetail(missionId: "demo-presence-h1", context: DemoWorld.context)
        XCTAssertEqual(validee.presence?.valideParEtablissement, true)
        XCTAssertEqual(validee.presence?.valideLe, "2026-11-01T14:00:00.000Z")
        let reconstruite = try await gateway.ficheDetail(missionId: "demo-presence-h3", context: DemoWorld.context)
        XCTAssertNotNil(reconstruite.mission)
        XCTAssertNil(reconstruite.presence, "heures pointées sans présence : ni validation ni contrôles")
        let enCours = try await gateway.ficheDetail(missionId: "demo-presence-b", context: DemoWorld.context)
        XCTAssertEqual(enCours.mission?.statut, "EN_COURS")
        let inconnue = try await gateway.ficheDetail(missionId: "inconnue", context: DemoWorld.context)
        XCTAssertNil(inconnue.mission, "« Mission introuvable »")
    }

    func testDetailDemoDeLaPresenceAValiderProposeLaRelance() async throws {
        let gateway = DemoPointageGateway()
        let detail = try await gateway.detail(missionId: "demo-presence-h2", context: DemoWorld.context)
        let fiche = try await gateway.ficheDetail(missionId: "demo-presence-h2", context: DemoWorld.context)
        let mission = try XCTUnwrap(fiche.mission)
        let presentation = PresentationDetailPresences.construire(mission: mission, creneaux: detail.creneaux, resume: detail.resume,
                                                                  presence: fiche.presence, maintenant: DemoWorld.fixedNow)
        XCTAssertTrue(presentation.relanceProposee)
        XCTAssertEqual(presentation.entete.periode, "📅 ven. 30 oct. 2026 · 08:00 → 16:00")
        XCTAssertEqual(presentation.jours.first?.segments.first?.validation, "✅ Relevé clôturé")
        XCTAssertEqual(presentation.jours.first?.segments.first?.duree, "Durée : 8h00")
    }

    // MARK: - Accueil : scénario `accueil-pointage`

    func testScenarioAccueilPointageAjouteLaMissionDuJourEtUnOubli() async throws {
        let normal = try await DemoDashboardGateway().dashboard(context: DemoWorld.context, delaiEcran: 5)
        XCTAssertEqual(normal.missionsOublieesCount, 0)
        XCTAssertNil(PointsEntreePresences.allerPointer(normal.prochaines, maintenant: DemoWorld.fixedNow),
                     "démo normale : aucune mission à pointer dans l'heure")

        let scenario = try await DemoDashboardGateway(scenario: .pointage).dashboard(context: DemoWorld.context, delaiEcran: 5)
        XCTAssertEqual(scenario.missionsOublieesCount, 1)
        XCTAssertEqual(scenario.prochaines.map(\.id), ["demo-presence-a"] + normal.prochaines.map(\.id))
        let widget = try XCTUnwrap(PointsEntreePresences.allerPointer(scenario.prochaines, maintenant: DemoWorld.fixedNow))
        XCTAssertEqual(widget.missionId, "demo-presence-a")
        XCTAssertEqual(widget.titre, "Créneau de travail actuel")
        XCTAssertEqual(widget.mission, "Démonstration · Pointage du jour — Établissement fictif République")
        XCTAssertEqual(widget.horaire, "lundi 2 novembre · 01:05 → 09:05")
        XCTAssertEqual(widget.bouton, "Aller pointer →")
        XCTAssertEqual(widget.onglet, .aujourdhui)
    }

    func testArgumentDuScenarioAccueil() {
        XCTAssertEqual(ScenarioAccueilDemo(arguments: ["-JOLENE_DEMO_SCENARIO", "accueil-pointage"]), .pointage)
        XCTAssertEqual(ScenarioAccueilDemo(arguments: ["-JOLENE_DEMO_SCENARIO", "upload-incertain"]), .normal, "scénario d'un autre domaine")
        XCTAssertEqual(ScenarioAccueilDemo(arguments: []), .normal)
    }
}
