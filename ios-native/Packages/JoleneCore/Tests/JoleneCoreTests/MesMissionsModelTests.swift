import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurMesMissions = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                       emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                       appMetadataRole: "SOIGNANT")

/// Modèle de « Mes missions » (lot 1, T5) : mêmes règles que `AccueilModel` (annulation jamais
/// affichée en erreur, relecture sans démontage, session expirée, epoch périmé et lecture dépassée
/// ignorés, borne `resolutionTimeout`), plus la relecture de la première page à chaque sélection
/// d'onglet (web : `setPage(0)` au changement d'onglet) et la lecture **cumulative** du web (« M1 »,
/// `range(0, (page + 1) * 50 - 1)`) : « Charger plus » relit les pages 0…n+1 et remplace la liste,
/// seulement après une lecture pleine ; une relecture (apparition, tirer pour actualiser) garde les
/// pages déjà chargées.
@MainActor
final class MesMissionsModelTests: XCTestCase {
    private struct ModelError: Error {}

    /// Port scripté : chaque appel consomme l'étape suivante de sa méthode et s'inscrit au journal.
    /// Une étape `retenue` attend l'ouverture de sa barrière (deux lectures se chevauchent).
    private final class ScriptedMesMissions: MesMissionsPort, @unchecked Sendable {
        enum Etape {
            case candidatures([CandidatureRecord])
            case page(MissionsPage)
            case echec(Error)
            case retenue(MissionsPage, entree: Gate, sortie: Gate)
            /// Échoue après l'ouverture de sa barrière (erreur tardive d'une lecture chevauchée).
            case retenueEchec(Error, entree: Gate, sortie: Gate)
            /// Ne répond jamais (délai de l'écran).
            case muet(Gate)
        }
        private let lock = NSLock()
        private var etapes: [String: [Etape]]
        private var appelsRecus: [String] = []

        init(candidatures: [Etape] = [], aVenir: [Etape] = [], passees: [Etape] = []) {
            etapes = ["candidatures": candidatures, "aVenir": aVenir, "passees": passees]
        }

        var appels: [String] { lock.lock(); defer { lock.unlock() }; return appelsRecus }

        private func suivante(_ methode: String, page: Int?) -> Etape {
            lock.lock(); defer { lock.unlock() }
            appelsRecus.append(page.map { "\(methode) \($0)" } ?? methode)
            guard var file = etapes[methode], !file.isEmpty else { return .echec(nonScripte) }
            let etape = file.removeFirst()
            etapes[methode] = file
            return etape
        }

        private func jouer(_ etape: Etape) async throws -> MissionsPage {
            switch etape {
            case let .page(page): return page
            case let .echec(error): throw error
            case let .retenue(page, entree, sortie):
                await entree.open()
                await sortie.wait()
                return page
            case let .retenueEchec(error, entree, sortie):
                await entree.open()
                await sortie.wait()
                throw error
            case let .muet(gate):
                await gate.wait()
                throw CancellationError()
            case .candidatures: throw nonScripte
            }
        }

        func candidatures(context: MissionReadContext) async throws -> [CandidatureRecord] {
            switch suivante("candidatures", page: nil) {
            case let .candidatures(lignes): return lignes
            case let .echec(error): throw error
            default: throw nonScripte
            }
        }

        func aVenir(context: MissionReadContext, page: Int) async throws -> MissionsPage {
            try await jouer(suivante("aVenir", page: page))
        }

