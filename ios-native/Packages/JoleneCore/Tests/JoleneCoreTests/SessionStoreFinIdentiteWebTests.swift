import XCTest
@testable import JoleneCore

/// Lot 3, T3b — revue fraîche B8, M1 : le navigateur intégré de l'app (`SFSafariViewController`, magasin de données
/// propre à l'app : cookies, cache, `localStorage` où le web Supabase garde sa session) ne survit à aucune fin
/// d'identité native. `SessionStore` appelle le port injecté `FinIdentiteWebPort` (coordinateur des liens de l'app :
/// fermeture du renvoi affiché, effacement du magasin hors démo) :
/// - **une fois** par fin d'identité : déconnexion volontaire (double tap compris, `.signedOut` du SDK émis pendant la
///   déconnexion compris), fin de compte (`signOutLocally`), absence de session confirmée par le contrôleur après une
///   identité (`.signedOut` du SDK, revalidation qui ne trouve plus de session), espace prêt ou bloqué ;
/// - **jamais** sur une fin transitoire (restauration hors ligne, profil illisible, connexion refusée : le SDK détient
///   encore la session), ni au lancement à froid sans session (aucune identité dans ce processus : un renvoi ouvert
///   par le lien de lancement, écart n°1, n'est pas fermé) ;
/// - avant chaque connexion par mot de passe (`signIn`) : l'identité qui s'ouvre ne trouve jamais les données web
///   d'une autre (identité close hors de l'app, session web ouverte sans identité native par l'écart n°1, identité
///   remplacée après une fin transitoire) ;
/// - indépendamment du coordinateur push (port seul, sans push).
/// Aucune attente arbitraire : chaque test se synchronise sur une condition observable.
@MainActor
final class SessionStoreFinIdentiteWebTests: XCTestCase {
    /// Double du port : compte les appels et journalise l'état publié au moment de l'appel.
    private final class EspionFinIdentiteWeb: FinIdentiteWebPort {
        private(set) var appels = 0
        private(set) var etatsAuMomentDeLAppel: [SessionState] = []
        weak var store: SessionStore?

        func identiteTerminee() {
            appels += 1
            if let store { etatsAuMomentDeLAppel.append(store.state) }
        }
    }

    private func store(_ monde: MondePush, push: Bool = true) -> (SessionStore, EspionFinIdentiteWeb) {
        let espion = EspionFinIdentiteWeb()
        let store = SessionStore(controller: monde.controller, push: push ? monde.coordinator : nil, finIdentiteWeb: espion)
        espion.store = store
        return (store, espion)
    }

    // MARK: - Fins d'identité : un appel chacune

    func testDeconnexionVolontaireAppelleLePortUneFoisApresLaRevocation() async throws {
        let monde = MondePush()
        let (store, espion) = store(monde)
        await store.start()
        XCTAssertTrue(store.state.isReady)
        XCTAssertEqual(espion.appels, 0, "ouverture de l'espace par restauration : rien à effacer")
        await store.signOut()
        XCTAssertEqual(espion.appels, 1)
        XCTAssertEqual(espion.etatsAuMomentDeLAppel, [.signedOut(message: nil)],
                       "appelé une fois l'identité close : un renvoi présenté ensuite l'est pour personne")
        XCTAssertEqual(monde.journal.entrees.filter { $0 == "auth.signOut" }.count, 1)
    }

    func testDeconnexionVolontaireSansCoordinateurPushAppelleAussiLePort() async throws {
        let monde = MondePush()
        let (store, espion) = store(monde, push: false)
        await store.start()
        await store.signOut()
        XCTAssertEqual(espion.appels, 1, "le port ne dépend pas du push")
        XCTAssertNil(store.finDeSessionPush)
    }

    func testDoubleTapSurSeDeconnecterUnSeulAppel() async throws {
        let barriere = Gate()
        let monde = MondePush()
        let (store, espion) = store(monde)
        await store.start()
        await store.pushEnCours?.value
        await monde.gateway.regler(barriereDesactivation: barriere)
        let premiere = Task { await store.signOut() }
        await waitUntil { monde.journal.entrees.contains { $0.hasPrefix("desactiver:") } }
        await store.signOut() // second tap : ignoré
        XCTAssertEqual(espion.appels, 0, "l'identité est encore ouverte pendant la désactivation du token")
        await barriere.open()
        await premiere.value
        XCTAssertEqual(espion.appels, 1)
    }

