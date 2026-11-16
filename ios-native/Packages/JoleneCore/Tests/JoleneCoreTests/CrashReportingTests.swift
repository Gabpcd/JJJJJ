import XCTest
@testable import JoleneCore

/// Lot 3, T15 (D21, blueprint `LOT3_PLAN.md` §2.7 et §3 T15) — démarrage de Sentry Cocoa :
/// - **jamais en démo**, ni sans DSN (clé `JoleneSentryDSN` de l'Info.plist vide, absente ou non résolue), ni pour un
///   environnement refusé par la garde (`JoleneEnvironment.validate`) : la fabrique de l'adaptateur Sentry n'est alors
///   jamais appelée, aucun service n'est créé ; en démo, la sentinelle réseau « 0 requête » des XCUITest démo
///   (`network-sentinel`, `DemoConsultationTests` et suivants) reste donc inchangée ;
/// - environnement = mode de l'app, release `<CFBundleIdentifier>@<CFBundleShortVersionString>+<CFBundleVersion>` lue dans
///   le bundle (jamais codée en dur), réglages sans PII ;
/// - identifiant utilisateur posé sur `.ready`, conservé par une revalidation transitoire (l'espace reste prêt), retiré
///   (`nil`) hors d'un espace prêt : fin d'identité, espace bloqué, fin transitoire, avant toute ouverture d'identité
///   (revue B8 n°1, M2 : jamais l'identifiant d'un compte pour le compte suivant) ;
/// - crash de test (`-JOLENE_SENTRY_CRASH_TEST`, DEBUG) seulement si Sentry a démarré.
/// Gardes statiques de la cible app (Sentry importé par `CrashReporting.swift` seul, démarrage avant le conteneur, démo
/// sans rapport de crash, DSN jamais versionné) : lecture des sources, comme `FusionLocalisationLot2Tests`.
@MainActor
final class CrashReportingTests: XCTestCase {
    // MARK: - Doubles

    /// Double du port : journalise les appels (verrou : le port est `Sendable`, appelé depuis le main actor).
    final class EspionCrash: CrashReportingPort, @unchecked Sendable {
        enum Appel: Equatable { case demarrer(JoleneMode, String), utilisateur(String?) }
        private let verrou = NSLock()
        private var _appels: [Appel] = []
        var appels: [Appel] { verrou.lock(); defer { verrou.unlock() }; return _appels }
        var utilisateurs: [String?] {
            appels.compactMap { if case let .utilisateur(id) = $0 { return .some(id) } else { return nil } }
        }
        func demarrer(environnement: JoleneMode, release: String) { noter(.demarrer(environnement, release)) }
        func utilisateur(id: String?) { noter(.utilisateur(id)) }
        private func noter(_ appel: Appel) { verrou.lock(); _appels.append(appel); verrou.unlock() }
    }

    /// DSN fictif bien formé (clé publique et projet inventés, hôte réservé `.invalid`) : jamais un DSN réel.
    private static let dsnFictif = "https://0123456789abcdef0123456789abcdef@o000000.ingest.example.invalid/0000000"

    private static func info(dsn: Any? = dsnFictif, version: String? = "2.0.0", build: String? = "25",
                             bundle: String? = "app.jolene") -> [String: Any] {
        var info: [String: Any] = [:]
        info["JoleneSentryDSN"] = dsn
        info["CFBundleShortVersionString"] = version
        info["CFBundleVersion"] = build
        info["CFBundleIdentifier"] = bundle
        return info
    }

    private static let staging = JoleneEnvironment(mode: .staging,
                                                   supabaseURL: URL(string: "https://mejpriaetwgtcstbgfid.supabase.co"),
                                                   publishableKey: "sb_publishable_fictive")
    private static let production = JoleneEnvironment(mode: .production,
                                                      supabaseURL: URL(string: "https://flripxtsyegjshnhzjkz.supabase.co"),
                                                      publishableKey: "sb_publishable_fictive")
    private static let demo = JoleneEnvironment(mode: .demo, supabaseURL: nil, publishableKey: nil)

    // MARK: - Démarrage : jamais en démo, jamais sans DSN

    func testDemoJamaisDemarreMemeAvecUnDSN() {
        XCTAssertNil(ConfigurationCrash.auLancement(environnement: Self.demo, info: Self.info()))
        // Mode démo lu comme au lancement (`-JOLENE_MODE demo`, DEBUG), Info.plist portant un DSN.
        let lu = JoleneEnvironment.load(arguments: ["Jolene", "-JOLENE_MODE", "demo"], environment: [:],
                                        info: Self.info().merging(["JoleneEnvironment": "staging"]) { $1 })
        XCTAssertEqual(lu.mode, .demo)
        XCTAssertNil(ConfigurationCrash.auLancement(environnement: lu, info: Self.info()))
    }

    func testDSNVideAbsentOuNonResoluJamaisDemarre() {
        // Valeur des xcconfig versionnés (vide), blancs, réglage non résolu.
        for dsn in ["", "   ", "\n", "$(JOLENE_SENTRY_DSN)"] {
            XCTAssertNil(ConfigurationCrash.auLancement(environnement: Self.staging, info: Self.info(dsn: dsn)),
                         "DSN « \(dsn) » : Sentry désactivé")
            XCTAssertNil(ConfigurationCrash.auLancement(environnement: Self.production, info: Self.info(dsn: dsn)))
        }
        // Clé absente de l'Info.plist, ou d'un autre type.
        XCTAssertNil(ConfigurationCrash.auLancement(environnement: Self.production, info: Self.info(dsn: nil)))
        XCTAssertNil(ConfigurationCrash.auLancement(environnement: Self.production, info: Self.info(dsn: 42)))
    }

