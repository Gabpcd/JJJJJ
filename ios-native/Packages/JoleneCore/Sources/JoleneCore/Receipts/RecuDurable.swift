import Foundation

// Socle des reçus durables (blueprint `docs/mobile-swift/LOT2_PLAN.md` §2.6, PRINCIPES §4).
//
// Tout reçu se décrit par `RecuDurable` (domaine, utilisateur, essai, état terminal, succession des phases,
// encodage versionné et relecture fail-closed) ; le journal générique `ReceiptJournal` (même dossier) les écrit
// dans un `ReceiptStorePort` (Keychain : `JoleneSupabase/Keychain/KeychainReceiptStore.swift`, service
// `app.jolene.receipts`), une clé par utilisateur et par domaine. Décision 23 du lot 2 : la tranche T7 du lot 1,
// qui devait livrer ce journal, n'existe sur aucune branche ; T1 du lot 2 le livre et T7 le consomme sans changer
// son API (`docs/mobile-swift/DECISIONS_LOT2.md`). Les transitions des reçus sont des fonctions pures.

/// Ce qu'un journal de reçus borné par utilisateur et par domaine doit savoir d'un reçu.
public protocol RecuDurable: Equatable, Sendable {
    /// Domaine de la clé du journal (`scan`, `document` ; `justificatif` au lot 1) : `^[a-z][a-z_]{0,31}$`.
    static var domaine: String { get }
    var userId: String { get }
    /// Identifiant de l'essai : deux reçus du même essai décrivent la même action (même envoi, même scan).
    var attemptId: String { get }
    /// Vrai quand plus rien n'est en vol : le journal peut le remplacer par un autre essai ou l'effacer.
    var estTermine: Bool { get }
    /// Contrôle de succession dans le journal. `precedent` : reçu du MÊME essai déjà journalisé, nil s'il n'y en a
    /// pas (premier enregistrement : phase initiale `prepared` seulement, `de: "absent"`). Champs immuables
    /// identiques (`RecuErreur.champInvalide(nom)`), puis réécriture à l'identique ou transition du graphe
    /// (`RecuErreur.transitionInterdite`). Jamais de retour en arrière.
    func verifierSuccession(apres precedent: Self?) throws
    /// JSON versionné, clés triées, sans secret, sans code saisi, sans octet de fichier ni URL signée.
    func encoder() throws -> Data
    /// Relecture stricte : version inconnue, clé inattendue ou invariant rompu → `RecuErreur.illisible` ;
    /// reçu d'un autre utilisateur → `RecuErreur.utilisateurDifferent`. Jamais de réparation silencieuse.
    /// Une version N+1 relit toujours la version N (décodeur de la N conservé) ; la N ne relit jamais la N+1.
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
    /// Reçu illisible ou altéré, ou journal inaccessible (`ReceiptJournal` : tout échec du magasin).
    case illisible
}

extension RecuErreur {
    /// Premier enregistrement d'un essai hors de sa phase initiale.
    static func premierEnregistrement(vers phase: String) -> RecuErreur {
        .transitionInterdite(de: "absent", vers: phase)
    }
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
