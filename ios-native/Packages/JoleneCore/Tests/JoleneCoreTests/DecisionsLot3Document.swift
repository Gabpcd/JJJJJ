import XCTest

/// Lecture de `docs/mobile-swift/DECISIONS_LOT3.md` par les tests qui épinglent un texte natif sans équivalent web
/// (L3-TJ) : depuis la délégation de Gabrielle du 8 novembre 2026, ces textes ne sont plus « à relire par Gabrielle »
/// dans la section HARD STOP, ils sont tranchés sous « Décisions déléguées du 8 novembre 2026 », chacun dans une
/// sous-section `### TJn — …` qui porte la ligne de délégation.
enum DecisionsLot3Document {
    static let chemin = "docs/mobile-swift/DECISIONS_LOT3.md"
    static let titreDeleguees = "## Décisions déléguées du 8 novembre 2026"
    static let ligneDelegation = "décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026"

    static func document() throws -> String {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent(chemin)
        guard FileManager.default.fileExists(atPath: fichier.path) else { throw XCTSkip("\(chemin) introuvable") }
        return try String(contentsOf: fichier, encoding: .utf8)
    }

    /// Section `## <titre>` (jusqu'à la section suivante).
    static func section(_ titre: String, dans document: String) throws -> Substring {
        let debut = try XCTUnwrap(document.range(of: "\n\(titre)"), "section « \(titre) » de \(chemin)")
        let suite = document[debut.upperBound...]
        return suite.range(of: "\n## ").map { suite[..<$0.lowerBound] } ?? suite
    }

    /// Puce de premier niveau qui commence par `entete` dans la section des décisions déléguées, et sous-section
    /// `### TJn — …` qui la contient. Échoue si la puce est absente ou si sa sous-section n'est pas tranchée par
    /// délégation (ligne de délégation absente).
    static func puceDeleguee(_ entete: String, file: StaticString = #filePath, line: UInt = #line) throws
        -> (puce: Substring, sousSection: Substring) {
        let deleguees = try section(titreDeleguees, dans: try document())
        let debut = try XCTUnwrap(deleguees.range(of: "\n" + entete), "puce « \(entete) » des décisions déléguées",
                                  file: file, line: line)
        let suite = deleguees[debut.upperBound...]
        let puce = suite.range(of: "\n- ").map { suite[..<$0.lowerBound] } ?? suite
        let titre = try XCTUnwrap(deleguees[..<debut.lowerBound].range(of: "\n### TJ", options: .backwards),
                                  "sous-section TJ de la puce « \(entete) »", file: file, line: line)
        let reste = deleguees[titre.upperBound...]
        let sousSection = deleguees[titre.lowerBound..<(reste.range(of: "\n### ")?.lowerBound ?? deleguees.endIndex)]
        XCTAssertTrue(sousSection.contains(ligneDelegation), "sous-section tranchée par délégation (ligne de délégation)",
                      file: file, line: line)
        return (puce, sousSection)
    }

    /// Plus aucun texte natif n'attend la relecture de Gabrielle dans la section HARD STOP.
    static func assertHardStopSansRelectureEnAttente(file: StaticString = #filePath, line: UInt = #line) throws {
        let hardStop = try section("## HARD STOP n°4", dans: try document())
        XCTAssertFalse(hardStop.contains("à relire par Gabrielle"), "HARD STOP : plus aucun texte « à relire par Gabrielle »",
                       file: file, line: line)
    }
}
