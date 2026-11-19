import XCTest
@testable import JoleneCore

/// Règles pures de l'espace (lot 5, T2a ; `docs/mobile-swift/LOT5_PLAN.md` §2.2, D2, D3) :
/// - `EspaceResolution.espace(user:role:)` remplace `MobileAccess.validate` (fichier gelé, conservé tel
///   quel) dans le contrôleur de session : soignant, établissement (membre et alias legacy), ou blocage ;
/// - `EspaceResolution.perimetre(candidat:permissions:)` : le périmètre est celui que confirme
///   `fn_mes_permissions_etab(NULL)`, jamais le candidat (`fn_get_my_role`, `app_metadata`, repli `user.id`).
///
/// Les cinq cas de `src/hooks/useEtablissementScope.test.ts` sont rejoués en sémantique native : le
/// candidat n'est jamais une valeur de filtre, il est seulement comparé à la réponse serveur.
final class EspaceResolutionTests: XCTestCase {
    private let confirmeLe = Date(timeIntervalSince1970: 1_700_000_000)

    private func utilisateur(_ id: String = "utilisateur-id", role: String? = nil, etablissementId: String? = nil,
                             confirme: Bool = true) -> AuthenticatedUser {
        AuthenticatedUser(id: id, email: "\(id)@example.invalid", emailConfirmedAt: confirme ? confirmeLe : nil,
                          appMetadataRole: role, appMetadataEtablissementId: etablissementId)
    }

    private func reponse(success: Bool = true, role: String? = "PROPRIETAIRE", etablissementId: String? = "etab-1",
                         permissions: Set<PermissionEtab> = [.lecture]) -> PermissionsEtabResult {
        PermissionsEtabResult(success: success, role: role.map(RoleEtab.init(brut:)), etablissementId: etablissementId,
                              permissions: PermissionsEtab(accordees: permissions))
    }

    // MARK: - Espace

    func testEspaceSoignantEtablissementOuBlocage() {
        XCTAssertEqual(EspaceResolution.espace(user: nil, role: "SOIGNANT"), .bloque(.signInRequired))
        XCTAssertEqual(EspaceResolution.espace(user: utilisateur(confirme: false), role: "SOIGNANT"), .bloque(.emailUnconfirmed))
        XCTAssertEqual(EspaceResolution.espace(user: utilisateur(), role: "SOIGNANT"), .soignant)
        XCTAssertEqual(EspaceResolution.espace(user: utilisateur(), role: "ADMIN_ETABLISSEMENT"), .etablissement)
        XCTAssertEqual(EspaceResolution.espace(user: utilisateur(), role: "ETABLISSEMENT"), .etablissement,
                       "alias legacy signé : même espace que le membre")
        for raw in ["ADMIN_PLATEFORME", "ADMIN_GROUPE"] {
            XCTAssertEqual(EspaceResolution.espace(user: utilisateur(), role: raw), .bloque(.unsupportedRole(raw)))
        }
        XCTAssertEqual(EspaceResolution.espace(user: utilisateur(), role: nil), .bloque(.unsupportedRole(nil)))
        XCTAssertEqual(EspaceResolution.espace(user: utilisateur(), role: "INCONNU"), .bloque(.unsupportedRole("INCONNU")))
    }

    func testIsNativelyServedOuvertALEtablissementSeulementPourLeLot5() {
        // D3 : exception consignée dans PRINCIPES §2 — une API figée à `false` serait un piège silencieux.
        XCTAssertTrue(UserRole.soignant.isNativelyServed)
        XCTAssertTrue(UserRole.adminEtablissement.isNativelyServed)
        XCTAssertTrue(UserRole.etablissementLegacy.isNativelyServed)
        XCTAssertFalse(UserRole.adminPlateforme.isNativelyServed)
        XCTAssertFalse(UserRole.adminGroupe.isNativelyServed)
    }

    func testMobileAccessGeleRefuseToujoursLEtablissement() {
        // `Account.swift` est un fichier gelé : sa règle du lot 0 ne change pas, seul le contrôleur cesse de l'appeler.
        XCTAssertEqual(MobileAccess.validate(user: utilisateur(), role: "ADMIN_ETABLISSEMENT"),
                       .unsupportedRole("ADMIN_ETABLISSEMENT"))
        XCTAssertEqual(MobileAccess.validate(user: utilisateur(), role: "SOIGNANT"), .allowed)
    }

