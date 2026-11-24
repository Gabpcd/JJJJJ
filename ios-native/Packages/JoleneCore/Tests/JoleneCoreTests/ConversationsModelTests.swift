import XCTest
@testable import JoleneCore

/// Liste des conversations (lot 4, T7a ; `LOT4_PLAN.md` §2.4-§2.5, port de `PageMessagerie.tsx` l.156-290). Règles
/// prouvées : pagination keyset par pages de 100, dédoublonnage, arrêt sans curseur, sur curseur inchangé et à cent
/// pages ; interlocuteurs par lots de 100 ; onglets actives / archivées dérivés de `archived_at` ; INSERT reçu → aperçu
/// mis à jour, conversation inconnue → liste relue ; « rejoint » après coupure → liste relue ; fil lu → non-lus à 0.
@MainActor
final class ConversationsModelTests: XCTestCase {
    private func conversation(_ numero: Int, archivee: Bool = false, nonLus: Int = 0) -> ConversationApercu {
        let id = String(format: "c-%03d", numero)
        let ordre = String(format: "2026-11-01T%02d:%02d:00.000000+00:00", 23 - numero / 60, 59 - numero % 60)
        return ConversationApercu(id: id, autreId: "etab-\(numero)", missionId: "m-\(numero)", etablissementId: "e-\(numero)",
                                  dernierContenu: "Aperçu \(numero)", nonLus: nonLus,
                                  archivedAt: archivee ? "2026-10-01T00:00:00+00:00" : nil, soignantId: SessionMessagerie.moi,
                                  dernierMessageLe: ordre, creeLe: "2026-10-01T00:00:00+00:00", missionIntitule: "Mission \(numero)",
                                  ordreLe: ordre)
    }

    private struct Banc {
        let model: ConversationsModel
        let messagerie: MessagerieFactice
        let realtime: RealtimeFactice
        let journal: JournalAppels
        let store: SessionStore
        let cycle: CycleRealtime
    }

    private func banc(_ pages: [PageConversations], preparer: (MessagerieFactice) -> Void = { _ in }) async throws -> Banc {
        let journal = JournalAppels()
        let messagerie = MessagerieFactice(journal: journal)
        let realtime = RealtimeFactice(journal: journal)
        messagerie.pages = pages
        preparer(messagerie)
        let store = SessionStore(controller: SessionController(gateways: SessionMessagerie.gateways(messagerie: messagerie, realtime: realtime)))
        await store.start()
        let snapshot = try XCTUnwrap(store.state.snapshot)
        let cycle = CycleRealtime(session: store, ecranLivre: true)
        await cycle.premierPlan()
        let model = ConversationsModel(controller: store.controller, snapshot: snapshot, cycle: cycle)
        return Banc(model: model, messagerie: messagerie, realtime: realtime, journal: journal, store: store, cycle: cycle)
    }

    private func pause(_ secondes: TimeInterval = 0.06) async {
        try? await Task.sleep(nanoseconds: UInt64(secondes * 1_000_000_000))
    }

    // MARK: - Pagination keyset

    func testPaginationKeysetDedoublonneEtSArreteSansCurseur() async throws {
        let premiere = (1...100).map { conversation($0) }
        let seconde = [conversation(100)] + (101...129).map { conversation($0) } // la dernière de la page 1 est resservie
        let curseur = try XCTUnwrap(premiere.last?.curseur)
        let b = try await banc([PageConversations(conversations: premiere, suivant: curseur),
                                PageConversations(conversations: seconde, suivant: nil)]) { messagerie in
            messagerie.interlocuteursServis = [
                Interlocuteur(conversationId: "c-001", participantId: "etab-1", prenom: "Clinique fictive", nom: nil,
                              avatarUrl: "https://exemple.invalid/logo.png"),
            ]
        }
        await b.model.charger()
        XCTAssertEqual(b.model.etat, .pret)
        XCTAssertEqual(b.model.conversations.count, 129, "dédoublonnage par id entre deux pages")
        XCTAssertEqual(b.model.conversations.map(\.id).prefix(2), ["c-001", "c-002"], "ordre serveur conservé")
        XCTAssertEqual(b.journal.appels.filter { $0.hasPrefix("conversations") },
                       ["conversations debut", "conversations \(curseur.ordreLe)|\(curseur.id)"],
                       "curseur = (ordre_le, id) de la dernière ligne ; arrêt sans curseur suivant")
        XCTAssertEqual(b.journal.appels.filter { $0.hasPrefix("interlocuteurs") }, ["interlocuteurs 100", "interlocuteurs 29"],
                       "cent identifiants au plus par appel")
        let premiereAffichee = try XCTUnwrap(b.model.conversation("c-001"))
        XCTAssertEqual(premiereAffichee.interlocuteur?.nomServeur, "Clinique fictive")
        XCTAssertFalse(premiereAffichee.estJolene)
        XCTAssertEqual(premiereAffichee.avatarUrl, "https://exemple.invalid/logo.png")
        let sansLigne = try XCTUnwrap(b.model.conversation("c-002"))
        XCTAssertTrue(sansLigne.estJolene, "sans ligne d'interlocuteur : conversation de la plateforme, comme le web")
        XCTAssertNil(sansLigne.avatarUrl)
    }

