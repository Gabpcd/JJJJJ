import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Candidature du lot 1 (T6a) sur `fn_confirmer_action_planning_v1` et `fn_repondre_proposition` : une forme de
/// réponse de la fiche `CONTRATS_RPC_SOIGNANT.md` = un test, dans l'ordre normatif du `LOT1_PLAN.md` §2.4.
/// Messages serveur repris de `supabase/schema/public.sql`, affirmés mot pour mot (HARD STOP n°4) ; un succès
/// n'est jamais annoncé sans relecture, et une relecture qui ne confirme pas est une erreur.
final class SupabaseCandidatureGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let missionId = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let candidatureId = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
    private let contratId = "9e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6b"
    private let rpc = "/rest/v1/rpc/fn_confirmer_action_planning_v1"
    private let repondre = "/rest/v1/rpc/fn_repondre_proposition"
    private let audit = "/rest/v1/rpc/fn_ecrire_audit_safe"
    private let creneaux = [CreneauConfirme(debut: "2026-12-01T19:00:00Z", fin: "2026-12-02T07:00:00Z")]

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseCandidatureGateway { SupabaseCandidatureGateway(client: TestClient.make()) }

    private func confirmer(_ action: ActionPlanning, message: String? = nil, choix: String? = nil,
                           candidature: String? = nil, creneaux: [CreneauConfirme]? = nil) async throws -> CandidatureOutcome {
        try await gateway().confirmer(action: action, missionId: missionId, creneaux: creneaux ?? self.creneaux, message: message,
                                      choixContrat: choix, candidatureId: candidature, context: TestClient.context)
    }

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

    private func reponse(_ json: String, statut: Int = 200) {
        registry.add("POST", rpc, respond: .json(statut, json))
    }

    private func exception(_ sqlstate: String, _ message: String) -> String {
        #"{"code":"\#(sqlstate)","details":null,"hint":null,"message":"\#(message)"}"#
    }

    private func candidatureJSON(_ statut: String, id: String? = nil, contrat: String? = nil) -> String {
        let choisi = contrat.map { #""\#($0)""# } ?? "null"
        return #"[{"id":"\#(id ?? candidatureId)","statut":"\#(statut)","message":null,"type_contrat_choisi":\#(choisi),"cree_le":"2026-11-02T00:00:00+00:00","mission_id":"\#(missionId)"}]"#
    }

    /// Lecture du contrat d'une proposition (`contratColumns`), distincte de la relecture de l'attribution.
    private func stubContratMission(_ contrat: String) {
        registry.add("GET", "/rest/v1/missions", where: { $0.query("select") == SupabaseCandidatureGateway.contratColumns },
                     respond: .json(200, #"[{"id":"\#(missionId)","type_contrat_recherche":"\#(contrat)"}]"#))
    }

    private func toutesLesRequetes() -> Int {
        [rpc, repondre, audit, "/rest/v1/candidatures", "/rest/v1/missions"].map { registry.requests(to: $0).count }.reduce(0, +)
    }

    private func attributionJSON(statut: String = "ASSIGNEE", soignant: String = TestClient.userId) -> String {
        #"[{"id":"\#(missionId)","statut":"\#(statut)","soignant_assigne_id":"\#(soignant)","intitule":"Remplacement IDE nuit","debut_le":"2026-12-01T19:00:00+00:00","fin_le":"2026-12-02T07:00:00+00:00","etablissement_id":"etab-1"}]"#
    }

    private func corps(_ path: String) throws -> [String: Any] {
        try XCTUnwrap(registry.requests(to: path).first?.bodyJSON as? [String: Any], "aucun corps \(path)")
    }

    // MARK: - Succès relus (formes 8 et 9)

    func testPostulerSuccesAvecDocumentsACompleterRelitLaCandidatureSansAudit() async throws {
        // Forme 8 (`public.sql` l.48519-48526) : `documents_requis_pour` accompagne le succès, sans `error` : jamais un refus.
        reponse(#"{"success":true,"candidature_id":"\#(candidatureId)","choix_contrat":"SALARIE","profession_requise":"IDE","docs_a_completer":true,"documents_requis_pour":"SALARIE"}"#)
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, candidatureJSON("EN_ATTENTE")))
        let issue = try await confirmer(.postuler, message: "")
        XCTAssertEqual(issue, .confirmed(candidatureId: candidatureId, contratId: nil))
        let envoye = try corps(rpc)
        XCTAssertEqual(envoye["p_mission_id"] as? String, missionId)
        XCTAssertEqual(envoye["p_action"] as? String, "POSTULER")
        XCTAssertTrue(envoye["p_message"] is NSNull, "message vide envoyé à null (`|| null` du web)")
        XCTAssertTrue(envoye["p_choix_contrat"] is NSNull)
        XCTAssertTrue(envoye["p_candidature_id"] is NSNull)
        let planning = try XCTUnwrap(envoye["p_creneaux_confirmes"] as? [[String: String]])
        XCTAssertEqual(planning, [["debut": "2026-12-01T19:00:00Z", "fin": "2026-12-02T07:00:00Z"]])
        let relecture = try XCTUnwrap(registry.requests(to: "/rest/v1/candidatures").first)
        XCTAssertEqual(relecture.query("select"), "id,statut,message,type_contrat_choisi,cree_le,mission_id")
        XCTAssertEqual(relecture.query("id"), "eq.\(candidatureId)")
        XCTAssertEqual(relecture.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertTrue(registry.requests(to: audit).isEmpty, "décision 5 : aucune ligne d'audit sur POSTULER")
        XCTAssertEqual(registry.requests(to: rpc).count, 1, "une seule requête, aucun renvoi")
    }

    func testPostulerRelectureQuiNeConfirmePasEstUneErreur() async throws {
        reponse(#"{"success":true,"candidature_id":"\#(candidatureId)"}"#)
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, "[]"))
        let vide = await erreur { _ = try await self.confirmer(.postuler) }
        XCTAssertEqual(vide, JoleneError(.contract, SupabaseCandidatureGateway.relectureMessage))
        registry.reset()
        reponse(#"{"success":true,"candidature_id":"\#(candidatureId)"}"#)
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, candidatureJSON("ANNULEE")))
        let annulee = await erreur { _ = try await self.confirmer(.postuler) }
        XCTAssertEqual(annulee, JoleneError(.contract, SupabaseCandidatureGateway.relectureMessage))
    }

    func testPostulerSansIdentifiantDeCandidatureRefuseDeContrat() async throws {
        reponse(#"{"success":true,"choix_contrat":"SALARIE"}"#)
        let refus = await erreur { _ = try await self.confirmer(.postuler) }
        XCTAssertEqual(refus?.kind, .contract)
        XCTAssertTrue(registry.requests(to: "/rest/v1/candidatures").isEmpty)
    }

    func testAccepterSuccesRelitLAttributionPuisAuditeCommeLeWeb() async throws {
        // Forme 9 (`public.sql` l.37344-37352).
        reponse(#"{"success":true,"contrat_id":"\#(contratId)","contrat_numero":"C-1","choix_applique":"SALARIE","profession_requise":"IDE","type_paiement":"SALAIRE","mode_paiement":"VIREMENT"}"#)
        registry.add("GET", "/rest/v1/missions", respond: .json(200, attributionJSON()))
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: .json(200, TestClient.etablissementJSON))
        registry.add("POST", audit, respond: .json(200, #"{"success":true,"id":"0a0a0a0a-1b1b-4c2c-8d3d-4e4e4e4e4e4e"}"#))
        let issue = try await confirmer(.accepter, choix: "SALARIE")
        XCTAssertEqual(issue, .confirmed(candidatureId: nil, contratId: contratId))
        XCTAssertTrue(registry.requests(to: "/rest/v1/candidatures").isEmpty, "ACCEPTER : aucun verrou de proposition")
        XCTAssertEqual(try corps(rpc)["p_choix_contrat"] as? String, "SALARIE")
        let relecture = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(relecture.query("select"), SupabaseCandidatureGateway.attributionColumns)
        XCTAssertEqual(relecture.query("id"), "eq.\(missionId)")
        let ecrit = try corps(audit)
        XCTAssertEqual(ecrit["p_action"] as? String, "MISSION_ASSIGNATION")
        XCTAssertEqual(ecrit["p_type_ressource"] as? String, "mission")
        XCTAssertEqual(ecrit["p_id_ressource"] as? String, missionId)
        XCTAssertEqual(ecrit["p_details"] as? [String: String], ["intitule": "Remplacement IDE nuit", "etablissement": "Clinique des Tests",
                                                                 "debut": "2026-12-01T19:00:00+00:00", "fin": "2026-12-02T07:00:00+00:00"])
    }

    func testAuditEnEchecNInvalideJamaisLAttributionRelue() async throws {
        reponse(#"{"success":true,"contrat_id":"\#(contratId)"}"#)
        registry.add("GET", "/rest/v1/missions", respond: .json(200, attributionJSON()))
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: .networkFailure())
        registry.add("POST", audit, respond: .json(500, exception("XX000", "panne")))
        let issue = try await confirmer(.accepter)
        XCTAssertEqual(issue, .confirmed(candidatureId: nil, contratId: contratId))
        XCTAssertEqual(registry.requests(to: audit).count, 1, "audit tenté une fois, jamais renvoyé")
        XCTAssertNil(try corps(audit)["p_details"].flatMap { ($0 as? [String: String])?["etablissement"] },
                     "établissement illisible : détail omis, rien d'inventé")
    }

    func testAccepterRelectureAttribueeAUnAutreEstUneErreurSansAudit() async throws {
        reponse(#"{"success":true,"contrat_id":"\#(contratId)"}"#)
        registry.add("GET", "/rest/v1/missions", respond: .json(200, attributionJSON(soignant: "00000000-1111-4222-8333-444444444444")))
        let refus = await erreur { _ = try await self.confirmer(.accepter) }
        XCTAssertEqual(refus, JoleneError(.contract, SupabaseCandidatureGateway.relectureMessage))
        XCTAssertTrue(registry.requests(to: audit).isEmpty)
        registry.reset()
        reponse(#"{"success":true,"contrat_id":"\#(contratId)"}"#)
        registry.add("GET", "/rest/v1/missions", respond: .json(200, attributionJSON(statut: "OUVERTE")))
        let ouverte = await erreur { _ = try await self.confirmer(.accepter) }
        XCTAssertEqual(ouverte, JoleneError(.contract, SupabaseCandidatureGateway.relectureMessage))
    }

    func testPropositionLiberaleContratReluPuisEnvoyeeEtRelue() async throws {
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, candidatureJSON("PROPOSEE", contrat: "LIBERAL")))
        stubContratMission("TOUS")
        reponse(#"{"success":true,"contrat_id":"\#(contratId)","message":"Proposition acceptée"}"#)
        registry.add("GET", "/rest/v1/missions", where: { $0.query("select") == SupabaseCandidatureGateway.attributionColumns },
                     respond: .json(200, attributionJSON()))
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: .json(200, TestClient.etablissementJSON))
        registry.add("POST", audit, respond: .json(200, #"{"success":true}"#))
        let issue = try await confirmer(.proposition, choix: "LIBERAL", candidature: candidatureId.uppercased())
        XCTAssertEqual(issue, .confirmed(candidatureId: candidatureId, contratId: contratId))
        let envoye = try corps(rpc)
        XCTAssertEqual(envoye["p_action"] as? String, "PROPOSITION")
        XCTAssertEqual(envoye["p_candidature_id"] as? String, candidatureId, "uuid canonique")
        XCTAssertTrue(envoye["p_choix_contrat"] is NSNull, "null comme le web : le contrat déclaré ne sert qu'au verrou")
        let lecture = try XCTUnwrap(registry.requests(to: "/rest/v1/candidatures").first)
        XCTAssertEqual(lecture.query("id"), "eq.\(candidatureId)")
        XCTAssertEqual(lecture.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(registry.requests(to: audit).count, 1, "décision 5 : audit sur PROPOSITION aussi")
    }

    // MARK: - Verrou de l'attestation hebdomadaire (revue B8 de T6a, M1)

    func testPropositionNonLiberaleVerrouilleeSansAucuneRequete() async throws {
        for declare in [nil, "SALARIE", "TOUS", ""] as [String?] {
            registry.reset()
            do {
                _ = try await confirmer(.proposition, choix: declare, candidature: candidatureId)
                XCTFail("proposition \(declare ?? "nil") envoyée sans l'attestation hebdomadaire")
            } catch let verrou as CandidatureVerrou {
                XCTAssertEqual(verrou, .renvoiWeb(chemin: CandidatureVerrou.cheminProposition))
            }
            XCTAssertEqual(toutesLesRequetes(), 0, "\(declare ?? "nil") : aucune requête, ni lecture ni RPC")
        }
    }

    func testPropositionDeclareeLiberaleMaisReluesSalarieeVerrouilleeSansRPC() async throws {
        for (choisi, recherche) in [(nil, "SALARIE"), ("SALARIE", "TOUS"), (nil, "TOUS")] as [(String?, String)] {
            registry.reset()
            registry.add("GET", "/rest/v1/candidatures", respond: .json(200, candidatureJSON("PROPOSEE", contrat: choisi)))
            stubContratMission(recherche)
            do {
                _ = try await confirmer(.proposition, choix: "LIBERAL", candidature: candidatureId)
                XCTFail("contrat relu \(choisi ?? recherche) : jamais envoyé")
            } catch let verrou as CandidatureVerrou {
                XCTAssertEqual(verrou, .renvoiWeb(chemin: CandidatureVerrou.cheminProposition))
            }
            XCTAssertTrue(registry.requests(to: rpc).isEmpty, "aucune RPC")
            XCTAssertTrue(registry.requests(to: audit).isEmpty)
        }
    }

    // MARK: - Garde locale (aucune requête)

    func testGardeLocalePlanningVidePropositionSansCandidatureIdentifiantInvalide() async throws {
        let vide = await erreur { _ = try await self.confirmer(.postuler, creneaux: []) }
        XCTAssertEqual(vide, JoleneError(.contract, SupabaseCandidatureGateway.planningRequisMessage))
        let sansCandidature = await erreur { _ = try await self.confirmer(.proposition) }
        XCTAssertEqual(sansCandidature, JoleneError(.contract, SupabaseCandidatureGateway.identifiantInvalideMessage))
        let invalide = await erreur {
            _ = try await self.gateway().confirmer(action: .accepter, missionId: "m-1", creneaux: self.creneaux, message: nil,
                                                   choixContrat: nil, candidatureId: nil, context: TestClient.context)
        }
        XCTAssertEqual(invalide, JoleneError(.contract, SupabaseCandidatureGateway.identifiantInvalideMessage))
        XCTAssertTrue(registry.requests(to: rpc).isEmpty, "aucune requête")
    }

    // MARK: - Réponses des délégués sans clé `success` (formes 10 à 12)

    func testChoixRequisSansSuccessDemandeLeChoix() async throws {
        reponse(#"{"choix_requis":true,"error":"Choisissez votre mode de contrat.","options":[{"value":"SALARIE","label":"Salarié (CDD / bulletin de paie)"},{"value":"LIBERAL","label":"Libéral (note d'honoraires)"}]}"#)
        let issue = try await confirmer(.postuler)
        XCTAssertEqual(issue, .choixRequis([ChoixContratOption(value: "SALARIE", label: "Salarié (CDD / bulletin de paie)"),
                                            ChoixContratOption(value: "LIBERAL", label: "Libéral (note d'honoraires)")]))
        XCTAssertTrue(registry.requests(to: "/rest/v1/candidatures").isEmpty, "aucune relecture d'un refus")
    }

    func testDocumentsRequisRefusVerbatimAvecLeRegime() async throws {
        let message = "Les documents requis pour candidater en libéral sont manquants ou expirés."
        reponse(#"{"error":"\#(message)","documents_requis_pour":"LIBERAL","lien_documents":"/soignant/mes-documents"}"#)
        let issue1 = try await confirmer(.postuler)
        XCTAssertEqual(issue1, .refusee(code: nil, message: message, documentsRequisPour: "LIBERAL"))
        registry.reset()
        let salarie = "Les documents requis pour une mission salarie ne sont pas encore validés."
        reponse(#"{"error":"\#(salarie)","documents_requis_pour":"SALARIE","lien_documents":"/soignant/mes-documents"}"#)
        let issue2 = try await confirmer(.accepter)
        XCTAssertEqual(issue2, .refusee(code: nil, message: salarie, documentsRequisPour: "SALARIE"))
    }

    func testPlafondHebdomadaireEtPlanningIncompletRefusVerbatimAvecCode() async throws {
        let plafond = "Dépassement du plafond de 48 h pour la semaine du 30/11/2026 (40.0 h déjà planifiées + 12.0 h pour cette mission + 0.0 h ailleurs)."
        reponse(#"{"error":"\#(plafond)","code":"PLAFOND_48H_HEBDO","semaine_du":"2026-11-30","heures_existantes":40,"heures_mission":12,"heures_externes":0,"total":52}"#)
        let issue3 = try await confirmer(.accepter)
        XCTAssertEqual(issue3, .refusee(code: "PLAFOND_48H_HEBDO", message: plafond, documentsRequisPour: nil))
        registry.reset()
        let incomplet = "Planning hebdomadaire incomplet : impossible de vérifier le plafond de 48 h."
        reponse(#"{"error":"\#(incomplet)","code":"PLANNING_HEBDOMADAIRE_INDISPONIBLE","creneaux_valides":1,"creneaux_attendus":2}"#)
        let incompletIssue = try await confirmer(.accepter)
        XCTAssertEqual(incompletIssue, .refusee(code: "PLANNING_HEBDOMADAIRE_INDISPONIBLE", message: incomplet, documentsRequisPour: nil))
    }

    // MARK: - Refus propres à la RPC (formes 1 à 7)

    func testPlanningAReconfirmerLesDeuxCodes() async throws {
        let formes = [
            ("PLANNING_A_RECONFIRMER", "Le planning confirmé n'est pas exploitable. Rechargez la mission avant de continuer."),
            ("PLANNING_MODIFIE_RECONFIRMER", "Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires."),
        ]
        for (code, message) in formes {
            registry.reset()
            reponse(#"{"success":false,"ok":false,"code":"\#(code)","error":"\#(message)"}"#)
            let issue4 = try await confirmer(.accepter)
            XCTAssertEqual(issue4, .planningAReconfirmer(code: code, message: message), code)
            XCTAssertEqual(registry.requests(to: rpc).count, 1, "\(code) : jamais renvoyée telle quelle")
        }
    }

    func testConflitsDePlanningRefusVerbatim() async throws {
        let formes = [
            // `fn_conflit_planning_soignant` : textes du serveur (tutoiement compris), jamais reformulés.
            ("CONFLIT_PLANNING", "Ce planning entre en conflit avec une mission déjà confirmée."),
            ("REPOS_11H", "Repos insuffisant avec « Nuit Urgences » : 8.5 h au lieu de 11 h minimum."),
            ("PLANNING_DETAILLE_INDISPONIBLE", "Le planning détaillé de cette mission doit être confirmé avant toute candidature."),
            ("PLANNING_EXISTANT_INDISPONIBLE", "Le planning détaillé d'une mission déjà confirmée doit être vérifié avant cette candidature."),
        ]
        for (code, message) in formes {
            registry.reset()
            reponse(#"{"success":false,"ok":false,"code":"\#(code)","error":"\#(message)"}"#)
            let issue5 = try await confirmer(.postuler)
            XCTAssertEqual(issue5, .refusee(code: code, message: message, documentsRequisPour: nil), code)
        }
    }

    func testRefusSansCodeDeLaRPCVerbatim() async throws {
        // §2.4 règle 5 (aligné sur le code, revue B8 m2) : refus drapeauté sans code → `.refusee(code: nil)`, verbatim.
        for message in ["Accès réservé aux soignants authentifiés.", "Action de candidature invalide.", "Proposition introuvable."] {
            registry.reset()
            reponse(#"{"success":false,"ok":false,"error":"\#(message)"}"#)
            let issue6 = try await confirmer(.postuler)
            XCTAssertEqual(issue6, .refusee(code: nil, message: message, documentsRequisPour: nil), message)
        }
    }

    // MARK: - `{error}` seul (forme 13) et réponse inattendue

    func testErreurSeuleEnHTTP200LeveLeMessageServeur() async throws {
        for message in ["Trop de candidatures en peu de temps. Réessayez plus tard.", "Vous avez déjà postulé à cette mission",
                        "Cette proposition a expiré"] {
            registry.reset()
            reponse(#"{"error":"\#(message)"}"#)
            let refus = await erreur { _ = try await self.confirmer(.postuler) }
            XCTAssertEqual(refus, JoleneError(.unknown, message), message)
        }
        registry.reset()
        reponse(#"{"error":"Non authentifié"}"#)
        let session = await erreur { _ = try await self.confirmer(.accepter) }
        XCTAssertEqual(session?.kind, .unauthorized)
    }

    func testReponseSansCleConnueEstUnRefusDeContrat() async throws {
        reponse("{}")
        let refus = await erreur { _ = try await self.confirmer(.accepter) }
        XCTAssertEqual(refus?.kind, .contract)
    }

    // MARK: - Exceptions PostgREST (forme 14)

    func testCodeDuTravailRestitueMotPourMotSansRelecture() async throws {
        // HARD STOP n°4 : texte légal du trigger affiché à l'identique, préfixe compris.
        let message = "[CODE DU TRAVAIL] Semaine du 30/11/2026 : 40.0h Jolene + 10.0h ailleurs = 50.0h total (max 48h, Art. L3121-20)"
        reponse(exception("P0001", message), statut: 400)
        let issue = try await confirmer(.accepter)
        XCTAssertEqual(issue, .refusee(code: CandidatureOutcome.codeRefusCodeDuTravail, message: message, documentsRequisPour: nil))
        XCTAssertTrue(registry.requests(to: "/rest/v1/missions").isEmpty)
        XCTAssertTrue(registry.requests(to: audit).isEmpty)
    }

    func testMissionSortieDeLEtatOuverteSurLesMessagesExacts() async throws {
        // Revue B8 de T6a, m1 : la vraie course (forme 3 sous verrou `FOR UPDATE`, délégués, attribution concurrente).
        let formes = [
            #"{"success":false,"ok":false,"error":"Cette mission n'est plus disponible."}"#,
            #"{"error":"Cette mission n'est plus disponible"}"#,
            #"{"error":"Cette mission vient d'être attribuée."}"#,
        ]
        let messages = ["Cette mission n'est plus disponible.", "Cette mission n'est plus disponible",
                        "Cette mission vient d'être attribuée."]
        for (forme, message) in zip(formes, messages) {
            registry.reset()
            reponse(forme)
            let issue7 = try await confirmer(.accepter)
            XCTAssertEqual(issue7, .missionDejaAttribuee(message: message), forme)
            XCTAssertEqual(registry.requests(to: rpc).count, 1, "aucun renvoi")
            XCTAssertTrue(registry.requests(to: "/rest/v1/missions").isEmpty, "aucune relecture de succès")
        }
    }

    func testAncienneBrancheZeroRowsNeReconnaitPlusRien() async throws {
        reponse(exception("PGRST116", "The result contains 10 rows"), statut: 406)
        let refus = await erreur { _ = try await self.confirmer(.accepter) }
        XCTAssertNotNil(refus, "exception → erreur générique, jamais `.missionDejaAttribuee`")
        XCTAssertFalse(refus?.message.contains("rows") == true, "jamais le message technique")
    }

    func testErreurDeTransportPendantLaRelectureDitQueLaReponseEstPartie() async throws {
        // Revue B8 de T6a, m3 : nature gardée (réseau), message de relecture, jamais « connexion impossible » seul.
        reponse(#"{"success":true,"candidature_id":"\#(candidatureId)"}"#)
        registry.add("GET", "/rest/v1/candidatures", respond: .networkFailure())
        let postuler = await erreur { _ = try await self.confirmer(.postuler) }
        XCTAssertEqual(postuler, JoleneError(.network, SupabaseCandidatureGateway.relectureMessage))
        registry.reset()
        reponse(#"{"success":true,"contrat_id":"\#(contratId)"}"#)
        registry.add("GET", "/rest/v1/missions", respond: .networkFailure())
        let accepter = await erreur { _ = try await self.confirmer(.accepter) }
        XCTAssertEqual(accepter, JoleneError(.network, SupabaseCandidatureGateway.relectureMessage))
        XCTAssertTrue(registry.requests(to: audit).isEmpty, "aucun audit sans relecture")
        XCTAssertEqual(registry.requests(to: rpc).count, 1, "aucun renvoi")
    }

    func testAutreExceptionMessageGenerique() async throws {
        reponse(exception("XX000", "relation interne introuvable"), statut: 500)
        let refus = await erreur { _ = try await self.confirmer(.accepter) }
        XCTAssertNotNil(refus)
        XCTAssertFalse(refus?.message.contains("relation interne") == true, "jamais le message technique")
    }

    // MARK: - Refus d'une proposition

    func testRefuserPropositionRelitREFUSEE() async throws {
        registry.add("POST", repondre, respond: .json(200, #"{"success":true,"message":"Proposition refusée"}"#))
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, candidatureJSON("REFUSEE")))
        try await gateway().refuserProposition(candidatureId: candidatureId, context: TestClient.context)
        let envoye = try corps(repondre)
        XCTAssertEqual(envoye["p_candidature_id"] as? String, candidatureId)
        XCTAssertEqual(envoye["p_accepter"] as? Bool, false)
        XCTAssertTrue(registry.requests(to: rpc).isEmpty, "le refus ne passe pas par la RPC de planning")
    }

    func testRefuserPropositionExpireeOuNonRelueEstUneErreur() async throws {
        registry.add("POST", repondre, respond: .json(200, #"{"error":"Cette proposition a expiré"}"#))
        let expiree = await erreur { try await self.gateway().refuserProposition(candidatureId: self.candidatureId, context: TestClient.context) }
        XCTAssertEqual(expiree, JoleneError(.unknown, "Cette proposition a expiré"))
        registry.reset()
        registry.add("POST", repondre, respond: .json(200, #"{"success":true,"message":"Proposition refusée"}"#))
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, candidatureJSON("PROPOSEE")))
        let nonRelue = await erreur { try await self.gateway().refuserProposition(candidatureId: self.candidatureId, context: TestClient.context) }
        XCTAssertEqual(nonRelue, JoleneError(.contract, SupabaseCandidatureGateway.relectureMessage))
    }

    // MARK: - Lecture de la candidature d'une mission

    func testCandidatureDeLaMissionRelueSousLaSession() async throws {
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, candidatureJSON("PROPOSEE")))
        let lue = try await gateway().candidature(missionId: missionId, context: TestClient.context)
        XCTAssertEqual(lue?.id, candidatureId)
        XCTAssertEqual(lue?.statut, "PROPOSEE")
        let requete = try XCTUnwrap(registry.requests(to: "/rest/v1/candidatures").first)
        XCTAssertEqual(requete.query("mission_id"), "eq.\(missionId)")
        XCTAssertEqual(requete.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(requete.query("order"), "cree_le.desc.nullsfirst", "`order(cree_le, desc)` : NULLS FIRST de PostgreSQL")
        XCTAssertEqual(requete.query("limit"), "1")
        registry.reset()
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, "[]"))
        let aucune = try await gateway().candidature(missionId: missionId, context: TestClient.context)
        XCTAssertNil(aucune)
    }

    // MARK: - Annulations (T7) : une forme de réponse de la fiche = un test

    private let annulerCandidature = "/rest/v1/rpc/fn_annuler_candidature_soignant"
    private let annulerMission = "/rest/v1/rpc/fn_annuler_mission_soignant"
    private let explication = "Train supprimé ce matin, aucun autre trajet possible."
    private var cheminJustificatif: String {
        "\(TestClient.userId)/annulations-candidature/\(candidatureId)/1793577600000_billet.pdf"
    }

    private func annuler(chemin: String? = nil) async throws -> AnnulationOutcome {
        try await gateway().annulerCandidature(id: candidatureId, motif: "PROBLEME_TRANSPORT", texte: explication,
                                               justificatifPath: chemin, context: TestClient.context)
    }

    func testCandidatureEnAttenteRetireeSansImpactRelue() async throws {
        registry.add("POST", annulerCandidature, respond: .json(200, #"{"success":true,"libre":true,"points":0,"message":"Candidature retirée sans impact"}"#))
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, candidatureJSON("ANNULEE")))
        let issue = try await annuler()
        XCTAssertEqual(issue, .annulee(points: 0, libre: true, contestable: nil))
        let envoye = try corps(annulerCandidature)
        XCTAssertEqual(envoye["p_candidature_id"] as? String, candidatureId)
        XCTAssertEqual(envoye["p_motif_categorie"] as? String, "PROBLEME_TRANSPORT")
        XCTAssertEqual(envoye["p_texte_libre"] as? String, explication)
        XCTAssertTrue(envoye["p_justificatif_storage_path"] is NSNull, "aucun justificatif : null")
        let relecture = try XCTUnwrap(registry.requests(to: "/rest/v1/candidatures").first)
        XCTAssertEqual(relecture.query("id"), "eq.\(candidatureId)")
        XCTAssertEqual(relecture.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(registry.requests(to: annulerCandidature).count, 1, "une seule requête")
    }

    func testCandidatureAccepteePenaliteServeurEtJustificatifTransmis() async throws {
        registry.add("POST", annulerCandidature, respond: .json(200, #"{"success":true,"libre":false,"points":-5,"motif_score":"ANNULATION_12_24H","event_score_id":"0a0a0a0a-1b1b-4c2c-8d3d-4e4e4e4e4e4e","contestable":true,"signalement_admin":false}"#))
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, candidatureJSON("ANNULEE")))
        let issue = try await annuler(chemin: cheminJustificatif)
        XCTAssertEqual(issue, .annulee(points: -5, libre: false, contestable: true), "valeurs serveur, aucun barème client")
        XCTAssertEqual(try corps(annulerCandidature)["p_justificatif_storage_path"] as? String, cheminJustificatif)
        XCTAssertEqual(TextesWeb.Annulation.succesCandidature(points: -5), "Candidature annulée. Score impacté : -5 pts.")
    }

    func testRefusStructuresVerbatim() async throws {
        let refus: [(String, String)] = [
            ("STATUT_INVALIDE", "Candidature pas dans un état annulable (statut : ANNULEE)"),
            ("TEXTE_REQUIS", "Texte libre obligatoire (min 10 caractères)"),
            ("MOTIF_INVALIDE", "Motif requis (URGENCE_PERSONNELLE, URGENCE_MEDICALE, DEUIL, PROBLEME_TRANSPORT, CHANGEMENT_AVIS, AUTRE)"),
            ("CANDIDATURE_INTROUVABLE", "Candidature introuvable"),
            ("NON_AUTORISE", "Vous n'êtes pas le soignant de cette candidature"),
            ("MISSION_INTROUVABLE", "Mission introuvable"),
        ]
        for (code, message) in refus {
            registry.reset()
            registry.add("POST", annulerCandidature, respond: .json(200, #"{"success":false,"error_code":"\#(code)","error":"\#(message)"}"#))
            let issue = try await annuler()
            XCTAssertEqual(issue, .refusee(code: code, message: message), code)
            XCTAssertTrue(registry.requests(to: "/rest/v1/candidatures").isEmpty, "\(code) : aucune relecture d'un refus")
        }
    }

    func testNonAuthentifieSessionExpiree() async throws {
        registry.add("POST", annulerCandidature, respond: .json(200, #"{"success":false,"error_code":"NON_AUTHENTIFIE","error":"Non authentifié"}"#))
        let refus = await erreur { _ = try await self.annuler() }
        XCTAssertEqual(refus?.kind, .unauthorized)
    }

    func testSuccesSansRelectureAnnuleeEstUneErreur() async throws {
        registry.add("POST", annulerCandidature, respond: .json(200, #"{"success":true,"libre":true,"points":0}"#))
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, candidatureJSON("ACCEPTEE")))
        let refus = await erreur { _ = try await self.annuler() }
        XCTAssertEqual(refus, JoleneError(.contract, SupabaseCandidatureGateway.relectureAnnulationMessage))
        registry.reset()
        registry.add("POST", annulerCandidature, respond: .json(200, "{}"))
        let vide = await erreur { _ = try await self.annuler() }
        XCTAssertEqual(vide?.kind, .contract, "réponse inattendue : jamais un succès")
    }

    func testCheminDeJustificatifEtrangerRefuseSansAppel() async throws {
        let refus = await erreur {
            _ = try await self.annuler(chemin: "autre/annulations-candidature/\(self.candidatureId)/1_a.pdf")
        }
        XCTAssertEqual(refus?.kind, .contract)
        XCTAssertTrue(registry.requests.isEmpty)
    }

    func testMissionSansCandidatureRelueAuditeeCommeLeWeb() async throws {
        registry.add("POST", annulerMission, respond: .json(200, #"{"success":true,"annulation_tardive":true,"penalite_score":-8}"#))
        registry.add("GET", "/rest/v1/missions", respond: .json(200, attributionJSON(statut: "OUVERTE", soignant: "")
            .replacingOccurrences(of: #""soignant_assigne_id":"""#, with: #""soignant_assigne_id":null"#)))
        registry.add("POST", audit, respond: .json(200, #"{"success":true,"id":"0a0a0a0a-1b1b-4c2c-8d3d-4e4e4e4e4e4e"}"#))
        let issue = try await gateway().annulerMission(id: missionId, motif: nil, context: TestClient.context)
        XCTAssertEqual(issue, .annulee(points: -8, libre: nil, contestable: nil))
        let envoye = try corps(annulerMission)
        XCTAssertEqual(envoye["p_mission_id"] as? String, missionId)
        XCTAssertNil(envoye["p_motif"], "aucun motif, comme le web (l.892)")
        let ecrit = try corps(audit)
        XCTAssertEqual(ecrit["p_action"] as? String, "MISSION_ANNULATION")
        XCTAssertEqual(ecrit["p_type_ressource"] as? String, "mission")
        XCTAssertEqual(ecrit["p_id_ressource"] as? String, missionId)
        XCTAssertEqual(ecrit["p_details"] as? [String: String], ["motif": "Annulation volontaire par le soignant"])
    }

    func testMissionRefusErrorSeulVerbatimSansAudit() async throws {
        for message in ["Mission introuvable", "Cette mission ne vous est pas assignée",
                        "Annulation impossible dans cet état. Si la mission est en cours, ouvrez un litige."] {
            registry.reset()
            registry.add("POST", annulerMission, respond: .json(200, #"{"error":"\#(message)"}"#))
            let issue = try await gateway().annulerMission(id: missionId, motif: nil, context: TestClient.context)
            XCTAssertEqual(issue, .refusee(code: nil, message: message))
            XCTAssertTrue(registry.requests(to: audit).isEmpty)
            XCTAssertTrue(registry.requests(to: "/rest/v1/missions").isEmpty)
        }
    }

    func testMissionEncoreAttribueeApresSuccesEstUneErreurSansAudit() async throws {
        registry.add("POST", annulerMission, respond: .json(200, #"{"success":true,"annulation_tardive":false,"penalite_score":0}"#))
        registry.add("GET", "/rest/v1/missions", respond: .json(200, attributionJSON()))
        let refus = await erreur { _ = try await self.gateway().annulerMission(id: self.missionId, motif: nil, context: TestClient.context) }
        XCTAssertEqual(refus, JoleneError(.contract, SupabaseCandidatureGateway.relectureAnnulationMessage))
        XCTAssertTrue(registry.requests(to: audit).isEmpty)
    }

    func testMissionAuditEnEchecSansEffetSurLeSucces() async throws {
        registry.add("POST", annulerMission, respond: .json(200, #"{"success":true,"annulation_tardive":false,"penalite_score":0}"#))
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[]"))
        registry.add("POST", audit, respond: .json(200, #"{"success":false,"error":"Non authentifié"}"#))
        let issue = try await gateway().annulerMission(id: missionId, motif: nil, context: TestClient.context)
        XCTAssertEqual(issue, .annulee(points: 0, libre: nil, contestable: nil), "ligne invisible : plus attribuée au soignant")
    }
}
