import XCTest
@testable import JoleneCore

/// Identité confirmée sans espace soignant (rôle `INCONNU` jusqu'à la création du profil par le serveur simulé).
private let compteCompletion = AuthenticatedUser(id: "u-completion", email: "completion@example.invalid",
                                                 emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000))

/// Serveur simulé : le profil soignant n'existe qu'après une finalisation acceptée (ou une issue inconnue qui l'a créé).
private actor ServeurCompletion {
    private(set) var profilCree = false
    private(set) var lecturesRole = 0
    func creerProfil() { profilCree = true }
    func lireRole() -> String {
        lecturesRole += 1
        return profilCree ? UserRole.soignant.rawValue : "INCONNU"
    }
}

private struct AuthCompletion: AuthPort {
    func restoreSession() async throws -> AuthenticatedUser? { compteCompletion }
    func signIn(email: String, password: String) async throws -> AuthenticatedUser { compteCompletion }
    func signOut() async throws {}
}

private struct RoleCompletion: RolePort {
    let serveur: ServeurCompletion
    func currentRole() async throws -> RoleResult { RoleResult(role: await serveur.lireRole()) }
}

private struct MissionsCompletion: MissionsPort {
    let serveur: ServeurCompletion
    func profile(userId: String) async throws -> SoignantProfile? {
        await serveur.profilCree ? SoignantProfile(id: userId, profession: "IDE") : nil
    }
    func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
    func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
}

/// Port d'inscription scripté pour la complétion (T8) : référentiel, brouillon et finalisation consomment leur file ;
/// chaque formulaire transmis est conservé (aucune donnée n'est journalisée hors du test).
private final class CompletionScriptee: InscriptionPort, @unchecked Sendable {
    private let lock = NSLock()
    var types: [Result<[String]?, Error>] = []
    var brouillons: [Result<Void, Error>] = []
    var finalisations: [Result<ResultatFinalisation, Error>] = []
    /// L'issue inconnue a quand même créé le profil côté serveur.
    var creeAvantErreur = false
    /// `.finalisee` crée le profil (faux : profil créé mais rôle relu sans espace, revue B8 de T8, m5).
    var creeSurFinalisee = true
    var retenue: Gate?
    /// Retient la lecture du référentiel (annulation du `.task`, revue B8 de T8, m2).
    var retenueTypes: Gate?
    let serveur: ServeurCompletion
    private var appelsRecus: [String] = []
    private var formulairesRecus: [FormulaireInscription] = []

    init(serveur: ServeurCompletion) { self.serveur = serveur }

    var appels: [String] { lock.lock(); defer { lock.unlock() }; return appelsRecus }
    var formulaires: [FormulaireInscription] { lock.lock(); defer { lock.unlock() }; return formulairesRecus }

    private func noter(_ appel: String, _ formulaire: FormulaireInscription? = nil) {
        lock.lock(); defer { lock.unlock() }
        appelsRecus.append(appel)
        if let formulaire { formulairesRecus.append(formulaire) }
    }

    private func suivant<T>(_ file: ReferenceWritableKeyPath<CompletionScriptee, [Result<T, Error>]>) -> Result<T, Error> {
        lock.lock(); defer { lock.unlock() }
        return self[keyPath: file].isEmpty ? .failure(nonScripte) : self[keyPath: file].removeFirst()
    }

    func creerCompte(email: String, motDePasse: String, intention: IntentionInscription) async throws -> ResultatCompte { throw nonScripte }
    func confirmer(_ credentials: AuthCallbackCredentials) async throws -> ResultatConfirmation { throw nonScripte }
    func contexte() async throws -> ContexteOnboarding? { throw nonScripte }
    func parcours(userId: String) async throws -> ParcoursInscription? { throw nonScripte }
    func demarrer(intention: IntentionInscription) async throws -> ParcoursInscription { throw nonScripte }

