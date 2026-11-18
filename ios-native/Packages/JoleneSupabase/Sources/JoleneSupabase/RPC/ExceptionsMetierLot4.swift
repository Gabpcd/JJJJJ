import Foundation
import JoleneCore
import Supabase

/// Lecture des exceptions PostgREST du lot 4 : couple « SQLSTATE **et** message connu » (blueprint
/// `docs/mobile-swift/LOT4_PLAN.md` §2.4, corrections 14 et 15 ; fiche « Lot 4 — lecture des exceptions PostgREST et
/// des réponses edge » de `CONTRATS_RPC_SOIGNANT.md`).
///
/// Plusieurs RPC du lot 4 lèvent `42501` pour un refus métier (`fn_marquer_messages_lus` « Accès refusé »,
/// `fn_obtenir_conversation` « Conversation non autorisée », `fn_lister_copies_bulletins` `COPIE_ACCES_REFUSE`…), que
/// `SupabaseErrorMapping` (inchangé) traduirait en « Votre session a expiré », et `28000` pour une session absente, qu'il
/// réduirait au message générique. Contrairement à `exceptionsMetier:` du lot 3 (SQLSTATE seul), une règle du lot 4
/// peut exiger le message exact : un `42501` au message inconnu garde le comportement du lot 0 (`.unauthorized`).
///
/// Ordre : `[CODE DU TRAVAIL]` → règles déclarées par la RPC → `SupabaseErrorMapping`. Un `42501` « permission denied
/// for … » (GRANT manquant, incident #835) est toujours `.contract`, jamais restitué. Une seule requête, aucun renvoi.
public struct ExceptionsLot4: Equatable, Sendable {
    /// Traitement d'une exception reconnue.
    public enum Lecture: Equatable, Sendable {
        /// Restituée en refus structuré `{success:false, ok:false, code:"SQLSTATE_<x>", error:<message brut>}`
        /// (`RPCResponse.refusMetier`) : l'appelant la traduit en issue.
        case refusMetier
        /// `.unauthorized` (« Votre session a expiré »).
        case sessionExpiree
        /// `.contract` : défaut du client (curseur incomplet, interlocuteur invalide…), jamais « session expirée ».
        case contrat
    }

    public struct Regle: Equatable, Sendable {
        public let sqlstate: String
        /// Messages exacts (espaces de bord ignorés) ; `nil` : tout message de ce SQLSTATE.
        public let messages: Set<String>?
        public let lecture: Lecture

        public init(_ sqlstate: String, _ messages: Set<String>? = nil, _ lecture: Lecture) {
            self.sqlstate = sqlstate; self.messages = messages; self.lecture = lecture
        }
    }

    /// `28000` (`invalid_authorization_specification`, « Non authentifié » / `NON_AUTHENTIFIE`) : session absente, quel
    /// que soit le message. Toujours en tête : `SupabaseErrorMapping` ne connaît pas ce SQLSTATE.
    public static let sessionAbsente = Regle("28000", nil, .sessionExpiree)

    public let regles: [Regle]

    public init(_ regles: [Regle]) {
        self.regles = [Self.sessionAbsente] + regles
    }

    /// Lecture d'une exception, `nil` hors règles (comportement des lots 0 à 3 conservé).
    public func lecture(sqlstate: String?, message: String) -> Lecture? {
        guard let sqlstate else { return nil }
        if sqlstate == "42501", RPCResponse.estPrivilegeManquant(message) { return .contrat }
        let texte = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return regles.first { $0.sqlstate == sqlstate && ($0.messages?.contains(texte) ?? true) }?.lecture
    }
}

