import XCTest
@testable import JoleneCore

/// Point de la carte en lecture seule du détail mission (lot 1, T4a) : coordonnées de
/// l'établissement lues via `fn_etablissements_safe`, jamais recalculées ni géocodées côté app.
final class CarteMissionTests: XCTestCase {
    typealias S = MissionsTestSupport

    private func avecEtablissement(_ change: (inout EtablissementSummary) -> Void) -> Mission {
        var mission = S.mission()
        if var etablissement = mission.etablissement {
            change(&etablissement)
            mission.etablissement = etablissement
        }
        return mission
    }

    func testPointDepuisLesCoordonneesServeur() throws {
        let point = try XCTUnwrap(CarteMission.point(pour: S.mission()))
        XCTAssertEqual(point.latitude, 48.8566)
        XCTAssertEqual(point.longitude, 2.3522)
        XCTAssertEqual(point.titre, "Établissement de test")
        XCTAssertEqual(point.adresse, "75011 Paris")
        XCTAssertEqual(point.legende, "Établissement de test · 75011 Paris")
        XCTAssertEqual(point.accessibilityLabel, "Carte de la mission : Établissement de test, 75011 Paris")
    }

    func testAucunPointSansEtablissementNiCoordonnees() {
        var orpheline = S.mission(); orpheline.etablissement = nil
        XCTAssertNil(CarteMission.point(pour: orpheline))
        XCTAssertNil(CarteMission.point(pour: avecEtablissement { $0.adresseLat = nil }))
        XCTAssertNil(CarteMission.point(pour: avecEtablissement { $0.adresseLng = nil }))
    }

    func testCoordonneesNullesOuInvalidesSontAbsentes() {
        // Parité : carte visible de tous = `CarteMissionsExploration.tsx` l.54-56 (`lat == null || lng == null`,
        // 0 y est ACCEPTÉ). Écart natif assumé et documenté (`CarteMission.point(pour:)`) : une coordonnée
        // exactement nulle est traitée comme absente — le point (0, 0) du golfe de Guinée signale un
        // géocodage manquant, jamais un établissement français. (`DetailMissionSoignant.tsx` l.1111 ne
        // gouverne que les liens Plans / Maps / Waze du soignant assigné, pas une carte.)
        XCTAssertNil(CarteMission.point(pour: avecEtablissement { $0.adresseLat = 0 }))
        XCTAssertNil(CarteMission.point(pour: avecEtablissement { $0.adresseLng = 0 }))
        XCTAssertNil(CarteMission.point(pour: avecEtablissement { $0.adresseLat = 91 }))
        XCTAssertNil(CarteMission.point(pour: avecEtablissement { $0.adresseLng = -181 }))
        XCTAssertNil(CarteMission.point(pour: avecEtablissement { $0.adresseLat = .nan }))
        XCTAssertNil(CarteMission.point(pour: avecEtablissement { $0.adresseLng = .infinity }))
        XCTAssertNotNil(CarteMission.point(pour: avecEtablissement { $0.adresseLat = -90; $0.adresseLng = 180 }))
    }

    func testLegendeSansAdresseNiNom() throws {
        let sansAdresse = try XCTUnwrap(CarteMission.point(pour: avecEtablissement { $0.adresseVille = nil; $0.adresseCodePostal = nil }))
        XCTAssertNil(sansAdresse.adresse)
        XCTAssertEqual(sansAdresse.legende, "Établissement de test")
        XCTAssertEqual(sansAdresse.accessibilityLabel, "Carte de la mission : Établissement de test")
        let villeSeule = try XCTUnwrap(CarteMission.point(pour: avecEtablissement { $0.adresseCodePostal = nil }))
        XCTAssertEqual(villeSeule.adresse, "Paris")
        let sansNom = try XCTUnwrap(CarteMission.point(pour: avecEtablissement { $0.nom = "" }))
        XCTAssertEqual(sansNom.titre, "Établissement", "repli d'affichage du détail (MissionDetailScreen)")
    }

    func testEtendueDeLaCarte() {
        XCTAssertEqual(CarteMission.etendueMetres, 1_500)
    }

    func testCleIdentiteSuitLesSeulesCoordonnees() {
        // `Map(initialPosition:)` n'est lu qu'au premier rendu : la carte est recréée (`.id`) quand la
        // relecture du détail déplace l'établissement, jamais pour un simple changement de libellé.
        let point = PointCarte(latitude: 48.8566, longitude: 2.3522, titre: "A", adresse: nil)
        XCTAssertEqual(CarteMission.cleIdentite(point), "48.8566,2.3522")
        var renomme = point; renomme.titre = "B"; renomme.adresse = "75011 Paris"
        XCTAssertEqual(CarteMission.cleIdentite(renomme), CarteMission.cleIdentite(point))
        var latitude = point; latitude.latitude = 48.867
        XCTAssertNotEqual(CarteMission.cleIdentite(latitude), CarteMission.cleIdentite(point))
        var longitude = point; longitude.longitude = 2.363
        XCTAssertNotEqual(CarteMission.cleIdentite(longitude), CarteMission.cleIdentite(point))
    }

    func testMissionsDemoToutesLocalisees() async throws {
        let missions = try await DemoMissionsGateway().listMissions(context: DemoWorld.context,
                                                                    filters: MissionBusiness.defaultFilters(profile: DemoWorld.context.profile))
        XCTAssertEqual(missions.count, 30)
        XCTAssertTrue(missions.allSatisfy { CarteMission.point(pour: $0) != nil }, "chaque détail démo affiche sa carte")
    }
}
