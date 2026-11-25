import XCTest
@testable import JoleneCore

/// Parcours du ❤️ de la vue Swipe (lot 4, T3b ; `LOT4_PLAN.md` §2.5 ; revue B8 de #1165, m3). Règles prouvées :
/// récapitulatif exact avant tout envoi ; feuille « première candidature » obligatoire avant le premier ❤️ envoyé du
/// compte, une seule fois, jamais mémorisée par « Pas maintenant » ; choix de contrat rejoué avec l'option ; carte déjà
/// swipée refusée puis absente ; avis du ❤️ (avertissement serveur verbatim, documents à compléter) ; verrou synchrone
/// des gestes. Monde démo de bout en bout (fixture `demo-swipe.json`) et ports factices pour les cas qu'il ne sert pas.
@MainActor
final class ParcoursCandidatureSwipeTests: XCTestCase {
    private static let choix = "demo-swipe-choix"
    private static let deja = "demo-swipe-deja"

    // MARK: - Ports factices

    /// Paquet fixe, sans réseau : cartes fournies, ✕ / ⭐ acceptés.
    private struct PaquetFixe: SwipePort {
        var cartes: [CarteSwipe]
        func paquet(context: MissionReadContext) async throws -> [CarteSwipe] { cartes }
        func enregistrer(missionId: String, direction: DirectionSwipe, context: MissionReadContext) async throws -> SwipeOutcome { .enregistre }
        func retirer(candidatureId: String, context: MissionReadContext) async throws -> RetraitOutcome { .retiree }
        func nombreSwipes(context: MissionReadContext) async throws -> Int { 0 }
        func initialiserPreferences(_ preferences: PreferencesMatching, context: MissionReadContext) async throws {}
    }

    actor Compteur {
        private(set) var envois = 0
        func noter() { envois += 1 }
    }

    /// Port de candidature qui rend les avis du ❤️ (`CandidatureSwipePort`).
    private struct CandidatureAvecAvis: CandidatureSwipePort {
        let compteur: Compteur
        var avis: AvisSwipeLike?

        func confirmerSwipeLike(missionId: String, creneaux: [CreneauConfirmePayload], choixContrat: String?,
                                context: MissionReadContext) async throws -> IssueSwipeLike {
            await compteur.noter()
            return IssueSwipeLike(issue: .confirmed(candidatureId: "c-\(missionId)", contratId: nil), avis: avis)
        }
        func confirmer(action: ActionPlanning, missionId: String, creneaux: [CreneauConfirmePayload], message: String?,
                       choixContrat: String?, candidatureId: String?, context: MissionReadContext) async throws -> CandidatureOutcome {
            throw JoleneError(.contract, "le ❤️ doit passer par confirmerSwipeLike")
        }
        func refuserProposition(candidatureId: String, context: MissionReadContext) async throws { throw JoleneError(.contract, "x") }
        func candidature(missionId: String, context: MissionReadContext) async throws -> CandidatureRecord? { nil }
        func annulerCandidature(id: String, motif: String, texte: String, justificatifPath: String?,
                                context: MissionReadContext) async throws -> AnnulationOutcome { throw JoleneError(.contract, "x") }
        func annulerMission(id: String, motif: String?, context: MissionReadContext) async throws -> AnnulationOutcome {
            throw JoleneError(.contract, "x")
        }
    }

    // MARK: - Préparation

    private struct Monde {
        var parcours: ParcoursCandidatureSwipe
        var model: SwipeModel
        var marqueurs: SwipeMarqueurs
        var gateways: Gateways
        var context: MissionReadContext
    }

    /// Session démo prête ; `adapter` remplace des ports avant la connexion (cas que le monde démo ne sert pas).
    private func monde(premiereCandidatureVue: Bool = false, adapter: (inout Gateways) -> Void = { _ in }) async throws -> Monde {
        var gateways = DemoWorld.gateways()
        adapter(&gateways)
        let controller = SessionController(gateways: gateways)
        let etat = await controller.signIn(email: "demonstration@example.invalid", password: "demonstration")
        let snapshot = try XCTUnwrap(etat.snapshot, "session démo prête attendue, obtenu \(etat)")
        let marqueurs = SwipeMarqueurs(stockage: MemoireStockageAppareil(), userId: snapshot.user.id)
        if premiereCandidatureVue { marqueurs.marquerPremiereCandidatureVue() }
        let model = SwipeModel(controller: controller, snapshot: snapshot)
        await model.charger()
        return Monde(parcours: ParcoursCandidatureSwipe(model: model, marqueurs: marqueurs), model: model, marqueurs: marqueurs,
                     gateways: gateways, context: snapshot.context)
    }

