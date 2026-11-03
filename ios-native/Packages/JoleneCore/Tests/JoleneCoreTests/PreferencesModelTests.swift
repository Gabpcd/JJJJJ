import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurPreferences = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                       emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                       appMetadataRole: "SOIGNANT")

/// Modèle de l'écran « Préférences de notifications » (lot 3, T6) : lecture bornée par epoch, matrice
/// modifiable seulement là où le web l'est, enregistrement annoncé seulement après relecture concordante
/// (PRINCIPES §3), refus serveur verbatim, échec partiel de l'alerte SMS (web l.236-238), délai dépassé →
/// relecture sans renvoi (PRINCIPES §5), aucun double envoi.
@MainActor
final class PreferencesModelTests: XCTestCase {
    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurPreferences }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw nonScripte }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    /// Port scripté : chaque appel consomme une étape de sa file (`lectures`, `ecritures`) ; journalise
    /// les demandes reçues. `retenueEcriture` retient l'écriture jusqu'à son ouverture par le test.
    private final class ScriptedPreferences: NotificationPreferencesPort, @unchecked Sendable {
        private let lock = NSLock()
        private var lectures: [Result<PreferencesNotifications, Error>]
        private var ecritures: [Result<PreferencesNotifications, Error>]
        private var demandesRecues: [PreferencesNotifications] = []
        private var lecturesFaites = 0
        let entreeEcriture = Gate()
        var retenueEcriture: Gate?

        init(lectures: [Result<PreferencesNotifications, Error>], ecritures: [Result<PreferencesNotifications, Error>] = []) {
            self.lectures = lectures; self.ecritures = ecritures
        }

        var demandes: [PreferencesNotifications] { lock.lock(); defer { lock.unlock() }; return demandesRecues }
        var nombreLectures: Int { lock.lock(); defer { lock.unlock() }; return lecturesFaites }

        func lire(context: MissionReadContext) async throws -> PreferencesNotifications {
            let etape: Result<PreferencesNotifications, Error> = {
                lock.lock(); defer { lock.unlock() }
                lecturesFaites += 1
                return lectures.isEmpty ? .failure(nonScripte) : lectures.removeFirst()
            }()
            return try etape.get()
        }

        func enregistrer(_ preferences: PreferencesNotifications, context: MissionReadContext) async throws -> PreferencesNotifications {
            let etape: Result<PreferencesNotifications, Error> = {
                lock.lock(); defer { lock.unlock() }
                demandesRecues.append(preferences)
                return ecritures.isEmpty ? .failure(nonScripte) : ecritures.removeFirst()
            }()
            await entreeEcriture.open()
            if let retenueEcriture { await retenueEcriture.wait() }
            return try etape.get()
        }
    }

    private static let initiales = PreferencesNotifications(
        canalEmail: true, canalSms: false, canalPush: true, canalInApp: true,
        parEvenement: [PreferenceEvenement(typeEvenement: "LITIGE_RESOLU", canal: .push, actif: false)],
        smsAlertesActives: true, typeExercice: "MIXTE")

    private func pret(_ port: ScriptedPreferences,
                      timeout: TimeInterval = SessionController.defaultResolutionTimeout) async throws -> (SessionController, SessionSnapshot) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.preferences = port
        let controller = SessionController(gateways: gateways, resolutionTimeout: timeout)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return (controller, snapshot)
    }

    private func charge(_ port: ScriptedPreferences) async throws -> PreferencesModel {
        let (controller, snapshot) = try await pret(port)
        let model = PreferencesModel(controller: controller, snapshot: snapshot)
        await model.load()
        return model
    }

    // MARK: - Lecture

    func testChargementPublieLesPreferencesRelues() async throws {
        let model = try await charge(ScriptedPreferences(lectures: [.success(Self.initiales)]))
        XCTAssertEqual(model.state, .loaded(Self.initiales))
        XCTAssertEqual(model.preferences, Self.initiales)
        XCTAssertEqual(model.enregistrement, .aucun)
        XCTAssertFalse(model.sessionExpired)
    }

    func testEchecDeLectureAfficheLeMessageDuWebJamaisDeDefauts() async throws {
        for erreur: Error in [JoleneError(.network, SessionController.timeoutMessage),
                              JoleneError(.contract, PreferencesNotifications.messageIndisponible),
                              JoleneError(.unknown, "Erreur interne")] {
            let model = try await charge(ScriptedPreferences(lectures: [.failure(erreur)]))
            XCTAssertEqual(model.state, .failed(PreferencesTextes.chargementImpossible), "\(erreur)")
            XCTAssertNil(model.preferences, "aucune préférence par défaut affichée")
            XCTAssertFalse(model.sessionExpired)
        }
    }

    func testSessionExpireeALaLecture() async throws {
        let model = try await charge(ScriptedPreferences(lectures: [.failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))]))
        XCTAssertTrue(model.sessionExpired)
        XCTAssertEqual(model.state, .failed("Votre session a expiré. Reconnectez-vous."))
    }

    func testAnnulationNEstJamaisUneErreur() async throws {
        let model = try await charge(ScriptedPreferences(lectures: [.failure(CancellationError())]))
        XCTAssertEqual(model.state, .loading)
        let annule = try await charge(ScriptedPreferences(lectures: [.failure(JoleneError(.cancelled, "Chargement annulé."))]))
        XCTAssertEqual(annule.state, .loading)
    }

    func testReessayerApresEchecRelit() async throws {
        let port = ScriptedPreferences(lectures: [.failure(JoleneError(.network, "x")), .success(Self.initiales)])
        let model = try await charge(port)
        XCTAssertEqual(model.state, .failed(PreferencesTextes.chargementImpossible))
        await model.load()
        XCTAssertEqual(model.state, .loaded(Self.initiales))
        XCTAssertEqual(port.nombreLectures, 2)
    }

    func testChargerSiNecessaireNeRelitPasUnEcranCharge() async throws {
        let port = ScriptedPreferences(lectures: [.success(Self.initiales)])
        let model = try await charge(port)
        await model.chargerSiNecessaire()
        XCTAssertEqual(port.nombreLectures, 1, "un écran chargé garde son brouillon")
    }

    // MARK: - Édition

    func testEditionSuitLesReglesDeLaMatrice() async throws {
        let model = try await charge(ScriptedPreferences(lectures: [.success(Self.initiales)]))
        model.basculer(type: "CANDIDATURE_ACCEPTEE", canal: .sms)
        XCTAssertEqual(model.preferences?.parEvenement, Self.initiales.parEvenement, "canal SMS coupé : case non modifiable")
        model.definirCanalGlobal(.sms, actif: true)
        model.basculer(type: "CANDIDATURE_ACCEPTEE", canal: .sms)
        XCTAssertEqual(model.preferences?.estActif(type: "CANDIDATURE_ACCEPTEE", canal: .sms), false)
        model.definirAlerteSms(false)
        XCTAssertEqual(model.preferences?.smsAlertesActives, false)
    }

    func testAlerteSmsJamaisPoseeSansLigneSoignantNiCanalSms() async throws {
        var sansLigne = Self.initiales
        sansLigne.smsAlertesActives = nil
        let model = try await charge(ScriptedPreferences(lectures: [.success(sansLigne)]))
        model.definirCanalGlobal(.sms, actif: true)
        model.definirAlerteSms(false)
        XCTAssertNil(model.preferences?.smsAlertesActives, "ligne soignants non lue : jamais écrite (web l.230)")
        let coupe = try await charge(ScriptedPreferences(lectures: [.success(Self.initiales)]))
        coupe.definirAlerteSms(false)
        XCTAssertEqual(coupe.preferences?.smsAlertesActives, true, "canal SMS coupé : interrupteur grisé")
    }

    // MARK: - Enregistrement

    func testEnregistrementAnnonceApresRelectureConcordante() async throws {
        var attendu = Self.initiales
        attendu.canalEmail = false
        let port = ScriptedPreferences(lectures: [.success(Self.initiales)], ecritures: [.success(attendu)])
        let model = try await charge(port)
        model.definirCanalGlobal(.email, actif: false)
        await model.enregistrer()
        XCTAssertEqual(port.demandes, [attendu], "la demande est le brouillon, alerte SMS comprise")
        XCTAssertEqual(model.enregistrement, .enregistre)
        XCTAssertEqual(model.state, .loaded(attendu))
        model.definirCanalGlobal(.email, actif: true)
        XCTAssertEqual(model.enregistrement, .aucun, "une modification efface l'annonce « Préférences enregistrées »")
    }

    func testRelectureNonConcordanteNEstJamaisUnSucces() async throws {
        var relu = Self.initiales
        relu.canalPush = true
        let port = ScriptedPreferences(lectures: [.success(Self.initiales)], ecritures: [.success(relu)])
        let model = try await charge(port)
        model.definirCanalGlobal(.push, actif: false)
        await model.enregistrer()
        XCTAssertEqual(model.enregistrement, .echec(PreferencesTextes.echecEnregistrement))
        XCTAssertEqual(model.state, .loaded(relu), "l'écran montre l'état serveur relu")
    }

    func testEchecPartielDeLAlerteSmsMessageDuWeb() async throws {
        var debut = Self.initiales
        debut.canalSms = true
        let relu = debut // alerte relue inchangée (`true`) : la mise à jour de la colonne n'a pas pris
        let port = ScriptedPreferences(lectures: [.success(debut)], ecritures: [.success(relu)])
        let model = try await charge(port)
        model.definirAlerteSms(false)
        await model.enregistrer()
        XCTAssertEqual(port.demandes.first?.smsAlertesActives, false)
        XCTAssertEqual(model.enregistrement, .partiel(PreferencesTextes.echecPartielAlerteSms))
        XCTAssertEqual(model.preferences?.smsAlertesActives, true, "valeur serveur relue")
    }

    func testRefusServeurVerbatimEtBrouillonConserve() async throws {
        let port = ScriptedPreferences(lectures: [.success(Self.initiales)],
                                       ecritures: [.failure(JoleneError(.unknown, "Message serveur verbatim"))])
        let model = try await charge(port)
        model.definirCanalGlobal(.inApp, actif: false)
        await model.enregistrer()
        XCTAssertEqual(model.enregistrement, .echec("Message serveur verbatim"))
        XCTAssertEqual(model.preferences?.canalInApp, false, "refus explicite : le brouillon de l'utilisateur est conservé")
        XCTAssertEqual(port.nombreLectures, 1, "refus explicite : aucune relecture imposée")
        XCTAssertEqual(port.demandes.count, 1, "aucun renvoi automatique")
    }

    func testDelaiDepasseImposeUneRelectureJamaisUnRenvoi() async throws {
        var serveur = Self.initiales
        serveur.canalInApp = false
        let port = ScriptedPreferences(lectures: [.success(Self.initiales), .success(serveur)],
                                       ecritures: [.failure(JoleneError(.network, SessionController.timeoutMessage))])
        let model = try await charge(port)
        model.definirCanalGlobal(.inApp, actif: false)
        await model.enregistrer()
        XCTAssertEqual(model.enregistrement, .echec(SessionController.timeoutMessage))
        XCTAssertEqual(port.demandes.count, 1, "jamais de renvoi")
        XCTAssertEqual(port.nombreLectures, 2, "issue inconnue : relecture")
        XCTAssertEqual(model.state, .loaded(serveur), "l'écran montre ce que le serveur a réellement")
    }

    func testDelaiDepasseEtRelectureEnEchecGardeLeBrouillon() async throws {
        let port = ScriptedPreferences(lectures: [.success(Self.initiales), .failure(JoleneError(.network, "x"))],
                                       ecritures: [.failure(JoleneError(.network, SessionController.timeoutMessage))])
        let model = try await charge(port)
        model.definirCanalGlobal(.inApp, actif: false)
        await model.enregistrer()
        XCTAssertEqual(model.enregistrement, .echec(SessionController.timeoutMessage))
        XCTAssertEqual(model.preferences?.canalInApp, false)
    }

    func testSessionExpireeALEnregistrement() async throws {
        let port = ScriptedPreferences(lectures: [.success(Self.initiales)],
                                       ecritures: [.failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))])
        let model = try await charge(port)
        await model.enregistrer()
        XCTAssertTrue(model.sessionExpired)
        XCTAssertEqual(model.enregistrement, .echec("Votre session a expiré. Reconnectez-vous."))
    }

    func testAucunDoubleEnvoiNiEditionPendantLEnregistrement() async throws {
        let port = ScriptedPreferences(lectures: [.success(Self.initiales)], ecritures: [.success(Self.initiales)])
        let retenue = Gate()
        port.retenueEcriture = retenue
        let model = try await charge(port)
        let premier = Task { await model.enregistrer() }
        await port.entreeEcriture.wait()
        XCTAssertEqual(model.enregistrement, .enCours)
        await model.enregistrer()
        model.definirCanalGlobal(.email, actif: false)
        XCTAssertEqual(model.preferences?.canalEmail, true, "aucune modification pendant l'envoi")
        await retenue.open()
        await premier.value
        XCTAssertEqual(port.demandes.count, 1, "un seul envoi")
        XCTAssertEqual(model.enregistrement, .enregistre)
    }

    func testEnregistrerSansPreferencesChargeesNEnvoieRien() async throws {
        let port = ScriptedPreferences(lectures: [.failure(JoleneError(.network, "x"))])
        let model = try await charge(port)
        await model.enregistrer()
        XCTAssertEqual(port.demandes, [], "jamais de défauts envoyés")
        XCTAssertEqual(model.enregistrement, .aucun)
    }
}
