import XCTest
@testable import JoleneCore

/// Lot 3, T15 (D21, blueprint `LOT3_PLAN.md` §2.6 et §3 T15) : rien de ce que Sentry reçoit ne porte d'URL de rappel
/// (`token_hash`, `code`, `access_token`, `refresh_token`), de jeton, d'IBAN ni d'adresse e-mail. `CrashScrubber` est la
/// règle pure appliquée par les rappels `beforeSend` et `beforeBreadcrumb` de la cible app (`CrashReporting.swift`) à
/// chaque texte (message, valeur d'exception, transaction, fil d'Ariane) et à chaque dictionnaire (données des fils
/// d'Ariane, `extra`, contextes, étiquettes). Les valeurs de test sont fictives (IBAN d'exemple ISO 13616, domaines
/// `example.invalid`).
final class CrashScrubberTests: XCTestCase {
    private let masque = CrashScrubber.masque
    private let ibanExemple = "FR7630006000011234567890189"

    /// Aucun fragment de la valeur sensible ne survit au nettoyage.
    private func assertMasque(_ brut: String, sansFragments fragments: [String], attendu: String? = nil,
                              file: StaticString = #filePath, line: UInt = #line) {
        let net = CrashScrubber.texte(brut)
        for fragment in fragments {
            XCTAssertFalse(net.contains(fragment), "« \(fragment) » survit dans « \(net) »", file: file, line: line)
        }
        XCTAssertTrue(net.contains(masque), "aucun masque dans « \(net) »", file: file, line: line)
        if let attendu { XCTAssertEqual(net, attendu, file: file, line: line) }
    }

    // MARK: - URL de rappel et de session

    func testTokenHashDUnLienDeConfirmationEstMasque() {
        assertMasque("https://jolene.app/inscription/confirmer?token_hash=pkce_8f3a2b91c0&type=signup",
                     sansFragments: ["pkce_8f3a2b91c0"],
                     attendu: "https://jolene.app/inscription/confirmer?token_hash=\(masque)&type=signup")
    }

    func testCodePKCEDUnRetourEstMasqueSansToucherAuxAutresParametres() {
        assertMasque("Lien refusé : https://jolene.app/auth/callback?state=s1&code=4f9e2c7a-11aa-4b2c-9d0e-77f1a2b3c4d5",
                     sansFragments: ["4f9e2c7a", "77f1a2b3c4d5"],
                     attendu: "Lien refusé : https://jolene.app/auth/callback?state=s1&code=\(masque)")
    }

    func testAccessTokenEtRefreshTokenDuFragmentSontMasques() {
        let brut = "https://jolene.app/#access_token=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1LXB1c2gifQ.c2lnbmF0dXJl"
            + "&refresh_token=r3fr35h-t0k3n&expires_in=3600&type=recovery"
        assertMasque(brut, sansFragments: ["eyJhbGciOiJIUzI1NiJ9", "c2lnbmF0dXJl", "r3fr35h-t0k3n"])
        let net = CrashScrubber.texte(brut)
        XCTAssertTrue(net.contains("expires_in=3600"), "un paramètre non sensible reste lisible : \(net)")
        XCTAssertTrue(net.contains("type=recovery"), net)
    }

    func testParametreEncodeDansUneURLDeRedirectionEstMasque() {
        assertMasque("redirect_to=https%3A%2F%2Fjolene.app%2Finscription%2Fconfirmer%3Ftoken_hash%3Dhash-secret-42",
                     sansFragments: ["hash-secret-42"])
    }

    func testCleJSONSensibleDansUnTexteEstMasquee() {
        let brut = #"Réponse illisible : {"access_token":"jeton-opaque-1","code":"123456","refresh_token":"r-2"}"#
        assertMasque(brut, sansFragments: ["jeton-opaque-1", "123456", "r-2"])
    }

    func testJetonPorteurEtJWTIsolesSontMasques() {
        assertMasque("Authorization: Bearer sb-opaque.token_value-9", sansFragments: ["sb-opaque.token_value-9"])
        assertMasque("jeton eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.Zm9vYmFyYmF6 expiré",
                     sansFragments: ["eyJhbGciOiJIUzI1NiJ9", "Zm9vYmFyYmF6"])
    }

    func testNomsVoisinsNonSensiblesInchanges() {
        // `error_code` (refus IBAN, T14b), `barcode`, `status_code` : pas des paramètres de session.
        for texte in ["error_code=IBAN_INVALIDE", "barcode=3760001", "status_code=500", "codeEtablissement=E1"] {
            XCTAssertEqual(CrashScrubber.texte(texte), texte)
        }
    }

    // MARK: - IBAN

    func testIBANCompactEspaceOuEnMinusculesEstMasque() {
        assertMasque(ibanExemple, sansFragments: ["30006000011234567890189"], attendu: masque)
        assertMasque("FR76 3000 6000 0112 3456 7890 189", sansFragments: ["3000 6000", "7890 189"], attendu: masque)
        assertMasque("fr7630006000011234567890189", sansFragments: ["30006000011234567890189"])
        assertMasque("DE89370400440532013000", sansFragments: ["370400440532013000"])
    }

    func testIBANDansUnePhraseNeMasqueQueLIBAN() {
        XCTAssertEqual(CrashScrubber.texte("IBAN \(ibanExemple) refusé par le serveur"), "IBAN \(masque) refusé par le serveur")
        XCTAssertEqual(CrashScrubber.texte("IBAN FR76 3000 6000 0112 3456 7890 189 refusé"), "IBAN \(masque) refusé")
    }

