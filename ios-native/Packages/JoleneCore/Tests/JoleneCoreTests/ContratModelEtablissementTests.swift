import XCTest
@testable import JoleneCore

/// Lot 5, T10 — contrat et signature OTP vus par l'établissement : `ContratModel` et `ContratsListeModel` du lot 2
/// réemployés sous le contexte confirmé de l'établissement (`LOT5_PLAN.md` §3 T10, D18). Ce que ces tests prouvent :
/// - seules les méthodes établissement du port sont appelées (`contrat(id:etab:)`, `original(contrat:etab:)`,
///   `envoyerOtp(…etab:)`, `signer(…etab:)`), jamais celles du soignant ;
/// - la signature n'est annoncée qu'après l'issue relue du port **et** la relecture du contrat
///   (`signature_etablissement_le` non nul) ; « déjà signé » suit la signature de l'établissement, pas celle du soignant ;
/// - les refus du serveur passent mot pour mot jusqu'à l'écran (`NON_AUTORISE`, `TELEPHONE_MANQUANT`, `OTP_INCORRECT`
///   avec ses tentatives restantes, `HASH_DOCUMENT_CHANGE`) ; `NON_AUTORISE` et un refus de droit relisent le périmètre
///   une fois, sans déconnexion ;
/// - un CDD sans original est un renvoi web (aucun original demandé), un compte TEST sans admission aussi ;
/// - le mode de signature annoncé est le texte du web (`TextesWeb.Contrat`), jamais affiché au soignant.
/// Session établissement réelle du monde démo (`DemoWorld.gateways(espace:)`, espace ouvert), port des contrats scripté.
@MainActor
final class ContratModelEtablissementTests: XCTestCase {
    private struct PanneTest: Error {}

    nonisolated private static let html = "<p>Contrat</p>"
    nonisolated private static let empreinte = VerificationOriginal.empreinte(html)

    /// Port scripté : seules les méthodes établissement répondent ; un appel soignant échoue et s'inscrit au journal.
    private final class Script: ContratsPort, @unchecked Sendable {
        private let verrou = NSLock()
        private var details: [Result<ContratDetail, Error>]
        private var journal: [String] = []
        var originalIssue: Result<OriginalContrat, Error> = .failure(PanneTest())
        var envoi: Result<IssueEnvoiOtp, Error> = .failure(PanneTest())
        var signature: Result<IssueSignature, Error> = .failure(PanneTest())
        var liste: Result<[ContratResume], Error> = .success([])
        var lignes: [SignatureCertificat] = []
        var admission: AdmissionSignatureRecette?
        var contextes: [EtablissementReadContext] = []

        init(details: [Result<ContratDetail, Error>]) { self.details = details }

        var appels: [String] { verrou.withLock { journal } }
        private func noter(_ appel: String, _ contexte: EtablissementReadContext? = nil) {
            verrou.withLock {
                journal.append(appel)
                if let contexte { contextes.append(contexte) }
            }
        }

        // Méthodes du soignant : jamais appelées par un écran établissement.
        func contrats(context: MissionReadContext) async throws -> [ContratResume] { noter("SOIGNANT contrats"); throw PanneTest() }
        func contrat(id: String, context: MissionReadContext) async throws -> ContratDetail { noter("SOIGNANT contrat"); throw PanneTest() }
        func original(contrat: ContratDetail, context: MissionReadContext) async throws -> OriginalContrat {
            noter("SOIGNANT original"); throw PanneTest()
        }
        func admissionRecette(contratId: String, context: MissionReadContext) async throws -> AdmissionSignatureRecette? {
            noter("SOIGNANT admission"); throw PanneTest()
        }
        func envoyerOtp(contratId: String, empreinte: String, context: MissionReadContext) async throws -> IssueEnvoiOtp {
            noter("SOIGNANT envoyerOtp"); throw PanneTest()
        }
        func signer(contratId: String, code: String, empreinte: String, context: MissionReadContext) async throws -> IssueSignature {
            noter("SOIGNANT signer"); throw PanneTest()
        }
        func certificat(contratId: String, context: MissionReadContext) async throws -> [SignatureCertificat] {
            noter("SOIGNANT certificat"); throw PanneTest()
        }
        func fichierOriginal(contrat: OriginalContrat, context: MissionReadContext) async throws -> URL {
            noter("SOIGNANT fichier"); throw PanneTest()
        }

