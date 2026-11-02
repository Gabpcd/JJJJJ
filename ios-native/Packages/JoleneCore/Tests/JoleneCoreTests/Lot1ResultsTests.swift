import XCTest
@testable import JoleneCore

/// Contrats d'échange des ports du lot 1 (`Models/Lot1Results.swift`) : clés snake_case
/// explicites (PRINCIPES §2), décodage tolérant aux NULL PostgREST, sérialisation exacte
/// des paramètres envoyés au serveur.
final class Lot1ResultsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testCreneauConfirmeSerialiseExactementDebutEtFin() throws {
        let creneau = CreneauConfirmePayload(debut: "2026-11-03T07:00:00Z", fin: "2026-11-03T15:00:00Z")
        let encoded = try JSONEncoder().encode([creneau])
        let objet = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: String]])
        XCTAssertEqual(objet, [["debut": "2026-11-03T07:00:00Z", "fin": "2026-11-03T15:00:00Z"]])
        XCTAssertEqual(try decode([CreneauConfirmePayload].self, String(decoding: encoded, as: UTF8.self)), [creneau])
    }

    func testCreneauConfirmeMemeContratQueLeTypeDeT2() {
        // Même forme que `CreneauConfirme` de T2 (`Missions/CreneauxConfirmes.swift` :
        // `debut`/`fin` String, `init(debut:fin:)`, Codable + Hashable + Sendable) : la PR mergée
        // en second remplace l'un des deux par un `public typealias`, sans conversion en T6a.
        let a = CreneauConfirmePayload(debut: "2026-11-03T07:00:00Z", fin: "2026-11-03T15:00:00Z")
        var b = a
        b.fin = "2026-11-03T16:00:00Z"
        let ensemble: Set<CreneauConfirmePayload> = [a, a, b]
        XCTAssertEqual(ensemble.count, 2)
        XCTAssertEqual(Set([a, b]), ensemble)
    }

    func testCandidatureToleranteAuxNull() throws {
        let complete = try decode(CandidatureRecord.self, """
        {"id":"c-1","mission_id":"m-1","statut":"EN_ATTENTE","message":"Disponible","type_contrat_choisi":"SALARIE",
         "cree_le":"2026-11-02T08:00:00+00:00","soignant_id":"u-1","acceptee_a":null}
        """)
        XCTAssertEqual(complete, CandidatureRecord(id: "c-1", missionId: "m-1", statut: "EN_ATTENTE", message: "Disponible",
                                                   typeContratChoisi: "SALARIE", creeLe: "2026-11-02T08:00:00+00:00"))
        let minimale = try decode(CandidatureRecord.self, #"{"id":"c-2","mission_id":"m-2","statut":null,"message":null}"#)
        XCTAssertEqual(minimale, CandidatureRecord(id: "c-2", missionId: "m-2", statut: nil, message: nil,
                                                   typeContratChoisi: nil, creeLe: nil))
        XCTAssertThrowsError(try decode(CandidatureRecord.self, #"{"mission_id":"m-3"}"#), "id conditionne toute action")
    }

    func testChoixContratOption() throws {
        let options = try decode([ChoixContratOption].self, """
        [{"value":"SALARIE","label":"Salarié (CDD / bulletin de paie)"},{"value":"LIBERAL","label":"Libéral (note d'honoraires)"}]
        """)
        XCTAssertEqual(options.map(\.value), ["SALARIE", "LIBERAL"])
        XCTAssertEqual(options.first?.label, "Salarié (CDD / bulletin de paie)")
    }

    func testFavorisDecodesDepuisLesFormesServeur() throws {
        let sauvegarde = try decode(MissionSauvegardee.self, """
        {"id":"s-1","mission_id":"m-1","cree_le":"2026-11-01T10:00:00+00:00","soignant_id":"u-1","notifie_expiration":false}
        """)
        XCTAssertEqual(sauvegarde, MissionSauvegardee(id: "s-1", missionId: "m-1", creeLe: "2026-11-01T10:00:00+00:00"))

        // Élément de `fn_mes_favoris_etablissements` (jsonb_agg, l.41844-41852 du dump).
        let favori = try decode(EtablissementFavori.self, """
        {"etablissement_id":"e-1","nom":"Clinique des Tests","ville":"Lyon","logo_url":null,
         "type_etablissement":"CLINIQUE","nb_missions_ouvertes":3,"cree_le":"2026-10-01T09:00:00+00:00"}
        """)
        XCTAssertEqual(favori, EtablissementFavori(id: "e-1", nom: "Clinique des Tests", ville: "Lyon", logoUrl: nil,
                                                   typeEtablissement: "CLINIQUE", nbMissionsOuvertes: 3,
                                                   creeLe: "2026-10-01T09:00:00+00:00"))
        let minimal = try decode(EtablissementFavori.self, #"{"etablissement_id":"e-2","nom":null}"#)
        XCTAssertEqual(minimal.id, "e-2")
        XCTAssertNil(minimal.nom)
        XCTAssertNil(minimal.nbMissionsOuvertes)
    }

    func testIssuesSontComparables() {
        XCTAssertNotEqual(CandidatureOutcome.planningAReconfirmer(code: "PLANNING_MODIFIE_RECONFIRMER", message: "a"),
                          CandidatureOutcome.refusee(code: "PLANNING_MODIFIE_RECONFIRMER", message: "a", documentsRequisPour: nil))
        XCTAssertEqual(AnnulationOutcome.annulee(points: -5, libre: false, contestable: true),
                       AnnulationOutcome.annulee(points: -5, libre: false, contestable: true))
        XCTAssertNotEqual(AuditResultat.enregistre, AuditResultat.nonEnregistre)
        XCTAssertEqual(DashboardSnapshot(), DashboardSnapshot(notifsNonLues: 0, missionsOublieesCount: 0))
    }
}
