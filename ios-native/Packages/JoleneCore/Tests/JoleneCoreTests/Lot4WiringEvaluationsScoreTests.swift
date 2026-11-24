import XCTest
@testable import JoleneCore

/// Câblage démo des évaluations reçues et du score (lot 4, T9 ; garde anti-oubli `Lot4Wiring<Domaine>Tests`,
/// `LOT4_PLAN.md` §2.2) et parcours du monde démo : signalement → `signale: true` relu, contestation → événement relu
/// non contestable, refus verbatim du serveur, aucune moyenne recalculée, contexte étranger refusé.
final class Lot4WiringEvaluationsScoreTests: XCTestCase {
    private let context = DemoWorld.context

    func testDemoWorldCableLesEvaluationsEtLeScore() {
        let gateways = DemoWorld.gateways()
        XCTAssertTrue(gateways.evaluationsRecues is DemoEvaluationsGateway)
        XCTAssertTrue(gateways.score is DemoScoreGateway)
        XCTAssertFalse(gateways.unwiredPorts.contains("evaluationsRecues"))
        XCTAssertFalse(gateways.unwiredPorts.contains("score"))
        XCTAssertTrue(EcranSecondaire.evaluations.estLivre)
        XCTAssertTrue(EcranSecondaire.score.estLivre)
    }

    func testLiensDesDeuxEcransOuvrentLEcranNatif() throws {
        for (chemin, ecran) in [("/soignant/evaluations", EcranSecondaire.evaluations), ("/soignant/score", .score),
                                ("/soignant/fiabilite", .score), ("/soignant/fiabilite-legacy", .score)] {
            let lien = try XCTUnwrap(DestinationLien(link: chemin), chemin)
            XCTAssertEqual(lien.destination, .secondaire(ecran), "\(chemin) : écran natif livré, plus de renvoi web ni de repli")
            XCTAssertEqual(CibleNotification(lien), .secondaire(ecran), chemin)
        }
    }

    func testParcoursDemoSignalement() async throws {
        let evaluations = DemoWorld.gateways().evaluationsRecues
        let page = try await evaluations.recues(filtre: FiltreEvaluations(), page: 0, context: context)
        XCTAssertEqual(page.notations.count, 4, "quatre notations publiées")
        XCTAssertEqual(page.stats?.noteMoyenneGlobale, 4.4)

        let issue = try await evaluations.signaler(notationId: "demo-notation-002", motif: "Évaluation sans rapport avec la mission.",
                                                   context: context)
        XCTAssertEqual(issue, .signale)
        let relue = try await evaluations.recues(filtre: FiltreEvaluations(), page: 0, context: context)
        XCTAssertEqual(relue.notations.first { $0.id == "demo-notation-002" }?.signale, true)
        XCTAssertEqual(relue.stats, page.stats, "le signalement ne change aucune statistique servie")
        let encore = try await evaluations.signaler(notationId: "demo-notation-002", motif: "Évaluation sans rapport.", context: context)
        XCTAssertEqual(encore, .refuse(message: "Notation déjà signalée"))
        let fixture = try await evaluations.signaler(notationId: "demo-notation-004", motif: "Évaluation sans rapport.", context: context)
        XCTAssertEqual(fixture, .refuse(message: "Notation déjà signalée"), "déjà signalée dans la fixture")
        let inconnue = try await evaluations.signaler(notationId: "absente", motif: "Évaluation sans rapport.", context: context)
        XCTAssertEqual(inconnue, .refuse(message: "Vous ne pouvez signaler que les notations vous concernant"))
    }

    func testFiltresDemoSansRecalculDesStatistiques() async throws {
        let evaluations = DemoEvaluationsGateway()
        let tout = try await evaluations.recues(filtre: FiltreEvaluations(), page: 0, context: context)
        let cas: [(FiltreEvaluations, [String])] = [
            (FiltreEvaluations(periode: .troisMois), ["demo-notation-001", "demo-notation-002"]),
            (FiltreEvaluations(periode: .sixMois), ["demo-notation-001", "demo-notation-002", "demo-notation-003"]),
            (FiltreEvaluations(periode: .douzeMois), ["demo-notation-001", "demo-notation-002", "demo-notation-003", "demo-notation-004"]),
            (FiltreEvaluations(noteMin: 5), ["demo-notation-001"]),
            (FiltreEvaluations(noteMin: 4), ["demo-notation-001", "demo-notation-002", "demo-notation-003", "demo-notation-004"]),
            (FiltreEvaluations(etablissementId: "demo-etab-3"), ["demo-notation-004"]),
            (FiltreEvaluations(periode: .troisMois, noteMin: 5, etablissementId: "demo-etab-2"), []),
        ]
        for (filtre, attendues) in cas {
            let page = try await evaluations.recues(filtre: filtre, page: 0, context: context)
            XCTAssertEqual(page.notations.map(\.id), attendues, "\(filtre)")
            XCTAssertEqual(page.total, attendues.count)
            XCTAssertEqual(page.stats, tout.stats, "statistiques globales : indépendantes des filtres, comme la RPC")
            XCTAssertEqual(page.evolution, tout.evolution)
            XCTAssertEqual(page.etablissements, tout.etablissements)
        }
        let auDela = try await evaluations.recues(filtre: FiltreEvaluations(), page: 3, context: context)
        XCTAssertEqual(auDela.notations, [])
        XCTAssertEqual(auDela.total, 4)
    }

