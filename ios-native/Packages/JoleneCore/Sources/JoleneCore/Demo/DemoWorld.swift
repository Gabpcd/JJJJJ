import Foundation

/// Monde démo (plan §4.6) : un seul jeu de fixtures JSON, une horloge fixée,
/// aucun réseau. `DemoWorld.gateways()` fournit les ports du mode `-JOLENE_MODE demo`.
public enum DemoWorld {
    /// Horloge fixée du monde démo : 2026-11-02T00:00:00Z. Identique à `fixed_now`
    /// des trois fichiers JSON (vérifié par test). Les 30 missions démarrent entre le
    /// 03/11/2026 et le 02/12/2026.
    public static let fixedNow: Date = Date(timeIntervalSince1970: 1_793_577_600)

    /// Copie de `DEMO_CONTEXT` (demoGateway.ts) ; `demo-profile.json` doit lui être égal. Lot 1, T6b : les cinq
    /// colonnes du soft-gate (`ProfilCompletion`) sont celles de l'identité démo unique de l'exporteur
    /// (`DEMO_IDENTITE`, aussi dans `demo-profil-complet.json`) : sans téléphone, RPPS non vérifié. Date de naissance
    /// et téléphone réduits à leur présence (minimisation, revue B8 de T6a m6), comme après décodage du fichier.
    public static let context: MissionReadContext = {
        var profile = SoignantProfile(id: "demo-soignant", profession: "IDE", adresseLat: 48.8566, adresseLng: 2.3522,
                                      rayonDeplacementKm: 50, tousDocumentsValides: false, typeContrat: "CDD",
                                      typesContratAcceptes: "[\"CDD\",\"LIBERAL\"]", typeExercice: "MIXTE", tauxHoraireMinimum: 0)
        profile.prenom = "Camille"
        profile.nom = "Démo"
        profile.dateNaissanceRenseignee = true
        profile.telephoneRenseigne = false
        profile.rppsVerifie = false
        return MissionReadContext(userId: "demo-soignant", email: "demonstration@example.invalid", profile: profile)
    }()

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
        gateways(drapeaux: drapeaux, varianteProfil: nil)
    }

    /// T6b : `varianteProfil` (DEBUG, `JOLENE_DEMO_PROFIL`, lue par `AppContainer`) s'applique aussi à la projection
    /// du lot 1 (`MissionsPort.profile`, soft-gate de la candidature), pour que les deux projections du profil démo
    /// restent identiques sous chaque variante (le lot 3 l'applique à `DemoProfilGateway`).
    public static func gateways(drapeaux: [String: Bool], varianteProfil: VarianteProfilDemo?) -> Gateways {
        let auth = DemoAuthGateway()
        // T6a : un seul acteur de candidature par monde ; ses candidatures de session sont relues par Mes missions
        // (point de fusion de T5), si bien qu'une candidature posée apparaît dans l'onglet Candidatures.
        let candidature = DemoCandidatureGateway(clock: FixedClock(fixedNow))
        // T6b (revue B8, M1) : une seule ligne `soignants` démo, celle du lot 3 (`DemoProfilStore`, variante comprise),
        // dont la projection du lot 1 est relue à chaque `profile(userId:)` : une modification du profil (téléphone…)
        // lève le soft-gate au retour sur le détail, comme en production.
        let profilDemo = varianteProfil.map { DemoProfilGateway(variante: $0) } ?? DemoProfilGateway()
        let profil: @Sendable () async throws -> SoignantProfile = { try await profilDemo.projectionLot1(context.profile) }
        // T6c : la confirmation de présence lit la mission servie (attribution de session comprise) et pose
        // `presence_confirmee_le` dans son acteur ; le détail la relit par la surcouche `presences`.
        // Intégration de la vague B (T6c × T7) : une mission annulée pendant la session n'est plus confirmable.
        let lecturePresence = DemoMissionsGateway(profil: profil, missionsAttribuees: { await candidature.missionsAttribuees() },
                                                  missionsAnnulees: { await candidature.missionsAnnulees() })
        let presence = DemoPresenceGateway(clock: FixedClock(fixedNow), mission: { id in
            try await lecturePresence.mission(id: id, context: context)?.record
        })
        var gateways = Gateways(
            auth: auth,
            role: DemoRoleGateway(),
            missions: DemoMissionsGateway(profil: profil, missionsAttribuees: { await candidature.missionsAttribuees() },
                                          presences: { await presence.surcouche($0) },
                                          missionsAnnulees: { await candidature.missionsAnnulees() }), // T7
            clock: FixedClock(fixedNow),
            dashboard: DemoDashboardGateway(clock: FixedClock(fixedNow)),
            candidature: candidature,                   // T6a (annulations : T7)
            presence: presence,                         // T6c
            favoris: DemoFavorisGateway(clock: FixedClock(fixedNow)),
            mesMissions: DemoMesMissionsGateway(clock: FixedClock(fixedNow),
                                                candidaturesDeSession: { await candidature.candidaturesDeSession() },
                                                missionsAnnulees: { await candidature.missionsAnnulees() }), // T7
            compte: DemoAccountGateway(),
            audit: DemoAuditGateway(),
            flags: DemoFlagsGateway(surcharges: drapeaux),
            recovery: UnwiredRecoveryPort(),            // T10
            justificatifs: DemoJustificatifStorage()    // T7
        )
        câblerLot2(&gateways)
        câblerLot3(&gateways, profil: profilDemo)
        DemoLot4.cabler(&gateways) // lot 4 : une fabrique par domaine (`Demo/Lot4/`)
        // Lot 5 (T1) : ports établissement ; l'identité est celle de la session démo courante, si bien
        // que le compte soignant fictif y est refusé (`.demoOnly`).
        gateways.etablissement = DemoEtablissementWorld.gateways(identite: { try? await auth.restoreSession()?.id },
                                                                messagerie: gateways.messagerie as? DemoMessagerieGateway)
        return gateways
    }

    /// Lot 2 (blueprint `LOT2_PLAN.md` §2.2) : seul point d'assignation des ports du lot 2 du monde démo,
    /// après l'init du lot 1 (aucun troisième init). Chaque tranche y remplace son stub par sa gateway démo
    /// dans la même PR qu'au monde Supabase (`SupabaseGateways.câblerLot2`) et retire le port de
    /// `DemoWorldTests.portsEnAttenteLot2`. L'appareil démo (GPS, réseau, terminal) n'est pas un port
    /// backend : `Appareil.demo(gps:reseau:)`, injecté par `AppContainer` (T4b).
    static func câblerLot2(_ gateways: inout Gateways) {
        gateways.pointage = DemoPointageGateway(clock: FixedClock(fixedNow)) // T3
        gateways.contestation = DemoContestationGateway()          // T5b
        gateways.notation = DemoNotationGateway()                  // T5a
        gateways.documents = DemoDocumentsGateway()                // T6 (scénario démo : `-JOLENE_DEMO_SCENARIO`, T7)
        gateways.contrats = DemoContratsGateway(clock: FixedClock(fixedNow)) // T8
    }

    /// Lot 3 (blueprint `LOT3_PLAN.md` §2.2) : seul point d'assignation des ports du lot 3 du monde
    /// démo, après l'init du lot 1 (aucun troisième init). Chaque tranche y remplace son stub par sa
    /// gateway démo dans la même PR qu'au monde Supabase (`SupabaseGateways.câblerLot3`) et retire
    /// le port de `DemoWorldTests.portsEnAttenteLot3`.
    static func câblerLot3(_ gateways: inout Gateways, profil: DemoProfilGateway = DemoProfilGateway()) {
        gateways.push = DemoPushGateway()                                  // T4
        gateways.notifications = DemoNotificationsGateway()                // T5
        gateways.preferences = DemoPreferencesGateway()                    // T6
        // T7 (compte, confirmation, parcours) ; T8 (brouillon, modes d'exercice, `register-soignant` simulée).
        gateways.inscription = DemoInscriptionGateway(auth: gateways.auth as? DemoAuthGateway ?? DemoAuthGateway())
        gateways.profil = profil                                           // T9 (même ligne que `missions.profile`, T6b)
        gateways.avatar = DemoWorld.avatar(profil: gateways.profil)       // T10 (même ligne démo que `profil`)
        gateways.geocodage = DemoGeocodage()                               // T10
        gateways.motDePasse = DemoMotDePasseGateway()                      // T11
        gateways.exportRGPD = DemoExportRGPDGateway()                      // T11
        // T12 ; T13 : un seul serveur simulé des paiements déclarés, relu aussi par l'onglet (état des missions).
        let paiements = DemoPaiementsGateway()
        gateways.revenus = DemoRevenusGateway(paiementsDeclares: paiements)
        gateways.paiements = paiements                                     // T13
        gateways.iban = DemoIbanGateway()                                  // T14b
        gateways.stripeConnect = DemoStripeConnectGateway()                // T14a
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
/// après `signIn`, jusqu'à `signOut`. Lot 2 (T4b, seconde revue fraîche, m2) : liée à une
/// `ExpirationSessionDemo` (scénarios DEBUG `session-expiree-*`), une restauration d'une
/// session ouverte (« Vérifier ma session » → `SessionController.start`) la revalide.
/// Lot 3, T7 : l'adresse d'un compte créé pendant ce lancement (`DemoInscriptionGateway`,
/// mêmes `store` et `comptes`) ouvre ce nouveau compte, sans profil soignant.
public struct DemoAuthGateway: AuthPort {
    let store = DemoSessionStore()
    let comptes = DemoComptesInscription()
    private let expiration: ExpirationSessionDemo?
    /// Compte fictif ouvert pour l'email saisi (déjà débarrassé de ses espaces), si aucun compte n'a été créé
    /// pendant ce lancement pour cette adresse : toujours le soignant fictif hors lot 5 ; choisi par email dans le
    /// monde à deux espaces du lot 5 (`DemoWorld.gateways(espace:)`).
    private let compte: @Sendable (String) throws -> AuthenticatedUser

    public init(expiration: ExpirationSessionDemo? = nil) {
        self.expiration = expiration
        self.compte = { _ in DemoWorld.user }
    }

    /// Lot 5 (T2a) : compte fictif choisi selon l'email saisi.
    public init(expiration: ExpirationSessionDemo? = nil, compte: @escaping @Sendable (String) throws -> AuthenticatedUser) {
        self.expiration = expiration
        self.compte = compte
    }

    public func restoreSession() async throws -> AuthenticatedUser? {
        let user = await store.current()
        if user != nil { await expiration?.revalider() }
        return user
    }

    public func signIn(email: String, password: String) async throws -> AuthenticatedUser {
        let emailSaisi = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !emailSaisi.isEmpty, !password.isEmpty else {
            throw JoleneError(.invalidCredentials, "Saisissez votre email et votre mot de passe.")
        }
        let cree = await comptes.utilisateur(email: emailSaisi)
        let ouvert = try cree ?? compte(emailSaisi)
        await store.set(ouvert)
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
    /// Source des missions du soignant ouvrables en détail hors Explorer : missions ASSIGNEE de
    /// l'Accueil (T3 : fiches de `demo-dashboard.json`, aussi « À venir » de Mes missions) puis
    /// missions passées de Mes missions (T5 : `demo-mes-missions.json`). Lue seulement pour un
    /// identifiant absent de `demo-missions.json` : une fixture illisible ne casse jamais le détail
    /// Explorer.
    private let missionsAssignees: @Sendable () throws -> [DemoFixtures.MissionFixture]
    /// Lot 1, T6a (revue B8, m5) : missions ouvertes attribuées au profil fictif pendant la session
    /// (`DemoCandidatureGateway.missionsAttribuees`) : servies `ASSIGNEE` en détail, retirées d'Explorer.
    private let missionsAttribuees: @Sendable () async -> Set<String>
    /// Profil fictif servi à la session, relu à chaque appel (T6b : projection de la ligne démo du lot 3, variante DEBUG
    /// `JOLENE_DEMO_PROFIL` comprise).
    private let profil: @Sendable () async throws -> SoignantProfile
    /// T6c : présence confirmée pendant la session (`DemoPresenceGateway.surcouche`), appliquée à chaque détail relu :
    /// l'écran relit ce que le monde démo a écrit, jamais une date posée localement.
    private let presences: @Sendable (MissionRecord) async -> MissionRecord
    /// Lot 1, T7 (revue B8 de #1156, M1) : missions annulées par le profil fictif pendant la session
    /// (`DemoCandidatureGateway.missionsAnnulees`) : servies comme le serveur les remet en ligne (`OUVERTE`, sans
    /// soignant assigné), en détail comme dans Explorer.
    private let missionsAnnulees: @Sendable () async -> Set<String>

    public init(missionsAssignees: @escaping @Sendable () throws -> [DemoFixtures.MissionFixture] = {
        // T6c : mission de recette de la confirmation de présence, ouverte par lien seulement (hors listes).
        try DemoFixtures.loadDashboard().missionsAssignees + DemoFixtures.loadMesMissions().passees.map(\.mission)
            + (DemoPresenceGateway.missionJ1().map { [$0] } ?? [])
    }, profil: @escaping @Sendable () async throws -> SoignantProfile = { DemoWorld.context.profile },
       missionsAttribuees: @escaping @Sendable () async -> Set<String> = { [] },
       presences: @escaping @Sendable (MissionRecord) async -> MissionRecord = { $0 },
       missionsAnnulees: @escaping @Sendable () async -> Set<String> = { [] }) {
        self.missionsAssignees = missionsAssignees
        self.profil = profil
        self.missionsAttribuees = missionsAttribuees
        self.presences = presences
        self.missionsAnnulees = missionsAnnulees
    }

    /// Mission remise en ligne par une annulation (`fn_annuler_mission_soignant`, `fn_annuler_candidature_soignant`).
    static func remiseEnLigne(_ fixture: DemoFixtures.MissionFixture) -> DemoFixtures.MissionFixture {
        var ouverte = fixture
        ouverte.record.statut = "OUVERTE"
        ouverte.record.soignantAssigneId = nil
        return ouverte
    }

    public func profile(userId: String) async throws -> SoignantProfile? {
        userId == DemoWorld.context.userId ? try await profil() : nil
    }

    public func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] {
        try check(context)
        let (missions, etablissements) = try chargerFixtures()
        let attribuees = await missionsAttribuees()
        let annulees = await missionsAnnulees()
        // T7 : une mission assignée annulée pendant la session est remise en ligne, comme sur le serveur.
        let remises = annulees.isEmpty ? []
            : try missionsAssignees().filter { annulees.contains($0.record.id) }.map(Self.remiseEnLigne)
        return MissionBusiness.filter((missions.filter { !attribuees.contains($0.record.id) } + remises)
                                        .map { enrich($0, context: context, etablissements: etablissements) },
                                      context: context, filters: filters)
    }

    public func mission(id: String, context: MissionReadContext) async throws -> Mission? {
        try check(context)
        let (missions, etablissements) = try chargerFixtures()
        if var fixture = missions.first(where: { $0.record.id == id }) {
            if await missionsAttribuees().contains(id) {
                fixture.record.statut = CandidatureRules.statutAssignee
                fixture.record.soignantAssigneId = DemoWorld.context.userId
            }
            fixture.record = await presences(fixture.record)
            return enrich(fixture, context: context, etablissements: etablissements)
        }
        // T3 : les missions ASSIGNEE du tableau de bord démo s'ouvrent en détail, sans entrer dans Explorer.
        guard var fixture = try missionsAssignees().first(where: { $0.record.id == id }) else { return nil }
        // T7 : annulée pendant la session → relue remise en ligne, jamais encore « assignée » (ni confirmée, T6c).
        if await missionsAnnulees().contains(id) {
            return enrich(Self.remiseEnLigne(fixture), context: context, etablissements: etablissements)
        }
        fixture.record = await presences(fixture.record)
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
