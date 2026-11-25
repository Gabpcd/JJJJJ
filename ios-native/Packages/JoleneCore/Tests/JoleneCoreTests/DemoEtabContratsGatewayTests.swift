import XCTest
@testable import JoleneCore

/// Contrats de l'établissement démo (lot 5, T10) servis par le port des contrats du monde démo
/// (`DemoContratsGateway` → `DemoEtabContratsGateway`, fixture `demo-etab-contrats.json`) : permission `contrats`
/// exigée, contrats de l'établissement démo seulement, triple contrôle de l'original avant tout envoi et avant la
/// signature, OTP démo (`000000`), refus traduits comme le web, signature relue (`signature_etablissement_le`).
final class DemoEtabContratsGatewayTests: XCTestCase {
    private func contexte(_ role: RoleEtab = .rh, etablissementId: String = "demo-etab-1") throws -> EtablissementReadContext {
        let permissions = try XCTUnwrap(try DemoFixtures.loadPermissionsEtab().roles[role.brut])
        return EtablissementReadContext(userId: DemoEtablissementWorld.userId, etablissementId: etablissementId, roleEtab: role,
                                        permissions: permissions, epoch: 1)
    }

    private func port(_ scenario: ScenarioDemoContrats = .nominal) -> DemoContratsGateway {
        DemoContratsGateway(scenario: scenario)
    }

    private let aSigner = DemoEtabContratsGateway.contratASigner

    func testListeDesContratsDeLEtablissementDemo() async throws {
        let liste = try await port().contratsEtablissement(context: contexte())
        XCTAssertEqual(Set(liste.map(\.id)), [DemoEtabContratsGateway.contratASigner, DemoEtabContratsGateway.contratSigne])
        XCTAssertTrue(liste.allSatisfy { $0.etablissementId == "demo-etab-1" })
        let cartes = Dictionary(uniqueKeysWithValues: liste.map { ($0.id, EtabContratsPresentation.carte($0)) })
        XCTAssertEqual(cartes[aSigner]?.aSigner, true)
        XCTAssertEqual(cartes[DemoEtabContratsGateway.contratSigne]?.aSigner, false)
    }

    func testPointageOnlyEtLectureSeuleSansLaPermissionContrats() async throws {
        for role: RoleEtab in [.pointageOnly, .lectureSeule] {
            do {
                _ = try await port().contratsEtablissement(context: contexte(role))
                XCTFail("\(role) : refus attendu")
            } catch let refus as RefusAccesEtablissement {
                XCTAssertEqual(refus.message, ContratsEtablissement.messageRoleInsuffisant)
            }
        }
    }

    func testContratDUnAutreEtablissementIntrouvable() async throws {
        do {
            _ = try await port().contrat(id: aSigner, etab: contexte(etablissementId: "autre"))
            XCTFail("refus attendu")
        } catch {
            // Refus du monde démo (établissement fictif seulement) ou contrat introuvable : jamais un contrat servi.
        }
    }

    func testOriginalControleEnvoiPuisSignatureRelue() async throws {
        let port = port()
        let ctx = try contexte()
        let contrat = try await port.contrat(id: aSigner, etab: ctx)
        let original = try await port.original(contrat: contrat, etab: ctx)
        XCTAssertEqual(original.empreinte, contrat.hashDocument, "triple contrôle : empreinte de l'original = hash_document")

        // Autre empreinte que l'original contrôlé : aucun code envoyé, aucune signature.
        let autre = String(repeating: "0", count: 64)
        let refusEnvoi = try await port.envoyerOtp(contratId: aSigner, empreinte: autre, etab: ctx)
        XCTAssertEqual(refusEnvoi, ContratsEtablissement.refusEnvoiOriginalChange)
        let sansCode = try await port.signer(contratId: aSigner, code: "000000", empreinte: original.empreinte, etab: ctx)
        XCTAssertEqual(sansCode, .refuse(code: "OTP_NON_DEMANDE", message: TextesWeb.SignatureOtp.message(
            code: "OTP_NON_DEMANDE", erreurServeur: nil, repli: LibellesWeb.SignatureOtp.repliSignature), tentativesRestantes: nil))

        let envoi = try await port.envoyerOtp(contratId: aSigner, empreinte: original.empreinte, etab: ctx)
        guard case let .envoye(otp) = envoi else { return XCTFail("envoi attendu : \(envoi)") }
        XCTAssertEqual(otp.role, "etablissement")
        XCTAssertEqual(otp.telephoneMasque, DemoContratsGateway.telephoneMasque, "numéro masqué seulement")

        let mauvaiseEmpreinte = try await port.signer(contratId: aSigner, code: "000000", empreinte: autre, etab: ctx)
        XCTAssertEqual(mauvaiseEmpreinte, ContratsEtablissement.refusSignatureOriginalChange)
        let incorrect = try await port.signer(contratId: aSigner, code: "111111", empreinte: original.empreinte, etab: ctx)
        XCTAssertEqual(incorrect, .refuse(code: "OTP_INCORRECT", message: TextesWeb.SignatureOtp.otpIncorrect,
                                         tentativesRestantes: DemoContratsGateway.maxTentatives - 1))
        let signe = try await port.signer(contratId: aSigner, code: DemoContratsGateway.codeAccepte, empreinte: original.empreinte, etab: ctx)
        XCTAssertEqual(signe, .signee(contratComplet: false))

        let relu = try await port.contrat(id: aSigner, etab: ctx)
        XCTAssertEqual(relu.signatureEtablissement, true)
        XCTAssertNotNil(relu.signatureEtablissementLe, "signature_etablissement_le relu non nul")
        XCTAssertEqual(relu.statut, "SIGNE_ETABLISSEMENT")
        let preuves = try await port.certificat(contratId: aSigner, etab: ctx)
        XCTAssertTrue(preuves.contains { $0.signataireRole == "etablissement" && $0.hashDocument == original.empreinte })
        let deja = try await port.envoyerOtp(contratId: aSigner, empreinte: original.empreinte, etab: ctx)
        guard case .refuse(code: "DEJA_SIGNE", _, _) = deja else { return XCTFail("DEJA_SIGNE attendu : \(deja)") }
    }

    func testCddAPreparerSansOriginal() async throws {
        let port = port(.cddAPreparer)
        let ctx = try contexte()
        let contrat = try await port.contrat(id: aSigner, etab: ctx)
        XCTAssertTrue(ContratRules.cddSansOriginal(contrat))
        do {
            _ = try await port.original(contrat: contrat, etab: ctx)
            XCTFail("aucun original pour un CDD à préparer")
        } catch let refus as ContratOriginalIndisponible {
            XCTAssertEqual(refus.motif, .cddAPreparer)
        }
    }

    func testContratsDuSoignantDemoInchanges() async throws {
        // Le scénario de l'établissement n'altère jamais les contrats du soignant démo.
        let soignant = try await port(.cddAPreparer).contrats(context: DemoWorld.context)
        let nominal = try await port().contrats(context: DemoWorld.context)
        XCTAssertEqual(soignant, nominal)
    }
}
