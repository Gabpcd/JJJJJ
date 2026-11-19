import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/statut-litige.json` (port de `src/lib/statut-litige-regles.ts`, L4-T2).
final class RulesStatutLitigeTests: XCTestCase {
    func testVecteursGoldenStatutLitige() throws {
        var parFonction: [String: Int] = [:]
        let rejoues = try Golden.rejouer("statut-litige") { vecteur in
            parFonction[vecteur.fonction, default: 0] += 1
            let statut = try XCTUnwrap(vecteur.input["statut"]?.string)
            switch vecteur.fonction {
            case "statutLitigeRegle":
                let regle = StatutLitige.regle(statut)
                return .object(["label": .string(regle.libelle), "icone": .string(regle.icone.rawValue),
                                "groupe": .string(regle.groupe.rawValue)])
            case "estResolu": return .bool(StatutLitige.estResolu(statut))
            case "peutProposerMediation": return .bool(StatutLitige.peutProposerMediation(statut))
            case "peutConfirmerAccord": return .bool(StatutLitige.peutConfirmerAccord(statut))
            default: return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 80)
        for fonction in ["statutLitigeRegle", "estResolu", "peutProposerMediation", "peutConfirmerAccord"] {
            XCTAssertGreaterThan(parFonction[fonction] ?? 0, 0, "aucun vecteur golden pour \(fonction)")
        }
    }

    /// Chaque groupe et chaque icône du web est atteint par au moins un statut connu (filtres de T8).
    func testGroupesEtIconesTousAtteints() {
        let connus = ["OUVERT", "EN_DISCUSSION", "EN_MEDIATION", "MEDIATION_EN_COURS", "REVUE_ADMIN", "RESOLU_ACCORD_PARTIES",
                      "RESOLU_FAVEUR_SOIGNANT", "RESOLU_FAVEUR_ETAB", "RESOLU_PARTAGE", "RESOLU_SOIGNANT", "RESOLU_ETABLISSEMENT",
                      "RESOLU_ADMIN", "FERME"].map(StatutLitige.regle)
        XCTAssertEqual(Set(connus.map(\.groupe)), Set(GroupeStatutLitige.allCases))
        XCTAssertEqual(Set(connus.map(\.icone)), Set(IconeStatutLitige.allCases))
    }
}
