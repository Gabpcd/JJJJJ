import XCTest
@testable import JoleneCore

/// Liens de l'espace établissement (lot 5, T2b ; `docs/mobile-swift/LOT5_PLAN.md` §3 T2, D29) : table
/// `LinkRouter.etablissementDestination(link:)` et présentation (`EtabRoute.presentation`).
///
/// Ce que ces tests prouvent (niveau 1) :
/// - les 47 routes établissement de la matrice de parité (`PARITE_ETABLISSEMENT.md`, elle-même confrontée à
///   `src/App.tsx` par `tests/node/contrats-etablissement-ios.node.mjs`) : natif ou renvoi web, exactement la cible
///   de la matrice ;
/// - alias `Navigate` (`dashboard`, `assurance`, `contrat-plateforme`), query portée telle que reçue (`?statut=`,
///   `?periode=`, `?tab=`, `?conv=`), segments encodés, barre oblique finale ;
/// - un écran empilé non livré (T5-T11) est un renvoi web de l'URL canonique, query et fragment conservés ; un onglet
///   (écran provisoire compris) est présenté dans la coquille ;
/// - description masquée (PRINCIPES §7).
final class EtabRouteTests: XCTestCase {
    private func route(_ lien: String, file: StaticString = #filePath, line: UInt = #line) throws -> EtabRoute {
        try XCTUnwrap(LinkRouter.etablissementDestination(link: lien)?.route, lien, file: file, line: line)
    }

    // MARK: - Matrice de parité

    /// Lignes `| \`/chemin\` (l.N) | … | statut | cible | …` de la matrice ; segments dynamiques instanciés.
    private func lignesDeLaMatrice() throws -> [(chemin: String, natif: Bool)] {
        let doc = try SourceWebLot5.lire("docs/mobile-swift/PARITE_ETABLISSEMENT.md")
        return doc.split(separator: "\n").map(String.init).filter { $0.hasPrefix("| `/") }.compactMap { ligne in
            let colonnes = ligne.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard colonnes.count > 4, let fin = colonnes[1].dropFirst().firstIndex(of: "`") else { return nil }
            let chemin = String(colonnes[1].dropFirst()[..<fin])
            return (chemin, colonnes[4].hasPrefix("natif"))
        }
    }

    func testLes47RoutesDeLaMatriceSuiventLeurCible() throws {
        let lignes = try lignesDeLaMatrice()
        XCTAssertEqual(lignes.count, 47, "une ligne de matrice par route établissement de App.tsx")
        XCTAssertEqual(lignes.filter(\.natif).count, 13, "13 routes natives au lot 5 (T0)")
        for (chemin, natif) in lignes {
            let lien = chemin.replacingOccurrences(of: ":id", with: "m-1").replacingOccurrences(of: ":token", with: "jeton")
            let obtenue = try route(lien)
            XCTAssertEqual(obtenue.isNative, natif, "\(chemin) : \(obtenue)")
            if !natif {
                XCTAssertEqual(obtenue, .safari(URL(string: "https://jolene.app\(lien)")!), chemin)
            }
        }
    }

    // MARK: - Table

    func testRoutesNativesEtAlias() throws {
        let cas: [(String, EtabRoute)] = [
            ("/etablissement/tableau-de-bord", .accueil),
            ("/etablissement/dashboard", .accueil),
            ("https://jolene.app/etablissement/tableau-de-bord/", .accueil),
            ("/etablissement/missions", .missions(statut: nil, periode: nil)),
            ("/etablissement/missions/creer", .publierMission),
            ("/etablissement/missions/m%201", .missionDetail(id: "m 1")),
            ("/etablissement/presences", .presences(onglet: nil)),
            ("/etablissement/presences/mission/m-2", .presencesMission(id: "m-2")),
            ("/etablissement/contrats", .contrats(statut: nil)),
            ("/etablissement/assurance", .contrats(statut: nil)),
            ("/etablissement/contrat-plateforme?statut=SIGNE", .contrats(statut: nil)),
            ("/contrat/c-1", .contrat(id: "c-1")),
            ("/etablissement/messagerie", .messagerie(conversation: nil)),
            ("/etablissement/mon-compte", .monCompte),
        ]
        for (lien, attendue) in cas {
            XCTAssertEqual(try route(lien), attendue, lien)
        }
    }

    func testQueryPorteeTelleQueRecue() throws {
        XCTAssertEqual(try route("/etablissement/missions?statut=OUVERTE"), .missions(statut: "OUVERTE", periode: nil))
        XCTAssertEqual(try route("/etablissement/missions?statut=EN_COURS&periode=mois"),
                       .missions(statut: "EN_COURS", periode: "mois"))
        XCTAssertEqual(try route("/etablissement/presences?tab=alertes"), .presences(onglet: "alertes"))
        XCTAssertEqual(try route("/etablissement/contrats?statut=EN_ATTENTE_SIGNATURES"),
                       .contrats(statut: "EN_ATTENTE_SIGNATURES"))
        XCTAssertEqual(try route("/etablissement/messagerie?conv=conv-9"), .messagerie(conversation: "conv-9"))
        let cible = try XCTUnwrap(try route("/etablissement/missions?statut=OUVERTE").cible)
        XCTAssertEqual(cible, CibleEtablissement(onglet: .missions, statut: "OUVERTE"))
        XCTAssertEqual(try route("/etablissement/presences?tab=alertes").cible,
                       CibleEtablissement(onglet: .presences, ongletPresences: "alertes"))
    }

