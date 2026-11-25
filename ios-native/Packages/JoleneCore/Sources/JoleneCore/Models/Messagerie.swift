import Foundation

// Contrats d'échange de `MessageriePort` et de `RealtimePort` (lot 4, T7a ; `docs/mobile-swift/LOT4_PLAN.md` §2.3-§2.5,
// fiches de `CONTRATS_RPC_SOIGNANT.md`), déplacés de `Models/Lot4Results.swift` par la tranche qui les livre et complétés
// des colonnes réelles (`supabase/schema/public.sql` : `fn_lister_conversations_messagerie`,
// `fn_interlocuteurs_conversations`, tables `messages_chat`, `typing_status`, `presence_status`). Décodage tolérant :
// seules les clés qui conditionnent une action sont requises ; une valeur d'un autre type est ignorée seule. Les
// horodatages sont gardés tels que servis (microsecondes) : ils servent de curseur et de clé de relecture, jamais
// reformatés. Le contenu d'un message n'est jamais journalisé (§2.6).

/// Lecture tolérante d'un objet JSON : une clé absente, `null` ou d'un autre type vaut `nil` (jamais un échec).
struct ChampsTolerants<Cle: CodingKey> {
    let conteneur: KeyedDecodingContainer<Cle>

    func valeur(_ cle: Cle) -> ValeurJSON? { try? conteneur.decodeIfPresent(ValeurJSON.self, forKey: cle) }

    func texte(_ cle: Cle) -> String? {
        guard case .chaine(let texte)? = valeur(cle) else { return nil }
        return texte
    }

    func texteNonVide(_ cle: Cle) -> String? {
        guard let texte = texte(cle), !texte.isEmpty else { return nil }
        return texte
    }

    func requis(_ cle: Cle) throws -> String {
        guard let texte = texteNonVide(cle) else {
            throw DecodingError.keyNotFound(cle, .init(codingPath: conteneur.codingPath, debugDescription: "clé requise"))
        }
        return texte
    }

    /// Entier servi en nombre, ou en texte numérique (`bigint` : le web lit `Number(c.non_lus) || 0`).
    func entier(_ cle: Cle) -> Int? {
        switch valeur(cle) {
        case .nombre(let nombre)? where nombre.rounded() == nombre && abs(nombre) < 1e15: return Int(nombre)
        case .chaine(let texte)?: return Int(texte)
        default: return nil
        }
    }

    func vrai(_ cle: Cle) -> Bool {
        if case .booleen(true)? = valeur(cle) { return true }
        return false
    }
}

// MARK: - Liste des conversations

/// Curseur keyset `(ordre_le, id)` de `fn_lister_conversations_messagerie` (`p_avant`, `p_avant_id`).
public struct CurseurConversations: Equatable, Sendable {
    public var ordreLe: String
    public var id: String
    public init(ordreLe: String, id: String) { self.ordreLe = ordreLe; self.id = id }
}

/// Ligne de `fn_lister_conversations_messagerie` (`RETURNS TABLE(id, participant_1_id, participant_2_id, mission_id,
/// etablissement_id, soignant_id, dernier_message_le, cree_le, archived_at, autre_id, dernier_contenu, non_lus,
/// mission_intitule, ordre_le)`). Requis : `id`. `autre_id` : interlocuteur opérationnel de l'établissement pour le
/// soignant (cible du blocage) ; `non_lus` : affichage par conversation seulement (le badge est `fn_messages_non_lus`).
public struct ConversationApercu: Equatable, Sendable, Identifiable, Decodable {
    public var id: String
    public var participant1Id: String?
    public var participant2Id: String?
    public var missionId: String?
    public var etablissementId: String?
    public var soignantId: String?
    public var dernierMessageLe: String?
    public var creeLe: String?
    /// `archived_at` : non nul = lecture seule (archivage 30 jours après la mission).
    public var archivedAt: String?
    public var autreId: String?
    public var dernierContenu: String?
    public var nonLus: Int
    public var missionIntitule: String?
    /// `COALESCE(dernier_message_le, cree_le)` : clé de tri serveur et première moitié du curseur.
    public var ordreLe: String?

    enum CodingKeys: String, CodingKey {
        case id, participant1Id = "participant_1_id", participant2Id = "participant_2_id", missionId = "mission_id"
        case etablissementId = "etablissement_id", soignantId = "soignant_id", dernierMessageLe = "dernier_message_le"
        case creeLe = "cree_le", archivedAt = "archived_at", autreId = "autre_id", dernierContenu = "dernier_contenu"
        case nonLus = "non_lus", missionIntitule = "mission_intitule", ordreLe = "ordre_le"
    }

