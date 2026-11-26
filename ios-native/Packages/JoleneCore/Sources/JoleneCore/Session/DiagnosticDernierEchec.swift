import Foundation

#if DEBUG
/// DEBUG seulement : dernier échec d'une lecture ou d'une écriture serveur (code PostgREST ou Postgres, statut HTTP,
/// message serveur masqué par `DiagnosticServeur`), noté par `SupabaseErrorMapping.map` (quatrième parcours STAGING
/// du lot 5, 26/11/2026). L'app le pose comme valeur d'accessibilité de `debug-dernier-echec` ; le XCUITest STAGING
/// l'écrit dans le journal du job quand une attente échoue. Jamais affiché ; ni jeton, ni adresse, ni identifiant.
/// Absent en Release.
public final class DiagnosticDernierEchec: @unchecked Sendable {
    public static let partage = DiagnosticDernierEchec()

    private let verrou = NSLock()
    private var courant: String?

    public init() {}

    public func noter(_ texte: String) {
        verrou.lock(); defer { verrou.unlock() }
        courant = texte
    }

    public var valeur: String? {
        verrou.lock(); defer { verrou.unlock() }
        return courant
    }

    public func effacer() {
        verrou.lock(); defer { verrou.unlock() }
        courant = nil
    }
}
#endif
