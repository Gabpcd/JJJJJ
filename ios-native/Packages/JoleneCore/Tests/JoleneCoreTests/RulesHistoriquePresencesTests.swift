import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/presences-soignant-ui.json`
/// (port de `src/lib/presencesSoignantUi.ts`).
final class RulesHistoriquePresencesTests: XCTestCase {
    /// Projection de l'export : la ligne web recopie la mission (`...mission`), l'attendu n'en
    /// garde que l'identifiant, l'établissement résolu et les créneaux.
    private func golden(_ ligne: LigneHistoriqueEffectifs<JSONValue>) -> JSONValue {
        .object([
            "id": .string(ligne.id),
            "mission_id": .string(ligne.missionId),
            "soignant_id": .string(ligne.soignantId),
            "pointage_arrivee_le": .string(ligne.pointageArriveeLe),
            "pointage_depart_le": .chaine(ligne.pointageDepartLe),
            "valide_par_etablissement": .bool(ligne.valideParEtablissement),
            "valide_le": .chaine(ligne.valideLe),
            "methode_pointage_arrivee": .chaine(ligne.methodePointageArrivee),
            "methode_pointage_depart": .chaine(ligne.methodePointageDepart),
            "origine_effectifs_sans_presence": .bool(ligne.origineEffectifsSansPresence),
            "missions": .object([
                "id": .string(ligne.missionId),
                "etablissements": ligne.etablissement ?? .null,
                "creneaux": .array(ligne.creneaux.map(\.golden)),
            ]),
        ])
    }

    private func historique(_ entree: JSONValue) throws -> JSONValue {
        let missions = try XCTUnwrap(entree["missions"]?.array).map { mission in
            MissionHistorique(id: try XCTUnwrap(mission["id"]?.string), etablissementId: mission["etablissement_id"]?.string)
        }
        let presences = try XCTUnwrap(entree["presences"]?.array).map { $0["mission_id"]?.string }
        var creneaux: [String: [MissionSlot]] = [:]
        if case .object(let carte)? = entree["creneauxParMission"] {
            for (missionId, liste) in carte { creneaux[missionId] = try liste.decode([MissionSlot].self) }
        }
        var etablissements: [String: JSONValue] = [:]
        if case .object(let carte)? = entree["etablissements"] { etablissements = carte }
        let lignes = HistoriquePresences.construireEffectifsSansPresence(
            missions: missions, missionsAvecPresence: presences, creneauxParMission: creneaux,
            etablissements: etablissements, soignantId: try XCTUnwrap(entree["soignantId"]?.string)
        )
        return .array(lignes.map(golden))
    }

    func testVecteursGoldenPresencesSoignantUi() throws {
        let rejoues = try Golden.rejouer("presences-soignant-ui") { vecteur in
            switch vecteur.fonction {
            case "construireHistoriqueEffectifsSansPresence":
                return try historique(vecteur.input)
            case "mesureGpsDisponible":
                // Le natif décode `numeric` en `Double?` : toute autre valeur JSON (chaîne, booléen,
                // objet) n'est pas une mesure, exactement comme `typeof value === 'number'`.
                return .bool(HistoriquePresences.mesureGpsDisponible(vecteur.input["valeur"]?.double))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    func testUneLigneReconstruiteNeSePretendJamaisValidable() throws {
        let lignes = HistoriquePresences.construireEffectifsSansPresence(
            missions: [MissionHistorique(id: "m", etablissementId: "e")],
            missionsAvecPresence: [],
            creneauxParMission: ["m": [
                MissionSlot(debut: "2026-07-07T06:00:00Z", fin: "2026-07-07T10:00:00Z", estPause: false, typeCreneau: "EFFECTIF"),
                MissionSlot(debut: "2026-07-06T06:00:00Z", fin: "2026-07-06T14:00:00Z", estPause: false, typeCreneau: "EFFECTIF"),
            ]],
            etablissements: ["e": "Clinique Test"],
            soignantId: "s"
        )
        XCTAssertEqual(lignes.count, 1)
        let ligne = try XCTUnwrap(lignes.first)
        XCTAssertEqual(ligne.id, "effectifs-mission-m", "jamais un faux identifiant de présence")
        XCTAssertEqual(ligne.pointageArriveeLe, "2026-07-06T06:00:00Z", "premier segment par début")
        XCTAssertEqual(ligne.pointageDepartLe, "2026-07-07T10:00:00Z", "fin du dernier segment par début")
        XCTAssertEqual(ligne.valideParEtablissement, false)
        XCTAssertNil(ligne.valideLe)
        XCTAssertEqual(ligne.origineEffectifsSansPresence, true)
        XCTAssertEqual(ligne.etablissement, "Clinique Test")
    }

    func testMesureGpsAbsenteNEstPasUneDistanceNulle() {
        XCTAssertTrue(HistoriquePresences.mesureGpsDisponible(0))
        XCTAssertFalse(HistoriquePresences.mesureGpsDisponible(nil))
        XCTAssertFalse(HistoriquePresences.mesureGpsDisponible(-1))
        XCTAssertFalse(HistoriquePresences.mesureGpsDisponible(.nan))
        XCTAssertFalse(HistoriquePresences.mesureGpsDisponible(.infinity))
    }

    func testMissionLueUtilisableDirectement() throws {
        let record = MissionsTestSupport.record(nbCreneaux: 1)
        XCTAssertEqual(MissionHistorique(record: record), MissionHistorique(id: record.id, etablissementId: record.etablissementId))
    }
}
