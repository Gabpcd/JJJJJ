import XCTest
@testable import JoleneCore

/// Registre de destinations de l'espace établissement (lot 5, T2a, corrigé v2 ; §4) : un cas par écran
/// poussé depuis un onglet (détail mission, candidatures, pointage, présences de mission, contrat,
/// conversation, publication). Chaque tranche remplace **sa** ligne du `switch` de l'app ; aucune ne
/// référence l'écran d'une autre. Le contrôle d'accès est fail-closed : la permission exigée vient du
/// tableau §2.7, les booléens viennent du serveur (aucune correspondance rôle → permission en Swift).
final class EtabDestinationTests: XCTestCase {
    private let toutes: [EtabDestination] = [
        .detailMission(id: "m-1"), .candidatures(missionId: "m-1"), .pointage(missionId: "m-1"),
        .presencesMission(missionId: "m-1"), .contrat(id: "c-1"), .conversation(id: "conv-1"), .publication,
    ]

    func testPermissionExigeeParDestinationCommeLeTableau27() {
        XCTAssertEqual(EtabDestination.detailMission(id: "m").permissionRequise, .lecture)
        XCTAssertEqual(EtabDestination.candidatures(missionId: "m").permissionRequise, .candidatures)
        XCTAssertEqual(EtabDestination.pointage(missionId: "m").permissionRequise, .pointage)
        XCTAssertEqual(EtabDestination.presencesMission(missionId: "m").permissionRequise, .lecture)
        XCTAssertEqual(EtabDestination.contrat(id: "c").permissionRequise, .contrats)
        XCTAssertEqual(EtabDestination.conversation(id: "c").permissionRequise, .lecture)
        XCTAssertEqual(EtabDestination.publication.permissionRequise, .missions)
    }

    func testDrapeauEtTrancheParDestination() {
        XCTAssertEqual(toutes.map(\.drapeau), [.missions, .missions, .pointage, .presences, .missions, .messages, .publier])
        XCTAssertEqual(toutes.map(\.tranche), ["T5", "T6", "T7", "T8", "T10", "T11", "T9"])
        XCTAssertEqual(toutes.map(\.identifiant),
                       ["detail-mission", "candidatures", "pointage", "presences-mission", "contrat", "conversation", "publication"])
        XCTAssertEqual(Set(toutes.map(\.identifiant)).count, toutes.count, "identifiants distincts")
    }

    func testAccesFailClosedParRoleServi() throws {
        let fichier = try DemoFixtures.loadPermissionsEtab()
        func accessibles(_ role: RoleEtab) throws -> [String] {
            let permissions = try XCTUnwrap(fichier.roles[role.brut])
            return toutes.filter { $0.accessible(avec: permissions) }.map(\.identifiant)
        }
        XCTAssertEqual(try accessibles(.proprietaire), toutes.map(\.identifiant))
        XCTAssertEqual(try accessibles(.rh), toutes.map(\.identifiant))
        XCTAssertEqual(try accessibles(.pointageOnly), ["detail-mission", "pointage", "presences-mission", "conversation"],
                       "POINTAGE_ONLY : ni candidatures, ni contrat, ni publication")
        XCTAssertEqual(try accessibles(.lectureSeule), ["detail-mission", "presences-mission", "conversation"],
                       "LECTURE_SEULE : lecture seulement, aucune action")
        XCTAssertTrue(toutes.allSatisfy { !$0.accessible(avec: .aucune) }, "aucune permission : tout refusé")
    }

    func testCheminWebDeRenvoiEncodeLesIdentifiants() {
        XCTAssertEqual(EtabDestination.detailMission(id: "m 1/2").cheminWeb, "/etablissement/missions/m%201%2F2")
        XCTAssertEqual(EtabDestination.candidatures(missionId: "m-1").cheminWeb, "/etablissement/missions/m-1")
        XCTAssertEqual(EtabDestination.pointage(missionId: "m-1").cheminWeb, "/etablissement/presences/mission/m-1")
        XCTAssertEqual(EtabDestination.presencesMission(missionId: "m-1").cheminWeb, "/etablissement/presences/mission/m-1")
        XCTAssertEqual(EtabDestination.contrat(id: "c-1").cheminWeb, "/contrat/c-1")
        XCTAssertEqual(EtabDestination.conversation(id: "conv-1").cheminWeb, "/etablissement/messagerie")
        XCTAssertEqual(EtabDestination.publication.cheminWeb, "/etablissement/missions/creer")
        for destination in toutes {
            XCTAssertEqual(destination.urlWeb.absoluteString, "https://jolene.app\(destination.cheminWeb)")
        }
    }

    func testDestinationsHashablesPourLaPileDeNavigation() {
        XCTAssertEqual(Set(toutes).count, toutes.count)
        XCTAssertEqual(EtabDestination.detailMission(id: "a"), .detailMission(id: "a"))
        XCTAssertNotEqual(EtabDestination.detailMission(id: "a"), .candidatures(missionId: "a"))
    }
}
