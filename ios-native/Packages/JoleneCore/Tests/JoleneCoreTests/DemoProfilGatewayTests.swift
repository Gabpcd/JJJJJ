import XCTest
@testable import JoleneCore

/// Profil du monde démo (lot 3, T9) : fixture `demo-profil-complet.json` en liste blanche, règles de
/// `fn_modifier_mon_profil` appliquées en mémoire puis relues par le même décodeur que Supabase.
final class DemoProfilGatewayTests: XCTestCase {
    private let contexte = DemoWorld.context

    func testFixtureSansAucuneCleSensibleEtLueParLeDecodeur() throws {
        let fichier = try DemoFixtures.loadProfilComplet()
        XCTAssertEqual(fichier.fixedNow, "2026-11-02T00:00:00.000Z")
        guard case .objet(let ligne) = fichier.profil else { return XCTFail("objet attendu") }
        XCTAssertEqual(Set(ligne.keys).intersection(ProfilComplet.clesSensibles), [], "clé sensible dans la fixture démo")
        XCTAssertTrue(Set(ligne.keys).isSubset(of: ProfilComplet.clesLues.union(["specialites"])),
                      "fixture réduite à la liste blanche : \(Set(ligne.keys).subtracting(ProfilComplet.clesLues))")
        let profil = try ProfilComplet.depuis(fichier.profil, userId: contexte.userId)
        XCTAssertEqual(profil.prenom, "Camille")
        XCTAssertEqual(profil.nom, "Démo")
        XCTAssertEqual(profil.email, contexte.email)
        XCTAssertEqual(profil.profession, contexte.profile.profession)
        XCTAssertEqual(profil.rayonDeplacementKm, 50)
        XCTAssertEqual(profil.typesContratAcceptes, ["CDD", "LIBERAL"], "mêmes contrats que demo-profile.json")
    }

    func testLectureEtModificationReluesEnMemoire() async throws {
        let gateway = DemoProfilGateway()
        let avant = try await gateway.profil(context: contexte)
        XCTAssertNil(avant.villeRecherche)
        let apres = try await gateway.modifier(ModificationProfil(villeRecherche: "Lyon", typesContratAcceptes: ["CDD"]),
                                               context: contexte)
        XCTAssertEqual(apres.villeRecherche, "Lyon")
        XCTAssertEqual(apres.typesContratAcceptes, ["CDD"], "écrit `array_to_string(p_types_contrat, ',')` puis relu")
        let relu = try await gateway.profil(context: contexte)
        XCTAssertEqual(relu, apres, "l'état persiste pour le jeu de ports")
        // `COALESCE` : un paramètre absent ne change rien.
        let inchange = try await gateway.modifier(ModificationProfil(bio: "Bonjour"), context: contexte)
        XCTAssertEqual(inchange.villeRecherche, "Lyon")
        XCTAssertEqual(inchange.bio, "Bonjour")
    }

    func testPrenomOuNomVidesRefusesAvecLeMessageServeur() async throws {
        let gateway = DemoProfilGateway()
        do {
            _ = try await gateway.modifier(ModificationProfil(prenom: " "), context: contexte)
            XCTFail("refus attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur, JoleneError(.unknown, "Le prénom ne peut pas être vide"))
        }
        do {
            _ = try await gateway.modifier(ModificationProfil(nom: ""), context: contexte)
            XCTFail("refus attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur, JoleneError(.unknown, "Le nom ne peut pas être vide"))
        }
        let relu = try await gateway.profil(context: contexte)
        XCTAssertEqual(relu.prenom, "Camille", "rien n'a été écrit")
    }

    func testPrenomEnregistreSansBlancsEtRppsFigeApresVerification() async throws {
        let ligne: ValeurJSON = .objet(["id": .chaine("demo-soignant"), "prenom": .chaine("Camille"), "nom": .chaine("Démo"),
                                        "email": .null, "profession": .chaine("IDE"), "rpps_verifie": .booleen(true),
                                        "numero_rpps": .chaine("10101010101")])
        let gateway = DemoProfilGateway(fixture: { ligne })
        let relu = try await gateway.modifier(ModificationProfil(prenom: "  Lou  ", numeroRpps: "20202020202"), context: contexte)
        XCTAssertEqual(relu.prenom, "Lou")
        XCTAssertEqual(relu.numeroRpps, "10101010101", "RPPS vérifié : inchangé, sans erreur (l.43949-43952)")
    }

    func testAutreCompteRefuse() async {
        let autre = MissionReadContext(userId: "u-1", email: nil, profile: SoignantProfile(id: "u-1", profession: "IDE"))
        do {
            _ = try await DemoProfilGateway().profil(context: autre)
            XCTFail("refus attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        } catch {
            XCTFail("erreur inattendue \(error)")
        }
    }

    func testLeMondeDemoCableLeProfil() async throws {
        let gateways = DemoWorld.gateways()
        XCTAssertTrue(gateways.profil is DemoProfilGateway)
        let profil = try await gateways.profil.profil(context: contexte)
        XCTAssertEqual(profil.id, contexte.userId)
    }
}