        func passees(context: MissionReadContext, page: Int) async throws -> MissionsPage {
            try await jouer(suivante("passees", page: page))
        }
    }

    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurMesMissions }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw ModelError() }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    private func mission(_ id: String) -> Mission {
        let record = MissionRecord(id: id, intitule: "Mission \(id)", description: nil, service: nil, professionRequise: "IDE",
                                   specialiteMedicaleRequise: nil, accepteNonSpecialises: nil, debutLe: "2026-11-05T07:00:00.000Z",
                                   finLe: "2026-11-05T15:00:00.000Z", dureeHeures: 8, nbCreneaux: 1, tauxHoraireBase: 27,
                                   tauxRistPlafonne: nil, ristPlafondApplique: false, totalBrut: nil, netAPayer: nil,
                                   estUrgente: false, niveauUrgence: nil, statut: "ASSIGNEE", etablissementId: "e-1",
                                   typeContratRecherche: "SALARIE", boosteeLe: nil, modeRemuneration: nil, retrocessionPct: nil)
        return Mission(record: record, etablissement: nil, distanceKm: nil, creneauxPlanifies: [], planningExact: true)
    }

    private func page(_ ids: [String], page numero: Int = 0, aSuivre: Bool = false,
                      finances: [String: MissionGainLigne] = [:]) -> MissionsPage {
        var lue = MissionsPage(missions: ids.map(mission), page: numero, aSuivre: aSuivre)
        lue.finances = finances
        return lue
    }

    private func finance(_ id: String) -> MissionGainLigne {
        MissionGainLigne(id: id, typeContratApplique: "LIBERAL", typeContratRecherche: nil, totalBrut: nil, netAPayer: 100, netEstime: nil)
    }

    private func pret(_ port: ScriptedMesMissions, timeout: TimeInterval = SessionController.defaultResolutionTimeout)
        async throws -> (SessionController, SessionSnapshot) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.mesMissions = port
        let controller = SessionController(gateways: gateways, resolutionTimeout: timeout)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return (controller, snapshot)
    }

    // MARK: - Lecture

    func testOngletParDefautAVenirEtPremiereLecture() async throws {
        let port = ScriptedMesMissions(aVenir: [.page(page(["m-1", "m-2"]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        XCTAssertEqual(model.onglet, .aVenir, "onglet du web par défaut")
        XCTAssertEqual(model.aVenir.contenu, .chargement)
        await model.charger()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1", "m-2"])
        XCTAssertEqual(model.aVenir.page, 0)
        XCTAssertFalse(model.aVenir.aSuivre)
        XCTAssertFalse(model.aVenir.rafraichissement)
        XCTAssertEqual(model.horloge.now(), DemoWorld.fixedNow, "horloge des gateways de la session")
        XCTAssertEqual(model.mission(id: "m-2")?.id, "m-2", "valeur initiale du détail")
        XCTAssertEqual(port.appels, ["aVenir 0"])
        XCTAssertEqual(model.candidatures.contenu, .chargement, "les autres onglets ne sont lus qu'à leur sélection")
    }

    func testChaqueSelectionDOngletRelitSaPremierePage() async throws {
        var candidature = CandidatureRecord(id: "c-1", missionId: "m-9", statut: "EN_ATTENTE", message: nil, typeContratChoisi: nil, creeLe: nil)
        candidature.mission = mission("m-9")
        let port = ScriptedMesMissions(candidatures: [.candidatures([candidature]), .candidatures([])],
                                       aVenir: [.page(page(["m-1"]))],
                                       passees: [.page(page(["m-5"], finances: ["m-5": finance("m-5")]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot, onglet: .candidatures)
        await model.charger()
        XCTAssertEqual(model.candidatures.elements.map(\.id), ["c-1"])
        XCTAssertEqual(model.mission(id: "m-9")?.id, "m-9")
        await model.selectionner(.passees)
        XCTAssertEqual(model.onglet, .passees)
        XCTAssertEqual(model.passees.elements.map(\.id), ["m-5"])
        XCTAssertEqual(model.finances["m-5"]?.netAPayer, 100)
        await model.selectionner(.aVenir)
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1"])
        await model.selectionner(.candidatures)
        XCTAssertEqual(model.candidatures.elements, [], "relue à la sélection : la candidature retirée disparaît")
        XCTAssertEqual(port.appels, ["candidatures", "passees 0", "aVenir 0", "candidatures"])
    }

    func testRelectureConserveLaListeEtExposeSonErreur() async throws {
        let port = ScriptedMesMissions(aVenir: [.page(page(["m-1"])), .echec(JoleneError(.network, "Connexion impossible.")),
                                                .echec(CancellationError()), .page(page(["m-2"]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        await model.charger()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1"], "la liste reste à l'écran après une relecture échouée")
        XCTAssertEqual(model.aVenir.erreurRafraichissement, "Connexion impossible.")
        XCTAssertFalse(model.aVenir.rafraichissement)
        await model.charger()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1"], "relecture interrompue : liste conservée")
        XCTAssertNil(model.aVenir.erreurRafraichissement)
        await model.charger()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-2"], "le succès remplace la liste")
    }

    func testEchecDePremiereLectureEtMessageGenerique() async throws {
        let port = ScriptedMesMissions(passees: [.echec(JoleneError(.network, "Connexion impossible.")), .echec(ModelError()),
                                                 .page(page(["m-1"]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot, onglet: .passees)
        await model.charger()
        XCTAssertEqual(model.passees.contenu, .echec("Connexion impossible."))
        await model.charger()
        XCTAssertEqual(model.passees.contenu, .echec(MesMissionsModel.genericFailureMessage), "jamais le détail technique")
        await model.charger()
        XCTAssertEqual(model.passees.elements.map(\.id), ["m-1"], "« Réessayer » relit")
    }

    func testAnnulationLaisseLEtatEnChargement() async throws {
        let port = ScriptedMesMissions(aVenir: [.echec(CancellationError()), .echec(JoleneError(.cancelled, "Chargement annulé."))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.aVenir.contenu, .chargement)
        await model.charger()
        XCTAssertEqual(model.aVenir.contenu, .chargement, "`.task` relancera la lecture au prochain affichage")
        XCTAssertNil(model.aVenir.erreurRafraichissement)
    }

    func testSessionExpireeSignaleePourRevalidation() async throws {
        let port = ScriptedMesMissions(candidatures: [.echec(JoleneError(.unauthorized, SessionController.sessionExpiredMessage)), .candidatures([])])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot, onglet: .candidatures)
        await model.charger()
        XCTAssertTrue(model.sessionExpired)
        XCTAssertEqual(model.candidatures.contenu, .echec(SessionController.sessionExpiredMessage))
        await model.charger()
        XCTAssertFalse(model.sessionExpired, "une lecture réussie lève l'indicateur")
        XCTAssertEqual(model.candidatures.contenu, .chargee([]))
    }

    /// Revue B8 de T5 : une erreur qui n'est pas une `JoleneError`, après une session expirée, n'est
    /// pas affichée « Session à vérifier » (indicateur baissé, message générique, « Réessayer »).
    func testErreurGeneriqueApresSessionExpireeBaisseLIndicateur() async throws {
        let port = ScriptedMesMissions(aVenir: [.echec(JoleneError(.unauthorized, SessionController.sessionExpiredMessage)),
                                                .echec(ModelError())])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertTrue(model.sessionExpired)
        await model.charger()
        XCTAssertFalse(model.sessionExpired, "une panne quelconque n'est pas une session expirée")
        XCTAssertEqual(model.aVenir.contenu, .echec(MesMissionsModel.genericFailureMessage))
    }

    /// Revue B8 de T5 (2e passe) : l'indicateur de session est rangé par onglet, comme l'erreur. Une
    /// panne réseau d'un autre onglet n'est pas affichée « Session à vérifier », et le succès d'un autre
    /// onglet n'efface pas l'indicateur de l'onglet resté en échec de session.
    func testSessionExpireeRangeeParOngletCommeLErreur() async throws {
        let port = ScriptedMesMissions(candidatures: [.echec(JoleneError(.unauthorized, SessionController.sessionExpiredMessage))],
                                       aVenir: [.echec(JoleneError(.network, "Connexion impossible."))],
                                       passees: [.page(page(["m-5"]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot, onglet: .candidatures)
        await model.charger()
        XCTAssertTrue(model.candidatures.sessionExpiree)
        XCTAssertTrue(model.sessionExpired, "onglet affiché en échec de session : « Vérifier ma session »")
        await model.selectionner(.aVenir)
        XCTAssertEqual(model.aVenir.contenu, .echec("Connexion impossible."))
        XCTAssertFalse(model.aVenir.sessionExpiree, "une panne réseau n'est pas une session expirée")
        XCTAssertFalse(model.sessionExpired, "onglet affiché en panne : « Réessayer »")
        XCTAssertTrue(model.candidatures.sessionExpiree, "l'onglet resté en échec de session le reste")
        await model.selectionner(.passees)
        XCTAssertEqual(model.passees.elements.map(\.id), ["m-5"])
        XCTAssertFalse(model.sessionExpired)
        XCTAssertTrue(model.candidatures.sessionExpiree, "le succès d'un autre onglet n'efface pas l'indicateur")
        XCTAssertFalse(model.aVenir.sessionExpiree)
    }

    /// Revue B8 de T5 (2e passe) : deux lectures d'onglets différents se chevauchent ; le
    /// `.unauthorized` arrivé en retard sur À venir ne marque pas l'erreur réseau de Candidatures,
    /// affichée entre-temps.
    func testSessionExpireeTardiveDUnOngletNeMarquePasLErreurDUnAutre() async throws {
        let entree = Gate()
        let sortie = Gate()
        let port = ScriptedMesMissions(candidatures: [.echec(JoleneError(.network, "Connexion impossible."))],
                                       aVenir: [.retenueEchec(JoleneError(.unauthorized, SessionController.sessionExpiredMessage),
                                                              entree: entree, sortie: sortie)])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        let lente = Task { await model.charger() }
        await entree.wait()
        await model.selectionner(.candidatures)
        XCTAssertEqual(model.candidatures.contenu, .echec("Connexion impossible."))
        await sortie.open()
        await lente.value
        XCTAssertEqual(model.aVenir.contenu, .echec(SessionController.sessionExpiredMessage), "l'échec reste rangé sur son onglet")
        XCTAssertTrue(model.aVenir.sessionExpiree)
        XCTAssertFalse(model.candidatures.sessionExpiree)
        XCTAssertFalse(model.sessionExpired, "l'onglet affiché garde « Réessayer » sur son erreur réseau")
    }

    // MARK: - Pages (lecture cumulative du web, « M1 »)

    /// Revue B8 de T5 (2e passe) : pendant une relecture, « Charger plus » ne ferait rien ; le bouton
    /// est donc désactivé (`peutChargerPlus`, seule règle du modèle et de l'écran), jamais un tap
    /// perdu sans retour. Même règle pendant le chargement de la page suivante.
    func testChargerPlusInactifPendantUneRelectureEtPendantLaSuite() async throws {
        let entree = Gate()
        let sortie = Gate()
        let entreeSuite = Gate()
        let sortieSuite = Gate()
        let port = ScriptedMesMissions(aVenir: [.page(page(["m-1"], aSuivre: true)),
                                                .retenue(page(["m-1"], aSuivre: true), entree: entree, sortie: sortie),
                                                .retenue(page(["m-1", "m-2"], page: 1, aSuivre: true), entree: entreeSuite, sortie: sortieSuite),
                                                .page(page(["m-1", "m-2"], page: 2))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        XCTAssertFalse(model.aVenir.peutChargerPlus, "rien avant une première page lue")
        await model.charger()
        XCTAssertTrue(model.aVenir.peutChargerPlus)

        let relecture = Task { await model.charger() }
        await entree.wait()
        XCTAssertTrue(model.aVenir.rafraichissement)
        XCTAssertFalse(model.aVenir.peutChargerPlus, "bouton désactivé pendant la relecture")
        await model.chargerPlus()
        XCTAssertEqual(port.appels, ["aVenir 0", "aVenir 0"], "aucune page suivante pendant la relecture")
        await sortie.open()
        await relecture.value
        XCTAssertTrue(model.aVenir.peutChargerPlus, "relecture terminée : « Charger plus » de nouveau actif")

        let suite = Task { await model.chargerPlus() }
        await entreeSuite.wait()
        XCTAssertTrue(model.aVenir.chargementSuite)
        XCTAssertFalse(model.aVenir.peutChargerPlus, "bouton désactivé pendant la page suivante")
        await sortieSuite.open()
        await suite.value
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1", "m-2"])
        XCTAssertTrue(model.aVenir.peutChargerPlus)
        await model.chargerPlus()
        XCTAssertFalse(model.aVenir.aSuivre)
        XCTAssertFalse(model.aVenir.peutChargerPlus, "lecture incomplète : plus de « Charger plus »")
        XCTAssertEqual(port.appels, ["aVenir 0", "aVenir 0", "aVenir 1", "aVenir 2"])
    }

    func testChargerPlusRelitLesPagesCumuleesEtRemplaceLaListe() async throws {
        let port = ScriptedMesMissions(aVenir: [.page(page(["m-1", "m-2"], aSuivre: true)),
                                                .page(page(["m-1", "m-2", "m-3"], page: 1, aSuivre: false))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertTrue(model.aVenir.aSuivre)
        await model.chargerPlus()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1", "m-2", "m-3"], "pages 0 et 1 relues ensemble : la liste est remplacée")
        XCTAssertEqual(model.aVenir.page, 1)
        XCTAssertFalse(model.aVenir.aSuivre)
        XCTAssertFalse(model.aVenir.chargementSuite)
        await model.chargerPlus()
        XCTAssertEqual(port.appels, ["aVenir 0", "aVenir 1"], "aucune lecture après une lecture incomplète")
    }

    /// Effet (a) de la revue B8 de T5 : une mission terminée entre deux lectures (`fin_le` dépassée)
    /// sortait de la requête et décalait l'offset d'une page disjointe, si bien que la suivante était
    /// sautée. En lecture cumulative, la relecture rend toutes les missions restantes.
    func testMissionTermineeEntreDeuxLecturesAucuneMissionSautee() async throws {
        let premiere = (1...3).map { "m-\($0)" }
        let relue = (2...5).map { "m-\($0)" } // m-1 terminée entre-temps, m-4 et m-5 au-delà de la première page
        let port = ScriptedMesMissions(aVenir: [.page(page(premiere, aSuivre: true)), .page(page(relue, page: 1))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        await model.chargerPlus()
        XCTAssertEqual(model.aVenir.elements.map(\.id), relue, "m-4 n'est pas sautée et m-1, terminée, disparaît")
    }

    /// Effet (c) de la revue B8 de T5 : tirer pour actualiser (et chaque apparition de l'écran) relit les
    /// pages déjà chargées, comme le web qui garde `page` (`refreshTick`) ; seule une sélection d'onglet
    /// revient à la première page (`setPage(0)`, l.248).
    func testRelectureGardeLesPagesChargeesEtSelectionRevientALaPremiere() async throws {
        let port = ScriptedMesMissions(aVenir: [.page(page(["m-1"], aSuivre: true)),
                                                .page(page(["m-1", "m-2"], page: 1, aSuivre: true)),
                                                .page(page(["m-1", "m-2"], page: 1, aSuivre: true)),
                                                .page(page(["m-1"], aSuivre: true))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        await model.chargerPlus()
        await model.charger()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1", "m-2"], "la relecture ne ramène pas à la première page")
        XCTAssertEqual(model.aVenir.page, 1)
        XCTAssertNil(model.aVenir.erreurRafraichissement)
        await model.selectionner(.aVenir)
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1"])
        XCTAssertEqual(model.aVenir.page, 0)
        XCTAssertEqual(port.appels, ["aVenir 0", "aVenir 1", "aVenir 1", "aVenir 0"])
    }

    func testDoublonDUneRelectureEcarteLaPremiereOccurrenceGardee() async throws {
        let port = ScriptedMesMissions(aVenir: [.page(page(["m-1", "m-2", "m-1"]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1", "m-2"], "identifiants uniques pour la liste (`ForEach`)")
    }

    func testChargerPlusEnEchecConserveLaListeEtNExistePasPourLesCandidatures() async throws {
        let port = ScriptedMesMissions(candidatures: [.candidatures([])],
                                       aVenir: [.page(page(["m-1"], aSuivre: true)), .echec(JoleneError(.network, "Connexion impossible.")),
                                                .page(page(["m-1", "m-2"], page: 1))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.chargerPlus()
        XCTAssertEqual(port.appels, [], "rien avant une première page lue")
        await model.charger()
        await model.chargerPlus()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1"])
        XCTAssertEqual(model.aVenir.erreurSuite, "Connexion impossible.")
        XCTAssertNil(model.aVenir.erreurRafraichissement, "l'échec d'une page suivante n'est pas une relecture échouée")
        XCTAssertTrue(model.aVenir.aSuivre, "« Charger plus » reste proposé")
        await model.chargerPlus()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1", "m-2"])
        XCTAssertNil(model.aVenir.erreurSuite)
        await model.selectionner(.candidatures)
        await model.chargerPlus()
        XCTAssertEqual(port.appels, ["aVenir 0", "aVenir 1", "aVenir 1", "candidatures"], "aucune page suivante pour les candidatures")
    }

    func testFinancesDesPasseesRemplaceesParChaqueLecture() async throws {
        let port = ScriptedMesMissions(passees: [.page(page(["m-1"], aSuivre: true, finances: ["m-1": finance("m-1")])),
                                                 .page(page(["m-1", "m-2"], page: 1, finances: ["m-1": finance("m-1"), "m-2": finance("m-2")])),
                                                 .page(page(["m-1"], finances: ["m-1": finance("m-1")]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot, onglet: .passees)
        await model.charger()
        await model.chargerPlus()
        XCTAssertEqual(Set(model.finances.keys), ["m-1", "m-2"], "colonnes des pages relues ensemble")
        await model.selectionner(.passees)
        XCTAssertEqual(Set(model.finances.keys), ["m-1"], "première page relue : colonnes de la lecture seulement")
        XCTAssertEqual(model.passees.elements.map(\.id), ["m-1"])
    }

    // MARK: - Identité, chevauchement, délai

    func testEpochPerimeAucunAppel() async throws {
        let port = ScriptedMesMissions(aVenir: [.page(page(["m-1"]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        _ = await controller.signOut()
        await model.charger()
        XCTAssertEqual(model.aVenir.contenu, .chargement, "epoch périmé : aucun résultat publié")
        XCTAssertEqual(port.appels, [], "aucune lecture sans gateways valides")
    }

    func testReponseApresUnChangementDIdentiteIgnoree() async throws {
        let entree = Gate()
        let sortie = Gate()
        let port = ScriptedMesMissions(aVenir: [.retenue(page(["ancienne"]), entree: entree, sortie: sortie)])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        let lecture = Task { await model.charger() }
        await entree.wait()
        _ = await controller.signOut()
        await sortie.open()
        await lecture.value
        XCTAssertEqual(model.aVenir.contenu, .chargement, "réponse de l'identité précédente abandonnée")
    }

    func testLectureDepasseeParUnePlusRecenteIgnoree() async throws {
        let entree = Gate()
        let sortie = Gate()
        let port = ScriptedMesMissions(aVenir: [.retenue(page(["lente"]), entree: entree, sortie: sortie), .page(page(["recente"]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        let lente = Task { await model.charger() }
        await entree.wait()
        await model.charger()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["recente"])
        await sortie.open()
        await lente.value
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["recente"], "la réponse plus lente d'une lecture dépassée est ignorée")
        XCTAssertFalse(model.aVenir.rafraichissement)
    }

    func testLectureBorneeAuDelaiDeResolution() async throws {
        let jamais = Gate()
        let port = ScriptedMesMissions(aVenir: [.muet(jamais)])
        let (controller, snapshot) = try await pret(port, timeout: 0.2)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.aVenir.contenu, .echec(SessionController.timeoutMessage), "un port muet rend l'erreur générique de délai")
        await jamais.open()
    }
}
