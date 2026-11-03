import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Réponses jsonb des RPC établissement (lot 5 T1, §2.5) : `message` prioritaire pour un code de
/// blocage de publication (correction 8), `{error}` sans drapeau verbatim, issues de
/// `fn_traiter_candidature_planning_v1` sans succès supposé.
final class RPCResponseEtablissementTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let fallback = "Impossible de traiter cette candidature. Réessayez."
    private let rpcTraiter = "fn_traiter_candidature_planning_v1"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func reponse(_ json: String) throws -> RPCResponse {
        RPCResponse(try JSONDecoder().decode(AnyJSON.self, from: Data(json.utf8)))
    }

    private func issue(_ json: String, _ decision: DecisionCandidature = .acceptee) throws -> TraitementCandidatureOutcome {
        try reponse(json).issueTraitementCandidature(decision: decision, fallback: fallback)
    }

    private func leve(_ appel: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) -> JoleneError? {
        do {
            try appel()
            XCTFail("attendu : erreur levée", file: file, line: line)
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: - Blocage de publication (correction 8)

    func testCodeDeBlocageMessagePrioritaire() throws {
        let r = try reponse(#"{"error":"CONTRAT_SERVICE_REQUIS","message":"Le contrat de service Jolene doit être signé avant de publier des missions."}"#)
        XCTAssertEqual(r.messageRefus, "Le contrat de service Jolene doit être signé avant de publier des missions.")
        XCTAssertEqual(r.blocagePublication?.code, "CONTRAT_SERVICE_REQUIS")
        XCTAssertEqual(r.blocagePublication?.message, "Le contrat de service Jolene doit être signé avant de publier des missions.")
        // `PUBLICATION_SUSPENDUE` porte aussi des raisons chiffrées : jamais lues.
        let suspendue = try reponse("""
        {"error":"PUBLICATION_SUSPENDUE","message":"Publication suspendue en raison d obligations de paiement à régulariser.",
         "bloque_auto_le":"2026-11-01T07:00:00+00:00","raisons":{"montant_du":1200}}
        """)
        XCTAssertEqual(suspendue.messageRefus, "Publication suspendue en raison d obligations de paiement à régulariser.")
    }

    func testErreurOrdinaireRestePrioritaire() throws {
        XCTAssertEqual(try reponse(#"{"success":false,"error":"L'intitulé est obligatoire.","message":"autre"}"#).messageRefus,
                       "L'intitulé est obligatoire.", "hors code de blocage, `error` reste le texte affiché")
        XCTAssertNil(try reponse(#"{"error":"CONTRAT_SERVICE_REQUIS"}"#).blocagePublication, "code sans message : pas de blocage lisible")
        XCTAssertNil(try reponse(#"{"success":true,"error":"CONTRAT_SERVICE_REQUIS","message":"x"}"#).blocagePublication)
        XCTAssertNil(try reponse(#"{"success":true}"#).messageRefus)
    }

    func testErreurSansDrapeauEstVerbatimJamaisSessionExpiree() throws {
        // `fn_traiter_candidature` l.61718-61757 : `{error}` sans `success`.
        for message in ["Non autorisé", "Cette candidature a déjà été traitée.", "Mission introuvable"] {
            let r = try reponse(#"{"error":"\#(message)"}"#)
            XCTAssertEqual(leve { try r.leverSiErreur(fallback: self.fallback) }, JoleneError(.unknown, message), message)
            XCTAssertEqual(leve { _ = try r.issueTraitementCandidature(decision: .acceptee, fallback: self.fallback) },
                           JoleneError(.unknown, message), message)
        }
    }

    func testCodesDeBlocageEgauxAuDump() throws {
        let schema = try Depot.texte("supabase/schema/public.sql")
        let entete = "CREATE OR REPLACE FUNCTION \"public\".\"" + "fn_" + "blocage_publication_etab\"("
        let debut = try XCTUnwrap(schema.range(of: entete), "fn_blocage_publication_etab absente du dump")
        let fin = try XCTUnwrap(schema.range(of: "\n$$;", range: debut.upperBound..<schema.endIndex))
        let corps = String(schema[debut.lowerBound..<fin.lowerBound])
        let expression = try NSRegularExpression(pattern: "'error', '([A-Z_]+)',\\s*'message', '((?:[^']|'')*)'")
        let trouves = expression.matches(in: corps, range: NSRange(corps.startIndex..., in: corps)).compactMap { resultat -> String? in
            Range(resultat.range(at: 1), in: corps).map { String(corps[$0]) }
        }
        XCTAssertEqual(trouves.count, 5)
        XCTAssertEqual(Set(trouves), RPCResponse.codesBlocagePublication)
    }

    // MARK: - fn_traiter_candidature_planning_v1

    func testSuccesAcceptationEtRefus() throws {
        XCTAssertEqual(try issue(#"{"success":true,"choix_applique":"SALARIE","contrat_id":"k-1"}"#), .acceptee(contratId: "k-1"))
        XCTAssertEqual(try issue(#"{"success":true}"#), .acceptee(contratId: nil))
        XCTAssertEqual(try issue(#"{"success":true}"#, .refusee), .refusEnregistre)
    }

    func testFormeInattendueEstUnRefusDeContrat() throws {
        for json in ["{}", "null", "[]", #"{"ok":"oui"}"#] {
            XCTAssertEqual(leve { _ = try self.issue(json) }, JoleneError(.contract, SupabaseErrorMapping.contractMessage), json)
        }
    }

    func testNonAuthentifieDevientSessionExpiree() throws {
        XCTAssertEqual(leve { _ = try self.issue(#"{"success":false,"error":"Non authentifié."}"#) }?.kind, .unauthorized)
    }

    func testCadreEtudiant() throws {
        // l.61929-61935 : seul A_CONFIRMER renvoie au web ; les autres codes sont des refus verbatim.
        XCTAssertEqual(try issue(#"{"success":false,"code":"CADRE_ETUDIANT_A_CONFIRMER","error":"Confirmez le cadre."}"#),
                       .cadreEtudiant(code: "CADRE_ETUDIANT_A_CONFIRMER", message: "Confirmez le cadre."))
        for code in ["CADRE_ETUDIANT_PROFESSION_INVALIDE", "CADRE_ETUDIANT_SALARIAT_REQUIS", "CADRE_ETUDIANT_STRUCTURE_INELIGIBLE"] {
            XCTAssertEqual(try issue(#"{"success":false,"code":"\#(code)","error":"Refus serveur."}"#),
                           .refusee(code: code, message: "Refus serveur.", documentsRequisPour: nil), code)
        }
    }

    func testPlanningAReconfirmer() throws {
        for code in ["PLANNING_A_RECONFIRMER", "PLANNING_MODIFIE_RECONFIRMER"] {
            XCTAssertEqual(try issue(#"{"success":false,"code":"\#(code)","error":"Le planning a changé."}"#),
                           .planningAReconfirmer(code: code, message: "Le planning a changé."), code)
        }
    }

    func testRefusRelayesVerbatim() throws {
        // Délégué interne (`{success:false, error}`), choix de contrat, documents requis, `{error, code}`.
        XCTAssertEqual(try issue(#"{"success":false,"error":"Mission introuvable ou accès refusé."}"#),
                       .refusee(code: nil, message: "Mission introuvable ou accès refusé.", documentsRequisPour: nil))
        XCTAssertEqual(try issue(#"{"choix_requis":true,"error":"Choisissez un mode de contrat.","options":[{"value":"SALARIE","label":"Salarié"}]}"#),
                       .refusee(code: nil, message: "Choisissez un mode de contrat.", documentsRequisPour: nil))
        XCTAssertEqual(try issue(#"{"error":"Documents à valider.","documents_requis_pour":"SALARIE","lien_documents":"/x"}"#),
                       .refusee(code: nil, message: "Documents à valider.", documentsRequisPour: "SALARIE"))
        XCTAssertEqual(try issue(#"{"error":"Plafond atteint.","code":"PLAFOND_48H_HEBDO"}"#),
                       .refusee(code: "PLAFOND_48H_HEBDO", message: "Plafond atteint.", documentsRequisPour: nil))
        XCTAssertEqual(try issue(#"{"success":false}"#),
                       .refusee(code: nil, message: fallback, documentsRequisPour: nil), "refus sans message : texte générique")
    }

    private func exceptionPostgREST(_ status: Int, _ sqlstate: String, _ message: String) -> StubResponse {
        .json(status, #"{"code":"\#(sqlstate)","details":null,"hint":null,"message":"\#(message)"}"#)
    }

    private func appelerTraiter(_ stub: StubResponse) async throws -> RPCResponse {
        registry.add("POST", "/rest/v1/rpc/\(rpcTraiter)", respond: stub)
        return try await RPCResponse.appeler(TestClient.make(), rpcTraiter, params: ["p_decision": .string("ACCEPTEE")],
                                             fallback: fallback, interceptions: ListesBlanchesEtablissement.interceptions(rpc: rpcTraiter))
    }

    func testExceptionsInterceptees() async throws {
        let paiement = "Cette mission ne peut pas être attribuée : le mandat SEPA de l'établissement n'est pas encore posé (IBAN à ajouter dans Paramètres → Facturation)."
        let r = try await appelerTraiter(exceptionPostgREST(400, "P0001", paiement))
        XCTAssertEqual(try r.issueTraitementCandidature(decision: .acceptee, fallback: fallback), .paiementNonConfigure(message: paiement))

        registry.reset()
        let rbac = try await appelerTraiter(exceptionPostgREST(403, "42501", "Permission etablissement candidatures requise"))
        XCTAssertEqual(try rbac.issueTraitementCandidature(decision: .refusee, fallback: fallback),
                       .accesRefuse(message: RPCInterception.messageRoleInsuffisant))

        registry.reset()
        let travail = "[CODE DU TRAVAIL] Repos insuffisant avant mission : 8.5 heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée."
        let t = try await appelerTraiter(exceptionPostgREST(400, "23514", travail))
        XCTAssertEqual(try t.issueTraitementCandidature(decision: .acceptee, fallback: fallback),
                       .refusee(code: CandidatureOutcome.codeRefusCodeDuTravail, message: travail, documentsRequisPour: nil))
    }

    func testRefusMetierHorsPaiementJamaisAfficheCommePaiement() throws {
        // Défense : un refus métier intercepté qui n'est pas un refus de paiement reste générique.
        let r = RPCInterception.refus(code: RPCInterception.codeRefusMetier, sqlstate: "P0001", message: "Autre refus")
        XCTAssertEqual(leve { _ = try r.issueTraitementCandidature(decision: .acceptee, fallback: self.fallback) },
                       JoleneError(.unknown, fallback))
    }
}
