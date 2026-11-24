import XCTest
@testable import JoleneCore

/// Câblage démo du swipe (lot 4, T3a ; garde anti-oubli `Lot4Wiring<Domaine>Tests`, `LOT4_PLAN.md` §2.2) et parcours
/// du monde démo de bout en bout : paquet de `demo-swipe.json` au planning de `demo-missions.json`, ✕ / ⭐ consignés,
/// ⭐ relu dans les favoris démo, ❤️ par `SWIPE_LIKE` (`DemoCandidatureGateway`), retrait sans retour au paquet.
final class Lot4WiringSwipeTests: XCTestCase {
    private let context = DemoWorld.context

    func testDemoWorldCableLeSwipe() {
        let gateways = DemoWorld.gateways()
        XCTAssertTrue(gateways.swipe is DemoSwipeGateway)
        XCTAssertFalse(gateways.unwiredPorts.contains("swipe"))
    }

    func testParcoursDemoPasserSauvegarderCandidaterPuisRetirer() async throws {
        let gateways = DemoWorld.gateways()
        let swipe = gateways.swipe
        let quiz = try await swipe.nombreSwipes(context: context)
        XCTAssertEqual(quiz, 0, "quiz au premier contact")
        let paquet = try await swipe.paquet(context: context)
        XCTAssertEqual(paquet.count, 12)
        XCTAssertTrue(paquet.allSatisfy(\.mission.planningExact), "planning exact de demo-missions.json")
        XCTAssertEqual(paquet.filter { $0.score == nil }.count, 2)

        let passee = paquet[0].id, favorite = paquet[1].id, aimee = paquet[2].id
        let passe = try await swipe.enregistrer(missionId: passee, direction: .passer, context: context)
        XCTAssertEqual(passe, .enregistre)
        let encore = try await swipe.enregistrer(missionId: passee, direction: .favori, context: context)
        XCTAssertEqual(encore, .refuse(code: "mission_deja_swipee", message: "Vous avez déjà répondu à cette mission."))

        let favori = try await swipe.enregistrer(missionId: favorite, direction: .favori, context: context)
        XCTAssertEqual(favori, .enregistre)
        let favoris = try await gateways.favoris.missionsSauvegardees(context: context)
        XCTAssertTrue(FavorisRegles.estSauvegardee(favorite, dans: favoris), "⭐ visible dans Mes favoris")

        let carte = try XCTUnwrap(paquet.first { $0.id == aimee })
        let creneaux = try XCTUnwrap(CreneauxConfirmes.pourAction(PlanningCandidatInput(mission: carte.mission)))
        let issue = try await gateways.candidature.confirmer(action: .swipeLike, missionId: aimee, creneaux: creneaux, message: nil,
                                                             choixContrat: nil, candidatureId: nil, context: context)
        guard case let .confirmed(candidatureId?, _) = issue else { return XCTFail("❤️ confirmé attendu, obtenu \(issue)") }
        let posee = try await gateways.candidature.candidature(missionId: aimee, context: context)
        XCTAssertEqual(posee?.statut, "EN_ATTENTE")
        let deuxieme = try await gateways.candidature.confirmer(action: .swipeLike, missionId: aimee, creneaux: creneaux, message: nil,
                                                                choixContrat: nil, candidatureId: nil, context: context)
        XCTAssertEqual(deuxieme, .refusee(code: nil, message: "Vous avez déjà candidaté à cette mission", documentsRequisPour: nil))

        let retrait = try await swipe.retirer(candidatureId: candidatureId, context: context)
        XCTAssertEqual(retrait, .retiree)
        let relue = try await gateways.candidature.candidature(missionId: aimee, context: context)
        XCTAssertNil(relue, "candidature supprimée")
        let encoreRetrait = try await swipe.retirer(candidatureId: candidatureId, context: context)
        XCTAssertEqual(encoreRetrait, .refuse(message: "Candidature introuvable"))

        let relu = try await swipe.paquet(context: context)
        XCTAssertEqual(relu.count, 9)
        XCTAssertTrue(Set(relu.map(\.id)).isDisjoint(with: [passee, favorite, aimee]), "carte jamais remise après le retrait (D4)")
        let nombre = try await swipe.nombreSwipes(context: context)
        XCTAssertEqual(nombre, 3)
    }

    /// URGENCE est livrée par T11 (`DemoPoolUrgenceTests` côté cœur) : un planning vide n'est jamais accepté.
    func testUrgenceSansPlanningJamaisAccepteeEnDemo() async throws {
        let gateways = DemoWorld.gateways()
        let issue = try await gateways.candidature.confirmer(action: .urgence, missionId: "demo-mission-015", creneaux: [],
                                                             message: nil, choixContrat: nil, candidatureId: nil, context: context)
        XCTAssertEqual(issue, .planningAReconfirmer(code: DemoCandidatureGateway.codePlanningModifie,
                                                    message: DemoCandidatureGateway.Textes.planningModifie))
    }

    func testPreferencesHorsBornesRefuseesEtContexteEtrangerRefuse() async throws {
        let swipe = DemoWorld.gateways().swipe
        do {
            try await swipe.initialiserPreferences(PreferencesMatching(nuit: 1.5, jour: 0, weekend: 0, semaine: 0), context: context)
            XCTFail("hors bornes")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.message, "Préférences hors bornes [0,1]")
        }
        try await swipe.initialiserPreferences(.depuisQuiz(horaire: .jour, rythme: .tous), context: context)
        var etranger = context
        etranger.userId = "autre"
        etranger.profile.id = "autre"
        do {
            _ = try await swipe.paquet(context: etranger)
            XCTFail("contexte étranger accepté")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
    }
}
