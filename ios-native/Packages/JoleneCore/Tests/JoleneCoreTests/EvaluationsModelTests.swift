import XCTest
@testable import JoleneCore

/// « Mes évaluations » (L4-T9) sur le monde démo (`DemoEvaluationsGateway`, fixture `demo-evaluations.json`) et sur des
/// ports témoins : statistiques du serveur jamais recalculées, filtres et pages dérivés de la page lue, signalement
/// confirmé par relecture (PRINCIPES §3), refus serveur verbatim.
@MainActor
final class EvaluationsModelTests: XCTestCase {
    /// Port témoin : lecture du monde démo (ou remplacée), signalement remplacé ; compte les appels.
    private final class PortTemoin: EvaluationsPort, @unchecked Sendable {
        private let verrou = NSLock()
        private let demo = DemoEvaluationsGateway()
        private var lectures = 0
        private var signalements = 0
        var lecture: (@Sendable (Int, FiltreEvaluations, Int) throws -> PageEvaluations?)?
        var signalement: @Sendable () throws -> IssueSignalement = { .signale }

        var nombreDeLectures: Int { verrou.withLock { lectures } }
        var nombreDeSignalements: Int { verrou.withLock { signalements } }

        func recues(filtre: FiltreEvaluations, page: Int, context: MissionReadContext) async throws -> PageEvaluations {
            let rang = verrou.withLock { () -> Int in lectures += 1; return lectures }
            if let remplacee = try lecture?(rang, filtre, page) { return remplacee }
            return try await demo.recues(filtre: filtre, page: page, context: context)
        }

        func signaler(notationId: String, motif: String, context: MissionReadContext) async throws -> IssueSignalement {
            verrou.withLock { signalements += 1 }
            return try signalement()
        }
    }

    private func session(_ port: any EvaluationsPort) async throws -> (SessionController, SessionSnapshot) {
        var gateways = DemoWorld.gateways()
        gateways.evaluationsRecues = port
        let controller = SessionController(gateways: gateways)
        let state = await controller.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        return (controller, try XCTUnwrap(state.snapshot, "session démo prête attendue, obtenu \(state)"))
    }

    private func modele(_ port: any EvaluationsPort = DemoEvaluationsGateway()) async throws -> EvaluationsModel {
        let (controller, snapshot) = try await session(port)
        let model = EvaluationsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        return model
    }

    private static let motif = "Cette évaluation ne correspond pas à la mission."

    // MARK: - Lecture

    func testPageDeLaFixtureStatistiquesDuServeur() async throws {
        let model = try await modele()
        let page = try XCTUnwrap(model.etat.page)
        XCTAssertEqual(page.notations.map(\.id), ["demo-notation-001", "demo-notation-002", "demo-notation-003", "demo-notation-004"])
        XCTAssertEqual(page.total, 4)
        XCTAssertEqual(page.stats, StatsEvaluations(noteMoyenneGlobale: 4.4, totalEvaluations: 4, pct5Etoiles: 25))
        XCTAssertEqual(page.evolution.map(\.mois), ["2026-07", "2026-09", "2026-10"])
        XCTAssertEqual(page.etablissements.map(\.id), ["demo-etab-1", "demo-etab-2", "demo-etab-3"])
        XCTAssertEqual(page.notations.map(\.signale), [false, false, false, true], "une notation déjà signalée")
        XCTAssertEqual(model.nombreDePages, 1)
        XCTAssertFalse(model.aPageSuivante)
        XCTAssertFalse(model.aPagePrecedente)
        XCTAssertNil(model.erreur)
    }

