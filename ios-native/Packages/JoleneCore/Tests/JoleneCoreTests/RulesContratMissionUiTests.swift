import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/contrat-mission-ui.json` (port de `src/lib/contratMissionUi.ts`).
final class RulesContratMissionUiTests: XCTestCase {
    private func contrat(_ valeur: JSONValue?) throws -> PreuveSignatureContrat? {
        guard let valeur, !valeur.estNull else { return nil }
        return try valeur.decode(PreuveSignatureContrat.self)
    }

    func testVecteursGoldenContratMissionUi() throws {
        let rejoues = try Golden.rejouer("contrat-mission-ui") { vecteur in
            let entree = vecteur.input
            switch vecteur.fonction {
            case "contientVariablesContratNonRendues":
                return .bool(ContratMissionUi.contientVariablesContratNonRendues(entree["html"]?.string))
            case "contratPossedeSignature":
                return .bool(ContratMissionUi.contratPossedeSignature(try contrat(entree["contrat"])))
            case "contratNecessiteRenduServeur":
                // Le premier paramètre web (`_html`) est ignoré par la règle : le natif ne le prend pas.
                return .bool(ContratMissionUi.contratNecessiteRenduServeur(storagePath: entree["storagePath"]?.string,
                                                                           contrat: try contrat(entree["contrat"])))
            case "choisirContenuContratAffiche":
                return .string(ContratMissionUi.choisirContenuContratAffiche(
                    serveur: entree["contenuServeur"]?.string,
                    reconstitue: entree["contenuReconstitue"]?.string,
                    conserverOriginal: entree["conserverOriginal"]?.bool ?? false
                ))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    func testUnDocumentFigeNEstJamaisRegenere() {
        // Un changement de gabarit ne justifie jamais de réécrire un document stocké ou signé.
        XCTAssertFalse(ContratMissionUi.contratNecessiteRenduServeur(storagePath: "contrat/ancien.html", contrat: nil))
        XCTAssertFalse(ContratMissionUi.contratNecessiteRenduServeur(storagePath: nil,
                                                                    contrat: PreuveSignatureContrat(statut: "SIGNE_SOIGNANT")))
        XCTAssertTrue(ContratMissionUi.contratNecessiteRenduServeur(storagePath: nil,
                                                                   contrat: PreuveSignatureContrat(statut: "EN_ATTENTE_SIGNATURES")))
        XCTAssertEqual(ContratMissionUi.choisirContenuContratAffiche(serveur: "<p>Original {{variable}}</p>",
                                                                     reconstitue: "<p>Nouveau</p>", conserverOriginal: true),
                       "<p>Original {{variable}}</p>")
    }

    func testVariablesDeGabaritDetectees() {
        XCTAssertTrue(ContratMissionUi.contientVariablesContratNonRendues("<p>{{motif_cdd}}</p>"))
        XCTAssertTrue(ContratMissionUi.contientVariablesContratNonRendues("{{{x}}}"))
        XCTAssertTrue(ContratMissionUi.contientVariablesContratNonRendues("{{a\nb}}"))
        XCTAssertFalse(ContratMissionUi.contientVariablesContratNonRendues("{{}}"))
        XCTAssertFalse(ContratMissionUi.contientVariablesContratNonRendues("{{x}"))
        XCTAssertFalse(ContratMissionUi.contientVariablesContratNonRendues(nil))
    }
}
