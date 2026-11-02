import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurAccueil = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                   emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                   appMetadataRole: "SOIGNANT")

/// Modèle de l'onglet Accueil (lot 1, T3) : mêmes règles que `MissionsListModel` (annulation
/// jamais affichée en erreur, rafraîchissement sans démontage, session expirée, epoch périmé
/// ignoré), plus la borne `resolutionTimeout` (décision 14), transmise au port comme seule source
/// du délai de l'écran, la relecture à l'apparition au-delà de 60 s (`DashboardSoignant.tsx` :
/// `staleTime: 60_000`), des chargements sérialisés (seul le plus récent publie) et « Vérifier ma
/// session », qui relit le tableau quand la session reste valide (revue B8 de T3, 2e passe).
@MainActor
final class AccueilModelTests: XCTestCase {
    private struct ModelError: Error {}

    /// Port scripté : chaque appel consomme une étape ; `entree` est ouverte dès l'appel, `retenue`
    /// (si présente) retient la réponse jusqu'à son ouverture par le test. Une étape `.retenue` a ses
    /// propres barrières : deux chargements peuvent alors se chevaucher et répondre dans l'ordre
    /// choisi par le test. `delais` journalise le délai de l'écran reçu à chaque appel.
    private final class ScriptedDashboard: DashboardPort, @unchecked Sendable {
        enum Step {
            case snapshot(DashboardSnapshot), failure(Error)
            /// `entree` s'ouvre à l'appel ; la réponse attend l'ouverture de `sortie`.
            case retenue(Result<DashboardSnapshot, Error>, entree: Gate, sortie: Gate)
        }
        private let lock = NSLock()
        private var steps: [Step]
        private var appels = 0
        private var delaisRecus: [TimeInterval] = []
        let entree = Gate()
        var retenue: Gate?

        init(_ steps: [Step], retenue: Gate? = nil) { self.steps = steps; self.retenue = retenue }

        var calls: Int { lock.lock(); defer { lock.unlock() }; return appels }
        var delais: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return delaisRecus }

        private func next(delai: TimeInterval) -> Step {
            lock.lock(); defer { lock.unlock() }
            appels += 1
            delaisRecus.append(delai)
            return steps.isEmpty ? .snapshot(DashboardSnapshot()) : steps.removeFirst()
        }

