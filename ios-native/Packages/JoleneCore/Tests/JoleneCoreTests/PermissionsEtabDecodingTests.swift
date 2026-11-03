import XCTest
@testable import JoleneCore

/// Décodage fail-closed de `fn_mes_permissions_etab` (lot 5 T1, §2.5, §2.7) : onze clés exactes,
/// clé absente = `false`, `{}` des réponses sans rôle, rôle inconnu conservé (jamais promu).
final class PermissionsEtabDecodingTests: XCTestCase {
    /// Les onze clés de `fn_mes_permissions_etab` (l.42290-42302) et de `PERMISSIONS_VIDES`
    /// (`src/hooks/useEtabPermissions.ts` l.21-33), dans l'ordre.
    static let onzeCles = ["gerer_equipe", "supprimer_compte", "profil_etab", "paiement", "lecture_paiement", "missions",
                           "candidatures", "contrats", "pointage", "rh", "lecture"]

    private func decoder<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testOnzeClesExactesDansLOrdreDuServeur() throws {
        XCTAssertEqual(PermissionEtab.allCases.map(\.rawValue), Self.onzeCles)
        let toutes = PermissionsEtab(accordees: Set(PermissionEtab.allCases))
        let encode = try JSONSerialization.jsonObject(with: JSONEncoder().encode(toutes)) as? [String: Bool]
        XCTAssertEqual(encode?.keys.sorted(), Self.onzeCles.sorted(), "l'encodage pose les onze clés exactes, rien d'autre")
        XCTAssertTrue(encode?.values.allSatisfy { $0 } ?? false)
        XCTAssertEqual(PermissionsEtab.aucune.accordees, [])
        XCTAssertEqual(toutes.accordees, PermissionEtab.allCases)
    }

