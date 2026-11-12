import XCTest
@testable import JoleneCore

/// Ports du compte du monde démo (lot 3, T11) : mot de passe en mémoire (ancien `demo-motdepasse`, blueprint
/// §2.7), export lu dans `demo-export-rgpd.json` octet pour octet, refus scripté verbatim serveur ; tout autre
/// contexte que le profil fictif est refusé (`.demoOnly`) ; aucune requête réseau (`DemoNoNetworkTests`).
final class DemoCompteGatewaysTests: XCTestCase {
    private let autre = MissionReadContext(userId: "u-reel", email: "reel@example.invalid",
                                           profile: SoignantProfile(id: "u-reel", profession: "IDE"))

    func testMotDePasseDemoAncienVerifiePuisRemplace() async throws {
        let port = DemoMotDePasseGateway()
        let contexte = DemoWorld.context
        let incorrect = try await port.changer(ancien: "demonstration", nouveau: "Nouveau-mdp-2026", context: contexte)
        XCTAssertEqual(incorrect, .ancienIncorrect)
        let modifie = try await port.changer(ancien: DemoMotDePasseGateway.ancienDemo, nouveau: "Nouveau-mdp-2026", context: contexte)
        XCTAssertEqual(modifie, .modifie)
        let ancienPerime = try await port.changer(ancien: DemoMotDePasseGateway.ancienDemo, nouveau: "Autre-mdp-2026!", context: contexte)
        XCTAssertEqual(ancienPerime, .ancienIncorrect, "le nouveau mot de passe remplace l'ancien (relu en mémoire)")
        let enchaine = try await port.changer(ancien: "Nouveau-mdp-2026", nouveau: "Autre-mdp-2026!", context: contexte)
        XCTAssertEqual(enchaine, .modifie)
        XCTAssertEqual(DemoMotDePasseGateway.ancienDemo, "demo-motdepasse")
    }

    func testMotDePasseDemoRefuseUnAutreContexte() async {
        do {
            _ = try await DemoMotDePasseGateway().changer(ancien: "demo-motdepasse", nouveau: "x", context: autre)
            XCTFail("contexte réel refusé")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testExportDemoRendLaFixtureOctetPourOctet() async throws {
        let donnees = try await DemoExportRGPDGateway().exporter(context: DemoWorld.context)
        let fixture = try DemoFixtures.donneesExportRGPD()
        XCTAssertEqual(donnees.json, fixture, "aucun réencodage : l'ordre des clés du fichier est conservé")
        let racine = try JSONOrdonne.analyser(donnees.json)
        guard case .objet(let membres) = racine else { return XCTFail("objet attendu") }
        let cles = membres.map(\.cle)
        XCTAssertEqual(Set(["export_date", "utilisateur_id", "profil", "missions", "notifications", "notations_recues"])
            .subtracting(cles), [], "clés de l'export serveur (fn_rgpd_exporter_donnees_soignant)")
        // L'ordre des clés est celui d'un jsonb PostgreSQL (longueur, puis octets), comme la réponse réelle.
        let ordreJsonb = cles.sorted { a, b in
            let (octetsA, octetsB) = (Array(a.utf8), Array(b.utf8))
            return octetsA.count != octetsB.count ? octetsA.count < octetsB.count : octetsA.lexicographicallyPrecedes(octetsB)
        }
        XCTAssertEqual(cles, ordreJsonb)
        XCTAssertEqual(ExportRGPD.analyserReponse(donnees.json), .donnees(donnees))
        // Aucune donnée sensible dans la fixture (le serveur retire `numero_secu`, la démo n'en invente aucune).
        let texte = String(decoding: donnees.json, as: UTF8.self)
        for interdit in ["numero_secu", "iban", "stripe_account_id", "siret_liberal"] {
            XCTAssertFalse(texte.contains(interdit), interdit)
        }
        // Fichiers produits sans erreur dans les deux formats.
        let fichier = try ExportRGPD.fichier(donnees, format: .csv, maintenant: DemoWorld.fixedNow)
        XCTAssertEqual(fichier.nom, "mes-donnees-jolene-2026-11-02.csv")
        XCTAssertTrue(String(decoding: fichier.contenu, as: UTF8.self).hasPrefix("Champ,Valeur\n"))
    }

    func testExportDemoRefusVerbatimEtAutreContexte() async {
        do {
            _ = try await DemoExportRGPDGateway(refus: ExportRGPD.refusLimiteServeur).exporter(context: DemoWorld.context)
            XCTFail("refus scripté attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unknown)
            XCTAssertEqual(erreur.message, "Trop d'exports en peu de temps. Réessayez dans quelques minutes.")
        } catch {
            XCTFail("\(error)")
        }
        do {
            _ = try await DemoExportRGPDGateway().exporter(context: autre)
            XCTFail("contexte réel refusé")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testMondeDemoCableLesPortsDuCompte() {
        let gateways = DemoWorld.gateways()
        XCTAssertTrue(gateways.motDePasse is DemoMotDePasseGateway, "T11 câble le mot de passe")
        XCTAssertTrue(gateways.exportRGPD is DemoExportRGPDGateway, "T11 câble l'export RGPD")
    }
}
