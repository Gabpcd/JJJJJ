import XCTest
@testable import JoleneCore

/// Permissions démo par rôle (lot 5 T1, §2.7) : la fixture est générée depuis le `CASE` SQL de
/// `fn_a_permission_etablissement` par `export-demo-fixtures.mjs` ; elle doit donner exactement les
/// rôles attendus du blueprint. Aucune correspondance n'est écrite dans le code livré.
final class DemoEtabPermissionsFixtureTests: XCTestCase {
    func testCinqRolesEtOnzeClesCommeLeServeur() throws {
        let fichier = try DemoFixtures.loadPermissionsEtab()
        XCTAssertEqual(fichier.fixedNow, "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(fichier.cles, PermissionsEtabDecodingTests.onzeCles)
        XCTAssertEqual(Set(fichier.roles.keys), Set(RoleEtab.connus.map(\.brut)))
        let accordees = { (role: RoleEtab) in fichier.roles[role.brut]?.accordees }
        XCTAssertEqual(accordees(.proprietaire), PermissionEtab.allCases)
        XCTAssertEqual(accordees(.adminGroupe), PermissionEtab.allCases.filter { $0 != .gererEquipe && $0 != .supprimerCompte })
        XCTAssertEqual(accordees(.rh), [.missions, .candidatures, .contrats, .pointage, .rh, .lecture])
        XCTAssertEqual(accordees(.pointageOnly), [.pointage, .lecture])
        XCTAssertEqual(accordees(.lectureSeule), [.lecturePaiement, .lecture])
    }
}

/// Monde démo de l'espace établissement (lot 5 T1, §2.10) : formes serveur rejouées depuis les
/// fixtures, aucun réseau, tout autre utilisateur que `demo-etablissement` refusé.
final class DemoEtablissementWorldTests: XCTestCase {
    private let identiteEtablissement: @Sendable () async -> String? = { DemoEtablissementWorld.userId }

    private func session(_ configuration: DemoEtablissementWorld.Configuration = .init(),
                         identite: (@Sendable () async -> String?)? = nil) -> DemoEtabSessionGateway {
        DemoEtabSessionGateway(configuration: configuration, identite: identite ?? identiteEtablissement)
    }

    private func contexte(userId: String = DemoEtablissementWorld.userId, role: RoleEtab = .proprietaire) -> EtablissementReadContext {
        EtablissementReadContext(userId: userId, etablissementId: "demo-etab-1", roleEtab: role, permissions: .aucune, epoch: 1)
    }

    private func refuseDemoOnly(_ appel: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await appel()
            XCTFail("la démo ne sert aucun autre utilisateur", file: file, line: line)
        } catch let error as JoleneError {
            XCTAssertEqual(error, JoleneError(.demoOnly, DemoEtablissementWorld.messageDemoSeulement), file: file, line: line)
        } catch {
            XCTFail("type d'erreur inattendu : \(error)", file: file, line: line)
        }
    }

