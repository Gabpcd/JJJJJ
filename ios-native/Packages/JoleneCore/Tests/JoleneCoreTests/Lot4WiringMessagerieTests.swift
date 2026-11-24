import XCTest
@testable import JoleneCore

/// Câblage démo de la messagerie et du Realtime (lot 4, T7a ; garde anti-oubli `Lot4Wiring<Domaine>Tests`,
/// `LOT4_PLAN.md` §2.2) et parcours du monde démo (§2.7) : trois conversations (établissement, plateforme, archivée),
/// colonnes dérivées des messages, badge, envoi relu puis réponse de l'établissement démo reçue sur le flux entrant,
/// anti-fuite sur « 06 12 34 56 78 », conversation archivée, blocage, signalement, « Écrire à l'établissement ».
final class Lot4WiringMessagerieTests: XCTestCase {
    private let context = DemoWorld.context
    private let etablissement = "demo-conv-001"
    private let interlocuteur = "demo-interlocuteur-etab-1"

    actor Recus<Valeur: Sendable> {
        private(set) var valeurs: [Valeur] = []
        func ajouter(_ valeur: Valeur) { valeurs.append(valeur) }
    }

    private func collecter<Valeur: Sendable>(_ flux: AsyncStream<Valeur>) -> (Recus<Valeur>, Task<Void, Never>) {
        let recus = Recus<Valeur>()
        return (recus, Task { for await valeur in flux { await recus.ajouter(valeur) } })
    }

    // MARK: - Câblage

    func testDemoWorldCableLaMessagerieEtLeRealtime() {
        let gateways = DemoWorld.gateways()
        XCTAssertTrue(gateways.messagerie is DemoMessagerieGateway)
        XCTAssertTrue(gateways.realtime is DemoRealtimeGateway)
        XCTAssertFalse(gateways.unwiredPorts.contains("messagerie"))
        XCTAssertFalse(gateways.unwiredPorts.contains("realtime"))
        XCTAssertTrue(VerrousLot4.abonnementRealtimePermis(gateways.realtime), "T7a : abonnement Realtime permis")
    }

    func testFixturesDemoALHorlogeFixee() throws {
        let conversations = try DemoFixtures.loadConversations()
        let messages = try DemoFixtures.loadMessages()
        XCTAssertEqual(PlanningHorlogeParis.instant(conversations.fixedNow), DemoWorld.fixedNow)
        XCTAssertEqual(PlanningHorlogeParis.instant(messages.fixedNow), DemoWorld.fixedNow)
        XCTAssertEqual(conversations.conversations.map(\.apercu.id), ["demo-conv-001", "demo-conv-002", "demo-conv-003"])
        XCTAssertEqual(conversations.conversations.map(\.missionStatut), ["OUVERTE", nil, "TERMINEE"])
        XCTAssertEqual(messages.messages.count, 6)
        XCTAssertTrue(messages.messages.allSatisfy { ($0.instant ?? .distantFuture) < DemoWorld.fixedNow }, "messages antérieurs à l'horloge démo")
        XCTAssertFalse(messages.messages.contains { DemoMessagerieGateway.contientTelephone($0.contenu) }, "aucun faux positif anti-fuite")
        XCTAssertFalse(DemoMessagerieGateway.contientTelephone(messages.reponseDemo.contenu))
    }

    // MARK: - Liste et badge

    func testListeDemoColonnesDeriveesDesMessagesEtBadge() async throws {
        let messagerie = DemoWorld.gateways().messagerie
        let page = try await messagerie.conversations(avant: nil, context: context)
        XCTAssertEqual(page.conversations.map(\.id), ["demo-conv-001", "demo-conv-002", "demo-conv-003"], "dernier message décroissant")
        XCTAssertNil(page.suivant, "page incomplète : pas de curseur")
        XCTAssertEqual(page.conversations.map(\.nonLus), [2, 0, 0])
        XCTAssertEqual(page.conversations.map(\.archivee), [false, false, true])
        XCTAssertEqual(page.conversations[0].autreId, interlocuteur)
        XCTAssertEqual(page.conversations[0].missionIntitule, "Démonstration · Soins de suite 4")
        XCTAssertEqual(page.conversations[0].ordreLe, page.conversations[0].dernierMessageLe)
        let fil = try await messagerie.messages(conversationId: etablissement, context: context)
        XCTAssertEqual(fil.map(\.id), ["demo-message-001", "demo-message-002", "demo-message-003"])
        XCTAssertEqual(page.conversations[0].dernierContenu, fil.last?.contenu, "aperçu dérivé du dernier message")
        let badge = try await messagerie.nonLus(context: context)
        XCTAssertEqual(badge, 2, "non-lus hors conversations archivées")
        let apres = try await messagerie.conversations(avant: page.conversations[0].curseur, context: context)
        XCTAssertEqual(apres.conversations.map(\.id), ["demo-conv-002", "demo-conv-003"], "curseur keyset (ordre_le, id)")
        let noms = try await messagerie.interlocuteurs(ids: page.conversations.map(\.id), context: context)
        XCTAssertEqual(noms.map(\.nomServeur), ["Établissement fictif République", "Jolene", "Établissement fictif des Lilas"])
        XCTAssertEqual(noms.map(\.estJolene), [false, true, false])
        do {
            _ = try await messagerie.interlocuteurs(ids: (0...100).map { "c-\($0)" }, context: context)
            XCTFail("plus de cent identifiants acceptés")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
        }
    }

