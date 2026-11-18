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
///   `{success:true, litige_id}` → audit `PRESENCE_CONTESTATION` best-effort (`SupabaseAuditGateway.ecrire`, action
///   `AuditAction.presenceContestation` sous la garde du CHECK), puis relecture du litige par `presence_id` (le serveur
///   rattache la dernière présence de la mission, `public.sql` l.46981-46984 : à défaut, relecture par `id`).
///   `.ouverte` n'est rendu qu'avec le litige relu ; toute autre réponse sans `{error}` (`success` sans `litige_id`
///   compris, revue B8 de T5b, m7) lève `.contract`, et le modèle relit. **Aucun** appel `fn_creer_notification`
///   (`RPC_JAMAIS_SUIVIES`) : le trigger `trg_notifier_creation_litige` notifie déjà l'établissement.
/// - Audit minimisé (décision m2 de la revue B8 de T5b, `DECISIONS_LOT2.md`) : `p_details` ne porte que la longueur du
///   motif et l'identifiant du litige, jamais le motif libre (déjà dans `litiges.motif`, table rectifiable) : RGPD
///   art. 5 §1 c) et e), `journaux_audit` étant immuable (art. 16 et 17 inapplicables). Le web copie encore le motif.
public struct SupabaseContestationGateway: ContestationPort {
    public static let rpcOuverture = "fn_ouvrir_litige_rate_limited"
    public static let rpcFenetre = "fn_fenetre_contestation_ouverte"
    public static let typeRessourceAudit = "presence"
    /// Colonnes de `litiges` lues (jamais `select=*`).
    public static let colonnes = "id,statut,presence_id,mission_id,type_litige,cree_le"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func litige(presenceId: String, context: MissionReadContext) async throws -> LitigePresence? {
        try MissionQuery.validate(context: context)
        return try await lire(fallback: PointageQuery.fallbackDetail) { $0.eq("presence_id", value: presenceId) }
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
        // Réponse hors contrat : le litige a pu être créé, le modèle relit (jamais un refus définitif supposé).
        guard reponse.success == true, let litigeId = reponse.string("litige_id"), !litigeId.isEmpty else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        await auditer(presenceId: presenceId, litigeId: litigeId, motif: nettoye, context: context)
        if let relu = try await lire(fallback: fallback, { $0.eq("presence_id", value: presenceId) }), relu.id == litigeId {
            return .ouverte(relu)
        }
        if let relu = try await lire(fallback: fallback, { $0.eq("id", value: litigeId) }) {
            return .ouverte(relu)
        }
        // Litige annoncé mais jamais relu : aucun succès fabriqué (PRINCIPES §3) ; le modèle relit ensuite.
        throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
    }

    // MARK: - Interne

    /// Dernier litige (par `cree_le` décroissant) du filtre donné ; `fallback` : message d'une erreur sans texte lisible.
    private func lire(fallback: String,
                      _ filtre: (PostgrestFilterBuilder) -> PostgrestFilterBuilder) async throws -> LitigePresence? {
        do {
            let lignes: [LitigePresence] = try await filtre(client.from("litiges").select(Self.colonnes))
                .order("cree_le", ascending: false, nullsFirst: true) // = `order=cree_le.desc` du web (défaut PostgREST)
                .limit(1)
                .execute().value
            return lignes.first
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: fallback)
        }
    }

    /// Audit client du web (`fn_ecrire_audit_safe`, l.134-139) par `SupabaseAuditGateway.ecrire` (uuid validés avant
    /// tout appel), best-effort : un échec est avalé, la contestation est enregistrée par le serveur. Détails minimisés.
    private func auditer(presenceId: String, litigeId: String, motif: String, context: MissionReadContext) async {
        let details = ["motif_longueur": String(motif.unicodeScalars.count), "litige_id": litigeId]
        _ = try? await SupabaseAuditGateway(client: client).ecrire(action: .presenceContestation,
                                                                   typeRessource: Self.typeRessourceAudit,
                                                                   idRessource: presenceId, details: details,
                                                                   context: context)
    }
}
