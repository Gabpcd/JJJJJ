import Foundation

// Localisation ponctuelle du profil (lot 3, T10 ; blueprint `LOT3_PLAN.md` §3 T10, D12, D15). Port MINIMAL et
// PROVISOIRE : le blueprint v2 réutilise `LocationPort` du lot 2 (`Ports/AppareilPorts.swift`, `Appareil.localisation`,
// L2-T1 et L2-T4b), qui n'est pas sur la base du lot 3 (`feat/ios-lot2`). Aucun second service de localisation n'est
// créé : un seul appel, une seule implémentation réelle isolée dans la cible app (`LocalisationProfilProvisoire`,
// `Jolene/Composition/LocalisationProfilProvisoire.swift`), nommée pour être remplacée à la fusion des lots.
//
// Point de fusion (consigné dans `docs/mobile-swift/DECISIONS_LOT3.md`, section T10) : à l'arrivée du lot 2,
// `LocalisationProfilProvisoire` est supprimée et ce port est servi par un adaptateur de quelques lignes sur
// `Appareil.localisation` (`autorisation()` → `demanderAutorisation()` si `.nonDeterminee` → `positionUnique(delai:)`,
// `ObservationGps.disponible` → `.disponible`, `.refusee` → `.refusee`, le reste → `.indisponible`). Les noms de ce
// fichier ne recouvrent aucun type du lot 2 (`LocationPort`, `AutorisationPosition`, `ObservationGps`,
// `DemoLocationPort`, `LocationPolicy`) : la fusion ne produit aucune double déclaration.

/// Issue d'une demande de position unique pour le profil. Seule `.disponible` porte des coordonnées ; elles ne
/// sont jamais affichées ni journalisées (blueprint §2.6) : la description du cas les masque.
public enum PositionPonctuelle: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case disponible(latitude: Double, longitude: Double)
    /// Autorisation refusée ou restreinte (réglages, contrôle parental).
    case refusee
    /// Aucune position dans le délai, service coupé, erreur du système.
    case indisponible

    public var description: String {
        switch self {
        case .disponible: return "PositionPonctuelle.disponible(position masquée)"
        case .refusee: return "PositionPonctuelle.refusee"
        case .indisponible: return "PositionPonctuelle.indisponible"
        }
    }

    public var debugDescription: String { description }
}

/// Position du profil, sur appui de l'utilisateur seulement (« Utiliser ma position actuelle »), comme le web
/// (`SectionProfilPrincipal.tsx` l.625-643 → `src/lib/geoloc.ts` l.71-101) : l'autorisation « lorsque l'app est
/// active » est demandée si elle ne l'a jamais été, puis une position unique est attendue au plus `delai` secondes.
/// Ne lève jamais : toute erreur du système est `.indisponible`.
public protocol LocalisationPort: Sendable {
    func localiser(delai: TimeInterval) async -> PositionPonctuelle
}

public enum LocalisationPolicy {
    /// `obtenirGeoloc({ enableHighAccuracy: true, timeout: 15_000 })` (`SectionProfilPrincipal.tsx` l.628).
    public static let delaiProfil: TimeInterval = 15
}

// MARK: - Démo

/// Valeurs de l'argument DEBUG `-JOLENE_DEMO_LOCALISATION` (lu par `AppContainer`, démo seulement).
public enum ScenarioLocalisationDemo: String, CaseIterable, Sendable {
    case accordee, refusee, indisponible

    public static let argument = "-JOLENE_DEMO_LOCALISATION"

    /// Scénario demandé au lancement ; nil si l'argument est absent ou inconnu (le défaut `.accordee` s'applique).
    public init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: Self.argument), arguments.indices.contains(index + 1),
              let scenario = ScenarioLocalisationDemo(rawValue: arguments[index + 1]) else { return nil }
        self = scenario
    }
}

/// Localisation du monde démo : aucune feuille système, aucun réseau. Position fixe place Bellecour (Lyon), distincte
/// de celle du profil fictif (Paris), pour que l'enregistrement change réellement la position relue.
public actor DemoLocalisationProfil: LocalisationPort {
    public static let latitudeDemo = 45.7578
    public static let longitudeDemo = 4.832

    private let scenario: ScenarioLocalisationDemo
    /// Nombre de demandes reçues (tests).
    public private(set) var demandes = 0

    public init(scenario: ScenarioLocalisationDemo = .accordee) {
        self.scenario = scenario
    }

    public func localiser(delai: TimeInterval) -> PositionPonctuelle {
        demandes += 1
        switch scenario {
        case .accordee: return .disponible(latitude: Self.latitudeDemo, longitude: Self.longitudeDemo)
        case .refusee: return .refusee
        case .indisponible: return .indisponible
        }
    }
}
