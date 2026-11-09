import Foundation

/// Position reçue de l'appareil (valeurs d'une `CLLocation`, extraites dans la cible app : aucun import de CoreLocation
/// ici). `precision` est l'`horizontalAccuracy` : négative = position invalide. Jamais décrite ni journalisée
/// (`LOT2_PLAN.md` §2.7 : aucune coordonnée dans un journal).
public struct FixPosition: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let latitude: Double
    public let longitude: Double
    public let precision: Double
    public let instant: Date

    public init(latitude: Double, longitude: Double, precision: Double, instant: Date) {
        self.latitude = latitude; self.longitude = longitude; self.precision = precision; self.instant = instant
    }

    public var description: String { "FixPosition(masquée)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// Échec signalé par l'appareil (`CLError`, traduit dans la cible app).
public enum EchecPosition: Equatable, Sendable {
    /// `locationUnknown` : transitoire, la recherche continue jusqu'au délai.
    case transitoire
    /// `denied` : autorisation retirée pendant la demande.
    case refus
    /// Toute autre erreur.
    case autre
}

/// Demande de position unique du pointage (revue fraîche de T4b, m8) : logique de `LocationService` (cible app), extraite
/// pour être testée sans CoreLocation (`DemandePositionTests`). Une seule demande ouverte à la fois ; sa suite (`rendre`,
/// une `CheckedContinuation` dans l'app) est reprise UNE fois exactement — position admissible, précision réduite, refus,
/// erreur, expiration au délai du web ou nouvelle demande — puis la demande est close (toute reprise ultérieure est sans
/// effet). Position admissible : la plus récente de valide (précision ≥ 0) postérieure à la demande à `tolerance` près
/// (une position en cache, plus ancienne, est ignorée : parité du `maximumAge` implicite de 0 du web, `src/lib/platform.ts`
/// l.298). Précision réduite (`precise == false`) : `.precisionReduite`, aucune coordonnée (décision 5).
@MainActor
public final class DemandesPosition {
    /// `timeout: 15000` du web (`src/lib/platform.ts` l.298).
    public nonisolated static let delai: TimeInterval = LocationPolicy.delaiPosition
    /// Écart admis entre l'instant d'une position et celui de la demande (horodatage de CoreLocation à la seconde près).
    public nonisolated static let tolerance: TimeInterval = 1

    private struct Ouverte {
        let jeton: UUID
        let debut: Date
        let rendre: @MainActor (ObservationGps) -> Void
    }

    private var ouverte: Ouverte?

    public init() {}

    /// Une demande attend une issue.
    public var enCours: Bool { ouverte != nil }

    /// Ouvre une demande ; une précédente encore ouverte est close `.indisponible` (jamais laissée en attente). Rend le
    /// jeton de l'expiration.
    public func ouvrir(debut: Date, rendre: @escaping @MainActor (ObservationGps) -> Void) -> UUID {
        terminer(.indisponible)
        let jeton = UUID()
        ouverte = Ouverte(jeton: jeton, debut: debut, rendre: rendre)
        return jeton
    }

    /// Positions reçues : close la demande avec la position admissible, ou `.precisionReduite` ; nil si rien n'est conclu.
    @discardableResult
    public func recevoir(_ fixes: [FixPosition], precise: Bool) -> ObservationGps? {
        guard let ouverte else { return nil }
        guard precise else { return terminer(.precisionReduite) }
        guard let fix = Self.selection(fixes, depuis: ouverte.debut) else { return nil }
        return terminer(.disponible(latitude: fix.latitude, longitude: fix.longitude, precisionM: fix.precision))
    }

    /// Erreur de l'appareil : transitoire → on continue ; refus → `.refusee` ; sinon `.indisponible`.
    @discardableResult
    public func echouer(_ echec: EchecPosition) -> ObservationGps? {
        switch echec {
        case .transitoire: return nil
        case .refus: return terminer(.refusee)
        case .autre: return terminer(.indisponible)
        }
    }

    /// Délai écoulé pour la demande `jeton` : `.indisponible` si elle est encore ouverte, sinon rien.
    @discardableResult
    public func expirer(_ jeton: UUID) -> ObservationGps? {
        guard ouverte?.jeton == jeton else { return nil }
        return terminer(.indisponible)
    }

    /// Close la demande ouverte (reprise unique) ; nil si aucune.
    @discardableResult
    public func terminer(_ observation: ObservationGps) -> ObservationGps? {
        guard let courante = ouverte else { return nil }
        ouverte = nil
        courante.rendre(observation)
        return observation
    }

    /// Position admissible : la dernière valide dont l'instant n'est pas antérieur à `debut - tolerance`.
    public nonisolated static func selection(_ fixes: [FixPosition], depuis debut: Date) -> FixPosition? {
        fixes.last { $0.precision >= 0 && $0.instant >= debut.addingTimeInterval(-tolerance) }
    }
}
