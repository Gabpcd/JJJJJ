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
