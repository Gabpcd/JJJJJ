import XCTest
@testable import JoleneCore

/// Verrou biométrique applicatif (lot 1, T9, décision 1) : `LAContext` devant `restoreSession`,
/// item Keychain inchangé (aucun `SecAccessControl`), désactivé en démo et sans biométrie enrôlée.
/// « Sans Keychain » se lit dans le journal : ni `restoreSession` ni `signOut` après un refus.
@MainActor
final class BiometricGateTests: XCTestCase {

    private func gate(_ script: BiometricScript, activePour userId: String? = soignantDurci.id,
                      preferences: InMemoryBiometricPreferences = InMemoryBiometricPreferences()) -> BiometricGate {
        if let userId {
            preferences.setEnabled(true, userId: userId)
            preferences.setSessionIdentity(userId)
        }
        return BiometricGate(port: FakeBiometrics(script: script), preferences: preferences)
    }

    func testBiometrieIndisponiblePasseEtRestaure() async {
        let script = BiometricScript(availability: .unavailable)
        let monde = SessionDurcieMonde(restored: soignantDurci)
        let store = monde.store(biometrie: gate(script))
        await store.start()
        XCTAssertTrue(store.state.isReady, "non enrôlé : le verrou s'efface, obtenu \(store.state)")
        let raisons = await script.raisons
        XCTAssertEqual(raisons, [], "aucune évaluation sans biométrie disponible")
        let entrees = await monde.journal.entries
        XCTAssertEqual(entrees, ["restoreSession"])
    }

    func testEchecVerrouilleSansToucherALaSession() async {
        let script = BiometricScript(results: [.failed])
        let monde = SessionDurcieMonde(restored: soignantDurci)
        let store = monde.store(biometrie: gate(script))
        await store.start()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        XCTAssertTrue(store.canRetryRestore, "« Réessayer sans mot de passe » relance le verrou")
        let entrees = await monde.journal.entries
        XCTAssertEqual(entrees, [], "ni restoreSession ni signOut : la session persistée n'est pas touchée")
        let session = await monde.authState.session
        XCTAssertEqual(session, soignantDurci, "la session persistée reste intacte")
        let epoch = await store.controller.epoch
        XCTAssertEqual(epoch, 0, "aucune identité n'était active au lancement")
        let raisons = await script.raisons
        XCTAssertEqual(raisons, [BiometricGate.raisonDeverrouillage])
    }

    func testAnnulationVerrouilleCommeUnEchec() async {
        let script = BiometricScript(results: [.cancelled])
        let monde = SessionDurcieMonde(restored: soignantDurci)
        let store = monde.store(biometrie: gate(script))
        await store.start()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        XCTAssertTrue(store.canRetryRestore)
        let entrees = await monde.journal.entries
        XCTAssertEqual(entrees, [])
    }

    func testSuccesRestaureLaSession() async {
        let script = BiometricScript(results: [.success])
        let monde = SessionDurcieMonde(restored: soignantDurci)
        let store = monde.store(biometrie: gate(script))
        await store.start()
        XCTAssertTrue(store.state.isReady, "obtenu \(store.state)")
        XCTAssertEqual(store.state.snapshot?.user.id, soignantDurci.id)
        let raisons = await script.raisons
        XCTAssertEqual(raisons.count, 1)
        let entrees = await monde.journal.entries
        XCTAssertEqual(entrees, ["restoreSession"], "LAContext AVANT restoreSession")
        XCTAssertFalse(store.deverrouillageEnCours)
    }

    func testIndisponibleAuMomentDeLEvaluationPasse() async {
        let script = BiometricScript(results: [.unavailable])
        let monde = SessionDurcieMonde(restored: soignantDurci)
        let store = monde.store(biometrie: gate(script))
        await store.start()
        XCTAssertTrue(store.state.isReady, "biométrie retirée entre-temps : désactivée, pas de verrou")
    }

    func testPreferenceDesactiveeOuAutreIdentiteNeDemandeRien() async {
        let script = BiometricScript(results: [.failed])
        let monde = SessionDurcieMonde(restored: soignantDurci)
        let store = monde.store(biometrie: gate(script, activePour: nil))
        await store.start()
        XCTAssertTrue(store.state.isReady)

        let preferences = InMemoryBiometricPreferences()
        preferences.setEnabled(true, userId: "autre-soignant")
        preferences.setSessionIdentity(soignantDurci.id)
        let autre = SessionDurcieMonde(restored: soignantDurci)
        let store2 = autre.store(biometrie: BiometricGate(port: FakeBiometrics(script: script), preferences: preferences))
        await store2.start()
        XCTAssertTrue(store2.state.isReady, "la préférence d'un autre compte ne verrouille pas celui-ci")
        let raisons = await script.raisons
        let verifications = await script.verificationsDisponibilite
        XCTAssertEqual(raisons, [])
        XCTAssertEqual(verifications, 0, "sans préférence active, LAContext n'est même pas interrogé")
    }

    func testReessayerApresUnRefusRedemandeLaBiometrie() async {
        let script = BiometricScript(results: [.cancelled, .success])
        let monde = SessionDurcieMonde(restored: soignantDurci)
        let store = monde.store(biometrie: gate(script))
        await store.start()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        await store.start()
        XCTAssertTrue(store.state.isReady, "obtenu \(store.state)")
        XCTAssertFalse(store.canRetryRestore)
        let raisons = await script.raisons
        XCTAssertEqual(raisons.count, 2)
    }