    // MARK: - Adresses e-mail

    func testAdresseEMailEstMasquee() {
        assertMasque("Connexion refusée pour u-push@example.invalid", sansFragments: ["u-push", "example.invalid"],
                     attendu: "Connexion refusée pour \(masque)")
        assertMasque("https://jolene.app/connexion?email=prenom.nom%40example.invalid&x=1",
                     sansFragments: ["prenom.nom", "example.invalid"])
    }

    // MARK: - Textes sans donnée sensible

    func testTexteSansDonneeSensibleInchange() {
        for texte in [
            "Mission 3f2a9c1e-5b7d-4e2a-9c1e-5b7d4e2a9c1e introuvable",
            "PGRST202 : fonction absente", "HTTP 500", "/soignant/missions?tab=a-venir",
            "Fatal error: Unexpectedly found nil while unwrapping an Optional value",
            "MainTabView.presenter(_:)", "",
        ] {
            XCTAssertEqual(CrashScrubber.texte(texte), texte)
        }
    }

    func testNettoyageIdempotent() {
        let brut = "?token_hash=a&code=b u@example.invalid \(ibanExemple) Bearer x.y.z"
        let une = CrashScrubber.texte(brut)
        XCTAssertEqual(CrashScrubber.texte(une), une)
    }

    // MARK: - Dictionnaires (données des fils d'Ariane, `extra`, contextes)

    func testDictionnaireImbriqueMasqueParValeurEtParCle() throws {
        let brut: [String: Any] = [
            "url": "https://jolene.app/inscription/confirmer?token_hash=secret-1&type=signup",
            "email": "pas-une-adresse-mais-une-cle-sensible",
            "token_hash": "secret-2",
            "Code": "secret-3",
            "code": 42,
            "compte": 3,
            "detail": ["iban": "FR76 3000 6000 0112 3456 7890 189", "ecran": "profil"],
            "liste": ["ok", "u@example.invalid", 7],
            "lien": URL(string: "https://jolene.app/#access_token=secret-4")!,
        ]
        let net = CrashScrubber.dictionnaire(brut)
        let rendu = String(describing: net)
        for fragment in ["secret-1", "secret-2", "secret-3", "secret-4", "pas-une-adresse", "3000 6000", "u@example"] {
            XCTAssertFalse(rendu.contains(fragment), "« \(fragment) » survit : \(rendu)")
        }
        XCTAssertEqual(net["compte"] as? Int, 3, "les nombres sont conservés")
        XCTAssertEqual(net["code"] as? Int, 42, "un code numérique (NSError, HTTP) n'est pas une valeur de session")
        XCTAssertEqual(net["email"] as? String, masque)
        XCTAssertEqual(net["token_hash"] as? String, masque)
        XCTAssertEqual(net["Code"] as? String, masque, "clé sensible reconnue sans tenir compte de la casse")
        let detail = try XCTUnwrap(net["detail"] as? [String: Any])
        XCTAssertEqual(detail["ecran"] as? String, "profil")
        let liste = try XCTUnwrap(net["liste"] as? [Any])
        XCTAssertEqual(liste.count, 3)
        XCTAssertEqual(liste.first as? String, "ok")
        XCTAssertEqual(liste.last as? Int, 7)
    }

    func testEtiquettesNettoyees() {
        let net = CrashScrubber.etiquettes(["ecran": "connexion", "lien": "?code=c-1", "contact": "a@example.invalid"])
        XCTAssertEqual(net["ecran"], "connexion")
        XCTAssertEqual(net["lien"], "?code=\(masque)")
        XCTAssertEqual(net["contact"], masque)
    }

    func testContextesSansNomDeLAppareilEtNettoyes() throws {
        let net = CrashScrubber.contextes([
            "device": ["name": "iPhone de Prénom Nom", "model": "iPhone17,1", "family": "iOS"],
            "app": ["app_identifier": "app.jolene", "app_version": "2.0.0"],
            "jolene": ["dernier_lien": "https://jolene.app/?code=c-2"],
        ])
        let device = try XCTUnwrap(net["device"])
        XCTAssertNil(device["name"], "le nom de l'appareil porte souvent le prénom de la personne")
        XCTAssertEqual(device["model"] as? String, "iPhone17,1")
        XCTAssertEqual(net["app"]?["app_version"] as? String, "2.0.0")
        XCTAssertEqual(net["jolene"]?["dernier_lien"] as? String, "https://jolene.app/?code=\(masque)")
    }

    // MARK: - Fils d'Ariane

    func testFilsDArianeReseauJamaisConserves() {
        // Défense en profondeur : `enableNetworkBreadcrumbs = false` ; un fil `http` qui passerait quand même est rejeté.
        XCTAssertFalse(CrashScrubber.filConserve(categorie: "http", type: nil))
        XCTAssertFalse(CrashScrubber.filConserve(categorie: "app", type: "http"))
        XCTAssertFalse(CrashScrubber.filConserve(categorie: "HTTP", type: nil))
        XCTAssertTrue(CrashScrubber.filConserve(categorie: "navigation", type: "navigation"))
        XCTAssertTrue(CrashScrubber.filConserve(categorie: "ui.lifecycle", type: nil))
        XCTAssertTrue(CrashScrubber.filConserve(categorie: "touch", type: "user"))
    }
}
