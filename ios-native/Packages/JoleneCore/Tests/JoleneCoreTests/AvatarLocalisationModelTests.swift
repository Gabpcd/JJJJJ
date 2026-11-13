import XCTest
@testable import JoleneCore

/// Géocodage simulé : adresse, absence ou erreur scriptées ; coordonnées reçues journalisées.
actor GeocodageSimule: GeocodagePort {
    var reponse: Result<AdresseGeocodee?, Error> = .success(AdresseGeocodee(libelle: "Place Bellecour 69002 Lyon", ville: "Lyon"))
    private(set) var appels = 0

    func scripter(_ reponse: Result<AdresseGeocodee?, Error>) { self.reponse = reponse }

    func adresse(lat: Double, lng: Double) throws -> AdresseGeocodee? {
        appels += 1
        return try reponse.get()
    }
}

/// Localisation simulée : issue scriptée, demandes comptées ; barrière optionnelle (position en cours d'obtention).
actor LocalisationSimulee: LocalisationPort {
    var issue: PositionPonctuelle
    private(set) var demandes: [TimeInterval] = []
    private let barriere: Gate?

    init(_ issue: PositionPonctuelle, barriere: Gate? = nil) { self.issue = issue; self.barriere = barriere }

    func localiser(delai: TimeInterval) async -> PositionPonctuelle {
        demandes.append(delai)
        if let barriere { await barriere.wait() }
        return issue
    }
}

