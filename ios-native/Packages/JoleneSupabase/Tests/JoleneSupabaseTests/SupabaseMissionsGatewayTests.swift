import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

final class SupabaseMissionsGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21T14:13:20Z

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseMissionsGateway {
        SupabaseMissionsGateway(client: TestClient.make(), clock: FixedClock(now))
    }

    private func stubEnrichment(slots: [String], count: Int) {
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: .json(200, TestClient.etablissementJSON))
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(
            200, "[\(slots.joined(separator: ","))]", headers: ["Content-Range": "0-\(max(count - 1, 0))/\(count)"]
        ))
    }

    // MARK: - Profil

    func testProfileReturnsRowMatchingSession() async throws {
        registry.add("GET", "/rest/v1/soignants", respond: .json(200, """
        {"id":"\(TestClient.userId)","profession":"IADE","adresse_lat":45.75,"adresse_lng":4.85,"rayon_deplacement_km":30,
         "tous_documents_valides":true,"type_contrat":"SALARIE","types_contrat_acceptes":null,"type_exercice":"SALARIE","taux_horaire_minimum":25}
        """))
        let profile = try await gateway().profile(userId: TestClient.userId)
        XCTAssertEqual(profile, TestClient.profile)
        let request = try XCTUnwrap(registry.requests(to: "/rest/v1/soignants").first)
        XCTAssertEqual(request.query("select"), MissionQuery.profileSelect)
        XCTAssertEqual(request.query("id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(request.header("Accept"), "application/vnd.pgrst.object+json")
    }

    func testProfileWithoutProfessionIsNil() async throws {
        registry.add("GET", "/rest/v1/soignants", respond: .json(200, """
        {"id":"\(TestClient.userId)","profession":"","adresse_lat":null,"adresse_lng":null,"rayon_deplacement_km":null,
         "tous_documents_valides":false,"type_contrat":null,"types_contrat_acceptes":null,"type_exercice":null,"taux_horaire_minimum":null}
        """))
        let profile = try await gateway().profile(userId: TestClient.userId)
        XCTAssertNil(profile)
    }

    func testProfileWithNullProfessionAndDocumentsIsNil() async throws {
        registry.add("GET", "/rest/v1/soignants", respond: .json(200, """
        {"id":"\(TestClient.userId)","profession":null,"adresse_lat":null,"adresse_lng":null,"rayon_deplacement_km":null,
         "tous_documents_valides":null,"type_contrat":null,"types_contrat_acceptes":null,"type_exercice":null,"taux_horaire_minimum":null}
        """))
        let profile = try await gateway().profile(userId: TestClient.userId)
        XCTAssertNil(profile, "profession NULL = inscription non terminée, jamais une erreur de chargement")
    }

    func testProfileMissingRowIsNil() async throws {
        // PostgREST maybeSingle sans ligne : 406 + PGRST116 « 0 rows ».
        registry.add("GET", "/rest/v1/soignants", respond: .json(406, """
        {"code":"PGRST116","details":"The result contains 0 rows","hint":null,"message":"JSON object requested, multiple (or no) rows returned"}
        """))
        let profile = try await gateway().profile(userId: TestClient.userId)
        XCTAssertNil(profile)
    }

    func testProfileIdMismatchIsContractError() async throws {
        registry.add("GET", "/rest/v1/soignants", respond: .json(200, """
        {"id":"autre-id","profession":"IDE","adresse_lat":null,"adresse_lng":null,"rayon_deplacement_km":null,
         "tous_documents_valides":false,"type_contrat":null,"types_contrat_acceptes":null,"type_exercice":null,"taux_horaire_minimum":null}
        """))
        do {
            _ = try await gateway().profile(userId: TestClient.userId)
            XCTFail("attendu : refus")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
        }
    }

    // MARK: - Liste

    func testListMissionsSinglePageBuildsPilotQueryAndEnriches() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(TestClient.missionJSON)]"))
        stubEnrichment(slots: [
            TestClient.slotJSON(id: "s-1", missionId: "m-1", debut: "2026-12-01T19:00:00+00:00", fin: "2026-12-02T01:00:00+00:00"),
            TestClient.slotJSON(id: "s-2", missionId: "m-1", debut: "2026-12-02T01:00:00+00:00", fin: "2026-12-02T07:00:00+00:00"),
        ], count: 2)

        let missions = try await gateway().listMissions(context: TestClient.context, filters: MissionFilters())

        // Requête missions : exactement celle du pilote.
        let request = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.query("select"), MissionQuery.missionSelect)
        XCTAssertEqual(request.query("statut"), "eq.OUVERTE")
        XCTAssertEqual(request.query("debut_le"), "gte.2026-09-21T14:13:20.000Z")
        XCTAssertEqual(request.query("or"), "(profession_requise.eq.IADE,profession_requise.eq.IDE)")
        XCTAssertNil(request.query("profession_requise"))
        XCTAssertEqual(request.query("taux_horaire_base"), "gte.25.0", "tauxMin par défaut = taux_horaire_minimum du profil")
        XCTAssertNil(request.query("est_urgente"))
        XCTAssertNil(request.query("etablissement_id"))
        // Ordre du pilote : `est_urgente.desc` sans suffixe côté supabase-js = NULLS FIRST (défaut Postgres
        // sur DESC), encodé explicitement ici ; `debut_le` est NOT NULL, `.nullslast` y est sans effet.
        XCTAssertEqual(request.query("order"), "boostee_le.desc.nullslast,est_urgente.desc.nullsfirst,debut_le.asc.nullslast")
        XCTAssertEqual(request.query("limit"), "500")

        // Établissements : RPC avec les ids uniques.
        let rpc = try XCTUnwrap(registry.requests(to: "/rest/v1/rpc/fn_etablissements_safe").first)
        let body = try XCTUnwrap(rpc.bodyJSON as? [String: Any])
        XCTAssertEqual(body["p_ids"] as? [String], ["etab-1"])

        // Créneaux : lot unique, page unique, compte exact.
        let slots = try XCTUnwrap(registry.requests(to: "/rest/v1/mission_creneaux").first)
        XCTAssertEqual(slots.query("select"), MissionQuery.slotSelect)
        XCTAssertEqual(slots.query("mission_id"), "in.(m-1)")
        XCTAssertEqual(slots.query("type_creneau"), "eq.PREVISIONNEL")
        XCTAssertEqual(slots.query("est_pause"), "eq.false")
        XCTAssertEqual(slots.query("order"), "mission_id.asc.nullslast,debut.asc.nullslast,id.asc.nullslast")
        XCTAssertEqual(slots.query("offset"), "0")
        XCTAssertEqual(slots.query("limit"), "500")
        XCTAssertTrue(slots.header("Prefer")?.contains("count=exact") == true)

        // Enrichissement par défaut (MissionBusiness.enrich) puis filtres de présentation (MissionBusiness.filter).
        XCTAssertEqual(missions.count, 1)
        let mission = try XCTUnwrap(missions.first)
        XCTAssertEqual(mission.id, "m-1")
        XCTAssertEqual(mission.record.netAPayer, 300.1, "montant serveur, jamais recalculé")
        XCTAssertEqual(mission.etablissement?.nom, "Clinique des Tests")
        XCTAssertEqual(mission.etablissement?.adresseVille, "Lyon")
        XCTAssertEqual(mission.distanceKm, 1.1)
        XCTAssertEqual(mission.creneauxPlanifies.map { $0.id }, ["s-1", "s-2"])
        XCTAssertTrue(mission.planningExact, "nb_creneaux = 2 et deux créneaux PREVISIONNEL reçus")
        XCTAssertFalse(mission.erreurPlanning)
        XCTAssertTrue(registry.unmatched.isEmpty, "requêtes non stubées : \(registry.unmatched.map(\.path))")
    }

    // MARK: - Filtres de présentation sur le chemin réel (relecture lot 0)

    private func missionJSON(id: String, intitule: String = "Remplacement IDE", etablissementId: String = "etab-1",
                             nbCreneaux: Int = 1, estUrgente: String = "true", statut: String = "\"OUVERTE\"") -> String {
        """
        {"id":"\(id)","intitule":"\(intitule)","description":null,"service":null,"profession_requise":"IDE",
         "specialite_medicale_requise":null,"accepte_non_specialises":null,"debut_le":"2026-12-01T08:00:00+00:00",
         "fin_le":"2026-12-01T16:00:00+00:00","duree_heures":8,"nb_creneaux":\(nbCreneaux),"taux_horaire_base":30,
         "taux_rist_plafonne":null,"rist_plafond_applique":false,"total_brut":null,"net_a_payer":null,"est_urgente":\(estUrgente),
         "niveau_urgence":null,"statut":\(statut),"etablissement_id":"\(etablissementId)","type_contrat_recherche":"SALARIE",
         "boostee_le":null,"mode_remuneration":null,"retrocession_pct":null}
        """
    }

    private let etablissementsLoinEtPres = """
    [{"id":"etab-1","nom":"Clinique des Tests","adresse_code_postal":"69003","adresse_ville":"Lyon","adresse_lat":45.76,"adresse_lng":4.85,"type":"CLINIQUE","logo_url":null},
     {"id":"etab-loin","nom":"Hôpital lointain","adresse_code_postal":"75001","adresse_ville":"Paris","adresse_lat":48.8566,"adresse_lng":2.3522,"type":"HOPITAL","logo_url":null}]
    """

    func testListMissionsHidesPlaywrightFixturesFromOrdinaryAccounts() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(missionJSON(id: "m-pw", intitule: "[pw-test:x] Fixture")),\(missionJSON(id: "m-ok"))]"))
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: .json(200, etablissementsLoinEtPres))
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[]", headers: ["Content-Range": "0-0/0"]))
        let missions = try await gateway().listMissions(context: TestClient.context, filters: MissionFilters())
        XCTAssertEqual(missions.map(\.id), ["m-ok"], "`[pw-test:…]` n'est visible que d'un compte playwright-*")

        let playwright = MissionReadContext(userId: TestClient.userId, email: "playwright-ide@example.test", profile: TestClient.profile)
        let visibles = try await gateway().listMissions(context: playwright, filters: MissionFilters())
        XCTAssertEqual(Set(visibles.map(\.id)), ["m-pw", "m-ok"])
    }

    func testMissionDetailHidesPlaywrightFixtureFromOrdinaryAccount() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, missionJSON(id: "m-pw", intitule: "[playwright-test] Fixture")))
        let mission = try await gateway().mission(id: "m-pw", context: TestClient.context)
        XCTAssertNil(mission)
        XCTAssertTrue(registry.requests(to: "/rest/v1/rpc/fn_etablissements_safe").isEmpty, "aucun enrichissement d'une fixture masquée")
    }

    func testListMissionsPlanningNotExactWhenSlotsDoNotMatchNbCreneaux() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(missionJSON(id: "m-2", nbCreneaux: 2))]"))
        stubEnrichment(slots: [
            TestClient.slotJSON(id: "s-1", missionId: "m-2", debut: "2026-12-01T08:00:00+00:00", fin: "2026-12-01T12:00:00+00:00"),
        ], count: 1)
        let missions = try await gateway().listMissions(context: TestClient.context, filters: MissionFilters())
        let mission = try XCTUnwrap(missions.first)
        XCTAssertFalse(mission.planningExact, "nb_creneaux = 2 avec un seul créneau serveur : planning non exact")
        XCTAssertEqual(mission.creneauxPlanifies.map { $0.id }, ["s-1"], "les créneaux chargés sont conservés tels quels")
    }

    func testListMissionsAppliesRadiusCityAndSortsByDistance() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(missionJSON(id: "m-loin", etablissementId: "etab-loin")),\(missionJSON(id: "m-pres"))]"))
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: .json(200, etablissementsLoinEtPres))
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[]", headers: ["Content-Range": "0-0/0"]))
        // Profil à Lyon, rayon_deplacement_km = 30 : Paris (~390 km) est hors rayon.
        let missions = try await gateway().listMissions(context: TestClient.context, filters: MissionFilters())
        XCTAssertEqual(missions.map(\.id), ["m-pres"])

        let large = try await gateway().listMissions(context: TestClient.context, filters: MissionFilters(rayonKm: 1000))
        XCTAssertEqual(large.map(\.id), ["m-pres", "m-loin"], "tri par distance croissante")

        let paris = try await gateway().listMissions(context: TestClient.context, filters: MissionFilters(ville: "paris", rayonKm: 1000))
        XCTAssertEqual(paris.map(\.id), ["m-loin"], "filtre ville appliqué sur le chemin réel")
    }

    func testListMissionsToleratesNullEstUrgenteAndStatut() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(missionJSON(id: "m-null", estUrgente: "null", statut: "null")),\(missionJSON(id: "m-ok"))]"))
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: .json(200, etablissementsLoinEtPres))
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[]", headers: ["Content-Range": "0-0/0"]))
        let missions = try await gateway().listMissions(context: TestClient.context, filters: MissionFilters())
        XCTAssertEqual(Set(missions.map(\.id)), ["m-null", "m-ok"], "une ligne à NULL ne fait pas échouer la page")
        XCTAssertEqual(missions.first { $0.id == "m-null" }?.record.estUrgente, false)
        XCTAssertEqual(missions.first { $0.id == "m-null" }?.record.statut, "")
    }

    func testListMissionsExplicitFiltersUseStrictProfessionAndFlags() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[]"))
        let filters = MissionFilters(tauxMin: 0, profession: "AS", urgentesOnly: true, etablissementId: "etab-9")
        let missions = try await gateway().listMissions(context: TestClient.context, filters: filters)
        XCTAssertEqual(missions, [])
        let request = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(request.query("profession_requise"), "eq.AS")
        XCTAssertNil(request.query("or"))
        XCTAssertNil(request.query("taux_horaire_base"), "tauxMin explicite 0 : pas de filtre")
        XCTAssertEqual(request.query("est_urgente"), "eq.true")
        XCTAssertEqual(request.query("etablissement_id"), "eq.etab-9")
        XCTAssertTrue(registry.requests(to: "/rest/v1/rpc/fn_etablissements_safe").isEmpty, "aucun enrichissement sur liste vide")
    }

    func testListMissionsRejectsMismatchedContextBeforeNetwork() async throws {
        let context = MissionReadContext(userId: "autre", email: nil, profile: TestClient.profile)
        do {
            _ = try await gateway().listMissions(context: context, filters: MissionFilters())
            XCTFail("attendu : refus")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
        }
        XCTAssertTrue(registry.requests.isEmpty)
    }

    func testListMissionsInconsistentSlotPaginationFails() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(TestClient.missionJSON)]"))
        // Le serveur renvoie un créneau d'une mission hors lot : le planning n'est jamais présenté.
        stubEnrichment(slots: [
            TestClient.slotJSON(id: "s-x", missionId: "m-autre", debut: "2026-12-01T19:00:00+00:00", fin: "2026-12-02T01:00:00+00:00"),
        ], count: 1)
        do {
            _ = try await gateway().listMissions(context: TestClient.context, filters: MissionFilters())
            XCTFail("attendu : planning incohérent")
        } catch let error as JoleneError {
            XCTAssertEqual(error, MissionSlotPager.planningInconsistent)
        }
    }

    func testListMissionsMissingCountFails() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(TestClient.missionJSON)]"))
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: .json(200, TestClient.etablissementJSON))
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[]")) // pas de Content-Range
        do {
            _ = try await gateway().listMissions(context: TestClient.context, filters: MissionFilters())
            XCTFail("attendu : compte non vérifiable")
        } catch let error as JoleneError {
            XCTAssertEqual(error, MissionSlotPager.countUnavailable)
        }
    }

    func testListMissionsUnauthorizedStatusIsMapped() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(401, #"{"code":"PGRST301","message":"JWT expired","details":null,"hint":null}"#))
        do {
            _ = try await gateway().listMissions(context: TestClient.context, filters: MissionFilters())
            XCTFail("attendu : non autorisé")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
        }
    }

    func testListMissionsCustomEnricherReceivesServerData() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(TestClient.missionJSON)]"))
        stubEnrichment(slots: [], count: 0)
        let gateway = SupabaseMissionsGateway(client: TestClient.make(), clock: FixedClock(now)) { context, records, etablissements, slots in
            XCTAssertEqual(context.userId, TestClient.userId)
            XCTAssertEqual(records.map(\.id), ["m-1"])
            XCTAssertEqual(etablissements.keys.sorted(), ["etab-1"])
            XCTAssertEqual(slots, [])
            return []
        }
        let missions = try await gateway.listMissions(context: TestClient.context, filters: MissionFilters())
        XCTAssertEqual(missions, [], "l'enrichisseur injecté décide du résultat")
    }

    // MARK: - Détail

    func testMissionDetailRereadsUnderCurrentJWT() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, TestClient.missionJSON))
        stubEnrichment(slots: [], count: 0)
        let mission = try await gateway().mission(id: "m-1", context: TestClient.context)
        let request = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(request.query("id"), "eq.m-1")
        XCTAssertEqual(request.header("Accept"), "application/vnd.pgrst.object+json")
        XCTAssertEqual(mission?.id, "m-1")
        XCTAssertEqual(mission?.planningExact, false, "sans créneau serveur, le planning n'est pas exact")
        XCTAssertEqual(mission?.creneauxPlanifies, [])
    }

    func testMissionDetailIdMismatchIsContractError() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, TestClient.missionJSON))
        do {
            _ = try await gateway().mission(id: "m-2", context: TestClient.context)
            XCTFail("attendu : refus")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
        }
    }

    func testMissionDetailEmptyIdIsNilWithoutNetwork() async throws {
        let mission = try await gateway().mission(id: "", context: TestClient.context)
        XCTAssertNil(mission)
        XCTAssertTrue(registry.requests.isEmpty)
    }
}
