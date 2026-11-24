import XCTest
@testable import JoleneCore

/// Table de liens du lot 4 (blueprint `docs/mobile-swift/LOT4_PLAN.md` §3 T1) : chaque écran secondaire a sa route
/// `.secondaire(_:)` ; tant que sa tranche ne l'a pas livré, la destination est la page web canonique (query et
/// fragment conservés), sauf le swipe et le score qui gardent l'écran natif d'avant L4-T1 (Explorer, hub du compte).
final class LinksRouterLot4Tests: XCTestCase {
    private func lien(_ chemin: String) throws -> DestinationLien {
        try XCTUnwrap(DestinationLien(url: try XCTUnwrap(URL(string: "https://jolene.app" + chemin))), chemin)
    }

    func testRoutesDesEcransSecondaires() throws {
        let cas: [(String, EcranSecondaire)] = [
            ("/soignant/swipe-missions", .swipe),
            ("/soignant/recherche-missions?vue=swipe", .swipe),
            ("/soignant/parametres/recherches-sauvegardees", .recherches),
            ("/soignant/disponibilites", .disponibilites),
            ("/soignant/parrainage", .parrainage),
            ("/soignant/litiges", .litiges(onglet: nil, litigeId: nil)),
            ("/soignant/litiges?tab=reclamations", .litiges(onglet: .reclamations, litigeId: nil)),
            ("/soignant/litiges?tab=inconnu&litige=l1", .litiges(onglet: nil, litigeId: "l1")),
            ("/soignant/litiges#l%202", .litiges(onglet: nil, litigeId: "l 2")),               // pushs LITIGE_* (pushNative.ts)
            ("/soignant/litiges?litige=l3#l4", .litiges(onglet: nil, litigeId: "l3")),          // `?litige=` d'abord (web l.53-54)
            ("/soignant/reclamations", .litiges(onglet: .reclamations, litigeId: nil)),        // alias `Navigate` l.406
            ("/soignant/messagerie", .messagerie(conversationId: nil)),
            ("/soignant/messagerie?conv=c1", .messagerie(conversationId: "c1")),
            ("/soignant/evaluations", .evaluations),
            ("/soignant/score", .score),
            ("/soignant/fiabilite", .score),
            ("/soignant/fiabilite-legacy/", .score),
            ("/soignant/pool-urgence", .poolUrgence),
            ("/soignant/exclusions", .exclusions),
        ]
        for (chemin, ecran) in cas {
            let d = try lien(chemin)
            XCTAssertEqual(d.route, .secondaire(ecran), chemin)
            XCTAssertEqual(DestinationLien.ecranNatifLivre(d.route), SecondairesLot4Tests.livre(ecran),
                           "\(chemin) : seuls les écrans des tranches livrées")
            if SecondairesLot4Tests.livre(ecran) {
                XCTAssertEqual(d.destination, .secondaire(ecran), chemin)
                continue
            }
            switch ecran {
            case .swipe: XCTAssertEqual(d.destination, .explorer, chemin)
            case .score: XCTAssertEqual(d.destination, .monCompte, chemin)
            default: XCTAssertEqual(d.destination, .safari(d.canonique), chemin)
            }
        }
    }

    func testRoutesVoisinesInchangees() throws {
        XCTAssertEqual(try lien("/soignant/recherche-missions").route, .explorer)
        XCTAssertEqual(try lien("/soignant/recherche-missions?vue=liste").route, .explorer)
        XCTAssertEqual(try lien("/soignant/mes-gains?tab=factures").route, .revenus(section: .factures))
        // Bulletins : route de Revenus gardée ; T10 redirige sa destination vers `.secondaire(.bulletins)`.
        XCTAssertEqual(try lien("/soignant/mes-gains?tab=bulletins").route, .revenus(section: .bulletins))
        XCTAssertEqual(try lien("/soignant/bulletins-paie").route, .revenus(section: .bulletins))
        XCTAssertEqual(try lien("/soignant/mon-compte").route, .monCompte)
        XCTAssertEqual(try lien("/soignant/missions/serie/s1").route, .serieDetail(id: "s1"), "série : aiguillée par T1c")
    }

    func testRenvoiWebCanoniqueEtIntentions() throws {
        let litige = try lien("/soignant/litiges?tab=litiges#l9")
        XCTAssertEqual(litige.destination.externalURL?.absoluteString, "https://jolene.app/soignant/litiges?tab=litiges#l9")
        XCTAssertEqual(DeepLinkIntent(litige), .renvoiWeb(litige))
        XCTAssertEqual(CibleNotification(litige), .web(.safari(litige.canonique)))
        let swipe = try lien("/soignant/swipe-missions")
        XCTAssertEqual(DeepLinkIntent(swipe), .espace(swipe))
        XCTAssertEqual(CibleNotification(swipe), .explorer, "repli natif : Explorer, comme avant L4-T1")
        XCTAssertEqual(CibleNotification(try lien("/soignant/score")), .monCompte)
    }

    func testDescriptionMasqueLesIdentifiants() throws {
        let cas: [(String, String)] = [
            ("/soignant/litiges?tab=reclamations&litige=SECRET1", "secondaire(litiges, reclamations, id masqué)"),
            ("/soignant/messagerie?conv=SECRET2", "secondaire(messagerie, id masqué)"),
            ("/soignant/parrainage", "secondaire(parrainage)"),
            ("/soignant/pool-urgence", "secondaire(pool_urgence)"),
        ]
        for (chemin, attendu) in cas {
            let d = try lien(chemin)
            XCTAssertEqual(String(describing: d.route), attendu, chemin)
            XCTAssertFalse(String(describing: d).contains("SECRET"), chemin)
        }
        XCTAssertEqual(String(describing: JoleneRoute.secondaire(.serie(id: "SECRET4"))), "secondaire(serie, id masqué)")
        XCTAssertEqual(LienMasque.gabarit(chemin: "/soignant/pool-urgence"), "/soignant/pool-urgence")
    }
}
