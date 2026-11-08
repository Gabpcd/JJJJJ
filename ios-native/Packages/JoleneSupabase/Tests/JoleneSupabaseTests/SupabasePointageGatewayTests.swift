import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Pointage du lot 2 (T3) sur Supabase : forme de la requête (clés de `PointageRotatifSoignant.tsx` l.122-126, P3),
/// réponse en liste blanche AVANT et APRÈS la PR B1 (`fix/scanner-code-sans-code-suivant` : code suivant retiré de la
/// réponse), exceptions verbatim interceptées avant `SupabaseErrorMapping`, une seule requête, succès seulement après
/// relecture, réconciliation (règle des 8 s), projections imposées, `{error}` de l'état, consentement relu, détail,
/// relance. Ce fichier de test peut nommer les clés du code suivant pour prouver qu'elles sont ignorées ; les sources
/// Swift ne les nomment jamais (garde de T0). Stubs de `fn_etat_pointage_mission` : `est_etab: null` (consigne T3).
final class SupabasePointageGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let scanPath = "/rest/v1/rpc/fn_scanner_code_pointage"
    private let etatPath = "/rest/v1/rpc/fn_etat_pointage_mission"
    private let scansPath = "/rest/v1/scans_pointage"
    private let mission = "m-1"
    private let terminal = "TERM_IOS_ABCDEFGHIJKLMNOPQRST"
    private let now = Date(timeIntervalSince1970: 1_793_577_600) // 2026-11-02T00:00:00Z
    private let position = ObservationGps.disponible(latitude: 48.8566, longitude: 2.3522, precisionM: 12.5)

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway(decalage: TimeInterval = 0) -> SupabasePointageGateway {
        SupabasePointageGateway(client: TestClient.make(), clock: FixedClock(now.addingTimeInterval(decalage)))
    }

    private func recu(nbScansAvant: Int = 0, preuves: [String] = ["s-0"]) throws -> RecuScan {
        try RecuScan.preparer(userId: TestClient.userId, epoch: 1, missionId: mission, terminalId: terminal, typeAttendu: .ouverture,
                              nbScansAvant: nbScansAvant, preuvesAvant: preuves, gps: .disponible)
            .demarrer(le: now)
    }

    private func etatJSON(nbScans: Int, prochain: String, codeEtab: String = "null") -> String {
        """
        {"statut":"EN_COURS","intitule":"Nuit","prochain_type_scan":"\(prochain)","nb_scans":\(nbScans),"segment_ouvert":true,
         "segments":[{"id":"c-1","debut":"2026-11-02T00:00:00+00:00","fin":null}],"code_pointage_actif":\(codeEtab),"est_etab":null}
        """
    }

    private func preuveJSON(_ id: String, numero: Int, terminal: String? = nil, mission: String? = nil) -> String {
        #"{"id":"\#(id)","mission_id":"\#(mission ?? self.mission)","numero_scan":\#(numero),"type_scan":"OUVERTURE","# +
            #""scanne_le":"2026-11-02T00:00:01+00:00","id_terminal":"\#(terminal ?? self.terminal)","precision_gps_m":12.5}"#
    }

    private func exception(_ sqlstate: String, _ message: String) -> StubResponse {
        .json(RPCResponseExceptionsMetierTests.statut(sqlstate), #"{"code":"\#(sqlstate)","details":null,"hint":null,"message":"\#(message)"}"#)
    }

    private let succesAvantB1 = """
    {"type_scan_effectue":"OUVERTURE","prochain_type_scan":"FERMETURE","creneau_effectif_id":"c-1",
     "horodatage_effectif":"2026-11-02T00:00:01+00:00","horodatage_arrondi":"2026-11-02T00:00:00+00:00","numero_scan":1,
     "validation_etab_requise":false,"nouveau_code":"482913","nouveau_hmac":"f00dbabe"}
    """
    /// Forme de la migration B1 (`20261102205212_scanner_code_sans_code_suivant.sql`) : mêmes clés, sans code suivant.
    private let succesApresB1 = """
    {"type_scan_effectue":"OUVERTURE","prochain_type_scan":"FERMETURE","creneau_effectif_id":"c-1",
     "horodatage_effectif":"2026-11-02T00:00:01+00:00","horodatage_arrondi":"2026-11-02T00:00:00+00:00","numero_scan":1,
     "validation_etab_requise":false}
    """

    private func stubRelecture(nbScans: Int = 1, prochain: String = "FERMETURE", preuves: [String]? = nil) {
        registry.add("POST", etatPath, respond: .json(200, etatJSON(nbScans: nbScans, prochain: prochain)))
        let lignes = preuves ?? [preuveJSON("s-1", numero: 1), preuveJSON("s-0", numero: 0)]
        registry.add("GET", scansPath, respond: .json(200, "[\(lignes.joined(separator: ","))]"))
    }

    private func scanner(_ reponse: StubResponse, observation: ObservationGps? = nil, relecture: Bool = true,
                         file: StaticString = #filePath, line: UInt = #line) async throws -> IssueScan {
        registry.reset()
        registry.add("POST", scanPath, respond: reponse)
        if relecture { stubRelecture() }
        let issue = try await gateway().scanner(code: "123456", metadonnees: MetadonneesScan(idTerminal: terminal, observation: observation),
                                                recu: try recu(), context: TestClient.context)
        XCTAssertEqual(registry.requests(to: scanPath).count, 1, "une seule requête, aucun renvoi", file: file, line: line)
        return issue
    }

    // MARK: - Requête (P3)

    func testCorpsDeLaRequeteAuxClesDuWeb() async throws {
        _ = try await scanner(.json(200, succesApresB1), observation: position)
        let corps = try XCTUnwrap(registry.requests(to: scanPath).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(Set(corps.keys), ["p_code", "p_metadata"])
        XCTAssertEqual(corps["p_code"] as? String, "123456")
        let meta = try XCTUnwrap(corps["p_metadata"] as? [String: Any])
        XCTAssertEqual(Set(meta.keys), ["id_terminal", "latitude", "longitude", "precision_gps_m"], "clés de l.122-126")
        XCTAssertEqual(meta["id_terminal"] as? String, terminal)
        XCTAssertEqual(meta["latitude"] as? Double, 48.8566)
        XCTAssertEqual(meta["longitude"] as? Double, 2.3522)
        XCTAssertEqual(meta["precision_gps_m"] as? Double, 12.5)

        for observation in [nil, ObservationGps.refusee, .indisponible, .precisionReduite] {
            _ = try await scanner(.json(200, succesApresB1), observation: observation)
            let sansGps = try XCTUnwrap((registry.requests(to: scanPath).first?.bodyJSON as? [String: Any])?["p_metadata"] as? [String: Any])
            XCTAssertEqual(Set(sansGps.keys), ["id_terminal"], "aucune coordonnée sans position précise (décision 5)")
        }
    }

    // MARK: - Réponse : avant et après B1

    func testReponseAvantEtApresB1MemeSuccesSansCodeSuivant() async throws {
        let avant = try await scanner(.json(200, succesAvantB1))
        let apres = try await scanner(.json(200, succesApresB1))
        XCTAssertEqual(avant, .enregistre(typeScan: .ouverture, numeroScan: 1))
        XCTAssertEqual(apres, avant, "forme d'après B1 décodée, forme d'avant tolérée")
        for valeur in [String(describing: avant), String(reflecting: avant), "\(Mirror(reflecting: avant).children.map(\.value))"] {
            XCTAssertFalse(valeur.contains("482913") || valeur.contains("f00dbabe"), "code suivant jamais exposé ni conservé")
        }
        // Relecture : état puis preuve hors base du reçu.
        XCTAssertEqual(registry.requests(to: etatPath).count, 1)
        let relecture = try XCTUnwrap(registry.requests(to: scansPath).first)
        XCTAssertEqual(relecture.query("mission_id"), "eq.m-1")
    }

    func testSuccesNonConfirmeParLaRelectureResteIncertain() async throws {
        registry.add("POST", scanPath, respond: .json(200, succesApresB1))
        registry.add("POST", etatPath, respond: .json(200, etatJSON(nbScans: 0, prochain: "OUVERTURE")))
        registry.add("GET", scansPath, respond: .json(200, "[\(preuveJSON("s-1", numero: 1))]"))
        let pasBascule = try await gateway().scanner(code: "123456", metadonnees: MetadonneesScan(idTerminal: terminal, observation: nil),
                                                     recu: try recu(), context: TestClient.context)
        XCTAssertEqual(pasBascule, .incertain, "état non basculé : jamais un succès supposé")

        registry.reset()
        registry.add("POST", scanPath, respond: .json(200, succesApresB1))
        stubRelecture(preuves: [preuveJSON("s-1", numero: 1, terminal: "TERM_IOS_AUTREAUTREAUTREAUTRE")])
        let autreTerminal = try await gateway().scanner(code: "123456", metadonnees: MetadonneesScan(idTerminal: terminal, observation: nil),
                                                        recu: try recu(), context: TestClient.context)
        XCTAssertEqual(autreTerminal, .incertain, "preuve d'un autre terminal : rien n'est prouvé")

        let sansNumero = try await scanner(.json(200, #"{"type_scan_effectue":"OUVERTURE"}"#))
        XCTAssertEqual(sansNumero, .incertain, "HTTP 200 sans numero_scan : la fonction a pu valider")
        let relectureEnPanne = try await scanner(.json(200, succesApresB1), relecture: false)
        XCTAssertEqual(relectureEnPanne, .incertain)
    }

    // MARK: - Exceptions

    func testExceptionsVerbatimInterceptees() async throws {
        let refus: [(String, String)] = [
            ("P0002", "Code de pointage invalide ou expiré."),
            ("42501", "Vous n'êtes pas assigné(e) à cette mission."),
            ("23514", "Scan déjà pris en compte. Prochain scan possible dans 87 secondes."),
            ("23514", "Le contrat doit être signé avant le pointage."),
            ("23514", "Pointage trop tôt. Mission commence à 08:00. Possible à partir de 07:45."),
            ("P0002", "Aucun créneau effectif ouvert à fermer."),
            ("23514", "La fin réelle doit être postérieure au début réel du créneau."),
            ("22023", "Mission et soignant requis"),
            ("42501", "Le soignant n'est pas affecté à cette mission."),
            ("23503", "Profil soignant introuvable."),
            ("23514", "Le contrat signé par les deux parties est requis avant le pointage."),
            ("P0001", "Pointage trop tôt. La mission commence à 07:30."),
        ]
        for (sqlstate, message) in refus {
            let issue = try await scanner(exception(sqlstate, message), relecture: false)
            XCTAssertEqual(issue, .refuse(sqlstate: sqlstate, message: message), "\(sqlstate) verbatim, jamais « session expirée »")
            XCTAssertTrue(registry.requests(to: etatPath).isEmpty, "un refus n'est jamais relu comme un succès")
        }
    }

    func testRollbacksHorsListeEtContrat() async throws {
        let privilege = try await scanner(exception("42501", "permission denied for function fn_scanner_code_pointage"), relecture: false)
        XCTAssertEqual(privilege, .refuse(sqlstate: "42501", message: SupabaseErrorMapping.contractMessage), "GRANT manquant : contrat")
        let serialisation = try await scanner(exception("40001", "could not serialize access due to concurrent update"), relecture: false)
        XCTAssertEqual(serialisation, .refuse(sqlstate: "40001", message: PointageQuery.fallbackScan), "rollback prouvé : refus définitif")
        let introuvable = try await scanner(.json(404, """
        {"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.fn_scanner_code_pointage in the schema cache"}
        """), relecture: false)
        XCTAssertEqual(introuvable, .refuse(sqlstate: nil, message: SupabaseErrorMapping.contractMessage))
        let travail = try await scanner(exception("23514", "[CODE DU TRAVAIL] Repos insuffisant avant mission."), relecture: false)
        XCTAssertEqual(travail, .refuse(sqlstate: nil, message: "[CODE DU TRAVAIL] Repos insuffisant avant mission."))
    }

    func testTransportCoupeApresEnvoiIncertainSansSecondeRequete() async throws {
        let perdue = try await scanner(.networkFailure(.networkConnectionLost), relecture: false)
        XCTAssertEqual(perdue, .incertain)
        let passerelle = try await scanner(.json(504, #"{"message":"The upstream server is timing out"}"#), relecture: false)
        XCTAssertEqual(passerelle, .incertain)
        let coupure = try await scanner(.json(503, #"{"code":"PGRST001","details":null,"hint":null,"message":"Database client error."}"#),
                                        relecture: false)
        XCTAssertEqual(coupure, .incertain)
    }

    func testRecuIncoherentRefuseAvantToutEnvoi() async throws {
        let prepare = try RecuScan.preparer(userId: TestClient.userId, epoch: 1, missionId: mission, terminalId: terminal,
                                            typeAttendu: .ouverture, nbScansAvant: 0, preuvesAvant: [], gps: .nonDemande)
        let demarre = try recu()
        let cas: [(RecuScan, MetadonneesScan, String)] = [
            (prepare, MetadonneesScan(idTerminal: terminal, observation: nil), "123456"),
            (demarre, MetadonneesScan(idTerminal: "TERM_IOS_AUTREAUTREAUTREAUTRE", observation: nil), "123456"),
            (demarre, MetadonneesScan(idTerminal: terminal, observation: nil), "12345"),
        ]
        for (candidat, meta, code) in cas {
            do {
                _ = try await gateway().scanner(code: code, metadonnees: meta, recu: candidat, context: TestClient.context)
                XCTFail("reçu non démarré, terminal différent ou code mal formé")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .contract)
            }
        }
        XCTAssertTrue(registry.requests.isEmpty, "aucune requête")
    }

    // MARK: - Réconciliation et preuves

    func testProjectionDesPreuvesSansCodeSaisiNiCoordonnees() async throws {
        registry.add("GET", scansPath, respond: .json(200, "[\(preuveJSON("s-1", numero: 1)),\(preuveJSON("x", numero: 7, mission: "m-2"))]"))
        let preuves = try await gateway().preuvesScan(missionId: mission, context: TestClient.context)
        XCTAssertEqual(preuves.map(\.id), ["s-1"], "ligne d'une autre mission écartée")
        let requete = try XCTUnwrap(registry.requests(to: scansPath).first)
        XCTAssertEqual(requete.query("select"), "id,mission_id,numero_scan,type_scan,scanne_le,id_terminal,precision_gps_m")
        XCTAssertEqual(requete.query("mission_id"), "eq.m-1")
        XCTAssertEqual(requete.query("order"), "numero_scan.desc.nullslast")
        XCTAssertEqual(requete.query("limit"), "1000")
        for interdite in ["code_saisi", "ip_address", "latitude", "longitude"] {
            XCTAssertFalse(requete.url.absoluteString.contains(interdite), interdite)
        }
    }

    func testReconciliationRegleDesHuitSecondes() async throws {
        let started = try recu(nbScansAvant: 0, preuves: ["s-0"])
        registry.add("GET", scansPath, respond: .json(200, "[\(preuveJSON("s-1", numero: 1)),\(preuveJSON("s-0", numero: 0))]"))
        let recu1 = try await gateway(decalage: 2).reconcilier(recu: started, context: TestClient.context)
        XCTAssertEqual(recu1, .enregistre(typeScan: .ouverture, numeroScan: 1), "preuve hors base, même terminal")

        registry.reset()
        registry.add("GET", scansPath, respond: .json(200, "[\(preuveJSON("s-0", numero: 0)),\(preuveJSON("s-2", numero: 1, terminal: "TERM_IOS_AUTREAUTREAUTREAUTRE"))]"))
        let tot = try await gateway(decalage: 3).reconcilier(recu: started, context: TestClient.context)
        XCTAssertEqual(tot, .incertain, "relecture avant 8 s : relire encore")
        let tard = try await gateway(decalage: 9).reconcilier(recu: started, context: TestClient.context)
        XCTAssertEqual(tard, .nonRecu, "absence prouvée 8 s après `started`")
        let recule = try await gateway(decalage: -60).reconcilier(recu: started, context: TestClient.context)
        XCTAssertEqual(recule, .horlogeIncoherente)
        XCTAssertTrue(registry.requests(to: scanPath).isEmpty, "la réconciliation ne renvoie jamais le scan")
    }

    // MARK: - État

    func testEtatEnListeBlancheEtRefusVerbatim() async throws {
        registry.add("POST", etatPath, respond: .json(200, etatJSON(nbScans: 1, prochain: "FERMETURE", codeEtab: #""654321""#)))
        let etat = try await gateway().etat(missionId: mission, context: TestClient.context)
        XCTAssertEqual(etat.nbScans, 1)
        XCTAssertEqual(etat.prochainTypeScan, .fermeture)
        XCTAssertFalse(String(describing: etat).contains("654321"), "code_pointage_actif jamais décodé, même présent")
        let corps = try XCTUnwrap(registry.requests(to: etatPath).first?.bodyJSON as? [String: String])
        XCTAssertEqual(corps, ["p_mission_id": "m-1"])

        for (json, attendu) in [(#"{"error":"Accès interdit"}"#, JoleneError(.unknown, "Accès interdit")),
                                (#"{"error":"Mission introuvable"}"#, JoleneError(.unknown, "Mission introuvable")),
                                (#"{"error":"Non authentifié"}"#, JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)),
                                (#"{"statut":"EN_COURS"}"#, JoleneError(.contract, SupabaseErrorMapping.contractMessage))] {
            registry.reset()
            registry.add("POST", etatPath, respond: .json(200, json))
            do {
                _ = try await gateway().etat(missionId: mission, context: TestClient.context)
                XCTFail("\(json) n'est jamais un état")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur, attendu, json)
            }
        }
    }

    // MARK: - Présences

    func testPresencesQuatreLecturesProjectionsEtAssemblage() async throws {
        registry.add("GET", "/rest/v1/missions", where: { $0.query("statut") == "in.(ASSIGNEE,EN_COURS)" }, respond: .json(200, """
        [{"id":"m-1","intitule":"Nuit","service":null,"debut_le":"2026-11-02T00:05:00+00:00","fin_le":"2026-11-02T08:05:00+00:00",
          "duree_heures":8,"statut":"ASSIGNEE","etablissement_id":"etab-1"},{"intitule":"sans identifiant"}]
        """))
        registry.add("GET", "/rest/v1/missions", where: { $0.query("statut") == "in.(TERMINEE,LITIGE,ABSENCE)" }, respond: .json(200, """
        [{"id":"h-1","intitule":"Passée","debut_le":"2026-10-30T07:00:00+00:00","fin_le":"2026-10-30T15:00:00+00:00","statut":null,
          "etablissement_id":"etab-1"}]
        """))
        registry.add("GET", "/rest/v1/presences", where: { $0.query("valide_par_etablissement") != nil }, respond: .json(200, """
        [{"id":"p-1","mission_id":"h-1","soignant_id":"\(TestClient.userId)","valide_par_etablissement":true,
          "valide_le":"2026-11-01T14:00:00+00:00","missions":{"id":"h-1","intitule":"Passée","etablissement_id":"etab-1"}}]
        """))
        registry.add("GET", "/rest/v1/presences", where: { $0.query("valide_par_etablissement") == nil }, respond: .json(200, "[]"))
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, """
        [\(TestClient.slotJSON(id: "c-1", missionId: "m-1", debut: "2026-11-02T00:05:00+00:00", fin: "2026-11-02T08:05:00+00:00")),
         \(TestClient.slotJSON(id: "e-1", missionId: "h-1", debut: "2026-10-30T07:00:00+00:00", fin: "2026-10-30T15:00:00+00:00", type: "EFFECTIF"))]
        """, headers: ["Content-Range": "0-1/2"]))
        registry.add("GET", "/rest/v1/contrats_mission", respond: .json(200, """
        [{"id":"k-1","mission_id":"m-1","statut":null,"cree_le":"2026-10-01T00:00:00+00:00"},
         {"id":"k-x","mission_id":"autre","statut":"SIGNE_COMPLET","cree_le":null}]
        """))
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: .json(200, TestClient.etablissementJSON))

        let instantane = try await gateway().presences(context: TestClient.context)
        XCTAssertEqual(registry.unmatched.count, 0)
        XCTAssertEqual(instantane.missions.map(\.id), ["m-1"], "ligne sans identifiant écartée")
        XCTAssertEqual(instantane.missionsHistorique.map(\.statut), [""], "statut nul toléré")
        XCTAssertEqual(instantane.presencesValidees.map(\.id), ["p-1"])
        XCTAssertEqual(instantane.creneaux.map(\.id), ["e-1", "c-1"], "tous types, triés par début")
        XCTAssertEqual(instantane.contrats.map(\.id), ["k-1"], "contrat d'une autre mission écarté")
        XCTAssertEqual(instantane.contrats.first?.statut, "")
        XCTAssertEqual(instantane.etablissements["etab-1"]?.nom, "Clinique des Tests")
        XCTAssertEqual(instantane.chargeLe, now)

        let missions = registry.requests(to: "/rest/v1/missions")
        XCTAssertEqual(missions.count, 2)
        for requete in missions {
            XCTAssertEqual(requete.query("select"), "id,intitule,service,debut_le,fin_le,duree_heures,statut,etablissement_id")
            XCTAssertEqual(requete.query("soignant_assigne_id"), "eq.\(TestClient.userId)")
        }
        let presences = registry.requests(to: "/rest/v1/presences")
        XCTAssertEqual(presences.compactMap { $0.query("select") }.sorted(), [
            "id,mission_id,soignant_id,pointage_arrivee_le,pointage_depart_le,valide_par_etablissement,valide_le,methode_pointage_arrivee,methode_pointage_depart,missions!inner(id,intitule,etablissement_id,debut_le,fin_le)",
            "id,mission_id,soignant_id,pointage_arrivee_le,pointage_depart_le,valide_par_etablissement,valide_le,methode_pointage_arrivee,methode_pointage_depart,missions(id,intitule,etablissement_id,debut_le,fin_le,statut)",
        ])
        let validees = try XCTUnwrap(presences.first { $0.query("valide_par_etablissement") != nil })
        XCTAssertEqual(validees.query("valide_par_etablissement"), "eq.true")
        XCTAssertEqual(validees.query("valide_le"), "gte.2026-10-25T23:00:00.000Z",
                       "minuit de Paris 7 jours civils plus tôt (`ajouterJoursCivilsParis`, l.108)")
        let creneaux = try XCTUnwrap(registry.requests(to: "/rest/v1/mission_creneaux").first)
        XCTAssertEqual(creneaux.query("mission_id"), "in.(m-1,h-1)")
        XCTAssertNil(creneaux.query("type_creneau"), "tous types : EFFECTIF compris")
        XCTAssertEqual(try XCTUnwrap(registry.requests(to: "/rest/v1/contrats_mission").first).query("select"), "id,mission_id,statut,cree_le")
        for requete in registry.requests {
            let url = requete.url.absoluteString.removingPercentEncoding ?? ""
            XCTAssertFalse(url.contains("code_pointage"), "gap B1-ter : le code rotatif n'est jamais demandé")
            XCTAssertFalse(url.contains("etablissements("), "jamais l'embed etablissements")
            XCTAssertFalse(url.contains("select=*"), "jamais select=*")
        }
    }

    // MARK: - Consentement, détail, relance

    func testConsentementLuPuisEnregistreEtRelu() async throws {
        registry.add("GET", "/rest/v1/soignants", respond: .json(200, #"{"consentement_gps":null}"#))
        let initial = try await gateway().consentementGps(context: TestClient.context)
        XCTAssertNil(initial)
        let lecture = try XCTUnwrap(registry.requests(to: "/rest/v1/soignants").first)
        XCTAssertEqual(lecture.query("select"), "consentement_gps")
        XCTAssertEqual(lecture.query("id"), "eq.\(TestClient.userId)")

        registry.reset()
        registry.add("POST", "/rest/v1/rpc/fn_consentir_gps", respond: .json(200, #"{"success":true}"#))
        registry.add("GET", "/rest/v1/soignants", respond: .json(200, #"{"consentement_gps":false}"#))
        let relu = try await gateway().enregistrerConsentementGps(true, context: TestClient.context)
        XCTAssertEqual(relu, false, "valeur relue, jamais l'hypothèse locale")
        XCTAssertEqual(registry.requests(to: "/rest/v1/rpc/fn_consentir_gps").first?.bodyJSON as? [String: Bool], ["p_accepte": true])

        registry.reset()
        registry.add("POST", "/rest/v1/rpc/fn_consentir_gps", respond: .json(200, #"{"success":true}"#))
        registry.add("GET", "/rest/v1/soignants", respond: .json(200, #"{"consentement_gps":null}"#))
        do {
            _ = try await gateway().enregistrerConsentementGps(true, context: TestClient.context)
            XCTFail("relecture vide : aucune hypothèse")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur, JoleneError(.unknown, PointageQuery.fallbackLocalisation))
        }
    }

    func testDetailCarteMasqueeSurErreurEtRelanceVerbatim() async throws {
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, """
        [\(TestClient.slotJSON(id: "e-1", missionId: "m-1", debut: "2026-11-02T00:05:00+00:00", fin: "2026-11-02T08:05:00+00:00", type: "EFFECTIF"))]
        """, headers: ["Content-Range": "0-0/1"]))
        registry.add("POST", "/rest/v1/rpc/fn_presences_detail_mission", respond: .json(200, #"{"error":"Accès refusé"}"#))
        let masque = try await gateway().detail(missionId: mission, context: TestClient.context)
        XCTAssertEqual(masque.creneaux.map(\.id), ["e-1"], "reste de l'écran rendu")
        XCTAssertNil(masque.resume, "{error} : carte de synthèse masquée")

        registry.reset()
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[]", headers: ["Content-Range": "0-0/0"]))
        registry.add("POST", "/rest/v1/rpc/fn_presences_detail_mission", respond: .json(200, """
        {"pointage_effectue":true,"heures_reelles":7.5,"duree_pause_min":30,"distance_m":12,"alerte_teleportation":false,
         "methode_arrivee":"CODE","methode_depart":"CODE"}
        """))
        let detail = try await gateway().detail(missionId: mission, context: TestClient.context)
        XCTAssertEqual(detail.resume, ResumePresencesServeur(pointageEffectue: true, dureePauseMin: 30, distanceM: 12, alerteTeleportation: false,
                                                             methodeArrivee: "CODE", methodeDepart: "CODE"))

        for (json, attendu) in [
            (#"{"success":true,"message":"Établissement relancé. Il a été notifié de valider tes présences."}"#,
             IssueRelance.envoyee(message: "Établissement relancé. Il a été notifié de valider tes présences.")),
            (#"{"success":false,"error":"DEJA_RELANCE","message":"Tu as déjà relancé cet établissement aujourd'hui. Il a été notifié."}"#,
             .refusee(message: "Tu as déjà relancé cet établissement aujourd'hui. Il a été notifié.")),
            (#"{"success":false,"error":"RIEN_A_VALIDER"}"#, .refusee(message: "Relance impossible.")),
        ] {
            registry.reset()
            registry.add("POST", "/rest/v1/rpc/fn_relancer_validation_presence", respond: .json(200, json))
            let issue = try await gateway().relancerValidation(missionId: mission, context: TestClient.context)
            XCTAssertEqual(issue, attendu, json)
            XCTAssertEqual(registry.requests(to: "/rest/v1/rpc/fn_relancer_validation_presence").first?.bodyJSON as? [String: String],
                           ["p_mission_id": "m-1"])
        }
    }
}
