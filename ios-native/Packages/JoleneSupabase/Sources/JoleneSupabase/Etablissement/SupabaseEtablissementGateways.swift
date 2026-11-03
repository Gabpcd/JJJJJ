import Foundation
import JoleneCore
import Supabase

/// Fabrique des ports de l'espace établissement sur Supabase (lot 5 §2.3), assignée à
/// `Gateways.etablissement` par `SupabaseGateways.make(client:)`. Chaque port est câblé ici dans la même
/// PR que sa tranche ; un port encore stub y est nommé explicitement (`SupabaseGatewaysTests` compare
/// ce monde au monde démo, `DemoWorldTests.portsEnAttenteLot5`).
public enum SupabaseEtablissementGateways {
    public static func make(client: SupabaseClient) -> EtablissementGateways {
        EtablissementGateways(
            session: SupabaseEtabSessionGateway(client: client),
            dashboard: UnwiredEtabDashboardPort(),        // T4
            missions: UnwiredEtabMissionsPort(),          // T5
            candidatures: UnwiredEtabCandidaturesPort(),  // T6
            pointage: UnwiredEtabPointagePort(),          // T7
            presences: UnwiredEtabPresencesPort(),        // T8
            publication: UnwiredEtabPublicationPort(),    // T9
            audit: SupabaseEtabAuditGateway(client: client)
        )
    }
}