    func typesExercice(profession: String) async throws -> [String]? {
        noter("typesExercice(\(profession))")
        let resultat = suivant(\.types)
        if let retenueTypes { await retenueTypes.wait() }
        return try resultat.get()
    }

    func enregistrerBrouillon(_ brouillon: FormulaireInscription) async throws -> ParcoursInscription {
        noter("enregistrerBrouillon", brouillon)
        try suivant(\.brouillons).get()
        return ParcoursInscription(userId: compteCompletion.id, typeCompte: "SOIGNANT", brouillon: brouillon)
    }

    func finaliser(_ formulaire: FormulaireInscription) async throws -> ResultatFinalisation {
        noter("finaliser", formulaire)
        let resultat = suivant(\.finalisations)
        if let retenue { await retenue.wait() }
        if case .success(.finalisee) = resultat, creeSurFinalisee { await serveur.creerProfil() }
        if case .success(.indeterminee) = resultat, creeAvantErreur { await serveur.creerProfil() }
        if case .failure = resultat, creeAvantErreur { await serveur.creerProfil() }
        return try resultat.get()
    }
}

/// Complétion du profil soignant (lot 3, T8) : saisie depuis le brouillon, profession figée, modes par le référentiel,
/// garde du formulaire web, finalisation relue (rôle puis `.ready`), refus verbatim, déconnexion locale du 503, issue
/// inconnue relue, un seul envoi, réponse d'une identité partie ignorée.
@MainActor
final class CompletionProfilModelTests: XCTestCase {
    private typealias T = CompletionTextes

    /// 9 novembre 2026, 12:00 UTC.
    nonisolated private static let maintenant = Date(timeIntervalSince1970: 1_794_225_600)

    private static func parcours(_ brouillon: FormulaireInscription, userId: String = compteCompletion.id) -> ParcoursInscription {
        ParcoursInscription(userId: userId, typeCompte: "SOIGNANT", brouillon: brouillon,
                            consentementCguLe: "2026-11-02T00:00:00+00:00", modifieLe: "2026-11-02T00:00:00+00:00")
    }

    private static let brouillonComplet = FormulaireInscription(prenom: "Léa", nom: "Martin", telephone: "0612345678",
                                                                dateNaissance: "1990-05-14", profession: "IDE",
                                                                typesContrat: ["CDD"])

    private final class Annonces { var messages: [String] = [] }

    private struct Scenario {
        let model: CompletionProfilModel
        let session: SessionStore
        let port: CompletionScriptee
        let serveur: ServeurCompletion
        let annonces: Annonces
    }

    private func scenario(_ brouillon: FormulaireInscription = brouillonComplet,
                          timeout: TimeInterval = SessionController.defaultResolutionTimeout,
                          userIdParcours: String = compteCompletion.id) async -> Scenario {
        let serveur = ServeurCompletion()
        let port = CompletionScriptee(serveur: serveur)
        var gateways = Gateways(auth: AuthCompletion(), role: RoleCompletion(serveur: serveur),
                                missions: MissionsCompletion(serveur: serveur), clock: FixedClock(DemoWorld.fixedNow))
        gateways.inscription = port
        let session = SessionStore(controller: SessionController(gateways: gateways, resolutionTimeout: timeout))
        await session.start()
        let annonces = Annonces()
        let model = CompletionProfilModel(session: session, parcours: Self.parcours(brouillon, userId: userIdParcours),
                                          maintenant: { Self.maintenant },
                                          annoncerDeconnexion: { annonces.messages.append($0) })
        return Scenario(model: model, session: session, port: port, serveur: serveur, annonces: annonces)
    }

    private func estBloque(_ session: SessionStore) -> Bool {
        if case .blocked = session.state { return true }
        return false
    }

    // MARK: - Saisie initiale

