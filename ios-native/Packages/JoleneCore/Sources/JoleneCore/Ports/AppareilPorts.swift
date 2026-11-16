import Foundation

// Ports d'appareil du lot 2 (blueprint `docs/mobile-swift/LOT2_PLAN.md` §2.2, tranche T1). Ce ne sont pas
// des gateways backend : `Appareil` est injecté par `AppContainer` à côté de `Gateways`, avec une
// implémentation réelle (cible app, wrappers `@MainActor` de T4b ; Keychain : `KeychainTerminalIdentity` et
// `KeychainReceiptStore`, JoleneSupabase) et une démo (ci-dessous et `Receipts/ReceiptJournal.swift` : aucun
// prompt système, aucun réseau). Le protocole du magasin de reçus vit avec le journal (`ReceiptStorePort`,
// `Receipts/ReceiptJournal.swift`), pour que T7 du lot 1 le reprenne sans ce fichier. Méthodes `async` : une
// implémentation isolée au MainActor (CoreLocation) peut s'y conformer en concurrence stricte.

// MARK: - Position

/// Autorisation de position iOS « Lorsque l'app est active ». `precise: false` = précision réduite
/// (`accuracyAuthorization == .reducedAccuracy`, décision 5).
public enum AutorisationPosition: Equatable, Sendable {
    case nonDeterminee
    case refusee
    case accordee(precise: Bool)
}

/// Résultat d'une demande de position unique. Seul `.disponible` porte des coordonnées : un refus, une
/// indisponibilité ou une précision réduite donnent un scan sans GPS (décisions 4 et 5).
public enum ObservationGps: Equatable, Sendable {
    case disponible(latitude: Double, longitude: Double, precisionM: Double)
    case refusee
    case indisponible
    case precisionReduite
}

public protocol LocationPort: Sendable {
    func autorisation() async -> AutorisationPosition
    /// Demande l'autorisation iOS, seulement après un « Autoriser » sur le consentement verbatim (décision 4).
    func demanderAutorisation() async
    /// Position la plus récente postérieure à la demande, bornée à `delai` secondes ; ne lève jamais.
    func positionUnique(delai: TimeInterval) async -> ObservationGps
}

public enum LocationPolicy {
    /// Délai d'une position unique, comme le web (`src/lib/platform.ts` l.298 : `timeout: 15000`).
    public static let delaiPosition: TimeInterval = 15
}

// MARK: - Réseau

public protocol NetworkPathPort: Sendable {
    func estEnLigne() async -> Bool
    /// Changements d'état (vrai = en ligne). Hors ligne : aucun scan n'est envoyé ni mis en file (décision 2).
    func changements() -> AsyncStream<Bool>
}

// MARK: - Identifiant terminal (décision 7)

/// Identifiant du terminal envoyé dans `p_metadata.id_terminal` (stocké tel quel par le serveur,
/// `scans_pointage.id_terminal`). Une erreur de stockage lève `JoleneError(.environment)` sans jamais
/// produire un second identifiant.
public protocol TerminalIdentityPort: Sendable {
    func identifiant() throws -> String
}

/// Règles pures de l'identifiant terminal : `TERM_IOS_` + 20 caractères base32 (RFC 4648) aléatoires,
/// jamais `identifierForVendor` ni empreinte d'appareil.
public enum IdentifiantTerminal {
    public static let prefixe = "TERM_IOS_"
    public static let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    public static let longueurAleatoire = 20

    /// Vrai pour `^TERM_IOS_[A-Z2-7]{20}$` exactement.
    public static func estValide(_ valeur: String) -> Bool {
        guard valeur.hasPrefix(prefixe) else { return false }
        let suite = valeur.dropFirst(prefixe.count)
        return suite.count == longueurAleatoire && suite.allSatisfy { alphabet.contains($0) }
    }

    /// 100 bits d'aléa : chaque caractère prend les 5 bits de poids faible d'un tirage (sans biais,
    /// 32 divisant 2⁶⁴). `SystemRandomNumberGenerator` est cryptographiquement sûr sur les plateformes Apple.
    public static func generer<G: RandomNumberGenerator>(using generateur: inout G) -> String {
        let symboles = Array(alphabet)
        var suite = ""
        for _ in 0..<longueurAleatoire {
            suite.append(symboles[Int(truncatingIfNeeded: generateur.next() & 0x1F)])
        }
        return prefixe + suite
    }
}