    func testFiltresRelisentLaPageSansRecalculerLesStatistiques() async throws {
        let model = try await modele()
        await model.choisir(periode: .troisMois)
        XCTAssertEqual(model.etat.page?.notations.map(\.id), ["demo-notation-001", "demo-notation-002"])
        XCTAssertEqual(model.etat.page?.total, 2)
        // La moyenne des deux notes affichées vaut 4,75 : la moyenne globale servie reste 4,4, le total reste 4.
        XCTAssertEqual(model.etat.page?.stats, StatsEvaluations(noteMoyenneGlobale: 4.4, totalEvaluations: 4, pct5Etoiles: 25),
                       "statistiques globales du serveur : jamais dérivées de la page filtrée")
        await model.choisir(noteMin: 5)
        XCTAssertEqual(model.etat.page?.notations.map(\.id), ["demo-notation-001"])
        XCTAssertEqual(model.filtre, FiltreEvaluations(periode: .troisMois, noteMin: 5))
        await model.choisir(periode: .tout)
        await model.choisir(noteMin: nil)
        await model.choisir(etablissementId: "demo-etab-1")
        XCTAssertEqual(model.etat.page?.notations.map(\.id), ["demo-notation-001", "demo-notation-003"])
        await model.choisir(etablissementId: "")
        XCTAssertNil(model.filtre.etablissementId, "« Tous établissements »")
        XCTAssertEqual(model.etat.page?.total, 4)
        await model.choisir(periode: .douzeMois)
        XCTAssertEqual(model.etat.page?.total, 4)
        await model.choisir(periode: .sixMois)
        XCTAssertEqual(model.etat.page?.notations.map(\.id), ["demo-notation-001", "demo-notation-002", "demo-notation-003"])
    }

    func testPaginationParVingtEtRetourALaPremierePageAuChangementDeFiltre() async throws {
        let notations = (1...45).map { NotationRecue(id: "n-\($0)", noteMoyenne: 4, signale: false, creeLe: "2026-10-01T00:00:00Z") }
        let grande = PageEvaluations(total: 45, notations: notations, stats: nil, evolution: [], etablissements: [])
        let model = try await modele(DemoEvaluationsGateway(initiale: grande))
        XCTAssertEqual(model.etat.page?.notations.count, 20)
        XCTAssertEqual(model.nombreDePages, 3, "Math.ceil(45 / 20)")
        XCTAssertTrue(model.aPageSuivante)
        await model.pagePrecedente()
        XCTAssertEqual(model.page, 0, "déjà à la première page")
        await model.pageSuivante()
        await model.pageSuivante()
        XCTAssertEqual(model.page, 2)
        XCTAssertEqual(model.etat.page?.notations.map(\.id), ["n-41", "n-42", "n-43", "n-44", "n-45"])
        XCTAssertFalse(model.aPageSuivante)
        await model.pageSuivante()
        XCTAssertEqual(model.page, 2, "aucune page au-delà de la dernière")
        await model.choisir(noteMin: 4)
        XCTAssertEqual(model.page, 0, "un filtre remet la page à 0 (web l.189, l.200, l.211)")
        XCTAssertEqual(model.etat.page?.notations.first?.id, "n-1")
    }

    func testEchecDeLectureJamaisUnePageVideEtFiltresRevenusALaPageAffichee() async throws {
        let enEchec = PortTemoin()
        enEchec.lecture = { _, _, _ in throw JoleneError(.network, "Connexion impossible.") }
        let premier = try await modele(enEchec)
        XCTAssertEqual(premier.etat, .echec("Connexion impossible."), "jamais « Aucune évaluation » sur un échec")

        let port = PortTemoin()
        port.lecture = { rang, _, _ in
            if rang == 2 { throw JoleneError(.network, "Connexion impossible.") }
            return nil
        }
        let model = try await modele(port)
        XCTAssertEqual(model.etat.page?.total, 4)
        await model.choisir(periode: .troisMois)
        XCTAssertEqual(model.erreur, "Connexion impossible.")
        XCTAssertEqual(model.etat.page?.total, 4, "la page affichée reste celle d'avant")
        XCTAssertEqual(model.filtre, FiltreEvaluations(), "état dérivé : le filtre décrit la page affichée")
        XCTAssertEqual(model.page, 0)
        await model.choisir(periode: .troisMois)
        XCTAssertNil(model.erreur)
        XCTAssertEqual(model.etat.page?.total, 2)
    }

