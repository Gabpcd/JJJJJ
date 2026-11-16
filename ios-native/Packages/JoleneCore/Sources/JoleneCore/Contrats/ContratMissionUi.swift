import Foundation

/// Preuves de signature lues sur `contrats_mission` (type `PreuveSignature` du web).
public struct PreuveSignatureContrat: Codable, Equatable, Sendable {
    public var statut: String?
    public var signatureSoignant: Bool?
    public var signatureEtablissement: Bool?
    public var signatureSoignantLe: String?
    public var signatureEtablissementLe: String?

    public init(statut: String? = nil, signatureSoignant: Bool? = nil, signatureEtablissement: Bool? = nil,
                signatureSoignantLe: String? = nil, signatureEtablissementLe: String? = nil) {
        self.statut = statut; self.signatureSoignant = signatureSoignant; self.signatureEtablissement = signatureEtablissement
        self.signatureSoignantLe = signatureSoignantLe; self.signatureEtablissementLe = signatureEtablissementLe
    }

    enum CodingKeys: String, CodingKey {
        case statut
        case signatureSoignant = "signature_soignant"
        case signatureEtablissement = "signature_etablissement"
        case signatureSoignantLe = "signature_soignant_le"
        case signatureEtablissementLe = "signature_etablissement_le"
    }
}

/// Port de `src/lib/contratMissionUi.ts` : quel contenu de contrat afficher, et quand demander
/// le rendu serveur. Un document stocké ou signé n'est jamais réécrit.
public enum ContratMissionUi {
    /// Un statut `SIGNE…`, un drapeau de signature vrai ou une date de signature renseignée.
    public static func contratPossedeSignature(_ contrat: PreuveSignatureContrat?) -> Bool {
        guard let contrat else { return false }
        return (contrat.statut ?? "").hasPrefix("SIGNE")
            || contrat.signatureSoignant == true || contrat.signatureEtablissement == true
            || !(contrat.signatureSoignantLe ?? "").isEmpty || !(contrat.signatureEtablissementLe ?? "").isEmpty
    }

    /// `/\{\{\s*[^}]+\s*\}\}/` : « {{ », au moins un caractère autre que « } », puis « }} ».
    /// (`\s` étant inclus dans `[^}]`, la classe d'espaces n'ajoute aucune correspondance.)
    public static func contientVariablesContratNonRendues(_ html: String?) -> Bool {
        let unites = Array((html ?? "").utf16)
        let ouvrante = UInt16(UInt8(ascii: "{")), fermante = UInt16(UInt8(ascii: "}"))
        var index = 0
        while index + 1 < unites.count {
            defer { index += 1 }
            guard unites[index] == ouvrante, unites[index + 1] == ouvrante else { continue }
            var fin = index + 2
            while fin < unites.count, unites[fin] != fermante { fin += 1 }
            // Après la plus longue suite sans « } », seule une fermeture double peut conclure.
            if fin > index + 2, fin + 1 < unites.count, unites[fin + 1] == fermante { return true }
        }
        return false
    }

    /// Rendu serveur seulement sans original stocké et sans aucune preuve de signature : un
    /// changement de gabarit ne justifie jamais de réécrire un document figé. (Le premier
    /// paramètre web, le HTML, est ignoré par la règle et n'est pas repris.)
    public static func contratNecessiteRenduServeur(storagePath: String?, contrat: PreuveSignatureContrat?) -> Bool {
        (storagePath ?? "").isEmpty && !contratPossedeSignature(contrat)
    }

    /// Original serveur s'il faut le conserver ; sinon l'original s'il ne contient plus aucune
    /// variable, à défaut l'aperçu reconstitué.
    public static func choisirContenuContratAffiche(serveur: String?, reconstitue: String?, conserverOriginal: Bool = false) -> String {
        if conserverOriginal { return serveur ?? "" }
        if let serveur, !serveur.isEmpty, !contientVariablesContratNonRendues(serveur) { return serveur }
        return reconstitue ?? ""
    }
}
