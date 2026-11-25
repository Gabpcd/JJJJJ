import Foundation
import XCTest

/// Garde de source (L4-T13, `LOT4_PLAN.md` §3 T13 et §5, intégration de la vague D, décision f) : aucun chemin
/// `/soignant/*` n'est ouvert par `UIApplication.open` ni par `openURL` — il reviendrait dans l'app par lien universel
/// (`applinks:jolene.app`). Les renvois web passent par le présentateur `.safari` (`PresentateurRenvoiWeb`).
/// Parcourt les sources Swift de l'app (`ios-native/Jolene`), commentaires retirés.
final class RenvoisWebSourcesAppTests: XCTestCase {
    /// `ios-native/` depuis ce fichier (`Packages/JoleneSupabase/Tests/JoleneSupabaseTests/`).
    private static let racine = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func sourcesApp() throws -> [(chemin: String, code: String)] {
        let url = Self.racine.appendingPathComponent("Jolene")
        let enumerateur = try XCTUnwrap(FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil))
        var fichiers: [(String, String)] = []
        for case let fichier as URL in enumerateur where fichier.pathExtension == "swift" {
            let texte = try String(contentsOf: fichier, encoding: .utf8)
            let code = texte.split(separator: "\n", omittingEmptySubsequences: false).map { ligne -> String in
                // Commentaire de ligne ou de fin de ligne (« // » précédé d'une espace) ; une URL (« https:// ») reste du code.
                let l = String(ligne)
                if l.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let i = l.range(of: " //") else { return l }
                return String(l[..<i.lowerBound])
            }.joined(separator: "\n")
            fichiers.append((String(fichier.path.dropFirst(Self.racine.path.count + 1)), code))
        }
        XCTAssertGreaterThan(fichiers.count, 100, "sources de l'app trouvées")
        return fichiers
    }

    func testAucunCheminSoignantOuvertHorsDuPresentateur() throws {
        let sources = try sourcesApp()
        let ouvertureSysteme = sources.filter { $0.code.contains("UIApplication.shared.open(") }.map(\.chemin)
        XCTAssertEqual(ouvertureSysteme, [], "UIApplication.open : jamais pour un renvoi web")
        for source in sources where source.code.contains("openURL(") {
            XCTAssertFalse(source.code.contains("/soignant/"), "\(source.chemin) : openURL dans un fichier qui nomme un chemin /soignant/")
        }
    }
}