    func testSessionExpireeEtAnnulation() async throws {
        let expiree = PortTemoin()
        expiree.lecture = { _, _, _ in throw JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.") }
        let session = try await modele(expiree)
        XCTAssertTrue(session.sessionExpiree)
        XCTAssertEqual(session.etat, .echec("Votre session a expiré. Reconnectez-vous."))

        let annulee = PortTemoin()
        annulee.lecture = { _, _, _ in throw CancellationError() }
        let annulation = try await modele(annulee)
        XCTAssertEqual(annulation.etat, .chargement, "une annulation n'est jamais une erreur")
        XCTAssertNil(annulation.erreur)
    }

    // MARK: - Signalement

    func testSignalementConfirmeParLaPageRelue() async throws {
        let model = try await modele()
        let notation = try XCTUnwrap(model.etat.page?.notations.first)
        XCTAssertEqual(notation.signale, false)
        let signalee = await model.signaler(notation, motif: "  \(Self.motif)  ")
        XCTAssertTrue(signalee)
        XCTAssertEqual(model.confirmation, EvaluationsTextes.signalementTransmis)
        XCTAssertNil(model.erreur)
        XCTAssertEqual(model.etat.page?.notations.first?.signale, true, "badge « Déjà signalée » lu sur la page relue")
        XCTAssertNil(model.signalementEnCours)

        // Second signalement : refus du serveur, verbatim.
        let encore = await model.signaler(notation, motif: Self.motif)
        XCTAssertFalse(encore)
        XCTAssertEqual(model.erreur, "Notation déjà signalée")
        XCTAssertNil(model.confirmation)
        let dejaSignalee = try XCTUnwrap(model.etat.page?.notations.last)
        let fixture = await model.signaler(dejaSignalee, motif: Self.motif)
        XCTAssertFalse(fixture)
        XCTAssertEqual(model.erreur, DemoEvaluationsGateway.dejaSignalee)
    }

    func testMotifTropCourtAucunAppel() async throws {
        let port = PortTemoin()
        let model = try await modele(port)
        let notation = try XCTUnwrap(model.etat.page?.notations.first)
        for motif in ["", "   ", "Trop bref", "  neuf car  "] {
            let envoye = await model.signaler(notation, motif: motif)
            XCTAssertFalse(envoye, motif)
            XCTAssertEqual(model.erreur, EvaluationsTextes.signalementMotifRequis)
        }
        XCTAssertEqual(port.nombreDeSignalements, 0, "moins de dix caractères : aucun appel")
        XCTAssertEqual(EvaluationsPresentation.motifValide("  dix lettre  "), "dix lettre")
    }

    func testRelectureQuiNeConfirmePasJamaisUnSucces() async throws {
        // Le serveur répond « signalé » mais la page relue ne le montre pas : aucun succès annoncé.
        let port = PortTemoin()
        let model = try await modele(port)
        let notation = try XCTUnwrap(model.etat.page?.notations.first)
        let signalee = await model.signaler(notation, motif: Self.motif)
        XCTAssertFalse(signalee)
        XCTAssertEqual(model.erreur, EvaluationsTextes.signalementNonConfirme)
        XCTAssertNil(model.confirmation)
        XCTAssertEqual(port.nombreDeSignalements, 1, "aucun renvoi")
        XCTAssertEqual(port.nombreDeLectures, 2, "une relecture après le signalement")
    }

    func testRefusVerbatimEtErreurDeTransportPuisRelecture() async throws {
        let refus = PortTemoin()
        refus.signalement = { .refuse(message: "Vous ne pouvez signaler que les notations vous concernant") }
        let refuse = try await modele(refus)
        let notation = try XCTUnwrap(refuse.etat.page?.notations.first)
        let envoye = await refuse.signaler(notation, motif: Self.motif)
        XCTAssertFalse(envoye)
        XCTAssertEqual(refuse.erreur, "Vous ne pouvez signaler que les notations vous concernant")
        XCTAssertEqual(refus.nombreDeLectures, 2, "relecture après un refus")

        let sansMessage = PortTemoin()
        sansMessage.signalement = { .refuse(message: "") }
        let repli = try await modele(sansMessage)
        _ = await repli.signaler(notation, motif: Self.motif)
        XCTAssertEqual(repli.erreur, EvaluationsTextes.erreurSignalement, "repli du web pour un refus sans message")

        let reseau = PortTemoin()
        reseau.signalement = { throw JoleneError(.network, "Connexion impossible.") }
        let coupe = try await modele(reseau)
        let coupee = await coupe.signaler(notation, motif: Self.motif)
        XCTAssertFalse(coupee)
        XCTAssertEqual(coupe.erreur, "Connexion impossible.")
        XCTAssertEqual(reseau.nombreDeLectures, 2, "le serveur a pu agir : relecture, jamais de renvoi")
        XCTAssertEqual(reseau.nombreDeSignalements, 1)

        let session = PortTemoin()
        session.signalement = { throw JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.") }
        let expiree = try await modele(session)
        _ = await expiree.signaler(notation, motif: Self.motif)
        XCTAssertTrue(expiree.sessionExpiree)
        XCTAssertEqual(session.nombreDeLectures, 1, "session expirée : aucune relecture")
    }

    // MARK: - Présentation

    func testMiseEnFormeDesValeursServeur() {
        XCTAssertEqual(EvaluationsPresentation.note(4.4), "4.4")
        XCTAssertEqual(EvaluationsPresentation.note(5), "5.0")
        XCTAssertEqual(EvaluationsPresentation.note(4.25), "4.3", "toFixed(1) : demi exact vers le haut")
        XCTAssertEqual(EvaluationsPresentation.note(0), "0.0")
        XCTAssertEqual(EvaluationsPresentation.note(nil), "—", "note absente : jamais 0.0")
        XCTAssertEqual(EvaluationsPresentation.pourcentage(25), "25%")
        XCTAssertEqual(EvaluationsPresentation.pourcentage(33.3), "33.3%")
        XCTAssertEqual(EvaluationsPresentation.pourcentage(nil), "—")
        XCTAssertEqual(EvaluationsPresentation.noteDernierMois([]), "—")
        XCTAssertEqual(EvaluationsPresentation.noteDernierMois([PointEvolutionNotes(mois: "2026-09", noteMoyenne: 4.5, nb: 1),
                                                                 PointEvolutionNotes(mois: "2026-10", noteMoyenne: 5, nb: 1)]), "5.0")
        XCTAssertEqual(EvaluationsPresentation.date("2026-10-28T00:00:00.000Z"), "28 oct. 2026")
        XCTAssertEqual(EvaluationsPresentation.date("2026-10-31T23:30:00.000Z"), "1 nov. 2026", "heure de Paris")
        XCTAssertNil(EvaluationsPresentation.date("illisible"))
        XCTAssertEqual(EvaluationsPresentation.moisCourt("2026-07"), "juil.")
        XCTAssertEqual(EvaluationsPresentation.moisCourt("2026-13"), "2026-13")
        XCTAssertEqual(EvaluationsPresentation.nombreDePages(total: 0), 0)
        XCTAssertEqual(EvaluationsPresentation.nombreDePages(total: 20), 1)
        XCTAssertEqual(EvaluationsPresentation.nombreDePages(total: 21), 2)
        XCTAssertEqual(EvaluationsTextes.compte(0), "0 évaluation")
        XCTAssertEqual(EvaluationsTextes.compte(1), "1 évaluation")
        XCTAssertEqual(EvaluationsTextes.compte(4), "4 évaluations")
        XCTAssertEqual(EvaluationsTextes.page(0, sur: 3), "Page 1 / 3")
        XCTAssertEqual(EvaluationsTextes.commentaire("Très bien."), "« Très bien. »")
        XCTAssertEqual(EvaluationsTextes.noteMoyenneSur5("4.5"), "Note moyenne : 4.5/5")
        XCTAssertEqual(EvaluationsTextes.compteurMotif(7), "7 / 10+")
        XCTAssertEqual(EvaluationsTextes.libelle(noteMin: nil), "Toutes notes")
        XCTAssertEqual(EvaluationsTextes.notesMin.map { EvaluationsTextes.libelle(noteMin: $0) },
                       ["5 étoiles", "4 étoiles et +", "3 étoiles et +"])
        XCTAssertEqual(PeriodeEvaluations.allCases.map(EvaluationsTextes.libelle),
                       ["Toutes périodes", "3 derniers mois", "6 derniers mois", "12 derniers mois"])
    }
}
