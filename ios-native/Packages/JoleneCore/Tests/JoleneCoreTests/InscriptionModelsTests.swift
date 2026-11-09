import XCTest
@testable import JoleneCore

/// Identité confirmée sans espace soignant, restaurée par les ports d'auth de ces tests.
private let nouveauCompte = AuthenticatedUser(id: "u-nouveau", email: "nouveau@example.invalid",
                                              emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000))

/// Port d'inscription scripté : chaque appel consomme une étape de sa file et est journalisé (sans mot de passe,
/// seulement sa longueur). `retenue` retient les appels jusqu'à son ouverture par le test.
final class ScriptedInscription: InscriptionPort, @unchecked Sendable {
    private let lock = NSLock()
    var creations: [Result<ResultatCompte, Error>] = []
    var confirmations: [Result<ResultatConfirmation, Error>] = []
    var contextes: [Result<ContexteOnboarding?, Error>] = []
    var parcoursLus: [Result<ParcoursInscription?, Error>] = []
    var demarrages: [Result<ParcoursInscription, Error>] = []
    private var appelsRecus: [String] = []
    private var intentionsRecues: [IntentionInscription] = []
    let entree = Gate()
    var retenue: Gate?

    var appels: [String] { lock.lock(); defer { lock.unlock() }; return appelsRecus }
    var intentions: [IntentionInscription] { lock.lock(); defer { lock.unlock() }; return intentionsRecues }

    private func etape<T>(_ nom: String, _ file: ReferenceWritableKeyPath<ScriptedInscription, [Result<T, Error>]>,
                          intention: IntentionInscription? = nil) async throws -> T {
        let resultat: Result<T, Error> = {
            lock.lock(); defer { lock.unlock() }
            appelsRecus.append(nom)
            if let intention { intentionsRecues.append(intention) }
            return self[keyPath: file].isEmpty ? .failure(nonScripte) : self[keyPath: file].removeFirst()
        }()
        await entree.open()
        if let retenue { await retenue.wait() }
        return try resultat.get()
    }

    func creerCompte(email: String, motDePasse: String, intention: IntentionInscription) async throws -> ResultatCompte {
        try await etape("creerCompte(\(email), \(motDePasse.count))", \.creations, intention: intention)
    }
    func confirmer(_ credentials: AuthCallbackCredentials) async throws -> ResultatConfirmation {
        try await etape("confirmer", \.confirmations)
    }
    func contexte() async throws -> ContexteOnboarding? { try await etape("contexte", \.contextes) }
    func parcours(userId: String) async throws -> ParcoursInscription? { try await etape("parcours(\(userId))", \.parcoursLus) }
    func demarrer(intention: IntentionInscription) async throws -> ParcoursInscription {
        try await etape("demarrer(\(intention.profession ?? "-"))", \.demarrages, intention: intention)
    }
    func enregistrerBrouillon(_ brouillon: FormulaireInscription) async throws -> ParcoursInscription { throw nonScripte }
    func typesExercice(profession: String) async throws -> [String]? { throw nonScripte }
    func finaliser(_ formulaire: FormulaireInscription) async throws -> ResultatFinalisation { throw nonScripte }
}

/// Modèles de l'inscription native (lot 3, T7) : compte rapide (`InscriptionRapide.tsx` l.55-115), lien de
/// confirmation (`ConfirmationInscription.tsx`, D10) et aiguillage d'onboarding (`ParcoursInscription.tsx`).
@MainActor
final class InscriptionModelsTests: XCTestCase {
    private typealias T = InscriptionTextes

