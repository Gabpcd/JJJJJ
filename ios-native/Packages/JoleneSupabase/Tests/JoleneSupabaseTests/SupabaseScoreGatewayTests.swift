import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// « Mon score » sur Supabase (L4-T9) — fiches `fn_mon_breakdown_actuel`, `fn_evolution_score_soignant`,
/// `fn_mes_evenements_score`, `fn_lister_notations_recues` et `fn_creer_reclamation_score` de
/// `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` :
/// - événements sous la clé **`events`** ; une réponse `evenements` (celle que lit le web, correction 16) est un refus
///   de contrat, jamais « aucun événement » ;
/// - contestation : `p_evenement_type = 'SOIGNANT'`, quatre paramètres, **jamais** de chemin de justificatif (D10) ;
///   refus `TEXTE_REQUIS`, `NON_CONTESTABLE`, `DEJA_TRAITE`, `RECLAMATION_EN_COURS`… verbatim, avec leur code ;
/// - aucun défaut fabriqué pour le score ; notes lues par la seule RPC filtrée ; aucun renvoi.
final class SupabaseScoreGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let breakdown = "/rest/v1/rpc/fn_mon_breakdown_actuel"
    private let evolution = "/rest/v1/rpc/fn_evolution_score_soignant"
    private let evenements = "/rest/v1/rpc/fn_mes_evenements_score"
    private let notations = "/rest/v1/rpc/fn_lister_notations_recues"
    private let contester = "/rest/v1/rpc/fn_creer_reclamation_score"
    private let soignants = "/rest/v1/soignants"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseScoreGateway { SupabaseScoreGateway(client: TestClient.make()) }

    private static let evenementJSON = #"{"id":"7f0c8a0e-2222-4b1c-9e0a-7f3c1d2e5a66","type_evenement":"ANNULATION_12_24H","points":-5,"points_corriges":null,"motif":"Annulation tardive","contestable":true,"decision_admin":null,"cree_le":"2026-10-23T08:00:00+00:00","mission_id":"m-1"}"#
    private static let texte = "J'avais prévenu l'établissement la veille par téléphone."

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

    // MARK: - Détail du calcul

    func testBreakdownDuCalculCompleteDuProfilDeLaSession() async throws {
        registry.add("POST", breakdown, respond: .json(200, """
        {"id":"b-1","soignant_id":"\(TestClient.userId)","score_total":72.6,"niveau":"OR","en_periode_probatoire":false,
         "notation_etab_soignant_pct":88.8,"notation_etab_soignant_poids":38.9,"presentisme_pct":95,"presentisme_poids":22.2,
         "ponctualite_pct":72,"ponctualite_poids":16.7,"reactivite_pct":null,"reactivite_poids":null,
         "anciennete_volume_pct":40,"anciennete_volume_poids":11.1,"notation_soignant_etab_pct":50,"notation_soignant_etab_poids":11.1,
         "litiges_malus":0,"absence_sans_prevenir_malus":-5,"bonus_super_actif":0,
         "composantes_inactives_json":[{"composante":"reactivite","poids_initial":10}],"composantes_actives_count":5,
         "redistribution_json":{"facteur":1.111},"raison_recalcul":"MISSION_TERMINEE","cree_le":"2026-11-01T12:00:00+00:00"}
        """))
        registry.add("GET", soignants, respond: .json(200, #"{"total_missions_terminees":12,"score_fiabilite":72.6,"niveau":"OR","en_periode_probatoire":false}"#))
        let lu = try await gateway().breakdown(context: TestClient.context)
        XCTAssertTrue(lu.calcule)
        XCTAssertEqual(lu.score, 72.6)
        XCTAssertEqual(lu.niveau, "OR")
        XCTAssertEqual(lu.totalMissionsTerminees, 12)
        XCTAssertEqual(lu.composantes.count, 6)
        XCTAssertEqual(lu.composantes[3], ComposanteScore(cle: .reactivite, pct: nil, poids: nil, poidsInitial: 10))
        XCTAssertEqual(lu.absenceSansPrevenirMalus, -5)
        let ligne = try XCTUnwrap(registry.requests(to: soignants).first)
        XCTAssertEqual(ligne.query("select"), "total_missions_terminees,score_fiabilite,niveau,en_periode_probatoire",
                       "colonnes du web (PageScoreSoignant.tsx l.62)")
        XCTAssertEqual(ligne.query("id"), "eq.\(TestClient.userId)", "utilisateur de la session, jamais un autre")
        XCTAssertEqual(registry.requests(to: breakdown).count, 1)
        XCTAssertEqual(registry.requests.count, 2)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testBreakdownSansCalculAucunDefautFabrique() async throws {
        registry.add("POST", breakdown, respond: .json(200, "{}"))
        registry.add("GET", soignants, respond: .json(200, #"{"total_missions_terminees":1,"score_fiabilite":null,"niveau":null,"en_periode_probatoire":true}"#))
        let lu = try await gateway().breakdown(context: TestClient.context)
        XCTAssertEqual(lu, BreakdownScore(score: nil, niveau: nil, enPeriodeProbatoire: true, totalMissionsTerminees: 1),
                       "ni 50, ni Bronze (défauts du web l.75-76)")

        registry.reset()
        registry.add("POST", breakdown, respond: .json(200, #"{"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().breakdown(context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)
        XCTAssertTrue(registry.requests(to: soignants).isEmpty, "session expirée : aucune autre lecture")

        registry.reset()
        registry.add("POST", breakdown, respond: .json(200, "[]"))
        registry.add("GET", soignants, respond: .json(200, #"{"total_missions_terminees":1}"#))
        let forme = await erreur { _ = try await self.gateway().breakdown(context: TestClient.context) }
        XCTAssertEqual(forme?.kind, .contract)
    }

    // MARK: - Évolution et notations

    func testEvolutionSixMoisTableauOuObjetDErreur() async throws {
        registry.add("POST", evolution, respond: .json(200, #"[{"mois":"2026-10","score":77.6,"niveau":"OR","cree_le":"2026-10-01T12:00:00+00:00"},{"mois":"2026-11","score":72.6,"niveau":"OR","cree_le":"2026-11-01T12:00:00+00:00"}]"#))
        let points = try await gateway().evolution(mois: 6, context: TestClient.context)
        XCTAssertEqual(points, [PointEvolutionScore(mois: "2026-10", score: 77.6, niveau: "OR"),
                                PointEvolutionScore(mois: "2026-11", score: 72.6, niveau: "OR")])
        XCTAssertEqual(try corps(evolution)["p_limit"] as? Int, 6, "comme le web (GraphiqueEvolutionScore.tsx l.27)")

        registry.reset()
        registry.add("POST", evolution, respond: .json(200, #"{"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().evolution(mois: 6, context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized, "objet d'erreur au lieu d'un tableau")

        registry.reset()
        registry.add("POST", evolution, respond: .json(200, #"{"points":[]}"#))
        let forme = await erreur { _ = try await self.gateway().evolution(mois: 6, context: TestClient.context) }
        XCTAssertEqual(forme?.kind, .contract, "jamais « pas encore d'historique » sur une réponse illisible")
    }

    func testNotationsRecuesParLaSeuleRPCFiltree() async throws {
        registry.add("POST", notations, respond: .json(200, #"[{"id":"n-1","mission_id":"m-1","mission_intitule":"Renfort","mission_fin_le":"2026-09-21T00:00:00+00:00","critere_1":4,"critere_2":5,"critere_3":4,"critere_4":5,"note_moyenne":4.4,"commentaire":null,"cree_le":"2026-09-23T00:00:00+00:00"}]"#))
        let lues = try await gateway().notationsRecues(limite: 20, context: TestClient.context)
        XCTAssertEqual(lues.map(\.id), ["n-1"])
        XCTAssertEqual(lues.first?.noteMoyenne, 4.4, "note_moyenne du serveur, jamais (4+5+4+5)/4")
        XCTAssertNil(lues.first?.signale)
        XCTAssertEqual(try corps(notations)["p_limit"] as? Int, 20)
        XCTAssertEqual(registry.requests.count, 1, "aucune lecture de table")

        registry.reset()
        registry.add("POST", notations, respond: .json(200, #"{"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().notationsRecues(limite: 20, context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)

        registry.reset()
        registry.add("POST", notations, respond: .json(200, #"{"notations":[]}"#))
        let forme = await erreur { _ = try await self.gateway().notationsRecues(limite: 20, context: TestClient.context) }
        XCTAssertEqual(forme?.kind, .contract)
    }

    // MARK: - Événements

    func testEvenementsDecodesSousLaCleEvents() async throws {
        registry.add("POST", evenements, respond: .json(200, #"{"success":true,"type":"SOIGNANT","events":[\#(Self.evenementJSON)]}"#))
        let lus = try await gateway().evenements(limite: 20, context: TestClient.context)
        XCTAssertEqual(lus, [EvenementScore(id: "7f0c8a0e-2222-4b1c-9e0a-7f3c1d2e5a66", typeEvenement: "ANNULATION_12_24H", points: -5,
                                            motif: "Annulation tardive", contestable: true, creeLe: "2026-10-23T08:00:00+00:00",
                                            missionId: "m-1")])
        XCTAssertEqual(try corps(evenements)["p_limit"] as? Int, 20)
        XCTAssertEqual(registry.requests.count, 1)
    }

    func testReponseEvenementsRefuseeCommeContrat() async {
        // Correction 16 : le web lit `evenements` (ou un tableau nu) ; le serveur sert `events`. Aucune de ces formes
        // n'est lue comme « aucun événement ».
        for reponse in [#"{"success":true,"type":"SOIGNANT","evenements":[\#(Self.evenementJSON)]}"#, "[\(Self.evenementJSON)]",
                        #"{"success":true,"type":"ETAB","events":[]}"#, #"{"success":true,"events":[]}"#] {
            registry.reset()
            registry.add("POST", evenements, respond: .json(200, reponse))
            let forme = await erreur { _ = try await self.gateway().evenements(limite: 20, context: TestClient.context) }
            XCTAssertEqual(forme?.kind, .contract, reponse)
            XCTAssertEqual(registry.requests.count, 1, "aucun renvoi")
        }
    }

    func testEvenementsNonAuthentifieEtProfilNonIdentifie() async {
        registry.add("POST", evenements, respond: .json(200, #"{"success":false,"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().evenements(limite: 20, context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)

        registry.reset()
        registry.add("POST", evenements, respond: .json(200, #"{"success":false,"error":"Profil non identifié"}"#))
        let profil = await erreur { _ = try await self.gateway().evenements(limite: 20, context: TestClient.context) }
        XCTAssertEqual(profil?.kind, .unknown)
        XCTAssertEqual(profil?.message, "Profil non identifié", "message du serveur, verbatim")
    }

    // MARK: - Contestation

    func testContestationQuatreParametresJamaisDeJustificatif() async throws {
        registry.add("POST", contester, respond: .json(200, #"{"success":true,"reclamation_id":"7f0c8a0e-3333-4b1c-9e0a-7f3c1d2e5a66","statut":"PENDING"}"#))
        let issue = try await gateway().contester(evenementId: "7f0c8a0e-2222-4b1c-9e0a-7f3c1d2e5a66",
                                                  motif: MotifContestationScore.urgenceMedicale.rawValue, texte: Self.texte,
                                                  context: TestClient.context)
        XCTAssertEqual(issue, .enregistree(reclamationId: "7f0c8a0e-3333-4b1c-9e0a-7f3c1d2e5a66"))
        let params = try corps(contester)
        XCTAssertEqual(params["p_evenement_id"] as? String, "7f0c8a0e-2222-4b1c-9e0a-7f3c1d2e5a66")
        XCTAssertEqual(params["p_evenement_type"] as? String, "SOIGNANT")
        XCTAssertEqual(params["p_motif_categorie"] as? String, "URGENCE_MEDICALE")
        XCTAssertEqual(params["p_texte_libre"] as? String, Self.texte)
        XCTAssertEqual(Set(params.keys), ["p_evenement_id", "p_evenement_type", "p_motif_categorie", "p_texte_libre"],
                       "quatre paramètres : le chemin d'un justificatif n'est jamais envoyé (D10)")
        let brut = try XCTUnwrap(registry.requests(to: contester).first?.body.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertFalse(brut.contains("justificatif"), brut)
        XCTAssertEqual(registry.requests.count, 1, "les événements sont relus par le modèle, pas par la gateway")
    }

    func testRefusDeContestationVerbatimAvecLeurCode() async throws {
        let refus: [(String, String)] = [
            ("TEXTE_REQUIS", "Texte libre obligatoire (min 20 caractères)"),
            ("NON_CONTESTABLE", "Cet événement n'est pas contestable"),
            ("DEJA_TRAITE", "Cet événement a déjà été traité par un admin"),
            ("RECLAMATION_EN_COURS", "Une réclamation est déjà ouverte pour cet événement"),
            ("MOTIF_INVALIDE", "Motif catégorie invalide"),
            ("TYPE_INVALIDE", "evenement_type doit être SOIGNANT ou ETAB"),
            ("EVENT_INTROUVABLE", "Événement de score introuvable"),
            ("NON_AUTORISE", "Vous n'êtes pas concerné par cet événement"),
        ]
        for (code, message) in refus {
            registry.reset()
            let extra = code == "RECLAMATION_EN_COURS" ? #","reclamation_id":"r-1""# : ""
            registry.add("POST", contester, respond: .json(200, #"{"success":false,"error_code":"\#(code)","error":"\#(message)"\#(extra)}"#))
            let issue = try await gateway().contester(evenementId: "e-1", motif: "AUTRE", texte: Self.texte, context: TestClient.context)
            XCTAssertEqual(issue, .refusee(code: code, message: message), "refus du serveur, mot pour mot")
            XCTAssertEqual(registry.requests.count, 1, "aucun renvoi")
        }
    }

    func testContestationNonAuthentifieeEtSuccesSansIdentifiant() async {
        registry.add("POST", contester, respond: .json(200, #"{"success":false,"error_code":"NON_AUTHENTIFIE"}"#))
        let session = await erreur {
            _ = try await self.gateway().contester(evenementId: "e-1", motif: "AUTRE", texte: Self.texte, context: TestClient.context)
        }
        XCTAssertEqual(session?.kind, .unauthorized, "NON_AUTHENTIFIE → session expirée, jamais un refus métier")

        for reponse in [#"{"success":true,"statut":"PENDING"}"#, #"{"success":true,"reclamation_id":"","statut":"PENDING"}"#,
                        #"{"reclamation_id":"r-1"}"#, "[]"] {
            registry.reset()
            registry.add("POST", contester, respond: .json(200, reponse))
            let forme = await erreur {
                _ = try await self.gateway().contester(evenementId: "e-1", motif: "AUTRE", texte: Self.texte, context: TestClient.context)
            }
            XCTAssertEqual(forme?.kind, .contract, "\(reponse) : jamais une réclamation supposée")
            XCTAssertEqual(registry.requests.count, 1)
        }
    }
}
