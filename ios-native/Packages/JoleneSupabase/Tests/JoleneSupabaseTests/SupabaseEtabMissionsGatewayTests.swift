import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Missions de l'établissement sur Supabase (lot 5, T5) : requêtes exactes (aucune colonne monétaire, filtre
/// `etablissement_id` = établissement **confirmé** du contexte, pages cumulatives), lignes relues contrôlées,
/// compteurs et candidatures en lecture secondaire (fail-closed sans la permission `candidatures`), planning porté
/// par le détail, `fn_soignant_pour_etablissement` (`null` → indisponible, `{error}` verbatim, uuid exigé).
final class SupabaseEtabMissionsGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let etab = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let soignantId = "0b4d2b8e-4a9f-4b1c-9e0a-7f3c1d2e5a66"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseEtabMissionsGateway { SupabaseEtabMissionsGateway(client: TestClient.make()) }

    private func contexte(_ permissions: Set<PermissionEtab> = [.lecture, .candidatures]) -> EtablissementReadContext {
        EtablissementReadContext(userId: TestClient.userId, etablissementId: etab, roleEtab: .rh,
                                 permissions: PermissionsEtab(accordees: permissions), epoch: 1)
    }

    private func missionJSON(_ id: String, statut: String = "OUVERTE", etablissement: String? = nil) -> String {
        #"{"id":"\#(id)","etablissement_id":"\#(etablissement ?? etab)","intitule":"Mission \#(id)","description":null,"service":"Soins","profession_requise":"IDE","debut_le":"2026-11-05T06:00:00+00:00","fin_le":"2026-11-05T14:00:00+00:00","nb_creneaux":1,"statut":"\#(statut)","est_urgente":false,"niveau_urgence":0,"soignant_assigne_id":null,"mode_attribution":"CANDIDATURE","type_contrat_recherche":"SALARIE","cree_le":"2026-11-01T08:00:00+00:00"}"#
    }

    private func estListe(_ requete: RecordedRequest) -> Bool { requete.query("select") == SupabaseEtabMissionsGateway.missionSelect }

    private func stubListe(_ lignes: [String], statuts: String = #"[{"statut":"OUVERTE"},{"statut":"TERMINEE"}]"#, compte: Int = 2) {
        registry.add("GET", "/rest/v1/missions", where: { $0.query("select") == SupabaseEtabMissionsGateway.missionSelect },
                     respond: .json(200, "[\(lignes.joined(separator: ","))]"))
        registry.add("GET", "/rest/v1/missions", where: { $0.query("select") == "statut" },
                     respond: .json(200, statuts, headers: ["Content-Range": "0-\(max(compte - 1, 0))/\(compte)"]))
        let creneaux = lignes.isEmpty ? [] : [TestClient.slotJSON(id: "c-1", missionId: "m-1", debut: "2026-11-05T06:00:00+00:00",
                                                                   fin: "2026-11-05T14:00:00+00:00")]
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(
            200, "[\(creneaux.joined(separator: ","))]", headers: ["Content-Range": "0-\(max(creneaux.count - 1, 0))/\(creneaux.count)"]))
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, #"[{"mission_id":"m-1"},{"mission_id":"m-1"},{"mission_id":"autre"}]"#))
    }

    private func echec(_ appel: () async throws -> Void) async -> JoleneError? {
        do {
            try await appel()
            XCTFail("attendu : erreur levée")
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
            return nil
        }
    }

    // MARK: - Liste

    func testRequeteExacteSansMontantEtablissementConfirmeEtPageCumulative() async throws {
        stubListe([missionJSON("m-1"), missionJSON("m-2", statut: "TERMINEE")])
        let page = try await gateway().missions(context: contexte(), statut: nil, page: 1)
        XCTAssertEqual(page.missions.map(\.id), ["m-1", "m-2"])
        XCTAssertFalse(page.aSuivre, "2 lignes sur 100 demandées")
        XCTAssertEqual(page.compteurs?.nombre(.toutes), 2)
        XCTAssertEqual(page.compteurs?.nombre(.terminees), 1)
        XCTAssertEqual(page.creneaux["m-1"]?.count, 1)
        XCTAssertEqual(page.candidaturesEnAttente, ["m-1": 2], "candidature d'une mission non demandée ignorée")

        let liste = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first(where: estListe))
        let select = try XCTUnwrap(liste.query("select"))
        for montant in ["taux_horaire_base", "total_brut", "net_a_payer", "taux_rist_plafonne", "rist_plafond_applique", "net_estime"] {
            XCTAssertFalse(select.contains(montant), "\(montant) jamais lu (D15)")
        }
        XCTAssertEqual(liste.query("etablissement_id"), "eq.\(etab)", "établissement confirmé, jamais user.id")
        XCTAssertNil(liste.query("statut"), "« Toutes » : aucun filtre de statut")
        XCTAssertEqual(liste.query("order"), "debut_le.desc.nullslast,id.asc.nullslast")
        XCTAssertEqual(liste.query("offset"), "0", "page 1 : lignes 0 à 99, jamais 50 à 99")
        XCTAssertEqual(liste.query("limit"), "100")
        let statuts = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first { $0.query("select") == "statut" })
        XCTAssertEqual(statuts.query("etablissement_id"), "eq.\(etab)")
        let candidatures = try XCTUnwrap(registry.requests(to: "/rest/v1/candidatures").first)
        XCTAssertEqual(candidatures.query("mission_id"), "in.(m-1)", "missions OUVERTE de la page seulement")
        XCTAssertEqual(candidatures.query("statut"), "eq.EN_ATTENTE")
        XCTAssertEqual(try XCTUnwrap(registry.requests(to: "/rest/v1/mission_creneaux").first).query("type_creneau"), "eq.PREVISIONNEL")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testFiltreStatutEtCandidaturesJamaisLuesSansPermission() async throws {
        stubListe([missionJSON("m-1")])
        let page = try await gateway().missions(context: contexte([.lecture]), statut: "OUVERTE", page: 0)
        XCTAssertEqual(page.candidaturesEnAttente, [:])
        XCTAssertTrue(registry.requests(to: "/rest/v1/candidatures").isEmpty, "fail-closed : aucune lecture sans la permission")
        let liste = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first(where: estListe))
        XCTAssertEqual(liste.query("statut"), "eq.OUVERTE")
        XCTAssertEqual(liste.query("limit"), "50")
    }

    func testLigneDUnAutreEtablissementEstUnRefusDeContrat() async throws {
        stubListe([missionJSON("m-1", etablissement: "11111111-2222-4333-8444-555555555555")])
        let erreur = await echec { _ = try await self.gateway().missions(context: self.contexte(), statut: nil, page: 0) }
        XCTAssertEqual(erreur?.kind, .contract)
    }

    func testCompteursEnEchecRestentInconnusEtContexteInvalideRefuseAvantReseau() async throws {
        registry.add("GET", "/rest/v1/missions", where: { $0.query("select") == SupabaseEtabMissionsGateway.missionSelect },
                     respond: .json(200, "[]"))
        registry.add("GET", "/rest/v1/missions", where: { $0.query("select") == "statut" }, respond: .json(500, #"{"message":"boom"}"#))
        let page = try await gateway().missions(context: contexte(), statut: nil, page: 0)
        XCTAssertNil(page.compteurs, "jamais un « 0 » supposé")
        registry.reset()
        var invalide = contexte()
        invalide.etablissementId = " "
        let erreur = await echec { _ = try await self.gateway().missions(context: invalide, statut: nil, page: 0) }
        XCTAssertEqual(erreur?.kind, .unauthorized)
        XCTAssertTrue(registry.requests.isEmpty)
    }

    // MARK: - Détail

    func testDetailRelitLaMissionDeLEtablissementEtPortePlanningIndisponible() async throws {
        let missionId = "3c9e1d2a-5b6f-4a70-8b81-92a3b4c5d6e7"
        registry.add("GET", "/rest/v1/missions", respond: .json(200, missionJSON(missionId)))
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[]"))   // sans Content-Range : compte invérifiable
        registry.add("HEAD", "/rest/v1/candidatures", respond: .json(200, "", headers: ["Content-Range": "*/3"]))
        let detailLu = try await gateway().mission(id: missionId.uppercased(), context: contexte())
        let detail = try XCTUnwrap(detailLu)
        XCTAssertEqual(detail.mission.id, missionId)
        XCTAssertEqual(detail.erreurPlanning, MissionSlotPager.countUnavailable.message, "lecture secondaire : mission conservée")
        XCTAssertEqual(detail.candidaturesEnAttente, 3)
        let lecture = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(lecture.query("id"), "eq.\(missionId)", "uuid canonique")
        XCTAssertEqual(lecture.query("etablissement_id"), "eq.\(etab)")
        XCTAssertEqual(lecture.header("Accept"), "application/vnd.pgrst.object+json")
    }

    /// Intégration de la vague C (revue B8 de #1162, m4) : un identifiant qui n'est pas un uuid (ou l'uuid nul) rend
    /// « Mission introuvable » sans aucun appel, jamais une erreur réseau relancée en boucle.
    func testDetailIdentifiantNonUuidIntrouvableAvantReseau() async throws {
        for id in ["abc", "demo-etab-m01", "00000000-0000-0000-0000-000000000000", " "] {
            let lu = try await gateway().mission(id: id, context: contexte())
            XCTAssertNil(lu, "« \(id) » : introuvable")
        }
        XCTAssertTrue(registry.requests(to: "/rest/v1/missions").isEmpty, "aucune lecture PostgREST")
        XCTAssertTrue(registry.requests(to: "/rest/v1/mission_creneaux").isEmpty)
    }

    // MARK: - Soignant

    func testSoignantServiNullEtErreurVerbatim() async throws {
        registry.add("POST", "/rest/v1/rpc/fn_soignant_pour_etablissement", respond: .json(200, """
        {"id":"\(soignantId)","prenom":"Camille","nom":"D.","nom_anonymise":true,"profession":"IDE","telephone":null,
         "score_fiabilite":82,"total_missions_terminees":3,"note_moyenne":4.8,"type_exercice":"SALARIE"}
        """))
        let soignantLu = try await gateway().soignant(id: soignantId.uppercased(), context: contexte())
        let lu = try XCTUnwrap(soignantLu)
        XCTAssertEqual(lu.nom, "D.")
        XCTAssertEqual(lu.scoreFiabilite, 82)
        let corps = try XCTUnwrap(registry.requests(to: "/rest/v1/rpc/fn_soignant_pour_etablissement").first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps as? [String: String], ["p_soignant_id": soignantId], "uuid canonique, seul paramètre")

        registry.reset()
        registry.add("POST", "/rest/v1/rpc/fn_soignant_pour_etablissement", respond: .json(200, "null"))
        let supprime = try await gateway().soignant(id: soignantId, context: contexte())
        XCTAssertNil(supprime, "null SQL : soignant indisponible, jamais un profil vide")

        registry.reset()
        registry.add("POST", "/rest/v1/rpc/fn_soignant_pour_etablissement", respond: .json(200, #"{"error":"Accès refusé"}"#))
        let refus = await echec { _ = try await self.gateway().soignant(id: self.soignantId, context: self.contexte()) }
        XCTAssertEqual(refus, JoleneError(.unknown, "Accès refusé"))

        registry.reset()
        let invalide = await echec { _ = try await self.gateway().soignant(id: "demo-soignant", context: self.contexte()) }
        XCTAssertEqual(invalide?.kind, .contract)
        XCTAssertTrue(registry.requests.isEmpty, "identifiant invalide refusé avant réseau")
    }
}
