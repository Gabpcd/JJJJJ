import CoreLocation
import Foundation
import JoleneCore

/// Position du profil (lot 3, T10), implémentation PROVISOIRE et ISOLÉE de `LocalisationPort`, à SUPPRIMER à la fusion
/// des lots : le lot 2 (T4b, `feat/ios-lot2`) livre `LocationService` (`Jolene/Composition/Device/LocationService.swift`),
/// seul service de localisation de l'app ; le profil passera alors par un adaptateur sur `Appareil.localisation`
/// (point de fusion : `docs/mobile-swift/DECISIONS_LOT3.md`, section T10 et « Décisions déléguées du 8 novembre 2026 ») ;
/// `FusionLocalisationLot2Tests` échoue tant que ce fichier coexiste avec le port du lot 2. Aucun autre écran ne
/// l'utilise.
///
/// Comme le web (`src/lib/geoloc.ts` l.71-101) : autorisation « Lorsque l'app est active » demandée sur l'appui
/// « Utiliser ma position actuelle » si elle ne l'a jamais été (chaîne `NSLocationWhenInUseUsageDescription` du lot 0,
/// inchangée), puis une position unique (`requestLocation`) bornée au délai du web (15 s). Ne lève jamais, ne journalise
/// rien (aucune coordonnée dans un journal).
///
/// Revue B8 de T10 :
/// - m1 : précision réduite (« Position exacte » coupée) → `LocalisationPolicy.issuePrecisionReduite` (`.indisponible`),
///   sans demander de position, comme `LocationService` du lot 2 (`.precisionReduite` sans coordonnée) : le
///   comportement ne change pas à la fusion ;
/// - m12 : l'attente de la réponse à la feuille d'autorisation est bornée (`LocalisationPolicy.delaiAutorisationProfil`),
///   et l'instance étant partagée (`AppContainer.localisationProfil`), une demande faite pendant une autre en attente —
///   autorisation ou position — attend la MÊME issue au lieu de rendre `.indisponible` d'office.
@MainActor
final class LocalisationProfilProvisoire: NSObject, LocalisationPort, CLLocationManagerDelegate {
    private let gestionnaire = CLLocationManager()
    /// Demandes en attente de la réponse à la feuille d'autorisation, par jeton (reprise unique : réponse ou délai).
    private var attentesAutorisation: [Int: CheckedContinuation<Void, Never>] = [:]
    /// Demandes en attente de la position en cours ; toutes reçoivent la même issue.
    private var attentesPosition: [CheckedContinuation<PositionPonctuelle, Never>] = []
    private var prochainJeton = 0
    /// Demande de position en cours (`requestLocation` parti) : jeton de son délai.
    private var positionEnCours: Int?

    override init() {
        super.init()
        gestionnaire.delegate = self
        gestionnaire.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func localiser(delai: TimeInterval) async -> PositionPonctuelle {
        if gestionnaire.authorizationStatus == .notDetermined {
            await attendreAutorisation()
        }
        switch gestionnaire.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: break
        case .denied, .restricted: return .refusee
        default: return .indisponible
        }
        if gestionnaire.accuracyAuthorization == .reducedAccuracy { return LocalisationPolicy.issuePrecisionReduite }
        return await withCheckedContinuation { (suite: CheckedContinuation<PositionPonctuelle, Never>) in
            attentesPosition.append(suite)
            // Une position est déjà attendue : la nouvelle demande partage son issue (aucune seconde requête).
            guard positionEnCours == nil else { return }
            let jeton = nouveauJeton()
            positionEnCours = jeton
            gestionnaire.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.nanosecondes(delai, plafond: 120))
                self?.conclure(.indisponible, jeton: jeton)
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
            guard let self, let jeton = self.positionEnCours else { return }
            self.conclure(.disponible(latitude: latitude, longitude: longitude), jeton: jeton)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let refus = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in
            guard let self, let jeton = self.positionEnCours else { return }
            self.conclure(refus ? .refusee : .indisponible, jeton: jeton)
        }
    }

    // MARK: - Interne

    /// Attente de la réponse à la feuille d'autorisation, bornée : reprise unique par la réponse ou par le délai.
    private func attendreAutorisation() async {
        let jeton = nouveauJeton()
        await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
            let premiere = attentesAutorisation.isEmpty
            attentesAutorisation[jeton] = suite
            if premiere { gestionnaire.requestWhenInUseAuthorization() }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.nanosecondes(LocalisationPolicy.delaiAutorisationProfil, plafond: 600))
                self?.attentesAutorisation.removeValue(forKey: jeton)?.resume()
            }
        }
    }

    private func autorisationChangee() {
        guard gestionnaire.authorizationStatus != .notDetermined else { return }
        let attentes = attentesAutorisation.values
        attentesAutorisation.removeAll()
        attentes.forEach { $0.resume() }
    }

    /// Reprise UNIQUE de toutes les demandes de la position `jeton` (position, erreur ou délai : le premier arrivé
    /// l'emporte).
    private func conclure(_ issue: PositionPonctuelle, jeton: Int) {
        guard jeton == positionEnCours else { return }
        positionEnCours = nil
        let suites = attentesPosition
        attentesPosition.removeAll()
        suites.forEach { $0.resume(returning: issue) }
    }

    private func nouveauJeton() -> Int {
        prochainJeton += 1
        return prochainJeton
    }

    private nonisolated static func nanosecondes(_ secondes: TimeInterval, plafond: TimeInterval) -> UInt64 {
        UInt64(max(0, min(secondes.isFinite ? secondes : plafond, plafond)) * 1_000_000_000)
    }
}