    // MARK: - Cinq cas de useEtablissementScope.test.ts

    /// « ne transforme jamais une erreur de rôle en scope user.id » : RPC en échec et aucun raccourci
    /// signé → aucun rôle, espace bloqué ; avec l'alias legacy signé, le candidat `user.id` n'est qu'un
    /// candidat, et un périmètre serveur différent le refuse (jamais `user.id` comme scope).
    func testErreurDeRoleJamaisTransformeeEnScopeUserId() {
        let sansRaccourci = utilisateur()
        XCTAssertNil(RoleResolution.resolve(server: nil, user: sansRaccourci))
        XCTAssertEqual(EspaceResolution.espace(user: sansRaccourci, role: nil), .bloque(.unsupportedRole(nil)))

        let legacy = utilisateur(role: "ETABLISSEMENT")
        let candidat = RoleResolution.resolve(server: nil, user: legacy)?.etablissementId
        XCTAssertEqual(candidat, "utilisateur-id", "repli legacy borné à l'alias signé, candidat seulement")
        XCTAssertEqual(EspaceResolution.perimetre(candidat: candidat, permissions: reponse(etablissementId: "etab-serveur")),
                       .divergent, "le serveur sert un autre établissement : jamais le scope user.id")
    }

    /// « exposer le parcours pour distinguer exploration et rattachement perdu » : le natif n'a pas de
    /// `parcours` ; le rattachement perdu est la réponse serveur sans rôle (membre révoqué, l.42277-42283).
    func testRattachementPerduEstUnRefusSansAcces() {
        XCTAssertEqual(EspaceResolution.perimetre(candidat: "etab-1", permissions: reponse(role: nil, etablissementId: nil)),
                       .sansAcces)
        XCTAssertEqual(EspaceResolution.perimetre(candidat: nil, permissions: reponse(role: nil, etablissementId: nil)),
                       .sansAcces)
        XCTAssertEqual(EspaceResolution.perimetre(candidat: nil, permissions: reponse(role: "RH", etablissementId: nil)),
                       .sansAcces, "un rôle sans établissement n'ouvre rien")
    }

    /// « exige etablissement_id pour un membre ADMIN_ETABLISSEMENT » : aucun repli `user.id` pour un membre
    /// (non legacy) ; sans candidat, c'est le périmètre serveur qui décide.
    func testMembreSansEtablissementIdNAJamaisLeRepliUserId() {
        let membre = utilisateur(role: "ADMIN_ETABLISSEMENT")
        let candidat = RoleResolution.resolve(server: RoleResult(role: "ADMIN_ETABLISSEMENT"), user: membre)?.etablissementId
        XCTAssertNil(candidat)
        XCTAssertEqual(EspaceResolution.perimetre(candidat: candidat, permissions: reponse(etablissementId: "etab-serveur")),
                       .confirme(etablissementId: "etab-serveur", role: .proprietaire, permissions: PermissionsEtab(accordees: [.lecture])))
    }

