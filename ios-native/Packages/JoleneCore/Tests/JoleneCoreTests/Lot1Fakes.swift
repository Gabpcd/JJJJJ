import Foundation
@testable import JoleneCore

// Doubles des ports du lot 1, partagés par les tests de JoleneCore. Les doubles du lot 0
// (`FakeAuth`, `FakeRole`, `FakeMissions`, `AuthEventEmitter`, `Gate`, `CallLog`) restent
// dans `SessionControllerTests.swift` et sont réutilisés tels quels. Chaque tranche du lot 1
// complète ici le double de son port plutôt que d'en déclarer un second.

// MARK: - Socle lot 0 neutre

struct NeutralAuth: AuthPort {
    func restoreSession() async throws -> AuthenticatedUser? { nil }
    func signIn(email: String, password: String) async throws -> AuthenticatedUser {
        throw JoleneError(.invalidCredentials, "refusé")
    }
    func signOut() async throws {}
}

struct NeutralRole: RolePort {
    func currentRole() async throws -> RoleResult { RoleResult(role: UserRole.soignant.rawValue) }
}

struct NeutralMissions: MissionsPort {
    func profile(userId: String) async throws -> SoignantProfile? { nil }
    func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
    func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
}

/// Erreur renvoyée par un double non scripté : un test qui l'atteint a oublié son scénario.
let nonScripte = JoleneError(.unknown, "double non scripté")

// MARK: - Ports du lot 1

struct FakeDashboard: DashboardPort {
    var snapshot = DashboardSnapshot()
    func dashboard(context: MissionReadContext) async throws -> DashboardSnapshot { snapshot }
}

struct FakeCandidature: CandidaturePort {
    var outcome: CandidatureOutcome = .confirmed(candidatureId: nil, contratId: nil)
    func confirmer(action: ActionPlanning, missionId: String, creneaux: [CreneauConfirmePayload], message: String?,
                   choixContrat: String?, candidatureId: String?, context: MissionReadContext) async throws -> CandidatureOutcome {
        outcome
    }
    func refuserProposition(candidatureId: String, context: MissionReadContext) async throws { throw nonScripte }
    func candidature(missionId: String, context: MissionReadContext) async throws -> CandidatureRecord? { nil }
    func annulerCandidature(id: String, motif: String, texte: String, justificatifPath: String?,
                            context: MissionReadContext) async throws -> AnnulationOutcome { throw nonScripte }
    func annulerMission(id: String, motif: String?, context: MissionReadContext) async throws -> AnnulationOutcome {
        throw nonScripte
    }
}

struct FakePresence: PresencePort {
    func confirmerPresence(missionId: String, context: MissionReadContext) async throws -> PresenceOutcome { throw nonScripte }
}

struct FakeFavoris: FavorisPort {
    func missionsSauvegardees(context: MissionReadContext) async throws -> [MissionSauvegardee] { [] }
    func sauvegarder(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee] { throw nonScripte }
    func retirer(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee] { throw nonScripte }
    func etablissementsFavoris(context: MissionReadContext) async throws -> [EtablissementFavori] { [] }
    func basculerEtablissement(id: String, actif: Bool, context: MissionReadContext) async throws -> [EtablissementFavori] {
        throw nonScripte
    }
}

struct FakeMesMissions: MesMissionsPort {
    func candidatures(context: MissionReadContext) async throws -> [CandidatureRecord] { [] }
    func aVenir(context: MissionReadContext, page: Int) async throws -> MissionsPage {
        MissionsPage(missions: [], page: page, aSuivre: false)
    }
    func passees(context: MissionReadContext, page: Int) async throws -> MissionsPage {
        MissionsPage(missions: [], page: page, aSuivre: false)
    }
}

struct FakeAccount: AccountPort {
    func deleteAccount(context: MissionReadContext) async throws -> DeleteAccountOutcome { throw nonScripte }
}

/// Journal des écritures d'audit (ordre d'appel), pour les preuves « une fois par connexion ».
actor AuditJournal {
    private(set) var entries: [String] = []
    func record(_ entry: String) { entries.append(entry) }
}

struct FakeAudit: AuditPort {
    var journal = AuditJournal()
    var resultat: AuditResultat = .enregistre
    var erreur: JoleneError?

    func connexion() async throws -> AuditResultat { try await trace("connexion") }
    func deconnexion() async throws -> AuditResultat { try await trace("deconnexion") }
    func activite() async throws -> AuditResultat { try await trace("activite") }
    func ecrire(action: AuditAction, typeRessource: String, idRessource: String, details: [String: String],
                context: MissionReadContext) async throws -> AuditResultat {
        try await trace("\(action.rawValue) \(typeRessource) \(idRessource)")
    }

    private func trace(_ entry: String) async throws -> AuditResultat {
        await journal.record(entry)
        if let erreur { throw erreur }
        return resultat
    }
}

struct FakeFlags: FlagsPort {
    var valeurs: [String: Bool] = [:]
    func ecranActif(cle: String, defaut: Bool) async -> Bool { valeurs[cle] ?? defaut }
}

struct FakeRecovery: RecoveryPort {
    func requestReset(email: String) async throws { throw nonScripte }
    func openRecoverySession(_ credentials: AuthCallbackCredentials) async throws -> RecoveryOutcome { throw nonScripte }
    func updatePassword(_ password: String) async throws { throw nonScripte }
    func signOutAfterRecovery() async throws {}
}

struct FakeJustificatifs: JustificatifStoragePort {
    func upload(data: Data, fileName: String, candidatureId: String, userId: String) async throws -> String { throw nonScripte }
}

enum Lot1Fakes {
    /// Jeu complet (second init de `Gateways`) : aucun port « non câblé ».
    static func gateways(audit: AuditPort = FakeAudit(), flags: FlagsPort = FakeFlags(),
                         clock: ClockPort = FixedClock(Date(timeIntervalSince1970: 1_793_577_600))) -> Gateways {
        Gateways(auth: NeutralAuth(), role: NeutralRole(), missions: NeutralMissions(), clock: clock,
                 dashboard: FakeDashboard(), candidature: FakeCandidature(), presence: FakePresence(),
                 favoris: FakeFavoris(), mesMissions: FakeMesMissions(), compte: FakeAccount(),
                 audit: audit, flags: flags, recovery: FakeRecovery(), justificatifs: FakeJustificatifs())
    }
}