    func testSaisieInitialiseeDepuisLeBrouillonProfessionFigee() async {
        let s = await scenario(FormulaireInscription(prenom: "Léa", nom: "Martin", telephone: "06 12 34 56 78",
                                                     dateNaissance: "1990-02-30", profession: "AES", typesContrat: ["CDD"],
                                                     rpps: "12345678901", rayon: 25))
        XCTAssertTrue(estBloque(s.session), "identité sans espace soignant : aiguillage d'onboarding")
        XCTAssertEqual(s.model.prenom, "Léa")
        XCTAssertEqual(s.model.telephone, "06 12 34 56 78")
        XCTAssertNil(s.model.dateNaissance, "date illisible du brouillon : jamais affichée comme saisie")
        XCTAssertEqual(s.model.profession, "AES")
        XCTAssertTrue(s.model.professionValide)
        XCTAssertFalse(s.model.afficheRpps, "AES : aucun RPPS demandé")
        XCTAssertEqual(s.model.rpps, "", "`PROFESSIONS_SANS_RPPS` hors AS : numéro vidé (l.203-208)")
        XCTAssertEqual(s.model.typesContrat, ["CDD"])
        XCTAssertNil(s.model.estSalarieEtablissement, "aucune réponse supposée")
        XCTAssertEqual(s.model.formulaire.rayon, 25, "rayon du brouillon retransmis tel quel")
        XCTAssertEqual(s.model.formulaire.rpps, "")
        XCTAssertTrue(s.port.appels.isEmpty)
        s.model.rpps = "10 00-1234 5678 999"
        XCTAssertEqual(s.model.rpps, "10001234567", "saisie filtrée (chiffres, 11 au plus)")
    }

    func testProfessionHorsCatalogueBloqueLaFinalisation() async {
        let s = await scenario(FormulaireInscription(prenom: "Léa", profession: "INCONNUE"))
        XCTAssertFalse(s.model.professionValide)
        let issue = await s.model.finaliser()
        XCTAssertNil(issue)
        XCTAssertTrue(s.port.appels.isEmpty, "contrat rompu : aucun appel")
    }

    // MARK: - Référentiel des modes

    func testReferentielRetireLeLiberalNonProposeEtAfficheLaPhraseDuTypeUnique() async {
        let s = await scenario(FormulaireInscription(prenom: "Léa", profession: "AS", typesContrat: ["CDD", "LIBERAL"]))
        s.port.types = [.success(["SALARIE"])]
        await s.model.verifierModes()
        XCTAssertEqual(s.port.appels, ["typesExercice(AS)"])
        XCTAssertEqual(s.model.modes, .disponibles(["SALARIE"]))
        XCTAssertEqual(s.model.typesContrat, ["CDD"], "libéral retiré : non proposé par le référentiel (l.191-199)")
        XCTAssertEqual(s.model.choixModes.options.map(\.mode), [.salarie])
        XCTAssertTrue(s.model.choixModes.liberalNonPropose)
        XCTAssertEqual(s.model.phraseTypeUnique,
                       "En tant que Aide-Soignant(e) (AS), votre type d'exercice est automatiquement défini comme salarié.")
        XCTAssertFalse(s.model.reessaiModesPossible)
    }

