import XCTest

/// Décompte de `require`, socle des tests UI (`PartageUITests/RequireWait.swift`, fichier compilé
/// aussi dans JoleneUITests), vérifié sur une horloge simulée : chaque évaluation et chaque
/// intervalle avancent l'horloge d'une durée scriptée, sans attente réelle. Constantes de
/// `JoleneUITestCase` : 5 s décomptées au plus par évaluation, intervalle de 1 s.
final class RequireWaitTests: XCTestCase {
    private struct Run {
        let wait: RequireWait
        /// Durées d'intervalle demandées par la boucle, dans l'ordre.
        let requestedPauses: [TimeInterval]
    }

    /// Exécute `RequireWait.run` sur un scénario : `evaluations` donne la durée et le résultat de
    /// chaque évaluation, `slowPauses` la durée réelle des intervalles allongés (rang à partir de 1).
    private func run(timeout: TimeInterval = 15, stallBudget: TimeInterval = 15,
                     evaluations: [(duration: TimeInterval, result: Bool)],
                     slowPauses: [Int: TimeInterval] = [:],
                     file: StaticString = #filePath, line: UInt = #line) -> Run {
        var clock: TimeInterval = 1_000
        var next = 0
        var requested: [TimeInterval] = []
        let wait = RequireWait.run(
            timeout: timeout, stallBudget: stallBudget, maximumCharged: 5, interval: 1,
            now: { clock },
            evaluate: {
                guard next < evaluations.count else {
                    XCTFail("évaluation n° \(next + 1) non prévue par le scénario", file: file, line: line)
                    return false
                }
                let evaluation = evaluations[next]
                next += 1
                clock += evaluation.duration
                return evaluation.result
            },
            pause: { planned in
                requested.append(planned)
                clock += slowPauses[requested.count] ?? planned
            })
        XCTAssertEqual(next, evaluations.count, "chaque évaluation du scénario a eu lieu", file: file, line: line)
        return Run(wait: wait, requestedPauses: requested)
    }

    /// Run 42489677193, UI — iphone : une requête d'accessibilité de 12,5 s. L'attente réussit à
    /// l'évaluation suivante, et le temps non décompté (7,5 s) demande une trace.
    func testUneEvaluationDe12VirguleCinqSecondesReussitAvecTrace() {
        let run = run(evaluations: [(12.5, false), (0.25, true)])
        XCTAssertEqual(run.wait.outcome, .satisfied)
        XCTAssertEqual(run.wait.evaluations, 2)
        XCTAssertEqual(run.wait.stalls, [RequireWait.Stall(index: 1, start: 0, duration: 12.5)])
        XCTAssertEqual(run.wait.uncharged, 7.5, accuracy: 1e-9, "excédent au-delà des 5 s décomptées")
        XCTAssertEqual(run.wait.charged, 5.25, accuracy: 1e-9)
        XCTAssertEqual(run.requestedPauses, [1])
        XCTAssertTrue(run.wait.needsTrace, "une attente réussie après un blocage est tracée")
        XCTAssertFalse(run.wait.graceGranted)
    }

    /// Une évaluation de 21 s laisse 16 s non décomptées, au-delà du budget de blocage de 15 s :
    /// échec au plafond, même si la condition est vraie, et sans autre évaluation.
    func testUneEvaluationDe21SecondesEchoueAuBudgetDeBlocage() {
        let run = run(evaluations: [(21, true)])
        XCTAssertEqual(run.wait.outcome, .stallBudgetExceeded)
        XCTAssertTrue(run.wait.lastEvaluation, "la condition était vraie : le blocage seul fait échouer")
        XCTAssertEqual(run.wait.evaluations, 1)
        XCTAssertEqual(run.wait.uncharged, 16, accuracy: 1e-9)
        XCTAssertEqual(run.requestedPauses, [])
        XCTAssertTrue(run.wait.needsTrace)
    }