    func testDSNMalFormeJamaisDemarre() {
        for dsn in ["http://0123@o1.ingest.example.invalid/1", // non chiffré
                    "https://o1.ingest.example.invalid/1", // sans clé publique
                    "https://0123@o1.ingest.example.invalid", // sans projet
                    "https://0123@/1", "pas un dsn", "sentry://0123@o1.ingest.example.invalid/1"] {
            XCTAssertNil(ConfigurationCrash.auLancement(environnement: Self.staging, info: Self.info(dsn: dsn)), dsn)
        }
    }

    func testDSNAvecMotDePasseJamaisDemarre() {
        // Revue B8 n°1, m6 : un DSN Sentry porte une clé publique seule. Une partie `:<secret>` (ancien format à clé
        // secrète, ou valeur collée par erreur) n'est jamais embarquée dans l'app : Sentry reste désactivé.
        for dsn in ["https://0123456789abcdef:fedcba9876543210@o1.ingest.example.invalid/1",
                    "https://0123456789abcdef:@o1.ingest.example.invalid/1"] {
            XCTAssertNil(ConfigurationCrash.dsnValide(dsn), dsn)
            XCTAssertNil(ConfigurationCrash.auLancement(environnement: Self.production, info: Self.info(dsn: dsn)), dsn)
        }
        XCTAssertEqual(ConfigurationCrash.dsnValide(Self.dsnFictif), Self.dsnFictif, "clé publique seule : accepté")
    }

    func testEnvironnementRefuseOuModeInconnuJamaisDemarre() {
        var sansCle = Self.staging
        sansCle.publishableKey = ""
        XCTAssertNil(ConfigurationCrash.auLancement(environnement: sansCle, info: Self.info()),
                     "environnement refusé (écran bloquant) : aucun service réel")
        var cleSecrete = Self.production
        cleSecrete.publishableKey = "sb_secret_fictive"
        XCTAssertNil(ConfigurationCrash.auLancement(environnement: cleSecrete, info: Self.info()))
        let inconnu = JoleneEnvironment.load(arguments: [], environment: [:], info: ["JoleneEnvironment": "stagin"])
        XCTAssertNotNil(inconnu.unknownModeRaw)
        XCTAssertNil(ConfigurationCrash.auLancement(environnement: inconnu, info: Self.info()))
    }

    func testFabriqueJamaisAppeleeSansConfiguration() {
        var fabriques = 0
        let port = ConfigurationCrash.demarrer(nil) { _ in fabriques += 1; return EspionCrash() }
        XCTAssertNil(port)
        XCTAssertEqual(fabriques, 0, "démo ou DSN vide : aucun adaptateur Sentry n'est construit")
    }

    // MARK: - Démarrage : environnement, release, réglages

    func testStagingAvecDSNDemarreUneFoisAvecEnvironnementEtRelease() throws {
        let configuration = try XCTUnwrap(ConfigurationCrash.auLancement(environnement: Self.staging,
                                                                          info: Self.info(dsn: "  \(Self.dsnFictif)\n")))
        XCTAssertEqual(configuration.environnement, .staging)
        XCTAssertEqual(configuration.release, "app.jolene@2.0.0+25")
        XCTAssertEqual(configuration.dsn, Self.dsnFictif, "DSN débarrassé des blancs")
        let espion = EspionCrash()
        var fabriques: [ConfigurationCrash] = []
        let port = ConfigurationCrash.demarrer(configuration) { fabriques.append($0); return espion }
        XCTAssertTrue((port as? EspionCrash) === espion, "le port rendu est celui de la fabrique")
        XCTAssertEqual(fabriques, [configuration])
        XCTAssertEqual(espion.appels, [.demarrer(.staging, "app.jolene@2.0.0+25")])
    }

    func testProductionEnvironnementProduction() throws {
        let configuration = try XCTUnwrap(ConfigurationCrash.auLancement(environnement: Self.production, info: Self.info()))
        XCTAssertEqual(configuration.environnement, .production)
        XCTAssertEqual(configuration.environnement.rawValue, "production", "environnement Sentry = mode de l'app")
    }

    func testReleaseConstruiteDepuisLesClesDuBundle() throws {
        XCTAssertEqual(ConfigurationCrash.nomDeRelease(info: Self.info(version: "2.1.0", build: "31")), "app.jolene@2.1.0+31")
        XCTAssertEqual(ConfigurationCrash.nomDeRelease(info: Self.info()), "app.jolene@2.0.0+25")
        for info in [Self.info(version: nil), Self.info(build: ""), Self.info(bundle: nil),
                     Self.info(version: "$(MARKETING_VERSION)"), Self.info(build: "$(CURRENT_PROJECT_VERSION)")] {
            XCTAssertNil(ConfigurationCrash.nomDeRelease(info: info))
            XCTAssertNil(ConfigurationCrash.auLancement(environnement: Self.staging, info: info),
                         "release illisible : pas de crash non attribuable à un build")
        }
    }