    func testRenvoisWebHorsDuPerimetreNatif() throws {
        for lien in ["/etablissement/missions/m-1/modifier", "/contrat/c-1/certificat", "/etab/invitation/jeton",
                     "/inscription/etablissement", "/etablissement/reclamations", "/etablissement/facturation/f-1",
                     "/soignant/missions", "/soignant/tableau-de-bord", "/admin/utilisateurs", "/etablissement"] {
            guard case .safari(let url) = try route(lien) else { return XCTFail(lien) }
            XCTAssertEqual(url.absoluteString, "https://jolene.app\(lien)")
        }
        // Barre oblique finale ignorée : la liste des missions, pas un détail sans identifiant.
        XCTAssertEqual(try route("/etablissement/missions/"), .missions(statut: nil, periode: nil))
        XCTAssertNil(LinkRouter.etablissementDestination(link: "https://exemple.invalid/etablissement/missions"),
                     "hôte hors de JoleneLink.trustedWebHosts : pas un lien Jolene")
    }

    // MARK: - Présentation

    func testOngletsPresentesEcransEmpilesNonLivresEnRenvoiWeb() throws {
        let canonique = URL(string: "https://jolene.app/etablissement/missions/m-1?source=push#candidatures")!
        XCTAssertEqual(EtabRoute.missionDetail(id: "m-1").presentation(canonique: canonique),
                       .naviguer(CibleEtablissement(onglet: .missions, destination: .detailMission(id: "m-1"))),
                       "T5 livrée : le détail de mission est empilé sur l'onglet Missions")
        let onglets: [(EtabRoute, CibleEtablissement.Onglet)] = [
            (.accueil, .accueil), (.missions(statut: nil, periode: nil), .missions), (.presences(onglet: nil), .presences),
            (.messagerie(conversation: nil), .messages), (.monCompte, .compte),
        ]
        for (route, onglet) in onglets {
            guard case let .naviguer(cible) = route.presentation(canonique: canonique) else { return XCTFail("\(route)") }
            XCTAssertEqual(cible.onglet, onglet)
            XCTAssertNil(cible.destination)
        }
        XCTAssertEqual(EtabRoute.presencesMission(id: "m").presentation(canonique: canonique),
                       .naviguer(CibleEtablissement(onglet: .presences, destination: .presencesMission(missionId: "m"))),
                       "T8 livrée : les présences de la mission sont empilées sur l'onglet Présences")
        for route: EtabRoute in [.publierMission, .contrat(id: "c"), .contrats(statut: nil), .messagerie(conversation: "conv")] {
            XCTAssertEqual(route.presentation(canonique: canonique), .renvoiWeb(canonique), "\(route)")
        }
    }

    func testCiblesDesEcransEmpiles() {
        XCTAssertEqual(EtabRoute.missionDetail(id: "m").cible, CibleEtablissement(onglet: .missions, destination: .detailMission(id: "m")))
        XCTAssertEqual(EtabRoute.publierMission.cible, CibleEtablissement(onglet: .missions, destination: .publication))
        XCTAssertEqual(EtabRoute.presencesMission(id: "m").cible,
                       CibleEtablissement(onglet: .presences, destination: .presencesMission(missionId: "m")))
        XCTAssertEqual(EtabRoute.contrat(id: "c").cible, CibleEtablissement(onglet: .missions, destination: .contrat(id: "c")),
                       "/contrat/{id} : le contrat de l'espace établissement (T10), jamais l'écran soignant")
        XCTAssertEqual(EtabRoute.messagerie(conversation: "k").cible,
                       CibleEtablissement(onglet: .messages, destination: .conversation(id: "k")))
        XCTAssertNil(EtabRoute.contrats(statut: nil).cible, "point d'ancrage de la liste choisi par T10")
        // Aucune destination livrée avant sa tranche (une ligne par tranche dans `EtabDestination.ecranLivre`) : T5 a
        // livré le détail de mission.
        XCTAssertTrue(EtabDestination.detailMission(id: "m").ecranLivre, "T5")
        XCTAssertTrue(EtabDestination.candidatures(missionId: "m").ecranLivre, "T6")
        XCTAssertTrue(EtabDestination.pointage(missionId: "m").ecranLivre, "T7")
        XCTAssertTrue(EtabDestination.presencesMission(missionId: "m").ecranLivre, "T8")
        for destination: EtabDestination in [.publication, .contrat(id: "c"), .conversation(id: "k")] {
            XCTAssertFalse(destination.ecranLivre, destination.tranche)
        }
    }

    func testDescriptionMasquee() throws {
        let routes: [EtabRoute] = [try route("/etablissement/missions/secret-1?x=y"), try route("/contrat/secret-2"),
                                   try route("/etablissement/messagerie?conv=secret-3"), try route("/etab/invitation/secret-4"),
                                   try route("/etablissement/missions?statut=secret-5")]
        for route in routes {
            XCTAssertFalse(route.description.contains("secret"), route.description)
            XCTAssertTrue(route.description.hasPrefix("EtabRoute."))
        }
        XCTAssertEqual(EtabRoute.messagerie(conversation: "conv-9").libelleDebug, "etab messagerie(conv-9)")
    }
}
