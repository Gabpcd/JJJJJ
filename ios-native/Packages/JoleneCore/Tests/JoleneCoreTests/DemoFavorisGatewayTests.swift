import XCTest
@testable import JoleneCore

/// Favoris du monde démo (lot 1, T4b ; blueprint §2.7) : `demo-favoris.json` (une mission, un
/// établissement) et un acteur en mémoire — ajouts et retraits visibles jusqu'au relancement, chaque
/// mutation relue, aucun réseau, tout autre utilisateur refusé, ajout d'établissement verrouillé
/// (décision 8).
final class DemoFavorisGatewayTests: XCTestCase {
    private let contexte = DemoWorld.context

    private func autreContexte() -> MissionReadContext {
        var autre = DemoWorld.context
        autre.userId = "user-1"
        autre.profile.id = "user-1"
        return autre
    }

    func testFixtureCoherenteAvecLeMondeDemo() throws {
        let fichier = try DemoFixtures.loadFavoris()
        XCTAssertEqual(fichier.fixedNow, "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(fichier.missionsSauvegardees.map(\.missionId), ["demo-mission-002"])
        let missions = try DemoFixtures.loadMissions().missions
        let record = try XCTUnwrap(missions.first { $0.record.id == "demo-mission-002" }?.record)
        XCTAssertEqual(fichier.missionsSauvegardees.first?.mission, MissionSauvegardee.Apercu(record),
                       "jointure exportée = colonnes de la mission démo")

        XCTAssertEqual(fichier.etablissementsFavoris.map(\.id), ["demo-etab-2"])
        let favori = try XCTUnwrap(fichier.etablissementsFavoris.first)
        let etablissement = try XCTUnwrap(DemoFixtures.loadEtablissements().etablissements.first { $0.id == favori.id })
        XCTAssertEqual(favori.nom, etablissement.nom)
        XCTAssertEqual(favori.ville, etablissement.adresseVille)
        XCTAssertEqual(favori.typeEtablissement, etablissement.type)
        // `nb_missions_ouvertes` = count(*) OUVERTE ET debut_le > now de l'établissement (l.41850 du dump).
        let ouvertes = missions.filter {
            $0.record.etablissementId == favori.id && $0.record.statut == "OUVERTE"
                && (PlanningHorlogeParis.instant($0.record.debutLe) ?? .distantPast) > DemoWorld.fixedNow
        }
        XCTAssertEqual(favori.nbMissionsOuvertes, ouvertes.count)
        XCTAssertEqual(favori.nbMissionsOuvertes, 10)
    }

    func testLectureInitialeDepuisLaFixture() async throws {
        let favoris = DemoWorld.gateways().favoris
        let missions = try await favoris.missionsSauvegardees(context: contexte)
        XCTAssertEqual(missions.map(\.missionId), ["demo-mission-002"])
        XCTAssertEqual(FavorisRegles.missionsAffichees(missions, maintenant: DemoWorld.fixedNow).count, 1)
        let etablissements = try await favoris.etablissementsFavoris(context: contexte)
        XCTAssertEqual(etablissements.map(\.id), ["demo-etab-2"])
    }

    func testSauvegarderPuisRetirerSontRelusDansLeMemeJeuDePorts() async throws {
        let favoris = DemoWorld.gateways().favoris
        let apresAjout = try await favoris.sauvegarder(missionId: "demo-mission-001", context: contexte)
        XCTAssertEqual(apresAjout.map(\.missionId), ["demo-mission-001", "demo-mission-002"], "cree_le DESC : la plus récente d'abord")
        let ajoutee = try XCTUnwrap(apresAjout.first)
        XCTAssertEqual(ajoutee.creeLe, "2026-11-02T00:00:00.000Z", "horloge fixée du monde démo")
        XCTAssertEqual(ajoutee.mission?.intitule, "Démonstration · Médecine polyvalente 1")

        // Conflit UNIQUE (soignant, mission) : aucune seconde ligne.
        let doublon = try await favoris.sauvegarder(missionId: "demo-mission-001", context: contexte)
        XCTAssertEqual(doublon, apresAjout)

        let relue = try await favoris.missionsSauvegardees(context: contexte)
        XCTAssertEqual(relue, apresAjout)

        let apresRetrait = try await favoris.retirer(missionId: "demo-mission-002", context: contexte)
        XCTAssertEqual(apresRetrait.map(\.missionId), ["demo-mission-001"])
        let retraitAbsent = try await favoris.retirer(missionId: "demo-mission-999", context: contexte)
        XCTAssertEqual(retraitAbsent, apresRetrait, "retirer une mission non sauvegardée ne change rien")

        let neuf = try await DemoWorld.gateways().favoris.missionsSauvegardees(context: contexte)
        XCTAssertEqual(neuf.map(\.missionId), ["demo-mission-002"], "un nouveau jeu de ports repart de la fixture")
    }

    func testSauvegarderUneMissionAssigneeDuTableauDeBord() async throws {
        let favoris = DemoWorld.gateways().favoris
        let lignes = try await favoris.sauvegarder(missionId: "demo-assignee-001", context: contexte)
        XCTAssertEqual(lignes.first?.mission?.statut, "ASSIGNEE")
        XCTAssertTrue(FavorisRegles.estSauvegardee("demo-assignee-001", dans: lignes))
        XCTAssertFalse(FavorisRegles.missionsAffichees(lignes, maintenant: DemoWorld.fixedNow).contains { $0.missionId == "demo-assignee-001" },
                       "comme le web, une mission non OUVERTE n'est pas listée dans Mes favoris")
    }

    func testMissionInconnueRefusee() async {
        let favoris = DemoWorld.gateways().favoris
        do {
            _ = try await favoris.sauvegarder(missionId: "demo-mission-999", context: contexte)
            XCTFail("clé étrangère : une mission inexistante ne se sauvegarde pas")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unknown)
            XCTAssertEqual(error.message, DemoFavorisGateway.sauvegardeImpossible)
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
        }
    }

