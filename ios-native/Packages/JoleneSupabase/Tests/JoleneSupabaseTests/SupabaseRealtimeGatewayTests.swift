import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Canal Realtime de la messagerie (lot 4, T7a ; fiche « Realtime : tables, RLS, filtres, cycle de vie ») sur un
/// transport simulé : sujets et filtres du web, flux déclarés avant l'abonnement, canal partagé entre lecteurs, état
/// par canal, coupure puis rejoint par le SDK, canal fermé par le serveur → nouveau canal, abonnement en échec repris,
/// dernier lecteur parti → canal retiré, `fermerTout()` → tout retiré et flux terminés. Le SDK réel
/// (`TransportRealtimeSDK`) n'est pas exercé ici : aucun serveur Realtime n'est joint par ces tests.
final class SupabaseRealtimeGatewayTests: XCTestCase {
    private let conversation = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let autre = "9d8c7b6a-5f4e-4d3c-8b2a-1f0e9d8c7b6a"
    private let moi = "0b4d2b8e-4a9f-4b1c-9e0a-7f3c1d2e5a66"

    // MARK: - Transport simulé

    final class Journal: @unchecked Sendable {
        private let verrou = NSLock()
        private var entrees: [String] = []
        func noter(_ entree: String) { verrou.withLock { entrees.append(entree) } }
        var appels: [String] { verrou.withLock { entrees } }
        func nombre(_ prefixe: String) -> Int { appels.filter { $0.hasPrefix(prefixe) }.count }
    }

    final class CanalFactice: CanalRealtime, @unchecked Sendable {
        let sujet: String
        let numero: Int
        private let journal: Journal
        private let echec: Bool
        private let verrou = NSLock()
        private var flux: [String: DiffusionEvenements<ChangementRealtime>] = [:]
        private let etats = DiffusionEtat<StatutCanalRealtime>()

        init(sujet: String, numero: Int, journal: Journal, echec: Bool) {
            self.sujet = sujet; self.numero = numero; self.journal = journal; self.echec = echec
            etats.recevoir(.desabonne)
        }

        func declarer(_ flux: FluxRealtime) -> AsyncStream<ChangementRealtime> {
            let filtre = flux.colonne.map { "\($0)=eq.\(flux.valeur ?? "")" } ?? "sans filtre"
            journal.noter("declarer \(sujet) \(flux.table) \(flux.evenements.rawValue) \(filtre)")
            return verrou.withLock {
                let diffusion = self.flux[flux.table] ?? DiffusionEvenements()
                self.flux[flux.table] = diffusion
                return diffusion
            }.flux()
        }

        func abonner() async throws {
            journal.noter("abonner \(sujet)")
            if echec {
                journal.noter("echec \(sujet)")
                throw URLError(.timedOut)
            }
            etats.recevoir(.abonnement)
            etats.recevoir(.abonne)
        }

        var statut: StatutCanalRealtime { etats.lire() ?? .desabonne }

        func statuts() -> AsyncStream<StatutCanalRealtime> { etats.flux() }

        // Commandes du test
        func emettre(_ changement: ChangementRealtime, table: String) { verrou.withLock { flux[table] }?.emettre(changement) }
        func passer(_ statut: StatutCanalRealtime) { etats.recevoir(statut) }
        func terminer() {
            verrou.withLock { Array(flux.values) }.forEach { $0.terminer() }
            etats.recevoir(.desabonne)
        }
    }

    final class TransportFactice: TransportRealtime, @unchecked Sendable {
        let journal = Journal()
        private let verrou = NSLock()
        private var crees: [CanalFactice] = []
        private var enregistres: Set<ObjectIdentifier> = []
        private var echecsRestants = 0
        private var uid: String?
        private var lignes: [String: JSONObject] = [:]

        init(utilisateur: String?) { uid = utilisateur }

        var canaux: [CanalFactice] { verrou.withLock { crees } }
        func canaux(_ sujet: String) -> [CanalFactice] { canaux.filter { $0.sujet == sujet } }
        func echouer(_ nombre: Int) { verrou.withLock { echecsRestants = nombre } }
        func servir(_ ligne: JSONObject, table: String, valeur: String) { verrou.withLock { lignes["\(table):\(valeur)"] = ligne } }
        /// `phx_close` : le client ne connaît plus le canal, qui ne rejoindra jamais.
        func fermerParLeServeur(_ canal: CanalFactice) {
            _ = verrou.withLock { enregistres.remove(ObjectIdentifier(canal)) }
            canal.passer(.desabonne)
        }