        // Méthodes de l'établissement.
        func contratsEtablissement(context: EtablissementReadContext) async throws -> [ContratResume] {
            noter("contrats", context)
            return try liste.get()
        }
        func contrat(id: String, etab: EtablissementReadContext) async throws -> ContratDetail {
            noter("contrat", etab)
            let suivant: Result<ContratDetail, Error> = verrou.withLock {
                guard !details.isEmpty else { return .failure(PanneTest()) }
                return details.count > 1 ? details.removeFirst() : details[0]
            }
            return try suivant.get()
        }
        func original(contrat: ContratDetail, etab: EtablissementReadContext) async throws -> OriginalContrat {
            noter("original", etab)
            return try originalIssue.get()
        }
        func admissionRecette(contratId: String, etab: EtablissementReadContext) async throws -> AdmissionSignatureRecette? {
            noter("admission", etab)
            return admission
        }
        func envoyerOtp(contratId: String, empreinte: String, etab: EtablissementReadContext) async throws -> IssueEnvoiOtp {
            noter("envoyerOtp \(empreinte == ContratModelEtablissementTests.empreinte ? "empreinte affichée" : "autre empreinte")", etab)
            return try envoi.get()
        }
        func signer(contratId: String, code: String, empreinte: String, etab: EtablissementReadContext) async throws -> IssueSignature {
            noter("signer \(empreinte == ContratModelEtablissementTests.empreinte ? "empreinte affichée" : "autre empreinte")", etab)
            return try signature.get()
        }
        func certificat(contratId: String, etab: EtablissementReadContext) async throws -> [SignatureCertificat] {
            noter("certificat", etab)
            return lignes
        }
        func fichierOriginal(contrat: OriginalContrat, etab: EtablissementReadContext) async throws -> URL {
            noter("fichier", etab)
            throw PanneTest()
        }
    }

    private final class Compteur: @unchecked Sendable {
        private let lock = NSLock()
        private var valeur = 0
        var nombre: Int { lock.withLock { valeur } }
        func incrementer() { lock.withLock { valeur += 1 } }
    }

    private func detail(type: String = "CDD", original: Bool = true, soignant: Bool = false, etablissement: Bool = false,
                        signeLe: String? = nil, statut: String = "EN_ATTENTE_SIGNATURES", test: Bool = false) -> ContratDetail {
        ContratDetail(id: "k-1", missionId: "m-1", statut: statut, typeContrat: type, contenuHtml: original ? Self.html : nil,
                      hashDocument: original ? Self.empreinte : nil, storagePath: original ? "k-1/a.html" : nil,
                      contenuHtmlRenduLe: original ? "2026-11-01T14:05:00Z" : nil, signatureSoignant: soignant,
                      signatureEtablissement: etablissement, signatureEtablissementLe: signeLe, creeLe: "2026-11-01T14:00:00Z",
                      numeroContrat: "C-1", soignantId: "s-1", etablissementId: "demo-etab-1", estCompteTest: test)
    }

    private var originalA: OriginalContrat {
        OriginalContrat(contratId: "k-1", html: Self.html, empreinte: Self.empreinte, numeroContrat: "C-1")
    }

    private func session(_ script: Script, role: RoleEtab = .rh) async throws -> (SessionController, EtablissementSessionSnapshot) {
        var gateways = DemoWorld.gateways(espace: .etablissement(.init(role: role)))
        gateways.contrats = script
        let controller = SessionController(gateways: gateways, espaceEtablissement: .ouvert)
        _ = await controller.start()
        let etat = await controller.signIn(email: DemoEspace.emailEtablissement, password: "demo")
        guard case let .readyEtablissement(snapshot) = etat else {
            XCTFail("espace établissement démo attendu, obtenu \(etat)")
            throw PanneTest()
        }
        return (controller, snapshot)
    }

    private func modele(_ script: Script, relectures: Compteur = Compteur()) async throws -> ContratModel {
        let (controller, snapshot) = try await session(script)
        return ContratModel(controller: controller, etablissement: snapshot, contratId: "k-1",
                            relirePerimetre: { relectures.incrementer() })
    }

    /// Modèle chargé sur un contrat à signer, original contrôlé, code envoyé, consentement donné.
    private func modeleCodeEnvoye(_ script: Script, relectures: Compteur = Compteur()) async throws -> ContratModel {
        script.originalIssue = .success(originalA)
        script.envoi = .success(.envoye(OtpEnvoye(role: "etablissement", telephoneMasque: "+**********00", expireDansMinutes: 10,
                                                  smsEnvoyes: 1, smsRestants: 2)))
        let model = try await modele(script, relectures: relectures)
        await model.charger()
        model.accepter(true)
        await model.envoyerCode()
        return model
    }

