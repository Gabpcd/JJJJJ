import XCTest
@testable import JoleneCore

/// « Mon score » et la contestation d'un événement (L4-T9) sur le monde démo (`DemoScoreGateway`, fixture
/// `demo-score.json`) et sur des ports témoins : aucune lecture en échec remplacée par un état vide, contestation
/// confirmée par la relecture des événements (`contestable == false`, PRINCIPES §3), refus serveur verbatim.
@MainActor
final class ScoreModelTests: XCTestCase {
    /// Port témoin : lectures du monde démo (ou remplacées), contestation remplacée ; compte les appels.
    private final class PortTemoin: ScorePort, @unchecked Sendable {
        private let verrou = NSLock()
        private let demo = DemoScoreGateway()
        private var contestations = 0
        private var lecturesEvenements = 0
        var contestation: (@Sendable () throws -> ReclamationScoreOutcome)?
        var evenementsRemplaces: (@Sendable (Int) throws -> [EvenementScore]?)?
        var evolutionEnEchec: JoleneError?

        var nombreDeContestations: Int { verrou.withLock { contestations } }
        var nombreDeLecturesEvenements: Int { verrou.withLock { lecturesEvenements } }

        func breakdown(context: MissionReadContext) async throws -> BreakdownScore { try await demo.breakdown(context: context) }
        func evolution(mois: Int, context: MissionReadContext) async throws -> [PointEvolutionScore] {
            if let evolutionEnEchec { throw evolutionEnEchec }
            return try await demo.evolution(mois: mois, context: context)
        }
        func evenements(limite: Int, context: MissionReadContext) async throws -> [EvenementScore] {
            let rang = verrou.withLock { () -> Int in lecturesEvenements += 1; return lecturesEvenements }
            if let remplaces = try evenementsRemplaces?(rang) { return remplaces }
            return try await demo.evenements(limite: limite, context: context)
        }
        func notationsRecues(limite: Int, context: MissionReadContext) async throws -> [NotationRecue] {
            try await demo.notationsRecues(limite: limite, context: context)
        }
        func contester(evenementId: String, motif: String, texte: String,
                       context: MissionReadContext) async throws -> ReclamationScoreOutcome {
            verrou.withLock { contestations += 1 }
            if let contestation { return try contestation() }
            return try await demo.contester(evenementId: evenementId, motif: motif, texte: texte, context: context)
        }
    }

    private func modele(_ port: any ScorePort = DemoScoreGateway()) async throws -> ScoreModel {
        var gateways = DemoWorld.gateways()
        gateways.score = port
        let controller = SessionController(gateways: gateways)
        let state = await controller.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        let snapshot = try XCTUnwrap(state.snapshot, "session démo prête attendue, obtenu \(state)")
        let model = ScoreModel(controller: controller, snapshot: snapshot)
        await model.charger()
        return model
    }

    private static let texte = "J'avais prévenu l'établissement la veille par téléphone."

    // MARK: - Lecture

    func testPageDeLaFixture() async throws {
        let model = try await modele()
        let contenu = try XCTUnwrap(model.etat.contenu)
        XCTAssertEqual(contenu.breakdown.score, 72.6)
        XCTAssertEqual(ScorePresentation.score(contenu.breakdown), "73", "Math.round(score_total)")
        XCTAssertEqual(ScoreTextes.niveau(contenu.breakdown.niveau), "🥇 Or")
        XCTAssertFalse(ScorePresentation.nonNote(contenu.breakdown))
        XCTAssertEqual(contenu.evolution.count, 6)
        XCTAssertEqual(contenu.evenements.map(\.contestable), [true, false, false])
        XCTAssertEqual(contenu.notations.map(\.id), ["demo-notation-001", "demo-notation-002", "demo-notation-003", "demo-notation-004"])
        XCTAssertTrue(contenu.notations.allSatisfy { $0.signale == nil && $0.etablissementNom == nil },
                      "notations de « Mon score » : anonymes, sans `signale`, comme fn_lister_notations_recues")
        XCTAssertNil(model.erreur)
    }

    func testUneLectureEnEchecNEstJamaisUnEtatVide() async throws {
        // Le web afficherait « aucun événement » ou « pas encore d'historique » : ici, la page est en échec.
        let evolution = PortTemoin()
        evolution.evolutionEnEchec = JoleneError(.network, "Connexion impossible.")
        let sansEvolution = try await modele(evolution)
        XCTAssertEqual(sansEvolution.etat, .echec("Connexion impossible."))

        let contrat = PortTemoin()
        contrat.evenementsRemplaces = { _ in throw JoleneError(.contract, "Cette version de l'application n'est plus compatible avec le service. Mettez-la à jour.") }
        let illisible = try await modele(contrat)
        XCTAssertEqual(illisible.etat, .echec("Cette version de l'application n'est plus compatible avec le service. Mettez-la à jour."),
                       "réponse `evenements` (contrat) : jamais « aucun événement »")

        let session = PortTemoin()
        session.evolutionEnEchec = JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")
        let expiree = try await modele(session)
        XCTAssertTrue(expiree.sessionExpiree)
    }

