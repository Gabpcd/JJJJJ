import XCTest
@testable import JoleneCore

/// Preuves du monde démo (plan §4.6). Les listes d'identifiants attendues ont été
/// calculées en exécutant `DemoGateway` (mobile-native, tsx) avec l'horloge fixée
/// 2026-11-02T00:00:00Z : le port Swift doit produire exactement les mêmes.
final class DemoWorldTests: XCTestCase {
    static let ordreAttendu = ["demo-mission-001", "demo-mission-004", "demo-mission-007", "demo-mission-010", "demo-mission-013",
                               "demo-mission-016", "demo-mission-019", "demo-mission-022", "demo-mission-025", "demo-mission-028",
                               "demo-mission-002", "demo-mission-005", "demo-mission-008", "demo-mission-011", "demo-mission-014",
                               "demo-mission-017", "demo-mission-020", "demo-mission-023", "demo-mission-026", "demo-mission-029",
                               "demo-mission-003", "demo-mission-006", "demo-mission-009", "demo-mission-012", "demo-mission-015",
                               "demo-mission-018", "demo-mission-021", "demo-mission-024", "demo-mission-027", "demo-mission-030"]

    private func autreContexte() -> MissionReadContext {
        var autre = DemoWorld.context
        autre.userId = "user-1"
        autre.profile.id = "user-1"
        return autre
    }

    private func lister(_ filters: MissionFilters = MissionFilters()) async throws -> [String] {
        try await DemoWorld.gateways().missions.listMissions(context: DemoWorld.context, filters: filters).map(\.id)
    }

    func testHorlogeFixeeEtProfilIdentiquesAuxFixtures() throws {
        let missions = try DemoFixtures.loadMissions()
        let etablissements = try DemoFixtures.loadEtablissements()
        let profil = try DemoFixtures.loadProfile()
        for fixedNow in [missions.fixedNow, etablissements.fixedNow, profil.fixedNow] {
            XCTAssertEqual(fixedNow, "2026-11-02T00:00:00.000Z")
            XCTAssertEqual(PlanningHorlogeParis.instant(fixedNow), DemoWorld.fixedNow)
        }
        XCTAssertEqual(profil.context, DemoWorld.context)
        XCTAssertEqual(missions.missions.count, 30)
        XCTAssertEqual(etablissements.etablissements.map(\.id), ["demo-etab-1", "demo-etab-2", "demo-etab-3"])
        XCTAssertEqual(missions.missions.filter { $0.creneaux.count == 2 }.count, 5, "index % 6 == 5 : 5 missions multi-créneaux")
        XCTAssertEqual(missions.missions[0].record.tauxRistPlafonne, 23)
        XCTAssertEqual(missions.missions[0].record.ristPlafondApplique, true)
        XCTAssertEqual(missions.missions[1].record.tauxRistPlafonne, nil)
        XCTAssertEqual(DemoWorld.gateways().clock.now(), DemoWorld.fixedNow)
    }

    func testTrenteMissionsPourLeContexteDemo() async throws {
        let rows = try await DemoWorld.gateways().missions.listMissions(context: DemoWorld.context, filters: MissionFilters())
        XCTAssertEqual(rows.count, 30)
        XCTAssertEqual(rows.map(\.id), Self.ordreAttendu)
        XCTAssertTrue(rows.allSatisfy { $0.record.intitule.hasPrefix("Démonstration") })
        XCTAssertTrue(rows.allSatisfy(\.planningExact))
        XCTAssertTrue(rows.allSatisfy { $0.etablissement != nil })
        let distances = Dictionary(grouping: rows, by: { $0.record.etablissementId }).mapValues { Set($0.map { $0.distanceKm ?? -1 }) }
        XCTAssertEqual(distances, ["demo-etab-1": [1.4], "demo-etab-2": [5.6], "demo-etab-3": [6.4]])
        XCTAssertEqual(rows.first?.record.tauxHoraireBase, 23)
        XCTAssertEqual(rows.first?.record.netAPayer, nil, "aucun montant n'est calculé côté client")
    }

    func testDetailRelitLaMissionDemandee() async throws {
        let gateways = DemoWorld.gateways()
        let mission = try await gateways.missions.mission(id: "demo-mission-006", context: DemoWorld.context)
        XCTAssertEqual(mission?.id, "demo-mission-006")
        XCTAssertEqual(mission?.creneauxPlanifies.count, 2)
        XCTAssertEqual(mission?.record.typeContratRecherche, "LIBERAL")
        XCTAssertEqual(mission?.distanceKm, 6.4)
        let absente = try await gateways.missions.mission(id: "demo-mission-999", context: DemoWorld.context)
        XCTAssertNil(absente)
    }

