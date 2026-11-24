import XCTest
@testable import JoleneCore

/// Le double du lot 4 en contexte établissement (lot 5, T11) : chaque appel `etab:` est journalisé « etab … » (sans le
/// contenu des messages), puis servi par le même script que le contexte soignant.
extension MessagerieFactice {
    func conversations(avant: CurseurConversations?, etab: EtablissementReadContext) async throws -> PageConversations {
        journal.noter("etab conversations")
        return PageConversations(conversations: pagesEtab, suivant: nil)
    }

    func interlocuteurs(ids: [String], etab: EtablissementReadContext) async throws -> [Interlocuteur] {
        journal.noter("etab interlocuteurs \(ids.count)")
        return interlocuteursServis.filter { ids.contains($0.conversationId) }
    }

    func messages(conversationId: String, etab: EtablissementReadContext) async throws -> [MessageChat] {
        journal.noter("etab messages \(conversationId) \(etab.userId)")
        return fil.filter { $0.conversationId == conversationId }
    }

    func messages(conversationId: String, depuis: String, etab: EtablissementReadContext) async throws -> [MessageChat] {
        journal.noter("etab messages \(conversationId) depuis")
        return fil.filter { $0.conversationId == conversationId && FilMessages.pasAvant($0, depuis) }
    }

    func envoyer(conversationId: String, contenu: String, etab: EtablissementReadContext) async throws -> EnvoiOutcome {
        journal.noter("etab envoyer \(conversationId) \(etab.userId)")
        return try await envoi(contenu)
    }

    func message(id: String, conversationId: String, etab: EtablissementReadContext) async throws -> MessageChat? {
        journal.noter("etab message \(id)")
        return fil.first { $0.id == id && $0.conversationId == conversationId }
    }

    func marquerLus(conversationId: String, etab: EtablissementReadContext) async throws -> IssueLecture {
        journal.noter("etab marquerLus \(conversationId)")
        return try await lecture()
    }

    func saisie(debut: Bool, conversationId: String, etab: EtablissementReadContext) async throws {
        journal.noter("etab saisie \(debut ? "debut" : "fin") \(conversationId)")
    }

    func presence(etab: EtablissementReadContext) async throws { journal.noter("etab presence") }

    func nonLus(etab: EtablissementReadContext) async throws -> Int {
        journal.noter("etab nonLus")
        return nonLusSuccessifs.first ?? 0
    }

    func conversationPourSoignant(missionId: String, soignantId: String,
                                  etab: EtablissementReadContext) async throws -> IssueConversationMission {
        journal.noter("etab conversationPourSoignant \(missionId) \(soignantId)")
        return .conversation(id: "c-\(missionId)")
    }

    /// Conversations servies au contexte établissement (une page).
    var pagesEtab: [ConversationApercu] { pages.first?.conversations ?? [] }
}

/// Messagerie de l'espace établissement (lot 5, T11 ; `LOT5_PLAN.md` §3 T11). Prouvé : les modèles du lot 4 appellent
/// le port en contexte établissement (jamais le contexte soignant) ; l'auteur des messages est l'utilisateur courant,
/// jamais l'établissement ; le fil suit le canal Realtime de SA conversation ; les règles d'affichage du rôle
/// (non-lus du soignant seul, bulles de l'équipe) ; le compteur de l'Accueil est relu du serveur ; un port non câblé
/// refuse le contexte établissement.
@MainActor
final class MessagerieEtablissementTests: XCTestCase {
    private struct Panne: Error {}
    private let soignant = "s-1"

    private func pret(_ messagerie: MessagerieFactice, _ realtime: RealtimeFactice) async throws
        -> (SessionController, EtablissementSessionSnapshot) {
        var gateways = DemoWorld.gateways(espace: .etablissement(.init()))
        gateways.messagerie = messagerie
        gateways.realtime = realtime
        let controller = SessionController(gateways: gateways, espaceEtablissement: .ouvert)
        _ = await controller.start()
        let etat = await controller.signIn(email: DemoEspace.emailEtablissement, password: "demo")
        guard case let .readyEtablissement(snapshot) = etat else {
            XCTFail("espace établissement démo attendu, obtenu \(etat)")
            throw Panne()
        }
        return (controller, snapshot)
    }

    private func message(_ id: String, auteur: String, minute: Int, lu: Bool = false, admin: Bool = false) -> MessageChat {
        MessageChat(id: id, conversationId: "c-1", auteurId: auteur, contenu: "Texte \(id)",
                    creeLe: String(format: "2026-11-02T10:%02d:00.000000+00:00", minute), estAdmin: admin, lu: lu)
    }

    // MARK: - Identité de l'auteur

