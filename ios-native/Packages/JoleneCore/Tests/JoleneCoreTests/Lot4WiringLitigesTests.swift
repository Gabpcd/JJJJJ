import XCTest
@testable import JoleneCore

/// Câblage démo des litiges (lot 4, T8 ; garde anti-oubli `Lot4Wiring<Domaine>Tests`, `LOT4_PLAN.md` §2.2) et parcours
/// du monde démo de bout en bout (§2.7) : trois litiges de `demo-litiges.json` (OUVERT, EN_MEDIATION,
/// RESOLU_ACCORD_PARTIES), fil de `demo-litige-fil.json`, deux missions proposées, ouverture relue en tête, message
/// ajouté et relu, refus du serveur rejoués mot pour mot.
final class Lot4WiringLitigesTests: XCTestCase {
    private let context = DemoWorld.context

    func testDemoWorldCableLesLitiges() {
        let gateways = DemoWorld.gateways()
        XCTAssertTrue(gateways.litiges is DemoLitigesGateway)
        XCTAssertFalse(gateways.unwiredPorts.contains("litiges"))
    }

    func testFixturesLuesDansLOrdreServeurAvecLeNomDeLEtablissement() async throws {
        let port = DemoLitigesGateway()
        let litiges = try await port.lister(context: context)
        XCTAssertEqual(litiges.map(\.id), ["demo-litige-001", "demo-litige-002", "demo-litige-003"], "cree_le décroissant")
        XCTAssertEqual(litiges.map(\.statut), ["OUVERT", "EN_MEDIATION", "RESOLU_ACCORD_PARTIES"])
        XCTAssertEqual(litiges.map(\.typeLitige), ["AUTRE", "AUTRE", "AUTRE"])
        XCTAssertEqual(litiges[0], Litige(id: "demo-litige-001", missionId: "demo-litige-mission-001", etablissementId: "demo-etab-1",
                                          statut: "OUVERT", typeLitige: "AUTRE",
                                          motif: "Démonstration · Désaccord sur le poste occupé pendant la mission.",
                                          creeLe: "2026-11-01T04:00:00.000Z", missionIntitule: "Démonstration · Mission en litige 1",
                                          missionDebutLe: "2026-10-30T07:00:00.000Z", etablissementNom: "Établissement fictif République"))
        XCTAssertEqual(litiges[2].resolution, "Démonstration · Accord trouvé entre les parties.", "texte de clôture du serveur")
        XCTAssertEqual(try DemoFixtures.loadLitiges().fixedNow, "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(try DemoFixtures.loadLitigeFil().fixedNow, "2026-11-02T00:00:00.000Z")

        let fil = try await port.fil(litigeId: "demo-litige-001", context: context)
        XCTAssertEqual(fil.map(\.id), ["demo-litige-message-003", "demo-litige-message-004"], "ordre chronologique")
        XCTAssertEqual(fil.map(\.typeAuteur), ["SOIGNANT", "ETABLISSEMENT"])
        XCTAssertEqual(fil.first?.auteurId, context.userId)
        let inconnu = try await port.fil(litigeId: "demo-litige-999", context: context)
        XCTAssertEqual(inconnu, [], "aucun message lisible : fil vide, comme la lecture sous RLS")
    }

    /// Les missions proposées sont celles du monde démo (une seule source), jamais une copie dans la fixture des litiges.
    func testMissionsProposeesSontLesMissionsTermineesDuMondeDemo() async throws {
        let port = DemoLitigesGateway()
        let missions = try await port.missionsContestables(context: context)
        XCTAssertEqual(missions, [
            MissionContestable(id: "demo-terminee-001", intitule: "Démonstration · Mission terminée 1",
                               debutLe: "2026-11-01T07:00:00.000Z", etablissementId: "demo-etab-1",
                               etablissementNom: "Établissement fictif République"),
            MissionContestable(id: "demo-terminee-002", intitule: "Démonstration · Mission terminée 2",
                               debutLe: "2026-10-20T07:00:00.000Z", etablissementId: "demo-etab-2",
                               etablissementNom: "Établissement fictif des Lilas"),
        ], "TERMINEE seulement (la mission annulée n'est pas proposée), fin_le décroissant")
        let passees = try DemoFixtures.loadMesMissions().passees.map(\.mission.record)
        XCTAssertEqual(Set(missions.map(\.id)), Set(passees.filter { $0.statut == "TERMINEE" || $0.statut == "EN_COURS" }.map(\.id)))
        let enLitige = Set(try DemoFixtures.loadLitiges().litiges.compactMap(\.missionId))
        XCTAssertTrue(enLitige.isDisjoint(with: missions.map(\.id)), "aucune mission proposée n'a déjà un litige")
    }

    func testOuverturePuisFilEtRefusDuServeurMotPourMot() async throws {
        let port = DemoLitigesGateway()
        let court = try await port.ouvrir(missionId: "demo-terminee-001", motif: "  trop  ", context: context)
        XCTAssertEqual(court, .refuse(message: "Le motif doit contenir entre 10 et 2 000 caractères."))
        let long = try await port.ouvrir(missionId: "demo-terminee-001", motif: String(repeating: "a", count: 2001), context: context)
        XCTAssertEqual(long, .refuse(message: "Le motif doit contenir entre 10 et 2 000 caractères."))
        let absente = try await port.ouvrir(missionId: "demo-mission-absente", motif: "Motif assez long", context: context)
        XCTAssertEqual(absente, .refuse(message: "Mission introuvable"))
        let avant = try await port.lister(context: context)
        XCTAssertEqual(avant.count, 3, "aucun refus n'écrit de litige")

        let issue = try await port.ouvrir(missionId: "demo-terminee-001", motif: "  Désaccord sur les heures  ", context: context)
        XCTAssertEqual(issue, .ouvert(id: "demo-litige-ajout-1", informatif: false))
        let litiges = try await port.lister(context: context)
        XCTAssertEqual(litiges.map(\.id), ["demo-litige-ajout-1", "demo-litige-001", "demo-litige-002", "demo-litige-003"],
                       "le litige ouvert est relu en tête")
        XCTAssertEqual(litiges.first, Litige(id: "demo-litige-ajout-1", missionId: "demo-terminee-001", etablissementId: "demo-etab-1",
                                             statut: "OUVERT", typeLitige: "AUTRE", motif: "Désaccord sur les heures",
                                             creeLe: "2026-11-02T00:00:00.000Z", missionIntitule: "Démonstration · Mission terminée 1",
                                             missionDebutLe: "2026-11-01T07:00:00.000Z",
                                             etablissementNom: "Établissement fictif République"))
        let restantes = try await port.missionsContestables(context: context)
        XCTAssertEqual(restantes.map(\.id), ["demo-terminee-002"], "la mission en litige n'est plus proposée")
        let doublon = try await port.ouvrir(missionId: "demo-terminee-001", motif: "Second litige sur la même mission", context: context)
        XCTAssertEqual(doublon, .refuse(message: "Un litige de ce type est déjà ouvert pour cette mission."))

        // Fil du litige ouvert : vide, puis un message relu.
        let vide = try await port.fil(litigeId: "demo-litige-ajout-1", context: context)
        XCTAssertEqual(vide, [])
        let tropCourt = try await port.ajouterMessage(litigeId: "demo-litige-ajout-1", contenu: " bonjour ", context: context)
        XCTAssertEqual(tropCourt, .refuse(message: "Le message doit contenir entre 10 et 5000 caractères."))
        let ajout = try await port.ajouterMessage(litigeId: "demo-litige-ajout-1", contenu: "  Voici le détail du désaccord.  ", context: context)
        guard case let .ajoute(fil) = ajout else { return XCTFail("fil relu attendu, obtenu \(ajout)") }
        XCTAssertEqual(fil.map(\.contenu), ["Voici le détail du désaccord."])
        XCTAssertEqual(fil.first?.auteurId, context.userId)
        XCTAssertEqual(fil.first?.typeAuteur, "SOIGNANT")

        // Litige résolu ou inconnu : refus du serveur, mot pour mot, sans écriture.
        let clos = try await port.ajouterMessage(litigeId: "demo-litige-003", contenu: "Message sur un litige résolu", context: context)
        XCTAssertEqual(clos, .refuse(message: "Ce litige est clôturé."))
        let inconnu = try await port.ajouterMessage(litigeId: "demo-litige-999", contenu: "Message sur un litige inconnu", context: context)
        XCTAssertEqual(inconnu, .refuse(message: "Litige introuvable ou accès refusé"))
        let filResolu = try await port.fil(litigeId: "demo-litige-003", context: context)
        XCTAssertEqual(filResolu.count, 1, "aucun message ajouté au litige résolu")
    }

    func testPlafondHoraireEtContexteEtrangerRefuses() async throws {
        let recents = (1...3).map { numero in
            Litige(id: "recent-\(numero)", missionId: "autre-mission-\(numero)", statut: "OUVERT", typeLitige: "AUTRE",
                   creeLe: DateHeureParis.isoUTC(DemoWorld.fixedNow.addingTimeInterval(-600)))
        }
        let sature = DemoLitigesGateway(initiaux: recents)
        let plafond = try await sature.ouvrir(missionId: "demo-terminee-001", motif: "Quatrième litige de l'heure", context: context)
        XCTAssertEqual(plafond, .refuse(message: "Trop de litiges ouverts récemment. Réessayez plus tard."))

        var etranger = context
        etranger.userId = "autre"
        etranger.profile.id = "autre"
        do {
            _ = try await DemoLitigesGateway().lister(context: etranger)
            XCTFail("contexte étranger accepté")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
    }
}

/// Câblage démo des réclamations générales (lot 4, T8) et parcours du monde démo : fixture `demo-reclamations.json`,
/// réclamation soumise relue en tête au statut `EN_ATTENTE`.
final class Lot4WiringReclamationsTests: XCTestCase {
    private let context = DemoWorld.context

    func testDemoWorldCableLesReclamations() {
        let gateways = DemoWorld.gateways()
        XCTAssertTrue(gateways.reclamations is DemoReclamationsGateway)
        XCTAssertFalse(gateways.unwiredPorts.contains("reclamations"))
    }

    func testFixturePuisSoumissionRelueEnTete() async throws {
        let port = DemoReclamationsGateway()
        let liste = try await port.lister(context: context)
        XCTAssertEqual(liste.map(\.id), ["demo-reclamation-001", "demo-reclamation-002"], "cree_le décroissant")
        XCTAssertEqual(liste.map(\.statut), ["EN_ATTENTE", "RESOLUE"])
        XCTAssertNil(liste[0].reponseAdmin)
        XCTAssertEqual(liste[1].reponseAdmin, "Démonstration · L’horaire a été corrigé, merci de votre signalement.")
        XCTAssertEqual(liste[1].traiteLe, "2026-10-23T00:00:00.000Z")
        XCTAssertEqual(try DemoFixtures.loadReclamations().fixedNow, "2026-11-02T00:00:00.000Z")

        let issue = try await port.soumettre(categorie: .paiement, sujet: "Montant à vérifier", details: "Le montant affiché diffère.",
                                             context: context)
        let attendue = Reclamation(id: "demo-reclamation-ajout-1", categorie: "PAIEMENT", sujet: "Montant à vérifier",
                                   details: "Le montant affiché diffère.", statut: "EN_ATTENTE", creeLe: "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(issue, .soumise(attendue))
        let relue = try await port.lister(context: context)
        XCTAssertEqual(relue.map(\.id), ["demo-reclamation-ajout-1", "demo-reclamation-001", "demo-reclamation-002"])
        XCTAssertEqual(relue.first, attendue)
    }

    func testContexteEtrangerRefuse() async throws {
        var etranger = context
        etranger.userId = "autre"
        etranger.profile.id = "autre"
        do {
            _ = try await DemoReclamationsGateway().soumettre(categorie: .autre, sujet: "s", details: "d", context: etranger)
            XCTFail("contexte étranger accepté")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
    }
}
