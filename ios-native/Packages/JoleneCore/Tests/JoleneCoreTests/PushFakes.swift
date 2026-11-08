import Foundation
@testable import JoleneCore

// Doubles du push du lot 3 (tranche T4), partagés par `PushCoordinatorTests` et `SessionStorePushTests`.
// Un journal synchrone unique (`JournalPush`) reçoit les appels de tous les doubles : l'ordre
// « RPC → désinscription → oubli → révocation » se lit dans une seule liste.

/// Journal synchrone (verrou) : utilisable depuis un acteur comme depuis un port synchrone.
final class JournalPush: @unchecked Sendable {
    private let lock = NSLock()
    private var lignes: [String] = []

    func noter(_ ligne: String) {
        lock.lock(); defer { lock.unlock() }
        lignes.append(ligne)
    }

    var entrees: [String] {
        lock.lock(); defer { lock.unlock() }
        return lignes
    }

    /// Entrées commençant par `prefixe` (ex. « upsert: »).
    func entrees(prefixe: String) -> [String] { entrees.filter { $0.hasPrefix(prefixe) } }
}

/// Jetons de test : jamais de littéral hexadécimal (aucune valeur qui ressemble à un secret).
enum JetonsTest {
    /// 32 octets 0x00…0x1f, comme un token APNs.
    static let a = Data((0..<32).map { UInt8($0) })
    /// 32 octets 0xe0…0xff (majuscules attendues en minuscules dans l'hexadécimal).
    static let b = Data((0..<32).map { UInt8(0xe0 + $0) })

    /// Hexadécimal minuscule calculé indépendamment de `PushCoordinator.hex`.
    static func hex(_ data: Data) -> String {
        data.map { octet in
            let chiffres = Array("0123456789abcdef")
            return String([chiffres[Int(octet >> 4)], chiffres[Int(octet & 0x0f)]])
        }.joined()
    }
}

actor FakePushPermission: PushPermissionPort {
    private var courant: AutorisationPush
    private(set) var demandes = 0
    private(set) var lectures = 0

    init(_ etat: AutorisationPush) { courant = etat }

    func etat() async -> AutorisationPush {
        lectures += 1
        return courant
    }

    func demander() async throws -> Bool {
        demandes += 1
        return courant.permetEnregistrement
    }

    func regler(_ etat: AutorisationPush) { courant = etat }
}

/// Registrar APNs simulé : token configurable, échec, barrière (enregistrement « en vol »).
actor FakePushRegistrar: PushRegistrarPort {
    private var token: Data
    private var echec: Error?
    private var barriere: Gate?
    private let journal: JournalPush
    private(set) var enregistrements = 0
    private(set) var desinscriptions = 0

    init(token: Data = JetonsTest.a, journal: JournalPush, barriere: Gate? = nil) {
        self.token = token; self.journal = journal; self.barriere = barriere
    }

    func enregistrer() async throws -> Data {
        enregistrements += 1
        journal.noter("registrar.enregistrer")
        if let barriere { await barriere.wait() }
        if let echec { throw echec }
        return token
    }

    func desinscrire() async {
        desinscriptions += 1
        journal.noter("desinscrire")
    }

    func regler(token: Data) { self.token = token }
    func regler(echec: Error?) { self.echec = echec }
    func regler(barriere: Gate?) { self.barriere = barriere }
}

/// Gateway push espionne : journalise `upsert:<token>:<userId>` et `desactiver:<token>` ;
/// échecs et lenteur configurables.
actor SpyPushGateway: PushRegistrationPort {
    private let journal: JournalPush
    private var echecsUpsert: [Error] = []
    private var echecDesactivation: Error?
    private var lenteurDesactivation: UInt64 = 0
    private var issueDesactivation: IssueDesactivationPush = .desactive(tokensDesactives: 1)
    private(set) var upserts: [String] = []
    private(set) var desactivations: [String] = []

    init(journal: JournalPush) { self.journal = journal }

    func enregistrer(token: String, context: MissionReadContext) async throws {
        journal.noter("upsert:\(token):\(context.userId)")
        if !echecsUpsert.isEmpty { throw echecsUpsert.removeFirst() }
        upserts.append(token)
    }

    func desactiver(token: String) async throws -> IssueDesactivationPush {
        journal.noter("desactiver:\(token)")
        desactivations.append(token)
        if lenteurDesactivation > 0 { try await Task.sleep(nanoseconds: lenteurDesactivation) }
        if let echecDesactivation { throw echecDesactivation }
        return issueDesactivation
    }

    func echouerUpserts(_ erreurs: [Error]) { echecsUpsert = erreurs }
    func echouerDesactivation(_ erreur: Error?) { echecDesactivation = erreur }
    func ralentirDesactivation(secondes: Double) { lenteurDesactivation = UInt64(secondes * 1_000_000_000) }
    func repondreDesactivation(_ issue: IssueDesactivationPush) { issueDesactivation = issue }
}

