import XCTest
@testable import JoleneCore

/// Cycle de vie Realtime de la messagerie (lot 4, T7a ; `LOT4_PLAN.md` §2.5, fiche « Realtime : tables, RLS, filtres,
/// cycle de vie »), porté par `CycleRealtime` (JoleneCore) et appelé par `Jolene/Composition/RealtimeLifecycle.swift`.
/// Règles prouvées : rien n'est ouvert hors premier plan ni sans session prête ; arrière-plan → `fermerTout()` ; retour
/// au premier plan → réabonnement et badge relu ; changement d'epoch d'identité → `fermerTout()` avant toute nouvelle
/// session ; INSERT entrant → badge relu ; ordre « flux déclarés → abonnement → battement de présence » ; port Realtime
/// non câblé → aucun appel.
@MainActor
final class RealtimeLifecycleTests: XCTestCase {
    private struct Banc {
        let cycle: CycleRealtime
        let store: SessionStore
        let messagerie: MessagerieFactice
        let realtime: RealtimeFactice
        let journal: JournalAppels
    }

    private func banc(demarrer: Bool = true, realtimeCable: Bool = true, nonLus: [Int] = [3]) async -> Banc {
        let journal = JournalAppels()
        let messagerie = MessagerieFactice(journal: journal)
        messagerie.nonLusSuccessifs = nonLus
        let realtime = RealtimeFactice(journal: journal)
        var gateways = SessionMessagerie.gateways(messagerie: messagerie, realtime: realtime)
        if !realtimeCable { gateways.realtime = UnwiredRealtimePort() }
        let store = SessionStore(controller: SessionController(gateways: gateways))
        let cycle = CycleRealtime(session: store, ecranLivre: true)
        if demarrer { await store.start() }
        await cycle.repos()
        return Banc(cycle: cycle, store: store, messagerie: messagerie, realtime: realtime, journal: journal)
    }

    private func pause(_ secondes: TimeInterval = 0.06) async {
        try? await Task.sleep(nanoseconds: UInt64(secondes * 1_000_000_000))
    }

    // MARK: - Premier plan, arrière-plan

    func testRienNEstOuvertAvantLePremierPlan() async {
        let b = await banc()
        XCTAssertTrue(b.store.state.isReady)
        XCTAssertEqual(b.journal.appels, [], "session prête mais scène pas encore active : aucun canal, aucune lecture")
        XCTAssertNil(b.cycle.nonLus)
        XCTAssertEqual(b.cycle.generation, 0)
    }

    func testPremierPlanDeclareLeFluxDeLaListePuisRelitLeBadge() async throws {
        let b = await banc()
        await b.cycle.premierPlan()
        XCTAssertEqual(b.journal.appels.first, "flux messages liste", "flux de la liste déclaré d'abord")
        XCTAssertEqual(b.journal.nombre("nonLus"), 1)
        XCTAssertEqual(b.cycle.nonLus, 3, "badge = valeur serveur de fn_messages_non_lus")
        XCTAssertEqual(b.cycle.generation, 1)
        XCTAssertEqual(b.journal.nombre("fermerTout"), 0)
    }

    func testArrierePlanFermeToutPuisPremierPlanReabonneEtRelit() async {
        let b = await banc(nonLus: [3, 5])
        await b.cycle.premierPlan()
        await b.cycle.arrierePlan()
        XCTAssertEqual(b.journal.nombre("fermerTout"), 1, "arrière-plan : tous les canaux retirés")
        XCTAssertEqual(b.realtime.lecteurs(nil), 0)
        XCTAssertEqual(b.cycle.nonLus, 3, "le dernier badge lu reste affiché")
        await b.cycle.premierPlan()
        XCTAssertEqual(b.journal.nombre("flux messages liste"), 2, "retour au premier plan : réabonnement")
        XCTAssertEqual(b.cycle.nonLus, 5, "badge relu au premier plan")
        XCTAssertEqual(b.cycle.generation, 2, "les écrans relancent leur suivi")
        await b.cycle.arrierePlan()
        await b.cycle.arrierePlan()
        XCTAssertEqual(b.journal.nombre("fermerTout"), 2, "déjà fermé : pas de second appel")
    }

