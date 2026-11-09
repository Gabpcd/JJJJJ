import Foundation

/// Décompte d'une attente bornée de `require` (`JoleneUITests/UITestSupport.swift`), extrait en
/// fonction pure : horloge, évaluateur et intervalle sont injectés, si bien que la logique se
/// teste sur une horloge simulée, sans simulateur ni attente réelle (`RequireWaitTests`).
///
/// Fichier PARTAGÉ : compilé dans la cible JoleneUITests (source listée dans `project.yml`) et
/// dans JoleneCoreTests, qui le teste sur macOS (`swift test`) comme sur simulateur. Il ne
/// dépend que de Foundation : ni XCTest, ni XCUITest, ni JoleneCore. Traces (activités, pièces
/// jointes) et échecs restent dans `require`.
///
/// Règles de décompte, seule source de `require` et de ses tests :
/// - une évaluation compte pour sa durée mesurée, plafonnée à `maximumCharged` ; l'excédent est
///   du temps NON décompté, et l'évaluation est dite bloquée ;
/// - un intervalle entre deux évaluations compte pour sa durée mesurée, jamais moins que prévu ;
/// - délai fonctionnel `timeout` : la condition est réévaluée tant que le temps décompté reste
///   sous `timeout` ;
/// - budget de blocage `stallBudget`, distinct du délai : le temps non décompté cumulé sur
///   l'appel ne le dépasse pas ; au-delà, l'attente échoue aussitôt, condition vraie ou non ;
/// - évaluation de grâce : si l'évaluation qui épuise le délai était bloquée, une seule
///   évaluation de plus est accordée, après un intervalle, sous le même budget, pour que l'état
///   soit constaté après le blocage ;
/// - intervalle allongé : un intervalle qui épuise le délai est toujours suivi d'une évaluation
///   finale ; l'attente n'échoue jamais sur un état lu avant l'intervalle.
struct RequireWait: Sendable {
    /// Évaluation bloquée : rang (1 pour la première), début relatif au début de l'attente,
    /// durée mesurée.
    struct Stall: Sendable, Equatable {
        let index: Int
        let start: TimeInterval
        let duration: TimeInterval
    }

    enum Outcome: Sendable, Equatable {
        /// Condition vraie à la dernière évaluation, budget de blocage respecté.
        case satisfied
        /// Condition fausse à chaque évaluation, délai fonctionnel épuisé.
        case conditionFalse
        /// Temps non décompté au-delà du budget de blocage : échec, condition vraie ou non.
        case stallBudgetExceeded
    }

    let timeout: TimeInterval
    let stallBudget: TimeInterval
    let maximumCharged: TimeInterval
    let interval: TimeInterval

    private(set) var evaluations = 0
    /// Début de chaque évaluation, relatif au début de l'attente.
    private(set) var evaluationStarts: [TimeInterval] = []
    private(set) var stalls: [Stall] = []
    /// Part décomptée des évaluations (chacune plafonnée à `maximumCharged`).
    private(set) var charged: TimeInterval = 0
    /// Excédent des évaluations bloquées, borné par `stallBudget`.
    private(set) var uncharged: TimeInterval = 0
    /// Intervalles mesurés (chacun au moins égal à sa durée prévue).
    private(set) var pauses: TimeInterval = 0
    private(set) var graceGranted = false
    /// Valeur de la condition à la dernière évaluation.
    private(set) var lastEvaluation = false

    private init(timeout: TimeInterval, stallBudget: TimeInterval, maximumCharged: TimeInterval, interval: TimeInterval) {
        self.timeout = timeout
        self.stallBudget = stallBudget
        self.maximumCharged = maximumCharged
        self.interval = interval
    }

    /// Délai fonctionnel restant : `timeout` moins les évaluations décomptées et les intervalles.
    var remaining: TimeInterval { timeout - charged - pauses }
    var stallBudgetExceeded: Bool { uncharged > stallBudget }
    var longestStall: TimeInterval { stalls.map(\.duration).max() ?? 0 }
    /// Vrai dès qu'une évaluation a été bloquée : `require` trace alors l'appel, réussi ou non.
    var needsTrace: Bool { uncharged > 0 }

    var outcome: Outcome {
        if stallBudgetExceeded { return .stallBudgetExceeded }
        return lastEvaluation ? .satisfied : .conditionFalse
    }

    /// Évalue `evaluate` jusqu'à ce qu'il soit vrai, que le délai fonctionnel soit épuisé ou que
    /// le budget de blocage soit dépassé. `now` est une horloge monotone en secondes ; `pause`
    /// laisse passer l'intervalle demandé (sa durée réelle est mesurée par `now`). Synchrone et
    /// non isolé : les fermetures s'exécutent dans l'isolation de l'appelant.
    static func run(timeout: TimeInterval, stallBudget: TimeInterval, maximumCharged: TimeInterval,
                    interval: TimeInterval, now: () -> TimeInterval, evaluate: () -> Bool,
                    pause: (TimeInterval) -> Void) -> RequireWait {
        var wait = RequireWait(timeout: timeout, stallBudget: stallBudget, maximumCharged: maximumCharged, interval: interval)
        let origin = now()
        while true {
            let start = now()
            let satisfied = evaluate()
            let stalled = wait.record(start: start - origin, duration: now() - start, satisfied: satisfied)
            if satisfied || wait.stallBudgetExceeded { break }
            if wait.remaining <= 0 {
                // Délai épuisé : une seule évaluation de plus, si celle qui l'a épuisé était bloquée.
                guard stalled, !wait.graceGranted else { break }
                wait.graceGranted = true
            }
            let planned = wait.remaining > 0 ? min(interval, wait.remaining) : interval
            let pauseStart = now()
            pause(planned)
            wait.pauses += max(planned, now() - pauseStart)
        }
        return wait
    }

    /// Compte une évaluation ; vrai si elle était bloquée.
    private mutating func record(start: TimeInterval, duration: TimeInterval, satisfied: Bool) -> Bool {
        evaluations += 1
        evaluationStarts.append(start)
        lastEvaluation = satisfied
        charged += min(duration, maximumCharged)
        let excess = duration - maximumCharged
        guard excess > 0 else { return false }
        stalls.append(Stall(index: evaluations, start: start, duration: duration))
        uncharged += excess
        return true
    }
}
