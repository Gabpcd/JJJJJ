import XCTest
@testable import JoleneCore

/// Preuve statique qu'aucune API réseau n'entre dans JoleneCore (plan §4.6 : aucune
/// requête ne part en mode démo). Introspection des sources du package.
final class DemoNoNetworkTests: XCTestCase {
    private var sourcesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // JoleneCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // JoleneCore (package)
            .appendingPathComponent("Sources/JoleneCore", isDirectory: true)
    }

    private func fichiersSwift() throws -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: sourcesURL, includingPropertiesForKeys: nil) else {
            throw JoleneError(.unknown, "Sources/JoleneCore introuvable")
        }
        var fichiers: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            fichiers.append(url)
        }
        return fichiers.sorted { $0.path < $1.path }
    }

    func testAucunImportReseauNiURLSessionDansJoleneCore() throws {
        let fichiers = try fichiersSwift()
        XCTAssertGreaterThanOrEqual(fichiers.count, 10, "l'introspection doit couvrir le package entier")
        XCTAssertTrue(fichiers.contains { $0.lastPathComponent == "DemoWorld.swift" })
        let motInterdit = "URL" + "Session"
        let importsInterdits = ["Network", "CFNetwork", "Supabase", "Alamofire"]
        for url in fichiers {
            let contenu = try String(contentsOf: url, encoding: .utf8)
            let relatif = url.path.replacingOccurrences(of: sourcesURL.path, with: "")
            XCTAssertFalse(contenu.contains(motInterdit), "\(relatif) mentionne \(motInterdit)")
            for (numero, ligne) in contenu.components(separatedBy: "\n").enumerated() {
                let nette = ligne.trimmingCharacters(in: .whitespaces)
                guard nette.hasPrefix("import ") || nette.hasPrefix("@testable import ") else { continue }
                let module = nette.replacingOccurrences(of: "@testable import ", with: "").replacingOccurrences(of: "import ", with: "")
                    .split(separator: " ").first.map(String.init) ?? ""
                XCTAssertFalse(importsInterdits.contains(module), "\(relatif):\(numero + 1) importe \(module)")
            }
        }
    }
}