        func dashboard(context: MissionReadContext, delaiEcran: TimeInterval) async throws -> DashboardSnapshot {
            let step = next(delai: delaiEcran)
            await entree.open()
            if let retenue { await retenue.wait() }
            switch step {
            case let .snapshot(snapshot): return snapshot
            case let .failure(error): throw error
            case let .retenue(issue, entreeEtape, sortie):
                await entreeEtape.open()
                await sortie.wait()
                return try issue.get()
            }
        }
    }

    /// Horloge que le test fait avancer (relecture au-delà de 60 s).
    private final class HorlogeReglable: ClockPort, @unchecked Sendable {
        private let lock = NSLock()
        private var instant: Date
        init(_ instant: Date) { self.instant = instant }
        func now() -> Date { lock.lock(); defer { lock.unlock() }; return instant }
        func avancer(_ secondes: TimeInterval) { lock.lock(); instant += secondes; lock.unlock() }
    }

    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurAccueil }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw ModelError() }
        func signOut() async throws {}
    }

    /// Restauration pilotée par le test (`MutableAuthState`) : `restored = nil` = session fermée.
    private struct AuthPilotee: AuthPort {
        let etat: MutableAuthState
        func restoreSession() async throws -> AuthenticatedUser? {
            if let error = await etat.restoreError { throw error }
            return await etat.restored
        }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw ModelError() }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    private func tableau(_ prenom: String, prochaine: String? = nil) -> DashboardSnapshot {
        var snapshot = DashboardSnapshot(profil: DashboardProfil(prenom: prenom, profession: "IDE", tousDocumentsValides: true, typeExercice: nil))
        if let prochaine {
            let ligne = DashboardMissionLigne(id: prochaine, intitule: "Mission \(prochaine)", service: nil, debutLe: nil, finLe: nil,
                                              statut: "ASSIGNEE", estUrgente: false, tauxHoraireBase: nil, etablissementId: nil, etabNom: nil)
            snapshot.prochaines = [AccueilMission(ligne: ligne, etablissementNom: "Établissement", etablissementVille: nil,
                                                  planning: .indisponible, mission: nil)]
        }
        return snapshot
    }

    private func pret(_ port: ScriptedDashboard, horloge: ClockPort = FixedClock(DemoWorld.fixedNow),
                      timeout: TimeInterval = SessionController.defaultResolutionTimeout,
                      auth: AuthPort = PretAuth()) async throws -> (SessionController, SessionSnapshot) {
        var gateways = Gateways(auth: auth, role: NeutralRole(), missions: PretMissions(), clock: horloge)
        gateways.dashboard = port
        let controller = SessionController(gateways: gateways, resolutionTimeout: timeout)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return (controller, snapshot)
    }

    func testChargementPublieLeTableauEtSonInstant() async throws {
        let port = ScriptedDashboard([.snapshot(tableau("Camille", prochaine: "m-1"))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        XCTAssertEqual(model.state, .loading)
        await model.load()
        XCTAssertEqual(model.tableau?.profil?.prenom, "Camille")
        XCTAssertEqual(model.chargeLe, DemoWorld.fixedNow, "instant de l'horloge des gateways")
        XCTAssertEqual(model.horloge.now(), DemoWorld.fixedNow)
        XCTAssertEqual(model.mission(id: "m-1"), nil, "sans fiche relue, le détail se chargera lui-même")
        XCTAssertFalse(model.sessionExpired)
        XCTAssertEqual(port.calls, 1)
    }

    func testEchecPuisSuccesEtMessageGeneriquePourUneErreurInconnue() async throws {
        let port = ScriptedDashboard([.failure(JoleneError(.network, "Connexion impossible.")), .failure(ModelError()),
                                      .snapshot(tableau("Camille"))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.state, .failed("Connexion impossible."))
        await model.load()
        XCTAssertEqual(model.state, .failed(AccueilModel.genericFailureMessage), "jamais le détail technique d'une erreur inconnue")
        await model.load()
        XCTAssertEqual(model.tableau?.profil?.prenom, "Camille")
    }

    func testRafraichissementConserveLeTableauEnCasDEchecOuDAnnulation() async throws {
        let port = ScriptedDashboard([.snapshot(tableau("A")), .failure(JoleneError(.network, "Connexion impossible.")),
                                      .failure(CancellationError()), .snapshot(tableau("B"))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        await model.load()
        XCTAssertEqual(model.tableau?.profil?.prenom, "A", "le tableau reste à l'écran après un rafraîchissement échoué")
        XCTAssertEqual(model.refreshError, "Connexion impossible.")
        XCTAssertFalse(model.isRefreshing)
        await model.load()
        XCTAssertEqual(model.tableau?.profil?.prenom, "A", "pull-to-refresh interrompu : tableau conservé")
        XCTAssertNil(model.refreshError)
        await model.load()
        XCTAssertEqual(model.tableau?.profil?.prenom, "B", "le succès remplace le tableau")
    }

    func testAnnulationLaisseLEtatEnChargement() async throws {
        let port = ScriptedDashboard([.failure(CancellationError()), .failure(JoleneError(.cancelled, "Chargement annulé."))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.state, .loading)
        await model.load()
        XCTAssertEqual(model.state, .loading, "`.task` relancera le chargement au prochain affichage")
        XCTAssertNil(model.refreshError)
    }

    func testSessionExpireeSignaleePourRevalidation() async throws {
        let port = ScriptedDashboard([.failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertTrue(model.sessionExpired)
        XCTAssertEqual(model.state, .failed("Votre session a expiré. Reconnectez-vous."))
    }

    func testEpochPerimeAucunAppel() async throws {
        let port = ScriptedDashboard([.snapshot(tableau("A"))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        _ = await controller.signOut()
        await model.load()
        XCTAssertEqual(model.state, .loading, "epoch périmé : aucun résultat publié")
        XCTAssertEqual(port.calls, 0, "aucune lecture sans gateways valides")
    }

    func testReponseRecueApresUnChangementDIdentiteIgnoree() async throws {
        let retenue = Gate()
        let port = ScriptedDashboard([.snapshot(tableau("Ancienne identité"))], retenue: retenue)
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        let chargement = Task { await model.load() }
        await port.entree.wait()
        _ = await controller.signOut()
        await retenue.open()
        await chargement.value
        XCTAssertEqual(model.state, .loading, "la réponse d'un epoch périmé n'est jamais publiée")
        XCTAssertNil(model.tableau)
    }

    func testDelaiDepasseEstUneErreurReseauBornee() async throws {
        let retenue = Gate() // jamais ouverte avant la fin du test : port muet
        let port = ScriptedDashboard([.snapshot(tableau("Trop tard"))], retenue: retenue)
        let (controller, snapshot) = try await pret(port, timeout: 0.05)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        let debut = Date()
        await model.load()
        XCTAssertEqual(model.state, .failed(SessionController.timeoutMessage))
        XCTAssertLessThan(Date().timeIntervalSince(debut), 2, "le délai de la session, pas le port, rend la main")
        XCTAssertFalse(model.sessionExpired)
        await retenue.open()
    }

    func testRelectureALApparitionSeulementAuDelaDeSoixanteSecondes() async throws {
        let horloge = HorlogeReglable(DemoWorld.fixedNow)
        let port = ScriptedDashboard([.snapshot(tableau("A")), .snapshot(tableau("B")), .snapshot(tableau("C"))])
        let (controller, snapshot) = try await pret(port, horloge: horloge)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.loadIfStale()
        XCTAssertEqual(port.calls, 1, "premier affichage : chargement")
        horloge.avancer(AccueilModel.delaiRelecture)
        await model.loadIfStale()
        XCTAssertEqual(port.calls, 1, "60 s pile : données encore fraîches")
        horloge.avancer(1)
        await model.loadIfStale()
        XCTAssertEqual(port.calls, 2, "au-delà de 60 s : relecture")
        XCTAssertEqual(model.tableau?.profil?.prenom, "B")
        XCTAssertEqual(AccueilModel.delaiRelecture, 60)
    }

    func testEchecNeRelancePasAutomatiquementALApparition() async throws {
        let port = ScriptedDashboard([.failure(JoleneError(.network, "Connexion impossible.")), .snapshot(tableau("A"))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.loadIfStale()
        await model.loadIfStale()
        XCTAssertEqual(port.calls, 1, "après un échec, « Réessayer » relance ; l'apparition ne boucle pas")
        await model.load()
        XCTAssertEqual(model.tableau?.profil?.prenom, "A")
    }
    // MARK: - Revue B8 de T3, 2e passe : délai unique, chargements sérialisés, « Vérifier ma session »

    func testDelaiDeLEcranTransmisAuPortEstCeluiDuControleur() async throws {
        let port = ScriptedDashboard([.snapshot(tableau("A")), .snapshot(tableau("B"))])
        let (controller, snapshot) = try await pret(port, timeout: 3)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        await model.load()
        XCTAssertEqual(port.delais, [3, 3],
                       "une seule source : le `resolutionTimeout` du contrôleur borne l'appel et les sous-lectures de la gateway")
    }

    func testChargementsChevauchesSeulLePlusRecentPublie() async throws {
        let entreeAncien = Gate(), sortieAncien = Gate(), entreeRecent = Gate(), sortieRecent = Gate()
        let port = ScriptedDashboard([
            .snapshot(tableau("A")),
            .retenue(.success(tableau("Ancien")), entree: entreeAncien, sortie: sortieAncien),
            .retenue(.success(tableau("Récent")), entree: entreeRecent, sortie: sortieRecent),
        ])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        let ancien = Task { await model.load() }  // tirer-pour-rafraîchir
        await entreeAncien.wait()
        let recent = Task { await model.load() }  // « Réessayer » ou `.task` pendant la lecture précédente
        await entreeRecent.wait()
        XCTAssertTrue(model.isRefreshing)

        await sortieRecent.open()
        await recent.value
        XCTAssertEqual(model.tableau?.profil?.prenom, "Récent")
        XCTAssertFalse(model.isRefreshing, "la lecture la plus récente a répondu")

        await sortieAncien.open()
        await ancien.value
        XCTAssertEqual(model.tableau?.profil?.prenom, "Récent",
                       "la réponse la plus lente d'une lecture dépassée n'écrase jamais un instantané plus récent")
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.refreshError)
    }

    func testLectureDepasseeNEteintPasLIndicateurNiNAfficheSonEchec() async throws {
        let entreeAncien = Gate(), sortieAncien = Gate(), entreeRecent = Gate(), sortieRecent = Gate()
        let port = ScriptedDashboard([
            .snapshot(tableau("A")),
            .retenue(.failure(JoleneError(.network, "Connexion impossible.")), entree: entreeAncien, sortie: sortieAncien),
            .retenue(.success(tableau("Récent")), entree: entreeRecent, sortie: sortieRecent),
        ])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        let ancien = Task { await model.load() }
        await entreeAncien.wait()
        let recent = Task { await model.load() }
        await entreeRecent.wait()

        await sortieAncien.open()
        await ancien.value
        XCTAssertTrue(model.isRefreshing, "la lecture la plus récente est encore en vol : l'indicateur reste allumé")
        XCTAssertNil(model.refreshError, "l'échec d'une lecture dépassée n'est jamais affiché")
        XCTAssertEqual(model.tableau?.profil?.prenom, "A")

        await sortieRecent.open()
        await recent.value
        XCTAssertEqual(model.tableau?.profil?.prenom, "Récent")
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.refreshError)
    }

    func testVerifierMaSessionRelitLeTableauQuandLaSessionResteValide() async throws {
        let port = ScriptedDashboard([.failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")),
                                      .snapshot(tableau("Camille"))])
        let (controller, snapshot) = try await pret(port)
        let session = SessionStore(controller: controller)
        await session.refresh()
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertTrue(model.sessionExpired)

        await model.verifierSession(session)
        XCTAssertEqual(session.state.snapshot?.epoch, snapshot.epoch, "session encore valide : même epoch, espace non démonté")
        XCTAssertEqual(model.tableau?.profil?.prenom, "Camille",
                       "sans relecture, l'écran resterait sur « Session à vérifier » (`loadIfStale` ne relance jamais un échec)")
        XCTAssertFalse(model.sessionExpired)
        XCTAssertEqual(port.calls, 2)
    }

    func testVerifierMaSessionFermeeNeRelitRienPourLAncienneIdentite() async throws {
        let etat = MutableAuthState(restored: utilisateurAccueil, restoreError: nil)
        let port = ScriptedDashboard([.failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))])
        let (controller, snapshot) = try await pret(port, auth: AuthPilotee(etat: etat))
        let session = SessionStore(controller: controller)
        await session.refresh()
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.load()

        await etat.set(restored: nil, restoreError: nil)
        await model.verifierSession(session)
        XCTAssertEqual(session.state, .signedOut(message: nil), "la racine affiche la connexion")
        XCTAssertEqual(port.calls, 1, "aucune lecture pour une identité qui n'est plus active")
        XCTAssertEqual(model.state, .failed("Votre session a expiré. Reconnectez-vous."))
    }
}
