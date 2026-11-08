import Foundation

/// Membre d'un objet JSON, dans l'ordre d'énumération d'un objet JavaScript.
public struct MembreJSON: Equatable, Sendable {
    public var cle: String
    public var valeur: JSONOrdonne

    public init(cle: String, valeur: JSONOrdonne) {
        self.cle = cle; self.valeur = valeur
    }
}

/// Valeur JSON lue comme `JSON.parse` du web la donnerait à `Object.entries` et à `JSON.stringify` (lot 3, T11,
/// export RGPD) : `ValeurJSON` et `AnyJSON` passent par des dictionnaires, qui perdent l'ordre des clés ; le
/// fichier exporté doit être celui du web, clé pour clé. Règles ECMAScript portées :
/// - ordre des propriétés propres (`OrdinaryOwnPropertyKeys`) : d'abord les indices de tableau (entier canonique
///   de 0 à 2^32 − 2) par ordre croissant, puis les autres clés dans l'ordre d'insertion ; une clé en double
///   garde sa première place et prend la dernière valeur (`CreateDataProperty`) ;
/// - nombres en `Double` (arrondi correct, comme `JSON.parse`) ;
/// - analyse stricte (RFC 8259, comme `JSON.parse`) : aucune virgule finale, aucun zéro de tête, aucun
///   caractère de contrôle brut dans une chaîne. Seul écart : une moitié de paire de substitution isolée
///   (`\ud83d`) est refusée, une `String` Swift ne pouvant pas la porter (un jsonb PostgreSQL n'en contient
///   jamais).
/// Aucune règle métier ici.
public indirect enum JSONOrdonne: Equatable, Sendable {
    case null
    case booleen(Bool)
    case nombre(Double)
    case chaine(String)
    case tableau([JSONOrdonne])
    case objet([MembreJSON])

    /// Erreur d'analyse (position en octets), jamais affichée.
    public struct ErreurAnalyse: Error, Equatable, Sendable {
        public let position: Int
    }

    public static func analyser(_ donnees: Data) throws -> JSONOrdonne {
        var analyseur = Analyseur(octets: Array(donnees))
        analyseur.espaces()
        let valeur = try analyseur.valeur(profondeur: 0)
        analyseur.espaces()
        guard analyseur.position == analyseur.octets.count else { throw ErreurAnalyse(position: analyseur.position) }
        return valeur
    }

    /// Valeur d'un membre (dernière valeur d'une clé), nil si absent ou si ce n'est pas un objet.
    public subscript(cle: String) -> JSONOrdonne? {
        guard case .objet(let membres) = self else { return nil }
        return membres.first { $0.cle == cle }?.valeur
    }

    /// Valeur « vraie » au sens JavaScript (`ToBoolean`) : tout sauf `null`, `false`, `0`, `-0`, `NaN` et `""`.
    public var estVraie: Bool {
        switch self {
        case .null: return false
        case .booleen(let valeur): return valeur
        case .nombre(let valeur): return valeur != 0 && !valeur.isNaN
        case .chaine(let valeur): return !valeur.isEmpty
        case .tableau, .objet: return true
        }
    }

    // MARK: - `JSON.stringify`

    /// `JSON.stringify(valeur)` (sans espace).
    public var texteCompact: String {
        var sortie = ""
        ecrire(dans: &sortie, indentation: nil, niveau: 0)
        return sortie
    }

    /// `JSON.stringify(valeur, null, 2)`.
    public var texteIndente: String {
        var sortie = ""
        ecrire(dans: &sortie, indentation: "  ", niveau: 0)
        return sortie
    }

    private func ecrire(dans sortie: inout String, indentation: String?, niveau: Int) {
        switch self {
        case .null:
            sortie += "null"
        case .booleen(let valeur):
            sortie += valeur ? "true" : "false"
        case .nombre(let valeur):
            // `SerializeJSONProperty` : un nombre non fini s'écrit `null`.
            sortie += valeur.isFinite ? ExportRGPD.texteNombre(valeur) : "null"
        case .chaine(let valeur):
            Self.citer(valeur, dans: &sortie)
        case .tableau(let elements):
            guard !elements.isEmpty else { sortie += "[]"; return }
            sortie += "["
            for (index, element) in elements.enumerated() {
                if index > 0 { sortie += "," }
                Self.retour(dans: &sortie, indentation: indentation, niveau: niveau + 1)
                element.ecrire(dans: &sortie, indentation: indentation, niveau: niveau + 1)
            }
            Self.retour(dans: &sortie, indentation: indentation, niveau: niveau)
            sortie += "]"
        case .objet(let membres):
            guard !membres.isEmpty else { sortie += "{}"; return }
            sortie += "{"
            for (index, membre) in membres.enumerated() {
                if index > 0 { sortie += "," }
                Self.retour(dans: &sortie, indentation: indentation, niveau: niveau + 1)
                Self.citer(membre.cle, dans: &sortie)
                sortie += indentation == nil ? ":" : ": "
                membre.valeur.ecrire(dans: &sortie, indentation: indentation, niveau: niveau + 1)
            }
            Self.retour(dans: &sortie, indentation: indentation, niveau: niveau)
            sortie += "}"
        }
    }

    private static func retour(dans sortie: inout String, indentation: String?, niveau: Int) {
        guard let indentation else { return }
        sortie += "\n" + String(repeating: indentation, count: niveau)
    }

    /// `QuoteJSONString` : `"` et `\` échappés, `\b \t \n \f \r`, autres unités < 0x20 en `\u00xx` minuscule ;
    /// tout le reste tel quel (ni `/`, ni non-ASCII, ni U+2028 échappés).
    private static func citer(_ texte: String, dans sortie: inout String) {
        sortie += "\""
        for scalaire in texte.unicodeScalars {
            switch scalaire {
            case "\"": sortie += "\\\""
            case "\\": sortie += "\\\\"
            case "\u{08}": sortie += "\\b"
            case "\u{09}": sortie += "\\t"
            case "\u{0A}": sortie += "\\n"
            case "\u{0C}": sortie += "\\f"
            case "\u{0D}": sortie += "\\r"
            default:
                if scalaire.value < 0x20 {
                    let hex = String(scalaire.value, radix: 16)
                    sortie += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    sortie.unicodeScalars.append(scalaire)
                }
            }
        }
        sortie += "\""
    }
}

