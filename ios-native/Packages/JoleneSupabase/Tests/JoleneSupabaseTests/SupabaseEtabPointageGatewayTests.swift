import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Pointage terrain de l'établissement sur Supabase (lot 5, T7) : état (`fn_etat_pointage_mission`, corps exact, décodage
/// en liste blanche, refus jsonb verbatim sans aucune autre clé), signature (`fn_contrat_signe_pour_pointage` : booléen
/// exigé, 42501 de la liste blanche → `false`), planning (mission de l'établissement confirmé sans montant, créneaux
/// PREVISIONNEL hors pause), identifiant canonique exigé avant réseau. Aucune clé de la réponse du scanner n'est lue.
final class SupabaseEtabPointageGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let etab = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let missionId = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
    private let rpcEtat = "/rest/v1/rpc/fn_etat_pointage_mission"
    private let rpcContrat = "/rest/v1/rpc/fn_contrat_signe_pour_pointage"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseEtabPointageGateway { SupabaseEtabPointageGateway(client: TestClient.make()) }

    private func contexte() -> EtablissementReadContext {
        EtablissementReadContext(userId: TestClient.userId, etablissementId: etab, roleEtab: .pointageOnly,
                                 permissions: PermissionsEtab(accordees: [.lecture, .pointage]), epoch: 1)
    }

    private func exception(_ sqlstate: String, _ message: String) -> String {
        #"{"code":"\#(sqlstate)","details":null,"hint":null,"message":"\#(message)"}"#
    }

    private func echec(_ appel: () async throws -> Void) async -> Error? {
        do {
            try await appel()
            XCTFail("attendu : erreur levée")
            return nil
        } catch {
            return error
        }
    }

    // MARK: - État

    func testEtatCorpsExactEtDecodageEnListeBlanche() async throws {
        registry.add("POST", rpcEtat, respond: .json(200, #"""
        {"statut":"EN_COURS","intitule":"Nuit","prochain_type_scan":"FERMETURE","nb_scans":1,"segment_ouvert":true,
         "segments":[{"id":"s-1","debut":"2026-11-03T07:02:00.123456+00:00","fin":null}],
         "code_pointage_actif":"100002","est_etab":true}
        """#))
        let etat = try await gateway().etat(missionId: missionId.uppercased(), context: contexte())
        XCTAssertEqual(etat, EtatPointageEtab(statut: "EN_COURS", prochainTypeScan: "FERMETURE", segmentOuvert: true,
                                              segments: [.init(id: "s-1", debut: "2026-11-03T07:02:00.123456+00:00", fin: nil)],
                                              codePointageActif: "100002"))
        let requete = try XCTUnwrap(registry.requests(to: rpcEtat).first)
        XCTAssertEqual(requete.bodyJSON as? [String: String], ["p_mission_id": missionId], "uuid canonique, un seul argument")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testEtatRefusJsonbVerbatimSansAucuneAutreCle() async throws {
        registry.add("POST", rpcEtat, respond: .json(200, #"{"error":"Accès interdit","code_pointage_actif":"123456","statut":"ASSIGNEE"}"#))
        let refus = try await gateway().etat(missionId: missionId, context: contexte())
        XCTAssertEqual(refus.erreur, "Accès interdit")
        XCTAssertNil(refus.codePointageActif, "jamais un code à côté d'un refus")
        XCTAssertNil(refus.statut)

        registry.reset()
        registry.add("POST", rpcEtat, respond: .json(200, #"{"error":"Mission introuvable"}"#))
        let introuvable = try await gateway().etat(missionId: missionId, context: contexte())
        XCTAssertEqual(introuvable.erreur, "Mission introuvable")

        registry.reset()
        registry.add("POST", rpcEtat, respond: .json(200, #"[1,2]"#))
        let erreur = await echec { _ = try await self.gateway().etat(missionId: self.missionId, context: self.contexte()) }
        XCTAssertEqual((erreur as? JoleneError)?.kind, .contract, "forme inattendue : refus de contrat")
    }

    func testIdentifiantNonCanoniqueRefuseAvantReseau() async throws {
        for appel in [
            { _ = try await self.gateway().etat(missionId: "demo-etab-m04", context: self.contexte()) },
            { _ = try await self.gateway().contratSigne(missionId: "00000000-0000-0000-0000-000000000000", context: self.contexte()) },
            { _ = try await self.gateway().planning(missionId: "", context: self.contexte()) },
        ] as [() async throws -> Void] {
            let erreur = await echec(appel)
            XCTAssertEqual((erreur as? JoleneError)?.kind, .contract)
        }
        XCTAssertTrue(registry.requests(to: rpcEtat).isEmpty && registry.requests(to: rpcContrat).isEmpty
                      && registry.requests(to: "/rest/v1/missions").isEmpty)
    }

    // MARK: - Signature

    func testSignatureBooleenExigeEt42501VautFaux() async throws {
        registry.add("POST", rpcContrat, respond: .json(200, "true"))
        let signe = try await gateway().contratSigne(missionId: missionId, context: contexte())
        XCTAssertTrue(signe)
        XCTAssertEqual(registry.requests(to: rpcContrat).first?.bodyJSON as? [String: String], ["p_mission_id": missionId])

        registry.reset()
        registry.add("POST", rpcContrat, respond: .json(200, "false"))
        let nonSigne = try await gateway().contratSigne(missionId: missionId, context: contexte())
        XCTAssertFalse(nonSigne)

        registry.reset()
        registry.add("POST", rpcContrat, respond: .json(403, exception("42501", "Lecture du pointage non autorisée.")))
        let refuse = try await gateway().contratSigne(missionId: missionId, context: contexte())
        XCTAssertFalse(refuse, "liste blanche : fail-closed, aucun code d'arrivée")

        registry.reset()
        registry.add("POST", rpcContrat, respond: .json(200, #"{"signe":true}"#))
        let erreur = await echec { _ = try await self.gateway().contratSigne(missionId: self.missionId, context: self.contexte()) }
        XCTAssertEqual(erreur as? JoleneError, JoleneError(.contract, "État de signature indisponible."), "web l.158")
    }

    // MARK: - Planning

    func testPlanningMissionDeLEtablissementConfirmeSansMontant() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, #"""
        {"id":"\#(missionId)","debut_le":"2026-11-03T07:00:00+00:00","fin_le":"2026-11-03T15:00:00+00:00","nb_creneaux":1,"etablissement_id":"\#(etab)"}
        """#))
        let creneau = TestClient.slotJSON(id: "c-1", missionId: missionId, debut: "2026-11-03T07:00:00+00:00", fin: "2026-11-03T15:00:00+00:00")
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[\(creneau)]", headers: ["Content-Range": "0-0/1"]))
        let planning = try await gateway().planning(missionId: missionId, context: contexte())
        XCTAssertEqual(planning.mission, MissionAvecPlanningAttendu(id: missionId, debutLe: "2026-11-03T07:00:00+00:00",
                                                                    finLe: "2026-11-03T15:00:00+00:00", nbCreneaux: 1))
        XCTAssertEqual(planning.creneaux.map(\.id), ["c-1"])
        let mission = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(mission.query("select"), "id,debut_le,fin_le,nb_creneaux,etablissement_id", "aucun montant lu")
        XCTAssertEqual(mission.query("etablissement_id"), "eq.\(etab)", "établissement confirmé")
        XCTAssertEqual(mission.query("id"), "eq.\(missionId)")
        let creneaux = try XCTUnwrap(registry.requests(to: "/rest/v1/mission_creneaux").first)
        XCTAssertEqual(creneaux.query("type_creneau"), "eq.PREVISIONNEL")
        XCTAssertEqual(creneaux.query("est_pause"), "eq.false")
    }

    func testPlanningMissionIllisibleOuDUnAutreEtablissementRefuse() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(406, #"{"code":"PGRST116","details":"The result contains 0 rows","hint":null,"message":"JSON object requested, multiple (or no) rows returned"}"#))
        let absente = await echec { _ = try await self.gateway().planning(missionId: self.missionId, context: self.contexte()) }
        XCTAssertNotNil(absente, "mission illisible sous RLS : planning indisponible, code masqué")

        registry.reset()
        registry.add("GET", "/rest/v1/missions", respond: .json(200, #"""
        {"id":"\#(missionId)","debut_le":null,"fin_le":null,"nb_creneaux":1,"etablissement_id":"00000000-1111-4222-8333-444444444444"}
        """#))
        let autre = await echec { _ = try await self.gateway().planning(missionId: self.missionId, context: self.contexte()) }
        XCTAssertEqual((autre as? JoleneError)?.kind, .contract)
        XCTAssertTrue(registry.requests(to: "/rest/v1/mission_creneaux").isEmpty, "aucun créneau lu pour une mission non confirmée")
    }

    func testPortCableDansLeMondeSupabaseEtCadenceNominale() {
        let ports = SupabaseEtablissementGateways.make(client: TestClient.make())
        XCTAssertTrue(ports.pointage is SupabaseEtabPointageGateway)
        XCTAssertEqual(ports.pointage.cadenceLecture, 5, "D23 : jamais une autre cadence hors démo")
    }
}
