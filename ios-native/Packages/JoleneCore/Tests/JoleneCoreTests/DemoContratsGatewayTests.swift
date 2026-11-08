import XCTest
@testable import JoleneCore

/// Lot 2, T8 — contrats du monde démo (`Demo/DemoContratsGateway.swift`, `LOT2_PLAN.md` §2.8) : fixtures de
/// `export-demo-fixtures.mjs` (`demo-contrats.json`, originaux rendus par le moteur serveur), OTP `000000`
/// accepté, `111111` → `OTP_INCORRECT` (4 restantes), scénario `otp-expire`, refus de tout autre compte
/// (`.demoOnly`), aucun réseau (sentinelle `DemoNoNetworkTests`).
final class DemoContratsGatewayTests: XCTestCase {
    private let contexte = DemoWorld.context

    func testListeDesTroisContratsDemo() async throws {
        let liste = try await DemoContratsGateway().contrats(context: contexte)
        XCTAssertEqual(liste.map(\.id), ["demo-contrat-003", "demo-contrat-001", "demo-contrat-002"], "cree_le décroissant (l.71)")
        XCTAssertEqual(liste.map(\.statut), ["EN_ATTENTE_SIGNATURES", "EN_ATTENTE_SIGNATURES", "SIGNE_COMPLET"])
        XCTAssertEqual(liste.first { $0.id == "demo-contrat-001" }?.mission?.intitule, "Démonstration · Mission assignée 1")
        XCTAssertTrue(liste.allSatisfy { $0.soignantId == contexte.userId })
    }

    func testContratEnAttenteAvecSoixanteDeuxHeuresRestantesEtOriginalControle() async throws {
        let gateway = DemoContratsGateway()
        let detail = try await gateway.contrat(id: "demo-contrat-001", context: contexte)
        XCTAssertEqual(detail.statut, "EN_ATTENTE_SIGNATURES", "statut réel (ListeContrats.tsx l.20)")
        XCTAssertEqual(CompteARebours72h.etat(creeLe: detail.creeLe, maintenant: DemoWorld.fixedNow).restantSecondes, 62 * 3600)
        XCTAssertEqual(detail.mission?.id, "demo-assignee-001")
        XCTAssertEqual(detail.etablissementNom, "Établissement fictif République")
        XCTAssertFalse(detail.estCompteTest)
        let original = try await gateway.original(contrat: detail, context: contexte)
        XCTAssertEqual(original.empreinte, detail.hashDocument)
        XCTAssertEqual(original.numeroContrat, "DEMO-0001")
        XCTAssertTrue(original.html.contains("data-jolene-cdd=\"employeur-v1\""), "rendu par rendreCddEmployeur")
        let admission = try await gateway.admissionRecette(contratId: detail.id, context: contexte)
        XCTAssertNil(admission, "jamais de recette STAGING en démo")
    }

    func testContratSigneAvecDeuxLignesDeCertificat() async throws {
        let gateway = DemoContratsGateway()
        let detail = try await gateway.contrat(id: "demo-contrat-002", context: contexte)
        XCTAssertEqual(detail.statut, "SIGNE_COMPLET")
        let certificat = try await gateway.certificat(contratId: detail.id, context: contexte)
        XCTAssertEqual(certificat.map(\.signataireRole), ["etablissement", "soignant"])
        XCTAssertTrue(certificat.allSatisfy { $0.hashDocument == detail.hashDocument && $0.statutSignature == "signe" })
        let original = try await gateway.original(contrat: detail, context: contexte)
        let fichier = try await gateway.fichierOriginal(contrat: original, context: contexte)
        defer { FichierContratTemporaire.effacer(fichier) }
        XCTAssertEqual(fichier.lastPathComponent, "Contrat-DEMO-0002.html")
        XCTAssertEqual(VerificationOriginal.empreinte(try String(contentsOf: fichier, encoding: .utf8)), detail.hashDocument)
    }

    func testCddSansOriginal() async throws {
        let gateway = DemoContratsGateway()
        let detail = try await gateway.contrat(id: "demo-contrat-003", context: contexte)
        XCTAssertTrue(ContratRules.cddSansOriginal(detail))
        do {
            _ = try await gateway.original(contrat: detail, context: contexte)
            XCTFail("aucun original pour un CDD à préparer")
        } catch let erreur as ContratOriginalIndisponible {
            XCTAssertEqual(erreur.motif, .cddAPreparer)
        }
    }

