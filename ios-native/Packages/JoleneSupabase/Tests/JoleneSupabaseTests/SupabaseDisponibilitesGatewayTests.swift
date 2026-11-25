import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Disponibilités sur Supabase (L4-T5) — fiche `fn_definir_disponibilite` de
/// `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` et lecture PostgREST de `disponibilites_soignant` :
/// - lecture `select=jour,creneau`, `jour >= <jour Paris>` comme le web (`MesDisponibilites.tsx` l.51-53), bornée au
///   soignant de la session ; réponse illisible → contrat, jamais une grille vide ;
/// - bascule : `p_jour`, `p_creneau` (`JOURNEE` ou `NUIT`), `p_disponible` ; `{success:true}` puis relecture de la
///   semaine civile du jour (aucun état optimiste) ; refus `{error}` verbatim sans relecture ; toute autre forme →
///   contrat ;
/// - un jour qui n'est pas une date n'est jamais envoyé ; la bascule n'est jamais renvoyée.
final class SupabaseDisponibilitesGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let table = "/rest/v1/disponibilites_soignant"
    private let rpc = "/rest/v1/rpc/fn_definir_disponibilite"

    private static let lundi = JourParis(iso: "2026-11-02")
    private static let mardi = JourParis(iso: "2026-11-03")
    private static let mardiJour = DispoCle(jour: mardi, creneau: .journee)
    private static let mardiNuit = DispoCle(jour: mardi, creneau: .nuit)
    private static let jeudiNuit = DispoCle(jour: JourParis(iso: "2026-11-05"), creneau: .nuit)
    private static let lignesJSON = """
    [{"jour":"2026-11-03","creneau":"JOURNEE"},{"jour":"2026-11-03","creneau":"NUIT"},{"jour":"2026-11-05","creneau":"NUIT"},
     {"jour":"2026-11-06","creneau":"MATIN"}]
    """

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseDisponibilitesGateway { SupabaseDisponibilitesGateway(client: TestClient.make()) }

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

    private func bornes(_ requete: RecordedRequest) -> [String] {
        requete.queryItems.filter { $0.name == "jour" }.compactMap(\.value)
    }

    // MARK: - Lecture

    func testLectureDepuisLeJourParisSousLIdentiteDuSoignant() async throws {
        registry.add("GET", table, respond: .json(200, Self.lignesJSON))
        let cles = try await gateway().lister(depuis: Self.lundi, context: TestClient.context)
        XCTAssertEqual(cles, [Self.mardiJour, Self.mardiNuit, Self.jeudiNuit], "créneau hors grille (MATIN) ignoré")
        let requete = try XCTUnwrap(registry.requests(to: table).first)
        XCTAssertEqual(requete.method, "GET")
        XCTAssertEqual(requete.query("select"), "jour,creneau")
        XCTAssertEqual(bornes(requete), ["gte.2026-11-02"], "comme le web : `.gte('jour', <aujourd'hui>)`, sans borne haute")
        XCTAssertEqual(requete.query("soignant_id"), "eq.\(TestClient.userId)", "jamais les lignes d'un autre (la policy admet aussi l'admin)")
        XCTAssertEqual(registry.requests.count, 1, "une seule requête")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testLectureVideEstUneGrilleSansCreneau() async throws {
        registry.add("GET", table, respond: .json(200, "[]"))
        let cles = try await gateway().lister(depuis: Self.lundi, context: TestClient.context)
        XCTAssertEqual(cles, [])
    }

    func testLectureIllisibleOuRefuseeJamaisUneGrilleVide() async {
        registry.add("GET", table, respond: .json(200, #"[{"jour":"03/11/2026","creneau":"NUIT"}]"#))
        let jour = await erreur { _ = try await self.gateway().lister(depuis: Self.lundi, context: TestClient.context) }
        XCTAssertEqual(jour?.kind, .contract, "jour illisible")

        registry.reset()
        registry.add("GET", table, respond: .json(200, #"{"jour":"2026-11-03","creneau":"NUIT"}"#))
        let forme = await erreur { _ = try await self.gateway().lister(depuis: Self.lundi, context: TestClient.context) }
        XCTAssertEqual(forme?.kind, .contract, "réponse qui n'est pas un tableau de lignes")

        registry.reset()
        registry.add("GET", table, respond: .json(200, #"[{"creneau":"NUIT"}]"#))
        let colonne = await erreur { _ = try await self.gateway().lister(depuis: Self.lundi, context: TestClient.context) }
        XCTAssertEqual(colonne?.kind, .contract, "colonne absente")

        registry.reset()
        registry.add("GET", table, respond: .json(401, #"{"code":"PGRST301","message":"JWT expired","details":null,"hint":null}"#))
        let session = await erreur { _ = try await self.gateway().lister(depuis: Self.lundi, context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)
        // Coupure réseau d'une lecture : `testBasculeAccepteeMaisRelectureImpossibleEstUneErreur` (même lecture ; le SDK
        // rejoue de lui-même un GET idempotent, jamais une écriture).
    }

    func testJourQuiNEstPasUneDateJamaisEnvoye() async {
        for iso in ["", "2026-11-3", "2026-02-30", "2026-11-03T00:00:00Z"] {
            let lecture = await erreur { _ = try await self.gateway().lister(depuis: JourParis(iso: iso), context: TestClient.context) }
            XCTAssertEqual(lecture?.kind, .contract, "lecture depuis « \(iso) »")
            let bascule = await erreur {
                _ = try await self.gateway().definir(jour: JourParis(iso: iso), creneau: .nuit, disponible: true, context: TestClient.context)
            }
            XCTAssertEqual(bascule?.kind, .contract, "bascule du « \(iso) »")
        }
        XCTAssertTrue(registry.requests.isEmpty, "aucune requête")
    }

    func testProfilQuiNeCorrespondPasALaSessionAucuneRequete() async {
        let autre = MissionReadContext(userId: TestClient.userId, email: nil, profile: SoignantProfile(id: "autre", profession: "IDE"))
        let lecture = await erreur { _ = try await self.gateway().lister(depuis: Self.lundi, context: autre) }
        XCTAssertEqual(lecture?.kind, .unauthorized)
        let bascule = await erreur {
            _ = try await self.gateway().definir(jour: Self.mardi, creneau: .nuit, disponible: true, context: autre)
        }
        XCTAssertEqual(bascule?.kind, .unauthorized)
        XCTAssertTrue(registry.requests.isEmpty, "aucune requête")
    }

    // MARK: - Bascule

    func testBasculeAccepteePuisRelectureDeLaSemaineCivile() async throws {
        registry.add("POST", rpc, respond: .json(200, #"{"success":true}"#))
        registry.add("GET", table, respond: .json(200, Self.lignesJSON))
        let issue = try await gateway().definir(jour: Self.mardi, creneau: .nuit, disponible: true, context: TestClient.context)
        XCTAssertEqual(issue, .relue([Self.mardiJour, Self.mardiNuit, Self.jeudiNuit]), "semaine relue rendue telle quelle (le modèle confirme)")

        let appel = try XCTUnwrap(registry.requests(to: rpc).first)
        XCTAssertEqual(appel.method, "POST")
        let params = try XCTUnwrap(appel.bodyJSON as? [String: Any])
        XCTAssertEqual(Set(params.keys), ["p_jour", "p_creneau", "p_disponible"])
        XCTAssertEqual(params["p_jour"] as? String, "2026-11-03")
        XCTAssertEqual(params["p_creneau"] as? String, "NUIT")
        XCTAssertEqual(params["p_disponible"] as? Bool, true)

        let relecture = try XCTUnwrap(registry.requests(to: table).first)
        XCTAssertEqual(relecture.query("select"), "jour,creneau")
        XCTAssertEqual(bornes(relecture), ["gte.2026-11-02", "lte.2026-11-08"], "du lundi au dimanche de la semaine du jour")
        XCTAssertEqual(relecture.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(registry.requests.map(\.path), [rpc, table], "bascule puis relecture, une requête chacune")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testRetraitEnvoieLeCreneauJourneeEtFaux() async throws {
        registry.add("POST", rpc, respond: .json(200, #"{"success":true}"#))
        registry.add("GET", table, respond: .json(200, "[]"))
        let issue = try await gateway().definir(jour: JourParis(iso: "2026-10-25"), creneau: .journee, disponible: false,
                                                context: TestClient.context)
        XCTAssertEqual(issue, .relue([]))
        let params = try XCTUnwrap(registry.requests(to: rpc).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(params["p_jour"] as? String, "2026-10-25")
        XCTAssertEqual(params["p_creneau"] as? String, "JOURNEE")
        XCTAssertEqual(params["p_disponible"] as? Bool, false)
        let relecture = try XCTUnwrap(registry.requests(to: table).first)
        XCTAssertEqual(bornes(relecture), ["gte.2026-10-19", "lte.2026-10-25"], "semaine du changement d'heure : jours civils")
    }

    func testRefusDeLaRPCVerbatimSansRelecture() async throws {
        for message in ["La disponibilité doit être entre aujourd'hui et J+90", "Créneau invalide", "Profil soignant introuvable"] {
            registry.reset()
            registry.add("POST", rpc, respond: .json(200, #"{"error":"\#(message)"}"#))
            let issue = try await gateway().definir(jour: Self.mardi, creneau: .nuit, disponible: true, context: TestClient.context)
            XCTAssertEqual(issue, .refusee(message: message))
            XCTAssertTrue(registry.requests(to: table).isEmpty, "aucune relecture d'un refus")
            XCTAssertEqual(registry.requests(to: rpc).count, 1)
        }
    }

    func testReponseSansSuccesNiRefusJamaisUnSucces() async {
        for corps in ["{}", #"{"success":false}"#, "null", "true", #"{"deleted":1}"#] {
            registry.reset()
            registry.add("POST", rpc, respond: .json(200, corps))
            let forme = await erreur {
                _ = try await self.gateway().definir(jour: Self.mardi, creneau: .nuit, disponible: true, context: TestClient.context)
            }
            XCTAssertEqual(forme?.kind, .contract, corps)
            XCTAssertTrue(registry.requests(to: table).isEmpty, "aucune relecture sans succès annoncé : \(corps)")
        }
        registry.reset()
        registry.add("POST", rpc, respond: .json(200, #"{"error":"Non authentifié"}"#))
        let session = await erreur {
            _ = try await self.gateway().definir(jour: Self.mardi, creneau: .nuit, disponible: true, context: TestClient.context)
        }
        XCTAssertEqual(session?.kind, .unauthorized)
    }

    func testErreursDeTransportDeLaBasculeSansRenvoi() async {
        registry.add("POST", rpc, respond: .json(401, #"{"code":"PGRST301","message":"JWT expired","details":null,"hint":null}"#))
        let session = await erreur {
            _ = try await self.gateway().definir(jour: Self.mardi, creneau: .nuit, disponible: true, context: TestClient.context)
        }
        XCTAssertEqual(session?.kind, .unauthorized)

        registry.reset()
        registry.add("POST", rpc, respond: .json(404, #"{"code":"PGRST202","message":"Could not find the function","details":null,"hint":null}"#))
        let contrat = await erreur {
            _ = try await self.gateway().definir(jour: Self.mardi, creneau: .nuit, disponible: true, context: TestClient.context)
        }
        XCTAssertEqual(contrat?.kind, .contract)
        XCTAssertEqual(registry.requests(to: rpc).count, 1, "PGRST202 : refus définitif, aucun renvoi")

        registry.reset()
        registry.add("POST", rpc, respond: .networkFailure())
        let reseau = await erreur {
            _ = try await self.gateway().definir(jour: Self.mardi, creneau: .nuit, disponible: true, context: TestClient.context)
        }
        XCTAssertEqual(reseau?.kind, .network)
        XCTAssertEqual(registry.requests.count, 1, "aucun renvoi, aucune relecture")
    }

    func testBasculeAccepteeMaisRelectureImpossibleEstUneErreur() async {
        registry.add("POST", rpc, respond: .json(200, #"{"success":true}"#))
        registry.add("GET", table, respond: .networkFailure())
        let reseau = await erreur {
            _ = try await self.gateway().definir(jour: Self.mardi, creneau: .nuit, disponible: true, context: TestClient.context)
        }
        XCTAssertEqual(reseau?.kind, .network, "sans relecture, aucun succès annoncé : le modèle réconcilie")
        XCTAssertEqual(registry.requests(to: rpc).count, 1, "la bascule n'est jamais renvoyée (seule la lecture GET est rejouée par le SDK)")
        XCTAssertFalse(registry.requests(to: table).isEmpty)

        registry.reset()
        registry.add("POST", rpc, respond: .json(200, #"{"success":true}"#))
        registry.add("GET", table, respond: .json(200, #"[{"jour":"x","creneau":"NUIT"}]"#))
        let illisible = await erreur {
            _ = try await self.gateway().definir(jour: Self.mardi, creneau: .nuit, disponible: true, context: TestClient.context)
        }
        XCTAssertEqual(illisible?.kind, .contract)
    }

    // MARK: - Câblage

    func testFabriqueSupabaseCableLaGateway() {
        XCTAssertTrue(SupabaseGateways.make(client: TestClient.make()).disponibilites is SupabaseDisponibilitesGateway)
        XCTAssertEqual(SupabaseDisponibilitesGateway.rpcDefinir, "fn_definir_disponibilite")
        XCTAssertEqual(SupabaseDisponibilitesGateway.table, "disponibilites_soignant")
    }
}