    func testReglagesSansPIIConformesAuBlueprint() {
        let r = ConfigurationCrash.reglages
        XCTAssertFalse(r.sendDefaultPii)
        XCTAssertFalse(r.attachScreenshot)
        XCTAssertFalse(r.attachViewHierarchy)
        XCTAssertFalse(r.enableNetworkBreadcrumbs)
        XCTAssertFalse(r.enableCaptureFailedRequests)
        XCTAssertEqual(r.tracesSampleRate, 0)
        XCTAssertTrue(r.enableAutoSessionTracking, "le lot 4 mesure le taux de sessions sans crash")
        XCTAssertTrue(r.enableAppHangTracking)
        // Au-delà du blueprint (SENTRY_IOS.md) : aucune instrumentation de URLSession, aucun en-tête de trace envoyé aux
        // hôtes appelés (Supabase, api-adresse.data.gouv.fr, Stripe), aucune relecture de session.
        XCTAssertFalse(r.enableNetworkTracking)
        XCTAssertEqual(r.tracePropagationTargets, [])
        XCTAssertEqual(r.sessionReplaySessionSampleRate, 0)
        XCTAssertEqual(r.sessionReplayOnErrorSampleRate, 0)
    }

    func testDSNJamaisRestitueParUneDescription() throws {
        let configuration = try XCTUnwrap(ConfigurationCrash.auLancement(environnement: Self.staging, info: Self.info()))
        var dump = ""
        Swift.dump(configuration, to: &dump)
        for rendu in [String(describing: configuration), String(reflecting: configuration), "\(configuration)", dump] {
            XCTAssertFalse(rendu.contains("0123456789abcdef"), "le DSN fuit : \(rendu)")
            XCTAssertFalse(rendu.contains("ingest"), "le DSN fuit : \(rendu)")
            XCTAssertTrue(rendu.contains("staging"), rendu)
        }
    }

    // MARK: - Crash de test (DEBUG)

    func testCrashDeTestSeulementSiSentryADemarre() throws {
        let arguments = ["Jolene", ConfigurationCrash.argumentCrashTest]
        XCTAssertEqual(ConfigurationCrash.argumentCrashTest, "-JOLENE_SENTRY_CRASH_TEST")
        XCTAssertFalse(ConfigurationCrash.crashTestDemande(arguments: arguments, configuration: nil),
                       "démo ou DSN vide : l'argument est ignoré, l'app ne plante pas")
        let configuration = try XCTUnwrap(ConfigurationCrash.auLancement(environnement: Self.staging, info: Self.info()))
        XCTAssertTrue(ConfigurationCrash.crashTestDemande(arguments: arguments, configuration: configuration))
        XCTAssertFalse(ConfigurationCrash.crashTestDemande(arguments: ["Jolene"], configuration: configuration))
    }

    // MARK: - Identifiant utilisateur (SessionStore)

    private func store(_ monde: MondePush) -> (SessionStore, EspionCrash) {
        let espion = EspionCrash()
        return (SessionStore(controller: monde.controller, crashReporting: espion), espion)
    }

    func testIdentifiantPoseSurReadyUneSeuleFoisParIdentite() async {
        let monde = MondePush()
        let (store, espion) = store(monde)
        XCTAssertEqual(espion.appels, [])
        await store.start()
        XCTAssertTrue(store.state.isReady)
        XCTAssertEqual(espion.appels, [.utilisateur("u-push")], "identifiant seul, aucune autre donnée")
        await store.start() // revalidation (reprise après 30 minutes) : même identité
        XCTAssertEqual(espion.appels, [.utilisateur("u-push")])
    }

    func testDeconnexionVolontaireRetireLIdentifiant() async {
        let monde = MondePush()
        let (store, espion) = store(monde)
        await store.start()
        await store.signOut()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        XCTAssertEqual(espion.utilisateurs, ["u-push", nil])
        // Reconnexion : l'identifiant est reposé.
        await store.signIn(email: "u-push@example.invalid", password: "fictif")
        XCTAssertTrue(store.state.isReady)
        XCTAssertEqual(espion.utilisateurs, ["u-push", nil, "u-push"])
    }

    func testFinDeCompteRetireLIdentifiant() async {
        let (store, espion) = store(MondePush())
        await store.start()
        await store.signOutLocally()
        XCTAssertEqual(espion.utilisateurs, ["u-push", nil])
    }

    func testSessionEffaceeParLeSDKRetireLIdentifiant() async {
        let monde = MondePush()
        let (store, espion) = store(monde)
        store.observeAuthEvents()
        await store.start()
        monde.events.emit(.signedOut)
        await waitUntil { @MainActor in store.state == .signedOut(message: SessionController.sessionExpiredMessage) }
        XCTAssertEqual(espion.utilisateurs, ["u-push", nil])
    }

    func testFinTransitoireConserveLIdentifiant() async {
        // Revalidation hors ligne d'un espace prêt : l'espace reste prêt (PRINCIPES §5, erreur transitoire tolérée) ;
        // l'identifiant n'est ni retiré ni reposé.
        let restaurations = MutableAuthState(restored: MondePush.utilisateur, restoreError: nil)
        let (store, espion) = store(MondePush(restaurations: restaurations))
        await store.start()
        await restaurations.set(restored: MondePush.utilisateur, restoreError: JoleneError(.network, "hors ligne"))
        await store.start()
        XCTAssertTrue(store.state.isReady)
        XCTAssertEqual(espion.utilisateurs, ["u-push"], "le SDK détient encore la session : identité inchangée")
        // Lancement à froid hors ligne, profil illisible : `.signedOut` transitoire, aucun identifiant posé ni retiré.
        let horsLigne = MondePush(restaurations: MutableAuthState(restored: nil, restoreError: JoleneError(.network, "hors ligne")))
        let (froid, espionFroid) = self.store(horsLigne)
        await froid.start()
        XCTAssertEqual(froid.state, .signedOut(message: SessionController.restoreFailedMessage))
        let (illisible, espionIllisible) = self.store(MondePush(missions: MissionsHorsLigne()))
        await illisible.start()
        XCTAssertEqual(illisible.state, .signedOut(message: SessionController.profileLoadFailedMessage))
        XCTAssertEqual(espionFroid.appels + espionIllisible.appels, [])
    }

