import XCTest
@testable import JoleneCore

// MARK: - Doubles du profil (T9)

/// Profil serveur simulé : lectures et écritures journalisées, réponses scriptées, barrière optionnelle.
actor ProfilServeur {
    var profil: ProfilComplet
    private(set) var lectures = 0
    private(set) var ecritures: [ModificationProfil] = []
    var erreurLecture: Error?
    var erreurEcriture: Error?
    /// Erreur de transport levée APRÈS l'application de l'écriture (le serveur a agi, la réponse est perdue).
    var perteReponseEcriture: Error?
    var barriereEcriture: Gate?

    init(profil: ProfilComplet) { self.profil = profil }

    func lire() throws -> ProfilComplet {
        lectures += 1
        if let erreurLecture { throw erreurLecture }
        return profil
    }

    func ecrire(_ champs: ModificationProfil) async throws -> ProfilComplet {
        ecritures.append(champs)
        if let barriereEcriture { await barriereEcriture.wait() }
        if let erreurEcriture { throw erreurEcriture }
        if let ville = champs.villeRecherche { profil.villeRecherche = ville }
        if let rayon = champs.rayonDeplacementKm { profil.rayonDeplacementKm = rayon }
        if let bio = champs.bio { profil.bio = bio }
        if let perteReponseEcriture { throw perteReponseEcriture }
        return try lire()
    }

    func sansProfession() { profil.profession = nil }

    func scripter(erreurLecture: Error? = nil, erreurEcriture: Error? = nil, perteReponse: Error? = nil, barriere: Gate? = nil) {
        self.erreurLecture = erreurLecture; self.erreurEcriture = erreurEcriture
        self.perteReponseEcriture = perteReponse; self.barriereEcriture = barriere
    }
}

struct FakeProfil: ProfilPort {
    let serveur: ProfilServeur
    func profil(context: MissionReadContext) async throws -> ProfilComplet { try await serveur.lire() }
    func modifier(_ champs: ModificationProfil, context: MissionReadContext) async throws -> ProfilComplet {
        try await serveur.ecrire(champs)
    }
}

/// `fn_types_exercice_autorises` seulement (le reste de l'inscription n'est pas scripté).
struct FakeTypesExercice: InscriptionPort {
    var types: Result<[String]?, Error>
    func creerCompte(email: String, motDePasse: String, intention: IntentionInscription) async throws -> ResultatCompte { throw nonScripte }
    func confirmer(_ credentials: AuthCallbackCredentials) async throws -> ResultatConfirmation { throw nonScripte }
    func contexte() async throws -> ContexteOnboarding? { throw nonScripte }
    func parcours(userId: String) async throws -> ParcoursInscription? { throw nonScripte }
    func demarrer(intention: IntentionInscription) async throws -> ParcoursInscription { throw nonScripte }
    func enregistrerBrouillon(_ brouillon: FormulaireInscription) async throws -> ParcoursInscription { throw nonScripte }
    func typesExercice(profession: String) async throws -> [String]? { try types.get() }
    func finaliser(_ formulaire: FormulaireInscription) async throws -> ResultatFinalisation { throw nonScripte }
}

