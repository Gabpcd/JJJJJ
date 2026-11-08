import Foundation
import JoleneCore
import Supabase

/// Fabrique du jeu de ports Supabase (plan §4.1, §4.2). Un seul `SupabaseClient` par app :
/// PKCE, session en Keychain local (`KeychainSessionStorage`), rafraîchissement automatique
/// du jeton, en-tête `X-Client-Info` Jolene. La garde d'environnement est appliquée AVANT
/// toute construction de client : une configuration refusée ne crée jamais de client.
public enum SupabaseGateways {
    /// Construit les gateways pour `staging` ou `production`. Lève `JoleneError(.environment)`
    /// si la configuration est refusée, `JoleneError(.demoOnly)` en mode démonstration.
    public static func make(
        environment: JoleneEnvironment,
        clock: any ClockPort = SystemClock(),
        enrich: @escaping MissionQuery.Enricher = MissionQuery.defaultEnrich
    ) throws -> Gateways {
        try environment.validate()
        guard environment.mode != .demo else {
            throw JoleneError(.demoOnly, "Le mode démonstration n'utilise pas Supabase.")
        }
        guard let url = environment.supabaseURL, let key = environment.publishableKey else {
            throw JoleneError(.environment, "Configuration Supabase incomplète.")
        }
        let client = makeClient(url: url, publishableKey: key, storage: KeychainSessionStorage())
        return make(client: client, clock: clock, enrich: enrich)
    }

    /// Assemble les ports autour d'un client existant (tests : transport injecté, stockage
    /// en mémoire). Aucune validation d'environnement ici : elle a déjà eu lieu.
    /// Chaque port du lot 1 est câblé ici dans la même PR que sa tranche ; un port encore stub
    /// y est nommé explicitement (`SupabaseGatewaysTests.testAucunPortNonCable`).
    public static func make(
        client: SupabaseClient,
        clock: any ClockPort = SystemClock(),
        enrich: @escaping MissionQuery.Enricher = MissionQuery.defaultEnrich
    ) -> Gateways {
        var gateways = Gateways(
            auth: SupabaseAuthGateway(client: client),
            role: SupabaseRoleGateway(client: client),
            missions: SupabaseMissionsGateway(client: client, clock: clock, enrich: enrich),
            clock: clock,
            dashboard: SupabaseDashboardGateway(client: client, clock: clock),
            candidature: UnwiredCandidaturePort(),      // T6a, T7
            presence: UnwiredPresencePort(),            // T6c
            favoris: UnwiredFavorisPort(),              // T4b
            mesMissions: UnwiredMesMissionsPort(),      // T5
            compte: SupabaseAccountGateway(client: client),
            audit: SupabaseAuditGateway(client: client),
            flags: SupabaseFlagsGateway(client: client),
            recovery: UnwiredRecoveryPort(),            // T10
            justificatifs: UnwiredJustificatifStoragePort() // T7
        )
        câblerLot2(&gateways, client: client)
        return gateways
    }

    /// Lot 2 (blueprint `LOT2_PLAN.md` §2.2) : seul point d'assignation des ports du lot 2 du monde
    /// Supabase, après l'init du lot 1 (aucun troisième init). Chaque tranche y remplace son stub par sa
    /// gateway dans la même PR qu'au monde démo (`DemoWorld.câblerLot2`) ;
    /// `SupabaseGatewaysTests.testAucunPortNonCable` compare les deux mondes.
    static func câblerLot2(_ gateways: inout Gateways, client: SupabaseClient) {
        gateways.pointage = UnwiredPointagePort()                  // T3
        gateways.contestation = UnwiredContestationPort()          // T5b
        gateways.notation = UnwiredNotationPort()                  // T5a
        gateways.documents = UnwiredDocumentsPort()                // T6
        gateways.contrats = UnwiredContratsPort()                  // T8
    }

    /// Construction du client : options vérifiées dans `SupabaseClientOptions` de 2.55.5
    /// (`AuthOptions.storage/flowType/autoRefreshToken`, `GlobalOptions.headers/session`).
    public static func makeClient(
        url: URL,
        publishableKey: String,
        storage: any AuthLocalStorage,
        session: URLSession = .shared,
        autoRefreshToken: Bool = true
    ) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: url,
            supabaseKey: publishableKey,
            options: clientOptions(storage: storage, session: session, autoRefreshToken: autoRefreshToken)
        )
    }

    /// Options exactes transmises au SDK (le client ne les ré-expose pas publiquement) :
    /// PKCE, stockage injecté, rafraîchissement automatique, en-tête `X-Client-Info` Jolene,
    /// `URLSession` injectable pour les transports de test.
    public static func clientOptions(
        storage: any AuthLocalStorage,
        session: URLSession = .shared,
        autoRefreshToken: Bool = true
    ) -> SupabaseClientOptions {
        SupabaseClientOptions(
            auth: .init(storage: storage, flowType: .pkce, autoRefreshToken: autoRefreshToken),
            global: .init(headers: ["X-Client-Info": JoleneSupabase.clientInfo], session: session)
        )
    }
}