    func testReferentielIndisponibleConserveLesChoixSansAjoutDuLiberalPuisReessai() async {
        let s = await scenario(FormulaireInscription(prenom: "Léa", profession: "IDE", typesContrat: ["CDD", "LIBERAL"]))
        s.port.types = [.failure(JoleneError(.network, "Le service ne répond pas.")), .success(nil),
                        .success(["SALARIE", "LIBERAL", "MIXTE"])]
        await s.model.verifierModes()
        XCTAssertEqual(s.model.modes, .indisponible)
        XCTAssertTrue(s.model.choixModes.indisponible)
        XCTAssertTrue(s.model.reessaiModesPossible, "« Réessayer la vérification » du web")
        XCTAssertEqual(s.model.typesContrat, ["CDD", "LIBERAL"], "« Vos choix sont conservés » (ChoixModesExercice.tsx l.43)")
        XCTAssertNil(s.model.phraseTypeUnique)
        s.model.basculerMode(.liberal, selectionne: false)
        XCTAssertEqual(s.model.choixModes.options.map(\.mode), [.salarie], "libéral décoché : plus proposé sans référentiel")
        s.model.basculerMode(.liberal, selectionne: true)
        s.model.basculerMode(.liberal, selectionne: false)
        await s.model.verifierModes()
        XCTAssertEqual(s.model.modes, .indisponible, "réponse qui n'est pas un tableau : indisponible")
        await s.model.verifierModes()
        XCTAssertEqual(s.model.modes, .disponibles(["SALARIE", "LIBERAL", "MIXTE"]))
        XCTAssertEqual(s.model.choixModes.options.map(\.mode), [.salarie, .liberal], "libéral proposé après confirmation")
        s.model.basculerMode(.salarie, selectionne: false)
        XCTAssertEqual(s.model.typesContrat, [], "inscription : la liste peut être vidée, refusée à l'envoi")
        XCTAssertTrue(s.model.choixModes.aucunMode)
    }

    // MARK: - Garde du formulaire

    func testSaisieIncompleteAfficheLaListeDuWebSansAucunAppel() async {
        let s = await scenario(FormulaireInscription(profession: "MEDECIN"))
        XCTAssertNil(s.model.erreurDateNaissance, "aucun message avant la première tentative")
        let issue = await s.model.finaliser()
        XCTAssertNil(issue)
        XCTAssertEqual(s.model.erreur,
                       "Vérifiez les informations suivantes : prénom, nom, téléphone valide, date de naissance (18 ans minimum), mode d’exercice, numéro RPPS à 11 chiffres.")
        XCTAssertEqual(s.model.erreurDateNaissance, T.dateNaissanceObligatoire, "l.555 : après une tentative")
        XCTAssertTrue(s.port.appels.isEmpty, "aucun appel tant que la saisie est refusée")
        XCTAssertGreaterThan(s.model.annonces, 0, "encart annoncé à VoiceOver")
        s.model.telephone = "06"
        XCTAssertEqual(s.model.erreurTelephone, T.telephoneInvalide)
        s.model.dateNaissance = "2010-01-01"
        XCTAssertEqual(s.model.erreurDateNaissance, T.dateNaissanceMineur)
    }

    // MARK: - Finalisation

    func testFinaliseeRelitLeRoleEtOuvreLEspace() async throws {
        let s = await scenario()
        s.port.finalisations = [.success(.finalisee(soignantId: compteCompletion.id))]
        s.model.estSalarieEtablissement = true
        let issue = await s.model.finaliser()
        XCTAssertEqual(issue, .espaceOuvert)
        guard case let .ready(snapshot) = s.session.state else { return XCTFail("espace relu attendu : \(s.session.state)") }
        XCTAssertEqual(snapshot.user.id, compteCompletion.id)
        XCTAssertEqual(s.port.appels, ["finaliser"])
        let envoye = try XCTUnwrap(s.port.formulaires.first)
        // Revue B8 de T8, m4 : la réponse « salarié(e) » part dans le brouillon comme sur le web (`donneesFormulaire`) ;
        // `register-soignant` ne la reçoit jamais (`CompletionRules.corpsFinalisation`, correction 21).
        XCTAssertEqual(envoye, FormulaireInscription(prenom: "Léa", nom: "Martin", telephone: "0612345678", dateNaissance: "1990-05-14",
                                                     profession: "IDE", typesContrat: ["CDD"], rpps: "", rayon: nil,
                                                     estSalarieEtablissement: true),
                       "profession du parcours ; déclaration étudiant jamais réécrite")
        XCTAssertNil(CompletionRules.corpsFinalisation(envoye)["estSalarieEtablissement"])
        XCTAssertNil(s.model.erreur)
        XCTAssertTrue(s.annonces.messages.isEmpty)
    }

    // MARK: - Revue fraîche B8 de T8

