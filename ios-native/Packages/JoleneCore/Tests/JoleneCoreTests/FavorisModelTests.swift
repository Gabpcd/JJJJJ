import XCTest
@testable import JoleneCore

/// Modèle des favoris (lot 1, T4b), partagé par l'étoile d'Explorer, l'étoile du détail et l'écran
/// « Mes favoris » (`MesFavorisSoignant.tsx`, `BoutonSauvegarderMission.tsx`). Règles prouvées :
/// lecture des deux listes bornée à `resolutionTimeout` ; une mutation n'est annoncée qu'après une
/// relecture qui la confirme (PRINCIPES §3) ; un délai dépassé ou une coupure impose une relecture,
/// jamais un renvoi ; un second appui pendant l'appel est ignoré ; session expirée signalée ;
/// annulation jamais présentée comme une erreur ; réponse d'un epoch périmé ignorée.
@MainActor
final class FavorisModelTests: XCTestCase {
    private struct AuthPrete: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? {
            AuthenticatedUser(id: "u-1", email: "u-1@example.invalid", emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                              appMetadataRole: "SOIGNANT")
        }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw JoleneError(.invalidCredentials, "refusé") }
        func signOut() async throws {}
    }

    private let maintenant = DemoWorld.fixedNow

    private func pret(_ scenario: FavorisScenario, timeout: TimeInterval = SessionController.defaultResolutionTimeout) async throws
        -> (FavorisModel, SessionController) {
        var gateways = Lot1Fakes.gateways(clock: FixedClock(maintenant))
        gateways.auth = AuthPrete()
        gateways.missions = FakeMissions(profile: SoignantProfile(id: "u-1", profession: "IDE"), profileError: nil, gate: nil, log: CallLog())
        gateways.favoris = FakeFavoris(scenario: scenario)
        let controller = SessionController(gateways: gateways, resolutionTimeout: timeout)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return (FavorisModel(controller: controller, snapshot: snapshot), controller)
    }

    private func ligne(_ missionId: String, statut: String = "OUVERTE", debut: String = "2026-11-10T07:00:00.000Z") -> MissionSauvegardee {
        MissionSauvegardee(id: "s-\(missionId)", missionId: missionId, creeLe: "2026-11-01T10:00:00+00:00",
                           mission: MissionSauvegardee.Apercu(id: missionId, intitule: "Mission \(missionId)", debutLe: debut,
                                                              finLe: nil, dureeHeures: 8, nbCreneaux: 1, statut: statut))
    }

    private func etablissement(_ id: String) -> EtablissementFavori {
        EtablissementFavori(id: id, nom: "Établissement \(id)", ville: "Lyon", logoUrl: nil, typeEtablissement: "CLINIQUE",
                            nbMissionsOuvertes: 2, creeLe: "2026-10-01T09:00:00+00:00")
    }

    // MARK: - Lecture

    func testChargerLitLesDeuxListesEtDeriveLesMissionsAffichees() async throws {
        let scenario = FavorisScenario([
            "lire": [.missions([ligne("m-1"), ligne("m-passee", debut: "2026-10-01T07:00:00.000Z"), ligne("m-assignee", statut: "ASSIGNEE")])],
            "etablissements": [.etablissements([etablissement("e-1")])],
        ])
        let (model, _) = try await pret(scenario)
        XCTAssertEqual(model.missions, .chargement)
        XCTAssertEqual(model.etablissements, .chargement)

        await model.charger()

        XCTAssertEqual(model.missions.elements.map(\.missionId), ["m-1", "m-passee", "m-assignee"])
        XCTAssertEqual(model.missionsAffichees.map(\.missionId), ["m-1"], "filtre du web sur l'horloge des gateways")
        XCTAssertEqual(model.etablissements, .prete([etablissement("e-1")]))
        XCTAssertTrue(model.estSauvegardee("m-1"))
        XCTAssertTrue(model.estSauvegardee("m-assignee"), "l'étoile reflète la ligne, même hors de l'écran Favoris")
        XCTAssertFalse(model.estSauvegardee("m-2"))
        XCTAssertEqual(model.etablissement(id: "e-1")?.nom, "Établissement e-1")
        XCTAssertNil(model.erreurAction)
        XCTAssertFalse(model.sessionExpired)
    }

    func testEchecDeLaPremiereLectureParSectionPuisReprise() async throws {
        let scenario = FavorisScenario([
            "lire": [.echec(JoleneError(.network, "Connexion impossible.")), .missions([ligne("m-1")])],
            "etablissements": [.etablissements([etablissement("e-1")])],
        ])
        let (model, _) = try await pret(scenario)
        await model.charger()
        XCTAssertEqual(model.missions, .echec("Connexion impossible."))
        XCTAssertEqual(model.etablissements, .prete([etablissement("e-1")]), "une section en échec n'empêche pas l'autre")
        XCTAssertNil(model.erreurAction, "l'échec d'une première lecture est porté par sa section")

        await model.chargerMissions()
        XCTAssertEqual(model.missions.elements.map(\.missionId), ["m-1"])
    }

    func testEchecDUneRelectureConserveLaListeEtLeSignale() async throws {
        let scenario = FavorisScenario(["lire": [.missions([ligne("m-1")]), .echec(JoleneError(.network, "Connexion impossible."))]])
        let (model, _) = try await pret(scenario)
        await model.chargerMissions()
        await model.chargerMissions()
        XCTAssertEqual(model.missions.elements.map(\.missionId), ["m-1"], "une liste affichée n'est jamais effacée par un échec")
        XCTAssertEqual(model.erreurAction, "Connexion impossible.")
        XCTAssertEqual(model.tentatives, 1)
    }

    func testErreurInattendueDonneLeMessageGenerique() async throws {
        struct Inattendue: Error {}
        let scenario = FavorisScenario()
        let (model, _) = try await pret(scenario)
        scenario.ajouter("etablissements", .echec(JoleneError(.unknown, "Établissements indisponibles.")))
        await model.chargerEtablissements()
        XCTAssertEqual(model.etablissements, .echec("Établissements indisponibles."))
        XCTAssertEqual(FavorisModel.message(pour: Inattendue(), repli: "repli")?.message, "repli")
        XCTAssertNil(FavorisModel.message(pour: CancellationError(), repli: "repli"))
        XCTAssertNil(FavorisModel.message(pour: JoleneError(.cancelled, "Chargement annulé."), repli: "repli"))
        XCTAssertEqual(FavorisModel.message(pour: JoleneError(.unauthorized, "Session"), repli: "repli")?.sessionExpiree, true)
    }

    func testSessionExpireeALaLecture() async throws {
        let scenario = FavorisScenario(["lire": [.echec(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))]])
        let (model, _) = try await pret(scenario)
        await model.chargerMissions()
        XCTAssertTrue(model.sessionExpired)
        XCTAssertEqual(model.missions, .echec("Votre session a expiré. Reconnectez-vous."))
    }

    func testLectureBorneeAuDelaiDeLaSession() async throws {
        let scenario = FavorisScenario(["lire": [.silence]])
        let (model, _) = try await pret(scenario, timeout: 0.05)
        await model.chargerMissions()
        XCTAssertEqual(model.missions, .echec(SessionController.timeoutMessage), "jamais un chargement sans issue")
    }

    func testAnnulationDeLaLectureNEstPasUneErreur() async throws {
        let scenario = FavorisScenario(["lire": [.annulation]])
        let (model, _) = try await pret(scenario)
        await model.chargerMissions()
        XCTAssertEqual(model.missions, .chargement, "une annulation laisse l'état en attente : la vue relancera")
        XCTAssertNil(model.erreurAction)
    }

    func testChargerSiNecessaireNeRelitPasUneListeDejaLue() async throws {
        let scenario = FavorisScenario(["lire": [.missions([ligne("m-1")])]])
        let (model, _) = try await pret(scenario)
        await model.chargerMissionsSiNecessaire()
        await model.chargerMissionsSiNecessaire()
        XCTAssertEqual(scenario.nombre("lire"), 1)
        XCTAssertEqual(scenario.nombre("etablissements"), 0, "Explorer ne lit que les missions sauvegardées")
    }

    func testReponseDUnEpochPerimeIgnoree() async throws {
        let barriere = Gate()
        let scenario = FavorisScenario(["lire": [.apres(barriere, .missions([ligne("m-1")]))]])
        let (model, controller) = try await pret(scenario)
        let lecture = Task { await model.chargerMissions() }
        await waitUntil { scenario.nombre("lire") == 1 }
        _ = await controller.signOut()
        await barriere.open()
        await lecture.value
        XCTAssertEqual(model.missions, .chargement, "la liste d'une identité retirée n'est jamais publiée")
        await model.basculer(missionId: "m-2")
        XCTAssertEqual(scenario.nombre("sauvegarder"), 0, "aucun appel pour un epoch périmé")
    }

    // MARK: - Missions : sauvegarde et retrait

    func testSauvegarderRelitPuisAllumeLEtoile() async throws {
        let scenario = FavorisScenario(["lire": [.missions([])], "sauvegarder": [.missions([ligne("m-1")])]])
        let (model, _) = try await pret(scenario)
        await model.chargerMissions()
        XCTAssertFalse(model.estSauvegardee("m-1"))

        await model.basculer(missionId: "m-1")

        XCTAssertEqual(scenario.appels, ["lire", "sauvegarder(m-1)"])
        XCTAssertTrue(model.estSauvegardee("m-1"), "liste relue par le port")
        XCTAssertEqual(model.missionsAffichees.map(\.missionId), ["m-1"])
        XCTAssertNil(model.erreurAction)
        XCTAssertFalse(model.enCours(missionId: "m-1"))
    }

    func testBasculerUneMissionSauvegardeeLaRetire() async throws {
        let scenario = FavorisScenario(["lire": [.missions([ligne("m-1"), ligne("m-2")])], "retirer": [.missions([ligne("m-2")])]])
        let (model, _) = try await pret(scenario)
        await model.chargerMissions()
        await model.basculer(missionId: "m-1")
        XCTAssertEqual(scenario.appels.last, "retirer(m-1)")
        XCTAssertFalse(model.estSauvegardee("m-1"))
        XCTAssertTrue(model.estSauvegardee("m-2"))

        scenario.ajouter("retirer", .missions([]))
        await model.retirerMission("m-2")
        XCTAssertEqual(scenario.appels.last, "retirer(m-2)")
        XCTAssertEqual(model.missions, .prete([]))
        XCTAssertTrue(model.missionsAffichees.isEmpty)
    }

    func testSansLectureLEtoileSauvegardeEtLaRelectureFaitFoi() async throws {
        // Liste pas encore lue (Explorer en cours de chargement) : l'étoile éteinte sauvegarde ; si la
        // mission l'était déjà (conflit UNIQUE côté serveur), la relecture le dit, sans erreur.
        let scenario = FavorisScenario(["sauvegarder": [.missions([ligne("m-1")])]])
        let (model, _) = try await pret(scenario)
        await model.basculer(missionId: "m-1")
        XCTAssertEqual(scenario.appels, ["sauvegarder(m-1)"])
        XCTAssertTrue(model.estSauvegardee("m-1"))
    }

    func testRelectureQuiNeConfirmePasLaSauvegardeEstUneErreur() async throws {
        let scenario = FavorisScenario(["lire": [.missions([])], "sauvegarder": [.missions([ligne("m-2")])]])
        let (model, _) = try await pret(scenario)
        await model.chargerMissions()
        await model.basculer(missionId: "m-1")
        XCTAssertFalse(model.estSauvegardee("m-1"), "aucun succès fabriqué : l'étoile suit la relecture")
        XCTAssertEqual(model.erreurAction, FavorisModel.sauvegardeNonConfirmee)
        XCTAssertEqual(model.missions.elements.map(\.missionId), ["m-2"], "la relecture reste la vérité affichée")
        XCTAssertEqual(model.tentatives, 1)
    }

    func testRelectureQuiNeConfirmePasLeRetraitEstUneErreur() async throws {
        let scenario = FavorisScenario(["lire": [.missions([ligne("m-1")])], "retirer": [.missions([ligne("m-1")])]])
        let (model, _) = try await pret(scenario)
        await model.chargerMissions()
        await model.retirerMission("m-1")
        XCTAssertTrue(model.estSauvegardee("m-1"))
        XCTAssertEqual(model.erreurAction, FavorisModel.retraitNonConfirme)
    }

    func testDelaiDepasseSurUneMutationRelitSansRenvoyer() async throws {
        let scenario = FavorisScenario(["lire": [.missions([]), .missions([ligne("m-1")])], "sauvegarder": [.silence]])
        let (model, _) = try await pret(scenario, timeout: 0.05)
        await model.chargerMissions()

        await model.basculer(missionId: "m-1")

        XCTAssertEqual(scenario.nombre("sauvegarder"), 1, "jamais de renvoi automatique")
        XCTAssertEqual(scenario.appels, ["lire", "sauvegarder(m-1)", "lire"], "relecture après le délai dépassé")
        XCTAssertEqual(model.erreurAction, SessionController.timeoutMessage)
        XCTAssertTrue(model.estSauvegardee("m-1"), "le serveur avait agi : la relecture le montre")
    }

    func testCoupureSurUneMutationRelitEtGardeLeMessageDeLaMutation() async throws {
        let scenario = FavorisScenario([
            "lire": [.missions([ligne("m-1")]), .echec(JoleneError(.network, "Relecture impossible."))],
            "retirer": [.echec(JoleneError(.network, "Connexion impossible."))],
        ])
        let (model, _) = try await pret(scenario)
        await model.chargerMissions()
        await model.retirerMission("m-1")
        XCTAssertEqual(scenario.appels, ["lire", "retirer(m-1)", "lire"])
        XCTAssertEqual(model.erreurAction, "Connexion impossible.", "le message de l'action reste affiché")
        XCTAssertTrue(model.estSauvegardee("m-1"), "liste précédente conservée faute de relecture")
    }

    func testSessionExpireeSurUneMutationSansRelecture() async throws {
        let scenario = FavorisScenario([
            "lire": [.missions([])],
            "sauvegarder": [.echec(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))],
        ])
        let (model, _) = try await pret(scenario)
        await model.chargerMissions()
        await model.basculer(missionId: "m-1")
        XCTAssertTrue(model.sessionExpired)
        XCTAssertEqual(model.erreurAction, "Votre session a expiré. Reconnectez-vous.")
        XCTAssertEqual(scenario.appels, ["lire", "sauvegarder(m-1)"], "revalider la session plutôt que relire")
    }

    func testSecondAppuiPendantLAppelEstIgnore() async throws {
        let barriere = Gate()
        let scenario = FavorisScenario(["sauvegarder": [.apres(barriere, .missions([ligne("m-1")]))]])
        let (model, _) = try await pret(scenario)
        let premier = Task { await model.basculer(missionId: "m-1") }
        await waitUntil { scenario.nombre("sauvegarder") == 1 }
        XCTAssertTrue(model.enCours(missionId: "m-1"), "étoile désactivée pendant l'appel")
        await model.basculer(missionId: "m-1")
        await barriere.open()
        await premier.value
        XCTAssertEqual(scenario.nombre("sauvegarder"), 1)
        XCTAssertEqual(scenario.nombre("retirer"), 0)
        XCTAssertFalse(model.enCours(missionId: "m-1"))
        XCTAssertTrue(model.estSauvegardee("m-1"))
    }

    func testUneLectureLanceeApresLaMutationGagne() async throws {
        // Deux relectures qui se chevauchent : seule la dernière demandée publie.
        let barriere = Gate()
        let scenario = FavorisScenario([
            "sauvegarder": [.apres(barriere, .missions([ligne("m-1")]))],
            "lire": [.missions([ligne("m-1"), ligne("m-2")])],
        ])
        let (model, _) = try await pret(scenario)
        let mutation = Task { await model.basculer(missionId: "m-1") }
        await waitUntil { scenario.nombre("sauvegarder") == 1 }
        await model.chargerMissions()
        await barriere.open()
        await mutation.value
        XCTAssertEqual(model.missions.elements.map(\.missionId), ["m-1", "m-2"], "la relecture plus récente n'est pas écrasée")
        XCTAssertNil(model.erreurAction, "la mutation reste confirmée par sa propre relecture")
    }

    func testEffacerErreur() async throws {
        let scenario = FavorisScenario(["sauvegarder": [.echec(JoleneError(.unknown, "Refus."))]])
        let (model, _) = try await pret(scenario)
        await model.basculer(missionId: "m-1")
        XCTAssertEqual(model.erreurAction, "Refus.")
        model.effacerErreur()
        XCTAssertNil(model.erreurAction)
    }

    // MARK: - Établissements : retrait seulement (décision 8)

    func testRetraitDUnEtablissementConfirmeParLaRelecture() async throws {
        let scenario = FavorisScenario([
            "etablissements": [.etablissements([etablissement("e-1"), etablissement("e-2")])],
            "basculer": [.etablissements([etablissement("e-2")])],
        ])
        let (model, _) = try await pret(scenario)
        await model.chargerEtablissements()
        let retire = await model.retirerEtablissement("e-1")
        XCTAssertTrue(retire)
        XCTAssertEqual(scenario.appels, ["etablissements", "basculer(e-1,false)"], "jamais p_actif = true")
        XCTAssertEqual(model.etablissements, .prete([etablissement("e-2")]))
        XCTAssertNil(model.erreurAction)
        XCTAssertFalse(model.retraitEnCours(etablissementId: "e-1"))
    }

    func testRetraitNonConfirmeOuRefuseResteOuvert() async throws {
        let scenario = FavorisScenario([
            "etablissements": [.etablissements([etablissement("e-1")]), .etablissements([])],
            "basculer": [.etablissements([etablissement("e-1")]), .echec(JoleneError(.unknown, "Établissement introuvable"))],
        ])
        let (model, _) = try await pret(scenario)
        await model.chargerEtablissements()

        let nonConfirme = await model.retirerEtablissement("e-1")
        XCTAssertFalse(nonConfirme)
        XCTAssertEqual(model.erreurAction, FavorisModel.retraitNonConfirme)

        let refuse = await model.retirerEtablissement("e-1")
        XCTAssertFalse(refuse)
        XCTAssertEqual(model.erreurAction, "Établissement introuvable", "message serveur verbatim")
        XCTAssertEqual(scenario.appels, ["etablissements", "basculer(e-1,false)", "basculer(e-1,false)", "etablissements"],
                       "après un refus, la liste est relue (jamais de renvoi)")
        XCTAssertEqual(model.etablissements, .prete([]))
        XCTAssertEqual(model.tentatives, 2)
    }

    func testRetraitDEtablissementPendantLAppelIgnore() async throws {
        let barriere = Gate()
        let scenario = FavorisScenario(["basculer": [.apres(barriere, .etablissements([]))]])
        let (model, _) = try await pret(scenario)
        let premier = Task { await model.retirerEtablissement("e-1") }
        await waitUntil { scenario.nombre("basculer") == 1 }
        XCTAssertTrue(model.retraitEnCours(etablissementId: "e-1"))
        let second = await model.retirerEtablissement("e-1")
        XCTAssertFalse(second)
        await barriere.open()
        let resultat = await premier.value
        XCTAssertTrue(resultat)
        XCTAssertEqual(scenario.nombre("basculer"), 1)
    }
}
