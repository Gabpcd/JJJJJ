import Foundation
import XCTest

/// Garde de source (revue B8 sécurité de l'intégration de la vague D, m6) : les copies temporaires de contrats et de
/// bulletins (`FichiersTemporairesSensibles.purger()`) sont purgées au lancement de l'app et à la disparition de chacun
/// des deux espaces (déconnexion, changement d'epoch). La cible app n'a pas de tests unitaires : la garde lit ses sources.
final class FichiersTemporairesSourcesAppTests: XCTestCase {
    /// `ios-native/` depuis ce fichier (`Packages/JoleneSupabase/Tests/JoleneSupabaseTests/`).
    private static let racine = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func code(_ relatif: String) throws -> String {
        let texte = try String(contentsOf: Self.racine.appendingPathComponent(relatif), encoding: .utf8)
        return texte.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testPurgeAuLancementEtALaSortieDesDeuxEspaces() throws {
        let lancement = try code("Jolene/JoleneApp.swift")
        XCTAssertTrue(lancement.contains("FichiersTemporairesSensibles.purger()"), "purge au lancement (JoleneApp.init)")
        for espace in ["Jolene/Screens/MainTabView.swift", "Jolene/Screens/Etablissement/EtablissementTabView.swift"] {
            let source = try code(espace)
            XCTAssertNotNil(source.range(of: #"\.onDisappear \{[^}]*FichiersTemporairesSensibles\.purger\(\)"#, options: .regularExpression),
                            "\(espace) : purge à la disparition de l'espace")
        }
    }
}
