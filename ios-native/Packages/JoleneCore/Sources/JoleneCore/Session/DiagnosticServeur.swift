import Foundation

#if DEBUG
/// Message serveur recopiable dans le diagnostic DEBUG de la session (revue de #1187, r2) : jeton, clé, uuid et adresse
/// masqués AVANT la troncature (jamais un fragment d'identifiant), espaces réduits, 160 caractères au plus. Même règle
/// que `messageServeur` du pré-vol STAGING (`scripts/mobile/staging-lot5-fixture.mjs`). Absent en Release.
public enum DiagnosticServeur {
    public static let limite = 160

    private static let masques: [(motif: String, remplacement: String)] = [
        (#"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*"#, "<jeton>"),
        (#"sb_(?:publishable|secret)_[A-Za-z0-9_-]+"#, "<clé>"),
        (#"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#, "<uuid>"),
        (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "<adresse>"),
        (#"\s+"#, " "),
    ]

    public static func masquer(_ texte: String) -> String {
        var resultat = texte
        for (motif, remplacement) in masques {
            resultat = resultat.replacingOccurrences(of: motif, with: remplacement, options: .regularExpression)
        }
        resultat = resultat.trimmingCharacters(in: .whitespacesAndNewlines)
        return resultat.count > limite ? String(resultat.prefix(limite)) + "…" : resultat
    }
}
#endif
