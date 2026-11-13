import XCTest
@testable import JoleneCore

/// Centre de notifications du monde démo (lot 3, T5 ; blueprint §2.7) : `demo-notifications.json` exporté par
/// `scripts/mobile/export-demo-fixtures.mjs`, profil fictif seul, tri décroissant, deux non lues comme le compteur
/// de l'Accueil démo, « marquer lue » relu dans l'acteur, identifiant inconnu jamais un succès.
final class DemoNotificationsGatewayTests: XCTestCase {
    func testFixtureExporteeEtCoherenteAvecLAccueil() throws {
        let fichier = try DemoFixtures.loadNotifications()
        XCTAssertEqual(fichier.fixedNow, "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(fichier.notifications.map(\.id), (1...7).map { "demo-notification-00\($0)" })
        let nonLues = fichier.notifications.filter { !$0.lue }.count
        XCTAssertEqual(nonLues, try DemoFixtures.loadDashboard().dashboard.notifsNonLues,
                       "même nombre de non lues que le compteur `notifs_non_lues` de l'Accueil démo")
        XCTAssertEqual(fichier.notifications.map(\.lien), [
            "/soignant/missions/demo-assignee-001", "/soignant/missions", "/soignant/mes-gains?tab=factures",
            "/soignant/stripe-connect", "/soignant/parametres/notifications", "/soignant/litiges", nil,
        ])
        for notification in fichier.notifications {
            XCTAssertTrue(notification.titre.hasPrefix("Démonstration · "), "contenu fictif : \(notification.id)")
        }
    }

    func testListeDuProfilFictifTrieeEtBornee() async throws {
        let gateway = DemoNotificationsGateway()
        let liste = try await gateway.liste(context: DemoWorld.context)
        XCTAssertEqual(liste.count, 7)
        XCTAssertEqual(liste.compactMap(\.creeLe), liste.compactMap(\.creeLe).sorted(by: >), "cree_le décroissant")
    }

    /// Revue L3-T5, m10 : mêmes règles que la gateway Supabase (`order=cree_le.desc.nullsfirst`, parité du DESC sans
    /// suffixe du web) : une ligne sans `cree_le` vient en tête, puis les autres du plus récent au plus ancien.
    func testTriNullsFirstCommeSupabase() async throws {
        func ligne(_ id: String, _ creeLe: String?) -> NotificationJolene {
            NotificationJolene(id: id, type: "SYSTEM", titre: "Démonstration · \(id)", corps: "c", lue: true, creeLe: creeLe)
        }
        let lignes = [ligne("ancienne", "2026-11-01T08:00:00.000Z"), ligne("sans-date", nil),
                      ligne("recente", "2026-11-01T22:00:00.000Z")]
        let gateway = DemoNotificationsGateway(charger: { lignes })
        let liste = try await gateway.liste(context: DemoWorld.context)
        XCTAssertEqual(liste.map(\.id), ["sans-date", "recente", "ancienne"])
    }

    func testAutreCompteRefuse() async {
        let gateway = DemoNotificationsGateway()
        let autre = MissionReadContext(userId: "autre", email: nil, profile: SoignantProfile(id: "autre", profession: "IDE"))
        do {
            _ = try await gateway.liste(context: autre)
            XCTFail("la démo n'est jamais un repli pour un compte réel")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testMarquerLueRelueEtPersistanteDansLActeur() async throws {
        let gateway = DemoNotificationsGateway()
        let relue = try await gateway.marquerLue(id: "demo-notification-001", context: DemoWorld.context)
        XCTAssertTrue(relue.lue)
        XCTAssertEqual(relue.lueLe, "2026-11-02T00:00:00.000Z", "horloge démo")
        let liste = try await gateway.liste(context: DemoWorld.context)
        XCTAssertEqual(liste.first { $0.id == "demo-notification-001" }?.lue, true)
        XCTAssertEqual(liste.filter { !$0.lue }.map(\.id), ["demo-notification-002"])
        do {
            _ = try await gateway.marquerLue(id: "inconnue", context: DemoWorld.context)
            XCTFail("identifiant inconnu : jamais un succès")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.message, DemoNotificationsGateway.messageIntrouvable)
        }
    }

    func testDemoWorldCableLeCentre() {
        XCTAssertTrue(DemoWorld.gateways().notifications is DemoNotificationsGateway, "T5 câble le centre de notifications")
    }
}