    func testContexteEtablissementMoiEstLUtilisateurCourantJamaisLEtablissement() async throws {
        let (_, snapshot) = try await pret(MessagerieFactice(), RealtimeFactice())
        let contexte = ContexteMessagerie(snapshot)
        XCTAssertTrue(contexte.estEtablissement)
        XCTAssertEqual(contexte.moi, snapshot.user.id)
        XCTAssertEqual(contexte.moi, snapshot.context.userId)
        XCTAssertNotEqual(contexte.moi, snapshot.context.etablissementId, "l'auteur est l'utilisateur, le serveur compare à l'établissement")
    }

    func testFilEnContexteEtablissementSuitSaConversationEtEnvoieSousLUtilisateur() async throws {
        let journal = JournalAppels()
        let messagerie = MessagerieFactice(journal: journal)
        let realtime = RealtimeFactice(journal: journal)
        let (controller, snapshot) = try await pret(messagerie, realtime)
        let moi = snapshot.user.id
        messagerie.fil = [message("m-1", auteur: soignant, minute: 0)]
        messagerie.envoi = { _ in .envoye(messageId: "m-2") }
        let fil = FilModel(controller: controller, contexte: ContexteMessagerie(snapshot), conversationId: "c-1", autreId: soignant)
        let suivi = Task { await fil.suivre() }
        defer { suivi.cancel() }
        await waitUntil({ @MainActor in fil.etat == .pret })
        await waitUntil({ journal.nombre("etab marquerLus c-1") >= 1 })
        XCTAssertEqual(fil.moi, moi)
        XCTAssertNotNil(journal.index("flux messages c-1"), "canal Realtime filtré par la conversation du fil")
        XCTAssertNil(journal.index("flux messages liste"), "le fil n'écoute jamais le canal de la liste")
        XCTAssertNotNil(journal.index("etab messages c-1 \(moi)"))
        XCTAssertEqual(journal.appels.filter { $0.hasPrefix("messages ") || $0.hasPrefix("marquerLus ") }, [],
                       "aucun appel en contexte soignant depuis l'espace établissement")

        // Envoi : edge sous l'utilisateur courant, puis relecture de la ligne par id ; « envoyé » seulement relu.
        messagerie.fil += [message("m-2", auteur: moi, minute: 5)]
        let confirme = await fil.envoyer("Bonjour")
        XCTAssertTrue(confirme)
        XCTAssertNotNil(journal.index("etab envoyer c-1 \(moi)"))
        XCTAssertNotNil(journal.index("etab message m-2"))
        XCTAssertEqual(fil.messages.map(\.id), ["m-1", "m-2"])
        XCTAssertEqual(MessageriePresentation.natureEtablissement(fil.messages[1], moi: moi, soignantId: soignant), .moi)
    }

    func testEnvoiNonConfirmeEnContexteEtablissementAucunRenvoi() async throws {
        let journal = JournalAppels()
        let messagerie = MessagerieFactice(journal: journal)
        let (controller, snapshot) = try await pret(messagerie, RealtimeFactice(journal: journal))
        messagerie.fil = [message("m-1", auteur: soignant, minute: 0)]
        let fil = FilModel(controller: controller, contexte: ContexteMessagerie(snapshot), conversationId: "c-1", autreId: soignant)
        let suivi = Task { await fil.suivre() }
        defer { suivi.cancel() }
        await waitUntil({ @MainActor in fil.etat == .pret })
        let confirme = await fil.envoyer("Bonjour")
        XCTAssertFalse(confirme)
        XCTAssertTrue(fil.envoiNonConfirme, "issue inconnue affichée comme telle")
        XCTAssertEqual(journal.nombre("etab envoyer"), 1, "aucun renvoi automatique")
    }

    // MARK: - Liste et règles du rôle