    // MARK: - Fil : lecture, envoi, réponse entrante

    func testOuverturePuisEnvoiReluPuisReponseDemoSurLeFluxEntrant() async throws {
        let gateways = DemoWorld.gateways()
        let messagerie = gateways.messagerie
        let (recus, ecoute) = collecter(gateways.realtime.messagesEntrants(conversationId: etablissement))
        let (liste, ecouteListe) = collecter(gateways.realtime.messagesEntrants(conversationId: nil))
        let (saisies, ecouteSaisies) = collecter(gateways.realtime.saisies(conversationId: etablissement))
        defer { ecoute.cancel(); ecouteListe.cancel(); ecouteSaisies.cancel() }
        var etats = gateways.realtime.etat(conversationId: etablissement).makeAsyncIterator()
        let premierEtat = await etats.next()
        XCTAssertEqual(premierEtat, .rejoint, "canal simulé abonné sans délai")

        let lecture = try await messagerie.marquerLus(conversationId: etablissement, context: context)
        XCTAssertEqual(lecture, .lus)
        let badge = try await messagerie.nonLus(context: context)
        XCTAssertEqual(badge, 0, "ouverture → non-lus à 0")

        let issue = try await messagerie.envoyer(conversationId: etablissement, contenu: "Bonjour, voici mes disponibilités.", context: context)
        guard case let .envoye(messageId) = issue else { return XCTFail("envoi confirmé attendu, obtenu \(issue)") }
        let avantRelecture = await recus.valeurs
        XCTAssertEqual(avantRelecture, [], "aucun écho Realtime du message envoyé : la bulle vient de la relecture")
        let relu = try await messagerie.message(id: messageId, conversationId: etablissement, context: context)
        XCTAssertEqual(relu?.contenu, "Bonjour, voici mes disponibilités.")
        XCTAssertEqual(relu?.auteurId, context.userId)

        await waitUntil { await recus.valeurs.count == 1 }
        let reponse = try XCTUnwrap(await recus.valeurs.first)
        XCTAssertEqual(reponse.auteurId, interlocuteur, "réponse de l'établissement démo")
        XCTAssertEqual(reponse.contenu, try DemoFixtures.loadMessages().reponseDemo.contenu)
        XCTAssertEqual(reponse.instant, try XCTUnwrap(relu?.instant).addingTimeInterval(1), "horloge démo + 1 s")
        await waitUntil { await liste.valeurs.count == 1 } // même INSERT sur le canal de la liste
        await waitUntil { await saisies.valeurs.count == 2 }
        let indicateurs = await saisies.valeurs
        XCTAssertEqual(indicateurs, [EtatSaisie(userId: interlocuteur, enTrain: true), EtatSaisie(userId: interlocuteur, enTrain: false)])

        let apres = try await messagerie.nonLus(context: context)
        XCTAssertEqual(apres, 1, "la réponse reçue est non lue")
        _ = try await messagerie.message(id: messageId, conversationId: etablissement, context: context)
        let fil = try await messagerie.messages(conversationId: etablissement, context: context)
        XCTAssertEqual(fil.count, 5, "une seule réponse par message envoyé")
        XCTAssertEqual(fil.suffix(2).map(\.id), [messageId, reponse.id], "ordre cree_le : envoi puis réponse")
        let depuis = try await messagerie.messages(conversationId: etablissement, depuis: try XCTUnwrap(relu?.creeLe), context: context)
        XCTAssertEqual(depuis.map(\.id), [messageId, reponse.id], "relecture depuis un cree_le")
    }

