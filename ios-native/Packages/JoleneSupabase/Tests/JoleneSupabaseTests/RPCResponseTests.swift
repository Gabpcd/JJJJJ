import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Réponses jsonb renvoyées en HTTP 200 (blueprint lot 1 §2.4) : `{error}` seul est une
/// erreur levée (« Non authentifié » → session expirée, sinon message serveur verbatim) ;
/// `{success:false|ok:false, …}`, `{choix_requis:true, …}` et `{documents_requis_pour, …}` sans
/// `success:true` sont des refus structurés traduits en issue métier ; aucune clé n'est exigée
/// sauf celles qui conditionnent une action.
final class RPCResponseTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let fallback = "Impossible de traiter votre demande. Réessayez."

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func reponse(_ json: String) throws -> RPCResponse {
        RPCResponse(try JSONDecoder().decode(AnyJSON.self, from: Data(json.utf8)))
    }

    private func leve(_ reponse: RPCResponse, file: StaticString = #filePath, line: UInt = #line) -> JoleneError? {
        do {
            try reponse.leverSiErreur(fallback: fallback)
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: - Lecture tolérante

    func testSuccesSimple() throws {
        let r = try reponse(#"{"success":true}"#)
        XCTAssertTrue(r.estSucces)
        XCTAssertFalse(r.estRefus)
        XCTAssertNil(r.erreur)
        XCTAssertNil(leve(r))
        XCTAssertNil(r.issueCandidatureRefusee(fallback: fallback))
        XCTAssertTrue(try reponse(#"{"ok":true,"contrat_id":"k-1"}"#).estSucces)
    }

    func testAccesseursTolerants() throws {
        let r = try reponse("""
        {"candidature_id":"c-1","points":-5,"ratio":0.5,"entier_flottant":3.0,"libre":false,"liste":["a","b",3],
         "vide":"","nul":null,"objet":{"a":1}}
        """)
        XCTAssertEqual(r.string("candidature_id"), "c-1")
        XCTAssertEqual(r.int("points"), -5)
        XCTAssertEqual(r.int("entier_flottant"), 3)
        XCTAssertNil(r.int("ratio"), "un nombre non entier n'est pas un entier")
        XCTAssertEqual(r.double("ratio"), 0.5)
        XCTAssertEqual(r.double("points"), -5)
        XCTAssertEqual(r.bool("libre"), false)
        XCTAssertEqual(r.strings("liste"), ["a", "b"], "les éléments non textuels sont ignorés")
        XCTAssertNil(r.string("nul"))
        XCTAssertNil(r.string("absente"))
        XCTAssertNil(r.string("objet"))
        XCTAssertEqual(r.string("vide"), "")
        XCTAssertFalse(r.estSucces, "sans success/ok explicite, rien n'est un succès")
        XCTAssertFalse(r.estRefus)
    }

    func testCleQuiConditionneUneActionEstExigee() throws {
        let r = try reponse(#"{"success":true,"candidature_id":"c-1","contrat_id":"  "}"#)
        XCTAssertEqual(try r.requiredString("candidature_id"), "c-1")
        for cle in ["contrat_id", "absente"] {
            XCTAssertThrowsError(try r.requiredString(cle)) { error in
                XCTAssertEqual((error as? JoleneError)?.kind, .contract)
                XCTAssertEqual((error as? JoleneError)?.message, SupabaseErrorMapping.contractMessage)
            }
        }
    }

    func testCorpsNonObjet() throws {
        for json in ["null", "true", "[]", #""texte""#, "42"] {
            let r = try reponse(json)
            XCTAssertEqual(r.objet, [:], json)
            XCTAssertFalse(r.estSucces, json)
            XCTAssertFalse(r.estRefus, json)
            XCTAssertNil(leve(r), json)
        }
    }

    // MARK: - `{error}` seul

    func testErreurSeuleNonAuthentifieDevientSessionExpiree() throws {
        for message in ["Non authentifié", "Non authentifié.", "  non authentifié  ", "Non authentifie"] {
            let erreur = leve(try reponse(#"{"error":"\#(message)"}"#))
            XCTAssertEqual(erreur?.kind, .unauthorized, message)
            XCTAssertEqual(erreur?.message, SupabaseErrorMapping.unauthorizedMessage, message)
        }
        XCTAssertFalse(RPCResponse.estNonAuthentifie("Non authentifié pour cette mission précise"),
                       "seul le message exact signifie une session absente")
    }

    func testErreurSeuleEstLeveeVerbatim() throws {
        // `fn_confirmer_presence_mission` l.24615-24617 du dump : HTTP 200.
        for message in ["Mission introuvable", "Cette mission n'est plus active."] {
            let erreur = leve(try reponse(#"{"error":"\#(message)"}"#))
            XCTAssertEqual(erreur, JoleneError(.unknown, message))
        }
        let nonTextuelle = leve(try reponse(#"{"error":{"detail":"x"}}"#))
        XCTAssertEqual(nonTextuelle, JoleneError(.unknown, fallback), "erreur non textuelle : message générique")
        XCTAssertNil(leve(try reponse(#"{"error":"","success":true}"#)), "erreur vide : ignorée")
        XCTAssertTrue(try reponse(#"{"error":"","success":true}"#).estSucces)
        XCTAssertFalse(try reponse(#"{"error":"Refus","success":true}"#).estSucces, "un message d'erreur annule le succès")
    }

    // MARK: - Refus structurés → CandidatureOutcome

    func testRefusStructureNeLevePas() throws {
        let r = try reponse(#"{"success":false,"ok":false,"error":"Cette mission n'est plus disponible."}"#)
        XCTAssertTrue(r.estRefus)
        XCTAssertNil(leve(r))
        XCTAssertEqual(r.issueCandidatureRefusee(fallback: fallback),
                       .refusee(code: nil, message: "Cette mission n'est plus disponible.", documentsRequisPour: nil))
    }

    func testRefusNonAuthentifieDevientSessionExpiree() throws {
        let erreur = leve(try reponse(#"{"success":false,"error":"Non authentifié"}"#))
        XCTAssertEqual(erreur?.kind, .unauthorized)
    }

    func testPlanningAReconfirmer() throws {
        // `fn_confirmer_action_planning_v1` l.24199 et l.24247 du dump.
        for code in ["PLANNING_A_RECONFIRMER", "PLANNING_MODIFIE_RECONFIRMER"] {
            let message = "Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires."
            let r = try reponse(#"{"success":false,"ok":false,"code":"\#(code)","error":"\#(message)"}"#)
            XCTAssertEqual(r.code, code)
            XCTAssertEqual(r.issueCandidatureRefusee(fallback: fallback), .planningAReconfirmer(code: code, message: message))
        }
    }

    func testConflitEtCodeDuTravailRestentVerbatim() throws {
        let conflit = try reponse("""
        {"success":false,"ok":false,"code":"REPOS_11H","error":"[CODE DU TRAVAIL] Repos quotidien de 11 h non respecté."}
        """)
        XCTAssertEqual(conflit.issueCandidatureRefusee(fallback: fallback),
                       .refusee(code: "REPOS_11H", message: "[CODE DU TRAVAIL] Repos quotidien de 11 h non respecté.",
                                documentsRequisPour: nil))
        let codeErreur = try reponse(#"{"success":false,"error_code":"PROFESSION_NON_ELIGIBLE","code":"AUTRE","error":"Refus"}"#)
        XCTAssertEqual(codeErreur.code, "PROFESSION_NON_ELIGIBLE", "error_code prime sur code")
        let sansMessage = try reponse(#"{"success":false}"#)
        XCTAssertEqual(sansMessage.issueCandidatureRefusee(fallback: fallback),
                       .refusee(code: nil, message: fallback, documentsRequisPour: nil))
    }

    // Vecteurs « documents requis » et « choix de contrat » copiés des RETURN du dump
    // (`supabase/schema/public.sql`), une RPC par action. Les RPC que
    // `fn_confirmer_action_planning_v1` délègue au lot 1 (POSTULER, ACCEPTER, PROPOSITION,
    // l.24274-24312) renvoient ces refus SANS `success` ni `ok` : seuls `documents_requis_pour`
    // ou `choix_requis` les signalent.

    func testDocumentsRequisPostuler() throws {
        // POSTULER → `fn_postuler_mission_rate_limited` → `fn_postuler_mission` l.47990-47996.
        let r = try reponse("""
        {"error":"Les documents requis pour candidater en libéral sont manquants ou expirés.",
         "documents_requis_pour":"LIBERAL","lien_documents":"/soignant/mes-documents"}
        """)
        XCTAssertNil(r.success)
        XCTAssertNil(r.ok)
        XCTAssertTrue(r.estRefus, "documents_requis_pour sans success:true est un refus structuré")
        XCTAssertFalse(r.estSucces)
        XCTAssertNil(leve(r), "un refus structuré ne lève pas : il devient une issue métier")
        XCTAssertEqual(r.string("lien_documents"), "/soignant/mes-documents")
        XCTAssertEqual(r.issueCandidatureRefusee(fallback: fallback),
                       .refusee(code: nil, message: "Les documents requis pour candidater en libéral sont manquants ou expirés.",
                                documentsRequisPour: "LIBERAL"))
    }

    func testDocumentsRequisAccepterEtProposition() throws {
        // ACCEPTER → `fn_accepter_mission` (l.5136-5137, relaie tel quel) et PROPOSITION →
        // `fn_repondre_proposition` (l.53636-53637, `RETURN v_result` tel quel) : refus de
        // `fn_finaliser_attribution_mission` l.36757-36763 (`lower(v_choix)` dans le message).
        for (contrat, minuscule) in [("SALARIE", "salarie"), ("LIBERAL", "liberal")] {
            let message = "Les documents requis pour une mission \(minuscule) ne sont pas encore validés."
            let r = try reponse("""
            {"error":"\(message)","documents_requis_pour":"\(contrat)","lien_documents":"/soignant/mes-documents"}
            """)
            XCTAssertTrue(r.estRefus, contrat)
            XCTAssertFalse(r.estSucces, contrat)
            XCTAssertNil(leve(r), contrat)
            XCTAssertEqual(r.issueCandidatureRefusee(fallback: fallback),
                           .refusee(code: nil, message: message, documentsRequisPour: contrat), contrat)
        }
    }

    func testSuccesPostulerAvecDocumentsACompleterNEstPasUnRefus() throws {
        // `fn_postuler_mission` l.48061-48068 : le SUCCÈS porte aussi `documents_requis_pour`
        // (rappel des documents à compléter). `success:true` prime : jamais un refus.
        let r = try reponse("""
        {"success":true,"candidature_id":"c-1","choix_contrat":"SALARIE","profession_requise":"AS",
         "docs_a_completer":true,"documents_requis_pour":"SALARIE"}
        """)
        XCTAssertFalse(r.estRefus)
        XCTAssertTrue(r.estSucces)
        XCTAssertNil(leve(r))
        XCTAssertNil(r.issueCandidatureRefusee(fallback: fallback))
        XCTAssertEqual(r.documentsRequisPour, "SALARIE")
        XCTAssertEqual(r.bool("docs_a_completer"), true)
        XCTAssertEqual(try r.requiredString("candidature_id"), "c-1")
    }

    func testDocumentsRequisVideNEstPasUnRefus() throws {
        let r = try reponse(#"{"documents_requis_pour":"  ","nb":1}"#)
        XCTAssertNil(r.documentsRequisPour, "valeur vide : absente")
        XCTAssertFalse(r.estRefus)
        XCTAssertNil(leve(r))
    }

    func testDocumentsRequisPourUrgenceLot4() throws {
        // URGENCE, lot 4 (pool urgence, hors lot 1) : `fn_accepter_mission_urgence` l.5178-5183,
        // seule forme `success:false` + `documents_requis_pour` (sans `lien_documents`).
        let r = try reponse("""
        {"success":false,"error":"Vos documents ne sont pas validés pour cette mission salarie","documents_requis_pour":"SALARIE"}
        """)
        XCTAssertEqual(r.issueCandidatureRefusee(fallback: fallback),
                       .refusee(code: nil, message: "Vos documents ne sont pas validés pour cette mission salarie",
                                documentsRequisPour: "SALARIE"))
    }

    private let optionsAttendues = [
        ChoixContratOption(value: "SALARIE", label: "Salarié (CDD / bulletin de paie)"),
        ChoixContratOption(value: "LIBERAL", label: "Libéral (note d'honoraires)"),
    ]

    func testChoixDeContratRequisSansDrapeauPostulerAccepterProposition() throws {
        // `fn_resoudre_contrat_mission` l.54551-54563 renvoie `{ok:false, choix_requis, error,
        // options}` ; POSTULER (`fn_postuler_mission` l.47969-47970) et ACCEPTER / PROPOSITION
        // (`fn_finaliser_attribution_mission` l.36752-36753) le relaient en `v_resolution - 'ok'` :
        // ni `success` ni `ok`.
        let r = try reponse("""
        {"choix_requis":true,"error":"Choisissez votre mode de contrat.",
         "options":[{"value":"SALARIE","label":"Salarié (CDD / bulletin de paie)"},{"value":"LIBERAL","label":"Libéral (note d'honoraires)"}]}
        """)
        XCTAssertNil(r.success)
        XCTAssertNil(r.ok)
        XCTAssertTrue(r.choixRequis)
        XCTAssertTrue(r.estRefus)
        XCTAssertFalse(r.estSucces)
        XCTAssertNil(leve(r), "le choix de contrat n'est pas une erreur : l'action est rejouée avec l'option choisie")
        XCTAssertEqual(r.issueCandidatureRefusee(fallback: fallback), .choixRequis(optionsAttendues))
    }

    func testChoixDeContratRequisAvecDrapeauLot4() throws {
        // Lot 4 seulement : SWIPE_LIKE (`fn_enregistrer_swipe` l.32804-32805, `{ok:false} || …`)
        // et URGENCE (`fn_accepter_mission_urgence` l.5175-5176, `{success:false} || …`).
        for prefixe in [#""ok":false"#, #""success":false"#] {
            let r = try reponse("""
            {\(prefixe),"choix_requis":true,"error":"Choisissez votre mode de contrat.",
             "options":[{"value":"SALARIE","label":"Salarié (CDD / bulletin de paie)"},{"value":"LIBERAL","label":"Libéral (note d'honoraires)"},
                        {"value":null,"label":"illisible"}]}
            """)
            XCTAssertTrue(r.choixRequis)
            XCTAssertEqual(r.issueCandidatureRefusee(fallback: fallback), .choixRequis(optionsAttendues),
                           "une option sans valeur est écartée")
        }
    }

    // MARK: - Transport

    func testAppelTransmetLesParametresEtLitLaReponse() async throws {
        registry.add("POST", "/rest/v1/rpc/fn_test_jsonb", respond: .json(200, #"{"success":true,"id":"x-1"}"#))
        let r = try await RPCResponse.appeler(TestClient.make(), "fn_test_jsonb",
                                              params: ["p_id": .string("x-1"), "p_actif": .bool(true)], fallback: fallback)
        XCTAssertTrue(r.estSucces)
        XCTAssertEqual(r.string("id"), "x-1")
        let requete = try XCTUnwrap(registry.requests(to: "/rest/v1/rpc/fn_test_jsonb").first)
        let corps = try XCTUnwrap(requete.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["p_id"] as? String, "x-1")
        XCTAssertEqual(corps["p_actif"] as? Bool, true)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testAppelPGRST202EstUnRefusDeContratSansRenvoi() async throws {
        registry.add("POST", "/rest/v1/rpc/fn_test_jsonb", respond: .json(404, """
        {"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.fn_test_jsonb in the schema cache"}
        """))
        do {
            _ = try await RPCResponse.appeler(TestClient.make(), "fn_test_jsonb", fallback: fallback)
            XCTFail("attendu : erreur de contrat")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
            XCTAssertFalse(error.message.contains("PGRST"))
        }
        XCTAssertEqual(registry.requests(to: "/rest/v1/rpc/fn_test_jsonb").count, 1)
    }

    func testAppelReseauIndisponible() async throws {
        registry.add("POST", "/rest/v1/rpc/fn_test_jsonb", respond: .networkFailure())
        do {
            _ = try await RPCResponse.appeler(TestClient.make(), "fn_test_jsonb", fallback: fallback)
            XCTFail("attendu : erreur réseau")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .network)
        }
    }
}
