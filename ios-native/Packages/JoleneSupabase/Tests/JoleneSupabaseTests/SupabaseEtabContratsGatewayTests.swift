import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Lot 5, T10 — contrats et signature OTP de l'établissement sur Supabase (`Etablissement/SupabaseEtabContratsGateway.swift`,
/// `LOT5_PLAN.md` §3 T10) : requêtes exactes (`contrats_mission` `eq(etablissement_id)` de l'établissement confirmé,
/// détail borné à cet établissement, compte TEST sur `etablissements`, jamais la mission ni ses montants), aucun appel
/// sans la permission `contrats`, triple contrôle avant l'envoi, refus `{success:false, error_code, error}` de
/// `fn_envoyer_otp_signature` / `fn_signer_contrat_otp` traduits comme le web (`NON_AUTORISE`, `TELEPHONE_MANQUANT`,
/// `OTP_INCORRECT` avec `tentatives_restantes`, `HASH_DOCUMENT_CHANGE`), succès seulement après relecture de
/// `signature_etablissement_le` non nul et de la preuve du membre.
final class SupabaseEtabContratsGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let id = "6d3f0a52-8b1e-4c7a-9f20-31e5c4b7d8a9"
    private let missionId = "a1b2c3d4-0000-4000-8000-000000000001"
    private let etab = "e1e2e3e4-0000-4000-8000-000000000002"
    private let soignantId = "5a5a5a5a-0000-4000-8000-000000000003"
    private let html = "<!doctype html><p>Contrat d’essai — été</p>"
    private var empreinte: String { VerificationOriginal.empreinte(html) }
    private var chemin: String { "\(id)/0c7e1c2a-5f3b-4a8e-9d21-7b6f3e2a1c90.html" }

    private let cheminTable = "/rest/v1/contrats_mission"
    private let cheminSignatures = "/rest/v1/signatures_contrats"
    private let cheminEnvoi = "/rest/v1/rpc/fn_envoyer_otp_signature"
    private let cheminSignature = "/rest/v1/rpc/fn_signer_contrat_otp"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway(_ client: SupabaseClient = TestClient.make()) -> SupabaseContratsGateway {
        SupabaseContratsGateway(client: client, clock: FixedClock(Date(timeIntervalSince1970: 1_793_577_600)))
    }

    private func contexte(_ permissions: Set<PermissionEtab> = [.lecture, .missions, .candidatures, .contrats, .pointage, .rh])
        -> EtablissementReadContext {
        EtablissementReadContext(userId: TestClient.userId, etablissementId: etab, roleEtab: .rh,
                                 permissions: PermissionsEtab(accordees: permissions), epoch: 1)
    }

    private func connecte() async throws -> SupabaseClient {
        let client = TestClient.make()
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))
        _ = try await SupabaseAuthGateway(client: client).signIn(email: TestClient.email, password: "motdepasse-test")
        return client
    }

    private func ligne(etablissementId: String? = nil, signeEtab: Bool = false, signeLe: String? = nil,
                       statut: String = "EN_ATTENTE_SIGNATURES") -> String {
        """
        {"id":"\(id)","mission_id":"\(missionId)","soignant_id":"\(soignantId)","etablissement_id":"\(etablissementId ?? etab)",
         "numero_contrat":"C-2026-1","type_contrat":"CDDU","statut":"\(statut)","mode_signature":"JOLENE_OTP",
         "contenu_html":"\(html)","hash_document":"\(empreinte)","storage_path":"\(chemin)",
         "contenu_html_rendu_le":"2026-11-01T14:05:00+00:00","signature_soignant":false,"signature_soignant_le":null,
         "signature_etablissement":\(signeEtab),"signature_etablissement_le":\(signeLe.map { "\"\($0)\"" } ?? "null"),
         "cree_le":"2026-11-01T14:00:00+00:00"}
        """
    }

    private func preuve(role: String = "etablissement", user: String? = nil) -> String {
        """
        {"id":"\(UUID().uuidString.lowercased())","contrat_id":"\(id)","signataire_user_id":"\(user ?? TestClient.userId)",
         "signataire_role":"\(role)","signe_a":"2026-11-02T00:00:00+00:00","ip_signature":null,"user_agent":null,
         "hash_document":"\(empreinte)","otp_valide_a":"2026-11-02T00:00:00+00:00","psc_session_active":false,
         "rpps_verifie":false,"traits_identite_verifies":false,"statut_signature":"signe","cree_le":"2026-11-01T15:00:00+00:00"}
        """
    }

    private func erreur<T>(_ bloc: () async throws -> T) async -> Error? {
        do { _ = try await bloc(); XCTFail("erreur attendue"); return nil } catch { return error }
    }

    // MARK: - Lectures

    func testListeDeLEtablissementConfirmeProjectionDuWebEtLignesEtrangeresEcartees() async throws {
        registry.add("GET", cheminTable, respond: .json(200, """
        [{"id":"k-1","mission_id":"m-1","numero_contrat":"C-1","type_contrat":"CDD","statut":"EN_ATTENTE_SIGNATURES",
          "soignant_id":"\(soignantId)","etablissement_id":"\(etab.uppercased())","signature_soignant":true,
          "signature_etablissement":false,"cree_le":"2026-11-01T10:00:00+00:00","missions":{"intitule":"Nuit","debut_le":null,"fin_le":null}},
         {"id":"k-2","mission_id":"m-2","statut":"SIGNE_COMPLET","etablissement_id":"autre"}]
        """))
        let liste = try await gateway().contratsEtablissement(context: contexte())
        XCTAssertEqual(liste.map(\.id), ["k-1"], "ligne d'un autre établissement écartée (défense en profondeur de la RLS)")
        let requete = try XCTUnwrap(registry.requests(to: cheminTable).first)
        XCTAssertEqual(requete.query("select"), ContratResume.selection)
        XCTAssertEqual(requete.query("etablissement_id"), "eq.\(etab)", "établissement confirmé du contexte, jamais user.id")
        XCTAssertNil(requete.query("soignant_id"))
        XCTAssertEqual(requete.query("order"), "cree_le.desc.nullsfirst")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testSansLaPermissionContratsAucunAppel() async throws {
        let sans = contexte([.lecture, .pointage])
        let appels: [() async throws -> Void] = [
            { _ = try await self.gateway().contratsEtablissement(context: sans) },
            { _ = try await self.gateway().contrat(id: self.id, etab: sans) },
            { _ = try await self.gateway().envoyerOtp(contratId: self.id, empreinte: self.empreinte, etab: sans) },
            { _ = try await self.gateway().signer(contratId: self.id, code: "123456", empreinte: self.empreinte, etab: sans) },
            { _ = try await self.gateway().certificat(contratId: self.id, etab: sans) },
        ]
        for appel in appels {
            let refus = await erreur(appel)
            XCTAssertEqual(refus as? RefusAccesEtablissement, RefusAccesEtablissement(message: ContratsEtablissement.messageRoleInsuffisant))
        }
        XCTAssertTrue(registry.requests.isEmpty, "fail-closed : aucune requête sans la permission servie")
        XCTAssertEqual(ContratsEtablissement.messageRoleInsuffisant, RPCInterception.messageRoleInsuffisant,
                       "même message neutre que le refus RBAC du serveur")
    }

    func testDetailBorneALEtablissementCompteTestSurEtablissementsSansMission() async throws {
        registry.add("GET", cheminTable, respond: .json(200, "[\(ligne())]"))
        registry.add("GET", "/rest/v1/etablissements", respond: .json(200, #"[{"id":"\#(etab)","est_compte_test":true}]"#))
        let contrat = try await gateway().contrat(id: id, etab: contexte())
        XCTAssertTrue(contrat.estCompteTest)
        XCTAssertNil(contrat.mission, "aucune lecture de la mission (montants, D15)")
        let lecture = try XCTUnwrap(registry.requests(to: cheminTable).first)
        XCTAssertEqual(lecture.query("id"), "eq.\(id)")
        XCTAssertEqual(lecture.query("etablissement_id"), "eq.\(etab)")
        XCTAssertEqual(lecture.query("select"), ContratDetail.selection)
        let compte = try XCTUnwrap(registry.requests(to: "/rest/v1/etablissements").first)
        XCTAssertEqual(compte.query("select"), "id,est_compte_test")
        XCTAssertEqual(compte.query("id"), "eq.\(etab)")
        XCTAssertEqual(registry.requests(to: "/rest/v1/missions").count, 0)
        XCTAssertEqual(registry.requests(to: "/rest/v1/soignants").count, 0)
    }

    func testContratDUnAutreEtablissementEstIntrouvable() async throws {
        registry.add("GET", cheminTable, respond: .json(200, "[\(ligne(etablissementId: "autre"))]"))
        let refus = await erreur { try await self.gateway().contrat(id: self.id, etab: self.contexte()) }
        XCTAssertEqual((refus as? JoleneError)?.message, MessagesContrats.indisponible)
    }

    func testCompteTestIllisibleFaitEchouerLeDetail() async throws {
        registry.add("GET", cheminTable, respond: .json(200, "[\(ligne())]"))
        registry.add("GET", "/rest/v1/etablissements", respond: .json(200, "[]"))
        let refus = await erreur { try await self.gateway().contrat(id: self.id, etab: self.contexte()) }
        XCTAssertNotNil(refus as? JoleneError, "fail-closed : sans relecture, ni OTP ni renvoi ne sont choisis")
    }

    // MARK: - Envoi du code

    private func stubEmpreinteActuelle(_ valeur: String? = nil) {
        registry.add("GET", cheminTable, where: { $0.query("select") == "id,hash_document" },
                     respond: .json(200, #"[{"id":"\#(id)","hash_document":"\#(valeur ?? empreinte)"}]"#))
    }

    func testEnvoiNumeroMasqueSeulementEtCleExacte() async throws {
        let client = try await connecte()
        stubEmpreinteActuelle()
        registry.add("POST", cheminEnvoi, respond: .json(200, """
        {"success":true,"role":"etablissement","telephone_masked":"+**********42","expire_dans_minutes":10,"sms_envoyes":1,"sms_restants":2}
        """))
        let issue = try await gateway(client).envoyerOtp(contratId: id, empreinte: empreinte, etab: contexte())
        XCTAssertEqual(issue, .envoye(OtpEnvoye(role: "etablissement", telephoneMasque: "+**********42", expireDansMinutes: 10,
                                                 smsEnvoyes: 1, smsRestants: 2)))
        let corps = try XCTUnwrap(registry.requests(to: cheminEnvoi).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps.keys.sorted(), ["p_contrat_id"], "aucun numéro de téléphone envoyé par l'app")
        XCTAssertEqual(registry.requests(to: cheminEnvoi).count, 1)
    }

    func testDocumentChangeAvantEnvoiAucunSms() async throws {
        let client = try await connecte()
        stubEmpreinteActuelle(String(repeating: "0", count: 64))
        let issue = try await gateway(client).envoyerOtp(contratId: id, empreinte: empreinte, etab: contexte())
        XCTAssertEqual(issue, .refuse(code: "HASH_DOCUMENT_CHANGE", message: TextesWeb.SignatureOtp.hashDocumentChange, bloquant: true))
        XCTAssertEqual(registry.requests(to: cheminEnvoi).count, 0)
    }

    func testRefusDEnvoiDuServeurTraduitsCommeLeWeb() async throws {
        let client = try await connecte()
        let g = gateway(client)
        let cas: [(String, String)] = [
            (#"{"success":false,"error_code":"NON_AUTORISE","error":"Non autorisé à signer ce contrat"}"#, TextesWeb.SignatureOtp.nonAutorise),
            (#"{"success":false,"error_code":"TELEPHONE_MANQUANT","error":"Numéro de téléphone manquant. Mettez à jour votre profil avant de signer."}"#,
             TextesWeb.SignatureOtp.telephoneManquant),
        ]
        for (corps, message) in cas {
            registry.reset()
            stubEmpreinteActuelle()
            registry.add("POST", cheminEnvoi, respond: .json(200, corps))
            let issue = try await g.envoyerOtp(contratId: id, empreinte: empreinte, etab: contexte())
            guard case let .refuse(code, recu, bloquant) = issue else { return XCTFail("refus attendu : \(issue)") }
            XCTAssertEqual(recu, message, code ?? "")
            XCTAssertEqual(bloquant, TextesWeb.SignatureOtp.codesBloquants.contains(code ?? ""))
            XCTAssertEqual(registry.requests(to: cheminEnvoi).count, 1, "jamais rejoué")
        }
    }

    // MARK: - Signature

    func testSignatureAnnonceeApresRelectureDeSignatureEtablissementLe() async throws {
        let client = try await connecte()
        registry.add("POST", cheminSignature, respond: .json(200, #"{"success":true,"role":"etablissement","contrat_complet":false}"#))
        registry.add("GET", cheminTable, respond: .json(200, "[\(ligne(signeEtab: true, signeLe: "2026-11-02T00:00:00+00:00", statut: "SIGNE_ETABLISSEMENT"))]"))
        registry.add("GET", cheminSignatures, respond: .json(200, "[\(preuve())]"))
        let issue = try await gateway(client).signer(contratId: id, code: "123456", empreinte: empreinte, etab: contexte())
        XCTAssertEqual(issue, .signee(contratComplet: false))
        let corps = try XCTUnwrap(registry.requests(to: cheminSignature).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps.keys.sorted(), ["p_contrat_id", "p_hash_document", "p_otp_code", "p_signature_image"])
        XCTAssertTrue(corps["p_signature_image"] is NSNull, "OTP seul, signature manuscrite non portée")
        XCTAssertEqual(registry.requests(to: cheminTable).first?.query("etablissement_id"), "eq.\(etab)")
    }

    func testSuccesSansSignatureEtablissementLeNiPreuveDuMembreNEstPasUnSucces() async throws {
        for (ligneRelue, preuves) in [(ligne(signeEtab: true, signeLe: nil), [preuve()]),
                                      (ligne(signeEtab: true, signeLe: "2026-11-02T00:00:00+00:00"), [preuve(role: "soignant")]),
                                      (ligne(signeEtab: true, signeLe: "2026-11-02T00:00:00+00:00"), [preuve(user: soignantId)])] {
            registry.reset()
            let client = try await connecte()
            registry.add("POST", cheminSignature, respond: .json(200, #"{"success":true,"role":"etablissement"}"#))
            registry.add("GET", cheminTable, respond: .json(200, "[\(ligneRelue)]"))
            registry.add("GET", cheminSignatures, respond: .json(200, "[\(preuves.joined(separator: ","))]"))
            let refus = await erreur {
                try await self.gateway(client).signer(contratId: self.id, code: "123456", empreinte: self.empreinte, etab: self.contexte())
            }
            XCTAssertEqual((refus as? JoleneError)?.message, SupabaseContratsGateway.messageSignatureNonConfirmee)
        }
    }

    func testCodeIncorrectAvecTentativesRestantesEtNonAutorise() async throws {
        let client = try await connecte()
        registry.add("POST", cheminSignature, respond: .json(200, """
        {"success":false,"error_code":"OTP_INCORRECT","error":"Code incorrect.","tentatives_restantes":3}
        """))
        let incorrect = try await gateway(client).signer(contratId: id, code: "111111", empreinte: empreinte, etab: contexte())
        XCTAssertEqual(incorrect, .refuse(code: "OTP_INCORRECT", message: TextesWeb.SignatureOtp.otpIncorrect, tentativesRestantes: 3))
        XCTAssertEqual(registry.requests(to: cheminSignatures).count, 0)

        registry.reset()
        let autre = try await connecte()
        registry.add("POST", cheminSignature, respond: .json(200, #"{"success":false,"error_code":"NON_AUTORISE","error":"Non autorisé à signer ce contrat"}"#))
        let refuse = try await gateway(autre).signer(contratId: id, code: "123456", empreinte: empreinte, etab: contexte())
        XCTAssertEqual(refuse, .refuse(code: "NON_AUTORISE", message: TextesWeb.SignatureOtp.nonAutorise, tentativesRestantes: nil))
    }

    func testEmpreinteInvalideAucuneRequete() async throws {
        let issue = try await gateway().signer(contratId: id, code: "123456", empreinte: "abc", etab: contexte())
        XCTAssertEqual(issue, ContratsEtablissement.refusSignatureOriginalChange)
        XCTAssertTrue(registry.requests.isEmpty)
    }
}
