import XCTest
@testable import JoleneCore

/// Point de fusion VERROUILLÉ de la localisation du profil (lot 3, T10 ; revue fraîche B8 de T10, m1 ;
/// `DECISIONS_LOT3.md`, « Décisions déléguées du 8 novembre 2026 », « T10 — localisation du profil livrée sans le port du
/// lot 2 ») : la position du profil passe aujourd'hui par le port minimal `LocalisationPort` et l'implémentation isolée
/// `LocalisationProfilProvisoire` (cible app), parce que `LocationPort` du lot 2 n'est pas sur la base du lot 3. Ce test
/// échoue dès que `LocationPort` du lot 2 arrive dans JoleneCore alors que l'implémentation provisoire existe encore :
/// la fusion ne peut pas laisser deux services de localisation dans l'app (PRINCIPES §2). Avant la fusion, il exige que
/// l'implémentation provisoire soit la SEULE utilisatrice de CoreLocation dans la cible app, et la règle de la précision
/// réduite tranchée (`LocalisationPolicy.issuePrecisionReduite`).
final class FusionLocalisationLot2Tests: XCTestCase {
    /// Racine `ios-native/` (le fichier est sous `ios-native/Packages/JoleneCore/Tests/JoleneCoreTests/`).
    private static var racine: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    private static let provisoire = "Jolene/Composition/LocalisationProfilProvisoire.swift"

    /// Sources Swift sous `relatif` (chemins relatifs à `ios-native/`), triées. Un dossier absent est une erreur : un
    /// garde qui ne lit rien serait vide de sens.
    private static func sourcesSwift(_ relatif: String) throws -> [(chemin: String, contenu: String)] {
        let dossier = racine.appendingPathComponent(relatif, isDirectory: true)
        var estDossier: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dossier.path, isDirectory: &estDossier), estDossier.boolValue,
              let parcours = FileManager.default.enumerator(at: dossier, includingPropertiesForKeys: nil) else {
            throw JoleneError(.contract, "\(relatif) introuvable sous \(racine.path)")
        }
        var fichiers: [(String, String)] = []
        for case let url as URL in parcours where url.pathExtension == "swift" {
            let chemin = url.path.replacingOccurrences(of: racine.path + "/", with: "")
            fichiers.append((chemin, try String(contentsOf: url, encoding: .utf8)))
        }
        return fichiers.sorted { $0.0 < $1.0 }
    }

    func testImplementationProvisoireRetireeDesQueLePortDuLot2Arrive() throws {
        let coeur = try Self.sourcesSwift("Packages/JoleneCore/Sources")
        let app = try Self.sourcesSwift("Jolene")
        XCTAssertGreaterThan(coeur.count, 50, "les sources de JoleneCore sont lues")
        XCTAssertGreaterThan(app.count, 20, "les sources de l'app sont lues")
        let portDuLot2 = coeur.filter { $0.contenu.contains("protocol LocationPort") }.map(\.chemin)
        let provisoirePresente = FileManager.default.fileExists(atPath: Self.racine.appendingPathComponent(Self.provisoire).path)
        let references = (coeur + app).filter { $0.contenu.contains("LocalisationProfilProvisoire") }.map(\.chemin)
        if portDuLot2.isEmpty {
            // Avant la fusion : une seule implémentation réelle, isolée et nommée pour être supprimée.
            XCTAssertTrue(provisoirePresente, "\(Self.provisoire) attendu tant que le lot 2 n'est pas fusionné")
            let coreLocation = app.filter { $0.contenu.contains("import CoreLocation") }.map(\.chemin)
            XCTAssertEqual(coreLocation, [Self.provisoire],
                           "seule l'implémentation provisoire utilise CoreLocation dans la cible app avant la fusion")
        } else {
            XCTAssertFalse(provisoirePresente,
                           "`LocationPort` du lot 2 est arrivé (\(portDuLot2)) : supprimer \(Self.provisoire) et servir "
                           + "`LocalisationPort` par un adaptateur sur `Appareil.localisation` (DECISIONS_LOT3.md, section T10)")
            XCTAssertEqual(references, [],
                           "plus aucune référence à `LocalisationProfilProvisoire` après la fusion avec le lot 2")
        }
    }

    /// Règle de la précision réduite, tranchée AVANT la fusion (revue B8 de T10, m1) : aucune coordonnée n'est demandée
    /// ni transmise ; l'issue est `.indisponible`, donc le message du web (« Localisation refusée ou indisponible. Vous
    /// pouvez saisir votre adresse manuellement. ») — comme `ObservationGps.precisionReduite` du lot 2, que l'adaptateur
    /// de la fusion traduira de la même façon. La recette appareil et la décision consignée disent la même chose.
    func testPrecisionReduiteTrancheeAvantLaFusion() throws {
        XCTAssertEqual(LocalisationPolicy.issuePrecisionReduite, .indisponible)
        XCTAssertEqual(LocalisationPolicy.delaiAutorisationProfil, 60, "attente bornée de la réponse à la feuille système")
        var depot = Self.racine
        depot.deleteLastPathComponent()
        let recette = try String(contentsOf: depot.appendingPathComponent("docs/mobile-swift/RECETTE_DEVICE_LOT3.md"),
                                 encoding: .utf8)
        let ligne = try XCTUnwrap(recette.components(separatedBy: "\n").first { $0.contains("Position en précision réduite") })
        XCTAssertTrue(ligne.contains(ProfilLocalisation.Textes.refusee), "recette appareil alignée sur la règle : \(ligne)")
        XCTAssertFalse(ligne.contains("ville renseignée"), "plus de « ville renseignée » en précision réduite")
        let decisions = try String(contentsOf: depot.appendingPathComponent("docs/mobile-swift/DECISIONS_LOT3.md"),
                                   encoding: .utf8)
        XCTAssertTrue(decisions.contains("`.precisionReduite` → `.indisponible`"), "règle de fusion consignée")
        XCTAssertTrue(decisions.contains("T10 — localisation du profil livrée sans le port du lot 2"),
                      "décision explicite qui déroge au blueprint v2 §3 T10")
    }
}