        func utilisateur() -> String? { verrou.withLock { uid } }

        func canal(_ sujet: String) -> any CanalRealtime {
            verrou.withLock {
                let echec = echecsRestants > 0
                if echec { echecsRestants -= 1 }
                let canal = CanalFactice(sujet: sujet, numero: crees.count + 1, journal: journal, echec: echec)
                journal.noter("canal \(sujet)")
                crees.append(canal)
                enregistres.insert(ObjectIdentifier(canal))
                return canal
            }
        }

        func estEnregistre(_ canal: any CanalRealtime) -> Bool {
            verrou.withLock { enregistres.contains(ObjectIdentifier(canal)) }
        }

        func retirer(_ canal: any CanalRealtime) async {
            guard let factice = canal as? CanalFactice else { return }
            journal.noter("retirer \(factice.sujet)")
            _ = verrou.withLock { enregistres.remove(ObjectIdentifier(factice)) }
            factice.terminer()
        }

        func retirerTout() async {
            journal.noter("retirerTout")
            let tous = verrou.withLock { () -> [CanalFactice] in
                let actifs = crees.filter { enregistres.contains(ObjectIdentifier($0)) }
                enregistres = []
                return actifs
            }
            tous.forEach { $0.terminer() }
        }

        func ligne(table: String, colonnes: String, colonne: String, valeur: String) async -> JSONObject? {
            journal.noter("ligne \(table) \(colonnes) \(colonne)=eq.\(valeur)")
            return verrou.withLock { lignes["\(table):\(valeur)"] }
        }
    }

    actor Recus<Valeur: Sendable> {
        private(set) var valeurs: [Valeur] = []
        private(set) var termine = false
        func ajouter(_ valeur: Valeur) { valeurs.append(valeur) }
        func finir() { termine = true }
    }

    private func collecter<Valeur: Sendable>(_ flux: AsyncStream<Valeur>) -> (Recus<Valeur>, Task<Void, Never>) {
        let recus = Recus<Valeur>()
        return (recus, Task {
            for await valeur in flux { await recus.ajouter(valeur) }
            await recus.finir()
        })
    }

    private func attendre(_ condition: @Sendable () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<400 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("condition non atteinte dans le délai", file: file, line: line)
    }

    private func banc(utilisateur: String? = "0b4d2b8e-4a9f-4b1c-9e0a-7f3c1d2e5a66",
                      reglages: SupabaseRealtimeGateway.Reglages = .init(surveillance: 0.02, sansRejoint: 0.2, reprises: [0.01])) -> (SupabaseRealtimeGateway, TransportFactice) {
        let transport = TransportFactice(utilisateur: utilisateur)
        return (SupabaseRealtimeGateway(transport: transport, reglages: reglages), transport)
    }

    private func ligneMessage(_ id: String, conversation: String? = nil) -> JSONObject {
        ["id": .string(id), "conversation_id": .string(conversation ?? self.conversation), "auteur_id": .string(autre),
         "contenu": .string("Bonjour"), "lu": .bool(false), "est_admin": .bool(false), "cree_le": .string("2026-11-02T10:00:00+00:00")]
    }

    // MARK: - Sujets, filtres, ordre

    func testCanalDuFilFluxDeclareAvantLAbonnement() async throws {
        let (passerelle, transport) = banc()
        let sujet = "chat-conv-\(conversation)"
        let (recus, ecoute) = collecter(passerelle.messagesEntrants(conversationId: conversation))
        defer { ecoute.cancel() }
        let (etats, suivi) = collecter(passerelle.etat(conversationId: conversation))
        defer { suivi.cancel() }
        await attendre { await etats.valeurs.last == .rejoint }
        XCTAssertEqual(transport.journal.appels, [
            "canal \(sujet)",
            "declarer \(sujet) messages_chat insertions conversation_id=eq.\(conversation)",
            "abonner \(sujet)",
        ], "canal créé → flux déclaré → abonnement (exigence du SDK)")
        let ordre = await etats.valeurs
        XCTAssertEqual(ordre.suffix(2), [.connexion, .rejoint])

        let canal = try XCTUnwrap(transport.canaux(sujet).first)
        canal.emettre(.insertion(ligneMessage("m-1")), table: "messages_chat")
        canal.emettre(.insertion(["id": .string("illisible")]), table: "messages_chat")
        canal.emettre(.miseAJour(ligneMessage("m-2")), table: "messages_chat")
        canal.emettre(.insertion(ligneMessage("m-3")), table: "messages_chat")
        await attendre { await recus.valeurs.count == 2 }
        let messages = await recus.valeurs
        XCTAssertEqual(messages.map(\.id), ["m-1", "m-3"], "INSERT seulement ; ligne illisible ignorée, jamais complétée")
        XCTAssertEqual(messages.first?.auteurId, autre)
    }

