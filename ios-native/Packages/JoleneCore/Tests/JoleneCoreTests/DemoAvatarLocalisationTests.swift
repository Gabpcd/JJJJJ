import XCTest
@testable import JoleneCore

/// Monde démo de la photo et de la position (lot 3, T10 ; blueprint §2.7) et règles pures du géocodage inverse
/// (`src/lib/geocodage.ts`). Aucun réseau : l'avatar démo est déposé en mémoire, relu par la même ligne `soignants`
/// que le profil démo ; la photo source est une ressource HEIC de synthèse.
final class DemoAvatarLocalisationTests: XCTestCase {
    private let contexte = DemoWorld.context

    // MARK: - Géocodage inverse (règles pures)

    func testAdresseDeLaRequeteCommeLeWeb() throws {
        let url = try XCTUnwrap(GeocodageInverse.url(lat: 45.7578, lng: 4.832))
        XCTAssertEqual(url.absoluteString, "https://api-adresse.data.gouv.fr/reverse/?lon=4.832&lat=45.7578",
                       "longitude d'abord, nombres comme `String(number)`")
        XCTAssertEqual(GeocodageInverse.url(lat: 45, lng: 5)?.absoluteString, "https://api-adresse.data.gouv.fr/reverse/?lon=5&lat=45")
        XCTAssertNil(GeocodageInverse.url(lat: .nan, lng: 4.8))
        XCTAssertNil(url.user)
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name), ["lon", "lat"],
                       "seules les coordonnées partent, aucun identifiant")
    }

    func testLectureDeLaReponse() {
        // Réponse au format constaté le 09/11/2026 (extrait).
        let reponse = #"{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"label":"Place Bellecour 69002 Lyon","name":"Place Bellecour","postcode":"69002","city":"Lyon"}}]}"#
        XCTAssertEqual(GeocodageInverse.adresse(depuis: Data(reponse.utf8)),
                       AdresseGeocodee(libelle: "Place Bellecour 69002 Lyon", ville: "Lyon", codePostal: "69002"))
        XCTAssertNil(GeocodageInverse.adresse(depuis: Data(#"{"features":[]}"#.utf8)), "aucune entité : introuvable")
        XCTAssertNil(GeocodageInverse.adresse(depuis: Data("<html>".utf8)))
        XCTAssertEqual(GeocodageInverse.adresse(depuis: Data(#"{"features":[{"properties":{"city":""}}]}"#.utf8)),
                       AdresseGeocodee(libelle: "", ville: nil, codePostal: nil), "`label || ''`, `city || null`")
    }

    // MARK: - Localisation démo

    func testScenariosDeLocalisationDemo() async {
        XCTAssertNil(ScenarioLocalisationDemo(arguments: ["-JOLENE_MODE", "demo"]))
        XCTAssertEqual(ScenarioLocalisationDemo(arguments: ["-JOLENE_DEMO_LOCALISATION", "refusee"]), .refusee)
        XCTAssertNil(ScenarioLocalisationDemo(arguments: ["-JOLENE_DEMO_LOCALISATION"]))
        let accordee = DemoLocalisationProfil()
        let position = await accordee.localiser(delai: 15)
        XCTAssertEqual(position, .disponible(latitude: 45.7578, longitude: 4.832))
        XCTAssertNotEqual(DemoWorld.context.profile.adresseLat, 45.7578, "position démo distincte de celle du profil fictif")
        let refusee = await DemoLocalisationProfil(scenario: .refusee).localiser(delai: 15)
        XCTAssertEqual(refusee, .refusee)
        let indisponible = await DemoLocalisationProfil(scenario: .indisponible).localiser(delai: 15)
        XCTAssertEqual(indisponible, .indisponible)
        let demandes = await accordee.demandes
        XCTAssertEqual(demandes, 1)
    }

    func testGeocodageDemo() async throws {
        let adresse = try await DemoGeocodage().adresse(lat: 45.7578, lng: 4.832)
        XCTAssertEqual(adresse?.ville, "Lyon")
        XCTAssertEqual(adresse?.libelle, "Place Bellecour 69002 Lyon")
        let echec = try await DemoGeocodage(enEchec: true).adresse(lat: 1, lng: 1)
        XCTAssertNil(echec)
        XCTAssertTrue(DemoGeocodage.enEchec(arguments: ["-JOLENE_DEMO_GEOCODAGE", "echec"]))
        XCTAssertFalse(DemoGeocodage.enEchec(arguments: []))
    }

    // MARK: - Avatar démo

    func testRessourcePhotoDemoHeicConvertible() throws {
        let source = try DemoFixtures.avatarDemo()
        XCTAssertEqual(Array(source.prefix(12).suffix(4)), Array("heic".utf8), "ressource démo au format HEIC (boîte ftyp)")
        let jpeg = try ConversionAvatar.jpeg(depuis: source)
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8])
    }

    func testAvatarDemoDeposeEnMemoireReluParLeProfilEtLuSansReseau() async throws {
        let gateways = DemoWorld.gateways()
        XCTAssertTrue(gateways.avatar is EnvoiAvatar)
        XCTAssertTrue(gateways.geocodage is DemoGeocodage)
        let jpeg = try ConversionAvatar.jpeg(depuis: try DemoFixtures.avatarDemo())
        let url = try await gateways.avatar.televerser(jpeg: jpeg, context: contexte)
        XCTAssertEqual(url.host, DemoStockageAvatar.hote, "hôte réservé, jamais résolu")
        XCTAssertTrue(url.path.hasPrefix("/storage/v1/object/sign/jolene-documents/demo-soignant/avatar-"))
        let relu = try await gateways.profil.profil(context: contexte)
        XCTAssertEqual(relu.avatarUrl, url.absoluteString, "même ligne démo que le profil")
        let image = await gateways.avatar.image(url: url)
        XCTAssertEqual(image, jpeg)
        let ailleurs = await gateways.avatar.image(url: URL(string: "https://exemple.invalid/a.jpg")!)
        XCTAssertNil(ailleurs, "aucune lecture hors du stockage démo")
        let issue = try await gateways.avatar.reconcilier(context: contexte)
        XCTAssertEqual(issue, .aucune)
    }

    func testAvatarDemoEnRefusAucuneURLLiee() async throws {
        let profil = DemoProfilGateway()
        let avatar = DemoWorld.avatar(profil: profil, scenario: .refus)
        do {
            _ = try await avatar.televerser(jpeg: Data([0xFF, 0xD8, 0xFF]), context: contexte)
            XCTFail("refus attendu")
        } catch let refus as RefusAvatar {
            XCTAssertEqual(refus.message, "Une erreur est survenue lors de l'upload. Veuillez réessayer.")
        }
        let relu = try await profil.profil(context: contexte)
        XCTAssertNil(relu.avatarUrl, "aucun `p_avatar_url` après le refus du stockage")
        XCTAssertEqual(ScenarioAvatarDemo(arguments: ["-JOLENE_DEMO_AVATAR", "refus"]), .refus)
        XCTAssertNil(ScenarioAvatarDemo(arguments: []))
    }

    func testAvatarDemoRefuseUnAutreUtilisateur() async {
        let avatar = DemoWorld.gateways().avatar
        let autre = MissionReadContext(userId: "u-x", email: nil, profile: SoignantProfile(id: "u-x", profession: "IDE"))
        do {
            _ = try await avatar.televerser(jpeg: Data([0xFF, 0xD8]), context: autre)
            XCTFail("la démo n'est jamais un repli pour un compte réel")
        } catch {
            XCTAssertEqual((error as? JoleneError)?.kind, .demoOnly)
        }
    }

    func testPositionDemoEnregistreeEtRelue() async throws {
        let gateways = DemoWorld.gateways()
        let relu = try await gateways.profil.modifier(ModificationProfil(villeRecherche: "Lyon", adresseLat: 45.7578, adresseLng: 4.832),
                                                      context: contexte)
        XCTAssertEqual(relu.adresseLat, 45.7578)
        XCTAssertEqual(relu.adresseLng, 4.832)
        XCTAssertEqual(relu.villeRecherche, "Lyon")
    }
}
