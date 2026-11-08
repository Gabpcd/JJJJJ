import Foundation

/// Format d'export (`handleExportRGPD(fmt: 'json' | 'csv')`, `SectionConfidentialite.tsx` l.30).
public enum FormatExportRGPD: String, CaseIterable, Sendable {
    case json, csv

    /// `mime` (l.65, l.69).
    public var mime: String {
        switch self {
        case .json: return "application/json"
        case .csv: return "text/csv"
        }
    }

    /// `fmt.toUpperCase()` du message de succès (l.73).
    public var libelle: String { rawValue.uppercased() }
}

/// Issue de la lecture d'une réponse de `fn_rgpd_exporter_rate_limited`.
public enum IssueReponseExport: Equatable, Sendable {
    /// Objet sans `error` « vrai » : octets rendus tels quels (ordre des clés conservé jusqu'au fichier).
    case donnees(ExportDonneesRGPD)
    /// `{error}` « vrai » (l.37) : message serveur s'il est textuel, aucun fichier écrit.
    case refus(message: String?)
    /// Corps illisible ou non objet : refus de contrat (le serveur ne renvoie qu'un objet).
    case illisible
}

/// Fichier prêt à partager : nom, type et contenu UTF-8 (sans BOM), jamais persisté hors de son dossier
/// temporaire (`DossierExportTemporaire`).
public struct FichierExportRGPD: Equatable, Sendable {
    public var nom: String
    public var mime: String
    public var contenu: Data
}

/// Export RGPD du hub (lot 3, T11), port de `handleExportRGPD` (`SectionConfidentialite.tsx` l.30-78). Le
/// contenu est celui du serveur, jamais recalculé : JSON indenté `JSON.stringify(data, null, 2)` (l.68) ou CSV
/// aplati par `flatten` (l.53-64), dans l'ordre des clés d'un objet JavaScript (`JSONOrdonne`).
public enum ExportRGPD {
    /// Refus de limite de `fn_rgpd_exporter_rate_limited` (définition live relue le 08/11/2026) : valeur JSON
    /// réelle (le littéral SQL double l'apostrophe). Serveur, verbatim ; utilisé par la démo. Ligne du dump
    /// indicative : `CompteVerbatimTests` localise le texte dans le corps de la fonction.
    // source: supabase/schema/public.sql:55385
    public static let refusLimiteServeur = "Trop d'exports en peu de temps. Réessayez dans quelques minutes."

    /// `p_type_ressource: 'soignant'` (l.45) ; action `RGPD_EXPORT_DONNEES` (l.44).
    public static let auditTypeRessource = "soignant"

    /// `p_details: { format: fmt }` (l.46).
    public static func auditDetails(_ format: FormatExportRGPD) -> [String: String] { ["format": format.rawValue] }

    /// Réponse de la RPC (corps HTTP 200), lue comme le web : `data && typeof data === 'object' && data.error`.
    public static func analyserReponse(_ donnees: Data) -> IssueReponseExport {
        guard let racine = try? JSONOrdonne.analyser(donnees), case .objet = racine else { return .illisible }
        if let erreur = racine["error"], erreur.estVraie {
            if case .chaine(let message) = erreur { return .refus(message: message) }
            return .refus(message: nil)
        }
        return .donnees(ExportDonneesRGPD(json: donnees))
    }

    /// `mes-donnees-jolene-${new Date().toISOString().slice(0, 10)}.<ext>` (l.66, l.70) : date UTC.
    public static func nomFichier(format: FormatExportRGPD, maintenant: Date) -> String {
        let formateur = ISO8601DateFormatter()
        formateur.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        formateur.timeZone = TimeZone(secondsFromGMT: 0)
        return "mes-donnees-jolene-\(formateur.string(from: maintenant)).\(format.rawValue)"
    }

    /// Fichier du format demandé ; lève si le corps n'est pas un objet JSON (jamais un fichier d'erreur).
    public static func fichier(_ donnees: ExportDonneesRGPD, format: FormatExportRGPD, maintenant: Date) throws -> FichierExportRGPD {
        let racine = try JSONOrdonne.analyser(donnees.json)
        guard case .objet = racine else { throw JSONOrdonne.ErreurAnalyse(position: 0) }
        let texte: String
        switch format {
        case .json: texte = contenuJSON(racine)
        case .csv: texte = contenuCSV(racine)
        }
        return FichierExportRGPD(nom: nomFichier(format: format, maintenant: maintenant), mime: format.mime, contenu: Data(texte.utf8))
    }

    /// `JSON.stringify(data, null, 2)` (l.68).
    public static func contenuJSON(_ racine: JSONOrdonne) -> String { racine.texteIndente }

    /// `'Champ,Valeur\n' + rows.map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n')`
    /// (l.64), lignes de `flatten` (l.55-62) : tableau → `JSON.stringify(v)` compact ; objet non nul → récursion
    /// avec le préfixe `parent.cle` (un objet vide n'ajoute aucune ligne) ; sinon `String(v ?? '')`.
    public static func contenuCSV(_ racine: JSONOrdonne) -> String {
        var lignes: [(String, String)] = []
        aplatir(racine, prefixe: "", dans: &lignes)
        let corps = lignes.map { ligne in [ligne.0, ligne.1].map(celluleCSV).joined(separator: ",") }
        return "Champ,Valeur\n" + corps.joined(separator: "\n")
    }