    private struct AuthNouveauCompte: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { nouveauCompte }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { nouveauCompte }
        func signOut() async throws {}
    }

    private func controleur(_ port: ScriptedInscription, auth: AuthPort = NeutralAuth(),
                            timeout: TimeInterval = SessionController.defaultResolutionTimeout) -> SessionController {
        var gateways = Gateways(auth: auth, role: NeutralRole(), missions: NeutralMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.inscription = port
        return SessionController(gateways: gateways, resolutionTimeout: timeout)
    }

    private func formulaireValide(_ model: InscriptionRapideModel) {
        model.email = "  Nouveau@Example.Invalid "
        model.motDePasse = "motdepasse-8"
        model.profession = "IDE"
        model.cgu = true
    }

    private static let parcoursSoignant = ParcoursInscription(userId: "u-nouveau", typeCompte: "SOIGNANT",
                                                              brouillon: FormulaireInscription(profession: "IDE"),
                                                              consentementCguLe: "2026-11-02T00:00:00+00:00",
                                                              modifieLe: "2026-11-02T00:00:00+00:00")

    // MARK: - Compte rapide

    func testSaisieInvalideNAppelleRienEtFocaliseLePremierChamp() async {
        let port = ScriptedInscription()
        let model = InscriptionRapideModel(controller: controleur(port))
        model.email = "pas-un-email"
        let issue = await model.soumettre()
        XCTAssertNil(issue)
        XCTAssertEqual(model.erreurs, [.email: T.erreurEmail, .motDePasse: T.erreurMotDePasse,
                                       .profession: T.erreurProfession, .cgu: T.erreurCGU])
        XCTAssertEqual(model.champAFocaliser, .email)
        XCTAssertTrue(port.appels.isEmpty, "aucun appel tant que la saisie est refusée")
        XCTAssertEqual(model.libelleBouton, T.creerMonCompte)
    }

    func testCreationEnvoieEmailNormaliseEtIntentionPuisAfficheLaConfirmation() async {
        let port = ScriptedInscription()
        port.creations = [.success(.confirmationEnvoyee)]
        let model = InscriptionRapideModel(controller: controleur(port))
        formulaireValide(model)
        let issue = await model.soumettre()
        XCTAssertNil(issue, "lien envoyé : l'écran reste affiché avec le message")
        XCTAssertEqual(port.appels, ["creerCompte(nouveau@example.invalid, 12)"])
        XCTAssertEqual(port.intentions, [IntentionInscription(typeCompte: "SOIGNANT", profession: "IDE", nom: "", cgu: true, cgv: false)])
        XCTAssertEqual(model.etape, .confirmationEnvoyee)
        XCTAssertEqual(model.libelleBouton, T.jaiConfirme)
        XCTAssertTrue(model.erreurs.isEmpty)
        XCTAssertNil(model.erreurService)
        XCTAssertFalse(model.enCours)
    }

    func testApresLaConfirmationLeBoutonConnecteParMotDePasseSansSecondSignUp() async {
        let port = ScriptedInscription()
        port.creations = [.success(.confirmationEnvoyee)]
        let model = InscriptionRapideModel(controller: controleur(port))
        formulaireValide(model)
        _ = await model.soumettre()
        let issue = await model.soumettre()
        XCTAssertEqual(issue, .connexion(email: "nouveau@example.invalid", motDePasse: "motdepasse-8"))
        XCTAssertEqual(port.appels.count, 1, "jamais un second signUp (web l.63-68)")
    }

    func testCompteExistantProposeLaConnexion() async {
        let port = ScriptedInscription()
        port.creations = [.success(.connexionRequise)]
        let model = InscriptionRapideModel(controller: controleur(port))
        formulaireValide(model)
        let issue1 = await model.soumettre()
        XCTAssertNil(issue1)
        XCTAssertEqual(model.etape, .connexionRequise)
        XCTAssertEqual(model.erreurService, T.compteExistant)
        XCTAssertEqual(model.libelleBouton, T.seConnecterEtContinuer)
        let issue2 = await model.soumettre()
        XCTAssertEqual(issue2, .connexion(email: "nouveau@example.invalid", motDePasse: "motdepasse-8"))
        XCTAssertEqual(port.appels.count, 1)
    }

    func testModifierLEmailRevientALaSaisie() async {
        let port = ScriptedInscription()
        port.creations = [.success(.confirmationEnvoyee)]
        let model = InscriptionRapideModel(controller: controleur(port))
        formulaireValide(model)
        _ = await model.soumettre()
        XCTAssertEqual(model.etape, .confirmationEnvoyee)
        model.email = "autre@example.invalid"
        XCTAssertEqual(model.etape, .saisie, "web l.165-169")
        XCTAssertEqual(model.libelleBouton, T.creerMonCompte)
    }

    func testSessionOuverteParLeSignUpDemarreLeParcours() async {
        let port = ScriptedInscription()
        port.creations = [.success(.sessionOuverte)]
        port.demarrages = [.success(Self.parcoursSoignant)]
        let model = InscriptionRapideModel(controller: controleur(port))
        formulaireValide(model)
        let issue = await model.soumettre()
        XCTAssertEqual(issue, .parcoursDemarre)
        XCTAssertEqual(port.appels, ["creerCompte(nouveau@example.invalid, 12)", "demarrer(IDE)"])
        XCTAssertEqual(port.intentions.last?.cgu, true, "consentement transmis à fn_demarrer_inscription (p_cgu)")
        XCTAssertEqual(model.motDePasse, "", "mot de passe effacé après la création (web l.87)")
    }

    func testRefusDuDemarrageAfficheLeMessageSansIssue() async {
        let port = ScriptedInscription()
        port.creations = [.success(.sessionOuverte)]
        port.demarrages = [.failure(InscriptionRules.refusDemarrage(sqlstate: "23505", messageServeur: "ACCOUNT_ALREADY_REGISTERED"))]
        let model = InscriptionRapideModel(controller: controleur(port))
        formulaireValide(model)
        let issue3 = await model.soumettre()
        XCTAssertNil(issue3)
        XCTAssertEqual(model.erreurService, T.compteDejaEspace)
        XCTAssertFalse(model.refusCaptcha)
    }

    func testRefusCaptchaSignaleUnSeulAppelEtLeMessageGenerique() async {
        let port = ScriptedInscription()
        port.creations = [.failure(InscriptionRules.refusCreation(messageServeur: "captcha protection: request disallowed",
                                                                  codeServeur: "captcha_failed"))]
        let model = InscriptionRapideModel(controller: controleur(port))
        formulaireValide(model)
        let issue4 = await model.soumettre()
        XCTAssertNil(issue4)
        XCTAssertTrue(model.refusCaptcha)
        XCTAssertEqual(model.erreurService, T.erreurInattendue)
        XCTAssertEqual(model.etape, .saisie)
        XCTAssertEqual(port.appels.count, 1, "aucun renvoi automatique")
    }

    func testDelaiDepasseAfficheLeTexteReseauSansRenvoi() async {
        let port = ScriptedInscription()
        port.creations = [.success(.confirmationEnvoyee)]
        port.retenue = Gate()
        let model = InscriptionRapideModel(controller: controleur(port, timeout: 0.05))
        formulaireValide(model)
        let issue5 = await model.soumettre()
        XCTAssertNil(issue5)
        XCTAssertEqual(model.erreurService, T.connexionInstable)
        XCTAssertEqual(model.etape, .saisie, "issue inconnue : jamais une confirmation supposée")
        XCTAssertEqual(port.appels.count, 1)
        await port.retenue?.open()
    }

    func testUnSeulEnvoiALaFois() async {
        let port = ScriptedInscription()
        port.creations = [.success(.confirmationEnvoyee), .success(.confirmationEnvoyee)]
        port.retenue = Gate()
        let model = InscriptionRapideModel(controller: controleur(port))
        formulaireValide(model)
        let premier = Task { await model.soumettre() }
        await port.entree.wait()
        XCTAssertTrue(model.enCours)
        XCTAssertEqual(model.libelleBouton, T.creationEnCours)
        let second = await model.soumettre()
        XCTAssertNil(second)
        await port.retenue?.open()
        _ = await premier.value
        XCTAssertEqual(port.appels.count, 1, "second appui ignoré pendant l'envoi")
    }

    func testModeSessionOuverteNeCreeAucunCompte() async {
        let port = ScriptedInscription()
        port.demarrages = [.success(Self.parcoursSoignant)]
        let model = InscriptionRapideModel(controller: controleur(port), mode: .sessionOuverte(email: "nouveau@example.invalid"))
        XCTAssertFalse(model.saisitIdentifiants)
        XCTAssertEqual(model.email, "nouveau@example.invalid")
        model.profession = "AS"
        let issue6 = await model.soumettre()
        XCTAssertNil(issue6, "consentement manquant")
        XCTAssertEqual(model.erreurs, [.cgu: T.erreurCGU])
        model.cgu = true
        let issue7 = await model.soumettre()
        XCTAssertEqual(issue7, .parcoursDemarre)
        XCTAssertEqual(port.appels, ["demarrer(AS)"])
    }

    func testProfessionPreRemplieDepuisLeLien() {
        let model = InscriptionRapideModel(controller: controleur(ScriptedInscription()),
                                           profession: InscriptionRules.professionDepuisLien(EtapeInscription(page: .soignant, query: "profession=KINE")))
        XCTAssertEqual(model.profession, "KINE")
    }

    // MARK: - Lien de confirmation

    func testConfirmationOuvreLaSessionUneSeuleFois() async {
        let port = ScriptedInscription()
        port.confirmations = [.success(.sessionOuverte), .success(.sessionOuverte)]
        let model = ConfirmationInscriptionModel(controller: controleur(port),
                                                 credentials: .tokenHash(tokenHash: "h", otpType: "signup"))
        XCTAssertEqual(model.etat, .verification)
        await model.confirmer()
        await model.confirmer()
        XCTAssertEqual(model.etat, .confirme)
        XCTAssertEqual(port.appels, ["confirmer"], "code à usage unique : un seul échange par lien")
    }

    func testLienSansFormatReconnuRefuseSansAppel() async {
        let port = ScriptedInscription()
        let model = ConfirmationInscriptionModel(controller: controleur(port), credentials: nil)
        await model.confirmer()
        XCTAssertEqual(model.etat, .refuse(T.lienNonValide))
        XCTAssertTrue(port.appels.isEmpty)
    }

    func testLienRefuseOuEchecRendLeTexteWeb() async {
        let refuse = ScriptedInscription()
        refuse.confirmations = [.success(.lienRefuse(message: T.lienNonValide))]
        let premier = ConfirmationInscriptionModel(controller: controleur(refuse), credentials: .pkce(code: "c"))
        await premier.confirmer()
        XCTAssertEqual(premier.etat, .refuse(T.lienNonValide))

        let echec = ScriptedInscription()
        echec.confirmations = [.failure(JoleneError(.network, "x"))]
        let second = ConfirmationInscriptionModel(controller: controleur(echec), credentials: .pkce(code: "c"))
        await second.confirmer()
        XCTAssertEqual(second.etat, .refuse(T.lienNonValide), "le compte a pu être confirmé par /verify : « Se connecter »")
    }

    // MARK: - Aiguillage d'onboarding

    private func contexte(intention: IntentionInscription?) -> ContexteOnboarding {
        ContexteOnboarding(userId: "u-nouveau", email: "nouveau@example.invalid", emailConfirme: true, intention: intention)
    }

    func testParcoursSoignantMeneALaCompletion() async {
        let port = ScriptedInscription()
        port.contextes = [.success(contexte(intention: nil))]
        port.parcoursLus = [.success(Self.parcoursSoignant)]
        let model = OnboardingModel(controller: controleur(port))
        await model.chargerSiNecessaire()
        XCTAssertEqual(model.etat, .completerSoignant(Self.parcoursSoignant))
        XCTAssertEqual(port.appels, ["contexte", "parcours(u-nouveau)"])
    }

    func testIntentionSansParcoursDemarreLeParcours() async {
        let port = ScriptedInscription()
        let intention = InscriptionRules.intention(profession: "IDE", cgu: true)
        port.contextes = [.success(contexte(intention: intention))]
        port.parcoursLus = [.success(nil)]
        port.demarrages = [.success(Self.parcoursSoignant)]
        let model = OnboardingModel(controller: controleur(port))
        await model.charger()
        XCTAssertEqual(model.etat, .completerSoignant(Self.parcoursSoignant))
        XCTAssertEqual(port.appels, ["contexte", "parcours(u-nouveau)", "demarrer(IDE)"])
        XCTAssertEqual(port.intentions, [intention])
    }

    func testSansIntentionNiParcoursChoixDEspace() async {
        let port = ScriptedInscription()
        port.contextes = [.success(contexte(intention: nil))]
        port.parcoursLus = [.success(nil)]
        let model = OnboardingModel(controller: controleur(port))
        await model.charger()
        XCTAssertEqual(model.etat, .choixEspace(email: "nouveau@example.invalid"))
        XCTAssertFalse(port.appels.contains { $0.hasPrefix("demarrer") })
    }

    func testIntentionEtablissementRenvoieAuWebSansDemarrer() async {
        let port = ScriptedInscription()
        port.contextes = [.success(contexte(intention: IntentionInscription(typeCompte: "ETABLISSEMENT", profession: "",
                                                                             nom: "Clinique", cgu: true, cgv: true)))]
        port.parcoursLus = [.success(nil)]
        let model = OnboardingModel(controller: controleur(port))
        await model.charger()
        XCTAssertEqual(model.etat, .espaceEtablissement)
        XCTAssertEqual(port.appels, ["contexte", "parcours(u-nouveau)"])
    }

    func testEchecDeLectureOuDeDemarrageRendLErreurWebPuisReessayer() async {
        let port = ScriptedInscription()
        port.contextes = [.success(contexte(intention: InscriptionRules.intention(profession: "IDE", cgu: true))),
                          .success(contexte(intention: nil))]
        port.parcoursLus = [.success(nil), .success(Self.parcoursSoignant)]
        port.demarrages = [.failure(InscriptionRules.refusDemarrage(sqlstate: "22023", messageServeur: "Choisissez votre profession."))]
        let model = OnboardingModel(controller: controleur(port))
        await model.charger()
        XCTAssertEqual(model.etat, .erreur)
        await model.chargerSiNecessaire()
        XCTAssertEqual(model.etat, .erreur, "un échec attend « Réessayer »")
        await model.charger()
        XCTAssertEqual(model.etat, .completerSoignant(Self.parcoursSoignant))
    }

    func testContexteAbsentEstUneErreur() async {
        let port = ScriptedInscription()
        port.contextes = [.success(nil)]
        let model = OnboardingModel(controller: controleur(port))
        await model.charger()
        XCTAssertEqual(model.etat, .erreur)
    }

    func testReponseArriveeApresUnChangementDIdentiteIgnoree() async {
        let port = ScriptedInscription()
        port.contextes = [.success(contexte(intention: nil))]
        port.parcoursLus = [.success(Self.parcoursSoignant)]
        port.retenue = Gate()
        let controller = controleur(port, auth: AuthNouveauCompte())
        _ = await controller.start()
        let model = OnboardingModel(controller: controller)
        let chargement = Task { await model.charger() }
        await port.entree.wait()
        _ = await controller.signOut()
        await port.retenue?.open()
        await chargement.value
        XCTAssertEqual(model.etat, .chargement, "rien n'est publié pour l'identité partie")
        XCTAssertEqual(port.appels, ["contexte"], "aucune lecture de plus pour l'identité partie")
    }

    func testNouvelleIdentiteRelitLAiguillageMemeIdentiteNon() async {
        let port = ScriptedInscription()
        port.contextes = [.success(contexte(intention: nil)), .success(contexte(intention: nil))]
        port.parcoursLus = [.success(Self.parcoursSoignant), .success(nil)]
        let controller = controleur(port, auth: AuthNouveauCompte())
        _ = await controller.start()
        let model = OnboardingModel(controller: controller)
        await model.chargerSiNecessaire()
        XCTAssertEqual(model.etat, .completerSoignant(Self.parcoursSoignant))
        await model.chargerSiNecessaire()
        XCTAssertEqual(port.appels.count, 2, "même identité : aucune relecture")
        _ = await controller.signOut()
        _ = await controller.signIn(email: "autre@example.invalid", password: "x")
        await model.chargerSiNecessaire()
        XCTAssertEqual(model.etat, .choixEspace(email: "nouveau@example.invalid"), "identité changée : état relu")
        XCTAssertEqual(port.appels.count, 4)
    }

    // MARK: - Point d'extension des liens

    func testLiensDInscriptionConsommesHorsDeLEspace() throws {
        let boite = BoiteLiensInscription()
        let confirmer = try XCTUnwrap(DestinationLien(link: "https://jolene.app/inscription/confirmer?token_hash=h&type=signup"))
        XCTAssertTrue(boite.recevoir(confirmer))
        XCTAssertEqual(boite.confirmation?.credentials, .tokenHash(tokenHash: "h", otpType: "signup"))
        let premier = boite.confirmation?.id
        XCTAssertTrue(boite.recevoir(confirmer))
        XCTAssertNotEqual(boite.confirmation?.id, premier, "un lien reçu à nouveau est une nouvelle tentative")
        boite.retirerConfirmation()
        XCTAssertNil(boite.confirmation)

        let soignant = try XCTUnwrap(DestinationLien(link: "/inscription/soignant?profession=IDE"))
        XCTAssertTrue(boite.recevoir(soignant))
        XCTAssertEqual(boite.inscription, EtapeInscription(page: .soignant, query: "profession=IDE"))
        boite.retirerInscription()
        XCTAssertTrue(boite.recevoir(try XCTUnwrap(DestinationLien(link: "/inscription/reprendre"))))
        XCTAssertEqual(boite.inscription?.page, .reprendre)

        // T8 : la complétion est consommée comme la reprise ; route de l'espace : non consommée.
        boite.retirerInscription()
        XCTAssertTrue(boite.recevoir(try XCTUnwrap(DestinationLien(link: "/inscription/completer?ref=ABCD-12"))))
        XCTAssertEqual(boite.inscription, EtapeInscription(page: .completer, query: "ref=ABCD-12"))
        boite.retirerInscription()
        XCTAssertFalse(boite.recevoir(try XCTUnwrap(DestinationLien(link: "/soignant/missions"))))
        XCTAssertNil(boite.inscription)
        XCTAssertNil(boite.confirmation)
    }
}