    func testActifSansPassageEnArrierePlanNeReabonnePasMaisRelitLeBadge() async {
        let b = await banc(nonLus: [3, 4])
        await b.cycle.premierPlan()
        await b.cycle.premierPlan() // inactif → actif (centre de contrôle) : les canaux sont restés ouverts
        XCTAssertEqual(b.journal.nombre("flux messages liste"), 1)
        XCTAssertEqual(b.cycle.generation, 1)
        XCTAssertEqual(b.cycle.nonLus, 4)
    }

    func testSessionPreteApresLePremierPlanOuvreLesCanaux() async {
        let b = await banc(demarrer: false)
        await b.cycle.premierPlan()
        XCTAssertEqual(b.journal.appels, [], "premier plan sans session prête : rien")
        await b.store.start()
        await b.cycle.repos()
        XCTAssertEqual(b.journal.nombre("flux messages liste"), 1)
        XCTAssertEqual(b.cycle.nonLus, 3)
        XCTAssertEqual(b.cycle.generation, 1)
    }

    // MARK: - Epoch d'identité

    func testChangementDEpochFermeToutAvantLaNouvelleSession() async throws {
        let b = await banc(nonLus: [3, 7])
        await b.cycle.premierPlan()
        let premierEpoch = b.store.state.snapshot?.epoch
        await b.store.signOut()
        await b.cycle.repos()
        XCTAssertEqual(b.journal.nombre("fermerTout"), 1, "fin d'identité : canaux retirés")
        XCTAssertNil(b.cycle.nonLus, "le badge d'un compte ne suit jamais le suivant")
        XCTAssertNil(b.cycle.filOuvert)
        await b.store.signIn(email: "u-1@example.invalid", password: "secret-de-test")
        await b.cycle.repos()
        XCTAssertNotEqual(b.store.state.snapshot?.epoch, premierEpoch)
        XCTAssertEqual(b.journal.nombre("flux messages liste"), 2)
        XCTAssertLessThan(try XCTUnwrap(b.journal.index("fermerTout")), try XCTUnwrap(b.journal.dernierIndex("flux messages liste")),
                          "fermerTout() avant tout canal de la nouvelle session")
        XCTAssertEqual(b.cycle.nonLus, 7)
        XCTAssertEqual(b.cycle.generation, 2)
    }

    func testRevalidationDuMemeEpochNeToucheARien() async {
        let b = await banc()
        await b.cycle.premierPlan()
        b.journal.vider()
        await b.store.start() // reprise après 30 minutes : même epoch
        await b.cycle.repos()
        XCTAssertEqual(b.journal.appels, [])
        XCTAssertEqual(b.cycle.generation, 1)
    }

    // MARK: - Badge

    func testInsertEntrantRelitLeBadgeMaisPasMonMessage() async {
        let b = await banc(nonLus: [3, 4])
        await b.cycle.premierPlan()
        b.realtime.emettre(SessionMessagerie.message("m-1", auteur: SessionMessagerie.moi))
        await pause()
        XCTAssertEqual(b.journal.nombre("nonLus"), 1, "mon propre message ne change pas mes non-lus")
        b.realtime.emettre(SessionMessagerie.message("m-2", auteur: "etab-user"))
        await waitUntil { @MainActor in b.cycle.nonLus == 4 }
        XCTAssertEqual(b.journal.nombre("nonLus"), 2)
    }

    func testBadgeIllisibleAucuneValeurFabriquee() async {
        let journal = JournalAppels()
        let realtime = RealtimeFactice(journal: journal)
        let messagerie = MessagerieEnEchec(base: MessagerieFactice(journal: journal))
        let store = SessionStore(controller: SessionController(gateways: SessionMessagerie.gateways(messagerie: messagerie, realtime: realtime)))
        await store.start()
        let cycle = CycleRealtime(session: store, ecranLivre: true)
        await cycle.premierPlan()
        XCTAssertNil(cycle.nonLus, "lecture en échec : aucun badge fabriqué")
        XCTAssertEqual(cycle.generation, 1, "les canaux sont ouverts malgré l'échec du badge")
    }

