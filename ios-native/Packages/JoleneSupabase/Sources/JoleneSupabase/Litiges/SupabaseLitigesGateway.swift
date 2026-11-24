import Foundation
import JoleneCore
import Supabase

/// `LitigesPort` sur Supabase (lot 4, T8 ; `docs/mobile-swift/LOT4_PLAN.md` §2.3-§2.4, D9), port de
/// `LitigesSoignant.tsx` et de `FilDiscussionLitige.tsx`, avec le JWT du soignant.
///
/// - `lister` : PostgREST `litiges` sous RLS (`pol_litige_select` : `soignant_id = auth.uid()`), **colonnes
///   explicites** (`colonnes`, jamais `select=*` : ni montant, ni `payload_modifications`), mission jointe comme le web
///   (`missions(id,intitule,debut_le)`), `cree_le` décroissant. Le nom de l'établissement vient de
///   `fn_etablissements_safe` (lot 0), jamais d'un embed `etablissements` (refusé au soignant) ; son échec laisse les
///   noms absents (l'écran affiche « Établissement non disponible », comme le web), session expirée relevée.
/// - `missionsContestables` : `missions` assignées `TERMINEE` / `EN_COURS` (`fin_le` décroissant, 50 au plus) et
///   `litiges(mission_id)` du soignant, lues en parallèle comme le web (l.133-143) ; les missions déjà en litige sont
///   retirées (`LitigesPresentation.contestables`).
/// - `ouvrir` : `fn_ouvrir_litige_rate_limited` par **trois clés exactes** `{p_mission_id, p_type_litige:'AUTRE',
///   p_motif}` : PostgREST retient la signature canonique `(uuid, type_litige, text)`, jamais le wrapper déprécié à deux
///   clés que le web appelle encore. `{error}` en HTTP 200 → `.refuse` mot pour mot (motif, doublon, plafond horaire,
///   fenêtre fermée…), sauf « Non authentifié » → session expirée. Succès `{success:true, litige_id, est_informatif}` :
///   `litige_id` exigé, puis litige relu par son identifiant ; un succès sans `litige_id` ou un litige jamais relu lève
///   `.contract` (aucun succès fabriqué, PRINCIPES §3).
/// - `fil` : PostgREST `messages_litige` sous RLS (`pol_messages_litige_select`), colonnes explicites, ordre
///   chronologique.
/// - `ajouterMessage` : `fn_ajouter_message_litige(p_litige_id, p_contenu)` ; `{error}` → `.refuse` mot pour mot
///   (« Ce litige est clôturé. », longueur, accès) ; succès `{success:true, message_id}` puis fil relu, qui doit
///   contenir ce message.
/// Une seule requête par écriture, aucun renvoi ; aucune exception PostgREST métier n'est déclarée par ces deux RPC
/// (mapping des lots 0-1). Aucun appel `fn_creer_notification` : les triggers serveur notifient l'établissement.
public struct SupabaseLitigesGateway: LitigesPort {
    public static let rpcOuverture = "fn_ouvrir_litige_rate_limited"
    public static let rpcMessage = "fn_ajouter_message_litige"
    /// Seul type ouvert ici (D9) ; les litiges typés sur facture restent sur le web.
    public static let typeLitige = "AUTRE"
    public static let table = "litiges"
    /// Colonnes de `litiges` lues (jamais `select=*`).
    public static let colonnes = "id,mission_id,etablissement_id,statut,type_litige,motif,resolution,cree_le,missions(id,intitule,debut_le)"
    public static let tableMessages = "messages_litige"
    public static let colonnesMessages = "id,litige_id,auteur_id,type_auteur,contenu,cree_le"
    public static let tableMissions = "missions"
    public static let colonnesMissions = "id,intitule,debut_le,fin_le,etablissement_id"
    /// Statuts des missions proposées à l'ouverture (`LitigesSoignant.tsx` l.137).
    public static let statutsContestables = ["TERMINEE", "EN_COURS"]
    public static let limiteMissions = 50

    private let client: SupabaseClient
    private let etablissements: SupabaseMissionsGateway

    public init(client: SupabaseClient) {
        self.client = client
        self.etablissements = SupabaseMissionsGateway(client: client)
    }

    // MARK: - Lecture

    public func lister(context: MissionReadContext) async throws -> [Litige] {
        try MissionQuery.validate(context: context)
        var litiges: [Litige]
        do {
            litiges = try await client.from(Self.table)
                .select(Self.colonnes)
                .eq("soignant_id", value: context.userId)
                .order("cree_le", ascending: false, nullsFirst: true) // = `order=cree_le.desc` du web (défaut PostgREST)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: LitigesTextes.chargementImpossible)
        }
        let noms = try await nomsEtablissements(litiges.compactMap(\.etablissementId), fallback: LitigesTextes.chargementImpossible)
        for index in litiges.indices {
            litiges[index].etablissementNom = litiges[index].etablissementId.flatMap { noms[$0] }
        }
        return litiges
    }