    func testSignedOutDuSDKPendantLaDeconnexionVolontaireUnSeulAppel() async throws {
        let barriere = Gate()
        let monde = MondePush()
        let (store, espion) = store(monde)
        store.observeAuthEvents()
        await store.start()
        await store.pushEnCours?.value
        await monde.gateway.regler(barriereDesactivation: barriere)
        let deconnexion = Task { await store.signOut() }
        await waitUntil { monde.journal.entrees.contains { $0.hasPrefix("desactiver:") } }
        let traites = store.evenementsAuthTraites
        monde.events.emit(.signedOut)
        await waitUntil { @MainActor in store.evenementsAuthTraites == traites + 1 }
        await barriere.open()
        await deconnexion.value
        XCTAssertEqual(espion.appels, 1, "fin voulue : le `.signedOut` du SDK ne compte pas une seconde fin")
    }

    func testFinDeCompteAppelleLePortUneFois() async throws {
        let monde = MondePush()
        let (store, espion) = store(monde)
        await store.start()
        await store.signOutLocally()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        XCTAssertEqual(espion.appels, 1)
        XCTAssertEqual(espion.etatsAuMomentDeLAppel, [.signedOut(message: nil)])
    }

    func testSignedOutSubiDuSDKAppelleLePortUneFois() async throws {
        let monde = MondePush()
        let (store, espion) = store(monde)
        store.observeAuthEvents()
        await store.start()
        monde.events.emit(.signedOut)
        await waitUntil { @MainActor in store.state == .signedOut(message: SessionController.sessionExpiredMessage) }
        XCTAssertEqual(espion.appels, 1)
        XCTAssertEqual(espion.etatsAuMomentDeLAppel, [.signedOut(message: SessionController.sessionExpiredMessage)])
        // Le même `.signedOut` revu (retour de `start()`, boucle d'événements) n'est pas une seconde fin.
        await store.refresh()
        monde.events.emit(.signedOut)
        await waitUntil { @MainActor in store.evenementsAuthTraites == 2 }
        XCTAssertEqual(espion.appels, 1)
    }

    func testRevalidationSansSessionApresUnEspacePretAppelleLePort() async throws {
        let restaurations = MutableAuthState(restored: MondePush.utilisateur, restoreError: nil)
        let monde = MondePush(restaurations: restaurations)
        let (store, espion) = store(monde, push: false)
        await store.start()
        await restaurations.set(restored: nil, restoreError: nil)
        await store.start() // reprise après 30 minutes : session effacée hors de l'app
        XCTAssertEqual(store.state, .signedOut(message: nil))
        XCTAssertEqual(espion.appels, 1)
    }

    func testRevalidationSansSessionApresUnEspaceBloqueAppelleLePort() async throws {
        let restaurations = MutableAuthState(restored: MondePush.utilisateur, restoreError: nil)
        let monde = MondePush(restaurations: restaurations, missions: NeutralMissions())
        let (store, espion) = store(monde)
        await store.start()
        guard case .blocked = store.state else { return XCTFail("attendu : espace bloqué, obtenu \(store.state)") }
        await restaurations.set(restored: nil, restoreError: nil)
        await store.start()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        XCTAssertEqual(espion.appels, 1, "un compte bloqué peut avoir ouvert un renvoi web (écart n°1)")
    }

    // MARK: - Fins transitoires : jamais

    func testRestaurationTransitoireApresUnEspaceNAppelleJamaisLePort() async throws {
        let restaurations = MutableAuthState(restored: MondePush.utilisateur, restoreError: nil)
        let monde = MondePush(restaurations: restaurations, missions: NeutralMissions())
        let (store, espion) = store(monde)
        await store.start()
        guard case .blocked = store.state else { return XCTFail("attendu : espace bloqué, obtenu \(store.state)") }
        await restaurations.set(restored: MondePush.utilisateur, restoreError: JoleneError(.network, "hors ligne"))
        await store.start()
        XCTAssertEqual(store.state, .signedOut(message: SessionController.restoreFailedMessage))
        XCTAssertEqual(espion.appels, 0, "le SDK détient encore la session : rien n'est effacé ni fermé")
        // Réseau revenu : « Réessayer » rouvre la même identité, toujours sans appel.
        await restaurations.set(restored: MondePush.utilisateur, restoreError: nil)
        await store.start()
        XCTAssertEqual(espion.appels, 0)
    }

