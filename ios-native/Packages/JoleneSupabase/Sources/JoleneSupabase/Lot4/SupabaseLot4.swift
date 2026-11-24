import Foundation
import JoleneCore
import Supabase

/// Lot 4 (blueprint `docs/mobile-swift/LOT4_PLAN.md` §2.2, décision D1) : seul point d'assignation des treize ports du
/// lot 4 du monde Supabase, appelé une fois par `SupabaseGateways.make(client:clock:enrich:)` après l'init du lot 1.
/// Une fabrique par domaine, chacune dans son fichier (`Lot4/Supabase<Domaine>Factory.swift`) ;
/// `SupabaseGatewaysTests.testAucunPortNonCable` compare les deux mondes.
enum SupabaseLot4 {
    static func cabler(_ gateways: inout Gateways, client: SupabaseClient) {
        gateways.swipe = swipe(client: client)
        gateways.filtres = filtres(client: client)
        gateways.disponibilites = disponibilites(client: client)
        gateways.parrainage = parrainage(client: client)
        gateways.litiges = litiges(client: client)
        gateways.reclamations = reclamations(client: client)
        gateways.messagerie = messagerie(client: client)
        gateways.realtime = realtime(client: client)
        gateways.bulletins = bulletins(client: client)
        gateways.evaluationsRecues = evaluationsRecues(client: client)
        gateways.poolUrgence = poolUrgence(client: client)
        gateways.score = score(client: client)
        gateways.exclusions = exclusions(client: client)
        // T12 : quatorzième port (précision 13 de `DECISIONS_LOT4.md`) ; l'acceptation réutilise la candidature du lot 1.
        gateways.serie = serie(client: client, candidature: gateways.candidature, clock: gateways.clock)
    }
}
