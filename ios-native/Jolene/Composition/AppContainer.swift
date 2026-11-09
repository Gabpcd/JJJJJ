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
///
/// Lot 3, T5 : boîte des taps push (`NotificationCenterDelegate.shared.boite`, délégué posé au lancement) et
/// contexte du pré-prompt (compteur de lancements à froid et marque : `UserDefaults` en staging/production,
/// mémoire vive en démo) ; DEBUG : `-JOLENE_SIMULER_PUSH` (démo, tap à froid simulé) et `-JOLENE_SESSION_COUNT`
/// (numéro de session imposé, sans persistance).
///
/// Lot 3, T3b (reliquat L1-T10) : coordinateur des liens (`DeepLinkCoordinator`), point d'entrée unique des liens
/// universels et des taps push ; DEBUG : `-JOLENE_OPEN_URL <url>` (démo et staging), lien universel simulé à froid.
/// Revue B8 de T3b : le coordinateur est le port `FinIdentiteWebPort` de la session (M1 : renvoi fermé et magasin
/// `SFSafariViewController` effacé à chaque fin d'identité, aucun effacement en démo) ; DEBUG, démo :
/// `-JOLENE_OPEN_URL_SUIVANT <url>` (lien remis pendant un renvoi affiché, m1) et `JOLENE_FORCE_OUBLI_POINTAGE=1`
/// (Accueil avec un oubli de pointage, m4).
///
/// Lot 3, T10 : localisation ponctuelle du profil (`localisationProfil`) — démo : `DemoLocalisationProfil` (DEBUG :
/// `-JOLENE_DEMO_LOCALISATION accordee|refusee|indisponible`) ; staging/production : `LocalisationProfilProvisoire`,
/// implémentation isolée remplacée à la fusion par un adaptateur sur `LocationService` du lot 2 (une seule source de
/// position dans l'app). DEBUG, démo : `-JOLENE_DEMO_AVATAR refus` (stockage en refus) et `-JOLENE_DEMO_GEOCODAGE echec`.
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
    /// Lot 3, T5 : taps de notification en attente de l'espace prêt (`MainTabView`).
    let tapsPush: BoiteTapsPush
    /// Lot 3, T3b : coordinateur des liens universels et des taps push (`DeepLinkCoordinator`).
    let liens: DeepLinkCoordinator
    /// Lot 3, T5 : contexte du pré-prompt pour ce lancement (nil si l'environnement est refusé).
    private(set) var prePrompt: ContextePrePromptPush?
    /// Lot 1, T8 : avis de fin de compte partagé entre l'écran de suppression et la racine.
    let finDeCompte = AvisFinDeCompte()
    /// Lot 3, T7 : liens d'inscription (`/inscription/confirmer`, `/inscription/soignant`, `/inscription/reprendre`)
    /// consommés hors de l'espace prêt ; alimentés par le coordinateur des liens (T3b, intégration du lot 3), lus par
    /// `RootView`.
    let liensInscription: BoiteLiensInscription
    /// Lot 3, T11 : thème de l'app (D16), appliqué à la racine (`ThemeRacine`) ; par appareil (`UserDefaults`,
    /// clé `jolene.theme`) en staging et production, mémoire vive en démo (chaque lancement démo part de Système).
    let theme: PreferenceThemeModel
    /// Lot 3, T10 : position du profil (« Utiliser ma position actuelle ») ; nil si l'environnement est refusé.
    let localisationProfil: LocalisationPort?
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
        let boite = NotificationCenterDelegate.shared.boite
        tapsPush = boite
        // Revue B8 de T3b, M1 : le coordinateur est aussi le port `FinIdentiteWebPort` de la session (fermeture du renvoi
        // affiché, effacement du magasin `SFSafariViewController` hors démo). Intégration de T7 : il dépose les liens
        // d'inscription dans `liensInscription`, que `RootView` présente hors de l'espace.
        let inscription = BoiteLiensInscription()
        liensInscription = inscription
        let liens = DeepLinkCoordinator(taps: boite, inscription: inscription, estDemo: environment.mode == .demo,
                                        effaceur: environment.mode == .demo ? nil : EffaceurDonneesSafari())
        self.liens = liens
        theme = PreferenceThemeModel(stockage: environment.mode == .demo ? MemoireStockageAppareil() : UserDefaultsStockageAppareil())
        // Lot 3, T11 (revue B8, m8) : un fichier d'export RGPD laissé par un arrêt brutal (feuille de partage jamais
        // fermée) est retiré dès le lancement, sans attendre le prochain hub ni la prochaine connexion.
        DossierExportTemporaire.systeme.purgerResidus()

        // Un mode inconnu (`unknownModeRaw`) est refusé par `validate()` avant tout choix de gateways.
        if let error = Self.refusal(of: environment) {
            #if DEBUG
            networkSentinel = nil
            #endif
            clock = SystemClock()
            session = nil
            push = nil
            pushPermission = nil
            localisationProfil = nil
            environmentError = error
            return
        }

        #if DEBUG
        // Lot 3, T3b : lien universel simulé à froid, reçu avant toute session (mémorisé jusqu'à l'espace prêt, ou
        // renvoi web présenté aussitôt) ; mêmes refus qu'un lien réel (hôtes de l'AASA, https).
        if let url = DeepLinkIntent.ouvertureSimulee(arguments: arguments) { liens.recevoirAuLancement(url: url) }
        // Revue B8 de T3b, m1 : lien remis par le double démo du renvoi web, pendant un renvoi affiché (démo seulement).
        if let url = DeepLinkIntent.lienSuivantSimule(arguments: arguments) { liens.preparerLienSuivantDemo(url) }
        #endif

        switch environment.mode {
        case .demo:
            #if DEBUG
            NetworkSentinel.install()
            networkSentinel = NetworkSentinel.Monitor.shared
            #endif
            let gateways = Self.demoGateways(arguments: arguments, processEnvironment: processEnvironment)
            clock = gateways.clock
            let controller = SessionController(gateways: gateways)
            let permission = DemoPushPermission(etat: Self.autorisationPushDemo(arguments: arguments))
            let coordinator = PushCoordinator(controller: controller, permission: permission,
                                              registrar: DemoPushRegistrar(), memoire: MemoirePushTokenStore())
            push = coordinator
            pushPermission = permission
            localisationProfil = DemoLocalisationProfil(scenario: Self.scenarioLocalisationDemo(arguments: arguments))
            session = SessionStore(controller: controller, push: coordinator, finIdentiteWeb: liens)
            environmentError = nil
            prePrompt = Self.contextePrePrompt(mode: .demo, arguments: arguments)
            #if DEBUG
            // Tap à froid simulé (blueprint §2.7) : rejoué par le premier espace prêt, après la connexion démo.
            if let tap = PushTapIntent.simule(arguments: arguments) { boite.recevoir(tap) }
            #endif
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
                localisationProfil = LocalisationProfilProvisoire()
                let store = SessionStore(controller: controller, push: coordinator, finIdentiteWeb: liens)
                // Session effacée côté SDK (révocation, déconnexion globale, refresh refusé) :
                // l'écran bascule sans action de l'utilisateur.
                store.observeAuthEvents()
                session = store
                environmentError = nil
                prePrompt = Self.contextePrePrompt(mode: environment.mode, arguments: arguments)
            } catch let error as JoleneError {
                clock = SystemClock()
                session = nil
                push = nil
                pushPermission = nil
                localisationProfil = nil
                environmentError = error
            } catch {
                clock = SystemClock()
                session = nil
                push = nil
                pushPermission = nil
                localisationProfil = nil
                environmentError = JoleneError(.environment, "Configuration de l'application invalide.")
            }
        }
    }

    /// Ports du monde démo. DEBUG seulement : `JOLENE_FORCE_ACCUEIL_ECHEC=1` (variable d'environnement
    /// du processus, comme `JOLENE_FORCE_BAD_KEY`) fait échouer le premier chargement de l'Accueil
    /// (`DemoDashboardEchecGateway`) pour la recette de l'état d'erreur et de la reprise
    /// (`DemoAccueilTests.testAccueilErreurPuisReprise`) ; lot 3, T6 : `JOLENE_FORCE_PREFERENCES_ECHEC=1`,
    /// de même pour les préférences de notifications (`DemoPreferencesEchecGateway`,
    /// `DemoPreferencesTests.testPreferencesErreurPuisReprise`) ; lot 3, T9 : `JOLENE_DEMO_PROFIL=<variante>`
    /// (`VarianteProfilDemo`) sert le profil démo dans une variante de recette (`DemoProfilTests`) ; lot 3, T3b :
    /// `JOLENE_FORCE_OUBLI_POINTAGE=1` sert le tableau de bord démo avec un oubli de pointage
    /// (`DemoDashboardGateway(missionsOubliees:)`, `DemoAccueilTests.testOubliDePointageOuvreLesPresencesSurLeWeb`) ;
    /// lot 3, T7 : `-JOLENE_DEMO_INSCRIPTION_REFUS <code>` (`RefusInscriptionDemo`, blueprint §2.7) rejoue un refus
    /// d'inscription (`DemoInscriptionTests`) ; lot 3, T11 : `JOLENE_FORCE_EXPORT_ECHEC=1` fait refuser l'export RGPD
    /// avec le message serveur verbatim (`DemoCompteLot3Tests.testExportRefuseParLeServeurAfficheLeMessageSansFeuille`).
    /// Jamais compilé en Release.
    private static func demoGateways(arguments: [String], processEnvironment: [String: String]) -> Gateways {
        #if DEBUG
        var gateways = DemoWorld.gateways()
        if let refus = RefusInscriptionDemo(arguments: arguments), let auth = gateways.auth as? DemoAuthGateway {
            gateways.inscription = DemoInscriptionGateway(auth: auth, refus: refus) // lot 3, T7
        }
        if processEnvironment["JOLENE_FORCE_ACCUEIL_ECHEC"] == "1" {
            gateways.dashboard = DemoDashboardEchecGateway()
        } else if processEnvironment[DemoDashboardGateway.variableOubliPointage] == "1" {
            gateways.dashboard = DemoDashboardGateway(missionsOubliees: 1) // lot 3, T3b (revue B8, m4)
        }
        if processEnvironment["JOLENE_FORCE_PREFERENCES_ECHEC"] == "1" {
            gateways.preferences = DemoPreferencesEchecGateway() // lot 3, T6
        }
        if let variante = processEnvironment[VarianteProfilDemo.variableEnvironnement].flatMap(VarianteProfilDemo.init(rawValue:)) {
            gateways.profil = DemoProfilGateway(variante: variante) // lot 3, T9
            gateways.avatar = DemoWorld.avatar(profil: gateways.profil) // lot 3, T10 : même ligne que la variante
        }
        if let scenario = ScenarioAvatarDemo(arguments: arguments) {
            gateways.avatar = DemoWorld.avatar(profil: gateways.profil, scenario: scenario) // lot 3, T10
        }
        if DemoGeocodage.enEchec(arguments: arguments) {
            gateways.geocodage = DemoGeocodage(enEchec: true) // lot 3, T10
        }
        if processEnvironment["JOLENE_FORCE_EXPORT_ECHEC"] == "1" {
            gateways.exportRGPD = DemoExportRGPDGateway(refus: ExportRGPD.refusLimiteServeur) // lot 3, T11
        }
        return gateways
        #else
        return DemoWorld.gateways()
        #endif
    }

    /// Lot 3, T10 : scénario de la localisation démo. DEBUG seulement : `-JOLENE_DEMO_LOCALISATION` ; sinon (et toujours
    /// en Release) position accordée.
    private static func scenarioLocalisationDemo(arguments: [String]) -> ScenarioLocalisationDemo {
        #if DEBUG
        return ScenarioLocalisationDemo(arguments: arguments) ?? .accordee
        #else
        return .accordee
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

    /// Lot 3, T5 : lancement à froid compté une fois par processus (`AppContainer` est unique) ; démo en mémoire
    /// vive (chaque lancement démo est une 1re session : jamais de pré-prompt sans `-JOLENE_SESSION_COUNT`).
    /// DEBUG seulement : `-JOLENE_SESSION_COUNT <n>` impose le numéro de session, compteur et marque en mémoire.
    private static func contextePrePrompt(mode: JoleneMode, arguments: [String]) -> ContextePrePromptPush {
        #if DEBUG
        if let numero = PrePromptPush.numeroSessionForce(arguments: arguments) {
            return ContextePrePromptPush(stockage: MemoireStockageAppareil(), numeroSession: numero)
        }
        #endif
        if mode == .demo { return .lancement(stockage: MemoireStockageAppareil()) }
        return .lancement(stockage: UserDefaultsStockageAppareil())
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
