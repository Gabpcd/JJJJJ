import Foundation
import JoleneCore
import Supabase

/// `PresencePort` sur Supabase (lot 1, T6c, `docs/mobile-swift/LOT1_PLAN.md` §3 T6c, décision 16), sous le JWT du
/// soignant : `fn_confirmer_presence_mission(p_mission_id)` (`supabase/schema/public.sql` l.24992-25012).
///
/// Formes de réponse (HTTP 200) : `{success:true}` ; `{error:'Mission introuvable'}` (mission d'un autre soignant ou
/// invisible, y compris sans session : `auth.uid()` NULL) ; `{error:"Cette mission n'est plus active."}` (statut hors
/// `ASSIGNEE`/`EN_COURS`). Un `{error}` est un refus affiché verbatim (`.refusee`, HARD STOP n°4). Une session absente
/// ou expirée est une erreur PostgREST (401, 42501 : `anon` n'a pas EXECUTE), traduite par `SupabaseErrorMapping` ;
/// l'écran affiche alors le repli web « Confirmation impossible. » (`ConfirmationPresenceModel`, revue B8 m2-m3).
///
/// Succès annoncé seulement après relecture de la mission (PRINCIPES §3) : `presence_confirmee_le` non nul sur la
/// mission attribuée à la session. La RPC n'a **aucune idempotence** (chaque appel réécrit l'instant et notifie
/// l'établissement, l.25003-25009) : une seule requête, jamais de renvoi automatique ; l'écran désactive le bouton
/// pendant l'appel et le masque après relecture.
public struct SupabasePresenceGateway: PresencePort {
    public static let rpc = "fn_confirmer_presence_mission"
    public static let relectureColumns = "id,statut,soignant_assigne_id,presence_confirmee_le"
    /// Le serveur a répondu mais la relecture ne montre pas la confirmation : rien n'est renvoyé automatiquement.
    public static let relectureMessage = "Votre confirmation a été envoyée mais n'a pas pu être relue. Rouvrez la mission avant de réessayer."
    public static let identifiantInvalideMessage = "Identifiant de mission invalide."

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func confirmerPresence(missionId: String, context: MissionReadContext) async throws -> PresenceOutcome {
        try MissionQuery.validate(context: context)
        guard let id = SupabaseCandidatureGateway.uuid(missionId) else {
            throw JoleneError(.contract, Self.identifiantInvalideMessage)
        }
        let repli = TextesWeb.ConfirmationPresence.repliRefus
        let reponse = try await RPCResponse.appeler(client, Self.rpc, params: ["p_mission_id": .string(id)], fallback: repli)
        if let erreur = reponse.erreur { return .refusee(message: PresenceRules.messageRefus(erreur)) }
        try reponse.leverSiErreur(fallback: repli)
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }

        let relue = try await relire(id)
        guard let relue, relue.id == id, let assigne = relue.soignantAssigneId,
              assigne.caseInsensitiveCompare(context.userId) == .orderedSame,
              let confirmee = relue.presenceConfirmeeLe, !confirmee.isEmpty else {
            throw JoleneError(.contract, Self.relectureMessage)
        }
        return .confirmee(presenceConfirmeeLe: confirmee)
    }

    struct Relecture: Decodable, Equatable {
        var id: String
        var statut: String?
        var soignantAssigneId: String?
        var presenceConfirmeeLe: String?

        enum CodingKeys: String, CodingKey {
            case id, statut
            case soignantAssigneId = "soignant_assigne_id"
            case presenceConfirmeeLe = "presence_confirmee_le"
        }
    }

    private func relire(_ id: String) async throws -> Relecture? {
        let lignes: [Relecture]
        do {
            lignes = try await client.from("missions")
                .select(Self.relectureColumns)
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.relectureMessage)
        }
        return lignes.first
    }
}
