import Foundation
import XCTest

/// Fichiers du dépôt lus par les gardes de contrat du lot 5 (`ios-native/rpc-contracts.json`,
/// `supabase/schema/public.sql`). Package isolé de son dépôt : rien à comparer (même règle que
/// `SourceWebLot5` de JoleneCoreTests).
enum Depot {
    /// Racine : Tests/JoleneSupabaseTests/Support/<fichier> → 7 niveaux au-dessus.
    static var racine: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { url = url.deletingLastPathComponent() }
        return url
    }

    static func donnees(_ cheminRelatif: String) throws -> Data {
        let url = racine.appendingPathComponent(cheminRelatif)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Fichier du dépôt introuvable : \(url.path)")
        }
        return try Data(contentsOf: url)
    }

    static func texte(_ cheminRelatif: String) throws -> String {
        guard let texte = String(data: try donnees(cheminRelatif), encoding: .utf8) else {
            throw XCTSkip("Fichier du dépôt illisible : \(cheminRelatif)")
        }
        return texte
    }

    /// Exceptions du contrat versionné, RPC par RPC (champ `exceptions`, lot 5).
    struct ExceptionContrat: Decodable, Equatable {
        var sqlstate: String
        var message: String
        var fonction: String
        var declencheur: String?
    }

    struct Contrat: Decodable {
        var name: String
        var statut: String
        var lot: Int
        var exceptions: [ExceptionContrat]?
    }

    struct Contrats: Decodable {
        var rpcs: [Contrat]
    }

    static func contrats() throws -> Contrats {
        try JSONDecoder().decode(Contrats.self, from: donnees("ios-native/rpc-contracts.json"))
    }
}
