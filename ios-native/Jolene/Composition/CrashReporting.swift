import Foundation
import JoleneCore
import Sentry

/// Lot 3, T15 (D21, blueprint `LOT3_PLAN.md` §3 T15, `docs/mobile-swift/SENTRY_IOS.md`) — rapport de crash Sentry Cocoa
/// (crashs et app hangs, sans PII). Seul fichier du dépôt qui importe Sentry (garde `CrashReportingTests`).
///
/// Démarré par `JoleneApp.init`, AVANT le conteneur, sur la même lecture de l'environnement que lui
/// (`AppContainer.environnementDeLancement`, surcharges DEBUG comprises) ; la décision est celle de JoleneCore
/// (`ConfigurationCrash.auLancement`) : jamais en démo, jamais sans DSN (`JoleneSentryDSN` vide dans le dépôt), jamais
/// pour un environnement refusé. Le port rendu (nil sinon) est remis à la session (`SessionStore`) par le conteneur, en
/// staging et en production seulement : identifiant utilisateur sur `.ready`, retiré hors d'un espace prêt.
@MainActor
enum CrashReporting {
    /// Délai du crash de test après le démarrage : Sentry a installé ses gestionnaires et l'app a fini son lancement.
    static let delaiCrashTest: TimeInterval = 2

    /// Démarre Sentry si la configuration le permet ; rend le port à remettre à la session, ou nil.
    /// DEBUG : `-JOLENE_SENTRY_CRASH_TEST` provoque un crash de test, une fois, si Sentry a démarré (jamais en démo).
    static func demarrerAuLancement(arguments: [String] = CommandLine.arguments,
                                    processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
                                    info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> CrashReportingPort? {
        let environnement = AppContainer.environnementDeLancement(arguments: arguments, processEnvironment: processEnvironment,
                                                                  info: info)
        let configuration = ConfigurationCrash.auLancement(environnement: environnement, info: info)
        let port = ConfigurationCrash.demarrer(configuration) { SentryCrashReporting(dsn: $0.dsn) }
        #if DEBUG
        if ConfigurationCrash.crashTestDemande(arguments: arguments, configuration: configuration) {
            // Lancement sans débogueur attaché (un débogueur intercepte le crash) ; l'événement part à la relance suivante.
            DispatchQueue.main.asyncAfter(deadline: .now() + delaiCrashTest) { SentrySDK.crash() }
        }
        #endif
        return port
    }
}

/// Adaptateur Sentry de `CrashReportingPort`. Le DSN n'est jamais journalisé.
struct SentryCrashReporting: CrashReportingPort {
    let dsn: String

    func demarrer(environnement: JoleneMode, release: String) {
        let dsn = self.dsn
        SentrySDK.start { options in
            Self.configurer(options, dsn: dsn, environnement: environnement, release: release)
        }
    }

    /// Identifiant seul (ni e-mail, ni nom, ni adresse IP) ; nil hors d'un espace prêt (`SessionStore`).
    func utilisateur(id: String?) {
        SentrySDK.setUser(id.map { User(userId: $0) })
    }

    /// Réglages de `ConfigurationCrash.reglages` appliqués un à un (garde `CrashReportingTests`).
    static func configurer(_ options: Options, dsn: String, environnement: JoleneMode, release: String) {
        let reglages = ConfigurationCrash.reglages
        options.dsn = dsn
        options.environment = environnement.rawValue
        options.releaseName = release
        options.sendDefaultPii = reglages.sendDefaultPii
        options.attachScreenshot = reglages.attachScreenshot
        options.attachViewHierarchy = reglages.attachViewHierarchy
        options.enableNetworkBreadcrumbs = reglages.enableNetworkBreadcrumbs
        options.enableCaptureFailedRequests = reglages.enableCaptureFailedRequests
        options.enableNetworkTracking = reglages.enableNetworkTracking
        options.tracePropagationTargets = reglages.tracePropagationTargets
        options.tracesSampleRate = NSNumber(value: reglages.tracesSampleRate)
        options.enableAutoSessionTracking = reglages.enableAutoSessionTracking
        options.enableAppHangTracking = reglages.enableAppHangTracking
        options.sessionReplay.sessionSampleRate = reglages.sessionReplaySessionSampleRate
        options.sessionReplay.onErrorSampleRate = reglages.sessionReplayOnErrorSampleRate
        options.beforeSend = { event in nettoyer(event) }
        options.beforeBreadcrumb = { fil in nettoyer(fil) }
    }

    /// `beforeSend` : chaque texte et chaque dictionnaire de l'événement passe par `CrashScrubber` ; ni requête, ni nom de
    /// serveur, ni autre donnée utilisateur que l'identifiant. Chaque propriété publique d'`Event`, `SentryMessage`,
    /// `Exception`, `Mechanism` et `Breadcrumb` (Sentry 9.32.0) est traitée ici ou conservée pour une raison écrite :
    /// recensement et garde statique dans `CrashReportingTests` (revue B8 n°1, M1 et m3).
    static func nettoyer(_ event: Event) -> Event? {
        if let message = event.message {
            let propre = SentryMessage(formatted: CrashScrubber.texte(message.formatted))
            propre.message = message.message.map(CrashScrubber.texte)
            propre.params = message.params?.map(CrashScrubber.texte)
            event.message = propre
        }
        event.exceptions?.forEach { nettoyer($0) }
        event.breadcrumbs = event.breadcrumbs?.compactMap { nettoyer($0) }
        event.tags = event.tags.map(CrashScrubber.etiquettes)
        event.extra = event.extra.map(CrashScrubber.dictionnaire)
        event.context = event.context.map(CrashScrubber.contextes)
        event.transaction = event.transaction.map(CrashScrubber.texte)
        event.fingerprint = event.fingerprint?.map(CrashScrubber.texte)
        event.logger = event.logger.map(CrashScrubber.texte)
        event.request = nil
        event.serverName = nil
        event.user = event.user?.userId.map { User(userId: $0) }
        return event
    }

    /// Exception (crash, `NSException`, app hang) : valeur, type et mécanisme nettoyés. Sentry 9.32.0 range dans
    /// `mechanism.data` les `crash_info_messages` (messages du runtime Swift, texte d'un `fatalError` compris :
    /// `SentryCrashReportConverter.m` l.501-511), et `mechanism.desc` est un texte libre.
    static func nettoyer(_ exception: Exception) {
        exception.value = exception.value.map(CrashScrubber.texte)
        exception.type = exception.type.map(CrashScrubber.texte)
        guard let mecanisme = exception.mechanism else { return }
        mecanisme.desc = mecanisme.desc.map(CrashScrubber.texte)
        mecanisme.data = mecanisme.data.map(CrashScrubber.dictionnaire)
    }

    /// `beforeBreadcrumb` : fils d'Ariane réseau rejetés, message et données nettoyés.
    static func nettoyer(_ fil: Breadcrumb) -> Breadcrumb? {
        guard CrashScrubber.filConserve(categorie: fil.category, type: fil.type) else { return nil }
        fil.message = fil.message.map(CrashScrubber.texte)
        // Chaque clé est réécrite par `setData(value:key:)` (le setter de `data` est déprécié) ; aucune n'est ajoutée.
        for (cle, valeur) in CrashScrubber.dictionnaire(fil.data ?? [:]) { fil.setData(value: valeur, key: cle) }
        return fil
    }
}