    func testChaqueCleEstLueSurSonChamp() throws {
        for permission in PermissionEtab.allCases {
            let lu = try decoder(PermissionsEtab.self, #"{"\#(permission.rawValue)":true}"#)
            XCTAssertEqual(lu.accordees, [permission], permission.rawValue)
            XCTAssertTrue(lu[permission], permission.rawValue)
            XCTAssertEqual(lu, PermissionsEtab(accordees: [permission]))
        }
    }

    func testCleAbsenteNulleOuNonBooleenneVautFaux() throws {
        let lu = try decoder(PermissionsEtab.self, """
        {"lecture":true,"pointage":null,"missions":"true","contrats":1,"rh":{},"validation_pointage":true,"lecture_finances":true}
        """)
        XCTAssertEqual(lu.accordees, [.lecture], "seul un booléen vrai accorde ; les clés de EQUIPE_ETAB.md n'existent pas")
        XCTAssertEqual(try decoder(PermissionsEtab.self, "{}"), .aucune)
    }

    func testReponseCompleteDUnMembre() throws {
        let lu = try decoder(PermissionsEtabResult.self, """
        {"success":true,"role":"POINTAGE_ONLY","etablissement_id":"6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b",
         "permissions":{"gerer_equipe":false,"supprimer_compte":false,"profil_etab":false,"paiement":false,
                        "lecture_paiement":false,"missions":false,"candidatures":false,"contrats":false,
                        "pointage":true,"rh":false,"lecture":true}}
        """)
        XCTAssertTrue(lu.success)
        XCTAssertEqual(lu.role, .pointageOnly)
        XCTAssertEqual(lu.etablissementId, "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b")
        XCTAssertEqual(lu.permissions.accordees, [.pointage, .lecture])
    }

    func testCompteInactifSuccessFalseEtPermissionsVides() throws {
        // l.42274 : `{success:false, role:null, permissions:{}}`.
        let lu = try decoder(PermissionsEtabResult.self, #"{"success":false,"role":null,"permissions":{}}"#)
        XCTAssertEqual(lu, PermissionsEtabResult(success: false, role: nil, etablissementId: nil, permissions: .aucune))
        // Fail-closed : un success:false n'accorde jamais rien, même si la réponse en porte.
        let forge = try decoder(PermissionsEtabResult.self, #"{"success":false,"role":"PROPRIETAIRE","etablissement_id":"e","permissions":{"lecture":true}}"#)
        XCTAssertEqual(forge.permissions, .aucune)
    }

    func testSansEtablissementOuMembreRevoqueRoleNul() throws {
        // l.42277 et l.42282 : même forme pour « aucun établissement » et « membre révoqué ».
        let lu = try decoder(PermissionsEtabResult.self, #"{"success":true,"role":null,"etablissement_id":null,"permissions":{}}"#)
        XCTAssertTrue(lu.success)
        XCTAssertNil(lu.role)
        XCTAssertNil(lu.etablissementId)
        XCTAssertEqual(lu.permissions, .aucune)
        // Sans rôle, aucune permission n'est retenue, quoi que porte la réponse.
        let forge = try decoder(PermissionsEtabResult.self, #"{"success":true,"role":"  ","etablissement_id":"","permissions":{"lecture":true}}"#)
        XCTAssertNil(forge.role, "rôle vide → nil")
        XCTAssertNil(forge.etablissementId, "identifiant vide → nil")
        XCTAssertEqual(forge.permissions, .aucune)
    }

    func testRoleInconnuConserveTelQuel() throws {
        // `COALESCE(v_role, 'ADMIN_PLATEFORME')` l.42287 : rôle hors des cinq, jamais promu.
        let lu = try decoder(PermissionsEtabResult.self, """
        {"success":true,"role":"ADMIN_PLATEFORME","etablissement_id":"e-1","permissions":{"lecture":true,"pointage":true}}
        """)
        XCTAssertEqual(lu.role, .inconnu("ADMIN_PLATEFORME"))
        XCTAssertFalse(lu.role?.estConnu ?? true)
        XCTAssertEqual(lu.permissions.accordees, [.pointage, .lecture], "le décodage n'interprète pas : EspaceResolution (T2) bloque")
    }

    func testSuccessAbsentEstUneErreurDeDecodage() {
        XCTAssertThrowsError(try decoder(PermissionsEtabResult.self, #"{"role":"RH","permissions":{}}"#))
        XCTAssertThrowsError(try decoder(PermissionsEtabResult.self, #"{"success":"true"}"#))
    }

    func testPermissionsNonObjetVautAucune() throws {
        for permissions in ["[]", #""lecture""#, "true", "null"] {
            let lu = try decoder(PermissionsEtabResult.self, #"{"success":true,"role":"RH","etablissement_id":"e","permissions":\#(permissions)}"#)
            XCTAssertEqual(lu.permissions, .aucune, permissions)
        }
        let sansCle = try decoder(PermissionsEtabResult.self, #"{"success":true,"role":"RH","etablissement_id":"e"}"#)
        XCTAssertEqual(sansCle.permissions, .aucune)
    }

    func testRolesConnusAllerRetour() throws {
        XCTAssertEqual(RoleEtab.connus.map(\.brut), ["PROPRIETAIRE", "ADMIN_GROUPE", "RH", "POINTAGE_ONLY", "LECTURE_SEULE"])
        for role in RoleEtab.connus + [.inconnu("ETABLISSEMENT"), .inconnu("")] {
            XCTAssertEqual(RoleEtab(brut: role.brut), role)
            let donnees = try JSONEncoder().encode([role])
            XCTAssertEqual(try JSONDecoder().decode([RoleEtab].self, from: donnees), [role])
        }
        XCTAssertTrue(RoleEtab.connus.allSatisfy(\.estConnu))
        XCTAssertEqual(RoleEtab(brut: "proprietaire"), .inconnu("proprietaire"), "valeur serveur exacte, sensible à la casse")
    }

    func testContexteEtablissementVerifie() throws {
        let valide = EtablissementReadContext(userId: "u-1", etablissementId: "e-1", roleEtab: .rh,
                                              permissions: .aucune, epoch: 3)
        XCTAssertNoThrow(try valide.verifier())
        var sansEtablissement = valide
        sansEtablissement.etablissementId = "  "
        var sansUtilisateur = valide
        sansUtilisateur.userId = ""
        var roleInconnu = valide
        roleInconnu.roleEtab = .inconnu("ADMIN_PLATEFORME")
        for invalide in [sansEtablissement, sansUtilisateur, roleInconnu] {
            XCTAssertThrowsError(try invalide.verifier()) { error in
                XCTAssertEqual(error as? JoleneError, JoleneError(.unauthorized, EtablissementReadContext.contexteInvalideMessage))
            }
        }
        XCTAssertFalse(EtablissementReadContext.contexteInvalideMessage.contains("e-1"))
    }
}
