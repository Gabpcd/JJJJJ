import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurContrats = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                    emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                    appMetadataRole: "SOIGNANT")

/// Lot 2, T8 — modèles `@MainActor` des contrats (`Contrats/ContratModel.swift`, `ContratsListeModel.swift`) :
/// chargement du contrat puis de son original contrôlé (rendu serveur relu, CDD sans original jamais
/// demandé), certificat, admission de recette d'un compte TEST (renvoi web sans admission, décision 18),
/// session OTP pilotée par le port (un envoi à la fois, relecture après signature), session expirée,
/// annulation jamais affichée en erreur, épuisement du délai `resolutionTimeout`.
@MainActor
final class ContratModelTests: XCTestCase {
    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurContrats }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw nonScripte }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    private static let html = "<p>Contrat</p>"
    private static let empreinte = VerificationOriginal.empreinte(html)
    private static let maintenant = DemoWorld.fixedNow

    /// Port scripté : chaque méthode rend la valeur posée par le test et compte ses appels.
    private actor PortScripte: ContratsPort {
        var details: [ContratDetail] = []
        var original: Result<OriginalContrat, Error> = .failure(nonScripte)
        var admission: AdmissionSignatureRecette?
        var envoi: Result<IssueEnvoiOtp, Error> = .failure(nonScripte)
        var signature: Result<IssueSignature, Error> = .failure(nonScripte)
        var certificatLignes: [SignatureCertificat] = []
        var certificatErreur: Error?
        var liste: Result<[ContratResume], Error> = .success([])
        var attenteEnvoi: Duration = .zero
        private(set) var appels: [String] = []

        func poser(details: [ContratDetail]) { self.details = details }
        func poser(original: Result<OriginalContrat, Error>) { self.original = original }
        func poser(admission: AdmissionSignatureRecette?) { self.admission = admission }
        func poser(envoi: Result<IssueEnvoiOtp, Error>, attente: Duration = .zero) { self.envoi = envoi; attenteEnvoi = attente }
        func poser(signature: Result<IssueSignature, Error>) { self.signature = signature }
        func poser(certificat: [SignatureCertificat], erreur: Error? = nil) { certificatLignes = certificat; certificatErreur = erreur }
        func poser(liste: Result<[ContratResume], Error>) { self.liste = liste }
        func compte(_ nom: String) -> Int { appels.filter { $0 == nom }.count }

        func contrats(context: MissionReadContext) async throws -> [ContratResume] {
            appels.append("contrats"); return try liste.get()
        }
        func contrat(id: String, context: MissionReadContext) async throws -> ContratDetail {
            appels.append("contrat")
            guard !details.isEmpty else { throw nonScripte }
            return details.count > 1 ? details.removeFirst() : details[0]
        }
        func original(contrat: ContratDetail, context: MissionReadContext) async throws -> OriginalContrat {
            appels.append("original"); return try original.get()
        }
        func admissionRecette(contratId: String, context: MissionReadContext) async throws -> AdmissionSignatureRecette? {
            appels.append("admission"); return admission
        }
        func envoyerOtp(contratId: String, empreinte: String, context: MissionReadContext) async throws -> IssueEnvoiOtp {
            appels.append("envoyerOtp")
            if attenteEnvoi > .zero { try await Task.sleep(for: attenteEnvoi) }
            return try envoi.get()
        }
        func signer(contratId: String, code: String, empreinte: String, context: MissionReadContext) async throws -> IssueSignature {
            appels.append("signer:\(code)"); return try signature.get()
        }
        func certificat(contratId: String, context: MissionReadContext) async throws -> [SignatureCertificat] {
            appels.append("certificat")
            if let certificatErreur { throw certificatErreur }
            return certificatLignes
        }
        func fichierOriginal(contrat: OriginalContrat, context: MissionReadContext) async throws -> URL {
            appels.append("fichier"); throw nonScripte
        }
    }

    private func pret(_ port: PortScripte, timeout: TimeInterval = SessionController.defaultResolutionTimeout)
        async throws -> (SessionController, SessionSnapshot) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: FixedClock(Self.maintenant))
        gateways.contrats = port
        let controller = SessionController(gateways: gateways, resolutionTimeout: timeout)
        let state = await controller.start()
        return (controller, try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)"))
    }

    private func detail(type: String = "CDDU", chemin: String? = "k-1/a.html", soignant: Bool? = false,
                        etablissement: Bool? = false, test: Bool = false, statut: String = "EN_ATTENTE_SIGNATURES") -> ContratDetail {
        ContratDetail(id: "k-1", missionId: "m-1", statut: statut, typeContrat: type, contenuHtml: chemin == nil ? nil : Self.html,
                      hashDocument: chemin == nil ? nil : Self.empreinte, storagePath: chemin,
                      contenuHtmlRenduLe: chemin == nil ? nil : "2026-11-01T14:05:00Z", signatureSoignant: soignant,
                      signatureEtablissement: etablissement, creeLe: "2026-11-01T14:00:00Z", numeroContrat: "C-1",
                      soignantId: "u-1", estCompteTest: test)
    }

    private var originalA: OriginalContrat {
        OriginalContrat(contratId: "k-1", html: Self.html, empreinte: Self.empreinte, numeroContrat: "C-1")
    }

    private func modele(_ port: PortScripte) async throws -> ContratModel {
        let (controller, snapshot) = try await pret(port)
        return ContratModel(controller: controller, snapshot: snapshot, contratId: "k-1")
    }

    // MARK: - Chargement

    func testChargementNominalPoseLaCleDeLaSessionSurLOriginalControle() async throws {
        let port = PortScripte()
        await port.poser(details: [detail()])
        await port.poser(original: .success(originalA))
        let model = try await modele(port)
        XCTAssertEqual(model.etat, .chargement)
        await model.charger()
        XCTAssertEqual(model.etat, .charge)
        XCTAssertEqual(model.original, originalA)
        XCTAssertNil(model.indisponibilite)
        XCTAssertEqual(model.session.cle, CleSessionOtp(contratId: "k-1", empreinte: Self.empreinte, documentPret: true))
        XCTAssertEqual(model.signature, .possible)
        let appels = await port.appels
        XCTAssertEqual(appels, ["contrat", "original"], "ni certificat (aucune signature), ni admission (compte réel)")
    }

    func testCddSansOriginalNeDemandeJamaisLOriginal() async throws {
        let port = PortScripte()
        await port.poser(details: [detail(type: "CDD", chemin: nil)])
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.etat, .charge)
        XCTAssertEqual(model.indisponibilite, .cddAPreparer)
        XCTAssertNil(model.original)
        XCTAssertEqual(model.signature, .indisponible)
        XCTAssertEqual(model.session.cle.documentPret, false)
        let appelsOriginal = await port.compte("original")
        XCTAssertEqual(appelsOriginal, 0, "décision 19 : aucune action soignant, aucun rendu")
    }

    func testOriginalIndisponibleLaisseLeContratLisibleSansSignature() async throws {
        let port = PortScripte()
        await port.poser(details: [detail()])
        await port.poser(original: .failure(ContratOriginalIndisponible(motif: .storageMismatch)))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.etat, .charge)
        XCTAssertEqual(model.indisponibilite, .storageMismatch)
        XCTAssertEqual(model.signature, .indisponible)
        XCTAssertFalse(model.session.peutEnvoyer())
    }

    func testRenduServeurPuisRelectureDuContrat() async throws {
        let port = PortScripte()
        await port.poser(details: [detail(chemin: nil), detail()])
        await port.poser(original: .success(originalA))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.contrat?.storagePath, "k-1/a.html", "contrat relu après le rendu serveur")
        XCTAssertEqual(model.original, originalA)
        let appels = await port.appels
        XCTAssertEqual(appels, ["contrat", "original", "contrat"])
    }

    func testRenduQuiNeCorrespondPasALaRelectureEstRefuse() async throws {
        let port = PortScripte()
        var relu = detail()
        relu.hashDocument = String(repeating: "c", count: 64)
        await port.poser(details: [detail(chemin: nil), relu])
        await port.poser(original: .success(originalA))
        let model = try await modele(port)
        await model.charger()
        XCTAssertNil(model.original, "l'original rendu doit être celui que le contrat relu porte")
        XCTAssertEqual(model.indisponibilite, .hashMismatch)
    }

    func testCertificatLuQuandUneSignatureExisteEtErreurNonBloquante() async throws {
        let port = PortScripte()
        await port.poser(details: [detail(etablissement: true)])
        await port.poser(original: .success(originalA))
        await port.poser(certificat: [], erreur: JoleneError(.network, "Connexion impossible."))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.etat, .charge, "un certificat illisible ne masque pas le contrat")
        XCTAssertEqual(model.erreurCertificat, "Connexion impossible.")
        let appels = await port.compte("certificat")
        XCTAssertEqual(appels, 1)
    }

    func testCompteTestSansAdmissionRenvoieVersLeWeb() async throws {
        let port = PortScripte()
        await port.poser(details: [detail(test: true)])
        await port.poser(original: .success(originalA))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.signature, .renvoiWeb, "décision 18 : continuer sur jolene.app")
        let admissions = await port.compte("admission")
        XCTAssertEqual(admissions, 1)
    }

    func testCompteTestAdmisReprendUnCodeEncoreValide() async throws {
        let port = PortScripte()
        await port.poser(details: [detail(test: true)])
        await port.poser(original: .success(originalA))
        await port.poser(admission: AdmissionSignatureRecette(expireLe: Self.maintenant.addingTimeInterval(1_800), peutEnvoyer: false,
                                                              peutValider: true, otpExpireLe: Self.maintenant.addingTimeInterval(300)))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.signature, .possible)
        XCTAssertEqual(model.session.etape, .otpEnvoye)
        XCTAssertEqual(model.session.secondesRestantes(maintenant: Self.maintenant), 300)
        model.accepter(true)
        await model.envoyerCode()
        let envois = await port.compte("envoyerOtp")
        XCTAssertEqual(envois, 0, "aucun nouvel envoi hors budget de recette (`can_send` faux)")
    }

    func testSessionExpireeEtEchecGenerique() async throws {
        let port = PortScripte()
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.etat, .echec(nonScripte.message), "message d'une JoleneError affiché tel quel")
        XCTAssertFalse(model.sessionExpired)
        let expire = PortScripte()
        let autre = try await modele(expire)
        await expire.poser(details: [detail()])
        await expire.poser(original: .failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")))
        await autre.charger()
        XCTAssertTrue(autre.sessionExpired)
        XCTAssertEqual(autre.etat, .echec("Votre session a expiré. Reconnectez-vous."))
    }

    func testEchecInconnuDonneLeMessageGenerique() async throws {
        struct Inconnue: Error {}
        let port = PortScripte()
        await port.poser(details: [detail()])
        await port.poser(original: .failure(Inconnue()))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.etat, .echec(MessagesContrats.indisponible), "jamais le détail technique d'une erreur inconnue")
    }

    // MARK: - OTP

    func testEnvoiUniquePuisSignatureEtRelecture() async throws {
        let port = PortScripte()
        await port.poser(details: [detail(), detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        await port.poser(original: .success(originalA))
        await port.poser(envoi: .success(.envoye(OtpEnvoye(role: "soignant", telephoneMasque: "+**********00",
                                                            expireDansMinutes: 10, smsEnvoyes: 1, smsRestants: 2))),
                         attente: .milliseconds(50))
        await port.poser(signature: .success(.signee(contratComplet: false)))
        let model = try await modele(port)
        await model.charger()
        model.accepter(true)
        async let premier: Void = model.envoyerCode()
        async let second: Void = model.envoyerCode()
        _ = await (premier, second)
        let envois = await port.compte("envoyerOtp")
        XCTAssertEqual(envois, 1, "double tap : une seule requête")
        XCTAssertEqual(model.session.etape, .otpEnvoye)
        model.saisirCode("000000")
        await model.signer()
        XCTAssertEqual(model.session.etape, .signe)
        XCTAssertEqual(model.contrat?.signatureSoignant, true, "contrat relu après la signature")
        let appels = await port.appels
        XCTAssertEqual(appels, ["contrat", "original", "envoyerOtp", "signer:000000", "contrat", "certificat"])
    }

    func testCodeIncompletJamaisEnvoyeAuPort() async throws {
        let port = PortScripte()
        await port.poser(details: [detail()])
        await port.poser(original: .success(originalA))
        await port.poser(envoi: .success(.envoye(OtpEnvoye(telephoneMasque: "+**********00", expireDansMinutes: 10))))
        let model = try await modele(port)
        await model.charger()
        model.accepter(true)
        await model.envoyerCode()
        model.saisirCode("12a")
        await model.signer()
        let signatures = await port.appels.filter { $0.hasPrefix("signer") }
        XCTAssertEqual(signatures, [])
        XCTAssertEqual(model.session.retour, .erreur(LibellesWeb.SignatureOtp.codeSixChiffresRequis))
    }

    func testEchecDeTransportDuCodeAfficheLeMessageDeLErreur() async throws {
        let port = PortScripte()
        await port.poser(details: [detail()])
        await port.poser(original: .success(originalA))
        await port.poser(envoi: .failure(JoleneError(.network, "Connexion impossible. Vérifiez votre réseau puis réessayez.")))
        let model = try await modele(port)
        await model.charger()
        model.accepter(true)
        await model.envoyerCode()
        XCTAssertEqual(model.session.retour, .erreur("Connexion impossible. Vérifiez votre réseau puis réessayez."))
        XCTAssertEqual(model.session.etape, .idle)
    }

    // MARK: - Liste

    func testListeFiltreeCommeLeWebEtEchec() async throws {
        let port = PortScripte()
        await port.poser(liste: .success([ContratResume(id: "a", missionId: "m", statut: "SIGNE_COMPLET"),
                                          ContratResume(id: "b", missionId: "m", statut: "EN_ATTENTE_SIGNATURES")]))
        let (controller, snapshot) = try await pret(port)
        let liste = ContratsListeModel(controller: controller, snapshot: snapshot, filtreInitial: .initial(statut: "SIGNE_COMPLET"))
        await liste.charger()
        XCTAssertEqual(liste.affiches.map(\.id), ["a"])
        liste.choisir(.tous)
        XCTAssertEqual(liste.affiches.map(\.id), ["a", "b"], "filtre local, aucune relecture")
        let lectures = await port.compte("contrats")
        XCTAssertEqual(lectures, 1)
        await port.poser(liste: .failure(JoleneError(.network, "Connexion impossible.")))
        await liste.charger()
        XCTAssertEqual(liste.etat, .echec("Connexion impossible."))
    }
}
