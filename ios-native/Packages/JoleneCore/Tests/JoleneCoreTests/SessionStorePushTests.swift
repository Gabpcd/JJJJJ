import XCTest
@testable import JoleneCore

/// Crochets push de `SessionStore` (lot 3, T4 ; blueprint §2.5 « Déconnexion volontaire » et
/// correction 11) : `.ready` d'un nouvel epoch → `surReady` ; `signOut` → désactivation du token
/// (JWT encore valide, bornée à 2,5 s) AVANT `controller.signOut()`, une seule fois même sur un double
/// tap ; toute fin de session subie publiée (événement `.signedOut` du SDK, revalidation qui ne trouve
/// plus de session, depuis un espace prêt ou bloqué) → désinscription locale seule, sans RPC, APRÈS la
/// publication de l'état ; lancement à froid sans session → oubli d'un token laissé par la session
/// précédente ; suppression de compte (`LocalSignOut` du lot 1, T8) → désinscription locale sans RPC.
/// Aucune attente arbitraire : chaque test se synchronise sur une condition observable
/// (`pushEnCours`, `finDeSessionPush`, `evenementsAuthTraites`, journal des doubles).
@MainActor
final class SessionStorePushTests: XCTestCase {
    private let hexA = JetonsTest.hex(JetonsTest.a)

    private func store(_ monde: MondePush) -> SessionStore {
        SessionStore(controller: monde.controller, push: monde.coordinator)
    }

