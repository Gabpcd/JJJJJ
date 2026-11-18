import XCTest
@testable import JoleneCore

/// Coquille des écrans secondaires du lot 4 (L4-T1c, `docs/mobile-swift/LOT4_PLAN.md` §3 T1c) côté JoleneCore :
/// verrous « m6 » (revue B8 de #1146), cible native d'un écran livré, lien web d'un écran, entrées du hub.
final class SecondairesLot4Tests: XCTestCase {
    private static let tous: [EcranSecondaire] = [
        .swipe, .recherches, .disponibilites, .parrainage,
        .litiges(onglet: nil, litigeId: nil), .litiges(onglet: .reclamations, litigeId: "l 1"),
        .messagerie(conversationId: nil), .messagerie(conversationId: "c1"),
        .bulletins(copieId: nil), .bulletins(copieId: "b1"),
        .evaluations, .score, .poolUrgence, .exclusions, .serie(id: "s 1"),
    ]

    // MARK: - Verrous m6 (revue B8 de #1146)

    /// Aucun branchement de la capture du parrainage avant T6 : `estLivree` figé à `false`, aucun code capturé quel que
    /// soit le lien, et le verrou bascule avec le port `parrainage` (une seule PR, T6, livre les deux).
    func testCaptureDuParrainageVerrouilleeAvantT6() throws {
        let enAttente = DemoWorldTests.portsEnAttenteLot4.contains("parrainage")
        XCTAssertEqual(ParrainageCapture.estLivree, !enAttente,
                       "T6 livre ensemble ParrainageCapture (estLivree) et le port parrainage (portsEnAttenteLot4)")
        XCTAssertEqual(VerrousLot4.parrainageBranche, ParrainageCapture.estLivree)
        XCTAssertEqual(DemoWorld.gateways().parrainage is UnwiredPort, enAttente)
        guard enAttente else { return }
        for lien in ["https://jolene.app/inscription/soignant?ref=ABCD1234",
                     "https://jolene.app/soignant/tableau-de-bord?parrain=XYZ-1234",
                     "https://jolene.app/?ref=abcd1234"] {
            let url = try XCTUnwrap(URL(string: lien))
            XCTAssertNil(VerrousLot4.codeParrainageACapturer(depuis: url), "\(lien) : aucune capture avant T6")
        }
    }

    /// Aucun abonnement Realtime avant T7a : permis seulement pour un port câblé, et le port `realtime` des deux mondes
    /// reste non câblé tant qu'il figure dans `portsEnAttenteLot4` (garde jumelle côté Supabase :
    /// `SupabaseGatewaysTests.testAbonnementRealtimeVerrouilleAvantT7a`).
    func testAbonnementRealtimeVerrouilleAvantT7a() {
        let enAttente = DemoWorldTests.portsEnAttenteLot4.contains("realtime")
        XCTAssertEqual(VerrousLot4.abonnementRealtimePermis(DemoWorld.gateways().realtime), !enAttente,
                       "abonnement permis si et seulement si T7a a câblé le port realtime")
        XCTAssertFalse(VerrousLot4.abonnementRealtimePermis(UnwiredRealtimePort()))
        XCTAssertTrue(VerrousLot4.abonnementRealtimePermis(RealtimeCable()), "le verrou n'est pas un faux constant")
    }

    // MARK: - Cible d'un écran secondaire livré

    func testAucunEcranDuLot4NestLivreParT1c() {
        for ecran in Self.tous {
            XCTAssertFalse(ecran.estLivre, "\(ecran) : renvoi web actuel gardé jusqu'à sa tranche")
        }
    }

    /// Un écran livré (destination `.secondaire`, ou `.serieDetail` pour T12) a sa cible native, présentable et portée
    /// par un onglet : la tranche qui livre n'a qu'à passer sa ligne de `ecranNatifLivre`.
    func testEcranLivreAUneCibleNativePresentable() throws {
        let canonique = try XCTUnwrap(URL(string: "https://jolene.app/soignant/parrainage"))
        for ecran in Self.tous where ecran != .serie(id: "s 1") {
            let cible = CibleNotification(destination: .secondaire(ecran), canonique: canonique)
            XCTAssertEqual(cible, .secondaire(ecran))
            XCTAssertTrue(cible.estPresentable(renvoiWebDisponible: false), "\(ecran)")
            XCTAssertEqual(cible.onglet, ecran == .swipe ? .explorer : .profil, "\(ecran)")
        }
        let serie = CibleNotification(destination: .serieDetail(id: "s 1"), canonique: canonique)
        XCTAssertEqual(serie, .secondaire(.serie(id: "s 1")), "T1c aiguille la série vers l'écran du lot 4 (T12)")
    }

