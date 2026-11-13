import Foundation

/// Valeur JSON brute, comparée structurellement. Sert aux réponses dont le web contrôle le
/// type de chaque champ (`typeof x === 'boolean'`, `Number.isInteger`…) : un décodage typé
/// (`Bool?`) confondrait « absent » et « présent d'un autre type », et accepterait donc ce que
/// le web refuse. Ne porte jamais de logique métier.
public indirect enum ValeurJSON: Equatable, Sendable, Codable {
    case null
    case booleen(Bool)
    case nombre(Double)
    case chaine(String)
    case tableau([ValeurJSON])
    case objet([String: ValeurJSON])

    public init(from decoder: Decoder) throws {
        let conteneur = try decoder.singleValueContainer()
        // L'ordre compte : un booléen JSON n'est jamais lu comme un nombre, ni l'inverse.
        if conteneur.decodeNil() {
            self = .null
        } else if let valeur = try? conteneur.decode(Bool.self) {
            self = .booleen(valeur)
        } else if let valeur = try? conteneur.decode(Double.self) {
            self = .nombre(valeur)
        } else if let valeur = try? conteneur.decode(String.self) {
            self = .chaine(valeur)
        } else if let valeur = try? conteneur.decode([ValeurJSON].self) {
            self = .tableau(valeur)
        } else if let valeur = try? conteneur.decode([String: ValeurJSON].self) {
            self = .objet(valeur)
        } else {
            throw DecodingError.dataCorruptedError(in: conteneur, debugDescription: "Valeur JSON non reconnue")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var conteneur = encoder.singleValueContainer()
        switch self {
        case .null: try conteneur.encodeNil()
        case .booleen(let valeur): try conteneur.encode(valeur)
        case .nombre(let valeur): try conteneur.encode(valeur)
        case .chaine(let valeur): try conteneur.encode(valeur)
        case .tableau(let valeur): try conteneur.encode(valeur)
        case .objet(let valeur): try conteneur.encode(valeur)
        }
    }

    /// Champ d'un objet ; `nil` si la clé est absente ou si la valeur n'est pas un objet.
    public subscript(cle: String) -> ValeurJSON? {
        if case .objet(let objet) = self { return objet[cle] }
        return nil
    }
}