    func testCanalDeLaListeSansFiltrePartageEntreDeuxLecteurs() async throws {
        let (passerelle, transport) = banc()
        let sujet = "messagerie-liste-\(moi)"
        let (badge, ecouteBadge) = collecter(passerelle.messagesEntrants(conversationId: nil))
        let (liste, ecouteListe) = collecter(passerelle.messagesEntrants(conversationId: nil))
        defer { ecouteBadge.cancel(); ecouteListe.cancel() }
        let (etats, suivi) = collecter(passerelle.etat(conversationId: nil))
        defer { suivi.cancel() }
        await attendre { await etats.valeurs.last == .rejoint }
        XCTAssertEqual(transport.journal.appels, ["canal \(sujet)", "declarer \(sujet) messages_chat insertions sans filtre", "abonner \(sujet)"],
                       "un seul canal pour deux lecteurs, sans filtre : la RLS est le seul filtre d'accès")
        try XCTUnwrap(transport.canaux(sujet).first).emettre(.insertion(ligneMessage("m-1", conversation: "c-autre")), table: "messages_chat")
        await attendre { await badge.valeurs.count == 1 }
        await attendre { await liste.valeurs.count == 1 }
    }

    func testListeSansSessionFluxFermeSansCanal() async {
        let (passerelle, transport) = banc(utilisateur: nil)
        var recus = 0
        for await _ in passerelle.messagesEntrants(conversationId: nil) { recus += 1 }
        for await _ in passerelle.etat(conversationId: nil) { recus += 1 }
        XCTAssertEqual(recus, 0)
        XCTAssertEqual(transport.journal.appels, [], "sans session : aucun canal")
    }

    func testEtatGlobalDesCanauxDeMessagesSeulement() async {
        let (passerelle, _) = banc()
        let (globaux, suivi) = collecter(passerelle.etat())
        defer { suivi.cancel() }
        let (_, saisies) = collecter(passerelle.saisies(conversationId: conversation))
        defer { saisies.cancel() }
        try? await Task.sleep(nanoseconds: 60_000_000)
        let avant = await globaux.valeurs
        XCTAssertEqual(avant, [], "canal de saisie : aucun état de canal de messages")
        let (_, ecoute) = collecter(passerelle.messagesEntrants(conversationId: conversation))
        defer { ecoute.cancel() }
        await attendre { await globaux.valeurs == [.connexion, .rejoint] }
    }

    // MARK: - Saisie et présence

    func testSaisiesInsertUpdateDelete() async throws {
        let (passerelle, transport) = banc()
        let sujet = "typing-\(conversation)"
        let (recus, ecoute) = collecter(passerelle.saisies(conversationId: conversation))
        defer { ecoute.cancel() }
        await attendre { transport.journal.nombre("abonner \(sujet)") == 1 }
        XCTAssertEqual(transport.journal.appels.prefix(2), ["canal \(sujet)", "declarer \(sujet) typing_status tous conversation_id=eq.\(conversation)"])
        let canal = try XCTUnwrap(transport.canaux(sujet).first)
        let ligne: JSONObject = ["conversation_id": .string(conversation), "user_id": .string(autre), "started_at": .string("2026-11-02T10:00:00+00:00")]
        await attendre { canal.statut == .abonne }
        try? await Task.sleep(nanoseconds: 30_000_000)
        canal.emettre(.insertion(ligne), table: "typing_status")
        canal.emettre(.miseAJour(ligne), table: "typing_status")
        canal.emettre(.suppression(["conversation_id": .string(conversation), "user_id": .string(autre)]), table: "typing_status")
        canal.emettre(.suppression([:]), table: "typing_status")
        await attendre { await recus.valeurs.count == 3 }
        let saisies = await recus.valeurs
        XCTAssertEqual(saisies, [EtatSaisie(userId: autre, enTrain: true), EtatSaisie(userId: autre, enTrain: true),
                                 EtatSaisie(userId: autre, enTrain: false)])
    }

