import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Évaluations reçues sur Supabase (L4-T9) — fiches `fn_mes_notations_recues_avec_stats` et `fn_signaler_notation` de
/// `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` :
/// - deux RPC seulement, aucune requête PostgREST (la table des notations n'est jamais lue : filtre de visibilité
///   centralisé) ; `p_limit = 20`, `p_offset = page × 20`, filtres omis quand ils sont absents ;
/// - `note_moyenne` et statistiques du serveur reprises telles quelles ; `NON_AUTHENTIFIE` → session expirée ; réponse
///   illisible → contrat, jamais une page vide ;
/// - signalement : `{success:true}` → `.signale` ; refus verbatim (double signalement, notation d'un autre, compte
///   désactivé, exception P0001) ; une seule requête par appel, aucun renvoi.
final class SupabaseEvaluationsGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let lecture = "/rest/v1/rpc/fn_mes_notations_recues_avec_stats"
    private let signalement = "/rest/v1/rpc/fn_signaler_notation"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseEvaluationsGateway { SupabaseEvaluationsGateway(client: TestClient.make()) }

    /// `note_moyenne` 3.9 et `note_moyenne_globale` 4.9 ne se déduisent d'aucun calcul sur les critères servis.
    private static let pageJSON = """
    {"success":true,"total":41,"limit":20,"offset":20,
     "notations":[{"id":"7f0c8a0e-1111-4b1c-9e0a-7f3c1d2e5a66","mission_id":"m-1","mission_intitule":"Remplacement IDE",
                   "mission_fin_le":"2026-10-26T18:00:00+00:00","etablissement_id":"e-1","etablissement_nom":"Clinique des Tests",
                   "critere_1":4,"critere_2":4,"critere_3":5,"critere_4":4,"note_moyenne":3.9,"commentaire":"Très bien.",
                   "signale":false,"cree_le":"2026-10-28T09:30:00+00:00"}],
     "stats":{"note_moyenne_globale":4.9,"total_evaluations":41,"pct_5_etoiles":33.3},
     "evolution_6m":[{"mois":"2026-10","note_moyenne":4.5,"nb":2}],
     "etabs_disponibles":[{"id":"e-1","nom":"Clinique des Tests"}]}
    """

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

    func testLecturePageDeVingtEtValeursServeurTellesQuelles() async throws {
        registry.add("POST", lecture, respond: .json(200, Self.pageJSON))
        let page = try await gateway().recues(filtre: FiltreEvaluations(periode: .sixMois, noteMin: 4, etablissementId: "e-1"),
                                              page: 1, context: TestClient.context)
        XCTAssertEqual(page.total, 41)
        XCTAssertEqual(page.notations.map(\.noteMoyenne), [3.9], "note_moyenne du serveur, jamais (4+4+5+4)/4")
        XCTAssertEqual(page.notations.first?.signale, false)
        XCTAssertEqual(page.notations.first?.etablissementNom, "Clinique des Tests")
        XCTAssertEqual(page.stats, StatsEvaluations(noteMoyenneGlobale: 4.9, totalEvaluations: 41, pct5Etoiles: 33.3),
                       "statistiques du serveur : ni moyenne ni total recalculés depuis la page")
        XCTAssertEqual(page.evolution, [PointEvolutionNotes(mois: "2026-10", noteMoyenne: 4.5, nb: 2)])
        XCTAssertEqual(page.etablissements, [EtablissementEvaluateur(id: "e-1", nom: "Clinique des Tests")])
        let params = try corps(lecture)
        XCTAssertEqual(params["p_periode"] as? String, "6M")
        XCTAssertEqual(params["p_note_min"] as? Int, 4)
        XCTAssertEqual(params["p_etablissement_id"] as? String, "e-1")
        XCTAssertEqual(params["p_limit"] as? Int, 20, "PAR_PAGE du web")
        XCTAssertEqual(params["p_offset"] as? Int, 20, "page × 20")
        XCTAssertEqual(Set(params.keys), ["p_periode", "p_note_min", "p_etablissement_id", "p_limit", "p_offset"])
        XCTAssertEqual(registry.requests.count, 1, "une seule requête : la RPC filtrée, aucune lecture de table")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testFiltresAbsentsOmisEtPremierePage() async throws {
        registry.add("POST", lecture, respond: .json(200, #"{"success":true,"total":0,"notations":[]}"#))
        let page = try await gateway().recues(filtre: FiltreEvaluations(), page: 0, context: TestClient.context)
        XCTAssertEqual(page, PageEvaluations(total: 0, notations: [], stats: nil, evolution: [], etablissements: []))
        let params = try corps(lecture)
        XCTAssertEqual(Set(params.keys), ["p_periode", "p_limit", "p_offset"], "p_note_min et p_etablissement_id omis (DEFAULT NULL)")
        XCTAssertEqual(params["p_periode"] as? String, "TOUT")
        XCTAssertEqual(params["p_offset"] as? Int, 0)
    }

    func testNonAuthentifieSessionExpireeEtReponseIllisibleContrat() async {
        registry.add("POST", lecture, respond: .json(200, #"{"success":false,"error_code":"NON_AUTHENTIFIE"}"#))
        let session = await erreur { _ = try await self.gateway().recues(filtre: FiltreEvaluations(), page: 0, context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized, "NON_AUTHENTIFIE → session expirée")
        XCTAssertEqual(session?.message, SupabaseErrorMapping.unauthorizedMessage)

        for reponse in [#"{"success":true,"notations":[]}"#, #"{"rows":[]}"#, "[]", #"{"success":false}"#,
                        #"{"success":true,"total":1,"notations":[{"note_moyenne":5}]}"#] {
            registry.reset()
            registry.add("POST", lecture, respond: .json(200, reponse))
            let forme = await erreur { _ = try await self.gateway().recues(filtre: FiltreEvaluations(), page: 0, context: TestClient.context) }
            XCTAssertEqual(forme?.kind, .contract, "\(reponse) : jamais une page vide plausible")
            XCTAssertEqual(registry.requests.count, 1, "aucun renvoi")
        }

        registry.reset()
        registry.add("POST", lecture, respond: .json(404, #"{"code":"PGRST202","message":"Could not find the function","details":null,"hint":null}"#))
        let absente = await erreur { _ = try await self.gateway().recues(filtre: FiltreEvaluations(), page: 0, context: TestClient.context) }
        XCTAssertEqual(absente?.kind, .contract)
        XCTAssertEqual(registry.requests.count, 1, "PGRST202 : refus définitif, aucun renvoi")
    }

    func testProfilQuiNeCorrespondPasALaSessionAucuneRequete() async {
        var etranger = TestClient.context
        etranger.userId = "autre"
        let refus = await erreur { _ = try await self.gateway().recues(filtre: FiltreEvaluations(), page: 0, context: etranger) }
        XCTAssertEqual(refus?.kind, .unauthorized)
        XCTAssertTrue(registry.requests.isEmpty)
    }

    // MARK: - Signalement

    func testSignalementAccepte() async throws {
        registry.add("POST", signalement, respond: .json(200, #"{"success":true}"#))
        let issue = try await gateway().signaler(notationId: "7f0c8a0e-1111-4b1c-9e0a-7f3c1d2e5a66",
                                                 motif: "Évaluation sans rapport avec la mission.", context: TestClient.context)
        XCTAssertEqual(issue, .signale)
        let params = try corps(signalement)
        XCTAssertEqual(params["p_notation_id"] as? String, "7f0c8a0e-1111-4b1c-9e0a-7f3c1d2e5a66")
        XCTAssertEqual(params["p_motif"] as? String, "Évaluation sans rapport avec la mission.")
        XCTAssertEqual(Set(params.keys), ["p_notation_id", "p_motif"])
        XCTAssertEqual(registry.requests.count, 1, "la page est relue par le modèle, pas par la gateway")
    }

    func testSignalementDoubleEtAutresRefusVerbatim() async throws {
        for message in ["Notation déjà signalée", "Vous ne pouvez signaler que les notations vous concernant",
                        "Compte suspendu, supprimé ou désactivé"] {
            registry.reset()
            registry.add("POST", signalement, respond: .json(200, #"{"success":false,"error":"\#(message)"}"#))
            let issue = try await gateway().signaler(notationId: "n-1", motif: "Motif de dix caractères.", context: TestClient.context)
            XCTAssertEqual(issue, .refuse(message: message), "refus du serveur, mot pour mot")
            XCTAssertEqual(registry.requests.count, 1, "aucun renvoi")
        }
    }

    func testSignalementNonAuthentifieExceptionEtFormeInconnue() async throws {
        registry.add("POST", signalement, respond: .json(200, #"{"success":false,"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().signaler(notationId: "n-1", motif: "Motif de dix caractères.", context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)

        // Audit non écrit : la transaction est annulée, le message du serveur est rédigé pour l'utilisateur.
        registry.reset()
        let exception = "Le signalement n’a pas pu être enregistré. Veuillez réessayer."
        registry.add("POST", signalement, respond: .json(400, #"{"code":"P0001","message":"\#(exception)","details":null,"hint":null}"#))
        let issue = try await gateway().signaler(notationId: "n-1", motif: "Motif de dix caractères.", context: TestClient.context)
        XCTAssertEqual(issue, .refuse(message: exception), "exception P0001 restituée telle quelle, jamais « session expirée »")
        XCTAssertEqual(registry.requests.count, 1)

        registry.reset()
        registry.add("POST", signalement, respond: .json(200, #"{"statut":"ok"}"#))
        let forme = await erreur { _ = try await self.gateway().signaler(notationId: "n-1", motif: "Motif de dix caractères.", context: TestClient.context) }
        XCTAssertEqual(forme?.kind, .contract, "ni success ni error : jamais un signalement supposé")

        registry.reset()
        registry.add("POST", signalement, respond: .json(400, #"{"code":"P0001","message":"autre exception","details":null,"hint":null}"#))
        let inconnue = await erreur { _ = try await self.gateway().signaler(notationId: "n-1", motif: "Motif de dix caractères.", context: TestClient.context) }
        XCTAssertNotNil(inconnue, "exception P0001 au message inconnu : jamais restituée comme un refus métier")
        XCTAssertNotEqual(inconnue?.message, "autre exception")
    }
}
