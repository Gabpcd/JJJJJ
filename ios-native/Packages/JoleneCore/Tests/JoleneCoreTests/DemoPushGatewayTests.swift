import XCTest
@testable import JoleneCore

/// Push du monde démo (blueprint §2.7) : `DemoPushPermission` (aucune feuille système),
/// `DemoPushRegistrar` (token fixe de 32 octets), `DemoPushGateway` (acteur, compte les appels,
/// mêmes refus que `fn_upsert_token_push` / `fn_desactiver_mon_token_push`). Aucun réseau.
final class DemoPushGatewayTests: XCTestCase {
    private let contexte = DemoWorld.context

    func testCablerLot3PoseLaGatewayPushDemo() {
        XCTAssertTrue(DemoWorld.gateways().push is DemoPushGateway, "T4 câble le push dans le monde démo")
        XCTAssertFalse(DemoWorld.gateways().unwiredPorts.contains("push"))
    }

    func testTokenDemoFixeDe32Octets() async throws {
        let registrar = DemoPushRegistrar()
        let premier = try await registrar.enregistrer()
        let second = try await registrar.enregistrer()
        XCTAssertEqual(premier, second, "token fixe")
        XCTAssertEqual(premier.count, 32)
        XCTAssertEqual(PushCoordinator.hex(premier).count, 64)
        XCTAssertEqual(premier, DemoPushRegistrar.tokenDemo)
        let compte = await registrar.enregistrements
        XCTAssertEqual(compte, 2)
        await registrar.desinscrire()
        let desinscriptions = await registrar.desinscriptions
        XCTAssertEqual(desinscriptions, 1)
    }

    func testPermissionDemoSansFeuilleSysteme() async throws {
        let parDefaut = DemoPushPermission()
        let etatInitial = await parDefaut.etat()
        XCTAssertEqual(etatInitial, .nonDemandee, "appareil neuf par défaut")
        let accordee = try await parDefaut.demander()
        XCTAssertTrue(accordee)
        let apres = await parDefaut.etat()
        XCTAssertEqual(apres, .accordee)

        let refusee = DemoPushPermission(etat: .refusee)
        let reponse = try await refusee.demander()
        XCTAssertFalse(reponse, "un refus système n'est jamais renversé par une nouvelle demande")
        let toujours = await refusee.etat()
        XCTAssertEqual(toujours, .refusee)
    }

    func testEnregistrementEtDesactivationDemo() async throws {
        let gateway = DemoPushGateway()
        let token = PushCoordinator.hex(DemoPushRegistrar.tokenDemo)
        try await gateway.enregistrer(token: token, context: contexte)
        var actifs = await gateway.tokensActifs
        XCTAssertEqual(actifs, [token])
        let issue = try await gateway.desactiver(token: token)
        XCTAssertEqual(issue, .desactive(tokensDesactives: 1))
        actifs = await gateway.tokensActifs
        XCTAssertEqual(actifs, [])
        let inconnu = try await gateway.desactiver(token: String(repeating: "c", count: 64))
        XCTAssertEqual(inconnu, .desactive(tokensDesactives: 0), "token absent : 0 ligne, comme la fonction serveur")
        let journal = await gateway.journal
        XCTAssertEqual(journal, ["enregistrer", "desactiver", "desactiver"])
    }

    func testRefusDemoCommeLeServeur() async {
        let gateway = DemoPushGateway()
        do {
            try await gateway.enregistrer(token: String(repeating: "a", count: 64),
                                          context: MissionReadContext(userId: "autre", email: nil,
                                                                      profile: SoignantProfile(id: "autre", profession: "IDE")))
            XCTFail("attendu : refus démo")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        } catch { XCTFail("\(error)") }
        do {
            try await gateway.enregistrer(token: "court", context: contexte)
            XCTFail("attendu : token invalide")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract, "22023 « Token push invalide » → refus de contrat")
        } catch { XCTFail("\(error)") }
        let refus = try? await gateway.desactiver(token: "court")
        XCTAssertEqual(refus, .nonDesactive, "`{success:false, error:'Token push invalide'}`")
        let actifs = await gateway.tokensActifs
        XCTAssertEqual(actifs, [])
    }
}
