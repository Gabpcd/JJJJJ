import Foundation
import JoleneCore
import JoleneSupabase

/// Racine de composition (plan §4.1). Lit l'environnement, choisit le jeu de gateways
/// et construit la session. Le mode démonstration n'instancie JAMAIS JoleneSupabase.
///
/// Surcharges de lancement (`-JOLENE_MODE`, `JOLENE_MODE`, `JOLENE_FORCE_BAD_KEY`,
/// `JOLENE_FORCE_ACCUEIL_ECHEC`, `JOLENE_FORCE_PREFERENCES_ECHEC`, `-JOLENE_PUSH_AUTORISATION` en démo, `-JOLENE_PUSH_TOKEN_FACTICE` en
/// staging) et sentinelle réseau : honorées en build DEBUG uniquement. En Release, seul l'Info.plist
/// (xcconfig Production) fait foi, et la sentinelle n'existe pas dans le binaire.
///
/// Lot 3, T4 : le coordinateur push est construit avec la session (`SessionStore(controller:push:)`) :
/// démo = doubles sans feuille système ni réseau (`DemoPushPermission`, `DemoPushRegistrar`, mémoire
/// vive) ; staging/production = `UNUserNotificationCenter`, `PushRegistrar` (APNs) et trousseau
/// `app.jolene.push`.
@MainActor
final class AppContainer: ObservableObject {
    let environment: JoleneEnvironment
    /// Non nul si la garde d'environnement ou la construction du client a échoué :
    /// l'app affiche alors l'écran bloquant `env-blocked` et rien d'autre.
    let environmentError: JoleneError?
    let session: SessionStore?
    let clock: ClockPort
    /// Lot 3, T4 : enregistrement et désactivation du token APNs (nil si l'environnement est refusé).
    let push: PushCoordinator?
    /// Lot 3, T4 : autorisation des notifications de l'appareil (carte `push-etat-appareil`).
    let pushPermission: PushPermissionPort?
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
            push = nil
            pushPermission = nil
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
            let controller = SessionController(gateways: gateways)
            let permission = DemoPushPermission(etat: Self.autorisationPushDemo(arguments: arguments))
            let coordinator = PushCoordinator(controller: controller, permission: permission,
                                              registrar: DemoPushRegistrar(), memoire: MemoirePushTokenStore())
            push = coordinator
            pushPermission = permission
            session = SessionStore(controller: controller, push: coordinator)
            environmentError = nil
        case .staging, .production:
            #if DEBUG
            networkSentinel = nil
            #endif
            do {
                let gateways = try SupabaseGateways.make(environment: environment)
                clock = gateways.clock
                let controller = SessionController(gateways: gateways)
                let (permission, registrar) = Self.appareilPush(mode: environment.mode, arguments: arguments)
                let coordinator = PushCoordinator(controller: controller, permission: permission,
                                                  registrar: registrar, memoire: KeychainPushTokenStore())
                push = coordinator
                pushPermission = permission
                let store = SessionStore(controller: controller, push: coordinator)
                // Session effacée côté SDK (révocation, déconnexion globale, refresh refusé) :
                // l'écran bascule sans action de l'utilisateur.
                store.observeAuthEvents()
                session = store
                environmentError = nil
            } catch let error as JoleneError {
                clock = SystemClock()
                session = nil
                push = nil
                pushPermission = nil
                environmentError = error
            } catch {
                clock = SystemClock()
                session = nil
                push = nil
                pushPermission = nil
                environmentError = JoleneError(.environment, "Configuration de l'application invalide.")
            }
        }
    }

    /// Ports du monde démo. DEBUG seulement : `JOLENE_FORCE_ACCUEIL_ECHEC=1` (variable d'environnement
    /// du processus, comme `JOLENE_FORCE_BAD_KEY`) fait échouer le premier chargement de l'Accueil
    /// (`DemoDashboardEchecGateway`) pour la recette de l'état d'erreur et de la reprise
    /// (`DemoAccueilTests.testAccueilErreurPuisReprise`) ; lot 3, T6 : `JOLENE_FORCE_PREFERENCES_ECHEC=1`,
    /// de même pour les préférences de notifications (`DemoPreferencesEchecGateway`,
    /// `DemoPreferencesTests.testPreferencesErreurPuisReprise`). Jamais compilé en Release.
    private static func demoGateways(processEnvironment: [String: String]) -> Gateways {
        #if DEBUG
        var gateways = DemoWorld.gateways()
        if processEnvironment["JOLENE_FORCE_ACCUEIL_ECHEC"] == "1" {
            gateways.dashboard = DemoDashboardEchecGateway()
        }
        if processEnvironment["JOLENE_FORCE_PREFERENCES_ECHEC"] == "1" {
            gateways.preferences = DemoPreferencesEchecGateway() // lot 3, T6
        }
        return gateways
        #else
        return DemoWorld.gateways()
        #endif
    }

    /// Lot 3, T4 : état d'autorisation du double démo. DEBUG seulement : `-JOLENE_PUSH_AUTORISATION`
    /// (`PushLancement`) ; sinon (et toujours en Release) un appareil neuf, autorisation jamais demandée.
    private static func autorisationPushDemo(arguments: [String]) -> AutorisationPush {
        #if DEBUG
        return PushLancement.autorisation(arguments: arguments) ?? .nonDemandee
        #else
        return .nonDemandee
        #endif
    }

    /// Lot 3, T4 : capacités push réelles (`UNUserNotificationCenter`, APNs). DEBUG et staging seulement :
    /// `-JOLENE_PUSH_TOKEN_FACTICE <hex>` remplace APNs par ce token et simule l'autorisation accordée,
    /// pour la preuve STAGING de T16 (`tokens_push` relu, `actif` vrai puis faux). Jamais en production.
    private static func appareilPush(mode: JoleneMode, arguments: [String]) -> (PushPermissionPort, PushRegistrarPort) {
        #if DEBUG
        if mode == .staging, let factice = PushLancement.tokenFactice(arguments: arguments) {
            return (DemoPushPermission(etat: .accordee), DemoPushRegistrar(token: factice))
        }
        #endif
        return (SystemePushPermission(), PushRegistrar.shared)
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