    private func carte(_ id: String, nbCreneaux: Int = 1) throws -> CarteSwipe {
        let ligne: [String: Any] = ["mission_id": id, "intitule": "Mission \(id)", "profession_requise": "IDE", "etablissement_id": "e-1",
                                    "etablissement_nom": "Clinique", "debut_le": "2026-12-01T07:00:00+00:00",
                                    "fin_le": "2026-12-01T15:00:00+00:00", "nb_creneaux": nbCreneaux]
        let decodee = try JSONDecoder().decode(LigneSwipe.self, from: JSONSerialization.data(withJSONObject: ligne))
        return CarteSwipe(ligne: decodee, creneaux: [MissionSlot(id: "\(id)-s1", missionId: id, debut: "2026-12-01T07:00:00+00:00",
                                                                 fin: "2026-12-01T15:00:00+00:00", estPause: false,
                                                                 typeCreneau: "PREVISIONNEL")])
    }

    // MARK: - Récapitulatif, puis feuille « première candidature »

    func testRecapitulatifToujoursPuisFeuilleObligatoireAvantLePremierEnvoi() async throws {
        let m = try await monde()
        XCTAssertEqual(m.model.cartes.count, 12)
        XCTAssertEqual(m.parcours.etape, .aucune)

        m.parcours.demander("demo-mission-015")
        XCTAssertEqual(m.parcours.etape, .recapitulatif(missionId: "demo-mission-015"), "❤️ : récapitulatif, jamais un envoi")
        XCTAssertEqual(m.parcours.etape.missionId, "demo-mission-015")
        XCTAssertFalse(m.parcours.envoiEnCours)
        m.parcours.demander("demo-mission-016")
        XCTAssertEqual(m.parcours.etape, .recapitulatif(missionId: "demo-mission-015"), "un parcours ouvert n'est pas remplacé")
        XCTAssertTrue(m.parcours.planningExact("demo-mission-015"))
        var posee = try await m.gateways.candidature.candidature(missionId: "demo-mission-015", context: m.context)
        XCTAssertNil(posee)

        await m.parcours.confirmerRecapitulatif()
        XCTAssertEqual(m.parcours.etape, .premiereCandidature(missionId: "demo-mission-015"), "première candidature du compte : feuille")
        XCTAssertEqual(m.parcours.etape.missionId, "demo-mission-015")
        posee = try await m.gateways.candidature.candidature(missionId: "demo-mission-015", context: m.context)
        XCTAssertNil(posee, "rien n'est envoyé avant « J'ai compris — envoyer ma candidature »")
        XCTAssertEqual(m.model.cartes.count, 12)

        // « Pas maintenant » : rien d'envoyé, rien de mémorisé, la feuille reviendra.
        m.parcours.abandonner()
        XCTAssertEqual(m.parcours.etape, .aucune)
        XCTAssertFalse(m.marqueurs.premiereCandidatureVue)
        await m.parcours.confirmerPremiereCandidature()
        posee = try await m.gateways.candidature.candidature(missionId: "demo-mission-015", context: m.context)
        XCTAssertNil(posee, "sans feuille ouverte, la confirmation n'envoie rien")

        m.parcours.demander("demo-mission-015")
        await m.parcours.confirmerRecapitulatif()
        XCTAssertEqual(m.parcours.etape, .premiereCandidature(missionId: "demo-mission-015"), "feuille de nouveau, tant qu'elle n'est pas confirmée")
        await m.parcours.confirmerPremiereCandidature()
        XCTAssertEqual(m.parcours.etape, .aucune)
        XCTAssertTrue(m.marqueurs.premiereCandidatureVue)
        posee = try await m.gateways.candidature.candidature(missionId: "demo-mission-015", context: m.context)
        XCTAssertEqual(posee?.statut, "EN_ATTENTE", "candidature relue par le monde démo")
        XCTAssertEqual(m.model.annonce, .candidatureEnvoyee(missionId: "demo-mission-015"))
        XCTAssertNotNil(m.model.candidatureAnnulable)
        XCTAssertEqual(m.model.cartes.count, 11)
        XCTAssertEqual(m.model.avisCandidature, AvisSwipeLike(documentsACompleter: true),
                       "documents du profil fictif non validés : `docs_a_completer`, comme le serveur")

        // Deuxième ❤️ du même compte : plus de feuille, l'envoi suit le récapitulatif.
        m.parcours.demander("demo-mission-016")
        XCTAssertEqual(m.parcours.etape, .recapitulatif(missionId: "demo-mission-016"))
        await m.parcours.confirmerRecapitulatif()
        XCTAssertEqual(m.parcours.etape, .aucune)
        let seconde = try await m.gateways.candidature.candidature(missionId: "demo-mission-016", context: m.context)
        XCTAssertEqual(seconde?.statut, "EN_ATTENTE")
        XCTAssertEqual(m.model.cartes.count, 10)

        // Mes missions › Candidatures liste les deux candidatures de la session.
        let listees = try await m.gateways.mesMissions.candidatures(context: m.context).map(\.missionId)
        XCTAssertTrue(listees.contains("demo-mission-015") && listees.contains("demo-mission-016"), "\(listees)")
    }

