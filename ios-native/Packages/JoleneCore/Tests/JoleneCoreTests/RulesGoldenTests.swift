import XCTest
@testable import JoleneCore

/// Valeur JSON générique : les vecteurs golden sont comparés structurellement,
/// jamais par chaîne, pour que l'ordre des clés et la mise en forme n'importent pas.
indirect enum JSONValue: Codable, Equatable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let conteneur = try decoder.singleValueContainer()
        if conteneur.decodeNil() {
            self = .null
        } else if let valeur = try? conteneur.decode(Bool.self) {
            self = .bool(valeur)
        } else if let valeur = try? conteneur.decode(Double.self) {
            self = .number(valeur)
        } else if let valeur = try? conteneur.decode(String.self) {
            self = .string(valeur)
        } else if let valeur = try? conteneur.decode([JSONValue].self) {
            self = .array(valeur)
        } else if let valeur = try? conteneur.decode([String: JSONValue].self) {
            self = .object(valeur)
        } else {
            throw DecodingError.dataCorruptedError(in: conteneur, debugDescription: "Valeur JSON non reconnue")
        }
    }

    func encode(to encoder: Encoder) throws {
        var conteneur = encoder.singleValueContainer()
        switch self {
        case .null: try conteneur.encodeNil()
        case .bool(let valeur): try conteneur.encode(valeur)
        case .number(let valeur): try conteneur.encode(valeur)
        case .string(let valeur): try conteneur.encode(valeur)
        case .array(let valeur): try conteneur.encode(valeur)
        case .object(let valeur): try conteneur.encode(valeur)
        }
    }

    subscript(cle: String) -> JSONValue? {
        if case .object(let objet) = self { return objet[cle] }
        return nil
    }

    var string: String? { if case .string(let v) = self { return v }; return nil }
    var double: Double? { if case .number(let v) = self { return v }; return nil }
    var int: Int? { double.map { Int($0) } }
    var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    var estNull: Bool { if case .null = self { return true }; return false }

    /// Ré-encode la valeur puis la décode dans un type Codable du socle
    /// (les clés snake_case des vecteurs sont celles de PostgREST).
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }

    static func depuis<T: Encodable>(_ valeur: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(valeur))
    }

    static func chaine(_ valeur: String?) -> JSONValue { valeur.map(JSONValue.string) ?? .null }
    static func instant(_ date: Date?) -> JSONValue { date.map { .string(DateHeureParis.isoUTC($0)) } ?? .null }

    /// Rendu canonique (clés triées) pour les messages d'échec.
    var description: String {
        switch self {
        case .null: return "null"
        case .bool(let v): return v ? "true" : "false"
        case .number(let v): return v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : "\(v)"
        case .string(let v): return "\"\(v)\""
        case .array(let v): return "[" + v.map(\.description).joined(separator: ",") + "]"
        case .object(let v): return "{" + v.keys.sorted().map { "\"\($0)\":\(v[$0]!.description)" }.joined(separator: ",") + "}"
        }
    }
}

struct VecteurGolden: Decodable {
    let name: String
    let input: JSONValue
    let expected: JSONValue

    var fonction: String { input["fonction"]?.string ?? "" }
}

/// Chargement et rejeu des fichiers golden exportés par
/// `scripts/mobile/export-golden-vectors.mjs` (règle : si un vecteur diverge,
/// on corrige le port Swift, jamais le vecteur).
enum Golden {
    static let fichiers = ["date-heure-paris", "format-mission", "heures-hebdomadaires-mission", "disponibilite-pointage",
                           // Lot 1, T2 : planning candidat, sélection de série, complétude du planning.
                           "planning-candidat", "selection-serie-candidat", "completude-planning-mission",
                           // Lot 3, T2 : routage push, compteur de sessions, montants et paiements, profil,
                           // modes d'exercice, listes RPPS.
                           "push-routing", "session-count", "mission-finance-display", "paiement-soignant-ui",
                           "valider-profil-soignant", "preferences-modes-exercice", "professions-rpps"]
    static let minimumTotal = 200

    struct FichierIntrouvable: Error, CustomStringConvertible {
        let fichier: String
        var description: String { "Fichier golden introuvable dans Bundle.module : Resources/golden/\(fichier).json" }
    }

    static func charger(_ fichier: String) throws -> [VecteurGolden] {
        guard let url = Bundle.module.url(forResource: fichier, withExtension: "json", subdirectory: "Resources/golden") else {
            throw FichierIntrouvable(fichier: fichier)
        }
        return try JSONDecoder().decode([VecteurGolden].self, from: Data(contentsOf: url))
    }