    /// Tant qu'aucun écran n'est livré, la cible d'un lien du lot 4 reste celle d'avant T1c : renvoi web canonique, ou
    /// repli natif (swipe → Explorer, score → hub).
    func testLiensDuLot4GardentLeurRenvoiWeb() throws {
        for ecran in Self.tous {
            let url = try XCTUnwrap(ecran.urlWeb, "\(ecran)")
            let lien = try XCTUnwrap(DestinationLien(url: url), "\(ecran)")
            switch ecran {
            case .swipe: XCTAssertEqual(CibleNotification(lien), .explorer)
            case .score: XCTAssertEqual(CibleNotification(lien), .monCompte)
            default: XCTAssertEqual(CibleNotification(lien), .web(.safari(lien.canonique)), "\(ecran)")
            }
        }
    }

    // MARK: - Lien web d'un écran

    func testLienWebAllerRetourParLinkRouter() throws {
        for ecran in Self.tous {
            let url = try XCTUnwrap(ecran.urlWeb, "\(ecran)")
            XCTAssertEqual(url.host, "jolene.app")
            let route = try XCTUnwrap(LinkRouter.route(url: url), "\(ecran)")
            switch ecran {
            case .bulletins: XCTAssertEqual(route, .revenus(section: .bulletins), "route de Revenus gardée (T10)")
            case .serie(let id): XCTAssertEqual(route, .serieDetail(id: id))
            default: XCTAssertEqual(route, .secondaire(ecran), url.absoluteString)
            }
        }
        XCTAssertEqual(EcranSecondaire.litiges(onglet: .reclamations, litigeId: "l 1").lienWeb,
                       "/soignant/litiges?tab=reclamations&litige=l%201")
        XCTAssertEqual(EcranSecondaire.bulletins(copieId: nil).lienWeb, "/soignant/mes-gains?tab=bulletins")
        XCTAssertEqual(EcranSecondaire.messagerie(conversationId: nil).lienWeb, "/soignant/messagerie")
        XCTAssertEqual(EcranSecondaire.serie(id: "a/b").lienWeb, "/soignant/missions/serie/a%2Fb")
        XCTAssertEqual(EcranSecondaire.poolUrgence.urlWeb?.absoluteString, "https://jolene.app/soignant/pool-urgence")
    }

    // MARK: - Entrées du hub

    func testEntreesDuHubSuiventLeWebEtNeMontrentQueLesEcransLivres() {
        XCTAssertEqual(EntreesHubLot4.sections(), [], "aucun écran livré : aucune entrée native, renvois web inchangés")
        let toutes = EntreesHubLot4.sections(livre: { _ in true })
        XCTAssertEqual(toutes, EntreesHubLot4.sectionsWeb)
        XCTAssertEqual(toutes.map(\.titre), ["Recherche & disponibilité", nil, "Suivi"], "MonCompteSoignant.tsx l.94, l.107")
        XCTAssertEqual(toutes.flatMap(\.entrees).map(\.libelle),
                       ["Recherches sauvegardées", "Établissements exclus", "Parrainage", "Litiges & contestations"],
                       "MonCompteSoignant.tsx l.96-97, l.103, l.109")
        XCTAssertEqual(toutes.flatMap(\.entrees).map(\.identifiant),
                       ["hub-recherches", "hub-exclusions", "hub-parrainage", "hub-litiges"])
        let seulementParrainage = EntreesHubLot4.sections(livre: { $0 == .parrainage })
        XCTAssertEqual(seulementParrainage, [EntreesHubLot4.Section(titre: nil, entrees: [
            EntreesHubLot4.Entree(ecran: .parrainage, libelle: "Parrainage"),
        ])], "section vide retirée")
    }
}

/// Port Realtime câblé fictif (témoin du verrou) : aucun flux.
private struct RealtimeCable: RealtimePort {
    func messagesEntrants(conversationId: String?) -> AsyncStream<MessageChat> { AsyncStream { $0.finish() } }
    func saisies(conversationId: String) -> AsyncStream<EtatSaisie> { AsyncStream { $0.finish() } }
    func presence(userId: String) -> AsyncStream<EtatPresence> { AsyncStream { $0.finish() } }
    func etat() -> AsyncStream<EtatCanal> { AsyncStream { $0.finish() } }
    func fermerTout() async {}
}