    func testPresenceLectureInitialePuisChangementsEtSuppression() async throws {
        let (passerelle, transport) = banc()
        let sujet = "presence-\(autre)"
        transport.servir(["user_id": .string(autre), "status": .string("AWAY"), "last_seen_at": .string("2026-11-02T09:00:00+00:00")],
                         table: "presence_status", valeur: autre)
        let (recus, ecoute) = collecter(passerelle.presence(userId: autre))
        defer { ecoute.cancel() }
        await attendre { await recus.valeurs.count == 1 }
        let initiale = await recus.valeurs.first
        XCTAssertEqual(initiale, EtatPresence(userId: autre, statut: .absent, vuLe: Date(timeIntervalSince1970: 1_793_610_000)),
                       "ligne courante lue après l'abonnement")
        let journal = transport.journal.appels
        XCTAssertEqual(journal, ["canal \(sujet)", "declarer \(sujet) presence_status tous user_id=eq.\(autre)", "abonner \(sujet)",
                                 "ligne presence_status user_id,status,last_seen_at user_id=eq.\(autre)"])
        let canal = try XCTUnwrap(transport.canaux(sujet).first)
        canal.emettre(.miseAJour(["user_id": .string(autre), "status": .string("ONLINE"), "last_seen_at": .string("2026-11-02T09:00:30+00:00")]),
                      table: "presence_status")
        canal.emettre(.suppression(["user_id": .string(autre)]), table: "presence_status")
        await attendre { await recus.valeurs.count == 3 }
        let etats = await recus.valeurs
        XCTAssertEqual(etats[1].statut, .enLigne)
        XCTAssertEqual(etats[2], EtatPresence(userId: autre, statut: .horsLigne, vuLe: nil), "ligne supprimée : hors ligne")
    }

    // MARK: - Coupure, fermeture par le serveur, échec d'abonnement

    func testCoupurePuisRejointParLeSDKSansNouveauCanal() async throws {
        let (passerelle, transport) = banc(reglages: .init(surveillance: 0.02, sansRejoint: 30, reprises: [0.01]))
        let sujet = "chat-conv-\(conversation)"
        let (_, ecoute) = collecter(passerelle.messagesEntrants(conversationId: conversation))
        defer { ecoute.cancel() }
        let (etats, suivi) = collecter(passerelle.etat(conversationId: conversation))
        defer { suivi.cancel() }
        await attendre { await etats.valeurs.last == .rejoint }
        let canal = try XCTUnwrap(transport.canaux(sujet).first)
        canal.passer(.desabonne) // socket perdu : le SDK garde le canal et le rejoindra
        await attendre { await etats.valeurs.last == .coupe }
        canal.passer(.abonnement)
        canal.passer(.abonne)
        await attendre { await etats.valeurs.suffix(3) == [.coupe, .connexion, .rejoint] }
        XCTAssertEqual(transport.canaux(sujet).count, 1, "rejoint par le SDK : le canal est gardé")
        XCTAssertEqual(transport.journal.nombre("retirer"), 0)
    }

    func testCanalFermeParLeServeurRemplaceParUnCanalNeuf() async throws {
        let (passerelle, transport) = banc()
        let sujet = "chat-conv-\(conversation)"
        let (recus, ecoute) = collecter(passerelle.messagesEntrants(conversationId: conversation))
        defer { ecoute.cancel() }
        let (etats, suivi) = collecter(passerelle.etat(conversationId: conversation))
        defer { suivi.cancel() }
        await attendre { await etats.valeurs.last == .rejoint }
        let premier = try XCTUnwrap(transport.canaux(sujet).first)
        transport.fermerParLeServeur(premier)
        await attendre { transport.canaux(sujet).count == 2 }
        await attendre { await etats.valeurs.suffix(3) == [.coupe, .connexion, .rejoint] }
        let apres = transport.journal.appels.suffix(3)
        XCTAssertEqual(Array(apres), ["canal \(sujet)", "declarer \(sujet) messages_chat insertions conversation_id=eq.\(conversation)", "abonner \(sujet)"],
                       "canal neuf : flux redéclaré avant l'abonnement")
        XCTAssertEqual(transport.journal.nombre("retirer \(sujet)"), 1, "l'ancien canal est retiré")
        // Le lecteur garde son flux : un INSERT du canal neuf lui parvient.
        transport.canaux(sujet)[1].emettre(.insertion(ligneMessage("m-apres")), table: "messages_chat")
        await attendre { await recus.valeurs.map(\.id) == ["m-apres"] }
    }