    func testEspaceBloqueNePosePasDIdentifiant() async {
        let (store, espion) = store(MondePush(missions: NeutralMissions()))
        await store.start()
        guard case .blocked = store.state else { return XCTFail("attendu : espace bloqué, obtenu \(store.state)") }
        XCTAssertEqual(espion.appels, [], "identifiant posé sur `.ready` seulement (blueprint §3 T15)")
    }

    // MARK: - Identifiant utilisateur : changement d'identité (revue B8 n°1, M2)

    /// Monde à deux comptes : A (profil soignant, espace prêt) et B (sans profil, espace bloqué). Restauration et
    /// connexion servent le compte courant de `session` ; `reseau` rend les profils illisibles (fin transitoire).
    private struct MondeDeuxComptes {
        static let a = AuthenticatedUser(id: "u-a", email: "a@example.invalid",
                                         emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000), appMetadataRole: "SOIGNANT")
        static let b = AuthenticatedUser(id: "u-b", email: "b@example.invalid",
                                         emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000), appMetadataRole: "SOIGNANT")
        let session = MutableAuthState(restored: MondeDeuxComptes.a, restoreError: nil)
        let reseau = ReseauProfils()
        let events = AuthEventEmitter()
        let temoin = TemoinConnexion()
        let controller: SessionController

        init() {
            controller = SessionController(gateways: Gateways(auth: AuthDeuxComptes(session: session, events: events, temoin: temoin),
                                                              role: NeutralRole(), missions: MissionsDeuxComptes(reseau: reseau)))
        }
    }

    private actor ReseauProfils {
        private(set) var horsLigne = false
        func regler(horsLigne: Bool) { self.horsLigne = horsLigne }
    }

    /// Revue B8 de la vague 5, m2 : identifiants remis au rapport de crash, relevés au moment même de l'appel
    /// `AuthPort.signIn`. À cet instant, la connexion n'a encore publié aucun état (`.loading` ne touche pas
    /// l'identifiant) : seul le retrait du début de `SessionStore.signIn` peut y avoir ajouté `nil`. Le `.blocked` ou le
    /// `.signedOut` publié après le refus, eux, viennent trop tard pour ce relevé.
    private final class TemoinConnexion: @unchecked Sendable {
        private let verrou = NSLock()
        private var espion: EspionCrash?
        private var _releves: [[String?]] = []
        var releves: [[String?]] { verrou.lock(); defer { verrou.unlock() }; return _releves }
        func observer(_ espion: EspionCrash) { verrou.lock(); self.espion = espion; verrou.unlock() }
        func noterAppel() {
            verrou.lock()
            defer { verrou.unlock() }
            if let espion { _releves.append(espion.utilisateurs) }
        }
    }

    private struct AuthDeuxComptes: AuthPort {
        let session: MutableAuthState
        let events: AuthEventEmitter
        let temoin: TemoinConnexion
        func restoreSession() async throws -> AuthenticatedUser? {
            if let erreur = await session.restoreError { throw erreur }
            return await session.restored
        }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser {
            temoin.noterAppel()
            guard let compte = await session.restored else { throw JoleneError(.invalidCredentials, "refusé") }
            return compte
        }
        func signOut() async throws {}
        func authEvents() -> AsyncStream<AuthEvent> { events.stream() }
    }

    private struct MissionsDeuxComptes: MissionsPort {
        let reseau: ReseauProfils
        func profile(userId: String) async throws -> SoignantProfile? {
            if await reseau.horsLigne { throw JoleneError(.network, "hors ligne") }
            return userId == MondeDeuxComptes.a.id ? SoignantProfile(id: userId, profession: "IDE") : nil
        }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    private func storeDeuxComptes() async -> (SessionStore, EspionCrash, MondeDeuxComptes) {
        let monde = MondeDeuxComptes()
        let espion = EspionCrash()
        let store = SessionStore(controller: monde.controller, crashReporting: espion)
        monde.temoin.observer(espion)
        store.observeAuthEvents()
        await store.start()
        XCTAssertTrue(store.state.isReady, "A ouvre son espace")
        XCTAssertEqual(espion.utilisateurs, ["u-a"])
        return (store, espion, monde)
    }

    func testLienDeConfirmationDUnAutreCompteVersUnEspaceBloqueRetireLIdentifiant() async {
        // Espace de A prêt ; un lien de confirmation de B est échangé (`ouvrirIdentiteInscription`) : B sans profil.
        let (store, espion, monde) = await storeDeuxComptes()
        await monde.session.set(restored: MondeDeuxComptes.b, restoreError: nil)
        await store.ouvrirIdentiteInscription()
        guard case .blocked = store.state else { return XCTFail("attendu : espace bloqué de B, obtenu \(store.state)") }
        XCTAssertEqual(espion.utilisateurs, ["u-a", nil], "aucun crash de B attribué à A")
        // Même compte relu par l'inscription : retiré avant la relecture, reposé au `.ready`.
        await monde.session.set(restored: MondeDeuxComptes.a, restoreError: nil)
        await store.ouvrirIdentiteInscription()
        XCTAssertTrue(store.state.isReady)
        XCTAssertEqual(espion.utilisateurs, ["u-a", nil, "u-a"])
        await store.ouvrirIdentiteInscription()
        XCTAssertEqual(espion.utilisateurs, ["u-a", nil, "u-a", nil, "u-a"])
    }

    func testSessionDUnAutreCompteVersUnEspaceBloqueRetireLIdentifiant() async {
        // Espace de A prêt ; le SDK annonce la session de B (`.session(B)`, identité différente) : B sans profil.
        let (store, espion, monde) = await storeDeuxComptes()
        await monde.session.set(restored: MondeDeuxComptes.b, restoreError: nil)
        monde.events.emit(.session(userId: MondeDeuxComptes.b.id))
        await waitUntil { @MainActor in store.evenementsAuthTraites == 1 }
        guard case .blocked = store.state else { return XCTFail("attendu : espace bloqué de B, obtenu \(store.state)") }
        XCTAssertEqual(espion.utilisateurs, ["u-a", nil])
    }

    func testFinTransitoirePuisConnexionDUnAutreCompteBloqueRetireLIdentifiant() async {
        // Espace de A prêt ; la session de B arrive alors que le profil est illisible : fin transitoire (le SDK détient la
        // session de B, plus celle de A). Puis connexion de B depuis l'écran affiché : espace bloqué.
        let (store, espion, monde) = await storeDeuxComptes()
        await monde.session.set(restored: MondeDeuxComptes.b, restoreError: nil)
        await monde.reseau.regler(horsLigne: true)
        monde.events.emit(.session(userId: MondeDeuxComptes.b.id))
        await waitUntil { @MainActor in store.evenementsAuthTraites == 1 }
        XCTAssertEqual(store.state, .signedOut(message: SessionController.profileLoadFailedMessage))
        XCTAssertEqual(espion.utilisateurs, ["u-a", nil], "l'espace de A est fermé : son identifiant ne suit pas B")
        await monde.reseau.regler(horsLigne: false)
        await store.signIn(email: "b@example.invalid", password: "fictif")
        guard case .blocked = store.state else { return XCTFail("attendu : espace bloqué de B, obtenu \(store.state)") }
        XCTAssertEqual(espion.utilisateurs, ["u-a", nil])
    }

    func testConnexionRefuseeRetireLIdentifiantJusquAuReadySuivant() async {
        // Une connexion refusée laisse l'app sans identifiant, reposé au `.ready` suivant seulement. Le `nil` final vient
        // aussi du `.signedOut` du refus : seul le relevé au moment de l'appel (`TemoinConnexion`) prouve que `signIn` l'a
        // retiré AVANT la tentative, comme il vide le navigateur intégré (T3b ; revue B8 de la vague 5, m2).
        let (store, espion, monde) = await storeDeuxComptes()
        await monde.session.set(restored: nil, restoreError: nil)
        await store.signIn(email: "inconnu@example.invalid", password: "fictif")
        guard case .signedOut(let message?) = store.state, !message.isEmpty else {
            return XCTFail("attendu : connexion refusée, obtenu \(store.state)")
        }
        XCTAssertEqual(monde.temoin.releves, [["u-a", nil]], "identifiant de A retiré avant l'appel d'authentification")
        XCTAssertEqual(espion.utilisateurs, ["u-a", nil])
        await monde.session.set(restored: MondeDeuxComptes.a, restoreError: nil)
        await store.signIn(email: "a@example.invalid", password: "fictif")
        XCTAssertTrue(store.state.isReady)
        XCTAssertEqual(monde.temoin.releves, [["u-a", nil], ["u-a", nil]], "rien de reposé avant le `.ready`")
        XCTAssertEqual(espion.utilisateurs, ["u-a", nil, "u-a"])
    }

    func testConnexionDepuisUnEspacePretRetireLIdentifiantAvantLAppel() async {
        // Revue B8 de la vague 5, m2 : depuis un espace prêt, ni `.blocked` ni `.signedOut` n'ont encore été publiés au
        // moment de l'appel ; le `nil` relevé ne peut venir que du retrait du début de `SessionStore.signIn`.
        let (store, espion, monde) = await storeDeuxComptes()
        // Même compte : retiré avant l'appel, reposé au `.ready` (sans le retrait, rien ne bougerait).
        await store.signIn(email: "a@example.invalid", password: "fictif")
        XCTAssertTrue(store.state.isReady)
        XCTAssertEqual(monde.temoin.releves, [["u-a", nil]], "identifiant de A retiré avant l'appel d'authentification")
        XCTAssertEqual(espion.utilisateurs, ["u-a", nil, "u-a"])
        // Autre compte, espace bloqué : l'identifiant de A n'est déjà plus là quand B s'authentifie.
        await monde.session.set(restored: MondeDeuxComptes.b, restoreError: nil)
        await store.signIn(email: "b@example.invalid", password: "fictif")
        guard case .blocked = store.state else { return XCTFail("attendu : espace bloqué de B, obtenu \(store.state)") }
        XCTAssertEqual(monde.temoin.releves, [["u-a", nil], ["u-a", nil, "u-a", nil]], "aucun crash de B attribué à A")
        XCTAssertEqual(espion.utilisateurs, ["u-a", nil, "u-a", nil])
    }

    // MARK: - Gardes statiques de la cible app

    /// Racine `ios-native/` (le fichier est sous `ios-native/Packages/JoleneCore/Tests/JoleneCoreTests/`).
    private static var racine: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    private static func lire(_ relatif: String) throws -> String {
        try String(contentsOf: racine.appendingPathComponent(relatif), encoding: .utf8)
    }

    private static func sourcesSwift(_ relatif: String) throws -> [(chemin: String, contenu: String)] {
        let dossier = racine.appendingPathComponent(relatif, isDirectory: true)
        guard let parcours = FileManager.default.enumerator(at: dossier, includingPropertiesForKeys: nil) else {
            throw JoleneError(.contract, "\(relatif) introuvable sous \(racine.path)")
        }
        var fichiers: [(String, String)] = []
        for case let url as URL in parcours where url.pathExtension == "swift" && !url.path.contains("/.build/") {
            fichiers.append((url.path.replacingOccurrences(of: racine.path + "/", with: ""),
                             try String(contentsOf: url, encoding: .utf8)))
        }
        return fichiers.sorted { $0.0 < $1.0 }
    }

    func testSentryImporteParLaCibleAppSeulementDansCrashReporting() throws {
        let app = try Self.sourcesSwift("Jolene")
        let paquets = try Self.sourcesSwift("Packages")
        XCTAssertGreaterThan(app.count, 20)
        XCTAssertGreaterThan(paquets.count, 100)
        let importe = { (fichier: (chemin: String, contenu: String)) in
            fichier.contenu.components(separatedBy: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "import Sentry" }
        }
        XCTAssertEqual(app.filter(importe).map(\.chemin), ["Jolene/Composition/CrashReporting.swift"])
        XCTAssertEqual(paquets.filter(importe).map(\.chemin), [], "JoleneCore, JoleneSupabase et JoleneDesign ignorent Sentry")
    }

    func testDemarrageAvantLeConteneurEtJamaisPourLaDemo() throws {
        let app = try Self.lire("Jolene/JoleneApp.swift")
        let demarrage = try XCTUnwrap(app.range(of: "CrashReporting.demarrerAuLancement()"), "démarrage dans JoleneApp")
        let conteneur = try XCTUnwrap(app.range(of: "AppContainer(crashReporting:"), "conteneur construit avec le port")
        XCTAssertLessThan(demarrage.lowerBound, conteneur.lowerBound, "Sentry démarre avant le conteneur")

        let container = try Self.lire("Jolene/Composition/AppContainer.swift")
        let debutDemo = try XCTUnwrap(container.range(of: "case .demo:\n"))
        let debutReel = try XCTUnwrap(container.range(of: "case .staging, .production:\n",
                                                      range: debutDemo.upperBound..<container.endIndex))
        let brancheDemo = container[debutDemo.upperBound..<debutReel.lowerBound]
        XCTAssertTrue(brancheDemo.contains("SessionStore(controller:"), "branche démo localisée")
        XCTAssertFalse(brancheDemo.contains("crashReporting"), "la session démo ne reçoit jamais le rapport de crash")
        let brancheReelle = container[debutReel.upperBound...]
        XCTAssertTrue(brancheReelle.contains("crashReporting: crashReporting)"),
                      "staging et production : la session pose l'identifiant utilisateur")

        // Même lecture de l'environnement que le conteneur (surcharges DEBUG comprises).
        let reporting = try Self.lire("Jolene/Composition/CrashReporting.swift")
        XCTAssertTrue(reporting.contains("AppContainer.environnementDeLancement("))
        XCTAssertTrue(container.contains("Self.environnementDeLancement("))
    }

    func testReglagesAppliquesEtCrashDeTestDEBUGSeulement() throws {
        let reporting = try Self.lire("Jolene/Composition/CrashReporting.swift")
        for option in ["sendDefaultPii", "attachScreenshot", "attachViewHierarchy", "enableNetworkBreadcrumbs",
                       "enableCaptureFailedRequests", "enableNetworkTracking", "tracePropagationTargets",
                       "enableAutoSessionTracking", "enableAppHangTracking"] {
            XCTAssertTrue(reporting.contains("options.\(option) = reglages.\(option)\n"), "réglage \(option) non appliqué")
        }
        for ligne in ["options.tracesSampleRate = NSNumber(value: reglages.tracesSampleRate)",
                      "options.sessionReplay.sessionSampleRate = reglages.sessionReplaySessionSampleRate",
                      "options.sessionReplay.onErrorSampleRate = reglages.sessionReplayOnErrorSampleRate",
                      "options.environment = environnement.rawValue", "options.releaseName = release",
                      "options.beforeSend = ", "options.beforeBreadcrumb = "] {
            XCTAssertTrue(reporting.contains(ligne), "« \(ligne) » absent de CrashReporting.swift")
        }
        let crash = try XCTUnwrap(reporting.range(of: "SentrySDK.crash()"))
        XCTAssertEqual(reporting.components(separatedBy: "SentrySDK.crash()").count, 2, "un seul appel")
        let avant = reporting[..<crash.lowerBound]
        let ouverture = try XCTUnwrap(avant.range(of: "#if DEBUG", options: .backwards))
        XCTAssertNil(avant[ouverture.upperBound...].range(of: "#endif"), "SentrySDK.crash() hors d'un bloc #if DEBUG")
        XCTAssertTrue(reporting.contains("ConfigurationCrash.crashTestDemande(arguments:"),
                      "le crash de test n'est déclenché que si Sentry a démarré")
    }

    // MARK: - Champs reçus par `beforeSend` et `beforeBreadcrumb` (revue B8 n°1, M1 et m3)

    /// Version de Sentry dont les propriétés publiques sont recensées ci-dessous : en-têtes `SentryEvent.h`,
    /// `SentryMessage.h`, `SentryException.h`, `SentryMechanism.h` et `SentryBreadcrumb.h` de `Sources/Sentry/Public/`, à
    /// la révision épinglée `4e1e4ba9`. Une montée de version rougit `testRecensementDeLaVersionEpinglee` : relire ces
    /// en-têtes, classer chaque propriété nouvelle (traitée ou conservée, avec sa raison), puis changer cette version.
    private static let versionRecensee = "9.32.0"

    /// Toutes les propriétés publiques d'un type Sentry reçu par les rappels : chacune est traitée par
    /// `CrashReporting.swift` (ligne exacte attendue) ou conservée telle quelle (raison). La cible app n'a pas de tests
    /// unitaires (`project.yml`) : cette garde statique tient lieu de test des fonctions `nettoyer`, dont chaque ligne
    /// applique une règle pure de `CrashScrubber`, elle-même testée (`CrashScrubberTests`).
    private struct Recensement {
        let type: String
        /// Variable qui porte une instance de ce type dans `CrashReporting.swift`.
        let variable: String
        let proprietes: [String]
        let traitees: [String: String]
        let conservees: [String: String]
    }

    private static let recensements: [Recensement] = [
        Recensement(
            type: "Event", variable: "event",
            proprietes: ["breadcrumbs", "context", "debugMeta", "dist", "environment", "error", "eventId", "exceptions",
                         "extra", "fingerprint", "level", "logger", "message", "modules", "platform", "releaseName",
                         "request", "sdk", "serverName", "stacktrace", "startTimestamp", "tags", "threads", "timestamp",
                         "transaction", "type", "user"],
            traitees: [
                "message": "event.message = propre",
                "exceptions": "event.exceptions?.forEach { nettoyer($0) }",
                "breadcrumbs": "event.breadcrumbs = event.breadcrumbs?.compactMap { nettoyer($0) }",
                "tags": "event.tags = event.tags.map(CrashScrubber.etiquettes)",
                "extra": "event.extra = event.extra.map(CrashScrubber.dictionnaire)",
                "context": "event.context = event.context.map(CrashScrubber.contextes)",
                "transaction": "event.transaction = event.transaction.map(CrashScrubber.texte)",
                "fingerprint": "event.fingerprint = event.fingerprint?.map(CrashScrubber.texte)",
                "logger": "event.logger = event.logger.map(CrashScrubber.texte)",
                "request": "event.request = nil",
                "serverName": "event.serverName = nil",
                "user": "event.user = event.user?.userId.map { User(userId: $0) }",
            ],
            conservees: [
                "eventId": "identifiant aléatoire de l'événement",
                "error": "NSError d'une capture manuelle, jamais sérialisé (SentryEvent.m) ; l'app ne capture aucune erreur",
                "timestamp": "date", "startTimestamp": "date", "level": "niveau", "platform": "« cocoa »",
                "releaseName": "posé par l'app (release du bundle)", "dist": "posé par le SDK (numéro de build)",
                "environment": "posé par l'app (mode)", "type": "posé par le SDK (« default », « transaction »)",
                "sdk": "nom, version et intégrations du SDK", "modules": "noms et versions de modules",
                "threads": "piles des fils (symboles, adresses)", "stacktrace": "pile (symboles, adresses)",
                "debugMeta": "images binaires chargées (UUID, adresses)",
            ]),
        Recensement(
            type: "Message", variable: "propre",
            proprietes: ["formatted", "message", "params"],
            traitees: [
                "formatted": "let propre = SentryMessage(formatted: CrashScrubber.texte(message.formatted))",
                "message": "propre.message = message.message.map(CrashScrubber.texte)",
                "params": "propre.params = message.params?.map(CrashScrubber.texte)",
            ],
            conservees: [:]),
        Recensement(
            type: "Exception", variable: "exception",
            proprietes: ["mechanism", "module", "stacktrace", "threadId", "type", "value"],
            traitees: [
                "value": "exception.value = exception.value.map(CrashScrubber.texte)",
                "type": "exception.type = exception.type.map(CrashScrubber.texte)",
                "mechanism": "guard let mecanisme = exception.mechanism else { return }",
            ],
            conservees: ["module": "module Swift ou nil", "threadId": "numéro de fil", "stacktrace": "pile (symboles, adresses)"]),
        Recensement(
            type: "Mechanism", variable: "mecanisme",
            proprietes: ["data", "desc", "handled", "helpLink", "meta", "synthetic", "type"],
            traitees: [
                // Sentry 9.32.0 y range `crash_info_messages` (messages du runtime Swift, texte d'un `fatalError` compris) :
                // `SentryCrashReportConverter.m` l.501-511.
                "data": "mecanisme.data = mecanisme.data.map(CrashScrubber.dictionnaire)",
                "desc": "mecanisme.desc = mecanisme.desc.map(CrashScrubber.texte)",
            ],
            conservees: ["type": "« mach », « signal », « nsexception », « AppHang »…", "handled": "booléen",
                         "synthetic": "booléen", "helpLink": "lien d'aide posé par le SDK",
                         "meta": "signal, exception Mach, domaine et code NSError"]),
        Recensement(
            type: "Breadcrumb", variable: "fil",
            proprietes: ["category", "data", "level", "message", "origin", "timestamp", "type"],
            traitees: [
                "category": "guard CrashScrubber.filConserve(categorie: fil.category, type: fil.type) else { return nil }",
                "type": "guard CrashScrubber.filConserve(categorie: fil.category, type: fil.type) else { return nil }",
                "message": "fil.message = fil.message.map(CrashScrubber.texte)",
                "data": "for (cle, valeur) in CrashScrubber.dictionnaire(fil.data ?? [:]) { fil.setData(value: valeur, key: cle) }",
            ],
            conservees: ["level": "niveau", "timestamp": "date", "origin": "origine posée par le SDK (« auto.… »)"]),
    ]

    func testRecensementCompletEtSansDoublon() {
        XCTAssertEqual(Self.recensements.map(\.type), ["Event", "Message", "Exception", "Mechanism", "Breadcrumb"])
        for r in Self.recensements {
            let traitees = Set(r.traitees.keys), conservees = Set(r.conservees.keys)
            XCTAssertEqual(traitees.intersection(conservees), [], "\(r.type) : propriété à la fois traitée et conservée")
            XCTAssertEqual(traitees.union(conservees), Set(r.proprietes), "\(r.type) : propriété non classée")
            XCTAssertEqual(r.proprietes.count, Set(r.proprietes).count, r.type)
        }
    }

    func testChaqueProprieteTraiteeLEstDansCrashReporting() throws {
        // M1 : `exceptions[].mechanism.data` (où Sentry 9.32.0 range `crash_info_messages`) et `mechanism.desc` passent
        // par `CrashScrubber`, comme la valeur et le type de l'exception.
        let reporting = try Self.lire("Jolene/Composition/CrashReporting.swift")
        for r in Self.recensements {
            for (propriete, ligne) in r.traitees.sorted(by: { $0.key < $1.key }) {
                XCTAssertTrue(reporting.contains(ligne), "\(r.type).\(propriete) : « \(ligne) » absent de CrashReporting.swift")
            }
        }
    }

    func testAucuneAffectationHorsRecensement() throws {
        // m3 : toute propriété réécrite par `CrashReporting.swift` est recensée comme traitée (rien de nettoyé, retiré ou
        // ajouté en silence) ; les options du SDK (`options.…`) ne sont pas concernées.
        let reporting = try Self.lire("Jolene/Composition/CrashReporting.swift")
        let variables = Dictionary(uniqueKeysWithValues: Self.recensements.map { ($0.variable, $0) })
        let affectation = try NSRegularExpression(pattern: #"\b(event|propre|exception|mecanisme|fil)\.(\w+)\s*=[^=]"#)
        let plage = NSRange(reporting.startIndex..<reporting.endIndex, in: reporting)
        var vues = 0
        for resultat in affectation.matches(in: reporting, range: plage) {
            guard let v = Range(resultat.range(at: 1), in: reporting), let p = Range(resultat.range(at: 2), in: reporting),
                  let r = variables[String(reporting[v])] else { continue }
            vues += 1
            XCTAssertNotNil(r.traitees[String(reporting[p])], "\(r.type).\(reporting[p]) réécrite sans être recensée")
        }
        XCTAssertGreaterThanOrEqual(vues, 15, "affectations lues : \(vues)")
    }

    func testRecensementDeLaVersionEpinglee() throws {
        let projet = try Self.lire("project.yml")
        XCTAssertTrue(projet.contains("    url: https://github.com/getsentry/sentry-cocoa\n    exactVersion: \(Self.versionRecensee)\n"),
                      "Sentry n'est plus en \(Self.versionRecensee) : relire les en-têtes et refaire le recensement")
        let resolu = try Self.lire("Jolene.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        let sentry = try XCTUnwrap(resolu.range(of: "\"identity\" : \"sentry-cocoa\""))
        let suite = resolu[sentry.upperBound...]
        let fin = suite.range(of: "}")?.upperBound ?? suite.endIndex
        XCTAssertTrue(suite[..<fin].contains("\"version\" : \"\(Self.versionRecensee)\""), "Package.resolved ≠ \(Self.versionRecensee)")
    }

    func testDSNJamaisVersionne() throws {
        let plist = try Self.lire("Jolene/Info.plist")
        XCTAssertTrue(plist.contains("<key>JoleneSentryDSN</key>\n\t<string>$(JOLENE_SENTRY_DSN)</string>"),
                      "Info.plist : JoleneSentryDSN alimentée par le réglage xcconfig")
        for fichier in ["Config/Base.xcconfig", "Config/Staging.xcconfig", "Config/Production.xcconfig"] {
            let contenu = try Self.lire(fichier)
            XCTAssertFalse(contenu.lowercased().contains("sentry.io"), "\(fichier) : DSN versionné")
            for ligne in contenu.components(separatedBy: "\n") where ligne.hasPrefix("JOLENE_SENTRY_DSN") {
                XCTAssertEqual(ligne.trimmingCharacters(in: .whitespaces), "JOLENE_SENTRY_DSN =", "\(fichier) : DSN non vide")
            }
        }
        XCTAssertTrue(try Self.lire("Config/Base.xcconfig").contains("\nJOLENE_SENTRY_DSN =\n"))
    }
}