/// Mémoire du token journalisée (`memoriser:<token>:<userId>`, `oublier`).
final class JournalPushTokenStore: PushTokenStorePort, @unchecked Sendable {
    private let lock = NSLock()
    private var valeur: TokenPushMemorise?
    private let journal: JournalPush

    init(journal: JournalPush, initial: TokenPushMemorise? = nil) {
        self.journal = journal; self.valeur = initial
    }

    func memoriser(_ token: TokenPushMemorise) {
        lock.lock(); valeur = token; lock.unlock()
        journal.noter("memoriser:\(token.token):\(token.userId)")
    }

    func lire() -> TokenPushMemorise? {
        lock.lock(); defer { lock.unlock() }
        return valeur
    }

    func oublier() {
        lock.lock(); valeur = nil; lock.unlock()
        journal.noter("oublier")
    }
}

/// Auth de test : restaure `restored`, journalise la révocation (`auth.signOut`) et la purge locale.
struct PushAuth: AuthPort {
    var restored: AuthenticatedUser?
    var journal: JournalPush
    var events: AuthEventEmitter?

    func restoreSession() async throws -> AuthenticatedUser? { restored }
    func signIn(email: String, password: String) async throws -> AuthenticatedUser {
        guard let restored else { throw JoleneError(.invalidCredentials, "refusé") }
        return restored
    }
    func signOut() async throws { journal.noter("auth.signOut") }
    func authEvents() -> AsyncStream<AuthEvent> { events?.stream() ?? AsyncStream { $0.finish() } }
}

/// Profil soignant servi pour tout identifiant.
struct PushMissions: MissionsPort {
    func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
    func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
    func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
}

/// Monde de test du push : contrôleur, doubles et coordinateur reliés au même journal.
struct MondePush {
    static let utilisateur = AuthenticatedUser(id: "u-push", email: "u-push@example.invalid",
                                               emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                               appMetadataRole: "SOIGNANT")

    let journal: JournalPush
    let controller: SessionController
    let gateway: SpyPushGateway
    let permission: FakePushPermission
    let registrar: FakePushRegistrar
    let memoire: JournalPushTokenStore
    let coordinator: PushCoordinator
    let events: AuthEventEmitter

    init(etat: AutorisationPush = .accordee, token: Data = JetonsTest.a, barriere: Gate? = nil,
         memorise: TokenPushMemorise? = nil,
         delaiDesactivation: TimeInterval = PushCoordinator.delaiDesactivation,
         delaiToken: TimeInterval = PushCoordinator.delaiToken) {
        let journal = JournalPush()
        let events = AuthEventEmitter()
        let gateway = SpyPushGateway(journal: journal)
        var gateways = Gateways(auth: PushAuth(restored: Self.utilisateur, journal: journal, events: events),
                                role: NeutralRole(), missions: PushMissions())
        gateways.push = gateway
        let controller = SessionController(gateways: gateways)
        let permission = FakePushPermission(etat)
        let registrar = FakePushRegistrar(token: token, journal: journal, barriere: barriere)
        let memoire = JournalPushTokenStore(journal: journal, initial: memorise)
        self.journal = journal
        self.events = events
        self.controller = controller
        self.gateway = gateway
        self.permission = permission
        self.registrar = registrar
        self.memoire = memoire
        self.coordinator = PushCoordinator(controller: controller, permission: permission, registrar: registrar,
                                           memoire: memoire, delaiDesactivation: delaiDesactivation, delaiToken: delaiToken)
    }

    /// Ouvre la session de `utilisateur` et rend l'instantané prêt.
    func pret() async throws -> SessionSnapshot {
        let etat = await controller.start()
        guard case let .ready(snapshot) = etat else {
            throw JoleneError(.unknown, "session non prête : \(etat)")
        }
        return snapshot
    }
}