    /// B1 : un brouillon étudiant (« Je suis étudiant(e) » sur le web, `estEtudiant: true`) n'est jamais finalisé en
    /// natif — sans cela `register-soignant` écrirait `est_etudiant = false` (index.ts l.309) et l'établissement ne
    /// verrait plus le cadre étudiant. Verrou explicite (CLAUDE.md, « un gap connu reste verrouillé ») : aucun appel,
    /// aucun texte nouveau ; seule la complétion web est proposée (D11).
    func testBrouillonEtudiantVerrouilleLaFinalisationNativeSansAucunAppel() async {
        let s = await scenario(FormulaireInscription(prenom: "Léa", nom: "Martin", telephone: "0612345678",
                                                     dateNaissance: "1990-05-14", profession: "AS", typesContrat: ["CDD"],
                                                     estEtudiant: true))
        XCTAssertTrue(s.model.parcoursEtudiant, "déclaration étudiant du brouillon serveur")
        s.port.finalisations = [.success(.finalisee(soignantId: compteCompletion.id))]
        let issue = await s.model.finaliser()
        XCTAssertNil(issue)
        XCTAssertTrue(s.port.appels.isEmpty, "verrou D11 : ni brouillon ni register-soignant")
        XCTAssertNil(s.model.erreur, "aucun texte nouveau : l'écran ne propose que la complétion web")
        XCTAssertTrue(estBloque(s.session), "jamais d'espace ouvert pour un parcours étudiant natif")
        XCTAssertNil(s.model.formulaire.estEtudiant, "la déclaration n'est jamais réécrite par le natif")
        let sansDeclaration = await scenario(FormulaireInscription(profession: "AS", estEtudiant: false))
        XCTAssertFalse(sansDeclaration.model.parcoursEtudiant)
    }

    /// B1 : le brouillon relu par le serveur au moment de la finalisation (déclaration faite sur le web pendant que
    /// l'écran natif restait ouvert) prime : `.parcoursEtudiant` bascule l'écran vers la complétion web, sans message.
    func testBrouillonDevenuEtudiantAuServeurBasculeVersLaCompletionWeb() async {
        let s = await scenario()
        XCTAssertFalse(s.model.parcoursEtudiant)
        s.port.finalisations = [.success(.parcoursEtudiant)]
        let issue = await s.model.finaliser()
        XCTAssertNil(issue)
        XCTAssertTrue(s.model.parcoursEtudiant, "verrou D11 posé par la relecture serveur")
        XCTAssertNil(s.model.erreur)
        XCTAssertFalse(s.model.enCours)
        let second = await s.model.finaliser()
        XCTAssertNil(second)
        XCTAssertEqual(s.port.appels, ["finaliser"], "plus aucun envoi natif ensuite")
    }

    /// M1, cas 2 : 409 `ACCOUNT_ALREADY_REGISTERED` (renvoi après une issue inconnue, délai côté client pendant que
    /// l'edge termine, ou complétion faite sur le web) prouve un profil existant : rôle relu puis espace ouvert, jamais
    /// l'impasse « Connectez-vous pour continuer » d'un utilisateur déjà connecté.
    func testCompteDejaFinaliseRelitLeRoleEtOuvreLEspace() async {
        let s = await scenario()
        let message = "Ce compte soignant existe déjà. Connectez-vous pour continuer."
        s.port.finalisations = [.success(.indeterminee(message: message))]
        s.port.creeAvantErreur = true
        let issue = await s.model.finaliser()
        XCTAssertEqual(issue, .espaceOuvert)
        if case .ready = s.session.state {} else { XCTFail("espace relu attendu : \(s.session.state)") }
        XCTAssertNil(s.model.erreur, "le profil existe : aucun message")
        XCTAssertEqual(s.port.appels, ["finaliser"], "aucun renvoi")
    }

