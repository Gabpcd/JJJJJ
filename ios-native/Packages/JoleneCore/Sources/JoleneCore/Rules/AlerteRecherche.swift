import Foundation

/// Résultat de `preparerAlerteMissions` : la recherche exactement équivalente à réutiliser (jamais une recherche de
/// même nom avec d'autres critères), le nom libre et les critères à enregistrer.
public struct PreparationAlerte: Equatable, Sendable {
    public var deja: FiltreSauvegarde?
    public var nom: String
    public var filtres: FiltresAlerte

    public init(deja: FiltreSauvegarde?, nom: String, filtres: FiltresAlerte) {
        self.deja = deja; self.nom = nom; self.filtres = filtres
    }
}

/// Alerte rapide depuis les critères d'Explorer : port de `src/lib/alertes-recherche-missions.ts`, vecteurs
/// `alertes-recherche-missions.json` (L4-T2, `LOT4_PLAN.md` §3 T2 et §5 « `50` vs `50.0` »).
///
/// Clé de comparaison = `JSON.stringify` des filtres, clés de premier niveau triées : les nombres s'écrivent comme
/// en JavaScript (`25`, jamais `25.0` ; `1e+21`, `1e-7`), les textes avec les échappements de `JSON.stringify`, et deux
/// clés sont égales unité UTF-16 par unité (une forme décomposée n'égale pas la forme composée). Le web trie par
/// `localeCompare`, Swift par unités UTF-16 : les deux ordres coïncident sur les clés des critères, et deux objets aux
/// mêmes clés restent triés à l'identique quel que soit l'ordre ; les objets imbriqués, dont JSON relu par Swift ne
/// garde pas l'ordre, sont triés de même (domaine golden : au plus une clé). Les noms sont comparés par unités UTF-16 et
/// tronqués à 90 unités ; une troncature qui couperait une paire de substitution s'arrête avant elle (le web
/// enverrait une demi-paire, hors domaine golden).
public enum AlerteRecherche {
    public static let longueurNomMax = 90

    public static func preparer(criteres: FiltresAlerte, recherches: [FiltreSauvegarde], nomBase: String) -> PreparationAlerte {
        let cleCriteres = Array(cle(valeur(criteres)).utf16)
        let deja = recherches.first { Array(cle($0.filtres).utf16) == cleCriteres }
        let noms = Set(recherches.map { Array($0.nom.utf16) })
        let base = tronquer(nomBase, longueurNomMax)
        var nom = base
        var suffixe = 2
        while noms.contains(Array(nom.utf16)) {
            nom = "\(base) (\(suffixe))"
            suffixe += 1
        }
        return PreparationAlerte(deja: deja, nom: nom, filtres: criteres)
    }

    /// `{ ...criteres }` : les sept clés camelCase, toujours présentes.
    public static func valeur(_ criteres: FiltresAlerte) -> ValeurJSON {
        .objet([
            "profession": .chaine(criteres.profession),
            "rayonKm": .nombre(Double(criteres.rayonKm)),
            "tauxMin": .nombre(criteres.tauxMin),
            "typeContrat": .chaine(criteres.typeContrat),
            "urgentesOnly": .booleen(criteres.urgentesOnly),
            "horaire": .chaine(criteres.horaire),
            "villeRecherche": .chaine(criteres.villeRecherche),
        ])
    }

    /// Fonction `cle` du web : `JSON.stringify(Object.fromEntries(Object.entries(valeur).sort(...)))`. `Object.entries`
    /// d'un tableau ou d'un texte en donne les index (unités UTF-16 pour un texte) ; d'un nombre ou d'un booléen,
    /// aucune entrée. `null` vaut `{}` (`recherche.filtres ?? {}` de l'appelant).
    public static func cle(_ valeur: ValeurJSON) -> String {
        let entrees: [(String, String)]
        switch valeur {
        case .objet(let objet):
            entrees = objet.map { ($0.key, JSONJavaScript.stringify($0.value)) }
        case .tableau(let elements):
            entrees = elements.enumerated().map { (String($0.offset), JSONJavaScript.stringify($0.element)) }
        case .chaine(let texte):
            entrees = Array(texte.utf16).enumerated().map { (String($0.offset), JSONJavaScript.texte(unites: [$0.element])) }
        case .null, .nombre, .booleen:
            entrees = []
        }
        let triees = entrees.sorted { Array($0.0.utf16).lexicographicallyPrecedes(Array($1.0.utf16)) }
        return "{" + triees.map { JSONJavaScript.texte($0.0) + ":" + $0.1 }.joined(separator: ",") + "}"
    }

