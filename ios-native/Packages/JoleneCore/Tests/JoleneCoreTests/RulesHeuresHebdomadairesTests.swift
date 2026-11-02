import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/heures-hebdomadaires-mission.json`
/// (port de `src/lib/heures-hebdomadaires-mission.ts`).
final class RulesHeuresHebdomadairesTests: XCTestCase {
    private func mission(_ valeur: JSONValue?) throws -> MissionPourCalculHebdomadaire {
        MissionPourCalculHebdomadaire(
            id: try XCTUnwrap(valeur?["id"]?.string),
            debutLe: try XCTUnwrap(valeur?["debut_le"]?.string),
            finLe: try XCTUnwrap(valeur?["fin_le"]?.string),
            dureeHeures: Golden.nombreJS(valeur?["duree_heures"]),
            nbCreneaux: Golden.entier(valeur?["nb_creneaux"]),
            statut: valeur?["statut"]?.string,
            typeContratApplique: valeur?["type_contrat_applique"]?.string,
            choixContratSoignant: valeur?["choix_contrat_soignant"]?.string,
            typeContratRecherche: valeur?["type_contrat_recherche"]?.string
        )
    }

    private func missions(_ valeur: JSONValue?) throws -> [MissionPourCalculHebdomadaire] {
        try (valeur?.array ?? []).map(mission)
    }

    private func creneaux(_ valeur: JSONValue?) throws -> [MissionSlot] {
        try (valeur ?? .array([])).decode([MissionSlot].self)
    }

    private func golden(_ semaine: HeuresSemaineMission) -> JSONValue {
        .object([
            "cleSemaine": .string(semaine.cleSemaine),
            "debutSemaine": .instant(semaine.debutSemaine),
            "heures": .number(semaine.heures),
        ])
    }

    private func golden(_ carte: [String: HeuresSemaineMission]) -> JSONValue {
        .object(carte.mapValues(golden))
    }

    func testVecteursGoldenHeuresHebdomadaires() throws {
        let rejoues = try Golden.rejouer("heures-hebdomadaires-mission") { vecteur in
            let entree = vecteur.input
            switch vecteur.fonction {
            case "debutSemaineCivile":
                return .instant(HeuresHebdomadaires.debutSemaineCivile(try Golden.instant(entree["valeur"])))
            case "cleSemaineCivile":
                return .string(HeuresHebdomadaires.cleSemaineCivile(try Golden.instant(entree["valeur"])))
            case "semaineSuivante":
                return .instant(HeuresHebdomadaires.semaineSuivante(try Golden.instant(entree["valeur"])))
            case "heuresMissionParSemaine":
                return .array(HeuresHebdomadaires.heuresMissionParSemaine(try mission(entree["mission"]), try creneaux(entree["creneaux"])).map(golden))
            case "planningMissionHebdomadaireDisponible":
                return .bool(HeuresHebdomadaires.planningMissionHebdomadaireDisponible(try mission(entree["mission"]), try creneaux(entree["creneaux"])))
            case "additionnerHeuresParSemaine":
                return golden(HeuresHebdomadaires.additionnerHeuresParSemaine(try missions(entree["missions"]), try creneaux(entree["creneaux"])))
            case "additionnerHeuresSalarieesParSemaine":
                return golden(HeuresHebdomadaires.additionnerHeuresSalarieesParSemaine(try missions(entree["missions"]), try creneaux(entree["creneaux"])))
            case "missionComptePourPlafond48h":
                return .bool(HeuresHebdomadaires.missionComptePourPlafond48h(try mission(entree["mission"])))
            case "missionPlafond48hConditionnel":
                return .bool(HeuresHebdomadaires.missionPlafond48hConditionnel(try mission(entree["mission"])))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    func testProjectionDepuisMissionRecordGardeLeRegimeRecherche() {
        let record = MissionRecord(
            id: "m1", intitule: "IDE", description: nil, service: nil, professionRequise: "IDE",
            specialiteMedicaleRequise: nil, accepteNonSpecialises: nil,
            debutLe: "2026-07-20T13:00:00+02:00", finLe: "2026-07-20T21:00:00+02:00",
            dureeHeures: 8, nbCreneaux: 1, tauxHoraireBase: nil, tauxRistPlafonne: nil, ristPlafondApplique: nil,
            totalBrut: nil, netAPayer: nil, estUrgente: false, niveauUrgence: nil, statut: "OUVERTE",
            etablissementId: "e1", typeContratRecherche: "LIBERAL", boosteeLe: nil, modeRemuneration: nil, retrocessionPct: nil
        )
        let projection = record.pourCalculHebdomadaire
        XCTAssertFalse(HeuresHebdomadaires.missionComptePourPlafond48h(projection))
        XCTAssertEqual(HeuresHebdomadaires.heuresMissionParSemaine(projection, []).map(\.heures), [8])
    }
}
