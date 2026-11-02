import XCTest
@testable import JoleneCore

/// Écran Profil › Sécurité (lot 1, T9) : interrupteur `biometrie-toggle` grisé sans biométrie
/// (« Non disponible sur cet appareil », démo comprise), activation confirmée par une
/// biométrie réussie, préférence par compte.
@MainActor
final class SecuriteModelTests: XCTestCase {

    private func modele(_ script: BiometricScript, preferences: InMemoryBiometricPreferences = InMemoryBiometricPreferences(),
                        userId: String = soignantDurci.id) -> SecuriteModel {
        SecuriteModel(gate: BiometricGate(port: FakeBiometrics(script: script), preferences: preferences), userId: userId)
    }

    func testIndisponibleInterrupteurGriseEtMessage() async {
        let model = modele(BiometricScript(availability: .unavailable))
        XCTAssertFalse(model.interrupteurModifiable, "grisé tant que la disponibilité n'est pas connue")
        await model.charger()
        XCTAssertEqual(model.disponibilite, .indisponible)
        XCTAssertFalse(model.interrupteurModifiable)
        XCTAssertFalse(model.interrupteur)
        XCTAssertEqual(SecuriteModel.indisponibleMessage, "Non disponible sur cet appareil")
        XCTAssertEqual(model.libelleInterrupteur, "Déverrouillage biométrique")
    }

    func testDemoIndisponible() async {
        let model = SecuriteModel(gate: .inactif, userId: DemoWorld.context.userId)
        await model.charger()
        XCTAssertEqual(model.disponibilite, .indisponible, "démo : biométrie désactivée")
        XCTAssertFalse(model.interrupteurModifiable)
    }

    func testActivationExigeUneBiometrieReussie() async {
        let preferences = InMemoryBiometricPreferences()
        let script = BiometricScript(availability: .available(.faceID), results: [.success])
        let model = modele(script, preferences: preferences)
        await model.charger()
        XCTAssertEqual(model.libelleInterrupteur, "Déverrouiller avec Face ID")
        XCTAssertTrue(model.interrupteurModifiable)
        XCTAssertFalse(model.interrupteur)
        await model.basculer(true)
        XCTAssertTrue(model.interrupteur)
        XCTAssertTrue(preferences.isEnabled(userId: soignantDurci.id))
        XCTAssertNil(model.message)
        let raisons = await script.raisons
        XCTAssertEqual(raisons, ["Confirmez pour activer le déverrouillage par Face ID."])
    }

    func testActivationAnnuleeResteDesactiveeSansMessage() async {
        let preferences = InMemoryBiometricPreferences()
        let model = modele(BiometricScript(results: [.cancelled]), preferences: preferences)
        await model.charger()
        await model.basculer(true)
        XCTAssertFalse(model.interrupteur)
        XCTAssertFalse(preferences.isEnabled(userId: soignantDurci.id))
        XCTAssertNil(model.message, "une annulation volontaire n'est pas une erreur")
    }

    func testActivationEchoueeAfficheUnMessage() async {
        let preferences = InMemoryBiometricPreferences()
        let model = modele(BiometricScript(availability: .available(.touchID), results: [.failed]), preferences: preferences)
        await model.charger()
        XCTAssertEqual(model.libelleInterrupteur, "Déverrouiller avec Touch ID")
        await model.basculer(true)
        XCTAssertFalse(model.interrupteur)
        XCTAssertFalse(preferences.isEnabled(userId: soignantDurci.id))
        XCTAssertEqual(model.message, SecuriteModel.activationEchoueeMessage)
    }

    func testBiometrieRetireePendantLActivation() async {
        let model = modele(BiometricScript(results: [.unavailable]))
        await model.charger()
        await model.basculer(true)
        XCTAssertFalse(model.interrupteur)
        XCTAssertEqual(model.disponibilite, .indisponible, "l'écran se met à jour : interrupteur grisé")
    }

    func testDesactivationSansDemande() async {
        let preferences = InMemoryBiometricPreferences()
        preferences.setEnabled(true, userId: soignantDurci.id)
        let script = BiometricScript()
        let model = modele(script, preferences: preferences)
        await model.charger()
        XCTAssertTrue(model.interrupteur)
        await model.basculer(false)
        XCTAssertFalse(model.interrupteur)
        XCTAssertFalse(preferences.isEnabled(userId: soignantDurci.id))
        let raisons = await script.raisons
        XCTAssertEqual(raisons, [], "désactiver ne demande aucune biométrie")
    }

    func testPreferenceActiveMaisBiometrieRetireeAfficheDesactive() async {
        let preferences = InMemoryBiometricPreferences()
        preferences.setEnabled(true, userId: soignantDurci.id)
        let model = modele(BiometricScript(availability: .unavailable), preferences: preferences)
        await model.charger()
        XCTAssertFalse(model.interrupteur, "sans biométrie, le verrou ne s'applique pas : l'interrupteur ne le prétend pas")
        XCTAssertFalse(model.interrupteurModifiable)
    }

    func testPreferenceParCompte() async {
        let preferences = InMemoryBiometricPreferences()
        preferences.setEnabled(true, userId: "autre-soignant")
        let model = modele(BiometricScript(), preferences: preferences)
        await model.charger()
        XCTAssertFalse(model.interrupteur, "la préférence d'un autre compte ne s'affiche pas")
    }

    func testExplicationVouvoieeSelonLaBiometrie() async {
        let model = modele(BiometricScript(availability: .available(.faceID)))
        await model.charger()
        XCTAssertEqual(model.explication,
                       "À l'ouverture de l'application et au retour après 30 minutes d'absence, Face ID vous est demandé avant d'afficher votre espace. Votre session reste enregistrée sur cet appareil.")
    }
}
