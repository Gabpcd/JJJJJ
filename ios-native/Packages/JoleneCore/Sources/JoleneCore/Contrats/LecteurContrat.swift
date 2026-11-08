import Foundation

/// Isolement du lecteur de contrat (lot 2, T9a ; décision 17, `LOT2_PLAN.md` §3 T9a) : règles pures appliquées par
/// la vue `WKWebView` de l'app (`Composition/ContratReaderView.swift`), qui affiche l'original contrôlé
/// (`OriginalContrat.html` : SHA-256 = `hash_document` = octets Storage). Le lecteur n'exécute aucun script
/// (`allowsContentJavaScript = false`), ne charge aucune ressource (règle `WKContentRuleList` ci-dessous et politique
/// CSP injectée), ne garde aucune donnée (`.nonPersistent()`) et ne suit aucune navigation hors du chargement
/// initial (`loadHTMLString(_, baseURL: nil)`, donc `about:blank`).
///
/// Écart assumé avec le web : le web affiche une vue DOMPurify du HTML (balises en liste blanche, `src/lib/sanitize.ts`
/// l.3-16) ; le natif rend les octets signés tels quels, isolés, plus deux balises `<meta>` d'en-tête (politique et
/// viewport) qui ne changent ni le texte ni l'empreinte du fichier partagé.
public enum LecteurContrat {
    /// Politique de contenu injectée (blueprint T9a) : aucune ressource, styles en ligne seulement.
    public static let politiqueContenu = "default-src 'none'; style-src 'unsafe-inline'"

    /// Balises injectées en tête du `<head>`, avant tout autre contenu.
    public static let entete = "<meta http-equiv=\"Content-Security-Policy\" content=\"" + politiqueContenu + "\">"
        + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"

    /// Identifiant de la règle compilée par `WKContentRuleListStore`.
    public static let identifiantRegles = "app.jolene.contrat-lecteur"

    /// Schémas de chargement bloqués (filtres WebKit : ni alternative `|`, ni groupe ; un filtre par schéma).
    static let filtresBloques = ["^https?:", "^wss?:", "^ftps?:", "^file:", "^data:", "^blob:"]

    /// Règle `WKContentRuleList` (JSON) : toute ressource chargée par l'un de ces schémas est bloquée.
    public static var regleBlocage: String {
        let regles = filtresBloques.map { filtre in
            "{\"trigger\":{\"url-filter\":\"" + filtre + "\"},\"action\":{\"type\":\"block\"}}"
        }
        return "[" + regles.joined(separator: ",") + "]"
    }

    /// Document affiché : l'en-tête injecté juste après l'ouverture du `<head>` (insensible à la casse, attributs
    /// admis, `<header>` exclu) ; à défaut un `<head>` créé après l'ouverture du `<html>`, sinon en tête du
    /// document. Le reste des octets est inchangé.
    public static func documentIsole(_ html: String) -> String {
        if let fin = finDeBalise("head", dans: html) {
            return String(html[..<fin]) + entete + String(html[fin...])
        }
        let head = "<head>" + entete + "</head>"
        if let fin = finDeBalise("html", dans: html) {
            return String(html[..<fin]) + head + String(html[fin...])
        }
        return head + html
    }

    /// Seul le chargement initial (`about:blank`, avant qu'il soit fait) est autorisé ; liens, formulaires,
    /// redirections, rechargements et ancres sont annulés et jamais ouverts ailleurs.
    public static func navigationAutorisee(url: URL?, chargementInitialFait: Bool) -> Bool {
        !chargementInitialFait && url?.absoluteString == "about:blank"
    }

    /// Index qui suit le `>` de la première balise ouvrante `<nom` (casse ignorée, suivie de `>`, `/` ou d'un blanc).
    private static func finDeBalise(_ nom: String, dans html: String) -> String.Index? {
        var debut = html.startIndex
        while let ouverture = html.range(of: "<" + nom, options: [.caseInsensitive], range: debut..<html.endIndex) {
            let apres = ouverture.upperBound
            guard apres < html.endIndex else { return nil }
            let suivant = html[apres]
            if suivant == ">" || suivant == "/" || suivant.isWhitespace {
                guard let fermeture = html[apres...].firstIndex(of: ">") else { return nil }
                return html.index(after: fermeture)
            }
            debut = apres
        }
        return nil
    }
}
