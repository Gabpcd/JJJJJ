import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Mes missions du lot 1 (T5) : requêtes de `MissionsSoignant.tsx` l.177-233 sous le JWT du soignant
/// — `candidatures` en attente avec la mission embarquée, missions à venir et passées assignées au
/// soignant, lecture cumulative des pages de 50 comme le web (`range(0, (page + 1) * 50 - 1)`, départage
/// par `id`) — **sans** l'embed `etablissements(...)` du web : noms par
/// `fn_etablissements_safe` seulement (repli « Établissement » en échec, comme le web qui ignore
/// l'erreur ; session expirée propagée), créneaux PREVISIONNEL par le pager du lot 0 (en échec :
/// erreur de l'onglet, comme le web). Trois requêtes stubées, chaque paramètre affirmé.
final class SupabaseMesMissionsGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let now = Date(timeIntervalSince1970: 1_793_577_600) // 2026-11-02T00:00:00Z

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseMesMissionsGateway {
        SupabaseMesMissionsGateway(client: TestClient.make(), clock: FixedClock(now))
    }

    private func missionJSON(_ id: String, statut: String = "ASSIGNEE", extra: String = "") -> String {
        """
        {"id":"\(id)","intitule":"Mission \(id)","description":null,"service":null,"profession_requise":"IDE",
         "specialite_medicale_requise":null,"accepte_non_specialises":null,"debut_le":"2026-11-05T07:00:00+00:00",
         "fin_le":"2026-11-05T15:00:00+00:00","duree_heures":8,"nb_creneaux":1,"taux_horaire_base":26,
         "taux_rist_plafonne":null,"rist_plafond_applique":false,"total_brut":208,"net_a_payer":224.6,"est_urgente":false,
         "niveau_urgence":0,"statut":"\(statut)","etablissement_id":"etab-1","type_contrat_recherche":"SALARIE",
         "boostee_le":null,"mode_remuneration":null,"retrocession_pct":null\(extra)}
        """
    }

    private func stubEnrichissement(_ ids: [String], etablissements: StubResponse = .json(200, TestClient.etablissementJSON),
                                    creneaux: StubResponse? = nil) {
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: etablissements)
        if let creneaux {
            registry.add("GET", "/rest/v1/mission_creneaux", respond: creneaux)
            return
        }
        // Un stub par lot du pager (`MissionSlotPager.batches`, 50 missions) : chaque lot ne reçoit que
        // les créneaux de ses missions.
        for lot in MissionSlotPager.batches(ids) {
            let slots = lot.map {
                TestClient.slotJSON(id: "s-\($0)", missionId: $0, debut: "2026-11-05T07:00:00+00:00", fin: "2026-11-05T15:00:00+00:00")
            }
            let filtre = "in.(\(lot.joined(separator: ",")))"
            registry.add("GET", "/rest/v1/mission_creneaux", where: { $0.query("mission_id") == filtre }, respond: .json(
                200, "[\(slots.joined(separator: ","))]", headers: ["Content-Range": "0-\(max(slots.count - 1, 0))/\(slots.count)"]))
        }
    }

    private func requete(_ path: String) throws -> RecordedRequest {
        try XCTUnwrap(registry.requests(to: path).first, "aucune requête \(path)")
    }

    // MARK: - Candidatures

    func testCandidaturesRequeteDuWebSansEmbedEtablissementEtMissionEnrichie() async throws {
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, """
        [{"id":"c-1","statut":"EN_ATTENTE","message":"Super-like","type_contrat_choisi":"LIBERAL",
          "cree_le":"2026-11-01T18:00:00+00:00","mission_id":"m-1","missions":\(missionJSON("m-1", statut: "OUVERTE"))},
         {"id":"c-2","statut":"EN_ATTENTE_VALIDATION_ETAB","message":null,"type_contrat_choisi":null,
          "cree_le":"2026-11-01T09:00:00+00:00","mission_id":"m-cachee","missions":null}]
        """))
        stubEnrichissement(["m-1"])

        let candidatures = try await gateway().candidatures(context: TestClient.context)

        let lecture = try requete("/rest/v1/candidatures")
        XCTAssertEqual(lecture.method, "GET")
        XCTAssertEqual(lecture.query("select"), "id,statut,message,type_contrat_choisi,cree_le,mission_id,missions(\(MissionQuery.missionSelect))")
        XCTAssertFalse(lecture.query("select")?.contains("etablissements") ?? true, "`pol_etab_select` interdit l'embed au soignant")
        XCTAssertEqual(lecture.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(lecture.query("statut"), "in.(EN_ATTENTE,EN_ATTENTE_VALIDATION_ETAB)")
        XCTAssertEqual(lecture.query("order"), "cree_le.desc.nullsfirst", "`order('cree_le', { ascending: false })`")
        XCTAssertNil(lecture.query("limit"), "aucune pagination des candidatures, comme le web")

        XCTAssertEqual(candidatures.map(\.id), ["c-1"], "mission masquée par la RLS (embed nul) : candidature écartée")
        let candidature = try XCTUnwrap(candidatures.first)
        XCTAssertEqual(candidature.statut, "EN_ATTENTE")
        XCTAssertEqual(candidature.typeContratChoisi, "LIBERAL")
        XCTAssertEqual(candidature.mission?.etablissement?.nom, "Clinique des Tests", "nom par fn_etablissements_safe")
        XCTAssertEqual(candidature.mission?.creneauxPlanifies.map(\.id), ["s-m-1"])
        let rpc = try requete("/rest/v1/rpc/fn_etablissements_safe")
        XCTAssertEqual((rpc.bodyJSON as? [String: Any])?["p_ids"] as? [String], ["etab-1"])
        XCTAssertEqual(try requete("/rest/v1/mission_creneaux").query("mission_id"), "in.(m-1)")
        XCTAssertTrue(registry.unmatched.isEmpty, "requêtes non stubées : \(registry.unmatched.map(\.path))")
    }

    func testCandidatureDontLaMissionNeCorrespondPasRefusee() async throws {
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, """
        [{"id":"c-1","statut":"EN_ATTENTE","message":null,"type_contrat_choisi":null,"cree_le":null,
          "mission_id":"m-autre","missions":\(missionJSON("m-1"))}]
        """))
        do {
            _ = try await gateway().candidatures(context: TestClient.context)
            XCTFail("attendu : refus de contrat")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
        }
        XCTAssertTrue(registry.requests(to: "/rest/v1/rpc/fn_etablissements_safe").isEmpty, "aucune lecture complémentaire")
    }

    // MARK: - À venir

    func testAVenirPremierePageMissionsAssigneesNonTerminees() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(missionJSON("m-2"))]"))
        stubEnrichissement(["m-2"])

        let page = try await gateway().aVenir(context: TestClient.context, page: 0)

        let lecture = try requete("/rest/v1/missions")
        XCTAssertEqual(lecture.query("select"), MissionQuery.missionSelect)
        XCTAssertEqual(lecture.query("soignant_assigne_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(lecture.query("statut"), "in.(ASSIGNEE,EN_COURS)")
        XCTAssertEqual(lecture.query("fin_le"), "gte.2026-11-02T00:00:00.000Z", "missions non terminées (`gte('fin_le', maintenant)`)")
        XCTAssertEqual(lecture.query("order"), "debut_le.asc.nullslast,id.asc.nullslast",
                       "`debut_le` comme le web, puis départage par `id` (ordre stable d'une lecture à l'autre)")
        XCTAssertEqual(lecture.query("offset"), "0")
        XCTAssertEqual(lecture.query("limit"), "50")

        XCTAssertEqual(page.missions.map(\.id), ["m-2"])
        XCTAssertEqual(page.page, 0)
        XCTAssertFalse(page.aSuivre, "page incomplète : rien à charger ensuite")
        XCTAssertEqual(page.finances, [:])
        let mission = try XCTUnwrap(page.missions.first)
        XCTAssertEqual(mission.etablissement?.nom, "Clinique des Tests")
        XCTAssertEqual(mission.record.netAPayer, 224.6, "montant serveur tel quel")
        XCTAssertEqual(MesMissionsPresentation.ligneAVenir(mission, maintenant: now).horaire,
                       "Prochain créneau : 5 nov. · 08h00 → 16h00 (8h)")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    /// Lecture cumulative du web (« M1 », `range(0, (page + 1) * PAGE_SIZE - 1)`, l.244-246) : la page 1
    /// relit les lignes 0 à 99 et remplace la liste. Une page disjointe (50-99) sautait une mission quand
    /// une autre sortait de la requête entre deux lectures (`fin_le` dépassée), revue B8 de T5.
    func testAVenirPageSuivanteRelitLesPagesCumuleesCommeLeWeb() async throws {
        let ids = (0..<(2 * MissionsPage.taille)).map { "m-\($0)" }
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(ids.map { missionJSON($0) }.joined(separator: ","))]"))
        stubEnrichissement(ids)

        let page = try await gateway().aVenir(context: TestClient.context, page: 1)

        let lecture = try requete("/rest/v1/missions")
        XCTAssertEqual(lecture.query("offset"), "0", "page 1 : lignes 0 à 99, jamais 50 à 99")
        XCTAssertEqual(lecture.query("limit"), "100")
        XCTAssertEqual(lecture.query("order"), "debut_le.asc.nullslast,id.asc.nullslast")
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.missions.map(\.id), ids, "ordre serveur conservé")
        XCTAssertTrue(page.aSuivre, "lecture pleine (100 = 2 × 50) : « Charger plus de missions » proposé (web l.623)")
        XCTAssertEqual(registry.requests(to: "/rest/v1/mission_creneaux").count, 2, "créneaux des 100 missions relues, deux lots")
        XCTAssertEqual(page.missions.map { $0.creneauxPlanifies.map(\.id) }, ids.map { ["s-\($0)"] })
        XCTAssertTrue(registry.unmatched.isEmpty, "requêtes non stubées : \(registry.unmatched.map(\.path))")
    }

    func testAVenirLectureCumuleeIncompleteSansSuite() async throws {
        let ids = (0..<(MissionsPage.taille + 25)).map { "m-\($0)" }
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(ids.map { missionJSON($0) }.joined(separator: ","))]"))
        stubEnrichissement(ids)
        let page = try await gateway().aVenir(context: TestClient.context, page: 1)
        XCTAssertEqual(page.missions.count, 75)
        XCTAssertFalse(page.aSuivre, "75 < 100 : plus rien à charger")
        XCTAssertEqual(SupabaseMesMissionsGateway.bornes(page: 0).debut, 0)
        XCTAssertEqual(SupabaseMesMissionsGateway.bornes(page: 0).fin, 49)
        XCTAssertEqual(SupabaseMesMissionsGateway.bornes(page: 2).debut, 0)
        XCTAssertEqual(SupabaseMesMissionsGateway.bornes(page: 2).fin, 149)
        XCTAssertEqual(SupabaseMesMissionsGateway.bornes(page: -1).fin, 49, "page négative ramenée à la première")
    }

    // MARK: - Passées

    func testPasseesStatutsOrdreEtColonnesFinancieres() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, """
        [\(missionJSON("m-3", statut: "TERMINEE", extra: #","net_estime":162.4,"type_contrat_applique":"SALARIE""#)),
         \(missionJSON("m-4", statut: "ANNULEE_PAR_ETABLISSEMENT", extra: #","net_estime":null,"type_contrat_applique":null"#))]
        """))
        stubEnrichissement(["m-3", "m-4"])

        let page = try await gateway().passees(context: TestClient.context, page: 0)

        let lecture = try requete("/rest/v1/missions")
        XCTAssertEqual(lecture.query("select"), "\(MissionQuery.missionSelect),net_estime,type_contrat_applique")
        XCTAssertEqual(lecture.query("soignant_assigne_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(lecture.query("statut"), "in.(TERMINEE,ANNULEE_PAR_SOIGNANT,ANNULEE_PAR_ETABLISSEMENT,ABSENCE)")
        XCTAssertNil(lecture.query("fin_le"))
        XCTAssertEqual(lecture.query("order"), "debut_le.desc.nullsfirst,id.asc.nullslast",
                       "`order('debut_le', { ascending: false })`, puis départage par `id`")
        XCTAssertEqual(lecture.query("offset"), "0")
        XCTAssertEqual(lecture.query("limit"), "50")

        XCTAssertEqual(page.missions.map(\.id), ["m-3", "m-4"])
        XCTAssertEqual(page.finances["m-3"]?.netEstime, 162.4)
        XCTAssertEqual(page.finances["m-3"]?.typeContratApplique, "SALARIE")
        let mission = try XCTUnwrap(page.missions.first)
        XCTAssertEqual(MesMissionsPresentation.montantPassee(mission, finance: page.finances["m-3"]), "Net salarié estimé* : ~162,40\u{00A0}€",
                       "salarié : `net_estime`, jamais `net_a_payer`")
        XCTAssertNil(MesMissionsPresentation.montantPassee(page.missions[1], finance: page.finances["m-4"]),
                     "salarié sans net estimé : aucun montant")
    }

    // MARK: - Lectures complémentaires

    func testEtablissementsIndisponiblesRepliEtablissementMaisSessionExpireePropagee() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(missionJSON("m-2"))]"))
        stubEnrichissement(["m-2"], etablissements: .json(500, #"{"code":"XX000","message":"panne"}"#))
        let page = try await gateway().aVenir(context: TestClient.context, page: 0)
        XCTAssertEqual(page.missions.map(\.id), ["m-2"], "le web ignore l'échec de fn_etablissements_safe")
        XCTAssertNil(page.missions.first?.etablissement)
        XCTAssertEqual(page.missions.first.map { MesMissionsPresentation.lieu($0, avecVille: true) }, "Établissement")

        registry.reset()
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(missionJSON("m-2"))]"))
        stubEnrichissement(["m-2"], etablissements: .json(401, #"{"code":"PGRST301","message":"JWT expired"}"#))
        do {
            _ = try await gateway().aVenir(context: TestClient.context, page: 0)
            XCTFail("attendu : session expirée")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
        }
    }

    func testCreneauxEnEchecMettentLOngletEnErreur() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(missionJSON("m-2"))]"))
        stubEnrichissement(["m-2"], creneaux: .json(500, #"{"code":"XX000","message":"panne"}"#))
        do {
            _ = try await gateway().aVenir(context: TestClient.context, page: 0)
            XCTFail("attendu : erreur (le web : « Impossible de charger les missions et leurs horaires. »)")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unknown)
            XCTAssertFalse(error.message.contains("panne"), "aucun détail technique du serveur")
        }
    }

    // MARK: - Erreurs et garde

    func testErreursDeTransportEtDeSession() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(401, #"{"code":"PGRST301","message":"JWT expired"}"#))
        do {
            _ = try await gateway().passees(context: TestClient.context, page: 0)
            XCTFail("attendu : session expirée")
        } catch let error as JoleneError {
            XCTAssertEqual(error, JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage))
        }
        registry.reset()
        registry.add("GET", "/rest/v1/candidatures", respond: .networkFailure())
        do {
            _ = try await gateway().candidatures(context: TestClient.context)
            XCTFail("attendu : réseau")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .network)
        }
        registry.reset()
        registry.add("GET", "/rest/v1/missions", respond: .json(500, #"{"code":"XX000","message":"détail interne"}"#))
        do {
            _ = try await gateway().aVenir(context: TestClient.context, page: 0)
            XCTFail("attendu : erreur")
        } catch let error as JoleneError {
            XCTAssertEqual(error, JoleneError(.unknown, SupabaseMesMissionsGateway.fallbackMessage))
        }
    }

    func testListeVideSansLectureComplementaireEtContexteIncoherentSansRequete() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[]"))
        let vide = try await gateway().aVenir(context: TestClient.context, page: 0)
        XCTAssertEqual(vide.missions, [])
        XCTAssertFalse(vide.aSuivre)
        XCTAssertTrue(registry.requests(to: "/rest/v1/rpc/fn_etablissements_safe").isEmpty)
        XCTAssertTrue(registry.requests(to: "/rest/v1/mission_creneaux").isEmpty)

        registry.reset()
        var incoherent = TestClient.context
        incoherent.profile.id = "autre"
        do {
            _ = try await gateway().candidatures(context: incoherent)
            XCTFail("attendu : refus")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
        }
        XCTAssertTrue(registry.requests.isEmpty, "aucune requête pour un profil qui ne correspond pas à la session")
    }
}