    func testAntiFuiteSurUnTelephoneSaufMissionAttribuee() async throws {
        let messagerie = DemoWorld.gateways().messagerie
        let fuite = try await messagerie.envoyer(conversationId: etablissement, contenu: "Appelez-moi au 06 12 34 56 78", context: context)
        XCTAssertEqual(fuite, .antiFuite(.telephone))
        let fil = try await messagerie.messages(conversationId: etablissement, context: context)
        XCTAssertEqual(fil.count, 3, "rien n'est inséré")
        // Fil d'une mission attribuée : les coordonnées figurent au contrat, l'edge ne bloque plus.
        let ouverture = try await messagerie.conversationPourMission(missionId: "demo-presence-a", etablissementId: "demo-etab-1", context: context)
        guard case let .conversation(id) = ouverture else { return XCTFail("conversation attendue, obtenu \(ouverture)") }
        let admis = try await messagerie.envoyer(conversationId: id, contenu: "Mon numéro : 06 12 34 56 78", context: context)
        guard case .envoye = admis else { return XCTFail("envoi admis attendu, obtenu \(admis)") }
    }

    func testRefusDeLEdgeSimules() async throws {
        let messagerie = DemoWorld.gateways().messagerie
        let cas: [(String, String, String)] = [
            ("demo-conv-003", "Bonjour", CodeEnvoi.conversationArchivee),
            ("conversation-inconnue", "Bonjour", CodeEnvoi.conversationNonAutorisee),
            (etablissement, "   ", CodeEnvoi.contenuVide),
            (etablissement, String(repeating: "a", count: CodeEnvoi.longueurMax + 1), CodeEnvoi.contenuTropLong),
        ]
        for (conversation, contenu, code) in cas {
            let issue = try await messagerie.envoyer(conversationId: conversation, contenu: contenu, context: context)
            XCTAssertEqual(issue, .refuse(code: code, message: MessagerieRepli.message), code)
        }
        let limite = try await messagerie.envoyer(conversationId: etablissement, contenu: String(repeating: "a", count: CodeEnvoi.longueurMax),
                                                  context: context)
        guard case .envoye = limite else { return XCTFail("4 000 caractères admis, obtenu \(limite)") }
        let inconnue = try await messagerie.marquerLus(conversationId: "conversation-inconnue", context: context)
        XCTAssertEqual(inconnue, .accesRefuse)
    }

    // MARK: - Blocage, signalement, « Écrire à l'établissement »

