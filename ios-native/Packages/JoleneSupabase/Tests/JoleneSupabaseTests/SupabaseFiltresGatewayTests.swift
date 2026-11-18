import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Recherches sauvegardées sur Supabase (L4-T4) — fiches `fn_lister_mes_filtres_sauvegardes`, `fn_creer_filtre_sauvegarde`,
/// `fn_modifier_filtre_sauvegarde`, `fn_supprimer_filtre_sauvegarde` de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` :
/// - audience toujours `SOIGNANT_RECHERCHE_MISSIONS` ; `p_filtres` à sept clés camelCase, entiers sans décimale ;
/// - critères hors validateur jamais envoyés ; refus `{error}` verbatim (limite 20, nom en double, critères, filtre
///   introuvable), « Non authentifié » → session expirée ; toute autre réponse → contrat ;
/// - chaque mutation acceptée est suivie de la relecture de la liste (rendue au modèle, qui confirme) ;
/// - une seule requête par appel, aucun renvoi.
final class SupabaseFiltresGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let lister = "/rest/v1/rpc/fn_lister_mes_filtres_sauvegardes"
    private let creer = "/rest/v1/rpc/fn_creer_filtre_sauvegarde"
    private let modifier = "/rest/v1/rpc/fn_modifier_filtre_sauvegarde"
    private let supprimer = "/rest/v1/rpc/fn_supprimer_filtre_sauvegarde"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseFiltresGateway { SupabaseFiltresGateway(client: TestClient.make()) }

    private static let listeJSON = """
    [{"id":"7f0c8a0e-1111-4b1c-9e0a-7f3c1d2e5a66","nom":"Nuits","audience":"SOIGNANT_RECHERCHE_MISSIONS",
      "filtres":{"profession":"","rayonKm":30,"tauxMin":0,"typeContrat":"TOUS","urgentesOnly":false,"horaire":"NUIT","villeRecherche":""},
      "alerte_active":true,"frequence_alerte":"IMMEDIATE","dernier_check_le":"2026-11-01T18:00:00.123456+00:00",
      "nb_resultats_dernier_check":3,"cree_le":"2026-10-24T00:00:00+00:00","mis_a_jour_le":"2026-10-31T00:00:00+00:00"}]
    """

    private static let criteres = FiltresAlerte(profession: "", rayonKm: 25, tauxMin: 30, typeContrat: "CDD", urgentesOnly: true,
                                                horaire: "NUIT", villeRecherche: "Paris")

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
        let requete = try XCTUnwrap(registry.requests(to: chemin).first, "requête \(chemin) attendue")
        XCTAssertEqual(requete.method, "POST")
        return try XCTUnwrap(requete.bodyJSON as? [String: Any])
    }

    // MARK: - Lecture

    func testListeAudienceSoignantEtDecodage() async throws {
        registry.add("POST", lister, respond: .json(200, Self.listeJSON))
        let liste = try await gateway().lister(context: TestClient.context)
        XCTAssertEqual(liste, [FiltreSauvegarde(id: "7f0c8a0e-1111-4b1c-9e0a-7f3c1d2e5a66", nom: "Nuits", filtres: .objet([
            "profession": .chaine(""), "rayonKm": .nombre(30), "tauxMin": .nombre(0), "typeContrat": .chaine("TOUS"),
            "urgentesOnly": .booleen(false), "horaire": .chaine("NUIT"), "villeRecherche": .chaine(""),
        ]), alerteActive: true, frequence: .immediate, dernierCheckLe: "2026-11-01T18:00:00.123456+00:00", nbResultatsDernierCheck: 3)])
        XCTAssertEqual(try corps(lister)["p_audience"] as? String, "SOIGNANT_RECHERCHE_MISSIONS")
        XCTAssertEqual(registry.requests.count, 1, "une seule requête")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testListeIllisibleOuRefusJamaisUneListeVide() async {
        registry.add("POST", lister, respond: .json(200, #"{"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().lister(context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)

        registry.reset()
        registry.add("POST", lister, respond: .json(200, #"{"rows":[]}"#))
        let forme = await erreur { _ = try await self.gateway().lister(context: TestClient.context) }
        XCTAssertEqual(forme?.kind, .contract)

        registry.reset()
        registry.add("POST", lister, respond: .json(200, #"[{"id":"x","nom":"x"}]"#))
        let ligne = await erreur { _ = try await self.gateway().lister(context: TestClient.context) }
        XCTAssertEqual(ligne?.kind, .contract, "état d'alerte illisible : jamais une ligne plausible")
    }

    // MARK: - Création

    func testCreationSeptClesEntiersSansDecimalePuisRelecture() async throws {
        registry.add("POST", creer, respond: .json(200, #"{"success":true,"id":"7f0c8a0e-1111-4b1c-9e0a-7f3c1d2e5a66"}"#))
        registry.add("POST", lister, respond: .json(200, Self.listeJSON))
        let issue = try await gateway().creer(nom: "Alerte missions IDE", filtres: Self.criteres, alerte: true, frequence: .immediate,
                                              context: TestClient.context)
        guard case .relue(let liste) = issue else { return XCTFail("relecture attendue, obtenu \(issue)") }
        XCTAssertEqual(liste.map(\.nom), ["Nuits"], "liste relue rendue telle quelle (le modèle confirme)")
        let params = try corps(creer)
        XCTAssertEqual(params["p_nom"] as? String, "Alerte missions IDE")
        XCTAssertEqual(params["p_audience"] as? String, "SOIGNANT_RECHERCHE_MISSIONS", "p_audience obligatoire")
        XCTAssertEqual(params["p_alerte_active"] as? Bool, true)
        XCTAssertEqual(params["p_frequence_alerte"] as? String, "IMMEDIATE")
        let filtres = try XCTUnwrap(params["p_filtres"] as? [String: Any])
        XCTAssertEqual(Set(filtres.keys), ["profession", "rayonKm", "tauxMin", "typeContrat", "urgentesOnly", "horaire", "villeRecherche"])
        XCTAssertEqual(filtres["villeRecherche"] as? String, "Paris")
        let brut = try XCTUnwrap(registry.requests(to: creer).first?.body.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(brut.contains(#""rayonKm":25"#) && brut.contains(#""tauxMin":30"#), "entiers sans décimale : \(brut)")
        XCTAssertFalse(brut.contains("25.0") || brut.contains("30.0"))
        XCTAssertFalse(brut.contains("etablissement"), "jamais de filtre établissement")
        XCTAssertEqual(registry.requests(to: creer).count, 1)
        XCTAssertEqual(registry.requests(to: lister).count, 1, "relecture après la création")
    }

    func testRefusDeCreationVerbatim() async throws {
        for message in ["Limite de 20 recherches sauvegardées atteinte. Supprimez-en une avant d'en créer une nouvelle.",
                        "Un filtre avec ce nom existe déjà", "Compte ou critères de recherche invalides.",
                        "Nom invalide (1-100 caractères)"] {
            registry.reset()
            registry.add("POST", creer, respond: .json(200, #"{"error":"\#(message)"}"#))
            let issue = try await gateway().creer(nom: "x", filtres: Self.criteres, alerte: true, frequence: .immediate,
                                                  context: TestClient.context)
            XCTAssertEqual(issue, .refusee(message: message))
            XCTAssertTrue(registry.requests(to: lister).isEmpty, "aucune relecture d'un refus")
        }
        registry.reset()
        registry.add("POST", creer, respond: .json(200, #"{"error":"Non authentifié"}"#))
        let session = await erreur {
            _ = try await self.gateway().creer(nom: "x", filtres: Self.criteres, alerte: true, frequence: .immediate,
                                               context: TestClient.context)
        }
        XCTAssertEqual(session?.kind, .unauthorized)
    }

    func testCriteresHorsValidateurJamaisEnvoyes() async {
        var criteres = Self.criteres
        criteres.typeContrat = "INTERIM"
        let refus = await erreur {
            _ = try await self.gateway().creer(nom: "x", filtres: criteres, alerte: true, frequence: .immediate, context: TestClient.context)
        }
        XCTAssertEqual(refus?.kind, .contract)
        XCTAssertTrue(registry.requests.isEmpty, "aucune requête")
    }

    // MARK: - Modification et suppression

    func testModificationPuisRelectureEtFiltreIntrouvable() async throws {
        registry.add("POST", modifier, respond: .json(200, #"{"success":true}"#))
        registry.add("POST", lister, respond: .json(200, Self.listeJSON))
        let issue = try await gateway().modifier(id: "7f0c8a0e-1111-4b1c-9e0a-7f3c1d2e5a66", nom: "Nuits", alerte: false,
                                                 frequence: .hebdomadaire, context: TestClient.context)
        guard case .relue = issue else { return XCTFail("relecture attendue, obtenu \(issue)") }
        let params = try corps(modifier)
        XCTAssertEqual(params["p_id"] as? String, "7f0c8a0e-1111-4b1c-9e0a-7f3c1d2e5a66")
        XCTAssertEqual(params["p_nom"] as? String, "Nuits")
        XCTAssertEqual(params["p_alerte_active"] as? Bool, false)
        XCTAssertEqual(params["p_frequence_alerte"] as? String, "HEBDOMADAIRE")
        XCTAssertNil(params["p_filtres"], "filtres non modifiables")

        registry.reset()
        registry.add("POST", modifier, respond: .json(200, #"{"error":"Filtre introuvable"}"#))
        let introuvable = try await gateway().modifier(id: "x", nom: "x", alerte: true, frequence: .immediate, context: TestClient.context)
        XCTAssertEqual(introuvable, .refusee(message: "Filtre introuvable"))
    }

    func testSuppressionPuisRelectureSansLaLigne() async throws {
        registry.add("POST", supprimer, respond: .json(200, #"{"success":true}"#))
        registry.add("POST", lister, respond: .json(200, "[]"))
        let issue = try await gateway().supprimer(id: "7f0c8a0e-1111-4b1c-9e0a-7f3c1d2e5a66", context: TestClient.context)
        XCTAssertEqual(issue, .relue([]))
        XCTAssertEqual(try corps(supprimer)["p_id"] as? String, "7f0c8a0e-1111-4b1c-9e0a-7f3c1d2e5a66")
        XCTAssertEqual(registry.requests.map(\.path), [supprimer, lister], "suppression puis relecture, une requête chacune")

        registry.reset()
        registry.add("POST", supprimer, respond: .json(200, #"{"ok":true}"#))
        registry.add("POST", lister, respond: .json(200, "[]"))
        let forme = await erreur { _ = try await self.gateway().supprimer(id: "x", context: TestClient.context) }
        XCTAssertNil(forme, "`ok:true` est un succès annoncé (`estSucces`)")

        registry.reset()
        registry.add("POST", supprimer, respond: .json(200, #"{"deleted":1}"#))
        let inconnue = await erreur { _ = try await self.gateway().supprimer(id: "x", context: TestClient.context) }
        XCTAssertEqual(inconnue?.kind, .contract, "réponse sans succès ni refus : jamais un succès")
    }

    func testFabriqueSupabaseCableLaGateway() {
        XCTAssertTrue(SupabaseGateways.make(client: TestClient.make()).filtres is SupabaseFiltresGateway)
    }
}
