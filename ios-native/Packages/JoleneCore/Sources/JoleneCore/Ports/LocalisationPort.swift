import Foundation

// Localisation ponctuelle du profil (lot 3, T10 ; blueprint `LOT3_PLAN.md` §3 T10, D12, D15). Port MINIMAL : le
// blueprint v2 réutilise `LocationPort` du lot 2 (`Ports/AppareilPorts.swift`, `Appareil.localisation`, L2-T1 et
// L2-T4b), absent de la base du lot 3 quand T10 a été livrée ; T10 l'a donc servi par une implémentation réelle isolée
// dans la cible app, nommée pour être supprimée à la fusion des lots.
//
// Fusion des lots 2 et 3 (point de fusion consigné dans `docs/mobile-swift/DECISIONS_LOT3.md`, section T10) :
// l'implémentation isolée est supprimée ; ce port est servi par `LocalisationProfilAppareil` (ci-dessous), adaptateur de
// quelques lignes sur `Appareil.localisation` (`autorisation()` → `demanderAutorisation()` si `.nonDeterminee`, attente
// bornée à `LocalisationPolicy.delaiAutorisationProfil` → `positionUnique(delai:)` ; `ObservationGps.disponible` →
// `.disponible`, `.refusee` → `.refusee`, `.precisionReduite` → `LocalisationPolicy.issuePrecisionReduite`
// (`.indisponible`), le reste → `.indisponible`). Un seul service de localisation dans l'app : `LocationService` du lot 2.
// Les noms de ce fichier ne recouvrent aucun type du lot 2 (`LocationPort`, `AutorisationPosition`, `ObservationGps`,
// `DemoLocationPort`, `LocationPolicy`). Verrou : `FusionLocalisationLot2Tests` (aucune implémentation provisoire ni
// référence à elle une fois le port du lot 2 présent ; correspondance des issues de l'adaptateur).

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

    /// Issue du profil quand l'utilisateur n'a accordé que la position APPROXIMATIVE (« Position exacte » coupée).
    /// Décision du 09/11/2026 (`DECISIONS_LOT3.md`, « Décisions déléguées du 8 novembre 2026 ») : aucune coordonnée
    /// n'est demandée ni transmise, issue `.indisponible` (message du web, saisie manuelle de la ville), comme
    /// `ObservationGps.precisionReduite` du lot 2, qui ne porte aucune coordonnée (décision 5 du lot 2) et que
    /// l'adaptateur de la fusion traduira de la même façon : le comportement ne change pas à la fusion.
    public static let issuePrecisionReduite: PositionPonctuelle = .indisponible

    /// Attente bornée de la réponse à la feuille système d'autorisation (revue B8 de T10, m12) : au-delà, la demande
    /// rend `.indisponible` ; une réponse donnée plus tard vaut pour l'appui suivant.
    public static let delaiAutorisationProfil: TimeInterval = 60
}

// MARK: - Adaptateur sur le port du lot 2 (fusion des lots 2 et 3)

/// `LocalisationPort` servi par `Appareil.localisation` (`LocationPort` du lot 2 : `LocationService` en staging et en
/// production). Même comportement que l'implémentation isolée de T10 qu'il remplace : autorisation « Lorsque l'app est
/// active » demandée sur l'appui seulement si elle ne l'a jamais été, attente de la réponse bornée
/// (`delaiAutorisation`, revue B8 de T10, m12 : au-delà, `.indisponible`, et une réponse donnée plus tard vaut pour
/// l'appui suivant), aucune position demandée en précision réduite (m1), une position unique bornée à `delai`. Ne lève
/// jamais, ne journalise rien.
public struct LocalisationProfilAppareil: LocalisationPort {
    private let localisation: LocationPort
    private let delaiAutorisation: TimeInterval

    public init(localisation: LocationPort, delaiAutorisation: TimeInterval = LocalisationPolicy.delaiAutorisationProfil) {
        self.localisation = localisation
        self.delaiAutorisation = delaiAutorisation
    }

    public func localiser(delai: TimeInterval) async -> PositionPonctuelle {
        if await localisation.autorisation() == .nonDeterminee {
            let localisation = self.localisation
            await AttenteBornee.attendre(delai: delaiAutorisation) { await localisation.demanderAutorisation() }
        }
        switch await localisation.autorisation() {
        case .nonDeterminee: return .indisponible
        case .refusee: return .refusee
        case .accordee(precise: false): return LocalisationPolicy.issuePrecisionReduite
        case .accordee(precise: true): break
        }
        return Self.issue(await localisation.positionUnique(delai: delai))
    }

    /// Correspondance des issues du lot 2 vers celles du profil (`DECISIONS_LOT3.md`, section T10, point 1).
    public static func issue(_ observation: ObservationGps) -> PositionPonctuelle {
        switch observation {
        case let .disponible(latitude, longitude, _): return .disponible(latitude: latitude, longitude: longitude)
        case .refusee: return .refusee
        case .precisionReduite: return LocalisationPolicy.issuePrecisionReduite
        case .indisponible: return .indisponible
        }
    }
}

/// Attente d'une opération bornée à `delai` secondes : rend dès que l'opération finit ou que le délai expire, le
/// premier des deux l'emportant (reprise unique). L'opération n'est pas annulée : une réponse tardive à la feuille
/// d'autorisation reste acquise pour la demande suivante.
enum AttenteBornee {
    static func attendre(delai: TimeInterval, _ operation: @escaping @Sendable () async -> Void) async {
        let issue = IssueUnique()
        await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
            Task { await issue.poser(suite) }
            Task {
                await operation()
                await issue.conclure()
            }
            Task {
                let secondes = max(0, min(delai.isFinite ? delai : 600, 600))
                try? await Task.sleep(nanoseconds: UInt64(secondes * 1_000_000_000))
                await issue.conclure()
            }
        }
    }

    /// Reprise unique d'une suite, quel que soit l'ordre d'arrivée de la suite et des conclusions.
    private actor IssueUnique {
        private var suite: CheckedContinuation<Void, Never>?
        private var conclue = false

        func poser(_ suite: CheckedContinuation<Void, Never>) {
            if conclue { suite.resume() } else { self.suite = suite }
        }

        func conclure() {
            guard !conclue else { return }
            conclue = true
            suite?.resume()
            suite = nil
        }
    }
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