    /// M1, cas 1 : 5xx illisible (passerelle, délai de l'edge) = issue inconnue. Sans profil relu, le message (repli
    /// verbatim du web) est affiché, saisie conservée ; avec un profil relu, l'espace s'ouvre.
    func testIssueIndetermineeSansProfilAfficheLeMessageApresRelecture() async {
        let s = await scenario()
        s.port.finalisations = [.success(.indeterminee(message: T.saisieConservee))]
        let lecturesAvant = await s.serveur.lecturesRole
        let issue = await s.model.finaliser()
        XCTAssertNil(issue)
        let lecturesApres = await s.serveur.lecturesRole
        XCTAssertEqual(lecturesApres, lecturesAvant + 1, "issue inconnue : rôle relu une fois (PRINCIPES §5)")
        XCTAssertEqual(s.model.erreur, T.saisieConservee)
        XCTAssertEqual(s.model.prenom, "Léa")
        XCTAssertTrue(estBloque(s.session))
    }

    /// M1 : au retour du renvoi web étudiant (complétion terminée sur `/inscription/completer`), le rôle est relu ;
    /// un profil créé sur le web ouvre l'espace sans aucun envoi natif, sinon rien n'est affiché.
    func testRetourDuRenvoiWebRelitLeRole() async {
        let s = await scenario(FormulaireInscription(profession: "AS", estEtudiant: true))
        let sansProfil = await s.model.relireApresRenvoiWeb()
        XCTAssertNil(sansProfil)
        XCTAssertNil(s.model.erreur, "retour sans complétion : aucun message")
        XCTAssertTrue(estBloque(s.session))
        await s.serveur.creerProfil()
        let issue = await s.model.relireApresRenvoiWeb()
        XCTAssertEqual(issue, .espaceOuvert)
        if case .ready = s.session.state {} else { XCTFail("espace relu attendu : \(s.session.state)") }
        XCTAssertTrue(s.port.appels.isEmpty, "aucun appel du port d'inscription : relecture du rôle seulement")
    }

    /// m2 : un `.task` coupé pendant la lecture du référentiel (feuille plein écran présentée, vue démontée) ne laisse
    /// pas l'écran bloqué sur « Vérification… » : l'état repart à `.inactif`, que le `.task` suivant relance.
    func testLectureDuReferentielAnnuleeRevientAInactif() async {
        let s = await scenario()
        let retenue = Gate()
        s.port.retenueTypes = retenue
        s.port.types = [.success(["SALARIE", "LIBERAL", "MIXTE"]), .success(["SALARIE", "LIBERAL", "MIXTE"])]
        let lecture = Task { await s.model.verifierModes() }
        while s.model.modes != .chargement { await Task.yield() }
        lecture.cancel()
        await lecture.value
        XCTAssertEqual(s.model.modes, .inactif, "annulation : jamais un chargement sans fin")
        await retenue.open()
        s.port.retenueTypes = nil
        await s.model.verifierModes()
        XCTAssertEqual(s.model.modes, .disponibles(["SALARIE", "LIBERAL", "MIXTE"]), "relance effective")
    }

    /// m4 : la réponse « salarié(e) » est restaurée depuis le brouillon (web l.135-138) : l'avertissement d'exclusivité
    /// survit à la reprise.
    func testReponseSalarieRestaureeDepuisLeBrouillon() async {
        let s = await scenario(FormulaireInscription(prenom: "Léa", profession: "IDE", estSalarieEtablissement: true))
        XCTAssertEqual(s.model.estSalarieEtablissement, true)
        XCTAssertEqual(s.model.formulaire.estSalarieEtablissement, true)
        s.model.estSalarieEtablissement = false
        XCTAssertEqual(s.model.formulaire.estSalarieEtablissement, false)
    }

