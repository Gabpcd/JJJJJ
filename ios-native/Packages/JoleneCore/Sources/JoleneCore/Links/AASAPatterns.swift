import Foundation

/// Table des quinze motifs de `public/.well-known/apple-app-site-association`
/// (clé `paths`, format historique), dans l'ordre exact du fichier. Un test garde
/// la dérive entre cette constante et le fichier du dépôt.
///
/// Sémantique retenue pour le glob (documentation Apple du format `paths`) :
/// - `*` correspond à n'importe quelle sous-chaîne, y compris vide et y compris des « / »
///   (`/soignant/*` couvre `/soignant/missions/abc`) ;
/// - `?` correspond à exactement un caractère ;
/// - la comparaison est sensible à la casse et porte sur le chemin seul (ni query ni fragment) ;
/// - le premier motif qui correspond l'emporte (le préfixe `NOT` n'est pas utilisé ici).
/// Conséquence : `/soignant/missions`, `/soignant/missions/*`, `/etablissement/missions` et
/// `/etablissement/missions/*` sont redondants avec les motifs 1 et 2, mais conservés pour
/// refléter le fichier à l'identique.
public enum AASAPatterns {
    /// Hôtes déclarés dans `Jolene.entitlements` (`applinks:jolene.app`) : Apple sert le
    /// même fichier pour `www.`. Aucun autre hôte n'ouvre l'app par Universal Link.
    public static let hosts: Set<String> = ["jolene.app", "www.jolene.app"]

    public static let paths: [String] = [
        "/soignant/*",
        "/etablissement/*",
        "/groupe/*",
        "/admin/*",
        "/connexion",
        "/inscription/*",
        "/reset-password",
        "/auth/psc/callback",
        "/etab/invitation/*",
        "/mission/*",
        "/contrat/*",
        "/soignant/missions",
        "/soignant/missions/*",
        "/etablissement/missions",
        "/etablissement/missions/*",
    ]

    /// Premier motif (index et texte) correspondant au chemin, dans l'ordre du fichier.
    public static func firstMatch(path: String) -> (index: Int, pattern: String)? {
        for (index, pattern) in paths.enumerated() where matches(pattern: pattern, path: path) {
            return (index, pattern)
        }
        return nil
    }

    /// Correspondance glob (`*` sous-chaîne quelconque, `?` un caractère), sensible à la casse.
    public static func matches(pattern: String, path: String) -> Bool {
        glob(Array(pattern.unicodeScalars), 0, Array(path.unicodeScalars), 0)
    }

    private static func glob(_ p: [Unicode.Scalar], _ pi: Int, _ s: [Unicode.Scalar], _ si: Int) -> Bool {
        var pi = pi, si = si
        var starP = -1, starS = -1
        while si < s.count {
            if pi < p.count, p[pi] == "*" {
                starP = pi; starS = si; pi += 1
            } else if pi < p.count, p[pi] == "?" || p[pi] == s[si] {
                pi += 1; si += 1
            } else if starP >= 0 {
                starS += 1; si = starS; pi = starP + 1
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
