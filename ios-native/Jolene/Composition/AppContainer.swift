import Foundation
import JoleneCore
import JoleneSupabase

/// Racine de composition (plan §4.1). Lit l'environnement, choisit le jeu de gateways
/// et construit la session. Le mode démonstration n'instancie JAMAIS JoleneSupabase.
///
/// Surcharges de lancement (`-JOLENE_MODE`, `JOLENE_MODE`, `JOLENE_FORCE_BAD_KEY`,
/// `JOLENE_FORCE_ACCUEIL_ECHEC`) et sentinelle réseau : honorées en build DEBUG uniquement. En
/// Release, seul l'Info.plist (xcconfig Production) fait foi, et la sentinelle n'existe pas dans
/// le binaire.
@MainActor
final class AppContainer: ObservableObject {
    let environment: JoleneEnvironment
    /// Non nul si la garde d'environnement ou la construction du client a échoué :
    /// l'app affiche alors l'écran bloquant `env-blocked` et rien d'autre.
    let environmentError: JoleneError?
    let session: SessionStore?
    let clock: ClockPort
    /// Lot 1, T8 : avis de fin de compte partagé entre l'écran de suppression et la racine.
    let finDeCompte = AvisFinDeCompte()
    /// Lot 2, T7 : sélecteurs de médias du monde démo (`DemoMediaPicker`, fichier de `-JOLENE_DEMO_SOURCE_DOC` en DEBUG),
    /// à la place de l'appareil photo, de la photothèque et de Fichiers ; nil hors démo (vrais sélecteurs).
    private(set) var mediaDemo: DemoMediaPicker?
    /// Lot 2, T4b : capacités d'appareil (position, réseau, identifiant terminal, magasin des reçus durables), réelles ou
    /// démo (`Appareil.demo`, scénarios `-JOLENE_DEMO_GPS` et `-JOLENE_DEMO_RESEAU` en DEBUG), injectées à côté des
    /// gateways (blueprint §2.2) ; scanner de QR réel ou démo (`-JOLENE_DEMO_QR` en DEBUG) ; fabrique de la zone de
    /// pointage, injectée au-dessus des onglets par `MainTabView`.
    let appareil: Appareil
    let scannerQR: ModeScannerQR
    let fabriqueZonePointage: FabriqueZonePointageNative
    #if DEBUG
    let networkSentinel: NetworkSentinel.Monitor?
    #endif

    var isDemo: Bool { environment.mode == .demo }

    convenience init() {
        self.init(arguments: CommandLine.arguments,
                  processEnvironment: ProcessInfo.processInfo.environment,
                  info: Bundle.main.infoDictionary ?? [:])
    }

    init(arguments: [String], processEnvironment: [String: String], info: [String: Any]) {
        #if DEBUG
        let allowOverrides = true
        #else
        let allowOverrides = false
        #endif
        var environment = JoleneEnvironment.load(arguments: arguments, environment: processEnvironment, info: info,
                                                 allowOverrides: allowOverrides)
        #if DEBUG
        // Test de garde (EnvironmentGuardTests) : une clé injectée par l'environnement de
        // test remplace la clé du bundle. Jamais compilé en Release.
        if let forced = processEnvironment["JOLENE_FORCE_BAD_KEY"], !forced.isEmpty {
            environment.publishableKey = forced
        }
        #endif
        self.environment = environment

        // Un mode inconnu (`unknownModeRaw`) est refusé par `validate()` avant tout choix de gateways.
        let refus = Self.refusal(of: environment)
        // Garde d'environnement d'abord (seconde revue fraîche de T4b, m7) : un mode refusé (mauvaise clé,
        // `JOLENE_FORCE_BAD_KEY`, mode inconnu) reçoit l'appareil démo, jamais utilisé (aucune session n'est construite) ;
        // aucun service réel (CoreLocation, `NWPathMonitor`, trousseau) n'est créé pour lui.
        let appareil = refus == nil ? Self.appareil(mode: environment.mode, arguments: arguments) : Appareil.demo()
        let scanner = Self.scanner(mode: environment.mode, arguments: arguments)
        self.appareil = appareil
        scannerQR = scanner
        fabriqueZonePointage = FabriqueZonePointageNative(appareil: appareil, scanner: scanner)

        if let error = refus {
            #if DEBUG
            networkSentinel = nil
            #endif
            clock = SystemClock()
            session = nil
            environmentError = error
            return
        }

        switch environment.mode {
        case .demo:
            #if DEBUG
            NetworkSentinel.install()
            networkSentinel = NetworkSentinel.Monitor.shared
            #endif
            let gateways = Self.demoGateways(arguments: arguments, processEnvironment: processEnvironment)
            #if DEBUG
            mediaDemo = DemoMediaPicker(source: SourceDocumentDemo(arguments: arguments))
            #else
            mediaDemo = DemoMediaPicker(source: .png)
            #endif
            clock = gateways.clock
            session = SessionStore(controller: SessionController(gateways: gateways))
            environmentError = nil
        case .staging, .production:
            #if DEBUG
            networkSentinel = nil
            #endif
            do {
                let gateways = try SupabaseGateways.make(environment: environment)
                clock = gateways.clock
                let store = SessionStore(controller: SessionController(gateways: gateways))
                // Session effacée côté SDK (révocation, déconnexion globale, refresh refusé) :
                // l'écran bascule sans action de l'utilisateur.
                store.observeAuthEvents()
                session = store
                environmentError = nil
            } catch let error as JoleneError {
                clock = SystemClock()
                session = nil
                environmentError = error
            } catch {
                clock = SystemClock()
                session = nil
                environmentError = JoleneError(.environment, "Configuration de l'application invalide.")
            }
        }
    }

