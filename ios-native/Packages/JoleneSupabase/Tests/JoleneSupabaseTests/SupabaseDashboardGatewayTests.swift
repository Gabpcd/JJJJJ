import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Tableau de bord du lot 1 (T3) : `fn_dashboard_soignant_complet` puis, en parallèle, fiches
/// `missions` + créneaux PREVISIONNEL (pager lot 0), `fn_etablissements_safe` et relecture des
/// missions TERMINEE du mois (décision 10), comme `DashboardSoignant.tsx` l.104-215. Une lecture
/// complémentaire en échec dégrade l'écran sans erreur ; `{error}` en HTTP 200 n'est jamais un succès.
final class SupabaseDashboardGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let rpcPath = "/rest/v1/rpc/fn_dashboard_soignant_complet"
    private let now = Date(timeIntervalSince1970: 1_795_168_800) // 2026-11-20T10:00:00Z

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseDashboardGateway {
        SupabaseDashboardGateway(client: TestClient.make(), clock: FixedClock(now))
    }

    private let corpsJSON = """
    {"profil":{"prenom":"Alex","nom":"Martin","telephone":null,"date_naissance":null,"profession":"IADE",
               "numero_rpps":null,"tous_documents_valides":true,"type_exercice":"SALARIE"},
     "missions_ouvertes":[{"id":"m-1","intitule":"Remplacement IDE nuit","service":"Urgences",
       "debut_le":"2026-12-01T19:00:00+00:00","fin_le":"2026-12-02T07:00:00+00:00","duree_heures":12,"nb_creneaux":2,
       "taux_horaire_base":28.5,"total_brut":342,"net_a_payer":300.1,"net_estime":null,"est_urgente":true,
       "etablissement_id":"etab-1","profession_requise":"IDE","type_contrat_recherche":"SALARIE",
       "accepte_non_specialises":null,"specialite_medicale_requise":null,"etab_nom":"Nom du tableau de bord"}],
     "mes_missions":[{"id":"m-2","intitule":"Mission assignée","debut_le":"2026-11-25T07:00:00+00:00",
       "fin_le":"2026-11-25T15:00:00+00:00","duree_heures":8,"statut":"ASSIGNEE","etablissement_id":"etab-2",
       "etab_nom":"Clinique hors cohorte"}],
     "documents":[],"heures_semaine":0,"gains_mois":{"net_total":999,"brut_total":999,"nb_missions":1},
     "propositions":[],"missions_oubliees_count":0,"notifs_non_lues":4}
    """

    private let missionAssigneeJSON = """
    {"id":"m-2","intitule":"Mission assignée","description":null,"service":null,"profession_requise":"IDE",
     "specialite_medicale_requise":null,"accepte_non_specialises":null,"debut_le":"2026-11-25T07:00:00+00:00",
     "fin_le":"2026-11-25T15:00:00+00:00","duree_heures":8,"nb_creneaux":1,"taux_horaire_base":25,
     "taux_rist_plafonne":null,"rist_plafond_applique":false,"total_brut":null,"net_a_payer":null,"est_urgente":false,
     "niveau_urgence":0,"statut":"ASSIGNEE","etablissement_id":"etab-2","type_contrat_recherche":"SALARIE",
     "boostee_le":null,"mode_remuneration":null,"retrocession_pct":null}
    """

    private let gainsJSON = """
    [{"id":"t-1","type_contrat_applique":"LIBERAL","type_contrat_recherche":"TOUS","total_brut":500,"net_a_payer":480,"net_estime":390},
     {"id":"t-2","type_contrat_applique":null,"type_contrat_recherche":"SALARIE","total_brut":200,"net_a_payer":230,"net_estime":160.5}]
    """

    private func estFiche(_ requete: RecordedRequest) -> Bool { requete.query("select") == MissionQuery.missionSelect }
    private func estGains(_ requete: RecordedRequest) -> Bool { requete.query("select") == SupabaseDashboardGateway.gainsSelect }

    /// Stubs du chemin nominal ; chaque lecture complémentaire peut être remplacée par un échec.
    private func stubNominal(rpc: StubResponse? = nil, fiches: StubResponse? = nil, creneaux: StubResponse? = nil,
                             etablissements: StubResponse? = nil, gains: StubResponse? = nil) {
        registry.add("POST", rpcPath, respond: rpc ?? .json(200, corpsJSON))
        registry.add("GET", "/rest/v1/missions", where: { $0.query("select") == MissionQuery.missionSelect },
                     respond: fiches ?? .json(200, "[\(TestClient.missionJSON),\(missionAssigneeJSON)]"))
        registry.add("GET", "/rest/v1/missions", where: { $0.query("select") == SupabaseDashboardGateway.gainsSelect }, respond: gains ?? .json(200, gainsJSON))
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: etablissements ?? .json(200, TestClient.etablissementJSON))
        registry.add("GET", "/rest/v1/mission_creneaux", respond: creneaux ?? .json(200, """
        [\(TestClient.slotJSON(id: "s-1", missionId: "m-1", debut: "2026-12-01T19:00:00+00:00", fin: "2026-12-02T01:00:00+00:00")),
         \(TestClient.slotJSON(id: "s-2", missionId: "m-1", debut: "2026-12-02T01:00:00+00:00", fin: "2026-12-02T07:00:00+00:00")),
         \(TestClient.slotJSON(id: "s-3", missionId: "m-2", debut: "2026-11-25T07:00:00+00:00", fin: "2026-11-25T15:00:00+00:00"))]
        """, headers: ["Content-Range": "0-2/3"]))
    }

    private func attendreErreur(_ attendue: JoleneError.Kind, message: String? = nil,
                                file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await gateway().dashboard(context: TestClient.context)
            XCTFail("attendu : erreur \(attendue)", file: file, line: line)
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, attendue, file: file, line: line)
            if let message { XCTAssertEqual(error.message, message, file: file, line: line) }
        } catch {
            XCTFail("type d'erreur inattendu : \(error)", file: file, line: line)
        }
    }

    // MARK: - Chemin nominal

    func testTableauDeBordCompletRelitFichesCreneauxEtablissementsEtGains() async throws {
        stubNominal()
        let snapshot = try await gateway().dashboard(context: TestClient.context)

        // RPC sans paramètre, JWT du soignant.
        let rpc = try XCTUnwrap(registry.requests(to: rpcPath).first)
        XCTAssertEqual(rpc.method, "POST")
        XCTAssertEqual(registry.requests(to: rpcPath).count, 1)

        // Fiches : les missions du tableau de bord, prochaines d'abord.
        let fiches = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first(where: estFiche))
        XCTAssertEqual(fiches.query("id"), "in.(m-2,m-1)")
        // Créneaux : pager du lot 0, PREVISIONNEL hors pause.
        let creneaux = try XCTUnwrap(registry.requests(to: "/rest/v1/mission_creneaux").first)
        XCTAssertEqual(creneaux.query("mission_id"), "in.(m-2,m-1)")
        XCTAssertEqual(creneaux.query("type_creneau"), "eq.PREVISIONNEL")
        XCTAssertEqual(creneaux.query("est_pause"), "eq.false")
        // Établissements : seule source du nom (jamais fn_etablissement_public).
        let etablissements = try XCTUnwrap(registry.requests(to: "/rest/v1/rpc/fn_etablissements_safe").first)
        XCTAssertEqual((etablissements.bodyJSON as? [String: Any])?["p_ids"] as? [String], ["etab-2", "etab-1"])
        // Gains : relecture du web (TERMINEE du soignant, fin depuis le début du mois de Paris).
        let gains = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first(where: estGains))
        XCTAssertEqual(gains.query("soignant_assigne_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(gains.query("statut"), "eq.TERMINEE")
        XCTAssertEqual(gains.query("fin_le"), "gte.2026-10-31T23:00:00.000Z")
        XCTAssertTrue(registry.unmatched.isEmpty, "requêtes non stubées : \(registry.unmatched.map(\.path))")

        XCTAssertEqual(snapshot.profil?.prenom, "Alex")
        XCTAssertEqual(snapshot.notifsNonLues, 4)
        XCTAssertEqual(snapshot.gainsMoisNbMissions, 1)
        XCTAssertFalse(snapshot.planningIndisponible)

        let prochaine = try XCTUnwrap(snapshot.prochaines.first)
        XCTAssertEqual(prochaine.etablissementNom, "Clinique hors cohorte", "établissement absent de la ligne safe : repli etab_nom")
        XCTAssertEqual(AccueilPresentation.planningProchaine(prochaine.planning), "mercredi 25 nov. · 08h00 → 16h00")
        XCTAssertEqual(prochaine.mission?.record.statut, "ASSIGNEE")

        let pourToi = try XCTUnwrap(snapshot.pourToi.first)
        XCTAssertEqual(pourToi.etablissementNom, "Clinique des Tests", "fn_etablissements_safe prime sur etab_nom")
        XCTAssertEqual(pourToi.etablissementVille, "Lyon")
        XCTAssertEqual(AccueilPresentation.planningPourToi(pourToi.planning), "mardi 1 déc. · 20h00 → 02h00 · 2 créneaux au total")
        XCTAssertEqual(pourToi.mission?.record.netAPayer, 300.1, "montant serveur, jamais recalculé")

        let gainsDuMois = try XCTUnwrap(snapshot.gains)
        XCTAssertEqual(gainsDuMois, GainsDuMois(honoraires: 480, netSalarie: 160.5, brutIndicatif: 0, nombreMissions: 2))
        XCTAssertEqual(AccueilPresentation.texteGains(gainsDuMois),
                       "💰 Ce mois : 480,00\u{00A0}€ d’honoraires + 160,50\u{00A0}€ net salarié estimé* sur 2 missions")
    }

    func testTableauVideNeLitNiFichesNiCreneauxNiEtablissements() async throws {
        registry.add("POST", rpcPath, respond: .json(200, #"{"profil":null,"mes_missions":[],"missions_ouvertes":[],"propositions":[]}"#))
        registry.add("GET", "/rest/v1/missions", where: { $0.query("select") == SupabaseDashboardGateway.gainsSelect }, respond: .json(200, "[]"))
        let snapshot = try await gateway().dashboard(context: TestClient.context)
        XCTAssertEqual(snapshot.prochaines, [])
        XCTAssertEqual(snapshot.pourToi, [])
        XCTAssertEqual(snapshot.gains, GainsDuMois(honoraires: 0, netSalarie: 0, brutIndicatif: 0, nombreMissions: 0))
        XCTAssertEqual(registry.requests.map(\.path).sorted(), ["/rest/v1/missions", rpcPath])
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    // MARK: - Rendu partiel (jamais une erreur d'écran)

    func testCreneauxEnEchecRendentLePlanningIndisponible() async throws {
        stubNominal(creneaux: .json(500, #"{"code":"XX000","message":"erreur","details":null,"hint":null}"#))
        let snapshot = try await gateway().dashboard(context: TestClient.context)
        XCTAssertTrue(snapshot.planningIndisponible)
        XCTAssertEqual((snapshot.prochaines + snapshot.pourToi).map(\.planning), [.indisponible, .indisponible])
        XCTAssertEqual(snapshot.prochaines.map(\.id), ["m-2"], "les lignes restent affichées")
        XCTAssertNotNil(snapshot.gains, "les gains ne dépendent pas du planning")
    }

    func testCompteDeCreneauxIncoherentRendLePlanningIndisponible() async throws {
        // Compte annoncé (5) > créneaux reçus (3) : le pager refuse, le planning n'est jamais présenté comme exact.
        stubNominal(creneaux: .json(200, """
        [\(TestClient.slotJSON(id: "s-1", missionId: "m-1", debut: "2026-12-01T19:00:00+00:00", fin: "2026-12-02T01:00:00+00:00"))]
        """, headers: ["Content-Range": "0-0/5"]))
        let snapshot = try await gateway().dashboard(context: TestClient.context)
        XCTAssertTrue(snapshot.planningIndisponible)
        XCTAssertEqual(snapshot.pourToi.first?.planning, .indisponible)
    }

    func testFichesEnEchecRendentLePlanningIndisponible() async throws {
        // 500 plutôt qu'une coupure réseau ou un 503 : le SDK rejoue ces GET idempotents (≈ 7 s).
        stubNominal(fiches: .json(500, #"{"code":"XX000","message":"erreur","details":null,"hint":null}"#))
        let snapshot = try await gateway().dashboard(context: TestClient.context)
        XCTAssertTrue(snapshot.planningIndisponible)
        XCTAssertNil(snapshot.prochaines.first?.mission)
    }

    func testGainsEnEchecMasquentLaCarteSansErreur() async throws {
        stubNominal(gains: .json(500, #"{"code":"XX000","message":"erreur","details":null,"hint":null}"#))
        let snapshot = try await gateway().dashboard(context: TestClient.context)
        XCTAssertNil(snapshot.gains)
        XCTAssertFalse(snapshot.planningIndisponible)
    }

    func testEtablissementsEnEchecRepliSurLeNomDuTableauDeBord() async throws {
        stubNominal(etablissements: .networkFailure())
        let snapshot = try await gateway().dashboard(context: TestClient.context)
        XCTAssertEqual(snapshot.pourToi.first?.etablissementNom, "Nom du tableau de bord")
        XCTAssertEqual(snapshot.prochaines.first?.etablissementNom, "Clinique hors cohorte")
        XCTAssertFalse(snapshot.planningIndisponible)
    }

    // MARK: - Refus

    func testNonAuthentifieEnHTTP200EstUneSessionExpireeSansAutreRequete() async {
        registry.add("POST", rpcPath, respond: .json(200, #"{"error":"Non authentifié"}"#))
        await attendreErreur(.unauthorized, message: SupabaseErrorMapping.unauthorizedMessage)
        XCTAssertEqual(registry.requests.count, 1, "aucune lecture complémentaire après un refus")
    }

    func testAutreErreurServeurAfficheeVerbatim() async {
        registry.add("POST", rpcPath, respond: .json(200, #"{"error":"Profil soignant introuvable"}"#))
        await attendreErreur(.unknown, message: "Profil soignant introuvable")
    }

    func testCorpsQuiNestPasUnObjetEstUnRefusDeContrat() async {
        for corps in ["null", "[]", "42"] {
            registry.reset()
            registry.add("POST", rpcPath, respond: .json(200, corps))
            await attendreErreur(.contract, message: SupabaseErrorMapping.contractMessage)
            XCTAssertEqual(registry.requests.count, 1, corps)
        }
    }

    func testFonctionIntrouvablePGRST202EstUnRefusDefinitif() async {
        registry.add("POST", rpcPath, respond: .json(404, """
        {"code":"PGRST202","details":null,"hint":null,
         "message":"Could not find the function public.fn_dashboard_soignant_complet without parameters in the schema cache"}
        """))
        await attendreErreur(.contract, message: SupabaseErrorMapping.contractMessage)
        XCTAssertEqual(registry.requests(to: rpcPath).count, 1, "aucun renvoi automatique")
    }

    func testReseauIndisponible() async {
        registry.add("POST", rpcPath, respond: .networkFailure())
        await attendreErreur(.network, message: SupabaseErrorMapping.networkMessage)
    }

    func testContexteIncoherentRefuseAvantToutAppel() async {
        var contexte = TestClient.context
        contexte.profile.id = "autre-id"
        do {
            _ = try await gateway().dashboard(context: contexte)
            XCTFail("profil désynchronisé")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
        }
        XCTAssertTrue(registry.requests.isEmpty)
    }
}
