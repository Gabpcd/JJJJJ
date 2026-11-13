import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/signature-sms-staging-admission.json`
/// (port de `readSignatureSmsStagingAdmission`, `src/lib/signatureSmsStagingAdmission.ts`).
final class RulesAdmissionRecetteTests: XCTestCase {
    private struct ErreurSimulee: Error {}

    /// Compte les appels simulés (l'export consigne leurs arguments `{ p_contrat_id }`).
    private final class Journal {
        var contrats: [String] = []
    }

    private func golden(_ admission: AdmissionSignatureRecette?) -> JSONValue {
        guard let admission else { return .null }
        return .object([
            "expiresAt": .instant(admission.expireLe),
            "canSend": .bool(admission.peutEnvoyer),
            "canValidate": .bool(admission.peutValider),
            "otpExpiresAt": .instant(admission.otpExpireLe),
        ])
    }

    private func lire(_ entree: JSONValue) async throws -> JSONValue {
        let reponse = try XCTUnwrap(entree["reponse"])
        let journal = Journal()
        let admission = await AdmissionRecette.lire(
            url: try XCTUnwrap(entree["url"]?.string),
            contratId: try XCTUnwrap(entree["contratId"]?.string),
            maintenant: try Golden.instant(entree["maintenant"])
        ) { contratId in
            journal.contrats.append(contratId)
            // `{ error }` non nul ou transport levé : le gateway lève, la règle renvoie nil.
            if reponse["leve"]?.bool == true { throw ErreurSimulee() }
            if let erreur = reponse["error"], !erreur.estNull { throw ErreurSimulee() }
            return try (reponse["data"] ?? .null).decode(ValeurJSON.self)
        }
        return .object([
            "appels": .array(journal.contrats.map { .object(["p_contrat_id": .string($0)]) }),
            "resultat": golden(admission),
        ])
    }

    func testVecteursGoldenAdmissionRecette() async throws {
        let rejoues = try await Golden.rejouerAsync("signature-sms-staging-admission") { vecteur in
            switch vecteur.fonction {
            case "readSignatureSmsStagingAdmission": return try await lire(vecteur.input)
            default: return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    func testURLStagingDeriveeDeLAllowlistDEnvironnement() {
        XCTAssertEqual(AdmissionRecette.urlStaging, "https://\(JoleneEnvironment.allowedProjectRefs[.staging]!).supabase.co")
        XCTAssertFalse(AdmissionRecette.doitInterroger(url: "https://\(JoleneEnvironment.allowedProjectRefs[.production]!).supabase.co",
                                                       contratId: "3f2c9a10-5b7d-4e21-9c3a-0d8e6f4b2a17"),
                       "jamais appelée hors STAGING : la fonction n'existe pas en production")
    }

    func testEchecFermeSurReponseMalformee() throws {
        let maintenant = try DateHeureParis.instantJolene("2026-11-02T10:00:00Z")
        XCTAssertNil(AdmissionRecette.interpreter(.null, maintenant: maintenant))
        XCTAssertNil(AdmissionRecette.interpreter(.tableau([]), maintenant: maintenant))
        XCTAssertNil(AdmissionRecette.interpreter(.objet(["admitted": .booleen(true)]), maintenant: maintenant))
        let valide: ValeurJSON = .objet([
            "admitted": .booleen(true), "can_send": .booleen(true), "can_validate": .booleen(false),
            "remaining": .nombre(1), "expires_at": .chaine("2026-11-02T10:30:00Z"),
        ])
        let admission = try XCTUnwrap(AdmissionRecette.interpreter(valide, maintenant: maintenant))
        XCTAssertTrue(admission.peutEnvoyer)
        XCTAssertNil(admission.otpExpireLe)
    }
}
