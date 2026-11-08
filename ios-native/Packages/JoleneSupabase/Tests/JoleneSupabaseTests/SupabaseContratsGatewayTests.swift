import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Lot 2, T8 — `ContratsPort` sur Supabase (`Contrats/SupabaseContratsGateway.swift`), d'après les fiches
/// `fn_envoyer_otp_signature`, `fn_signer_contrat_otp`, `fn_admission_otp_signature_recette`, « Edge
/// `generate-contrat-mission-pdf` » et « Storage du lot 2 » de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` :
/// projections explicites (jamais `select=*`, correction 22), original triple-contrôlé (octets Storage
/// `contrats-signes` = HTML UTF-8 = `hash_document`), rendu serveur demandé une seule fois (jamais pour un CDD),
/// OTP par nom de RPC et clés exactes (revue de T2, constat 3), `p_signature_image` NULL, relecture avant tout
/// succès de signature, admission seulement sur STAGING. Une réponse = un test ; aucun renvoi automatique.
final class SupabaseContratsGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let id = "6d3f0a52-8b1e-4c7a-9f20-31e5c4b7d8a9"
    private let missionId = "a1b2c3d4-0000-4000-8000-000000000001"
    private let etabId = "e1e2e3e4-0000-4000-8000-000000000002"
    private var chemin: String { "\(id)/0c7e1c2a-5f3b-4a8e-9d21-7b6f3e2a1c90.html" }
    private let html = "<!doctype html><p>Contrat d’essai — été</p>"
    private var empreinte: String { VerificationOriginal.empreinte(html) }
    private let maintenant = Date(timeIntervalSince1970: 1_793_577_600) // 2026-11-02T00:00:00Z

    private let cheminTable = "/rest/v1/contrats_mission"
    private let cheminSignatures = "/rest/v1/signatures_contrats"
    private let cheminEdge = "/functions/v1/generate-contrat-mission-pdf"
    private let cheminEnvoi = "/rest/v1/rpc/fn_envoyer_otp_signature"
    private let cheminSignature = "/rest/v1/rpc/fn_signer_contrat_otp"
    private let cheminAdmission = "/rest/v1/rpc/fn_admission_otp_signature_recette"
    private var cheminObjet: String { "/storage/v1/object/contrats-signes/\(chemin)" }

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway(_ client: SupabaseClient = TestClient.make()) -> SupabaseContratsGateway {
        SupabaseContratsGateway(client: client, clock: FixedClock(maintenant))
    }

    /// Client connecté (session GoTrue simulée) : les mutations exigent la session du compte affiché.
    private func connecte() async throws -> SupabaseClient {
        let client = TestClient.make()
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))
        _ = try await SupabaseAuthGateway(client: client).signIn(email: TestClient.email, password: "motdepasse-test")
        return client
    }

    private func ligne(type: String = "CDDU", statut: String = "EN_ATTENTE_SIGNATURES", original: Bool = true,
                       soignant: Bool = false, soignantId: String? = nil, hash: String? = nil) -> String {
        let contenu = original ? "\"\(html)\"" : "null"
        let empreinteServeur = original ? "\"\(hash ?? empreinte)\"" : "null"
        let objet = original ? "\"\(chemin)\"" : "null"
        let rendu = original ? "\"2026-11-01T14:05:00+00:00\"" : "null"
        return """
        {"id":"\(id)","mission_id":"\(missionId)","soignant_id":"\(soignantId ?? TestClient.userId)","etablissement_id":"\(etabId)",
         "numero_contrat":"C-2026-1","type_contrat":"\(type)","statut":"\(statut)","mode_signature":"JOLENE_OTP",
         "contenu_html":\(contenu),"hash_document":\(empreinteServeur),"storage_path":\(objet),"contenu_html_rendu_le":\(rendu),
         "signature_soignant":\(soignant),"signature_soignant_le":\(soignant ? "\"2026-11-02T00:00:00+00:00\"" : "null"),
         "signature_etablissement":false,"signature_etablissement_le":null,"cree_le":"2026-11-01T14:00:00+00:00"}
        """
    }

    private func estDetail(_ r: RecordedRequest) -> Bool { r.query("select") == ContratDetail.selection }

    /// Lecture du détail (une ligne) et de son contexte : mission, nom d'établissement, compte TEST. Les
    /// prédicats ne lisent jamais le registre (son verrou est tenu pendant leur évaluation).
    private func stubDetail(_ corps: String, estCompteTest: Bool = false, mission: StubResponse? = nil,
                            etablissements: StubResponse? = nil, compte: StubResponse? = nil) {
        registry.add("GET", cheminTable, where: { $0.query("select") == ContratDetail.selection }, respond: .json(200, "[\(corps)]"))
        registry.add("GET", "/rest/v1/missions", where: { $0.query("select") == MissionContrat.selection }, respond: mission ?? .json(200, """
        [{"id":"\(missionId)","intitule":"Nuit en médecine","service":"Médecine","debut_le":"2026-11-03T19:00:00+00:00",
          "fin_le":"2026-11-04T07:00:00+00:00","duree_heures":12,"taux_horaire_base":28.5}]
        """))
        registry.add("POST", "/rest/v1/rpc/fn_etablissements_safe", respond: etablissements ?? .json(200, """
        [{"id":"\(etabId)","nom":"Clinique des Tests","adresse_rue":null,"adresse_code_postal":null,"adresse_ville":"Lyon",
          "adresse_departement":null,"adresse_lat":null,"adresse_lng":null,"type":"CLINIQUE","finess":null,
          "taux_majoration_nuit_pourcent":null,"taux_majoration_dimanche_pourcent":null,"taux_majoration_ferie_pourcent":null,
          "logo_url":null,"couleur_theme":null,"paiement_rapide":false,"jour_paie_habituel":null}]
        """))
        registry.add("GET", "/rest/v1/soignants", respond: compte ?? .json(200, #"[{"est_compte_test":\#(estCompteTest)}]"#))
    }

    private func detail(_ corps: String? = nil) async throws -> ContratDetail {
        stubDetail(corps ?? ligne())
        return try await gateway().contrat(id: id, context: TestClient.context)
    }

    private func signature(_ role: String, statut: String = "signe", hash: String? = nil, user: String? = nil) -> String {
        """
        {"id":"\(UUID().uuidString.lowercased())","contrat_id":"\(id)","signataire_user_id":"\(user ?? TestClient.userId)",
         "signataire_role":"\(role)","signe_a":\(statut == "signe" ? "\"2026-11-02T00:00:00+00:00\"" : "null"),"ip_signature":null,
         "user_agent":null,"hash_document":\(statut == "signe" ? "\"\(hash ?? empreinte)\"" : "null"),
         "otp_valide_a":\(statut == "signe" ? "\"2026-11-02T00:00:00+00:00\"" : "null"),"psc_session_active":false,
         "rpps_verifie":false,"traits_identite_verifies":false,"statut_signature":"\(statut)","cree_le":"2026-11-01T15:00:00+00:00"}
        """
    }

    private func attendreErreur<T>(_ bloc: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async -> Error? {
        do {
            _ = try await bloc()
            XCTFail("erreur attendue", file: file, line: line)
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Liste

    func testListeProjectionDuWebFiltreeSurLeSoignantEtTriee() async throws {
        registry.add("GET", cheminTable, respond: .json(200, """
        [{"id":"k-1","mission_id":"m-1","numero_contrat":"C-1","type_contrat":"CDD","statut":"SIGNE_COMPLET",
          "soignant_id":"\(TestClient.userId)","etablissement_id":"e-1","signature_soignant":true,"signature_etablissement":true,
          "cree_le":"2026-11-01T10:00:00+00:00","missions":{"intitule":"Nuit","debut_le":null,"fin_le":null}},
         {"id":"k-2","mission_id":"m-2","statut":null,"soignant_id":"autre"}]
        """))
        let liste = try await gateway().contrats(context: TestClient.context)
        XCTAssertEqual(liste.map(\.id), ["k-1"], "ligne d'un autre soignant écartée (défense en profondeur de la RLS l.79073)")
        let requete = try XCTUnwrap(registry.requests(to: cheminTable).first)
        XCTAssertEqual(requete.query("select"), ContratResume.selection)
        XCTAssertEqual(requete.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(requete.query("order"), "cree_le.desc.nullsfirst", "même tri que `order(cree_le, desc)` du web (NULLS FIRST par défaut)")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    // MARK: - Détail

    func testDetailAvecMissionNomDEtablissementEtCompteTest() async throws {
        stubDetail(ligne(), estCompteTest: true)
        let contrat = try await gateway().contrat(id: id, context: TestClient.context)
        XCTAssertEqual(contrat.numeroContrat, "C-2026-1")
        XCTAssertEqual(contrat.mission?.intitule, "Nuit en médecine")
        XCTAssertEqual(contrat.etablissementNom, "Clinique des Tests", "nom par fn_etablissements_safe uniquement")
        XCTAssertTrue(contrat.estCompteTest)
        let lecture = try XCTUnwrap(registry.requests(to: cheminTable).first)
        XCTAssertEqual(lecture.query("id"), "eq.\(id)")
        XCTAssertFalse(lecture.query("select")?.contains("*") ?? true)
        let compte = try XCTUnwrap(registry.requests(to: "/rest/v1/soignants").first)
        XCTAssertEqual(compte.query("select"), "est_compte_test")
        XCTAssertEqual(compte.query("id"), "eq.\(TestClient.userId)")
        let etab = try XCTUnwrap(registry.requests(to: "/rest/v1/rpc/fn_etablissements_safe").first?.bodyJSON as? [String: Any])
        XCTAssertEqual(etab["p_ids"] as? [String], [etabId])
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testMissionEtEtablissementIllisiblesNeMasquentPasLeContrat() async throws {
        stubDetail(ligne(), mission: .json(500, #"{"message":"boom"}"#), etablissements: .networkFailure())
        let contrat = try await gateway().contrat(id: id, context: TestClient.context)
        XCTAssertNil(contrat.mission)
        XCTAssertNil(contrat.etablissementNom)
        XCTAssertEqual(contrat.id, id)
    }

    func testCompteTestIllisibleFaitEchouerLeDetail() async throws {
        stubDetail(ligne(), compte: .networkFailure())
        let erreur = await attendreErreur { try await self.gateway().contrat(id: self.id, context: TestClient.context) }
        XCTAssertEqual((erreur as? JoleneError)?.kind, .network, "jamais un compte supposé réel (fail-closed)")
    }

    func testContratDUnAutreSoignantOuAbsentOuIdentifiantInvalide() async throws {
        stubDetail(ligne(soignantId: "11111111-2222-4333-8444-555555555555"))
        var erreur = await attendreErreur { try await self.gateway().contrat(id: self.id, context: TestClient.context) }
        XCTAssertEqual((erreur as? JoleneError)?.message, MessagesContrats.indisponible)
        registry.reset()
        registry.add("GET", cheminTable, respond: .json(200, "[]"))
        erreur = await attendreErreur { try await self.gateway().contrat(id: self.id, context: TestClient.context) }
        XCTAssertEqual((erreur as? JoleneError)?.message, MessagesContrats.indisponible)
        registry.reset()
        erreur = await attendreErreur { try await self.gateway().contrat(id: "pas-un-uuid", context: TestClient.context) }
        XCTAssertEqual((erreur as? JoleneError)?.message, MessagesContrats.indisponible)
        XCTAssertTrue(registry.requests.isEmpty, "identifiant hors format : aucune requête")
    }

    // MARK: - Original

    private func stubOriginal(_ objet: StubResponse, signatures: [String] = []) {
        registry.add("GET", cheminObjet, respond: objet)
        registry.add("GET", cheminSignatures, respond: .json(200, "[\(signatures.joined(separator: ","))]"))
    }

    func testOriginalTripleControle() async throws {
        let contrat = try await detail()
        stubOriginal(StubResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data(html.utf8), failure: nil))
        let original = try await gateway().original(contrat: contrat, context: TestClient.context)
        XCTAssertEqual(original, OriginalContrat(contratId: id, html: html, empreinte: empreinte, numeroContrat: "C-2026-1"))
        XCTAssertEqual(registry.requests(to: cheminObjet).count, 1)
        XCTAssertEqual(registry.requests(to: cheminEdge).count, 0, "original figé : jamais de rendu")
        XCTAssertEqual(registry.requests(to: cheminSignatures).first?.query("select"), SignatureCertificat.selection)
    }

    func testOctetStorageModifieOuObjetAbsent() async throws {
        let contrat = try await detail()
        var octets = Data(html.utf8)
        octets[0] ^= 0x01
        stubOriginal(StubResponse(status: 200, headers: [:], body: octets, failure: nil))
        var erreur = await attendreErreur { try await self.gateway().original(contrat: contrat, context: TestClient.context) }
        XCTAssertEqual((erreur as? ContratOriginalIndisponible)?.motif, .storageMismatch)
        registry.reset()
        stubOriginal(.json(400, #"{"statusCode":"404","error":"not_found","message":"Object not found"}"#))
        erreur = await attendreErreur { try await self.gateway().original(contrat: contrat, context: TestClient.context) }
        XCTAssertEqual((erreur as? ContratOriginalIndisponible)?.motif, .storageMismatch)
        registry.reset()
        stubOriginal(.networkFailure())
        erreur = await attendreErreur { try await self.gateway().original(contrat: contrat, context: TestClient.context) }
        XCTAssertEqual((erreur as? JoleneError)?.kind, .network, "panne de transport : réessayer, jamais un motif d'intégrité")
    }

    func testSignatureSurUneAutreEmpreinteRefuseLOriginal() async throws {
        let contrat = try await detail()
        stubOriginal(StubResponse(status: 200, headers: [:], body: Data(html.utf8), failure: nil),
                     signatures: [signature("etablissement", hash: String(repeating: "f", count: 64))])
        let erreur = await attendreErreur { try await self.gateway().original(contrat: contrat, context: TestClient.context) }
        XCTAssertEqual((erreur as? ContratOriginalIndisponible)?.motif, .signatureMismatch)
    }

    func testEmpreinteServeurDifferenteRefuseeSansTelechargement() async throws {
        let contrat = try await detail(ligne(hash: String(repeating: "0", count: 64)))
        let erreur = await attendreErreur { try await self.gateway().original(contrat: contrat, context: TestClient.context) }
        XCTAssertEqual((erreur as? ContratOriginalIndisponible)?.motif, .hashMismatch)
        XCTAssertEqual(registry.requests(to: cheminObjet).count, 0)
    }

    func testRenduServeurDemandeUneSeuleFoisPuisContratRelu() async throws {
        stubDetail(ligne(original: false))
        let gateway = gateway()
        let avant = try await gateway.contrat(id: id, context: TestClient.context)
        registry.reset()
        registry.add("GET", cheminTable, where: { $0.query("select") == ContratDetail.selection }, respond: .json(200, "[\(ligne())]"))
        registry.add("POST", cheminEdge, respond: .json(200, """
        {"success":true,"contrat_id":"\(id)","storage_path":"\(chemin)","hash_document":"\(empreinte)",
         "signed_url":"https://example.invalid/signe","ttl_seconds":86400}
        """))
        stubOriginal(StubResponse(status: 200, headers: [:], body: Data(html.utf8), failure: nil))
        let original = try await gateway.original(contrat: avant, context: TestClient.context)
        XCTAssertEqual(original.empreinte, empreinte)
        let rendus = registry.requests(to: cheminEdge)
        XCTAssertEqual(rendus.count, 1, "rendu demandé une seule fois")
        let corps = try XCTUnwrap(rendus.first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps.keys.sorted(), ["contrat_id"], "jamais de donnees_cdd côté soignant (décision 19)")
        XCTAssertEqual(corps["contrat_id"] as? String, id)
        XCTAssertEqual(registry.requests(to: cheminTable).filter(estDetail).count, 1, "contrat relu après le rendu")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testRenduRefuseRestitueLeMessageServeurSansRenvoi() async throws {
        let contrat = try await detail(ligne(original: false))
        registry.add("POST", cheminEdge, respond: .json(409, #"{"error":"Le contrat a changé. Rechargez la page."}"#))
        let erreur = await attendreErreur { try await self.gateway().original(contrat: contrat, context: TestClient.context) }
        XCTAssertEqual((erreur as? ContratOriginalIndisponible)?.motif, .renduRefuse(messageServeur: "Le contrat a changé. Rechargez la page."))
        XCTAssertEqual(registry.requests(to: cheminEdge).count, 1, "aucun renvoi automatique")
        registry.reset()
        registry.add("POST", cheminEdge, respond: .json(200, #"{"success":false}"#))
        let sansMessage = await attendreErreur { try await self.gateway().original(contrat: contrat, context: TestClient.context) }
        XCTAssertEqual((sansMessage as? ContratOriginalIndisponible)?.motif, .renduRefuse(messageServeur: nil))
    }

    func testCddSansOriginalEtContratSigneSansOriginalJamaisRendus() async throws {
        let cdd = try await detail(ligne(type: "CDD", original: false))
        var erreur = await attendreErreur { try await self.gateway().original(contrat: cdd, context: TestClient.context) }
        XCTAssertEqual((erreur as? ContratOriginalIndisponible)?.motif, .cddAPreparer)
        registry.reset()
        let signe = try await detail(ligne(statut: "SIGNE_SOIGNANT", original: false, soignant: true))
        erreur = await attendreErreur { try await self.gateway().original(contrat: signe, context: TestClient.context) }
        XCTAssertEqual((erreur as? ContratOriginalIndisponible)?.motif, .nonFige)
        XCTAssertEqual(registry.requests(to: cheminEdge).count, 0, "un document signé n'est jamais réécrit")
    }

    func testFichierOriginalEcritLesOctetsControles() async throws {
        let original = OriginalContrat(contratId: id, html: html, empreinte: empreinte, numeroContrat: "C-2026-1")
        let url = try await gateway().fichierOriginal(contrat: original, context: TestClient.context)
        defer { FichierContratTemporaire.effacer(url) }
        XCTAssertEqual(url.lastPathComponent, "Contrat-C-2026-1.html")
        XCTAssertEqual(try Data(contentsOf: url), Data(html.utf8))
        XCTAssertTrue(registry.requests.isEmpty, "aucune requête : les octets sont ceux déjà contrôlés")
    }

    // MARK: - Certificat

    func testCertificatProjectionAccordeeTrieeParCreation() async throws {
        registry.add("GET", cheminSignatures, respond: .json(200, "[\(signature("etablissement")),\(signature("soignant"))]"))
        let lignes = try await gateway().certificat(contratId: id, context: TestClient.context)
        XCTAssertEqual(lignes.map(\.signataireRole), ["etablissement", "soignant"])
        let requete = try XCTUnwrap(registry.requests(to: cheminSignatures).first)
        XCTAssertEqual(requete.query("select"), SignatureCertificat.selection, "GRANT colonne par colonne : jamais select=*")
        XCTAssertEqual(requete.query("contrat_id"), "eq.\(id)")
        XCTAssertEqual(requete.query("order"), "cree_le.asc.nullslast")
    }

    // MARK: - Envoi du code

    private func stubEmpreinteActuelle(_ valeur: String? = nil) {
        registry.add("GET", cheminTable, where: { $0.query("select") == "id,hash_document" },
                     respond: .json(200, #"[{"id":"\#(id)","hash_document":"\#(valeur ?? empreinte)"}]"#))
    }

    func testEnvoiParNomDeRPCEtCleExacte() async throws {
        let client = try await connecte()
        stubEmpreinteActuelle()
        registry.add("POST", cheminEnvoi, respond: .json(200, """
        {"success":true,"role":"soignant","telephone_masked":"+**********78","expire_dans_minutes":10,"sms_envoyes":1,"sms_restants":2}
        """))
        let issue = try await gateway(client).envoyerOtp(contratId: id, empreinte: empreinte, context: TestClient.context)
        XCTAssertEqual(issue, .envoye(OtpEnvoye(role: "soignant", telephoneMasque: "+**********78", expireDansMinutes: 10,
                                                 smsEnvoyes: 1, smsRestants: 2)))
        let requetes = registry.requests(to: cheminEnvoi)
        XCTAssertEqual(requetes.count, 1)
        let corps = try XCTUnwrap(requetes.first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps.keys.sorted(), ["p_contrat_id"])
        XCTAssertEqual(corps["p_contrat_id"] as? String, id)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testRefusDEnvoiTraduitsCommeLeWeb() async throws {
        let client = try await connecte()
        let g = gateway(client)
        /// Une réponse d'envoi par appel ; la session reste celle du client connecté.
        func repondre(_ corps: String) {
            registry.reset()
            stubEmpreinteActuelle()
            registry.add("POST", cheminEnvoi, respond: .json(200, corps))
        }
        repondre(#"{"success":false,"error_code":"TROP_DE_SMS","error":"Trop de SMS envoyés (3 max / 24h).","sms_envoyes":3}"#)
        let plafond = try await g.envoyerOtp(contratId: id, empreinte: empreinte, context: TestClient.context)
        XCTAssertEqual(plafond, .refuse(code: "TROP_DE_SMS", message: TextesWeb.SignatureOtp.tropDeSms, bloquant: true))
        repondre(#"{"success":false,"error_code":"TROP_DE_SMS_IP","error":"Trop de demandes de signature depuis votre IP. Réessayez dans 1h."}"#)
        let ip = try await g.envoyerOtp(contratId: id, empreinte: empreinte, context: TestClient.context)
        XCTAssertEqual(ip, .refuse(code: "TROP_DE_SMS_IP", message: "Trop de demandes de signature depuis votre IP. Réessayez dans 1h.",
                                   bloquant: false), "code absent de MESSAGES_ERREUR : message serveur verbatim")
        repondre(#"{"success":false,"error_code":"SMS_RECETTE_INDISPONIBLE","error":"Envoi du code indisponible pour cette recette."}"#)
        let recette = try await g.envoyerOtp(contratId: id, empreinte: empreinte, context: TestClient.context)
        XCTAssertEqual(recette, .refuse(code: "SMS_RECETTE_INDISPONIBLE", message: "Envoi du code indisponible pour cette recette.",
                                        bloquant: false))
    }

    func testEmpreinteChangeeAvantEnvoiAucunSms() async throws {
        let client = try await connecte()
        stubEmpreinteActuelle(String(repeating: "9", count: 64))
        let issue = try await gateway(client).envoyerOtp(contratId: id, empreinte: empreinte, context: TestClient.context)
        XCTAssertEqual(issue, .refuse(code: "HASH_DOCUMENT_CHANGE", message: TextesWeb.SignatureOtp.hashDocumentChange, bloquant: true))
        XCTAssertEqual(registry.requests(to: cheminEnvoi).count, 0, "aucun SMS pour une révision qui n'est plus celle affichée")
    }

    func testEnvoiSansSessionDuCompteAffiche() async throws {
        let erreur = await attendreErreur {
            try await self.gateway().envoyerOtp(contratId: self.id, empreinte: self.empreinte, context: TestClient.context)
        }
        XCTAssertEqual((erreur as? JoleneError)?.kind, .unauthorized)
        XCTAssertEqual(registry.requests(to: cheminEnvoi).count, 0)
    }

    // MARK: - Signature

    private func stubRelectureSignee(statut: String = "SIGNE_SOIGNANT", soignant: Bool = true, signatures: [String]? = nil) {
        registry.add("GET", cheminTable, where: { $0.query("select") == ContratDetail.selection },
                     respond: .json(200, "[\(ligne(statut: statut, soignant: soignant))]"))
        registry.add("GET", cheminSignatures, respond: .json(200, "[\((signatures ?? [signature("soignant")]).joined(separator: ","))]"))
    }

    func testSignatureCleExacteImageNulleEtRelecture() async throws {
        let client = try await connecte()
        registry.add("POST", cheminSignature, respond: .json(200, #"{"success":true,"role":"soignant","contrat_complet":false}"#))
        stubRelectureSignee()
        let issue = try await gateway(client).signer(contratId: id, code: "123456", empreinte: empreinte, context: TestClient.context)
        XCTAssertEqual(issue, .signee(contratComplet: false))
        let requete = try XCTUnwrap(registry.requests(to: cheminSignature).first)
        let corps = try XCTUnwrap(requete.bodyJSON as? [String: Any])
        XCTAssertEqual(corps.keys.sorted(), ["p_contrat_id", "p_hash_document", "p_otp_code", "p_signature_image"])
        XCTAssertEqual(corps["p_otp_code"] as? String, "123456")
        XCTAssertEqual(corps["p_hash_document"] as? String, empreinte)
        XCTAssertTrue(corps["p_signature_image"] is NSNull, "OTP seul : image toujours NULL (décision 18)")
        XCTAssertEqual(registry.requests(to: cheminSignature).count, 1)
        XCTAssertEqual(registry.requests(to: cheminSignatures).count, 1, "relecture de la preuve avant le succès")
    }

    func testSuccesNonConfirmeParLaRelectureNEstPasUnSucces() async throws {
        let client = try await connecte()
        registry.add("POST", cheminSignature, respond: .json(200, #"{"success":true,"role":"soignant","contrat_complet":true}"#))
        stubRelectureSignee(soignant: false, signatures: [signature("soignant", statut: "otp_envoye")])
        let erreur = await attendreErreur {
            try await self.gateway(client).signer(contratId: self.id, code: "123456", empreinte: self.empreinte, context: TestClient.context)
        }
        XCTAssertEqual((erreur as? JoleneError)?.message, SupabaseContratsGateway.messageSignatureNonConfirmee)
    }

    func testCodeIncorrectAvecTentativesRestantes() async throws {
        let client = try await connecte()
        registry.add("POST", cheminSignature, respond: .json(200, """
        {"success":false,"error_code":"OTP_INCORRECT","error":"Code incorrect.","tentatives_restantes":4}
        """))
        let issue = try await gateway(client).signer(contratId: id, code: "111111", empreinte: empreinte, context: TestClient.context)
        XCTAssertEqual(issue, .refuse(code: "OTP_INCORRECT", message: TextesWeb.SignatureOtp.otpIncorrect, tentativesRestantes: 4))
        XCTAssertEqual(registry.requests(to: cheminSignatures).count, 0, "un refus ne demande aucune relecture de preuve")
    }

    func testCodeNonNumeriqueOuEmpreinteInvalideAucuneRequete() async throws {
        let client = try await connecte()
        let avant = registry.requests.count
        let lettres = try await gateway(client).signer(contratId: id, code: "12a456", empreinte: empreinte, context: TestClient.context)
        XCTAssertEqual(lettres, .refuse(code: nil, message: LibellesWeb.SignatureOtp.codeSixChiffresRequis, tentativesRestantes: nil))
        let court = try await gateway(client).signer(contratId: id, code: "12345", empreinte: empreinte, context: TestClient.context)
        XCTAssertEqual(court, lettres)
        let revision = try await gateway(client).signer(contratId: id, code: "123456", empreinte: "abc", context: TestClient.context)
        XCTAssertEqual(revision, .refuse(code: "HASH_DOCUMENT_CHANGE", message: TextesWeb.SignatureOtp.hashDocumentChange,
                                         tentativesRestantes: nil))
        XCTAssertEqual(registry.requests.count, avant, "refus local : aucune requête")
    }

    func testReponsePerdueReconcilieeParRelecture() async throws {
        let client = try await connecte()
        registry.add("POST", cheminSignature, respond: .networkFailure(.networkConnectionLost))
        stubRelectureSignee(statut: "SIGNE_COMPLET")
        let issue = try await gateway(client).signer(contratId: id, code: "123456", empreinte: empreinte, context: TestClient.context)
        XCTAssertEqual(issue, .signee(contratComplet: true), "signature appliquée, réponse perdue : succès relu")
        XCTAssertEqual(registry.requests(to: cheminSignature).count, 1, "jamais de renvoi")
    }

    func testReponsePerdueSansPreuveRestitueLErreur() async throws {
        let client = try await connecte()
        registry.add("POST", cheminSignature, respond: .networkFailure(.networkConnectionLost))
        stubRelectureSignee(soignant: false, signatures: [])
        let erreur = await attendreErreur {
            try await self.gateway(client).signer(contratId: self.id, code: "123456", empreinte: self.empreinte, context: TestClient.context)
        }
        XCTAssertEqual((erreur as? JoleneError)?.kind, .network)
        XCTAssertEqual(registry.requests(to: cheminSignature).count, 1)
    }

    func testRoleDeSignatureInvalideEstUnRefusVerbatim() async throws {
        let client = try await connecte()
        registry.add("POST", cheminSignature, respond: .json(400, #"{"code":"23514","message":"Rôle de signature invalide","details":null,"hint":null}"#))
        let issue = try await gateway(client).signer(contratId: id, code: "123456", empreinte: empreinte, context: TestClient.context)
        XCTAssertEqual(issue, .refuse(code: "SQLSTATE_23514", message: "Rôle de signature invalide", tentativesRestantes: nil))
    }

    // MARK: - Admission de recette

    func testAdmissionSurStagingParNomDeRPCEtCleExacte() async throws {
        registry.add("POST", cheminAdmission, respond: .json(200, """
        {"admitted":true,"can_send":true,"can_validate":false,"otp_expires_at":null,
         "expires_at":"2026-11-02T00:30:00.000Z","remaining":2}
        """))
        let admission = try await gateway().admissionRecette(contratId: id, context: TestClient.context)
        XCTAssertEqual(admission, AdmissionSignatureRecette(expireLe: maintenant.addingTimeInterval(1_800), peutEnvoyer: true,
                                                            peutValider: false, otpExpireLe: nil))
        let requete = try XCTUnwrap(registry.requests(to: cheminAdmission).first)
        let corps = try XCTUnwrap(requete.bodyJSON as? [String: Any])
        XCTAssertEqual(corps.keys.sorted(), ["p_contrat_id"])
        XCTAssertEqual(corps["p_contrat_id"] as? String, id)
    }

    func testAdmissionJamaisDemandeeEnProduction() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let production = SupabaseGateways.makeClient(
            url: URL(string: "https://\(JoleneEnvironment.allowedProjectRefs[.production]!).supabase.co")!,
            publishableKey: TestClient.publishableKey, storage: InMemoryAuthStorage(),
            session: URLSession(configuration: configuration), autoRefreshToken: false)
        let admission = try await gateway(production).admissionRecette(contratId: id, context: TestClient.context)
        XCTAssertNil(admission)
        XCTAssertTrue(registry.requests.isEmpty, "PGRST202 en production : la RPC n'est jamais appelée")
    }

    func testAdmissionRefuseeOuIllisibleVautAbsence() async throws {
        registry.add("POST", cheminAdmission, respond: .json(200, #"{"admitted":false}"#))
        let refusee = try await gateway().admissionRecette(contratId: id, context: TestClient.context)
        XCTAssertNil(refusee)
        registry.reset()
        registry.add("POST", cheminAdmission, respond: .json(404, #"{"code":"PGRST202","message":"Could not find the function"}"#))
        let absente = try await gateway().admissionRecette(contratId: id, context: TestClient.context)
        XCTAssertNil(absente, "jamais une erreur de contrat")
    }
}
