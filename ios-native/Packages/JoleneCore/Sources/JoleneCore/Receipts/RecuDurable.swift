import Foundation

// Socle des reçus durables du lot 2 (blueprint `docs/mobile-swift/LOT2_PLAN.md` §2.6, PRINCIPES §4).
//
// Le journal qui les écrit en Keychain (`JoleneCore/Receipts/ReceiptJournal.swift` et
// `JoleneSupabase/Keychain/KeychainReceiptStore.swift`, service `app.jolene.receipts`, une clé par
// utilisateur et par domaine) est livré par la tranche T7 du lot 1, absente de la base de T1 (décision 23).
// Point d'extension minimal posé ici : tout reçu du lot 2 se décrit par `RecuDurable` (domaine, utilisateur,
// état terminal, encodage versionné et relecture fail-closed), de sorte que le journal de T7 puisse les
// stocker sans changer d'API. Les transitions sont des fonctions pures : aucun stockage ici.

/// Ce qu'un magasin de reçus borné par utilisateur et par domaine doit savoir d'un reçu.
public protocol RecuDurable: Equatable, Sendable {
    /// Domaine de la clé du journal (`scan`, `document` ; `justificatif` au lot 1).
    static var domaine: String { get }
    var userId: String { get }
    /// Vrai quand plus rien n'est en vol : le journal peut le remplacer ou l'effacer.
    var estTermine: Bool { get }
    /// JSON versionné, clés triées, sans secret, sans code saisi, sans octet de fichier ni URL signée.
    func encoder() throws -> Data
    /// Relecture stricte : version inconnue, clé inattendue ou invariant rompu → `RecuErreur.illisible` ;
    /// reçu d'un autre utilisateur → `RecuErreur.utilisateurDifferent`. Jamais de réparation silencieuse.
    static func decoder(_ data: Data, userId: String) throws -> Self
}

/// Refus des transitions et des relectures de reçu (fail-closed). Messages d'écran : constantes du
/// domaine (`RecuScan.messageRecuEnCours`, `RecuScan.messageIllisible`).
public enum RecuErreur: Error, Equatable, Sendable {
    /// Un reçu du même utilisateur est encore en vol : réconcilier avant tout nouvel envoi.
    case recuEnCours
    /// Reçu d'un autre utilisateur : le journal est tenu par utilisateur, c'est une corruption.
    case utilisateurDifferent
    /// Plus de preuves que la borne du reçu.
    case borneDepassee
    /// Champ hors contrat (nom du champ Swift).
    case champInvalide(String)
    /// Transition hors du graphe (phases encodées).
    case transitionInterdite(de: String, vers: String)
    /// Reçu illisible ou altéré.
    case illisible
}

enum RecuValidation {
    /// Identifiant opaque (utilisateur, mission, preuve) : même motif que le pilote (`attemptJournal.ts`
    /// l.34, `terminalId`), sans `/` (segment de chemin Storage pour un justificatif).
    static func identifiantValide(_ valeur: String) -> Bool {
        guard (1...160).contains(valeur.count) else { return false }
        return valeur.unicodeScalars.allSatisfy { scalaire in
            switch scalaire {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "_", ":", "-": return true
            default: return false
            }
        }
    }

    /// Relit un objet JSON en refusant toute clé hors de `autorisees`, puis le décode.
    static func decoderStrict<T: Decodable>(_ type: T.Type, _ data: Data, autorisees: Set<String>) throws -> T {
        guard let objet = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(objet.keys).isSubset(of: autorisees),
              let valeur = try? JSONDecoder().decode(T.self, from: data) else {
            throw RecuErreur.illisible
        }
        return valeur
    }

    static func encoder<T: Encodable>(_ valeur: T) throws -> Data {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.sortedKeys]
        return try encodeur.encode(valeur)
    }
}