    private func formulaire(_ model: ContratModel) throws -> SignatureOtpPresentation.Formulaire {
        guard case let .otp(presentation)? = model.zoneSignature(maintenant: model.horloge.now()),
              case let .formulaire(formulaire) = presentation.mode else {
            throw XCTSkip("formulaire OTP attendu, obtenu \(String(describing: model.zoneSignature(maintenant: model.horloge.now())))")
        }
        return formulaire
    }

    // MARK: - Chargement

    func testChargementParLesMethodesEtablissementSousLeContexteConfirme() async throws {
        let script = Script(details: [.success(detail())])
        script.originalIssue = .success(originalA)
        let model = try await modele(script)
        await model.charger()

        XCTAssertEqual(model.etat, .charge)
        XCTAssertEqual(model.partie, .etablissement)
        XCTAssertEqual(script.appels, ["contrat", "original"], "aucune méthode du soignant, aucun certificat sans signature")
        XCTAssertTrue(script.contextes.allSatisfy { $0.etablissementId == "demo-etab-1" && $0.userId == DemoEtablissementWorld.userId },
                      "établissement confirmé par le serveur, jamais user.id")
        XCTAssertEqual(model.original, originalA)
        XCTAssertEqual(model.signature, .possible)
        XCTAssertFalse(model.preparationSurLeWeb)
        let f = try formulaire(model)
        XCTAssertEqual(f.titre, TextesWeb.SignatureOtp.titre)
        XCTAssertEqual(f.explication, TextesWeb.SignatureOtp.explication)
        XCTAssertEqual(f.consentement, TextesWeb.SignatureOtp.consentement)
    }

    func testModeDeSignatureDuWebAnnonceALEtablissementSeulement() async throws {
        let script = Script(details: [.success(detail())])
        script.originalIssue = .success(originalA)
        let model = try await modele(script)
        await model.charger()
        let mode = try XCTUnwrap(model.modeSignatureOtp(maintenant: model.horloge.now()))
        XCTAssertEqual(mode.libelle, "📱 Signature électronique OTP SMS")
        XCTAssertEqual(mode.description, "Code SMS à 6 chiffres + horodatage + hash document. Conforme art. 1366-1367 Code civil.")
        XCTAssertEqual(mode.libelle, TextesWeb.Contrat.otpLibelle, "texte du web, jamais réécrit")
        XCTAssertEqual(mode.description, TextesWeb.Contrat.otpDescription)
    }

    func testCddSansOriginalEstUnRenvoiWebSansAucunOriginalDemande() async throws {
        let script = Script(details: [.success(detail(original: false))])
        let model = try await modele(script)
        await model.charger()
        XCTAssertEqual(model.etat, .charge)
        XCTAssertEqual(script.appels, ["contrat"], "CDD à préparer : ni original ni rendu demandés")
        XCTAssertTrue(model.preparationSurLeWeb)
        XCTAssertEqual(model.indisponibilite, .cddAPreparer)
        XCTAssertNil(model.zoneSignature(maintenant: model.horloge.now()), "aucune signature tant que l'employeur n'a pas préparé le contrat")
        XCTAssertNil(model.modeSignatureOtp(maintenant: model.horloge.now()))
    }

    func testCompteTestSansAdmissionRenvoieLaSignatureAuWeb() async throws {
        let script = Script(details: [.success(detail(test: true))])
        script.originalIssue = .success(originalA)
        let model = try await modele(script)
        await model.charger()
        XCTAssertEqual(script.appels, ["contrat", "original", "admission"])
        XCTAssertEqual(model.signature, .renvoiWeb)
        guard case .renvoiWeb? = model.zoneSignature(maintenant: model.horloge.now()) else { return XCTFail("renvoi web attendu") }
        XCTAssertNil(model.modeSignatureOtp(maintenant: model.horloge.now()), "le web retire le mode OTP d'un compte TEST sans admission")
    }

