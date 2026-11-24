import Foundation
import XCTest
import JoleneCore
@testable import JoleneSupabase

/// Garde de source (L4-T11, D26, correction 17) : la bascule du pool urgence passe uniquement par `fn_toggle_pool_urgence`
/// (`SupabasePoolUrgenceGateway`) ; aucun autre code natif n'écrit `soignants.disponible_urgence`. Parcourt les sources
/// Swift de l'app et des paquets (`ios-native/` seulement) :
/// - le littéral de la RPC de bascule n'apparaît que dans la gateway du pool ;
/// - la colonne n'est nommée que là où elle est lue ou interdite (validation du profil, liste des paramètres jamais
///   envoyés de `fn_modifier_mon_profil`) ;
/// - aucune requête PostgREST n'écrit la table `soignants` avec la colonne.
final class PoolUrgenceSourceGuardTests: XCTestCase {
    /// `ios-native/` depuis ce fichier (`Packages/JoleneSupabase/Tests/JoleneSupabaseTests/`).
    private static let racine = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private static let colonne = ["disponible", "urgence"].joined(separator: "_")
    private static let rpcBascule = "\"" + ["fn", "toggle", "pool", "urgence"].joined(separator: "_") + "\""

    private func sourcesSwift() throws -> [(chemin: String, texte: String)] {
        let dossiers = ["Jolene", "Packages/JoleneCore/Sources", "Packages/JoleneSupabase/Sources", "Packages/JoleneDesign/Sources"]
        var fichiers: [(String, String)] = []
        for dossier in dossiers {
            let url = Self.racine.appendingPathComponent(dossier)
            guard let enumerateur = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
                XCTFail("dossier illisible : \(dossier)")
                continue
            }
            for case let fichier as URL in enumerateur where fichier.pathExtension == "swift" {
                let relatif = String(fichier.path.dropFirst(Self.racine.path.count + 1))
                fichiers.append((relatif, try String(contentsOf: fichier, encoding: .utf8)))
            }
        }
        XCTAssertGreaterThan(fichiers.count, 100, "sources trouvées")
        return fichiers
    }

    func testBasculeDuPoolParLaSeuleRPCDediee() throws {
        let sources = try sourcesSwift()
        let avecRPC = sources.filter { $0.texte.contains(Self.rpcBascule) }.map(\.chemin)
        XCTAssertEqual(avecRPC, ["Packages/JoleneSupabase/Sources/JoleneSupabase/PoolUrgence/SupabasePoolUrgenceGateway.swift"])
        XCTAssertEqual("\"" + SupabasePoolUrgenceGateway.rpcBasculer + "\"", Self.rpcBascule)

        let autorises: Set<String> = [
            "Packages/JoleneCore/Sources/JoleneCore/Profil/ModificationProfil.swift",   // `p_<colonne>` dans parametresInterdits
            "Packages/JoleneCore/Sources/JoleneCore/Profil/ValidationProfil.swift",     // lecture (validation du profil)
        ]
        let avecColonne = Set(sources.filter { $0.texte.contains(Self.colonne) }.map(\.chemin))
        XCTAssertTrue(avecColonne.isSubset(of: autorises), "colonne nommée hors des lecteurs connus : \(avecColonne.subtracting(autorises))")
        XCTAssertTrue(ModificationProfil.parametresInterdits.contains("p_" + Self.colonne),
                      "fn_modifier_mon_profil ne l'envoie jamais")
        XCTAssertFalse(ModificationProfil.parametresAutorises.contains("p_" + Self.colonne))
        for source in sources where source.texte.contains("from(\"soignants\")") {
            XCTAssertFalse(source.texte.contains(".update(") && source.texte.contains(Self.colonne), source.chemin)
        }
    }
}