    /// `"${String(c).replace(/"/g, '""')}"` (l.64), scalaire par scalaire (revue B8, m4) : la recherche de
    /// `String` suit l'équivalence canonique et ne verrait pas un `"` suivi d'une marque combinante ; le web, lui,
    /// double chaque unité `"`.
    static func celluleCSV(_ valeur: String) -> String {
        var cellule = String.UnicodeScalarView()
        cellule.append("\"")
        for scalaire in valeur.unicodeScalars {
            cellule.append(scalaire)
            if scalaire == "\"" { cellule.append("\"") }
        }
        cellule.append("\"")
        return String(cellule)
    }

    private static func aplatir(_ valeur: JSONOrdonne, prefixe: String, dans lignes: inout [(String, String)]) {
        // `Object.entries(obj || {})` : seul un objet a des entrées ici (la racine est toujours un objet).
        guard case .objet(let membres) = valeur else { return }
        for membre in membres {
            let cle = prefixe.isEmpty ? membre.cle : "\(prefixe).\(membre.cle)"
            switch membre.valeur {
            case .tableau:
                lignes.append((cle, membre.valeur.texteCompact))
            case .objet:
                aplatir(membre.valeur, prefixe: cle, dans: &lignes)
            case .null:
                lignes.append((cle, ""))
            case .booleen(let booleen):
                lignes.append((cle, booleen ? "true" : "false"))
            case .nombre(let nombre):
                lignes.append((cle, texteNombre(nombre)))
            case .chaine(let chaine):
                lignes.append((cle, chaine))
            }
        }
    }

    /// `Number::toString` (`String(n)`) : chiffres les plus courts qui relisent le même `Double` (ceux de
    /// `description`, même règle), écrits selon ECMAScript — notation décimale pour un exposant décimal de
    /// −6 à 20, exponentielle `1e+21` / `1e-7` au-delà ; `-0` → `0`.
    public static func texteNombre(_ valeur: Double) -> String {
        if valeur.isNaN { return "NaN" }
        if valeur.isInfinite { return valeur < 0 ? "-Infinity" : "Infinity" }
        if valeur == 0 { return "0" }
        let signe = valeur < 0 ? "-" : ""
        let description = "\(abs(valeur))"
        var mantisse = Substring(description)
        var exposant = 0
        if let e = description.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantisse = description[..<e]
            exposant = Int(description[description.index(after: e)...]) ?? 0
        }
        let parties = mantisse.split(separator: ".", omittingEmptySubsequences: false)
        let entier = parties.first.map(String.init) ?? ""
        let fraction = parties.count > 1 ? String(parties[1]) : ""
        var chiffres = Array(entier + fraction)
        // Valeur = 0,c1c2…ck × 10^n.
        var n = entier.count + exposant
        while chiffres.first == "0" { chiffres.removeFirst(); n -= 1 }
        while chiffres.last == "0" { chiffres.removeLast() }
        let k = chiffres.count
        let texte = String(chiffres)
        if k <= n && n <= 21 { return signe + texte + String(repeating: "0", count: n - k) }
        if 0 < n && n <= 21 { return signe + texte.prefix(n) + "." + texte.dropFirst(n) }
        if -6 < n && n <= 0 { return signe + "0." + String(repeating: "0", count: -n) + texte }
        let e = n - 1
        let suffixe = "e" + (e < 0 ? "-" : "+") + String(abs(e))
        if k == 1 { return signe + texte + suffixe }
        return signe + texte.prefix(1) + "." + texte.dropFirst() + suffixe
    }

    /// Textes de la section. Ceux du web sont repris **mot pour mot, en tutoiement** (HARD STOP n°4 : wording
    /// RGPD non revalidé par Gabrielle, comme la suppression de compte du lot 1) ; gardés par `CompteVerbatimTests`.
    public enum Textes {
        // source: src/components/profil-soignant/SectionConfidentialite.tsx:111
        public static let titre = "Mes données (RGPD)"
        // source: src/components/profil-soignant/SectionConfidentialite.tsx:114
        public static let description = "Télécharge l'intégralité de tes données personnelles dans le format de ton choix."
        // source: src/components/profil-soignant/SectionConfidentialite.tsx:123
        public static let exporterJSON = "Exporter JSON"
        // source: src/components/profil-soignant/SectionConfidentialite.tsx:131
        public static let exporterCSV = "Exporter CSV"
        // source: src/components/profil-soignant/SectionConfidentialite.tsx:123
        public static let enCours = "Export…"
        // source: src/lib/erreurs.ts:532 (repli d'`extraireMessageErreur`, l.76)
        public static let echec = "Une erreur est survenue. Veuillez réessayer."

        /// `Données exportées en ${fmt.toUpperCase()}.` (l.73).
        public static func succes(_ format: FormatExportRGPD) -> String { "Données exportées en \(format.libelle)." }

        public static func bouton(_ format: FormatExportRGPD) -> String {
            switch format {
            case .json: return exporterJSON
            case .csv: return exporterCSV
            }
        }
    }
}
