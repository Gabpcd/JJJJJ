import Foundation

// Scénarios DEBUG de l'appareil et du pointage démo (blueprint lot 2 §2.2, §2.8 ; tranche T4b), lus par `AppContainer`
// dans les arguments de lancement (`-NOM valeur`, comme `-JOLENE_DEMO_SOURCE_DOC`). Une valeur absente ou inconnue
// retombe sur le scénario nominal ; aucun prompt système, aucun réseau.

extension ScenarioGpsDemo {
    public static let argument = "-JOLENE_DEMO_GPS"

    /// Valeur qui suit `-JOLENE_DEMO_GPS` (`accorde`, `refuse`, `indisponible`, `reduite`) ; défaut `.accorde`.
    public init(arguments: [String]) {
        self = ArgumentsDemo.valeur(Self.argument, dans: arguments).flatMap(ScenarioGpsDemo.init(rawValue:)) ?? .accorde
    }
}

extension ScenarioReseauDemo {
    public static let argument = "-JOLENE_DEMO_RESEAU"

    /// Valeur qui suit `-JOLENE_DEMO_RESEAU` (`enligne`, `horsligne`) ; défaut `.enLigne`.
    public init(arguments: [String]) {
        self = ArgumentsDemo.valeur(Self.argument, dans: arguments).flatMap(ScenarioReseauDemo.init(rawValue:)) ?? .enLigne
    }
}

extension DemoPointageGateway.Scenario {
    public static let argument = "-JOLENE_DEMO_SCENARIO"

    /// Valeur qui suit `-JOLENE_DEMO_SCENARIO` ; celle d'un autre domaine (`upload-incertain`, `otp-expire`) : `.normal`.
    public init(arguments: [String]) {
        self = ArgumentsDemo.valeur(Self.argument, dans: arguments).flatMap(DemoPointageGateway.Scenario.init(rawValue:)) ?? .normal
    }

    /// Ports du monde démo pour ce scénario (DEBUG, `AppContainer.demoGateways`) : le pointage du scénario et une
    /// authentification démo qui partagent la même `ExpirationSessionDemo`, pour que « Vérifier ma session »
    /// (`SessionController.start` → `restoreSession`) revalide la session expirée par le scénario (seconde revue fraîche
    /// de T4b, m2). `.normal` ne change rien. À appeler avant la connexion (l'authentification démo repart vierge).
    public func installer(dans gateways: inout Gateways) {
        guard self != .normal else { return }
        let expiration = ExpirationSessionDemo()
        gateways.auth = DemoAuthGateway(expiration: expiration)
        gateways.pointage = DemoPointageGateway(clock: FixedClock(DemoWorld.fixedNow), scenario: self, expiration: expiration)
    }
}

/// Session démo expirée côté « serveur » (scénarios DEBUG `session-expiree-scan` et `session-expiree-consentement`) :
/// tant qu'elle est expirée, `DemoPointageGateway` répond 401 à tout appel ; `DemoAuthGateway.restoreSession` la revalide
/// quand une session est ouverte (« Vérifier ma session »). En mémoire seulement.
public actor ExpirationSessionDemo {
    public private(set) var expiree = false

    public init() {}

    public func expirer() {
        expiree = true
    }

    public func revalider() {
        expiree = false
    }
}

extension DemoFlagsGateway {
    /// Préfixe des surcharges de drapeaux d'écran du monde démo (DEBUG, lues par `AppContainer`) :
    /// `-JOLENE_FLAG_<cle> true|false`, par exemple `-JOLENE_FLAG_ios_natif_presences_actif false` (coupe-circuit D-FLAGS,
    /// seconde revue fraîche de T4b, m3).
    public static let prefixeArgument = "-JOLENE_FLAG_"

    /// Surcharges lues dans les arguments de lancement ; une clé vide, une valeur absente ou autre que `true` / `false`
    /// est ignorée (le drapeau garde son défaut fail-open).
    public static func surcharges(arguments: [String]) -> [String: Bool] {
        var surcharges: [String: Bool] = [:]
        for (index, argument) in arguments.enumerated() where argument.hasPrefix(prefixeArgument) && index + 1 < arguments.count {
            let cle = String(argument.dropFirst(prefixeArgument.count))
            guard !cle.isEmpty else { continue }
            switch arguments[index + 1] {
            case "true": surcharges[cle] = true
            case "false": surcharges[cle] = false
            default: continue
            }
        }
        return surcharges
    }
}

/// QR lu par le scanner démo (`DemoQRScannerView`, `-JOLENE_DEMO_QR`) : un payload, détecté deux fois (preuve « une seule
/// remise par session »), ou un refus de la caméra.
public enum ScenarioQRDemo: Equatable, Sendable {
    case lecture(String)
    case refus

    public static let argument = "-JOLENE_DEMO_QR"
    /// Payload d'un QR étranger (jamais six chiffres) : « QR non reconnu… », caméra conservée.
    public static let payloadIllisible = "JOLENE-DEMO-QR"

    /// `-JOLENE_DEMO_QR <payload | illisible | refus>` ; défaut : le code affiché de la mission a (`123456`).
    public init(arguments: [String]) {
        switch ArgumentsDemo.valeur(Self.argument, dans: arguments) {
        case "refus"?: self = .refus
        case "illisible"?: self = .lecture(Self.payloadIllisible)
        case let valeur?: self = .lecture(valeur)
        case nil: self = .lecture("123456")
        }
    }

    /// Payloads remis par le scanner démo, dans l'ordre.
    public var detections: [String] {
        switch self {
        case let .lecture(payload): return [payload, payload]
        case .refus: return []
        }
    }
}
