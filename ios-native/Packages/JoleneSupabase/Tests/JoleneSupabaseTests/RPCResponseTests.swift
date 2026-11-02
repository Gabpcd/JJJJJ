import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Réponses jsonb renvoyées en HTTP 200 (blueprint lot 1 §2.4) : `{error}` seul est une
/// erreur levée (« Non authentifié » → session expirée, sinon message serveur verbatim) ;
/// `{success:false|ok:false, …}`, `{choix_requis:true, …}`, `{documents_requis_pour, …}` et
/// `{error, code, …}` sans drapeau vrai sont des refus structurés traduits en issue métier, de
/// même que l'exception PostgREST `[CODE DU TRAVAIL]` (HTTP 400) restituée mot pour mot ; aucune
/// clé n'est exigée sauf celles qui conditionnent une action.
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
        // `fn_confirmer_action_planning_v1` du dump, un message exact par code :
        // l.24199-24200 (créneaux confirmés inexploitables) et l.24247-24248 (planning modifié).
        let vecteurs = [
            ("PLANNING_A_RECONFIRMER",
             "Le planning confirmé n'est pas exploitable. Rechargez la mission avant de continuer."),
            ("PLANNING_MODIFIE_RECONFIRMER",
             "Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires."),
        ]
        for (code, message) in vecteurs {
            let r = try reponse(#"{"success":false,"ok":false,"code":"\#(code)","error":"\#(message)"}"#)
            XCTAssertEqual(r.code, code)
            XCTAssertEqual(r.issueCandidatureRefusee(fallback: fallback), .planningAReconfirmer(code: code, message: message))
        }
    }

    func testConflitDePlanningRestentVerbatim() throws {
        // `fn_confirmer_action_planning_v1` l.24256-24264 relaie `fn_conflit_planning_soignant` :
        // REPOS_11H (l.24921-24929, message sans préfixe « [CODE DU TRAVAIL] ») et chevauchement
        // sans code (l.24858-24869 → `CONFLIT_PLANNING`, tutoiement serveur conservé tel quel).
        let vecteurs = [
            ("REPOS_11H", "Repos insuffisant avec « Nuit USIC » : 8.5 h au lieu de 11 h minimum."),
            ("CONFLIT_PLANNING",
             "Tu es déjà confirmé(e) sur « Nuit USIC » le 03/11 19h00–04/11 07h00. Ce créneau chevauche la mission."),
        ]
        for (code, message) in vecteurs {
            let r = try reponse(#"{"success":false,"ok":false,"code":"\#(code)","error":"\#(message)"}"#)
            XCTAssertNil(leve(r), code)
            XCTAssertEqual(r.issueCandidatureRefusee(fallback: fallback),
                           .refusee(code: code, message: message, documentsRequisPour: nil), code)
        }
        let sansMessage = try reponse(#"{"success":false}"#)
        XCTAssertEqual(sansMessage.issueCandidatureRefusee(fallback: fallback),
                       .refusee(code: nil, message: fallback, documentsRequisPour: nil))
    }

    func testCodeLitCodeSansSeRabattreSurErrorCode() throws {
        // Fiche T0 de `fn_confirmer_action_planning_v1` : le décodeur lit `code` et ne se rabat pas
        // sur `error_code`. `error_code` (seule `fn_annuler_candidature_soignant` le pose au lot 1,
        // l.17557-17590) se lit par `codeErreur` (T7).
        let annulation = try reponse("""
        {"success":false,"error_code":"CANDIDATURE_INTROUVABLE","error":"Candidature introuvable"}
        """)
        XCTAssertNil(annulation.code, "error_code n'est jamais lu comme code")
        XCTAssertEqual(annulation.codeErreur, "CANDIDATURE_INTROUVABLE")
        XCTAssertEqual(annulation.issueCandidatureRefusee(fallback: fallback),
                       .refusee(code: nil, message: "Candidature introuvable", documentsRequisPour: nil))
        let lesDeux = try reponse(#"{"success":false,"error_code":"X","code":"Y","error":"Refus"}"#)
        XCTAssertEqual(lesDeux.code, "Y")
        XCTAssertEqual(lesDeux.codeErreur, "X")
        let vides = try reponse(#"{"success":false,"error_code":" ","code":"","error":"Refus"}"#)
        XCTAssertNil(vides.code, "code vide : absent")
        XCTAssertNil(vides.codeErreur, "error_code vide : absent")
    }

    func testPlafondHebdomadaireSansDrapeauAccepterProposition() throws {
        // ACCEPTER (`fn_accepter_mission` l.5136-5137) et PROPOSITION (`fn_repondre_proposition`
        // l.53636-53637) relaient tels quels les refus de `fn_finaliser_attribution_mission`
        // l.36788-36793 et l.36811-36825 : `{error, code, …}` SANS `success` ni `ok`.
        let incomplet = try reponse("""
        {"error":"Planning hebdomadaire incomplet : impossible de vérifier le plafond de 48 h.",
         "code":"PLANNING_HEBDOMADAIRE_INDISPONIBLE","creneaux_valides":3,"creneaux_attendus":5}
        """)
        let depassement = try reponse("""
        {"error":"Dépassement du plafond de 48 h pour la semaine du 02/11/2026 (40.0 h déjà planifiées + 12.0 h pour cette mission + 0.0 h ailleurs).",
         "code":"PLAFOND_48H_HEBDO","semaine_du":"2026-11-02","heures_existantes":40.00,"heures_mission":12.00,
         "heures_externes":0.00,"total":52.00}
        """)
        let attendus: [(RPCResponse, String, String)] = [
            (incomplet, "PLANNING_HEBDOMADAIRE_INDISPONIBLE",
             "Planning hebdomadaire incomplet : impossible de vérifier le plafond de 48 h."),
            (depassement, "PLAFOND_48H_HEBDO",
             "Dépassement du plafond de 48 h pour la semaine du 02/11/2026 (40.0 h déjà planifiées + 12.0 h pour cette mission + 0.0 h ailleurs)."),
        ]
        for (r, code, message) in attendus {
            XCTAssertNil(r.success, code)
            XCTAssertNil(r.ok, code)
            XCTAssertTrue(r.estRefus, "\(code) : `code` + `error` sans drapeau est un refus structuré")
            XCTAssertFalse(r.estSucces, code)
            XCTAssertNil(leve(r), "\(code) : un refus structuré ne lève pas, le code n'est pas perdu")
            XCTAssertEqual(r.issueCandidatureRefusee(fallback: fallback),
                           .refusee(code: code, message: message, documentsRequisPour: nil), code)
        }
        XCTAssertEqual(incomplet.int("creneaux_attendus"), 5)
        XCTAssertEqual(depassement.double("total"), 52)
    }

    func testCodeSansMessageOuAvecSuccesNEstPasUnRefus() throws {
        // Un `code` seul ne porte aucun message à afficher ; accompagné de `success:true` ou
        // `ok:true`, c'est un succès. Seul `code` + `error` sans drapeau vrai est un refus.
        for json in [#"{"code":"X"}"#, #"{"code":"X","error":""}"#, #"{"code":"","error":"Refus"}"#] {
            XCTAssertFalse(try reponse(json).estRefus, json)
        }
        XCTAssertEqual(leve(try reponse(#"{"code":"","error":"Refus"}"#)), JoleneError(.unknown, "Refus"),
                       "code vide : `{error}` seul, levé verbatim")
        XCTAssertTrue(try reponse(#"{"success":true,"code":"X"}"#).estSucces)
        XCTAssertFalse(try reponse(#"{"ok":true,"code":"X","error":"Refus"}"#).estRefus)
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

    // MARK: - Exception `[CODE DU TRAVAIL]` (HTTP 400)

    /// Refus des triggers du Code du travail, au format exact des `RAISE EXCEPTION` du dump
    /// (valeurs plausibles à la place des `%`). Ils se déclenchent sur l'`UPDATE public.missions`
    /// de `fn_finaliser_attribution_mission` (l.36840), donc sur ACCEPTER et PROPOSITION, et
    /// remontent en exception PostgREST HTTP 400, jamais en jsonb HTTP 200. Le repos de 11 h lève
    /// `check_violation` (23514) avec un DETAIL, les trois autres le SQLSTATE par défaut P0001.
    private let refusCodeDuTravail: [(trigger: String, sqlstate: String, details: String?, message: String)] = [
        ("dec_verifier_plafond_48h l.4477-4481", "P0001", nil,
         "[CODE DU TRAVAIL] Semaine du 02/11/2026 : 40.0h Jolene + 10.0h ailleurs = 50.0h total (max 48h, Art. L3121-20)"),
        ("dec_verifier_repos_11h l.4614-4618", "23514", "mission_conflictuelle=6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b",
         "[CODE DU TRAVAIL] Repos insuffisant avant mission : 8.5 heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée."),
        ("dec_verifier_moyenne_44h_12_semaines l.4321-4325", "P0001", nil,
         "[CODE DU TRAVAIL] Moyenne dépassée du 10/08/2026 au 01/11/2026 : 45.2h/semaine sur 12 semaines (max 44h, Art. L3121-22). Assignation bloquée."),
        ("dec_verifier_repos_hebdo_35h l.4706-4708", "P0001", nil,
         "[CODE DU TRAVAIL] Repos hebdomadaire insuffisant : plage max de 30.5h consécutives sans travail (minimum légal 35h, Art. L3132-2 = 24h + 11h repos quotidien). Assignation bloquée."),
    ]

    private let planningRPC = "/rest/v1/rpc/fn_confirmer_action_planning_v1"

    private func exceptionPostgREST(sqlstate: String, details: String?, message: String) -> String {
        let detail = details.map { #""\#($0)""# } ?? "null"
        return #"{"code":"\#(sqlstate)","details":\#(detail),"hint":null,"message":"\#(message)"}"#
    }

    func testExceptionCodeDuTravailRestitueeVerbatimEnRefusStructure() async throws {
        // Décision 2 / HARD STOP n°4 : le texte légal du serveur est affiché mot pour mot, jamais
        // remplacé par le message générique de `SupabaseErrorMapping`.
        for vecteur in refusCodeDuTravail {
            registry.reset()
            registry.add("POST", planningRPC, respond: .json(400, exceptionPostgREST(sqlstate: vecteur.sqlstate,
                                                                                     details: vecteur.details,
                                                                                     message: vecteur.message)))
            let r = try await RPCResponse.appeler(TestClient.make(), "fn_confirmer_action_planning_v1",
                                                  params: ["p_action": .string("ACCEPTER")], fallback: fallback)
            XCTAssertTrue(r.estRefus, vecteur.trigger)
            XCTAssertFalse(r.estSucces, vecteur.trigger)
            XCTAssertNil(leve(r), "\(vecteur.trigger) : refus structuré, jamais une erreur générique")
            XCTAssertEqual(r.erreur, vecteur.message, "\(vecteur.trigger) : mot pour mot, préfixe compris")
            XCTAssertEqual(r.code, CandidatureOutcome.codeRefusCodeDuTravail, vecteur.trigger)
            XCTAssertEqual(r.issueCandidatureRefusee(fallback: fallback),
                           .refusee(code: CandidatureOutcome.codeRefusCodeDuTravail, message: vecteur.message,
                                    documentsRequisPour: nil), vecteur.trigger)
            XCTAssertFalse(r.erreur?.contains("mission_conflictuelle") ?? true, "le DETAIL technique n'est jamais repris")
            XCTAssertEqual(registry.requests(to: planningRPC).count, 1, "\(vecteur.trigger) : une seule requête, aucun renvoi")
            XCTAssertTrue(registry.unmatched.isEmpty)
        }
    }

    func testExceptionCodeDuTravailInterceptéeAussiSansParametre() async throws {
        let message = refusCodeDuTravail[0].message
        registry.add("POST", "/rest/v1/rpc/fn_test_jsonb",
                     respond: .json(400, exceptionPostgREST(sqlstate: "P0001", details: nil, message: message)))
        let r = try await RPCResponse.appeler(TestClient.make(), "fn_test_jsonb", fallback: fallback)
        XCTAssertEqual(r.issueCandidatureRefusee(fallback: fallback),
                       .refusee(code: CandidatureOutcome.codeRefusCodeDuTravail, message: message, documentsRequisPour: nil))
        XCTAssertEqual(registry.requests(to: "/rest/v1/rpc/fn_test_jsonb").count, 1)
    }

    func testExceptionSansMarqueurResteUneErreurGenerique() async throws {
        // `fn_confirmer_action_planning_v1` l.24311 : texte technique, jamais affiché.
        registry.add("POST", planningRPC,
                     respond: .json(400, exceptionPostgREST(sqlstate: "P0001", details: nil, message: "Action planning non traitée")))
        do {
            _ = try await RPCResponse.appeler(TestClient.make(), "fn_confirmer_action_planning_v1",
                                              params: ["p_action": .string("ACCEPTER")], fallback: fallback)
            XCTFail("attendu : erreur générique")
        } catch let error as JoleneError {
            XCTAssertEqual(error, JoleneError(.unknown, fallback))
        }
        XCTAssertEqual(registry.requests(to: planningRPC).count, 1)
    }

    func testMarqueurCodeDuTravailCommeLeWeb() {
        // Parité `estBlocageCodeTravail` (`src/lib/erreurs.ts` l.586-588) : `includes`, sensible à la casse.
        XCTAssertTrue(RPCResponse.estRefusCodeDuTravail(refusCodeDuTravail[1].message))
        XCTAssertTrue(RPCResponse.estRefusCodeDuTravail("ERREUR : [CODE DU TRAVAIL] Semaine du 02/11/2026"))
        XCTAssertFalse(RPCResponse.estRefusCodeDuTravail("CODE DU TRAVAIL Semaine du 02/11/2026"))
        XCTAssertFalse(RPCResponse.estRefusCodeDuTravail("[code du travail] Semaine du 02/11/2026"))
        XCTAssertFalse(RPCResponse.estRefusCodeDuTravail(
            "[PLANNING_HEBDOMADAIRE_INDISPONIBLE] Mission 6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b : 3 créneau(x) valide(s) sur 5 attendu(s)"))
    }

    func testSupabaseErrorMappingResteInchange() {
        // L'interception vit dans `RPCResponse.appeler`, avant le mapping du lot 0, qui reste tel quel.
        let erreur = PostgrestError(code: "P0001", message: refusCodeDuTravail[0].message)
        XCTAssertEqual(SupabaseErrorMapping.map(erreur, fallback: fallback), JoleneError(.unknown, fallback))
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
