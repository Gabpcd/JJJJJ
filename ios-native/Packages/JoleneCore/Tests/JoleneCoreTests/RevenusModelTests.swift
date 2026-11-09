import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurRevenus = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                   emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                   appMetadataRole: "SOIGNANT")

/// Modèle de l'onglet Revenus (lot 3, T12, B9 ; lecture seule) : trois sections lues pour l'epoch de la session,
/// chacune avec son état (totaux serveur, paiements rapides, missions terminées paginées par 50), audit
/// `DONNEES_PERSO_CONSULTATION` (`page: mes_gains`) une seule fois par ouverture, après une lecture réussie, jamais
/// bloquant ; échec des missions → « Impossible de charger tous les revenus » + message, liste gardée, « Réessayer »
/// relit la page demandée en dernier (web `reloadKey`) ; session expirée → « Vérifier ma session » ; réponse d'un epoch
/// périmé ignorée. Aucun montant calculé : le modèle ne fait que publier les valeurs relues.
@MainActor
final class RevenusModelTests: XCTestCase {
    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurRevenus }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw nonScripte }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    /// Audit espion : action, ressource et détails de chaque écriture.
    private actor JournalAudit {
        private(set) var ecritures: [String] = []
        func noter(_ ecriture: String) { ecritures.append(ecriture) }
    }

    private struct AuditEspion: AuditPort {
        let journal: JournalAudit
        var erreur: JoleneError?
        func connexion() async throws -> AuditResultat { .enregistre }
        func deconnexion() async throws -> AuditResultat { .enregistre }
        func activite() async throws -> AuditResultat { .enregistre }
        func ecrire(action: AuditAction, typeRessource: String, idRessource: String, details: [String: String],
                    context: MissionReadContext) async throws -> AuditResultat {
            await journal.noter("\(action.rawValue) \(typeRessource) \(idRessource) \(details)")
            if let erreur { throw erreur }
            return .enregistre
        }
    }

    /// Port scripté : chaque appel consomme l'étape suivante de sa file ; `retenue` retient les missions jusqu'à son
    /// ouverture (changement d'identité pendant la lecture).
    private final class ScriptedRevenus: RevenusPort, @unchecked Sendable {
        private let lock = NSLock()
        private var totauxEtapes: [Result<TotauxRevenus?, Error>]
        private var rapidesEtapes: [Result<[PaiementRapide], Error>]
        private var missionsEtapes: [Result<PageMissionsTerminees, Error>]
        private var pagesDemandees: [Int] = []
        var retenue: Gate?

        init(totaux: [Result<TotauxRevenus?, Error>] = [], rapides: [Result<[PaiementRapide], Error>] = [],
             missions: [Result<PageMissionsTerminees, Error>] = []) {
            totauxEtapes = totaux; rapidesEtapes = rapides; missionsEtapes = missions
        }

        var pages: [Int] { lock.lock(); defer { lock.unlock() }; return pagesDemandees }

        private func suivante<V>(_ file: inout [Result<V, Error>]) -> Result<V, Error> {
            lock.lock(); defer { lock.unlock() }
            return file.isEmpty ? .failure(nonScripte) : file.removeFirst()
        }

        func totaux(context: MissionReadContext) async throws -> TotauxRevenus? { try suivante(&totauxEtapes).get() }
        func paiementsRapides(context: MissionReadContext) async throws -> [PaiementRapide] { try suivante(&rapidesEtapes).get() }
        func missionsTerminees(context: MissionReadContext, page: Int) async throws -> PageMissionsTerminees {
            let etape: Result<PageMissionsTerminees, Error> = {
                lock.lock(); defer { lock.unlock() }
                pagesDemandees.append(page)
                return missionsEtapes.isEmpty ? .failure(nonScripte) : missionsEtapes.removeFirst()
            }()
            if let retenue { await retenue.wait() }
            return try etape.get()
        }
    }

    private static let totaux = TotauxRevenus(moisEnCours: 195, total: 1425.6, enAttente: 780, stripeConnectActif: true)
    private static let rapides = [PaiementRapide(missionId: "m-r", honorairesCents: 24000, etat: "RESERVE")]

    private static func page(_ ids: [String], page: Int = 0, aSuivre: Bool = false) -> PageMissionsTerminees {
        PageMissionsTerminees(missions: ids.map { MissionTerminee(id: $0, typeContratApplique: "SALARIE") }, page: page, aSuivre: aSuivre)
    }

    private func pret(_ port: ScriptedRevenus, journal: JournalAudit = JournalAudit(),
                      auditErreur: JoleneError? = nil) async throws -> (SessionController, SessionSnapshot) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.revenus = port
        gateways.audit = AuditEspion(journal: journal, erreur: auditErreur)
        let controller = SessionController(gateways: gateways)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return (controller, snapshot)
    }

    // MARK: - Chargement

    func testChargementPublieLesTroisSectionsEtAuditeUneSeuleFois() async throws {
        let port = ScriptedRevenus(totaux: [.success(Self.totaux), .success(Self.totaux)],
                                   rapides: [.success(Self.rapides), .success(Self.rapides)],
                                   missions: [.success(Self.page(["m-1", "m-2"])), .success(Self.page(["m-1"]))])
        let journal = JournalAudit()
        let (controller, snapshot) = try await pret(port, journal: journal)
        let model = RevenusModel(controller: controller, snapshot: snapshot)

        await model.charger()

        XCTAssertEqual(model.totaux, .pret(Self.totaux))
        XCTAssertEqual(model.paiementsRapides, .pret(Self.rapides))
        XCTAssertEqual(model.missions.map(\.id), ["m-1", "m-2"])
        XCTAssertTrue(model.missionsChargees)
        XCTAssertFalse(model.aSuivre)
        XCTAssertNil(model.erreur)
        XCTAssertFalse(model.afficheVide)
        XCTAssertEqual(model.lignes.map(\.id), ["m-1", "m-2"])
        let premieres = await journal.ecritures
        XCTAssertEqual(premieres, ["DONNEES_PERSO_CONSULTATION soignant u-1 [\"page\": \"mes_gains\"]"],
                       "audit du web (MesGains.tsx l.147-153), sur l'utilisateur de la session")

        await model.charger() // tirer pour actualiser : page 0 relue, liste remplacée
        XCTAssertEqual(model.missions.map(\.id), ["m-1"])
        let apres = await journal.ecritures
        XCTAssertEqual(apres.count, 1, "une seule consultation journalisée par ouverture de l'écran")
        XCTAssertEqual(port.pages, [0, 0])
    }

    func testTotauxMasquesPourUnProfilSansExerciceLiberal() async throws {
        let port = ScriptedRevenus(totaux: [.success(nil)], rapides: [.success([])], missions: [.success(Self.page([]))])
        let (controller, snapshot) = try await pret(port)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.totaux, .masques)
        XCTAssertEqual(model.paiementsRapides, .pret([]))
        XCTAssertFalse(model.escrowAffiche.afficheSection, "I5 : aucun paiement rapide → section absente")
        XCTAssertTrue(model.afficheVide, "aucune mission terminée : état vide du web")
    }

    func testEchecDesMissionsPuisRepriseEtAuditApresLaReussite() async throws {
        let port = ScriptedRevenus(totaux: [.success(Self.totaux)], rapides: [.success(Self.rapides)],
                                   missions: [.failure(JoleneError(.network, "Connexion impossible.")), .success(Self.page(["m-1"]))])
        let journal = JournalAudit()
        let (controller, snapshot) = try await pret(port, journal: journal)
        let model = RevenusModel(controller: controller, snapshot: snapshot)

        await model.charger()
        XCTAssertEqual(model.erreur, "Connexion impossible.")
        XCTAssertTrue(model.missions.isEmpty)
        XCTAssertFalse(model.missionsChargees)
        XCTAssertFalse(model.afficheVide, "jamais l'état vide sur une erreur (web l.802)")
        XCTAssertEqual(model.totaux, .pret(Self.totaux), "sections indépendantes : les totaux restent affichés")
        let avant = await journal.ecritures
        XCTAssertTrue(avant.isEmpty, "aucune consultation journalisée sans lecture réussie")

        await model.reessayer()
        XCTAssertNil(model.erreur)
        XCTAssertEqual(model.missions.map(\.id), ["m-1"])
        let apres = await journal.ecritures
        XCTAssertEqual(apres.count, 1)
        XCTAssertEqual(port.pages, [0, 0])
    }

    func testErreurNonJoleneDonneLeMessageDuWeb() async throws {
        struct Inattendue: Error {}
        let port = ScriptedRevenus(totaux: [.success(nil)], rapides: [.success([])], missions: [.failure(Inattendue())])
        let (controller, snapshot) = try await pret(port)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.erreur, RevenusTextes.erreurDefaut)
        XCTAssertFalse(model.sessionExpiree)
    }

    func testAuditEnEchecNeBloqueJamaisLEcran() async throws {
        let port = ScriptedRevenus(totaux: [.success(nil)], rapides: [.success([])], missions: [.success(Self.page(["m-1"]))])
        let journal = JournalAudit()
        let (controller, snapshot) = try await pret(port, journal: journal, auditErreur: JoleneError(.network, "x"))
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.missions.map(\.id), ["m-1"])
        XCTAssertNil(model.erreur)
        let ecritures = await journal.ecritures
        XCTAssertEqual(ecritures.count, 1)
    }

    func testSessionExpireeProposeLaVerification() async throws {
        let refus = JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")
        let port = ScriptedRevenus(totaux: [.failure(refus)], rapides: [.success([])], missions: [.failure(refus)])
        let (controller, snapshot) = try await pret(port)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertTrue(model.sessionExpiree)
        XCTAssertEqual(model.erreur, refus.message)
    }

    // MARK: - Pagination

    func testChargerPlusFusionneParIdentifiantEtReprendLaPageEnEchec() async throws {
        let pleine = Self.page((0..<50).map { "m-\($0)" }, aSuivre: true)
        let suite = PageMissionsTerminees(missions: [MissionTerminee(id: "m-49", intitule: "relue", typeContratApplique: "SALARIE"),
                                                     MissionTerminee(id: "m-50", typeContratApplique: "SALARIE")],
                                          page: 1, aSuivre: false)
        let port = ScriptedRevenus(totaux: [.success(nil)], rapides: [.success([])],
                                   missions: [.success(pleine), .failure(JoleneError(.network, "Connexion impossible.")), .success(suite)])
        let (controller, snapshot) = try await pret(port)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertTrue(model.aSuivre)

        await model.chargerPlus()
        XCTAssertEqual(model.erreur, "Connexion impossible.")
        XCTAssertEqual(model.missions.count, 50, "liste gardée sur l'échec d'une page suivante (web l.789-800)")
        XCTAssertTrue(model.aSuivre)

        await model.reessayer() // la page demandée en dernier, comme `reloadKey` du web
        XCTAssertNil(model.erreur)
        XCTAssertEqual(model.missions.count, 51)
        XCTAssertEqual(model.missions[49].intitule, "relue", "même identifiant : ligne remplacée à sa place (Map du web)")
        XCTAssertEqual(model.missions.last?.id, "m-50")
        XCTAssertFalse(model.aSuivre)
        XCTAssertEqual(port.pages, [0, 1, 1])

        await model.chargerPlus()
        XCTAssertEqual(port.pages, [0, 1, 1], "aucune page suivante annoncée : rien n'est demandé")
    }

    // MARK: - Sections indépendantes

    func testPaiementsRapidesEtTotauxEnEchecSeRelisentSeparement() async throws {
        let port = ScriptedRevenus(totaux: [.failure(JoleneError(.unknown, RevenusTextes.totauxIndisponibles)), .success(Self.totaux)],
                                   rapides: [.failure(JoleneError(.network, "Connexion impossible.")), .success(Self.rapides)],
                                   missions: [.success(Self.page(["m-1"]))])
        let (controller, snapshot) = try await pret(port)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.totaux, .echec(RevenusTextes.totauxIndisponibles))
        XCTAssertEqual(model.paiementsRapides, .echec("Connexion impossible."))
        XCTAssertEqual(model.missions.map(\.id), ["m-1"])
        XCTAssertNil(model.erreur)

        await model.rechargerPaiementsRapides()
        XCTAssertEqual(model.paiementsRapides, .pret(Self.rapides))
        XCTAssertTrue(model.escrowAffiche.afficheSection)
        await model.rechargerTotaux()
        XCTAssertEqual(model.totaux, .pret(Self.totaux))
        XCTAssertEqual(port.pages, [0], "relire une section ne relit pas les missions")
    }

    func testEchecNonJoleneDesSectionsDonneLesMessagesDuWeb() async throws {
        struct Inattendue: Error {}
        let port = ScriptedRevenus(totaux: [.failure(Inattendue())], rapides: [.failure(Inattendue())], missions: [.success(Self.page([]))])
        let (controller, snapshot) = try await pret(port)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.totaux, .echec(RevenusTextes.totauxIndisponibles))
        XCTAssertEqual(model.paiementsRapides, .echec(RevenusTextes.escrowErreurDefaut))
    }

    // MARK: - Epoch

    func testReponseDUnEpochPerimeIgnoree() async throws {
        let port = ScriptedRevenus(totaux: [.success(nil)], rapides: [.success([])], missions: [.success(Self.page(["m-1"]))])
        let gate = Gate()
        port.retenue = gate
        let (controller, snapshot) = try await pret(port)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        let chargement = Task { await model.charger() }
        while port.pages.isEmpty { await Task.yield() }
        _ = await controller.signOut()
        await gate.open()
        await chargement.value
        XCTAssertTrue(model.missions.isEmpty, "identité changée pendant la lecture : rien n'est publié")
        XCTAssertNil(model.erreur)
        XCTAssertFalse(model.missionsChargees)
    }

    func testChargerSiNecessaireNeRelitPasUnEcranCharge() async throws {
        let port = ScriptedRevenus(totaux: [.success(nil)], rapides: [.success([])], missions: [.success(Self.page(["m-1"]))])
        let (controller, snapshot) = try await pret(port)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.chargerSiNecessaire()
        await model.chargerSiNecessaire()
        XCTAssertEqual(port.pages, [0], "retour sur l'onglet : aucune relecture automatique d'un écran chargé")
    }
}