    /// « utilise en priorité l'identifiant explicite résolu par le serveur » : `fn_get_my_role` gagne sur
    /// `app_metadata` ; il doit égaler le périmètre de `fn_mes_permissions_etab`.
    func testIdentifiantServeurPrioritaireEtCompareAuPerimetre() {
        let membre = utilisateur(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-perime")
        let candidat = RoleResolution.resolve(server: RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etablissement-explicite"),
                                              user: membre)?.etablissementId
        XCTAssertEqual(candidat, "etablissement-explicite")
        XCTAssertEqual(EspaceResolution.perimetre(candidat: candidat, permissions: reponse(etablissementId: "etablissement-explicite")),
                       .confirme(etablissementId: "etablissement-explicite", role: .proprietaire,
                                 permissions: PermissionsEtab(accordees: [.lecture])))
        XCTAssertEqual(EspaceResolution.perimetre(candidat: "etab-perime", permissions: reponse(etablissementId: "etablissement-explicite")),
                       .divergent, "métadonnée périmée : divergence, jamais un repli")
    }

    /// « tolère user.id uniquement pour l'ancien rôle ETABLISSEMENT confirmé » : legacy confirmé quand le
    /// serveur sert bien `etablissements.id = user.id` (`mon_etablissement_id()` branche 2, l.67108-67116).
    func testLegacyConfirmeParLeServeur() {
        let legacy = utilisateur(role: "ETABLISSEMENT")
        let candidat = RoleResolution.resolve(server: RoleResult(role: "ADMIN_ETABLISSEMENT"), user: legacy)?.etablissementId
        XCTAssertEqual(candidat, "utilisateur-id")
        XCTAssertEqual(EspaceResolution.perimetre(candidat: candidat, permissions: reponse(etablissementId: "utilisateur-id")),
                       .confirme(etablissementId: "utilisateur-id", role: .proprietaire, permissions: PermissionsEtab(accordees: [.lecture])))
    }

    // MARK: - Compléments (§2.2)

    func testLegacyRefuseQuandLeServeurNeSertAucunRole() {
        let legacy = utilisateur(role: "ETABLISSEMENT")
        let candidat = RoleResolution.resolve(server: RoleResult(role: "ADMIN_ETABLISSEMENT"), user: legacy)?.etablissementId
        XCTAssertEqual(EspaceResolution.perimetre(candidat: candidat, permissions: reponse(role: nil, etablissementId: nil)),
                       .sansAcces)
    }

    func testCompteInactifPrimeSurToutLeReste() {
        // `{success:false, role:null, permissions:{}}` (l.42274) : compte inactif, aucune permission retenue.
        XCTAssertEqual(EspaceResolution.perimetre(candidat: "etab-1", permissions: reponse(success: false)), .compteInactif)
        XCTAssertEqual(EspaceResolution.perimetre(candidat: nil, permissions: reponse(success: false, role: nil, etablissementId: nil)),
                       .compteInactif)
    }

    func testRoleInconnuNOuvreJamaisLEspace() {
        // `COALESCE(v_role, 'ADMIN_PLATEFORME')` (l.42287) pour un administrateur : rôle non servi.
        XCTAssertEqual(EspaceResolution.perimetre(candidat: "etab-1", permissions: reponse(role: "ADMIN_PLATEFORME")),
                       .roleNonServi("ADMIN_PLATEFORME"))
        XCTAssertEqual(EspaceResolution.perimetre(candidat: nil, permissions: reponse(role: "VALEUR_INATTENDUE")),
                       .roleNonServi("VALEUR_INATTENDUE"))
    }

    func testPermissionsServiesTellesQuellesSansCorrespondanceEcriteEnSwift() {
        for role in RoleEtab.connus {
            let accordees: Set<PermissionEtab> = [.pointage, .lecture]
            XCTAssertEqual(EspaceResolution.perimetre(candidat: "etab-1", permissions: reponse(role: role.brut, permissions: accordees)),
                           .confirme(etablissementId: "etab-1", role: role, permissions: PermissionsEtab(accordees: accordees)),
                           "\(role.brut) : les booléens serveur, jamais une table rôle → permissions côté client")
        }
    }

    func testCodesEtMessagesDeBlocageSansValeurNiTexteJuridique() {
        let sansAcces = MobileAccess.unsupportedRole(SessionState.etabSansAccesCode)
        let divergent = MobileAccess.unsupportedRole(SessionState.etabScopeDivergentCode)
        XCTAssertEqual(SessionState.etabSansAccesCode, "ETAB_SANS_ACCES")
        XCTAssertEqual(SessionState.etabScopeDivergentCode, "ETAB_SCOPE_DIVERGENT")
        for access in [sansAcces, divergent] {
            let message = access.sessionMessage ?? ""
            XCTAssertFalse(message.isEmpty)
            XCTAssertTrue(message.contains("jolene.app"), "renvoi web annoncé : \(message)")
            XCTAssertNotEqual(message, MobileAccess.unsupportedRole("X").message, "message spécialisé attendu")
        }
        XCTAssertNotEqual(sansAcces.sessionMessage, divergent.sessionMessage)
        XCTAssertTrue(divergent.estPerimetreDivergent)
        XCTAssertFalse(sansAcces.estPerimetreDivergent)
        XCTAssertFalse(MobileAccess.unsupportedRole(nil).estPerimetreDivergent)
    }
}