    func testCurseurInchangeArreteLaPagination() async throws {
        let fige = CurseurConversations(ordreLe: "2026-11-01T10:00:00+00:00", id: "c-001")
        let ligne = conversation(1)
        let b = try await banc([]) { messagerie in
            messagerie.servirPage = { _ in PageConversations(conversations: [ligne], suivant: fige) }
        }
        await b.model.charger()
        XCTAssertEqual(b.journal.nombre("conversations"), 2, "curseur rendu = curseur envoyé : arrêt")
        XCTAssertEqual(b.model.conversations.count, 1)
    }

    func testCentPagesAuPlus() async throws {
        let compteur = JournalAppels()
        let b = try await banc([]) { messagerie in
            messagerie.servirPage = { _ in
                compteur.noter("page")
                let numero = compteur.nombre("page")
                let id = "c-\(numero)"
                let ordre = "2026-11-01T00:00:00.\(String(format: "%06d", 999_999 - numero))+00:00"
                return PageConversations(conversations: [ConversationApercu(id: id, ordreLe: ordre)],
                                         suivant: CurseurConversations(ordreLe: ordre, id: id))
            }
        }
        await b.model.charger()
        XCTAssertEqual(b.journal.nombre("conversations"), PageConversations.pagesMax)
        XCTAssertEqual(b.model.conversations.count, 100)
    }

    // MARK: - Onglets et erreurs

    func testActivesEtArchiveesDeriveesDeArchivedAt() async throws {
        let b = try await banc([PageConversations(conversations: [conversation(1, nonLus: 2), conversation(2, archivee: true), conversation(3)],
                                                  suivant: nil)])
        await b.model.charger()
        XCTAssertEqual(b.model.actives.map(\.id), ["c-001", "c-003"])
        XCTAssertEqual(b.model.archivees.map(\.id), ["c-002"])
        XCTAssertEqual(b.model.conversation("c-001")?.apercu.nonLus, 2)
        XCTAssertEqual(b.model.conversation("c-001")?.apercu.missionIntitule, "Mission 1")
    }

    func testEchecDeLaPremiereLecturePuisRelectureEtSessionExpiree() async throws {
        let reseau = JoleneError(.network, "Connexion impossible. Vérifiez votre réseau puis réessayez.")
        let b = try await banc([PageConversations(conversations: [conversation(1)], suivant: nil)]) { messagerie in
            messagerie.avantPage = { throw reseau }
        }
        await b.model.charger()
        XCTAssertEqual(b.model.etat, .echec(reseau.message))
        XCTAssertTrue(b.model.conversations.isEmpty, "aucune liste vide plausible : l'état est un échec")
        b.messagerie.avantPage = {}
        await b.model.charger()
        XCTAssertEqual(b.model.etat, .pret)
        XCTAssertEqual(b.model.conversations.count, 1)
        // Relecture en échec sur une liste déjà affichée : la liste reste, le message est exposé.
        b.messagerie.avantPage = { throw JoleneError(.unauthorized, SessionController.sessionExpiredMessage) }
        await b.model.charger()
        XCTAssertEqual(b.model.etat, .pret)
        XCTAssertEqual(b.model.conversations.count, 1)
        XCTAssertEqual(b.model.message, SessionController.sessionExpiredMessage)
        XCTAssertTrue(b.model.sessionExpiree)
    }

    func testInterlocuteursRefusesLaListeResteSansNoms() async throws {
        let b = try await banc([PageConversations(conversations: [conversation(1)], suivant: nil)]) { messagerie in
            messagerie.avantInterlocuteurs = { throw JoleneError(.unknown, "Compte inactif") }
        }
        await b.model.charger()
        XCTAssertEqual(b.model.etat, .pret, "refus métier des interlocuteurs : la liste reste, sans noms")
        XCTAssertEqual(b.model.conversations.count, 1)
        XCTAssertNil(b.model.conversations.first?.interlocuteur)
        XCTAssertEqual(b.model.message, "Compte inactif", "message serveur mot pour mot")
        XCTAssertFalse(b.model.sessionExpiree)
    }

    // MARK: - Realtime

