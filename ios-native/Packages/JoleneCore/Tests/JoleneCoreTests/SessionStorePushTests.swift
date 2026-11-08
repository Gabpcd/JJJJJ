import XCTest
@testable import JoleneCore

/// Crochets push de `SessionStore` (lot 3, T4 ; blueprint §2.5 « Déconnexion volontaire » et
/// correction 11) : `.ready` d'un nouvel epoch → `surReady` ; `signOut` → désactivation du token
/// (JWT encore valide, bornée à 2,5 s) AVANT `controller.signOut()` ; `.signedOut` subi du SDK et
/// suppression de compte (`LocalSignOut` du lot 1, T8) → désinscription locale seule, sans RPC.
@MainActor
final class SessionStorePushTests: XCTestCase {
    private let hexA = JetonsTest.hex(JetonsTest.a)

    private func store(_ monde: MondePush) -> SessionStore {
        SessionStore(controller: monde.controller, push: monde.coordinator)
    }

    func testReadyDUnNouvelEpochEnregistreLeToken() async throws {
        let monde = MondePush()
        let store = store(monde)
        await store.start()
        XCTAssertTrue(store.state.isReady)
        await store.pushEnCours?.value
        XCTAssertEqual(monde.journal.entrees(prefixe: "upsert:"), ["upsert:\(hexA):\(MondePush.utilisateur.id)"])
    }

    func testRevalidationDuMemeEpochNeRelancePasLEnregistrement() async throws {
        let monde = MondePush()
        let store = store(monde)
        await store.start()
        await store.pushEnCours?.value
        await store.start() // reprise après 30 minutes : même identité, même epoch
        await store.pushEnCours?.value
        let enregistrements = await monde.registrar.enregistrements
        XCTAssertEqual(enregistrements, 1, "seul un nouvel epoch déclenche surReady ; le premier plan relève de surActive")
    }

    func testSansCoordinateurLeStoreResteCeluiDuLot1() async throws {
        let monde = MondePush()
        let store = SessionStore(controller: monde.controller)
        await store.start()
        XCTAssertTrue(store.state.isReady)
        XCTAssertNil(store.pushEnCours)
        await store.signOut()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        XCTAssertEqual(monde.journal.entrees, ["auth.signOut"])
    }

    func testSignOutDesactiveLeTokenAvantLaRevocation() async throws {
        let monde = MondePush()
        let store = store(monde)
        await store.start()
        await store.pushEnCours?.value
        await store.signOut()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        let fin = Array(monde.journal.entrees.drop { !$0.hasPrefix("desactiver:") })
        XCTAssertEqual(fin, ["desactiver:\(hexA)", "desinscrire", "oublier", "auth.signOut"],
                       "RPC (JWT requis) puis désinscription et oubli, puis seulement la révocation")
    }

    func testSignOutDepuisUnEspaceBloqueDesactiveAussi() async throws {
        // Profil incomplet (`.blocked`) : le JWT est valide, un token mémorisé est désactivé.
        let journal = JournalPush()
        var gateways = Gateways(auth: PushAuth(restored: MondePush.utilisateur, journal: journal, events: nil),
                                role: NeutralRole(), missions: NeutralMissions())
        let gateway = SpyPushGateway(journal: journal)
        gateways.push = gateway
        let controller = SessionController(gateways: gateways)
        let memoire = JournalPushTokenStore(journal: journal, initial: TokenPushMemorise(token: hexA, userId: MondePush.utilisateur.id))
        let coordinator = PushCoordinator(controller: controller, permission: FakePushPermission(.accordee),
                                          registrar: FakePushRegistrar(journal: journal), memoire: memoire)
        let store = SessionStore(controller: controller, push: coordinator)
        await store.start()
        guard case .blocked = store.state else { return XCTFail("attendu : espace bloqué, obtenu \(store.state)") }
        XCTAssertNil(store.pushEnCours, "aucun enregistrement hors d'un espace prêt")
        await store.signOut()
        XCTAssertEqual(journal.entrees, ["desactiver:\(hexA)", "desinscrire", "oublier", "auth.signOut"])
    }

    func testSignOutAvecRPCMuetteNAttendQueLeDelai() async throws {
        let monde = MondePush(delaiDesactivation: 0.05)
        await monde.gateway.ralentirDesactivation(secondes: 10)
        let store = store(monde)
        await store.start()
        await store.pushEnCours?.value
        let debut = Date()
        await store.signOut()
        XCTAssertLessThan(Date().timeIntervalSince(debut), 2, "hors ligne, la déconnexion n'attend que le délai de 2,5 s")
        XCTAssertEqual(store.state, .signedOut(message: nil))
        XCTAssertEqual(Array(monde.journal.entrees.suffix(2)), ["oublier", "auth.signOut"])
    }

    func testSignedOutSubiDuSDKDesinscritSansRPC() async throws {
        let monde = MondePush()
        let store = store(monde)
        store.observeAuthEvents()
        await store.start()
        await store.pushEnCours?.value
        monde.events.emit(.signedOut)
        await waitUntil { @MainActor in store.state == .signedOut(message: SessionController.sessionExpiredMessage) }
        await waitUntil { monde.journal.entrees.contains("oublier") }
        XCTAssertEqual(monde.journal.entrees(prefixe: "desactiver:"), [], "JWT absent : aucune RPC")
        XCTAssertTrue(monde.journal.entrees.contains("desinscrire"))
        XCTAssertNil(monde.memoire.lire())
        XCTAssertEqual(monde.journal.entrees(prefixe: "auth."), [], "aucune révocation : le SDK a déjà effacé la session")
    }

    func testSignedOutEmisPendantUneDeconnexionVolontaireNeDesinscritPasDeuxFois() async throws {
        // Le SDK émet `.signedOut` pendant la révocation : l'événement est ignoré par le contrôleur
        // (aucune identité active), la désinscription locale n'est pas rejouée.
        let monde = MondePush()
        let store = store(monde)
        store.observeAuthEvents()
        await store.start()
        await store.pushEnCours?.value
        await store.signOut()
        monde.events.emit(.signedOut)
        // Laisse l'observateur traiter l'événement.
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(monde.journal.entrees.filter { $0 == "desinscrire" }.count, 1)
        XCTAssertEqual(store.state, .signedOut(message: nil), "jamais « session expirée » après une déconnexion volontaire")
    }

    func testSuppressionDeCompteDesinscritLocalementSansRPC() async throws {
        let monde = MondePush()
        let store = store(monde)
        await store.start()
        await store.pushEnCours?.value
        await store.signOutLocally()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        XCTAssertEqual(monde.journal.entrees(prefixe: "desactiver:"), [], "compte supprimé, JWT révoqué : aucune RPC")
        let fin = Array(monde.journal.entrees.drop { $0 != "desinscrire" })
        XCTAssertEqual(fin, ["desinscrire", "oublier", "auth.signOut"],
                       "désinscription locale, puis purge locale (`signOutLocally` → `signOut` pour un port sans purge dédiée)")
    }
}