    func testMarqueurDeLaFeuilleParCompteEtAbsentPourUnAutre() {
        let stockage = MemoireStockageAppareil()
        let premier = SwipeMarqueurs(stockage: stockage, userId: "u-1")
        premier.marquerPremiereCandidatureVue()
        XCTAssertTrue(premier.premiereCandidatureVue)
        XCTAssertFalse(SwipeMarqueurs(stockage: stockage, userId: "u-2").premiereCandidatureVue,
                       "un autre compte sur le même appareil revoit la feuille")
    }

    func testPlanningNonExactJamaisConfirmeNiEnvoye() async throws {
        let compteur = Compteur()
        let incomplete = try carte("m-incomplet", nbCreneaux: 2)
        let m = try await monde(premiereCandidatureVue: true) { gateways in
            gateways.swipe = PaquetFixe(cartes: [incomplete])
            gateways.candidature = CandidatureAvecAvis(compteur: compteur)
        }
        XCTAssertEqual(m.model.cartes.map(\.id), ["m-incomplet"])
        m.parcours.demander("m-incomplet")
        XCTAssertEqual(m.parcours.etape, .recapitulatif(missionId: "m-incomplet"), "le récapitulatif montre le blocage")
        XCTAssertFalse(m.parcours.planningExact("m-incomplet"))
        await m.parcours.confirmerRecapitulatif()
        XCTAssertEqual(m.parcours.etape, .recapitulatif(missionId: "m-incomplet"), "planning non exact : confirmation sans effet")
        let envois = await compteur.envois
        XCTAssertEqual(envois, 0)

        m.parcours.abandonner()
        m.parcours.demander("m-inconnue")
        XCTAssertEqual(m.parcours.etape, .aucune, "carte hors du paquet : aucun récapitulatif")
        XCTAssertFalse(m.parcours.planningExact("m-inconnue"))
    }

    // MARK: - Avis du ❤️

