import XCTest
@testable import JoleneCore

/// Carte « Autorisation du téléphone » (lot 3, T4 ; reprise par les préférences de T6) : textes
/// verbatim de `src/pages/PageParametresNotifications.tsx` l.341-352 (HARD STOP n°4), choisis comme
/// le web l.147-155 : autorisé ET enregistrement confirmé → « autorisées », autorisé sans
/// confirmation → « n'a pas pu être enregistré », non demandé → « doit encore autoriser »,
/// refusé → « bloquées ». Le canal push de Jolene (T6) n'est connu que des préférences.
final class EtatNotificationsAppareilTests: XCTestCase {
    private typealias E = EtatNotificationsAppareil

    private static func sourceWeb(_ chemin: String) throws -> String {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent(chemin)
        guard FileManager.default.fileExists(atPath: fichier.path) else {
            throw XCTSkip("\(chemin) introuvable : \(fichier.path)")
        }
        return try String(contentsOf: fichier, encoding: .utf8)
    }

    func testTextesVerbatimDuWeb() throws {
        let web = try Self.sourceWeb("src/pages/PageParametresNotifications.tsx")
        let lignes = web.components(separatedBy: "\n")
        // (texte, ligne du web) : chaque texte affiché est présent mot pour mot à sa ligne source.
        let attendus: [(String, Int)] = [
            (E.titre, 341), (E.verification, 343), (E.autorisees, 346), (E.canalDesactive, 347),
            (E.aAutoriser, 349), (E.bloquees, 350), (E.indisponible, 351), (E.nonEnregistre, 352),
        ]
        for (texte, ligne) in attendus {
            XCTAssertGreaterThanOrEqual(lignes.count, ligne)
            XCTAssertTrue(lignes[ligne - 1].contains(texte), "« \(texte) » absent de PageParametresNotifications.tsx l.\(ligne)")
        }
        // Apostrophes typographiques du web conservées.
        XCTAssertTrue(E.verification.contains("’") && E.nonEnregistre.contains("’") && E.indisponible.contains("’"))
    }

    func testLibelleDeSectionDuHubWeb() throws {
        let web = try Self.sourceWeb("src/pages/MonCompteSoignant.tsx")
        let ligne = web.components(separatedBy: "\n")[114]
        XCTAssertTrue(ligne.contains("label: '\(E.sectionHub)'"), "MonCompteSoignant.tsx l.115")
    }

    func testChoixDuMessageCommeLeWeb() {
        XCTAssertEqual(E.message(autorisation: nil, enregistrementConfirme: false), E.verification, "lecture en cours")
        XCTAssertEqual(E.message(autorisation: .accordee, enregistrementConfirme: true), E.autorisees)
        XCTAssertEqual(E.message(autorisation: .provisoire, enregistrementConfirme: true), E.autorisees)
        XCTAssertEqual(E.message(autorisation: .accordee, enregistrementConfirme: false), E.nonEnregistre)
        XCTAssertEqual(E.message(autorisation: .provisoire, enregistrementConfirme: false), E.nonEnregistre)
        XCTAssertEqual(E.message(autorisation: .nonDemandee, enregistrementConfirme: false), E.aAutoriser)
        XCTAssertEqual(E.message(autorisation: .refusee, enregistrementConfirme: false), E.bloquees)
        XCTAssertEqual(E.message(autorisation: .refusee, enregistrementConfirme: true), E.bloquees, "refus système prioritaire")
    }

    func testCanalPushConnuDesPreferences() {
        // Web l.345-347 : autorisé, canal coupé dans Jolene → message dédié (T6 fournit le canal).
        XCTAssertEqual(E.message(autorisation: .accordee, enregistrementConfirme: true, canalPush: false), E.canalDesactive)
        XCTAssertEqual(E.message(autorisation: .accordee, enregistrementConfirme: true, canalPush: true), E.autorisees)
        XCTAssertEqual(E.message(autorisation: .refusee, enregistrementConfirme: false, canalPush: false), E.bloquees)
    }

    func testTonDeLaCarte() {
        // Web l.328-332 : vert seulement quand le téléphone autorise et que l'appareil est enregistré.
        XCTAssertTrue(E.estPositif(autorisation: .accordee, enregistrementConfirme: true))
        XCTAssertFalse(E.estPositif(autorisation: .accordee, enregistrementConfirme: false))
        XCTAssertFalse(E.estPositif(autorisation: .refusee, enregistrementConfirme: true))
        XCTAssertFalse(E.estPositif(autorisation: nil, enregistrementConfirme: true))
    }
}
