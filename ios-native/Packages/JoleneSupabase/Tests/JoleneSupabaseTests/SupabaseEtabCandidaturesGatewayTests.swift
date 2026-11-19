import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Candidatures de l'établissement sur Supabase (lot 5, T6) : lecture habilitée (uuid exigé, mission relue comparée,
/// 42501 de la liste blanche → refus de droit, jamais « session expirée »), acceptation (relecture D25 sous RLS avant
/// tout appel RPC, corps exact, écho des chaînes relues à la microseconde), refus (`p_motif` du web), issues serveur
/// verbatim (planning, cadre étudiant, `[CODE DU TRAVAIL]`, paiement, `{error}` sans drapeau).
final class SupabaseEtabCandidaturesGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let etab = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let missionId = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
    private let candidatureId = "9f8e7d6c-5b4a-4c3d-8e2f-1a0b9c8d7e6f"
    private let rpcLecture = "/rest/v1/rpc/fn_lire_candidatures_mission_habilitee"
    private let rpcTraiter = "/rest/v1/rpc/fn_traiter_candidature_planning_v1"
    private let debutMicro = "2026-11-03T08:00:00.123456+00:00"
    private let fin = "2026-11-03T16:00:00+00:00"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseEtabCandidaturesGateway { SupabaseEtabCandidaturesGateway(client: TestClient.make()) }

    private func contexte() -> EtablissementReadContext {
        EtablissementReadContext(userId: TestClient.userId, etablissementId: etab, roleEtab: .rh,
                                 permissions: PermissionsEtab(accordees: [.lecture, .candidatures, .missions]), epoch: 1)
    }

    private func exception(_ sqlstate: String, _ message: String) -> String {
        #"{"code":"\#(sqlstate)","details":null,"hint":null,"message":"\#(message)"}"#
    }

    private func lectureJSON(mission: String? = nil, etablissement: String? = nil, sansEtablissement: Bool = false) -> String {
        let cleEtablissement = sansEtablissement ? "" : #""etablissement_id":"\#(etablissement ?? etab)","#
        return #"{"mission":{"id":"\#(mission ?? missionId)","intitule":"Nuit",\#(cleEtablissement)"statut":"OUVERTE","mode_attribution":"CANDIDATURE","nb_creneaux":1,"profession_requise":"IDE"},"creneaux":[{"id":"c-1","mission_id":"\#(missionId)","debut":"\#(debutMicro)","fin":"\#(fin)","est_pause":false,"type_creneau":"PREVISIONNEL"}],"candidatures":[{"id":"\#(candidatureId)","soignant_id":"s-1","message":null,"statut":"EN_ATTENTE","cree_le":"2026-11-01T08:00:00+00:00","soignant":{"id":"s-1","prenom":"Camille","nom":"D.","nom_anonymise":true,"profession":"IDE","est_etudiant":false,"note_moyenne":4.9}}]}"#
    }

    private func stubPerimetre(contrat: String = "SALARIE", profession: String = "IDE") {
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, #"{"id":"\#(candidatureId)","mission_id":"\#(missionId)"}"#))
        registry.add("GET", "/rest/v1/missions", respond: .json(
            200, #"{"id":"\#(missionId)","etablissement_id":"\#(etab)","type_contrat_recherche":"\#(contrat)","profession_requise":"\#(profession)"}"#))
    }

    private var charge: [CreneauConfirmePayload] { [CreneauConfirme(debut: debutMicro, fin: fin)] }

    private func accepter() async throws -> TraitementCandidatureOutcome {
        try await gateway().accepter(candidatureId: candidatureId, creneauxConfirmes: charge, context: contexte())
    }

    private func echec(_ appel: () async throws -> Void) async -> Error? {
        do {
            try await appel()
            XCTFail("attendu : erreur levée")
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Lecture

    func testLectureCorpsExactEtMissionRelueComparee() async throws {
        registry.add("POST", rpcLecture, respond: .json(200, lectureJSON()))
        let lecture = try await gateway().lecture(missionId: missionId.uppercased(), context: contexte())
        XCTAssertEqual(lecture.candidatures.first?.soignant?.nom, "D.")
        XCTAssertEqual(lecture.creneaux.first?.debut, debutMicro)
        let requete = try XCTUnwrap(registry.requests(to: rpcLecture).first)
        XCTAssertEqual(requete.bodyJSON as? [String: String], ["p_mission_id": missionId], "uuid canonique, un seul argument")

        registry.reset()
        registry.add("POST", rpcLecture, respond: .json(200, lectureJSON(etablissement: "00000000-1111-4222-8333-444444444444")))
        let erreur = await echec { _ = try await self.gateway().lecture(missionId: self.missionId, context: self.contexte()) }
        XCTAssertEqual((erreur as? JoleneError)?.kind, .contract, "mission d'un autre établissement refusée")

        // Intégration de la vague C (revue B8 de #1164, m2) : clé `etablissement_id` absente → refus (fail-closed).
        registry.reset()
        registry.add("POST", rpcLecture, respond: .json(200, lectureJSON(sansEtablissement: true)))
        let sansCle = await echec { _ = try await self.gateway().lecture(missionId: self.missionId, context: self.contexte()) }
        XCTAssertEqual((sansCle as? JoleneError)?.kind, .contract, "réponse sans établissement : jamais tenue pour la nôtre")
    }

    func testLectureRefusDeDroitJamaisSessionExpiree() async throws {
        registry.add("POST", rpcLecture, respond: .json(403, exception("42501", "Mission indisponible ou accès refusé")))
        let erreur = await echec { _ = try await self.gateway().lecture(missionId: self.missionId, context: self.contexte()) }
        XCTAssertEqual(erreur as? RefusAccesEtablissement, RefusAccesEtablissement(message: "Mission indisponible ou accès refusé"))
    }

    func testIdentifiantNonCanoniqueRefuseAvantReseau() async throws {
        let erreur = await echec { _ = try await self.gateway().lecture(missionId: "demo-etab-m01", context: self.contexte()) }
        XCTAssertEqual((erreur as? JoleneError)?.kind, .contract)
        let refus = await echec { _ = try await self.gateway().refuser(candidatureId: "00000000-0000-0000-0000-000000000000", context: self.contexte()) }
        XCTAssertEqual((refus as? JoleneError)?.kind, .contract)
        XCTAssertTrue(registry.requests(to: rpcLecture).isEmpty && registry.requests(to: rpcTraiter).isEmpty)
    }

    // MARK: - Acceptation

    func testAcceptationCorpsExactEchoMicrosecondes() async throws {
        stubPerimetre()
        registry.add("POST", rpcTraiter, respond: .json(200, #"{"success":true,"contrat_id":"ct-1"}"#))
        let issue = try await accepter()
        XCTAssertEqual(issue, .acceptee(contratId: "ct-1"))
        let corps = try XCTUnwrap(registry.requests(to: rpcTraiter).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["p_candidature_id"] as? String, candidatureId)
        XCTAssertEqual(corps["p_decision"] as? String, "ACCEPTEE")
        XCTAssertTrue(corps["p_motif"] is NSNull, "p_motif NULL à l'acceptation (jamais CADRE_ETUDIANT_AS_CONFIRME)")
        let creneaux = try XCTUnwrap(corps["p_creneaux_confirmes"] as? [[String: String]])
        XCTAssertEqual(creneaux, [["debut": debutMicro, "fin": fin]], "écho exact des chaînes relues (D26)")
        let mission = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(mission.query("select"), "id,etablissement_id,type_contrat_recherche,profession_requise", "aucun montant lu")
        XCTAssertEqual(mission.query("etablissement_id"), "eq.\(etab)", "établissement confirmé")
    }

    func testHorsPerimetreD25AucunAppelRPC() async throws {
        stubPerimetre(contrat: "TOUS")
        let tous = try await accepter()
        XCTAssertEqual(tous, .renvoiWeb(motif: .contratNonSalarie))
        registry.reset()
        stubPerimetre(profession: "MEDECIN")
        let medecin = try await accepter()
        XCTAssertEqual(medecin, .renvoiWeb(motif: .medecin))
        XCTAssertTrue(registry.requests(to: rpcTraiter).isEmpty, "aucun escrow possible : la RPC n'est jamais appelée")
    }

    func testMissionIllisibleAucunEnvoi() async throws {
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, #"{"id":"\#(candidatureId)","mission_id":"\#(missionId)"}"#))
        registry.add("GET", "/rest/v1/missions", respond: .json(406, #"{"code":"PGRST116","details":"The result contains 0 rows","hint":null,"message":"JSON object requested, multiple (or no) rows returned"}"#))
        let erreur = await echec { _ = try await self.accepter() }
        XCTAssertNotNil(erreur)
        XCTAssertTrue(registry.requests(to: rpcTraiter).isEmpty, "fail-closed : jamais un salariat supposé")
    }

    func testIssuesServeurVerbatim() async throws {
        let cas: [(String, Int, TraitementCandidatureOutcome)] = [
            (#"{"success":false,"code":"PLANNING_MODIFIE_RECONFIRMER","error":"Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires."}"#,
             200, .planningAReconfirmer(code: "PLANNING_MODIFIE_RECONFIRMER",
                                        message: "Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires.")),
            (#"{"success":false,"code":"CADRE_ETUDIANT_A_CONFIRMER","error":"Message serveur du cadre."}"#,
             200, .cadreEtudiant(code: "CADRE_ETUDIANT_A_CONFIRMER", message: "Message serveur du cadre.")),
            (#"{"success":false,"code":"CADRE_ETUDIANT_SALARIAT_REQUIS","error":"Refus serveur du cadre."}"#,
             200, .refusee(code: "CADRE_ETUDIANT_SALARIAT_REQUIS", message: "Refus serveur du cadre.", documentsRequisPour: nil)),
            (exception("P0001", "[CODE DU TRAVAIL] Semaine du 30/11/2026 : 50.0h total (max 48h, Art. L3121-20)"),
             400, .refusee(code: CandidatureOutcome.codeRefusCodeDuTravail,
                           message: "[CODE DU TRAVAIL] Semaine du 30/11/2026 : 50.0h total (max 48h, Art. L3121-20)", documentsRequisPour: nil)),
            (exception("P0001", "Cette mission ne peut pas être attribuée : le mandat SEPA de l'établissement n'est pas encore posé (IBAN à ajouter dans Paramètres → Facturation)."),
             400, .paiementNonConfigure(message: "Cette mission ne peut pas être attribuée : le mandat SEPA de l'établissement n'est pas encore posé (IBAN à ajouter dans Paramètres → Facturation).")),
            (exception("42501", "Permission etablissement candidatures requise"),
             403, .accesRefuse(message: "Votre rôle dans cet établissement ne permet pas cette action.")),
        ]
        for (json, statut, attendu) in cas {
            registry.reset()
            stubPerimetre()
            registry.add("POST", rpcTraiter, respond: .json(statut, json))
            let issue = try await accepter()
            XCTAssertEqual(issue, attendu, json)
        }
    }

    func testDejaTraiteeSansDrapeauVerbatimEtNotificationJamaisAffichee() async throws {
        registry.add("POST", rpcTraiter, respond: .json(200, #"{"error":"Cette candidature a déjà été traitée."}"#))
        let erreur = await echec { _ = try await self.gateway().refuser(candidatureId: self.candidatureId, context: self.contexte()) }
        XCTAssertEqual(erreur as? JoleneError, JoleneError(.unknown, "Cette candidature a déjà été traitée."))

        registry.reset()
        stubPerimetre()
        registry.add("POST", rpcTraiter, respond: .json(400, exception("P0001", "Notification d'acceptation impossible : détail interne")))
        let generique = await echec { _ = try await self.accepter() }
        XCTAssertFalse((generique as? JoleneError)?.message.contains("détail interne") ?? true, "suite non garantie jamais affichée")
    }

    // MARK: - Refus

    func testRefusCorpsExact() async throws {
        registry.add("POST", rpcTraiter, respond: .json(200, #"{"success":true}"#))
        let issue = try await gateway().refuser(candidatureId: candidatureId, context: contexte())
        XCTAssertEqual(issue, .refusEnregistre)
        let corps = try XCTUnwrap(registry.requests(to: rpcTraiter).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["p_decision"] as? String, "REFUSEE")
        XCTAssertTrue(corps["p_creneaux_confirmes"] is NSNull)
        XCTAssertEqual(corps["p_motif"] as? String, "Refusé par l'établissement", "motif du web (l.320)")
        XCTAssertTrue(registry.requests(to: "/rest/v1/missions").isEmpty, "le refus reste natif pour toute mission")
    }
}
