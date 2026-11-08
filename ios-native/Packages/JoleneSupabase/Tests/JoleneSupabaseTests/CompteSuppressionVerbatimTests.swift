import Foundation
import JoleneCore
import XCTest
import JoleneSupabase

/// HARD STOP n°4 (CLAUDE.md) : les textes RGPD de la suppression de compte sont ceux du web,
/// mot pour mot et en tutoiement, tant que Gabrielle n'a pas validé un autre wording
/// (`docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`, fiche « Edge `delete-account` »).
///
/// Le test lit la source web dans le dépôt (`#filePath`) : il vit dans JoleneSupabaseTests, exécuté
/// par `swift test` sur macOS (job « Cœur » de `ios-swift-ci.yml`), jamais sur le simulateur, au
/// contraire de JoleneCoreTests. Une reformulation côté web ou côté Swift sans validation le fait échouer.
final class CompteSuppressionVerbatimTests: XCTestCase {
    private static let sourceWeb = "src/components/profil-soignant/SectionConfidentialite.tsx"

    private func lireSourceWeb() throws -> String {
        var racine = URL(fileURLWithPath: #filePath)
        // …/ios-native/Packages/JoleneSupabase/Tests/JoleneSupabaseTests/<fichier> → racine du dépôt.
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let url = racine.appendingPathComponent(Self.sourceWeb)
        guard let texte = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("source web illisible : \(url.path)")
            return ""
        }
        return texte
    }

    /// Texte JSX ramené au texte affiché : `<strong>` retiré (« Tape <strong>SUPPRIMER</strong> pour
    /// confirmer. »), blancs et retours à la ligne fusionnés en une espace.
    static func texteAffiche(_ jsx: String) -> String {
        jsx.replacingOccurrences(of: "<strong>", with: "").replacingOccurrences(of: "</strong>", with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func testTextesRGPDIdentiquesALaSourceWeb() throws {
        let source = try lireSourceWeb()
        let web = Self.texteAffiche(source)
        let t = CompteSuppression.Textes.self
        for texte in [t.sectionTitre, t.sectionAvertissement, t.boutonOuvrir, t.confirmationAvertissement,
                      t.confirmationConsigne, t.boutonAnnuler, t.boutonConfirmer] {
            XCTAssertTrue(web.contains(texte), "« \(texte) » absent de \(Self.sourceWeb) : wording à faire valider (HARD STOP n°4)")
        }
        // La modale web enchaîne l'avertissement et la consigne dans un seul paragraphe (l.171-172).
        XCTAssertTrue(web.contains("\(t.confirmationAvertissement) \(t.confirmationConsigne)"))
        // Titre de la modale (l.170) : repris sans le pictogramme décoratif « 🗑️ ».
        XCTAssertTrue(web.contains("\(t.confirmationTitre)</h3>"))
        XCTAssertTrue(source.contains("placeholder=\"\(t.confirmationExemple)\""), "exemple de saisie l.178")
    }

    func testRegleDeSaisieEtRepliIdentiquesAuWeb() throws {
        let source = try lireSourceWeb()
        XCTAssertTrue(source.contains("deleteConfirmText !== '\(CompteSuppression.motConfirmation)'"),
                      "égalité stricte avec la phrase exigée (l.192)")
        XCTAssertTrue(source.contains("'\(CompteSuppression.refusParDefautMessage)'"), "repli sans message serveur (l.89)")
        XCTAssertTrue(source.contains("supabase.functions.invoke<DeleteAccountResponse>('\(SupabaseAccountGateway.fonction)', { body: {} })"),
                      "même edge, même corps (l.86)")
        XCTAssertTrue(source.contains("data?.success !== true"), "seul `success === true` vaut succès (l.88)")
        XCTAssertTrue(source.contains("signOut({ scope: 'local' })"), "purge locale après succès (l.96)")
    }
}
