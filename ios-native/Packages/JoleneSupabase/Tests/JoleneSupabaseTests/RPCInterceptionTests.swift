import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Interceptions des exceptions PostgREST avant `SupabaseErrorMapping` (lot 5 T1, §2.5, D12) : 42501
/// de droit en liste blanche → refus structuré (jamais « session expirée »), refus métier verbatim,
/// 28000 → session, tout le reste inchangé (lot 0), `[CODE DU TRAVAIL]` toujours intercepté (lot 1).
final class RPCInterceptionTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let fallback = "Impossible de traiter votre demande. Réessayez."

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    /// Nom de RPC fictif (garde `check-rpc-contracts.node.mjs` : aucun littéral `fn_` non suivi).
    private let chemin = "/rest/v1/rpc/rpc_fictive_etab"

    private func exception(_ status: Int, sqlstate: String?, message: String, details: String? = nil,
                           hint: String? = nil) -> StubResponse {
        let code = sqlstate.map { #""\#($0)""# } ?? "null"
        let detail = details.map { #""\#($0)""# } ?? "null"
        let indice = hint.map { #""\#($0)""# } ?? "null"
        return .json(status, #"{"code":\#(code),"details":\#(detail),"hint":\#(indice),"message":"\#(message)"}"#)
    }

    private func appeler(_ reponse: StubResponse, interceptions: [RPCInterception]? = nil) async throws -> RPCResponse {
        registry.reset()
        registry.add("POST", chemin, respond: reponse)
        defer {
            XCTAssertEqual(registry.requests(to: chemin).count, 1, "une seule requête, aucun renvoi")
            XCTAssertTrue(registry.unmatched.isEmpty)
        }
        if let interceptions {
            return try await RPCResponse.appeler(TestClient.make(), "rpc_fictive_etab", params: ["p_id": .string("x")],
                                                 fallback: fallback, interceptions: interceptions)
        }
        return try await RPCResponse.appeler(TestClient.make(), "rpc_fictive_etab", params: ["p_id": .string("x")], fallback: fallback)
    }

    private func erreur(_ reponse: StubResponse, interceptions: [RPCInterception]? = nil,
                        file: StaticString = #filePath, line: UInt = #line) async -> JoleneError? {
        do {
            _ = try await appeler(reponse, interceptions: interceptions)
            XCTFail("attendu : erreur levée", file: file, line: line)
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: - Correspondance des modèles

    func testCorrespondanceExacteEtJokersNonVides() {
        XCTAssertTrue(RPCInterception.correspond(modele: "Mission indisponible ou accès refusé", message: "Mission indisponible ou accès refusé"))
        XCTAssertFalse(RPCInterception.correspond(modele: "Mission indisponible ou accès refusé", message: "Mission indisponible ou accès refusé."))
        XCTAssertFalse(RPCInterception.correspond(modele: "Mission indisponible ou accès refusé", message: "mission indisponible ou accès refusé"),
                       "sensible à la casse")
        XCTAssertFalse(RPCInterception.correspond(modele: "Lecture du pointage non autorisée.", message: " Lecture du pointage non autorisée."),
                       "aucun espace ignoré")
        let mission = "Mission % introuvable ou dans un statut incompatible."
        XCTAssertTrue(RPCInterception.correspond(modele: mission, message: "Mission 6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b introuvable ou dans un statut incompatible."))
        XCTAssertFalse(RPCInterception.correspond(modele: mission, message: "Mission introuvable ou dans un statut incompatible."),
                       "un joker ne correspond jamais à un texte vide")
        let heures = "L'heure de fin (%) doit être postérieure au début du créneau (%)."
        XCTAssertTrue(RPCInterception.correspond(modele: heures,
                                                 message: "L'heure de fin (2026-11-02 10:00:00+01) doit être postérieure au début du créneau (2026-11-02 11:00:00+01)."))
        XCTAssertFalse(RPCInterception.correspond(modele: heures, message: "L'heure de fin () doit être postérieure au début du créneau (x)."))
        XCTAssertFalse(RPCInterception.correspond(modele: heures, message: "L'heure de fin (x) doit être postérieure au début du créneau ()."))
        XCTAssertFalse(RPCInterception.correspond(modele: heures, message: "L'heure de fin (x) doit être postérieure au début du créneau (y). Détail"))
        // Retour arrière : le littéral suivant figure aussi dans la valeur d'un argument.
        XCTAssertTrue(RPCInterception.correspond(modele: "A (%) B (%).", message: "A (x) B (y) B (z)."))
        XCTAssertTrue(RPCInterception.correspond(modele: "Notification d'acceptation impossible : %",
                                                 message: "Notification d'acceptation impossible : délai dépassé"))
        XCTAssertFalse(RPCInterception.correspond(modele: "Notification d'acceptation impossible : %",
                                                  message: "Notification d'acceptation impossible : "))
        XCTAssertTrue(RPCInterception.correspond(modele: "%", message: "x"))
        XCTAssertFalse(RPCInterception.correspond(modele: "%", message: ""))
    }

    // MARK: - 42501

    func testAccesRefuseEnListeBlancheDevientUnRefusStructure() async throws {
        // `fn_lire_candidatures_mission_habilitee` l.39533 : PostgREST rend 42501 en HTTP 403 (rôle authenticated).
        let message = "Mission indisponible ou accès refusé"
        let r = try await appeler(exception(403, sqlstate: "42501", message: message, details: "technique", hint: "indice"),
                                  interceptions: [.codeDuTravail, .accesRefuse(messagesExacts: [message])])
        XCTAssertTrue(r.estRefus)
        XCTAssertTrue(r.estAccesRefuse)
        XCTAssertFalse(r.estRefusMetier)
        XCTAssertFalse(r.estSucces)
        XCTAssertEqual(r.code, RPCInterception.codeAccesRefuse)
        XCTAssertEqual(r.sqlstate, "42501")
        XCTAssertEqual(r.erreur, message, "message serveur verbatim")
        XCTAssertFalse("\(r.raw)".contains("technique"), "le DETAIL n'est jamais repris")
        XCTAssertFalse("\(r.raw)".contains("indice"), "le HINT n'est jamais repris")
    }

    func testAccesRefuseDuTriggerRBACAfficheLeMessageNeutre() async throws {
        let r = try await appeler(exception(403, sqlstate: "42501", message: "Permission etablissement pointage requise"),
                                  interceptions: ListesBlanchesEtablissement.interceptions(rpc: "fn_valider_presence"))
        XCTAssertTrue(r.estAccesRefuse)
        XCTAssertEqual(r.erreur, RPCInterception.messageRoleInsuffisant)
        XCTAssertEqual(RPCInterception.messageRoleInsuffisant, "Votre rôle dans cet établissement ne permet pas cette action.")
    }

    func testAccesRefuseHorsListeResteSessionExpiree() async {
        // Comportement du lot 0 : 42501 hors liste blanche → `.unauthorized`.
        let interceptions = ListesBlanchesEtablissement.interceptions(rpc: "fn_lire_candidatures_mission_habilitee")
        for message in ["permission denied for function rpc_fictive_etab", "Mission indisponible ou accès refusé.",
                        "Permission etablissement pointage requise"] {
            let lue = await erreur(exception(403, sqlstate: "42501", message: message), interceptions: interceptions)
            XCTAssertEqual(lue, JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage), message)
        }
    }

    func testMessageEnListeMaisSqlstateDifferentNonIntercepte() async {
        let message = "Mission indisponible ou accès refusé"
        let lue = await erreur(exception(400, sqlstate: "P0001", message: message),
                               interceptions: [.accesRefuse(messagesExacts: [message])])
        XCTAssertEqual(lue, JoleneError(.unknown, fallback), "un SQLSTATE différent n'est jamais intercepté")
        let sansCode = await erreur(exception(400, sqlstate: nil, message: message),
                                    interceptions: [.accesRefuse(messagesExacts: [message])])
        XCTAssertEqual(sansCode, JoleneError(.unknown, fallback))
    }

    func testParDefautLeComportementDuLot1EstInchange() async {
        // Sans liste blanche (appel du lot 1), un 42501 de droit reste « session expirée ».
        let lue = await erreur(exception(403, sqlstate: "42501", message: "Mission indisponible ou accès refusé"))
        XCTAssertEqual(lue, JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage))
        XCTAssertEqual(RPCInterception.parDefaut, [.codeDuTravail])
    }

    // MARK: - Refus métier

    func testRefusMetierEnListeBlancheVerbatim() async throws {
        // `trg_bloquer_validation_presence_avant_fin_planning`, forme `USING ERRCODE = …, MESSAGE = '…'`.
        let interceptions = ListesBlanchesEtablissement.interceptions(rpc: "fn_valider_presence")
        for (sqlstate, status, message) in [
            ("P0001", 400, "Un pointage est encore ouvert pour cette mission."),
            ("P0001", 400, "La présence ne peut être validée avant la fin du dernier créneau planifié."),
            ("23503", 409, "Mission introuvable pour cette présence."),
        ] {
            let r = try await appeler(exception(status, sqlstate: sqlstate, message: message), interceptions: interceptions)
            XCTAssertTrue(r.estRefusMetier, message)
            XCTAssertFalse(r.estAccesRefuse, message)
            XCTAssertEqual(r.code, RPCInterception.codeRefusMetier)
            XCTAssertEqual(r.sqlstate, sqlstate)
            XCTAssertEqual(r.erreur, message)
        }
    }

    func testRefusMetierAvecJokers() async throws {
        let interceptions = ListesBlanchesEtablissement.interceptions(rpc: "fn_declarer_fin_retroactive")
        let introuvable = "Mission 6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b introuvable ou dans un statut incompatible."
        let r = try await appeler(exception(500, sqlstate: "P0002", message: introuvable), interceptions: interceptions)
        XCTAssertEqual(r.erreur, introuvable, "le message instancié par le serveur est affiché tel quel")
        XCTAssertEqual(r.sqlstate, "P0002")
        let heures = "L'heure de fin (2026-11-02 10:00:00+01) doit être postérieure au début du créneau (2026-11-02 11:00:00+01)."
        let h = try await appeler(exception(400, sqlstate: "23514", message: heures), interceptions: interceptions)
        XCTAssertEqual(h.erreur, heures)
        XCTAssertTrue(h.estRefusMetier)
        // Fin rétroactive : 42501 propre (verbatim) et RBAC (neutre).
        let interdit = "Vous n'êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission."
        let i = try await appeler(exception(403, sqlstate: "42501", message: interdit), interceptions: interceptions)
        XCTAssertEqual(i.erreur, interdit)
        let rbac = try await appeler(exception(403, sqlstate: "42501", message: "Permission etablissement missions requise"),
                                     interceptions: interceptions)
        XCTAssertEqual(rbac.erreur, RPCInterception.messageRoleInsuffisant)
    }

    func testP0001SansSqlstateExpliciteDeLaGardeDePaiement() async throws {
        // `fn_trg_gate_assignation_paiement` lève sans ERRCODE (l.63314) : PostgREST sert « P0001 ».
        let message = "Cette mission ne peut pas être attribuée : l'établissement doit d'abord configurer un mode de paiement (Paramètres → Facturation)."
        let r = try await appeler(exception(400, sqlstate: "P0001", message: message),
                                  interceptions: ListesBlanchesEtablissement.interceptions(rpc: "fn_traiter_candidature_planning_v1"))
        XCTAssertTrue(r.estRefusMetier)
        XCTAssertEqual(r.erreur, message)
    }

    func testP0001InconnuOuGeneriqueResteUnMessageGenerique() async {
        let interceptions = ListesBlanchesEtablissement.interceptions(rpc: "fn_traiter_candidature_planning_v1")
        // Revue B8 de T0, mineur 5 : « Notification d'acceptation impossible : % » n'est jamais affiché.
        for message in ["Notification d'acceptation impossible : Mission 6f1c2a3b introuvable", "Erreur interne inattendue"] {
            let lue = await erreur(exception(400, sqlstate: "P0001", message: message), interceptions: interceptions)
            XCTAssertEqual(lue, JoleneError(.unknown, fallback), message)
        }
    }

    // MARK: - 28000, Code du travail, transport

    func testNonAuthentifie28000DevientSessionExpiree() async {
        let interceptions = ListesBlanchesEtablissement.interceptions(rpc: "fn_creer_mission_multi_jours_v4")
        XCTAssertTrue(interceptions.contains(.nonAuthentifie(sqlstate: "28000")))
        let lue = await erreur(exception(403, sqlstate: "28000", message: "Non authentifié"), interceptions: interceptions)
        XCTAssertEqual(lue, JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage))
        // Sans l'interception, 28000 n'est pas une session expirée pour le lot 0 (message générique).
        let sans = await erreur(exception(403, sqlstate: "28000", message: "Non authentifié"))
        XCTAssertEqual(sans, JoleneError(.unknown, fallback))
    }

    func testCodeDuTravailToujoursInterceptePremier() async throws {
        let message = "[CODE DU TRAVAIL] Semaine du 02/11/2026 : 40.0h Jolene + 10.0h ailleurs = 50.0h total (max 48h, Art. L3121-20)"
        let r = try await appeler(exception(400, sqlstate: "P0001", message: message),
                                  interceptions: ListesBlanchesEtablissement.interceptions(rpc: "fn_traiter_candidature_planning_v1"))
        XCTAssertEqual(r.code, CandidatureOutcome.codeRefusCodeDuTravail)
        XCTAssertEqual(r.erreur, message)
        XCTAssertEqual(ListesBlanchesEtablissement.interceptions(rpc: "fn_valider_presence").first, .codeDuTravail)
        XCTAssertEqual(ListesBlanchesEtablissement.interceptions(rpc: "rpc_inconnue"), RPCInterception.parDefaut,
                       "une RPC sans liste blanche garde le comportement du lot 1")
    }

    func testReseauEtContratInchanges() async {
        let interceptions = ListesBlanchesEtablissement.interceptions(rpc: "fn_valider_presence")
        let reseau = await erreur(.networkFailure(), interceptions: interceptions)
        XCTAssertEqual(reseau?.kind, .network)
        let contrat = await erreur(exception(404, sqlstate: "PGRST202", message: "Could not find the function"), interceptions: interceptions)
        XCTAssertEqual(contrat, JoleneError(.contract, SupabaseErrorMapping.contractMessage))
    }

    func testSucces200NonTouche() async throws {
        registry.add("POST", chemin, respond: .json(200, #"{"success":true}"#))
        let r = try await RPCResponse.appeler(TestClient.make(), "rpc_fictive_etab", fallback: fallback,
                                              interceptions: ListesBlanchesEtablissement.interceptions(rpc: "fn_valider_presence"))
        XCTAssertTrue(r.estSucces)
    }
}
