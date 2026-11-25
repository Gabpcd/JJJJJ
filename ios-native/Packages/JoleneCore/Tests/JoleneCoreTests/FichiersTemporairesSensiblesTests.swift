import XCTest
@testable import JoleneCore

/// Revue B8 sécurité de l'intégration de la vague D (m6) : une purge unique efface les copies de contrats et de
/// bulletins ; le câblage (lancement, sortie des deux espaces) est gardé par `FichiersTemporairesSourcesAppTests`.
final class FichiersTemporairesSensiblesTests: XCTestCase {
    func testPurgeEffaceLesCopiesDeContratsEtDeBulletins() throws {
        let gestionnaire = FileManager.default
        var ecrits: [URL] = []
        for dossier in FichiersTemporairesSensibles.dossiers() {
            let sous = dossier.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try gestionnaire.createDirectory(at: sous, withIntermediateDirectories: true)
            let fichier = sous.appendingPathComponent("copie.bin")
            try Data("copie".utf8).write(to: fichier)
            ecrits.append(fichier)
        }
        XCTAssertEqual(ecrits.count, 2)
        XCTAssertEqual(Set(FichiersTemporairesSensibles.dossiers()),
                       [FichierContratTemporaire.dossier(), FichierCopieBulletinTemporaire.dossier()])
        FichiersTemporairesSensibles.purger()
        for fichier in ecrits { XCTAssertFalse(gestionnaire.fileExists(atPath: fichier.path), fichier.lastPathComponent) }
        for dossier in FichiersTemporairesSensibles.dossiers() { XCTAssertFalse(gestionnaire.fileExists(atPath: dossier.path)) }
        FichiersTemporairesSensibles.purger() // idempotente
    }
}
