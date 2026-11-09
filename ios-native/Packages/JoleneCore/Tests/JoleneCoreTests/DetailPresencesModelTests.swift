import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurDetail = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                  emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                  appMetadataRole: "SOIGNANT")

/// Modèle du détail des présences (lot 2, T5a ; parité `DetailPresencesMission.tsx`) : deux lectures en parallèle
/// (`detail`, `ficheDetail`), mission illisible → « Mission introuvable », synthèse serveur en refus → carte masquée et
/// reste rendu, échec → message du port puis « Réessayer », annulation jamais affichée, session expirée ; relance de
/// l'établissement : message serveur verbatim, repli du web, un envoi à la fois.
@MainActor
final class DetailPresencesModelTests: XCTestCase {
    private struct ModelError: Error {}

    /// Port de pointage scripté : `detail`, `ficheDetail` et `relancerValidation` répondent ; le reste refuse.
    private final class PortDetail: PointagePort, @unchecked Sendable {
        private let lock = NSLock()
        var detailReponse: Result<DetailPresences, Error>
        var ficheReponse: Result<FicheDetailPresences, Error>
        var relances: [Result<IssueRelance, Error>] = []
        private(set) var appelsRelance = 0
        private(set) var appelsDetail = 0
        var porteRelance: (entree: Gate, sortie: Gate)?

        init(detail: Result<DetailPresences, Error>, fiche: Result<FicheDetailPresences, Error>) {
            detailReponse = detail; ficheReponse = fiche
        }

        private var refus: JoleneError { JoleneError(.contract, "jamais appelé par le détail des présences") }

