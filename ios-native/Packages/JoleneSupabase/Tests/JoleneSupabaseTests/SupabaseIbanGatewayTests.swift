import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// IBAN sur Supabase (lot 3, T14b, B9 ; D20, TJ6 ; liste de tests du blueprint §3 T14b) :
/// - `success:false` sans `error` → refus portant le code, jamais « IBAN enregistré » ;
/// - `TITULAIRE_NON_CONCORDANT` / `RIB_VERIFIE_REQUIS` → `error` serveur verbatim ;
/// - succès → `fn_consulter_mon_iban` relue, `iban_verifie == true` (et les quatre derniers caractères) exigés ;
/// - un seul POST d'enregistrement, IBAN nettoyé et titulaire envoyés tels quels, jamais renvoyés.
final class SupabaseIbanGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let consulterChemin = "/rest/v1/rpc/fn_consulter_mon_iban"
    private let enregistrerChemin = "/rest/v1/rpc/fn_enregistrer_mon_iban"
    private let iban = "FR7630006000011234567890189"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseIbanGateway { SupabaseIbanGateway(client: TestClient.make()) }

    private static let verifieJSON = #"{"iban_renseigne":true,"iban_verifie":true,"verification_requise":false,"iban_last4":"0189","iban_titulaire":"Camille Test"}"#

    // MARK: - Consulter

    func testConsulterDecodeEtProfilIntrouvableSansVerificationRequise() async throws {
        registry.add("POST", consulterChemin, respond: .json(200, Self.verifieJSON))
        let lue = try await gateway().consulter(context: TestClient.context)
        XCTAssertEqual(lue, ConsultationIban(ibanRenseigne: true, ibanVerifie: true, verificationRequise: false,
                                             ibanLast4: "0189", ibanTitulaire: "Camille Test"))
        registry.reset()
        // Profil introuvable (dump l.25938) : deux clés seulement, `verification_requise` dérivée comme au serveur.
        registry.add("POST", consulterChemin, respond: .json(200, #"{"iban_renseigne":false,"iban_verifie":false}"#))
        let vide = try await gateway().consulter(context: TestClient.context)
        XCTAssertEqual(vide, ConsultationIban(ibanRenseigne: false, ibanVerifie: false, verificationRequise: false))
    }

    func testConsulterErreursSessionEtContrat() async throws {
        let cas: [(String, JoleneError.Kind)] = [
            (#"{"error":"Non authentifié"}"#, .unauthorized),
            (#"{"iban_renseigne":"oui","iban_verifie":false}"#, .contract),
            (#"{"iban_renseigne":true,"iban_verifie":true,"verification_requise":false,"iban_last4":null}"#, .contract),
        ]
        for (corps, attendu) in cas {
            registry.reset()
            registry.add("POST", consulterChemin, respond: .json(200, corps))
            do {
                let lue = try await gateway().consulter(context: TestClient.context)
                XCTFail("\(corps) : erreur attendue, obtenu \(lue)")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, attendu, corps)
            }
        }
    }

    // MARK: - Enregistrer

    func testSuccesRelitLaConsultationEtExigeIbanVerifie() async throws {
        registry.add("POST", enregistrerChemin,
                     respond: .json(200, #"{"success":true,"iban_last4":"0189","titulaire":"Camille Test","source_document_id":"d-1"}"#))
        registry.add("POST", consulterChemin, respond: .json(200, Self.verifieJSON))
        let resultat = try await gateway().enregistrer(iban: iban, titulaire: "Camille Test", context: TestClient.context)
        guard case let .enregistre(relue) = resultat else { return XCTFail("succès attendu, obtenu \(resultat)") }
        XCTAssertEqual(relue.ibanLast4, "0189")
        let appel = try XCTUnwrap(registry.requests(to: enregistrerChemin).first)
        XCTAssertEqual(appel.bodyJSON as? [String: String], ["p_iban": iban, "p_titulaire": "Camille Test"])
        XCTAssertEqual(registry.requests(to: enregistrerChemin).count, 1)
        XCTAssertEqual(registry.requests(to: consulterChemin).count, 1, "succès → relecture")
    }

    func testSuccesSansRelectureProbanteNEstJamaisEnregistre() async throws {
        let relectures = [
            #"{"iban_renseigne":true,"iban_verifie":false,"verification_requise":true,"iban_last4":"0189","iban_titulaire":null}"#,
            #"{"iban_renseigne":true,"iban_verifie":true,"verification_requise":false,"iban_last4":"9999","iban_titulaire":"X"}"#,
        ]
        for relecture in relectures {
            registry.reset()
            registry.add("POST", enregistrerChemin, respond: .json(200, #"{"success":true}"#))
            registry.add("POST", consulterChemin, respond: .json(200, relecture))
            do {
                let resultat = try await gateway().enregistrer(iban: iban, titulaire: "Camille Test", context: TestClient.context)
                XCTFail("relecture non probante : jamais un succès, obtenu \(resultat)")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur, JoleneError(.unknown, IbanTextes.erreurGenerique))
            }
            XCTAssertEqual(registry.requests(to: enregistrerChemin).count, 1, "jamais renvoyé")
        }
    }

    func testRefusSansErrorPorteLeCodeJamaisUnSucces() async throws {
        for code in ["IBAN_INVALIDE", "RIB_COURANT_REQUIS", "IDENTITE_VERIFIEE_REQUISE", "IDENTITE_COURANTE_REQUISE",
                     "RIB_NON_CONCORDANT"] {
            registry.reset()
            registry.add("POST", enregistrerChemin, respond: .json(200, #"{"success":false,"error_code":"\#(code)"}"#))
            let resultat = try await gateway().enregistrer(iban: iban, titulaire: "Camille Test", context: TestClient.context)
            XCTAssertEqual(resultat, .refuse(code: code, message: nil), code)
            XCTAssertTrue(registry.requests(to: consulterChemin).isEmpty, "\(code) : aucune relecture de succès")
        }
    }

    func testRefusAvecErrorVerbatim() async throws {
        let cas = [("TITULAIRE_NON_CONCORDANT", "Le titulaire doit correspondre exactement à votre identité vérifiée."),
                   ("RIB_VERIFIE_REQUIS", "Téléversez puis faites vérifier le RIB correspondant.")]
        for (code, message) in cas {
            registry.reset()
            registry.add("POST", enregistrerChemin,
                         respond: .json(200, #"{"success":false,"error_code":"\#(code)","error":"\#(message)"}"#))
            let resultat = try await gateway().enregistrer(iban: iban, titulaire: "Camille Test", context: TestClient.context)
            XCTAssertEqual(resultat, .refuse(code: code, message: message))
        }
    }

    func testNonAuthentifieProfilIntrouvableEtCorpsInattendu() async throws {
        let cas: [(String, JoleneError)] = [
            (#"{"success":false,"error_code":"NON_AUTHENTIFIE"}"#,
             JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)),
            (#"{"success":false,"error_code":"PROFIL_INTROUVABLE"}"#, JoleneError(.contract, IbanTextes.erreurGenerique)),
            (#"{"ok":true}"#, JoleneError(.contract, SupabaseErrorMapping.contractMessage)),
        ]
        for (corps, attendu) in cas {
            registry.reset()
            registry.add("POST", enregistrerChemin, respond: .json(200, corps))
            do {
                let resultat = try await gateway().enregistrer(iban: iban, titulaire: "Camille Test", context: TestClient.context)
                XCTFail("\(corps) : erreur attendue, obtenu \(resultat)")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur, attendu, corps)
            }
        }
    }

    /// Test-garde : RPC et paramètres du web (`SectionPaiements.tsx` l.242, l.254-257).
    func testRPCIdentiquesALaSourceWeb() throws {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let web = try String(contentsOf: racine.appendingPathComponent("src/components/profil-soignant/SectionPaiements.tsx"),
                             encoding: .utf8).components(separatedBy: "\n")
        XCTAssertTrue(web[241].contains("supabase.rpc('\(SupabaseIbanGateway.consulterRPC)'"), "l.242")
        XCTAssertTrue(web[253].contains("supabase.rpc('\(SupabaseIbanGateway.enregistrerRPC)'"), "l.254")
        XCTAssertTrue(web[254].contains("p_iban: ibanClean"), "l.255")
        XCTAssertTrue(web[255].contains("p_titulaire: titulaire.trim()"), "l.256")
    }
}
