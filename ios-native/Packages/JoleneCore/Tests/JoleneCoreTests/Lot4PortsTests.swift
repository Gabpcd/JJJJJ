import XCTest
@testable import JoleneCore

/// Fondation du lot 4 (blueprint `docs/mobile-swift/LOT4_PLAN.md` §2.2-§2.3, tranche T1) : bloc « Lot 4 » de treize
/// champs additifs de `Gateways`, chacun « non câblé » par défaut ; un stub refuse explicitement (`.contract`) en citant
/// la tranche ET le lot qui le livrent ; `unwiredPorts` nomme aussi les ports du lot 4, après ceux du lot 3. Les inits
/// des lots 0 et 1 restent mot pour mot ; chaque monde assigne le bloc par `DemoLot4.cabler` / `SupabaseLot4.cabler`.
final class Lot4PortsTests: XCTestCase {
    /// Champs ajoutés au lot 4, dans l'ordre de déclaration de `Gateways` (§2.2 ; `evaluationsRecues` : garde-fou 18).
    static let portsLot4 = ["swipe", "filtres", "disponibilites", "parrainage", "litiges", "reclamations", "messagerie",
                            "realtime", "bulletins", "evaluationsRecues", "poolUrgence", "score", "exclusions"]

    private let c = DemoWorld.context

    // MARK: - Bloc lot 4 de `Gateways`

    func testInitDuLot0LaisseLesPortsDuLot4NonCablesApresCeuxDuLot3() {
        let g = Gateways(auth: NeutralAuth(), role: NeutralRole(), missions: NeutralMissions())
        XCTAssertEqual(g.unwiredPorts, Lot1PortsTests.portsLot1 + Lot2PortsTests.portsLot2 + Lot3PortsTests.portsLot3 + Self.portsLot4)
        XCTAssertEqual(Self.portsLot4.count, 13)
    }

    func testAssignerUnPortDuLot4LeRetireDeLaListe() {
        var g = Gateways(auth: NeutralAuth(), role: NeutralRole(), missions: NeutralMissions())
        g.swipe = SwipeTemoin()
        XCTAssertEqual(g.unwiredPorts.filter(Self.portsLot4.contains), Self.portsLot4.filter { $0 != "swipe" })
    }

    func testCablerDuLot4NAssigneQueLeBlocDuLot4() {
        // Témoin posé d'abord : `cabler` doit écrire le champ (ici avec le stub de T1), jamais le laisser.
        var g = Gateways(auth: NeutralAuth(), role: NeutralRole(), missions: NeutralMissions())
        g.swipe = SwipeTemoin()
        DemoLot4.cabler(&g)
        XCTAssertTrue(g.swipe is UnwiredSwipePort, "T1 : fabrique démo du swipe = stub jusqu'à T3a")
        XCTAssertEqual(g.unwiredPorts, Lot1PortsTests.portsLot1 + Lot2PortsTests.portsLot2 + Lot3PortsTests.portsLot3
                       + DemoWorldTests.portsEnAttenteLot4)
    }

    // MARK: - Stubs « non câblés »

    func testChaquePortNonCableDuLot4RefuseEnCitantSaTrancheEtSonLot() async {
        let g = Gateways(auth: NeutralAuth(), role: NeutralRole(), missions: NeutralMissions())
        let jour = JourParis(iso: "2026-11-03")
        await refuse("T3a") { _ = try await g.swipe.paquet(context: self.c) }
        await refuse("T3a") { _ = try await g.swipe.enregistrer(missionId: "m", direction: .passer, context: self.c) }
        await refuse("T3a") { _ = try await g.swipe.retirer(candidatureId: "c", context: self.c) }
        await refuse("T4") { _ = try await g.filtres.lister(context: self.c) }
        await refuse("T5") { _ = try await g.disponibilites.definir(jour: jour, creneau: .nuit, disponible: true, context: self.c) }
        await refuse("T6") { _ = try await g.parrainage.appliquer(code: "ABCD", context: self.c) }
        await refuse("T8") { _ = try await g.litiges.ouvrir(missionId: "m", motif: "Motif assez long", context: self.c) }
        await refuse("T8") { _ = try await g.reclamations.soumettre(categorie: .autre, sujet: "s", details: "d", context: self.c) }
        await refuse("T7a") { _ = try await g.messagerie.envoyer(conversationId: "x", contenu: "Bonjour", context: self.c) }
        await refuse("T7a") { _ = try await g.messagerie.nonLus(context: self.c) }
        await refuse("T10") { _ = try await g.bulletins.copies(context: self.c) }
        await refuse("T9") { _ = try await g.evaluationsRecues.recues(filtre: FiltreEvaluations(), page: 0, context: self.c) }
        await refuse("T9") { _ = try await g.score.evenements(limite: 20, context: self.c) }
        await refuse("T11") { _ = try await g.poolUrgence.basculer(actif: true, rayonKm: 30, context: self.c) }
        await refuse("T11") { _ = try await g.exclusions.exclure(etablissementId: "e", motif: "m", context: self.c) }
    }