        func detail(missionId: String, context: MissionReadContext) async throws -> DetailPresences {
            let r = lock.withLock { () -> Result<DetailPresences, Error> in appelsDetail += 1; return detailReponse }
            return try r.get()
        }
        func ficheDetail(missionId: String, context: MissionReadContext) async throws -> FicheDetailPresences {
            let r = lock.withLock { ficheReponse }
            return try r.get()
        }
        func relancerValidation(missionId: String, context: MissionReadContext) async throws -> IssueRelance {
            let (r, porte) = lock.withLock { () -> (Result<IssueRelance, Error>, (entree: Gate, sortie: Gate)?) in
                appelsRelance += 1
                return (relances.isEmpty ? .success(.envoyee(message: nil)) : relances.removeFirst(), porteRelance)
            }
            if let porte {
                await porte.entree.open()
                await porte.sortie.wait()
            }
            return try r.get()
        }
        func presences(context: MissionReadContext) async throws -> InstantanePresences { throw refus }
        func etat(missionId: String, context: MissionReadContext) async throws -> EtatPointage { throw refus }
        func consentementGps(context: MissionReadContext) async throws -> Bool? { throw refus }
        func enregistrerConsentementGps(_ accepte: Bool, context: MissionReadContext) async throws -> Bool { throw refus }
        func scanner(code: String, metadonnees: MetadonneesScan, recu: RecuScan,
                     context: MissionReadContext) async throws -> IssueScan { throw refus }
        func reconcilier(recu: RecuScan, context: MissionReadContext) async throws -> IssueScan { throw refus }
    }

    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurDetail }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw ModelError() }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    private func pret(_ port: PortDetail) async throws -> (SessionController, SessionSnapshot) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.pointage = port
        let controller = SessionController(gateways: gateways)
        let state = await controller.start()
        return (controller, try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)"))
    }

    private let mission = MissionPresenceLue(id: "m-1", intitule: "Mission de test", debutLe: "2026-10-30T07:00:00Z",
                                             finLe: "2026-10-30T15:00:00Z", dureeHeures: 8, statut: "TERMINEE", etablissementId: "e-1")
    private let creneaux = [
        MissionSlot(id: "prevu", missionId: "m-1", debut: "2026-10-30T07:00:00Z", fin: "2026-10-30T15:00:00Z", estPause: false,
                    typeCreneau: "PREVISIONNEL"),
        MissionSlot(id: "e-1", missionId: "m-1", debut: "2026-10-30T07:00:00Z", fin: "2026-10-30T15:00:00Z", estPause: false,
                    typeCreneau: "EFFECTIF"),
    ]

    private func port(resume: ResumePresencesServeur? = ResumePresencesServeur(pointageEffectue: true),
                      presence: PresenceControlee? = PresenceControlee(id: "pr-1", valideParEtablissement: false)) -> PortDetail {
        PortDetail(detail: .success(DetailPresences(missionId: "m-1", creneaux: creneaux, resume: resume)),
                   fiche: .success(FicheDetailPresences(mission: mission, presence: presence)))
    }

    // MARK: - Chargement

    func testChargementConstruitLaPresentationSurLHorlogeDesGateways() async throws {
        let p = port()
        let (controller, snapshot) = try await pret(p)
        let model = DetailPresencesModel(missionId: "m-1", controller: controller, snapshot: snapshot)
        XCTAssertEqual(model.etat, .chargement)
        await model.charger()
        let attendue = PresentationDetailPresences.construire(mission: mission, creneaux: creneaux,
                                                              resume: ResumePresencesServeur(pointageEffectue: true),
                                                              presence: PresenceControlee(id: "pr-1", valideParEtablissement: false),
                                                              maintenant: DemoWorld.fixedNow)
        XCTAssertEqual(model.etat, .pret(attendue))
        XCTAssertTrue(model.presentation?.relanceProposee ?? false)
        XCTAssertFalse(model.sessionExpired)
    }

    func testSyntheseServeurEnRefusMasqueLaCarteSeulement() async throws {
        let (controller, snapshot) = try await pret(port(resume: nil))
        let model = DetailPresencesModel(missionId: "m-1", controller: controller, snapshot: snapshot)
        await model.charger()
        let presentation = try XCTUnwrap(model.presentation)
        XCTAssertNil(presentation.synthese, "`fn_presences_detail_mission` `{error}` : carte masquée")
        XCTAssertEqual(presentation.jours.count, 1, "le reste de l'écran est rendu")
    }

    func testMissionIllisibleEstIntrouvable() async throws {
        let p = PortDetail(detail: .success(DetailPresences(missionId: "m-1")), fiche: .success(FicheDetailPresences(mission: nil, presence: nil)))
        let (controller, snapshot) = try await pret(p)
        let model = DetailPresencesModel(missionId: "m-1", controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.etat, .introuvable)
    }

    func testEchecPuisReessaiEtSessionExpiree() async throws {
        let p = port()
        p.ficheReponse = .failure(JoleneError(.network, "Le service ne répond pas."))
        let (controller, snapshot) = try await pret(p)
        let model = DetailPresencesModel(missionId: "m-1", controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.etat, .echec("Le service ne répond pas."))
        XCTAssertFalse(model.sessionExpired)

        p.ficheReponse = .success(FicheDetailPresences(mission: mission, presence: nil))
        await model.charger()
        XCTAssertNotNil(model.presentation, "« Réessayer » relit le détail")

        p.detailReponse = .failure(JoleneError(.unauthorized, "Votre session a expiré."))
        await model.charger()
        XCTAssertEqual(model.etat, .echec("Votre session a expiré."), "échec de relecture : message du port")
        XCTAssertTrue(model.sessionExpired)
    }

    func testAnnulationJamaisAfficheeEnErreur() async throws {
        let p = port()
        p.detailReponse = .failure(CancellationError())
        let (controller, snapshot) = try await pret(p)
        let model = DetailPresencesModel(missionId: "m-1", controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.etat, .chargement, "annulation : l'état reste en chargement")
        p.detailReponse = .failure(JoleneError(.cancelled, "Annulé"))
        await model.charger()
        XCTAssertEqual(model.etat, .chargement)
    }

    func testEpochPerimeAbandonneLaReponse() async throws {
        let p = port()
        let (controller, snapshot) = try await pret(p)
        let model = DetailPresencesModel(missionId: "m-1", controller: controller, snapshot: snapshot)
        _ = await controller.signOut()
        await model.charger()
        XCTAssertEqual(model.etat, .chargement, "nouvel epoch : aucune publication")
        XCTAssertEqual(p.appelsDetail, 0, "aucune lecture sans gateways valides")
    }

    // MARK: - Relance

    func testRelanceMessageServeurVerbatimPuisRefus() async throws {
        let p = port()
        p.relances = [.success(.envoyee(message: "Établissement relancé. Il a été notifié de valider tes présences.")),
                      .success(.refusee(message: "Tu as déjà relancé cet établissement aujourd'hui. Il a été notifié.")),
                      .success(.envoyee(message: nil))]
        let (controller, snapshot) = try await pret(p)
        let model = DetailPresencesModel(missionId: "m-1", controller: controller, snapshot: snapshot)
        await model.charger()
        await model.relancer()
        XCTAssertEqual(model.retourRelance, .init(succes: true, message: "Établissement relancé. Il a été notifié de valider tes présences."))
        await model.relancer()
        XCTAssertEqual(model.retourRelance, .init(succes: false, message: "Tu as déjà relancé cet établissement aujourd'hui. Il a été notifié."))
        await model.relancer()
        XCTAssertEqual(model.retourRelance, .init(succes: true, message: "Établissement relancé."), "repli du web (l.122)")
        XCTAssertEqual(p.appelsRelance, 3)
    }

    func testRelanceErreurDeTransportEtSessionExpiree() async throws {
        let p = port()
        p.relances = [.failure(JoleneError(.network, "Le service ne répond pas.")),
                      .failure(JoleneError(.unauthorized, "Votre session a expiré."))]
        let (controller, snapshot) = try await pret(p)
        let model = DetailPresencesModel(missionId: "m-1", controller: controller, snapshot: snapshot)
        await model.charger()
        await model.relancer()
        XCTAssertEqual(model.retourRelance, .init(succes: false, message: "Le service ne répond pas."), "message de l'erreur (l.120)")
        XCTAssertFalse(model.sessionExpired)
        await model.relancer()
        XCTAssertTrue(model.sessionExpired)
    }

    func testRelanceUnSeulEnvoiALaFoisEtSeulementSiProposee() async throws {
        let p = port()
        let entree = Gate(), sortie = Gate()
        p.porteRelance = (entree, sortie)
        let (controller, snapshot) = try await pret(p)
        let model = DetailPresencesModel(missionId: "m-1", controller: controller, snapshot: snapshot)
        await model.charger()
        let premier = Task { await model.relancer() }
        await entree.wait()
        XCTAssertTrue(model.relanceEnCours)
        await model.relancer()
        await sortie.open()
        await premier.value
        XCTAssertEqual(p.appelsRelance, 1, "double tap : un seul appel")
        XCTAssertFalse(model.relanceEnCours)

        let validee = port(presence: PresenceControlee(id: "pr-1", valideParEtablissement: true))
        let (controller2, snapshot2) = try await pret(validee)
        let autre = DetailPresencesModel(missionId: "m-1", controller: controller2, snapshot: snapshot2)
        await autre.charger()
        await autre.relancer()
        XCTAssertEqual(validee.appelsRelance, 0, "présence validée : aucune relance")
    }
}
