import Foundation
import JoleneCore
import Supabase

/// `ExportRGPDPort` sur Supabase (lot 3, T11) : `fn_rgpd_exporter_rate_limited()` (SECURITY DEFINER, EXECUTE
/// `authenticated` ; définitions live de cette RPC et de `fn_rgpd_exporter_donnees_soignant` relues en lecture
/// seule le 08/11/2026, corps identiques au dump l.55300-55393), comme `SectionConfidentialite.tsx` l.33-41 :
/// - une seule requête POST sans paramètre ; le corps est rendu OCTET POUR OCTET (`execute()` → `Data`) : un
///   décodage `AnyJSON` passerait par un dictionnaire et perdrait l'ordre des clés du jsonb, que le fichier
///   exporté doit garder ;
/// - `{error}` « vrai » en HTTP 200 (`ExportRGPD.analyserReponse`) : « Non authentifié » → session expirée,
///   tout autre message → `.unknown` verbatim (« Trop d'exports en peu de temps… », 30 exports par heure),
///   valeur non textuelle → repli générique ; aucun fichier n'est écrit ;
/// - corps illisible ou non objet → refus de contrat ; transport → `SupabaseErrorMapping`.
/// Le contenu n'est jamais journalisé. L'audit `RGPD_EXPORT_DONNEES` est écrit par le serveur et, comme le web,
/// par le modèle d'écran (`ExportRGPDModel`). Signalement serveur hors lot 3 : `notations_recues` de l'export
/// contient les notes reçues non publiées (`publie_le` non filtré), voir la fiche de contrat.
public struct SupabaseExportGateway: ExportRGPDPort {
    public static let rpc = "fn_rgpd_exporter_rate_limited"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func exporter(context: MissionReadContext) async throws -> ExportDonneesRGPD {
        try MissionQuery.validate(context: context)
        let corps: Data
        do {
            let reponse: PostgrestResponse<Void> = try await client.rpc(Self.rpc).execute()
            corps = reponse.data
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: ExportRGPD.Textes.echec)
        }
        switch ExportRGPD.analyserReponse(corps) {
        case .donnees(let donnees):
            return donnees
        case .refus(let message?) where RPCResponse.estNonAuthentifie(message):
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        case .refus(let message):
            throw JoleneError(.unknown, message ?? ExportRGPD.Textes.echec)
        case .illisible:
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
    }
}