    public init(id: String, autreId: String? = nil, missionId: String? = nil, etablissementId: String? = nil,
                dernierContenu: String? = nil, nonLus: Int = 0, archivedAt: String? = nil, participant1Id: String? = nil,
                participant2Id: String? = nil, soignantId: String? = nil, dernierMessageLe: String? = nil,
                creeLe: String? = nil, missionIntitule: String? = nil, ordreLe: String? = nil) {
        self.id = id; self.autreId = autreId; self.missionId = missionId; self.etablissementId = etablissementId
        self.dernierContenu = dernierContenu; self.nonLus = nonLus; self.archivedAt = archivedAt
        self.participant1Id = participant1Id; self.participant2Id = participant2Id; self.soignantId = soignantId
        self.dernierMessageLe = dernierMessageLe; self.creeLe = creeLe; self.missionIntitule = missionIntitule
        self.ordreLe = ordreLe
    }

    public init(from decoder: Decoder) throws {
        let c = ChampsTolerants(conteneur: try decoder.container(keyedBy: CodingKeys.self))
        id = try c.requis(.id)
        participant1Id = c.texteNonVide(.participant1Id)
        participant2Id = c.texteNonVide(.participant2Id)
        missionId = c.texteNonVide(.missionId)
        etablissementId = c.texteNonVide(.etablissementId)
        soignantId = c.texteNonVide(.soignantId)
        dernierMessageLe = c.texteNonVide(.dernierMessageLe)
        creeLe = c.texteNonVide(.creeLe)
        archivedAt = c.texteNonVide(.archivedAt)
        autreId = c.texteNonVide(.autreId)
        dernierContenu = c.texteNonVide(.dernierContenu)
        nonLus = max(0, c.entier(.nonLus) ?? 0)
        missionIntitule = c.texteNonVide(.missionIntitule)
        ordreLe = c.texteNonVide(.ordreLe)
    }

    /// Dérivé de `archived_at` (jamais un second champ qui pourrait diverger).
    public var archivee: Bool { archivedAt != nil }

    /// Curseur de la page suivante quand cette ligne est la dernière ; `nil` sans `ordre_le` (pagination arrêtée).
    public var curseur: CurseurConversations? { ordreLe.map { CurseurConversations(ordreLe: $0, id: id) } }

    /// Clé de tri du web après un message reçu (`dernier_message_le || cree_le`, `PageMessagerie.tsx`).
    public var triLe: String? { dernierMessageLe ?? creeLe ?? ordreLe }
}

/// Page de conversations ; `suivant` nil quand la page est incomplète ou que le curseur ne change plus (arrêt).
public struct PageConversations: Equatable, Sendable {
    /// Taille de page, comme le web (`p_limite: 100`, bornée 1-100 par le serveur).
    public static let taille = 100
    /// Garde-fou du web : cent pages au plus par chargement.
    public static let pagesMax = 100

    public var conversations: [ConversationApercu]
    public var suivant: CurseurConversations?
    public init(conversations: [ConversationApercu], suivant: CurseurConversations?) {
        self.conversations = conversations; self.suivant = suivant
    }
}

/// Ligne de `fn_interlocuteurs_conversations` (`conversation_id, participant_id, prenom, nom, avatar_url, est_jolene`),
/// deux au plus par conversation. Un établissement est servi avec `prenom` = son nom et `nom` vide ; ni soignant ni
/// établissement : `prenom` = nom de la plateforme, `est_jolene` vrai.
public struct Interlocuteur: Equatable, Sendable, Identifiable, Decodable {
    /// Identifiants au plus par appel (`Trop de conversations demandées` au-delà, 22023).
    public static let lotMax = 100

    public var conversationId: String
    public var participantId: String
    public var prenom: String?
    public var nom: String?
    public var avatarUrl: String?
    public var estJolene: Bool

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id", participantId = "participant_id", prenom, nom
        case avatarUrl = "avatar_url", estJolene = "est_jolene"
    }

    public init(conversationId: String, participantId: String, prenom: String?, nom: String?, avatarUrl: String? = nil,
                estJolene: Bool = false) {
        self.conversationId = conversationId; self.participantId = participantId; self.prenom = prenom; self.nom = nom
        self.avatarUrl = avatarUrl; self.estJolene = estJolene
    }

    public init(from decoder: Decoder) throws {
        let c = ChampsTolerants(conteneur: try decoder.container(keyedBy: CodingKeys.self))
        conversationId = try c.requis(.conversationId)
        participantId = try c.requis(.participantId)
        prenom = c.texteNonVide(.prenom)
        nom = c.texteNonVide(.nom)
        avatarUrl = c.texteNonVide(.avatarUrl)
        estJolene = c.vrai(.estJolene)
    }

    /// Clé d'index du web (`cleInterlocuteur`, `src/lib/messagerieInterlocuteurs.ts`).
    public static func cle(conversationId: String, participantId: String) -> String { "\(conversationId):\(participantId)" }

    public var id: String { Self.cle(conversationId: conversationId, participantId: participantId) }

    /// `${prenom} ${nom}`.trim() du web, valeurs serveur ; `nil` si les deux sont vides.
    public var nomServeur: String? {
        let texte = [prenom, nom].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return texte.isEmpty ? nil : texte
    }
}

