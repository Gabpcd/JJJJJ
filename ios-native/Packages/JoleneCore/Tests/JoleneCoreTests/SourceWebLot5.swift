import XCTest

/// Garde de dérive des messages non juridiques repris mot pour mot du web par les règles pures
/// du lot 5 (T3) : chaque constante doit figurer telle quelle dans son fichier source. Un texte
/// modifié côté web rougit le test, qui impose de reprendre la nouvelle version (jamais de
/// reformulation native). Les textes juridiques passent, eux, par `Legal/TextesWeb.swift`
/// (tranche TL du lot 2) et sa garde Node.
enum SourceWebLot5 {
    struct SourceIntrouvable: Error, CustomStringConvertible {
        let chemin: String
        var description: String { "Fichier web introuvable : \(chemin)" }
    }

    /// Racine du dépôt : Tests/JoleneCoreTests/<fichier> → 6 niveaux au-dessus.
    static var racineDepot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // JoleneCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // JoleneCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // ios-native
            .deletingLastPathComponent() // racine
    }

    static func lire(_ cheminRelatif: String) throws -> String {
        let url = racineDepot.appendingPathComponent(cheminRelatif)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Package isolé de son dépôt : rien à comparer (même règle que LinksAASATests).
            throw XCTSkip(SourceIntrouvable(chemin: url.path).description)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func verifier(_ cheminRelatif: String, contient textes: [String],
                         file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try lire(cheminRelatif)
        for texte in textes {
            XCTAssertFalse(texte.isEmpty, file: file, line: line)
            XCTAssertTrue(source.contains(texte), "« \(texte) » absent de \(cheminRelatif) : reprendre le texte web exact",
                          file: file, line: line)
        }
    }
}
