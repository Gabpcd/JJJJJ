import XCTest
@testable import JoleneCore

/// Récupération du mot de passe (reste de L1-T10) : formats du lien, aiguillage, quarantaine de la session de
/// récupération, refus, non-révélation de la demande de lien, relecture après changement, textes verbatim.
@MainActor
final class ReinitialisationTests: XCTestCase {

    // MARK: - Port scripté

    /// Port de récupération scripté : journal des appels (sans valeur secrète), issues programmées.
    actor PortScripte: RecoveryPort {
        enum Appel: Equatable { case demande(String), ouverture, miseAJour, fermeture }
        private(set) var appels: [Appel] = []
        var issueOuverture: Result<RecoveryOutcome, JoleneError> = .success(.sessionOuverte)
        var issueMiseAJour: JoleneError?
        var issueFermeture: JoleneError?
        var issueDemande: JoleneError?
        /// Session de récupération tenue par le port (preuve de la quarantaine : ouverte, puis toujours refermée).
        private(set) var sessionOuverte = false

        func programmer(ouverture: Result<RecoveryOutcome, JoleneError>? = nil, miseAJour: JoleneError? = nil,
                        fermeture: JoleneError? = nil, demande: JoleneError? = nil) {
            if let ouverture { issueOuverture = ouverture }
            issueMiseAJour = miseAJour
            issueFermeture = fermeture
            issueDemande = demande
        }

        func requestReset(email: String) async throws {
            appels.append(.demande(email))
            if let issueDemande { throw issueDemande }
        }

        func openRecoverySession(_ credentials: AuthCallbackCredentials) async throws -> RecoveryOutcome {
            appels.append(.ouverture)
            let issue = try issueOuverture.get()
            sessionOuverte = issue == .sessionOuverte
            return issue
        }

        func updatePassword(_ password: String) async throws {
            appels.append(.miseAJour)
            if let issueMiseAJour { throw issueMiseAJour }
        }

        func signOutAfterRecovery() async throws {
            appels.append(.fermeture)
            sessionOuverte = false
            if let issueFermeture { throw issueFermeture }
        }
    }

    private static let lien = AuthCallbackCredentials.tokenHash(tokenHash: "h", otpType: "recovery")
    private static let nouveau = ["Nouveau", "-mdp-", "2026"].joined()

    private func modele(_ port: PortScripte, credentials: AuthCallbackCredentials? = lien) -> ReinitialisationModel {
        ReinitialisationModel(port: { port }, credentials: credentials)
    }

    // MARK: - Formats du lien (trois formats du web, `?code=` refusé)

    func testLesTroisFormatsDuWebSontDecodesEtSeulPKCEEstRefuse() throws {
        XCTAssertEqual(AuthCallbackCredentials.recovery(link: "/reset-password?token_hash=h&type=recovery"),
                       .tokenHash(tokenHash: "h", otpType: "recovery"))
        XCTAssertEqual(AuthCallbackCredentials.recovery(link: "/reset-password#access_token=a&refresh_token=r&type=recovery"),
                       .implicit(accessToken: "a", refreshToken: "r"))
        XCTAssertEqual(AuthCallbackCredentials.recovery(link: "/reset-password?code=c"), .pkce(code: "c"))
        XCTAssertNil(AuthCallbackCredentials.recovery(link: "/reset-password#access_token=a&refresh_token=r"),
                     "session implicit sans marqueur recovery : jamais acceptée")
        XCTAssertNil(AuthCallbackCredentials.recovery(link: "/reset-password?token_hash=h&type=signup"))

        let aiguillage = AiguillageLiens(taps: BoiteTapsPush())
        let boite = BoiteLiensInscription()
        for lien in ["https://jolene.app/reset-password?token_hash=h&type=recovery",
                     "https://jolene.app/reset-password#access_token=a&refresh_token=r&type=recovery",
                     "https://jolene.app/reset-password"] {
            let url = try XCTUnwrap(URL(string: lien))
            guard case .inscription(let destination)? = aiguillage.recevoir(url: url) else {
                return XCTFail("lien de réinitialisation présenté hors de l'espace : \(LienMasque.gabarit(url))")
            }
            XCTAssertTrue(boite.recevoir(destination))
            XCTAssertNotNil(boite.reinitialisation)
            XCTAssertNil(boite.confirmation, "jamais confondu avec la confirmation d'inscription")
        }
        XCTAssertNil(boite.reinitialisation.flatMap { $0.credentials }, "dernier lien reçu : sans identifiants")
        XCTAssertEqual(aiguillage.recevoir(url: try XCTUnwrap(URL(string: "https://jolene.app/reset-password?code=c"))),
                       .refusReinitialisation, "option B inchangée")
        let pkce = try XCTUnwrap(DestinationLien(link: "/reset-password?code=c"))
        boite.retirerReinitialisation()
        XCTAssertFalse(boite.recevoir(pkce), "la boîte ne présente jamais un lien `?code=`")
        XCTAssertNil(boite.reinitialisation)
    }