// MARK: - Fil

/// Ligne de `messages_chat` (`id, conversation_id, auteur_id, contenu, lu, est_admin, cree_le`), lue par PostgREST ou
/// reçue d'un INSERT Realtime (mêmes clés). Requis : `id`, `conversation_id`, `contenu`. Contenu jamais journalisé.
public struct MessageChat: Equatable, Sendable, Identifiable, Decodable {
    /// Colonnes lues, comme le web (`PageMessagerie.tsx`).
    public static let colonnes = "id, conversation_id, auteur_id, contenu, est_admin, lu, cree_le"

    public var id: String
    public var conversationId: String
    public var auteurId: String?
    public var contenu: String
    public var estAdmin: Bool
    public var lu: Bool
    /// `cree_le` tel que servi : clé de tri et de relecture après « rejoint ».
    public var creeLe: String?

    enum CodingKeys: String, CodingKey {
        case id, conversationId = "conversation_id", auteurId = "auteur_id", contenu, estAdmin = "est_admin", lu
        case creeLe = "cree_le"
    }

    public init(id: String, conversationId: String, auteurId: String?, contenu: String, creeLe: String?,
                estAdmin: Bool = false, lu: Bool = false) {
        self.id = id; self.conversationId = conversationId; self.auteurId = auteurId; self.contenu = contenu
        self.creeLe = creeLe; self.estAdmin = estAdmin; self.lu = lu
    }

    public init(from decoder: Decoder) throws {
        let c = ChampsTolerants(conteneur: try decoder.container(keyedBy: CodingKeys.self))
        id = try c.requis(.id)
        conversationId = try c.requis(.conversationId)
        guard let texte = c.texte(.contenu) else {
            throw DecodingError.keyNotFound(CodingKeys.contenu, .init(codingPath: decoder.codingPath, debugDescription: "clé requise"))
        }
        contenu = texte
        auteurId = c.texteNonVide(.auteurId)
        estAdmin = c.vrai(.estAdmin)
        lu = c.vrai(.lu)
        creeLe = c.texteNonVide(.creeLe)
    }

    /// Instant de `cree_le` (milliseconde) ; `nil` s'il est absent ou illisible.
    public var instant: Date? { creeLe.flatMap(PlanningHorlogeParis.instant) }
}

/// `DetectedType` de `supabase/functions/_shared/anti-leak.ts`.
public enum DetectedType: String, Equatable, Sendable, CaseIterable {
    case telephone = "TELEPHONE"
    case email = "EMAIL"
    case url = "URL"
    case handle = "HANDLE"
    case keyword = "KEYWORD"
}

/// Issue de l'envoi par l'edge `messagerie-validate` : jamais un écho Realtime supposé.
public enum EnvoiOutcome: Equatable, Sendable {
    case envoye(messageId: String)
    case antiFuite(DetectedType?)
    /// `code` : code machine de l'edge (`CodeEnvoi`), jamais affiché ; `message` : texte serveur verbatim s'il en existe
    /// un, repli générique sinon.
    case refuse(code: String?, message: String)
    /// Délai dépassé, statut inattendu ou 200 sans `message_id` : relecture du fil, aucun renvoi automatique.
    case nonConfirme
}

/// Codes machine de l'edge `messagerie-validate` (`supabase/functions/messagerie-validate/index.ts`). L'écran les
/// traduit en libellés du web ; ils ne sont jamais affichés.
public enum CodeEnvoi {
    public static let antiFuite = "ANTI_LEAK_REFUSE"
    public static let requeteInvalide = "BAD_REQUEST"
    public static let contenuVide = "CONTENT_EMPTY"
    public static let nonAuthentifie = "NON_AUTHENTIFIE"
    public static let conversationNonAutorisee = "CONVERSATION_NON_AUTORISEE"
    public static let envoiRefuse = "ENVOI_REFUSE"
    public static let conversationArchivee = "CONVERSATION_ARCHIVEE"
    public static let contenuTropLong = "CONTENT_TOO_LARGE"
    public static let limite = "RATE_LIMIT"
    public static let erreurInterne = "INTERNAL_ERROR"
    public static let autorisationIndisponible = "AUTORISATION_INDISPONIBLE"
    public static let envoiIndisponible = "ENVOI_INDISPONIBLE"
    /// Longueur maximale d'un message (`MAX_CONTENT_LENGTH` de l'edge, `MAX_LENGTH` du composeur web).
    public static let longueurMax = 4000
}

/// Issue de `fn_marquer_messages_lus` : `42501 Accès refusé` est un refus métier, jamais « session expirée ».
public enum IssueLecture: Equatable, Sendable {
    case lus
    case accesRefuse
}

