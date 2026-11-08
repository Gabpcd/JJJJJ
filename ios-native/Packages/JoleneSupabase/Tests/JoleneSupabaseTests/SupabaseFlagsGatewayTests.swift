import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Drapeaux d'écran natif (décision 15) : `fn_param_bool(p_cle, p_defaut)` lu avec la session
/// (aucun GRANT `anon`, l.83946-83948 du dump). Toute erreur rend le défaut demandé — `true`
/// pour les écrans natifs (fail-open, inverse assumé de `useParamBool.ts`) : un backend sans
/// les lignes B0, muet ou refusant ne masque jamais un écran.
final class SupabaseFlagsGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let chemin = "/rest/v1/rpc/fn_param_bool"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseFlagsGateway { SupabaseFlagsGateway(client: TestClient.make()) }

    func testValeurServeurTransmiseAvecCleEtDefaut() async throws {
        registry.add("POST", chemin, respond: .json(200, "false"))
        let actif = await gateway().ecranActif(.missions)
        XCTAssertFalse(actif, "arrêt d'urgence lu côté serveur")
        let requete = try XCTUnwrap(registry.requests(to: chemin).first)
        let corps = try XCTUnwrap(requete.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["p_cle"] as? String, "ios_natif_missions_actif")
        XCTAssertEqual(corps["p_defaut"] as? Bool, true)
        XCTAssertEqual(corps.count, 2)
        XCTAssertEqual(requete.header("X-Client-Info"), "jolene-ios/2.0.0")

        registry.reset()
        registry.add("POST", chemin, respond: .json(200, "true"))
        let reactive = await gateway().ecranActif(cle: EcranNatif.accueil.cle, defaut: false)
        XCTAssertTrue(reactive)
    }

    func testErreurReseauRendLeDefaut() async {
        registry.add("POST", chemin, respond: .networkFailure())
        let failOpen = await gateway().ecranActif(.accueil)
        XCTAssertTrue(failOpen, "défaut fail-open des écrans natifs")
        let defautDemande = await gateway().ecranActif(cle: EcranNatif.accueil.cle, defaut: false)
        XCTAssertFalse(defautDemande, "erreur → défaut demandé, jamais une valeur inventée")
    }

    func testRefusDeDroitsEtSessionExpireeRendentLeDefaut() async {
        for (statut, corps) in [(403, #"{"code":"42501","message":"permission denied for function fn_param_bool","details":null,"hint":null}"#),
                                (401, #"{"code":"PGRST301","message":"JWT expired","details":null,"hint":null}"#)] {
            registry.reset()
            registry.add("POST", chemin, respond: .json(statut, corps))
            let actif = await gateway().ecranActif(.explorer)
            XCTAssertTrue(actif, "HTTP \(statut)")
        }
    }

    func testFonctionIntrouvableRendLeDefautSansRenvoi() async {
        registry.add("POST", chemin, respond: .json(404, """
        {"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.fn_param_bool in the schema cache"}
        """))
        let actif = await gateway().ecranActif(.profil)
        XCTAssertTrue(actif)
        XCTAssertEqual(registry.requests(to: chemin).count, 1, "aucun renvoi automatique")
    }

    func testReponseNonBooleenneRendLeDefaut() async {
        for corps in ["null", #""true""#, "1", #"{"valeur":true}"#] {
            registry.reset()
            registry.add("POST", chemin, respond: .json(200, corps))
            let actif = await gateway().ecranActif(cle: EcranNatif.revenus.cle, defaut: true)
            XCTAssertTrue(actif, corps)
            let inactif = await gateway().ecranActif(cle: EcranNatif.revenus.cle, defaut: false)
            XCTAssertFalse(inactif, corps)
        }
    }

    func testCleVideRendLeDefautSansAppel() async {
        let actif = await gateway().ecranActif(cle: "  ", defaut: true)
        XCTAssertTrue(actif)
        XCTAssertTrue(registry.requests.isEmpty)
    }
}
