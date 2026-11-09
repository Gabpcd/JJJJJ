import CoreLocation
import Foundation
import JoleneCore

/// Position du profil (lot 3, T10), implémentation PROVISOIRE et ISOLÉE de `LocalisationPort`, à SUPPRIMER à la fusion
/// des lots : le lot 2 (T4b, `feat/ios-lot2`) livre `LocationService` (`Jolene/Composition/Device/LocationService.swift`),
/// seul service de localisation de l'app ; le profil passera alors par un adaptateur sur `Appareil.localisation`
/// (point de fusion : `docs/mobile-swift/DECISIONS_LOT3.md`, section T10). Aucun autre écran ne l'utilise.
///
/// Comme le web (`src/lib/geoloc.ts` l.71-101) : autorisation « Lorsque l'app est active » demandée sur l'appui
/// « Utiliser ma position actuelle » si elle ne l'a jamais été (chaîne `NSLocationWhenInUseUsageDescription` du lot 0,
/// inchangée), puis une position unique (`requestLocation`) bornée au délai du web (15 s). Précision réduite acceptée :
/// une ville suffit au profil. Ne lève jamais, ne journalise rien (aucune coordonnée dans un journal).
@MainActor
final class LocalisationProfilProvisoire: NSObject, LocalisationPort, CLLocationManagerDelegate {
    private let gestionnaire = CLLocationManager()
    private var attentesAutorisation: [CheckedContinuation<Void, Never>] = []
    private var attentePosition: CheckedContinuation<PositionPonctuelle, Never>?
    private var jeton = 0

    override init() {
        super.init()
        gestionnaire.delegate = self
        gestionnaire.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func localiser(delai: TimeInterval) async -> PositionPonctuelle {
        // Une seule demande à la fois (le modèle verrouille déjà le bouton) : une seconde est close sans attendre.
        guard attentePosition == nil else { return .indisponible }
        if gestionnaire.authorizationStatus == .notDetermined {
            await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
                attentesAutorisation.append(suite)
                gestionnaire.requestWhenInUseAuthorization()
            }
        }
        switch gestionnaire.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: break
        case .denied, .restricted: return .refusee
        default: return .indisponible
        }
        jeton += 1
        let courant = jeton
        return await withCheckedContinuation { (suite: CheckedContinuation<PositionPonctuelle, Never>) in
            attentePosition = suite
            gestionnaire.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, min(delai, 120)) * 1_000_000_000))
                self?.conclure(.indisponible, jeton: courant)
            }
        }
    }

    // MARK: - CLLocationManagerDelegate (appelé sur le fil principal, où le gestionnaire est créé)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.autorisationChangee() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Valeurs extraites ici (types `Sendable`) : aucune `CLLocation` ne traverse la frontière d'isolement.
        guard let derniere = locations.last, derniere.horizontalAccuracy >= 0 else { return }
        let latitude = derniere.coordinate.latitude
        let longitude = derniere.coordinate.longitude
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.conclure(.disponible(latitude: latitude, longitude: longitude), jeton: self.jeton)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let refus = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.conclure(refus ? .refusee : .indisponible, jeton: self.jeton)
        }
    }

    // MARK: - Interne

    private func autorisationChangee() {
        guard gestionnaire.authorizationStatus != .notDetermined else { return }
        let attentes = attentesAutorisation
        attentesAutorisation.removeAll()
        attentes.forEach { $0.resume() }
    }

    /// Reprise UNIQUE de la demande `jeton` (position, erreur ou délai : le premier arrivé l'emporte).
    private func conclure(_ issue: PositionPonctuelle, jeton: Int) {
        guard jeton == self.jeton, let suite = attentePosition else { return }
        attentePosition = nil
        suite.resume(returning: issue)
    }
}
