import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Export RGPD (lot 3, T11 ; fiche `fn_rgpd_exporter_rate_limited` de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`,
/// définitions live de `fn_rgpd_exporter_rate_limited` et `fn_rgpd_exporter_donnees_soignant` relues en lecture
/// seule le 08/11/2026 : corps identiques au dump) : POST `/rest/v1/rpc/fn_rgpd_exporter_rate_limited` sans
/// paramètre, une seule fois ; le corps est rendu OCTET POUR OCTET (ordre des clés du jsonb conservé jusqu'au
/// fichier) ; `{error}` en HTTP 200 → message serveur verbatim, « Non authentifié » → session expirée ; corps
/// non objet → refus de contrat.
final class SupabaseExportGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let chemin = "/rest/v1/rpc/fn_rgpd_exporter_rate_limited"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func exporter() async throws -> ExportDonneesRGPD {
        try await SupabaseExportGateway(client: TestClient.make()).exporter(context: TestClient.context)
    }

    private func erreur(_ status: Int = 200, _ corps: String) async -> JoleneError? {
        registry.reset()
        registry.add("POST", chemin, respond: .json(status, corps))
        do {
            _ = try await exporter()
            return nil
        } catch let jolene as JoleneError {
            return jolene
        } catch {
            XCTFail("erreur non traduite : \(error)")
            return nil
        }
    }

    func testCorpsRenduOctetPourOctet() async throws {
        // Ordre d'un jsonb (longueur puis octets), différent de l'ordre alphabétique : il doit survivre.
        let corps = #"{"profil":{"id":"u","nom":"Martin","prenom":"Léa"},"missions":[{"id":"m-1","statut":"TERMINEE"}],"export_date":"2026-11-08T10:00:00.123+00:00","utilisateur_id":"u","notations_recues":[]}"#
        registry.add("POST", chemin, respond: .json(200, corps))

        let donnees = try await exporter()

        XCTAssertEqual(donnees.json, Data(corps.utf8))
        let requete = try XCTUnwrap(registry.requests(to: chemin).first)
        XCTAssertEqual(registry.requests(to: chemin).count, 1, "un seul appel, aucun renvoi")
        XCTAssertEqual(requete.method, "POST")
        if let corpsRequete = requete.bodyJSON as? [String: Any] {
            XCTAssertTrue(corpsRequete.isEmpty, "aucun paramètre (`Args: never`)")
        }
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testRefusDeLimiteVerbatim() async {
        let refus = await erreur(#"{"error":"Trop d'exports en peu de temps. Réessayez dans quelques minutes."}"#)
        XCTAssertEqual(refus?.kind, .unknown)
        XCTAssertEqual(refus?.message, "Trop d'exports en peu de temps. Réessayez dans quelques minutes.")
        XCTAssertEqual(refus?.message, ExportRGPD.refusLimiteServeur)
    }

    func testNonAuthentifieEstUneSessionExpiree() async {
        let refus = await erreur(#"{"error":"Non authentifié"}"#)
        XCTAssertEqual(refus?.kind, .unauthorized)
        XCTAssertEqual(refus?.message, SupabaseErrorMapping.unauthorizedMessage)
    }

    func testErreurNonTextuelleRepliGenerique() async {
        let refus = await erreur(#"{"error":{"detail":"x"}}"#)
        XCTAssertEqual(refus?.kind, .unknown)
        XCTAssertEqual(refus?.message, ExportRGPD.Textes.echec)
    }

    func testCorpsNonObjetEstUnRefusDeContrat() async {
        for corps in ["[]", "\"export\"", "null", "{"] {
            let refus = await erreur(corps)
            XCTAssertEqual(refus?.kind, .contract, corps)
            XCTAssertEqual(refus?.message, SupabaseErrorMapping.contractMessage, corps)
        }
    }

    func testMondeSupabaseCableLesPortsDuCompte() {
        let gateways = SupabaseGateways.make(client: TestClient.make())
        XCTAssertTrue(gateways.motDePasse is SupabaseMotDePasseGateway, "lot 3, T11 câble le mot de passe")
        XCTAssertTrue(gateways.exportRGPD is SupabaseExportGateway, "lot 3, T11 câble l'export RGPD")
    }

    func testFonctionIntrouvableEtReseau() async {
        let introuvable = await erreur(404, #"{"code":"PGRST202","message":"Could not find the function"}"#)
        XCTAssertEqual(introuvable?.kind, .contract)
        registry.reset()
        registry.add("POST", chemin, respond: .networkFailure())
        do {
            _ = try await exporter()
            XCTFail("coupure : erreur attendue")
        } catch let jolene as JoleneError {
            XCTAssertEqual(jolene.kind, .network)
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertEqual(registry.requests(to: chemin).count, 1)
    }
}
