import XCTest
@testable import JoleneCore

/// Compte à rebours de signature (miroir de `calculerRestant`, `Countdown72hSignature.tsx`
/// l.79-82, et du cron d'expiration des contrats non signés) : état dérivé de `cree_le`,
/// recalculé à chaque seconde, jamais stocké. Pas de golden : la fonction web n'est pas exportée.
final class CompteARebours72hTests: XCTestCase {
    private let creeLe = "2026-11-01T14:00:00.000Z"

    private func etat(apres secondes: Int) throws -> EtatCompteARebours72h {
        let cree = try DateHeureParis.instantJolene(creeLe)
        return CompteARebours72h.etat(creeLe: creeLe, maintenant: cree.addingTimeInterval(TimeInterval(secondes)))
    }

    func testSoixanteDouzeHeuresExactesALaCreation() throws {
        let initial = try etat(apres: 0)
        XCTAssertEqual(initial.restantSecondes, 72 * 3600)
        XCTAssertEqual(initial.heures, 72)
        XCTAssertEqual(initial.minutes, 0)
        XCTAssertEqual(initial.secondes, 0)
        XCTAssertEqual(initial.ton, .confortable)
        XCTAssertFalse(initial.expire)
    }

    func testDecompositionHeuresMinutesSecondes() throws {
        let etat = try etat(apres: 10 * 3600 + 59) // 61 h 59 min 01 s restantes
        XCTAssertEqual(etat.restantSecondes, 62 * 3600 - 59)
        XCTAssertEqual([etat.heures, etat.minutes, etat.secondes], [61, 59, 1])
    }

    func testSeuilsDeCouleur48Et24Heures() throws {
        XCTAssertEqual(try etat(apres: 24 * 3600).ton, .confortable, "48 h restantes : vert")
        XCTAssertEqual(try etat(apres: 24 * 3600 + 1).ton, .attention, "47 h 59 min 59 s : orange")
        XCTAssertEqual(try etat(apres: 48 * 3600).ton, .attention, "24 h restantes : orange")
        XCTAssertEqual(try etat(apres: 48 * 3600 + 1).ton, .urgent, "moins de 24 h : rouge")
        XCTAssertEqual(try etat(apres: 72 * 3600 - 1).ton, .urgent)
    }

    func testExpireAuDelaDe72Heures() throws {
        XCTAssertEqual(try etat(apres: 72 * 3600 - 1).restantSecondes, 1)
        for secondes in [72 * 3600, 72 * 3600 + 1, 100 * 3600] {
            let etat = try etat(apres: secondes)
            XCTAssertEqual(etat.restantSecondes, 0)
            XCTAssertTrue(etat.expire)
            XCTAssertEqual(etat.ton, .urgent)
        }
    }

    func testFractionDeSecondeArrondieVersLeBas() throws {
        let cree = try DateHeureParis.instantJolene(creeLe)
        let etat = CompteARebours72h.etat(creeLe: creeLe, maintenant: cree.addingTimeInterval(0.4))
        XCTAssertEqual(etat.restantSecondes, 72 * 3600 - 1, "Math.floor des secondes restantes")
    }

    func testCreationIllisibleEchoueFermee() throws {
        // Le web afficherait « NaNh » : le natif considère le délai expiré (aucune signature proposée à tort).
        let maintenant = try DateHeureParis.instantJolene("2026-11-02T00:00:00Z")
        for creeLe in [nil, "", "pas une date"] as [String?] {
            let etat = CompteARebours72h.etat(creeLe: creeLe, maintenant: maintenant)
            XCTAssertTrue(etat.expire, "cree_le « \(creeLe ?? "nil") »")
            XCTAssertEqual(etat.restantSecondes, 0)
        }
    }
}