    func testCanalResteDesabonneTropLongtempsEstRemplace() async throws {
        let (passerelle, transport) = banc(reglages: .init(surveillance: 0.02, sansRejoint: 0.1, reprises: [0.01]))
        let sujet = "chat-conv-\(conversation)"
        let (_, ecoute) = collecter(passerelle.messagesEntrants(conversationId: conversation))
        defer { ecoute.cancel() }
        let (etats, suivi) = collecter(passerelle.etat(conversationId: conversation))
        defer { suivi.cancel() }
        await attendre { await etats.valeurs.last == .rejoint }
        try XCTUnwrap(transport.canaux(sujet).first).passer(.desabonne) // erreur de canal : toujours connu du client, jamais rejoint
        await attendre { transport.canaux(sujet).count == 2 }
        await attendre { await etats.valeurs.last == .rejoint }
        XCTAssertEqual(transport.journal.nombre("retirer \(sujet)"), 1)
    }

    func testAbonnementEnEchecReprisAvecUnCanalNeuf() async {
        let (passerelle, transport) = banc()
        let sujet = "chat-conv-\(conversation)"
        transport.echouer(2)
        let (_, ecoute) = collecter(passerelle.messagesEntrants(conversationId: conversation))
        defer { ecoute.cancel() }
        let (etats, suivi) = collecter(passerelle.etat(conversationId: conversation))
        defer { suivi.cancel() }
        await attendre { await etats.valeurs.last == .rejoint }
        XCTAssertEqual(transport.canaux(sujet).count, 3, "deux échecs, puis un abonnement réussi")
        XCTAssertEqual(transport.journal.nombre("echec \(sujet)"), 2)
        XCTAssertEqual(transport.journal.nombre("retirer \(sujet)"), 2, "un canal en échec est retiré avant la reprise")
        let ordre = await etats.valeurs
        XCTAssertTrue(ordre.contains(.coupe))
        XCTAssertEqual(transport.journal.appels.filter { $0.hasPrefix("declarer") }.count, 3, "flux déclaré sur chaque canal, avant son abonnement")
    }

    // MARK: - Fermetures

    func testDernierLecteurPartiLeCanalEstRetire() async throws {
        let (passerelle, transport) = banc()
        let fil = "chat-conv-\(conversation)"
        let (_, premier) = collecter(passerelle.messagesEntrants(conversationId: conversation))
        let (_, second) = collecter(passerelle.messagesEntrants(conversationId: conversation))
        let (_, saisies) = collecter(passerelle.saisies(conversationId: conversation))
        defer { saisies.cancel() }
        let (etats, suivi) = collecter(passerelle.etat(conversationId: conversation))
        defer { suivi.cancel() }
        await attendre { await etats.valeurs.last == .rejoint }
        premier.cancel()
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(transport.journal.nombre("retirer \(fil)"), 0, "encore un lecteur : canal gardé")
        second.cancel()
        await attendre { transport.journal.nombre("retirer \(fil)") == 1 }
        await attendre { await etats.valeurs.last == .ferme }
        XCTAssertEqual(transport.journal.nombre("retirer typing-\(conversation)"), 0, "les autres canaux restent")
        // Un nouveau lecteur rouvre un canal neuf.
        let (_, troisieme) = collecter(passerelle.messagesEntrants(conversationId: conversation))
        defer { troisieme.cancel() }
        await attendre { transport.canaux(fil).count == 2 }
        await attendre { await etats.valeurs.last == .rejoint }
    }

    /// Le client du SDK range ses canaux par sujet : le canal neuf d'un fil rouvert aussitôt n'est créé qu'après le
    /// retrait du précédent, sinon ce retrait l'emporterait.
    func testFilRouvertAussitotAttendLeRetraitDuCanalPrecedent() async throws {
        let (passerelle, transport) = banc()
        let sujet = "chat-conv-\(conversation)"
        let (_, premier) = collecter(passerelle.messagesEntrants(conversationId: conversation))
        await attendre { transport.journal.nombre("abonner \(sujet)") == 1 }
        premier.cancel() // le lecteur attendait le flux : son départ est traité avant le retour de `cancel()`
        let (_, second) = collecter(passerelle.messagesEntrants(conversationId: conversation))
        defer { second.cancel() }
        await attendre { transport.journal.nombre("abonner \(sujet)") == 2 }
        let appels = transport.journal.appels
        let retrait = try XCTUnwrap(appels.firstIndex(of: "retirer \(sujet)"))
        let neuf = try XCTUnwrap(appels.lastIndex(of: "canal \(sujet)"))
        XCTAssertLessThan(retrait, neuf, "retrait de l'ancien canal avant la création du canal neuf")
        XCTAssertEqual(transport.journal.nombre("retirer \(sujet)"), 1)
    }