// MARK: - Analyse

private struct Analyseur {
    let octets: [UInt8]
    var position = 0
    /// Garde contre une imbrication pathologique (pile) ; un export réel ne dépasse pas quelques niveaux.
    static let profondeurMaximale = 512

    init(octets: [UInt8]) { self.octets = octets }

    private func erreur() -> JSONOrdonne.ErreurAnalyse { JSONOrdonne.ErreurAnalyse(position: position) }

    mutating func espaces() {
        while position < octets.count, [0x20, 0x09, 0x0A, 0x0D].contains(octets[position]) { position += 1 }
    }

    mutating func valeur(profondeur: Int) throws -> JSONOrdonne {
        guard profondeur < Self.profondeurMaximale, position < octets.count else { throw erreur() }
        switch octets[position] {
        case UInt8(ascii: "{"): return try objet(profondeur: profondeur)
        case UInt8(ascii: "["): return try tableau(profondeur: profondeur)
        case UInt8(ascii: "\""): return .chaine(try chaine())
        case UInt8(ascii: "t"): try litteral("true"); return .booleen(true)
        case UInt8(ascii: "f"): try litteral("false"); return .booleen(false)
        case UInt8(ascii: "n"): try litteral("null"); return .null
        default: return .nombre(try nombre())
        }
    }

    private mutating func litteral(_ mot: String) throws {
        let attendu = Array(mot.utf8)
        guard position + attendu.count <= octets.count, Array(octets[position..<position + attendu.count]) == attendu else { throw erreur() }
        position += attendu.count
    }

    private mutating func objet(profondeur: Int) throws -> JSONOrdonne {
        position += 1
        var membres: [MembreJSON] = []
        var index: [String: Int] = [:]
        espaces()
        if position < octets.count, octets[position] == UInt8(ascii: "}") {
            position += 1
            return .objet([])
        }
        while true {
            espaces()
            guard position < octets.count, octets[position] == UInt8(ascii: "\"") else { throw erreur() }
            let cle = try chaine()
            espaces()
            guard position < octets.count, octets[position] == UInt8(ascii: ":") else { throw erreur() }
            position += 1
            espaces()
            let valeur = try valeur(profondeur: profondeur + 1)
            if let existant = index[cle] {
                membres[existant].valeur = valeur
            } else {
                index[cle] = membres.count
                membres.append(MembreJSON(cle: cle, valeur: valeur))
            }
            espaces()
            guard position < octets.count else { throw erreur() }
            if octets[position] == UInt8(ascii: ",") { position += 1; continue }
            guard octets[position] == UInt8(ascii: "}") else { throw erreur() }
            position += 1
            break
        }
        return .objet(Self.ordreJavaScript(membres))
    }

    private mutating func tableau(profondeur: Int) throws -> JSONOrdonne {
        position += 1
        var elements: [JSONOrdonne] = []
        espaces()
        if position < octets.count, octets[position] == UInt8(ascii: "]") {
            position += 1
            return .tableau([])
        }
        while true {
            espaces()
            elements.append(try valeur(profondeur: profondeur + 1))
            espaces()
            guard position < octets.count else { throw erreur() }
            if octets[position] == UInt8(ascii: ",") { position += 1; continue }
            guard octets[position] == UInt8(ascii: "]") else { throw erreur() }
            position += 1
            break
        }
        return .tableau(elements)
    }

