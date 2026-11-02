import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Favoris du lot 1 (T4b) : missions sauvegardées par PostgREST direct sur `missions_sauvegardees`
/// (RLS `soignant_id = auth.uid()`, l.78141-78149 du dump), établissements par
/// `fn_mes_favoris_etablissements` (tableau, ou `{error}` en HTTP 200) et retrait par
/// `fn_toggle_favori_etablissement(p_actif := false)` — jamais l'ajout (décision 8). Chaque mutation
/// rend la liste relue ; le conflit UNIQUE est un état à relire, pas une erreur ; `{error}` n'est
/// jamais un succès.
final class SupabaseFavorisGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let tablePath = "/rest/v1/missions_sauvegardees"
    private let listePath = "/rest/v1/rpc/fn_mes_favoris_etablissements"
    private let basculePath = "/rest/v1/rpc/fn_toggle_favori_etablissement"
    private let surPath = "/rest/v1/rpc/fn_etablissements_safe"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseFavorisGateway { SupabaseFavorisGateway(client: TestClient.make()) }

    private static func ligneJSON(_ id: String, mission: String, cree: String = "2026-11-01T10:00:00+00:00", jointure: String? = nil) -> String {
        let embed = jointure ?? """
        {"id":"\(mission)","intitule":"Mission \(mission)","debut_le":"2026-12-01T07:00:00+00:00","fin_le":"2026-12-01T15:00:00+00:00","duree_heures":8,"nb_creneaux":1,"statut":"OUVERTE"}
        """
        return #"{"id":"\#(id)","mission_id":"\#(mission)","cree_le":"\#(cree)","missions":\#(embed)}"#
    }

    private let favorisJSON = """
    [{"etablissement_id":"etab-1","nom":"Nom interne","ville":"Lyon","logo_url":null,"type_etablissement":"CLINIQUE",
      "nb_missions_ouvertes":3,"cree_le":"2026-10-15T09:00:00+00:00"},
     {"etablissement_id":"etab-2","nom":"Clinique sans mission","ville":null,"logo_url":null,"type_etablissement":null,
      "nb_missions_ouvertes":0,"cree_le":"2026-10-01T09:00:00+00:00"}]
    """

    private func attendreErreur(_ attendue: JoleneError.Kind, message: String? = nil, file: StaticString = #filePath, line: UInt = #line,
                                _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("attendu : erreur \(attendue)", file: file, line: line)
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, attendue, error.message, file: file, line: line)
            if let message { XCTAssertEqual(error.message, message, file: file, line: line) }
        } catch {
            XCTFail("type d'erreur inattendu : \(error)", file: file, line: line)
        }
    }

    // MARK: - Missions sauvegardées

    func testLectureDesMissionsSauvegardeesAvecJointureEtOrdreDuWeb() async throws {
        registry.add("GET", tablePath, respond: .json(200, """
        [\(Self.ligneJSON("s-1", mission: "m-1")), \(Self.ligneJSON("s-2", mission: "m-2", jointure: "null"))]
        """))
        let lignes = try await gateway().missionsSauvegardees(context: TestClient.context)

        let requete = try XCTUnwrap(registry.requests(to: tablePath).first)
        XCTAssertEqual(requete.method, "GET")
        XCTAssertEqual(requete.query("select"), SupabaseFavorisGateway.selectSauvegardees)
        XCTAssertEqual(SupabaseFavorisGateway.selectSauvegardees,
                       "id,mission_id,cree_le,missions(id,intitule,debut_le,fin_le,duree_heures,nb_creneaux,statut)")
        XCTAssertEqual(requete.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(requete.query("order"), "cree_le.desc.nullslast", "web : .order('cree_le', { ascending: false })")
        XCTAssertTrue(registry.unmatched.isEmpty)

        XCTAssertEqual(lignes.map(\.missionId), ["m-1", "m-2"])
        XCTAssertEqual(lignes.first?.mission?.intitule, "Mission m-1")
        XCTAssertNil(lignes.last?.mission, "jointure masquée par la RLS des missions : ligne conservée, mission non affichée")
    }

    func testLectureEnEchecTraduite() async {
        registry.add("GET", tablePath, respond: .json(401, #"{"code":"PGRST301","message":"JWT expired","details":null,"hint":null}"#))
        await attendreErreur(.unauthorized) { _ = try await self.gateway().missionsSauvegardees(context: TestClient.context) }
        registry.reset()
        registry.add("GET", tablePath, respond: .json(400, #"{"code":"PGRST200","message":"Could not find a relationship","details":null,"hint":null}"#))
        await attendreErreur(.contract, message: SupabaseErrorMapping.contractMessage) {
            _ = try await self.gateway().missionsSauvegardees(context: TestClient.context)
        }
        // (Coupure réseau sur un GET : rejouée par le SDK, 1 + 2 + 4 s ; couverte sur l'insertion, sans rejeu.)
    }

    func testSauvegarderInsereSansRetourPuisRelit() async throws {
        registry.add("POST", tablePath, respond: .json(201, ""))
        registry.add("GET", tablePath, respond: .json(200, "[\(Self.ligneJSON("s-1", mission: "m-1"))]"))

        let lignes = try await gateway().sauvegarder(missionId: "m-1", context: TestClient.context)

        let insertion = try XCTUnwrap(registry.requests(to: tablePath).first { $0.method == "POST" })
        let corps = try XCTUnwrap(insertion.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["mission_id"] as? String, "m-1")
        XCTAssertEqual(corps["soignant_id"] as? String, TestClient.userId, "RLS : soignant_id = auth.uid()")
        XCTAssertEqual(corps.count, 2)
        XCTAssertTrue(insertion.header("Prefer")?.contains("return=minimal") == true)
        XCTAssertEqual(registry.requests(to: tablePath).map(\.method), ["POST", "GET"], "relecture après l'insertion")
        XCTAssertEqual(lignes.map(\.missionId), ["m-1"])
    }

    func testConflitUniqueRelitLEtatSansErreur() async throws {
        registry.add("POST", tablePath, respond: .json(409, """
        {"code":"23505","details":"Key (soignant_id, mission_id) already exists.","hint":null,
         "message":"duplicate key value violates unique constraint \\"missions_sauvegardees_soignant_id_mission_id_key\\""}
        """))
        registry.add("GET", tablePath, respond: .json(200, "[\(Self.ligneJSON("s-1", mission: "m-1"))]"))

        let lignes = try await gateway().sauvegarder(missionId: "m-1", context: TestClient.context)

        XCTAssertEqual(registry.requests(to: tablePath).filter { $0.method == "POST" }.count, 1, "jamais de renvoi")
        XCTAssertEqual(lignes.map(\.missionId), ["m-1"], "déjà sauvegardée : la relecture fait foi")
    }

    func testInsertionRefuseeSansRelecture() async {
        // Compte non actif (politique restrictive l.78751) ou session d'un autre : 42501 → session à vérifier.
        registry.add("POST", tablePath, respond: .json(403, #"{"code":"42501","message":"new row violates row-level security policy","details":null,"hint":null}"#))
        await attendreErreur(.unauthorized) { _ = try await self.gateway().sauvegarder(missionId: "m-1", context: TestClient.context) }
        XCTAssertTrue(registry.requests(to: tablePath).allSatisfy { $0.method == "POST" }, "aucune relecture après un refus")

        // Mission supprimée entre l'affichage et l'appui (clé étrangère) : message générique, aucun détail technique.
        registry.reset()
        registry.add("POST", tablePath, respond: .json(409, #"{"code":"23503","message":"insert or update violates foreign key constraint","details":"Key (mission_id)=(m-1) is not present","hint":null}"#))
        await attendreErreur(.unknown, message: SupabaseFavorisGateway.sauvegardeFallback) {
            _ = try await self.gateway().sauvegarder(missionId: "m-1", context: TestClient.context)
        }

        registry.reset()
        registry.add("POST", tablePath, respond: .networkFailure())
        await attendreErreur(.network) { _ = try await self.gateway().sauvegarder(missionId: "m-1", context: TestClient.context) }
        XCTAssertEqual(registry.requests.count, 1, "réseau coupé : le modèle relira, la gateway ne renvoie rien")
    }

    func testRetirerSupprimeLaLigneDuSoignantPuisRelit() async throws {
        registry.add("DELETE", tablePath, respond: .json(204, ""))
        registry.add("GET", tablePath, respond: .json(200, "[]"))

        let lignes = try await gateway().retirer(missionId: "m-1", context: TestClient.context)

        let suppression = try XCTUnwrap(registry.requests(to: tablePath).first { $0.method == "DELETE" })
        XCTAssertEqual(suppression.query("mission_id"), "eq.m-1")
        XCTAssertEqual(suppression.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertTrue(suppression.header("Prefer")?.contains("return=minimal") == true)
        XCTAssertEqual(registry.requests(to: tablePath).map(\.method), ["DELETE", "GET"])
        XCTAssertEqual(lignes, [])
    }

    func testIdentifiantVideEtContexteIncoherentRefusesAvantToutAppel() async {
        await attendreErreur(.contract) { _ = try await self.gateway().sauvegarder(missionId: " ", context: TestClient.context) }
        await attendreErreur(.contract) { _ = try await self.gateway().retirer(missionId: "", context: TestClient.context) }
        var incoherent = TestClient.context
        incoherent.profile.id = "autre"
        await attendreErreur(.unauthorized) { _ = try await self.gateway().missionsSauvegardees(context: incoherent) }
        await attendreErreur(.unauthorized) { _ = try await self.gateway().etablissementsFavoris(context: incoherent) }
        XCTAssertTrue(registry.requests.isEmpty, "aucune requête : \(registry.requests.map(\.path))")
    }

    // MARK: - Établissements favoris

    func testEtablissementsFavorisTableauEtNomsDeFnEtablissementsSafe() async throws {
        registry.add("POST", listePath, respond: .json(200, favorisJSON))
        registry.add("POST", surPath, respond: .json(200, TestClient.etablissementJSON))

        let favoris = try await gateway().etablissementsFavoris(context: TestClient.context)

        XCTAssertEqual(registry.requests(to: listePath).count, 1)
        let sur = try XCTUnwrap(registry.requests(to: surPath).first)
        XCTAssertEqual((sur.bodyJSON as? [String: Any])?["p_ids"] as? [String], ["etab-1", "etab-2"])
        XCTAssertEqual(favoris.map(\.id), ["etab-1", "etab-2"], "ordre serveur (cree_le DESC)")
        XCTAssertEqual(favoris.first?.nom, "Clinique des Tests", "nom de fn_etablissements_safe quand la ligne existe")
        XCTAssertEqual(favoris.last?.nom, "Clinique sans mission", "sinon le nom de la RPC")
        XCTAssertEqual(favoris.first?.nbMissionsOuvertes, 3, "valeur serveur affichée telle quelle")
        XCTAssertEqual(favoris.first?.creeLe, "2026-10-15T09:00:00+00:00")
    }

    func testListeVideSansLectureDesNoms() async throws {
        registry.add("POST", listePath, respond: .json(200, "[]"))
        let favoris = try await gateway().etablissementsFavoris(context: TestClient.context)
        XCTAssertEqual(favoris, [])
        XCTAssertTrue(registry.requests(to: surPath).isEmpty)
    }

    func testElementIllisibleEcarteSeul() async throws {
        registry.add("POST", listePath, respond: .json(200, #"[{"nom":"sans identifiant"},{"etablissement_id":"etab-9","nom":"Gardé"}]"#))
        registry.add("POST", surPath, respond: .json(200, "[]"))
        let favoris = try await gateway().etablissementsFavoris(context: TestClient.context)
        XCTAssertEqual(favoris.map(\.id), ["etab-9"])
        XCTAssertEqual(favoris.first?.nom, "Gardé")
    }

    func testNomsSursIndisponiblesGardentLeNomDeLaRPC() async throws {
        registry.add("POST", listePath, respond: .json(200, favorisJSON))
        registry.add("POST", surPath, respond: .json(500, #"{"code":"57014","message":"canceling statement due to statement timeout","details":null,"hint":null}"#))
        let favoris = try await gateway().etablissementsFavoris(context: TestClient.context)
        XCTAssertEqual(favoris.map(\.nom), ["Nom interne", "Clinique sans mission"], "lecture complémentaire : jamais une erreur d'écran")
    }

    func testNomsSursSessionExpireePropagee() async {
        registry.add("POST", listePath, respond: .json(200, favorisJSON))
        registry.add("POST", surPath, respond: .json(401, #"{"code":"PGRST301","message":"JWT expired","details":null,"hint":null}"#))
        await attendreErreur(.unauthorized) { _ = try await self.gateway().etablissementsFavoris(context: TestClient.context) }
    }

    func testFormesDErreurDeFnMesFavorisEtablissements() async {
        // `{error}` en HTTP 200 (l.41843) : jamais un succès vide.
        registry.add("POST", listePath, respond: .json(200, #"{"error":"Non authentifié"}"#))
        await attendreErreur(.unauthorized, message: SupabaseErrorMapping.unauthorizedMessage) {
            _ = try await self.gateway().etablissementsFavoris(context: TestClient.context)
        }
        registry.reset()
        registry.add("POST", listePath, respond: .json(200, #"{"error":"Service indisponible"}"#))
        await attendreErreur(.unknown, message: "Service indisponible") {
            _ = try await self.gateway().etablissementsFavoris(context: TestClient.context)
        }
        registry.reset()
        registry.add("POST", listePath, respond: .json(200, "{}"))
        await attendreErreur(.contract, message: SupabaseErrorMapping.contractMessage) {
            _ = try await self.gateway().etablissementsFavoris(context: TestClient.context)
        }
        registry.reset()
        registry.add("POST", listePath, respond: .json(404, #"{"code":"PGRST202","message":"Could not find the function","details":null,"hint":null}"#))
        await attendreErreur(.contract) { _ = try await self.gateway().etablissementsFavoris(context: TestClient.context) }
        XCTAssertEqual(registry.requests(to: listePath).count, 1, "PGRST202 : refus définitif, aucun renvoi")
        XCTAssertTrue(registry.requests(to: surPath).isEmpty)
    }

    // MARK: - Retrait d'un établissement (décision 8 : jamais d'ajout)

    func testRetraitAppelleLaRPCAvecPActifFalsePuisRelit() async throws {
        registry.add("POST", basculePath, respond: .json(200, #"{"success":true,"actif":false}"#))
        registry.add("POST", listePath, respond: .json(200, """
        [{"etablissement_id":"etab-2","nom":"Clinique sans mission","ville":null,"logo_url":null,"type_etablissement":null,
          "nb_missions_ouvertes":0,"cree_le":"2026-10-01T09:00:00+00:00"}]
        """))
        registry.add("POST", surPath, respond: .json(200, "[]"))

        let favoris = try await gateway().basculerEtablissement(id: "etab-1", actif: false, context: TestClient.context)

        let appel = try XCTUnwrap(registry.requests(to: basculePath).first)
        let corps = try XCTUnwrap(appel.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["p_etablissement_id"] as? String, "etab-1")
        XCTAssertEqual(corps["p_actif"] as? Bool, false)
        XCTAssertEqual(corps.count, 2)
        XCTAssertEqual(registry.requests.map(\.path), [basculePath, listePath, surPath], "relecture après le retrait")
        XCTAssertEqual(favoris.map(\.id), ["etab-2"])
    }

    func testAjoutRefuseAvantToutAppel() async {
        await attendreErreur(.contract, message: FavorisRegles.ajoutEtablissementNonPropose) {
            _ = try await self.gateway().basculerEtablissement(id: "etab-1", actif: true, context: TestClient.context)
        }
        await attendreErreur(.contract) { _ = try await self.gateway().basculerEtablissement(id: "", actif: false, context: TestClient.context) }
        XCTAssertTrue(registry.requests.isEmpty, "décision 8 : p_actif = true n'est jamais envoyé")
    }

    func testFormesDeReponseDuRetrait() async {
        registry.add("POST", basculePath, respond: .json(200, #"{"success":false,"error":"Établissement introuvable"}"#))
        await attendreErreur(.unknown, message: "Établissement introuvable") {
            _ = try await self.gateway().basculerEtablissement(id: "etab-1", actif: false, context: TestClient.context)
        }
        XCTAssertTrue(registry.requests(to: listePath).isEmpty, "un refus n'est pas relu par la gateway (le modèle relit)")

        registry.reset()
        registry.add("POST", basculePath, respond: .json(200, #"{"success":false,"error":"Non authentifié"}"#))
        await attendreErreur(.unauthorized, message: SupabaseErrorMapping.unauthorizedMessage) {
            _ = try await self.gateway().basculerEtablissement(id: "etab-1", actif: false, context: TestClient.context)
        }

        registry.reset()
        registry.add("POST", basculePath, respond: .json(200, #"{"actif":false}"#))
        await attendreErreur(.contract, message: SupabaseErrorMapping.contractMessage) {
            _ = try await self.gateway().basculerEtablissement(id: "etab-1", actif: false, context: TestClient.context)
        }

        registry.reset()
        registry.add("POST", basculePath, respond: .json(400, #"{"code":"22P02","message":"invalid input syntax for type uuid","details":null,"hint":null}"#))
        await attendreErreur(.unknown, message: SupabaseFavorisGateway.retraitEtablissementFallback) {
            _ = try await self.gateway().basculerEtablissement(id: "pas-un-uuid", actif: false, context: TestClient.context)
        }
    }
}