    func testRealtimeNonCableNEmetAucunEvenement() async {
        let realtime = UnwiredRealtimePort()
        var recus = 0
        for await _ in realtime.messagesEntrants(conversationId: nil) { recus += 1 }
        for await _ in realtime.saisies(conversationId: "x") { recus += 1 }
        for await _ in realtime.presence(userId: "u") { recus += 1 }
        for await _ in realtime.etat() { recus += 1 }
        await realtime.fermerTout()
        XCTAssertEqual(recus, 0, "flux terminés immédiatement : aucun événement plausible")
    }

    // MARK: - Drapeaux des écrans secondaires (B0-bis, D18)

    func testClesDesCoupeCircuitsDuLot4() {
        let ecrans: [EcranSecondaire] = [.swipe, .recherches, .disponibilites, .parrainage, .litiges(onglet: nil, litigeId: nil),
                                         .litiges(onglet: .reclamations, litigeId: nil), .messagerie(conversationId: nil),
                                         .bulletins(copieId: nil), .evaluations, .score, .poolUrgence, .exclusions, .serie(id: "s")]
        XCTAssertEqual(ecrans.map(\.cleDrapeau), [
            "ios_natif_swipe_actif", "ios_natif_recherches_actif", "ios_natif_disponibilites_actif", "ios_natif_parrainage_actif",
            "ios_natif_litiges_actif", "ios_natif_reclamations_actif", "ios_natif_messagerie_actif", "ios_natif_bulletins_actif",
            "ios_natif_" + EcranSecondaire.Nom.evaluations.rawValue + "_actif", "ios_natif_score_actif",
            "ios_natif_pool_urgence_actif", "ios_natif_exclusions_actif", "ios_natif_serie_actif",
        ])
        XCTAssertEqual(Set(ecrans.map(\.nom)).count, EcranSecondaire.Nom.allCases.count, "treize clés, une par écran (D18)")
    }

    func testCoupeCircuitLuParLePortDeDrapeaux() async {
        let flags = DemoFlagsGateway(surcharges: ["ios_natif_messagerie_actif": false])
        let messagerie = await flags.ecranActif(EcranSecondaire.messagerie(conversationId: "x"))
        let score = await flags.ecranActif(EcranSecondaire.score)
        XCTAssertFalse(messagerie)
        XCTAssertTrue(score, "clé absente : défaut fail-open")
    }

    // MARK: - Outils

    private func refuse(_ tranche: String, file: StaticString = #filePath, line: UInt = #line,
                        _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("le stub doit refuser", file: file, line: line)
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract, file: file, line: line)
            XCTAssertTrue(erreur.message.contains("tranche \(tranche) du lot 4"), erreur.message, file: file, line: line)
            XCTAssertTrue(erreur.message.contains("LOT4_PLAN.md"), erreur.message, file: file, line: line)
        } catch {
            XCTFail("erreur inattendue : \(error)", file: file, line: line)
        }
    }
}

/// Double du port de swipe (témoin d'assignation).
private struct SwipeTemoin: SwipePort {
    func paquet(context: MissionReadContext) async throws -> [CarteSwipe] { [] }
    func enregistrer(missionId: String, direction: DirectionSwipe, context: MissionReadContext) async throws -> SwipeOutcome { .enregistre }
    func retirer(candidatureId: String, context: MissionReadContext) async throws -> RetraitOutcome { .retiree }
    func nombreSwipes(context: MissionReadContext) async throws -> Int { 0 }
    func initialiserPreferences(_ preferences: PreferencesMatching, context: MissionReadContext) async throws {}
}