    /// m5 : profil créé (200) mais rôle relu sans espace : même issue que l'échec de `refreshSession` — message annoncé
    /// à la connexion puis déconnexion locale (« Votre profil est enregistré. Reconnectez-vous… », web l.236), jamais
    /// une invitation à se reconnecter sans déconnexion.
    func testProfilCreeMaisRoleNonReluDeconnecteLocalement() async {
        let s = await scenario()
        s.port.creeSurFinalisee = false
        s.port.finalisations = [.success(.finalisee(soignantId: compteCompletion.id))]
        let issue = await s.model.finaliser()
        XCTAssertEqual(issue, .deconnecte(message: T.profilEnregistreReconnecter))
        XCTAssertEqual(s.annonces.messages, [T.profilEnregistreReconnecter])
        XCTAssertEqual(s.session.state, .signedOut(message: nil), "déconnexion locale, comme l'échec de refreshSession")
    }

    /// m6 : l'epoch n'est capturé que pour l'identité du parcours ; une session d'un autre utilisateur n'envoie jamais le
    /// brouillon de ce parcours.
    func testSessionDUnAutreUtilisateurQueLeParcoursNEnvoieRien() async {
        let s = await scenario(userIdParcours: "autre-utilisateur")
        s.port.finalisations = [.success(.finalisee(soignantId: "autre-utilisateur"))]
        s.port.brouillons = [.success(())]
        let issue = await s.model.finaliser()
        XCTAssertNil(issue)
        let brouillon = await s.model.enregistrerPlusTard()
        XCTAssertFalse(brouillon)
        XCTAssertTrue(s.port.appels.isEmpty, "aucun envoi pour une identité qui n'est pas celle du parcours")
    }

    func testRefusServeurAfficheLeMessageVerbatimSansRelecture() async {
        let s = await scenario()
        let message = "Vous devez avoir au moins 18 ans pour vous inscrire."
        s.port.finalisations = [.success(.refusee(code: "UNDERAGE", message: message))]
        let lecturesAvant = await s.serveur.lecturesRole
        let issue = await s.model.finaliser()
        XCTAssertNil(issue)
        XCTAssertEqual(s.model.erreur, message, "message serveur verbatim")
        let lecturesApres = await s.serveur.lecturesRole
        XCTAssertEqual(lecturesApres, lecturesAvant, "refus certain : aucune relecture")
        XCTAssertTrue(estBloque(s.session))
        XCTAssertEqual(s.model.prenom, "Léa", "saisie conservée")
        XCTAssertFalse(s.model.enCours)
    }

    func testFinalisationEnAttenteAnnonceLeMessagePuisDeconnecteLocalement() async {
        let s = await scenario()
        let message = "Votre profil est enregistré. Reconnectez-vous pour reprendre votre espace."
        s.port.finalisations = [.success(.finalisationEnAttente(message: message))]
        let issue = await s.model.finaliser()
        XCTAssertEqual(issue, .deconnecte(message: message))
        XCTAssertEqual(s.annonces.messages, [message], "message transmis à l'écran de connexion")
        XCTAssertEqual(s.session.state, .signedOut(message: nil), "déconnexion locale")
    }

    func testIssueInconnueAvecProfilCreeOuvreLEspace() async {
        let s = await scenario()
        s.port.finalisations = [.failure(JoleneError(.network, SessionController.timeoutMessage))]
        s.port.creeAvantErreur = true
        let issue = await s.model.finaliser()
        XCTAssertEqual(issue, .espaceOuvert, "rôle relu : le profil existe, l'espace s'ouvre sans nouvel envoi")
        XCTAssertEqual(s.port.appels, ["finaliser"], "jamais un renvoi automatique")
        if case .ready = s.session.state {} else { XCTFail("espace relu attendu") }
    }

