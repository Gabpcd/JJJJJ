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

    /// Port scripté : chaque méthode rend la valeur posée par le test et compte ses appels. Classe verrouillée
    /// (et non acteur) : le test pose ses réponses sans traverser de frontière d'isolation.
    private final class PortScripte: ContratsPort, @unchecked Sendable {
        private let verrou = NSLock()
        private var details: [ContratDetail] = []
        private var issueOriginal: Result<OriginalContrat, Error> = .failure(nonScripte)
        private var issueAdmission: AdmissionSignatureRecette?
        private var issueEnvoi: Result<IssueEnvoiOtp, Error> = .failure(nonScripte)
        private var issueSignature: Result<IssueSignature, Error> = .failure(nonScripte)
        private var certificatLignes: [SignatureCertificat] = []
        private var certificatErreur: Error?
        private var issueListe: Result<[ContratResume], Error> = .success([])
        private var issueFichier: Result<URL, Error> = .failure(nonScripte)
        /// Échecs de `contrat(id:context:)` par rang d'appel (1 = premier chargement) : la file `details` n'avance pas.
        private var echecsContrat: [Int: Error] = [:]
        private var attenteEnvoi: Duration = .zero
        private var attenteSignature: Duration = .zero
        private var attenteAdmission: Duration = .zero
        private var journal: [String] = []

        private func avec<T>(_ bloc: () throws -> T) rethrows -> T {
            verrou.lock(); defer { verrou.unlock() }
            return try bloc()
        }

        var appels: [String] { avec { journal } }
        func compte(_ nom: String) -> Int { avec { journal.filter { $0 == nom }.count } }
        func poser(details: [ContratDetail]) { avec { self.details = details } }
        func poser(original: Result<OriginalContrat, Error>) { avec { issueOriginal = original } }
        func poser(admission: AdmissionSignatureRecette?) { avec { issueAdmission = admission } }
        func poser(envoi: Result<IssueEnvoiOtp, Error>, attente: Duration = .zero) { avec { issueEnvoi = envoi; attenteEnvoi = attente } }
        func poser(signature: Result<IssueSignature, Error>, attente: Duration = .zero) {
            avec { issueSignature = signature; attenteSignature = attente }
        }
        func poser(attenteAdmission attente: Duration) { avec { attenteAdmission = attente } }
        func poser(certificat: [SignatureCertificat], erreur: Error? = nil) { avec { certificatLignes = certificat; certificatErreur = erreur } }
        func poser(liste: Result<[ContratResume], Error>) { avec { issueListe = liste } }
        func poser(fichier: Result<URL, Error>) { avec { issueFichier = fichier } }
        func poser(echecContrat rang: Int, erreur: Error) { avec { echecsContrat[rang] = erreur } }

        func contrats(context: MissionReadContext) async throws -> [ContratResume] {
            try avec { journal.append("contrats"); return try issueListe.get() }
        }
        func contrat(id: String, context: MissionReadContext) async throws -> ContratDetail {
            try avec {
                journal.append("contrat")
                if let erreur = echecsContrat[journal.filter { $0 == "contrat" }.count] { throw erreur }
                guard !details.isEmpty else { throw nonScripte }
                return details.count > 1 ? details.removeFirst() : details[0]
            }
        }
        func original(contrat: ContratDetail, context: MissionReadContext) async throws -> OriginalContrat {
            try avec { journal.append("original"); return try issueOriginal.get() }
        }
        func admissionRecette(contratId: String, context: MissionReadContext) async throws -> AdmissionSignatureRecette? {
            let attente = avec { journal.append("admission"); return attenteAdmission }
            if attente > .zero { try await Task.sleep(for: attente) }
            return avec { issueAdmission }
        }
        func envoyerOtp(contratId: String, empreinte: String, context: MissionReadContext) async throws -> IssueEnvoiOtp {
            let attente = avec { journal.append("envoyerOtp"); return attenteEnvoi }
            if attente > .zero { try await Task.sleep(for: attente) }
            return try avec { try issueEnvoi.get() }
        }
        func signer(contratId: String, code: String, empreinte: String, context: MissionReadContext) async throws -> IssueSignature {
            let attente = avec { journal.append("signer:\(code)"); return attenteSignature }
            if attente > .zero { try await Task.sleep(for: attente) }
            return try avec { try issueSignature.get() }
        }
        func certificat(contratId: String, context: MissionReadContext) async throws -> [SignatureCertificat] {
            try avec {
                journal.append("certificat")
                if let certificatErreur { throw certificatErreur }
                return certificatLignes
            }
        }
        func fichierOriginal(contrat: OriginalContrat, context: MissionReadContext) async throws -> URL {
            try avec { journal.append("fichier"); return try issueFichier.get() }
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
        port.poser(details: [detail()])
        port.poser(original: .success(originalA))
        let model = try await modele(port)
        XCTAssertEqual(model.etat, .chargement)
        await model.charger()
        XCTAssertEqual(model.etat, .charge)
        XCTAssertEqual(model.original, originalA)
        XCTAssertNil(model.indisponibilite)
        XCTAssertEqual(model.session.cle, CleSessionOtp(contratId: "k-1", empreinte: Self.empreinte, documentPret: true))
        XCTAssertEqual(model.signature, .possible)
        let appels = port.appels
        XCTAssertEqual(appels, ["contrat", "original"], "ni certificat (aucune signature), ni admission (compte réel)")
    }

    func testCddSansOriginalNeDemandeJamaisLOriginal() async throws {
        let port = PortScripte()
        port.poser(details: [detail(type: "CDD", chemin: nil)])
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.etat, .charge)
        XCTAssertEqual(model.indisponibilite, .cddAPreparer)
        XCTAssertNil(model.original)
        XCTAssertEqual(model.signature, .indisponible)
        XCTAssertEqual(model.session.cle.documentPret, false)
        let appelsOriginal = port.compte("original")
        XCTAssertEqual(appelsOriginal, 0, "décision 19 : aucune action soignant, aucun rendu")
    }

    func testOriginalIndisponibleLaisseLeContratLisibleSansSignature() async throws {
        let port = PortScripte()
        port.poser(details: [detail()])
        port.poser(original: .failure(ContratOriginalIndisponible(motif: .storageMismatch)))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.etat, .charge)
        XCTAssertEqual(model.indisponibilite, .storageMismatch)
        XCTAssertEqual(model.signature, .indisponible)
        XCTAssertFalse(model.session.peutEnvoyer())
    }

    func testRenduServeurPuisRelectureDuContrat() async throws {
        let port = PortScripte()
        port.poser(details: [detail(chemin: nil), detail()])
        port.poser(original: .success(originalA))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.contrat?.storagePath, "k-1/a.html", "contrat relu après le rendu serveur")
        XCTAssertEqual(model.original, originalA)
        let appels = port.appels
        XCTAssertEqual(appels, ["contrat", "original", "contrat"])
    }

    func testRenduQuiNeCorrespondPasALaRelectureEstRefuse() async throws {
        let port = PortScripte()
        var relu = detail()
        relu.hashDocument = String(repeating: "c", count: 64)
        port.poser(details: [detail(chemin: nil), relu])
        port.poser(original: .success(originalA))
        let model = try await modele(port)
        await model.charger()
        XCTAssertNil(model.original, "l'original rendu doit être celui que le contrat relu porte")
        XCTAssertEqual(model.indisponibilite, .hashMismatch)
    }

    func testCertificatLuQuandUneSignatureExisteEtErreurNonBloquante() async throws {
        let port = PortScripte()
        port.poser(details: [detail(etablissement: true)])
        port.poser(original: .success(originalA))
        port.poser(certificat: [], erreur: JoleneError(.network, "Connexion impossible."))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.etat, .charge, "un certificat illisible ne masque pas le contrat")
        XCTAssertEqual(model.erreurCertificat, "Connexion impossible.")
        let appels = port.compte("certificat")
        XCTAssertEqual(appels, 1)
    }

    func testCompteTestSansAdmissionRenvoieVersLeWeb() async throws {
        let port = PortScripte()
        port.poser(details: [detail(test: true)])
        port.poser(original: .success(originalA))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.signature, .renvoiWeb, "décision 18 : continuer sur jolene.app")
        let admissions = port.compte("admission")
        XCTAssertEqual(admissions, 1)
    }

    func testCompteTestAdmisReprendUnCodeEncoreValide() async throws {
        let port = PortScripte()
        port.poser(details: [detail(test: true)])
        port.poser(original: .success(originalA))
        port.poser(admission: AdmissionSignatureRecette(expireLe: Self.maintenant.addingTimeInterval(1_800), peutEnvoyer: false,
                                                              peutValider: true, otpExpireLe: Self.maintenant.addingTimeInterval(300)))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.signature, .possible)
        XCTAssertEqual(model.session.etape, .otpEnvoye)
        XCTAssertEqual(model.session.secondesRestantes(maintenant: Self.maintenant), 300)
        model.accepter(true)
        await model.envoyerCode()
        let envois = port.compte("envoyerOtp")
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
        expire.poser(details: [detail()])
        expire.poser(original: .failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")))
        await autre.charger()
        XCTAssertTrue(autre.sessionExpired)
        XCTAssertEqual(autre.etat, .echec("Votre session a expiré. Reconnectez-vous."))
    }

    func testEchecInconnuDonneLeMessageGenerique() async throws {
        struct Inconnue: Error {}
        let port = PortScripte()
        port.poser(details: [detail()])
        port.poser(original: .failure(Inconnue()))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.etat, .echec(MessagesContrats.indisponible), "jamais le détail technique d'une erreur inconnue")
    }

    // MARK: - OTP

    func testEnvoiUniquePuisSignatureEtRelecture() async throws {
        let port = PortScripte()
        port.poser(details: [detail(), detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        port.poser(original: .success(originalA))
        port.poser(envoi: .success(.envoye(OtpEnvoye(role: "soignant", telephoneMasque: "+**********00",
                                                            expireDansMinutes: 10, smsEnvoyes: 1, smsRestants: 2))),
                         attente: .milliseconds(50))
        port.poser(signature: .success(.signee(contratComplet: false)))
        let model = try await modele(port)
        await model.charger()
        model.accepter(true)
        async let premier: Void = model.envoyerCode()
        async let second: Void = model.envoyerCode()
        _ = await (premier, second)
        let envois = port.compte("envoyerOtp")
        XCTAssertEqual(envois, 1, "double tap : une seule requête")
        XCTAssertEqual(model.session.etape, .otpEnvoye)
        model.saisirCode("000000")
        await model.signer()
        XCTAssertEqual(model.session.etape, .signe)
        XCTAssertEqual(model.contrat?.signatureSoignant, true, "contrat relu après la signature")
        let appels = port.appels
        XCTAssertEqual(appels, ["contrat", "original", "envoyerOtp", "signer:000000", "contrat", "certificat"])
    }

    func testCodeIncompletJamaisEnvoyeAuPort() async throws {
        let port = PortScripte()
        port.poser(details: [detail()])
        port.poser(original: .success(originalA))
        port.poser(envoi: .success(.envoye(OtpEnvoye(telephoneMasque: "+**********00", expireDansMinutes: 10))))
        let model = try await modele(port)
        await model.charger()
        model.accepter(true)
        await model.envoyerCode()
        model.saisirCode("12a")
        await model.signer()
        let signatures = port.appels.filter { $0.hasPrefix("signer") }
        XCTAssertEqual(signatures, [])
        XCTAssertEqual(model.session.retour, .erreur(LibellesWeb.SignatureOtp.codeSixChiffresRequis))
    }

    func testEchecDeTransportDuCodeAfficheLeMessageDeLErreur() async throws {
        let port = PortScripte()
        port.poser(details: [detail()])
        port.poser(original: .success(originalA))
        port.poser(envoi: .failure(JoleneError(.network, "Connexion impossible. Vérifiez votre réseau puis réessayez.")))
        let model = try await modele(port)
        await model.charger()
        model.accepter(true)
        await model.envoyerCode()
        XCTAssertEqual(model.session.retour, .erreur("Connexion impossible. Vérifiez votre réseau puis réessayez."))
        XCTAssertEqual(model.session.etape, .idle)
    }

    // MARK: - Signature OTP (T9b)

    private func signatureSoignant() -> SignatureCertificat {
        SignatureCertificat(id: "s-soignant", contratId: "k-1", signataireRole: "soignant", signeA: "2026-11-02T00:00:00Z",
                            hashDocument: Self.empreinte, otpValideA: "2026-11-02T00:00:00Z", statutSignature: "signe")
    }

    private func envoye(sms: Int = 2) -> Result<IssueEnvoiOtp, Error> {
        .success(.envoye(OtpEnvoye(role: "soignant", telephoneMasque: "+**********00", expireDansMinutes: 10, smsEnvoyes: 1,
                                   smsRestants: sms)))
    }

    /// Modèle chargé, consentement donné, code envoyé.
    private func codeEnvoye(_ port: PortScripte, details: [ContratDetail]? = nil) async throws -> ContratModel {
        port.poser(details: details ?? [detail()])
        port.poser(original: .success(originalA))
        port.poser(envoi: envoye())
        let model = try await modele(port)
        await model.charger()
        model.accepter(true)
        await model.envoyerCode()
        XCTAssertEqual(model.session.etape, .otpEnvoye)
        return model
    }

    func testZoneDeSignatureSelonLeContratEtLeCompte() async throws {
        let reel = PortScripte()
        reel.poser(details: [detail()])
        reel.poser(original: .success(originalA))
        let modelReel = try await modele(reel)
        XCTAssertNil(modelReel.zoneSignature(maintenant: Self.maintenant), "rien avant le chargement")
        await modelReel.charger()
        guard case .otp(let presentation)? = modelReel.zoneSignature(maintenant: Self.maintenant),
              case .formulaire(let formulaire) = presentation.mode else { return XCTFail("formulaire OTP attendu") }
        XCTAssertEqual(formulaire.recevoir?.actif, false, "case non cochée")

        let test = PortScripte()
        test.poser(details: [detail(test: true)])
        test.poser(original: .success(originalA))
        let modelTest = try await modele(test)
        await modelTest.charger()
        XCTAssertEqual(modelTest.zoneSignature(maintenant: Self.maintenant),
                       .renvoiWeb(message: "Cet espace n'est pas encore disponible dans l'application. Rendez-vous sur jolene.app.",
                                  route: ContratPresentation.renvoiSignature(contratId: "k-1")),
                       "décision 18 : compte TEST sans admission, renvoi web ; texte du lot 0 (`MobileAccess.unsupportedRole`)")

        let signe = PortScripte()
        signe.poser(details: [detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        signe.poser(original: .success(originalA))
        let modelSigne = try await modele(signe)
        await modelSigne.charger()
        XCTAssertNil(modelSigne.zoneSignature(maintenant: Self.maintenant), "déjà signé : aucune zone (l.709)")

        let cdd = PortScripte()
        cdd.poser(details: [detail(type: "CDD", chemin: nil)])
        let modelCdd = try await modele(cdd)
        await modelCdd.charger()
        XCTAssertNil(modelCdd.zoneSignature(maintenant: Self.maintenant), "CDD à préparer : aucune action soignant (décision 19)")

        let nonFige = PortScripte()
        nonFige.poser(details: [detail()])
        nonFige.poser(original: .failure(ContratOriginalIndisponible(motif: .storageMismatch)))
        let modelNonFige = try await modele(nonFige)
        await modelNonFige.charger()
        guard case .otp(let indispo)? = modelNonFige.zoneSignature(maintenant: Self.maintenant),
              case .formulaire(let desactive) = indispo.mode else { return XCTFail("formulaire désactivé attendu (documentPret faux)") }
        XCTAssertEqual(desactive.recevoir?.actif, false)
    }

    func testCompteTestSansOriginalControleRenvoieAussiVersLeWeb() async throws {
        let port = PortScripte()
        port.poser(details: [detail(test: true)])
        port.poser(original: .failure(ContratOriginalIndisponible(motif: .storageMismatch)))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.signature, .renvoiWeb, "le web bascule un compte TEST sur un autre mode : jamais d'OTP sans admission")
    }

    func testAdmissionExpireeLocalementRenvoieVersLeWeb() async throws {
        let port = PortScripte()
        port.poser(details: [detail(test: true)])
        port.poser(original: .success(originalA))
        port.poser(admission: AdmissionSignatureRecette(expireLe: Self.maintenant.addingTimeInterval(600), peutEnvoyer: true,
                                                              peutValider: false, otpExpireLe: nil))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.disponibiliteSignature(maintenant: Self.maintenant), .possible)
        XCTAssertTrue(model.nouvelEnvoiAutorise(maintenant: Self.maintenant))
        let apres = Self.maintenant.addingTimeInterval(600)
        XCTAssertEqual(model.disponibiliteSignature(maintenant: apres), .renvoiWeb,
                       "capacité de recette échue : fermée comme le minuteur du web (`ContratMission.tsx` l.315-317)")
        XCTAssertFalse(model.nouvelEnvoiAutorise(maintenant: apres))
        guard case .renvoiWeb? = model.zoneSignature(maintenant: apres) else { return XCTFail("renvoi web attendu") }
    }

    /// Revue fraîche de T9b (m2) : le web ferme l'OTP à `admittedUntil = canSend ? expiresAt : otpExpiresAt`, et aussi quand
    /// cette valeur est nulle (`ContratMission.tsx` l.311-312) ; sans envoi possible, l'échéance est celle du code, pas
    /// celle de la capacité.
    func testAdmissionSansEnvoiFermeeALEcheanceDuCode() async throws {
        let port = PortScripte()
        port.poser(details: [detail(test: true)])
        port.poser(original: .success(originalA))
        port.poser(admission: AdmissionSignatureRecette(expireLe: Self.maintenant.addingTimeInterval(1_800), peutEnvoyer: false,
                                                              peutValider: true, otpExpireLe: Self.maintenant.addingTimeInterval(300)))
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.disponibiliteSignature(maintenant: Self.maintenant.addingTimeInterval(299)), .possible)
        let apresCode = Self.maintenant.addingTimeInterval(300)
        XCTAssertEqual(model.disponibiliteSignature(maintenant: apresCode), .renvoiWeb,
                       "sans envoi possible, fermée à l'échéance du code (l.311), pas à la fin de la capacité")
        XCTAssertFalse(model.nouvelEnvoiAutorise(maintenant: Self.maintenant))
        guard case .renvoiWeb? = model.zoneSignature(maintenant: apresCode) else { return XCTFail("renvoi web attendu") }

        let sansCode = PortScripte()
        sansCode.poser(details: [detail(test: true)])
        sansCode.poser(original: .success(originalA))
        sansCode.poser(admission: AdmissionSignatureRecette(expireLe: Self.maintenant.addingTimeInterval(1_800), peutEnvoyer: false,
                                                                  peutValider: false, otpExpireLe: nil))
        let ferme = try await modele(sansCode)
        await ferme.charger()
        XCTAssertEqual(ferme.disponibiliteSignature(maintenant: Self.maintenant), .renvoiWeb, "échéance nulle : fermée (l.312)")
        XCTAssertFalse(ferme.nouvelEnvoiAutorise(maintenant: Self.maintenant))

        let envoi = PortScripte()
        envoi.poser(details: [detail(test: true)])
        envoi.poser(original: .success(originalA))
        envoi.poser(admission: AdmissionSignatureRecette(expireLe: Self.maintenant.addingTimeInterval(1_800), peutEnvoyer: true,
                                                               peutValider: true, otpExpireLe: Self.maintenant.addingTimeInterval(300)))
        let ouvert = try await modele(envoi)
        await ouvert.charger()
        XCTAssertEqual(ouvert.disponibiliteSignature(maintenant: apresCode), .possible,
                       "envoi possible : ouverte jusqu'à la fin de la capacité (l.311)")
        XCTAssertEqual(ouvert.disponibiliteSignature(maintenant: Self.maintenant.addingTimeInterval(1_800)), .renvoiWeb)
    }

    func testSignatureAnnonceeSeulementApresLaRelectureDuContratEtDuCertificat() async throws {
        let port = PortScripte()
        let model = try await codeEnvoye(port, details: [detail(), detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        port.poser(signature: .success(.signee(contratComplet: false)))
        port.poser(certificat: [signatureSoignant()])
        var observe: [(SessionSignatureOtp.Etape, Bool?, Int)] = []
        let abonnement = model.$session.sink { [unowned model] nouvelle in
            observe.append((nouvelle.etape, model.contrat?.signatureSoignant, model.signatures.count))
        }
        model.saisirCode("000000")
        await model.signer()
        abonnement.cancel()
        XCTAssertEqual(model.session.etape, .signe)
        let premierSigne = try XCTUnwrap(observe.first { $0.0 == .signe })
        XCTAssertEqual(premierSigne.1, true, "le contrat relu est publié avant la confirmation")
        XCTAssertEqual(premierSigne.2, 1, "le certificat relu aussi")
        XCTAssertEqual(model.session.code, "", "code effacé après usage")
        guard case .otp(let presentation)? = model.zoneSignature(maintenant: Self.maintenant),
              case .signee(let confirmation, _, let actualisation) = presentation.mode else { return XCTFail("confirmation attendue") }
        XCTAssertNil(actualisation, "contrat et certificat relus : aucune actualisation proposée")
        XCTAssertEqual(confirmation, "Contrat signé ✅")
        XCTAssertTrue(ContratRules.dejaSigneParMoi(try XCTUnwrap(model.contrat)), "« déjà signé » relu du serveur")
        let appels = port.appels
        XCTAssertEqual(appels, ["contrat", "original", "envoyerOtp", "signer:000000", "contrat", "certificat"])
    }

    func testEchecDeTransportALaSignatureRelitLEtatSansSuccesSuppose() async throws {
        let port = PortScripte()
        let model = try await codeEnvoye(port, details: [detail(), detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        port.poser(signature: .failure(JoleneError(.network, "Connexion impossible.")))
        port.poser(certificat: [signatureSoignant()])
        model.saisirCode("000000")
        await model.signer()
        XCTAssertEqual(model.session.etape, .otpEnvoye, "jamais de succès sans confirmation de la gateway")
        XCTAssertEqual(model.session.retour, .erreur("Connexion impossible."))
        XCTAssertEqual(model.contrat?.signatureSoignant, true, "état relu : la signature avait été appliquée")
        XCTAssertEqual(model.signatures.count, 1)
        XCTAssertNil(model.zoneSignature(maintenant: Self.maintenant), "zone remplacée par « déjà signé », relu du serveur")
        let appels = port.appels
        XCTAssertEqual(appels, ["contrat", "original", "envoyerOtp", "signer:000000", "contrat", "certificat"],
                       "une relecture, jamais un second envoi du code")
    }

    func testDelaiEpuiseALaSignatureRelitAvecSonPropreBudget() async throws {
        let port = PortScripte()
        port.poser(details: [detail(), detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        port.poser(original: .success(originalA))
        port.poser(envoi: envoye())
        let (controller, snapshot) = try await pret(port, timeout: 0.05)
        let model = ContratModel(controller: controller, snapshot: snapshot, contratId: "k-1")
        await model.charger()
        model.accepter(true)
        await model.envoyerCode()
        port.poser(signature: .success(.signee(contratComplet: false)), attente: .seconds(5))
        port.poser(certificat: [signatureSoignant()])
        model.saisirCode("000000")
        await model.signer()
        XCTAssertNotEqual(model.session.etape, .signe, "délai épuisé : aucune confirmation")
        XCTAssertFalse(model.session.operationEnCours)
        XCTAssertEqual(model.contrat?.signatureSoignant, true, "relecture après le délai, budget distinct")
    }

    func testRefusDejaSigneRelitLeContrat() async throws {
        let port = PortScripte()
        let model = try await codeEnvoye(port, details: [detail(), detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        port.poser(signature: .success(.refuse(code: "DEJA_SIGNE", message: TextesWeb.SignatureOtp.dejaSigne, tentativesRestantes: nil)))
        port.poser(certificat: [signatureSoignant()])
        model.saisirCode("000000")
        await model.signer()
        XCTAssertEqual(model.session.erreurBloquante?.code, "DEJA_SIGNE")
        XCTAssertEqual(model.contrat?.signatureSoignant, true, "état du serveur relu après le refus")
        let lectures = port.compte("contrat")
        XCTAssertEqual(lectures, 2)
    }

    func testRefusIndisponibleALEnvoiRelitLeContratEtLesAutresNon() async throws {
        let port = PortScripte()
        port.poser(details: [detail(), detail(etablissement: true, statut: "SIGNE_COMPLET")])
        port.poser(original: .success(originalA))
        port.poser(envoi: .success(.refuse(code: "CONTRAT_DEJA_COMPLET", message: TextesWeb.SignatureOtp.contratDejaComplet,
                                           bloquant: true)))
        let model = try await modele(port)
        await model.charger()
        model.accepter(true)
        await model.envoyerCode()
        XCTAssertEqual(model.contrat?.statut, "SIGNE_COMPLET", "contrat relu après un refus qui rend la signature indisponible")

        let autre = PortScripte()
        autre.poser(details: [detail()])
        autre.poser(original: .success(originalA))
        autre.poser(envoi: .success(.refuse(code: "TELEPHONE_MANQUANT", message: TextesWeb.SignatureOtp.telephoneManquant,
                                            bloquant: true)))
        let second = try await modele(autre)
        await second.charger()
        second.accepter(true)
        await second.envoyerCode()
        let lectures = autre.compte("contrat")
        XCTAssertEqual(lectures, 1, "refus du profil (téléphone) : rien à relire")
        guard case .otp(let p)? = second.zoneSignature(maintenant: Self.maintenant), case .formulaire(let f) = p.mode else {
            return XCTFail("formulaire attendu")
        }
        XCTAssertEqual(f.alerte, TextesWeb.SignatureOtp.telephoneManquant)
    }

    func testSessionExpireeALaSignatureNeRelitRien() async throws {
        let port = PortScripte()
        let model = try await codeEnvoye(port)
        port.poser(signature: .failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")))
        model.saisirCode("000000")
        await model.signer()
        XCTAssertTrue(model.sessionExpired)
        let lectures = port.compte("contrat")
        XCTAssertEqual(lectures, 1, "aucune relecture avec une session expirée")
    }

    // Revue fraîche de T9b (m1) : signature confirmée par la gateway (`.signee`, preuve relue), puis relecture du contrat
    // par le modèle en échec. Le succès n'est jamais retiré ni renvoyé ; l'écran ne se contredit pas en silence.

    func testSigneePuisRelectureEnEchecLaRelanceUneFois() async throws {
        let port = PortScripte()
        let model = try await codeEnvoye(port, details: [detail(), detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        port.poser(signature: .success(.signee(contratComplet: false)))
        port.poser(certificat: [signatureSoignant()])
        port.poser(echecContrat: 2, erreur: JoleneError(.network, "Connexion impossible."))
        model.saisirCode("000000")
        await model.signer()
        XCTAssertEqual(model.session.etape, .signe)
        XCTAssertEqual(model.contrat?.signatureSoignant, true, "seconde relecture publiée")
        XCTAssertEqual(model.signatures.count, 1)
        XCTAssertNil(model.erreurRelecture)
        let appels = port.appels
        XCTAssertEqual(appels, ["contrat", "original", "envoyerOtp", "signer:000000", "contrat", "contrat", "certificat"],
                       "une seule relance de la relecture, jamais un second envoi du code")
        guard case .otp(let p)? = model.zoneSignature(maintenant: Self.maintenant),
              case .signee(_, _, let actualisation) = p.mode else { return XCTFail("confirmation attendue") }
        XCTAssertNil(actualisation)
    }

    func testSigneePuisRelecturesEnEchecProposeLActualisation() async throws {
        let port = PortScripte()
        let model = try await codeEnvoye(port, details: [detail(), detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        port.poser(signature: .success(.signee(contratComplet: false)))
        port.poser(certificat: [signatureSoignant()])
        port.poser(echecContrat: 2, erreur: JoleneError(.network, "Connexion impossible."))
        port.poser(echecContrat: 3, erreur: JoleneError(.network, SessionController.timeoutMessage))
        model.saisirCode("000000")
        await model.signer()
        XCTAssertEqual(model.session.etape, .signe, "signature confirmée par la gateway (preuve relue) : ni retirée ni renvoyée")
        XCTAssertEqual(model.contrat?.signatureSoignant, false, "contrat non relu : l'écran le dit")
        XCTAssertEqual(model.erreurRelecture, MessagesContrats.indisponible)
        XCTAssertFalse(model.sessionExpired)
        guard case .otp(let p)? = model.zoneSignature(maintenant: Self.maintenant),
              case .signee(let confirmation, _, let actualisation) = p.mode else { return XCTFail("confirmation attendue") }
        XCTAssertEqual(confirmation, "Contrat signé ✅")
        XCTAssertEqual(actualisation, MessagesContrats.indisponible, "actualisation proposée sous la confirmation")

        await model.actualiser()
        XCTAssertEqual(model.contrat?.signatureSoignant, true)
        XCTAssertEqual(model.signatures.count, 1)
        XCTAssertNil(model.erreurRelecture)
        XCTAssertTrue(ContratRules.dejaSigneParMoi(try XCTUnwrap(model.contrat)), "« déjà signé » relu du serveur")
        guard case .otp(let apres)? = model.zoneSignature(maintenant: Self.maintenant),
              case .signee(_, _, nil) = apres.mode else { return XCTFail("confirmation sans actualisation attendue") }
        let signatures = port.appels.filter { $0.hasPrefix("signer") }
        XCTAssertEqual(signatures, ["signer:000000"], "l'actualisation ne relit que le contrat et le certificat")
    }

    func testActualisationEnEchecGardeLaConfirmationEtLaProposition() async throws {
        let port = PortScripte()
        let model = try await codeEnvoye(port, details: [detail(), detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        port.poser(signature: .success(.signee(contratComplet: false)))
        for rang in 2...4 { port.poser(echecContrat: rang, erreur: JoleneError(.network, "Connexion impossible.")) }
        model.saisirCode("000000")
        await model.signer()
        await model.actualiser()
        XCTAssertEqual(model.etat, .charge, "jamais de démontage de l'écran sur une actualisation")
        XCTAssertEqual(model.session.etape, .signe)
        XCTAssertEqual(model.erreurRelecture, MessagesContrats.indisponible)
        let lectures = port.compte("contrat")
        XCTAssertEqual(lectures, 4, "une lecture par actualisation demandée, aucune relance automatique en plus")
    }

    func testSigneePuisSessionExpireeALaRelecture() async throws {
        let port = PortScripte()
        let model = try await codeEnvoye(port, details: [detail(), detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        port.poser(signature: .success(.signee(contratComplet: false)))
        port.poser(certificat: [signatureSoignant()])
        port.poser(echecContrat: 2, erreur: JoleneError(.unauthorized, SessionController.sessionExpiredMessage))
        model.saisirCode("000000")
        await model.signer()
        XCTAssertEqual(model.session.etape, .signe)
        XCTAssertTrue(model.sessionExpired, "jeton refusé à la relecture : session à vérifier")
        XCTAssertNil(model.erreurRelecture, "une session expirée n'est pas une lecture à réessayer")
        let lectures = port.compte("contrat")
        XCTAssertEqual(lectures, 2, "aucune relance avec une session expirée")

        await model.charger()
        XCTAssertFalse(model.sessionExpired, "session vérifiée puis contrat relu : plus de session à vérifier")
        XCTAssertEqual(model.contrat?.signatureSoignant, true)
        XCTAssertEqual(model.session.etape, .signe, "même révision : confirmation gardée")
    }

    func testSigneePuisCertificatRefuseParLeJetonExpireLaSession() async throws {
        let port = PortScripte()
        let model = try await codeEnvoye(port, details: [detail(), detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        port.poser(signature: .success(.signee(contratComplet: false)))
        port.poser(certificat: [], erreur: JoleneError(.unauthorized, SessionController.sessionExpiredMessage))
        model.saisirCode("000000")
        await model.signer()
        XCTAssertTrue(model.sessionExpired)
        XCTAssertNil(model.erreurCertificat, "jeton refusé : session à vérifier, pas une erreur du certificat")
    }

    func testSigneePuisRelectureAnnuleeNePublieAucuneErreur() async throws {
        let port = PortScripte()
        let model = try await codeEnvoye(port, details: [detail(), detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        port.poser(signature: .success(.signee(contratComplet: false)))
        port.poser(certificat: [], erreur: CancellationError())
        model.saisirCode("000000")
        await model.signer()
        XCTAssertEqual(model.session.etape, .signe)
        XCTAssertNil(model.erreurCertificat, "annulation : jamais une erreur vide")
        XCTAssertNil(model.erreurRelecture)
        XCTAssertFalse(model.sessionExpired)
        XCTAssertEqual(model.contrat?.signatureSoignant, false, "annulation : aucune relecture partielle publiée")
    }

    func testDoubleTapSurSignerUneSeuleRequete() async throws {
        let port = PortScripte()
        let model = try await codeEnvoye(port, details: [detail(), detail(soignant: true, statut: "SIGNE_SOIGNANT")])
        port.poser(signature: .success(.signee(contratComplet: false)), attente: .milliseconds(50))
        port.poser(certificat: [signatureSoignant()])
        model.saisirCode("000000")
        async let premier: Void = model.signer()
        async let second: Void = model.signer()
        _ = await (premier, second)
        let signatures = port.appels.filter { $0.hasPrefix("signer") }
        XCTAssertEqual(signatures, ["signer:000000"], "une seule requête de signature")
    }

    func testActionsSuspenduesPendantLaRelectureDeLAdmission() async throws {
        let port = PortScripte()
        port.poser(details: [detail(test: true)])
        port.poser(original: .success(originalA))
        port.poser(admission: AdmissionSignatureRecette(expireLe: Self.maintenant.addingTimeInterval(1_800), peutEnvoyer: true,
                                                              peutValider: false, otpExpireLe: nil))
        port.poser(envoi: envoye())
        let model = try await modele(port)
        await model.charger()
        XCTAssertFalse(model.actionsSuspendues)
        model.accepter(true)
        port.poser(admission: AdmissionSignatureRecette(expireLe: Self.maintenant.addingTimeInterval(1_800), peutEnvoyer: true,
                                                              peutValider: true, otpExpireLe: Self.maintenant.addingTimeInterval(600)))
        port.poser(attenteAdmission: .milliseconds(200))
        var etats: [Bool] = []
        let abonnement = model.$actionsSuspendues.sink { etats.append($0) }
        let envoi = Task { await model.envoyerCode() }
        let limite = Date().addingTimeInterval(5)
        while !model.actionsSuspendues && Date() < limite { await Task.yield() }
        XCTAssertTrue(model.actionsSuspendues, "relecture de l'admission en cours")
        model.saisirCode("000000")
        await model.signer()
        let signatures = port.appels.filter { $0.hasPrefix("signer") }
        XCTAssertEqual(signatures, [], "aucune signature pendant la relecture de l'admission (`actionsSuspendues`, l.164)")
        guard case .otp(let p)? = model.zoneSignature(maintenant: Self.maintenant), case .formulaire(let f) = p.mode else {
            return XCTFail("formulaire attendu")
        }
        XCTAssertEqual(f.suspension, LibellesWeb.SignatureOtp.verificationSignatureEnCours)
        await envoi.value
        abonnement.cancel()
        XCTAssertEqual(etats, [false, true, false])
        XCTAssertFalse(model.actionsSuspendues)
        XCTAssertEqual(model.session.secondesRestantes(maintenant: Self.maintenant), 600, "code relu de l'admission")
    }

    func testMondeDemoParcoursCompletJusquALaSignatureRelue() async throws {
        let controller = SessionController(gateways: DemoWorld.gateways())
        let state = await controller.signIn(email: "demonstration@example.invalid", password: "demonstration")
        let snapshot = try XCTUnwrap(state.snapshot)
        let model = ContratModel(controller: controller, snapshot: snapshot, contratId: "demo-contrat-001")
        await model.charger()
        let maintenant = DemoWorld.fixedNow
        XCTAssertEqual(model.signature, .possible)
        model.accepter(true)
        await model.envoyerCode()
        guard case .otp(let envoi)? = model.zoneSignature(maintenant: maintenant), case .formulaire(let f) = envoi.mode else {
            return XCTFail("formulaire attendu")
        }
        XCTAssertEqual(f.retour, .succes("Code envoyé au +**********00. Valide 10 min."))
        XCTAssertEqual(f.codeEnvoye?.smsRestants, "(2 envois restants)")
        model.saisirCode("111111")
        await model.signer()
        guard case .otp(let faux)? = model.zoneSignature(maintenant: maintenant), case .formulaire(let g) = faux.mode else {
            return XCTFail("formulaire attendu")
        }
        XCTAssertEqual(g.codeEnvoye?.tentatives, "Code incorrect. 4 tentatives restantes.")
        model.saisirCode("000000")
        await model.signer()
        guard case .otp(let signe)? = model.zoneSignature(maintenant: maintenant), case .signee = signe.mode else {
            return XCTFail("signé attendu")
        }
        XCTAssertEqual(model.contrat?.statut, "SIGNE_SOIGNANT")
        XCTAssertEqual(model.signatures.map(\.id), ["demo-signature-demo-contrat-001-soignant"])
        XCTAssertEqual(ContratPresentation.lignesSignatures(try XCTUnwrap(model.contrat)).last?.texte,
                       "Soignant(e) : ✅ Signé le 02/11/2026 à 01:00")
    }

    // MARK: - Partage (T9a)

    func testPartageSansOriginalControleNAppelleJamaisLePort() async throws {
        let port = PortScripte()
        port.poser(details: [detail(type: "CDD", chemin: nil)])
        let model = try await modele(port)
        await model.charger()
        let url = await model.preparerPartage()
        XCTAssertNil(url)
        XCTAssertEqual(model.erreurPartage, "Aucun contrat téléchargeable pour le moment.", "texte du web (`ContratMission.tsx` l.428)")
        let fichiers = port.compte("fichier")
        XCTAssertEqual(fichiers, 0, "seul l'original contrôlé est partagé, jamais une reconstitution")
    }

    func testPartageEcritLaCopieDeLOriginalControle() async throws {
        let port = PortScripte()
        let copie = FileManager.default.temporaryDirectory.appendingPathComponent("Contrat-C-1.html")
        port.poser(details: [detail()])
        port.poser(original: .success(originalA))
        port.poser(fichier: .success(copie))
        let model = try await modele(port)
        let avantChargement = await model.preparerPartage()
        XCTAssertNil(avantChargement, "rien à partager avant le contrôle de l'original")
        await model.charger()
        let url = await model.preparerPartage()
        XCTAssertEqual(url, copie)
        XCTAssertNil(model.erreurPartage)
        let fichiers = port.compte("fichier")
        XCTAssertEqual(fichiers, 1)
    }

    func testPartageEnEchecPublieLeMessageDuPort() async throws {
        let port = PortScripte()
        port.poser(details: [detail()])
        port.poser(original: .success(originalA))
        port.poser(fichier: .failure(JoleneError(.unknown, FichierContratTemporaire.messageIndisponible)))
        let model = try await modele(port)
        await model.charger()
        let url = await model.preparerPartage()
        XCTAssertNil(url)
        XCTAssertEqual(model.erreurPartage, FichierContratTemporaire.messageIndisponible)
        struct Inconnue: Error {}
        port.poser(fichier: .failure(Inconnue()))
        _ = await model.preparerPartage()
        XCTAssertEqual(model.erreurPartage, FichierContratTemporaire.messageIndisponible, "jamais le détail technique d'une erreur inconnue")
        port.poser(fichier: .success(FileManager.default.temporaryDirectory))
        _ = await model.preparerPartage()
        XCTAssertNil(model.erreurPartage, "un nouvel essai efface le message précédent")
    }

    // MARK: - Liste

    func testListeFiltreeCommeLeWebEtEchec() async throws {
        let port = PortScripte()
        port.poser(liste: .success([ContratResume(id: "a", missionId: "m", statut: "SIGNE_COMPLET"),
                                          ContratResume(id: "b", missionId: "m", statut: "EN_ATTENTE_SIGNATURES")]))
        let (controller, snapshot) = try await pret(port)
        let liste = ContratsListeModel(controller: controller, snapshot: snapshot, filtreInitial: .initial(statut: "SIGNE_COMPLET"))
        await liste.charger()
        XCTAssertEqual(liste.affiches.map(\.id), ["a"])
        liste.choisir(.tous)
        XCTAssertEqual(liste.affiches.map(\.id), ["a", "b"], "filtre local, aucune relecture")
        let lectures = port.compte("contrats")
        XCTAssertEqual(lectures, 1)
        port.poser(liste: .failure(JoleneError(.network, "Connexion impossible.")))
        await liste.charger()
        XCTAssertEqual(liste.etat, .echec("Connexion impossible."))
    }
}
