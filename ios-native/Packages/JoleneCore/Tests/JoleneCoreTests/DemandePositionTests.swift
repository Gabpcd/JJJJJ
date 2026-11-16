import XCTest
@testable import JoleneCore

/// Position unique du pointage (revue fraîche de T4b, m8) : logique de `LocationService` (cible app, `CLLocationManager`)
/// extraite dans `DemandesPosition` et testée ici sans CoreLocation — position périmée ignorée (antérieure à la demande
/// moins 1 s, parité du `maximumAge` implicite de 0 du web, `src/lib/platform.ts` l.298), précision invalide ignorée,
/// précision réduite sans coordonnée (décision 5), refus, erreur transitoire, expiration au délai du web (15 s), reprise
/// UNIQUE de la suite (une `CheckedContinuation` reprise deux fois ferait planter l'app).
@MainActor
final class DemandePositionTests: XCTestCase {
    private let debut = Date(timeIntervalSince1970: 1_800_000_000)

    /// Reprises d'une demande, dans l'ordre.
    private final class Reprises {
        private(set) var observations: [ObservationGps] = []
        func rendre(_ observation: ObservationGps) { observations.append(observation) }
    }

    private func fix(_ decalage: TimeInterval, precision: Double = 12, latitude: Double = 48.8566) -> FixPosition {
        FixPosition(latitude: latitude, longitude: 2.3522, precision: precision, instant: debut.addingTimeInterval(decalage))
    }

    private func ouvrir(_ demandes: DemandesPosition, _ reprises: Reprises) -> UUID {
        demandes.ouvrir(debut: debut) { reprises.rendre($0) }
    }

    func testDelaiEstCeluiDuWeb() {
        XCTAssertEqual(DemandesPosition.delai, 15, "`timeout: 15000` (src/lib/platform.ts l.298)")
        XCTAssertEqual(DemandesPosition.delai, LocationPolicy.delaiPosition)
        XCTAssertEqual(DemandesPosition.tolerance, 1)
    }

    func testPositionPerimeeIgnoreePuisPremierePositionPosterieureRetenue() {
        let demandes = DemandesPosition(), reprises = Reprises()
        _ = ouvrir(demandes, reprises)
        XCTAssertNil(demandes.recevoir([fix(-30), fix(-1.5)], precise: true), "positions en cache, antérieures à la demande")
        XCTAssertTrue(demandes.enCours)
        XCTAssertEqual(demandes.recevoir([fix(-0.5, latitude: 1), fix(2, latitude: 2)], precise: true),
                       .disponible(latitude: 2, longitude: 2.3522, precisionM: 12), "la plus récente admissible")
        XCTAssertEqual(reprises.observations, [.disponible(latitude: 2, longitude: 2.3522, precisionM: 12)])
        XCTAssertFalse(demandes.enCours)
    }

    func testToleranceDUneSeconde() {
        XCTAssertEqual(DemandesPosition.selection([fix(-1)], depuis: debut), fix(-1), "à 1 s près : admise")
        XCTAssertNil(DemandesPosition.selection([fix(-1.01)], depuis: debut))
    }

    func testPrecisionInvalideIgnoree() {
        let demandes = DemandesPosition(), reprises = Reprises()
        _ = ouvrir(demandes, reprises)
        XCTAssertNil(demandes.recevoir([fix(1, precision: -1)], precise: true), "`horizontalAccuracy` négative : position invalide")
        XCTAssertTrue(reprises.observations.isEmpty)
    }

    func testPrecisionReduiteSansCoordonnee() {
        let demandes = DemandesPosition(), reprises = Reprises()
        _ = ouvrir(demandes, reprises)
        XCTAssertEqual(demandes.recevoir([fix(1)], precise: false), .precisionReduite)
        XCTAssertEqual(reprises.observations, [.precisionReduite], "décision 5 : aucune coordonnée")
    }

    func testEchecsDeLAppareil() {
        let demandes = DemandesPosition(), reprises = Reprises()
        _ = ouvrir(demandes, reprises)
        XCTAssertNil(demandes.echouer(.transitoire), "position inconnue pour l'instant : la recherche continue jusqu'au délai")
        XCTAssertTrue(demandes.enCours)
        XCTAssertEqual(demandes.echouer(.refus), .refusee)

        let autre = DemandesPosition(), reprisesAutre = Reprises()
        _ = ouvrir(autre, reprisesAutre)
        XCTAssertEqual(autre.echouer(.autre), .indisponible)
        XCTAssertEqual(reprises.observations, [.refusee])
        XCTAssertEqual(reprisesAutre.observations, [.indisponible])
    }

    func testExpirationAuDelaiEtJetonPerimeSansEffet() {
        let demandes = DemandesPosition(), reprises = Reprises()
        let premier = ouvrir(demandes, reprises)
        XCTAssertEqual(demandes.expirer(premier), .indisponible, "délai de 15 s écoulé sans position")
        let second = ouvrir(demandes, reprises)
        XCTAssertNil(demandes.expirer(premier), "l'expiration d'une demande close ne touche pas la suivante")
        XCTAssertTrue(demandes.enCours)
        XCTAssertNotEqual(premier, second)
        XCTAssertEqual(reprises.observations, [.indisponible])
    }

    func testRepriseUniqueQuoiQuIlArrive() {
        let demandes = DemandesPosition(), reprises = Reprises()
        let jeton = ouvrir(demandes, reprises)
        XCTAssertNotNil(demandes.recevoir([fix(1)], precise: true))
        XCTAssertNil(demandes.recevoir([fix(2)], precise: true), "demande close : position suivante ignorée")
        XCTAssertNil(demandes.echouer(.refus))
        XCTAssertNil(demandes.expirer(jeton))
        XCTAssertEqual(reprises.observations.count, 1, "une seule reprise de la suite")
    }

    func testNouvelleDemandeCloLaPrecedente() {
        let demandes = DemandesPosition(), premieres = Reprises(), secondes = Reprises()
        _ = ouvrir(demandes, premieres)
        _ = demandes.ouvrir(debut: debut) { secondes.rendre($0) }
        XCTAssertEqual(premieres.observations, [.indisponible], "la précédente n'est jamais laissée en attente")
        XCTAssertNotNil(demandes.recevoir([fix(1)], precise: true))
        XCTAssertEqual(premieres.observations.count, 1)
        XCTAssertEqual(secondes.observations.count, 1)
    }

    func testAucuneDemandeAucuneReprise() {
        let demandes = DemandesPosition()
        XCTAssertFalse(demandes.enCours)
        XCTAssertNil(demandes.recevoir([fix(1)], precise: true))
        XCTAssertNil(demandes.recevoir([fix(1)], precise: false), "précision réduite hors demande : rien")
        XCTAssertNil(demandes.echouer(.refus))
    }
}