    func testInsertRecuMetAJourLApercuEtConversationInconnueRelitLaListe() async throws {
        let b = try await banc([PageConversations(conversations: [conversation(1), conversation(2)], suivant: nil)])
        let suivi = Task { await b.model.suivre() }
        defer { suivi.cancel() }
        await waitUntil { @MainActor in b.model.etat == .pret }
        await waitUntil { b.realtime.lecteurs(nil) >= 2 } // le cycle (badge) et la liste écoutent le même canal
        let entrant = SessionMessagerie.message("m-1", conversation: "c-002", auteur: "etab-2", contenu: "Nouveau message",
                                                creeLe: "2026-11-02T08:00:00+00:00")
        b.realtime.emettre(entrant)
        await waitUntil { @MainActor in b.model.conversations.first?.id == "c-002" }
        XCTAssertEqual(b.model.conversation("c-002")?.apercu.dernierContenu, "Nouveau message")
        XCTAssertEqual(b.model.conversation("c-002")?.apercu.nonLus, 1)
        b.realtime.emettre(entrant) // même INSERT reçu deux fois
        await pause()
        XCTAssertEqual(b.model.conversation("c-002")?.apercu.nonLus, 1, "un INSERT déjà appliqué n'est pas recompté")
        XCTAssertEqual(b.journal.nombre("conversations debut"), 1)
        b.messagerie.pages = [PageConversations(conversations: [conversation(3), conversation(1), conversation(2)], suivant: nil)]
        b.realtime.emettre(SessionMessagerie.message("m-2", conversation: "c-003", auteur: "etab-3"))
        await waitUntil { @MainActor in b.model.conversations.count == 3 }
        XCTAssertEqual(b.journal.nombre("conversations debut"), 2, "conversation inconnue : liste relue, aucun abonnement conversations")
    }

    func testFilOuvertPasDeNonLuEtFilLuRemisAZero() async throws {
        let b = try await banc([PageConversations(conversations: [conversation(1, nonLus: 3), conversation(2)], suivant: nil)])
        let suivi = Task { await b.model.suivre() }
        defer { suivi.cancel() }
        await waitUntil { @MainActor in b.model.etat == .pret }
        await waitUntil { b.realtime.lecteurs(nil) >= 2 }
        b.cycle.ouvrirFil("c-002")
        b.realtime.emettre(SessionMessagerie.message("m-1", conversation: "c-002", auteur: "etab-2", creeLe: "2026-11-02T08:00:00+00:00"))
        await waitUntil { @MainActor in b.model.conversations.first?.id == "c-002" }
        XCTAssertEqual(b.model.conversation("c-002")?.apercu.nonLus, 0, "fil ouvert : pas de non-lu")
        await b.cycle.conversationLue("c-001")
        XCTAssertEqual(b.model.conversation("c-001")?.apercu.nonLus, 0, "fil marqué lu : non-lus de la conversation à 0")
    }

    func testRejointApresCoupureRelitLaListe() async throws {
        let b = try await banc([PageConversations(conversations: [conversation(1)], suivant: nil)])
        let suivi = Task { await b.model.suivre() }
        defer { suivi.cancel() }
        await waitUntil { @MainActor in b.model.etat == .pret }
        await waitUntil { b.realtime.lecteurs(nil) >= 2 }
        await pause()
        XCTAssertEqual(b.journal.nombre("conversations debut"), 1, "premier abonnement : pas de seconde lecture")
        b.realtime.etatCanal(.coupe, conversationId: nil)
        b.messagerie.pages = [PageConversations(conversations: [conversation(2), conversation(1)], suivant: nil)]
        b.realtime.etatCanal(.rejoint, conversationId: nil)
        await waitUntil { @MainActor in b.model.conversations.count == 2 }
        XCTAssertEqual(b.journal.nombre("conversations debut"), 2)
    }

    func testArrierePlanTermineLeSuiviEtEpochPerimeIgnore() async throws {
        let barriere = Gate()
        let b = try await banc([PageConversations(conversations: [conversation(1)], suivant: nil)])
        let suivi = Task { await b.model.suivre() }
        await waitUntil { @MainActor in b.model.etat == .pret }
        await waitUntil { b.realtime.lecteurs(nil) >= 2 }
        await b.cycle.arrierePlan()
        await suivi.value // flux fermés : le suivi se termine, l'écran le relance au retour (`generation`)
        b.messagerie.avantPage = { await barriere.wait() }
        b.messagerie.pages = [PageConversations(conversations: [conversation(1), conversation(2)], suivant: nil)]
        let lecture = Task { await b.model.charger() }
        await waitUntil { b.journal.nombre("conversations debut") == 2 }
        await b.store.signOut()
        await barriere.open()
        await lecture.value
        XCTAssertEqual(b.model.conversations.count, 1, "réponse d'un epoch périmé ignorée")
    }
}
