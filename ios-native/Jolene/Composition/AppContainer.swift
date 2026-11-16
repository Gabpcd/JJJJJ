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
/// `-JOLENE_DEMO_LOCALISATION accordee|refusee|indisponible`) ; staging/production : `LocalisationProfilAppareil`,
/// adaptateur sur `Appareil.localisation` (`LocationService` du lot 2), qui remplace depuis la fusion des lots 2 et 3
/// l'implémentation isolée de T10 (une seule source de position dans l'app). DEBUG, démo : `-JOLENE_DEMO_AVATAR refus`
/// (stockage en refus), `-JOLENE_DEMO_AVATAR illisible` (photo choisie illisible, revue B8 M1) et
/// `-JOLENE_DEMO_GEOCODAGE echec`.
///
/// Lot 2 (T4b, T7, T9b) : capacités d'appareil (`appareil` : position, réseau, identifiant terminal, reçus durables),
/// scanner de QR et zone de pointage ; sélecteurs de médias démo (`mediaDemo`) ; scénarios DEBUG
/// `-JOLENE_DEMO_SCENARIO`, `-JOLENE_DEMO_GPS`, `-JOLENE_DEMO_RESEAU`, `-JOLENE_DEMO_QR`, `-JOLENE_DEMO_SOURCE_DOC` et
/// `-JOLENE_FLAG_<cle>` (démo seulement).
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
    /// Lot 3, T7 : liens d'inscription (`/inscription/confirmer`, `/inscription/soignant`, `/inscription/reprendre`)
    /// consommés hors de l'espace prêt ; alimentés par le coordinateur des liens (T3b, intégration du lot 3), lus par
    /// `RootView`.
    let liensInscription: BoiteLiensInscription
    /// Lot 3, T11 : thème de l'app (D16), appliqué à la racine (`ThemeRacine`) ; par appareil (`UserDefaults`,
    /// clé `jolene.theme`) en staging et production, mémoire vive en démo (chaque lancement démo part de Système).
    let theme: PreferenceThemeModel
    /// Lot 3, T10 : position du profil (« Utiliser ma position actuelle ») ; nil si l'environnement est refusé.
    let localisationProfil: LocalisationPort?
    /// Lot 3, T10 (revue B8, M1) : issue des sources de la photo en démo, sans feuille système (photo de démonstration,
    /// ou lecture impossible avec `-JOLENE_DEMO_AVATAR illisible`, DEBUG) ; nil en staging et en production (feuilles
    /// système réelles).
    let selectionAvatarDemo: SelectionPhotoAvatar?
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
        selectionAvatarDemo = environment.mode == .demo
            ? DemoFixtures.selectionAvatarDemo(scenario: Self.scenarioAvatarDemo(arguments: arguments)) : nil
        // Lot 3, T11 (revue B8, m8) : un fichier d'export RGPD laissé par un arrêt brutal (feuille de partage jamais
        // fermée) est retiré dès le lancement, sans attendre le prochain hub ni la prochaine connexion.
        DossierExportTemporaire.systeme.purgerResidus()

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
            #if DEBUG
            mediaDemo = DemoMediaPicker(source: SourceDocumentDemo(arguments: arguments))
            #else
            mediaDemo = DemoMediaPicker(source: .png)
            #endif
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
                // Fusion des lots 2 et 3 : la position du profil passe par le service de position du lot 2.
                localisationProfil = LocalisationProfilAppareil(localisation: appareil.localisation)
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
    /// (`DemoAccueilTests.testAccueilErreurPuisReprise`) ; lot 2 T7 : `-JOLENE_DEMO_SCENARIO upload-incertain`
    /// pose `DemoDocumentsGateway(scenario: .uploadIncertain)` (réponse perdue après application, `DemoDocumentsTests`) ;
    /// lot 2 T4b (seconde revue fraîche, m3) : `-JOLENE_FLAG_<cle> true|false` surcharge un drapeau d'écran
    /// (`DemoFlagsGateway.surcharges`, coupe-circuit D-FLAGS) ; lot 2 T9b : `otp-expire` et `compte-test` posent
    /// `DemoContratsGateway(scenario:)` ; lot 3, T6 : `JOLENE_FORCE_PREFERENCES_ECHEC=1`,
    /// de même pour les préférences de notifications (`DemoPreferencesEchecGateway`,
    /// `DemoPreferencesTests.testPreferencesErreurPuisReprise`) ; lot 3, T9 : `JOLENE_DEMO_PROFIL=<variante>`
    /// (`VarianteProfilDemo`) sert le profil démo dans une variante de recette (`DemoProfilTests`) ; lot 3, T3b :
    /// `JOLENE_FORCE_OUBLI_POINTAGE=1` sert le tableau de bord démo avec un oubli de pointage
    /// (`DemoDashboardGateway(missionsOubliees:)`, `DemoAccueilTests.testOubliDePointageOuvreLesPresencesNatives`) ;
    /// lot 3, T7 : `-JOLENE_DEMO_INSCRIPTION_REFUS <code>` (`RefusInscriptionDemo`, blueprint §2.7) rejoue un refus
    /// d'inscription (`DemoInscriptionTests`), y compris ceux de la complétion (T8, `DemoCompletionInscriptionTests`) ;
    /// lot 3, T8 : `JOLENE_DEMO_BROUILLON=<variante>` (`VarianteBrouillonDemo`) simule un brouillon serveur au démarrage
    /// du parcours ; lot 3, T11 : `JOLENE_FORCE_EXPORT_ECHEC=1` fait refuser l'export RGPD
    /// avec le message serveur verbatim (`DemoCompteLot3Tests.testExportRefuseParLeServeurAfficheLeMessageSansFeuille`) ;
    /// lot 3, T12 : `JOLENE_FORCE_REVENUS_ECHEC=1` fait échouer la première lecture des missions terminées
    /// (`DemoRevenusEchecGateway`, `DemoRevenusTests.testErreurPuisReprise`).
    /// Jamais compilé en Release.
    private static func demoGateways(arguments: [String], processEnvironment: [String: String]) -> Gateways {
        #if DEBUG
        var gateways = DemoWorld.gateways(drapeaux: DemoFlagsGateway.surcharges(arguments: arguments))
        // Lot 2 T4b : `-JOLENE_DEMO_SCENARIO scan-incertain` (premier scan appliqué, réponse perdue, réconciliation) ;
        // seconde revue fraîche (m2) : `session-expiree-scan`, `session-expiree-consentement` (pointage et authentification
        // démo liés : « Vérifier ma session » revalide), `consentement-echec`.
        DemoPointageGateway.Scenario(arguments: arguments).installer(dans: &gateways)
        // Lot 3, T7 ; T8. Fusion des lots 2 et 3 : le scénario de pointage ci-dessus peut remplacer l'authentification
        // démo (`ExpirationSessionDemo`) ; l'inscription démo est donc liée APRÈS lui, à l'authentification effectivement
        // servie (mêmes `store` et `comptes` : la connexion par mot de passe retrouve le compte créé).
        let refusInscription = RefusInscriptionDemo(arguments: arguments)
        let brouillonInscription = processEnvironment[VarianteBrouillonDemo.variableEnvironnement]
            .flatMap(VarianteBrouillonDemo.init(rawValue:))
        if let auth = gateways.auth as? DemoAuthGateway {
            gateways.inscription = DemoInscriptionGateway(auth: auth, refus: refusInscription,
                                                          brouillon: brouillonInscription) // lot 3, T7 ; T8
        }
        if processEnvironment["JOLENE_FORCE_ACCUEIL_ECHEC"] == "1" {
            gateways.dashboard = DemoDashboardEchecGateway()
        } else if processEnvironment[DemoDashboardGateway.variableOubliPointage] == "1" {
            gateways.dashboard = DemoDashboardGateway(missionsOubliees: 1) // lot 3, T3b (revue B8, m4)
        }
        let scenarioDocuments = ScenarioDocumentsDemo(arguments: arguments)
        if scenarioDocuments != .normal {
            gateways.documents = DemoDocumentsGateway(scenario: scenarioDocuments)
        }
        // Lot 2 T5a : `-JOLENE_DEMO_SCENARIO accueil-pointage` → mission du jour à pointer et départ oublié sur l'Accueil
        // (widget « Aller pointer », bandeau d'oubli de départ ; `DemoPresenceDetailTests`).
        if ScenarioAccueilDemo(arguments: arguments) == .pointage, processEnvironment["JOLENE_FORCE_ACCUEIL_ECHEC"] != "1" {
            gateways.dashboard = DemoDashboardGateway(scenario: .pointage)
        }
        // Lot 2 T9b : `-JOLENE_DEMO_SCENARIO otp-expire` (tout code refusé `OTP_EXPIRE`) ou `compte-test` (compte TEST
        // sans admission : renvoi web de la signature), `DemoSignatureContratTests`.
        let scenarioContrats = ScenarioDemoContrats(arguments: arguments)
        if scenarioContrats != .nominal {
            gateways.contrats = DemoContratsGateway(scenario: scenarioContrats)
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
        if processEnvironment[DemoRevenusEchecGateway.variableEnvironnement] == "1" {
            gateways.revenus = DemoRevenusEchecGateway() // lot 3, T12 (`DemoRevenusTests.testErreurPuisReprise`)
        }
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

    /// Lot 3, T10 (revue B8, M1) : scénario de l'avatar démo. DEBUG seulement : `-JOLENE_DEMO_AVATAR` ; sinon (et
    /// toujours en Release) aucun.
    private static func scenarioAvatarDemo(arguments: [String]) -> ScenarioAvatarDemo? {
        #if DEBUG
        return ScenarioAvatarDemo(arguments: arguments)
        #else
        return nil
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