    func testRetraitDEtablissementSeulementEtRelu() async throws {
        let favoris = DemoWorld.gateways().favoris
        do {
            _ = try await favoris.basculerEtablissement(id: "demo-etab-1", actif: true, context: contexte)
            XCTFail("décision 8 : aucun ajout d'établissement favori en natif")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
            XCTAssertEqual(error.message, FavorisRegles.ajoutEtablissementNonPropose)
        }
        let inchange = try await favoris.etablissementsFavoris(context: contexte)
        XCTAssertEqual(inchange.map(\.id), ["demo-etab-2"], "le refus n'a rien écrit")

        do {
            _ = try await favoris.basculerEtablissement(id: "demo-etab-999", actif: false, context: contexte)
            XCTFail("établissement inexistant refusé comme le serveur")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unknown)
            XCTAssertEqual(error.message, "Établissement introuvable", "message de fn_toggle_favori_etablissement, verbatim")
        }

        let nonSuivi = try await favoris.basculerEtablissement(id: "demo-etab-1", actif: false, context: contexte)
        XCTAssertEqual(nonSuivi.map(\.id), ["demo-etab-2"], "retirer un établissement non suivi : succès sans effet")
        let apres = try await favoris.basculerEtablissement(id: "demo-etab-2", actif: false, context: contexte)
        XCTAssertEqual(apres, [])
        let relu = try await favoris.etablissementsFavoris(context: contexte)
        XCTAssertEqual(relu, [])
    }

    func testAutreUtilisateurRefuse() async {
        let favoris = DemoWorld.gateways().favoris
        let autre = autreContexte()
        let operations: [(String, () async throws -> Void)] = [
            ("lire", { _ = try await favoris.missionsSauvegardees(context: autre) }),
            ("sauvegarder", { _ = try await favoris.sauvegarder(missionId: "demo-mission-001", context: autre) }),
            ("retirer", { _ = try await favoris.retirer(missionId: "demo-mission-002", context: autre) }),
            ("etablissements", { _ = try await favoris.etablissementsFavoris(context: autre) }),
            ("basculer", { _ = try await favoris.basculerEtablissement(id: "demo-etab-2", actif: false, context: autre) }),
        ]
        for (nom, operation) in operations {
            do {
                try await operation()
                XCTFail("\(nom) : la démo ne sert aucun autre utilisateur")
            } catch let error as JoleneError {
                XCTAssertEqual(error.kind, .demoOnly, nom)
                XCTAssertEqual(error.message, DemoWorld.messageDemoSeulement, nom)
            } catch {
                XCTFail("\(nom) : type d'erreur inattendu : \(error)")
            }
        }
    }
}
