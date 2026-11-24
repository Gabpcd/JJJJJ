import Foundation
import JoleneCore
import Supabase

/// `MessageriePort` sur Supabase (lot 4, T7a ; `docs/mobile-swift/LOT4_PLAN.md` §2.4, fiches de
/// `CONTRATS_RPC_SOIGNANT.md`), sous le JWT du soignant. Port de `src/pages/PageMessagerie.tsx`,
/// `src/lib/messagerieEnvoi.ts`, `src/lib/messagerieInterlocuteurs.ts`, `src/hooks/useOuvrirConversation.ts`,
/// `src/components/BloquerUtilisateur.tsx` et `src/components/SignalerUtilisateur.tsx`.
/// - Liste : `fn_lister_conversations_messagerie(p_avant, p_avant_id, p_limite := 100)` → tableau ; curseur suivant =
///   `(ordre_le, id)` de la dernière ligne d'une page pleine, `nil` si la page est incomplète, si cette ligne n'a pas
///   d'`ordre_le` ou si le curseur ne change pas (arrêt de la pagination) ; une ligne illisible est écartée seule ; une
///   réponse qui n'est pas un tableau est un défaut de contrat, jamais une liste vide.
/// - Interlocuteurs : `fn_interlocuteurs_conversations(p_conversation_ids)`, cent identifiants au plus (au-delà : rien
///   n'est envoyé) ; `42501 Compte inactif` → erreur au message serveur, jamais « session expirée ».
/// - Fil : PostgREST `messages_chat` (RLS `pol_msg_select`), `.order(cree_le desc).limit(500)`, rendu dans l'ordre du
///   fil ; relecture après « rejoint » : même requête bornée par `cree_le ≥ depuis` ; relecture d'un envoi : par id.
/// - Envoi : edge `messagerie-validate` seulement (garde-fou 19), `POST {conversation_id, content}` sous le jeton de
///   l'utilisateur. 200 `{success:true, message_id}` → `.envoye` (la ligne est relue par l'appelant) ; 200 sans l'un des
///   deux → `.nonConfirme` ; 401 → session expirée ; refus au code connu → `.antiFuite` ou `.refuse(code:)`, texte
///   serveur verbatim s'il est rédigé, sinon repli (un code machine et le détail technique d'un 500 ne sont jamais
///   affichés) ; `ENVOI_INDISPONIBLE`, `INTERNAL_ERROR`, statut ou corps inattendu → `.nonConfirme` (issue de
///   l'insertion inconnue). Aucun renvoi automatique.
/// - Lecture : `fn_marquer_messages_lus` (`void`) ; `42501 Accès refusé` → `.accesRefuse`. Badge :
///   `fn_messages_non_lus()` → entier nu.
/// - Saisie et présence : `fn_typing_start` (`42501 NON_AUTORISE` : indicateur abandonné sans erreur), `fn_typing_stop`,
///   `fn_update_presence`.
/// - Blocage : `fn_est_bloque` → booléen nu ; `fn_bloquer_utilisateur` / `fn_debloquer_utilisateur` → `{success:true}`
///   puis état relu ; refus `{error}` verbatim.
/// - Signalement : `fn_signaler_utilisateur` → `{success:true, signalement_id}` ; refus `{success:false, error}` verbatim.
/// - « Écrire à l'établissement » : `fn_user_id_pour_etablissement` puis `fn_obtenir_conversation(p_autre_id,
///   p_mission_id)` — jamais sans mission (D8) ; `null` ou `42501` au message connu → conversation indisponible.
/// Exceptions PostgREST lues avant `SupabaseErrorMapping` par les règles de chaque RPC (`ExceptionsMetierLot4`) :
/// `28000` → session expirée. Une seule requête par appel.
public struct SupabaseMessagerieGateway: MessageriePort {
    public static let rpcLister = "fn_lister_conversations_messagerie"
    public static let rpcInterlocuteurs = "fn_interlocuteurs_conversations"
    public static let rpcMarquerLus = "fn_marquer_messages_lus"
    public static let rpcNonLus = "fn_messages_non_lus"
    public static let rpcSaisieDebut = "fn_typing_start"
    public static let rpcSaisieFin = "fn_typing_stop"
    public static let rpcPresence = "fn_update_presence"
    public static let rpcEstBloque = "fn_est_bloque"
    public static let rpcBloquer = "fn_bloquer_utilisateur"
    public static let rpcDebloquer = "fn_debloquer_utilisateur"
    public static let rpcSignaler = "fn_signaler_utilisateur"
    public static let rpcInterlocuteurEtablissement = "fn_user_id_pour_etablissement"
    public static let rpcObtenirConversation = "fn_obtenir_conversation"
    public static let tableMessages = "messages_chat"
    public static let edgeEnvoi = "messagerie-validate"
    /// Colonnes de `messages_chat` lues (celles du web), sans espace.
    public static let colonnesMessages = MessageChat.colonnes.replacingOccurrences(of: " ", with: "")

