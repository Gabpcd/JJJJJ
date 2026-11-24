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
        // Reste de L1-T10 : récupération du mot de passe sur un client d'authentification isolé (quarantaine).
        return make(client: client, clock: clock, enrich: enrich,
                    recovery: SupabaseRecoveryGateway.fabrique(url: url, publishableKey: key))
    }

    /// Assemble les ports autour d'un client existant (tests : transport injecté, stockage
    /// en mémoire). Aucune validation d'environnement ici : elle a déjà eu lieu.
    /// Chaque port du lot 1 est câblé ici dans la même PR que sa tranche ; un port encore stub
    /// y est nommé explicitement (`SupabaseGatewaysTests.testAucunPortNonCable`).
    /// `recovery` (reste de L1-T10) : fabrique du client d'authentification isolé de la récupération du mot de passe ;
    /// absente (tests d'assemblage), le port est câblé mais verrouillé (`SupabaseRecoveryGateway.nonConfiguree`).
    public static func make(
        client: SupabaseClient,
        clock: any ClockPort = SystemClock(),
        enrich: @escaping MissionQuery.Enricher = MissionQuery.defaultEnrich,
        recovery: SupabaseRecoveryGateway.Fabrique? = nil
    ) -> Gateways {
        var gateways = Gateways(
            auth: SupabaseAuthGateway(client: client),
            role: SupabaseRoleGateway(client: client),
            missions: SupabaseMissionsGateway(client: client, clock: clock, enrich: enrich),
            clock: clock,
            dashboard: SupabaseDashboardGateway(client: client, clock: clock),
            candidature: SupabaseCandidatureGateway(client: client), // T6a (annulations : T7)
            presence: SupabasePresenceGateway(client: client), // T6c
            favoris: SupabaseFavorisGateway(client: client),
            mesMissions: SupabaseMesMissionsGateway(client: client, clock: clock, enrich: enrich),
            compte: SupabaseAccountGateway(client: client),
            audit: SupabaseAuditGateway(client: client),
            flags: SupabaseFlagsGateway(client: client),
            recovery: SupabaseRecoveryGateway(fabrique: recovery), // T10 (reste)
            justificatifs: SupabaseJustificatifStorage(client: client) // T7
        )
        câblerLot2(&gateways, client: client, clock: clock)
        câblerLot3(&gateways, client: client)
        SupabaseLot4.cabler(&gateways, client: client) // lot 4 : une fabrique par domaine (`Lot4/`)
        // Lot 5 (T1) : ports de l'espace établissement, assignés après l'init (signature inchangée).
        gateways.etablissement = SupabaseEtablissementGateways.make(client: client)
        return gateways
    }

    /// Lot 2 (blueprint `LOT2_PLAN.md` §2.2) : seul point d'assignation des ports du lot 2 du monde
    /// Supabase, après l'init du lot 1 (aucun troisième init). Chaque tranche y remplace son stub par sa
    /// gateway dans la même PR qu'au monde démo (`DemoWorld.câblerLot2`) ;
    /// `SupabaseGatewaysTests.testAucunPortNonCable` compare les deux mondes.
    static func câblerLot2(_ gateways: inout Gateways, client: SupabaseClient, clock: any ClockPort = SystemClock()) {
        gateways.pointage = SupabasePointageGateway(client: client, clock: gateways.clock) // T3
        gateways.contestation = SupabaseContestationGateway(client: client) // T5b
        gateways.notation = SupabaseNotationGateway(client: client) // T5a
        gateways.documents = SupabaseDocumentsGateway(client: client, clock: clock) // T6
        gateways.contrats = SupabaseContratsGateway(client: client, clock: gateways.clock) // T8
    }

    /// Lot 3 (blueprint `LOT3_PLAN.md` §2.2) : seul point d'assignation des ports du lot 3 du monde
    /// Supabase, après l'init du lot 1 (aucun troisième init). Chaque tranche y remplace son stub par
    /// sa gateway dans la même PR qu'au monde démo (`DemoWorld.câblerLot3`) ;
    /// `SupabaseGatewaysTests.testAucunPortNonCable` compare les deux mondes.
    static func câblerLot3(_ gateways: inout Gateways, client: SupabaseClient) {
        gateways.push = SupabasePushGateway(client: client)                // T4
        gateways.notifications = SupabaseNotificationsGateway(client: client, clock: gateways.clock) // T5
        gateways.preferences = SupabasePreferencesGateway(client: client)  // T6
        gateways.inscription = SupabaseInscriptionGateway(client: client) // T7 (complétion refusée jusqu'à T8)
        gateways.profil = SupabaseProfilGateway(client: client)            // T9
        // T10 : reçu Keychain provisoire (`KeychainRecusAvatar`) jusqu'à la fusion avec le journal du lot 2.
        gateways.avatar = EnvoiAvatar(stockage: SupabaseAvatarStorage(client: client), profil: SupabaseProfilGateway(client: client),
                                      recus: KeychainRecusAvatar(), horloge: gateways.clock)
        gateways.geocodage = ApiAdresseGeocodage()                         // T10
        gateways.motDePasse = SupabaseMotDePasseGateway(client: client)    // T11
        gateways.exportRGPD = SupabaseExportGateway(client: client)        // T11
        gateways.revenus = SupabaseRevenusGateway(client: client)          // T12
        gateways.paiements = SupabasePaiementsGateway(client: client)      // T13
        gateways.iban = SupabaseIbanGateway(client: client)                // T14b
        gateways.stripeConnect = SupabaseStripeConnectGateway(client: client) // T14a
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