    func testConversationLueRelitLeBadge() async {
        let b = await banc(nonLus: [3, 1])
        await b.cycle.premierPlan()
        b.cycle.ouvrirFil("c-1")
        XCTAssertEqual(b.cycle.filOuvert, "c-1")
        await b.cycle.conversationLue("c-1")
        XCTAssertEqual(b.cycle.nonLus, 1, "fn_messages_non_lus relu après marquerLus")
        b.cycle.fermerFil("autre")
        XCTAssertEqual(b.cycle.filOuvert, "c-1", "seul le fil ouvert se ferme")
        b.cycle.fermerFil("c-1")
        XCTAssertNil(b.cycle.filOuvert)
    }

    // MARK: - Verrou

    func testPortRealtimeNonCableAucunAppel() async {
        let b = await banc(realtimeCable: false)
        await b.cycle.premierPlan()
        XCTAssertEqual(b.journal.appels, [], "verrou m6 : ni canal, ni lecture du badge sans port Realtime câblé")
        XCTAssertEqual(b.cycle.generation, 0)
        let ports = await b.cycle.gateways()
        XCTAssertNotNil(ports, "ports de la session courante rendus à l'app pour son verrou")
    }

    /// T7a livre le cœur sans écran : le cycle construit par l'app (`init(session:)`) n'ouvre rien tant que l'écran
    /// natif de la messagerie n'est pas livré, et s'active de lui-même quand T7b passe sa ligne de
    /// `DestinationLien.ecranNatifLivre` à `true`.
    func testCycleDeLAppInactifTantQueLEcranNEstPasLivre() async {
        let journal = JournalAppels()
        let messagerie = MessagerieFactice(journal: journal)
        messagerie.nonLusSuccessifs = [3]
        let realtime = RealtimeFactice(journal: journal)
        let store = SessionStore(controller: SessionController(gateways: SessionMessagerie.gateways(messagerie: messagerie, realtime: realtime)))
        await store.start()
        let cycle = CycleRealtime(session: store)
        await cycle.premierPlan()
        let livre = EcranSecondaire.messagerie(conversationId: nil).estLivre
        XCTAssertEqual(journal.nombre("flux messages liste"), livre ? 1 : 0, "canal de la liste ouvert si et seulement si l'écran est livré")
        XCTAssertEqual(cycle.nonLus, livre ? 3 : nil, "aucun badge lu sans écran pour l'afficher")
        XCTAssertEqual(cycle.generation, livre ? 1 : 0)
    }

    func testCoupeCircuitDeLaMessagerieNiCanalNiBadge() async {
        let journal = JournalAppels()
        let messagerie = MessagerieFactice(journal: journal)
        let realtime = RealtimeFactice(journal: journal)
        var gateways = SessionMessagerie.gateways(messagerie: messagerie, realtime: realtime)
        gateways.flags = FakeFlags(valeurs: ["ios_natif_messagerie_actif": false])
        let store = SessionStore(controller: SessionController(gateways: gateways))
        await store.start()
        let cycle = CycleRealtime(session: store, ecranLivre: true)
        await cycle.premierPlan()
        XCTAssertEqual(journal.appels, [], "messagerie coupée par son drapeau (D18) : ni Realtime ni badge")
        XCTAssertNil(cycle.nonLus)
        XCTAssertEqual(cycle.generation, 0)
        await cycle.arrierePlan()
        XCTAssertEqual(journal.nombre("fermerTout"), 0, "rien n'était ouvert")
    }

    // MARK: - Ordre du fil : flux déclarés → abonnement → battement de présence

