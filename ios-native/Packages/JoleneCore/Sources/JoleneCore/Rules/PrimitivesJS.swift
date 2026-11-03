import Foundation

/// Primitives JavaScript dont dépendent les règles portées au lot 3 (T2) : `String.prototype.trim`,
/// `Number(valeur)`, `parseInt(texte, 10)`, `Number(x.toFixed(2))`, `String(n)` d'un entier et
/// `encodeURIComponent`. Portées à l'identique et couvertes par les vecteurs golden des règles qui
/// les appellent ; aucune règle métier ici.
enum PrimitivesJS {
    // MARK: - Espaces

    /// `WhiteSpace` et `LineTerminator` d'ECMAScript : ce que `trim`, `Number` et `parseInt`
    /// ignorent. U+FEFF en fait partie ; U+0085 et U+180E non (contrairement à
    /// `CharacterSet.whitespacesAndNewlines`, qui retire U+0085 et garde U+FEFF).
    static func estEspace(_ scalaire: Unicode.Scalar) -> Bool {
        switch scalaire.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// `String.prototype.trim`, scalaire par scalaire (les espaces JavaScript sont tous dans le plan
    /// multilingue de base : l'analyse UTF-16 et l'analyse par scalaire coïncident).
    static func trim(_ texte: String) -> String {
        let scalaires = Array(texte.unicodeScalars)
        guard let debut = scalaires.firstIndex(where: { !estEspace($0) }),
              let fin = scalaires.lastIndex(where: { !estEspace($0) }) else { return "" }
        var resultat = String.UnicodeScalarView()
        resultat.append(contentsOf: scalaires[debut...fin])
        return String(resultat)
    }

    // MARK: - Nombres

    /// `Number(valeur)` pour une valeur JSON (`nil` = `undefined`). Un tableau passe par
    /// `Array.prototype.join(",")` : vide → 0, un élément → son texte relu, au-delà la virgule rend NaN.
    static func nombre(_ valeur: ValeurJSON?) -> Double {
        guard let valeur else { return .nan }
        switch valeur {
        case .null: return 0
        case .booleen(let booleen): return booleen ? 1 : 0
        case .nombre(let nombre): return nombre
        case .chaine(let texte): return nombre(texte: texte)
        case .objet: return .nan // « [object Object] »
        case .tableau(let elements):
            guard elements.count == 1, let seul = elements.first else { return elements.isEmpty ? 0 : .nan }
            switch seul {
            case .null: return 0 // élément nul → ""
            case .nombre(let nombre): return nombre // `String(n)` relu par `Number` : aller-retour exact
            case .chaine(let texte): return nombre(texte: texte)
            case .tableau: return nombre(seul)
            case .booleen, .objet: return .nan // « true », « [object Object] »
            }
        }
    }

    /// `StringToNumber` : espaces JavaScript retirés, vide → 0, `0x`/`0o`/`0b` sans signe,
    /// `Infinity` signé, sinon littéral décimal strict (ni séparateur `_`, ni `inf`/`nan`).
    /// Limite : un entier non décimal au-delà de 2^53 est accumulé en `Double` (hors domaine golden).
    static func nombre(texte: String) -> Double {
        let scalaires = Array(trim(texte).unicodeScalars)
        guard !scalaires.isEmpty else { return 0 }
        if scalaires.count > 2, scalaires[0] == "0" {
            let base: Double?
            switch scalaires[1] {
            case "x", "X": base = 16
            case "o", "O": base = 8
            case "b", "B": base = 2
            default: base = nil
            }
            if let base { return entierNonDecimal(scalaires.dropFirst(2), base: base) }
        }
        var corps = scalaires[...]
        var signe = 1.0
        if let premier = corps.first, premier == "+" || premier == "-" {
            signe = premier == "-" ? -1 : 1
            corps = corps.dropFirst()
        }
        if String(String.UnicodeScalarView(corps)) == "Infinity" { return signe * .infinity }
        guard estLitteralDecimal(corps) else { return .nan }
        return Double(String(String.UnicodeScalarView(scalaires))) ?? .nan
    }

    private static func entierNonDecimal(_ chiffres: ArraySlice<Unicode.Scalar>, base: Double) -> Double {
        var valeur = 0.0
        for scalaire in chiffres {
            // ASCII seulement : `hexDigitValue` accepte aussi les chiffres pleine chasse.
            guard scalaire.isASCII, let chiffre = Character(scalaire).hexDigitValue, Double(chiffre) < base else { return .nan }
            valeur = valeur * base + Double(chiffre)
        }
        return valeur
    }

    /// `StrUnsignedDecimalLiteral` : `chiffres [. chiffres?] | . chiffres`, exposant facultatif.
    private static func estLitteralDecimal(_ scalaires: ArraySlice<Unicode.Scalar>) -> Bool {
        var index = scalaires.startIndex
        func chiffres() -> Int {
            var nombre = 0
            while index < scalaires.endIndex, ("0"..."9").contains(scalaires[index]) { index += 1; nombre += 1 }
            return nombre
        }
        var mantisse = chiffres()
        if index < scalaires.endIndex, scalaires[index] == "." {
            index += 1
            mantisse += chiffres()
        }
        guard mantisse > 0 else { return false }
        if index < scalaires.endIndex, scalaires[index] == "e" || scalaires[index] == "E" {
            index += 1
            if index < scalaires.endIndex, scalaires[index] == "+" || scalaires[index] == "-" { index += 1 }
            guard chiffres() > 0 else { return false }
        }
        return index == scalaires.endIndex
    }

    /// `parseInt(texte, 10)` : espaces de tête ignorés, signe facultatif, plus long préfixe de
    /// chiffres ASCII ; NaN sans chiffre.
    static func parseInt10(_ texte: String) -> Double {
        var scalaires = Array(texte.unicodeScalars)[...]
        while let premier = scalaires.first, estEspace(premier) { scalaires = scalaires.dropFirst() }
        var signe = 1.0
        if let premier = scalaires.first, premier == "+" || premier == "-" {
            signe = premier == "-" ? -1 : 1
            scalaires = scalaires.dropFirst()
        }
        let chiffres = scalaires.prefix { ("0"..."9").contains($0) }
        guard !chiffres.isEmpty, let valeur = Double(String(String.UnicodeScalarView(chiffres))) else { return .nan }
        return signe * valeur
    }

    /// `Number(x.toFixed(2))` : arrondi au centime de la valeur décimale exacte de `x`. Les égalités
    /// parfaites (x multiple impair de 1/8) vont vers la plus grande valeur absolue, comme `toFixed`
    /// (`printf` les arrondirait au pair) ; à partir de 1e21, `toFixed` rend `String(x)`, inchangé.
    static func arrondiCentimes(_ valeur: Double) -> Double {
        guard valeur.isFinite, abs(valeur) < 1e21 else { return valeur }
        let huitiemes = valeur * 8 // exact : multiplication par une puissance de 2
        if huitiemes == huitiemes.rounded(.towardZero), abs(huitiemes) < 9_007_199_254_740_992,
           Int64(huitiemes) % 2 != 0 {
            // |x| = m/8, m impair : |x|·100 + 0,5 = (25·m + 1) / 2 centimes, entier exact.
            let centimes = (25 * Int64(abs(huitiemes)) + 1) / 2
            let texte = (valeur < 0 ? "-" : "") + "\(centimes / 100)." + String(format: "%02lld", centimes % 100)
            return Double(texte) ?? valeur
        }
        return Double(String(format: "%.2f", valeur)) ?? valeur
    }

    /// `String(n)` d'un entier fini inférieur à 1e21 en valeur absolue (écriture décimale complète).
    static func texteEntier(_ valeur: Double) -> String {
        valeur == 0 ? "0" : String(format: "%.0f", valeur)
    }

    // MARK: - URI

    /// `encodeURIComponent` : octets UTF-8 encodés en `%XX` majuscules, sauf `A-Z a-z 0-9 - _ . ! ~ * ' ( )`.
    static func encodeURIComponent(_ texte: String) -> String {
        var sortie = ""
        for octet in texte.utf8 {
            switch octet {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x5F, 0x2E, 0x21, 0x7E, 0x2A, 0x27, 0x28, 0x29:
                sortie.unicodeScalars.append(Unicode.Scalar(octet))
            default:
                sortie += String(format: "%%%02X", octet)
            }
        }
        return sortie
    }
}