    /// Le budget de blocage ne suit pas le délai fonctionnel : un délai de 30 s ne tolère pas plus
    /// de blocage, et seul un budget explicite (à froid, 60 s) absorbe le pire cas observé, une
    /// évaluation de 34,4 s (run 42523240142, ipad-landscape, champ `login-email`).
    func testLeBudgetDeBlocageEstDistinctDuDelaiFonctionnel() {
        XCTAssertEqual(run(timeout: 30, stallBudget: 15, evaluations: [(21, true)]).wait.outcome, .stallBudgetExceeded)
        let froid = run(timeout: 15, stallBudget: 60, evaluations: [(34.4, true)])
        XCTAssertEqual(froid.wait.outcome, .satisfied)
        XCTAssertEqual(froid.wait.uncharged, 29.4, accuracy: 1e-9)
        XCTAssertTrue(froid.wait.needsTrace, "un blocage absorbé par le budget à froid reste tracé")
    }

    /// L'évaluation qui épuise le délai est bloquée : UNE évaluation de grâce suit, après un
    /// intervalle ; bloquée elle aussi, elle n'en ouvre pas une deuxième.
    func testUnBlocageSurLaDerniereEvaluationAccordeUneSeuleEvaluationDeGrace() {
        let echec = run(timeout: 3, evaluations: [(0.25, false), (0.25, false), (7, false), (7, false)])
        XCTAssertEqual(echec.wait.outcome, .conditionFalse)
        XCTAssertEqual(echec.wait.evaluations, 4, "trois évaluations dans le délai, une de grâce")
        XCTAssertTrue(echec.wait.graceGranted)
        XCTAssertEqual(echec.requestedPauses, [1, 1, 1], "l'évaluation de grâce suit un intervalle complet")
        XCTAssertEqual(echec.wait.uncharged, 4, accuracy: 1e-9)

        let reussite = run(timeout: 3, evaluations: [(0.25, false), (0.25, false), (7, false), (0.25, true)])
        XCTAssertEqual(reussite.wait.outcome, .satisfied, "l'état constaté après le blocage décide")
        XCTAssertTrue(reussite.wait.graceGranted)

        // Sans blocage, le délai épuisé termine l'attente : aucune grâce.
        let sansBlocage = run(timeout: 3, evaluations: [(0.25, false), (0.25, false), (0.25, false), (0.25, false)])
        XCTAssertEqual(sansBlocage.wait.outcome, .conditionFalse)
        XCTAssertFalse(sansBlocage.wait.graceGranted)
        XCTAssertEqual(sansBlocage.requestedPauses, [1, 1, 0.25], "le dernier intervalle est réduit au délai restant")
    }

    /// Un intervalle allongé (runner bloqué pendant la pause : 10 s au lieu de 1 s) épuise le
    /// délai ; l'attente évalue encore une fois, APRÈS l'intervalle, avant de conclure.
    func testUnIntervalleAllongeEstSuiviDUneEvaluationFinale() {
        let reussite = run(timeout: 3, evaluations: [(0.25, false), (0.25, true)], slowPauses: [1: 10])
        XCTAssertEqual(reussite.wait.outcome, .satisfied)
        XCTAssertEqual(reussite.wait.evaluationStarts, [0, 10.25], "évaluation finale au terme de l'intervalle allongé")
        XCTAssertEqual(reussite.wait.pauses, 10, accuracy: 1e-9, "l'intervalle compte pour sa durée mesurée")
        XCTAssertFalse(reussite.wait.needsTrace, "un intervalle allongé n'est pas du temps non décompté")

        let echec = run(timeout: 3, evaluations: [(0.25, false), (0.25, false)], slowPauses: [1: 10])
        XCTAssertEqual(echec.wait.outcome, .conditionFalse)
        XCTAssertEqual(echec.wait.evaluations, 2, "une seule évaluation finale, pas de grâce sans blocage")
        XCTAssertFalse(echec.wait.graceGranted)
    }
}