    func testBloquerCoupeLEnvoiPuisDebloquer() async throws {
        let messagerie = DemoWorld.gateways().messagerie
        let initial = try await messagerie.bloque(cibleId: interlocuteur, context: context)
        XCTAssertFalse(initial)
        let bloque = try await messagerie.basculerBlocage(cibleId: interlocuteur, bloquer: true, context: context)
        XCTAssertTrue(bloque, "état relu après blocage")
        let envoi = try await messagerie.envoyer(conversationId: etablissement, contenu: "Bonjour", context: context)
        XCTAssertEqual(envoi, .refuse(code: CodeEnvoi.envoiRefuse, message: MessagerieRepli.message), "blocage : messagerie coupée")
        let debloque = try await messagerie.basculerBlocage(cibleId: interlocuteur, bloquer: false, context: context)
        XCTAssertFalse(debloque)
        do {
            _ = try await messagerie.basculerBlocage(cibleId: context.userId, bloquer: true, context: context)
            XCTFail("blocage de soi-même accepté")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.message, "Cible invalide.")
        }
    }

    func testSignalerRefusVerbatimPuisSucces() async throws {
        let gateway = try XCTUnwrap(DemoWorld.gateways().messagerie as? DemoMessagerieGateway)
        func signaler(_ cible: String, _ categorie: String, _ motif: String) async throws -> IssueSignalement {
            try await gateway.signaler(cibleId: cible, type: .etablissement, categorie: categorie, motif: motif,
                                       missionId: "demo-mission-004", context: context)
        }
        let categorie = try await signaler("demo-etab-1", "INCONNUE", "Un motif assez long")
        XCTAssertEqual(categorie, .refuse(message: "Catégorie invalide"))
        let motif = try await signaler("demo-etab-1", "AUTRE", "  court  ")
        XCTAssertEqual(motif, .refuse(message: "Motif obligatoire (10 caractères minimum)."))
        let soi = try await signaler(context.userId, "AUTRE", "Un motif assez long")
        XCTAssertEqual(soi, .refuse(message: "Vous ne pouvez pas vous signaler vous-même."))
        let succes = try await signaler("demo-etab-1", "COMPORTEMENT_INAPPROPRIE", "Un motif assez long")
        XCTAssertEqual(succes, .signale)
        let nombre = await gateway.signalements
        XCTAssertEqual(nombre, 1)
    }

    func testEcrireALEtablissementRetrouveOuCreeLeFilDeLaMission() async throws {
        let messagerie = DemoWorld.gateways().messagerie
        let existante = try await messagerie.conversationPourMission(missionId: "demo-mission-004", etablissementId: "demo-etab-1", context: context)
        XCTAssertEqual(existante, .conversation(id: etablissement), "fil de la mission retrouvé")
        let creee = try await messagerie.conversationPourMission(missionId: "demo-presence-a", etablissementId: "demo-etab-1", context: context)
        XCTAssertEqual(creee, .conversation(id: "demo-conv-mission-demo-presence-a"))
        let encore = try await messagerie.conversationPourMission(missionId: "demo-presence-a", etablissementId: "demo-etab-1", context: context)
        XCTAssertEqual(encore, creee, "get-or-create : jamais deux fils pour une mission")
        let page = try await messagerie.conversations(avant: nil, context: context)
        XCTAssertEqual(page.conversations.count, 4)
        let noms = try await messagerie.interlocuteurs(ids: ["demo-conv-mission-demo-presence-a"], context: context)
        XCTAssertEqual(noms.map(\.nomServeur), ["Établissement fictif République"])
        let refus = try await messagerie.conversationPourMission(missionId: "demo-mission-004", etablissementId: "etablissement-inconnu", context: context)
        XCTAssertEqual(refus, .indisponible(message: "Non autorisé"), "message serveur mot pour mot, jamais « session expirée »")
    }

    func testContexteEtrangerRefuse() async {
        var etranger = context
        etranger.userId = "autre"
        etranger.profile.id = "autre"
        do {
            _ = try await DemoWorld.gateways().messagerie.nonLus(context: etranger)
            XCTFail("contexte étranger accepté")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        } catch {
            XCTFail("erreur inattendue : \(error)")
        }
    }

    // MARK: - Modèles sur le monde démo

    /// Équivalent Core du parcours XCUITest de T7b : badge, ouverture du fil → non-lus à 0, envoi → bulle relue →
    /// réponse démo affichée sans geste, puis arrière-plan et retour.
    @MainActor
    func testParcoursDesModelesSurLeMondeDemo() async throws {
        let store = SessionStore(controller: SessionController(gateways: DemoWorld.gateways()))
        await store.signIn(email: "demonstration@example.invalid", password: "demonstration")
        let snapshot = try XCTUnwrap(store.state.snapshot, "session démo prête attendue, obtenu \(store.state)")
        let cycle = CycleRealtime(session: store, ecranLivre: true)
        await cycle.premierPlan()
        XCTAssertEqual(cycle.nonLus, 2, "badge = non-lus du monde démo")

        let liste = ConversationsModel(controller: store.controller, snapshot: snapshot, cycle: cycle)
        let suiviListe = Task { await liste.suivre() }
        await waitUntil { @MainActor in liste.etat == .pret }
        XCTAssertEqual(liste.actives.map(\.id), ["demo-conv-001", "demo-conv-002"])
        XCTAssertEqual(liste.archivees.map(\.id), ["demo-conv-003"])
        XCTAssertEqual(liste.conversation("demo-conv-002")?.estJolene, true)
        let apercu = try XCTUnwrap(liste.conversation(etablissement)?.apercu)

        let fil = FilModel(controller: store.controller, snapshot: snapshot, conversationId: apercu.id, autreId: apercu.autreId,
                           archivee: apercu.archivee, cycle: cycle)
        let suiviFil = Task { await fil.suivre() }
        await waitUntil { @MainActor in fil.etat == .pret }
        XCTAssertEqual(fil.messages.count, 3)
        await waitUntil { @MainActor in cycle.nonLus == 0 }
        XCTAssertEqual(liste.conversation(etablissement)?.apercu.nonLus, 0, "ouverture → non-lus à 0")
        await waitUntil { @MainActor in fil.presence?.enLigne == true }
        await waitUntil { @MainActor in fil.canal == .rejoint }

        let fuite = await fil.envoyer("06 12 34 56 78")
        XCTAssertFalse(fuite)
        XCTAssertEqual(fil.antiFuite, .telephone)
        XCTAssertEqual(fil.messages.count, 3)

        let envoye = await fil.envoyer("Bonjour, je vous confirme mon expérience.")
        XCTAssertTrue(envoye)
        await waitUntil { @MainActor in fil.messages.count == 5 } // bulle relue puis réponse démo, sans geste
        XCTAssertEqual(fil.messages.suffix(2).map(\.auteurId), [snapshot.user.id, "demo-interlocuteur-etab-1"])
        await waitUntil { @MainActor in cycle.nonLus == 0 } // réponse reçue fil ouvert : marquée lue, badge relu
        await waitUntil { @MainActor in liste.conversation("demo-conv-001")?.apercu.dernierContenu == fil.messages.last?.contenu }

        await cycle.arrierePlan()
        await suiviFil.value
        await suiviListe.value
        await cycle.premierPlan()
        XCTAssertEqual(cycle.generation, 2)
        let relance = Task { await fil.suivre() }
        await waitUntil { @MainActor in fil.canal == .rejoint }
        relance.cancel()
        await relance.value
        await store.signOut()
        await cycle.repos()
        XCTAssertNil(cycle.nonLus)
    }
}
