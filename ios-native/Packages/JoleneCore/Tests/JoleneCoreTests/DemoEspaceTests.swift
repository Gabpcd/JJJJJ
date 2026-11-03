import XCTest
@testable import JoleneCore

/// Monde démo à deux espaces (lot 5, T2a ; §2.10, D20) : `-JOLENE_DEMO_ESPACE etablissement` ouvre
/// l'espace établissement fictif (`demo-etablissement` → `demo-etab-1`), le compte soignant fictif
/// restant joignable par son propre email dans la même session (déconnexion → connexion soignant).
/// Aucun réseau ; `DemoWorld.gateways()` du lot 0 est inchangé.
final class DemoEspaceTests: XCTestCase {
    private let motDePasse = "demonstration"

    // MARK: Arguments de lancement (DEBUG)

    func testArgumentsDeLancementDeLEspaceDemo() {
        XCTAssertEqual(DemoEspaceLancement.espace(arguments: []), .soignant)
        XCTAssertEqual(DemoEspaceLancement.espace(arguments: ["Jolene", "-JOLENE_MODE", "demo"]), .soignant)
        XCTAssertEqual(DemoEspaceLancement.espace(arguments: ["-JOLENE_DEMO_ESPACE", "etablissement"]), .etablissement(.init()))
        XCTAssertEqual(DemoEspaceLancement.espace(arguments: ["-JOLENE_DEMO_ESPACE", "soignant"]), .soignant)
        XCTAssertEqual(DemoEspaceLancement.espace(arguments: ["-JOLENE_DEMO_ESPACE", "inconnu"]), .soignant,
                       "valeur illisible : espace du lot 0")
        XCTAssertEqual(DemoEspaceLancement.espace(arguments: ["-JOLENE_DEMO_ESPACE"]), .soignant)
        XCTAssertEqual(
            DemoEspaceLancement.espace(arguments: ["-JOLENE_DEMO_ESPACE", "etablissement", "-JOLENE_DEMO_ROLE_ETAB", "LECTURE_SEULE",
                                                   "-JOLENE_DEMO_LEGACY", "1", "-JOLENE_DEMO_BLOCAGE", "1"]),
            .etablissement(.init(role: .lectureSeule, legacy: true, blocage: true)))
        XCTAssertEqual(DemoEspaceLancement.espace(arguments: ["-JOLENE_DEMO_ESPACE", "etablissement", "-JOLENE_DEMO_ROLE_ETAB", "RH"]),
                       .etablissement(.init(role: .rh)))
        XCTAssertEqual(DemoEspaceLancement.espace(arguments: ["-JOLENE_DEMO_ESPACE", "etablissement", "-JOLENE_DEMO_LEGACY", "0"]),
                       .etablissement(.init(legacy: false)))
        XCTAssertEqual(DemoEspaceLancement.espace(arguments: ["-JOLENE_DEMO_ROLE_ETAB", "RH", "-JOLENE_DEMO_LEGACY", "1"]), .soignant,
                       "sans -JOLENE_DEMO_ESPACE etablissement, les variantes sont ignorées")
    }

    // MARK: Monde soignant inchangé

    func testEspaceSoignantIdentiqueAuMondeDuLot0() async throws {
        let gateways = DemoWorld.gateways(espace: .soignant)
        XCTAssertEqual(gateways.unwiredPorts, DemoWorldTests.portsEnAttenteLot1)
        XCTAssertEqual(gateways.etablissement.unwiredPorts, DemoWorldTests.portsEnAttenteLot5)
        let user = try await gateways.auth.signIn(email: DemoEspace.emailEtablissement, password: motDePasse)
        XCTAssertEqual(user, DemoWorld.user, "monde soignant : tout email ouvre le compte soignant fictif")
    }

    // MARK: Espace établissement

    func testEmailDuCompteEtablissementIdentiqueALaFixture() throws {
        let fichier = try DemoFixtures.loadEtablissementDemo()
        XCTAssertEqual(DemoEspace.emailEtablissement, fichier.utilisateur.email)
        XCTAssertEqual(DemoEspace.emailEtablissement, fichier.utilisateurLegacy.email)
        XCTAssertNotEqual(DemoEspace.emailEtablissement, DemoWorld.context.email)
    }

