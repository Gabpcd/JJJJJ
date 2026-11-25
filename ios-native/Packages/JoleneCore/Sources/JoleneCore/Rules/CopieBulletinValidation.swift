import Foundation

/// Décodage STRICT de `fn_lister_copies_bulletins` (exception assumée au décodage tolérant, `LOT4_PLAN.md` §2.4) : port
/// de `validerListeCopiesBulletins` et `copieBulletinTelechargeable` (`src/lib/copiesBulletins.ts`), vecteurs
/// `copie-bulletin-validation.json` (L4-T2) produits par la fonction web réelle.
///
/// Une seule ligne invalide refuse toute la liste, avec le message du web : aucune donnée n'est fabriquée ni filtrée
/// en silence. Écarts assumés, plus stricts que le web (échec fermé, hors domaine golden ; `jsonb_build_object` ne
/// produit ni l'un ni l'autre) :
/// - `publie_le` doit suivre le format date-heure ISO d'ECMAScript (date complète, `T` majuscule, secondes et fraction
///   facultatives, `Z` ou `±HH:MM`) ; le repli permissif de `Date.parse` dans V8 (espace, `t` minuscule, `+0000`,
///   chiffres non ASCII, date partielle…) est refusé ;
/// - `statut` doit être un texte : le web lit `String(row.statut)`, qui accepterait le tableau `["PUBLIEE"]`.
public enum CopieBulletinValidation {
    public static let messageListeNonVerifiable = "La liste des copies ne peut pas être vérifiée. Réessayez."
    /// Taille maximale d'une copie (10 Mio, borne du dépôt `empreintePdfCopie`).
    public static let tailleMaxOctets = 10 * 1024 * 1024

    public struct ListeNonVerifiable: Error, Equatable, Sendable, LocalizedError {
        public var message: String
        public init(message: String = CopieBulletinValidation.messageListeNonVerifiable) { self.message = message }
        public var errorDescription: String? { message }
    }

    public static func valider(_ data: ValeurJSON) throws -> [CopieBulletin] {
        guard case .tableau(let lignes) = data else { throw ListeNonVerifiable() }
        return try lignes.map { ligne in
            guard case .objet(let champs) = ligne, let copie = copie(champs) else { throw ListeNonVerifiable() }
            return copie
        }
    }

    /// `copieBulletinTelechargeable` : les anciennes versions restent consultables, le PDF retiré ne l'est plus.
    public static func telechargeable(_ statut: StatutCopieBulletin) -> Bool {
        statut == .publiee || statut == .remplacee
    }

    public static func telechargeable(statut: String) -> Bool {
        statut == StatutCopieBulletin.publiee.rawValue || statut == StatutCopieBulletin.remplacee.rawValue
    }

    // MARK: - Ligne

    static func copie(_ ligne: [String: ValeurJSON]) -> CopieBulletin? {
        func texte(_ cle: String) -> String? {
            if case .chaine(let valeur)? = ligne[cle] { return valeur }
            return nil
        }
        guard let id = texte("id"), estUUID(id),
              let etablissementId = texte("etablissement_id"), estUUID(etablissementId),
              let soignantId = texte("soignant_id"), estUUID(soignantId),
              let etablissementNom = texte("etablissement_nom"), texte("soignant_nom") != nil, texte("soignant_prenom") != nil,
              let periodeDebut = texte("periode_debut"), estJour(periodeDebut),
              let periodeFin = texte("periode_fin"), estJour(periodeFin),
              // Deux dates `yyyy-MM-dd` ASCII : l'ordre des octets est celui de `<=` sur les textes du web.
              !Array(periodeFin.utf8).lexicographicallyPrecedes(Array(periodeDebut.utf8)),
              let publieLe = texte("publie_le"), instantLisible(publieLe),
              let statutBrut = texte("statut"), let statut = StatutCopieBulletin(rawValue: statutBrut),
              let version = entierSur(ligne["version"]), version > 0,
              let taille = entierSur(ligne["taille_octets"]), taille > 0, taille <= Double(tailleMaxOctets),
              let sha256 = texte("sha256"), estSha256(sha256),
              case .tableau(let missions)? = ligne["mission_ids"], !missions.isEmpty,
              case .booleen(let signalee)? = ligne["signalee"]
        else { return nil }
        var missionIds: [String] = []
        for mission in missions {
            guard case .chaine(let missionId) = mission, estUUID(missionId) else { return nil }
            missionIds.append(missionId)
        }
        switch ligne["remplace_id"] {
        case .null?: break
        case .chaine(let remplaceId)? where estUUID(remplaceId): break
        default: return nil
        }
        let motifRemplacement: MotifRemplacementCopie?
        switch ligne["motif_remplacement"] {
        case .null?: motifRemplacement = nil
        case .chaine("CONTENU")?: motifRemplacement = .contenu
        case .chaine("AUTRE")?: motifRemplacement = .autre
        default: return nil
        }
        // T10 : `version` est un entier sûr du web (`Number.isSafeInteger`), donc toujours représentable ici (64 bits).
        return CopieBulletin(id: id, etablissementId: etablissementId, employeurNom: etablissementNom,
                             periodeDebut: periodeDebut, periodeFin: periodeFin, statut: statut, version: Int(version),
                             publieLe: publieLe, motifRemplacement: motifRemplacement, tailleOctets: Int(taille),
                             sha256: sha256, missionIds: missionIds, signalee: signalee)
    }

