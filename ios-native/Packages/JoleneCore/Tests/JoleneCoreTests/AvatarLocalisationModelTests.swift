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

/// Localisation simulée : issue scriptée, demandes comptées.
actor LocalisationSimulee: LocalisationPort {
    var issue: PositionPonctuelle
    private(set) var demandes: [TimeInterval] = []

    init(_ issue: PositionPonctuelle) { self.issue = issue }

    func localiser(delai: TimeInterval) -> PositionPonctuelle {
        demandes.append(delai)
        return issue
    }
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

    private func scenario(recus: RecusAvatarEnMemoire = RecusAvatarEnMemoire()) async throws -> Scenario {
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
        let store = SessionStore(controller: SessionController(gateways: gateways))
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
}

extension ProfilAvatarSimule {
    func remplacer(_ nouveau: ProfilComplet) { ligne = nouveau }
}
