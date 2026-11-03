import Foundation
import JoleneCore
import JoleneSupabase

/// Racine de composition (plan §4.1). Lit l'environnement, choisit le jeu de gateways
/// et construit la session. Le mode démonstration n'instancie JAMAIS JoleneSupabase.
///
/// Surcharges de lancement (`-JOLENE_MODE`, `JOLENE_MODE`, `JOLENE_FORCE_BAD_KEY`,
/// `JOLENE_FORCE_ACCUEIL_ECHEC`, `-JOLENE_FLAG_<cle>` et `-JOLENE_DEMO_*` en démo) et sentinelle réseau :
/// honorées en build DEBUG uniquement. En
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
        if let error = Self.refusal(of: environment) {
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
    /// (`DemoAccueilTests.testAccueilErreurPuisReprise`). Jamais compilé en Release.
    ///
    /// Lot 5 (T2a, D20) : DEBUG seulement, `-JOLENE_DEMO_ESPACE etablissement` (+ `-JOLENE_DEMO_ROLE_ETAB`,
    /// `-JOLENE_DEMO_LEGACY 1`, `-JOLENE_DEMO_BLOCAGE 1`, `DemoEspaceLancement`) ouvre l'espace établissement
    /// fictif, et `-JOLENE_FLAG_<cle> true|false` (`DrapeauxLancement`, lot 1 T9) surcharge un drapeau
    /// d'écran (`DemoFlagsGateway`), pour la recette du renvoi web (`DemoEtabSessionTests`).
    private static func demoGateways(arguments: [String], processEnvironment: [String: String]) -> Gateways {
        #if DEBUG
        let drapeaux = DrapeauxLancement.surcharges(arguments: arguments)
        let espace = DemoEspaceLancement.espace(arguments: arguments)
        if processEnvironment["JOLENE_FORCE_ACCUEIL_ECHEC"] == "1" {
            var gateways = DemoWorld.gateways(espace: espace, drapeaux: drapeaux)
            gateways.dashboard = DemoDashboardEchecGateway()
            return gateways
        }
        return DemoWorld.gateways(espace: espace, drapeaux: drapeaux)
        #else
        return DemoWorld.gateways()
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
