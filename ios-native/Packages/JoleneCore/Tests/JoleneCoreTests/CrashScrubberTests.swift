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

    // MARK: - Revue B8 n°1, m2 : faux négatifs

    func testParametresDeLaFamilleDesJetonsEtMotDePasseSontMasques() {
        // `provider_refresh_token` et `provider_token` (retour OAuth de Supabase), `token`, `password`.
        assertMasque("https://jolene.app/#access_token=acc-0&provider_token=p-secret-1&provider_refresh_token=p-secret-2&type=x",
                     sansFragments: ["acc-0", "p-secret-1", "p-secret-2"])
        XCTAssertTrue(CrashScrubber.texte("?provider_refresh_token=p-secret-2&type=x").hasSuffix("&type=x"),
                      "les paramètres voisins restent lisibles")
        assertMasque("lien ?token=t-secret-3&type=invite", sansFragments: ["t-secret-3"],
                     attendu: "lien ?token=\(masque)&type=invite")
        assertMasque("form password=m0t-de-p4sse&email=x", sansFragments: ["m0t-de-p4sse"])
        assertMasque("mot_de_passe=secret-fr-1 motDePasse=\"secret-fr-2\"", sansFragments: ["secret-fr-1", "secret-fr-2"])
    }

    func testClesCamelCaseDUneDescriptionSwiftSontMasquees() {
        // Description d'une session (`String(describing:)`, `dump`) : clés camelCase, valeurs entre guillemets.
        let brut = #"Session(accessToken: "acc-secret-1", refreshToken: "ref-secret-2", tokenHash: Optional("th-secret-3"), "#
            + #"expiresIn: 3600, providerRefreshToken: "prov-secret-4")"#
        assertMasque(brut, sansFragments: ["acc-secret-1", "ref-secret-2", "th-secret-3", "prov-secret-4"])
        XCTAssertTrue(CrashScrubber.texte(brut).contains("expiresIn: 3600"), "un champ non sensible reste lisible")
    }

    func testJSONEchappeEtClesCamelCaseEnJSONSontMasques() {
        // JSON dans une chaîne JSON (corps de réponse journalisé tel quel) : guillemets échappés.
        let echappe = #"{"body":"{\"refresh_token\":\"esc-secret-1\",\"user\":\"u-1\",\"tokenHash\":\"esc-secret-2\"}"}"#
        assertMasque(echappe, sansFragments: ["esc-secret-1", "esc-secret-2"])
        XCTAssertTrue(CrashScrubber.texte(echappe).contains(#"\"user\":\"u-1\""#), CrashScrubber.texte(echappe))
        assertMasque(#"{"accessToken":"js-secret-3","refreshToken":"js-secret-4"}"#, sansFragments: ["js-secret-3", "js-secret-4"])
        // Valeur coupée (texte tronqué) : masquée jusqu'à la fin.
        assertMasque(#"{"refresh_token":"coupe-secret-5"#, sansFragments: ["coupe-secret-5"])
    }

    func testDoubleEncodageEstMasque() {
        // URL de redirection encodée deux fois (`%25` = `%`) : `%253F` pour `?`, `%253D` pour `=`.
        assertMasque("redirect_to=https%253A%252F%252Fjolene.app%252Finscription%253Ftoken_hash%253Ddouble-secret-1",
                     sansFragments: ["double-secret-1"])
        assertMasque("next=%252F%253Fcode%253Ddouble-secret-2%2526type%253Dx", sansFragments: ["double-secret-2"])
        assertMasque("contact=prenom.nom%2540example.invalid", sansFragments: ["prenom.nom", "example.invalid"])
    }

    func testIBANSepareParEspacesInsecablesOuTiretsEstMasque() {
        for separateur in ["\u{00A0}", "\u{202F}", "-"] {
            let iban = ["FR76", "3000", "6000", "0112", "3456", "7890", "189"].joined(separator: separateur)
            assertMasque("IBAN \(iban) refusé", sansFragments: ["3000", "7890", "189"], attendu: "IBAN \(masque) refusé")
        }
    }

    func testIdentifiantsTechniquesVoisinsToujoursLisibles() {
        // Généralisation des noms (suffixe `token`, camelCase) et des séparateurs d'IBAN (tiret) : aucun excès de masque
        // sur les identifiants techniques — UUID de mission commençant par deux lettres et deux chiffres compris.
        for texte in ["token_type=bearer", "tokens=3", "passwordless=true", "errorCode: \"IBAN_INVALIDE\"",
                      "Mission ab12cd34-ef56-ab78-cd90-ef12ab34cd56 introuvable", "FR-75 Paris",
                      "error_code=IBAN_INVALIDE", "barcode=3760001", "status_code=500", "codeEtablissement=E1"] {
            XCTAssertEqual(CrashScrubber.texte(texte), texte)
        }
    }

    func testCleSensibleMasqueToutTypeDeValeur() throws {
        // Une clé sensible masque sa valeur quel qu'en soit le type (tableau, dictionnaire, nombre) ; seul un nombre sous
        // la clé exacte `code` est conservé (code d'erreur NSError ou HTTP, `testDictionnaireImbriqueMasqueParValeurEtParCle`).
        let brut: [String: Any] = [
            "refresh_token": ["tab-secret-1"],
            "password": ["champ": "dict-secret-2"],
            "refreshToken": "camel-secret-3",
            "tokenHash": "camel-secret-4",
            "provider_refresh_token": "prov-secret-5",
            "access-token": 42,
            "code": 7,
            "ecran": "profil",
        ]
        let net = CrashScrubber.dictionnaire(brut)
        let rendu = String(describing: net)
        for fragment in ["tab-secret-1", "dict-secret-2", "camel-secret-3", "camel-secret-4", "prov-secret-5", "42"] {
            XCTAssertFalse(rendu.contains(fragment), "« \(fragment) » survit : \(rendu)")
        }
        for cle in ["refresh_token", "password", "refreshToken", "tokenHash", "provider_refresh_token", "access-token"] {
            XCTAssertEqual(net[cle] as? String, masque, cle)
        }
        XCTAssertEqual(net["code"] as? Int, 7)
        XCTAssertEqual(net["ecran"] as? String, "profil")
        XCTAssertEqual(CrashScrubber.etiquettes(["refreshToken": "e-1", "token_type": "bearer"]),
                       ["refreshToken": masque, "token_type": "bearer"])
    }

    // MARK: - Revue B8 de la vague 5, m3 : faux négatifs résiduels

    func testAdresseAPartieLocaleNonASCIIEstMasquee() {
        // La lecture à rebours s'arrêtait sur la première lettre non ASCII : ni la partie locale ni le domaine n'étaient
        // masqués. Lettres accentuées (composées ou décomposées), autres écritures, domaine internationalisé.
        assertMasque("Connexion refusée pour josé@example.fr", sansFragments: ["josé", "example.fr"],
                     attendu: "Connexion refusée pour \(masque)")
        assertMasque("contact jose\u{0301}.noe\u{0308}l@example.fr", sansFragments: ["jose", "l@", "example"],
                     attendu: "contact \(masque)")
        assertMasque("zoë.müller@exämple.fr refusée", sansFragments: ["zoë", "müller", "exämple"], attendu: "\(masque) refusée")
        assertMasque("adresse 李雷@example.cn", sansFragments: ["李雷", "example.cn"], attendu: "adresse \(masque)")
        assertMasque("email=renée%40example.fr&x=1", sansFragments: ["renée", "example.fr"])
    }

    func testCodeOTPDeSignatureEstMasque() throws {
        // `fn_signer_contrat_otp(p_contrat_id, p_otp_code, …)` (rpc-contracts.json) : le code reçu par SMS signe le contrat.
        let corps = #"{"p_contrat_id":"c-1","p_otp_code":"otp-secret-1","p_hash_document":"h-1"}"#
        assertMasque(corps, sansFragments: ["otp-secret-1"])
        XCTAssertTrue(CrashScrubber.texte(corps).contains(#""p_contrat_id":"c-1""#), "les paramètres voisins restent lisibles")
        assertMasque("otp=654321", sansFragments: ["654321"], attendu: "otp=\(masque)")
        assertMasque("?otp_code=445566&type=x", sansFragments: ["445566"], attendu: "?otp_code=\(masque)&type=x")
        assertMasque(#"Signature(otpCode: "112233", contratId: "c-2")"#, sansFragments: ["112233"])
        assertMasque(#"{"p_otp_code":778899}"#, sansFragments: ["778899"])
        let net = CrashScrubber.dictionnaire(["p_otp_code": "otp-secret-2", "otp": 123_456, "otpCode": "otp-secret-3",
                                              "p_contrat_id": "c-3"])
        XCTAssertEqual(net["p_otp_code"] as? String, masque)
        XCTAssertEqual(net["otp"] as? String, masque, "un code OTP numérique est masqué")
        XCTAssertEqual(net["otpCode"] as? String, masque)
        XCTAssertEqual(net["p_contrat_id"] as? String, "c-3")
    }

    func testCodeNumeriqueDansUnTexteEtCodeDePointageSontMasques() throws {
        // Dans un texte, rien ne distingue un code d'erreur d'un code OTP ou de pointage : tout nombre sous `code` est masqué
        // (revue B8 de la vague 5, m3), comme un texte. `p_code` (code QR de pointage, `fn_scanner_code_pointage`) aussi.
        for (brut, secret) in [
            ("code=123456", "123456"),
            (#"{"code":"223456"}"#, "223456"),
            (#"{"code":323456}"#, "323456"),
            (#"{"code": -42.5e3, "x": 1}"#, "42.5e3"),
            ("Verification(code: 423456)", "423456"),
            ("code: Optional(523456)", "523456"),
            (#"{"body":"{\"code\":623456}"}"#, "623456"),
            ("p_code=723456", "723456"),
            (#"{"p_code":"823456","p_metadata":{}}"#, "823456"),
            (#"{"p_code":923456}"#, "923456"),
        ] {
            assertMasque(brut, sansFragments: [secret])
        }
        XCTAssertTrue(CrashScrubber.texte(#"{"p_code":"823456","p_metadata":{}}"#).contains(#""p_metadata":{}"#))
        XCTAssertTrue(CrashScrubber.texte(#"{"code": -42.5e3, "x": 1}"#).contains(#""x": 1"#), "la suite reste lisible")
        let net = CrashScrubber.dictionnaire(["p_code": 987_654, "pointage": ["p_code": "qr-secret-1"], "code": 42])
        XCTAssertEqual(net["p_code"] as? String, masque, "code de pointage numérique masqué")
        XCTAssertEqual((net["pointage"] as? [String: Any])?["p_code"] as? String, masque)
        XCTAssertEqual(net["code"] as? Int, 42, "dictionnaire : un nombre sous la clé exacte `code` reste un code d'erreur")
        // Noms voisins toujours lisibles.
        for texte in ["p_code_postal=75001", "postal_code=75001", "codePostal: 75001", "error_code=IBAN_INVALIDE",
                      "codeEtablissement=E1", "laptop=1", "status_code=500"] {
            XCTAssertEqual(CrashScrubber.texte(texte), texte)
        }
    }

    func testJetonNuApresUnNomSensibleDansUneDescriptionSwiftEstMasqueEnEntier() {
        // Revue B8 de la vague 5, 3ᵉ tour, m1 : `code: ABC123` passait en clair, `code: 12AB34` n'était masqué qu'à moitié
        // (le nombre `12`, pas `AB34`). Le jeton nu entier qui suit `nom :` est masqué, jusqu'au premier blanc ou signe.
        for (brut, secret) in [
            ("Verification(code: ABC123)", "ABC123"),
            ("code: 12AB34, suite", "AB34"),
            ("code: Optional(A1B2C3)", "A1B2C3"),
            ("p_code: qr_secret-9.x", "qr_secret-9.x"),
            ("otp: 4F2A9C", "4F2A9C"),
            ("refreshToken: v1.abc-def~", "abc-def"),
            ("email: jane.doe", "jane.doe"),
            ("code: é42ü", "é42ü"),
        ] {
            assertMasque(brut, sansFragments: [secret])
        }
        XCTAssertEqual(CrashScrubber.texte("code: 12AB34, suite"), "code: \"\(masque)\", suite", "jeton entier, suite lisible")
        XCTAssertEqual(CrashScrubber.texte("code: Optional(A1B2C3) fin"), "code: Optional(\"\(masque)\") fin")
        // Noms voisins toujours lisibles.
        for texte in ["errorCode: IBAN_INVALIDE", "status_code: E42", "barcode: X1", "codePostal: A75001",
                      "p_code_postal: X", "error_code: ABC123"] {
            XCTAssertEqual(CrashScrubber.texte(texte), texte)
        }
    }

    func testDescriptionSwiftNeLaissePasLaSuiteDUnIBANNiLeDomaineDUneAdresse() {
        // Revue B8 de #1136, B1 : la règle des descriptions Swift passait avant les adresses et les IBAN ; son jeton nu,
        // arrêté au premier blanc ou à l'arobase, laissait `1732 8844 …` et `@example.com` en clair.
        for (brut, fragments) in [
            ("iban: FR76 1732 8844 0018 3164 8362 916", ["FR76", "1732", "8844", "916"]),
            ("p_iban: FR76\u{00A0}1732\u{00A0}8844\u{00A0}0018\u{00A0}3164\u{00A0}8362\u{00A0}916", ["FR76", "1732", "916"]),
            ("email: jane.doe@example.com", ["jane", "doe", "example"]),
            ("Profil(email: Optional(jane.doe@example.com), code: 4F2A9C)", ["jane", "example", "4F2A9C"]),
        ] {
            assertMasque(brut, sansFragments: fragments)
        }
        XCTAssertEqual(CrashScrubber.texte("iban: FR76 1732 8844 0018 3164 8362 916"), "iban: \(masque)")
        XCTAssertEqual(CrashScrubber.texte("email: jane.doe@example.com"), "email: \(masque)")
    }

    func testJetonNuEncodeMasqueEtNilLisible() {
        // Revue B8 de #1136, m2 : `%` fait partie du jeton nu (`%2Bdef` passait en clair) ; m1 : `nil` seul reste lisible.
        assertMasque("refreshToken: abc%2Bdef", sansFragments: ["abc", "2Bdef"])
        XCTAssertEqual(CrashScrubber.texte("refreshToken: abc%2Bdef, suite"), "refreshToken: \"\(masque)\", suite")
        XCTAssertEqual(CrashScrubber.texte("Verification(code: nil, otp: nil)"), "Verification(code: nil, otp: nil)")
        assertMasque("code: nilou7", sansFragments: ["nilou7"])
    }

    /// Texte de `longueurMaximale` caractères au moins : des « a » séparés par une espace, puis `fin`, qui commence
    /// `avant` caractères avant la limite.
    private func texteCoupe(_ fin: String, avant: Int) -> String {
        let debut = CrashScrubber.longueurMaximale - avant
        precondition(debut % 2 == 0, "le préfixe « a » + espace doit finir par une espace")
        return String(repeating: "a ", count: debut / 2) + fin
    }

    func testMotCoupeParLaTroncatureRetireEnEntier() {
        // Une adresse coupée dans son domaine (`jean.dupont@exam`) n'était plus reconnue : sa partie locale survivait.
        for (fin, avant, fragments) in [
            ("jean.dupont@example.fr suite", 16, ["jean", "dupont", "exam"]),
            ("jean.dupont@example.fr suite", 6, ["jean"]),
            ("contact=jean.dupont%40example.fr&x=1 suite", 30, ["jean", "dupont"]),
            ("eyJhbGciOiJIUzI1NiJ9.eyJlbWFpbCI6ImpAZXhhbXBsZS5mciJ9.c2lnbmF0dXJl suite", 40, ["eyJ", "eyJlbWFpbCI6"]),
        ] {
            let net = CrashScrubber.texte(texteCoupe(fin, avant: avant))
            XCTAssertTrue(net.hasSuffix(CrashScrubber.marqueTroncature), "marqueur absent")
            for fragment in fragments {
                XCTAssertFalse(net.contains(fragment), "« \(fragment) » survit à la troncature de « \(fin) »")
            }
            XCTAssertTrue(net.hasSuffix("a \(CrashScrubber.marqueTroncature)"), "seul le mot coupé est retiré : …\(net.suffix(30))")
        }
        // Un mot qui finit exactement à la limite n'est pas coupé : il est gardé, puis nettoyé comme le reste.
        let entier = texteCoupe("mot-ok suite", avant: 6)
        XCTAssertTrue(CrashScrubber.texte(entier).hasSuffix("a mot-ok\(CrashScrubber.marqueTroncature)"))
        let adresseEntiere = texteCoupe("u@example.fr suite", avant: 12)
        XCTAssertTrue(CrashScrubber.texte(adresseEntiere).hasSuffix("a \(masque)\(CrashScrubber.marqueTroncature)"))
        // Un texte sans aucun blanc avant la limite est un seul mot coupé : rien n'en reste.
        XCTAssertEqual(CrashScrubber.texte(String(repeating: "x", count: 9_000)), CrashScrubber.marqueTroncature)
    }

    // MARK: - Revue B8 n°1, m1 : coût borné

    /// Durée la plus courte de trois nettoyages du même texte : une préemption ponctuelle du processus (simulateur ou
    /// runner chargé) ne fait pas échouer le test.
    private func dureeMinimale(_ texte: String) -> TimeInterval {
        (0..<3).map { _ -> TimeInterval in
            let debut = DispatchTime.now().uptimeNanoseconds
            _ = CrashScrubber.texte(texte)
            return TimeInterval(DispatchTime.now().uptimeNanoseconds - debut) / 1e9
        }.min() ?? .infinity
    }

    /// Seuil : 100 ms pour 8 000 caractères, en Debug, sur le simulateur comme en `swift test` macOS. Mesures de la
    /// correction (MacBook, Xcode 16.4, Debug) : de 0,7 à 8,6 ms en `swift test` macOS, de 1,1 à 3,3 ms sur le simulateur
    /// iPhone 16 (iOS 18.6). Avant elle, ces textes prenaient de 1,5 à 2,1 s : l'adresse e-mail non bornée, le JWT et les
    /// noms sans borne de début avaient un coût quadratique (`REVUES_LOT3.md`, section L3-T15). Plus d'un ordre de grandeur
    /// de marge : le test ne doit pas être instable sur un runner partagé. Revue B8 de la vague 5 (m3 : OTP, `p_code`,
    /// nombres, adresses non ASCII, mot coupé retiré) : de 0,6 à 6,0 ms par texte en `swift test` macOS (Xcode 16.4, Debug),
    /// simulateur non remesuré.
    static let seuilHuitMilleCaracteres: TimeInterval = 0.1

    func testHuitMilleCaracteresAdversesTraitesSousLeSeuil() {
        let unite = "https://jolene.app/confirmer?token_hash=h-1&type=signup {\"refresh_token\":\"r-2\"} u@example.invalid "
            + "FR76 3000 6000 0112 3456 7890 189 Bearer b.c.d eyJabcd.efgh.ijkl "
        let textes: [(String, String)] = [
            ("sans @ ni point", String(repeating: "a", count: 8_000)),
            ("partie locale d'adresse", String(repeating: "a.", count: 4_000)),
            ("début de JWT répété", String(repeating: "eyJ", count: 2_667)),
            ("noms de jetons collés", String(repeating: "x_token", count: 1_143)),
            ("adresse en fin de texte", String(repeating: "a", count: 7_990) + "@example.fr"),
            ("texte non ASCII", String(repeating: "aé", count: 4_000)),
            // Revue B8 de la vague 5, m3 : noms OTP et codes de pointage, partie locale non ASCII, mot coupé par la limite.
            ("noms OTP collés", String(repeating: "x_otp", count: 1_600)),
            ("codes de pointage collés", String(repeating: "p_code:", count: 1_143)),
            ("adresse non ASCII en fin de texte", String(repeating: "é", count: 7_990) + "@exämple.fr"),
            ("mot coupé de 9 000 caractères", String(repeating: "x", count: 9_000)),
            ("texte réaliste répété", String(repeating: unite, count: 8_000 / unite.count + 1)),
        ]
        for (nom, texte) in textes {
            XCTAssertGreaterThanOrEqual(texte.count, 8_000)
            let duree = dureeMinimale(texte)
            XCTAssertLessThan(duree, Self.seuilHuitMilleCaracteres,
                              "\(nom) : \(Int(duree * 1000)) ms pour \(texte.count) caractères")
        }
    }

    func testTexteTropLongTronqueAvecUnMarqueur() {
        XCTAssertEqual(CrashScrubber.longueurMaximale, 8_192)
        let avant = "?token_hash=coupe-secret-1 "
        let apres = " apres-la-coupure u@example.invalid"
        let brut = avant + String(repeating: "x ", count: 10_000) + apres
        let net = CrashScrubber.texte(brut)
        XCTAssertTrue(net.hasSuffix(CrashScrubber.marqueTroncature), "marqueur de troncature absent")
        XCTAssertEqual(net.count, CrashScrubber.longueurMaximale - avant.count + "?token_hash=\(masque) ".count
                       + CrashScrubber.marqueTroncature.count)
        XCTAssertFalse(net.contains("coupe-secret-1"), "la partie conservée est nettoyée")
        XCTAssertFalse(net.contains("apres-la-coupure"), "rien au-delà de la longueur maximale")
        // Un texte à la longueur maximale exacte n'est pas tronqué.
        let juste = String(repeating: "y", count: CrashScrubber.longueurMaximale)
        XCTAssertEqual(CrashScrubber.texte(juste), juste)
    }

    func testReglesCompileesUneFoisEtToutesValides() {
        // Expressions compilées une seule fois (`static let`) ; un motif invalide rendrait `regles` nil et chaque texte
        // serait masqué en entier (repli fermé), ce que ce test interdit.
        let regles = CrashScrubber.regles
        XCTAssertNotNil(regles, "une expression ne compile pas")
        XCTAssertEqual(regles?.count, 9)
        XCTAssertEqual(regles?.filter(\.adresse).count, 1, "une seule règle d'adresse, lue à rebours")
        XCTAssertTrue(regles?.first?.expression === CrashScrubber.regles?.first?.expression, "expressions recompilées")
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