    func testAvisDuServeurVerbatimPuisRefermes() async throws {
        let compteur = Compteur()
        let avis = AvisSwipeLike(avertissement: "  Mission adjacente à moins d'une heure.  ", documentsACompleter: false)
        XCTAssertEqual(avis.avertissement, "Mission adjacente à moins d'une heure.")
        let cartes = [try carte("m-1"), try carte("m-2"), try carte("m-3")]
        let m = try await monde(premiereCandidatureVue: true) { gateways in
            gateways.swipe = PaquetFixe(cartes: cartes)
            gateways.candidature = CandidatureAvecAvis(compteur: compteur, avis: avis)
        }
        m.parcours.demander("m-1")
        await m.parcours.confirmerRecapitulatif()
        XCTAssertEqual(m.model.avisCandidature, avis, "avertissement du serveur, tel quel")
        XCTAssertEqual(m.model.annonce, .candidatureEnvoyee(missionId: "m-1"))
        // Le toast expire (5 s) : l'avis reste, il ne disparaît jamais sur minuterie.
        m.model.fermerAnnonce()
        XCTAssertNil(m.model.candidatureAnnulable)
        XCTAssertEqual(m.model.avisCandidature, avis)
        m.model.fermerAvis()
        XCTAssertNil(m.model.avisCandidature)

        // Candidature retirée : ses avis ne valent plus.
        m.parcours.demander("m-2")
        await m.parcours.confirmerRecapitulatif()
        XCTAssertEqual(m.model.avisCandidature, avis)
        await m.model.retirerCandidature()
        XCTAssertEqual(m.model.annonce, .candidatureRetiree(missionId: "m-2"))
        XCTAssertNil(m.model.avisCandidature)
        XCTAssertEqual(m.model.cartes.map(\.id), ["m-3"], "D4 : carte jamais remise")
        let envois = await compteur.envois
        XCTAssertEqual(envois, 2, "le port des avis est utilisé quand la session le propose")
    }

    func testAvisVideNonPublie() async throws {
        let compteur = Compteur()
        let cartes = [try carte("m-1")]
        let m = try await monde(premiereCandidatureVue: true) { gateways in
            gateways.swipe = PaquetFixe(cartes: cartes)
            gateways.candidature = CandidatureAvecAvis(compteur: compteur, avis: AvisSwipeLike())
        }
        m.parcours.demander("m-1")
        await m.parcours.confirmerRecapitulatif()
        XCTAssertEqual(m.model.annonce, .candidatureEnvoyee(missionId: "m-1"))
        XCTAssertNil(m.model.avisCandidature, "ni avertissement ni documents : rien à montrer")
        XCTAssertTrue(AvisSwipeLike().estVide)
        XCTAssertFalse(AvisSwipeLike(documentsACompleter: true).estVide)
        XCTAssertNil(AvisSwipeLike(avertissement: "   ").avertissement)
    }

    // MARK: - Choix de contrat (carte de recette `demo-swipe-choix`)

    func testChoixDeContratDemandePuisRejoueAvecLOption() async throws {
        let m = try await monde(premiereCandidatureVue: true)
        XCTAssertEqual(m.model.cartes[1].id, Self.choix, "deuxième carte du paquet démo")
        m.parcours.demander(Self.choix)
        await m.parcours.confirmerRecapitulatif()
        XCTAssertEqual(m.parcours.etape, .choixContrat(missionId: Self.choix), "le parcours reste ouvert sur le choix du contrat")
        XCTAssertFalse(m.parcours.envoiEnCours)
        XCTAssertEqual(m.model.optionsContrat, DemoCandidatureGateway.Textes.choixContrat, "mission TOUS, profil MIXTE : choix demandé")
        XCTAssertEqual(m.model.missionChoixContrat, Self.choix)
        XCTAssertEqual(m.model.cartes.first?.id, Self.choix, "la carte attend le choix, en tête")
        XCTAssertNil(m.model.annonce)
        var posee = try await m.gateways.candidature.candidature(missionId: Self.choix, context: m.context)
        XCTAssertNil(posee, "aucune candidature sans contrat choisi")

        await m.parcours.choisirContrat("INCONNU")
        posee = try await m.gateways.candidature.candidature(missionId: Self.choix, context: m.context)
        XCTAssertNil(posee, "option absente de celles du serveur : rien n'est envoyé")
        XCTAssertEqual(m.model.missionChoixContrat, Self.choix)
        XCTAssertEqual(m.parcours.etape, .choixContrat(missionId: Self.choix))

        await m.parcours.choisirContrat("LIBERAL")
        posee = try await m.gateways.candidature.candidature(missionId: Self.choix, context: m.context)
        XCTAssertEqual(posee?.statut, "EN_ATTENTE")
        XCTAssertEqual(posee?.typeContratChoisi, "LIBERAL", "❤️ rejoué avec l'option choisie")
        XCTAssertEqual(m.parcours.etape, .aucune, "candidature relue : le parcours se ferme")
        XCTAssertTrue(m.model.optionsContrat.isEmpty)
        XCTAssertNil(m.model.missionChoixContrat)
        XCTAssertEqual(m.model.annonce, .candidatureEnvoyee(missionId: Self.choix))
        XCTAssertFalse(m.model.cartes.contains { $0.id == Self.choix })
        await m.parcours.choisirContrat("SALARIE")
        let encore = try await m.gateways.candidature.candidature(missionId: Self.choix, context: m.context)
        XCTAssertEqual(encore?.typeContratChoisi, "LIBERAL", "plus aucune mission en attente de choix : rien")

        // La mission de recette se retrouve partout où le web la montrerait : Mes missions › Candidatures et son détail.
        let listees = try await m.gateways.mesMissions.candidatures(context: m.context)
        let ligne = try XCTUnwrap(listees.first { $0.missionId == Self.choix }, "candidature listée dans Mes missions")
        XCTAssertEqual(ligne.mission?.record.typeContratRecherche, "TOUS")
        let detail = try await m.gateways.missions.mission(id: Self.choix, context: m.context)
        XCTAssertEqual(detail?.record.statut, "OUVERTE")
        XCTAssertEqual(detail?.etablissement?.nom, "Établissement fictif République")
        // …mais jamais dans la liste d'Explorer.
        let explorer = try await m.gateways.missions.listMissions(context: m.context, filters: MissionFilters())
        XCTAssertFalse(explorer.contains { $0.id == Self.choix || $0.id == Self.deja }, "missions de recette hors d'Explorer")
        XCTAssertEqual(explorer.count, 30)
    }