    func testPortsDuMondeEtablissementCablesCommeLeMondeDuLot0() {
        let gateways = DemoWorld.gateways(espace: .etablissement(.init()))
        XCTAssertEqual(gateways.unwiredPorts, DemoWorldTests.portsEnAttenteLot1)
        XCTAssertEqual(gateways.etablissement.unwiredPorts, DemoWorldTests.portsEnAttenteLot5)
        XCTAssertTrue(gateways.etablissement.session is DemoEtabSessionGateway)
        XCTAssertTrue(gateways.role is DemoRoleEspaceGateway)
        XCTAssertEqual(gateways.clock.now(), DemoWorld.fixedNow)
    }

    func testConnexionEtablissementOuvreLEspaceDemo() async throws {
        let controller = SessionController(gateways: DemoWorld.gateways(espace: .etablissement(.init())))
        _ = await controller.start()
        let state = await controller.signIn(email: "  \(DemoEspace.emailEtablissement)  ", password: motDePasse)
        let snapshot = try XCTUnwrap(state.snapshotEtablissement, "espace établissement attendu, obtenu \(state)")
        let fichier = try DemoFixtures.loadEtablissementDemo()
        XCTAssertEqual(snapshot.user.id, DemoEtablissementWorld.userId)
        XCTAssertEqual(snapshot.user.appMetadataRole, "ADMIN_ETABLISSEMENT")
        XCTAssertEqual(snapshot.role, RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: fichier.etablissement.id))
        XCTAssertEqual(snapshot.context.etablissementId, "demo-etab-1")
        XCTAssertEqual(snapshot.context.roleEtab, .proprietaire)
        XCTAssertEqual(snapshot.context.permissions, try XCTUnwrap(DemoFixtures.loadPermissionsEtab().roles["PROPRIETAIRE"]))
        XCTAssertEqual(snapshot.etablissement, fichier.etablissement)
        XCTAssertNil(snapshot.etablissement.bloqueAutoLe)
    }

    func testCompteLegacyOuvreLeMemeEspaceEtLeMemeEtablissement() async throws {
        let controller = SessionController(gateways: DemoWorld.gateways(espace: .etablissement(.init(legacy: true))))
        _ = await controller.start()
        let state = await controller.signIn(email: DemoEspace.emailEtablissement, password: motDePasse)
        let snapshot = try XCTUnwrap(state.snapshotEtablissement, "legacy confirmé attendu, obtenu \(state)")
        XCTAssertEqual(snapshot.user.appMetadataRole, "ETABLISSEMENT")
        XCTAssertNil(snapshot.user.appMetadataEtablissementId)
        XCTAssertEqual(snapshot.context.etablissementId, "demo-etab-1",
                       "le rôle démo sert l'établissement confirmé, comme fn_get_my_role pour un legacy réel (revue T1, mineur 7)")
        XCTAssertEqual(snapshot.context.roleEtab, .proprietaire)
        XCTAssertEqual(snapshot.etablissement.nom, try DemoFixtures.loadEtablissementDemo().etablissement.nom)
    }

    func testRolesDEquipeDemoServisParLaFixture() async throws {
        let fichier = try DemoFixtures.loadPermissionsEtab()
        for role in RoleEtab.connus {
            let controller = SessionController(gateways: DemoWorld.gateways(espace: .etablissement(.init(role: role))))
            _ = await controller.start()
            let state = await controller.signIn(email: DemoEspace.emailEtablissement, password: motDePasse)
            let snapshot = try XCTUnwrap(state.snapshotEtablissement, "\(role.brut) : obtenu \(state)")
            XCTAssertEqual(snapshot.context.roleEtab, role)
            XCTAssertEqual(snapshot.context.permissions, fichier.roles[role.brut], role.brut)
        }
    }

    func testRoleDemoInconnuNOuvreJamaisLEspace() async {
        let controller = SessionController(gateways: DemoWorld.gateways(espace: .etablissement(.init(role: .inconnu("ADMIN_PLATEFORME")))))
        _ = await controller.start()
        let state = await controller.signIn(email: DemoEspace.emailEtablissement, password: motDePasse)
        XCTAssertEqual(state, .blocked(.unsupportedRole("ADMIN_PLATEFORME")))
    }

    func testBlocageDemoPorteLHorodatageDeLaFixture() async throws {
        let controller = SessionController(gateways: DemoWorld.gateways(espace: .etablissement(.init(blocage: true))))
        _ = await controller.start()
        let state = await controller.signIn(email: DemoEspace.emailEtablissement, password: motDePasse)
        XCTAssertEqual(state.snapshotEtablissement?.etablissement.bloqueAutoLe, "2026-11-01T07:00:00.000Z")
    }

    func testEmailSoignantPuisEtablissementDansLaMemeSession() async throws {
        let controller = SessionController(gateways: DemoWorld.gateways(espace: .etablissement(.init())))
        _ = await controller.start()
        let soignant = await controller.signIn(email: DemoWorld.context.email ?? "", password: motDePasse)
        XCTAssertEqual(soignant.snapshot?.user, DemoWorld.user, "le compte soignant fictif reste joignable par son email")
        XCTAssertNil(soignant.snapshotEtablissement)
        let epochSoignant = await controller.epoch
        _ = await controller.signOut()
        let etab = await controller.signIn(email: DemoEspace.emailEtablissement, password: motDePasse)
        XCTAssertEqual(etab.snapshotEtablissement?.epoch, epochSoignant + 2)
        _ = await controller.signOut()
        let encoreSoignant = await controller.signIn(email: DemoWorld.context.email ?? "", password: motDePasse)
        XCTAssertNotNil(encoreSoignant.snapshot)
        XCTAssertEqual(encoreSoignant.snapshot?.epoch, epochSoignant + 4)
    }

    func testRoleDemoSelonLIdentiteDeLaSession() async throws {
        let gateways = DemoWorld.gateways(espace: .etablissement(.init(legacy: true)))
        _ = try await gateways.auth.signIn(email: DemoEspace.emailEtablissement, password: motDePasse)
        let roleEtab = try await gateways.role.currentRole()
        XCTAssertEqual(roleEtab, RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "demo-etab-1"))
        try await gateways.auth.signOut()
        _ = try await gateways.auth.signIn(email: DemoWorld.context.email ?? "", password: motDePasse)
        let roleSoignant = try await gateways.role.currentRole()
        XCTAssertEqual(roleSoignant, RoleResult(role: "SOIGNANT", etablissementId: nil))
        try await gateways.auth.signOut()
        do {
            _ = try await gateways.role.currentRole()
            XCTFail("aucune session démo : aucun rôle servi")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
        }
    }

    func testIdentifiantsVidesRefusesCommeAuLot0() async {
        let gateways = DemoWorld.gateways(espace: .etablissement(.init()))
        do {
            _ = try await gateways.auth.signIn(email: " ", password: motDePasse)
            XCTFail("email vide refusé")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .invalidCredentials)
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
        }
        let session = try? await gateways.auth.restoreSession()
        XCTAssertNil(session ?? nil)
    }

    // MARK: Présentation

    func testLibellesDesRolesDEquipeReprisDuWeb() throws {
        // `src/pages/EquipeEtablissement.tsx` l.45-49 (`ROLE_INFO`, libellés non juridiques).
        XCTAssertEqual(RoleEtab.connus.map(\.libelle),
                       ["Propriétaire", "Admin groupe", "Ressources humaines", "Pointage uniquement", "Lecture seule"])
        try SourceWebLot5.verifier("src/pages/EquipeEtablissement.tsx",
                                   contient: RoleEtab.connus.map { "\($0.brut): { label: '\($0.libelle)'" })
        XCTAssertEqual(RoleEtab.inconnu("ADMIN_PLATEFORME").libelle, "ADMIN_PLATEFORME", "valeur inconnue affichée telle quelle")
    }
}