    /// Refus de l'edge restitués en `.refuse(code:)` : le message n'a pas été inséré.
    static let codesRefus: Set<String> = [
        CodeEnvoi.requeteInvalide, CodeEnvoi.contenuVide, CodeEnvoi.conversationNonAutorisee, CodeEnvoi.envoiRefuse,
        CodeEnvoi.conversationArchivee, CodeEnvoi.contenuTropLong, CodeEnvoi.limite, CodeEnvoi.autorisationIndisponible,
    ]
    /// Statuts de refus émis par l'edge (401 : session expirée ; 405 : jamais émis pour un `POST`).
    static let statutsRefus: Set<Int> = [400, 403, 409, 413, 429, 503]

    private static var repli: String { MessagerieRepli.message }

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Liste

    public func conversations(avant: CurseurConversations?, context: MissionReadContext) async throws -> PageConversations {
        try MissionQuery.validate(context: context)
        // Curseur complet ou nul : un seul des deux paramètres lèverait « Curseur incomplet » (22023).
        let params: JSONObject = [
            "p_avant": avant.map { .string($0.ordreLe) } ?? .null,
            "p_avant_id": avant.map { .string($0.id) } ?? .null,
            "p_limite": .integer(PageConversations.taille),
        ]
        let reponse = try await RPCResponse.appeler(client, Self.rpcLister, params: params, fallback: Self.repli,
                                                    exceptions: ExceptionsMetierLot4.listerConversations)
        let lignes: [ConversationApercu] = try Self.lignes(reponse.raw)
        guard let brutes = reponse.raw.arrayValue, brutes.count >= PageConversations.taille,
              let suivant = lignes.last?.curseur, suivant != avant,
              Self.decoder(ConversationApercu.self, brutes[brutes.count - 1]) != nil else {
            return PageConversations(conversations: lignes, suivant: nil)
        }
        return PageConversations(conversations: lignes, suivant: suivant)
    }

    public func interlocuteurs(ids: [String], context: MissionReadContext) async throws -> [Interlocuteur] {
        try MissionQuery.validate(context: context)
        guard !ids.isEmpty else { return [] }
        // « Trop de conversations demandées » (22023) : jamais envoyé.
        guard ids.count <= Interlocuteur.lotMax else { throw Self.contrat }
        let reponse = try await RPCResponse.appeler(client, Self.rpcInterlocuteurs,
                                                    params: ["p_conversation_ids": .array(ids.map { .string($0) })],
                                                    fallback: Self.repli, exceptions: ExceptionsMetierLot4.interlocuteurs)
        if reponse.estRefus { throw JoleneError(.unknown, reponse.erreur ?? Self.repli) }
        return try Self.lignes(reponse.raw)
    }

    // MARK: - Fil