/// Modèle de l'écran « Mon profil » (lot 3, T9) : lecture bornée, audit unique, enregistrement relu,
/// refus verbatim, relecture après un délai dépassé, epoch d'identité, modes d'exercice autorisés.
@MainActor
final class ProfilEditionModelTests: XCTestCase {
    private let utilisateur = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000))
    private let profilServeur = ProfilComplet(
        id: "u-1", prenom: "Léa", nom: "Martin", email: "u-1@example.invalid", profession: "IDE", rppsVerifie: false,
        rayonDeplacementKm: 40, villeRecherche: "Lyon", typesContratAcceptes: ["CDD", "LIBERAL"], anneesExperience: 3)

    private struct Scenario {
        var store: SessionStore
        var model: ProfilEditionModel
        var serveur: ProfilServeur
        var audit: FakeAudit
        var log: CallLog
    }

    private func scenario(audit: FakeAudit = FakeAudit(), types: Result<[String]?, Error> = .success(["SALARIE", "LIBERAL", "MIXTE"]),
                          inscription: InscriptionPort? = nil, timeout: TimeInterval = SessionController.defaultResolutionTimeout,
                          revalidation: Gate? = nil)
        async throws -> Scenario {
        let log = CallLog()
        let serveur = ProfilServeur(profil: profilServeur)
        var gateways = Lot1Fakes.gateways(audit: audit)
        // `revalidation` retient la 2e restauration de session (celle qui suit un enregistrement réussi).
        gateways.auth = FakeAuth(restored: utilisateur, signInResult: .success(utilisateur), log: log,
                                 restoreGate: revalidation, restoreGateFromCall: 2)
        gateways.role = FakeRole(result: .success(RoleResult(role: "SOIGNANT")), gate: nil, log: log)
        gateways.missions = FakeMissions(profile: SoignantProfile(id: "u-1", profession: "IDE"), profileError: nil, gate: nil, log: log)
        gateways.profil = FakeProfil(serveur: serveur)
        gateways.inscription = inscription ?? FakeTypesExercice(types: types)
        let store = SessionStore(controller: SessionController(gateways: gateways, resolutionTimeout: timeout))
        await store.start()
        let snapshot = try XCTUnwrap(store.state.snapshot, "session prête attendue, obtenu \(store.state)")
        return Scenario(store: store, model: ProfilEditionModel(session: store, snapshot: snapshot), serveur: serveur, audit: audit, log: log)
    }

    // MARK: - Lecture

    func testLectureRemplitLeFormulaireEtAuditeUneSeuleFoisParOuverture() async throws {
        let s = try await scenario()
        await s.model.charger()
        XCTAssertEqual(s.model.etat, .pret(profilServeur))
        XCTAssertEqual(s.model.formulaire, FormulaireProfil(profil: profilServeur))
        XCTAssertEqual(s.model.initial, FormulaireProfil(profil: profilServeur))
        XCTAssertTrue(s.model.modification.estVide)
        XCTAssertFalse(s.model.peutEnregistrer, "rien à enregistrer tant que rien n'a changé")
        await s.model.charger()
        let audits = await s.audit.journal.entries
        XCTAssertEqual(audits, ["DONNEES_PERSO_CONSULTATION soignant u-1"], "audit de consultation une fois par ouverture")
        // Une nouvelle ouverture (nouvelle instance du modèle) audite à nouveau.
        let snapshot = try XCTUnwrap(s.store.state.snapshot)
        await ProfilEditionModel(session: s.store, snapshot: snapshot).charger()
        let auditsApresReouverture = await s.audit.journal.entries.count
        XCTAssertEqual(auditsApresReouverture, 2)
    }

    func testAuditEnEchecNeBloqueJamaisLEcran() async throws {
        let s = try await scenario(audit: FakeAudit(erreur: JoleneError(.network, "hors ligne")))
        await s.model.charger()
        XCTAssertEqual(s.model.etat, .pret(profilServeur))
        XCTAssertNil(s.model.erreur)
    }

    func testEchecDeLectureAfficheLeMessageDuWebVouvoyePuisReessayer() async throws {
        let s = try await scenario()
        await s.serveur.scripter(erreurLecture: JoleneError(.unknown, "Profil introuvable"))
        await s.model.charger()
        XCTAssertEqual(s.model.etat, .echec("Votre profil n’a pas pu être chargé. Vous pouvez réessayer."))
        XCTAssertFalse(s.model.sessionExpiree)
        let audits = await s.audit.journal.entries
        XCTAssertTrue(audits.isEmpty, "aucun audit de consultation sans lecture réussie")
        await s.serveur.scripter()
        await s.model.charger()
        XCTAssertEqual(s.model.etat, .pret(profilServeur))
    }

    func testSessionExpireeALaLecture() async throws {
        let s = try await scenario()
        await s.serveur.scripter(erreurLecture: JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))
        await s.model.charger()
        XCTAssertEqual(s.model.etat, .echec("Votre session a expiré. Reconnectez-vous."))
        XCTAssertTrue(s.model.sessionExpiree)
    }

    func testEpochPerimeAucuneLecture() async throws {
        let s = try await scenario()
        await s.store.signOut()
        await s.model.charger()
        let lectures = await s.serveur.lectures
        XCTAssertEqual(lectures, 0)
        XCTAssertEqual(s.model.etat, .chargement)
    }

    // MARK: - Enregistrement

    func testEnregistrementEnvoieLaDifferencePuisAfficheLeProfilRelu() async throws {
        let s = try await scenario()
        await s.model.charger()
        s.model.formulaire.villeRecherche = "Grenoble"
        s.model.formulaire.rayonDeplacementKm = 25
        XCTAssertTrue(s.model.peutEnregistrer)
        let lecturesAvant = await s.serveur.lectures
        await s.model.enregistrer()
        let ecritures = await s.serveur.ecritures
        XCTAssertEqual(ecritures, [ModificationProfil(rayonDeplacementKm: 25, villeRecherche: "Grenoble")])
        XCTAssertEqual(s.model.succes, "Profil mis à jour avec succès !")
        XCTAssertNil(s.model.erreur)
        XCTAssertEqual(s.model.profil?.villeRecherche, "Grenoble", "profil relu par le port")
        XCTAssertEqual(s.model.formulaire.villeRecherche, "Grenoble")
        XCTAssertTrue(s.model.modification.estVide, "le formulaire relu devient la nouvelle base")
        XCTAssertFalse(s.model.enregistrementEnCours)
        let lecturesApres = await s.serveur.lectures
        XCTAssertEqual(lecturesApres, lecturesAvant + 1, "succès annoncé sur la relecture")
        // Revalidation de la session (profil de session relu : rayon, contrats, taux d'Explorer).
        let profilsRelus = await s.log.entries.filter { $0 == "profile(u-1)" }.count
        XCTAssertEqual(profilsRelus, 2, "profil de session lu à l'ouverture puis relu après l'enregistrement")
        XCTAssertTrue(s.store.state.isReady, "revalidation silencieuse : l'espace reste ouvert")
        // Une nouvelle saisie efface l'encart de succès.
        s.model.formulaire.bio = "Infirmière"
        XCTAssertNil(s.model.succes)
    }

    func testRefusServeurAfficheVerbatimEtConserveLaSaisie() async throws {
        let s = try await scenario()
        await s.model.charger()
        s.model.formulaire.prenom = " "
        await s.serveur.scripter(erreurEcriture: JoleneError(.unknown, "Le prénom ne peut pas être vide"))
        await s.model.enregistrer()
        XCTAssertEqual(s.model.erreur, "Le prénom ne peut pas être vide")
        XCTAssertNil(s.model.succes)
        XCTAssertEqual(s.model.formulaire.prenom, " ", "saisie conservée")
        let ecritures = await s.serveur.ecritures
        XCTAssertEqual(ecritures, [ModificationProfil(prenom: "")], "prénom vidé envoyé pour être refusé par le serveur")
        XCTAssertEqual(s.model.annonces, 1)
    }

    func testDelaiDepasseRelitLeProfilSansRenvoyerEtConserveLaSaisie() async throws {
        let s = try await scenario()
        await s.model.charger()
        s.model.formulaire.villeRecherche = "Nice"
        // Le serveur applique l'écriture puis la réponse est perdue.
        await s.serveur.scripter(perteReponse: JoleneError(.network, "Le service ne répond pas."))
        await s.model.enregistrer()
        let ecritures = await s.serveur.ecritures
        XCTAssertEqual(ecritures.count, 1, "jamais de renvoi automatique")
        XCTAssertEqual(s.model.erreur, "Le service ne répond pas.")
        XCTAssertNil(s.model.succes, "aucun succès annoncé sans réponse")
        XCTAssertEqual(s.model.profil?.villeRecherche, "Nice", "relecture : le serveur avait enregistré")
        XCTAssertEqual(s.model.formulaire.villeRecherche, "Nice")
        XCTAssertTrue(s.model.modification.estVide, "relu identique à la saisie : plus rien à envoyer")
    }

    func testDelaiDepasseSansEcritureCoteServeurLaisseLaModificationAEnvoyer() async throws {
        let s = try await scenario()
        await s.model.charger()
        s.model.formulaire.bio = "Nouvelle bio"
        await s.serveur.scripter(erreurEcriture: JoleneError(.network, "Le service ne répond pas."))
        await s.model.enregistrer()
        XCTAssertEqual(s.model.formulaire.bio, "Nouvelle bio", "saisie conservée pour une nouvelle tentative manuelle")
        XCTAssertEqual(s.model.modification, ModificationProfil(bio: "Nouvelle bio"))
    }

    func testDoubleAppuiNEnvoieQuUneDemande() async throws {
        let s = try await scenario()
        await s.model.charger()
        s.model.formulaire.villeRecherche = "Paris"
        let barriere = Gate()
        await s.serveur.scripter(barriere: barriere)
        let model = s.model
        async let premier: Void = model.enregistrer()
        while !model.enregistrementEnCours { await Task.yield() }
        XCTAssertFalse(model.peutEnregistrer)
        await model.enregistrer()
        await barriere.open()
        await premier
        let ecritures = await s.serveur.ecritures
        XCTAssertEqual(ecritures.count, 1)
    }

    func testRienAEnregistrerAucunAppel() async throws {
        let s = try await scenario()
        await s.model.charger()
        await s.model.enregistrer()
        let ecritures = await s.serveur.ecritures
        XCTAssertTrue(ecritures.isEmpty)
    }

    // MARK: - Modes d'exercice

    func testModesAutorisesLusApresLeProfil() async throws {
        let s = try await scenario(types: .success(["SALARIE"]))
        await s.model.charger()
        XCTAssertEqual(s.model.modes, .disponibles(["SALARIE"]))
        let choix = s.model.choixModes
        XCTAssertTrue(choix.liberalNonPropose)
        XCTAssertTrue(choix.anciennePreference, "LIBERAL coché mais plus autorisé")
        s.model.basculerMode(.liberal, selectionne: false)
        XCTAssertEqual(s.model.formulaire.typesContrat, ["CDD"])
        XCTAssertEqual(s.model.modification, ModificationProfil(typesContratAcceptes: ["CDD"]))
    }

    func testReferentielIndisponibleEtPortNonCableDonnentLEtatIndisponibleDuWeb() async throws {
        // `error || !Array.isArray(data)` puis `catch` (useTypesExerciceAutorises.ts l.32-40) : état « indisponible ».
        let reponses: [Result<[String]?, Error>] = [.success(nil), .failure(JoleneError(.network, "Le service ne répond pas."))]
        for types in reponses {
            let indisponible = try await scenario(types: types)
            await indisponible.model.charger()
            XCTAssertEqual(indisponible.model.modes, .indisponible)
            XCTAssertTrue(indisponible.model.choixModes.indisponible)
            XCTAssertTrue(indisponible.model.reessaiModesPossible, "« Réessayer la vérification » du web")
        }
        // Tant que T8 n'a pas câblé `inscription`, le stub refuserait toujours : même état du web, jamais un
        // référentiel supposé, mais sans « Réessayer la vérification » (jamais un bouton sans effet).
        let nonCable = try await scenario(inscription: UnwiredInscriptionPort())
        await nonCable.model.charger()
        XCTAssertEqual(nonCable.model.modes, .nonCable)
        XCTAssertTrue(nonCable.model.choixModes.indisponible)
        XCTAssertFalse(nonCable.model.reessaiModesPossible)
        XCTAssertEqual(nonCable.model.choixModes.options.map(\.mode), [.salarie, .liberal],
                       "salarié toujours proposé, libéral conservé parce qu'il est coché")
        XCTAssertFalse(nonCable.model.choixModes.liberalNonPropose, "aucun verdict sans référentiel")
    }

    func testSansProfessionAucuneVerificationDesModes() async throws {
        let s = try await scenario()
        await s.serveur.sansProfession()
        await s.model.charger()
        XCTAssertEqual(s.model.modes, .inactif, "`if (!profession)` : statut inactif, aucun appel")
        XCTAssertFalse(s.model.choixModes.chargement)
        XCTAssertFalse(s.model.reessaiModesPossible)
    }

    func testDernierModeJamaisDecoche() async throws {
        let s = try await scenario()
        await s.model.charger()
        s.model.basculerMode(.liberal, selectionne: false)
        s.model.basculerMode(.salarie, selectionne: false)
        XCTAssertEqual(s.model.formulaire.typesContrat, ["CDD"])
    }

    // MARK: - Textes

    func testTextesDuWebEtVouvoiement() {
        XCTAssertEqual(ProfilEdition.Textes.succes, "Profil mis à jour avec succès !")
        XCTAssertEqual(ProfilEdition.Textes.rppsCompteur(4), "4/11 chiffres")
        XCTAssertNil(ProfilEdition.Textes.rppsCompteur(0))
        XCTAssertNil(ProfilEdition.Textes.rppsCompteur(11))
        XCTAssertEqual(ProfilEdition.Textes.taux(32), "32 €/h")
        XCTAssertEqual(ProfilEdition.Textes.taux(32.5), "32.5 €/h")
        XCTAssertEqual(ProfilEdition.Textes.rayon(30), "Rayon : 30 km")
        for (web, natif) in ProfilEdition.vouvoiements {
            XCTAssertNotEqual(web, natif)
            for tutoiement in [" tu ", " tes ", "Ton ", " ton ", "Tu ", "Indique "] {
                XCTAssertFalse(natif.contains(tutoiement), "« \(natif) » doit être vouvoyé")
            }
        }
        XCTAssertEqual(ProfilEdition.renvoiTypeExercice, .safari(URL(string: "https://jolene.app/soignant/profil?tab=principal")!))
    }

    func testRenvoiDuTypeDExerciceSeulementPourUneProfessionConnue() {
        // `{profession && (… Type d'exercice …)}` (SectionProfilPrincipal.tsx l.895-896).
        XCTAssertTrue(ProfilEdition.afficheRenvoiTypeExercice(profilServeur))
        XCTAssertFalse(ProfilEdition.afficheRenvoiTypeExercice(ProfilComplet(id: "u-1", prenom: "", nom: "")))
        XCTAssertFalse(ProfilEdition.afficheRenvoiTypeExercice(ProfilComplet(id: "u-1", prenom: "", nom: "", profession: "")))
    }

    func testLeBoutonNAttendPasLaRevalidationDeLaSession() async throws {
        // La revalidation de la session (jusqu'à 15 s hors ligne) suit le succès relu : l'indicateur
        // d'enregistrement est levé et le succès annoncé avant elle.
        let revalidation = Gate()
        let s = try await scenario(revalidation: revalidation)
        await s.model.charger()
        s.model.formulaire.villeRecherche = "Annecy"
        let model = s.model
        async let enregistrement: Void = model.enregistrer()
        while await s.log.entries.filter({ $0 == "restoreSession" }).count < 2 { await Task.yield() }
        XCTAssertFalse(model.enregistrementEnCours, "revalidation en cours : le bouton n'est plus en attente")
        XCTAssertEqual(model.succes, ProfilEdition.Textes.succes)
        XCTAssertEqual(model.profil?.villeRecherche, "Annecy")
        await revalidation.open()
        await enregistrement
        XCTAssertTrue(s.store.state.isReady)
    }
}
