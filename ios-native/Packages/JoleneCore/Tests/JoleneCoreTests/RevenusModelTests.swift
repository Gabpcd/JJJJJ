import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurRevenus = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                   emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                   appMetadataRole: "SOIGNANT")

/// Modèle de l'onglet Revenus (lot 3, T12, B9 ; lecture seule) : trois sections lues pour l'epoch de la session,
/// chacune avec son état (totaux serveur, paiements rapides, missions terminées paginées par 50), audit
/// `DONNEES_PERSO_CONSULTATION` (`page: mes_gains`) une seule fois par session (epoch : le modèle vit autant que
/// l'onglet, toujours monté), après une lecture réussie, jamais bloquant ; échec des missions → « Impossible de charger tous les revenus » + message, liste gardée, « Réessayer »
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
        private var lecturesTotaux = 0
        private var lecturesRapides = 0
        var retenue: Gate?

        init(totaux: [Result<TotauxRevenus?, Error>] = [], rapides: [Result<[PaiementRapide], Error>] = [],
             missions: [Result<PageMissionsTerminees, Error>] = []) {
            totauxEtapes = totaux; rapidesEtapes = rapides; missionsEtapes = missions
        }

        var pages: [Int] { lock.lock(); defer { lock.unlock() }; return pagesDemandees }
        var appelsTotaux: Int { lock.lock(); defer { lock.unlock() }; return lecturesTotaux }
        var appelsRapides: Int { lock.lock(); defer { lock.unlock() }; return lecturesRapides }

        private func suivante<V>(_ file: inout [Result<V, Error>]) -> Result<V, Error> {
            lock.lock(); defer { lock.unlock() }
            return file.isEmpty ? .failure(nonScripte) : file.removeFirst()
        }

        func totaux(context: MissionReadContext) async throws -> TotauxRevenus? {
            compter(&lecturesTotaux)
            return try suivante(&totauxEtapes).get()
        }
        func paiementsRapides(context: MissionReadContext) async throws -> [PaiementRapide] {
            compter(&lecturesRapides)
            return try suivante(&rapidesEtapes).get()
        }

        private func compter(_ compteur: inout Int) {
            lock.lock(); defer { lock.unlock() }
            compteur += 1
        }
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

    /// Horloge que le test fait avancer (relecture au-delà de 60 s, revue B8 de T12, m1).
    private final class HorlogeReglable: ClockPort, @unchecked Sendable {
        private let lock = NSLock()
        private var instant: Date
        init(_ instant: Date) { self.instant = instant }
        func now() -> Date { lock.lock(); defer { lock.unlock() }; return instant }
        func avancer(_ secondes: TimeInterval) { lock.lock(); instant += secondes; lock.unlock() }
    }

    /// Audit retenu (revue B8 de T12, m2) : signale son entrée, attend la porte de sortie, puis note l'écriture, ou
    /// « annulé » si sa tâche a été annulée entre-temps (requête réseau abandonnée).
    private struct AuditRetenu: AuditPort {
        let journal: JournalAudit
        let entree: Gate
        let sortie: Gate
        func connexion() async throws -> AuditResultat { .enregistre }
        func deconnexion() async throws -> AuditResultat { .enregistre }
        func activite() async throws -> AuditResultat { .enregistre }
        func ecrire(action: AuditAction, typeRessource: String, idRessource: String, details: [String: String],
                    context: MissionReadContext) async throws -> AuditResultat {
            await entree.open()
            await sortie.wait()
            if Task.isCancelled {
                await journal.noter("annulé")
                throw CancellationError()
            }
            await journal.noter("\(action.rawValue) \(typeRessource) \(idRessource) \(details)")
            return .enregistre
        }
    }

    private static let totaux = TotauxRevenus(moisEnCours: 195, total: 1425.6, enAttente: 780, stripeConnectActif: true)
    private static let rapides = [PaiementRapide(missionId: "m-r", honorairesCents: 24000, etat: "RESERVE")]

    private static func page(_ ids: [String], page: Int = 0, aSuivre: Bool = false) -> PageMissionsTerminees {
        PageMissionsTerminees(missions: ids.map { MissionTerminee(id: $0, typeContratApplique: "SALARIE") }, page: page, aSuivre: aSuivre,
                              derniersPaiements: [:])
    }

    private func pret(_ port: ScriptedRevenus, journal: JournalAudit = JournalAudit(),
                      auditErreur: JoleneError? = nil, audit: (any AuditPort)? = nil,
                      horloge: any ClockPort = FixedClock(DemoWorld.fixedNow)) async throws -> (SessionController, SessionSnapshot) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: horloge)
        gateways.revenus = port
        gateways.audit = audit ?? AuditEspion(journal: journal, erreur: auditErreur)
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
        // L'audit part hors de la lecture (revue B8 de T12, m2) : son issue est attendue avant le constat.
        await model.auditEnCours?.value
        let premieres = await journal.ecritures
        XCTAssertEqual(premieres, ["DONNEES_PERSO_CONSULTATION soignant u-1 [\"page\": \"mes_gains\"]"],
                       "audit du web (MesGains.tsx l.147-153), sur l'utilisateur de la session")

        await model.charger() // tirer pour actualiser : page 0 relue, liste remplacée
        XCTAssertEqual(model.missions.map(\.id), ["m-1"])
        await model.auditEnCours?.value
        let apres = await journal.ecritures
        XCTAssertEqual(apres.count, 1, "une seule consultation journalisée par session (epoch), pas à chaque lecture")
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
        XCTAssertNil(model.auditEnCours, "aucun audit lancé sans lecture réussie")
        let avant = await journal.ecritures
        XCTAssertTrue(avant.isEmpty, "aucune consultation journalisée sans lecture réussie")

        await model.reessayer()
        XCTAssertNil(model.erreur)
        XCTAssertEqual(model.missions.map(\.id), ["m-1"])
        await model.auditEnCours?.value
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
        await model.auditEnCours?.value
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
                                          page: 1, aSuivre: false, derniersPaiements: [:])
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

    /// Une lecture annulée (changement d'onglet pendant le chargement) n'est jamais une erreur et laisse la section à lire :
    /// l'apparition suivante la relit, sans relire ce qui a abouti ; un échec, lui, attend « Réessayer ».
    func testApparitionApresUneLectureAnnuleeRelitSeulementCeQuiReste() async throws {
        let port = ScriptedRevenus(totaux: [.success(Self.totaux)], rapides: [.failure(CancellationError()), .success(Self.rapides)],
                                   missions: [.failure(CancellationError()), .success(Self.page(["m-1"]))])
        let (controller, snapshot) = try await pret(port)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.chargerSiNecessaire()
        XCTAssertEqual(model.totaux, .pret(Self.totaux))
        XCTAssertEqual(model.paiementsRapides, .chargement, "annulation : jamais un échec affiché")
        XCTAssertNil(model.erreur)
        XCTAssertFalse(model.missionsChargees)

        await model.chargerSiNecessaire()
        XCTAssertEqual(model.paiementsRapides, .pret(Self.rapides))
        XCTAssertEqual(model.missions.map(\.id), ["m-1"])
        XCTAssertEqual(port.pages, [0, 0])

        let echec = ScriptedRevenus(totaux: [.success(nil)], rapides: [.success([])],
                                    missions: [.failure(JoleneError(.network, "Connexion impossible."))])
        let (controller2, snapshot2) = try await pret(echec)
        let enEchec = RevenusModel(controller: controller2, snapshot: snapshot2)
        await enEchec.chargerSiNecessaire()
        await enEchec.chargerSiNecessaire()
        XCTAssertEqual(echec.pages, [0], "un échec attend « Réessayer » : aucune relecture à l'apparition")
    }

    func testChargerSiNecessaireNeRelitPasUnEcranChargeIlYAMoinsDeSoixanteSecondes() async throws {
        let port = ScriptedRevenus(totaux: [.success(nil)], rapides: [.success([])], missions: [.success(Self.page(["m-1"]))])
        let (controller, snapshot) = try await pret(port)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.chargerSiNecessaire()
        await model.chargerSiNecessaire()
        XCTAssertEqual(port.pages, [0], "retour sur l'onglet avant 60 s : aucune relecture d'un écran chargé")
        XCTAssertEqual(port.appelsTotaux, 1)
        XCTAssertEqual(port.appelsRapides, 1)
    }

    // MARK: - Revue B8 de T12

    /// m1 : le web relit l'aperçu à chaque montage de `/soignant/mes-gains` ; l'onglet natif, toujours monté, relit à
    /// l'apparition (retour sur l'onglet, retour au premier plan) chaque section lue il y a plus de `delaiRelecture`
    /// (60 s, comme l'Accueil), sans jamais relancer un échec (« Réessayer »).
    func testApparitionRelitLesSectionsLuesIlYAPlusDeSoixanteSecondes() async throws {
        let horloge = HorlogeReglable(DemoWorld.fixedNow)
        let port = ScriptedRevenus(totaux: [.success(Self.totaux), .success(nil)],
                                   rapides: [.success(Self.rapides), .success([])],
                                   missions: [.success(Self.page(["m-1", "m-2"])), .success(Self.page(["m-3"]))])
        let (controller, snapshot) = try await pret(port, horloge: horloge)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.chargerSiNecessaire()
        XCTAssertEqual(port.pages, [0])

        horloge.avancer(RevenusModel.delaiRelecture)
        await model.chargerSiNecessaire()
        XCTAssertEqual(port.pages, [0], "60 s pile : données encore fraîches")
        XCTAssertEqual(port.appelsTotaux, 1)

        horloge.avancer(1)
        await model.chargerSiNecessaire()
        XCTAssertEqual(port.pages, [0, 0], "au-delà de 60 s : missions relues depuis la page 0, comme un montage web")
        XCTAssertEqual(port.appelsTotaux, 2)
        XCTAssertEqual(port.appelsRapides, 2)
        XCTAssertEqual(model.missions.map(\.id), ["m-3"])
        XCTAssertEqual(model.totaux, .masques)
        XCTAssertEqual(model.paiementsRapides, .pret([]))
        XCTAssertEqual(RevenusModel.delaiRelecture, AccueilModel.delaiRelecture)

        // Un échec n'est jamais relancé par l'apparition, même périmé.
        let echec = ScriptedRevenus(totaux: [.failure(JoleneError(.unknown, RevenusTextes.totauxIndisponibles))],
                                    rapides: [.success([])], missions: [.failure(JoleneError(.network, "Connexion impossible."))])
        let horloge2 = HorlogeReglable(DemoWorld.fixedNow)
        let (controller2, snapshot2) = try await pret(echec, horloge: horloge2)
        let enEchec = RevenusModel(controller: controller2, snapshot: snapshot2)
        await enEchec.chargerSiNecessaire()
        horloge2.avancer(RevenusModel.delaiRelecture + 1)
        await enEchec.chargerSiNecessaire()
        XCTAssertEqual(echec.pages, [0], "échec des missions : « Réessayer », jamais une relecture à l'apparition")
        XCTAssertEqual(echec.appelsTotaux, 1, "échec des totaux : « Réessayer »")
        XCTAssertEqual(echec.appelsRapides, 2, "section réussie et périmée : relue")
    }

    /// m1 : un lien universel `/soignant/mes-gains` ou un tap qui présente l'onglet (`MainTabView.presenter(.revenus)`)
    /// avance le jeton de péremption : relecture immédiate, même avant 60 s, une seule fois par jeton ; une relecture
    /// annulée reste due.
    func testJetonDePeremptionImposeUneRelectureAvantSoixanteSecondes() async throws {
        let port = ScriptedRevenus(totaux: [.success(Self.totaux), .success(Self.totaux), .success(Self.totaux)],
                                   rapides: [.success(Self.rapides), .success(Self.rapides), .success(Self.rapides)],
                                   missions: [.success(Self.page(["m-1"])), .failure(CancellationError()), .success(Self.page(["m-2"]))])
        let (controller, snapshot) = try await pret(port)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.chargerSiNecessaire(peremption: 0)
        await model.chargerSiNecessaire(peremption: 0)
        XCTAssertEqual(port.pages, [0], "même jeton, moins de 60 s : données fraîches")

        await model.chargerSiNecessaire(peremption: 1)
        XCTAssertEqual(port.pages, [0, 0], "jeton avancé : relecture immédiate")
        XCTAssertEqual(port.appelsTotaux, 2)
        XCTAssertEqual(model.missions.map(\.id), ["m-1"], "relecture annulée : rien n'est publié, la liste reste")
        XCTAssertNil(model.erreur, "annulation : jamais une erreur")

        await model.chargerSiNecessaire(peremption: 1)
        XCTAssertEqual(port.pages, [0, 0, 0], "relecture des missions annulée : toujours due à l'apparition suivante")
        XCTAssertEqual(port.appelsTotaux, 2, "totaux relus avec succès pour ce jeton : pas de seconde relecture")
        XCTAssertEqual(model.missions.map(\.id), ["m-2"])

        await model.chargerSiNecessaire(peremption: 1)
        XCTAssertEqual(port.pages, [0, 0, 0], "jeton déjà vu, données fraîches : rien")
    }

    /// m2 : l'audit `DONNEES_PERSO_CONSULTATION` est lancé après la publication, hors du chargement (fire-and-forget du
    /// web, l.147-153) : « Charger plus », « Réessayer » et l'indicateur de tirer-pour-actualiser ne l'attendent jamais,
    /// et l'annulation de la tâche de la vue (changement d'onglet) ne le perd pas.
    func testAuditNeRetientJamaisLEcranEtSurvitALAnnulationDeLaVue() async throws {
        let port = ScriptedRevenus(totaux: [.success(nil)], rapides: [.success([])],
                                   missions: [.success(Self.page((0..<50).map { "m-\($0)" }, aSuivre: true))])
        let journal = JournalAudit()
        let entree = Gate(), sortie = Gate()
        let (controller, snapshot) = try await pret(port, audit: AuditRetenu(journal: journal, entree: entree, sortie: sortie))
        let model = RevenusModel(controller: controller, snapshot: snapshot)

        let tache = Task { await model.chargerSiNecessaire() }
        await entree.wait() // audit en vol
        XCTAssertTrue(model.missionsChargees)
        XCTAssertFalse(model.chargementMissions, "la lecture est terminée : l'audit ne retient ni le spinner ni « Charger plus »")
        tache.cancel() // la vue disparaît pendant l'écriture d'audit
        await tache.value
        await sortie.open()
        await model.auditEnCours?.value
        let ecritures = await journal.ecritures
        XCTAssertEqual(ecritures, ["DONNEES_PERSO_CONSULTATION soignant u-1 [\"page\": \"mes_gains\"]"],
                       "l'audit de cette session n'est jamais perdu par l'annulation de la vue")
    }

    /// m3 : après l'échec d'une page suivante, « Charger plus » est masqué (« Réessayer » est proposé) et, s'il est
    /// appelé, relit la page en échec : aucune page n'est sautée (défaut du web l.797-798 non reproduit).
    func testChargerPlusApresUnEchecRelitLaPageEnEchecSansEnSauter() async throws {
        let pleine = Self.page((0..<50).map { "m-\($0)" }, aSuivre: true)
        let suite = Self.page((50..<100).map { "m-\($0)" }, page: 1, aSuivre: true)
        let port = ScriptedRevenus(totaux: [.success(nil)], rapides: [.success([])],
                                   missions: [.success(pleine), .failure(JoleneError(.network, "Connexion impossible.")), .success(suite)])
        let (controller, snapshot) = try await pret(port)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertTrue(model.afficheChargerPlus)

        await model.chargerPlus()
        XCTAssertEqual(model.erreur, "Connexion impossible.")
        XCTAssertTrue(model.aSuivre)
        XCTAssertFalse(model.afficheChargerPlus, "bandeau d'erreur : « Réessayer » seul, jamais « Charger plus » à côté")

        await model.chargerPlus()
        XCTAssertEqual(port.pages, [0, 1, 1], "la page 1 en échec est relue, jamais la page 2")
        XCTAssertNil(model.erreur)
        XCTAssertEqual(model.missions.count, 100)
        XCTAssertTrue(model.afficheChargerPlus)
    }

    // MARK: - Revue B8 n°2 de T12

    /// m2 : chaque lecture d'une page relit TOUTES les déclarations du soignant (`paiements_soignant` sans filtre de
    /// mission, `MesGains.tsx` l.102-107) et le web remplace la carte entière (`setPaiementsMap`, l.140-142) : après
    /// « Charger plus », les lignes des pages précédentes prennent l'état de la dernière lecture, jamais celui de leur
    /// propre lecture. Exemple de la revue : une déclaration confirmée entre la page 0 et la page 1.
    func testChargerPlusRelitLEtatDesLignesDesPagesPrecedentes() async throws {
        let declare = PaiementSoignantLu(id: "p-0", missionId: "m-0", statut: "DECLARE", montantNet: .nombre(162.4),
                                         confirmeParSoignant: false, modifieLe: "2026-10-01T08:00:00+00:00")
        let confirme = PaiementSoignantLu(id: "p-0", missionId: "m-0", statut: "CONFIRME", montantNet: .nombre(162.4),
                                          confirmeParSoignant: true, modifieLe: "2026-10-02T08:00:00+00:00")
        let retiree = PaiementSoignantLu(id: "p-1", missionId: "m-1", statut: "DECLARE", montantNet: .nombre(80),
                                         modifieLe: "2026-10-01T08:00:00+00:00")
        let salariees = { (ids: Range<Int>) in ids.map { MissionTerminee(id: "m-\($0)", typeContratApplique: "SALARIE") } }
        let premiere = RevenusAssemblage.page(salariees(0..<50), paiements: [declare, retiree], etablissements: [:], page: 0)
        let suite = RevenusAssemblage.page(salariees(50..<51), paiements: [confirme], etablissements: [:], page: 1)
        let port = ScriptedRevenus(totaux: [.success(nil)], rapides: [.success([])], missions: [.success(premiere), .success(suite)])
        let (controller, snapshot) = try await pret(port)
        let model = RevenusModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.lignes[0].etat.texte, "Réception à confirmer")
        XCTAssertEqual(model.lignes[1].etat.texte, "Réception à confirmer")

        await model.chargerPlus()
        XCTAssertEqual(port.pages, [0, 1])
        XCTAssertEqual(model.missions.count, 51)
        XCTAssertEqual(model.missions[0].dernierPaiement, confirme)
        XCTAssertEqual(model.lignes[0].etat.texte, "Réception confirmée",
                       "déclaration confirmée entre les deux pages : état de la dernière lecture, comme le web")
        XCTAssertNil(model.missions[1].dernierPaiement, "déclaration absente de la dernière lecture : carte du web remplacée")
        XCTAssertEqual(model.lignes[1].etat.texte, "Aucun versement déclaré")
        XCTAssertNil(model.missions[50].dernierPaiement)
    }

    /// m3 : la trace `DONNEES_PERSO_CONSULTATION` est écrite une fois par SESSION (epoch), pas une fois par ouverture : le
    /// modèle vit autant que l'onglet, toujours monté (`StateObject` de `RevenusScreen` dans `MainTabView`). Une relecture
    /// au-delà de 60 s, un jeton de péremption (assimilés à un montage web pour les données, revue B8 de T12, m1),
    /// « Charger plus » et « Réessayer » ne la réécrivent pas, alors que le web l'écrit à chaque chargement réussi
    /// (montage, page, `reloadKey`, l.147-153) : trace moins fréquente que le web, écart consigné (`DECISIONS_LOT3.md`,
    /// section T12, revue B8 n°2) ; plan v2 : « audit consultation une fois ». Une nouvelle session (nouvel epoch, nouveau
    /// modèle) l'écrit de nouveau.
    func testAuditUneSeuleFoisParSessionMemeApresRelecturesEtPages() async throws {
        let horloge = HorlogeReglable(DemoWorld.fixedNow)
        let pleine = Self.page((0..<50).map { "m-\($0)" }, aSuivre: true)
        let port = ScriptedRevenus(totaux: Array(repeating: .success(nil), count: 4), rapides: Array(repeating: .success([]), count: 4),
                                   missions: [.success(pleine), .success(pleine), .success(pleine),
                                              .success(Self.page(["m-50"], page: 1))])
        let journal = JournalAudit()
        let (controller, snapshot) = try await pret(port, journal: journal, horloge: horloge)
        let model = RevenusModel(controller: controller, snapshot: snapshot)

        await model.chargerSiNecessaire(peremption: 0)
        await model.auditEnCours?.value
        await model.chargerSiNecessaire(peremption: 1) // lien universel ou tap : relecture immédiate
        await model.auditEnCours?.value
        horloge.avancer(RevenusModel.delaiRelecture + 1)
        await model.chargerSiNecessaire(peremption: 1) // retour sur l'onglet au-delà de 60 s
        await model.auditEnCours?.value
        await model.chargerPlus()
        await model.auditEnCours?.value
        XCTAssertEqual(port.pages, [0, 0, 0, 1], "trois lectures de la page 0 et une page suivante, toutes réussies")
        let ecritures = await journal.ecritures
        XCTAssertEqual(ecritures, ["DONNEES_PERSO_CONSULTATION soignant u-1 [\"page\": \"mes_gains\"]"],
                       "une seule trace par session (epoch), quel que soit le nombre de lectures")

        // Nouvelle session : nouveau modèle, nouvelle trace.
        let autre = ScriptedRevenus(totaux: [.success(nil)], rapides: [.success([])], missions: [.success(Self.page(["m-1"]))])
        let journal2 = JournalAudit()
        let (controller2, snapshot2) = try await pret(autre, journal: journal2)
        let nouvelle = RevenusModel(controller: controller2, snapshot: snapshot2)
        await nouvelle.chargerSiNecessaire()
        await nouvelle.auditEnCours?.value
        let ecritures2 = await journal2.ecritures
        XCTAssertEqual(ecritures2.count, 1)
    }
}
