import XCTest
@testable import JoleneCore

/// Monde démo des préférences (lot 3, T6 ; blueprint §2.7 « Préférences ») : `demo-preferences.json`
/// (global + 3 exceptions, ligne `soignants` du profil fictif), enregistrement relu depuis l'acteur avec
/// la sémantique de la RPC (canaux remplacés, exceptions mises à jour par clé, jamais supprimées), aucun
/// réseau, refus de tout autre utilisateur. Variante en échec forcé pour la recette de l'état d'erreur.
final class DemoPreferencesTests: XCTestCase {
    private let contexte = DemoWorld.context

    func testFixtureDeLaDemoAlHorlogeFixeeEtAuProfilFictif() throws {
        let fichier = try DemoFixtures.loadPreferences()
        XCTAssertEqual(fichier.fixedNow, "2026-11-02T00:00:00.000Z")
        let preferences = try PreferencesNotifications.decoder(preferences: fichier.preferences, soignant: fichier.soignant)
        XCTAssertEqual([preferences.canalEmail, preferences.canalSms, preferences.canalPush, preferences.canalInApp],
                       [true, false, true, true], "défauts serveur : SMS coupé (l.44114-44117)")
        XCTAssertEqual(preferences.parEvenement.count, 3, "trois exceptions (blueprint §2.7)")
        XCTAssertTrue(preferences.parEvenement.allSatisfy { CatalogueNotificationsSoignant.evenement(type: $0.typeEvenement) != nil })
        XCTAssertEqual(preferences.smsAlertesActives, true)
        XCTAssertEqual(preferences.typeExercice, DemoWorld.context.profile.typeExercice,
                       "état dérivé : le régime de la fixture est celui du profil démo")
    }

    func testLectureDemoRendLaFixture() async throws {
        let gateway = DemoPreferencesGateway()
        let lu = try await gateway.lire(context: contexte)
        let fichier = try DemoFixtures.loadPreferences()
        XCTAssertEqual(lu, try PreferencesNotifications.decoder(preferences: fichier.preferences, soignant: fichier.soignant))
        XCTAssertFalse(lu.estActif(type: "LITIGE_RESOLU", canal: .push), "exception de la fixture")
    }

    func testEnregistrementDemoRelitCeQuiAEteEcrit() async throws {
        let gateway = DemoPreferencesGateway()
        var demande = try await gateway.lire(context: contexte)
        demande.definirCanalGlobal(.sms, actif: true)
        demande.basculer(type: "CANDIDATURE_ACCEPTEE", canal: .sms)
        demande.basculer(type: "LITIGE_RESOLU", canal: .push)
        demande.smsAlertesActives = false
        demande.parEvenement.append(PreferenceEvenement(typeEvenement: "URGENCE", canal: .email, actif: false))
        let relu = try await gateway.enregistrer(demande, context: contexte)
        XCTAssertTrue(relu.canalSms)
        XCTAssertEqual(relu.smsAlertesActives, false)
        XCTAssertFalse(relu.estActif(type: "CANDIDATURE_ACCEPTEE", canal: .sms))
        XCTAssertTrue(relu.estActif(type: "LITIGE_RESOLU", canal: .push))
        XCTAssertFalse(relu.parEvenement.contains { $0.typeEvenement == "URGENCE" }, "type hors catalogue jamais écrit")
        XCTAssertEqual(relu.concordance(avec: demande), ConcordancePreferences(generales: true, alerteSms: true))
        let relue = try await gateway.lire(context: contexte)
        XCTAssertEqual(relue, relu, "nouvelle lecture = état enregistré dans l'acteur")
        let autreMonde = try await DemoPreferencesGateway().lire(context: contexte)
        XCTAssertTrue(autreMonde.estActif(type: "CANDIDATURE_ACCEPTEE", canal: .sms), "chaque jeu de ports démo repart de la fixture")
    }

    func testUneExceptionNEstJamaisSupprimeeParUnEnregistrement() async throws {
        let gateway = DemoPreferencesGateway()
        var demande = try await gateway.lire(context: contexte)
        let avant = demande.parEvenement
        demande.parEvenement = []
        let relu = try await gateway.enregistrer(demande, context: contexte)
        XCTAssertEqual(relu.parEvenement, avant, "UPSERT par (type, canal) : rien n'est supprimé (l.44124-44136)")
    }

    func testAlerteNonLueNEstPasEcrite() async throws {
        let gateway = DemoPreferencesGateway()
        var demande = try await gateway.lire(context: contexte)
        demande.smsAlertesActives = nil
        let relu = try await gateway.enregistrer(demande, context: contexte)
        XCTAssertEqual(relu.smsAlertesActives, true, "nil = colonne non écrite")
    }

    func testDemoRefuseUnAutreUtilisateur() async {
        let autre = MissionReadContext(userId: "autre", email: nil, profile: SoignantProfile(id: "autre", profession: "IDE"))
        let operations: [@Sendable () async throws -> Void] = [
            { _ = try await DemoPreferencesGateway().lire(context: autre) },
            { _ = try await DemoPreferencesGateway().enregistrer(DemoPreferencesTests.vide, context: autre) },
        ]
        for operation in operations {
            do {
                try await operation()
                XCTFail("la démo n'est jamais un repli pour un compte réel")
            } catch {
                XCTAssertEqual((error as? JoleneError)?.kind, .demoOnly)
            }
        }
    }

    func testVarianteEnEchecForcePuisReprise() async throws {
        let gateway = DemoPreferencesEchecGateway(echecs: 1)
        do {
            _ = try await gateway.lire(context: contexte)
            XCTFail("premier chargement en échec attendu")
        } catch {
            XCTAssertEqual(error as? JoleneError, JoleneError(.network, SessionController.timeoutMessage))
        }
        let lu = try await gateway.lire(context: contexte)
        XCTAssertEqual(lu.parEvenement.count, 3, "reprise : la fixture est relue")
        let relu = try await gateway.enregistrer(lu, context: contexte)
        XCTAssertEqual(relu, lu)
    }

    func testDemoWorldCableLesPreferences() {
        XCTAssertTrue(DemoWorld.gateways().preferences is DemoPreferencesGateway)
        XCTAssertFalse(DemoWorld.gateways().unwiredPorts.contains("preferences"))
    }

    private static let vide = PreferencesNotifications(canalEmail: true, canalSms: false, canalPush: true, canalInApp: true,
                                                       parEvenement: [])
}
