import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Swipe du lot 4 (T3a) sur `fn_obtenir_missions_swipe`, `fn_enregistrer_swipe`, `fn_retirer_candidature`,
/// `fn_initialiser_preferences_matching` et `swipes` : une forme de réponse de la fiche `CONTRATS_RPC_SOIGNANT.md` = un
/// test. Codes et messages repris de `supabase/schema/public.sql` ; un succès n'est jamais annoncé sans relecture.
final class SupabaseSwipeGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let missionId = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let candidatureId = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
    private let paquetRPC = "/rest/v1/rpc/fn_obtenir_missions_swipe"
    private let swipeRPC = "/rest/v1/rpc/fn_enregistrer_swipe"
    private let retraitRPC = "/rest/v1/rpc/fn_retirer_candidature"
    private let preferencesRPC = "/rest/v1/rpc/fn_initialiser_preferences_matching"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseSwipeGateway { SupabaseSwipeGateway(client: TestClient.make()) }

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

    private func corps(_ path: String) throws -> [String: Any] {
        try XCTUnwrap(registry.requests(to: path).first?.bodyJSON as? [String: Any], "aucun corps \(path)")
    }

    private func ligne(_ id: String, score: String = "null") -> String {
        """
        {"mission_id":"\(id)","intitule":"Nuit IDE","profession_requise":"IDE","etablissement_id":"e-1",
         "etablissement_nom":"Clinique fictive","etablissement_ville":"Lyon","debut_le":"2026-12-01T19:00:00+00:00",
         "fin_le":"2026-12-02T07:00:00+00:00","est_urgente":false,"nb_creneaux":1,"score":\(score),"breakdown":{},
         "paiement_rapide":false,"distance_km":4.2}
        """
    }

    private func creneaux(_ ids: [String]) {
        let slots = ids.map {
            #"{"id":"\#($0)-s1","mission_id":"\#($0)","debut":"2026-12-01T19:00:00+00:00","fin":"2026-12-02T07:00:00+00:00","est_pause":false,"type_creneau":"PREVISIONNEL"}"#
        }
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(
            200, "[\(slots.joined(separator: ","))]", headers: ["Content-Range": "0-\(max(ids.count - 1, 0))/\(ids.count)"]))
    }

    // MARK: - Paquet

    func testPaquetDecodeLesCartesPuisLitLePlanningPrevisionnel() async throws {
        registry.add("POST", paquetRPC, respond: .json(200, #"{"missions":[\#(ligne(missionId)),\#(ligne("m-2", score: "77"))]}"#))
        creneaux([missionId, "m-2"])
        let cartes = try await gateway().paquet(context: TestClient.context)
        XCTAssertEqual(cartes.map(\.id), [missionId, "m-2"], "ordre serveur conservé")
        XCTAssertEqual(cartes.map(\.score), [nil, 77], "score inconnu : jamais 0")
        XCTAssertTrue(cartes.allSatisfy(\.mission.planningExact))
        XCTAssertEqual(cartes.first?.etablissementNom, "Clinique fictive", "nom du payload, sans fn_etablissements_safe")
        XCTAssertEqual(cartes.first?.mission.distanceKm, 4.2)
        XCTAssertEqual(try corps(paquetRPC)["p_limit"] as? Int, 20)
        let slots = try XCTUnwrap(registry.requests(to: "/rest/v1/mission_creneaux").first)
        XCTAssertEqual(slots.query("type_creneau"), "eq.PREVISIONNEL")
        XCTAssertEqual(slots.query("est_pause"), "eq.false")
        XCTAssertTrue(registry.requests(to: "/rest/v1/rpc/fn_etablissements_safe").isEmpty)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testPaquetVideSansLectureDePlanning() async throws {
        registry.add("POST", paquetRPC, respond: .json(200, #"{"missions":[]}"#))
        let cartes = try await gateway().paquet(context: TestClient.context)
        XCTAssertTrue(cartes.isEmpty)
        XCTAssertTrue(registry.requests(to: "/rest/v1/mission_creneaux").isEmpty)
    }

    func testPaquetAuthRequiredEstUneSessionExpiree() async throws {
        registry.add("POST", paquetRPC, respond: .json(200, #"{"missions":[],"error":"auth_required"}"#))
        let refus = await erreur { _ = try await self.gateway().paquet(context: TestClient.context) }
        XCTAssertEqual(refus?.kind, .unauthorized)
    }

    func testPaquetSansPlanningLisibleEchoueEntier() async throws {
        registry.add("POST", paquetRPC, respond: .json(200, #"{"missions":[\#(ligne(missionId))]}"#))
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[]")) // pas de Content-Range
        let refus = await erreur { _ = try await self.gateway().paquet(context: TestClient.context) }
        XCTAssertEqual(refus, MissionSlotPager.countUnavailable, "jamais une carte au planning supposé")
    }

    func testPaquetSansCleMissionsEstUnDefautDeContrat() async throws {
        registry.add("POST", paquetRPC, respond: .json(200, #"{"cartes":[]}"#))
        let refus = await erreur { _ = try await self.gateway().paquet(context: TestClient.context) }
        XCTAssertEqual(refus?.kind, .contract)
    }

    // MARK: - ✕ et ⭐

    func testPasserOkSansChoixDeContrat() async throws {
        registry.add("POST", swipeRPC, respond: .json(200, #"{"ok":true,"swipe_id":"s-1","direction":"DISLIKE","candidature_id":null}"#))
        let issue = try await gateway().enregistrer(missionId: missionId.uppercased(), direction: .passer, context: TestClient.context)
        XCTAssertEqual(issue, .enregistre)
        let envoye = try corps(swipeRPC)
        XCTAssertEqual(envoye["p_mission_id"] as? String, missionId, "uuid canonique")
        XCTAssertEqual(envoye["p_direction"] as? String, "DISLIKE")
        XCTAssertNil(envoye["p_choix_contrat"], "p_choix_contrat jamais envoyé hors ❤️, comme le web")
        XCTAssertTrue(registry.requests(to: "/rest/v1/missions_sauvegardees").isEmpty, "✕ : aucune relecture de favori")
    }

    func testFavoriOkReluDansMissionsSauvegardees() async throws {
        registry.add("POST", swipeRPC, respond: .json(200, #"{"ok":true,"swipe_id":"s-1","direction":"FAVORI","sauvegardee":true}"#))
        registry.add("GET", "/rest/v1/missions_sauvegardees", respond: .json(200, #"[{"mission_id":"\#(missionId)"}]"#))
        let issue = try await gateway().enregistrer(missionId: missionId, direction: .favori, context: TestClient.context)
        XCTAssertEqual(issue, .enregistre)
        let relecture = try XCTUnwrap(registry.requests(to: "/rest/v1/missions_sauvegardees").first)
        XCTAssertEqual(relecture.query("mission_id"), "eq.\(missionId)")
        XCTAssertEqual(relecture.query("soignant_id"), "eq.\(TestClient.userId)")
    }

    func testFavoriOkMaisNonReluEstUneErreur() async throws {
        registry.add("POST", swipeRPC, respond: .json(200, #"{"ok":true,"direction":"FAVORI","sauvegardee":true}"#))
        registry.add("GET", "/rest/v1/missions_sauvegardees", respond: .json(200, "[]"))
        let refus = await erreur { _ = try await self.gateway().enregistrer(missionId: self.missionId, direction: .favori, context: TestClient.context) }
        XCTAssertEqual(refus, JoleneError(.contract, SupabaseSwipeGateway.relectureFavoriMessage))
        XCTAssertEqual(registry.requests(to: swipeRPC).count, 1, "aucun renvoi")
    }

    func testCodesTechniquesTraduitsEtAuthRequiredSessionExpiree() async throws {
        for code in ["direction_invalide", "mission_indisponible", "profil_introuvable", "profession_incompatible", "acces_refuse",
                     "mission_deja_swipee"] {
            registry.reset()
            registry.add("POST", swipeRPC, respond: .json(200, #"{"ok":false,"error":"\#(code)"}"#))
            let issue = try await gateway().enregistrer(missionId: missionId, direction: .passer, context: TestClient.context)
            XCTAssertEqual(issue, .refuse(code: code, message: try XCTUnwrap(SwipeRefus.libelles[code])), code)
        }
        registry.reset()
        registry.add("POST", swipeRPC, respond: .json(200, #"{"ok":false,"error":"auth_required"}"#))
        let refus = await erreur { _ = try await self.gateway().enregistrer(missionId: self.missionId, direction: .passer, context: TestClient.context) }
        XCTAssertEqual(refus?.kind, .unauthorized)
    }

    func testMessageRedigeRestitueVerbatimEtCorpsIncoherentRefuse() async throws {
        registry.add("POST", swipeRPC, respond: .json(200, #"{"ok":false,"error":"Vous avez déjà candidaté à cette mission"}"#))
        let issue = try await gateway().enregistrer(missionId: missionId, direction: .favori, context: TestClient.context)
        XCTAssertEqual(issue, .refuse(code: nil, message: "Vous avez déjà candidaté à cette mission"))
        registry.reset()
        registry.add("POST", swipeRPC, respond: .json(200, #"{"success":true}"#))
        let refus = await erreur { _ = try await self.gateway().enregistrer(missionId: self.missionId, direction: .passer, context: TestClient.context) }
        XCTAssertEqual(refus?.kind, .contract, "ni `ok:true` ni refus : jamais un succès supposé")
    }

    func testIdentifiantInvalideSansRequete() async throws {
        let refus = await erreur { _ = try await self.gateway().enregistrer(missionId: "pas-un-uuid", direction: .passer, context: TestClient.context) }
        XCTAssertEqual(refus?.kind, .contract)
        XCTAssertTrue(registry.requests.isEmpty)
    }

    // MARK: - Retrait

    func testRetraitSuccesPuisCandidatureRelueAbsente() async throws {
        registry.add("POST", retraitRPC, respond: .json(200, #"{"success":true}"#))
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, "[]"))
        let issue = try await gateway().retirer(candidatureId: candidatureId, context: TestClient.context)
        XCTAssertEqual(issue, .retiree)
        XCTAssertEqual(try corps(retraitRPC)["p_candidature_id"] as? String, candidatureId)
        let relecture = try XCTUnwrap(registry.requests(to: "/rest/v1/candidatures").first)
        XCTAssertEqual(relecture.query("id"), "eq.\(candidatureId)")
        XCTAssertEqual(relecture.query("soignant_id"), "eq.\(TestClient.userId)")
    }

    func testRetraitSuccesMaisCandidatureEncorePresenteEstUneErreur() async throws {
        registry.add("POST", retraitRPC, respond: .json(200, #"{"success":true}"#))
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200,
            #"[{"id":"\#(candidatureId)","statut":"EN_ATTENTE","message":null,"type_contrat_choisi":null,"cree_le":null,"mission_id":"\#(missionId)"}]"#))
        let refus = await erreur { _ = try await self.gateway().retirer(candidatureId: self.candidatureId, context: TestClient.context) }
        XCTAssertEqual(refus, JoleneError(.contract, SupabaseSwipeGateway.relectureRetraitMessage))
    }

    func testRetraitRefusVerbatimEtNonAuthentifie() async throws {
        let dejaTraitee = "La candidature a déjà été traitée et ne peut plus être retirée ici."
        for message in [dejaTraitee, "Candidature introuvable", "Non autorisé"] {
            registry.reset()
            registry.add("POST", retraitRPC, respond: .json(200, #"{"success":false,"error":"\#(message)"}"#))
            let issue = try await gateway().retirer(candidatureId: candidatureId, context: TestClient.context)
            XCTAssertEqual(issue, .refuse(message: message))
            XCTAssertTrue(registry.requests(to: "/rest/v1/candidatures").isEmpty, "aucune relecture d'un refus")
        }
        registry.reset()
        registry.add("POST", retraitRPC, respond: .json(200, #"{"success":false,"error":"Non authentifié"}"#))
        let refus = await erreur { _ = try await self.gateway().retirer(candidatureId: self.candidatureId, context: TestClient.context) }
        XCTAssertEqual(refus?.kind, .unauthorized)
    }

    // MARK: - Quiz

    func testNombreDeSwipesEnTeteSeulement() async throws {
        registry.add("HEAD", "/rest/v1/swipes", respond: .json(200, "", headers: ["Content-Range": "*/3"]))
        let nombre = try await gateway().nombreSwipes(context: TestClient.context)
        XCTAssertEqual(nombre, 3)
        let requete = try XCTUnwrap(registry.requests(to: "/rest/v1/swipes").first)
        XCTAssertEqual(requete.query("select"), "id")
        XCTAssertEqual(requete.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(requete.header("Prefer")?.contains("count=exact"), true)
    }

    func testPreferencesEnvoyeesPuisRefusVerbatim() async throws {
        registry.add("POST", preferencesRPC, respond: .json(200, #"{"success":true}"#))
        try await gateway().initialiserPreferences(.depuisQuiz(horaire: .nuit, rythme: .semaine), context: TestClient.context)
        let envoye = try corps(preferencesRPC)
        XCTAssertEqual(envoye["p_pref_nuit"] as? Double, 0.8)
        XCTAssertEqual(envoye["p_pref_jour"] as? Double, 0.3)
        XCTAssertEqual(envoye["p_pref_weekend"] as? Double, 0.3)
        XCTAssertEqual(envoye["p_pref_semaine"] as? Double, 0.8)

        registry.reset()
        registry.add("POST", preferencesRPC, respond: .json(200, #"{"success":false,"error":"Préférences hors bornes [0,1]"}"#))
        let refus = await erreur { try await self.gateway().initialiserPreferences(.depuisQuiz(horaire: .tous, rythme: .tous), context: TestClient.context) }
        XCTAssertEqual(refus, JoleneError(.unknown, "Préférences hors bornes [0,1]"))

        registry.reset()
        let horsBornes = await erreur {
            try await self.gateway().initialiserPreferences(PreferencesMatching(nuit: -1, jour: 0, weekend: 0, semaine: 0), context: TestClient.context)
        }
        XCTAssertEqual(horsBornes?.kind, .contract)
        XCTAssertTrue(registry.requests.isEmpty, "rien n'est envoyé hors bornes")
    }
}