// MARK: - Assemblage

/// Capacités d'appareil injectées à côté de `Gateways`, dont le magasin des reçus durables (`ReceiptStorePort`,
/// blueprint §2.2 ; livré par T1 du lot 2, décision 23) que lit et écrit `ReceiptJournal` : `KeychainReceiptStore`
/// (JoleneSupabase) en réel, `MagasinRecusEnMemoire` en démo.
public struct Appareil: Sendable {
    public var localisation: LocationPort
    public var reseau: NetworkPathPort
    public var terminal: TerminalIdentityPort
    public var recus: ReceiptStorePort

    public init(localisation: LocationPort, reseau: NetworkPathPort, terminal: TerminalIdentityPort,
                recus: ReceiptStorePort) {
        self.localisation = localisation; self.reseau = reseau; self.terminal = terminal; self.recus = recus
    }

    /// Appareil du mode démo (magasin de reçus vierge en mémoire) ; surcharges DEBUG `-JOLENE_DEMO_GPS` et
    /// `-JOLENE_DEMO_RESEAU` lues par `AppContainer` (T4b).
    public static func demo(gps: ScenarioGpsDemo = .accorde, reseau: ScenarioReseauDemo = .enLigne) -> Appareil {
        Appareil(localisation: DemoLocationPort(scenario: gps), reseau: DemoNetworkPathPort(scenario: reseau),
                 terminal: DemoTerminalIdentity(), recus: MagasinRecusEnMemoire())
    }
}

// MARK: - Démo

/// Valeurs de `-JOLENE_DEMO_GPS` (blueprint §2.2).
public enum ScenarioGpsDemo: String, CaseIterable, Sendable {
    case accorde, refuse, indisponible, reduite
}

/// Valeurs de `-JOLENE_DEMO_RESEAU` (blueprint §2.2).
public enum ScenarioReseauDemo: String, CaseIterable, Sendable {
    case enLigne = "enligne"
    case horsLigne = "horsligne"
}

/// Position démo : aucune décision avant `demanderAutorisation()` (comme iOS), puis l'issue du scénario ;
/// position à l'adresse du profil fictif (48.8566, 2.3522), précision 12 m. Aucun prompt système.
public actor DemoLocationPort: LocationPort {
    public static let precisionDemoM: Double = 12

    private let scenario: ScenarioGpsDemo
    private var decision: AutorisationPosition = .nonDeterminee
    /// Nombre de demandes d'autorisation reçues (tests).
    public private(set) var demandes = 0

    public init(scenario: ScenarioGpsDemo) {
        self.scenario = scenario
    }

    public func autorisation() -> AutorisationPosition { decision }

    public func demanderAutorisation() {
        demandes += 1
        switch scenario {
        case .accorde, .indisponible: decision = .accordee(precise: true)
        case .refuse: decision = .refusee
        case .reduite: decision = .accordee(precise: false)
        }
    }

    public func positionUnique(delai: TimeInterval) -> ObservationGps {
        guard case .accordee = decision else { return .refusee }
        switch scenario {
        case .accorde:
            return .disponible(latitude: DemoWorld.context.profile.adresseLat ?? 0,
                               longitude: DemoWorld.context.profile.adresseLng ?? 0, precisionM: Self.precisionDemoM)
        case .refuse: return .refusee
        case .indisponible: return .indisponible
        case .reduite: return .precisionReduite
        }
    }
}

/// Réseau démo figé : l'état du scénario, jamais de changement.
public struct DemoNetworkPathPort: NetworkPathPort {
    private let scenario: ScenarioReseauDemo

    public init(scenario: ScenarioReseauDemo) {
        self.scenario = scenario
    }

    public func estEnLigne() async -> Bool { scenario == .enLigne }

    public func changements() -> AsyncStream<Bool> {
        let enLigne = scenario == .enLigne
        return AsyncStream { continuation in
            continuation.yield(enLigne)
            continuation.finish()
        }
    }
}

/// Identifiant terminal démo constant (blueprint §2.2), au format des identifiants réels.
public struct DemoTerminalIdentity: TerminalIdentityPort {
    public static let identifiantDemo = "TERM_IOS_DEMODEMODEMODEMODEMO"

    public init() {}

    public func identifiant() throws -> String { Self.identifiantDemo }
}
