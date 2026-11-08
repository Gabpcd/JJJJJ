import CryptoKit
import Foundation

/// Motif pour lequel l'original d'un contrat n'est ni affiché, ni partagé, ni signable (`LOT2_PLAN.md` §2.5 ; motifs
/// du pilote `mobile-native/src/workflows/contracts/business.ts` l.29-45). L'écran choisit le texte du web
/// (`TextesWeb.Contrat.originalIndisponible` pour un contrat porteur d'une signature, sinon
/// `contenuPasDisponible` ; `cddAPreparer` : `TextesWeb.Contrat.cddAPreparer`).
public enum MotifOriginalIndisponible: Equatable, Sendable {
    /// Document non figé : HTML, `storage_path`, `hash_document` ou `contenu_html_rendu_le` absent (pilote `unprepared`).
    case nonFige
    /// Variable `{{…}}` restée dans le HTML (pilote `incomplete`, `fn_signer_contrat_otp` l.56556-56558).
    case variablesNonRendues
    /// `hash_document` hors format (64 hex minuscules) ou différent du SHA-256 UTF-8 du HTML.
    case hashMismatch
    /// Octets Storage différents du HTML (ou absents, hors du dossier du contrat, au-delà de 2 Mo).
    case storageMismatch
    /// Une signature (ou un OTP validé) porte une autre empreinte (pilote `signature_mismatch`).
    case signatureMismatch
    /// CDD sans original : préparé par l'employeur, aucune action soignant (décision 19).
    case cddAPreparer
    /// Rendu serveur refusé (`generate-contrat-mission-pdf` ≠ 200 ou `success` faux) : message serveur verbatim.
    case renduRefuse(messageServeur: String?)
}

/// Refus de l'original (`ContratsPort.original`) : jamais un original supposé, jamais une erreur de transport.
public struct ContratOriginalIndisponible: Error, Equatable, Sendable {
    public var motif: MotifOriginalIndisponible

    public init(motif: MotifOriginalIndisponible) {
        self.motif = motif
    }
}

/// Triple contrôle de l'original (§2.5) : SHA-256 des octets UTF-8 de `contenu_html` = `hash_document` (64 hex) =
/// octets de `contrats-signes/<storage_path>`, avec `storage_path` et `contenu_html_rendu_le` non nuls et aucune
/// variable non rendue — les conditions mêmes de `fn_signer_contrat_otp` (l.56549-56565). Aucune normalisation :
/// les octets affichés, partagés et signés sont exactement ceux que le serveur a figés.
public enum VerificationOriginal {
    /// Borne du téléchargement de l'original (blueprint T8 : 2 Mo).
    public static let tailleMaxOctets = 2 * 1024 * 1024
    /// Longueur maximale du chemin Storage (pilote `validContractStoragePath`).
    static let longueurMaxChemin = 255

