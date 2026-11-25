import XCTest
@testable import JoleneCore

/// Blocage, signalement et « Écrire à l'établissement » (lot 4, T7b ; exigence Apple 1.2). Règles prouvées : succès
/// annoncé seulement sur l'état relu ; blocage en deux temps, déblocage direct ; refus serveur verbatim ; délai dépassé →
/// statut relu, aucun nouvel envoi ; motif de 10 caractères au moins ; fil de la mission ouvert par la gateway démo.
@MainActor
final class ModerationModelsTests: XCTestCase {
    /// Port de modération scriptable ; tout le reste de la messagerie est hors sujet ici.
    private final class Moderation: MessageriePort, @unchecked Sendable {
        let journal = JournalAppels()
        var bloqueServi: @Sendable () async throws -> Bool = { false }
        var bascule: @Sendable (Bool) async throws -> Bool = { $0 }
        var signalement: @Sendable () async throws -> IssueSignalement = { .signale }
        var contact: @Sendable () async throws -> IssueConversationMission = { .conversation(id: "c-m") }
        private var hors: JoleneError { JoleneError(.contract, "hors sujet") }

        func conversations(avant: CurseurConversations?, context: MissionReadContext) async throws -> PageConversations { throw hors }
        func interlocuteurs(ids: [String], context: MissionReadContext) async throws -> [Interlocuteur] { throw hors }
        func messages(conversationId: String, context: MissionReadContext) async throws -> [MessageChat] { throw hors }
        func envoyer(conversationId: String, contenu: String, context: MissionReadContext) async throws -> EnvoiOutcome { throw hors }
        func message(id: String, conversationId: String, context: MissionReadContext) async throws -> MessageChat? { throw hors }
        func marquerLus(conversationId: String, context: MissionReadContext) async throws -> IssueLecture { throw hors }
        func saisie(debut: Bool, conversationId: String, context: MissionReadContext) async throws { throw hors }
        func presence(context: MissionReadContext) async throws { throw hors }
        func nonLus(context: MissionReadContext) async throws -> Int { throw hors }
        func bloque(cibleId: String, context: MissionReadContext) async throws -> Bool {
            journal.noter("bloque \(cibleId)")
            return try await bloqueServi()
        }
        func basculerBlocage(cibleId: String, bloquer: Bool, context: MissionReadContext) async throws -> Bool {
            journal.noter(bloquer ? "bloquer \(cibleId)" : "debloquer \(cibleId)")
            return try await bascule(bloquer)
        }
        func signaler(cibleId: String, type: TypeCibleSignalement, categorie: String, motif: String, missionId: String?,
                      context: MissionReadContext) async throws -> IssueSignalement {
            journal.noter("signaler \(cibleId) \(type.rawValue) \(categorie) \(missionId ?? "nil") \(motif)")
            return try await signalement()
        }
        func conversationPourMission(missionId: String, etablissementId: String,
                                     context: MissionReadContext) async throws -> IssueConversationMission {
            journal.noter("contact \(missionId) \(etablissementId)")
            return try await contact()
        }
    }

    private func session(_ port: MessageriePort, timeout: TimeInterval = SessionController.defaultResolutionTimeout) async throws
        -> (SessionController, SessionSnapshot) {
        try await SessionMessagerie.prete(messagerie: port, realtime: RealtimeFactice(journal: JournalAppels()), timeout: timeout)
    }

    // MARK: Blocage

    func testBlocageEnDeuxTempsPuisDeblocageDirect() async throws {
        let port = Moderation()
        let (controller, snapshot) = try await session(port)
        let model = BlocageModel(controller: controller, snapshot: snapshot, cibleId: "autre-1", libelleCible: "l’établissement")
        XCTAssertNil(model.libelleBouton, "aucun bouton tant que le statut n'est pas lu")
        await model.lire()
        XCTAssertEqual(model.statut, .lu(bloque: false))
        XCTAssertEqual(model.libelleBouton, "Bloquer")
        await model.demander()
        XCTAssertTrue(model.confirmation, "le blocage demande une confirmation")
        XCTAssertEqual(port.journal.nombre("bloquer"), 0)
        await model.confirmer()
        XCTAssertEqual(port.journal.nombre("bloquer autre-1"), 1)
        XCTAssertEqual(model.statut, .lu(bloque: true))
        XCTAssertFalse(model.confirmation)
        XCTAssertEqual(model.message, "L’établissement bloqué — les nouveaux messages sont coupés dans les deux sens.")
        XCTAssertTrue(model.succes)
        XCTAssertEqual(model.libelleBouton, "Débloquer")
        await model.demander()
        XCTAssertEqual(port.journal.nombre("debloquer autre-1"), 1, "déblocage direct, sans confirmation")
        XCTAssertEqual(model.message, "L’établissement débloqué.")
    }

