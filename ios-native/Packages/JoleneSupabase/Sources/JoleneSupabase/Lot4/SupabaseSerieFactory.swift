import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « série » (`Gateways.serie`), câblée par L4-T12 : lecture PostgREST des missions de la
    /// série, acceptation par la gateway de candidature du même monde (`Gateways.candidature`, lot 1).
    static func serie(client: SupabaseClient, candidature: any CandidaturePort, clock: any ClockPort) -> SeriePort {
        SupabaseSerieGateway(client: client, candidature: candidature, clock: clock)
    }
}
