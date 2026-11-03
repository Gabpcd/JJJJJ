import Foundation
import JoleneCore
import JoleneSupabase

/// Racine de composition (plan §4.1). Lit l'environnement, choisit le jeu de gateways
/// et construit la session. Le mode démonstration n'instancie JAMAIS JoleneSupabase.
///
/// Surcharges de lancement et sentinelle réseau : honorées en build DEBUG uniquement, toutes lues
/// ici (l'environnement du processus n'est lu nulle part ailleurs). En Release, seul l'Info.plist
/// (xcconfig Production) fait foi, et la sentinelle n'existe pas dans le binaire.
/// - `-JOLENE_MODE` / `JOLENE_MODE` : mode (démo, staging, production) ;
/// - `JOLENE_FORCE_BAD_KEY` : clé publiable remplacée (`EnvironmentGuardTests`) ;
/// - `JOLENE_FORCE_ACCUEIL_ECHEC=1` : premier chargement de l'Accueil démo en échec ;
/// - `JOLENE_FORCE_MES_MISSIONS_ECHEC=1|session`, `JOLENE_FORCE_MES_MISSIONS_VIDE=1`,
///   `JOLENE_DEMO_MES_MISSIONS_PAGE=<1…50>` : recette des états de Mes missions démo
///   (`DemoMesMissionsSurcharges`, JoleneCore) ;
/// - `JOLENE_FORCE_CALENDRIER_REFUS=1` : accès au calendrier démo refusé (`calendrierRefusDemo`).
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
    /// Lot 1, T5 : refus simulé de l'accès au calendrier démo (surcharge DEBUG
    /// `JOLENE_FORCE_CALENDRIER_REFUS`), toujours faux en Release et hors démo.
    let calendrierRefusDemo: Bool
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
        calendrierRefusDemo = environment.mode == .demo && processEnvironment[CalendrierAppareilDemo.variableRefus] == "1"
        #else
        calendrierRefusDemo = false
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
            let gateways = Self.demoGateways(processEnvironment: processEnvironment)
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

    /// Ports du monde démo. DEBUG seulement (variables d'environnement du processus, comme
    /// `JOLENE_FORCE_BAD_KEY`), jamais compilé en Release :
    /// - `JOLENE_FORCE_ACCUEIL_ECHEC=1` fait échouer le premier chargement de l'Accueil
    ///   (`DemoDashboardEchecGateway`, `DemoAccueilTests.testAccueilErreurPuisReprise`) ;
    /// - les surcharges de Mes missions (`DemoMesMissionsSurcharges`) installent l'échec forcé, la
    ///   session expirée, les listes vides ou une taille de page réduite (`DemoMesMissionsTests`).
    private static func demoGateways(processEnvironment: [String: String]) -> Gateways {
        var gateways = DemoWorld.gateways()
        #if DEBUG
        if processEnvironment["JOLENE_FORCE_ACCUEIL_ECHEC"] == "1" {
            gateways.dashboard = DemoDashboardEchecGateway()
        }
        if let mesMissions = DemoMesMissionsSurcharges.port(environment: processEnvironment, clock: gateways.clock) {
            gateways.mesMissions = mesMissions
        }
        #endif
        return gateways
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