    func testListeEtablissementNonLusDuSoignantSeul() async throws {
        let journal = JournalAppels()
        let messagerie = MessagerieFactice(journal: journal)
        let realtime = RealtimeFactice(journal: journal)
        let (controller, snapshot) = try await pret(messagerie, realtime)
        let apercu = ConversationApercu(id: "c-1", autreId: soignant, missionId: "m", etablissementId: snapshot.context.etablissementId,
                                        nonLus: 0, participant1Id: soignant, participant2Id: "contact-etab", soignantId: soignant,
                                        dernierMessageLe: "2026-11-02T09:00:00.000000+00:00", ordreLe: "2026-11-02T09:00:00.000000+00:00")
        messagerie.pages = [PageConversations(conversations: [apercu], suivant: nil)]
        let liste = ConversationsModel(controller: controller, contexte: ContexteMessagerie(snapshot))
        let suivi = Task { await liste.suivre() }
        defer { suivi.cancel() }
        await waitUntil({ @MainActor in liste.etat == .pret })
        XCTAssertNotNil(journal.index("etab conversations"))
        XCTAssertNil(journal.index("conversations debut"), "jamais la liste du contexte soignant")
        realtime.emettre(message("m-2", auteur: "collegue", minute: 10))
        realtime.emettre(message("m-3", auteur: snapshot.user.id, minute: 11))
        realtime.emettre(message("m-4", auteur: soignant, minute: 12))
        await waitUntil({ @MainActor in liste.conversations.first?.apercu.dernierContenu == "Texte m-4" })
        XCTAssertEqual(liste.conversations.first?.apercu.nonLus, 1,
                       "côté établissement, seul le message du soignant est un non-lu (web l.305-307)")
    }

    func testReglesDAffichageDuRoleEtablissement() {
        let moi = "membre-1"
        let soignantMsg = message("a", auteur: soignant, minute: 0)
        let collegue = message("b", auteur: "membre-2", minute: 1)
        let mien = message("c", auteur: moi, minute: 2)
        let admin = message("d", auteur: "admin-1", minute: 3, admin: true)
        XCTAssertEqual(MessageriePresentation.natureEtablissement(soignantMsg, moi: moi, soignantId: soignant), .interlocuteur)
        XCTAssertEqual(MessageriePresentation.natureEtablissement(collegue, moi: moi, soignantId: soignant), .moi)
        XCTAssertEqual(MessageriePresentation.natureEtablissement(mien, moi: moi, soignantId: soignant), .moi)
        XCTAssertEqual(MessageriePresentation.natureEtablissement(admin, moi: moi, soignantId: soignant), .jolene)
        XCTAssertTrue(MessageriePresentation.messageEquipe(collegue, moi: moi, soignantId: soignant), "« Équipe établissement »")
        XCTAssertFalse(MessageriePresentation.messageEquipe(mien, moi: moi, soignantId: soignant))
        XCTAssertFalse(MessageriePresentation.messageEquipe(soignantMsg, moi: moi, soignantId: soignant))
        // Sans soignant (conversation plateforme) : règle commune, auteur comparé à l'utilisateur courant.
        XCTAssertEqual(MessageriePresentation.natureEtablissement(collegue, moi: moi, soignantId: nil), .interlocuteur)
        XCTAssertEqual(MessagerieTextes.equipeEtablissement, "Équipe établissement")

        let conversation = ConversationAffichee(apercu: ConversationApercu(id: "c-1", autreId: soignant, missionId: "m",
                                                                           etablissementId: "e-1", soignantId: soignant),
                                                interlocuteur: Interlocuteur(conversationId: "c-1", participantId: soignant,
                                                                             prenom: "Camille", nom: "Démo"))
        let etab = ModerationConversation.pour(conversation, etablissement: true)
        XCTAssertEqual(etab.blocage, soignant)
        XCTAssertEqual(etab.libelleCible, MessagerieTextes.Blocage.cibleUtilisateur, "web : libellé par défaut hors rôle SOIGNANT")
        XCTAssertEqual(etab.signalement, .init(cibleId: soignant, type: .soignant, missionId: nil))
        let cote = ModerationConversation.pour(conversation)
        XCTAssertEqual(cote.libelleCible, MessagerieTextes.Blocage.cibleEtablissement, "côté soignant inchangé")
        XCTAssertEqual(cote.signalement?.type, .etablissement)
    }

    // MARK: - « Contacter le soignant »

    func testContacterLeSoignantRendLaConversationDeLaMission() async throws {
        let journal = JournalAppels()
        let (controller, snapshot) = try await pret(MessagerieFactice(journal: journal), RealtimeFactice(journal: journal))
        let contact = ContactSoignantModel(controller: controller, snapshot: snapshot)
        let id = await contact.ouvrir(missionId: "m-4", soignantId: soignant)
        XCTAssertEqual(id, "c-m-4")
        XCTAssertNil(contact.erreur)
        XCTAssertEqual(journal.appels, ["etab conversationPourSoignant m-4 \(soignant)"])
    }