    /// SHA-256 hexadécimal minuscule des octets UTF-8 (`sha256Hex` de l’edge, l.69-75).
    public static func empreinte(_ html: String) -> String {
        SHA256.hash(data: Data(html.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `/^[a-f0-9]{64}$/` (edge l.190, pilote `CONTRACT_SHA256`).
    public static func estEmpreinte(_ valeur: String?) -> Bool {
        guard let valeur else { return false }
        let scalaires = Array(valeur.unicodeScalars)
        return scalaires.count == 64 && scalaires.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// `<contratId>/<nom>.html`, nom `[A-Za-z0-9_-]+`, 255 caractères au plus (pilote `validContractStoragePath` ;
    /// l'edge écrit `${contratId}/${uuid}.html`, index.ts l.260).
    public static func cheminValide(_ chemin: String, contratId: String) -> Bool {
        let parties = chemin.components(separatedBy: "/")
        guard chemin.count <= longueurMaxChemin, parties.count == 2, parties[0] == contratId, !contratId.isEmpty,
              parties[1].hasSuffix(".html") else { return false }
        let nom = parties[1].dropLast(".html".count)
        return !nom.isEmpty && nom.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "_"
        }
    }

    /// Contrôles qui ne demandent pas Storage ; `nil` : le contrat peut être comparé à son objet Storage.
    public static func motifAvantStorage(_ contrat: ContratDetail) -> MotifOriginalIndisponible? {
        guard let html = contrat.contenuHtml, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let chemin = contrat.storagePath, !chemin.isEmpty, let hash = contrat.hashDocument, !hash.isEmpty,
              !(contrat.contenuHtmlRenduLe ?? "").isEmpty else { return .nonFige }
        if ContratMissionUi.contientVariablesContratNonRendues(html) { return .variablesNonRendues }
        guard cheminValide(chemin, contratId: contrat.id), html.utf8.count <= tailleMaxOctets else { return .storageMismatch }
        guard estEmpreinte(hash), empreinte(html) == hash else { return .hashMismatch }
        return nil
    }

    /// Triple contrôle complet, puis aucune signature sur une autre empreinte. Lève `ContratOriginalIndisponible`.
    public static func verifier(_ contrat: ContratDetail, octetsStorage: Data,
                                signatures: [SignatureCertificat]) throws -> OriginalContrat {
        if let motif = motifAvantStorage(contrat) { throw ContratOriginalIndisponible(motif: motif) }
        let html = contrat.contenuHtml ?? ""
        let empreinte = contrat.hashDocument ?? ""
        guard octetsStorage.count <= tailleMaxOctets, octetsStorage == Data(html.utf8) else {
            throw ContratOriginalIndisponible(motif: .storageMismatch)
        }
        let engagees = signatures.filter {
            $0.statutSignature == "signe" || !($0.signeA ?? "").isEmpty || !($0.otpValideA ?? "").isEmpty
        }
        guard engagees.allSatisfy({ $0.hashDocument == empreinte }) else {
            throw ContratOriginalIndisponible(motif: .signatureMismatch)
        }
        return OriginalContrat(contratId: contrat.id, html: html, empreinte: empreinte, numeroContrat: contrat.numeroContrat)
    }
}

/// Copie temporaire de l'original contrôlé, à partager ou imprimer (§2.7) : dossier temporaire de l'app, un
/// sous-dossier par copie, protection `complete`, exclue de la sauvegarde ; effacée à la fermeture de la feuille et
/// au changement d'epoch (`effacer`, `effacerTout`, appelés par l'écran, T9a). Jamais d'URL signée.
public enum FichierContratTemporaire {
    /// Échec d'écriture : texte du web (`ContratMission.tsx` l.428), repris tel quel.
    public static let messageIndisponible = "Aucun contrat téléchargeable pour le moment."

    public static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("jolene-contrats", isDirectory: true)
    }

    /// `Contrat-<numéro>.html` (numéro assaini, sinon l'identifiant), comme le partage prévu par T9a.
    public static func nomFichier(numero: String?, contratId: String) -> String {
        let base = (numero ?? "").isEmpty ? contratId : numero ?? contratId
        let assaini = String(base.unicodeScalars.map { scalaire -> Character in
            let permis = ("a"..."z").contains(scalaire) || ("A"..."Z").contains(scalaire) || ("0"..."9").contains(scalaire)
                || scalaire == "-" || scalaire == "_"
            return permis ? Character(scalaire) : "-"
        })
        return "Contrat-" + assaini + ".html"
    }

    /// Écrit les octets UTF-8 de l'original contrôlé ; lève `JoleneError(.unknown, messageIndisponible)`.
    public static func ecrire(_ original: OriginalContrat) throws -> URL {
        let gestionnaire = FileManager.default
        var sousDossier = dossier().appendingPathComponent(UUID().uuidString, isDirectory: true)
        var fichier = sousDossier.appendingPathComponent(nomFichier(numero: original.numeroContrat, contratId: original.contratId))
        do {
            try gestionnaire.createDirectory(at: sousDossier, withIntermediateDirectories: true)
            #if os(iOS)
            let options: Data.WritingOptions = [.atomic, .completeFileProtection]
            #else
            let options: Data.WritingOptions = [.atomic] // `swift test` macOS : pas de classe de protection
            #endif
            try Data(original.html.utf8).write(to: fichier, options: options)
            var exclusion = URLResourceValues()
            exclusion.isExcludedFromBackup = true
            try sousDossier.setResourceValues(exclusion)
            try fichier.setResourceValues(exclusion)
            return fichier
        } catch {
            try? gestionnaire.removeItem(at: sousDossier)
            throw JoleneError(.unknown, messageIndisponible)
        }
    }

    /// Efface une copie (et son sous-dossier) ; sans effet hors du dossier temporaire des contrats.
    public static func effacer(_ url: URL) {
        let racine = dossier().standardizedFileURL.path
        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard parent.path.hasPrefix(racine + "/") else { return }
        try? FileManager.default.removeItem(at: parent)
    }

    /// Efface toutes les copies (changement d'epoch, déconnexion).
    public static func effacerTout() {
        try? FileManager.default.removeItem(at: dossier())
    }
}