    func testOrdreFluxDeclaresAbonnementBattementDePresence() async throws {
        let b = await banc()
        b.realtime.rejointImmediat = false
        await b.cycle.premierPlan()
        let snapshot = try XCTUnwrap(b.store.state.snapshot)
        b.messagerie.fil = [SessionMessagerie.message("m-1")]
        let model = FilModel(controller: b.store.controller, snapshot: snapshot, conversationId: "c-1", autreId: "etab-user",
                             cycle: b.cycle,
                             delais: FilModel.Delais(battement: 0.05, rafraichissementSaisie: 2, inactiviteSaisie: 3, peremptionSaisie: 6))
        let suivi = Task { await model.suivre() }
        await waitUntil { @MainActor in model.etat == .pret }
        await waitUntil { b.journal.nombre("marquerLus") == 1 }
        await pause(0.12)
        XCTAssertEqual(b.journal.nombre("presence"), 0, "aucun battement tant que le canal du fil n'est pas abonné")
        b.realtime.etatCanal(.rejoint, conversationId: nil) // le canal de la liste ne suffit pas
        await pause(0.12)
        XCTAssertEqual(b.journal.nombre("presence"), 0, "seul le canal du fil déclenche le premier battement")
        b.realtime.etatCanal(.rejoint, conversationId: "c-1")
        await waitUntil { b.journal.nombre("presence") >= 1 }
        let flux = try XCTUnwrap(b.journal.index("flux messages c-1"))
        let abonnement = try XCTUnwrap(b.journal.index("canal c-1 rejoint"))
        let battement = try XCTUnwrap(b.journal.index("presence"))
        XCTAssertLessThan(flux, abonnement, "flux déclarés avant l'abonnement")
        XCTAssertLessThan(abonnement, battement, "premier fn_update_presence après l'abonnement réussi du canal du fil")
        await waitUntil { b.journal.nombre("presence") >= 3 } // battement périodique tant que le fil est visible
        suivi.cancel()
        await suivi.value
        await pause(0.12)
        let apresFermeture = b.journal.nombre("presence")
        await pause(0.15)
        XCTAssertEqual(b.journal.nombre("presence"), apresFermeture, "fil masqué : plus aucun battement")
        XCTAssertNil(b.cycle.filOuvert)
    }

    func testArrierePlanArreteLeFilEtSonBattement() async throws {
        let b = await banc()
        await b.cycle.premierPlan()
        let snapshot = try XCTUnwrap(b.store.state.snapshot)
        let model = FilModel(controller: b.store.controller, snapshot: snapshot, conversationId: "c-1", autreId: "etab-user",
                             cycle: b.cycle,
                             delais: FilModel.Delais(battement: 0.05, rafraichissementSaisie: 2, inactiviteSaisie: 3, peremptionSaisie: 6))
        let suivi = Task { await model.suivre() }
        await waitUntil { b.journal.nombre("presence") >= 1 }
        await b.cycle.arrierePlan()
        await suivi.value // flux fermés par fermerTout() : le suivi du fil se termine
        let battements = b.journal.nombre("presence")
        await pause(0.15)
        XCTAssertEqual(b.journal.nombre("presence"), battements, "arrière-plan : aucun battement, aucun mode d'arrière-plan")
    }
}

/// Port de messagerie dont le badge est illisible ; tout le reste est délégué.
private struct MessagerieEnEchec: MessageriePort {
    let base: MessagerieFactice

    func conversations(avant: CurseurConversations?, context: MissionReadContext) async throws -> PageConversations {
        try await base.conversations(avant: avant, context: context)
    }
    func interlocuteurs(ids: [String], context: MissionReadContext) async throws -> [Interlocuteur] {
        try await base.interlocuteurs(ids: ids, context: context)
    }
    func messages(conversationId: String, context: MissionReadContext) async throws -> [MessageChat] {
        try await base.messages(conversationId: conversationId, context: context)
    }
    func envoyer(conversationId: String, contenu: String, context: MissionReadContext) async throws -> EnvoiOutcome {
        try await base.envoyer(conversationId: conversationId, contenu: contenu, context: context)
    }
    func message(id: String, conversationId: String, context: MissionReadContext) async throws -> MessageChat? {
        try await base.message(id: id, conversationId: conversationId, context: context)
    }
    func marquerLus(conversationId: String, context: MissionReadContext) async throws -> IssueLecture {
        try await base.marquerLus(conversationId: conversationId, context: context)
    }
    func saisie(debut: Bool, conversationId: String, context: MissionReadContext) async throws {}
    func presence(context: MissionReadContext) async throws {}
    func bloque(cibleId: String, context: MissionReadContext) async throws -> Bool { false }
    func basculerBlocage(cibleId: String, bloquer: Bool, context: MissionReadContext) async throws -> Bool { bloquer }
    func signaler(cibleId: String, type: TypeCibleSignalement, categorie: String, motif: String, missionId: String?,
                  context: MissionReadContext) async throws -> IssueSignalement { .signale }
    func nonLus(context: MissionReadContext) async throws -> Int { throw JoleneError(.network, "coupure") }
    func conversationPourMission(missionId: String, etablissementId: String,
                                 context: MissionReadContext) async throws -> IssueConversationMission {
        .indisponible(message: "indisponible")
    }
}
