import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Présences de l'établissement sur Supabase (lot 5, T8, B9 paiements/escrow) : lecture sans position ni durée servie,
/// validation relue (`valide_par_etablissement`, `valide_le`) avant tout succès, relecture fausse → erreur, quatre refus
/// P0001 et le 23503 du trigger mot pour mot, 42501 RBAC → message neutre (jamais « session expirée »), « Déjà validée »
/// → relecture puis état validé, lot compté sur les lignes relues (jamais `nb_validees`), contestation relue, note au
/// mieux (« déjà notée » = succès), clôture sans clé `success` relue par `segment_ouvert`, heure future refusée avant
/// l'envoi (D28). Une requête par action : aucun renvoi.
final class SupabaseEtabPresencesGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let etab = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let presenceId = "9f8e7d6c-5b4a-4c3d-8e2f-1a0b9c8d7e6f"
    private let autreId = "2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091"
    private let missionId = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
    private let presences = "/rest/v1/presences"
    private let rpcValider = "/rest/v1/rpc/fn_valider_presence"
    private let rpcLot = "/rest/v1/rpc/fn_valider_presences_lot"
    private let rpcContester = "/rest/v1/rpc/fn_contester_presence"
    private let rpcNoter = "/rest/v1/rpc/fn_creer_notation_mission"
    private let rpcCloturer = "/rest/v1/rpc/fn_declarer_fin_retroactive"
    private let rpcEtat = "/rest/v1/rpc/fn_etat_pointage_mission"
    private let maintenant = Date(timeIntervalSince1970: 1_793_577_600) // 2026-11-02T00:00:00Z

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseEtabPresencesGateway {
        let instant = maintenant
        return SupabaseEtabPresencesGateway(client: TestClient.make(), maintenant: { instant })
    }

    private func contexte() -> EtablissementReadContext {
        EtablissementReadContext(userId: TestClient.userId, etablissementId: etab, roleEtab: .pointageOnly,
                                 permissions: PermissionsEtab(accordees: [.lecture, .pointage]), epoch: 1)
    }

    private func exception(_ sqlstate: String, _ message: String) -> String {
        #"{"code":"\#(sqlstate)","details":null,"hint":null,"message":"\#(message)"}"#
    }

    /// Ligne de relecture d'une présence (`relectureSelect`).
    private func relue(_ id: String, valide: Bool, motif: String? = nil, etablissement: String? = nil) -> String {
        let valideLe = valide ? #""2026-11-02T00:00:01.123456+00:00""# : "null"
        let motifJSON = motif.map { #""\#($0)""# } ?? "null"
        return #"{"id":"\#(id)","mission_id":"\#(missionId)","valide_par_etablissement":\#(valide),"valide_le":\#(valideLe),"motif_litige":\#(motifJSON),"missions":{"id":"\#(missionId)","etablissement_id":"\#(etablissement ?? etab)"}}"#
    }

    /// Stub des relectures par identifiant (`id=in.(…)`), distinct de la lecture de liste.
    private func stubRelecture(_ lignes: [String]) {
        registry.add("GET", presences, where: { $0.query("id") != nil }, respond: .json(200, "[\(lignes.joined(separator: ","))]"))
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

    func testListeColonnesExactesSansPositionEtCreneauxHorsPause() async throws {
        registry.add("GET", presences, respond: .json(200, #"""
        [{"id":"\#(presenceId)","mission_id":"\#(missionId)","soignant_id":"s-1","distance_etablissement_m":35,"perimetre_gps_valide":true,
          "alerte_teleportation":false,"arrivee_mock_detected":false,"depart_mock_detected":false,"valide_par_etablissement":false,
          "valide_le":null,"motif_litige":null,
          "missions":{"id":"\#(missionId)","intitule":"Nuit","service":"Urgences","debut_le":"2026-10-31T06:00:00+00:00",
                      "fin_le":"2026-10-31T14:00:00+00:00","nb_creneaux":1,"etablissement_id":"\#(etab)"}}]
        """#))
        let planifie = TestClient.slotJSON(id: "c-1", missionId: missionId, debut: "2026-10-31T06:00:00+00:00", fin: "2026-10-31T14:00:00+00:00")
        let effectif = TestClient.slotJSON(id: "c-2", missionId: missionId, debut: "2026-10-31T06:01:00+00:00", fin: "2026-10-31T14:03:00+00:00",
                                           type: "EFFECTIF")
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[\(planifie),\(effectif)]", headers: ["Content-Range": "0-1/2"]))

        let lues = try await gateway().presences(context: contexte())
        XCTAssertEqual(lues.map(\.id), [presenceId])
        XCTAssertEqual(lues.first?.creneaux.map(\.id), ["c-1", "c-2"], "planning et pointages relus avec la liste")
        XCTAssertEqual(lues.first?.mission?.intitule, "Nuit")

        let requete = try XCTUnwrap(registry.requests(to: presences).first)
        let select = try XCTUnwrap(requete.query("select"))
        XCTAssertEqual(select, "id,mission_id,soignant_id,distance_etablissement_m,perimetre_gps_valide,alerte_teleportation,"
                       + "arrivee_mock_detected,depart_mock_detected,valide_par_etablissement,valide_le,motif_litige,"
                       + "missions!inner(id,intitule,service,debut_le,fin_le,nb_creneaux,etablissement_id)")
        for interdite in ["arrivee_lat", "arrivee_lng", "depart_lat", "depart_lng", "coherence_incidents", "duree_heures", "heures_reelles",
                          "total_brut", "net_a_payer", "taux_horaire"] {
            XCTAssertFalse(select.contains(interdite), "\(interdite) n'est jamais lue")
        }
        XCTAssertEqual(requete.query("missions.etablissement_id"), "eq.\(etab)", "établissement confirmé du contexte")
        XCTAssertEqual(requete.query("pointage_arrivee_le"), "not.is.null", "arrivée pointée seulement (web l.80)")
        XCTAssertEqual(requete.query("order")?.hasPrefix("pointage_arrivee_le.desc"), true)
        let creneaux = try XCTUnwrap(registry.requests(to: "/rest/v1/mission_creneaux").first)
        XCTAssertEqual(creneaux.query("est_pause"), "eq.false")
        XCTAssertNil(creneaux.query("type_creneau"), "PREVISIONNEL et EFFECTIF")
        XCTAssertEqual(creneaux.query("select"), "id,mission_id,debut,fin,est_pause,type_creneau")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testListePresenceDUnAutreEtablissementOuPlanningTronqueRefuses() async throws {
        registry.add("GET", presences, respond: .json(200, #"""
        [{"id":"\#(presenceId)","mission_id":"\#(missionId)","valide_par_etablissement":false,
          "missions":{"id":"\#(missionId)","etablissement_id":"00000000-1111-4222-8333-444444444444"}}]
        """#))
        let etrangere = await echec { _ = try await self.gateway().presences(context: self.contexte()) }
        XCTAssertEqual((etrangere as? JoleneError)?.kind, .contract)
        XCTAssertTrue(registry.requests(to: "/rest/v1/mission_creneaux").isEmpty, "aucun créneau lu pour une ligne non confirmée")

        registry.reset()
        registry.add("GET", presences, respond: .json(200, "[\(relue(presenceId, valide: false))]"))
        let unSeul = TestClient.slotJSON(id: "c-1", missionId: missionId, debut: "2026-10-31T06:00:00+00:00", fin: "2026-10-31T14:00:00+00:00")
        // Réponse sans `Content-Range` : le compte exact manque.
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[\(unSeul)]"))
        let sansCompte = await echec { _ = try await self.gateway().presences(context: self.contexte()) }
        XCTAssertEqual(sansCompte as? JoleneError, MissionSlotPager.countUnavailable, "compte exact exigé : jamais un planning tronqué")
    }

    func testMissionsTermineesEtCreneauxRelus() async throws {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, #"""
        [{"id":"\#(missionId)","intitule":"Terminée","service":null,"debut_le":"2026-10-27T06:00:00+00:00","fin_le":"2026-10-27T14:00:00+00:00",
          "soignant_assigne_id":"s-1","statut":"TERMINEE","etablissement_id":"\#(etab)","total_brut":240}]
        """#))
        let terminees = try await gateway().missionsTerminees(context: contexte())
        XCTAssertEqual(terminees.map(\.id), [missionId])
        let requete = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(requete.query("select"), "id,intitule,service,debut_le,fin_le,soignant_assigne_id,statut,etablissement_id", "aucun montant lu")
        XCTAssertEqual(requete.query("etablissement_id"), "eq.\(etab)")
        XCTAssertEqual(requete.query("type_contrat_applique"), "eq.SALARIE")
        XCTAssertEqual(requete.query("statut"), "eq.TERMINEE")
        XCTAssertEqual(requete.query("soignant_assigne_id"), "not.is.null")

        registry.reset()
        let ouvert = #"{"id":"c-9","mission_id":"\#(missionId)","debut":"2026-11-01T23:58:00+00:00","fin":null,"est_pause":false,"type_creneau":"EFFECTIF"}"#
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[\(ouvert)]", headers: ["Content-Range": "0-0/1"]))
        let relus = try await gateway().creneaux(missionId: missionId.uppercased(), context: contexte())
        XCTAssertEqual(relus.map(\.id), ["c-9"])
        XCTAssertNil(relus.first?.fin, "segment ouvert relu tel quel")
        XCTAssertEqual(registry.requests(to: "/rest/v1/mission_creneaux").first?.query("mission_id"), "in.(\(missionId))")
    }

    // MARK: - Validation

    func testValidationSuccesSeulementApresRelecture() async throws {
        registry.add("POST", rpcValider, respond: .json(200, #"{"success":true}"#))
        stubRelecture([relue(presenceId, valide: true)])
        let issue = try await gateway().valider(presenceId: presenceId.uppercased(), context: contexte())
        XCTAssertEqual(issue, .validee(valideLe: "2026-11-02T00:00:01.123456+00:00"), "valide_le : valeur serveur relue, jamais posée ici")
        let appels = registry.requests(to: rpcValider)
        XCTAssertEqual(appels.count, 1, "une seule requête, jamais renvoyée")
        XCTAssertEqual(appels.first?.bodyJSON as? [String: String], ["p_presence_id": presenceId], "uuid canonique, un seul argument")
        let relecture = try XCTUnwrap(registry.requests(to: presences).first)
        XCTAssertEqual(relecture.query("select"), "id,mission_id,valide_par_etablissement,valide_le,motif_litige,missions!inner(id,etablissement_id)")
        XCTAssertEqual(relecture.query("id"), "in.(\(presenceId))")
        XCTAssertEqual(relecture.query("missions.etablissement_id"), "eq.\(etab)")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testRelectureFausseErreurJamaisUnSucces() async throws {
        for lignes in [[relue(presenceId, valide: false)], [], [relue(autreId, valide: true)]] {
            registry.reset()
            registry.add("POST", rpcValider, respond: .json(200, #"{"success":true}"#))
            stubRelecture(lignes)
            let erreur = await echec { _ = try await self.gateway().valider(presenceId: self.presenceId, context: self.contexte()) }
            XCTAssertEqual(erreur as? JoleneError, JoleneError(.unknown, SupabaseEtabPresencesGateway.nonConfirmee), "\(lignes)")
            XCTAssertEqual(registry.requests(to: rpcValider).count, 1, "aucun renvoi après une relecture non confirmée")
        }
        // Réponse sans `success` : refus de contrat, jamais un succès supposé.
        registry.reset()
        registry.add("POST", rpcValider, respond: .json(200, "{}"))
        let forme = await echec { _ = try await self.gateway().valider(presenceId: self.presenceId, context: self.contexte()) }
        XCTAssertEqual((forme as? JoleneError)?.kind, .contract)
    }

    func testRefusDuTriggerMotPourMot() async throws {
        let refus: [(String, String, Int)] = [
            ("P0001", "La présence ne peut être validée avant la fin du dernier créneau planifié.", 400),
            ("P0001", "Le planning détaillé doit être terminé avant validation de la présence.", 400),
            ("P0001", "Un pointage est encore ouvert pour cette mission.", 400),
            ("P0001", "Aucun pointage terminé ne permet de valider cette présence.", 400),
            ("23503", "Mission introuvable pour cette présence.", 409),
        ]
        for (sqlstate, message, statut) in refus {
            registry.reset()
            registry.add("POST", rpcValider, respond: .json(statut, exception(sqlstate, message)))
            let issue = try await gateway().valider(presenceId: presenceId, context: contexte())
            XCTAssertEqual(issue, .refusee(message: message), "texte serveur mot pour mot")
            XCTAssertTrue(registry.requests(to: presences).isEmpty, "un refus n'est jamais relu comme un succès")

            registry.reset()
            registry.add("POST", rpcLot, respond: .json(statut, exception(sqlstate, message)))
            let lot = try await gateway().validerLot(ids: [presenceId], context: contexte())
            XCTAssertEqual(lot, .refusee(message: message), "une seule ligne en faute annule tout le lot")
        }
        // P0001 hors liste blanche : jamais affiché, message générique.
        registry.reset()
        registry.add("POST", rpcValider, respond: .json(400, exception("P0001", "détail interne inattendu")))
        let horsListe = await echec { _ = try await self.gateway().valider(presenceId: self.presenceId, context: self.contexte()) }
        XCTAssertFalse((horsListe as? JoleneError)?.message.contains("détail interne") ?? true)
    }

    func testRefusDeDroitRBACMessageNeutreJamaisSessionExpiree() async throws {
        XCTAssertEqual(DemoEtabPresencesGateway.roleInsuffisant, RPCInterception.messageRoleInsuffisant, "même message dans les deux mondes")
        let rbac = exception("42501", "Permission etablissement pointage requise")
        registry.add("POST", rpcValider, respond: .json(403, rbac))
        registry.add("POST", rpcLot, respond: .json(403, rbac))
        registry.add("POST", rpcContester, respond: .json(403, rbac))
        let neutre = "Votre rôle dans cet établissement ne permet pas cette action."
        let validation = try await gateway().valider(presenceId: presenceId, context: contexte())
        XCTAssertEqual(validation, .accesRefuse(message: neutre))
        let lot = try await gateway().validerLot(ids: [presenceId], context: contexte())
        XCTAssertEqual(lot, .accesRefuse(message: neutre))
        let contestation = try await gateway().contester(presenceId: presenceId, motif: "Absent", context: contexte())
        XCTAssertEqual(contestation, .accesRefuse(message: neutre))

        // 42501 hors liste blanche : comportement du lot 0 (session), jamais un refus de droit inventé.
        registry.reset()
        registry.add("POST", rpcValider, respond: .json(403, exception("42501", "permission denied for function fn_valider_presence")))
        let horsListe = await echec { _ = try await self.gateway().valider(presenceId: self.presenceId, context: self.contexte()) }
        XCTAssertEqual((horsListe as? JoleneError)?.kind, .unauthorized)
    }

    func testDejaValideeRelecturePuisEtatValideEtRefusJsonb() async throws {
        registry.add("POST", rpcValider, respond: .json(200, #"{"success":false,"error":"Déjà validée"}"#))
        stubRelecture([relue(presenceId, valide: true)])
        let deja = try await gateway().valider(presenceId: presenceId, context: contexte())
        XCTAssertEqual(deja, .validee(valideLe: "2026-11-02T00:00:01.123456+00:00"), "état relu, puis validé")

        registry.reset()
        registry.add("POST", rpcValider, respond: .json(200, #"{"success":false,"error":"Déjà validée"}"#))
        stubRelecture([relue(presenceId, valide: false)])
        let nonConfirme = try await gateway().valider(presenceId: presenceId, context: contexte())
        XCTAssertEqual(nonConfirme, .refusee(message: "Déjà validée"), "relecture non confirmée : message serveur, jamais « Validée »")

        for message in ["Non autorisé", "Présence introuvable"] {
            registry.reset()
            registry.add("POST", rpcValider, respond: .json(200, #"{"success":false,"error":"\#(message)"}"#))
            let issue = try await gateway().valider(presenceId: presenceId, context: contexte())
            XCTAssertEqual(issue, .refusee(message: message))
        }
        registry.reset()
        registry.add("POST", rpcValider, respond: .json(200, #"{"success":false,"error":"Non authentifié"}"#))
        let session = await echec { _ = try await self.gateway().valider(presenceId: self.presenceId, context: self.contexte()) }
        XCTAssertEqual((session as? JoleneError)?.kind, .unauthorized)
    }

    // MARK: - Lot

    func testLotRelitChaqueIdentifiantEtCompteLesLignesRelues() async throws {
        // Le serveur annonce 2 validées ; la relecture n'en confirme qu'une : c'est elle qui est rendue.
        registry.add("POST", rpcLot, respond: .json(200, #"{"success":true,"nb_validees":2}"#))
        stubRelecture([relue(presenceId, valide: true), relue(autreId, valide: false)])
        let issue = try await gateway().validerLot(ids: [presenceId, autreId.uppercased()], context: contexte())
        XCTAssertEqual(issue, .traitee(validees: 1, selectionnees: 2), "1 validée sur 2 sélectionnées, relues une à une")
        let corps = try XCTUnwrap(registry.requests(to: rpcLot).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["p_ids"] as? [String], [presenceId, autreId], "identifiants canoniques, un seul argument")
        XCTAssertEqual(corps.count, 1)
        XCTAssertEqual(registry.requests(to: rpcLot).count, 1)
        let relecture = try XCTUnwrap(registry.requests(to: presences).first)
        XCTAssertEqual(relecture.query("id"), "in.(\(presenceId),\(autreId))")

        registry.reset()
        registry.add("POST", rpcLot, respond: .json(200, #"{"success":false,"error":"Non autorisé"}"#))
        let refus = try await gateway().validerLot(ids: [presenceId], context: contexte())
        XCTAssertEqual(refus, .refusee(message: "Non autorisé"))

        registry.reset()
        for ids in [[], ["demo-etab-p07"], [presenceId, presenceId]] as [[String]] {
            let erreur = await echec { _ = try await self.gateway().validerLot(ids: ids, context: self.contexte()) }
            XCTAssertEqual((erreur as? JoleneError)?.kind, .contract, "\(ids)")
        }
        XCTAssertTrue(registry.requests(to: rpcLot).isEmpty, "liste vide, identifiant non canonique ou doublon : refusés avant réseau")
    }

    // MARK: - Contestation

    func testContestationMotifBorneCorpsExactEtMotifRelu() async throws {
        let court = try await gateway().contester(presenceId: presenceId, motif: "  ab \n", context: contexte())
        XCTAssertEqual(court, .refusee(message: "Le motif est obligatoire (3 caractères min.)"), "borne et message du serveur")
        XCTAssertTrue(registry.requests(to: rpcContester).isEmpty, "aucune requête sous 3 caractères")

        registry.add("POST", rpcContester, respond: .json(200, #"{"success":true}"#))
        stubRelecture([relue(presenceId, valide: false, motif: "Absent")])
        let issue = try await gateway().contester(presenceId: presenceId, motif: "  Absent \n", context: contexte())
        XCTAssertEqual(issue, .contestee(motifLitige: "Absent"), "motif_litige relu")
        XCTAssertEqual(registry.requests(to: rpcContester).first?.bodyJSON as? [String: String],
                       ["p_presence_id": presenceId, "p_motif": "Absent"])
        XCTAssertEqual(registry.requests(to: rpcContester).count, 1)

        registry.reset()
        registry.add("POST", rpcContester, respond: .json(200, #"{"success":true}"#))
        stubRelecture([relue(presenceId, valide: false)])
        let nonRelu = await echec { _ = try await self.gateway().contester(presenceId: self.presenceId, motif: "Absent", context: self.contexte()) }
        XCTAssertEqual(nonRelu as? JoleneError, JoleneError(.unknown, SupabaseEtabPresencesGateway.nonConfirmee))

        registry.reset()
        registry.add("POST", rpcContester, respond: .json(200, #"{"success":false,"error":"Présence introuvable"}"#))
        let introuvable = try await gateway().contester(presenceId: presenceId, motif: "Absent", context: contexte())
        XCTAssertEqual(introuvable, .refusee(message: "Présence introuvable"))
    }

    // MARK: - Note

    func testNoteCorpsExactDejaNoteeEstUnSuccesEtRefusVerbatim() async throws {
        registry.add("POST", rpcNoter, respond: .json(200, #"{"success":true,"id":"n-1","tardive":false}"#))
        let enregistree = try await gateway().noter(missionId: missionId, note: 4, context: contexte())
        XCTAssertEqual(enregistree, .enregistree)
        let corps = try XCTUnwrap(registry.requests(to: rpcNoter).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(Set(corps.keys), ["p_mission_id", "p_sens", "p_critere_1", "p_critere_2", "p_critere_3", "p_critere_4", "p_commentaire"])
        XCTAssertEqual(corps["p_mission_id"] as? String, missionId)
        XCTAssertEqual(corps["p_sens"] as? String, "ETAB_VERS_SOIGNANT")
        XCTAssertEqual((1...4).map { corps["p_critere_\($0)"] as? Int }, [4, 4, 4, 4], "note répliquée sur les quatre critères")
        XCTAssertTrue(corps["p_commentaire"] is NSNull)

        let cas: [(String, Int, NotationOutcome)] = [
            (#"{"success":false,"error":"Mission déjà notée pour ce sens"}"#, 200, .enregistree),
            (#"{"success":false,"error":"Seules les missions TERMINEE peuvent être notées"}"#, 200,
             .nonEnregistree(message: "Seules les missions TERMINEE peuvent être notées")),
            (exception("P0001", "La notation n’a pas pu être enregistrée. Veuillez réessayer."), 400,
             .nonEnregistree(message: "La notation n’a pas pu être enregistrée. Veuillez réessayer.")),
            ("{}", 200, .nonEnregistree(message: nil)),
        ]
        for (json, statut, attendu) in cas {
            registry.reset()
            registry.add("POST", rpcNoter, respond: .json(statut, json))
            let issue = try await gateway().noter(missionId: missionId, note: 5, context: contexte())
            XCTAssertEqual(issue, attendu, json)
        }
        registry.reset()
        for note in [0, 6, -1] {
            let erreur = await echec { _ = try await self.gateway().noter(missionId: self.missionId, note: note, context: self.contexte()) }
            XCTAssertEqual((erreur as? JoleneError)?.kind, .contract, "note \(note) refusée avant réseau")
        }
        XCTAssertTrue(registry.requests(to: rpcNoter).isEmpty)
        XCTAssertTrue(registry.requests.allSatisfy { $0.method != "GET" }, "écriture seule : aucune note n'est jamais lue")
    }

    // MARK: - Clôture rétroactive

    func testClotureSuccesSansCleSuccessPuisSegmentFermeRelu() async throws {
        // Réponse du serveur sans clé `success` ; un code de pointage suivant qui y figurerait n'est jamais lu.
        registry.add("POST", rpcCloturer, respond: .json(200, #"""
        {"creneau_effectif_id":"c-9","debut_creneau":"2026-11-01T23:58:00+00:00","fin_declaree":"2026-11-02T00:00:00+00:00",
         "validation_etab_requise":true,"prochain_type_scan":"OUVERTURE","numero_scan":2,"nouveau_code":"654321","nouveau_hmac":"abc"}
        """#))
        registry.add("POST", rpcEtat, respond: .json(200, #"{"statut":"EN_COURS","segment_ouvert":false,"segments":[],"code_pointage_actif":"111222"}"#))
        let issue = try await gateway().cloturerSegment(missionId: missionId, heureFin: maintenant, context: contexte())
        XCTAssertEqual(issue, .cloturee)
        XCTAssertEqual(registry.requests(to: rpcCloturer).first?.bodyJSON as? [String: String], [
            "p_mission_id": missionId, "p_heure_fin": "2026-11-02T00:00:00.000Z",
            "p_raison": "Clôture par l'établissement (oubli de scan / sans téléphone)",
        ], "trois arguments, heure en ISO UTC, raison du web")
        XCTAssertEqual(registry.requests(to: rpcCloturer).count, 1)
        XCTAssertEqual(registry.requests(to: rpcEtat).first?.bodyJSON as? [String: String], ["p_mission_id": missionId])
    }

    func testClotureHeureFutureRefuseeAvantEnvoiEtRelectureNonConfirmee() async throws {
        let future = await echec {
            _ = try await self.gateway().cloturerSegment(missionId: self.missionId, heureFin: self.maintenant.addingTimeInterval(60), context: self.contexte())
        }
        XCTAssertEqual((future as? JoleneError)?.kind, .contract, "D28 : le serveur accepterait une heure future")
        XCTAssertTrue(registry.requests(to: rpcCloturer).isEmpty)

        registry.add("POST", rpcCloturer, respond: .json(200, #"{"creneau_effectif_id":"c-9"}"#))
        registry.add("POST", rpcEtat, respond: .json(200, #"{"statut":"EN_COURS","segment_ouvert":true,"segments":[]}"#))
        let ouvert = await echec { _ = try await self.gateway().cloturerSegment(missionId: self.missionId, heureFin: self.maintenant, context: self.contexte()) }
        XCTAssertEqual(ouvert as? JoleneError, JoleneError(.unknown, SupabaseEtabPresencesGateway.nonConfirmee), "segment encore ouvert : jamais « clôturé »")
        XCTAssertEqual(registry.requests(to: rpcCloturer).count, 1, "aucun renvoi")

        registry.reset()
        registry.add("POST", rpcCloturer, respond: .json(200, #"{"creneau_effectif_id":"c-9"}"#))
        registry.add("POST", rpcEtat, respond: .json(200, #"{"error":"Accès interdit"}"#))
        let refusEtat = await echec { _ = try await self.gateway().cloturerSegment(missionId: self.missionId, heureFin: self.maintenant, context: self.contexte()) }
        XCTAssertEqual((refusEtat as? JoleneError)?.kind, .unknown)

        registry.reset()
        registry.add("POST", rpcCloturer, respond: .json(200, #"{"fin_declaree":"2026-11-02T00:00:00+00:00"}"#))
        let sansIdentifiant = await echec { _ = try await self.gateway().cloturerSegment(missionId: self.missionId, heureFin: self.maintenant, context: self.contexte()) }
        XCTAssertEqual((sansIdentifiant as? JoleneError)?.kind, .contract, "sans creneau_effectif_id : jamais un succès supposé")
        XCTAssertTrue(registry.requests(to: rpcEtat).isEmpty)
    }

    func testClotureRefusServeurMotPourMot() async throws {
        let neutre = "Votre rôle dans cet établissement ne permet pas cette action."
        let heure = "L'heure de fin (2026-11-01 23:00:00+00) doit être postérieure au début du créneau (2026-11-01 23:58:00+00)."
        let cas: [(String, String, Int, ClotureOutcome)] = [
            ("P0002", "Mission \(missionId) introuvable ou dans un statut incompatible.", 400,
             .refusee(message: "Mission \(missionId) introuvable ou dans un statut incompatible.")),
            ("P0002", "Aucun créneau effectif ouvert à fermer pour cette mission.", 400,
             .refusee(message: "Aucun créneau effectif ouvert à fermer pour cette mission.")),
            ("23514", heure, 400, .refusee(message: heure)),
            ("42501", "Vous n'êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission.", 403,
             .accesRefuse(message: "Vous n'êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission.")),
            ("42501", "Permission etablissement pointage requise", 403, .accesRefuse(message: neutre)),
            ("42501", "Permission etablissement missions requise", 403, .accesRefuse(message: neutre)),
        ]
        for (sqlstate, message, statut, attendu) in cas {
            registry.reset()
            registry.add("POST", rpcCloturer, respond: .json(statut, exception(sqlstate, message)))
            let issue = try await gateway().cloturerSegment(missionId: missionId, heureFin: maintenant, context: contexte())
            XCTAssertEqual(issue, attendu, message)
            XCTAssertTrue(registry.requests(to: rpcEtat).isEmpty, "un refus n'est jamais relu comme une clôture")
        }
    }

    // MARK: - Garde-fous

    func testIdentifiantNonCanoniqueRefuseAvantReseau() async throws {
        let appels: [() async throws -> Void] = [
            { _ = try await self.gateway().valider(presenceId: "demo-etab-p07", context: self.contexte()) },
            { _ = try await self.gateway().contester(presenceId: "", motif: "Absent", context: self.contexte()) },
            { _ = try await self.gateway().noter(missionId: "00000000-0000-0000-0000-000000000000", note: 4, context: self.contexte()) },
            { _ = try await self.gateway().cloturerSegment(missionId: "m-1", heureFin: self.maintenant, context: self.contexte()) },
            { _ = try await self.gateway().creneaux(missionId: "m-1", context: self.contexte()) },
        ]
        for appel in appels {
            let erreur = await echec(appel)
            XCTAssertEqual((erreur as? JoleneError)?.kind, .contract)
        }
        XCTAssertTrue(registry.requests.isEmpty, "aucune requête pour un identifiant non canonique")
    }

    func testPortCableDansLeMondeSupabase() {
        let ports = SupabaseEtablissementGateways.make(client: TestClient.make())
        XCTAssertTrue(ports.presences is SupabaseEtabPresencesGateway)
        XCTAssertFalse(ports.unwiredPorts.contains("etablissement.presences"))
    }
}
