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
///
/// Sélection de la position (périmée si antérieure à la demande moins 1 s, précision invalide), reprise UNIQUE de la
/// suite, expiration et nouvelle demande : `DemandesPosition` (JoleneCore, `DemandePositionTests` ; revue fraîche de T4b,
/// m8). Ici ne restent que la traduction des types CoreLocation et le pilotage du gestionnaire.
@MainActor
final class LocationService: NSObject, LocationPort, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var attentesAutorisation: [CheckedContinuation<Void, Never>] = []
    private let demandes = DemandesPosition()

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
        return await withCheckedContinuation { (suite: CheckedContinuation<ObservationGps, Never>) in
            // Une demande précédente encore ouverte est close `.indisponible` par `ouvrir` (jamais reprise deux fois).
            let jeton = demandes.ouvrir(debut: Date()) { suite.resume(returning: $0) }
            manager.startUpdatingLocation()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, min(delai, 3600)) * 1_000_000_000))
                self?.conclure(self?.demandes.expirer(jeton))
            }
        }
    }

    // MARK: - CLLocationManagerDelegate (appelé sur le fil principal, où le gestionnaire est créé)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.autorisationChangee() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Valeurs extraites ici (types `Sendable`) : aucune `CLLocation` ne traverse la frontière d'isolement.
        let fixes = locations.map { FixPosition(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                                                precision: $0.horizontalAccuracy, instant: $0.timestamp) }
        Task { @MainActor [weak self] in self?.recevoir(fixes) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        Task { @MainActor [weak self] in self?.echouer(code) }
    }

    // MARK: - Interne

    private func autorisationChangee() {
        guard manager.authorizationStatus != .notDetermined else { return }
        let attentes = attentesAutorisation
        attentesAutorisation.removeAll()
        attentes.forEach { $0.resume() }
    }

    private func recevoir(_ fixes: [FixPosition]) {
        conclure(demandes.recevoir(fixes, precise: manager.accuracyAuthorization == .fullAccuracy))
    }

    private func echouer(_ code: CLError.Code?) {
        let echec: EchecPosition
        switch code {
        case .locationUnknown?: echec = .transitoire // CoreLocation continue de chercher jusqu'au délai
        case .denied?: echec = .refus
        default: echec = .autre
        }
        conclure(demandes.echouer(echec))
    }

    /// Demande close (une issue vient d'être rendue) : le gestionnaire s'arrête.
    private func conclure(_ issue: ObservationGps?) {
        guard issue != nil, !demandes.enCours else { return }
        manager.stopUpdatingLocation()
    }

    private static func traduire(_ statut: CLAuthorizationStatus, precise: Bool) -> AutorisationPosition {
        switch statut {
        case .notDetermined: return .nonDeterminee
        case .authorizedWhenInUse, .authorizedAlways: return .accordee(precise: precise)
        default: return .refusee
        }
    }
}