    func testChoixDeContratAbandonneLaisseLaCarte() async throws {
        let m = try await monde(premiereCandidatureVue: true)
        m.parcours.demander(Self.choix)
        await m.parcours.confirmerRecapitulatif()
        XCTAssertFalse(m.model.optionsContrat.isEmpty)
        m.parcours.abandonner()
        XCTAssertEqual(m.parcours.etape, .aucune)
        XCTAssertTrue(m.model.optionsContrat.isEmpty)
        XCTAssertNil(m.model.missionChoixContrat)
        XCTAssertTrue(m.model.cartes.contains { $0.id == Self.choix }, "feuille de choix refermée : la carte reste dans le paquet")
        await m.parcours.choisirContrat("LIBERAL")
        let posee = try await m.gateways.candidature.candidature(missionId: Self.choix, context: m.context)
        XCTAssertNil(posee)
    }

    func testSauvegarderLaCarteDeRecetteLaMetDansMesFavoris() async throws {
        let m = try await monde()
        await m.model.sauvegarder(Self.choix)
        XCTAssertEqual(m.model.annonce, .favoriSauvegarde(missionId: Self.choix))
        XCTAssertNil(m.model.message)
        let favoris = try await m.gateways.favoris.missionsSauvegardees(context: m.context)
        XCTAssertTrue(FavorisRegles.estSauvegardee(Self.choix, dans: favoris), "⭐ relu dans Mes favoris")
    }

    // MARK: - Carte déjà swipée (carte de recette `demo-swipe-deja`)

    func testCarteDejaSwipeeRefuseePuisAbsenteDesPaquetsRelus() async throws {
        let m = try await monde(premiereCandidatureVue: true)
        XCTAssertEqual(m.model.cartes.last?.id, Self.deja, "dernière carte du paquet démo")
        let quiz = try await m.gateways.swipe.nombreSwipes(context: m.context)
        XCTAssertEqual(quiz, 0, "une ligne posée ailleurs ne compte pas pour le quiz du premier contact")

        await m.model.passer(Self.deja)
        XCTAssertEqual(m.model.message, "Vous avez déjà répondu à cette mission.", "libellé produit, jamais le code technique")
        XCTAssertFalse(m.model.cartes.contains { $0.id == Self.deja }, "refus définitif : la carte quitte le paquet")
        XCTAssertEqual(m.model.cartes.count, 11)
        let relu = try await m.gateways.swipe.paquet(context: m.context)
        XCTAssertFalse(relu.contains { $0.id == Self.deja }, "le paquet relu ne la sert plus")
        XCTAssertEqual(relu.count, 11)
        await m.model.charger()
        XCTAssertEqual(m.model.cartes.count, 11)
    }

