import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Audit du lot 1 (décision 5) : connexion / déconnexion par `fn_audit_connexion` et activité
/// par `fn_maj_activite_soignant`, comme `AuthContext.tsx` l.186-198 ; assignation par
/// `fn_ecrire_audit_safe` comme `DetailMissionSoignant.tsx` l.824-836. Best-effort : un
/// `{success:false}` n'est pas une erreur ; un refus de contrat (PGRST202) n'est jamais renvoyé.
final class SupabaseAuditGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let missionId = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseAuditGateway { SupabaseAuditGateway(client: TestClient.make()) }

    private func corps(_ path: String) throws -> [String: Any] {
        let requete = try XCTUnwrap(registry.requests(to: path).first, "aucun appel à \(path)")
        return try XCTUnwrap(requete.bodyJSON as? [String: Any])
    }

    // MARK: - Connexion / déconnexion / activité

    func testConnexionEtDeconnexionEnvoientLActionAttendue() async throws {
        registry.add("POST", "/rest/v1/rpc/fn_audit_connexion", respond: .json(200, #"{"success":true}"#))
        let connexion = try await gateway().connexion()
        XCTAssertEqual(connexion, .enregistre)
        XCTAssertEqual(try corps("/rest/v1/rpc/fn_audit_connexion") as NSDictionary, ["p_action": "CONNEXION"] as NSDictionary)

        registry.reset()
        registry.add("POST", "/rest/v1/rpc/fn_audit_connexion", respond: .json(200, #"{"success":true}"#))
        let deconnexion = try await gateway().deconnexion()
        XCTAssertEqual(deconnexion, .enregistre)
        XCTAssertEqual(try corps("/rest/v1/rpc/fn_audit_connexion") as NSDictionary, ["p_action": "DECONNEXION"] as NSDictionary)
        let requete = try XCTUnwrap(registry.requests.first)
        XCTAssertEqual(requete.header("X-Client-Info"), "jolene-ios/2.0.0")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testSuccesFalseNEstPasUneErreur() async throws {
        // `fn_audit_connexion` avale ses exceptions (l.19744-19747 du dump) : l'audit ne bloque jamais.
        registry.add("POST", "/rest/v1/rpc/fn_audit_connexion", respond: .json(200, #"{"success":false}"#))
        let resultat = try await gateway().connexion()
        XCTAssertEqual(resultat, .nonEnregistre)
        XCTAssertEqual(registry.requests.count, 1, "aucun renvoi automatique")
    }

    func testActionRefuseeParLeServeurEstLeveeVerbatim() async throws {
        registry.add("POST", "/rest/v1/rpc/fn_audit_connexion", respond: .json(200, #"{"error":"Action non autorisée"}"#))
        do {
            _ = try await gateway().deconnexion()
            XCTFail("attendu : refus serveur")
        } catch let error as JoleneError {
            XCTAssertEqual(error, JoleneError(.unknown, "Action non autorisée"))
        }
    }

    func testFonctionIntrouvablePGRST202EstUnRefusDeContratSansRenvoi() async throws {
        registry.add("POST", "/rest/v1/rpc/fn_audit_connexion", respond: .json(404, """
        {"code":"PGRST202","details":null,"hint":null,
         "message":"Could not find the function public.fn_audit_connexion(p_action) in the schema cache"}
        """))
        do {
            _ = try await gateway().connexion()
            XCTFail("attendu : erreur de contrat")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
            XCTAssertEqual(error.message, SupabaseErrorMapping.contractMessage)
        }
        XCTAssertEqual(registry.requests(to: "/rest/v1/rpc/fn_audit_connexion").count, 1, "refus définitif : un seul appel")
    }

    func testReseauIndisponibleEtSessionRefusee() async throws {
        registry.add("POST", "/rest/v1/rpc/fn_audit_connexion", respond: .networkFailure())
        do {
            _ = try await gateway().connexion()
            XCTFail("attendu : erreur réseau")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .network)
        }
        registry.reset()
        registry.add("POST", "/rest/v1/rpc/fn_maj_activite_soignant",
                     respond: .json(401, #"{"code":"PGRST301","message":"JWT expired","details":null,"hint":null}"#))
        do {
            _ = try await gateway().activite()
            XCTFail("attendu : non autorisé")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
        }
    }

    func testActiviteSoignant() async throws {
        registry.add("POST", "/rest/v1/rpc/fn_maj_activite_soignant", respond: .json(200, #"{"success":true}"#))
        let resultat = try await gateway().activite()
        XCTAssertEqual(resultat, .enregistre)
        let requete = try XCTUnwrap(registry.requests(to: "/rest/v1/rpc/fn_maj_activite_soignant").first)
        let corps = requete.bodyJSON as? [String: Any]
        XCTAssertTrue(corps?.isEmpty ?? true, "fonction sans paramètre")
    }

    func testReponseInattendueEstUnRefusDeContrat() async throws {
        registry.add("POST", "/rest/v1/rpc/fn_maj_activite_soignant", respond: .json(200, "null"))
        do {
            _ = try await gateway().activite()
            XCTFail("une réponse sans success n'est ni un succès ni un refus")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
        }
    }

    // MARK: - fn_ecrire_audit_safe

    func testEcritureMissionAssignationCommeLeWeb() async throws {
        registry.add("POST", "/rest/v1/rpc/fn_ecrire_audit_safe",
                     respond: .json(200, #"{"success":true,"id":"0a0a0a0a-1b1b-4c2c-8d3d-4e4e4e4e4e4e"}"#))
        let resultat = try await gateway().ecrire(action: .missionAssignation, typeRessource: "mission",
                                                  idRessource: missionId.uppercased(),
                                                  details: ["intitule": "Remplacement IDE nuit", "debut": "2026-12-01T19:00:00+00:00"],
                                                  context: TestClient.context)
        XCTAssertEqual(resultat, .enregistre)
        let corps = try corps("/rest/v1/rpc/fn_ecrire_audit_safe")
        XCTAssertEqual(Set(corps.keys), ["p_acteur_id", "p_type_acteur", "p_action", "p_type_ressource", "p_id_ressource",
                                         "p_details", "p_navigateur"],
                       "p_cle_s3 et p_ip prennent leur défaut SQL (NULL)")
        XCTAssertEqual(corps["p_acteur_id"] as? String, TestClient.userId)
        XCTAssertEqual(corps["p_type_acteur"] as? String, "SOIGNANT")
        XCTAssertEqual(corps["p_action"] as? String, "MISSION_ASSIGNATION")
        XCTAssertEqual(corps["p_type_ressource"] as? String, "mission")
        XCTAssertEqual(corps["p_id_ressource"] as? String, missionId, "uuid normalisé en minuscules")
        XCTAssertEqual(corps["p_navigateur"] as? String, "jolene-ios/2.0.0")
        XCTAssertEqual(corps["p_details"] as? [String: String],
                       ["intitule": "Remplacement IDE nuit", "debut": "2026-12-01T19:00:00+00:00"])
    }

    func testEcritureSansDetailsOmetLeParametre() async throws {
        registry.add("POST", "/rest/v1/rpc/fn_ecrire_audit_safe", respond: .json(200, #"{"success":true,"id":"x"}"#))
        _ = try await gateway().ecrire(action: .missionAssignation, typeRessource: "mission", idRessource: missionId,
                                       details: [:], context: TestClient.context)
        XCTAssertNil(try corps("/rest/v1/rpc/fn_ecrire_audit_safe")["p_details"])
    }

    func testEcritureRefuseeParLaBaseNEstPasUneErreur() async throws {
        // La fonction avale l'exception et renvoie SQLERRM (l.31831-31833 du dump) : jamais affiché.
        registry.add("POST", "/rest/v1/rpc/fn_ecrire_audit_safe", respond: .json(200, """
        {"success":false,"error":"new row for relation \\"journaux_audit\\" violates check constraint \\"journaux_audit_action_check\\""}
        """))
        let resultat = try await gateway().ecrire(action: .missionAssignation, typeRessource: "mission", idRessource: missionId,
                                                  details: [:], context: TestClient.context)
        XCTAssertEqual(resultat, .nonEnregistre)
    }

    func testEcritureSansSessionNEstPasUneSessionExpiree() async throws {
        // `RAISE EXCEPTION 'Non authentifié'` (l.31815) est avalé par la fonction elle-même
        // (l.31831-31833) : `{success:false, error:'Non authentifié'}`. L'audit suit un ACCEPTER
        // réussi ; il ne doit jamais faire afficher « session expirée » après ce succès.
        registry.add("POST", "/rest/v1/rpc/fn_ecrire_audit_safe",
                     respond: .json(200, #"{"success":false,"error":"Non authentifié"}"#))
        let resultat = try await gateway().ecrire(action: .missionAssignation, typeRessource: "mission", idRessource: missionId,
                                                  details: [:], context: TestClient.context)
        XCTAssertEqual(resultat, .nonEnregistre)
        XCTAssertEqual(registry.requests(to: "/rest/v1/rpc/fn_ecrire_audit_safe").count, 1, "aucun renvoi automatique")
    }

    func testSuccesFalseAvecMessageNEstJamaisUneErreur() async throws {
        // Quel que soit le texte joint à `success:false`, l'audit best-effort rend `.nonEnregistre`.
        for corps in [#"{"success":false,"error":"Non authentifié"}"#, #"{"success":false,"error":"Action non autorisée"}"#,
                      #"{"success":false,"ok":false,"code":"X","error":"Refus"}"#] {
            registry.reset()
            registry.add("POST", "/rest/v1/rpc/fn_audit_connexion", respond: .json(200, corps))
            let resultat = try await gateway().deconnexion()
            XCTAssertEqual(resultat, .nonEnregistre, corps)
        }
    }

    func testJamaisDUuidNulNiInvalideDansPIdRessource() async throws {
        // CLAUDE.md « binding uuid cassé » : un identifiant absent ou nul n'est jamais envoyé.
        for invalide in ["", "  ", "demo-mission-001", "00000000-0000-0000-0000-000000000000", "null"] {
            do {
                _ = try await gateway().ecrire(action: .missionAssignation, typeRessource: "mission", idRessource: invalide,
                                               details: [:], context: TestClient.context)
                XCTFail("ressource « \(invalide) » refusée avant tout appel")
            } catch let error as JoleneError {
                XCTAssertEqual(error.kind, .contract, invalide)
                XCTAssertEqual(error.message, SupabaseAuditGateway.ressourceInvalideMessage, invalide)
            }
        }
        do {
            _ = try await gateway().ecrire(action: .missionAssignation, typeRessource: " ", idRessource: missionId,
                                           details: [:], context: TestClient.context)
            XCTFail("type de ressource vide refusé")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
        }
        XCTAssertTrue(registry.requests.isEmpty, "aucune requête pour un audit invalide")
    }

    func testEcritureRefuseUnContexteDesynchronise() async throws {
        var contexte = TestClient.context
        contexte.profile.id = "autre"
        do {
            _ = try await gateway().ecrire(action: .missionAssignation, typeRessource: "mission", idRessource: missionId,
                                           details: [:], context: contexte)
            XCTFail("profil désynchronisé")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
        }
        var nonUUID = TestClient.context
        nonUUID.userId = "pas-un-uuid"
        nonUUID.profile.id = "pas-un-uuid"
        do {
            _ = try await gateway().ecrire(action: .missionAssignation, typeRessource: "mission", idRessource: missionId,
                                           details: [:], context: nonUUID)
            XCTFail("acteur non uuid refusé")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
        }
        XCTAssertTrue(registry.requests.isEmpty)
    }
}
