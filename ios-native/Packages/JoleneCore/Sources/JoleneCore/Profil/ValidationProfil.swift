import Foundation

/// Port de `validerProfilSoignant` (`src/lib/valider-profil-soignant.ts`) : garde de la réponse de
/// `fn_mon_profil_soignant_complet` avant tout affichage. Le RPC peut répondre HTTP 200 avec
/// `{ error }` ; ni cette réponse ni des champs de type incompatible ne deviennent un profil vide.
/// Rend les spécialités normalisées ; la lecture des champs autorisés (liste blanche, correction 7 du
/// blueprint) appartient au décodeur du profil, pas à cette garde.
public enum ValidationProfil {
    /// Toute levée du web (`Error('PROFIL_INVALIDE')` comme la `SyntaxError` de `JSON.parse`) : le web
    /// les traite de la même façon (`ProfilSoignant.tsx` l.153-156).
    public enum Erreur: Error, Equatable, Sendable {
        case profilInvalide
    }

    static let clesObligatoires = ["prenom", "nom", "email", "profession"]
    static let textes = ["email", "prenom", "nom", "profession", "specialite_medicale", "specialite_medicale_declaree",
                         "specialite_source", "rpps_verifie_le", "statut_liberal", "type_exercice", "telephone", "date_naissance",
                         "numero_rpps", "bio", "avatar_url", "ville_recherche", "types_contrat_acceptes", "type_contrat"]
    static let nombres = ["heures_cumulees", "adresse_lat", "adresse_lng", "rayon_deplacement_km",
                          "annees_experience", "taux_horaire_minimum", "urgence_rayon_km"]
    static let booleens = ["specialite_verifiee", "rpps_verifie", "attestation_cumul_activite",
                           "consentement_gps", "disponible_urgence", "tous_documents_valides"]

    /// Valide la ligne et rend `specialites` (texte JSON historique, tableau ou absence).
    public static func valider(_ donnees: ValeurJSON, userId: String) throws -> [String] {
        guard case .objet(let ligne) = donnees else { throw Erreur.profilInvalide }
        guard ligne["id"] == .chaine(userId), ligne["error"] == nil,
              clesObligatoires.allSatisfy({ ligne[$0] != nil }) else { throw Erreur.profilInvalide }
        for cle in textes {
            switch ligne[cle] {
            case nil, .null?, .chaine?: continue
            default: throw Erreur.profilInvalide
            }
        }
        for cle in nombres {
            switch ligne[cle] {
            case nil, .null?: continue
            case .nombre(let nombre)? where nombre.isFinite: continue
            default: throw Erreur.profilInvalide
            }
        }
        for cle in booleens {
            switch ligne[cle] {
            case nil, .null?, .booleen?: continue
            default: throw Erreur.profilInvalide
            }
        }
        switch ligne["specialites"] {
        case nil, .null?, .chaine("")?:
            return []
        case .chaine(let texte)?:
            return try specialitesDepuisJSON(texte)
        case .tableau(let elements)?:
            return try elements.map { element in
                guard case .chaine(let texte) = element else { throw Erreur.profilInvalide }
                return texte
            }
        default:
            throw Erreur.profilInvalide
        }
    }

    /// `JSON.parse(brut)` dont le résultat doit être un tableau de textes. Grammaire JSON stricte
    /// (espaces JSON seuls, ni virgule finale, ni caractère de contrôle brut) ; une séquence `\uD800`
    /// isolée, qu'aucune chaîne Swift ne représente, est refusée (hors domaine golden).
    static func specialitesDepuisJSON(_ texte: String) throws -> [String] {
        var lecteur = LecteurTableauTextes(Array(texte.unicodeScalars))
        return try lecteur.lire()
    }
}

/// Lecteur strict d'un texte JSON qui doit être un tableau de chaînes.
private struct LecteurTableauTextes {
    private let scalaires: [Unicode.Scalar]
    private var index = 0

    init(_ scalaires: [Unicode.Scalar]) { self.scalaires = scalaires }

    private var courant: Unicode.Scalar? { index < scalaires.count ? scalaires[index] : nil }

    private mutating func espaces() {
        while let scalaire = courant, scalaire == " " || scalaire == "\t" || scalaire == "\n" || scalaire == "\r" { index += 1 }
    }

    private mutating func attendre(_ attendu: Unicode.Scalar) throws {
        guard courant == attendu else { throw ValidationProfil.Erreur.profilInvalide }
        index += 1
    }

    mutating func lire() throws -> [String] {
        espaces()
        try attendre("[")
        espaces()
        var textes: [String] = []
        if courant == "]" {
            index += 1
        } else {
            while true {
                espaces()
                textes.append(try chaine())
                espaces()
                if courant == "," { index += 1; continue }
                try attendre("]")
                break
            }
        }
        espaces()
        guard index == scalaires.count else { throw ValidationProfil.Erreur.profilInvalide }
        return textes
    }

    private mutating func chaine() throws -> String {
        try attendre("\"")
        var sortie = String.UnicodeScalarView()
        while true {
            guard let scalaire = courant else { throw ValidationProfil.Erreur.profilInvalide }
            index += 1
            switch scalaire {
            case "\"":
                return String(sortie)
            case "\\":
                sortie.append(try echappement())
            default:
                guard scalaire.value >= 0x20 else { throw ValidationProfil.Erreur.profilInvalide }
                sortie.append(scalaire)
            }
        }
    }

    private mutating func echappement() throws -> Unicode.Scalar {
        guard let scalaire = courant else { throw ValidationProfil.Erreur.profilInvalide }
        index += 1
        switch scalaire {
        case "\"": return "\""
        case "\\": return "\\"
        case "/": return "/"
        case "b": return "\u{08}"
        case "f": return "\u{0C}"
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        case "u":
            let unite = try quatreHexa()
            if (0xD800...0xDBFF).contains(unite) {
                // Paire de substitution : `😀` → U+1F600.
                guard courant == "\\" else { throw ValidationProfil.Erreur.profilInvalide }
                index += 1
                try attendre("u")
                let basse = try quatreHexa()
                guard (0xDC00...0xDFFF).contains(basse),
                      let combine = Unicode.Scalar(0x10000 + ((unite - 0xD800) << 10) + (basse - 0xDC00)) else {
                    throw ValidationProfil.Erreur.profilInvalide
                }
                return combine
            }
            guard let simple = Unicode.Scalar(unite) else { throw ValidationProfil.Erreur.profilInvalide }
            return simple
        default:
            throw ValidationProfil.Erreur.profilInvalide
        }
    }

    private mutating func quatreHexa() throws -> UInt32 {
        var valeur: UInt32 = 0
        for _ in 0..<4 {
            guard let scalaire = courant, scalaire.isASCII, let chiffre = Character(scalaire).hexDigitValue else {
                throw ValidationProfil.Erreur.profilInvalide
            }
            index += 1
            valeur = valeur * 16 + UInt32(chiffre)
        }
        return valeur
    }
}
