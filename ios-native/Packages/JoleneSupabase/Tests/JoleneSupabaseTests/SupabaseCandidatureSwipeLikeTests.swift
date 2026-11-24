import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// ❤️ du swipe (lot 4, T3a) : `CandidaturePort.confirmer(.swipeLike)` sur `fn_confirmer_action_planning_v1`, qui contrôle
/// le planning puis délègue à `fn_enregistrer_swipe(p_mission_id, 'LIKE', p_choix_contrat)` (`public.sql`, `WHEN
/// 'SWIPE_LIKE'`). Verrou levé parce que le serveur sert l'action ; succès `ok:true` sans `success`, annoncé après relecture
/// de la candidature ; URGENCE reste verrouillée (T11), sans requête.
final class SupabaseCandidatureSwipeLikeTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let missionId = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let candidatureId = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
    private let rpc = "/rest/v1/rpc/fn_confirmer_action_planning_v1"
    private let creneaux = [CreneauConfirme(debut: "2026-12-01T19:00:00Z", fin: "2026-12-02T07:00:00Z")]

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func aimer(_ action: ActionPlanning = .swipeLike, choix: String? = nil) async throws -> CandidatureOutcome {
        try await SupabaseCandidatureGateway(client: TestClient.make())
            .confirmer(action: action, missionId: missionId, creneaux: creneaux, message: nil, choixContrat: choix,
                       candidatureId: nil, context: TestClient.context)
    }

    private func reponse(_ json: String) { registry.add("POST", rpc, respond: .json(200, json)) }

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

    private func candidatureJSON(_ statut: String) -> String {
        #"[{"id":"\#(candidatureId)","statut":"\#(statut)","message":null,"type_contrat_choisi":"SALARIE","cree_le":"2026-11-18T00:00:00+00:00","mission_id":"\#(missionId)"}]"#
    }

    func testSwipeLikeOkSansSuccessReluParCandidatureId() async throws {
        reponse(#"{"ok":true,"swipe_id":"s-1","direction":"LIKE","candidature_id":"\#(candidatureId)","choix_contrat":"SALARIE","profession_requise":"IDE","docs_a_completer":false,"warning":null}"#)
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, candidatureJSON("EN_ATTENTE")))
        let issue = try await aimer(choix: "SALARIE")
        XCTAssertEqual(issue, .confirmed(candidatureId: candidatureId, contratId: nil))
        let envoye = try XCTUnwrap(registry.requests(to: rpc).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(envoye["p_action"] as? String, "SWIPE_LIKE")
        XCTAssertEqual(envoye["p_choix_contrat"] as? String, "SALARIE")
        XCTAssertTrue(envoye["p_message"] is NSNull, "aucun message sur un ❤️, comme le web")
        XCTAssertTrue(envoye["p_candidature_id"] is NSNull)
        XCTAssertEqual((envoye["p_creneaux_confirmes"] as? [[String: String]])?.count, 1, "planning exact affiché")
        XCTAssertEqual(registry.requests(to: "/rest/v1/candidatures").first?.query("id"), "eq.\(candidatureId)")
        XCTAssertTrue(registry.requests(to: "/rest/v1/rpc/fn_ecrire_audit_safe").isEmpty, "aucun audit sur un ❤️ (comme POSTULER)")
    }

    func testSwipeLikeOkMaisRelectureQuiNeConfirmePasEstUneErreur() async throws {
        reponse(#"{"ok":true,"candidature_id":"\#(candidatureId)"}"#)
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, "[]"))
        let refus = await erreur { _ = try await self.aimer() }
        XCTAssertEqual(refus, JoleneError(.contract, SupabaseCandidatureGateway.relectureMessage))
        XCTAssertEqual(registry.requests(to: rpc).count, 1, "aucun renvoi")
    }

    func testSwipeLikeSansCandidatureIdOuSansOkRefuseDeContrat() async throws {
        reponse(#"{"ok":true,"swipe_id":"s-1"}"#)
        let sansId = await erreur { _ = try await self.aimer() }
        XCTAssertEqual(sansId?.kind, .contract)
        registry.reset()
        reponse(#"{"swipe_id":"s-1","candidature_id":"\#(candidatureId)"}"#)
        let sansDrapeau = await erreur { _ = try await self.aimer() }
        XCTAssertEqual(sansDrapeau?.kind, .contract, "ni `ok:true` ni refus : jamais un succès supposé")
        XCTAssertTrue(registry.requests(to: "/rest/v1/candidatures").isEmpty)
    }

    func testSwipeLikeCodeTechniqueTraduitMessageRedigeVerbatim() async throws {
        reponse(#"{"ok":false,"error":"mission_deja_swipee"}"#)
        let deja = try await aimer()
        XCTAssertEqual(deja, .refusee(code: "mission_deja_swipee", message: "Vous avez déjà répondu à cette mission.", documentsRequisPour: nil))
        registry.reset()
        reponse(#"{"ok":false,"error":"Vous avez déjà candidaté à cette mission"}"#)
        let candidate = try await aimer()
        XCTAssertEqual(candidate, .refusee(code: nil, message: "Vous avez déjà candidaté à cette mission", documentsRequisPour: nil))
        registry.reset()
        reponse(#"{"ok":false,"error":"Ce planning chevauche une mission déjà confirmée.","conflit_planning":true}"#)
        let conflit = try await aimer()
        XCTAssertEqual(conflit, .refusee(code: nil, message: "Ce planning chevauche une mission déjà confirmée.", documentsRequisPour: nil))
        registry.reset()
        reponse(#"{"ok":false,"error":"Les documents requis pour candidater en libéral sont manquants ou expirés.","documents_requis_pour":"LIBERAL"}"#)
        let documents = try await aimer()
        XCTAssertEqual(documents, .refusee(code: nil, message: "Les documents requis pour candidater en libéral sont manquants ou expirés.",
                                           documentsRequisPour: "LIBERAL"))
    }

    func testSwipeLikeChoixRequisEtPlanningEtMissionFermeeEtSession() async throws {
        reponse(#"{"ok":false,"choix_requis":true,"error":"Choisissez votre mode de contrat.","options":[{"value":"SALARIE","label":"Salarié (CDD / bulletin de paie)"},{"value":"LIBERAL","label":"Libéral (note d'honoraires)"}]}"#)
        let choix = try await aimer()
        XCTAssertEqual(choix, .choixRequis([ChoixContratOption(value: "SALARIE", label: "Salarié (CDD / bulletin de paie)"),
                                            ChoixContratOption(value: "LIBERAL", label: "Libéral (note d'honoraires)")]))
        registry.reset()
        reponse(#"{"success":false,"ok":false,"code":"PLANNING_MODIFIE_RECONFIRMER","error":"Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires."}"#)
        let planning = try await aimer()
        XCTAssertEqual(planning, .planningAReconfirmer(code: "PLANNING_MODIFIE_RECONFIRMER",
                                                       message: "Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires."))
        registry.reset()
        reponse(#"{"success":false,"ok":false,"error":"Cette mission n'est plus disponible."}"#)
        let fermee = try await aimer()
        XCTAssertEqual(fermee, .missionDejaAttribuee(message: "Cette mission n'est plus disponible."))
        registry.reset()
        // Forme live sans session (revue B8 de #1165, m4) : le wrapper refuse avant toute délégation, verbatim.
        registry.reset()
        reponse(#"{"success":false,"ok":false,"error":"Accès réservé aux soignants authentifiés."}"#)
        let wrapper = try await aimer()
        XCTAssertEqual(wrapper, .refusee(code: nil, message: "Accès réservé aux soignants authentifiés.", documentsRequisPour: nil))
        // Branche défensive (inatteignable avec le wrapper live) : un `auth_required` délégué n'est jamais un code brut.
        registry.reset()
        reponse(#"{"ok":false,"error":"auth_required"}"#)
        let session = await erreur { _ = try await self.aimer() }
        XCTAssertEqual(session?.kind, .unauthorized)
    }

    /// URGENCE est livrée par T11 (`SupabaseCandidatureUrgenceTests`) : sans planning exact, aucune requête.
    func testUrgenceSansPlanningSansRequete() async throws {
        let refus = await erreur {
            _ = try await SupabaseCandidatureGateway(client: TestClient.make())
                .confirmer(action: .urgence, missionId: self.missionId, creneaux: [], message: nil, choixContrat: nil,
                           candidatureId: nil, context: TestClient.context)
        }
        XCTAssertEqual(refus?.message, SupabaseCandidatureGateway.planningRequisMessage)
        XCTAssertTrue(registry.requests.isEmpty, "planning exact obligatoire avant tout envoi (T11)")
    }
}