    func testFixtureEtablissementCoherenteAvecLeMondeSoignant() throws {
        let fichier = try DemoFixtures.loadEtablissementDemo()
        XCTAssertEqual(fichier.fixedNow, "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(PlanningHorlogeParis.instant(fichier.fixedNow), DemoWorld.fixedNow)
        // Un seul nom par identifiant : l'établissement démo est le premier établissement fictif du monde soignant.
        let soignant = try XCTUnwrap(DemoFixtures.loadEtablissements().etablissements.first)
        XCTAssertEqual(fichier.etablissement.id, soignant.id)
        XCTAssertEqual(fichier.etablissement.nom, soignant.nom)
        XCTAssertEqual(fichier.etablissement.peutPublierMissions, true)
        XCTAssertEqual(fichier.etablissement.statutVerification, "VERIFIE")
        XCTAssertNil(fichier.etablissement.bloqueAutoLe)
        var attenduBloque = fichier.etablissement
        attenduBloque.bloqueAutoLe = "2026-11-01T07:00:00.000Z"
        XCTAssertEqual(fichier.etablissementBloque, attenduBloque, "la variante bloquée ne diffère que par bloque_auto_le")
    }

    func testUtilisateursMembreEtLegacy() throws {
        let membre = try DemoEtablissementWorld.utilisateur()
        XCTAssertEqual(membre.id, DemoEtablissementWorld.userId)
        XCTAssertEqual(membre.appMetadataRole, "ADMIN_ETABLISSEMENT")
        XCTAssertEqual(membre.appMetadataEtablissementId, "demo-etab-1")
        XCTAssertEqual(membre.emailConfirmedAt, DemoWorld.fixedNow)
        XCTAssertTrue(membre.email?.hasSuffix("@example.invalid") ?? false)
        let legacy = try DemoEtablissementWorld.utilisateur(.init(legacy: true))
        XCTAssertEqual(legacy.id, DemoEtablissementWorld.userId)
        XCTAssertEqual(legacy.appMetadataRole, "ETABLISSEMENT", "alias signé legacy")
        XCTAssertNil(legacy.appMetadataEtablissementId, "legacy : aucun etablissement_id dans app_metadata")
        XCTAssertEqual(RoleResolution.normalize(legacy.appMetadataRole), UserRole.adminEtablissement.rawValue)
    }

    func testPermissionsParRoleDepuisLaFixture() async throws {
        let fichier = try DemoFixtures.loadPermissionsEtab()
        for role in RoleEtab.connus {
            let lu = try await session(.init(role: role)).permissions(etablissementId: nil)
            XCTAssertEqual(lu, PermissionsEtabResult(success: true, role: role, etablissementId: "demo-etab-1",
                                                     permissions: try XCTUnwrap(fichier.roles[role.brut])), role.brut)
        }
        let pointage = try await session(.init(role: .pointageOnly)).permissions(etablissementId: nil)
        XCTAssertEqual(pointage.permissions.accordees, [.pointage, .lecture])
    }

    func testLegacyToujoursProprietaire() async throws {
        let configuration = DemoEtablissementWorld.Configuration(role: .lectureSeule, legacy: true)
        XCTAssertEqual(configuration.roleServi, .proprietaire, "fn_role_etablissement_courant : repli PROPRIETAIRE")
        let lu = try await session(configuration).permissions(etablissementId: nil)
        XCTAssertEqual(lu.role, .proprietaire)
        XCTAssertEqual(lu.permissions.accordees, PermissionEtab.allCases)
    }

    func testAutreEtablissementDemandeSansRole() async throws {
        let lu = try await session().permissions(etablissementId: "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b")
        XCTAssertEqual(lu, PermissionsEtabResult(success: true, role: nil, etablissementId: nil, permissions: .aucune))
        let meme = try await session().permissions(etablissementId: "demo-etab-1")
        XCTAssertEqual(meme.role, .proprietaire)
    }

    func testRoleInconnuServiSansPermission() async throws {
        let lu = try await session(.init(role: .inconnu("ADMIN_PLATEFORME"))).permissions(etablissementId: nil)
        XCTAssertEqual(lu.role, .inconnu("ADMIN_PLATEFORME"))
        XCTAssertEqual(lu.permissions, .aucune)
    }

    func testProfilEtVarianteBloquee() async throws {
        let profil = try await session().profil()
        XCTAssertEqual(profil.id, "demo-etab-1")
        XCTAssertNil(profil.bloqueAutoLe)
        let bloque = try await session(.init(blocage: true)).profil()
        XCTAssertEqual(bloque.bloqueAutoLe, "2026-11-01T07:00:00.000Z")
    }

    func testAutreUtilisateurOuSansSessionRefuse() async {
        for identite in [{ DemoWorld.context.userId }, { nil }, { "user-1" }] as [@Sendable () async -> String?] {
            let gateway = session(identite: identite)
            await refuseDemoOnly { _ = try await gateway.permissions(etablissementId: nil) }
            await refuseDemoOnly { _ = try await gateway.profil() }
        }
    }

    func testAuditDemoJournaliseEtRefuseUnAutreContexte() async throws {
        let audit = DemoEtabAuditGateway()
        let resultat = try await audit.consultation(page: .tableauDeBord, context: contexte())
        XCTAssertEqual(resultat, .enregistre)
        await refuseDemoOnly { _ = try await audit.consultation(page: .tableauDeBord, context: self.contexte(userId: "user-1")) }
        do {
            _ = try await audit.consultation(page: .tableauDeBord, context: contexte(role: .inconnu("ADMIN_PLATEFORME")))
            XCTFail("un contexte incohérent n'est jamais audité")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
        }
        let journal = await audit.journal()
        XCTAssertEqual(journal, ["DONNEES_PERSO_CONSULTATION etablissement demo-etablissement dashboard_etablissement"],
                       "aucun refus n'est journalisé")
        let neuf = await DemoEtabAuditGateway().journal()
        XCTAssertEqual(neuf, [])
    }

    func testMondeDemoCableSessionEtAuditLeRestePourSesTranches() async throws {
        let ports = DemoEtablissementWorld.gateways(identite: identiteEtablissement)
        XCTAssertTrue(ports.session is DemoEtabSessionGateway)
        XCTAssertTrue(ports.audit is DemoEtabAuditGateway)
        XCTAssertEqual(ports.unwiredPorts, DemoWorldTests.portsEnAttenteLot5)
        let lu = try await ports.session.permissions(etablissementId: nil)
        XCTAssertEqual(lu.role, .proprietaire)
    }

    func testDemoWorldBrancheLIdentiteDeLaSessionDemo() async throws {
        // Le jeu de ports du mode démo soignant porte aussi les ports établissement : la session
        // démo courante est celle du soignant fictif, donc refusée ; sans session, refusée aussi.
        let gateways = DemoWorld.gateways()
        await refuseDemoOnly { _ = try await gateways.etablissement.session.permissions(etablissementId: nil) }
        _ = try await gateways.auth.signIn(email: "n-importe-qui@example.invalid", password: "mot-de-passe")
        await refuseDemoOnly { _ = try await gateways.etablissement.session.profil() }
    }
}
