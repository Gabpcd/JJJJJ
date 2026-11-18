import Foundation
import JoleneCore
import Supabase

/// `ContestationPort` sur Supabase (blueprint lot 2 §2.3-§2.4, tranche T5b, HARD STOP n°4 ; décision 9, D11 et D12 de
/// `DECISIONS_LOT2.md`), avec le JWT du soignant.
///
/// - `litige` : `litiges?select=<colonnes>&presence_id=eq.<id>&order=cree_le.desc&limit=1` (`PanneauContestation.tsx`
///   l.92-101, projection réduite à ce que l'écran affiche).
/// - `fenetreOuverte` : `fn_fenetre_contestation_ouverte` par deux clés `{p_type_litige, p_mission_id}` ; booléen nu,
///   toute autre forme → `.contract` (le modèle masque alors le bouton, fail-closed). Aucune constante de délai côté
///   client : le serveur lit `parametres_litiges.delai_contestation_pointage_h`.
/// - `contester` : `fn_ouvrir_litige_rate_limited` par **trois clés exactes** `{p_mission_id, p_type_litige, p_motif}`
///   (l.127-131) : PostgREST retient la surcharge canonique `(uuid, type_litige, text)` ; sans `p_type_litige` il
///   choisirait la surcharge à deux clés (litige `AUTRE`, fenêtre toujours ouverte). Une seule requête POST (jamais
///   rejouée par le SDK). `{error}` → `.refusee` verbatim (« Non authentifié » → `.unauthorized`) ; succès
///   `{success:true, litige_id}` → audit `PRESENCE_CONTESTATION` best-effort (`fn_ecrire_audit_safe`, CHECK
///   `journaux_audit_action_check`, parité l.134-139), puis relecture du litige par `presence_id` (le serveur rattache
///   la dernière présence de la mission, `public.sql` l.46985-46990 : à défaut, relecture par `id`). `.ouverte` n'est
///   rendu qu'avec le litige relu. **Aucun** appel `fn_creer_notification` (`RPC_JAMAIS_SUIVIES`) : le trigger
///   `trg_notifier_creation_litige` notifie déjà l'établissement.
public struct SupabaseContestationGateway: ContestationPort {
    public static let rpcOuverture = "fn_ouvrir_litige_rate_limited"
    public static let rpcFenetre = "fn_fenetre_contestation_ouverte"
    public static let auditRPC = "fn_ecrire_audit_safe"
    public static let actionAudit = "PRESENCE_CONTESTATION"
    /// Colonnes de `litiges` lues (jamais `select=*`).
    public static let colonnes = "id,statut,presence_id,mission_id,type_litige,cree_le"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func litige(presenceId: String, context: MissionReadContext) async throws -> LitigePresence? {
        try MissionQuery.validate(context: context)
        return try await lire { $0.eq("presence_id", value: presenceId) }
    }

    public func fenetreOuverte(missionId: String, context: MissionReadContext) async throws -> Bool {
        try MissionQuery.validate(context: context)
        let params: JSONObject = [
            "p_type_litige": .string(ContestationModel.typeLitige),
            "p_mission_id": .string(missionId),
        ]
        let reponse = try await RPCResponse.appeler(client, Self.rpcFenetre, params: params, fallback: PointageQuery.fallbackDetail)
        guard let ouverte = reponse.raw.boolValue else {
            try reponse.leverSiErreur(fallback: PointageQuery.fallbackDetail)
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return ouverte
    }

    public func contester(missionId: String, presenceId: String, motif: String,
                          context: MissionReadContext) async throws -> IssueContestation {
        try MissionQuery.validate(context: context)
        let nettoye = ContestationModel.nettoyer(motif)
        let params: JSONObject = [
            "p_mission_id": .string(missionId),
            "p_type_litige": .string(ContestationModel.typeLitige),
            "p_motif": .string(nettoye),
        ]
        let fallback = LibellesDetailPresences.Contestation.erreurEnvoi
        let reponse = try await RPCResponse.appeler(client, Self.rpcOuverture, params: params, fallback: fallback)
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) {
                throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
            }
            return .refusee(message: erreur)
        }
        guard reponse.success == true, let litigeId = reponse.string("litige_id"), !litigeId.isEmpty else {
            return .refusee(message: fallback)
        }
        await auditer(presenceId: presenceId, missionId: missionId, motif: nettoye, context: context)
        if let relu = try await lire({ $0.eq("presence_id", value: presenceId) }), relu.id == litigeId {
            return .ouverte(relu)
        }
        if let relu = try await lire({ $0.eq("id", value: litigeId) }) {
            return .ouverte(relu)
        }
        // Litige annoncé mais jamais relu : aucun succès fabriqué (PRINCIPES §3) ; le modèle relit ensuite.
        throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
    }

    // MARK: - Interne

    /// Dernier litige (par `cree_le` décroissant) du filtre donné.
    private func lire(_ filtre: (PostgrestFilterBuilder) -> PostgrestFilterBuilder) async throws -> LitigePresence? {
        do {
            let lignes: [LitigePresence] = try await filtre(client.from("litiges").select(Self.colonnes))
                .order("cree_le", ascending: false, nullsFirst: true) // = `order=cree_le.desc` du web (défaut PostgREST)
                .limit(1)
                .execute().value
            return lignes.first
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: PointageQuery.fallbackDetail)
        }
    }

    /// Audit client du web (`fn_ecrire_audit_safe`, l.134-139), best-effort : jamais d'uuid invalide dans
    /// `p_id_ressource` (refusé avant tout appel), échec avalé (la contestation est enregistrée par le serveur).
    private func auditer(presenceId: String, missionId: String, motif: String, context: MissionReadContext) async {
        guard let acteur = SupabaseAuditGateway.uuid(context.userId), let ressource = SupabaseAuditGateway.uuid(presenceId) else {
            return
        }
        let params: JSONObject = [
            "p_acteur_id": .string(acteur),
            "p_type_acteur": .string(SupabaseAuditGateway.typeActeur),
            "p_action": .string(Self.actionAudit),
            "p_type_ressource": .string("presence"),
            "p_id_ressource": .string(ressource),
            "p_details": .object([
                "motif": .string(motif),
                "mission_id": .string(missionId),
                "initie_par": .string(SupabaseAuditGateway.typeActeur),
            ]),
            "p_navigateur": .string(SupabaseAuditGateway.navigateur),
        ]
        _ = try? await RPCResponse.appeler(client, Self.auditRPC, params: params, fallback: SupabaseAuditGateway.fallbackMessage)
    }
}
