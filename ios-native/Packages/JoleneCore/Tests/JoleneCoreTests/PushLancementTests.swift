import XCTest
@testable import JoleneCore

/// Arguments de lancement DEBUG du push (blueprint §2.7 et §3 T4), lus par `AppContainer` en DEBUG
/// seulement : `-JOLENE_PUSH_AUTORISATION nonDemandee|accordee|refusee|provisoire` (démo) et
/// `-JOLENE_PUSH_TOKEN_FACTICE <hex>` (preuve STAGING de T16, relue dans `tokens_push`).
final class PushLancementTests: XCTestCase {
    func testAutorisationDemo() {
        XCTAssertEqual(PushLancement.argumentAutorisation, "-JOLENE_PUSH_AUTORISATION")
        for etat in AutorisationPush.allCases {
            XCTAssertEqual(PushLancement.autorisation(arguments: ["Jolene", "-JOLENE_PUSH_AUTORISATION", etat.rawValue]), etat)
        }
        XCTAssertNil(PushLancement.autorisation(arguments: ["Jolene"]))
        XCTAssertNil(PushLancement.autorisation(arguments: ["-JOLENE_PUSH_AUTORISATION"]), "valeur absente")
        XCTAssertNil(PushLancement.autorisation(arguments: ["-JOLENE_PUSH_AUTORISATION", "granted"]), "valeur inconnue")
        XCTAssertEqual(PushLancement.autorisation(arguments: ["-JOLENE_MODE", "demo", "-JOLENE_PUSH_AUTORISATION", "refusee"]),
                       .refusee)
    }

    func testTokenFacticeHexadecimal() {
        XCTAssertEqual(PushLancement.argumentTokenFactice, "-JOLENE_PUSH_TOKEN_FACTICE")
        let hex = JetonsTest.hex(JetonsTest.b)
        XCTAssertEqual(PushLancement.tokenFactice(arguments: ["-JOLENE_PUSH_TOKEN_FACTICE", hex]), JetonsTest.b)
        XCTAssertEqual(PushLancement.tokenFactice(arguments: ["-JOLENE_PUSH_TOKEN_FACTICE", hex.uppercased()]), JetonsTest.b,
                       "casse indifférente ; l'enregistrement repasse en minuscules")
        XCTAssertEqual(PushCoordinator.hex(PushLancement.tokenFactice(arguments: ["-JOLENE_PUSH_TOKEN_FACTICE", hex]) ?? Data()), hex)
    }

    func testTokenFacticeRefuseToutCeQuiNEstPasUnTokenAPNsPlausible() {
        let hex = JetonsTest.hex(JetonsTest.a)
        let refuses = [
            "", String(hex.dropLast()), // longueur impaire
            String(hex.prefix(62)), // moins de 32 octets
            String(hex.dropLast(2)) + "zz", // caractère non hexadécimal
            " " + hex, hex + " ",
            String(repeating: "ab", count: 2049), // plus de 4096 caractères (borne de fn_upsert_token_push)
        ]
        for valeur in refuses {
            XCTAssertNil(PushLancement.tokenFactice(arguments: ["-JOLENE_PUSH_TOKEN_FACTICE", valeur]), "« \(valeur.prefix(12))… »")
        }
        XCTAssertNil(PushLancement.tokenFactice(arguments: ["-JOLENE_PUSH_TOKEN_FACTICE"]))
        XCTAssertNil(PushLancement.tokenFactice(arguments: []))
        XCTAssertNotNil(PushLancement.tokenFactice(arguments: ["-JOLENE_PUSH_TOKEN_FACTICE", String(repeating: "ab", count: 2048)]))
    }
}