    func testEtatReluContraireAucunSucces() async throws {
        let port = Moderation()
        port.bascule = { _ in false } // le serveur relit « non bloqué »
        let (controller, snapshot) = try await session(port)
        let model = BlocageModel(controller: controller, snapshot: snapshot, cibleId: "autre-1", libelleCible: "cet utilisateur")
        await model.lire()
        await model.demander()
        await model.confirmer()
        XCTAssertEqual(model.statut, .lu(bloque: false))
        XCTAssertFalse(model.succes)
        XCTAssertEqual(model.message, "Action impossible pour le moment.")
    }

    func testRefusServeurVerbatimEtLectureIndisponible() async throws {
        let port = Moderation()
        port.bascule = { _ in throw JoleneError(.unknown, "Cible invalide.") }
        let (controller, snapshot) = try await session(port)
        let model = BlocageModel(controller: controller, snapshot: snapshot, cibleId: "autre-1", libelleCible: "cet utilisateur")
        await model.lire()
        await model.demander()
        await model.confirmer()
        XCTAssertEqual(model.message, "Cible invalide.")
        XCTAssertFalse(model.succes)

        port.bloqueServi = { throw JoleneError(.network, "coupure") }
        await model.lire()
        XCTAssertEqual(model.statut, .indisponible, "jamais un statut supposé")
        XCTAssertNil(model.libelleBouton)
    }

    func testDelaiDepasseStatutReluSansRenvoi() async throws {
        let port = Moderation()
        port.bascule = { _ in
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return true
        }
        let (controller, snapshot) = try await session(port, timeout: 0.2)
        let model = BlocageModel(controller: controller, snapshot: snapshot, cibleId: "autre-1", libelleCible: "cet utilisateur")
        await model.lire()
        port.bloqueServi = { true } // le blocage a abouti côté serveur
        await model.demander()
        await model.confirmer()
        XCTAssertEqual(port.journal.nombre("bloquer"), 1, "aucun nouvel envoi")
        XCTAssertEqual(port.journal.nombre("bloque autre-1"), 2, "statut relu après le délai")
        XCTAssertEqual(model.statut, .lu(bloque: true))
        XCTAssertEqual(model.message, "Action impossible pour le moment. Réessayez.")
        XCTAssertFalse(model.succes)
    }

    // MARK: Signalement

    func testSignalementMotifObligatoirePuisTransmis() async throws {
        let port = Moderation()
        let (controller, snapshot) = try await session(port)
        let cible = ModerationConversation.CibleSignalement(cibleId: "e-1", type: .etablissement, missionId: "m-1")
        let model = SignalementModel(controller: controller, snapshot: snapshot, cible: cible)
        XCTAssertEqual(model.categorie, "COMPORTEMENT_INAPPROPRIE")
        model.motif = "  court    "
        XCTAssertFalse(model.envoiPossible)
        let refuse = await model.envoyer()
        XCTAssertFalse(refuse)
        XCTAssertEqual(model.erreur, "Merci de préciser le motif (10 caractères minimum).")
        XCTAssertEqual(port.journal.nombre("signaler"), 0, "rien n'est envoyé sous 10 caractères")

        model.categorie = "FRAUDE_SUSPECTEE"
        model.motif = "  Comportement inacceptable au téléphone  "
        XCTAssertTrue(model.envoiPossible)
        let envoye = await model.envoyer()
        XCTAssertTrue(envoye)
        XCTAssertTrue(model.transmis)
        XCTAssertNil(model.erreur)
        XCTAssertEqual(port.journal.appels.last, "signaler e-1 ETABLISSEMENT FRAUDE_SUSPECTEE m-1 Comportement inacceptable au téléphone")
    }