    /// Chaîne JSON (guillemet ouvrant à `position`), échappements décodés ; octets UTF-8 invalides remplacés par
    /// U+FFFD comme le décodage du corps d'une réponse `fetch`.
    private mutating func chaine() throws -> String {
        position += 1
        var tampon: [UInt8] = []
        while true {
            guard position < octets.count else { throw erreur() }
            let octet = octets[position]
            switch octet {
            case UInt8(ascii: "\""):
                position += 1
                return String(decoding: tampon, as: UTF8.self)
            case UInt8(ascii: "\\"):
                position += 1
                guard position < octets.count else { throw erreur() }
                let echappe = octets[position]
                position += 1
                switch echappe {
                case UInt8(ascii: "\""): tampon.append(0x22)
                case UInt8(ascii: "\\"): tampon.append(0x5C)
                case UInt8(ascii: "/"): tampon.append(0x2F)
                case UInt8(ascii: "b"): tampon.append(0x08)
                case UInt8(ascii: "f"): tampon.append(0x0C)
                case UInt8(ascii: "n"): tampon.append(0x0A)
                case UInt8(ascii: "r"): tampon.append(0x0D)
                case UInt8(ascii: "t"): tampon.append(0x09)
                case UInt8(ascii: "u"):
                    let scalaire = try echappementUnicode()
                    tampon.append(contentsOf: Array(String(Character(scalaire)).utf8))
                default:
                    throw erreur()
                }
            default:
                guard octet >= 0x20 else { throw erreur() }
                tampon.append(octet)
                position += 1
            }
        }
    }

    /// `\uXXXX` (position après le `u`), paire de substitution recomposée.
    private mutating func echappementUnicode() throws -> Unicode.Scalar {
        let haut = try quatreHex()
        if (0xD800...0xDBFF).contains(haut) {
            guard position + 1 < octets.count, octets[position] == UInt8(ascii: "\\"), octets[position + 1] == UInt8(ascii: "u") else {
                throw erreur()
            }
            position += 2
            let bas = try quatreHex()
            guard (0xDC00...0xDFFF).contains(bas), let scalaire = Unicode.Scalar(0x10000 + ((haut - 0xD800) << 10) + (bas - 0xDC00)) else {
                throw erreur()
            }
            return scalaire
        }
        guard let scalaire = Unicode.Scalar(haut) else { throw erreur() } // moitié basse isolée
        return scalaire
    }

    private mutating func quatreHex() throws -> UInt32 {
        guard position + 4 <= octets.count else { throw erreur() }
        var valeur: UInt32 = 0
        for octet in octets[position..<position + 4] {
            guard let chiffre = Self.hexadecimal(octet) else { throw erreur() }
            valeur = valeur << 4 | chiffre
        }
        position += 4
        return valeur
    }

    private static func hexadecimal(_ octet: UInt8) -> UInt32? {
        switch octet {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return UInt32(octet - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return UInt32(octet - UInt8(ascii: "a") + 10)
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return UInt32(octet - UInt8(ascii: "A") + 10)
        default: return nil
        }
    }

    /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`, converti par `Double(_:)` (arrondi correct).
    private mutating func nombre() throws -> Double {
        let debut = position
        func chiffres() -> Int {
            let depart = position
            while position < octets.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(octets[position]) { position += 1 }
            return position - depart
        }
        if position < octets.count, octets[position] == UInt8(ascii: "-") { position += 1 }
        guard position < octets.count else { throw erreur() }
        if octets[position] == UInt8(ascii: "0") {
            position += 1
        } else {
            guard chiffres() > 0 else { throw erreur() }
        }
        if position < octets.count, octets[position] == UInt8(ascii: ".") {
            position += 1
            guard chiffres() > 0 else { throw erreur() }
        }
        if position < octets.count, octets[position] == UInt8(ascii: "e") || octets[position] == UInt8(ascii: "E") {
            position += 1
            if position < octets.count, octets[position] == UInt8(ascii: "+") || octets[position] == UInt8(ascii: "-") { position += 1 }
            guard chiffres() > 0 else { throw erreur() }
        }
        guard let valeur = Double(String(decoding: octets[debut..<position], as: UTF8.self)) else { throw erreur() }
        return valeur
    }

    /// `OrdinaryOwnPropertyKeys` : indices de tableau croissants d'abord, puis l'ordre d'insertion.
    static func ordreJavaScript(_ membres: [MembreJSON]) -> [MembreJSON] {
        var indices: [(UInt32, MembreJSON)] = []
        var autres: [MembreJSON] = []
        for membre in membres {
            if let indice = indiceDeTableau(membre.cle) { indices.append((indice, membre)) } else { autres.append(membre) }
        }
        return indices.sorted { $0.0 < $1.0 }.map { $0.1 } + autres
    }

    /// Indice de tableau ECMAScript : écriture décimale canonique d'un entier de 0 à 2^32 − 2.
    static func indiceDeTableau(_ cle: String) -> UInt32? {
        let unites = Array(cle.utf8)
        guard !unites.isEmpty, unites.count <= 10, unites.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        guard unites.count == 1 || unites[0] != 0x30 else { return nil }
        guard let valeur = UInt64(cle), valeur <= 4_294_967_294 else { return nil }
        return UInt32(valeur)
    }
}