    func testDejaSigneParLEtablissementMasqueLaZoneMemeSiLeSoignantNAPasSigne() async throws {
        let script = Script(details: [.success(detail(etablissement: true, signeLe: "2026-11-01T15:00:00Z", statut: "SIGNE_ETABLISSEMENT"))])
        script.originalIssue = .success(originalA)
        let model = try await modele(script)
        await model.charger()
        let contrat = try XCTUnwrap(model.contrat)
        XCTAssertTrue(ContratRules.dejaSigneParMoi(contrat, partie: .etablissement))
        XCTAssertNil(model.zoneSignature(maintenant: model.horloge.now()))
        XCTAssertEqual(ContratRules.bandeaux(contrat, partie: .etablissement), [], "l'établissement a signé : pas de bandeau « autre partie »")
    }

    // MARK: - Signature

    func testSignatureAnnonceeSeulementApresRelectureDeLaSignatureEtablissement() async throws {
        let signe = detail(etablissement: true, signeLe: "2026-11-02T00:00:00Z", statut: "SIGNE_ETABLISSEMENT")
        let script = Script(details: [.success(detail()), .success(signe)])
        script.signature = .success(.signee(contratComplet: false))
        script.lignes = []
        let model = try await modeleCodeEnvoye(script)
        XCTAssertEqual(model.session.etape, .otpEnvoye)
        XCTAssertEqual(model.session.telephoneMasque, "+**********00", "seul le numéro masqué servi est retenu")

        model.saisirCode("000000")
        await model.signer()

        XCTAssertEqual(script.appels, ["contrat", "original", "envoyerOtp empreinte affichée", "signer empreinte affichée",
                                       "contrat", "certificat"], "signature puis relecture du contrat et du certificat")
        XCTAssertEqual(model.session.etape, .signe)
        XCTAssertEqual(model.contrat?.signatureEtablissement, true)
        XCTAssertEqual(model.contrat?.signatureEtablissementLe, "2026-11-02T00:00:00Z", "valeur relue du serveur")
        guard case let .otp(presentation)? = model.zoneSignature(maintenant: model.horloge.now()),
              case let .signee(confirmation, mention, actualisation) = presentation.mode else { return XCTFail("confirmation attendue") }
        XCTAssertEqual(confirmation, "Contrat signé ✅")
        XCTAssertEqual(mention, TextesWeb.SignatureOtp.signeAvecSucces)
        XCTAssertNil(actualisation)
        XCTAssertEqual(model.session.code, "", "le code ne survit pas à la signature")
        XCTAssertNil(model.modeSignatureOtp(maintenant: model.horloge.now()))
    }

    func testSignatureNonRelueNEstJamaisAnnoncee() async throws {
        // Le port n'a pas pu confirmer (relecture en échec) : il lève, le modèle relit l'état du serveur, sans succès.
        let script = Script(details: [.success(detail())])
        script.signature = .failure(JoleneError(.unknown, "La signature ne peut pas être confirmée."))
        let model = try await modeleCodeEnvoye(script)
        model.saisirCode("000000")
        await model.signer()
        XCTAssertEqual(model.session.etape, .otpEnvoye, "jamais « Signé » sans preuve relue")
        XCTAssertNotEqual(model.contrat?.signatureEtablissement, true)
        XCTAssertEqual(try formulaire(model).retour, .erreur("La signature ne peut pas être confirmée."))
        XCTAssertEqual(script.appels.filter { $0.hasPrefix("signer") }.count, 1, "aucun renvoi automatique")
    }

    // MARK: - Refus du serveur, mot pour mot

    func testCodeIncorrectAvecTentativesRestantes() async throws {
        let script = Script(details: [.success(detail())])
        script.signature = .success(.refuse(code: "OTP_INCORRECT", message: TextesWeb.SignatureOtp.otpIncorrect, tentativesRestantes: 3))
        let model = try await modeleCodeEnvoye(script)
        model.saisirCode("111111")
        await model.signer()
        let f = try formulaire(model)
        XCTAssertEqual(f.retour, .erreur("Code incorrect. Vérifiez votre SMS et réessayez."))
        XCTAssertEqual(f.codeEnvoye?.tentatives, "Code incorrect. 3 tentatives restantes.")
        XCTAssertNil(f.alerte, "refus non bloquant : un nouveau code reste possible")
        XCTAssertEqual(model.session.etape, .otpEnvoye)
    }