    // MARK: - Contestation

    func testContestationConfirmeeParLesEvenementsRelus() async throws {
        let model = try await modele()
        let evenement = try XCTUnwrap(model.etat.contenu?.evenements.first)
        XCTAssertTrue(evenement.contestable)
        let envoyee = await model.contester(evenement, motif: .contexteParticulier, texte: "  \(Self.texte)  ")
        XCTAssertTrue(envoyee)
        XCTAssertEqual(model.confirmation, ScoreTextes.reclamationEnvoyee)
        XCTAssertNil(model.erreur)
        XCTAssertEqual(model.etat.contenu?.evenements.first?.contestable, false, "événement relu non contestable")
        XCTAssertNil(model.contestationEnCours)

        // Nouvelle contestation du même événement : refus du serveur, verbatim.
        let encore = await model.contester(evenement, motif: .autre, texte: Self.texte)
        XCTAssertFalse(encore)
        XCTAssertEqual(model.erreur, "Une réclamation est déjà ouverte pour cet événement")
        XCTAssertNil(model.confirmation)
    }

    func testRefusDuServeurVerbatimParCode() async throws {
        let model = try await modele()
        let evenements = try XCTUnwrap(model.etat.contenu?.evenements)
        let traite = await model.contester(evenements[1], motif: .erreurJolene, texte: Self.texte)
        XCTAssertFalse(traite)
        XCTAssertEqual(model.erreur, "Cet événement a déjà été traité par un admin")
        let nonContestable = await model.contester(evenements[2], motif: .erreurJolene, texte: Self.texte)
        XCTAssertFalse(nonContestable)
        XCTAssertEqual(model.erreur, "Cet événement n'est pas contestable")
        let inconnu = EvenementScore(id: "absent", typeEvenement: "AUTRE", points: -1, motif: nil, contestable: true)
        _ = await model.contester(inconnu, motif: .autre, texte: Self.texte)
        XCTAssertEqual(model.erreur, "Événement de score introuvable")

        for (code, message) in [("TEXTE_REQUIS", "Texte libre obligatoire (min 20 caractères)"),
                                ("NON_CONTESTABLE", "Cet événement n'est pas contestable"),
                                ("DEJA_TRAITE", "Cet événement a déjà été traité par un admin"),
                                ("RECLAMATION_EN_COURS", "Une réclamation est déjà ouverte pour cet événement")] {
            let port = PortTemoin()
            port.contestation = { .refusee(code: code, message: message) }
            let refuse = try await modele(port)
            let cible = try XCTUnwrap(refuse.etat.contenu?.evenements.first)
            let envoyee = await refuse.contester(cible, motif: .deuil, texte: Self.texte)
            XCTAssertFalse(envoyee, code)
            XCTAssertEqual(refuse.erreur, message, code)
            XCTAssertEqual(port.nombreDeContestations, 1, "aucun renvoi")
            XCTAssertEqual(port.nombreDeLecturesEvenements, 2, "événements relus après un refus")
        }
        let sansMessage = PortTemoin()
        sansMessage.contestation = { .refusee(code: "X", message: "") }
        let repli = try await modele(sansMessage)
        _ = await repli.contester(try XCTUnwrap(repli.etat.contenu?.evenements.first), motif: .deuil, texte: Self.texte)
        XCTAssertEqual(repli.erreur, ScoreTextes.erreur, "repli du web pour un refus sans message")
    }

    func testMotifAbsentOuTexteTropCourtAucunAppel() async throws {
        let port = PortTemoin()
        let model = try await modele(port)
        let evenement = try XCTUnwrap(model.etat.contenu?.evenements.first)
        let sansMotif = await model.contester(evenement, motif: nil, texte: Self.texte)
        XCTAssertFalse(sansMotif)
        XCTAssertEqual(model.erreur, ScoreTextes.motifRequis)
        for texte in ["", "   ", "Dix-neuf caractères", "  pas assez long   "] {
            let court = await model.contester(evenement, motif: .autre, texte: texte)
            XCTAssertFalse(court, texte)
            XCTAssertEqual(model.erreur, ScoreTextes.texteRequis)
        }
        XCTAssertEqual(port.nombreDeContestations, 0, "aucun appel sans motif ni explication de vingt caractères")
        XCTAssertEqual(ScorePresentation.texteValide("  vingt caractères ok.  "), "vingt caractères ok.")
        XCTAssertNil(ScorePresentation.texteValide("dix-neuf caractères"))
    }

