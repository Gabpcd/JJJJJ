import XCTest
@testable import JoleneCore

/// Les quinze motifs de `public/.well-known/apple-app-site-association` : un chemin accepté et
/// un refusé par motif, ordre du fichier, sémantique du glob, et garde de dérive avec le fichier.
final class LinksAASATests: XCTestCase {
    func testQuinzeMotifsDansLOrdreDuFichier() {
        XCTAssertEqual(AASAPatterns.paths.count, 15)
        XCTAssertEqual(AASAPatterns.paths, [
            "/soignant/*", "/etablissement/*", "/groupe/*", "/admin/*", "/connexion", "/inscription/*",
            "/reset-password", "/auth/psc/callback", "/etab/invitation/*", "/mission/*", "/contrat/*",
            "/soignant/missions", "/soignant/missions/*", "/etablissement/missions", "/etablissement/missions/*",
        ])
    }

    /// Un chemin accepté et un chemin refusé pour chacun des quinze motifs, pris isolément.
    func testChaqueMotifAccepteEtRefuse() {
        let cases: [(pattern: String, accepted: String, refused: String)] = [
            ("/soignant/*", "/soignant/tableau-de-bord", "/soignant"),
            ("/etablissement/*", "/etablissement/missions/creer", "/etablissements/x"),
            ("/groupe/*", "/groupe/tableau-de-bord", "/groupes"),
            ("/admin/*", "/admin/litiges", "/administration/x"),
            ("/connexion", "/connexion", "/connexion/"),
            ("/inscription/*", "/inscription/confirmer", "/inscription"),
            ("/reset-password", "/reset-password", "/reset-password/x"),
            ("/auth/psc/callback", "/auth/psc/callback", "/auth/psc/callback/x"),
            ("/etab/invitation/*", "/etab/invitation/token", "/etab/invitations/token"),
            ("/mission/*", "/mission/abc", "/missions/abc"),
            ("/contrat/*", "/contrat/contrat-id", "/contrats/contrat-id"),
            ("/soignant/missions", "/soignant/missions", "/soignant/missions/"),
            ("/soignant/missions/*", "/soignant/missions/abc", "/soignant/mission/abc"),
            ("/etablissement/missions", "/etablissement/missions", "/etablissement/mission"),
            ("/etablissement/missions/*", "/etablissement/missions/abc/modifier", "/etablissement/missionsx"),
        ]
        XCTAssertEqual(cases.count, 15)
        for c in cases {
            XCTAssertTrue(AASAPatterns.paths.contains(c.pattern), c.pattern)
            XCTAssertTrue(AASAPatterns.matches(pattern: c.pattern, path: c.accepted), "\(c.pattern) devrait accepter \(c.accepted)")
            XCTAssertFalse(AASAPatterns.matches(pattern: c.pattern, path: c.refused), "\(c.pattern) devrait refuser \(c.refused)")
        }
    }

    /// `*` = sous-chaîne quelconque (vide incluse, « / » inclus) ; `?` = un caractère ; casse respectée.
    func testSemantiqueDuGlob() {
        XCTAssertTrue(AASAPatterns.matches(pattern: "/soignant/*", path: "/soignant/"))
        XCTAssertTrue(AASAPatterns.matches(pattern: "/soignant/*", path: "/soignant/missions/abc/def"))
        XCTAssertFalse(AASAPatterns.matches(pattern: "/soignant/*", path: "/Soignant/missions"))
        XCTAssertTrue(AASAPatterns.matches(pattern: "/mission/?", path: "/mission/a"))
        XCTAssertFalse(AASAPatterns.matches(pattern: "/mission/?", path: "/mission/ab"))
        XCTAssertTrue(AASAPatterns.matches(pattern: "*", path: "/n/importe/quoi"))
        XCTAssertTrue(AASAPatterns.matches(pattern: "/a/*/c", path: "/a/b/x/c"))
        XCTAssertFalse(AASAPatterns.matches(pattern: "/a/*/c", path: "/a/b/x/d"))
    }

    /// Premier motif gagnant : `/soignant/missions` est capté par le motif 1, pas par le 12.
    func testPremierMotifGagnant() {
        XCTAssertEqual(AASAPatterns.firstMatch(path: "/soignant/missions")?.index, 0)
        XCTAssertEqual(AASAPatterns.firstMatch(path: "/soignant/missions/abc")?.index, 0)
        XCTAssertEqual(AASAPatterns.firstMatch(path: "/etablissement/missions")?.index, 1)
        XCTAssertEqual(AASAPatterns.firstMatch(path: "/admin/litiges")?.pattern, "/admin/*")
        XCTAssertEqual(AASAPatterns.firstMatch(path: "/groupe/x")?.pattern, "/groupe/*")
        XCTAssertEqual(AASAPatterns.firstMatch(path: "/mission/abc")?.index, 9)
        XCTAssertNil(AASAPatterns.firstMatch(path: "/"))
        XCTAssertNil(AASAPatterns.firstMatch(path: "/aide/pro-sante-connect"))
        XCTAssertNil(AASAPatterns.firstMatch(path: "/soignant"))
    }

    /// Garde de dérive : la constante Swift doit être identique aux `paths` du fichier versionné,
    /// pour chacun des appID déclarés. Ignoré si le dépôt web n'est pas présent (package isolé).
    func testTableIdentiqueAuFichierDuDepot() throws {
        let here = URL(fileURLWithPath: #filePath)
        // Tests/JoleneCoreTests/LinksAASATests.swift -> racine du dépôt (5 niveaux au-dessus).
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = repoRoot.appendingPathComponent("public/.well-known/apple-app-site-association")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw XCTSkip("Fichier AASA introuvable : \(file.path)")
        }
        let data = try Data(contentsOf: file)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let applinks = try XCTUnwrap(json["applinks"] as? [String: Any])
        let details = try XCTUnwrap(applinks["details"] as? [[String: Any]])
        XCTAssertFalse(details.isEmpty)
        for detail in details {
            let appID = detail["appID"] as? String ?? "?"
            XCTAssertEqual(detail["paths"] as? [String], AASAPatterns.paths, "dérive AASA pour \(appID)")
        }
    }
}
