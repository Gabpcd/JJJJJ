import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Notation rapide (lot 2, T5a) et fiche du détail des présences sur Supabase : corps exact de
/// `fn_creer_notation_mission` (sept clés, `NotationRapide.tsx` l.48-53), une seule requête, refus traduits comme le web
/// (« déjà notée » silencieux, refus verbatim, `P0001` verbatim, « Non authentifié » → session expirée), relecture de
/// `fin_le` ; aucune lecture de `notations_missions` (écriture seule, filtre centralisé `evaluations_publiees`) ; fiche du
/// détail par projections imposées (jamais `select=*`).
final class SupabaseNotationGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let rpcPath = "/rest/v1/rpc/fn_creer_notation_mission"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseNotationGateway { SupabaseNotationGateway(client: TestClient.make()) }

    // MARK: - fn_creer_notation_mission

    func testCorpsExactNoteRepliqueeEtSucces() async throws {
        registry.add("POST", rpcPath, respond: .json(200, #"{"success":true,"id":"n-1","tardive":false}"#))
        let issue = try await gateway().noter(missionId: "m-1", note: 4, criteres: nil, context: TestClient.context)
        XCTAssertEqual(issue, .enregistree)
        let appels = registry.requests(to: rpcPath)
        XCTAssertEqual(appels.count, 1, "une seule requête")
        let corps = try XCTUnwrap(appels.first?.bodyJSON as? [String: Any])
        XCTAssertEqual(Set(corps.keys), ["p_mission_id", "p_sens", "p_critere_1", "p_critere_2", "p_critere_3", "p_critere_4", "p_commentaire"])
        XCTAssertEqual(corps["p_mission_id"] as? String, "m-1")
        XCTAssertEqual(corps["p_sens"] as? String, "SOIGNANT_VERS_ETAB")
        XCTAssertEqual([1, 2, 3, 4].map { corps["p_critere_\($0)"] as? Int }, [4, 4, 4, 4], "note globale répliquée (l.47)")
        XCTAssertTrue(corps["p_commentaire"] is NSNull, "aucun commentaire : null (l.52)")
        XCTAssertTrue(registry.requests.allSatisfy { !$0.path.contains("notations_missions") }, "aucune lecture de note")
    }

    func testCriteresDetailles() async throws {
        registry.add("POST", rpcPath, respond: .json(200, #"{"success":true,"id":"n-1","tardive":true}"#))
        _ = try await gateway().noter(missionId: "m-1", note: 1, criteres: CriteresNotation(5, 4, 3, 2), context: TestClient.context)
        let corps = try XCTUnwrap(registry.requests(to: rpcPath).first?.bodyJSON as? [String: Any])
        XCTAssertEqual([1, 2, 3, 4].map { corps["p_critere_\($0)"] as? Int }, [5, 4, 3, 2])
    }

    func testRefusTraduitsCommeLeWeb() async throws {
        let cas: [(String, IssueNotation)] = [
            (#"{"success":false,"error":"Mission déjà notée pour ce sens"}"#, .dejaNotee),
            (#"{"success":false,"error":"Seules les missions TERMINEE peuvent être notées"}"#,
             .refusee(message: "Seules les missions TERMINEE peuvent être notées")),
            (#"{"success":false,"error":"Notation impossible pendant un litige en médiation ou en revue admin. Vous pourrez noter après résolution."}"#,
             .refusee(message: "Notation impossible pendant un litige en médiation ou en revue admin. Vous pourrez noter après résolution.")),
            (#"{"success":false}"#, .refusee(message: "La note n'a pas pu être enregistrée. Réessayez.")),
        ]
        for (json, attendu) in cas {
            registry.reset()
            registry.add("POST", rpcPath, respond: .json(200, json))
            let issue = try await gateway().noter(missionId: "m-1", note: 3, criteres: nil, context: TestClient.context)
            XCTAssertEqual(issue, attendu, json)
            XCTAssertEqual(registry.requests(to: rpcPath).count, 1)
        }
    }

    func testExceptionP0001VerbatimEtNonAuthentifie() async throws {
        registry.add("POST", rpcPath, respond: .json(RPCResponseExceptionsMetierTests.statut("P0001"),
            #"{"code":"P0001","details":null,"hint":null,"message":"La notation n’a pas pu être enregistrée. Veuillez réessayer."}"#))
        let issue = try await gateway().noter(missionId: "m-1", note: 3, criteres: nil, context: TestClient.context)
        XCTAssertEqual(issue, .refusee(message: "La notation n’a pas pu être enregistrée. Veuillez réessayer."),
                       "exception déclarée : rollback prouvé, message serveur verbatim")
        XCTAssertEqual(registry.requests(to: rpcPath).count, 1, "aucun renvoi")

        registry.reset()
        registry.add("POST", rpcPath, respond: .json(200, #"{"success":false,"error":"Non authentifié"}"#))
        do {
            _ = try await gateway().noter(missionId: "m-1", note: 3, criteres: nil, context: TestClient.context)
            XCTFail("session expirée attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
    }

    func testTransportCoupeEstUneErreurSansRenvoi() async throws {
        registry.add("POST", rpcPath, respond: .networkFailure())
        do {
            _ = try await gateway().noter(missionId: "m-1", note: 3, criteres: nil, context: TestClient.context)
            XCTFail("erreur de transport attendue")
        } catch let erreur as JoleneError {
            XCTAssertNotEqual(erreur.kind, .unauthorized)
        }
        XCTAssertEqual(registry.requests(to: rpcPath).count, 1, "POST jamais rejoué par le SDK")
    }

    // MARK: - fin_le relu

    func testFinPrevueReluePourLaMission() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, #"[{"fin_le":"2026-11-02T06:00:00+00:00"}]"#))
        let fin = try await gateway().finPrevue(missionId: "m-1", context: TestClient.context)
        XCTAssertEqual(fin, "2026-11-02T06:00:00+00:00")
        let lecture = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(lecture.query("select"), "fin_le")
        XCTAssertEqual(lecture.query("id"), "eq.m-1")

        registry.reset()
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[]"))
        let absente = try await gateway().finPrevue(missionId: "m-1", context: TestClient.context)
        XCTAssertNil(absente, "mission illisible : rien n'est proposé")
    }

    // MARK: - Fiche du détail des présences (PointagePort.ficheDetail)

    func testFicheDuDetailProjectionsImposeesEtPremierePresence() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, """
        [{"id":"m-1","intitule":"Nuit","service":"Urgences","debut_le":"2026-10-30T07:00:00+00:00","fin_le":"2026-10-30T15:00:00+00:00",
          "duree_heures":8,"statut":"TERMINEE","etablissement_id":"e-1"}]
        """))
        registry.add("GET", "/rest/v1/presences", respond: .json(200, """
        [{"id":"pr-1","pointage_arrivee_le":"2026-10-30T07:02:00+00:00","valide_par_etablissement":true,"valide_le":"2026-11-01T14:00:00+00:00",
          "distance_etablissement_m":"42.60","perimetre_gps_valide":true,"arrivee_precision_gps_m":12.4,"depart_precision_gps_m":null,
          "alerte_teleportation":false,"heures_ajustees_litige":null}]
        """))
        let gateway = SupabasePointageGateway(client: TestClient.make())
        let fiche = try await gateway.ficheDetail(missionId: "m-1", context: TestClient.context)
        XCTAssertEqual(fiche.mission?.intitule, "Nuit")
        XCTAssertEqual(fiche.mission?.statut, "TERMINEE")
        XCTAssertEqual(fiche.presence, PresenceControlee(id: "pr-1", pointageArriveeLe: "2026-10-30T07:02:00+00:00",
                                                         valideParEtablissement: true, valideLe: "2026-11-01T14:00:00+00:00",
                                                         distanceEtablissementM: 42.6, perimetreGpsValide: true,
                                                         arriveePrecisionGpsM: 12.4, alerteTeleportation: false))
        let missions = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(missions.query("select"), "id,intitule,service,debut_le,fin_le,duree_heures,statut,etablissement_id")
        XCTAssertEqual(missions.query("id"), "eq.m-1")
        let presences = try XCTUnwrap(registry.requests(to: "/rest/v1/presences").first)
        XCTAssertEqual(presences.query("select"), PresenceControlee.selection)
        XCTAssertFalse(presences.query("select")?.contains("*") ?? true, "jamais select=*")
        for interdite in ["latitude", "longitude", "code"] {
            XCTAssertFalse(presences.query("select")?.contains(interdite) ?? true, "\(interdite) jamais lue")
        }
        XCTAssertEqual(presences.query("mission_id"), "eq.m-1")
        // supabase-swift écrit `nullslast`, défaut de PostgreSQL pour un tri croissant : même ordre que `order=…asc` du web.
        XCTAssertEqual(presences.query("order"), "pointage_arrivee_le.asc.nullslast")
        XCTAssertEqual(presences.query("limit"), "1")
    }

    func testFicheSansMissionNiPresence() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[]"))
        registry.add("GET", "/rest/v1/presences", respond: .json(200, "[]"))
        let fiche = try await SupabasePointageGateway(client: TestClient.make()).ficheDetail(missionId: "m-1", context: TestClient.context)
        XCTAssertEqual(fiche, FicheDetailPresences(mission: nil, presence: nil), "« Mission introuvable »")
    }
}