    func testFermerToutRetireToutEtTermineLesFlux() async throws {
        let (passerelle, transport) = banc()
        let (messages, ecoute) = collecter(passerelle.messagesEntrants(conversationId: conversation))
        let (liste, ecouteListe) = collecter(passerelle.messagesEntrants(conversationId: nil))
        let (saisies, ecouteSaisies) = collecter(passerelle.saisies(conversationId: conversation))
        let (presences, ecoutePresences) = collecter(passerelle.presence(userId: autre))
        let (etats, suivi) = collecter(passerelle.etat(conversationId: conversation))
        let (globaux, suiviGlobal) = collecter(passerelle.etat())
        await attendre { transport.journal.nombre("abonner") == 4 }
        await attendre { await etats.valeurs.last == .rejoint }
        await passerelle.fermerTout()
        XCTAssertEqual(transport.journal.nombre("retirerTout"), 1, "removeAllChannels()")
        for tache in [ecoute, ecouteListe, ecouteSaisies, ecoutePresences, suivi, suiviGlobal] { await tache.value } // flux terminés
        let fins = [await messages.termine, await liste.termine, await saisies.termine, await presences.termine, await etats.termine,
                    await globaux.termine]
        XCTAssertEqual(fins, Array(repeating: true, count: 6))
        let dernier = await etats.valeurs.last
        XCTAssertEqual(dernier, .ferme)
        let canauxAvant = transport.canaux.count
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(transport.canaux.count, canauxAvant, "rien n'est rouvert après fermerTout()")
        // Retour au premier plan : un flux redemandé ouvre un canal neuf.
        let (_, reprise) = collecter(passerelle.messagesEntrants(conversationId: conversation))
        defer { reprise.cancel() }
        await attendre { transport.canaux.count == canauxAvant + 1 }
    }

    // MARK: - Adaptation du SDK (sans réseau)

    func testStatutsDuSDKEtSujets() {
        XCTAssertEqual(CanalRealtimeSDK.statut(.unsubscribed), .desabonne)
        XCTAssertEqual(CanalRealtimeSDK.statut(.subscribing), .abonnement)
        XCTAssertEqual(CanalRealtimeSDK.statut(.subscribed), .abonne)
        XCTAssertEqual(CanalRealtimeSDK.statut(.unsubscribing), .desabonnement)
        XCTAssertEqual(SupabaseRealtimeGateway.sujetListe("u"), "messagerie-liste-u")
        XCTAssertEqual(SupabaseRealtimeGateway.sujetFil("c"), "chat-conv-c")
        XCTAssertEqual(SupabaseRealtimeGateway.sujetSaisies("c"), "typing-c")
        XCTAssertEqual(SupabaseRealtimeGateway.sujetPresence("u"), "presence-u")
    }

    /// Le transport réel crée ses canaux sur `client.realtimeV2` sans ouvrir de connexion (aucun abonnement ici) : un
    /// canal créé est connu du client, un canal retiré ne l'est plus, et un sujet redemandé rend un canal neuf.
    func testTransportSDKCanalConnuPuisRetireSansConnexion() async {
        StubRegistry.shared.reset()
        let client = TestClient.make()
        let transport = TransportRealtimeSDK(client: client)
        XCTAssertNil(transport.utilisateur(), "aucune session : pas de sujet de liste")
        let canal = transport.canal("chat-conv-\(conversation)")
        XCTAssertTrue(transport.estEnregistre(canal))
        XCTAssertEqual(canal.statut, .desabonne)
        XCTAssertEqual((canal as? CanalRealtimeSDK)?.canal.topic, "realtime:chat-conv-\(conversation)")
        _ = canal.declarer(FluxRealtime(.insertions, table: "messages_chat", colonne: "conversation_id", valeur: conversation))
        await transport.retirer(canal)
        XCTAssertFalse(transport.estEnregistre(canal))
        let neuf = transport.canal("chat-conv-\(conversation)")
        XCTAssertFalse(neuf === canal, "sujet redemandé après retrait : canal neuf")
        await transport.retirerTout()
        XCTAssertFalse(transport.estEnregistre(neuf))
        XCTAssertTrue(StubRegistry.shared.requests.isEmpty, "aucune requête HTTP")
    }
}