    func testLancementAFroidHorsLigneOuProfilIllisibleNAppelleJamaisLePort() async throws {
        let horsLigne = MondePush(restaurations: MutableAuthState(restored: nil, restoreError: JoleneError(.network, "hors ligne")))
        let (store1, espion1) = store(horsLigne)
        await store1.start()
        XCTAssertEqual(store1.state, .signedOut(message: SessionController.restoreFailedMessage))
        XCTAssertEqual(espion1.appels, 0)

        let illisible = MondePush(missions: MissionsHorsLigne())
        let (store2, espion2) = store(illisible)
        store2.observeAuthEvents()
        await store2.start()
        XCTAssertEqual(store2.state, .signedOut(message: SessionController.profileLoadFailedMessage))
        XCTAssertEqual(espion2.appels, 0)
    }

    func testLancementAFroidSansSessionNAppellePasLePort() async throws {
        // Aucune identité dans ce processus : un renvoi présenté par le lien de lancement (écart n°1) reste affiché.
        let monde = MondePush(restaurations: MutableAuthState(restored: nil, restoreError: nil))
        let (store, espion) = store(monde)
        store.observeAuthEvents()
        await store.start()
        monde.events.emit(.signedOut)
        await waitUntil { @MainActor in store.evenementsAuthTraites == 1 }
        XCTAssertEqual(store.state, .signedOut(message: nil))
        XCTAssertEqual(espion.appels, 0)
    }

    // MARK: - Connexion par mot de passe

    func testChaqueConnexionParMotDePasseEstPrecedeeDUnAppel() async throws {
        // Connexion refusée : le port est appelé avant la tentative (aucune identité ouverte n'est touchée : l'écran de
        // connexion est affiché), et le refus n'en ajoute aucun.
        let espionRefus = EspionFinIdentiteWeb()
        let gateways = Gateways(auth: PushAuth(restored: nil, journal: JournalPush()), role: NeutralRole(), missions: PushMissions())
        let storeRefus = SessionStore(controller: SessionController(gateways: gateways), finIdentiteWeb: espionRefus)
        await storeRefus.start()
        await storeRefus.signIn(email: "u-push@example.invalid", password: "fictif")
        guard case .signedOut(let message?) = storeRefus.state, !message.isEmpty else {
            return XCTFail("attendu : connexion refusée, obtenu \(storeRefus.state)")
        }
        XCTAssertEqual(espionRefus.appels, 1)

        // Après une déconnexion : un appel pour la fin, un pour la connexion suivante ; l'ouverture n'en ajoute aucun.
        let monde = MondePush()
        let (store, espion) = store(monde)
        await store.start()
        await store.signOut()
        XCTAssertEqual(espion.appels, 1)
        await store.signIn(email: "u-push@example.invalid", password: "fictif")
        XCTAssertTrue(store.state.isReady)
        XCTAssertEqual(espion.appels, 2)
        XCTAssertEqual(espion.etatsAuMomentDeLAppel.last, .signedOut(message: nil),
                       "appelé avant la connexion : l'identité suivante ne trouve aucune donnée web")
    }

    func testConnexionApresUneFinTransitoireRemplaceLIdentiteSansDonneesWeb() async throws {
        // Profil illisible (fin transitoire, aucun appel), puis connexion par mot de passe depuis l'écran affiché :
        // l'identité suivante peut être une autre ; les données web de la précédente sont effacées avant.
        let restaurations = MutableAuthState(restored: MondePush.utilisateur, restoreError: nil)
        let monde = MondePush(restaurations: restaurations, missions: NeutralMissions())
        let (store, espion) = store(monde)
        await store.start()
        await restaurations.set(restored: MondePush.utilisateur, restoreError: JoleneError(.network, "hors ligne"))
        await store.start()
        XCTAssertEqual(espion.appels, 0)
        await store.signIn(email: "u-push@example.invalid", password: "fictif")
        XCTAssertEqual(espion.appels, 1)
    }
}