    func testAutreUtilisateurRefuseAvecErreurDemoOnly() async throws {
        let gateways = DemoWorld.gateways()
        let autre = autreContexte()
        do {
            _ = try await gateways.missions.listMissions(context: autre, filters: MissionFilters())
            XCTFail("la démo ne doit servir aucun autre utilisateur")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .demoOnly)
            XCTAssertEqual(error.message, DemoWorld.messageDemoSeulement)
        }
        do {
            _ = try await gateways.missions.mission(id: "demo-mission-001", context: autre)
            XCTFail("le détail ne doit pas non plus répondre")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .demoOnly)
        }
        // Un contexte incohérent est refusé avant même le contrôle démo.
        var incoherent = DemoWorld.context
        incoherent.profile.id = "user-1"
        do {
            _ = try await gateways.missions.listMissions(context: incoherent, filters: MissionFilters())
            XCTFail("profil désynchronisé")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
        }
        let profilAutre = try await gateways.missions.profile(userId: "user-1")
        XCTAssertNil(profilAutre)
        let profilDemo = try await gateways.missions.profile(userId: DemoWorld.context.userId)
        XCTAssertEqual(profilDemo, DemoWorld.context.profile)
    }

    func testFiltresValeursAttenduesCalculeesDepuisLePilote() async throws {
        let urgentes = try await lister(MissionFilters(urgentesOnly: true))
        XCTAssertEqual(urgentes, ["demo-mission-001", "demo-mission-016", "demo-mission-011", "demo-mission-026", "demo-mission-006", "demo-mission-021"])

        let taux28 = try await lister(MissionFilters(tauxMin: 28))
        XCTAssertEqual(taux28, ["demo-mission-007", "demo-mission-016", "demo-mission-022", "demo-mission-008", "demo-mission-014",
                                "demo-mission-023", "demo-mission-006", "demo-mission-015", "demo-mission-024", "demo-mission-030"])

        let lilas = ["demo-mission-002", "demo-mission-005", "demo-mission-008", "demo-mission-011", "demo-mission-014",
                     "demo-mission-017", "demo-mission-020", "demo-mission-023", "demo-mission-026", "demo-mission-029"]
        let villeLilas = try await lister(MissionFilters(ville: "lilas"))
        XCTAssertEqual(villeLilas, lilas)
        let codePostal = try await lister(MissionFilters(ville: "93"))
        XCTAssertEqual(codePostal, lilas)
        let etab2 = try await lister(MissionFilters(etablissementId: "demo-etab-2"))
        XCTAssertEqual(etab2, lilas)

        let cdd = try await lister(MissionFilters(typeContrat: .cdd))
        XCTAssertEqual(cdd, ["demo-mission-001", "demo-mission-004", "demo-mission-007", "demo-mission-010", "demo-mission-013",
                             "demo-mission-016", "demo-mission-019", "demo-mission-022", "demo-mission-025", "demo-mission-028",
                             "demo-mission-002", "demo-mission-005", "demo-mission-008", "demo-mission-011", "demo-mission-014",
                             "demo-mission-017", "demo-mission-020", "demo-mission-023", "demo-mission-026", "demo-mission-029"])
        let liberal = try await lister(MissionFilters(typeContrat: .liberal))
        XCTAssertEqual(liberal, ["demo-mission-003", "demo-mission-006", "demo-mission-009", "demo-mission-012", "demo-mission-015",
                                 "demo-mission-018", "demo-mission-021", "demo-mission-024", "demo-mission-027", "demo-mission-030"])

        let nuit = try await lister(MissionFilters(horaire: .nuit))
        XCTAssertEqual(nuit, ["demo-mission-004", "demo-mission-016", "demo-mission-028", "demo-mission-008", "demo-mission-020",
                              "demo-mission-012", "demo-mission-024"])
        let jour = try await lister(MissionFilters(horaire: .jour))
        XCTAssertEqual(jour.count, 23)
        XCTAssertEqual(Set(jour).intersection(nuit), [])
        XCTAssertEqual(jour, ["demo-mission-001", "demo-mission-007", "demo-mission-010", "demo-mission-013", "demo-mission-019",
                              "demo-mission-022", "demo-mission-025", "demo-mission-002", "demo-mission-005", "demo-mission-011",
                              "demo-mission-014", "demo-mission-017", "demo-mission-023", "demo-mission-026", "demo-mission-029",
                              "demo-mission-003", "demo-mission-006", "demo-mission-009", "demo-mission-015", "demo-mission-018",
                              "demo-mission-021", "demo-mission-027", "demo-mission-030"])
        let weekend = try await lister(MissionFilters(horaire: .weekend))
        XCTAssertEqual(weekend, ["demo-mission-004", "demo-mission-013", "demo-mission-019", "demo-mission-005", "demo-mission-020",
                                 "demo-mission-026", "demo-mission-006", "demo-mission-012", "demo-mission-018", "demo-mission-024",
                                 "demo-mission-027"])

        let rayon5 = try await lister(MissionFilters(rayonKm: 5))
        XCTAssertEqual(rayon5, ["demo-mission-001", "demo-mission-004", "demo-mission-007", "demo-mission-010", "demo-mission-013",
                                "demo-mission-016", "demo-mission-019", "demo-mission-022", "demo-mission-025", "demo-mission-028"])

        let combo = try await lister(MissionFilters(tauxMin: 25, urgentesOnly: true, horaire: .jour))
        XCTAssertEqual(combo, ["demo-mission-011", "demo-mission-006", "demo-mission-021"])
    }

    func testPresentationDesMissionsDemo() async throws {
        let rows = try await DemoWorld.gateways().missions.listMissions(context: DemoWorld.context, filters: MissionFilters())
        let parId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        XCTAssertEqual(MissionPresentation.remuneration(parId["demo-mission-001"]!), "23,00\u{00A0}€/h")
        XCTAssertEqual(MissionPresentation.remuneration(parId["demo-mission-008"]!), "30,00\u{00A0}€/h")
        XCTAssertEqual(MissionPresentation.periode(parId["demo-mission-001"]!), "03/11/2026 · 08:00–16:00")
        XCTAssertEqual(MissionPresentation.periode(parId["demo-mission-004"]!), "06/11/2026 → 07/11/2026 · 1 créneau")
        XCTAssertEqual(MissionPresentation.periode(parId["demo-mission-006"]!), "08/11/2026 → 10/11/2026 · 2 créneaux")
        XCTAssertEqual(MissionPresentation.periode(parId["demo-mission-012"]!), "14/11/2026 → 17/11/2026 · 2 créneaux")
    }

    func testAuthDemoEnMemoireEtRole() async throws {
        let gateways = DemoWorld.gateways()
        let avant = try await gateways.auth.restoreSession()
        XCTAssertNil(avant, "aucune session au premier lancement")
        do {
            _ = try await gateways.auth.signIn(email: "", password: "x")
            XCTFail("email vide refusé")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .invalidCredentials)
        }
        do {
            _ = try await gateways.auth.signIn(email: "a@b.c", password: "")
            XCTFail("mot de passe vide refusé")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .invalidCredentials)
        }
        let encoreRien = try await gateways.auth.restoreSession()
        XCTAssertNil(encoreRien, "un refus n'ouvre pas de session")
        let user = try await gateways.auth.signIn(email: "n-importe-qui@example.invalid", password: "mot-de-passe")
        XCTAssertEqual(user, DemoWorld.user)
        XCTAssertEqual(user.id, DemoWorld.context.userId)
        XCTAssertNotNil(user.emailConfirmedAt)
        XCTAssertEqual(user.appMetadataRole, "SOIGNANT")
        let restauree = try await gateways.auth.restoreSession()
        XCTAssertEqual(restauree, user)
        let role = try await gateways.role.currentRole()
        XCTAssertEqual(role, RoleResult(role: "SOIGNANT", etablissementId: nil))
        XCTAssertEqual(MobileAccess.validate(user: user, role: role.role), .allowed)
        try await gateways.auth.signOut()
        let apres = try await gateways.auth.restoreSession()
        XCTAssertNil(apres)
        // Un nouveau jeu de ports repart d'une session vierge.
        let neuf = try await DemoWorld.gateways().auth.restoreSession()
        XCTAssertNil(neuf)
    }

    // MARK: - Lot 1 (T1)

    /// Ports du lot 1 que leur tranche n'a pas encore câblés : SOURCE UNIQUE de la liste. Chaque
    /// PR qui câble un port le câble dans les deux mondes et le retire d'ici. Le monde Supabase
    /// n'a pas de liste propre : `SupabaseGatewaysTests.testAucunPortNonCable` compare
    /// `SupabaseGateways.make(client:).unwiredPorts` à `DemoWorld.gateways().unwiredPorts`, si
    /// bien qu'un port câblé dans un seul monde rougit l'un des deux tests. Critère de sortie de
    /// T12 (blueprint §2.2) : liste vide, `unwiredPorts.isEmpty` dans les deux mondes.
    static let portsEnAttenteLot1 = ["candidature", "presence", "mesMissions",
                                     "recovery", "justificatifs"]

    func testAucunPortNonCable() {
        let gateways = DemoWorld.gateways()
        XCTAssertEqual(gateways.unwiredPorts, Self.portsEnAttenteLot1,
                       "tout port livré doit être câblé dans DemoWorld.gateways() dans la même PR")
        XCTAssertTrue(gateways.audit is DemoAuditGateway)
        XCTAssertTrue(gateways.flags is DemoFlagsGateway)
        XCTAssertTrue(gateways.dashboard is DemoDashboardGateway, "T3 câble le tableau de bord")
        XCTAssertTrue(gateways.compte is DemoAccountGateway, "T8 câble la suppression de compte")
        XCTAssertTrue(gateways.favoris is DemoFavorisGateway, "T4b câble les favoris")
        XCTAssertEqual(DemoWorld.gateways(drapeaux: [:]).unwiredPorts, Self.portsEnAttenteLot1)
        XCTAssertEqual(gateways.clock.now(), DemoWorld.fixedNow)
    }

    func testAuditDemoJournaliseEnMemoireSansReseau() async throws {
        let gateways = DemoWorld.gateways()
        let audit = try XCTUnwrap(gateways.audit as? DemoAuditGateway)
        let connexion = try await audit.connexion()
        let activite = try await audit.activite()
        let ecriture = try await audit.ecrire(action: .missionAssignation, typeRessource: "mission",
                                              idRessource: "demo-mission-001", details: ["intitule": "Démonstration"],
                                              context: DemoWorld.context)
        let deconnexion = try await audit.deconnexion()
        XCTAssertEqual([connexion, activite, ecriture, deconnexion], [.enregistre, .enregistre, .enregistre, .enregistre])
        let journal = await audit.journal()
        XCTAssertEqual(journal, ["CONNEXION", "ACTIVITE", "MISSION_ASSIGNATION mission demo-mission-001", "DECONNEXION"])
        let autreMonde = await (DemoWorld.gateways().audit as? DemoAuditGateway)?.journal()
        XCTAssertEqual(autreMonde, [], "chaque jeu de ports démo repart d'un journal vierge")
    }

    func testAuditDemoRefuseUnAutreUtilisateurEtUneRessourceVide() async {
        let audit = DemoAuditGateway()
        do {
            _ = try await audit.ecrire(action: .missionAssignation, typeRessource: "mission", idRessource: "demo-mission-001",
                                       details: [:], context: autreContexte())
            XCTFail("la démo n'écrit pour aucun autre utilisateur")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .demoOnly)
            XCTAssertEqual(error.message, DemoWorld.messageDemoSeulement)
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
        }
        do {
            _ = try await audit.ecrire(action: .missionAssignation, typeRessource: "mission", idRessource: " ",
                                       details: [:], context: DemoWorld.context)
            XCTFail("une ressource vide n'est jamais auditée")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
        }
        let journal = await audit.journal()
        XCTAssertEqual(journal, [], "aucun refus n'est journalisé")
    }

    func testDrapeauxDemoFailOpenEtSurchargesExplicites() async {
        let parDefaut = DemoWorld.gateways().flags
        for ecran in EcranNatif.allCases {
            let actif = await parDefaut.ecranActif(ecran)
            XCTAssertTrue(actif, "\(ecran.cle) : défaut fail-open en démo")
        }
        let defautExplicite = await parDefaut.ecranActif(cle: "cle_inconnue", defaut: false)
        XCTAssertFalse(defautExplicite, "sans surcharge, le défaut demandé est rendu")

        let surcharge = DemoWorld.gateways(drapeaux: [EcranNatif.missions.cle: false]).flags
        let missions = await surcharge.ecranActif(.missions)
        let accueil = await surcharge.ecranActif(.accueil)
        XCTAssertFalse(missions, "surcharge de lancement (-JOLENE_FLAG_…, T9) honorée")
        XCTAssertTrue(accueil)
    }
}
