import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/format-mission.json` (port de `src/lib/format-mission.ts`).
final class RulesFormatMissionTests: XCTestCase {
    private func mission(_ valeur: JSONValue?) -> MissionHoraires {
        MissionHoraires(
            debutLe: valeur?["debut_le"]?.string,
            finLe: valeur?["fin_le"]?.string,
            dureeHeures: Golden.nombreJS(valeur?["duree_heures"]),
            nbCreneaux: Golden.entier(valeur?["nb_creneaux"])
        )
    }

    func testVecteursGoldenFormatMission() throws {
        let rejoues = try Golden.rejouer("format-mission") { vecteur in
            let m = mission(vecteur.input["mission"])
            switch vecteur.fonction {
            case "estMissionDeNuit": return .bool(FormatMission.estMissionDeNuit(debutISO: m.debutLe))
            case "estMultiJours": return .bool(FormatMission.estMultiJours(m))
            case "nbJoursTravailles": return .number(Double(FormatMission.nbJoursTravailles(m)))
            case "formatDateMission": return .string(FormatMission.formatDateMission(m))
            case "formatHorairesMission": return .string(FormatMission.formatHorairesMission(m))
            case "formatDureeCompacte": return .string(FormatMission.formatDureeCompacte(m))
            default: return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    func testProjectionDepuisMissionRecord() {
        let record = MissionRecord(
            id: "m1", intitule: "IDE de jour", description: nil, service: nil, professionRequise: "IDE",
            specialiteMedicaleRequise: nil, accepteNonSpecialises: nil,
            debutLe: "2026-09-03T08:00:00+02:00", finLe: "2026-09-03T15:30:00+02:00",
            dureeHeures: 7.5, nbCreneaux: 1, tauxHoraireBase: nil, tauxRistPlafonne: nil, ristPlafondApplique: nil,
            totalBrut: nil, netAPayer: nil, estUrgente: false, niveauUrgence: nil, statut: "OUVERTE",
            etablissementId: "e1", typeContratRecherche: nil, boosteeLe: nil, modeRemuneration: nil, retrocessionPct: nil
        )
        XCTAssertEqual(FormatMission.formatDureeCompacte(record.horaires), "7,5h")
        XCTAssertEqual(FormatMission.formatDateMission(record.horaires), "jeudi 3 septembre 2026")
        XCTAssertEqual(FormatMission.formatHorairesMission(record.horaires), "08h00 → 15h30 (7,5 h)")
    }
}