    func testRelectureQuiNeConfirmePasJamaisUnSucces() async throws {
        // Le serveur répond « enregistrée » mais l'événement relu reste contestable : aucun succès annoncé.
        let port = PortTemoin()
        port.contestation = { .enregistree(reclamationId: "r-1") }
        let model = try await modele(port)
        let evenement = try XCTUnwrap(model.etat.contenu?.evenements.first)
        let envoyee = await model.contester(evenement, motif: .autre, texte: Self.texte)
        XCTAssertFalse(envoyee)
        XCTAssertEqual(model.erreur, ScoreTextes.contestationNonConfirmee)
        XCTAssertNil(model.confirmation)

        // Relecture en échec après un succès du serveur : message de transport, aucun succès annoncé.
        let coupe = PortTemoin()
        coupe.contestation = { .enregistree(reclamationId: "r-2") }
        coupe.evenementsRemplaces = { rang in
            if rang >= 2 { throw JoleneError(.network, "Connexion impossible.") }
            return nil
        }
        let sansRelecture = try await modele(coupe)
        let cible = try XCTUnwrap(sansRelecture.etat.contenu?.evenements.first)
        let confirmee = await sansRelecture.contester(cible, motif: .autre, texte: Self.texte)
        XCTAssertFalse(confirmee)
        XCTAssertEqual(sansRelecture.erreur, "Connexion impossible.")
        XCTAssertNil(sansRelecture.confirmation)
    }