    /// Revue B8 tour 2 (mineur 5) : un même lien reçu deux fois pendant que sa demande est présentée n'ouvre pas de
    /// seconde tentative (qui révoquerait la première et consommerait de nouveau le `token_hash`) ; un lien différent,
    /// ou le même après fermeture de l'écran, en ouvre une.
    func testMemeLienRecuDeuxFoisNOuvreQuUneTentative() throws {
        let boite = BoiteLiensInscription()
        let lien = try XCTUnwrap(DestinationLien(link: "/reset-password?token_hash=h&type=recovery"))
        XCTAssertTrue(boite.recevoir(lien))
        let premiere = try XCTUnwrap(boite.reinitialisation)
        XCTAssertTrue(boite.recevoir(lien), "toujours consommé par la boîte, jamais présenté ailleurs")
        XCTAssertEqual(boite.reinitialisation, premiere, "lien identique : même demande, aucune nouvelle tentative")

        let implicite = try XCTUnwrap(DestinationLien(link: "/reset-password#access_token=a&refresh_token=r&type=recovery"))
        XCTAssertTrue(boite.recevoir(implicite))
        XCTAssertEqual(boite.reinitialisation?.credentials, .implicit(accessToken: "a", refreshToken: "r"))
        let deuxieme = try XCTUnwrap(boite.reinitialisation)
        XCTAssertNotEqual(deuxieme.id, premiere.id, "lien différent : nouvelle tentative")
        XCTAssertTrue(boite.recevoir(implicite))
        XCTAssertEqual(boite.reinitialisation, deuxieme)

        let autreHash = try XCTUnwrap(DestinationLien(link: "/reset-password?token_hash=h2&type=recovery"))
        XCTAssertTrue(boite.recevoir(autreHash))
        XCTAssertNotEqual(boite.reinitialisation?.id, deuxieme.id, "un seul caractère d'écart : nouvelle tentative")

        boite.retirerReinitialisation()
        XCTAssertTrue(boite.recevoir(autreHash))
        XCTAssertNotNil(boite.reinitialisation, "après fermeture, le même lien ouvre une nouvelle tentative")

        let sansIdentifiants = try XCTUnwrap(DestinationLien(link: "/reset-password"))
        XCTAssertTrue(boite.recevoir(sansIdentifiants))
        let refus = try XCTUnwrap(boite.reinitialisation)
        XCTAssertNil(refus.credentials)
        XCTAssertTrue(boite.recevoir(sansIdentifiants))
        XCTAssertNotEqual(boite.reinitialisation?.id, refus.id, "sans identifiants : refus sans appel, non dédoublonné")
    }

    // MARK: - Quarantaine et refus

    func testSansIdentifiantsRefusSansAucunAppel() async {
        let port = PortScripte()
        let m = modele(port, credentials: nil)
        await m.ouvrir()
        XCTAssertEqual(m.etat, .lienInvalide)
        let appels = await port.appels
        XCTAssertEqual(appels, [], "sans preuve recovery, aucun appel (web l.73-76)")
    }

