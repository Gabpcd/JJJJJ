import Foundation

// Journal générique des reçus durables (PRINCIPES §4 : « un reçu est écrit en Keychain avant tout scan et tout
// upload » ; blueprint `docs/mobile-swift/LOT2_PLAN.md` §2.2 et §2.6 ; décision 23 de
// `docs/mobile-swift/DECISIONS_LOT2.md` : livré par T1 du lot 2 faute de T7 du lot 1, qui le consomme sans changer
// son API). Modèle : pilote `mobile-native/src/workflows/presence/attemptJournal.ts` (un emplacement versionné par
// utilisateur, opérations sérialisées, relecture après écriture, corruption et erreurs de stockage fail-closed).
//
// Fichier autonome (avec `RecuDurable.swift`) : aucune dépendance au reste du lot 2, pour que T7 du lot 1 le reprenne
// octet pour octet. Le magasin réel est `KeychainReceiptStore` (JoleneSupabase), injecté par `Appareil.recus`.

/// Clé d'un reçu : une par (domaine, utilisateur). Compte Keychain `<domaine>.<userId>`.
public struct CleRecu: Hashable, Sendable {
    public let domaine: String
    public let userId: String

    /// Nil si le domaine n'est pas `^[a-z][a-z_]{0,31}$` ou si l'utilisateur n'est pas un identifiant opaque
    /// (`[A-Za-z0-9._:-]{1,160}`, jamais de séparateur de chemin).
    public init?(domaine: String, userId: String) {
        guard Self.domaineValide(domaine), RecuValidation.identifiantValide(userId) else { return nil }
        self.domaine = domaine
        self.userId = userId
    }

    /// Compte du trousseau (le domaine ne contient jamais de point : la séparation est univoque).
    public var compte: String { "\(domaine).\(userId)" }

    static func domaineValide(_ valeur: String) -> Bool {
        guard (1...32).contains(valeur.count), let premier = valeur.unicodeScalars.first, ("a"..."z").contains(premier) else {
            return false
        }
        return valeur.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || $0 == "_" }
    }
}

/// Magasin d'octets des reçus (blueprint §2.2 : lecture, écriture, effacement d'un reçu borné par utilisateur et par
/// domaine). Une erreur de stockage est levée, jamais traduite en « aucun reçu » : le journal la rend illisible.
public protocol ReceiptStorePort: Sendable {
    /// Octets stockés, nil si aucun reçu.
    func lire(_ cle: CleRecu) throws -> Data?
    func ecrire(_ donnees: Data, pour cle: CleRecu) throws
    /// Effacer un reçu absent n'est pas une erreur.
    func effacer(_ cle: CleRecu) throws
}

/// Acteur global qui sérialise toutes les opérations de journal du processus (lire, vérifier, écrire, relire),
/// quelle que soit l'instance de `ReceiptJournal` : deux essais concurrents ne passent jamais tous deux le contrôle.
@globalActor
public actor JournalRecusActeur {
    public static let shared = JournalRecusActeur()
}

/// Journal d'un domaine de reçus (`Recu.domaine`), une clé par utilisateur.
///
/// - Écriture refusée (`RecuErreur.recuEnCours`) tant qu'un reçu non terminé d'un AUTRE essai existe ; pour le
///   même essai, `Recu.verifierSuccession(apres:)` (premier enregistrement en `prepared`, graphe des phases).
/// - Relecture après écriture : les octets relus doivent être ceux écrits.
/// - Tout échec du magasin, tout reçu illisible (JSON, version, clé, invariant, autre utilisateur, taille) donne
///   `RecuErreur.illisible`, SANS réparation : rien n'est réécrit ni effacé par-dessus. L'écran affiche le message
///   fail-closed du domaine (`RecuScan.messageIllisible`) et aucun nouvel essai n'est envoyé ; il propose le renvoi
///   web du domaine, qui n'utilise pas ce journal (voie de récupération des consignes T3, T6 et lot 1 T7 de
///   `docs/mobile-swift/DECISIONS_LOT2.md`). Versions : une version N+1 d'un reçu relit la version N ; la version N
///   ne relit jamais la N+1 (retour à un build antérieur : illisible, renvoi web).
public struct ReceiptJournal<Recu: RecuDurable>: Sendable {
    /// Taille maximale d'un reçu (pilote `attemptJournal.ts` l.14 : `MAX_BYTES = 64_000`).
    public static var tailleMax: Int { 64_000 }

