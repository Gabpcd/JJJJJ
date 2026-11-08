import Foundation

/// Monde démo (plan §4.6) : un seul jeu de fixtures JSON, une horloge fixée,
/// aucun réseau. `DemoWorld.gateways()` fournit les ports du mode `-JOLENE_MODE demo`.
public enum DemoWorld {
    /// Horloge fixée du monde démo : 2026-11-02T00:00:00Z. Identique à `fixed_now`
    /// des trois fichiers JSON (vérifié par test). Les 30 missions démarrent entre le
    /// 03/11/2026 et le 02/12/2026.
    public static let fixedNow: Date = Date(timeIntervalSince1970: 1_793_577_600)

    /// Copie de `DEMO_CONTEXT` (demoGateway.ts) ; `demo-profile.json` doit lui être égal.
    public static let context = MissionReadContext(
        userId: "demo-soignant",
        email: "demonstration@example.invalid",
        profile: SoignantProfile(id: "demo-soignant", profession: "IDE", adresseLat: 48.8566, adresseLng: 2.3522,
                                 rayonDeplacementKm: 50, tousDocumentsValides: false, typeContrat: "CDD",
                                 typesContratAcceptes: "[\"CDD\",\"LIBERAL\"]", typeExercice: "MIXTE", tauxHoraireMinimum: 0)
    )

    /// Utilisateur confirmé renvoyé par `DemoAuthGateway.signIn`.
    public static let user = AuthenticatedUser(id: context.userId, email: context.email, emailConfirmedAt: fixedNow,
                                               appMetadataRole: UserRole.soignant.rawValue, appMetadataEtablissementId: nil)

    public static let messageDemoSeulement = "Le mode démonstration utilise uniquement son profil fictif."

    /// Un jeu de ports complet, horloge fixée comprise. Chaque appel crée une session
    /// démo vierge (pas de session restaurée avant `signIn`).
    public static func gateways() -> Gateways {
        gateways(drapeaux: [:])
    }

    /// Variante avec surcharges de drapeaux (`DemoFlagsGateway`). Chaque port du lot 1 est
    /// câblé ici dans la même PR que sa tranche ; un port encore stub y est nommé explicitement
    /// (`DemoWorldTests.testAucunPortNonCable`).
    public static func gateways(drapeaux: [String: Bool]) -> Gateways {
        var gateways = Gateways(
            auth: DemoAuthGateway(),
            role: DemoRoleGateway(),
            missions: DemoMissionsGateway(),
            clock: FixedClock(fixedNow),
            dashboard: DemoDashboardGateway(clock: FixedClock(fixedNow)),
            candidature: UnwiredCandidaturePort(),      // T6a, T7
            presence: UnwiredPresencePort(),            // T6c
            favoris: UnwiredFavorisPort(),              // T4b
            mesMissions: UnwiredMesMissionsPort(),      // T5
            compte: DemoAccountGateway(),
            audit: DemoAuditGateway(),
            flags: DemoFlagsGateway(surcharges: drapeaux),
            recovery: UnwiredRecoveryPort(),            // T10
            justificatifs: UnwiredJustificatifStoragePort() // T7
        )
        câblerLot3(&gateways)
        return gateways
    }

    /// Lot 3 (blueprint `LOT3_PLAN.md` §2.2) : seul point d'assignation des ports du lot 3 du monde
    /// démo, après l'init du lot 1 (aucun troisième init). Chaque tranche y remplace son stub par sa
    /// gateway démo dans la même PR qu'au monde Supabase (`SupabaseGateways.câblerLot3`) et retire
    /// le port de `DemoWorldTests.portsEnAttenteLot3`.
    static func câblerLot3(_ gateways: inout Gateways) {
        gateways.push = DemoPushGateway()                                  // T4
        gateways.notifications = UnwiredNotificationsCenterPort()          // T5
        gateways.preferences = UnwiredNotificationPreferencesPort()        // T6
        gateways.inscription = UnwiredInscriptionPort()                    // T7, T8
        gateways.profil = UnwiredProfilPort()                              // T9
        gateways.avatar = UnwiredAvatarStoragePort()                       // T10
        gateways.geocodage = UnwiredGeocodagePort()                        // T10
        gateways.motDePasse = UnwiredMotDePassePort()                      // T11
        gateways.exportRGPD = UnwiredExportRGPDPort()                      // T11
        gateways.revenus = UnwiredRevenusPort()                            // T12
        gateways.paiements = UnwiredPaiementsDeclaresPort()                // T13
        gateways.iban = UnwiredIbanPort()                                  // T14b
        gateways.stripeConnect = UnwiredStripeConnectPort()                // T14a
    }
}

