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
        private var attenteEnvoi: Duration = .zero
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
        func poser(signature: Result<IssueSignature, Error>) { avec { issueSignature = signature } }
        func poser(certificat: [SignatureCertificat], erreur: Error? = nil) { avec { certificatLignes = certificat; certificatErreur = erreur } }
        func poser(liste: Result<[ContratResume], Error>) { avec { issueListe = liste } }
        func poser(fichier: Result<URL, Error>) { avec { issueFichier = fichier } }

        func contrats(context: MissionReadContext) async throws -> [ContratResume] {
            try avec { journal.append("contrats"); return try issueListe.get() }
        }
        func contrat(id: String, context: MissionReadContext) async throws -> ContratDetail {
            try avec {
                journal.append("contrat")
                guard !details.isEmpty else { throw nonScripte }
                return details.count > 1 ? details.removeFirst() : details[0]
            }
        }
        func original(contrat: ContratDetail, context: MissionReadContext) async throws -> OriginalContrat {
            try avec { journal.append("original"); return try issueOriginal.get() }
        }
        func admissionRecette(contratId: String, context: MissionReadContext) async throws -> AdmissionSignatureRecette? {
            avec { journal.append("admission"); return issueAdmission }
        }
        func envoyerOtp(contratId: String, empreinte: String, context: MissionReadContext) async throws -> IssueEnvoiOtp {
            let attente = avec { journal.append("envoyerOtp"); return attenteEnvoi }
            if attente > .zero { try await Task.sleep(for: attente) }
            return try avec { try issueEnvoi.get() }
        }
        func signer(contratId: String, code: String, empreinte: String, context: MissionReadContext) async throws -> IssueSignature {
            try avec { journal.append("signer:\(code)"); return try issueSignature.get() }
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