    public func missionsContestables(context: MissionReadContext) async throws -> [MissionContestable] {
        try MissionQuery.validate(context: context)
        async let assignees = missionsAssignees(context: context)
        async let enLitige = missionsEnLitige(context: context)
        var missions = LitigesPresentation.contestables(try await assignees, idsEnLitige: try await enLitige)
        let noms = try await nomsEtablissements(missions.compactMap(\.etablissementId), fallback: LitigesTextes.missionsIndisponibles)
        for index in missions.indices {
            missions[index].etablissementNom = missions[index].etablissementId.flatMap { noms[$0] }
        }
        return missions
    }

    public func fil(litigeId: String, context: MissionReadContext) async throws -> [MessageLitige] {
        try MissionQuery.validate(context: context)
        do {
            return try await client.from(Self.tableMessages)
                .select(Self.colonnesMessages)
                .eq("litige_id", value: litigeId)
                .order("cree_le", ascending: true)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: LitigesTextes.filIndisponible)
        }
    }

    // MARK: - Écriture

    public func ouvrir(missionId: String, motif: String, context: MissionReadContext) async throws -> OuvertureLitigeOutcome {
        try MissionQuery.validate(context: context)
        let params: JSONObject = [
            "p_mission_id": .string(missionId),
            "p_type_litige": .string(Self.typeLitige),
            "p_motif": .string(LitigesPresentation.nettoyer(motif)),
        ]
        let fallback = LitigesTextes.erreurOuverture
        let reponse = try await RPCResponse.appeler(client, Self.rpcOuverture, params: params, fallback: fallback)
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) {
                throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
            }
            return .refuse(message: erreur)
        }
        // Réponse hors contrat : le litige a pu être créé, le modèle relit (jamais un refus définitif supposé).
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        let litigeId = try reponse.requiredString("litige_id")
        // Litige annoncé mais jamais relu : aucun succès fabriqué (PRINCIPES §3).
        guard try await existe(litigeId, fallback: fallback) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return .ouvert(id: litigeId, informatif: reponse.bool("est_informatif") ?? false)
    }

    public func ajouterMessage(litigeId: String, contenu: String, context: MissionReadContext) async throws -> IssueMessageLitige {
        try MissionQuery.validate(context: context)
        let params: JSONObject = [
            "p_litige_id": .string(litigeId),
            "p_contenu": .string(LitigesPresentation.nettoyer(contenu)),
        ]
        let reponse = try await RPCResponse.appeler(client, Self.rpcMessage, params: params, fallback: LitigesTextes.erreurEnvoi)
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) {
                throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
            }
            return .refuse(message: erreur)
        }
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        let messageId = try reponse.requiredString("message_id")
        let relu = try await fil(litigeId: litigeId, context: context)
        guard relu.contains(where: { $0.id == messageId }) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return .ajoute(relu)
    }

    // MARK: - Interne

    /// Ligne `mission_id` d'un litige du soignant (l.140-142).
    private struct MissionEnLitige: Decodable {
        var missionId: String?
        enum CodingKeys: String, CodingKey { case missionId = "mission_id" }
    }

    /// Identifiant seul : preuve de relecture d'un litige ouvert.
    private struct IdentifiantLitige: Decodable { var id: String }

    private func missionsAssignees(context: MissionReadContext) async throws -> [MissionContestable] {
        do {
            return try await client.from(Self.tableMissions)
                .select(Self.colonnesMissions)
                .eq("soignant_assigne_id", value: context.userId)
                .in("statut", values: Self.statutsContestables)
                .order("fin_le", ascending: false, nullsFirst: true)
                .limit(Self.limiteMissions)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: LitigesTextes.missionsIndisponibles)
        }
    }

    private func missionsEnLitige(context: MissionReadContext) async throws -> Set<String> {
        do {
            let lignes: [MissionEnLitige] = try await client.from(Self.table)
                .select("mission_id")
                .eq("soignant_id", value: context.userId)
                .execute()
                .value
            return Set(lignes.compactMap(\.missionId))
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: LitigesTextes.missionsIndisponibles)
        }
    }

    private func existe(_ litigeId: String, fallback: String) async throws -> Bool {
        do {
            let lignes: [IdentifiantLitige] = try await client.from(Self.table)
                .select("id")
                .eq("id", value: litigeId)
                .limit(1)
                .execute()
                .value
            return lignes.contains { $0.id == litigeId }
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: fallback)
        }
    }

    /// `fn_etablissements_safe`, seule source du nom (lot 0) ; en échec, noms absents sauf une session expirée ou une
    /// annulation, relevées.
    private func nomsEtablissements(_ ids: [String], fallback: String) async throws -> [String: String] {
        do {
            return try await etablissements.etablissements(ids: ids).mapValues(\.nom)
        } catch {
            let erreur = SupabaseErrorMapping.map(error, fallback: fallback)
            if erreur.kind == .unauthorized || erreur.kind == .cancelled { throw erreur }
            return [:]
        }
    }
}