    func testIssueInconnueSansProfilAfficheLeTexteDuWebEtConserveLaSaisie() async {
        let s = await scenario()
        s.port.finalisations = [.failure(JoleneError(.network, "Le service ne répond pas.")),
                                .failure(JoleneError(.contract, "Réponse inattendue."))]
        let premiere = await s.model.finaliser()
        XCTAssertNil(premiere)
        XCTAssertEqual(s.model.erreur, InscriptionTextes.connexionInstable)
        XCTAssertEqual(s.model.prenom, "Léa")
        let seconde = await s.model.finaliser()
        XCTAssertNil(seconde)
        XCTAssertEqual(s.model.erreur, T.saisieConservee, "issue illisible : « Votre saisie est conservée. Réessayez. »")
        XCTAssertTrue(estBloque(s.session), "jamais d'espace ouvert sans profil relu")
        XCTAssertEqual(s.port.appels, ["finaliser", "finaliser"], "un envoi par appui")
    }

    func testRefusDuBrouillonEtSessionExpireeAffichesSansRelecture() async {
        let s = await scenario()
        s.port.finalisations = [.failure(RefusInscription(code: "SQLSTATE_P0002", message: "Inscription introuvable.")),
                                .failure(JoleneError(.unauthorized, T.sessionAbsente))]
        _ = await s.model.finaliser()
        XCTAssertEqual(s.model.erreur, "Inscription introuvable.", "exception serveur verbatim")
        _ = await s.model.finaliser()
        XCTAssertEqual(s.model.erreur, T.sessionAbsente)
        let lectures = await s.serveur.lecturesRole
        XCTAssertEqual(lectures, 1, "seule la résolution initiale de la session a lu le rôle")
    }

    func testUnSeulEnvoiALaFois() async {
        let s = await scenario()
        let retenue = Gate()
        s.port.retenue = retenue
        s.port.finalisations = [.success(.refusee(code: "RATE_LIMITED", message: "Trop de tentatives. Réessayez dans quelques minutes."))]
        let premier = Task { await s.model.finaliser() }
        while s.port.appels.isEmpty { await Task.yield() }
        XCTAssertTrue(s.model.enCours)
        let second = await s.model.finaliser()
        XCTAssertNil(second, "second appui pendant l'envoi : ignoré")
        let brouillon = await s.model.enregistrerPlusTard()
        XCTAssertFalse(brouillon, "aucun brouillon pendant la finalisation")
        await retenue.open()
        _ = await premier.value
        XCTAssertEqual(s.port.appels, ["finaliser"])
        XCTAssertEqual(s.model.erreur, "Trop de tentatives. Réessayez dans quelques minutes.")
    }

    func testReponseDUneIdentitePartieIgnoree() async {
        let s = await scenario()
        let retenue = Gate()
        s.port.retenue = retenue
        s.port.finalisations = [.success(.refusee(code: "UNDERAGE", message: "refus tardif"))]
        let envoi = Task { await s.model.finaliser() }
        while s.port.appels.isEmpty { await Task.yield() }
        await s.session.signOut()
        await retenue.open()
        let issue = await envoi.value
        XCTAssertNil(issue)
        XCTAssertNil(s.model.erreur, "réponse pour une identité partie : rien n'est affiché")
    }

    // MARK: - Brouillon

    func testEnregistrerPlusTardEnvoieLeBrouillonRelu() async throws {
        let s = await scenario(FormulaireInscription(prenom: "Léa", profession: "IDE", typesContrat: ["CDD"], rayon: 30))
        s.port.brouillons = [.success(()), .failure(RefusInscription(code: "SQLSTATE_22023", message: "Brouillon invalide."))]
        s.model.nom = "Martin"
        let reussi = await s.model.enregistrerPlusTard()
        XCTAssertTrue(reussi)
        let envoye = try XCTUnwrap(s.port.formulaires.first)
        XCTAssertEqual(envoye.nom, "Martin")
        XCTAssertEqual(envoye.profession, "IDE")
        XCTAssertEqual(envoye.rayon, 30)
        XCTAssertNil(s.model.erreur)
        let refuse = await s.model.enregistrerPlusTard()
        XCTAssertFalse(refuse)
        XCTAssertEqual(s.model.erreur, "Brouillon invalide.", "message serveur verbatim")
    }
}