/// Issue de « Écrire à l'établissement » (`fn_user_id_pour_etablissement` puis `fn_obtenir_conversation`).
public enum IssueConversationMission: Equatable, Sendable {
    case conversation(id: String)
    /// Interlocuteur introuvable ou relation refusée : message serveur verbatim s'il existe, repli générique sinon.
    case indisponible(message: String)
}

/// Cible d'un signalement (`fn_signaler_utilisateur`, `p_cible_type`).
public enum TypeCibleSignalement: String, Equatable, Sendable, CaseIterable {
    case etablissement = "ETABLISSEMENT"
    case soignant = "SOIGNANT"
}

/// Valeurs de `p_categorie` admises par `fn_signaler_utilisateur` (hors liste : « Catégorie invalide ») et longueur
/// minimale du motif. Les libellés affichés sont ceux du web, repris par l'écran (T7b).
public enum SignalementUtilisateur {
    public static let categories = ["COMPORTEMENT_INAPPROPRIE", "FRAUDE_SUSPECTEE", "FAUX_DOCUMENT", "NON_PROFESSIONNALISME",
                                    "SECURITE_DANGER", "USURPATION_IDENTITE", "AUTRE"]
    public static let longueurMotifMin = 10
}

// MARK: - Realtime

/// Saisie en cours d'un participant (`typing_status` : INSERT / UPDATE = en train, DELETE = arrêt).
public struct EtatSaisie: Equatable, Sendable {
    /// Durée de vie d'un indicateur sans rafraîchissement (`TYPING_STALE_MS`, `useConversationRealtime.ts`).
    public static let peremption: TimeInterval = 6

    public var userId: String
    public var enTrain: Bool
    public init(userId: String, enTrain: Bool) { self.userId = userId; self.enTrain = enTrain }
}

/// `presence_status_enum`.
public enum StatutPresence: String, Equatable, Sendable, CaseIterable {
    case enLigne = "ONLINE"
    case absent = "AWAY"
    case horsLigne = "OFFLINE"
}

/// Présence d'un interlocuteur (`presence_status` : `user_id, status, last_seen_at`). Un statut inconnu ou une ligne
/// supprimée vaut `horsLigne` : jamais un « en ligne » supposé.
public struct EtatPresence: Equatable, Sendable {
    public var userId: String
    public var statut: StatutPresence
    public var vuLe: Date?

    public init(userId: String, statut: StatutPresence, vuLe: Date?) {
        self.userId = userId; self.statut = statut; self.vuLe = vuLe
    }

    public var enLigne: Bool { statut == .enLigne }
}

/// État d'un canal Realtime : à chaque `rejoint` après coupure, relecture du fil (§2.5).
public enum EtatCanal: Equatable, Sendable {
    case connexion
    case rejoint
    case coupe
    case ferme
}

/// Ligne `typing_status` (`conversation_id, user_id, started_at`), lue par PostgREST ou reçue d'un changement Realtime.
public struct LigneSaisie: Equatable, Sendable, Decodable {
    public var conversationId: String?
    public var userId: String
    public var startedAt: String?

    enum CodingKeys: String, CodingKey { case conversationId = "conversation_id", userId = "user_id", startedAt = "started_at" }

    public init(from decoder: Decoder) throws {
        let c = ChampsTolerants(conteneur: try decoder.container(keyedBy: CodingKeys.self))
        userId = try c.requis(.userId)
        conversationId = c.texteNonVide(.conversationId)
        startedAt = c.texteNonVide(.startedAt)
    }
}

/// Ligne `presence_status` (`user_id, status, last_seen_at`), lue par PostgREST ou reçue d'un changement Realtime.
public struct LignePresence: Equatable, Sendable, Decodable {
    public var userId: String?
    public var status: String?
    public var lastSeenAt: String?

    enum CodingKeys: String, CodingKey { case userId = "user_id", status, lastSeenAt = "last_seen_at" }

    public init(userId: String?, status: String?, lastSeenAt: String?) {
        self.userId = userId; self.status = status; self.lastSeenAt = lastSeenAt
    }

    public init(from decoder: Decoder) throws {
        let c = ChampsTolerants(conteneur: try decoder.container(keyedBy: CodingKeys.self))
        userId = c.texteNonVide(.userId)
        status = c.texteNonVide(.status)
        lastSeenAt = c.texteNonVide(.lastSeenAt)
    }

    /// État de l'interlocuteur `userId` (statut inconnu → hors ligne).
    public func etat(userId: String) -> EtatPresence {
        EtatPresence(userId: userId, statut: status.flatMap(StatutPresence.init(rawValue:)) ?? .horsLigne,
                     vuLe: lastSeenAt.flatMap(PlanningHorlogeParis.instant))
    }
}