/// Règles déclarées par RPC (messages exacts de `supabase/schema/public.sql`, fiche du lot 4). Une
/// interception par RPC, déclarée, jamais globale ; chaque gateway de domaine passe la sienne.
public enum ExceptionsMetierLot4 {
    /// `fn_lister_conversations_messagerie` : 28000 ; 22023 « Curseur incomplet ».
    public static let listerConversations = ExceptionsLot4([.init("22023", ["Curseur incomplet"], .contrat)])
    /// `fn_interlocuteurs_conversations` : 28000 ; 42501 « Compte inactif » ; 22023 « Trop de conversations demandées ».
    public static let interlocuteurs = ExceptionsLot4([
        .init("42501", ["Compte inactif"], .refusMetier),
        .init("22023", ["Trop de conversations demandées"], .contrat),
    ])
    /// `fn_marquer_messages_lus` : 28000 ; 42501 « Accès refusé » → `IssueLecture.accesRefuse`.
    public static let marquerMessagesLus = ExceptionsLot4([.init("42501", ["Accès refusé"], .refusMetier)])
    /// `fn_typing_start` : 28000 `NON_AUTHENTIFIE` ; 42501 `NON_AUTORISE` : indicateur abandonné sans message.
    public static let typingStart = ExceptionsLot4([.init("42501", ["NON_AUTORISE"], .refusMetier)])
    /// `fn_update_presence` : 28000 `NON_AUTHENTIFIE`.
    public static let updatePresence = ExceptionsLot4([])
    /// `fn_user_id_pour_etablissement` : 28000 ; 42501 « Non autorisé » → conversation indisponible.
    public static let userIdPourEtablissement = ExceptionsLot4([.init("42501", ["Non autorisé"], .refusMetier)])
    /// `fn_obtenir_conversation` : 28000 ; 42501 « Conversation non autorisée » ; 22023 « Interlocuteur invalide ».
    public static let obtenirConversation = ExceptionsLot4([
        .init("42501", ["Conversation non autorisée"], .refusMetier),
        .init("22023", ["Interlocuteur invalide"], .contrat),
    ])
    /// `fn_lister_copies_bulletins` : 42501 `COPIE_ACCES_REFUSE`.
    public static let listerCopiesBulletins = ExceptionsLot4([.init("42501", ["COPIE_ACCES_REFUSE"], .refusMetier)])
    /// `fn_signaler_copie_bulletin` : 42501 `COPIE_ACCES_REFUSE` ; 22023 `COPIE_MOTIF_INVALIDE`.
    public static let signalerCopieBulletin = ExceptionsLot4([
        .init("42501", ["COPIE_ACCES_REFUSE"], .refusMetier),
        .init("22023", ["COPIE_MOTIF_INVALIDE"], .contrat),
    ])
    /// `fn_soumettre_reclamation` : 23514 `reclamations_categorie_check` (texte PostgreSQL, libellé générique côté app).
    public static let soumettreReclamation = ExceptionsLot4([.init("23514", nil, .refusMetier)])
    /// `fn_signaler_notation` : P0001 « Le signalement n’a pas pu être enregistré. Veuillez réessayer. »,
    /// rédigé pour l'utilisateur, restitué tel quel.
    public static let signalerNotation = ExceptionsLot4([
        .init("P0001", ["Le signalement n’a pas pu être enregistré. Veuillez réessayer."], .refusMetier),
    ])
}

extension RPCResponse {
    /// Appel RPC du lot 4, paramètres nommés éventuels ; `exceptions` = règles de SA RPC (`ExceptionsMetierLot4`).
    static func appeler(_ client: SupabaseClient, _ fonction: String, params: JSONObject? = nil, fallback: String,
                        exceptions: ExceptionsLot4) async throws -> RPCResponse {
        try await executer(fallback: fallback, exceptions: exceptions) {
            if let params { return try await client.rpc(fonction, params: params).execute().value }
            return try await client.rpc(fonction).execute().value
        }
    }

    /// Lit l'exception selon `exceptions` avant de déléguer à `executer(fallback:_:)` (lot 1) : `[CODE DU TRAVAIL]` et
    /// `SupabaseErrorMapping` restent les seuls traitements de tout le reste.
    static func executer(fallback: String, exceptions: ExceptionsLot4,
                         _ requete: () async throws -> AnyJSON) async throws -> RPCResponse {
        try await executer(fallback: fallback) {
            do {
                return try await requete()
            } catch let postgrest as PostgrestError where !estRefusCodeDuTravail(postgrest.message) {
                switch exceptions.lecture(sqlstate: postgrest.code, message: postgrest.message) {
                case .refusMetier:
                    return refusMetier(sqlstate: postgrest.code ?? "", message: postgrest.message).raw
                case .sessionExpiree:
                    throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
                case .contrat:
                    throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
                case nil:
                    throw postgrest
                }
            }
        }
    }
}