    func testOtpDemo() async throws {
        let gateway = DemoContratsGateway()
        let detail = try await gateway.contrat(id: "demo-contrat-001", context: contexte)
        let empreinte = try XCTUnwrap(detail.hashDocument)
        let avant = try await gateway.signer(contratId: detail.id, code: "000000", empreinte: empreinte, context: contexte)
        XCTAssertEqual(avant, .refuse(code: "OTP_NON_DEMANDE", message: TextesWeb.SignatureOtp.otpNonDemande, tentativesRestantes: nil))
        let envoi = try await gateway.envoyerOtp(contratId: detail.id, empreinte: empreinte, context: contexte)
        XCTAssertEqual(envoi, .envoye(OtpEnvoye(role: "soignant", telephoneMasque: "+**********00", expireDansMinutes: 10,
                                                 smsEnvoyes: 1, smsRestants: 2)))
        let faux = try await gateway.signer(contratId: detail.id, code: "111111", empreinte: empreinte, context: contexte)
        XCTAssertEqual(faux, .refuse(code: "OTP_INCORRECT", message: TextesWeb.SignatureOtp.otpIncorrect, tentativesRestantes: 4))
        let autreRevision = try await gateway.signer(contratId: detail.id, code: "000000", empreinte: String(repeating: "0", count: 64),
                                                     context: contexte)
        XCTAssertEqual(autreRevision, .refuse(code: "HASH_DOCUMENT_CHANGE", message: TextesWeb.SignatureOtp.hashDocumentChange,
                                              tentativesRestantes: nil))
        let signe = try await gateway.signer(contratId: detail.id, code: "000000", empreinte: empreinte, context: contexte)
        XCTAssertEqual(signe, .signee(contratComplet: false))
        let relu = try await gateway.contrat(id: detail.id, context: contexte)
        XCTAssertEqual(relu.signatureSoignant, true, "relecture après signature")
        XCTAssertEqual(relu.signatureSoignantLe, "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(relu.statut, "SIGNE_SOIGNANT")
        let certificat = try await gateway.certificat(contratId: detail.id, context: contexte)
        XCTAssertEqual(certificat.map(\.statutSignature), ["signe"])
        let encore = try await gateway.envoyerOtp(contratId: detail.id, empreinte: empreinte, context: contexte)
        XCTAssertEqual(encore, .refuse(code: "DEJA_SIGNE", message: TextesWeb.SignatureOtp.dejaSigne, bloquant: true))
        let autreMonde = try await DemoContratsGateway().contrat(id: detail.id, context: contexte)
        XCTAssertEqual(autreMonde.signatureSoignant, false, "chaque gateway démo repart des fixtures")
    }

    func testCinqCodesFauxPuisTropDeTentativesEtPlafondDeSms() async throws {
        let gateway = DemoContratsGateway()
        let lu = try await gateway.contrat(id: "demo-contrat-001", context: contexte)
        let empreinte = try XCTUnwrap(lu.hashDocument)
        _ = try await gateway.envoyerOtp(contratId: "demo-contrat-001", empreinte: empreinte, context: contexte)
        var restantes: [Int?] = []
        for _ in 0..<5 {
            if case .refuse(_, _, let n) = try await gateway.signer(contratId: "demo-contrat-001", code: "222222",
                                                                    empreinte: empreinte, context: contexte) { restantes.append(n) }
        }
        XCTAssertEqual(restantes, [4, 3, 2, 1, 0])
        let bloque = try await gateway.signer(contratId: "demo-contrat-001", code: "000000", empreinte: empreinte, context: contexte)
        XCTAssertEqual(bloque, .refuse(code: "TROP_DE_TENTATIVES", message: TextesWeb.SignatureOtp.tropDeTentatives, tentativesRestantes: nil))
        _ = try await gateway.envoyerOtp(contratId: "demo-contrat-001", empreinte: empreinte, context: contexte)
        let troisieme = try await gateway.envoyerOtp(contratId: "demo-contrat-001", empreinte: empreinte, context: contexte)
        XCTAssertEqual(troisieme, .envoye(OtpEnvoye(role: "soignant", telephoneMasque: "+**********00", expireDansMinutes: 10,
                                                     smsEnvoyes: 3, smsRestants: 0)))
        let quatrieme = try await gateway.envoyerOtp(contratId: "demo-contrat-001", empreinte: empreinte, context: contexte)
        XCTAssertEqual(quatrieme, .refuse(code: "TROP_DE_SMS", message: TextesWeb.SignatureOtp.tropDeSms, bloquant: true))
    }

    func testScenarioOtpExpire() async throws {
        let gateway = DemoContratsGateway(scenario: .otpExpire)
        let lu = try await gateway.contrat(id: "demo-contrat-001", context: contexte)
        let empreinte = try XCTUnwrap(lu.hashDocument)
        _ = try await gateway.envoyerOtp(contratId: "demo-contrat-001", empreinte: empreinte, context: contexte)
        let issue = try await gateway.signer(contratId: "demo-contrat-001", code: "000000", empreinte: empreinte, context: contexte)
        XCTAssertEqual(issue, .refuse(code: "OTP_EXPIRE", message: TextesWeb.SignatureOtp.otpExpire, tentativesRestantes: nil))
        XCTAssertEqual(ScenarioDemoContrats(argument: "otp-expire"), .otpExpire)
        XCTAssertEqual(ScenarioDemoContrats(argument: "autre"), .nominal)
    }

    func testContratSigneRefuseLEnvoiEtContratInconnu() async throws {
        let gateway = DemoContratsGateway()
        let signe = try await gateway.contrat(id: "demo-contrat-002", context: contexte)
        let envoi = try await gateway.envoyerOtp(contratId: signe.id, empreinte: try XCTUnwrap(signe.hashDocument), context: contexte)
        XCTAssertEqual(envoi, .refuse(code: "CONTRAT_DEJA_COMPLET", message: TextesWeb.SignatureOtp.contratDejaComplet, bloquant: true))
        do {
            _ = try await gateway.contrat(id: "inconnu", context: contexte)
            XCTFail("contrat inconnu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.message, MessagesContrats.indisponible)
        }
    }

    func testToutAutreCompteEstRefuse() async {
        var autre = contexte
        autre.userId = "u-reel"
        autre.profile.id = "u-reel"
        let gateway = DemoContratsGateway()
        do {
            _ = try await gateway.contrats(context: autre)
            XCTFail("la démo n'est jamais un repli pour un compte réel")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        } catch {
            XCTFail("\(error)")
        }
    }
}