    func testLienRefuseDonneLeRefusEtNOuvreJamaisLeFormulaire() async {
        let port = PortScripte()
        await port.programmer(ouverture: .success(.lienRefuse(message: ReinitialisationTextes.lienInvalideDetail)))
        let m = modele(port)
        await m.ouvrir()
        XCTAssertEqual(m.etat, .lienInvalide)
        XCTAssertFalse(m.peutEnregistrer(nouveau: Self.nouveau, confirmation: Self.nouveau))
        await m.enregistrer(nouveau: Self.nouveau, confirmation: Self.nouveau)
        let appels = await port.appels
        XCTAssertFalse(appels.contains(.miseAJour))
        let ouverte = await port.sessionOuverte
        XCTAssertFalse(ouverte)
    }

    func testErreurDeVerificationFermeToutEtRefuse() async {
        let port = PortScripte()
        await port.programmer(ouverture: .failure(JoleneError(.network, "x")))
        let m = modele(port)
        await m.ouvrir()
        XCTAssertEqual(m.etat, .lienInvalide, "jamais un état à moitié ouvert")
        let appels = await port.appels
        XCTAssertEqual(appels, [.ouverture, .fermeture])
    }

    func testAbandonFermeLaSessionDeRecuperationEtInterditLaMiseAJour() async {
        let port = PortScripte()
        let m = modele(port)
        await m.ouvrir()
        XCTAssertEqual(m.etat, .formulaire)
        var ouverte = await port.sessionOuverte
        XCTAssertTrue(ouverte)
        await m.abandonner()
        await m.abandonner()
        ouverte = await port.sessionOuverte
        XCTAssertFalse(ouverte, "abandon : session de récupération fermée")
        await m.enregistrer(nouveau: Self.nouveau, confirmation: Self.nouveau)
        let appels = await port.appels
        XCTAssertEqual(appels, [.ouverture, .fermeture], "une seule fermeture, aucune mise à jour après l'abandon")
        XCTAssertFalse(m.estTermine, "l'abandon ne mène jamais au succès")
        XCTAssertEqual(m.etat, .lienInvalide, "envoi après fermeture : refus affiché, jamais ignoré en silence")
    }

    /// Écran retiré sans issue (fermeture par la racine, lien remplacé) : la session de récupération est fermée à la
    /// libération du modèle, plus sur `onDisappear` (émis aussi sur l'écran encore affiché, iOS 18). Une issue déjà
    /// fermée ne refait aucun appel.
    func testModeleLibereSansIssueFermeLaSessionUneSeuleFois() async throws {
        let port = PortScripte()
        var m: ReinitialisationModel? = modele(port)
        await m?.ouvrir()
        XCTAssertEqual(m?.etat, .formulaire)
        m = nil
        try await attendreFermeture(port)
        var appels = await port.appels
        XCTAssertEqual(appels, [.ouverture, .fermeture], "modèle libéré : session fermée")

        let autre = PortScripte()
        var abandonne: ReinitialisationModel? = modele(autre)
        await abandonne?.ouvrir()
        await abandonne?.abandonner()
        abandonne = nil
        try await Task.sleep(nanoseconds: 200_000_000)
        appels = await autre.appels
        XCTAssertEqual(appels, [.ouverture, .fermeture], "déjà fermée par l'abandon : aucune seconde fermeture")
    }