    public func messages(conversationId: String, context: MissionReadContext) async throws -> [MessageChat] {
        try await lireFil(conversationId: conversationId, depuis: nil, context: context)
    }

    public func messages(conversationId: String, depuis: String, context: MissionReadContext) async throws -> [MessageChat] {
        try await lireFil(conversationId: conversationId, depuis: depuis, context: context)
    }

    private func lireFil(conversationId: String, depuis: String?, context: MissionReadContext) async throws -> [MessageChat] {
        try MissionQuery.validate(context: context)
        let id = try Self.uuid(conversationId)
        let brut: AnyJSON
        do {
            var requete = client.from(Self.tableMessages).select(Self.colonnesMessages).eq("conversation_id", value: id)
            if let depuis { requete = requete.gte("cree_le", value: depuis) }
            brut = try await requete.order("cree_le", ascending: false).limit(FilMessages.limite).execute().value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.repli)
        }
        return FilMessages.fusionner([], try Self.lignes(brut), conversationId: id)
    }

    public func message(id: String, conversationId: String, context: MissionReadContext) async throws -> MessageChat? {
        try MissionQuery.validate(context: context)
        let message = try Self.uuid(id)
        let conversation = try Self.uuid(conversationId)
        let brut: AnyJSON
        do {
            brut = try await client.from(Self.tableMessages).select(Self.colonnesMessages)
                .eq("id", value: message).eq("conversation_id", value: conversation).limit(1).execute().value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.repli)
        }
        let lignes: [MessageChat] = try Self.lignes(brut)
        return lignes.first { $0.id.lowercased() == message && $0.conversationId.lowercased() == conversation }
    }

    // MARK: - Envoi

    public func envoyer(conversationId: String, contenu: String, context: MissionReadContext) async throws -> EnvoiOutcome {
        try MissionQuery.validate(context: context)
        let id = try Self.uuid(conversationId)
        let session: Session
        do {
            session = try await client.auth.session
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: SupabaseErrorMapping.unauthorizedMessage)
        }
        guard session.user.id.uuidString.lowercased() == context.userId.lowercased() else {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        let options = FunctionInvokeOptions(method: .post, headers: ["Authorization": "Bearer \(session.accessToken)"],
                                            body: ["conversation_id": id, "content": contenu])
        let reponse: EdgeResponse
        do {
            reponse = try await EdgeResponse.invoquer(client, Self.edgeEnvoi, options: options, fallback: Self.repli)
        } catch let erreur as JoleneError where erreur.kind == .unknown {
            return .nonConfirme // relais en échec ou réponse hors contrat : l'issue de l'insertion est inconnue
        }
        return try Self.issueEnvoi(reponse)
    }

    /// Issue d'une réponse de l'edge (`supabase/functions/messagerie-validate/index.ts`).
    static func issueEnvoi(_ reponse: EdgeResponse) throws -> EnvoiOutcome {
        if reponse.estNonAutorise { throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage) }
        if (200..<300).contains(reponse.statut) {
            // `{success:true, message_id}` exigé (web : `REPONSE_ENVOI_INVALIDE` sinon).
            guard reponse.success == true, let id = reponse.string("message_id"), !id.isEmpty else { return .nonConfirme }
            return .envoye(messageId: id)
        }
        guard statutsRefus.contains(reponse.statut), reponse.raw.objectValue != nil, let erreur = reponse.erreur else {
            return .nonConfirme
        }
        if reponse.statut == 400, erreur == CodeEnvoi.antiFuite {
            return .antiFuite(reponse.string("detected_type").flatMap(DetectedType.init(rawValue:)))
        }
        // 403 : refus de l'insertion relayé par l'edge (code, ou texte rédigé par le serveur) — rien n'a été inséré.
        let relaye = reponse.statut == 403
        if EdgeResponse.estCodeMachine(erreur) {
            // Code connu : refus sans insertion. Tout autre code (dont `ENVOI_INDISPONIBLE`) : issue inconnue.
            return codesRefus.contains(erreur) || relaye ? .refuse(code: erreur, message: repli) : .nonConfirme
        }
        return relaye ? .refuse(code: nil, message: erreur) : .nonConfirme
    }

    // MARK: - Lecture et badge

    public func marquerLus(conversationId: String, context: MissionReadContext) async throws -> IssueLecture {
        try MissionQuery.validate(context: context)
        let id = try Self.uuid(conversationId)
        let reponse = try await appelerSansCorps(Self.rpcMarquerLus, params: ["p_conversation_id": .string(id)],
                                                 exceptions: ExceptionsMetierLot4.marquerMessagesLus)
        return reponse.estRefus ? .accesRefuse : .lus
    }

    public func nonLus(context: MissionReadContext) async throws -> Int {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.rpcNonLus, fallback: Self.repli, exceptions: ExceptionsLot4([]))
        guard let nombre = reponse.raw.intValue, nombre >= 0 else { throw Self.contrat }
        return nombre
    }

    // MARK: - Saisie et présence

    public func saisie(debut: Bool, conversationId: String, context: MissionReadContext) async throws {
        try MissionQuery.validate(context: context)
        let params: JSONObject = ["p_conversation_id": .string(try Self.uuid(conversationId))]
        // `42501 NON_AUTORISE` de `fn_typing_start` (conversation inaccessible) : restitué puis ignoré, l'indicateur
        // est abandonné sans message.
        _ = try await appelerSansCorps(debut ? Self.rpcSaisieDebut : Self.rpcSaisieFin, params: params,
                                       exceptions: debut ? ExceptionsMetierLot4.typingStart : ExceptionsLot4([]))
    }

    public func presence(context: MissionReadContext) async throws {
        try MissionQuery.validate(context: context)
        _ = try await appelerSansCorps(Self.rpcPresence, params: nil, exceptions: ExceptionsMetierLot4.updatePresence)
    }

    // MARK: - Blocage et signalement

    public func bloque(cibleId: String, context: MissionReadContext) async throws -> Bool {
        try MissionQuery.validate(context: context)
        let cible = try Self.uuid(cibleId)
        let reponse = try await RPCResponse.appeler(client, Self.rpcEstBloque, params: ["p_cible_id": .string(cible)],
                                                    fallback: Self.repli)
        // Booléen nu exigé (web : `typeof data !== 'boolean'` → statut indisponible).
        guard let bloque = reponse.raw.boolValue else { throw Self.contrat }
        return bloque
    }

    public func basculerBlocage(cibleId: String, bloquer: Bool, context: MissionReadContext) async throws -> Bool {
        try MissionQuery.validate(context: context)
        let cible = try Self.uuid(cibleId)
        // Comme le web : `p_cible_id` seul (aucun motif).
        let reponse = try await RPCResponse.appeler(client, bloquer ? Self.rpcBloquer : Self.rpcDebloquer,
                                                    params: ["p_cible_id": .string(cible)], fallback: Self.repli)
        try reponse.leverSiErreur(fallback: Self.repli)
        guard reponse.success == true, reponse.erreur == nil else { throw Self.contrat }
        return try await bloque(cibleId: cible, context: context)
    }

    public func signaler(cibleId: String, type: TypeCibleSignalement, categorie: String, motif: String, missionId: String?,
                         context: MissionReadContext) async throws -> IssueSignalement {
        try MissionQuery.validate(context: context)
        let params: JSONObject = [
            "p_cible_id": .string(try Self.uuid(cibleId)),
            "p_cible_type": .string(type.rawValue),
            "p_categorie": .string(categorie),
            "p_motif": .string(motif.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_mission_id": try missionId.map { AnyJSON.string(try Self.uuid($0)) } ?? .null,
        ]
        let reponse = try await RPCResponse.appeler(client, Self.rpcSignaler, params: params, fallback: Self.repli)
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) { throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage) }
            return .refuse(message: erreur)
        }
        if reponse.estRefus { return .refuse(message: Self.repli) }
        // Aucune lecture de `signalements` n'est ouverte au client : le succès est l'identifiant rendu.
        guard reponse.success == true else { throw Self.contrat }
        _ = try reponse.requiredString("signalement_id")
        return .signale
    }

    // MARK: - « Écrire à l'établissement »

    public func conversationPourMission(missionId: String, etablissementId: String,
                                        context: MissionReadContext) async throws -> IssueConversationMission {
        try MissionQuery.validate(context: context)
        let mission = try Self.uuid(missionId)
        let etablissement = try Self.uuid(etablissementId)
        let interlocuteur = try await RPCResponse.appeler(client, Self.rpcInterlocuteurEtablissement,
                                                          params: ["p_etablissement_id": .string(etablissement)],
                                                          fallback: Self.repli,
                                                          exceptions: ExceptionsMetierLot4.userIdPourEtablissement)
        guard let autre = try Self.identifiant(interlocuteur) else {
            return .indisponible(message: interlocuteur.erreur ?? Self.repli)
        }
        let conversation = try await RPCResponse.appeler(client, Self.rpcObtenirConversation,
                                                         params: ["p_autre_id": .string(autre), "p_mission_id": .string(mission)],
                                                         fallback: Self.repli, exceptions: ExceptionsMetierLot4.obtenirConversation)
        guard let id = try Self.identifiant(conversation) else {
            return .indisponible(message: conversation.erreur ?? Self.repli)
        }
        return .conversation(id: id)
    }

    // MARK: - Interne

    private static var contrat: JoleneError { JoleneError(.contract, SupabaseErrorMapping.contractMessage) }

    /// Uuid canonique en minuscules ; une valeur vide ou invalide n'est jamais envoyée.
    static func uuid(_ valeur: String) throws -> String {
        guard let uuid = SupabaseCandidatureGateway.uuid(valeur) else { throw contrat }
        return uuid
    }

    /// Uuid nu rendu par une RPC ; `nil` pour `null` ou un refus restitué (`42501` au message connu) ; toute autre
    /// forme est un défaut de contrat.
    static func identifiant(_ reponse: RPCResponse) throws -> String? {
        if reponse.estRefus || reponse.raw.isNil { return nil }
        guard let texte = reponse.raw.stringValue, let uuid = SupabaseCandidatureGateway.uuid(texte) else { throw contrat }
        return uuid
    }

    static func decoder<T: Decodable>(_ type: T.Type, _ json: AnyJSON) -> T? {
        guard let donnees = try? JSONEncoder().encode(json) else { return nil }
        return try? JSONDecoder().decode(T.self, from: donnees)
    }

    /// Lignes d'un tableau JSON ; une ligne illisible est écartée seule, une réponse qui n'est pas un tableau est un
    /// défaut de contrat.
    static func lignes<T: Decodable>(_ json: AnyJSON) throws -> [T] {
        guard let elements = json.arrayValue else { throw contrat }
        return elements.compactMap { decoder(T.self, $0) }
    }

    /// RPC `RETURNS void` du lot 4 : `execute()` sans décodage (204 ou corps vide), exceptions lues par les règles de
    /// la RPC avant `SupabaseErrorMapping`. Refus métier restitué : `estRefus`.
    private func appelerSansCorps(_ fonction: String, params: JSONObject?, exceptions: ExceptionsLot4) async throws -> RPCResponse {
        try await RPCResponse.executer(fallback: Self.repli, exceptions: exceptions) {
            if let params {
                let _: PostgrestResponse<Void> = try await client.rpc(fonction, params: params).execute()
            } else {
                let _: PostgrestResponse<Void> = try await client.rpc(fonction).execute()
            }
            return AnyJSON.null
        }
    }
}
