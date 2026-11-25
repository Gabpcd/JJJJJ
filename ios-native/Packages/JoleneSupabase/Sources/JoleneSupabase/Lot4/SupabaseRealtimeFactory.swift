import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « Realtime » (`Gateways.realtime`), T7a : `SupabaseRealtimeGateway` sur
    /// `client.realtimeV2` (canaux de la liste, du fil, de la saisie et de la présence). Rien n'est ouvert à la
    /// construction : le premier canal l'est au premier flux demandé (`CycleRealtime`, scène active et espace prêt).
    static func realtime(client: SupabaseClient) -> RealtimePort { SupabaseRealtimeGateway(client: client) }
}
