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

/// Délai de l'écran transmis au port tableau de bord par les tests qui appellent un port
/// directement (en production : `SessionController.resolutionTimeout`, via `AccueilModel`).
let delaiEcranTest = SessionController.defaultResolutionTimeout

// MARK: - Ports du lot 1

struct FakeDashboard: DashboardPort {
    var snapshot = DashboardSnapshot()
    func dashboard(context: MissionReadContext, delaiEcran: TimeInterval) async throws -> DashboardSnapshot { snapshot }
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

/// Favoris (T4b). Sans scénario : lectures vides, mutations refusées (`nonScripte`), comme posé par T1.
/// Avec `scenario` : réponses scriptées par opération, journal des appels (`FavorisScenario`).
struct FakeFavoris: FavorisPort {
    var scenario: FavorisScenario?

    func missionsSauvegardees(context: MissionReadContext) async throws -> [MissionSauvegardee] {
        guard let scenario else { return [] }
        return try await scenario.missions("lire")
    }
    func sauvegarder(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee] {
        guard let scenario else { throw nonScripte }
        return try await scenario.missions("sauvegarder(\(missionId))")
    }
    func retirer(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee] {
        guard let scenario else { throw nonScripte }
        return try await scenario.missions("retirer(\(missionId))")
    }
    func etablissementsFavoris(context: MissionReadContext) async throws -> [EtablissementFavori] {
        guard let scenario else { return [] }
        return try await scenario.etablissements("etablissements")
    }
    func basculerEtablissement(id: String, actif: Bool, context: MissionReadContext) async throws -> [EtablissementFavori] {
        guard let scenario else { throw nonScripte }
        return try await scenario.etablissements("basculer(\(id),\(actif))")
    }
}

/// Scénario du port favoris : une file de réponses par opération (clé = nom d'opération sans argument :
/// `lire`, `sauvegarder`, `retirer`, `etablissements`, `basculer`), consommées dans l'ordre d'appel ;
/// file vide → lecture vide, mutation `nonScripte`. Chaque appel est journalisé avec son argument.
final class FavorisScenario: @unchecked Sendable {
    indirect enum Reponse: Sendable {
        case missions([MissionSauvegardee])
        case etablissements([EtablissementFavori])
        case echec(JoleneError)
        /// L'appelant est annulé (`CancellationError`).
        case annulation
        /// Attente muette de 30 s, interrompue seulement par une annulation.
        case silence
        /// Attend l'ouverture de la barrière, puis rend la réponse suivante.
        case apres(Gate, Reponse)
    }

    private let lock = NSLock()
    private var files: [String: [Reponse]] = [:]
    private var journal: [String] = []

    init(_ files: [String: [Reponse]] = [:]) { self.files = files }

    /// Appels reçus, dans l'ordre (ex. `sauvegarder(m-1)`).
    var appels: [String] { lock.lock(); defer { lock.unlock() }; return journal }

    func nombre(_ prefixe: String) -> Int { appels.filter { $0.hasPrefix(prefixe) }.count }

    func ajouter(_ operation: String, _ reponse: Reponse) {
        lock.lock(); defer { lock.unlock() }
        files[operation, default: []].append(reponse)
    }

    func missions(_ appel: String) async throws -> [MissionSauvegardee] {
        switch try await resoudre(suivante(appel)) {
        case let .missions(lignes): return lignes
        default: throw nonScripte
        }
    }

    func etablissements(_ appel: String) async throws -> [EtablissementFavori] {
        switch try await resoudre(suivante(appel)) {
        case let .etablissements(lignes): return lignes
        default: throw nonScripte
        }
    }

    private func suivante(_ appel: String) -> Reponse {
        let operation = String(appel.prefix { $0 != "(" })
        lock.lock(); defer { lock.unlock() }
        journal.append(appel)
        if var file = files[operation], !file.isEmpty {
            let reponse = file.removeFirst()
            files[operation] = file
            return reponse
        }
        switch operation {
        case "lire": return .missions([])
        case "etablissements": return .etablissements([])
        default: return .echec(nonScripte)
        }
    }

    private func resoudre(_ reponse: Reponse) async throws -> Reponse {
        switch reponse {
        case let .echec(erreur): throw erreur
        case .annulation: throw CancellationError()
        case .silence:
            try await Task.sleep(nanoseconds: 30_000_000_000)
            throw nonScripte
        case let .apres(barriere, suite):
            await barriere.wait()
            return try await resoudre(suite)
        case .missions, .etablissements: return reponse
        }
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

/// Appels reçus par `FakeAccount` (preuve « un seul appel, aucun renvoi »).
actor AccountCalls {
    private(set) var count = 0
    func record() { count += 1 }
}

/// Suppression de compte (T8) : issue ou erreur scriptée, barrière optionnelle pour faire changer
/// l'identité pendant l'appel. Sans scénario, le double refuse (`nonScripte`).
struct FakeAccount: AccountPort {
    var outcome: DeleteAccountOutcome?
    var erreur: Error?
    var gate: Gate?
    var appels = AccountCalls()

    func deleteAccount(context: MissionReadContext) async throws -> DeleteAccountOutcome {
        await appels.record()
        if let gate { await gate.wait() }
        if let erreur { throw erreur }
        guard let outcome else { throw nonScripte }
        return outcome
    }
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
