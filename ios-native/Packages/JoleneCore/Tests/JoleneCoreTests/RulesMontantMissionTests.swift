import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/mission-finance-display.json` : port de `src/lib/missionFinanceDisplay.ts`
/// (`montantFinanceAfficheMission`, `netEstimeAfficheMission`, correction de l'ancien plafond Rist).
final class RulesMontantMissionTests: XCTestCase {
    private func golden(_ montant: MontantMissionAffiche?) -> JSONValue {
        guard let montant else { return .null }
        return .object([
            "montant": .number(montant.montant),
            "nature": .string(montant.nature.rawValue),
            "libelle": .string(montant.libelle),
            "libelleCourt": .string(montant.libelleCourt),
            "approximatif": .bool(montant.approximatif),
        ])
    }

    func testVecteursGoldenMontantMission() throws {
        let rejoues = try Golden.rejouer("mission-finance-display") { vecteur in
            let mission = try XCTUnwrap(vecteur.input["mission"]).decode(MissionFinanceAffichee.self)
            switch vecteur.fonction {
            case "montantFinanceAfficheMission":
                return golden(MontantMission.montantAffiche(mission))
            case "netEstimeAfficheMission":
                return MontantMission.netEstimeAffiche(mission).map(JSONValue.number) ?? .null
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 500)
    }

    func testLibellesVerbatimDuWeb() {
        // missionFinanceDisplay.ts l.103-104, l.115-116, l.126-127 (HARD STOP n°4 : textes verbatim).
        let liberal = MontantMission.montantAffiche(MissionFinanceAffichee(typeContratApplique: "LIBERAL", netAPayer: 100))
        XCTAssertEqual(liberal, MontantMissionAffiche(montant: 100, nature: .honorairesLiberaux, libelle: "Honoraires bruts",
                                                      libelleCourt: "honoraires", approximatif: false))
        let salarie = MontantMission.montantAffiche(MissionFinanceAffichee(typeContratApplique: "SALARIE", netEstime: 80))
        XCTAssertEqual(salarie, MontantMissionAffiche(montant: 80, nature: .netSalarieEstime, libelle: "Net salarié estimé*",
                                                      libelleCourt: "net estimé*", approximatif: true))
        let brut = MontantMission.montantAffiche(MissionFinanceAffichee(typeContratRecherche: "TOUS", totalBrut: 120))
        XCTAssertEqual(brut, MontantMissionAffiche(montant: 120, nature: .brutIndicatif, libelle: "Rémunération brute indicative",
                                                   libelleCourt: "brut indicatif", approximatif: true))
    }

    func testColonnesDeMesGainsSansRistLaissentLeMontantIntact() {
        // Décision 5 du lot 3 : l'écran lit les colonnes de MesGains.tsx l.95 (sans colonnes Rist) ;
        // la correction reste inactive et aucun montant n'est recalculé.
        let mission = MissionFinanceAffichee(typeContratRecherche: "LIBERAL", netAPayer: 280.80)
        XCTAssertEqual(MontantMission.montantAffiche(mission)?.montant, 280.80)
    }

    func testUnMontantTexteSortDuDomaineType() {
        // Domaine du port : types de l'interface `MissionFinanceAffichee` (nombre JSON ou null).
        let json = Data(#"{"type_contrat_applique":"LIBERAL","net_a_payer":"100"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MissionFinanceAffichee.self, from: json))
    }
}
