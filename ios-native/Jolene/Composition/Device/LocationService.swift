import CoreLocation
import Foundation
import JoleneCore

/// Position réelle du pointage (`LocationPort`, blueprint lot 2 §2.2 ; décisions 4 et 5), enveloppe `@MainActor` de
/// `CLLocationManager` : autorisation « Lorsque l'app est active » seulement (jamais `UIBackgroundModes`, jamais
/// « Toujours »), demandée par l'écran après un consentement relu vrai ; une position unique, la première postérieure à
/// la demande (parité du `maximumAge` implicite de 0 du web, `src/lib/platform.ts` l.298), bornée au délai du web (15 s).
/// Précision réduite (`accuracyAuthorization == .reducedAccuracy`) → `.precisionReduite` : aucune coordonnée, pas de
/// `requestTemporaryFullAccuracyAuthorization` (nouvelle chaîne `Info.plist`, refusée par la décision 5). Ne lève jamais,
/// ne journalise rien (aucune coordonnée dans un journal, `LOT2_PLAN.md` §2.7). Chaîne d'autorisation : celle du lot 0
/// (`NSLocationWhenInUseUsageDescription`, verrouillée par la garde `check-textes-juridiques-ios`).
@MainActor
final class LocationService: NSObject, LocationPort, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var attentesAutorisation: [CheckedContinuation<Void, Never>] = []
    private var demande: Demande?

    /// Demande de position en cours : instant de départ et suite à reprendre une seule fois.
    private final class Demande {
        let debut: Date
        let jeton = UUID()
        var suite: CheckedContinuation<ObservationGps, Never>?

        init(debut: Date, suite: CheckedContinuation<ObservationGps, Never>) {
            self.debut = debut
            self.suite = suite
        }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - LocationPort

    func autorisation() async -> AutorisationPosition {
        Self.traduire(manager.authorizationStatus, precise: manager.accuracyAuthorization == .fullAccuracy)
    }

    func demanderAutorisation() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
            attentesAutorisation.append(suite)
            manager.requestWhenInUseAuthorization()
        }
    }

    func positionUnique(delai: TimeInterval) async -> ObservationGps {
        switch Self.traduire(manager.authorizationStatus, precise: manager.accuracyAuthorization == .fullAccuracy) {
        case .nonDeterminee, .refusee: return .refusee
        case .accordee(precise: false): return .precisionReduite
        case .accordee(precise: true): break
        }
        terminer(.indisponible) // une demande précédente encore ouverte n'est jamais reprise deux fois
        return await withCheckedContinuation { (suite: CheckedContinuation<ObservationGps, Never>) in
            let nouvelle = Demande(debut: Date(), suite: suite)
            demande = nouvelle
            manager.startUpdatingLocation()
            let jeton = nouvelle.jeton
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, min(delai, 3600)) * 1_000_000_000))
                self?.expirer(jeton)
            }
        }
    }

    // MARK: - CLLocationManagerDelegate (appelé sur le fil principal, où le gestionnaire est créé)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.autorisationChangee() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Valeurs extraites ici (types `Sendable`) : aucune `CLLocation` ne traverse la frontière d'isolement.
        let fixes = locations.map { Fix(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                                        precision: $0.horizontalAccuracy, instant: $0.timestamp) }
        Task { @MainActor [weak self] in self?.recevoir(fixes) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        Task { @MainActor [weak self] in self?.echouer(code) }
    }

    // MARK: - Interne

    private struct Fix: Sendable {
        let latitude: Double
        let longitude: Double
        let precision: Double
        let instant: Date
    }

    private func autorisationChangee() {
        guard manager.authorizationStatus != .notDetermined else { return }
        let attentes = attentesAutorisation
        attentesAutorisation.removeAll()
        attentes.forEach { $0.resume() }
    }

    private func recevoir(_ fixes: [Fix]) {
        guard let demande else { return }
        guard manager.accuracyAuthorization == .fullAccuracy else {
            terminer(.precisionReduite)
            return
        }
        // Première position postérieure à la demande (une position en cache, plus ancienne, est ignorée).
        guard let fix = fixes.last(where: { $0.precision >= 0 && $0.instant >= demande.debut.addingTimeInterval(-1) }) else { return }
        terminer(.disponible(latitude: fix.latitude, longitude: fix.longitude, precisionM: fix.precision))
    }

    private func echouer(_ code: CLError.Code?) {
        switch code {
        case .locationUnknown?: return // transitoire : CoreLocation continue de chercher jusqu'au délai
        case .denied?: terminer(.refusee)
        default: terminer(.indisponible)
        }
    }

    private func expirer(_ jeton: UUID) {
        guard demande?.jeton == jeton else { return }
        terminer(.indisponible)
    }

    private func terminer(_ observation: ObservationGps) {
        guard let courante = demande else { return }
        demande = nil
        manager.stopUpdatingLocation()
        courante.suite?.resume(returning: observation)
        courante.suite = nil
    }

    private static func traduire(_ statut: CLAuthorizationStatus, precise: Bool) -> AutorisationPosition {
        switch statut {
        case .notDetermined: return .nonDeterminee
        case .authorizedWhenInUse, .authorizedAlways: return .accordee(precise: precise)
        default: return .refusee
        }
    }
}