    func testRepriseApresTrenteMinutesVerrouilleLIdentiteActive() async {
        let script = BiometricScript(results: [.success, .failed])
        let monde = SessionDurcieMonde(restored: soignantDurci)
        let store = monde.store(biometrie: gate(script))
        await store.start()
        XCTAssertTrue(store.state.isReady)
        let epochPret = await store.controller.epoch
        await store.start() // reprise > 30 min (JoleneApp)
        XCTAssertEqual(store.state, .signedOut(message: nil), "verrou refusé à la reprise : l'espace se ferme")
        XCTAssertTrue(store.canRetryRestore)
        let epoch = await store.controller.epoch
        XCTAssertEqual(epoch, epochPret + 1, "l'identité est retirée : caches et écrans invalidés")
        let entrees = await monde.journal.entries
        XCTAssertEqual(entrees, ["restoreSession"], "aucun signOut : la session persistée reste")
        let session = await monde.authState.session
        XCTAssertEqual(session, soignantDurci)
    }

    func testVerificationPublieePendantLaDemande() async {
        let barriere = Gate()
        let script = BiometricScript(results: [.success])
        let preferences = InMemoryBiometricPreferences()
        preferences.setEnabled(true, userId: soignantDurci.id)
        preferences.setSessionIdentity(soignantDurci.id)
        let monde = SessionDurcieMonde(restored: soignantDurci)
        let store = monde.store(biometrie: BiometricGate(port: FakeBiometrics(script: script, gate: barriere), preferences: preferences))
        async let demarrage: Void = store.start()
        await waitUntil { @MainActor in store.deverrouillageEnCours }
        XCTAssertEqual(store.state, .loading, "l'espace n'est pas affiché pendant la demande")
        await store.start() // second appel pendant la demande : ignoré, aucune seconde invite
        await barriere.open()
        await demarrage
        XCTAssertFalse(store.deverrouillageEnCours)
        XCTAssertTrue(store.state.isReady)
        let raisons = await script.raisons
        XCTAssertEqual(raisons.count, 1)
    }

    func testIdentiteMemoriseeAuPretEtOublieeALaDeconnexion() async {
        let preferences = InMemoryBiometricPreferences()
        let monde = SessionDurcieMonde()
        let store = monde.store(biometrie: BiometricGate(port: FakeBiometrics(script: BiometricScript()), preferences: preferences))
        await store.signIn(email: "t9@example.invalid", password: "secret-value")
        XCTAssertEqual(preferences.sessionIdentity, soignantDurci.id, "identité dont la session est conservée")
        preferences.setEnabled(true, userId: soignantDurci.id)
        await store.signOut()
        XCTAssertNil(preferences.sessionIdentity, "plus de session à protéger après une déconnexion volontaire")
        XCTAssertTrue(preferences.isEnabled(userId: soignantDurci.id), "la préférence du compte survit à la déconnexion")
    }

    func testSessionEffaceeParLeSDKOublieLIdentite() async {
        let emitter = AuthEventEmitter()
        let preferences = InMemoryBiometricPreferences()
        var monde = SessionDurcieMonde(restored: soignantDurci)
        monde.events = emitter
        let store = monde.store(biometrie: BiometricGate(port: FakeBiometrics(script: BiometricScript()), preferences: preferences))
        store.observeAuthEvents()
        await store.start()
        XCTAssertEqual(preferences.sessionIdentity, soignantDurci.id)
        emitter.emit(.signedOut)
        await waitUntil { @MainActor in store.state == .signedOut(message: SessionController.sessionExpiredMessage) }
        XCTAssertNil(preferences.sessionIdentity, "session révoquée : plus rien à déverrouiller au prochain lancement")
    }

    func testVerrouInactifParDefaut() async {
        let verrou = BiometricGate.inactif
        XCTAssertFalse(verrou.verrouAttendu)
        let issue = await verrou.verifier()
        XCTAssertEqual(issue, .aucunVerrou)
        let disponibilite = await verrou.port.availability()
        XCTAssertEqual(disponibilite, .unavailable, "démo : biométrie « Non disponible sur cet appareil »")
    }

    // MARK: - Préférences

    func testPreferencesUserDefaultsParUtilisateurEtPurgeesAvecLeCompte() throws {
        let suite = "jolene.tests.biometrie.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = UserDefaultsBiometricPreferences(defaults: defaults)
        let a = "0b7e9a52-5a1c-4f0e-9a39-3f1d2c4b5a61"
        let b = "1c8f0b63-6b2d-4a1f-8b4a-4e2e3d5c6b72"
        XCTAssertFalse(preferences.isEnabled(userId: a))
        preferences.setEnabled(true, userId: a.uppercased())
        XCTAssertTrue(preferences.isEnabled(userId: a), "identifiant normalisé en minuscules")
        XCTAssertFalse(preferences.isEnabled(userId: b), "préférence propre à chaque compte")
        XCTAssertEqual(defaults.bool(forKey: "\(UserDefaultsBiometricPreferences.enabledKeyPrefix)\(a)"), true)
        preferences.setSessionIdentity(a)
        XCTAssertEqual(preferences.sessionIdentity, a)

        // Suppression de compte (T8) : les clés dont un segment est l'identifiant sont purgées.
        let purgees = CompteSuppression.purgerPreferencesLocales(userId: a, defaults: defaults)
        XCTAssertTrue(purgees.contains("\(UserDefaultsBiometricPreferences.enabledKeyPrefix)\(a)"))
        XCTAssertFalse(preferences.isEnabled(userId: a))

        preferences.setEnabled(true, userId: b)
        preferences.setEnabled(false, userId: b)
        XCTAssertNil(defaults.object(forKey: "\(UserDefaultsBiometricPreferences.enabledKeyPrefix)\(b)"), "désactiver retire la clé")
        preferences.setSessionIdentity(nil)
        XCTAssertNil(preferences.sessionIdentity)
        preferences.setEnabled(true, userId: "  ")
        XCTAssertFalse(preferences.isEnabled(userId: "  "), "identifiant vide refusé")
    }
}