/// Attente bornée d'un état intermédiaire (barrière atteinte, drapeau publié) : 2 s au plus, jamais un délai fixe.
@MainActor
func attendre(_ description: String, _ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<2_000 {
        if await condition() { return }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTFail("état attendu non atteint : \(description)", file: file, line: line)
}

/// Modèles de l'écran « Mon profil » pour la photo (`AvatarProfilModel`) et la position (`ProfilEditionModel.localiser`)
/// — lot 3, T10. Ce que ces tests prouvent : succès annoncé seulement sur l'URL relue, refus et messages du web,
/// réconciliation à l'ouverture, position et ville posées dans le formulaire SANS écriture serveur avant
/// « Enregistrer », puis `p_adresse_lat` / `p_adresse_lng` envoyés en paire ; aucun bouton sans port.
@MainActor
final class AvatarLocalisationModelTests: XCTestCase {
    private let utilisateur = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000))
    private let profilServeur = ProfilComplet(
        id: "u-1", prenom: "Léa", nom: "Martin", email: "u-1@example.invalid", profession: "IDE", rppsVerifie: false,
        rayonDeplacementKm: 40, villeRecherche: "Paris", typesContratAcceptes: ["CDD"], anneesExperience: 3,
        adresseLat: 48.8566, adresseLng: 2.3522)

    private struct Scenario {
        var store: SessionStore
        var snapshot: SessionSnapshot
        var profil: ProfilAvatarSimule
        var stockage: StockageAvatarSimule
        var recus: RecusAvatarEnMemoire
        var geocodage: GeocodageSimule
    }

    private func scenario(recus: RecusAvatarEnMemoire = RecusAvatarEnMemoire(),
                          timeout: TimeInterval = SessionController.defaultResolutionTimeout) async throws -> Scenario {
        let log = CallLog()
        let profil = ProfilAvatarSimule()
        await profil.remplacer(profilServeur)
        let stockage = StockageAvatarSimule()
        let geocodage = GeocodageSimule()
        var gateways = Lot1Fakes.gateways()
        gateways.auth = FakeAuth(restored: utilisateur, signInResult: .success(utilisateur), log: log)
        gateways.role = FakeRole(result: .success(RoleResult(role: "SOIGNANT")), gate: nil, log: log)
        gateways.missions = FakeMissions(profile: SoignantProfile(id: "u-1", profession: "IDE"), profileError: nil, gate: nil, log: log)
        gateways.profil = profil
        gateways.avatar = EnvoiAvatar(stockage: stockage, profil: profil, recus: recus,
                                      horloge: FixedClock(Date(timeIntervalSince1970: 1_793_577_600)),
                                      registre: RegistreEnvoisAvatar(), identifiant: { "essai-1" })
        gateways.geocodage = geocodage
        let store = SessionStore(controller: SessionController(gateways: gateways, resolutionTimeout: timeout))
        await store.start()
        let snapshot = try XCTUnwrap(store.state.snapshot, "session prête attendue, obtenu \(store.state)")
        return Scenario(store: store, snapshot: snapshot, profil: profil, stockage: stockage, recus: recus, geocodage: geocodage)
    }

    private func fixtureHeic() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "avatar-source", withExtension: "heic", subdirectory: "Resources/media"))
        return try Data(contentsOf: url)
    }

    // MARK: - Photo

    func testPhotoHeicConvertieEnvoyeeEtAnnonceeSurLURLRelue() async throws {
        let s = try await scenario()
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        await model.demarrer(avatarUrl: nil)
        XCTAssertNil(model.avis)
        await model.changer(source: try fixtureHeic())
        XCTAssertEqual(model.avis, .succes("Photo mise à jour !"))
        let relue = await s.profil.ligne.avatarUrl
        XCTAssertEqual(model.avatarUrl, relue, "URL affichée = URL relue")
        XCTAssertTrue(AvatarProfil.urlDesigne(model.avatarUrl, chemin: "u-1/avatar-1793577600000.jpg"))
        XCTAssertEqual(model.image.map { Array($0.prefix(2)) }, [0xFF, 0xD8], "JPEG envoyé affiché, jamais le HEIC")
        XCTAssertFalse(model.envoiEnCours)
        XCTAssertEqual(model.annonces, 1)
    }

    func testRefusDuStockageEtFichierIllisibleAffichentLesMessagesDuWeb() async throws {
        let s = try await scenario()
        await s.stockage.scripter(depot: .refus)
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        await model.changer(source: try fixtureHeic())
        XCTAssertEqual(model.avis, .erreur("Une erreur est survenue lors de l'upload. Veuillez réessayer."))
        XCTAssertNil(model.avatarUrl)
        let ecritures = await s.profil.ecritures
        XCTAssertTrue(ecritures.isEmpty)

        await model.changer(source: Data("pas une image".utf8))
        XCTAssertEqual(model.avis, .erreur("Impossible de lire le fichier sélectionné."))
        let operations = await s.stockage.operations
        XCTAssertEqual(operations.count, 1, "aucun dépôt pour un fichier illisible")
    }

    func testIssueInconnueRelueEtAnnonceeSiLeProfilPorteLaPhoto() async throws {
        let s = try await scenario()
        await s.profil.scripter(.perte)
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        await model.changer(source: try fixtureHeic())
        XCTAssertEqual(model.avis, .succes("Photo mise à jour !"), "relecture : la photo est liée malgré la réponse perdue")
        let ecritures = await s.profil.ecritures
        XCTAssertEqual(ecritures.count, 1, "jamais de second envoi")
        let reste = try await s.recus.lire(userId: "u-1")
        XCTAssertNil(reste)
    }

    func testIssueInconnueNonLieeResteEnEchec() async throws {
        let s = try await scenario()
        await s.stockage.scripter(depot: .perte)
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        await model.changer(source: try fixtureHeic())
        XCTAssertEqual(model.avis, .erreur("Une erreur est survenue lors de l'upload. Veuillez réessayer."))
        XCTAssertNil(model.avatarUrl)
        let operations = await s.stockage.operations
        XCTAssertEqual(operations.filter { $0.hasPrefix("deposer") }.count, 1, "aucun second dépôt")
    }

    func testReconciliationALOuvertureEtImageRelue() async throws {
        let recus = RecusAvatarEnMemoire()
        try await recus.ecrire(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: "u-1/avatar-1.jpg", phase: .stored))
        let s = try await scenario(recus: recus)
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        await model.demarrer(avatarUrl: nil)
        XCTAssertEqual(model.avis, .erreur("Une erreur est survenue lors de l'upload. Veuillez réessayer."),
                       "envoi interrompu non lié : la photo n'a pas changé")
        let operations = await s.stockage.operations
        XCTAssertTrue(operations.isEmpty, "réconciliation par relecture, jamais par un nouvel envoi")

        // Ouverture avec un avatar déjà lié : l'image est lue par le port, aucun avis.
        let t = try await scenario()
        await t.stockage.scripter()
        let lecteur = AvatarProfilModel(session: t.store, snapshot: t.snapshot)
        await lecteur.demarrer(avatarUrl: "https://ref.supabase.co/storage/v1/object/sign/jolene-documents/u-1/avatar-9.jpg?token=t")
        XCTAssertNil(lecteur.avis)
        XCTAssertNil(lecteur.image, "aucun objet chez le double : rien d'affiché, jamais une image plausible")
        await lecteur.demarrer(avatarUrl: nil)
        XCTAssertNotNil(lecteur.avatarUrl, "une seule ouverture par instance")
    }

    // MARK: - Photo : revue fraîche B8 de T10

    /// M1 : un fichier choisi mais illisible (photo iCloud non téléchargeable hors ligne, représentation illisible, prise
    /// de vue non encodable) n'est plus confondu avec une annulation : message du web, rien n'est envoyé.
    func testFichierChoisiIllisibleAfficheLeMessageDuWebSansEnvoi() async throws {
        let s = try await scenario()
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        await model.demarrer(avatarUrl: nil)
        XCTAssertTrue(model.peutChanger)
        model.lectureCommencee()
        XCTAssertTrue(model.lectureEnCours, "indicateur pendant la lecture du fichier choisi")
        XCTAssertFalse(model.peutChanger, "« Changer ma photo » inactif pendant la lecture")
        XCTAssertNil(model.avis)
        await model.recevoir(.illisible)
        XCTAssertEqual(model.avis, .erreur("Impossible de lire le fichier sélectionné."), "`documentUpload.ts` l.174, verbatim")
        XCTAssertEqual(model.annonces, 1, "annoncé à VoiceOver")
        XCTAssertFalse(model.lectureEnCours)
        XCTAssertTrue(model.peutChanger, "l'utilisateur peut choisir une autre photo")
        XCTAssertNil(model.avatarUrl)
        let operations = await s.stockage.operations
        XCTAssertTrue(operations.isEmpty, "aucun dépôt")
        let ecritures = await s.profil.ecritures
        XCTAssertTrue(ecritures.isEmpty, "aucun `p_avatar_url`")
        let recu = try await s.recus.lire(userId: "u-1")
        XCTAssertNil(recu, "aucun reçu : rien n'est parti")
    }

    /// M1 : l'annulation (aucun résultat, « Annuler » de l'appareil photo) reste silencieuse : ni message ni envoi.
    func testAnnulationDuSelecteurNiMessageNiEnvoi() async throws {
        let s = try await scenario()
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        await model.demarrer(avatarUrl: nil)
        await model.recevoir(.annulee)
        XCTAssertNil(model.avis)
        XCTAssertEqual(model.annonces, 0)
        XCTAssertFalse(model.lectureEnCours)
        let operations = await s.stockage.operations
        XCTAssertTrue(operations.isEmpty)
    }

    /// M1 : octets lus après l'indicateur de lecture → conversion et envoi, comme avant.
    func testOctetsLusApresLIndicateurEnvoyesEtAnnonces() async throws {
        let s = try await scenario()
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        await model.demarrer(avatarUrl: nil)
        model.lectureCommencee()
        await model.recevoir(.octets(try fixtureHeic()))
        XCTAssertEqual(model.avis, .succes("Photo mise à jour !"))
        XCTAssertFalse(model.lectureEnCours)
        XCTAssertFalse(model.envoiEnCours)
        let operations = await s.stockage.operations
        XCTAssertEqual(operations.filter { $0.hasPrefix("deposer") }.count, 1)
    }

    /// m6 : « Changer ma photo » reste inactif tant que la réconciliation d'ouverture n'est pas finie ; un envoi demandé
    /// pendant ce temps ne part pas (aucune réconciliation concurrente du même reçu, aucun échec parasite).
    func testChangerInactifPendantLaReconciliationDOuverture() async throws {
        let recus = RecusAvatarEnMemoire()
        try await recus.ecrire(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: "u-1/avatar-1.jpg", phase: .stored))
        let s = try await scenario(recus: recus)
        let barriere = Gate()
        await s.profil.retenir(lecture: barriere)
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        let ouverture = Task { await model.demarrer(avatarUrl: nil) }
        await attendre("réconciliation en relecture") { await s.profil.lectures == 1 }
        XCTAssertTrue(model.reconciliationEnCours)
        XCTAssertFalse(model.peutChanger, "bouton inactif pendant la réconciliation d'ouverture")
        await model.changer(source: try fixtureHeic())
        let pendant = await s.stockage.operations
        XCTAssertTrue(pendant.isEmpty, "aucun envoi pendant la réconciliation")
        XCTAssertNil(model.avis)
        await barriere.open()
        await ouverture.value
        XCTAssertFalse(model.reconciliationEnCours)
        XCTAssertTrue(model.peutChanger)
        XCTAssertEqual(model.avis, .erreur("Une erreur est survenue lors de l'upload. Veuillez réessayer."),
                       "envoi interrompu non lié : seul message, celui de la réconciliation")
        await model.changer(source: try fixtureHeic())
        XCTAssertEqual(model.avis, .succes("Photo mise à jour !"))
    }

    /// m7 : l'envoi a son propre budget (`AvatarProfil.delaiEnvoi`, cinq étapes réseau au délai de résolution) : un dépôt
    /// plus long qu'UN délai de résolution aboutit, au lieu d'être annulé en cours de route.
    func testEnvoiLentAuDelaDUnDelaiDeResolutionAboutit() async throws {
        XCTAssertEqual(AvatarProfil.etapesReseauEnvoi, 5)
        XCTAssertEqual(AvatarProfil.delaiEnvoi(resolution: 15), 75, "budget de l'envoi en production")
        let s = try await scenario(timeout: 0.25)
        await s.stockage.scripter(delaiDepot: 0.5)
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        await model.demarrer(avatarUrl: nil)
        await model.changer(source: try fixtureHeic())
        XCTAssertEqual(model.avis, .succes("Photo mise à jour !"), "dépôt de 0,5 s < budget de 1,25 s")
        XCTAssertNotNil(model.avatarUrl)
    }

    /// m7 : le budget reste une borne : un dépôt qui ne répond jamais finit en échec affiché, sans succès fabriqué.
    func testEnvoiBloqueAuDelaDuBudgetFinitEnEchec() async throws {
        let s = try await scenario(timeout: 0.05)
        let barriere = Gate()
        await s.stockage.scripter(barriere: barriere)
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        await model.demarrer(avatarUrl: nil)
        await model.changer(source: try fixtureHeic())
        XCTAssertEqual(model.avis, .erreur("Une erreur est survenue lors de l'upload. Veuillez réessayer."))
        XCTAssertNil(model.avatarUrl)
        XCTAssertFalse(model.envoiEnCours)
        await barriere.open()
    }

    /// m10 : identité remplacée PENDANT un envoi (déconnexion, autre compte) : rien n'est publié pour l'identité périmée.
    func testIdentiteRemplaceePendantLEnvoiRienNEstPublie() async throws {
        let s = try await scenario()
        let barriere = Gate()
        await s.stockage.scripter(barriere: barriere)
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        await model.demarrer(avatarUrl: nil)
        let source = try fixtureHeic()
        let envoi = Task { await model.changer(source: source) }
        await attendre("dépôt en vol") { await !s.stockage.operations.isEmpty }
        await s.store.signOut()
        await barriere.open()
        await envoi.value
        XCTAssertNil(model.avis, "epoch périmé : aucun avis publié")
        XCTAssertNil(model.avatarUrl)
        XCTAssertNil(model.image)
        XCTAssertEqual(model.annonces, 0)
        XCTAssertFalse(model.envoiEnCours)
    }

    /// m10 : identité remplacée PENDANT la réconciliation d'ouverture : ni avis ni image publiés.
    func testIdentiteRemplaceePendantLaReconciliationRienNEstPublie() async throws {
        let recus = RecusAvatarEnMemoire()
        try await recus.ecrire(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: "u-1/avatar-1.jpg", phase: .stored))
        let s = try await scenario(recus: recus)
        let barriere = Gate()
        await s.profil.retenir(lecture: barriere)
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        let ouverture = Task {
            await model.demarrer(avatarUrl: "https://ref.supabase.co/storage/v1/object/sign/jolene-documents/u-1/avatar-9.jpg?token=t")
        }
        await attendre("réconciliation en relecture") { await s.profil.lectures == 1 }
        await s.store.signOut()
        await barriere.open()
        await ouverture.value
        XCTAssertNil(model.avis, "envoi interrompu non lié : rien n'est publié pour l'identité périmée")
        XCTAssertNil(model.image)
        XCTAssertEqual(model.annonces, 0)
        XCTAssertFalse(model.reconciliationEnCours)
    }

    /// M1 et m10 : un fichier illisible signalé après un changement d'identité n'est pas annoncé.
    func testFichierIllisibleApresChangementDIdentiteRienNEstPublie() async throws {
        let s = try await scenario()
        let model = AvatarProfilModel(session: s.store, snapshot: s.snapshot)
        await model.demarrer(avatarUrl: nil)
        model.lectureCommencee()
        await s.store.signOut()
        await model.recevoir(.illisible)
        XCTAssertNil(model.avis)
        XCTAssertFalse(model.lectureEnCours, "indicateur toujours retiré")
    }

    // MARK: - Position

    func testPositionPoseLaPositionEtLaVilleSansEcritureServeurPuisEnregistreLaPaire() async throws {
        let s = try await scenario()
        let localisation = LocalisationSimulee(.disponible(latitude: 45.7578, longitude: 4.832))
        let model = ProfilEditionModel(session: s.store, snapshot: s.snapshot, localisation: localisation)
        await model.charger()
        XCTAssertTrue(model.localisationProposee)
        XCTAssertTrue(model.formulaire.positionRenseignee, "position relue du profil")
        await model.localiser()
        XCTAssertEqual(model.avisLocalisation, .succes("Place Bellecour 69002 Lyon"), "libellé de l'adresse, sans pictogramme")
        XCTAssertEqual(model.formulaire.villeRecherche, "Lyon")
        XCTAssertEqual(model.formulaire.adresseLat, 45.7578)
        XCTAssertEqual(model.formulaire.adresseLng, 4.832)
        let demandes = await localisation.demandes
        XCTAssertEqual(demandes, [15], "délai du web (timeout 15 000 ms)")
        var ecritures = await s.profil.ecritures
        XCTAssertTrue(ecritures.isEmpty, "rien n'est écrit avant « Enregistrer les modifications »")
        XCTAssertEqual(model.modification.parametres, [
            "p_ville_recherche": .texte("Lyon"), "p_adresse_lat": .reel(45.7578), "p_adresse_lng": .reel(4.832),
        ])
        await model.enregistrer()
        ecritures = await s.profil.ecritures
        XCTAssertEqual(ecritures.count, 1)
        XCTAssertEqual(ecritures.first?.adresseLat, 45.7578)
        XCTAssertEqual(ecritures.first?.adresseLng, 4.832)
    }

    func testGeocodageSansResultatOuEnEchecPositionRecuperee() async throws {
        for reponse: Result<AdresseGeocodee?, Error> in [.success(nil), .failure(JoleneError(.network, "x")),
                                                           .success(AdresseGeocodee(libelle: " "))] {
            let s = try await scenario()
            await s.geocodage.scripter(reponse)
            let model = ProfilEditionModel(session: s.store, snapshot: s.snapshot,
                                           localisation: LocalisationSimulee(.disponible(latitude: 45.7, longitude: 4.8)))
            await model.charger()
            await model.localiser()
            XCTAssertEqual(model.avisLocalisation, .succes("Position récupérée."))
            XCTAssertEqual(model.formulaire.villeRecherche, "Paris", "ville inchangée sans adresse")
            XCTAssertEqual(model.formulaire.adresseLat, 45.7, "la position reste posée")
        }
    }

    func testRefusOuIndisponibiliteMessageDuWebFormulaireInchange() async throws {
        for issue in [PositionPonctuelle.refusee, .indisponible] {
            let s = try await scenario()
            let model = ProfilEditionModel(session: s.store, snapshot: s.snapshot, localisation: LocalisationSimulee(issue))
            await model.charger()
            let avant = model.formulaire
            await model.localiser()
            XCTAssertEqual(model.avisLocalisation,
                           .erreur("Localisation refusée ou indisponible. Vous pouvez saisir votre adresse manuellement."))
            XCTAssertEqual(model.formulaire, avant)
            XCTAssertTrue(model.modification.estVide)
            let appels = await s.geocodage.appels
            XCTAssertEqual(appels, 0, "aucun géocodage sans position")
        }
    }

    func testSansPortDeLocalisationAucunBoutonNiAppel() async throws {
        let s = try await scenario()
        let model = ProfilEditionModel(session: s.store, snapshot: s.snapshot)
        await model.charger()
        XCTAssertFalse(model.localisationProposee)
        await model.localiser()
        XCTAssertNil(model.avisLocalisation)
        let appels = await s.geocodage.appels
        XCTAssertEqual(appels, 0)
    }

    func testIdentiteRemplaceePendantLaLocalisationRienNEstPublie() async throws {
        let s = try await scenario()
        let localisation = LocalisationSimulee(.disponible(latitude: 45.7, longitude: 4.8))
        let model = ProfilEditionModel(session: s.store, snapshot: s.snapshot, localisation: localisation)
        await model.charger()
        await s.store.signOut()
        await model.localiser()
        XCTAssertNil(model.avisLocalisation, "epoch périmé : aucun avis publié")
        XCTAssertEqual(model.formulaire.adresseLat, 48.8566, "formulaire de l'identité périmée inchangé")
    }

    // MARK: - Position : revue fraîche B8 de T10

    /// m4 : l'avis de la localisation a son propre jeton d'annonce VoiceOver ; « Enregistrer » ne réannonce pas
    /// « Place Bellecour… » encore affiché, et une localisation ne réannonce pas « Profil mis à jour avec succès ! ».
    func testAnnoncesDeLaLocalisationDistinctesDeCellesDeLEnregistrement() async throws {
        let s = try await scenario()
        let model = ProfilEditionModel(session: s.store, snapshot: s.snapshot,
                                       localisation: LocalisationSimulee(.disponible(latitude: 45.7578, longitude: 4.832)))
        await model.charger()
        XCTAssertEqual(model.annonces, 0)
        XCTAssertEqual(model.annoncesLocalisation, 0)
        await model.localiser()
        XCTAssertEqual(model.annoncesLocalisation, 1, "avis de la localisation annoncé par son jeton")
        XCTAssertEqual(model.annonces, 0, "encarts d'enregistrement non réannoncés")
        await model.enregistrer()
        XCTAssertEqual(model.succes, "Profil mis à jour avec succès !")
        XCTAssertEqual(model.annonces, 1)
        XCTAssertEqual(model.annoncesLocalisation, 1, "l'avis « Place Bellecour… » encore affiché n'est pas réannoncé")
        await model.localiser()
        XCTAssertEqual(model.annoncesLocalisation, 2)
        XCTAssertEqual(model.annonces, 1, "« Profil mis à jour… » n'est pas réannoncé par une localisation")

        // Refus de localisation : même jeton dédié.
        let t = try await scenario()
        let refus = ProfilEditionModel(session: t.store, snapshot: t.snapshot, localisation: LocalisationSimulee(.refusee))
        await refus.charger()
        await refus.localiser()
        XCTAssertEqual(refus.annoncesLocalisation, 1)
        XCTAssertEqual(refus.annonces, 0)
    }

    /// m5 : position en cours d'obtention → « Enregistrer » verrouillé (la position arrivée pendant un enregistrement
    /// serait écrasée par le profil relu alors que l'avis afficherait l'adresse trouvée).
    func testEnregistrementVerrouillePendantLaLocalisation() async throws {
        let s = try await scenario()
        let barriere = Gate()
        let localisation = LocalisationSimulee(.disponible(latitude: 45.7578, longitude: 4.832), barriere: barriere)
        let model = ProfilEditionModel(session: s.store, snapshot: s.snapshot, localisation: localisation)
        await model.charger()
        model.formulaire.bio = "Infirmière en réanimation."
        XCTAssertTrue(model.peutEnregistrer)
        XCTAssertTrue(model.peutLocaliser)
        let localiser = Task { await model.localiser() }
        await attendre("position en cours d'obtention") { model.localisationEnCours }
        XCTAssertFalse(model.peutEnregistrer, "« Enregistrer » inactif pendant la localisation")
        await model.enregistrer()
        let pendant = await s.profil.ecritures
        XCTAssertTrue(pendant.isEmpty, "aucun enregistrement ne part pendant la localisation")
        await barriere.open()
        await localiser.value
        XCTAssertTrue(model.peutEnregistrer)
        await model.enregistrer()
        let ecritures = await s.profil.ecritures
        XCTAssertEqual(ecritures.count, 1)
        XCTAssertEqual(ecritures.first?.bio, "Infirmière en réanimation.")
        XCTAssertEqual(ecritures.first?.adresseLat, 45.7578, "la position obtenue part avec l'enregistrement")
        XCTAssertEqual(model.formulaire.adresseLat, 45.7578, "position relue, jamais écrasée")
    }

    /// m5 : enregistrement en vol → « Utiliser ma position actuelle » verrouillé ; aucune position n'est demandée.
    func testLocalisationVerrouilleePendantLEnregistrement() async throws {
        let s = try await scenario()
        let barriere = Gate()
        await s.profil.retenir(ecriture: barriere)
        let localisation = LocalisationSimulee(.disponible(latitude: 45.7578, longitude: 4.832))
        let model = ProfilEditionModel(session: s.store, snapshot: s.snapshot, localisation: localisation)
        await model.charger()
        model.formulaire.bio = "Infirmière en réanimation."
        let enregistrer = Task { await model.enregistrer() }
        await attendre("enregistrement en vol") { model.enregistrementEnCours }
        XCTAssertFalse(model.peutLocaliser, "« Utiliser ma position actuelle » inactif pendant l'enregistrement")
        await model.localiser()
        let demandes = await localisation.demandes
        XCTAssertTrue(demandes.isEmpty, "aucune position demandée pendant l'enregistrement")
        XCTAssertNil(model.avisLocalisation)
        await barriere.open()
        await enregistrer.value
        XCTAssertTrue(model.peutLocaliser)
        XCTAssertEqual(model.succes, "Profil mis à jour avec succès !")
    }
}

extension ProfilAvatarSimule {
    func remplacer(_ nouveau: ProfilComplet) { ligne = nouveau }
}
