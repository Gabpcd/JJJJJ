import XCTest
@testable import JoleneCore

/// Clôture rétroactive d'un segment par l'établissement (lot 5, T8 ; correction 17, D28) : heure de Paris de la saisie,
/// heure que le fuseau refuse → message du web (12ᵉ scénario de `AffichageCodeRotatifEtab.test.tsx`, « signale une heure
/// rétroactive inexistante »), heure future jamais proposée ni envoyée (le serveur l'accepterait), bornes du sélecteur
/// dérivées du segment ouvert relu.
final class ClotureSegmentTests: XCTestCase {
    private func instant(_ iso: String) throws -> Date { try DateHeureParis.instantJolene(iso) }

    private func effectif(_ debut: String, _ fin: String?, pause: Bool = false) -> MissionSlot {
        MissionSlot(id: "e-\(debut)", missionId: "m-1", debut: debut, fin: fin, estPause: pause, typeCreneau: "EFFECTIF")
    }

    func testSaisieLueEnHeureDeParisQuelQueSoitLAppareil() throws {
        let maintenant = try instant("2026-11-02T12:00:00Z")
        // Hiver : Paris = UTC+1.
        XCTAssertEqual(ClotureSegment.analyser(saisie: "2026-11-02T08:30", maintenant: maintenant),
                       .heure(try instant("2026-11-02T07:30:00Z")))
        // Été : Paris = UTC+2.
        XCTAssertEqual(ClotureSegment.analyser(saisie: "2026-07-31T15:05", maintenant: maintenant),
                       .heure(try instant("2026-07-31T13:05:00Z")))
    }

    func testHeureInexistanteDuPassageALHeureDEteMessageDuWeb() throws {
        // Dimanche 29 mars 2026 : 02:00 → 03:00 à Paris, 02:30 n'existe pas (web : `RangeError` → l.196).
        let maintenant = try instant("2026-04-01T12:00:00Z")
        XCTAssertEqual(ClotureSegment.analyser(saisie: "2026-03-29T02:30", maintenant: maintenant),
                       .refus("Cette heure n’existe pas à Paris en raison du passage à l’heure d’été. Choisissez une autre heure."))
        // Une saisie illisible reçoit le même message (toute `RangeError` du web).
        XCTAssertEqual(ClotureSegment.analyser(saisie: "demain", maintenant: maintenant), .refus(ClotureSegment.messageHeureInexistante))
        XCTAssertEqual(ClotureSegment.analyser(saisie: "", maintenant: maintenant), .refus(ClotureSegment.messageHeureInexistante))
        // L'heure juste après le saut existe.
        XCTAssertEqual(ClotureSegment.analyser(saisie: "2026-03-29T03:00", maintenant: maintenant),
                       .heure(try instant("2026-03-29T01:00:00Z")))
    }

    func testHeureFutureRefuseeAvantToutEnvoi() throws {
        let maintenant = try instant("2026-11-02T00:00:30Z") // 01:00:30 à Paris
        XCTAssertEqual(ClotureSegment.analyser(saisie: "2026-11-02T01:00", maintenant: maintenant),
                       .heure(try instant("2026-11-02T00:00:00Z")), "la minute courante est acceptée")
        XCTAssertEqual(ClotureSegment.analyser(saisie: "2026-11-02T01:01", maintenant: maintenant),
                       .refus(ClotureSegment.messageHeureFuture), "D28 : le serveur accepterait une heure future")
        XCTAssertEqual(ClotureSegment.analyser(saisie: "2026-11-03T01:00", maintenant: maintenant),
                       .refus(ClotureSegment.messageHeureFuture))
        XCTAssertFalse(ClotureSegment.messageHeureFuture.isEmpty)
    }

    func testBornesDuSelecteurDuSegmentOuvertAMaintenant() throws {
        let maintenant = try instant("2026-11-02T00:00:00Z")
        let ouvert = effectif("2026-11-01T23:58:00.000Z", nil)
        let bornes = try XCTUnwrap(ClotureSegment.bornes(creneaux: [effectif("2026-11-01T06:02:00Z", "2026-11-01T14:01:00Z"), ouvert],
                                                         maintenant: maintenant))
        XCTAssertEqual(bornes, ClotureSegment.Bornes(debut: try instant("2026-11-01T23:58:00Z"), fin: maintenant))
        XCTAssertLessThanOrEqual(bornes.fin, maintenant, "l'heure future n'est jamais proposée")

        // Le segment ouvert le plus récent est celui que le serveur ferme (`ORDER BY debut DESC LIMIT 1`).
        let deux = try XCTUnwrap(ClotureSegment.bornes(creneaux: [effectif("2026-11-01T20:00:00Z", nil), ouvert], maintenant: maintenant))
        XCTAssertEqual(deux.debut, try instant("2026-11-01T23:58:00Z"))
    }

    func testAucuneBorneSansSegmentOuvertLisible() throws {
        let maintenant = try instant("2026-11-02T00:00:00Z")
        XCTAssertNil(ClotureSegment.bornes(creneaux: [], maintenant: maintenant))
        XCTAssertNil(ClotureSegment.bornes(creneaux: [effectif("2026-11-01T06:02:00Z", "2026-11-01T14:01:00Z")], maintenant: maintenant),
                     "segment fermé : rien à clôturer")
        XCTAssertNil(ClotureSegment.bornes(creneaux: [effectif("2026-11-01T23:58:00Z", nil, pause: true)], maintenant: maintenant),
                     "une pause n'est pas un segment de travail")
        XCTAssertNil(ClotureSegment.bornes(creneaux: [MissionSlot(id: "p", missionId: "m-1", debut: "2026-11-01T23:00:00Z", fin: nil,
                                                                  estPause: false, typeCreneau: "PREVISIONNEL")], maintenant: maintenant))
        XCTAssertNil(ClotureSegment.bornes(creneaux: [effectif("illisible", nil)], maintenant: maintenant))
        XCTAssertNil(ClotureSegment.bornes(creneaux: [effectif("2026-11-02T00:05:00Z", nil)], maintenant: maintenant),
                     "segment ouvert après maintenant : intervalle vide, jamais proposé")
    }

    func testRaisonEtMessagesRepritsDuWeb() throws {
        XCTAssertEqual(ClotureSegment.raison, "Clôture par l'établissement (oubli de scan / sans téléphone)")
        try SourceWebLot5.verifier("src/components/pointage/AffichageCodeRotatifEtab.tsx", contient: [
            ClotureSegment.raison, ClotureSegment.messageHeureInexistante,
            PresencesEtabPresentation.clotureProposer, PresencesEtabPresentation.clotureMessage,
            PresencesEtabPresentation.clotureHeure, PresencesEtabPresentation.cloturer, PresencesEtabPresentation.succesCloture,
        ])
    }
}
