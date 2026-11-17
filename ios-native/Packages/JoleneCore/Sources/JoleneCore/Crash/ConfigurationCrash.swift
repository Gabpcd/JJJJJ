import Foundation

/// Lot 3, T15 (D21, blueprint `LOT3_PLAN.md` §3 T15, `docs/mobile-swift/SENTRY_IOS.md`) — décision de démarrage du
/// rapport de crash et réglages, sans Sentry (importé par la cible app seulement, `Jolene/Composition/CrashReporting.swift`).
///
/// Sentry ne démarre que si **tout** est réuni : mode `staging` ou `production` accepté par la garde d'environnement
/// (jamais en démo, jamais pour un mode inconnu ou un environnement refusé, qui n'ouvrent que l'écran bloquant), DSN
/// `https` bien formé dans l'Info.plist (clé `JoleneSentryDSN`, alimentée par le réglage xcconfig `JOLENE_SENTRY_DSN`,
/// vide dans le dépôt), release lisible dans le bundle. Sinon : aucun adaptateur construit, aucun service démarré.
///
/// Le DSN n'est jamais restitué par une description, un `dump` ou un journal (`CustomStringConvertible`,
/// `CustomReflectable`).
public struct ConfigurationCrash: Equatable, Sendable {
    /// Clé de l'Info.plist qui porte le DSN (`$(JOLENE_SENTRY_DSN)`).
    public static let cleDSN = "JoleneSentryDSN"
    /// Argument de lancement DEBUG : un crash de test (`SentrySDK.crash()`) si Sentry a démarré (critère « Sentry reçoit
    /// un crash de test taggé release 2.0.0 (25) », lu en T17).
    public static let argumentCrashTest = "-JOLENE_SENTRY_CRASH_TEST"
    /// Réglages appliqués tels quels par l'adaptateur Sentry.
    public static let reglages = ReglagesCrash()

    public let dsn: String
    /// Environnement Sentry = mode de l'app (`staging`, `production`).
    public let environnement: JoleneMode
    /// `<CFBundleIdentifier>@<CFBundleShortVersionString>+<CFBundleVersion>`, par exemple `app.jolene@2.0.0+25`.
    public let release: String

    /// Configuration du lancement, ou nil : Sentry reste désactivé.
    public static func auLancement(environnement: JoleneEnvironment, info: [String: Any]) -> ConfigurationCrash? {
        guard environnement.mode != .demo, environnement.unknownModeRaw == nil else { return nil }
        guard (try? environnement.validate()) != nil else { return nil }
        guard let dsn = dsnValide(info[cleDSN]), let release = nomDeRelease(info: info) else { return nil }
        return ConfigurationCrash(dsn: dsn, environnement: environnement.mode, release: release)
    }

    /// Construit l'adaptateur par `fabrique` et le démarre, une fois ; sans configuration, `fabrique` n'est jamais appelée.
    @discardableResult
    public static func demarrer(_ configuration: ConfigurationCrash?,
                                fabrique: (ConfigurationCrash) -> CrashReportingPort) -> CrashReportingPort? {
        guard let configuration else { return nil }
        let port = fabrique(configuration)
        port.demarrer(environnement: configuration.environnement, release: configuration.release)
        return port
    }

    /// Vrai si le crash de test est demandé ET Sentry démarré (sinon l'argument est ignoré : l'app ne plante jamais en démo
    /// ni sans DSN). L'appelant ne le consulte qu'en DEBUG.
    public static func crashTestDemande(arguments: [String], configuration: ConfigurationCrash?) -> Bool {
        configuration != nil && arguments.contains(argumentCrashTest)
    }

    /// Release lue dans le bundle, jamais codée en dur ; nil si une clé manque ou n'est pas résolue.
    public static func nomDeRelease(info: [String: Any]) -> String? {
        let valeurs = ["CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"].map {
            ((info[$0] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard valeurs.allSatisfy({ !$0.isEmpty && !$0.contains("$(") && !$0.contains(" ") }) else { return nil }
        return "\(valeurs[0])@\(valeurs[1])+\(valeurs[2])"
    }

    /// DSN `https://<clé publique>@<hôte>/<projet>` débarrassé des blancs ; nil s'il est vide, non résolu ou mal formé, ou
    /// s'il porte un mot de passe (`<clé>:<secret>@`, ancien format à clé secrète ou valeur collée par erreur : revue B8
    /// n°1, m6). L'hôte n'est pas restreint à une région : la région de données de l'organisation reste à confirmer par
    /// Gabrielle (`SENTRY_IOS.md` §5), la restriction suivra.
    public static func dsnValide(_ brut: Any?) -> String? {
        guard let texte = (brut as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !texte.isEmpty,
              !texte.contains("$("), let composants = URLComponents(string: texte), composants.scheme == "https",
              let cle = composants.user, !cle.isEmpty, composants.password == nil, let hote = composants.host, !hote.isEmpty,
              composants.path.count > 1 else { return nil }
        return texte
    }
}

extension ConfigurationCrash: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "ConfigurationCrash(environnement: \(environnement.rawValue), release: \(release), dsn: \(CrashScrubber.masque))"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["environnement": environnement.rawValue, "release": release, "dsn": CrashScrubber.masque],
               displayStyle: .struct)
    }
}

/// Réglages Sentry du lot 3 (D21) : aucune PII, ni capture d'écran ni hiérarchie de vues, ni fil d'Ariane ni capture
/// des requêtes réseau, traces à 0 ; sessions automatiques et app hangs conservés. Au-delà du blueprint
/// (`SENTRY_IOS.md`) : ni instrumentation des requêtes réseau ni en-tête de trace envoyé aux hôtes appelés, relecture de
/// session coupée explicitement. Noms identiques aux options Sentry, appliqués un à un par la cible app.
public struct ReglagesCrash: Equatable, Sendable {
    public let sendDefaultPii = false
    public let attachScreenshot = false
    public let attachViewHierarchy = false
    public let enableNetworkBreadcrumbs = false
    public let enableCaptureFailedRequests = false
    public let enableNetworkTracking = false
    public let tracePropagationTargets: [String] = []
    public let tracesSampleRate: Double = 0
    /// Défaut de Sentry, conservé explicitement : le lot 4 mesure le taux de sessions sans crash (≥ 99,5 %).
    public let enableAutoSessionTracking = true
    public let enableAppHangTracking = true
    public let sessionReplaySessionSampleRate: Float = 0
    public let sessionReplayOnErrorSampleRate: Float = 0

    public init() {}
}
