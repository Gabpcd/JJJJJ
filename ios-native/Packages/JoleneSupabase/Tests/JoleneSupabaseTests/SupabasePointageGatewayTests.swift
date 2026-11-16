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
        // Revue fraîche de T3 (m3) : la liste blanche est prouvée sur le type décodé lui-même, ré-encodé.
        let decode = try JSONDecoder().decode(ScanEnregistre.self, from: Data(succesAvantB1.utf8))
        let reencode = try JSONEncoder().encode(decode)
        let cles = try XCTUnwrap(JSONSerialization.jsonObject(with: reencode) as? [String: Any])
        XCTAssertEqual(Set(cles.keys), ["type_scan_effectue", "prochain_type_scan", "creneau_effectif_id", "horodatage_effectif",
                                        "horodatage_arrondi", "numero_scan", "validation_etab_requise"])
        XCTAssertNil(cles["nouveau_code"])
        XCTAssertNil(cles["nouveau_hmac"])
        let texte = String(decoding: reencode, as: UTF8.self) + String(describing: decode) + String(reflecting: decode)
        XCTAssertFalse(texte.contains("482913") || texte.contains("f00dbabe"), "code suivant ni conservé ni ré-encodé")
        // Relecture : état puis preuve hors base du reçu.
        XCTAssertEqual(registry.requests(to: etatPath).count, 1)
        let relecture = try XCTUnwrap(registry.requests(to: scansPath).first)
        XCTAssertEqual(relecture.query("mission_id"), "eq.m-1")
    }

    /// Revue fraîche de T3 (M-A) : un HTTP 200 prouve le COMMIT (PostgREST construit la réponse après lui) ; non confirmé
    /// par la relecture, il n'est jamais `.incertain` (la réconciliation du reçu, filtrée sur sa mission, conclurait
    /// « non reçu ») ni un succès supposé : `.accepteSansPreuve`.
    func testSuccesNonConfirmeParLaRelectureJamaisIncertainNiSuppose() async throws {
        registry.add("POST", scanPath, respond: .json(200, succesApresB1))
        registry.add("POST", etatPath, respond: .json(200, etatJSON(nbScans: 0, prochain: "OUVERTURE")))
        registry.add("GET", scansPath, respond: .json(200, "[\(preuveJSON("s-1", numero: 1))]"))
        let pasBascule = try await gateway().scanner(code: "123456", metadonnees: MetadonneesScan(idTerminal: terminal, observation: nil),
                                                     recu: try recu(), context: TestClient.context)
        XCTAssertEqual(pasBascule, .accepteSansPreuve, "état non basculé : jamais un succès supposé")

        registry.reset()
        registry.add("POST", scanPath, respond: .json(200, succesApresB1))
        stubRelecture(preuves: [preuveJSON("s-1", numero: 1, terminal: "TERM_IOS_AUTREAUTREAUTREAUTRE")])
        let autreTerminal = try await gateway().scanner(code: "123456", metadonnees: MetadonneesScan(idTerminal: terminal, observation: nil),
                                                        recu: try recu(), context: TestClient.context)
        XCTAssertEqual(autreTerminal, .accepteSansPreuve, "preuve d'un autre terminal : rien n'est prouvé")

        let sansNumero = try await scanner(.json(200, #"{"type_scan_effectue":"OUVERTURE"}"#))
        XCTAssertEqual(sansNumero, .enregistre(typeScan: .ouverture, numeroScan: 1),
                       "HTTP 200 sans numero_scan : la preuve hors base de ce terminal, comptée par l'état, est celle de l'essai")
        let sansNumeroNiPreuve = try await scanner(.json(200, #"{"type_scan_effectue":"OUVERTURE"}"#), relecture: false)
        XCTAssertEqual(sansNumeroNiPreuve, .accepteSansPreuve)
        let erreurHTTP200 = try await scanner(.json(200, #"{"error":"inattendu"}"#), relecture: false)
        XCTAssertEqual(erreurHTTP200, .accepteSansPreuve, "`{error}` en HTTP 200 hors contrat : la fonction a rendu, jamais « non reçu »")
        let relectureEnPanne = try await scanner(.json(200, succesApresB1), relecture: false)
        XCTAssertEqual(relectureEnPanne, .accepteSansPreuve)
    }

    /// Seconde revue fraîche de T3 (mi-1) : `envoyerScan` ne fait que l'unique requête (le modèle borne à part les
    /// relectures d'un HTTP 200) ; `relireScanAccepte` fait les relectures ; `scanner` enchaîne les deux.
    func testEnvoyerScanSeulementLaRequeteRelecturesAPart() async throws {
        registry.add("POST", scanPath, respond: .json(200, succesAvantB1))
        stubRelecture()
        let started = try recu()
        let envoi = try await gateway().envoyerScan(code: "123456", metadonnees: MetadonneesScan(idTerminal: terminal, observation: nil),
                                                    recu: started, context: TestClient.context)
        let attendu = try JSONDecoder().decode(ScanEnregistre.self, from: Data(succesApresB1.utf8))
        XCTAssertEqual(envoi, .accepte(attendu), "HTTP 200 : réponse en liste blanche, relectures à faire")
        XCTAssertEqual(registry.requests(to: scanPath).count, 1)
        XCTAssertEqual(registry.requests(to: etatPath).count, 0, "aucune relecture dans la requête")
        XCTAssertEqual(registry.requests(to: scansPath).count, 0)
        let relu = try await gateway().relireScanAccepte(attendu, recu: started, context: TestClient.context)
        XCTAssertEqual(relu, .enregistre(typeScan: .ouverture, numeroScan: 1))
        XCTAssertEqual(registry.requests(to: scanPath).count, 1, "les relectures ne renvoient jamais le scan")
        XCTAssertEqual(registry.requests(to: etatPath).count, 1)

        // Refus et réponse perdue : verdict sans relecture.
        registry.reset()
        registry.add("POST", scanPath, respond: exception("P0002", "Code de pointage invalide ou expiré."))
        let refus = try await gateway().envoyerScan(code: "123456", metadonnees: MetadonneesScan(idTerminal: terminal, observation: nil),
                                                    recu: started, context: TestClient.context)
        XCTAssertEqual(refus, .issue(.refuse(sqlstate: "P0002", message: "Code de pointage invalide ou expiré.")))
        registry.reset()
        registry.add("POST", scanPath, respond: .networkFailure(.networkConnectionLost))
        let perdu = try await gateway().envoyerScan(code: "123456", metadonnees: MetadonneesScan(idTerminal: terminal, observation: nil),
                                                    recu: started, context: TestClient.context)
        XCTAssertEqual(perdu, .issue(.incertain))
        XCTAssertEqual(registry.requests(to: etatPath).count + registry.requests(to: scansPath).count, 0)

        // Même garde que la requête : reçu `started` du même utilisateur.
        let prepare = try RecuScan.preparer(userId: TestClient.userId, epoch: 1, missionId: mission, terminalId: terminal,
                                            typeAttendu: .ouverture, nbScansAvant: 0, preuvesAvant: [], gps: .disponible)
        do {
            _ = try await gateway().relireScanAccepte(attendu, recu: prepare, context: TestClient.context)
            XCTFail("reçu non démarré : erreur de contrat attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
        }
    }

    /// Revue fraîche de T3 (M-A) : `fn_scanner_code_pointage` trouve la mission par le seul code (`public.sql`
    /// l.55639-55644). Le code d'une autre mission du soignant, saisi dans ce bloc, pointe CETTE mission : la ligne du
    /// scan est relue sans filtre de mission, par le créneau et le numéro de la réponse.
    func testCodeDUneAutreMissionJamaisNonRecu() async throws {
        func stubs(localisation: StubResponse, etatAutre: String) {
            registry.reset()
            registry.add("POST", scanPath, respond: .json(200, succesApresB1))
            registry.add("POST", etatPath, where: { ($0.bodyJSON as? [String: String])?["p_mission_id"] == "m-1" },
                         respond: .json(200, etatJSON(nbScans: 0, prochain: "OUVERTURE")))
            registry.add("POST", etatPath, where: { ($0.bodyJSON as? [String: String])?["p_mission_id"] == "m-2" },
                         respond: .json(200, etatAutre))
            registry.add("GET", scansPath, where: { $0.query("mission_id") != nil },
                         respond: .json(200, "[\(preuveJSON("s-0", numero: 0))]"))
            registry.add("GET", scansPath, where: { $0.query("creneau_effectif_id") != nil }, respond: localisation)
        }
        func scannerDansLeBlocM1() async throws -> IssueScan {
            try await gateway().scanner(code: "123456", metadonnees: MetadonneesScan(idTerminal: terminal, observation: nil),
                                        recu: try recu(), context: TestClient.context)
        }

        stubs(localisation: .json(200, "[\(preuveJSON("s-9", numero: 1, mission: "m-2"))]"), etatAutre: etatJSONAutre)
        let ailleurs = try await scannerDansLeBlocM1()
        XCTAssertNotEqual(ailleurs, .nonRecu)
        XCTAssertEqual(ailleurs, .enregistreSurAutreMission(missionId: "m-2", typeScan: .ouverture, numeroScan: 1))
        XCTAssertEqual(registry.requests(to: scanPath).count, 1, "une seule requête, aucun renvoi")
        XCTAssertEqual(registry.unmatched.count, 0)
        let localisation = try XCTUnwrap(registry.requests(to: scansPath).first { $0.query("creneau_effectif_id") != nil })
        XCTAssertEqual(localisation.query("select"), PreuveScan.selection, "projection imposée")
        XCTAssertEqual(localisation.query("creneau_effectif_id"), "eq.c-1")
        XCTAssertEqual(localisation.query("numero_scan"), "eq.1")
        XCTAssertEqual(localisation.query("id_terminal"), "eq.\(terminal)")
        XCTAssertEqual(localisation.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertNil(localisation.query("mission_id"), "sans filtre de mission (`sp_select` l.79931)")
        XCTAssertEqual(registry.requests(to: etatPath).compactMap { ($0.bodyJSON as? [String: String])?["p_mission_id"] }.sorted(),
                       ["m-1", "m-2"], "état de la mission réellement pointée relu")

        // Ligne introuvable, lecture en panne, état de l'autre mission non basculé : COMMIT prouvé, jamais « non reçu ».
        // (Lecture en panne : 400 PostgREST, qu'aucun rejeu GET du SDK ne retarde.)
        let ligneAutre = "[\(preuveJSON("s-9", numero: 1, mission: "m-2"))]"
        let ligneAutreTerminal = "[\(preuveJSON("s-9", numero: 1, terminal: "TERM_IOS_AUTREAUTREAUTREAUTRE", mission: "m-2"))]"
        let panne = #"{"code":"PGRST100","details":null,"hint":null,"message":"failed to parse filter"}"#
        let echecs: [(StubResponse, String)] = [
            (.json(200, "[]"), etatJSONAutre),
            (.json(400, panne), etatJSONAutre),
            (.json(200, ligneAutre), etatJSON(nbScans: 0, prochain: "OUVERTURE")),
            (.json(200, ligneAutreTerminal), etatJSONAutre),
        ]
        for (reponse, etatAutre) in echecs {
            stubs(localisation: reponse, etatAutre: etatAutre)
            let issue = try await scannerDansLeBlocM1()
            XCTAssertEqual(issue, .accepteSansPreuve)
            XCTAssertEqual(registry.requests(to: scanPath).count, 1)
        }

        // La réconciliation du reçu (mission m-1) ne voit rien : c'est pourquoi le modèle ne la consulte jamais après un 200.
        registry.reset()
        registry.add("GET", scansPath, respond: .json(200, "[\(preuveJSON("s-0", numero: 0))]"))
        let reconciliation = try await gateway(decalage: 9).reconcilier(recu: try recu(), context: TestClient.context)
        XCTAssertEqual(reconciliation, .nonRecu, "limite consignée (DECISIONS_LOT2.md) : réponse perdue sur une autre mission")
    }

    /// État de la mission m-2 après l'ouverture rendue par `succesApresB1` (numéro 1, prochain FERMETURE).
    private var etatJSONAutre: String { etatJSON(nbScans: 1, prochain: "FERMETURE") }

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

    /// Revue fraîche de T3 (m1) : un JWT refusé n'est ni un refus métier ni un incertain muet ; `.unauthorized` remonte
    /// (le modèle signale la session expirée et garde le reçu `started`), au scan comme à la relance.
    func testSessionExpireeLeveeAuScanEtALaRelance() async throws {
        for reponse in [StubResponse.json(401, #"{"code":"PGRST301","details":null,"hint":null,"message":"JWT expired"}"#),
                        .json(401, "<html>Unauthorized</html>")] {
            registry.reset()
            registry.add("POST", scanPath, respond: reponse)
            do {
                _ = try await gateway().scanner(code: "123456", metadonnees: MetadonneesScan(idTerminal: terminal, observation: nil),
                                                recu: try recu(), context: TestClient.context)
                XCTFail("session expirée : jamais une issue de scan")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur, JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage))
            }
            XCTAssertEqual(registry.requests(to: scanPath).count, 1, "aucun renvoi")
        }

        registry.reset()
        registry.add("POST", "/rest/v1/rpc/fn_relancer_validation_presence", respond: .json(200, #"{"success":false,"error":"NON_AUTHENTIFIE"}"#))
        do {
            _ = try await gateway().relancerValidation(missionId: mission, context: TestClient.context)
            XCTFail("`NON_AUTHENTIFIE` (public.sql l.53023) : session expirée, jamais « Relance impossible. »")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur, JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage))
        }
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

    /// Revue fraîche de T3 (m5) : parité `fetchEtablissementsSafe` (`src/lib/etablissements.ts` l.31-38, erreur
    /// ignorée) : un échec de `fn_etablissements_safe` n'empêche jamais l'instantané ; les noms manquent seulement.
    func testPresencesSansNomsDEtablissementSiLaLectureEchoue() async throws {
        registry.add("GET", "/rest/v1/missions", where: { $0.query("statut") == "in.(ASSIGNEE,EN_COURS)" }, respond: .json(200, """
        [{"id":"m-1","intitule":"Nuit","service":null,"debut_le":"2026-11-02T00:05:00+00:00","fin_le":"2026-11-02T08:05:00+00:00",
          "duree_heures":8,"statut":"ASSIGNEE","etablissement_id":"etab-1"}]
        """))
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[]"))
        registry.add("GET", "/rest/v1/presences", respond: .json(200, "[]"))
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[]", headers: ["Content-Range": "0-0/0"]))
        registry.add("GET", "/rest/v1/contrats_mission", respond: .json(200, "[]"))
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe",
                     respond: .json(500, #"{"code":"XX000","details":null,"hint":null,"message":"panne"}"#))
        let instantane = try await gateway().presences(context: TestClient.context)
        XCTAssertEqual(instantane.missions.map(\.id), ["m-1"])
        XCTAssertTrue(instantane.etablissements.isEmpty, "noms absents : l'écran affiche le repli du web")
        XCTAssertEqual(registry.requests(to: "/rest/v1/rpc/fn_etablissements_safe").count, 1)
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
