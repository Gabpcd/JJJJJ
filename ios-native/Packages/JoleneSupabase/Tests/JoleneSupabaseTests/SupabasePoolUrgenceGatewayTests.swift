import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Pool urgence sur Supabase (L4-T11) — fiches `fn_pool_urgence_missions_pour_soignant`, `fn_toggle_pool_urgence`,
/// `fn_toggle_pool_urgence_sms` de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` :
/// - état complété par `missions(id, nb_creneaux, duree_heures)` et les créneaux PREVISIONNEL (planning exact dérivé) ;
/// - bascule : `p_creneaux = []`, refus « rayon » et « documents » verbatim, rayon hors 1-200 jamais envoyé ;
/// - chaque bascule acceptée est suivie de la relecture de l'état ; « Non authentifié » → session expirée.
final class SupabasePoolUrgenceGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let etatRPC = "/rest/v1/rpc/fn_pool_urgence_missions_pour_soignant"
    private let basculerRPC = "/rest/v1/rpc/fn_toggle_pool_urgence"
    private let smsRPC = "/rest/v1/rpc/fn_toggle_pool_urgence_sms"
    private let missionId = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabasePoolUrgenceGateway { SupabasePoolUrgenceGateway(client: TestClient.make()) }

    private func etatJSON(actif: Bool = true, rayon: Int = 15, statut: String? = nil) -> String {
        let statutJSON = statut.map { "\"\($0)\"" } ?? "null"
        return #"{"missions":[{"id":"\#(missionId)","intitule":"Nuit urgente","profession_requise":"IDE","specialite_medicale_requise":null,"type_contrat_recherche":"SALARIE","taux_horaire_base":27.5,"debut_le":"2026-12-01T19:00:00+00:00","fin_le":"2026-12-02T07:00:00+00:00","service":"Urgences","etablissement_nom":"Clinique fictive","etablissement_ville":"Paris","distance_km":4.2,"deja_candidate":\#(statut == nil ? "false" : "true"),"statut_candidature":\#(statutJSON)},{"intitule":"ligne illisible"}],"pool_actif":\#(actif),"rayon_km":\#(rayon),"sms_opt_in":false}"#
    }

    private func complements(creneaux: Bool = true) {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, #"[{"id":"\#(missionId)","nb_creneaux":1,"duree_heures":12}]"#))
        if creneaux {
            registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(
                200, #"[{"id":"s1","mission_id":"\#(missionId)","debut":"2026-12-01T19:00:00+00:00","fin":"2026-12-02T07:00:00+00:00","est_pause":false,"type_creneau":"PREVISIONNEL"}]"#,
                headers: ["Content-Range": "0-0/1"]))
        }
    }

    private func erreur(_ operation: () async throws -> Void) async -> JoleneError? {
        do {
            try await operation()
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
            return nil
        }
    }

    private func corps(_ chemin: String) throws -> [String: Any] {
        try XCTUnwrap(registry.requests(to: chemin).first?.bodyJSON as? [String: Any], "requête \(chemin) attendue")
    }

    // MARK: - État

    func testEtatDecodeLesMissionsEtDeriveLePlanningExact() async throws {
        registry.add("POST", etatRPC, respond: .json(200, etatJSON(statut: "EN_ATTENTE_VALIDATION_ETAB")))
        complements()
        let etat = try await gateway().etat(context: TestClient.context)
        XCTAssertTrue(etat.actif)
        XCTAssertEqual(etat.rayonKm, 15)
        XCTAssertFalse(etat.smsOptIn)
        XCTAssertEqual(etat.missions.map(\.id), [missionId], "ligne illisible écartée seule")
        let mission = try XCTUnwrap(etat.missions.first)
        XCTAssertTrue(mission.mission.planningExact, "planning exact dérivé des créneaux relus")
        XCTAssertEqual(mission.statutCandidature, "EN_ATTENTE_VALIDATION_ETAB")
        XCTAssertTrue(mission.dejaCandidate)
        XCTAssertEqual(mission.mission.distanceKm, 4.2)
        XCTAssertEqual(mission.mission.record.nbCreneaux, 1)
        XCTAssertEqual(mission.mission.etablissement?.nom, "Clinique fictive")
        XCTAssertEqual(PoolUrgenceRegles.libelleStatut(mission), PoolUrgenceTextes.statutEnAttente)
        XCTAssertEqual(registry.requests(to: "/rest/v1/missions").first?.query("select"), "id,nb_creneaux,duree_heures")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testCreneauxIllisiblesRendentLePlanningNonExactJamaisAcceptable() async throws {
        registry.add("POST", etatRPC, respond: .json(200, etatJSON()))
        complements(creneaux: false)
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(500, #"{"message":"boom"}"#))
        let etat = try await gateway().etat(context: TestClient.context)
        let mission = try XCTUnwrap(etat.missions.first)
        XCTAssertFalse(mission.mission.planningExact)
        XCTAssertFalse(PoolUrgenceRegles.acceptable(mission), "planning non vérifié : acceptation impossible (web l.85-87)")
    }

    func testEtatNonAuthentifieOuIllisible() async {
        registry.add("POST", etatRPC, respond: .json(200, #"{"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().etat(context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)

        registry.reset()
        registry.add("POST", etatRPC, respond: .json(200, #"{"error":"Profil soignant introuvable"}"#))
        let profil = await erreur { _ = try await self.gateway().etat(context: TestClient.context) }
        XCTAssertEqual(profil?.message, "Profil soignant introuvable", "refus verbatim")

        registry.reset()
        registry.add("POST", etatRPC, respond: .json(200, #"{"missions":[],"pool_actif":true}"#))
        let forme = await erreur { _ = try await self.gateway().etat(context: TestClient.context) }
        XCTAssertEqual(forme?.kind, .contract, "drapeaux absents : jamais un état plausible")
    }

    // MARK: - Bascules

    func testBasculeEnvoieCreneauxVidesPuisRelitLEtat() async throws {
        registry.add("POST", basculerRPC, respond: .json(200, #"{"success":true,"disponible_urgence":true,"documents_salarie_ok":true,"documents_liberal_ok":false}"#))
        registry.add("POST", etatRPC, respond: .json(200, etatJSON()))
        complements()
        let issue = try await gateway().basculer(actif: true, rayonKm: 15, context: TestClient.context)
        guard case .relu(let etat) = issue else { return XCTFail("relecture attendue, obtenu \(issue)") }
        XCTAssertTrue(etat.actif)
        XCTAssertEqual(etat.rayonKm, 15)
        let params = try corps(basculerRPC)
        XCTAssertEqual(params["p_actif"] as? Bool, true)
        XCTAssertEqual(params["p_rayon_km"] as? Int, 15)
        XCTAssertEqual((params["p_creneaux"] as? [Any])?.count, 0, "p_creneaux = [] comme le web (l.65-69)")
        XCTAssertEqual(registry.requests(to: basculerRPC).count, 1)
        XCTAssertEqual(registry.requests(to: etatRPC).count, 1, "relecture après la bascule")
    }

    func testRefusRayonEtDocumentsVerbatimSansRelecture() async throws {
        for message in ["Le rayon doit être compris entre 1 et 200 km.",
                        "Validez les documents d’au moins un type de mission (salariée ou libérale) pour rejoindre le pool urgence."] {
            registry.reset()
            registry.add("POST", basculerRPC, respond: .json(
                200, #"{"error":"\#(message)","documents_salarie_ok":false,"documents_liberal_ok":false}"#))
            let issue = try await gateway().basculer(actif: true, rayonKm: 30, context: TestClient.context)
            XCTAssertEqual(issue, .refuse(message: message))
            XCTAssertTrue(registry.requests(to: etatRPC).isEmpty, "aucune relecture d'un refus")
        }
        XCTAssertEqual(PoolUrgenceRegles.refusDocuments,
                       "Validez les documents d’au moins un type de mission (salariée ou libérale) pour rejoindre le pool urgence.")
    }

    func testRayonHorsBornesServeurJamaisEnvoye() async throws {
        for rayon in [0, 201, -5] {
            registry.reset()
            let issue = try await gateway().basculer(actif: true, rayonKm: rayon, context: TestClient.context)
            XCTAssertEqual(issue, .refuse(message: "Le rayon doit être compris entre 1 et 200 km."), "mots du serveur")
            XCTAssertTrue(registry.requests.isEmpty, "rayon \(rayon) : aucune requête")
        }
    }

    func testBasculeNonAuthentifieeEtReponseSansDrapeau() async {
        registry.add("POST", basculerRPC, respond: .json(200, #"{"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().basculer(actif: false, rayonKm: 15, context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)
        registry.reset()
        registry.add("POST", basculerRPC, respond: .json(200, #"{"disponible_urgence":true}"#))
        let forme = await erreur { _ = try await self.gateway().basculer(actif: true, rayonKm: 15, context: TestClient.context) }
        XCTAssertEqual(forme?.kind, .contract, "ni succès ni refus : jamais un succès supposé")
        XCTAssertTrue(registry.requests(to: etatRPC).isEmpty)
    }

    func testSMSPuisRelecture() async throws {
        registry.add("POST", smsRPC, respond: .json(200, #"{"success":true,"pool_urgence_sms_opt_in":true}"#))
        registry.add("POST", etatRPC, respond: .json(200, etatJSON()))
        complements()
        let issue = try await gateway().basculerSMS(true, context: TestClient.context)
        guard case .relu = issue else { return XCTFail("relecture attendue") }
        XCTAssertEqual(try corps(smsRPC)["p_actif"] as? Bool, true)
        XCTAssertEqual(Set(try corps(smsRPC).keys), ["p_actif"])

        registry.reset()
        registry.add("POST", smsRPC, respond: .json(200, #"{"success":false,"error":"Profil soignant introuvable"}"#))
        let refus = try await gateway().basculerSMS(false, context: TestClient.context)
        XCTAssertEqual(refus, .refuse(message: "Profil soignant introuvable"))
    }
}