    // MARK: - Contrôles de champ

    /// `/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i` (hexadécimal ASCII seulement).
    static func estUUID(_ valeur: String) -> Bool {
        let octets = Array(valeur.utf8)
        guard octets.count == 36 else { return false }
        for (index, octet) in octets.enumerated() {
            if [8, 13, 18, 23].contains(index) {
                guard octet == UInt8(ascii: "-") else { return false }
            } else if !estHexa(octet, majuscules: true) {
                return false
            }
        }
        return true
    }

    /// `/^[a-f0-9]{64}$/` (minuscules seulement).
    static func estSha256(_ valeur: String) -> Bool {
        let octets = Array(valeur.utf8)
        return octets.count == 64 && octets.allSatisfy { estHexa($0, majuscules: false) }
    }

    private static func estHexa(_ octet: UInt8, majuscules: Bool) -> Bool {
        (octet >= 0x30 && octet <= 0x39) || (octet >= 0x61 && octet <= 0x66) || (majuscules && octet >= 0x41 && octet <= 0x46)
    }

    /// `Number.isSafeInteger` d'un nombre JSON (un texte numérique est refusé, comme `typeof`).
    static func entierSur(_ valeur: ValeurJSON?) -> Double? {
        guard case .nombre(let nombre)? = valeur, nombre.isFinite, nombre.rounded(.towardZero) == nombre,
              abs(nombre) <= 9_007_199_254_740_991 else { return nil }
        return nombre
    }

    /// Jour `yyyy-MM-dd` (chiffres ASCII) qui existe au calendrier grégorien proleptique : le web exige `Date.parse`
    /// lisible (mois 1-12, jour 1-31) puis l'aller-retour `toISOString().slice(0, 10)` (« 2026-02-30 » refusé).
    static func estJour(_ valeur: String) -> Bool {
        var lecteur = LecteurASCII(valeur)
        guard let annee = lecteur.chiffres(4), lecteur.consomme("-"), let mois = lecteur.chiffres(2), lecteur.consomme("-"),
              let jour = lecteur.chiffres(2), lecteur.termine else { return false }
        return (1...12).contains(mois) && jour >= 1 && jour <= joursDansMois(annee: annee, mois: mois)
    }

    /// `!Number.isNaN(Date.parse(valeur))` sur le format date-heure ISO d'ECMAScript, bornes de V8 comprises : mois
    /// 1-12, jour 1-31 quel que soit le mois, heure 0-24 (24 seulement pour 24:00:00.000), minute et seconde 0-59,
    /// décalage ±00:00 à ±23:59. Hors de ce format : refus (voir l'en-tête).
    static func instantLisible(_ valeur: String) -> Bool {
        var lecteur = LecteurASCII(valeur)
        guard lecteur.chiffres(4) != nil, lecteur.consomme("-"), let mois = lecteur.chiffres(2), lecteur.consomme("-"),
              let jour = lecteur.chiffres(2), (1...12).contains(mois), (1...31).contains(jour) else { return false }
        if lecteur.termine { return true }
        guard lecteur.consomme("T"), let heure = lecteur.chiffres(2), lecteur.consomme(":"), let minute = lecteur.chiffres(2)
        else { return false }
        var seconde = 0
        var fractionNulle = true
        if lecteur.consomme(":") {
            guard let lue = lecteur.chiffres(2) else { return false }
            seconde = lue
            if lecteur.consomme(".") {
                guard let fraction = lecteur.chiffresVariables() else { return false }
                fractionNulle = fraction.allSatisfy { $0 == UInt8(ascii: "0") }
            }
        }
        guard heure <= 24, minute <= 59, seconde <= 59, heure < 24 || (minute == 0 && seconde == 0 && fractionNulle) else { return false }
        if lecteur.termine { return true }
        if lecteur.consomme("Z") { return lecteur.termine }
        guard lecteur.consomme("+") || lecteur.consomme("-"), let decalageHeures = lecteur.chiffres(2), lecteur.consomme(":"),
              let decalageMinutes = lecteur.chiffres(2), lecteur.termine else { return false }
        return decalageHeures <= 23 && decalageMinutes <= 59
    }

    static func joursDansMois(annee: Int, mois: Int) -> Int {
        switch mois {
        case 2: return (annee % 4 == 0 && annee % 100 != 0) || annee % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

/// Lecteur d'octets ASCII (chiffres `0-9` seulement, comme `\d` sans drapeau `u`).
private struct LecteurASCII {
    private let octets: [UInt8]
    private var index = 0

    init(_ valeur: String) { octets = Array(valeur.utf8) }

    var termine: Bool { index == octets.count }

    mutating func consomme(_ caractere: Unicode.Scalar) -> Bool {
        guard index < octets.count, octets[index] == UInt8(ascii: caractere) else { return false }
        index += 1
        return true
    }

    mutating func chiffres(_ nombre: Int) -> Int? {
        guard index + nombre <= octets.count else { return nil }
        var valeur = 0
        for octet in octets[index..<(index + nombre)] {
            guard octet >= 0x30 && octet <= 0x39 else { return nil }
            valeur = valeur * 10 + Int(octet - 0x30)
        }
        index += nombre
        return valeur
    }

    mutating func chiffresVariables() -> [UInt8]? {
        let debut = index
        while index < octets.count, octets[index] >= 0x30, octets[index] <= 0x39 { index += 1 }
        return index > debut ? Array(octets[debut..<index]) : nil
    }
}
