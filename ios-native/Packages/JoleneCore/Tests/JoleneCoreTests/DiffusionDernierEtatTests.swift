import XCTest
@testable import JoleneCore

/// Régression du 24/11/2026 (gel reproduit par la messagerie du lot 4 avec la même mécanique) : une diffusion faite sous
/// le verrou que prend `onTermination` s'interbloque avec l'annulation d'un lecteur. L'annulation d'une tâche exécute
/// son gestionnaire (`AsyncStream` → `onTermination` → `desabonner`, qui prend `verrou`) en tenant le verrou d'état de
/// cette tâche ; `yield`, appelé sous `verrou`, reprend la tâche qui attend le flux et prend pour cela ce même verrou
/// d'état. Chaque fil tient le verrou que l'autre attend.
///
/// Le test tourne hors du groupe de fils coopératifs (fils dédiés) et attend sa fin avec un délai : un gel le fait
/// échouer au lieu de figer la suite. Pas `@MainActor` : le fil principal ne fait qu'attendre.
final class DiffusionDernierEtatTests: XCTestCase {
    func testDiffusionPendantLAnnulationDesLecteursSansInterblocage() {
        let tours = 300
        let fini = DispatchSemaphore(value: 0)
        let avancement = Compteur()
        Thread.detachNewThread {
            for tour in 0..<tours {
                let diffusion = DiffusionDernierEtat<Int>()
                diffusion.recevoir(0)
                let lecteurs = (0..<4).map { _ in Task.detached { for await _ in diffusion.flux() {} } }
                let emis = DispatchSemaphore(value: 0)
                Thread.detachNewThread {
                    for valeur in 1...60 { diffusion.recevoir(valeur) }
                    emis.signal()
                }
                if tour % 2 == 0 { usleep(UInt32.random(in: 0...80)) }
                lecteurs.forEach { $0.cancel() }
                emis.wait()
                diffusion.terminer()
                avancement.incrementer()
            }
            fini.signal()
        }
        let resultat = fini.wait(timeout: .now() + 60)
        XCTAssertEqual(resultat, .success, "gel : \(avancement.valeur)/\(tours) tours terminés en 60 s")
    }
}

/// Tours terminés, lus par le fil du test après un gel.
private final class Compteur: @unchecked Sendable {
    private let verrou = NSLock()
    private var n = 0
    func incrementer() { verrou.lock(); n += 1; verrou.unlock() }
    var valeur: Int { verrou.lock(); defer { verrou.unlock() }; return n }
}