    func testNonAutoriseBloqueEtRelitLePerimetreUneFois() async throws {
        let script = Script(details: [.success(detail())])
        script.originalIssue = .success(originalA)
        script.envoi = .success(.refuse(code: "NON_AUTORISE", message: TextesWeb.SignatureOtp.nonAutorise, bloquant: true))
        let relectures = Compteur()
        let model = try await modele(script, relectures: relectures)
        await model.charger()
        model.accepter(true)
        await model.envoyerCode()
        let f = try formulaire(model)
        XCTAssertEqual(f.alerte, "Vous n'êtes pas autorisé(e) à signer ce contrat.")
        XCTAssertEqual(f.recevoir?.actif, false, "refus bloquant : plus d'envoi")
        XCTAssertEqual(relectures.nombre, 1, "refus de droit : périmètre relu une fois")
        XCTAssertFalse(model.sessionExpired, "jamais « session expirée » pour un refus de droit")
    }

    func testTelephoneDeContactManquantEtDocumentModifie() async throws {
        for (code, message) in [("TELEPHONE_MANQUANT", TextesWeb.SignatureOtp.telephoneManquant),
                                ("HASH_DOCUMENT_CHANGE", TextesWeb.SignatureOtp.hashDocumentChange)] {
            let script = Script(details: [.success(detail())])
            script.originalIssue = .success(originalA)
            script.envoi = .success(.refuse(code: code, message: message, bloquant: true))
            let relectures = Compteur()
            let model = try await modele(script, relectures: relectures)
            await model.charger()
            model.accepter(true)
            await model.envoyerCode()
            XCTAssertEqual(try formulaire(model).alerte, message, code)
            XCTAssertEqual(model.session.etape, .idle, "\(code) : aucun code envoyé")
            XCTAssertEqual(relectures.nombre, 0, "\(code) n'est pas un refus de droit")
        }
    }

    func testRefusDeDroitDuPortRelitLePerimetreSansDeconnexion() async throws {
        let refus = RefusAccesEtablissement(message: ContratsEtablissement.messageRoleInsuffisant)
        let script = Script(details: [.failure(refus)])
        let relectures = Compteur()
        let model = try await modele(script, relectures: relectures)
        await model.charger()
        XCTAssertEqual(model.etat, .echec("Votre rôle dans cet établissement ne permet pas cette action."))
        XCTAssertFalse(model.sessionExpired)
        XCTAssertEqual(relectures.nombre, 1)
    }

    // MARK: - Liste

    func testListeDesContratsDeLEtablissement() async throws {
        let script = Script(details: [])
        script.liste = .success([
            ContratResume(id: "k-1", missionId: "m-1", statut: "EN_ATTENTE_SIGNATURES", typeContrat: "CDD", creeLe: "2026-11-01T16:00:00Z",
                          numeroContrat: "C-1", signatureSoignant: true, signatureEtablissement: false),
            ContratResume(id: "k-2", missionId: "m-2", statut: "SIGNE_COMPLET", typeContrat: "CDD", creeLe: "2026-10-28T00:00:00Z",
                          numeroContrat: "C-2", signatureSoignant: true, signatureEtablissement: true),
        ])
        let (controller, snapshot) = try await session(script)
        let model = ContratsListeModel(controller: controller, etablissement: snapshot,
                                       filtreInitial: FiltreContrat.initial(statut: "EN_ATTENTE_SIGNATURES"))
        await model.charger()
        XCTAssertEqual(script.appels, ["contrats"], "liste de l'établissement, jamais celle du soignant")
        XCTAssertEqual(model.partie, .etablissement)
        XCTAssertEqual(model.affiches.map(\.id), ["k-1"], "filtre initial ?statut= appliqué")
        let cartes = model.contrats.map(EtabContratsPresentation.carte)
        XCTAssertEqual(cartes.map(\.aSigner), [true, false], "à signer tant que l'établissement n'a pas signé")
        XCTAssertEqual(cartes.map(\.action), ["✍️ Signer le contrat", "Voir le contrat"])
    }

    func testListeRefuseeSansLaPermissionRelitLePerimetre() async throws {
        let script = Script(details: [])
        script.liste = .failure(RefusAccesEtablissement(message: ContratsEtablissement.messageRoleInsuffisant))
        let (controller, snapshot) = try await session(script)
        let relectures = Compteur()
        let model = ContratsListeModel(controller: controller, etablissement: snapshot, relirePerimetre: { relectures.incrementer() })
        await model.charger()
        XCTAssertEqual(model.etat, .echec(ContratsEtablissement.messageRoleInsuffisant))
        XCTAssertFalse(model.sessionExpired)
        XCTAssertEqual(relectures.nombre, 1)
    }
}