    /// Rejoue tous les vecteurs d'un fichier. `executer` renvoie `nil` pour une
    /// fonction inconnue, ce qui est un échec : aucun vecteur ne doit être ignoré.
    static func rejouer(_ fichier: String, file: StaticString = #filePath, line: UInt = #line,
                        _ executer: (VecteurGolden) throws -> JSONValue?) throws -> Int {
        let vecteurs = try charger(fichier)
        XCTAssertFalse(vecteurs.isEmpty, "\(fichier).json ne contient aucun vecteur", file: file, line: line)
        var rejoues = 0
        for vecteur in vecteurs {
            let obtenu: JSONValue?
            do {
                obtenu = try executer(vecteur)
            } catch {
                XCTFail("vecteur « \(vecteur.name) » : erreur inattendue \(error)", file: file, line: line)
                continue
            }
            guard let obtenu else {
                XCTFail("vecteur « \(vecteur.name) » : fonction « \(vecteur.fonction) » non rejouée", file: file, line: line)
                continue
            }
            rejoues += 1
            XCTAssertEqual(obtenu, vecteur.expected,
                           "vecteur « \(vecteur.name) » : attendu \(vecteur.expected), obtenu \(obtenu)",
                           file: file, line: line)
        }
        return rejoues
    }

    /// Exécute un calcul et convertit une erreur de date en `{ "erreur": code }`,
    /// exactement comme `capture()` du script d'export.
    static func capture(_ calcul: () throws -> JSONValue) -> JSONValue {
        do {
            return try calcul()
        } catch let erreur as DateHeureParisError {
            return .object(["erreur": .string(erreur.code)])
        } catch {
            return .object(["erreur": .string("INVALIDE")])
        }
    }

    static func instant(_ valeur: JSONValue?) throws -> Date {
        guard let chaine = valeur?.string else { throw DateHeureParisError.invalide("absent") }
        return try DateHeureParis.instantJolene(chaine)
    }

    /// `Number(x)` JavaScript pour `numeric` Postgres : nombre, chaîne ou nul.
    /// Renvoie `nil` pour nul ou NaN (traités comme 0 par toutes les règles).
    static func nombreJS(_ valeur: JSONValue?) -> Double? {
        switch valeur {
        case nil, .null?: return nil
        case .number(let nombre)?: return nombre
        case .bool(let booleen)?: return booleen ? 1 : 0
        case .string(let chaine)?:
            let nettoyee = chaine.trimmingCharacters(in: .whitespacesAndNewlines)
            if nettoyee.isEmpty { return 0 }
            guard let nombre = Double(nettoyee), !nombre.isNaN else { return nil }
            return nombre
        default: return nil
        }
    }

    static func entier(_ valeur: JSONValue?) -> Int? {
        guard let nombre = nombreJS(valeur) else { return nil }
        return Int(nombre)
    }
}

extension MissionSlot {
    /// Forme JSON d'un créneau telle que les vecteurs l'attendent (clés PostgREST,
    /// `id` et `mission_id` seulement lorsqu'ils existent, comme `JSON.stringify`).
    var golden: JSONValue {
        var objet: [String: JSONValue] = [
            "debut": .string(debut),
            "fin": .chaine(fin),
            "est_pause": .bool(estPause),
            "type_creneau": .string(typeCreneau),
        ]
        if let id { objet["id"] = .string(id) }
        if let missionId { objet["mission_id"] = .string(missionId) }
        return .object(objet)
    }
}

/// Garde globale du critère du lot 0 : au moins 200 vecteurs golden importés.
final class RulesGoldenTests: XCTestCase {
    func testAuMoins200VecteursGoldenSontImportes() throws {
        var total = 0
        for fichier in Golden.fichiers {
            let vecteurs = try Golden.charger(fichier)
            XCTAssertFalse(vecteurs.isEmpty, "\(fichier).json est vide")
            let noms = Set(vecteurs.map(\.name))
            XCTAssertEqual(noms.count, vecteurs.count, "\(fichier).json contient des noms de vecteurs dupliqués")
            // Deux vecteurs d'entrée identique (rendu canonique, clés triées) ne comptent qu'une
            // fois : l'export fusionne ces doublons, le test refuse qu'ils reviennent.
            var entrees: [String: String] = [:]
            for vecteur in vecteurs {
                let cle = vecteur.input.description
                if let premier = entrees[cle] {
                    XCTFail("\(fichier).json : « \(vecteur.name) » a la même entrée que « \(premier) »")
                } else {
                    entrees[cle] = vecteur.name
                }
            }
            XCTAssertEqual(entrees.count, vecteurs.count, "\(fichier).json contient des entrées dupliquées")
            total += vecteurs.count
        }
        XCTAssertGreaterThanOrEqual(total, Golden.minimumTotal,
                                    "\(total) vecteurs golden chargés, le critère du lot 0 exige au moins \(Golden.minimumTotal)")
    }

    func testChaqueVecteurPorteNomEntreeEtAttendu() throws {
        for fichier in Golden.fichiers {
            for vecteur in try Golden.charger(fichier) {
                XCTAssertFalse(vecteur.name.isEmpty, "\(fichier).json : vecteur sans nom")
                XCTAssertFalse(vecteur.fonction.isEmpty, "\(fichier).json : vecteur « \(vecteur.name) » sans fonction")
            }
        }
    }
}
