import XCTest
@testable import JoleneCore

/// Lot 2, T9a — isolement du lecteur de contrat (`Contrats/LecteurContrat.swift`, décision 17, `LOT2_PLAN.md` §3
/// T9a) : la vue `WKWebView` de l'app (`Composition/ContratReaderView.swift`) n'exécute aucun script, ne charge
/// aucune ressource et ne suit aucune navigation. Ces règles sont pures et vérifiées ici : en-tête injecté (CSP
/// `default-src 'none'; style-src 'unsafe-inline'` et viewport) sans toucher au reste des octets contrôlés, règle
/// `WKContentRuleList` qui bloque chaque schéma de chargement, seul le chargement initial `about:blank` admis.
final class LecteurContratTests: XCTestCase {
    func testEnteteInjecteJusteApresLOuvertureDuHeadSansToucherAuReste() throws {
        let html = "<!doctype html>\n<html lang=\"fr\">\n<head>\n<meta charset=\"utf-8\" />\n<title>T</title>\n</head>\n<body><p>x</p></body>\n</html>"
        let isole = LecteurContrat.documentIsole(html)
        XCTAssertTrue(isole.contains("<head>" + LecteurContrat.entete), "la politique précède tout autre contenu du head")
        XCTAssertEqual(isole.components(separatedBy: LecteurContrat.entete).count, 2, "une seule injection")
        XCTAssertEqual(isole.replacingOccurrences(of: LecteurContrat.entete, with: ""), html, "octets contrôlés inchangés hors de l'en-tête")
        let csp = try XCTUnwrap(isole.range(of: "Content-Security-Policy"))
        let charset = try XCTUnwrap(isole.range(of: "<meta charset"))
        XCTAssertLessThan(csp.lowerBound, charset.lowerBound)
    }

    func testHeadEnMajusculesOuAvecAttributs() {
        let html = "<HTML><HEAD data-x=\"1\"><TITLE>T</TITLE></HEAD><BODY></BODY></HTML>"
        XCTAssertEqual(LecteurContrat.documentIsole(html),
                       "<HTML><HEAD data-x=\"1\">" + LecteurContrat.entete + "<TITLE>T</TITLE></HEAD><BODY></BODY></HTML>")
    }

    func testUnHeaderNEstPasUnHead() {
        let html = "<html lang=\"fr\"><body><header>Titre</header></body></html>"
        XCTAssertEqual(LecteurContrat.documentIsole(html),
                       "<html lang=\"fr\"><head>" + LecteurContrat.entete + "</head><body><header>Titre</header></body></html>")
    }

    func testFragmentSansHtmlNiHead() {
        XCTAssertEqual(LecteurContrat.documentIsole("<p>Contrat</p>"), "<head>" + LecteurContrat.entete + "</head><p>Contrat</p>")
        XCTAssertEqual(LecteurContrat.documentIsole(""), "<head>" + LecteurContrat.entete + "</head>")
    }

    func testOriginauxDeDemonstrationIsolesUneFois() throws {
        for fichier in ["demo-contrat-001.html", "demo-contrat-002.html"] {
            let html = String(decoding: try DemoFixtures.originalDemo(fichier: fichier), as: UTF8.self)
            let isole = LecteurContrat.documentIsole(html)
            XCTAssertEqual(isole.components(separatedBy: "Content-Security-Policy").count, 2, fichier)
            XCTAssertEqual(isole.replacingOccurrences(of: LecteurContrat.entete, with: ""), html, fichier)
            XCTAssertLessThan(try XCTUnwrap(isole.range(of: LecteurContrat.entete)).lowerBound,
                              try XCTUnwrap(isole.range(of: "<style>")).lowerBound, "\(fichier) : politique avant les styles")
        }
    }

    func testEnteteSansScriptNiReseau() {
        XCTAssertEqual(LecteurContrat.politiqueContenu, "default-src 'none'; style-src 'unsafe-inline'")
        XCTAssertTrue(LecteurContrat.entete.contains("content=\"default-src 'none'; style-src 'unsafe-inline'\""))
        XCTAssertTrue(LecteurContrat.entete.contains("name=\"viewport\""))
        XCTAssertFalse(LecteurContrat.entete.lowercased().contains("script"))
        XCTAssertFalse(LecteurContrat.entete.lowercased().contains("http:"))
        XCTAssertFalse(LecteurContrat.entete.lowercased().contains("https:"))
    }

    func testRegleDeBlocageCouvreChaqueSchemaDeChargement() throws {
        let donnees = Data(LecteurContrat.regleBlocage.utf8)
        let regles = try XCTUnwrap(try JSONSerialization.jsonObject(with: donnees) as? [[String: [String: String]]])
        XCTAssertEqual(regles.compactMap { $0["trigger"]?["url-filter"] },
                       ["^https?:", "^wss?:", "^ftps?:", "^file:", "^data:", "^blob:"])
        XCTAssertEqual(regles.compactMap { $0["action"]?["type"] }, Array(repeating: "block", count: 6))
        XCTAssertFalse(LecteurContrat.regleBlocage.contains("|"), "les filtres WebKit n'acceptent pas l'alternative")
        XCTAssertFalse(LecteurContrat.identifiantRegles.isEmpty)
    }

    func testSeulLeChargementInitialEstAutorise() throws {
        let vide = try XCTUnwrap(URL(string: "about:blank"))
        XCTAssertTrue(LecteurContrat.navigationAutorisee(url: vide, chargementInitialFait: false))
        XCTAssertFalse(LecteurContrat.navigationAutorisee(url: vide, chargementInitialFait: true), "aucun rechargement par le contenu")
        XCTAssertFalse(LecteurContrat.navigationAutorisee(url: URL(string: "https://jolene.app/contrat/k-1"), chargementInitialFait: false))
        XCTAssertFalse(LecteurContrat.navigationAutorisee(url: URL(string: "about:blank#signature"), chargementInitialFait: false))
        XCTAssertFalse(LecteurContrat.navigationAutorisee(url: URL(string: "mailto:contact@example.invalid"), chargementInitialFait: false))
        XCTAssertFalse(LecteurContrat.navigationAutorisee(url: nil, chargementInitialFait: false))
    }
}