    // MARK: - Ouverture d'un espace

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
        XCTAssertNil(store.finDeSessionPush)
        XCTAssertEqual(monde.journal.entrees, ["auth.signOut"])
    }

    // MARK: - Déconnexion volontaire

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
        XCTAssertNil(store.finDeSessionPush, "déconnexion voulue : aucune désinscription « subie » en plus")
    }

    func testSignOutDepuisUnEspaceBloqueDesactiveAussi() async throws {
        // Profil incomplet (`.blocked`) : le JWT est valide, un token mémorisé est désactivé.
        let monde = MondePush(memorise: TokenPushMemorise(token: hexA, userId: MondePush.utilisateur.id),
                              missions: NeutralMissions())
        let store = store(monde)
        await store.start()
        guard case .blocked = store.state else { return XCTFail("attendu : espace bloqué, obtenu \(store.state)") }
        XCTAssertNil(store.pushEnCours, "aucun enregistrement hors d'un espace prêt")
        await store.signOut()
        XCTAssertEqual(monde.journal.entrees, ["desactiver:\(hexA)", "desinscrire", "oublier", "auth.signOut"])
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

    func testDoubleTapSurSeDeconnecterUneSeuleDeconnexion() async throws {
        // Écran bloqué ou profil : un second tap pendant la RPC (jusqu'à 2,5 s) n'envoie ni deuxième RPC,
        // ni deuxième désinscription, ni deuxième révocation ; `deconnexionEnCours` montre l'attente.
        let barriere = Gate()
        let monde = MondePush()
        let store = store(monde)
        await store.start()
        await store.pushEnCours?.value
        await monde.gateway.regler(barriereDesactivation: barriere)
        XCTAssertFalse(store.deconnexionEnCours)
        let premiere = Task { await store.signOut() }
        let rpc = "desactiver:\(hexA)"
        await waitUntil { monde.journal.entrees.contains(rpc) }
        XCTAssertTrue(store.deconnexionEnCours, "déconnexion en cours, visible par l'écran")
        await store.signOut() // second tap : ignoré, rend la main aussitôt
        XCTAssertTrue(store.state.isReady, "le second tap n'a rien déclenché")
        await barriere.open()
        await premiere.value
        XCTAssertFalse(store.deconnexionEnCours)
        XCTAssertEqual(store.state, .signedOut(message: nil))
        XCTAssertEqual(monde.journal.entrees(prefixe: "desactiver:"), [rpc])
        XCTAssertEqual(monde.journal.entrees.filter { $0 == "desinscrire" }.count, 1)
        XCTAssertEqual(monde.journal.entrees.filter { $0 == "auth.signOut" }.count, 1)
    }

    func testSignedOutEmisPendantUneDeconnexionVolontaireNeDesinscritPasDeuxFois() async throws {
        // Le SDK émet `.signedOut` après la révocation : l'événement est ignoré par le contrôleur
        // (aucune identité active), la désinscription locale n'est pas rejouée.
        let monde = MondePush()
        let store = store(monde)
        store.observeAuthEvents()
        await store.start()
        await store.pushEnCours?.value
        await store.signOut()
        let traites = store.evenementsAuthTraites
        monde.events.emit(.signedOut)
        await waitUntil { @MainActor in store.evenementsAuthTraites == traites + 1 }
        await store.finDeSessionPush?.value
        XCTAssertNil(store.finDeSessionPush, "aucune désinscription subie après une déconnexion voulue")
        XCTAssertEqual(monde.journal.entrees.filter { $0 == "desinscrire" }.count, 1)
        XCTAssertEqual(store.state, .signedOut(message: nil), "jamais « session expirée » après une déconnexion volontaire")
    }

    // MARK: - Déconnexion subie

    func testSignedOutSubiDuSDKDesinscritSansRPC() async throws {
        let monde = MondePush()
        let store = store(monde)
        store.observeAuthEvents()
        await store.start()
        await store.pushEnCours?.value
        monde.events.emit(.signedOut)
        await waitUntil { @MainActor in store.state == .signedOut(message: SessionController.sessionExpiredMessage) }
        await store.finDeSessionPush?.value
        XCTAssertEqual(monde.journal.entrees(prefixe: "desactiver:"), [], "JWT absent : aucune RPC")
        XCTAssertEqual(Array(monde.journal.entrees.suffix(2)), ["desinscrire", "oublier"])
        XCTAssertNil(monde.memoire.lire())
        XCTAssertEqual(monde.journal.entrees(prefixe: "auth."), [], "aucune révocation : le SDK a déjà effacé la session")
    }

    func testSignedOutSubiPublieLEtatAvantLaDesinscription() async throws {
        // La désinscription locale n'a pas besoin du JWT : l'écran de connexion s'affiche sans l'attendre
        // (jusqu'à 2,5 s), au lieu de laisser l'espace prêt affiché après une révocation.
        let barriere = Gate()
        let monde = MondePush()
        let store = store(monde)
        store.observeAuthEvents()
        await store.start()
        await store.pushEnCours?.value
        await monde.registrar.regler(barriereDesinscription: barriere)
        monde.events.emit(.signedOut)
        await waitUntil { monde.journal.entrees.contains("desinscrire") } // désinscription commencée, retenue
        XCTAssertEqual(store.state, .signedOut(message: SessionController.sessionExpiredMessage),
                       "état publié avant la fin de la désinscription")
        XCTAssertNotNil(monde.memoire.lire(), "l'oubli suit la désinscription")
        await barriere.open()
        await store.finDeSessionPush?.value
        XCTAssertNil(monde.memoire.lire())
    }

    func testRevalidationSansSessionDesinscritLocalementSansRPC() async throws {
        // Reprise après 30 minutes : la session a été effacée pendant l'arrière-plan (refresh refusé hors
        // de l'app) ; `start()` ne trouve plus de session et publie `.signedOut` sans événement du SDK.
        let restaurations = MutableAuthState(restored: MondePush.utilisateur, restoreError: nil)
        let monde = MondePush(restaurations: restaurations)
        let store = store(monde)
        await store.start()
        await store.pushEnCours?.value
        XCTAssertNotNil(monde.memoire.lire())
        await restaurations.set(restored: nil, restoreError: nil)
        await store.start()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        await store.finDeSessionPush?.value
        XCTAssertEqual(monde.journal.entrees(prefixe: "desactiver:"), [], "JWT absent : aucune RPC")
        XCTAssertEqual(Array(monde.journal.entrees.suffix(2)), ["desinscrire", "oublier"])
        XCTAssertNil(monde.memoire.lire())
        XCTAssertEqual(monde.journal.entrees(prefixe: "auth."), [])
    }

    func testRevalidationSansSessionDepuisUnEspaceBloqueDesinscrit() async throws {
        // Espace bloqué (profil incomplet) puis session effacée : `.blocked → .loading → .signedOut`.
        let restaurations = MutableAuthState(restored: MondePush.utilisateur, restoreError: nil)
        let monde = MondePush(memorise: TokenPushMemorise(token: hexA, userId: MondePush.utilisateur.id),
                              restaurations: restaurations, missions: NeutralMissions())
        let store = store(monde)
        await store.start()
        guard case .blocked = store.state else { return XCTFail("attendu : espace bloqué, obtenu \(store.state)") }
        await restaurations.set(restored: nil, restoreError: nil)
        await store.start()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        await store.finDeSessionPush?.value
        XCTAssertEqual(monde.journal.entrees, ["desinscrire", "oublier"], "désinscription locale seule, sans RPC")
    }

    func testNouvelleConnexionApresUneDeconnexionSubieReenregistre() async throws {
        // La fin subie ferme l'identité perdue, jamais l'identité suivante.
        let monde = MondePush()
        let store = store(monde)
        store.observeAuthEvents()
        await store.start()
        await store.pushEnCours?.value
        monde.events.emit(.signedOut)
        await waitUntil { @MainActor in store.state == .signedOut(message: SessionController.sessionExpiredMessage) }
        await store.signIn(email: "u-push@example.invalid", password: "fictif")
        XCTAssertTrue(store.state.isReady)
        await store.pushEnCours?.value
        let upserts = await monde.gateway.upserts
        XCTAssertEqual(upserts, [hexA, hexA], "la nouvelle identité enregistre son token")
        XCTAssertEqual(monde.memoire.lire(), TokenPushMemorise(token: hexA, userId: MondePush.utilisateur.id))
    }

    // MARK: - Lancement à froid sans session

    func testLancementAFroidSansSessionOublieLeTokenDeLaSessionPrecedente() async throws {
        // Session close hors de l'app (application tuée pendant la déconnexion, refresh refusé hors ligne) :
        // le `.signedOut` du SDK est ignoré faute d'identité ; `start()` publie `.signedOut` et le token
        // laissé dans le trousseau est oublié après la désinscription locale (aucun JWT : aucune RPC).
        let restaurations = MutableAuthState(restored: nil, restoreError: nil)
        let monde = MondePush(memorise: TokenPushMemorise(token: hexA, userId: MondePush.utilisateur.id),
                              restaurations: restaurations)
        let store = store(monde)
        store.observeAuthEvents()
        await store.start()
        monde.events.emit(.signedOut) // `.signedOut` du SDK au lancement à froid : aucune identité, ignoré
        await waitUntil { @MainActor in store.evenementsAuthTraites == 1 }
        XCTAssertEqual(store.state, .signedOut(message: nil))
        await store.finDeSessionPush?.value
        XCTAssertEqual(monde.journal.entrees, ["desinscrire", "oublier"], "une seule fois, sans RPC")
        XCTAssertNil(monde.memoire.lire())
    }

    func testLancementAFroidSansSessionNiTokenNeDesinscritRien() async throws {
        let monde = MondePush(restaurations: MutableAuthState(restored: nil, restoreError: nil))
        let store = store(monde)
        await store.start()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        await store.finDeSessionPush?.value
        let desinscriptions = await monde.registrar.desinscriptions
        XCTAssertEqual(desinscriptions, 0, "rien à nettoyer : aucun appel système inutile")
        XCTAssertEqual(monde.journal.entrees, [])
    }

    // MARK: - Suppression de compte

    func testSuppressionDeCompteDesinscritLocalementSansRPC() async throws {
        let monde = MondePush()
        let store = store(monde)
        await store.start()
        await store.pushEnCours?.value
        await store.signOutLocally()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        XCTAssertNil(store.finDeSessionPush, "fin voulue : la désinscription est faite avant la purge, une seule fois")
        XCTAssertEqual(monde.journal.entrees(prefixe: "desactiver:"), [], "compte supprimé, JWT révoqué : aucune RPC")
        let fin = Array(monde.journal.entrees.drop { $0 != "desinscrire" })
        XCTAssertEqual(fin, ["desinscrire", "oublier", "auth.signOut"],
                       "désinscription locale, puis purge locale (`signOutLocally` → `signOut` pour un port sans purge dédiée)")
    }
}
