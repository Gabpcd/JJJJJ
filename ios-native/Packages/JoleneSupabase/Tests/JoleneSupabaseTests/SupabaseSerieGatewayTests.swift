import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Série sur Supabase (lot 4, T12) : lecture `missions` par le marqueur de série (même requête que le web), lignes
/// contrôlées et enrichies ; acceptation par `fn_confirmer_action_planning_v1` (action `ACCEPTER`, gateway de
/// candidature du lot 1), refus du serveur restitués mot pour mot (HARD STOP n°4), aucun renvoi. Câblage du port :
/// `Lot4WiringSerieTests`.
final class SupabaseSerieGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let serieId = "SERIE_1793577600000_ab12cd"
    private let missionId = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let contratId = "9e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6b"
    private let rpc = "/rest/v1/rpc/fn_confirmer_action_planning_v1"
    private let audit = "/rest/v1/rpc/fn_ecrire_audit_safe"
    private let creneaux = [CreneauConfirme(debut: "2026-12-01T19:00:00Z", fin: "2026-12-02T07:00:00Z")]

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseSerieGateway { SupabaseSerieGateway(client: TestClient.make()) }

    private func ligne(id: String, description: String?, debut: String = "2026-12-01T19:00:00+00:00", statut: String = "OUVERTE",
                       intitule: String = "Renfort IDE", assigne: String? = nil) -> String {
        let texte = description.map { #""\#($0)""# } ?? "null"
        let soignant = assigne.map { #""\#($0)""# } ?? "null"
        return """
        {"id":"\(id)","intitule":"\(intitule)","description":\(texte),"service":"Urgences","profession_requise":"IDE",
         "specialite_medicale_requise":null,"accepte_non_specialises":null,"debut_le":"\(debut)","fin_le":"2026-12-02T07:00:00+00:00",
         "duree_heures":12,"nb_creneaux":1,"taux_horaire_base":28.5,"taux_rist_plafonne":null,"rist_plafond_applique":false,
         "total_brut":342,"net_a_payer":300.1,"est_urgente":false,"niveau_urgence":null,"statut":"\(statut)",
         "etablissement_id":"etab-1","type_contrat_recherche":"SALARIE","boostee_le":null,"mode_remuneration":null,
         "retrocession_pct":null,"mode_attribution":"PREMIER_ARRIVE","presence_confirmee_le":null,"soignant_assigne_id":\(soignant)}
        """
    }

    private func stubEnrichissement(_ ids: [String]) {
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: .json(200, TestClient.etablissementJSON))
        let slots = ids.map { TestClient.slotJSON(id: "s-\($0)", missionId: $0, debut: "2026-12-01T19:00:00+00:00", fin: "2026-12-02T07:00:00+00:00") }
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(
            200, "[\(slots.joined(separator: ","))]", headers: ["Content-Range": "0-\(max(ids.count - 1, 0))/\(ids.count)"]
        ))
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

    // MARK: - Lecture

    func testLectureMemeRequeteQueLeWebPuisEnrichissement() async throws {
        let marqueur = "Renfort régulier [SERIE_ID:\(serieId)]"
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[" + [
            ligne(id: "m-1", description: marqueur),
            ligne(id: "m-2", description: marqueur, debut: "2026-12-03T19:00:00+00:00", statut: "ASSIGNEE", assigne: TestClient.userId),
        ].joined(separator: ",") + "]"))
        stubEnrichissement(["m-1", "m-2"])

        let missions = try await gateway().missions(serieId: serieId, context: TestClient.context)

        let requete = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(requete.method, "GET")
        XCTAssertEqual(requete.query("select"), MissionQuery.missionSelect)
        XCTAssertEqual(requete.query("description"), "ilike.%[SERIE_ID:\(serieId)]%", "filtre du web (`DetailSerieSoignant.tsx` l.95)")
        XCTAssertEqual(requete.query("order"), "debut_le.asc.nullslast")
        XCTAssertNil(requete.query("statut"), "toutes les missions visibles de la série, pourvues comprises")
        XCTAssertEqual(registry.requests(to: "/rest/v1/missions").count, 1)

        XCTAssertEqual(missions.map(\.id), ["m-1", "m-2"], "ordre du serveur")
        XCTAssertEqual(missions.map(\.record.statut), ["OUVERTE", "ASSIGNEE"])
        XCTAssertEqual(missions[1].record.soignantAssigneId, TestClient.userId)
        XCTAssertEqual(missions[0].etablissement?.nom, "Clinique des Tests")
        XCTAssertTrue(missions.allSatisfy { $0.planningExact && $0.creneauxPlanifies.count == 1 })
        let etablissements = try XCTUnwrap(registry.requests(to: "/rest/v1/rpc/fn_etablissements_safe").first)
        XCTAssertEqual((etablissements.bodyJSON as? [String: Any])?["p_ids"] as? [String], ["etab-1"])
        XCTAssertEqual(registry.requests(to: "/rest/v1/mission_creneaux").first?.query("mission_id"), "in.(m-1,m-2)")
    }

    func testSerieVideEtIdentifiantHorsFormeSansRequeteLarge() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[]"))
        let vide = try await gateway().missions(serieId: serieId, context: TestClient.context)
        XCTAssertEqual(vide, [], "aucune mission accessible : liste vide, aucune lecture d'établissement ni de créneau")
        XCTAssertEqual(registry.requests(to: "/rest/v1/rpc/fn_etablissements_safe").count, 0)
        XCTAssertEqual(registry.requests(to: "/rest/v1/mission_creneaux").count, 0)

        registry.reset()
        // Un joker ou toute valeur hors de la forme du web n'atteint jamais le filtre ILIKE.
        for horsForme in ["%", "", "demo-serie-001", "SERIE_%_abcd", "SERIE_1793577600000_AB12", "SERIE_1793577600000_ab12]%", "serie_1793577600000_ab12"] {
            let lues = try await gateway().missions(serieId: horsForme, context: TestClient.context)
            XCTAssertEqual(lues, [], horsForme)
        }
        XCTAssertEqual(registry.requests(to: "/rest/v1/missions").count, 0, "identifiant hors forme : aucune requête")
        XCTAssertTrue(SupabaseSerieGateway.identifiantValide(serieId))
        XCTAssertEqual(SupabaseSerieGateway.marqueur(serieId), "[SERIE_ID:\(serieId)]")
    }

    /// La forme de l'identifiant est celle que le web écrit et relit (`extraireSerieId`).
    func testFormeDeLIdentifiantEstCelleDuWeb() throws {
        let carte = try Depot.texte("src/components/CarteSerie.tsx").components(separatedBy: "\n")
        XCTAssertTrue(carte[27 - 1].contains(#"\[SERIE_ID:(SERIE_\d{10,15}_[a-z0-9]{4,8})\]"#), carte[27 - 1])
        XCTAssertEqual(SupabaseSerieGateway.motifIdentifiant, #"^SERIE_[0-9]{10,15}_[a-z0-9]{4,8}$"#)
    }

    func testLigneHorsSerieRefuseeEtFixturePlaywrightMasquee() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(ligne(id: "m-1", description: "Sans marqueur"))]"))
        let horsSerie = await erreur { _ = try await self.gateway().missions(serieId: self.serieId, context: TestClient.context) }
        XCTAssertEqual(horsSerie, JoleneError(.contract, SupabaseSerieGateway.ligneHorsSerieMessage))

        registry.reset()
        let marqueur = "[SERIE_ID:\(serieId)]"
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[" + [
            ligne(id: "m-1", description: marqueur, intitule: "[playwright-test] Série"),
            ligne(id: "m-2", description: marqueur),
        ].joined(separator: ",") + "]"))
        stubEnrichissement(["m-2"])
        let visibles = try await gateway().missions(serieId: serieId, context: TestClient.context)
        XCTAssertEqual(visibles.map(\.id), ["m-2"], "une fixture Playwright n'existe pas pour un compte ordinaire")
    }

    func testErreursDeLectureJamaisUneSerieVide() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(401, #"{"code":"PGRST301","details":null,"hint":null,"message":"JWT expired"}"#))
        let expiree = await erreur { _ = try await self.gateway().missions(serieId: self.serieId, context: TestClient.context) }
        XCTAssertEqual(expiree?.kind, .unauthorized)

        registry.reset()
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[\(ligne(id: "m-1", description: "[SERIE_ID:\(serieId)]"))]"))
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: .json(200, TestClient.etablissementJSON))
        // Compte de créneaux absent : planning invérifiable, la lecture échoue (jamais un planning présenté comme exact).
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[]"))
        let planning = await erreur { _ = try await self.gateway().missions(serieId: self.serieId, context: TestClient.context) }
        XCTAssertEqual(planning, MissionSlotPager.countUnavailable)

        var autre = TestClient.context
        autre.profile.id = "un-autre"
        registry.reset()
        let contexte = await erreur { _ = try await self.gateway().missions(serieId: self.serieId, context: autre) }
        XCTAssertEqual(contexte?.kind, .unauthorized, "profil et session doivent coïncider")
        XCTAssertEqual(registry.requests(to: "/rest/v1/missions").count, 0)
    }

    // MARK: - Acceptation

    func testAccepterEnvoieAccepterSansMessageNiChoixPuisRelitEtAudite() async throws {
        registry.add("POST", rpc, respond: .json(200, #"{"success":true,"contrat_id":"\#(contratId)"}"#))
        registry.add("GET", "/rest/v1/missions", respond: .json(200, """
        [{"id":"\(missionId)","statut":"ASSIGNEE","soignant_assigne_id":"\(TestClient.userId)","intitule":"Renfort IDE",
          "debut_le":"2026-12-01T19:00:00+00:00","fin_le":"2026-12-02T07:00:00+00:00","etablissement_id":"etab-1"}]
        """))
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: .json(200, TestClient.etablissementJSON))
        registry.add("POST", audit, respond: .json(200, #"{"success":true}"#))

        let issue = try await gateway().accepter(missionId: missionId, creneaux: creneaux, context: TestClient.context)

        XCTAssertEqual(issue, .confirmed(candidatureId: nil, contratId: contratId))
        let envois = registry.requests(to: rpc)
        XCTAssertEqual(envois.count, 1, "une seule requête par mission")
        let corps = try XCTUnwrap(envois.first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["p_mission_id"] as? String, missionId)
        XCTAssertEqual(corps["p_action"] as? String, "ACCEPTER")
        XCTAssertTrue(corps["p_message"] is NSNull, "comme le web (l.299-301) : message, choix de contrat et candidature à null")
        XCTAssertTrue(corps["p_choix_contrat"] is NSNull)
        XCTAssertTrue(corps["p_candidature_id"] is NSNull)
        XCTAssertEqual(corps["p_creneaux_confirmes"] as? [[String: String]], [["debut": "2026-12-01T19:00:00Z", "fin": "2026-12-02T07:00:00Z"]])
        XCTAssertEqual(registry.requests(to: audit).count, 1, "audit MISSION_ASSIGNATION de la mission acceptée (décision 5 du lot 1)")
        let details = try XCTUnwrap(registry.requests(to: audit).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(details["p_action"] as? String, "MISSION_ASSIGNATION")
        XCTAssertEqual(details["p_id_ressource"] as? String, missionId)
    }

    /// HARD STOP n°4 : l'exception d'un trigger de conformité est restituée mot pour mot, une seule requête, sans audit.
    func testRefusDeConformiteRestitueMotPourMotSansRenvoi() async throws {
        let message = "[CODE DU TRAVAIL] Repos insuffisant avant mission : 8.5 heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée."
        registry.add("POST", rpc, respond: .json(400, #"{"code":"23514","details":"mission_conflictuelle=x","hint":null,"message":"\#(message)"}"#))
        let issue = try await gateway().accepter(missionId: missionId, creneaux: creneaux, context: TestClient.context)
        XCTAssertEqual(issue, .refusee(code: CandidatureOutcome.codeRefusCodeDuTravail, message: message, documentsRequisPour: nil))
        XCTAssertEqual(registry.requests(to: rpc).count, 1, "aucun renvoi")
        XCTAssertEqual(registry.requests(to: audit).count, 0)
        XCTAssertEqual(registry.requests(to: "/rest/v1/missions").count, 0, "refus : aucune relecture d'attribution")
    }

    func testRefusStructuresEtChoixDeContratRendusTelsQuels() async throws {
        let conflit = "Tu es déjà confirmé(e) sur « Garde de nuit » le 12/11 08h00–12/11 16h00. Ce créneau chevauche la mission."
        registry.add("POST", rpc, respond: .json(200, #"{"success":false,"ok":false,"code":"CONFLIT_PLANNING","error":"\#(conflit)"}"#))
        let refus = try await gateway().accepter(missionId: missionId, creneaux: creneaux, context: TestClient.context)
        XCTAssertEqual(refus, .refusee(code: "CONFLIT_PLANNING", message: conflit, documentsRequisPour: nil))

        registry.reset()
        registry.add("POST", rpc, respond: .json(200, """
        {"choix_requis":true,"error":"Choisissez votre mode de contrat.",
         "options":[{"value":"SALARIE","label":"Salarié (CDD / bulletin de paie)"},{"value":"LIBERAL","label":"Libéral (note d'honoraires)"}]}
        """))
        let choix = try await gateway().accepter(missionId: missionId, creneaux: creneaux, context: TestClient.context)
        XCTAssertEqual(choix, .choixRequis([ChoixContratOption(value: "SALARIE", label: "Salarié (CDD / bulletin de paie)"),
                                            ChoixContratOption(value: "LIBERAL", label: "Libéral (note d'honoraires)")]))
        XCTAssertEqual(registry.requests(to: rpc).count, 1, "choix requis : jamais rejoué par la série")
    }

    func testPlanningVideJamaisEnvoye() async throws {
        let refus = await erreur { _ = try await self.gateway().accepter(missionId: self.missionId, creneaux: [], context: TestClient.context) }
        XCTAssertEqual(refus?.kind, .contract)
        XCTAssertEqual(registry.requests(to: rpc).count, 0, "fail-closed : un planning non exact n'est jamais envoyé")
    }
}