    func testLienDuDetailOuvreLaConversationNative() {
        XCTAssertTrue(EtabDestination.conversation(id: "c").ecranLivre, "T11 livrée")
        let mission = EtabMissionResume(id: "m-4", intitule: "Nuit", statut: "ASSIGNEE", soignantAssigneId: soignant)
        let detail = EtabMissionDetail(mission: mission, creneaux: [], soignantAssigneId: soignant)
        let lecture = EtabMissionsPresentation.liens(detail, permissions: PermissionsEtab(accordees: [.lecture]))
        let lien = try? XCTUnwrap(lecture.first { $0.cle == .message })
        XCTAssertEqual(lien?.titre, "Contacter le soignant")
        XCTAssertEqual(lien?.cible, .contactSoignant(missionId: "m-4", soignantId: soignant))
        XCTAssertEqual(lien?.identifiant, "etab-mission-lien-message")
        XCTAssertTrue(EtabMissionsPresentation.liens(detail, permissions: PermissionsEtab(accordees: [])).filter { $0.cle == .message }.isEmpty,
                      "sans `lecture` : aucun lien de message")
    }

    // MARK: - Compteur de l'Accueil et monde démo

    func testCompteurDeLAccueilRelutLesNonLusDeLaMessagerieDemo() async throws {
        let gateways = DemoWorld.gateways(espace: .etablissement(.init()))
        let controller = SessionController(gateways: gateways, espaceEtablissement: .ouvert)
        _ = await controller.start()
        guard case let .readyEtablissement(snapshot) = await controller.signIn(email: DemoEspace.emailEtablissement, password: "demo") else {
            return XCTFail("espace établissement démo attendu")
        }
        let etab = snapshot.context
        let messagerie = gateways.messagerie
        let avant = try await gateways.etablissement.dashboard.tableauDeBord(context: etab).stats.messagesNonLus
        let servis = try await messagerie.nonLus(etab: etab)
        XCTAssertEqual(avant, servis)
        XCTAssertEqual(avant, try DemoFixtures.loadEtabDashboard().stats.messagesNonLus, "fixtures cohérentes")
        let page = try await messagerie.conversations(avant: nil, etab: etab)
        XCTAssertEqual(page.conversations.map(\.id), ["demo-etab-conv-001", "demo-etab-conv-002"])
        XCTAssertEqual(page.conversations.first?.nonLus, 2, "deux messages du soignant ; celui du collègue n'en est pas un")
        let lecture = try await messagerie.marquerLus(conversationId: "demo-etab-conv-001", etab: etab)
        XCTAssertEqual(lecture, .lus)
        let apres = try await gateways.etablissement.dashboard.tableauDeBord(context: etab).stats.messagesNonLus
        XCTAssertEqual(apres, 0, "compteur relu (état serveur simulé), jamais recalculé par l'écran")
        // Envoi démo : auteur = utilisateur de la session ; conversation archivée refusée.
        let issue = try await messagerie.envoyer(conversationId: "demo-etab-conv-001", contenu: "Bonjour", etab: etab)
        guard case let .envoye(id) = issue else { return XCTFail("envoi démo attendu, obtenu \(issue)") }
        let relu = try await messagerie.message(id: id, conversationId: "demo-etab-conv-001", etab: etab)
        XCTAssertEqual(relu?.auteurId, snapshot.user.id)
        let archivee = try await messagerie.envoyer(conversationId: "demo-etab-conv-002", contenu: "Bonjour", etab: etab)
        XCTAssertEqual(archivee, .refuse(code: CodeEnvoi.conversationArchivee, message: MessagerieRepli.message))
        // « Contacter le soignant » : fil existant de la mission M4 ; mission sans ce soignant → refus.
        let existante = try await messagerie.conversationPourSoignant(missionId: "demo-etab-m04", soignantId: "demo-soignant", etab: etab)
        XCTAssertEqual(existante, .conversation(id: "demo-etab-conv-001"))
        let autre = try await messagerie.conversationPourSoignant(missionId: "demo-etab-m04", soignantId: "demo-soignant-etab-2", etab: etab)
        XCTAssertEqual(autre, .indisponible(message: DemoMessagerieGateway.conversationNonAutorisee))
        // Le compte soignant démo ne lit jamais la messagerie de l'établissement, et inversement.
        let soignantContexte = DemoWorld.context
        let refus = try? await messagerie.conversations(avant: nil, context: soignantContexte)
        XCTAssertFalse(refus?.conversations.contains { $0.id.hasPrefix("demo-etab-conv") } ?? false)
    }

    func testPortNonCableRefuseLeContexteEtablissement() async {
        let etab = EtablissementReadContext(userId: "u", etablissementId: "e", roleEtab: .rh,
                                            permissions: PermissionsEtab(accordees: [.lecture]), epoch: 1)
        do {
            _ = try await UnwiredMessageriePort().conversations(avant: nil, etab: etab)
            XCTFail("un port non câblé ne rend jamais une liste plausible")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
            XCTAssertTrue(erreur.message.contains("T11"))
        } catch {
            XCTFail("\(error)")
        }
    }
}