    func testSignalementRefuseGardeLaSaisie() async throws {
        let port = Moderation()
        port.signalement = { .refuse(message: "Catégorie invalide") }
        let (controller, snapshot) = try await session(port)
        let model = SignalementModel(controller: controller, snapshot: snapshot,
                                     cible: .init(cibleId: "e-1", type: .etablissement, missionId: nil))
        model.motif = "Un motif suffisamment long"
        let envoye = await model.envoyer()
        XCTAssertFalse(envoye)
        XCTAssertFalse(model.transmis)
        XCTAssertEqual(model.erreur, "Catégorie invalide")
        XCTAssertEqual(model.motif, "Un motif suffisamment long")

        port.signalement = { throw JoleneError(.network, "coupure") }
        _ = await model.envoyer()
        XCTAssertEqual(model.erreur, "Échec de l'envoi du signalement.")
    }

    // MARK: « Écrire à l'établissement »

    private func mission(statut: String, assigne: String?) -> MissionRecord {
        var record = MissionRecord(id: "m-1", intitule: "Mission", description: nil, service: nil, professionRequise: "IDE",
                                   specialiteMedicaleRequise: nil, accepteNonSpecialises: nil,
                                   debutLe: "2026-11-05T07:00:00.000Z", finLe: "2026-11-05T15:00:00.000Z", dureeHeures: nil,
                                   nbCreneaux: nil, tauxHoraireBase: nil, tauxRistPlafonne: nil, ristPlafondApplique: nil,
                                   totalBrut: nil, netAPayer: nil, estUrgente: false, niveauUrgence: nil, statut: statut,
                                   etablissementId: "e-1", typeContratRecherche: nil, boosteeLe: nil, modeRemuneration: nil,
                                   retrocessionPct: nil)
        record.soignantAssigneId = assigne
        return record
    }

    func testBoutonProposeAuSoignantAssigneDansLesStatutsDuWeb() {
        for statut in ["ASSIGNEE", "EN_COURS", "TERMINEE", "ABSENCE", "LITIGE"] {
            XCTAssertTrue(ContactMissionModel.propose(mission(statut: statut, assigne: "U-1"), userId: "u-1"), statut)
        }
        for statut in ["OUVERTE", "ANNULEE", "BROUILLON"] {
            XCTAssertFalse(ContactMissionModel.propose(mission(statut: statut, assigne: "u-1"), userId: "u-1"), statut)
        }
        XCTAssertFalse(ContactMissionModel.propose(mission(statut: "ASSIGNEE", assigne: "autre"), userId: "u-1"))
        XCTAssertFalse(ContactMissionModel.propose(mission(statut: "ASSIGNEE", assigne: nil), userId: "u-1"))
    }

    func testOuvertureDuFilOuMessageDuWeb() async throws {
        let port = Moderation()
        let (controller, snapshot) = try await session(port)
        let model = ContactMissionModel(controller: controller, snapshot: snapshot)
        let id = await model.ouvrir(mission(statut: "ASSIGNEE", assigne: SessionMessagerie.moi))
        XCTAssertEqual(id, "c-m")
        XCTAssertEqual(port.journal.appels.last, "contact m-1 e-1")

        port.contact = { .indisponible(message: "Conversation non autorisée") }
        let refus = await model.ouvrir(mission(statut: "ASSIGNEE", assigne: SessionMessagerie.moi))
        XCTAssertNil(refus)
        XCTAssertEqual(model.erreur, "Impossible d'ouvrir la conversation.", "message du web, jamais « session expirée »")
    }

    /// Monde démo : le fil d'une mission attribuée est créé à la demande et rouvert ensuite (même identifiant).
    func testDemoCreeLeFilDeLaMissionUneSeuleFois() async throws {
        let demo = DemoMessagerieGateway()
        let premier = try await demo.conversationPourMission(missionId: "demo-assignee-001", etablissementId: "demo-etab-1",
                                                             context: DemoWorld.context)
        let second = try await demo.conversationPourMission(missionId: "demo-assignee-001", etablissementId: "demo-etab-1",
                                                            context: DemoWorld.context)
        XCTAssertEqual(premier, .conversation(id: "demo-conv-mission-demo-assignee-001"))
        XCTAssertEqual(second, premier)
        let page = try await demo.conversations(avant: nil, context: DemoWorld.context)
        XCTAssertTrue(page.conversations.contains { $0.id == "demo-conv-mission-demo-assignee-001" && $0.missionId == "demo-assignee-001" })
        let nonLus = try await demo.nonLus(context: DemoWorld.context)
        XCTAssertEqual(nonLus, 2, "badge démo : deux messages non lus")
    }
}