    /// `texte.slice(0, n)` sans couper une paire de substitution.
    static func tronquer(_ texte: String, _ longueur: Int) -> String {
        let unites = Array(texte.utf16)
        guard unites.count > longueur else { return texte }
        var fin = longueur
        if fin > 0 && UTF16.isLeadSurrogate(unites[fin - 1]) { fin -= 1 }
        return String(decoding: unites[..<fin], as: UTF16.self)
    }
}

/// `JSON.stringify` d'ECMAScript pour une valeur JSON (clés d'objet triées par unités UTF-16, cf. `AlerteRecherche`).
enum JSONJavaScript {
    static func stringify(_ valeur: ValeurJSON) -> String {
        switch valeur {
        case .null: return "null"
        case .booleen(let booleen): return booleen ? "true" : "false"
        case .nombre(let nombre): return nombre.isFinite ? self.nombre(nombre) : "null"
        case .chaine(let chaine): return texte(chaine)
        case .tableau(let elements): return "[" + elements.map(stringify).joined(separator: ",") + "]"
        case .objet(let objet):
            let cles = objet.keys.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
            return "{" + cles.map { texte($0) + ":" + stringify(objet[$0] ?? .null) }.joined(separator: ",") + "}"
        }
    }

    /// `Number::toString(10)` : chiffres les plus courts qui relisent le même `Double` (ceux de `description`, même
    /// critère que JavaScript), mis en forme selon les règles d'ECMAScript (notation décimale de 1e-6 à 1e21 exclu).
    static func nombre(_ valeur: Double) -> String {
        if valeur == 0 { return "0" } // -0 compris
        if valeur < 0 { return "-" + nombre(-valeur) }
        let description = "\(valeur)"
        var mantisse = Substring(description)
        var exposant = 0
        if let e = description.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantisse = description[..<e]
            exposant = Int(description[description.index(after: e)...]) ?? 0
        }
        var entier = mantisse
        var fraction: Substring = ""
        if let point = mantisse.firstIndex(of: ".") {
            entier = mantisse[..<point]
            fraction = mantisse[mantisse.index(after: point)...]
        }
        var chiffres = Array(entier + fraction)
        var n = entier.count + exposant // position de la virgule après le premier chiffre de `chiffres`
        while chiffres.count > 1, chiffres.first == "0" { chiffres.removeFirst(); n -= 1 }
        while chiffres.count > 1, chiffres.last == "0" { chiffres.removeLast() }
        let k = chiffres.count
        let texte = String(chiffres)
        if k <= n && n <= 21 { return texte + String(repeating: "0", count: n - k) }
        if 0 < n && n <= 21 { return String(chiffres[..<n]) + "." + String(chiffres[n...]) }
        if -6 < n && n <= 0 { return "0." + String(repeating: "0", count: -n) + texte }
        let e = n - 1
        let suffixe = "e" + (e < 0 ? "-" : "+") + String(abs(e))
        return k == 1 ? texte + suffixe : String(chiffres[0]) + "." + String(chiffres[1...]) + suffixe
    }

    /// `QuoteJSONString` : `"`, `\`, `\b \f \n \r \t`, autres contrôles en `\u00xx`, demi-paires en `\udxxx`.
    static func texte(_ chaine: String) -> String { texte(unites: Array(chaine.utf16)) }

    static func texte(unites: [UInt16]) -> String {
        var resultat: [UInt16] = [0x22]
        func ajoute(_ ascii: String) { resultat.append(contentsOf: ascii.utf16) }
        var index = 0
        while index < unites.count {
            let unite = unites[index]
            switch unite {
            case 0x08: ajoute("\\b")
            case 0x09: ajoute("\\t")
            case 0x0A: ajoute("\\n")
            case 0x0C: ajoute("\\f")
            case 0x0D: ajoute("\\r")
            case 0x22: ajoute("\\\"")
            case 0x5C: ajoute("\\\\")
            case 0x00..<0x20: ajoute(String(format: "\\u%04x", unite))
            case 0xD800...0xDBFF where index + 1 < unites.count && UTF16.isTrailSurrogate(unites[index + 1]):
                resultat.append(unite)
                resultat.append(unites[index + 1])
                index += 1
            case 0xD800...0xDFFF: ajoute(String(format: "\\u%04x", unite))
            default: resultat.append(unite)
            }
            index += 1
        }
        resultat.append(0x22)
        return String(decoding: resultat, as: UTF16.self)
    }
}