    /// Ports du monde démo. DEBUG seulement : `JOLENE_FORCE_ACCUEIL_ECHEC=1` (variable d'environnement
    /// du processus, comme `JOLENE_FORCE_BAD_KEY`) fait échouer le premier chargement de l'Accueil
    /// (`DemoDashboardEchecGateway`) pour la recette de l'état d'erreur et de la reprise
    /// (`DemoAccueilTests.testAccueilErreurPuisReprise`) ; lot 2 T7 : `-JOLENE_DEMO_SCENARIO upload-incertain`
    /// pose `DemoDocumentsGateway(scenario: .uploadIncertain)` (réponse perdue après application, `DemoDocumentsTests`) ;
    /// lot 2 T4b (seconde revue fraîche, m3) : `-JOLENE_FLAG_<cle> true|false` surcharge un drapeau d'écran
    /// (`DemoFlagsGateway.surcharges`, coupe-circuit D-FLAGS). Jamais compilé en Release.
    private static func demoGateways(arguments: [String], processEnvironment: [String: String]) -> Gateways {
        #if DEBUG
        var gateways = DemoWorld.gateways(drapeaux: DemoFlagsGateway.surcharges(arguments: arguments))
        if processEnvironment["JOLENE_FORCE_ACCUEIL_ECHEC"] == "1" {
            gateways.dashboard = DemoDashboardEchecGateway()
        }
        let scenarioDocuments = ScenarioDocumentsDemo(arguments: arguments)
        if scenarioDocuments != .normal {
            gateways.documents = DemoDocumentsGateway(scenario: scenarioDocuments)
        }
        // Lot 2 T4b : `-JOLENE_DEMO_SCENARIO scan-incertain` (premier scan appliqué, réponse perdue, réconciliation) ;
        // seconde revue fraîche (m2) : `session-expiree-scan`, `session-expiree-consentement` (pointage et authentification
        // démo liés : « Vérifier ma session » revalide), `consentement-echec`.
        DemoPointageGateway.Scenario(arguments: arguments).installer(dans: &gateways)
        return gateways
        #else
        return DemoWorld.gateways()
        #endif
    }

    /// Appareil réel (Staging, Production : CoreLocation, `NWPathMonitor`, trousseau) ou démo (aucun prompt système,
    /// aucun réseau ; scénarios DEBUG). Appelé seulement pour un mode accepté par la garde d'environnement (`init`).
    private static func appareil(mode: JoleneMode, arguments: [String]) -> Appareil {
        switch mode {
        case .demo:
            #if DEBUG
            return Appareil.demo(gps: ScenarioGpsDemo(arguments: arguments), reseau: ScenarioReseauDemo(arguments: arguments))
            #else
            return Appareil.demo()
            #endif
        case .staging, .production:
            return Appareil(localisation: LocationService(), reseau: NetworkMonitor(), terminal: KeychainTerminalIdentity(),
                            recus: KeychainReceiptStore())
        }
    }

    private static func scanner(mode: JoleneMode, arguments: [String]) -> ModeScannerQR {
        guard mode == .demo else { return .reel }
        #if DEBUG
        return .demo(ScenarioQRDemo(arguments: arguments))
        #else
        return .demo(ScenarioQRDemo(arguments: []))
        #endif
    }

    private static func refusal(of environment: JoleneEnvironment) -> JoleneError? {
        do {
            try environment.validate()
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            return JoleneError(.environment, "Configuration de l'application invalide.")
        }
    }
}