    private let store: any ReceiptStorePort

    public init(store: any ReceiptStorePort) {
        self.store = store
    }

    /// Reçu de l'utilisateur dans ce domaine, nil s'il n'y en a pas.
    @JournalRecusActeur
    public func lire(userId: String) throws -> Recu? {
        try lire(try cleDe(userId))
    }

    /// Journalise `recu` (avant l'action pour `prepared`, à chaque transition ensuite).
    @JournalRecusActeur
    public func ecrire(_ recu: Recu) throws {
        let cle = try cleDe(recu.userId)
        let donnees = try Self.encoderRelisible(recu)
        let precedent = try lire(cle)
        if let precedent, !precedent.estTermine, precedent.attemptId != recu.attemptId {
            throw RecuErreur.recuEnCours
        }
        try recu.verifierSuccession(apres: precedent?.attemptId == recu.attemptId ? precedent : nil)
        do { try store.ecrire(donnees, pour: cle) } catch { throw RecuErreur.illisible }
        let relus: Data?
        do { relus = try store.lire(cle) } catch { throw RecuErreur.illisible }
        guard relus == donnees else { throw RecuErreur.illisible }
    }

    /// Efface le reçu de cet essai (succès relu, refus relu, essai abandonné). Aucun reçu : rien à faire ; reçu d'un
    /// autre essai : `recuEnCours`, jamais effacé.
    @JournalRecusActeur
    public func effacer(_ recu: Recu) throws {
        let cle = try cleDe(recu.userId)
        guard let precedent = try lire(cle) else { return }
        guard precedent.attemptId == recu.attemptId else { throw RecuErreur.recuEnCours }
        do { try store.effacer(cle) } catch { throw RecuErreur.illisible }
        let reste: Data?
        do { reste = try store.lire(cle) } catch { throw RecuErreur.illisible }
        guard reste == nil else { throw RecuErreur.illisible }
    }

    // MARK: - Interne

    private func cleDe(_ userId: String) throws -> CleRecu {
        guard let cle = CleRecu(domaine: Recu.domaine, userId: userId) else { throw RecuErreur.illisible }
        return cle
    }

    private func lire(_ cle: CleRecu) throws -> Recu? {
        let donnees: Data?
        do { donnees = try store.lire(cle) } catch { throw RecuErreur.illisible }
        guard let donnees else { return nil }
        guard donnees.count <= Self.tailleMax else { throw RecuErreur.illisible }
        do { return try Recu.decoder(donnees, userId: cle.userId) } catch { throw RecuErreur.illisible }
    }

    /// Encode puis relit le reçu à écrire : un reçu qui ne se relirait pas n'est jamais journalisé.
    private static func encoderRelisible(_ recu: Recu) throws -> Data {
        guard let donnees = try? recu.encoder(), donnees.count <= tailleMax,
              (try? Recu.decoder(donnees, userId: recu.userId)) != nil else {
            throw RecuErreur.illisible
        }
        return donnees
    }
}

/// Magasin de reçus en mémoire : mode démo (`Appareil.demo`) et tests. Aucun disque, aucun réseau ; vierge à chaque
/// instance.
public final class MagasinRecusEnMemoire: ReceiptStorePort, @unchecked Sendable {
    private let verrou = NSLock()
    private var elements: [CleRecu: Data] = [:]

    public init() {}

    public func lire(_ cle: CleRecu) throws -> Data? {
        verrou.lock(); defer { verrou.unlock() }
        return elements[cle]
    }

    public func ecrire(_ donnees: Data, pour cle: CleRecu) throws {
        verrou.lock(); defer { verrou.unlock() }
        elements[cle] = donnees
    }

    public func effacer(_ cle: CleRecu) throws {
        verrou.lock(); defer { verrou.unlock() }
        elements[cle] = nil
    }

    /// Clés présentes (inspection en démo et en test).
    public func cles() -> Set<CleRecu> {
        verrou.lock(); defer { verrou.unlock() }
        return Set(elements.keys)
    }
}