    func testParcoursDemoContestation() async throws {
        let score = DemoWorld.gateways().score
        let breakdown = try await score.breakdown(context: context)
        XCTAssertEqual(breakdown.score, 72.6)
        let evolution = try await score.evolution(mois: 6, context: context)
        XCTAssertEqual(evolution.count, 6, "six points d'évolution")
        let notations = try await score.notationsRecues(limite: 20, context: context)
        XCTAssertEqual(notations.count, 4)
        let evenements = try await score.evenements(limite: 20, context: context)
        XCTAssertEqual(evenements.count, 3)
        XCTAssertEqual(evenements.filter(\.contestable).map(\.id), ["demo-evenement-001"], "un seul événement contestable")

        let texte = "J'avais prévenu l'établissement la veille."
        let court = try await score.contester(evenementId: "demo-evenement-001", motif: "AUTRE", texte: "Trop court.", context: context)
        XCTAssertEqual(court, .refusee(code: "TEXTE_REQUIS", message: "Texte libre obligatoire (min 20 caractères)"))
        let motif = try await score.contester(evenementId: "demo-evenement-001", motif: "CONVENANCE", texte: texte, context: context)
        XCTAssertEqual(motif, .refusee(code: "MOTIF_INVALIDE", message: "Motif catégorie invalide"))
        let issue = try await score.contester(evenementId: "demo-evenement-001", motif: "FORCE_MAJEURE", texte: texte, context: context)
        XCTAssertEqual(issue, .enregistree(reclamationId: "demo-reclamation-1"))
        let relus = try await score.evenements(limite: 20, context: context)
        XCTAssertEqual(relus.map(\.contestable), [false, false, false], "événement contesté relu non contestable")
        let encore = try await score.contester(evenementId: "demo-evenement-001", motif: "FORCE_MAJEURE", texte: texte, context: context)
        XCTAssertEqual(encore, .refusee(code: "RECLAMATION_EN_COURS", message: "Une réclamation est déjà ouverte pour cet événement"))
        let traite = try await score.contester(evenementId: "demo-evenement-002", motif: "AUTRE", texte: texte, context: context)
        XCTAssertEqual(traite, .refusee(code: "DEJA_TRAITE", message: "Cet événement a déjà été traité par un admin"))
        let ferme = try await score.contester(evenementId: "demo-evenement-003", motif: "AUTRE", texte: texte, context: context)
        XCTAssertEqual(ferme, .refusee(code: "NON_CONTESTABLE", message: "Cet événement n'est pas contestable"))
        let absent = try await score.contester(evenementId: "absent", motif: "AUTRE", texte: texte, context: context)
        XCTAssertEqual(absent, .refusee(code: "EVENT_INTROUVABLE", message: "Événement de score introuvable"))
    }

    /// Les refus du monde démo sont ceux du serveur, mot pour mot (`supabase/schema/public.sql`).
    func testRefusDemoSontCeuxDuSchema() throws {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent("supabase/schema/public.sql")
        guard FileManager.default.fileExists(atPath: fichier.path) else { throw XCTSkip("public.sql introuvable : \(fichier.path)") }
        let schema = try String(contentsOf: fichier, encoding: .utf8)
        for message in [DemoEvaluationsGateway.nonConcerne, DemoEvaluationsGateway.dejaSignalee, DemoScoreGateway.motifInvalide,
                        DemoScoreGateway.texteRequis, DemoScoreGateway.introuvable, DemoScoreGateway.nonContestable,
                        DemoScoreGateway.dejaTraite, DemoScoreGateway.reclamationEnCours] {
            XCTAssertTrue(schema.contains("'\(message.replacingOccurrences(of: "'", with: "''"))'"), "« \(message) » absent du schéma")
        }
    }

    func testContexteEtrangerRefuse() async throws {
        var etranger = context
        etranger.userId = "autre"
        etranger.profile.id = "autre"
        let gateways = DemoWorld.gateways()
        for operation: () async throws -> Void in [
            { _ = try await gateways.evaluationsRecues.recues(filtre: FiltreEvaluations(), page: 0, context: etranger) },
            { _ = try await gateways.evaluationsRecues.signaler(notationId: "demo-notation-001", motif: "Motif assez long.", context: etranger) },
            { _ = try await gateways.score.breakdown(context: etranger) },
            { _ = try await gateways.score.evenements(limite: 20, context: etranger) },
            { _ = try await gateways.score.contester(evenementId: "demo-evenement-001", motif: "AUTRE", texte: "Vingt caractères au moins.", context: etranger) },
        ] {
            do {
                try await operation()
                XCTFail("contexte étranger accepté")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .demoOnly)
            }
        }
    }
}