    private func attendreFermeture(_ port: PortScripte) async throws {
        for _ in 0..<100 {
            if await port.appels.contains(.fermeture) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testReglesDuWebSeulementHuitUnitesEtConfirmationIdentique() async {
        let port = PortScripte()
        let m = modele(port)
        await m.ouvrir()
        XCTAssertFalse(m.peutEnregistrer(nouveau: "1234567", confirmation: "1234567"))
        XCTAssertFalse(m.peutEnregistrer(nouveau: "12345678", confirmation: "12345679"))
        XCTAssertTrue(m.peutEnregistrer(nouveau: "12345678", confirmation: "12345678"), "aucune règle inventée")
        XCTAssertTrue(ReinitialisationRules.afficherNonCorrespondance(nouveau: "12345678", confirmation: "1"))
        XCTAssertFalse(ReinitialisationRules.afficherNonCorrespondance(nouveau: "12345678", confirmation: ""))
        await m.enregistrer(nouveau: "1234567", confirmation: "1234567")
        let appels = await port.appels
        XCTAssertEqual(appels, [.ouverture])
    }

    func testSuccesEnregistrementPuisFermetureDansCetOrdre() async {
        let port = PortScripte()
        let m = modele(port)
        await m.ouvrir()
        await m.enregistrer(nouveau: Self.nouveau, confirmation: Self.nouveau)
        XCTAssertEqual(m.etat, .succes)
        XCTAssertTrue(m.estTermine)
        let appels = await port.appels
        XCTAssertEqual(appels, [.ouverture, .miseAJour, .fermeture])
        let ouverte = await port.sessionOuverte
        XCTAssertFalse(ouverte, "après succès, la session de récupération est fermée")
        await m.abandonner()
        let apres = await port.appels
        XCTAssertEqual(apres.count, 3, "aucune seconde fermeture")
    }

    func testRefusServeurAfficheVerbatimEtGardeLaQuarantaine() async {
        let port = PortScripte()
        let message = MotDePasse.messageRefus(code: "weak_password", message: "Password is known to be weak")
        await port.programmer(miseAJour: JoleneError(.invalidCredentials, message))
        let m = modele(port)
        await m.ouvrir()
        await m.enregistrer(nouveau: Self.nouveau, confirmation: Self.nouveau)
        XCTAssertEqual(m.etat, .formulaire)
        XCTAssertEqual(m.erreur, MotDePasse.Textes.motDePasseTropFaible)
        XCTAssertFalse(m.estTermine)
        await m.abandonner()
        let appels = await port.appels
        XCTAssertEqual(appels, [.ouverture, .miseAJour, .fermeture])
    }

    func testSessionDeRecuperationExpireePendantLaMiseAJourDonneLeRefus() async {
        let port = PortScripte()
        await port.programmer(miseAJour: JoleneError(.unauthorized, ReinitialisationTextes.lienInvalideDetail))
        let m = modele(port)
        await m.ouvrir()
        await m.enregistrer(nouveau: Self.nouveau, confirmation: Self.nouveau)
        XCTAssertEqual(m.etat, .lienInvalide)
        let appels = await port.appels
        XCTAssertEqual(appels, [.ouverture, .miseAJour, .fermeture])
    }

    func testFermetureEchoueeApresSuccesDonneLeMessageDuWeb() async {
        let port = PortScripte()
        await port.programmer(fermeture: JoleneError(.network, "x"))
        let m = modele(port)
        await m.ouvrir()
        await m.enregistrer(nouveau: Self.nouveau, confirmation: Self.nouveau)
        XCTAssertEqual(m.etat, .succesSessionNonFermee)
        XCTAssertTrue(m.estTermine)
    }

    // MARK: - Monde démo : quarantaine vis-à-vis de l'authentification

    func testDemoLaSessionDeRecuperationNOuvreAucuneIdentite() async throws {
        let gateways = DemoWorld.gateways()
        XCTAssertTrue(gateways.recovery is DemoRecoveryGateway)
        let m = ReinitialisationModel(port: { gateways.recovery },
                                      credentials: .tokenHash(tokenHash: DemoRecoveryGateway.tokenHashDemo, otpType: "recovery"))
        await m.ouvrir()
        XCTAssertEqual(m.etat, .formulaire)
        let identite = try await gateways.auth.restoreSession()
        XCTAssertNil(identite, "la session de récupération n'ouvre aucune identité de l'app")
        await m.enregistrer(nouveau: DemoRecoveryGateway.nouveauRefuse, confirmation: DemoRecoveryGateway.nouveauRefuse)
        XCTAssertEqual(m.erreur, MotDePasse.Textes.motDePasseTropFaible)
        await m.enregistrer(nouveau: Self.nouveau, confirmation: Self.nouveau)
        XCTAssertEqual(m.etat, .succes)
        let demo = try XCTUnwrap(gateways.recovery as? DemoRecoveryGateway)
        let ouverte = await demo.sessionOuverte
        let enregistre = await demo.motDePasseEnregistre
        XCTAssertFalse(ouverte)
        XCTAssertTrue(enregistre)
        let apres = try await gateways.auth.restoreSession()
        XCTAssertNil(apres)
    }

    func testDemoRefuseToutAutreLien() async throws {
        let demo = DemoRecoveryGateway()
        for lien: AuthCallbackCredentials in [.tokenHash(tokenHash: "autre", otpType: "recovery"),
                                              .tokenHash(tokenHash: "demo", otpType: "signup"),
                                              .implicit(accessToken: "a", refreshToken: "r"), .pkce(code: "demo")] {
            let issue = try await demo.openRecoverySession(lien)
            XCTAssertEqual(issue, .lienRefuse(message: ReinitialisationTextes.lienInvalideDetail))
        }
        do {
            try await demo.updatePassword(Self.nouveau)
            XCTFail("aucune mise à jour sans session de récupération")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
    }

    // MARK: - Demande de lien : non-révélation, délai, refus

    func testDemandeMemeReponseQueLeCompteExisteOuNon() async {
        var etats: [[String?]] = []
        for adresse in ["  Inscrite@Example.TEST ", "inconnue@example.test"] {
            let port = PortScripte()
            let m = DemandeReinitialisationModel(email: adresse, port: { port })
            await m.envoyer()
            let normalise = ReinitialisationRules.emailNormalise(adresse)
            let appels = await port.appels
            XCTAssertEqual(appels, [.demande(normalise)])
            XCTAssertEqual(m.email, normalise)
            XCTAssertEqual(m.messageEnvoye, ReinitialisationTextes.lienEnvoye(a: normalise))
            etats.append([m.annonce, m.erreur, m.libelleBouton, m.messageEnvoye?.replacingOccurrences(of: normalise, with: "…")])
        }
        XCTAssertEqual(etats[0], etats[1], "aucune différence à l'écran selon l'existence du compte")
        XCTAssertEqual(etats[0][0], ReinitialisationTextes.demandeEnvoyee)
    }

    func testDemandeDelaiDeSoixanteSecondesPuisRenvoi() async {
        let port = PortScripte()
        let m = DemandeReinitialisationModel(email: "a@example.test", port: { port })
        XCTAssertEqual(m.libelleBouton, ReinitialisationTextes.envoyerLeLien)
        await m.envoyer()
        XCTAssertEqual(m.disponibleDans, 60)
        XCTAssertEqual(m.libelleBouton, "Renvoyer dans 60 s")
        XCTAssertFalse(m.peutEnvoyer)
        await m.envoyer()
        let appels = await port.appels
        XCTAssertEqual(appels.count, 1, "aucun envoi pendant le délai")
        for _ in 0..<60 { m.seconde() }
        XCTAssertEqual(m.libelleBouton, ReinitialisationTextes.renvoyerLeLien)
        XCTAssertTrue(m.peutEnvoyer)
        m.email = "b@example.test"
        XCTAssertNil(m.messageEnvoye, "changer l'adresse efface la confirmation (web l.355-357)")
        XCTAssertEqual(m.libelleBouton, ReinitialisationTextes.envoyerLeLien)
    }

    func testDemandeAdresseInvalideSansAppelEtRefusServeurVerbatim() async {
        let port = PortScripte()
        let m = DemandeReinitialisationModel(email: "pas-une-adresse", port: { port })
        await m.envoyer()
        XCTAssertEqual(m.erreur, ReinitialisationTextes.emailInvalide)
        let aucun = await port.appels
        XCTAssertEqual(aucun, [])
        XCTAssertFalse(DemandeReinitialisationModel(email: "   ", port: { port }).peutEnvoyer)

        let limite = MotDePasse.messageRefus(code: "over_email_send_rate_limit", message: "Email rate limit exceeded")
        await port.programmer(demande: JoleneError(.invalidCredentials, limite))
        m.email = "a@example.test"
        await m.envoyer()
        XCTAssertEqual(m.erreur, "Trop de tentatives. Veuillez patienter quelques minutes.")
        XCTAssertNil(m.messageEnvoye)
        XCTAssertEqual(m.disponibleDans, 0)
    }

    func testRegleEmailDuWeb() {
        XCTAssertTrue(ReinitialisationRules.emailValide("a@b.fr"))
        XCTAssertTrue(ReinitialisationRules.emailValide(" A@B.FR "))
        XCTAssertFalse(ReinitialisationRules.emailValide("a@b.f"))
        XCTAssertFalse(ReinitialisationRules.emailValide("a b@c.fr"))
        XCTAssertFalse(ReinitialisationRules.emailValide("a@b.fr1"))
    }

    // MARK: - Textes verbatim

    func testChaqueTexteRepriseDuWebEstVerbatimASaLigne() throws {
        typealias T = ReinitialisationTextes
        let connexion = "src/pages/PageConnexion.tsx"
        let reset = "src/pages/PageResetPassword.tsx"
        let attendus: [(String, String, Int)] = [
            (T.motDePasseOublie, connexion, 345), (T.emailDuCompte, connexion, 350), (T.emailPlaceholder, connexion, 359),
            (T.emailInvalide, connexion, 234), (T.demandeEnvoyee, connexion, 251),
            ("Si un compte existe pour <strong>{resetEnvoyeA}</strong>, le lien vient d’être envoyé.", connexion, 367),
            ("Vérifiez aussi les courriers indésirables.", connexion, 368),
            (T.envoi, connexion, 380), ("`Renvoyer dans ${resetDisponibleDans} s`", connexion, 382),
            (T.renvoyerLeLien, connexion, 384), (T.envoyerLeLien, connexion, 385), (T.retourConnexion, connexion, 397),
            ("setResetDisponibleDans(60)", connexion, 248), ("/^[^\\s@]{1,64}@[^\\s@]{1,255}\\.[a-z]{2,}$/i", connexion, 410),
            (T.titre, reset, 126), (T.verification, reset, 132), (T.lienInvalide, reset, 141),
            (T.lienInvalideDetail, reset, 143), (T.retourConnexion, reset, 146), (T.modifie, reset, 156),
            (T.consigne, reset, 164), (T.nouveau, reset, 168), (T.nouveauPlaceholder, reset, 176),
            (T.confirmation, reset, 193), (T.nonCorrespondance, reset, 207), (T.miseAJour, reset, 218),
            (T.soumettre, reset, 218), (T.modifieAvecSucces, reset, 108), (T.sessionNonFermee, reset, 103),
            ("motDePasse.length >= 8 && motDePasse === confirmMdp", reset, 86),
        ]
        var fichiers: [String: [String]] = [:]
        for (texte, chemin, ligne) in attendus {
            if fichiers[chemin] == nil { fichiers[chemin] = try CompteVerbatimTests.lignes(chemin) }
            let lignes = try XCTUnwrap(fichiers[chemin])
            XCTAssertTrue(lignes.indices.contains(ligne - 1) && lignes[ligne - 1].contains(texte),
                          "« \(texte) » absent de \(chemin):\(ligne)")
        }
        XCTAssertEqual(T.lienEnvoye(a: "x@y.fr"),
                       "Si un compte existe pour x@y.fr, le lien vient d’être envoyé. Vérifiez aussi les courriers indésirables.")
        XCTAssertEqual(T.renvoyerDans(12), "Renvoyer dans 12 s")
    }

    // MARK: - Rapports d'erreur : aucun secret du lien ni mot de passe

    func testLeNettoyeurMasqueLesLiensDeRecuperationEtLeMotDePasse() {
        let secrets = ["SECRETHASH1", "SECRETACCES2", "SECRETREFRESH3", "SECRETCODE4", Self.nouveau]
        let textes = [
            "https://jolene.app/reset-password?token_hash=SECRETHASH1&type=recovery",
            "https://jolene.app/reset-password#access_token=SECRETACCES2&refresh_token=SECRETREFRESH3&type=recovery",
            "https://jolene.app/reset-password?code=SECRETCODE4",
            #"{"password":"\#(Self.nouveau)"}"#,
            "implicit(accessToken: \"SECRETACCES2\", refreshToken: \"SECRETREFRESH3\")",
            "tokenHash(tokenHash: \"SECRETHASH1\", otpType: \"recovery\")",
        ]
        for texte in textes {
            let net = CrashScrubber.texte(texte)
            for secret in secrets { XCTAssertFalse(net.contains(secret), "secret visible après nettoyage : \(net)") }
        }
        XCTAssertFalse(String(describing: AuthCallbackCredentials.implicit(accessToken: "SECRETACCES2", refreshToken: "r"))
            .contains("SECRETACCES2"))
    }
}