    func testCandidaterSurLaCarteDejaSwipeeEstRefuse() async throws {
        let m = try await monde(premiereCandidatureVue: true)
        m.parcours.demander(Self.deja)
        await m.parcours.confirmerRecapitulatif()
        XCTAssertEqual(m.model.message, "Vous avez déjà répondu à cette mission.")
        XCTAssertEqual(m.parcours.etape, .aucune, "refus : le parcours se ferme, le message est sur le paquet")
        XCTAssertNil(m.model.annonce)
        XCTAssertFalse(m.model.cartes.contains { $0.id == Self.deja })
        let posee = try await m.gateways.candidature.candidature(missionId: Self.deja, context: m.context)
        XCTAssertNil(posee, "aucune candidature fabriquée")
        await m.model.sauvegarder(Self.deja)
        let favoris = try await m.gateways.favoris.missionsSauvegardees(context: m.context)
        XCTAssertFalse(FavorisRegles.estSauvegardee(Self.deja, dans: favoris))
    }

    // MARK: - Verrou synchrone des gestes

    func testLancerPoseLeVerrouDansLAppelEtIgnoreLeSecondGeste() async throws {
        let m = try await monde()
        let geste = m.model.lancer(.passer, "demo-mission-015")
        XCTAssertNotNil(geste)
        XCTAssertEqual(m.model.actionEnCours, "demo-mission-015", "verrou posé avant toute suspension : le paquet garde la carte décalée")
        XCTAssertNil(m.model.lancer(.favori, "demo-mission-016"), "un second geste pendant l'appel est ignoré")
        m.parcours.demander("demo-mission-016")
        XCTAssertEqual(m.parcours.etape, .aucune, "aucun récapitulatif pendant une action en vol")
        await geste?.value
        XCTAssertNil(m.model.actionEnCours)
        XCTAssertEqual(m.model.cartes.count, 11)
        XCTAssertFalse(m.model.cartes.contains { $0.id == "demo-mission-015" })
        XCTAssertNil(m.model.lancer(.passer, "demo-mission-015"), "carte sortie du paquet : rien")
        XCTAssertNil(m.model.actionEnCours)

        let favori = m.model.lancer(.favori, "demo-mission-016")
        await favori?.value
        XCTAssertEqual(m.model.annonce, .favoriSauvegarde(missionId: "demo-mission-016"))
        XCTAssertEqual(m.model.cartes.count, 10)
    }

    // MARK: - Quiz du premier contact

    func testQuizPremierContactProposeUneFoisPuisMemorise() async throws {
        let m = try await monde()
        let premier = await m.model.quizPremierContact(dejaVu: m.marqueurs.quizVu)
        XCTAssertEqual(premier, .proposer, "aucun swipe en base, marqueur absent")
        m.marqueurs.marquerQuizVu()
        let ensuite = await m.model.quizPremierContact(dejaVu: m.marqueurs.quizVu)
        XCTAssertEqual(ensuite, .dejaFait)

        // Des swipes existent déjà (autre appareil) : rien à proposer, à mémoriser.
        let autre = try await monde()
        await autre.model.passer("demo-mission-015")
        let apresSwipe = await autre.model.quizPremierContact(dejaVu: false)
        XCTAssertEqual(apresSwipe, .dejaFait)

        // Validation du quiz : préférences amorcées dans le monde démo, critères d'Explorer dérivés des réponses.
        let reponses = ReponsesQuizSwipe(horaire: .nuit, rythme: .weekend, rayonKm: 10, tauxMin: 30)
        let applique = await m.model.appliquerQuiz(reponses.preferences)
        XCTAssertTrue(applique)
        let amorcees = await (m.gateways.swipe as? DemoSwipeGateway)?.preferences
        XCTAssertEqual(amorcees, PreferencesMatching(nuit: 0.8, jour: 0.3, weekend: 0.8, semaine: 0.3))
    }
}
