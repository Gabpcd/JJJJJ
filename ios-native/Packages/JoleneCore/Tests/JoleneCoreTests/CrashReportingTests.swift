import XCTest
@testable import JoleneCore

/// Lot 3, T15 (D21, blueprint `LOT3_PLAN.md` §2.7 et §3 T15) — démarrage de Sentry Cocoa :
/// - **jamais en démo**, ni sans DSN (clé `JoleneSentryDSN` de l'Info.plist vide, absente ou non résolue), ni pour un
///   environnement refusé par la garde (`JoleneEnvironment.validate`) : la fabrique de l'adaptateur Sentry n'est alors
///   jamais appelée, aucun service n'est créé ; en démo, la sentinelle réseau « 0 requête » des XCUITest démo
///   (`network-sentinel`, `DemoConsultationTests` et suivants) reste donc inchangée ;
/// - environnement = mode de l'app, release `<CFBundleIdentifier>@<CFBundleShortVersionString>+<CFBundleVersion>` lue dans
///   le bundle (jamais codée en dur), réglages sans PII ;
/// - identifiant utilisateur posé sur `.ready`, retiré (`nil`) à chaque fin d'identité, conservé sur une fin transitoire ;
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
        let restaurations = MutableAuthState(restored: MondePush.utilisateur, restoreError: nil)
        let monde = MondePush(restaurations: restaurations)
        let (store, espion) = store(monde)
        await store.start()
        await restaurations.set(restored: MondePush.utilisateur, restoreError: JoleneError(.network, "hors ligne"))
        await store.start()
        XCTAssertEqual(store.state, .signedOut(message: SessionController.restoreFailedMessage))
        XCTAssertEqual(espion.utilisateurs, ["u-push"], "le SDK détient encore la session : identité inchangée")
    }

    func testEspaceBloqueNePosePasDIdentifiant() async {
        let (store, espion) = store(MondePush(missions: NeutralMissions()))
        await store.start()
        guard case .blocked = store.state else { return XCTFail("attendu : espace bloqué, obtenu \(store.state)") }
        XCTAssertEqual(espion.appels, [], "identifiant posé sur `.ready` seulement (blueprint §3 T15)")
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