    func testErreurDeTransportPuisRelectureEtSessionExpiree() async throws {
        let reseau = PortTemoin()
        reseau.contestation = { throw JoleneError(.network, "Connexion impossible.") }
        let model = try await modele(reseau)
        let evenement = try XCTUnwrap(model.etat.contenu?.evenements.first)
        let envoyee = await model.contester(evenement, motif: .autre, texte: Self.texte)
        XCTAssertFalse(envoyee)
        XCTAssertEqual(model.erreur, "Connexion impossible.")
        XCTAssertEqual(reseau.nombreDeLecturesEvenements, 2, "le serveur a pu agir : relecture, jamais de renvoi")
        XCTAssertEqual(reseau.nombreDeContestations, 1)

        let session = PortTemoin()
        session.contestation = { throw JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.") }
        let expiree = try await modele(session)
        _ = await expiree.contester(try XCTUnwrap(expiree.etat.contenu?.evenements.first), motif: .autre, texte: Self.texte)
        XCTAssertTrue(expiree.sessionExpiree)
        XCTAssertEqual(session.nombreDeLecturesEvenements, 1, "session expirée : aucune relecture")

        let annulee = PortTemoin()
        annulee.contestation = { throw CancellationError() }
        let annulation = try await modele(annulee)
        _ = await annulation.contester(try XCTUnwrap(annulation.etat.contenu?.evenements.first), motif: .autre, texte: Self.texte)
        XCTAssertNil(annulation.erreur, "une annulation n'est jamais une erreur")
    }

    // MARK: - Présentation

    func testAffichageDuScoreSansDefautFabrique() throws {
        let sansRien = BreakdownScore(score: nil, niveau: nil)
        XCTAssertNil(ScorePresentation.score(sansRien), "jamais 50")
        XCTAssertNil(ScoreTextes.niveau(sansRien.niveau), "jamais Bronze")
        XCTAssertTrue(ScorePresentation.nonNote(sansRien))
        XCTAssertNil(ScorePresentation.missionsRestantes(sansRien),
                     "compte non servi : « Non noté » seul, jamais un nombre calculé sur un 0 par défaut (revue B8 textes, mineur 13)")
        XCTAssertEqual(ScoreTextes.scoreDisponibleApres(3), "Score disponible après 3 missions terminées de plus.")
        let deux = BreakdownScore(score: 50, niveau: "BRONZE", totalMissionsTerminees: 2)
        XCTAssertTrue(ScorePresentation.nonNote(deux))
        XCTAssertEqual(ScorePresentation.missionsRestantes(BreakdownScore(score: nil, niveau: nil, totalMissionsTerminees: 0)), 3)
        XCTAssertEqual(ScoreTextes.scoreDisponibleApres(try XCTUnwrap(ScorePresentation.missionsRestantes(deux))),
                       "Score disponible après 1 mission terminée de plus.")
        XCTAssertFalse(ScorePresentation.nonNote(BreakdownScore(score: 50, niveau: "BRONZE", totalMissionsTerminees: 3)))
        XCTAssertEqual(ScorePresentation.score(BreakdownScore(score: 72.5, niveau: nil)), "73", "Math.round : demi vers le haut")
        XCTAssertEqual(ScorePresentation.score(BreakdownScore(score: 0, niveau: nil)), "0", "un vrai 0 reste affiché")
        XCTAssertEqual(ScoreTextes.niveaux.map { ScoreTextes.niveau($0.code) }, ["🥉 Bronze", "🥈 Argent", "🥇 Or", "💎 Platine"])
        XCTAssertEqual(ScoreTextes.niveau("DIAMANT"), "DIAMANT", "niveau inconnu : valeur serveur telle quelle")
    }

    func testMiseEnFormeDuDetailEtDesEvenements() throws {
        let fichier = try DemoFixtures.loadScore()
        let breakdown = try XCTUnwrap(ScoreDecodage.breakdown(calcul: fichier.breakdown, profil: fichier.soignant))
        XCTAssertEqual(ScorePresentation.pourcentage(88.8), "89%")
        XCTAssertEqual(ScoreTextes.poids(38.9), "poids 39%")
        XCTAssertEqual(ScoreTextes.poids(22.2), "poids 22%")
        XCTAssertEqual(ScorePresentation.progression(120), 1)
        XCTAssertEqual(ScorePresentation.progression(40), 0.4)
        let inactives = breakdown.composantes.filter { !$0.estActive }
        XCTAssertEqual(inactives.map(ScoreTextes.inactive), ["• Réactivité aux propositions : 10% redistribué"])
        XCTAssertEqual(ScoreTextes.inactive(ComposanteScore(cle: .presentisme, pct: nil, poids: nil)), "• Présentéisme",
                       "poids initial non servi : aucun poids affiché (jamais une constante de l'app)")
        XCTAssertEqual(ScoreTextes.inactivesTexte(1), "1 composante non comptée (pas assez de données). Les autres composantes voient leur poids majoré proportionnellement.")
        XCTAssertEqual(ScoreTextes.inactivesTexte(2), "2 composantes non comptées (pas assez de données). Les autres composantes voient leur poids majoré proportionnellement.")
        XCTAssertEqual(ScorePresentation.malusEtBonus(breakdown), ["🚫 Absence sans prévenir : -5 pts"])
        XCTAssertEqual(ScorePresentation.malusEtBonus(BreakdownScore(score: 80, niveau: "OR", litigesMalus: -12.5,
                                                                     absenceSansPrevenirMalus: 0, bonusSuperActif: 5)),
                       ["⚠️ Litiges perdus 12 mois : -12.5 pts (cap -20)",
                        "Bonus super-actif (plus de 50 missions sur 12 mois) : +5 pts"])
        XCTAssertEqual(ScoreTextes.points(-5), "-5 pts")
        XCTAssertEqual(ScoreTextes.points(5), "+5 pts")
        XCTAssertEqual(ScoreTextes.points(0), "0 pts")
        XCTAssertEqual(ScoreTextes.pointsEvenement(-4), "-4 pts")
        XCTAssertEqual(ScoreTextes.decisionAdmin("REDUIRE"), "✔️ Décision admin : REDUIRE")
        let evenements = try XCTUnwrap(ScoreDecodage.evenements(fichier.evenements))
        XCTAssertEqual(ScorePresentation.etatNonContestable(evenements[1]), "Traitée")
        XCTAssertEqual(ScorePresentation.etatNonContestable(evenements[2]), "Non contestable")
        XCTAssertEqual(ScorePresentation.dateEvenement(evenements[0].creeLe), "23 octobre 2026 à 02:00", "heure de Paris")
        XCTAssertNil(ScorePresentation.dateEvenement("illisible"))
        let notation = NotationRecue(id: "n", missionFinLe: "2026-10-26T00:00:00.000Z", noteMoyenne: 5, creeLe: "2026-10-28T00:00:00.000Z")
        XCTAssertEqual(ScorePresentation.metaNotation(notation), "Mission terminée le 26 oct. 2026 · Notée par : Établissement anonyme · 28 oct.")
        XCTAssertEqual(ScorePresentation.metaNotation(NotationRecue(id: "n")), "Notée par : Établissement anonyme")
        XCTAssertEqual(ScoreTextes.noteSur5("5.0"), "⭐ 5.0/5")
        XCTAssertEqual(ScoreTextes.donneesLimitees(1), "Données limitées : 1 snapshot. Le graphique s'enrichira avec le temps.")
        XCTAssertEqual(ScoreTextes.compteurTexte(12), "12 / 20+")
        XCTAssertEqual(ScoreTextes.criteres.count, 4)
    }
}