/// Session démo en mémoire : rien n'est persisté entre deux lancements.
actor DemoSessionStore {
    private var user: AuthenticatedUser?

    func current() -> AuthenticatedUser? { user }
    func set(_ user: AuthenticatedUser?) { self.user = user }
}

/// Accepte n'importe quel email et mot de passe non vides et renvoie l'utilisateur démo
/// confirmé. `restoreSession` renvoie `nil` au premier lancement, puis l'utilisateur
/// après `signIn`, jusqu'à `signOut`.
public struct DemoAuthGateway: AuthPort {
    private let store = DemoSessionStore()

    public init() {}

    public func restoreSession() async throws -> AuthenticatedUser? {
        await store.current()
    }

    public func signIn(email: String, password: String) async throws -> AuthenticatedUser {
        let emailSaisi = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !emailSaisi.isEmpty, !password.isEmpty else {
            throw JoleneError(.invalidCredentials, "Saisissez votre email et votre mot de passe.")
        }
        await store.set(DemoWorld.user)
        // Relecture après mutation : aucun succès fabriqué.
        guard let user = await store.current() else {
            throw JoleneError(.unknown, "La session de démonstration n'a pas pu être ouverte.")
        }
        return user
    }

    public func signOut() async throws {
        await store.set(nil)
    }
}

/// Le compte démo est toujours un soignant sans établissement.
public struct DemoRoleGateway: RolePort {
    public init() {}

    public func currentRole() async throws -> RoleResult {
        RoleResult(role: UserRole.soignant.rawValue, etablissementId: nil)
    }
}

/// Missions démo chargées depuis `Bundle.module`, enrichies et filtrées comme le web
/// (`MissionBusiness`). Refuse tout contexte dont l'identifiant n'est pas celui du
/// profil fictif : la démo n'est jamais un repli pour un compte réel.
public struct DemoMissionsGateway: MissionsPort {
    /// Source des missions ASSIGNEE ouvrables en détail depuis l'Accueil (T3 : fiches de
    /// `demo-dashboard.json`). Lue seulement pour un identifiant absent de `demo-missions.json` :
    /// une fixture de tableau de bord illisible ne casse jamais le détail Explorer. Point de fusion
    /// T5 : cette source devient celle des missions ASSIGNEE de Mes missions (`LOT1_PLAN.md` §3 T5).
    private let missionsAssignees: @Sendable () throws -> [DemoFixtures.MissionFixture]

    public init(missionsAssignees: @escaping @Sendable () throws -> [DemoFixtures.MissionFixture] = {
        try DemoFixtures.loadDashboard().missionsAssignees
    }) {
        self.missionsAssignees = missionsAssignees
    }

    public func profile(userId: String) async throws -> SoignantProfile? {
        userId == DemoWorld.context.userId ? DemoWorld.context.profile : nil
    }

    public func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] {
        try check(context)
        let (missions, etablissements) = try chargerFixtures()
        return MissionBusiness.filter(missions.map { enrich($0, context: context, etablissements: etablissements) },
                                      context: context, filters: filters)
    }

    public func mission(id: String, context: MissionReadContext) async throws -> Mission? {
        try check(context)
        let (missions, etablissements) = try chargerFixtures()
        if let fixture = missions.first(where: { $0.record.id == id }) {
            return enrich(fixture, context: context, etablissements: etablissements)
        }
        // T3 : les missions ASSIGNEE du tableau de bord démo s'ouvrent en détail, sans entrer dans Explorer.
        guard let fixture = try missionsAssignees().first(where: { $0.record.id == id }) else { return nil }
        return enrich(fixture, context: context, etablissements: etablissements)
    }

    private func check(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }

    private func chargerFixtures() throws -> ([DemoFixtures.MissionFixture], [EtablissementSummary]) {
        (try DemoFixtures.loadMissions().missions, try DemoFixtures.loadEtablissements().etablissements)
    }

    private func enrich(_ fixture: DemoFixtures.MissionFixture, context: MissionReadContext,
                        etablissements: [EtablissementSummary]) -> Mission {
        let etablissement = etablissements.first { $0.id == fixture.record.etablissementId }
        return MissionBusiness.enrich(record: fixture.record, context: context, etablissement: etablissement, slots: fixture.creneaux)
    }
}
