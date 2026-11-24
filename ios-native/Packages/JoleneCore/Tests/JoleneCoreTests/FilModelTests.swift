import XCTest
@testable import JoleneCore

/// Fil d'une conversation (lot 4, T7a ; `LOT4_PLAN.md` §2.5 « Messagerie Realtime »). Règles prouvées : fusion par id
/// (un INSERT Realtime d'un message déjà relu est ignoré) ; message entrant fil ouvert → `marquerLus` puis badge relu ;
/// « rejoint » → relecture depuis le dernier `cree_le` ; epoch changé → flux quittés, réponses ignorées ; envoi par
/// l'edge puis relecture de la ligne par id ; délai d'envoi → « non confirmé » et relecture du fil, aucun renvoi ; un
/// seul envoi à la fois ; anti-fuite et refus sans effet sur le fil.
@MainActor
final class FilModelTests: XCTestCase {
    private let fil = "c-1"
    private let autre = "etab-user"

    private struct Banc {
        let model: FilModel
        let messagerie: MessagerieFactice
        let realtime: RealtimeFactice
        let controller: SessionController
        let cycle: CycleRealtime?
        let journal: JournalAppels
        let suivi: Task<Void, Never>
    }

    private let delaisCourts = FilModel.Delais(battement: 30, rafraichissementSaisie: 0.2, inactiviteSaisie: 0.08, peremptionSaisie: 0.08)

    /// Fil ouvert (`suivre()` lancé) et chargé. `avecCycle` : cycle de vie au premier plan (badge, liste).
    private func ouvert(_ messages: [MessageChat]? = nil, avecCycle: Bool = false, timeout: TimeInterval = SessionController.defaultResolutionTimeout,
                        archivee: Bool = false, preparer: (MessagerieFactice, RealtimeFactice) -> Void = { _, _ in },
                        file: StaticString = #filePath, line: UInt = #line) async throws -> Banc {
        let journal = JournalAppels()
        let messagerie = MessagerieFactice(journal: journal)
        let realtime = RealtimeFactice(journal: journal)
        messagerie.fil = messages ?? [
            SessionMessagerie.message("m-1", auteur: autre, creeLe: "2026-11-02T10:00:00.000000+00:00"),
            SessionMessagerie.message("m-2", auteur: SessionMessagerie.moi, creeLe: "2026-11-02T10:05:00.000000+00:00"),
        ]
        preparer(messagerie, realtime)
        let controller = SessionController(gateways: SessionMessagerie.gateways(messagerie: messagerie, realtime: realtime),
                                           resolutionTimeout: timeout)
        var cycle: CycleRealtime?
        let snapshot: SessionSnapshot
        if avecCycle {
            let store = SessionStore(controller: controller)
            await store.start()
            snapshot = try XCTUnwrap(store.state.snapshot, file: file, line: line)
            let nouveau = CycleRealtime(session: store, ecranLivre: true)
            await nouveau.premierPlan()
            cycle = nouveau
        } else {
            snapshot = try XCTUnwrap(await controller.start().snapshot, file: file, line: line)
        }
        let model = FilModel(controller: controller, snapshot: snapshot, conversationId: fil, autreId: autre, archivee: archivee,
                             cycle: cycle, delais: delaisCourts)
        let suivi = Task { await model.suivre() }
        await waitUntil({ @MainActor in model.etat == .pret }, file: file, line: line)
        await waitUntil({ journal.nombre("marquerLus") >= 1 }, file: file, line: line)
        // Canal abonné d'emblée par le double : la relecture qui suit ce premier « rejoint » est attendue ici, pour que
        // chaque test parte d'un journal stable.
        if realtime.rejointImmediat, !messagerie.fil.isEmpty {
            await waitUntil({ journal.nombre("messages c-1 depuis") >= 1 }, file: file, line: line)
        }
        return Banc(model: model, messagerie: messagerie, realtime: realtime, controller: controller, cycle: cycle, journal: journal,
                    suivi: suivi)
    }

    private func pause(_ secondes: TimeInterval = 0.06) async {
        try? await Task.sleep(nanoseconds: UInt64(secondes * 1_000_000_000))
    }

    // MARK: - Ouverture

    func testOuvertureDeclareLesFluxPuisLitLeFilLeMarqueLuEtRelitLeBadge() async throws {
        let banc = try await ouvert(avecCycle: true) { messagerie, _ in messagerie.nonLusSuccessifs = [4, 1] }
        defer { banc.suivi.cancel() }
        XCTAssertEqual(banc.model.messages.map(\.id), ["m-1", "m-2"], "ordre cree_le croissant")
        let journal = banc.journal
        let flux = try XCTUnwrap(journal.index("flux messages \(fil)"))
        let lecture = try XCTUnwrap(journal.index("messages \(fil)"))
        let lus = try XCTUnwrap(journal.index("marquerLus \(fil)"))
        XCTAssertLessThan(flux, lecture, "flux déclarés avant la lecture : aucun message perdu entre les deux")
        XCTAssertLessThan(lecture, lus, "lecture des messages à l'ouverture du fil")
        XCTAssertNotNil(journal.index("flux saisies \(fil)"))
        XCTAssertNotNil(journal.index("flux presence \(autre)"))
        await waitUntil { @MainActor in banc.cycle?.nonLus == 1 }
        XCTAssertGreaterThan(try XCTUnwrap(journal.dernierIndex("nonLus")), lus, "fn_messages_non_lus relu après marquerLus")
        XCTAssertEqual(banc.cycle?.filOuvert, fil)
    }

    func testEchecDeLaPremiereLectureEtRelecture() async throws {
        let journal = JournalAppels()
        let messagerie = MessagerieFactice(journal: journal)
        let realtime = RealtimeFactice(journal: journal)
        let echec = JoleneError(.network, "Connexion impossible. Vérifiez votre réseau puis réessayez.")
        messagerie.avantFil = { throw echec }
        let (controller, snapshot) = try await SessionMessagerie.prete(messagerie: messagerie, realtime: realtime)
        let model = FilModel(controller: controller, snapshot: snapshot, conversationId: fil, autreId: autre)
        let suivi = Task { await model.suivre() }
        defer { suivi.cancel() }
        await waitUntil { @MainActor in model.etat == .echec(echec.message) }
        XCTAssertEqual(journal.nombre("marquerLus"), 0, "rien n'est marqué lu sans fil lu")
        messagerie.avantFil = {}
        messagerie.fil = [SessionMessagerie.message("m-1")]
        await model.relire()
        XCTAssertEqual(model.etat, .pret)
        XCTAssertEqual(model.messages.map(\.id), ["m-1"])
        XCTAssertEqual(journal.nombre("marquerLus"), 1)
    }

    func testAccesRefuseALaLectureSansDeconnexion() async throws {
        let banc = try await ouvert(avecCycle: true) { messagerie, _ in messagerie.lecture = { .accesRefuse } }
        defer { banc.suivi.cancel() }
        await waitUntil { @MainActor in banc.model.accesRefuse }
        XCTAssertFalse(banc.model.sessionExpiree, "42501 « Accès refusé » : jamais une session expirée")
        let etat = await banc.controller.state
        XCTAssertTrue(etat.isReady)
    }

    // MARK: - Realtime

    func testInsertRealtimeDUnIdDejaReluIgnore() async throws {
        let banc = try await ouvert()
        defer { banc.suivi.cancel() }
        banc.realtime.emettre(SessionMessagerie.message("m-1", auteur: autre, creeLe: "2026-11-02T10:00:00.000000+00:00"))
        banc.realtime.emettre(SessionMessagerie.message("m-3", auteur: autre, creeLe: "2026-11-02T10:06:00.000000+00:00"))
        await waitUntil { @MainActor in banc.model.messages.count == 3 }
        XCTAssertEqual(banc.model.messages.map(\.id), ["m-1", "m-2", "m-3"], "dédoublonnage par id")
        banc.realtime.emettre(SessionMessagerie.message("m-x", conversation: "c-2"))
        await pause()
        XCTAssertEqual(banc.model.messages.count, 3, "message d'un autre fil ignoré")
    }

    func testMessageEntrantFilOuvertMarqueLuMaisPasLeMien() async throws {
        let banc = try await ouvert(avecCycle: true) { messagerie, _ in messagerie.nonLusSuccessifs = [2, 0] }
        defer { banc.suivi.cancel() }
        XCTAssertEqual(banc.journal.nombre("marquerLus"), 1)
        banc.realtime.emettre(SessionMessagerie.message("m-3", auteur: autre, creeLe: "2026-11-02T10:06:00+00:00"))
        await waitUntil { banc.journal.nombre("marquerLus") == 2 }
        let lus = try XCTUnwrap(banc.journal.dernierIndex("marquerLus"))
        await waitUntil { (banc.journal.dernierIndex("nonLus") ?? -1) > lus }
        banc.realtime.emettre(SessionMessagerie.message("m-4", auteur: SessionMessagerie.moi, creeLe: "2026-11-02T10:07:00+00:00"))
        await waitUntil { @MainActor in banc.model.messages.count == 4 }
        await pause()
        XCTAssertEqual(banc.journal.nombre("marquerLus"), 2, "mon propre message ne déclenche pas de marquage")
    }

    func testRejointApresCoupureRelitDepuisLeDernierCreeLe() async throws {
        let banc = try await ouvert()
        defer { banc.suivi.cancel() }
        await waitUntil { @MainActor in banc.model.canal == .rejoint }
        banc.journal.vider()
        banc.realtime.etatCanal(.coupe, conversationId: fil)
        await waitUntil { @MainActor in banc.model.canal == .coupe }
        // Message manqué pendant la coupure : jamais reçu par le flux, seulement relu.
        banc.messagerie.fil += [SessionMessagerie.message("m-3", auteur: autre, creeLe: "2026-11-02T10:09:00.000000+00:00")]
        banc.realtime.etatCanal(.rejoint, conversationId: fil)
        await waitUntil { @MainActor in banc.model.messages.count == 3 }
        XCTAssertEqual(banc.journal.nombre("messages \(fil) depuis 2026-11-02T10:05:00.000000+00:00"), 1,
                       "relecture depuis le dernier cree_le connu")
        XCTAssertEqual(banc.model.messages.map(\.id), ["m-1", "m-2", "m-3"])
        await waitUntil { banc.journal.nombre("marquerLus") == 1 }
    }

    func testSaisieEtPresenceDeLInterlocuteur() async throws {
        let banc = try await ouvert()
        defer { banc.suivi.cancel() }
        banc.realtime.emettre(saisie: EtatSaisie(userId: "un-tiers", enTrain: true), conversationId: fil)
        await pause(0.03)
        XCTAssertFalse(banc.model.saisieInterlocuteur, "saisie d'un autre utilisateur que l'interlocuteur ignorée")
        banc.realtime.emettre(saisie: EtatSaisie(userId: autre, enTrain: true), conversationId: fil)
        await waitUntil { @MainActor in banc.model.saisieInterlocuteur }
        await waitUntil { @MainActor in !banc.model.saisieInterlocuteur } // péremption sans rafraîchissement
        banc.realtime.emettre(saisie: EtatSaisie(userId: autre, enTrain: true), conversationId: fil)
        await waitUntil { @MainActor in banc.model.saisieInterlocuteur }
        banc.realtime.emettre(saisie: EtatSaisie(userId: autre, enTrain: false), conversationId: fil)
        await waitUntil { @MainActor in !banc.model.saisieInterlocuteur }
        let presence = EtatPresence(userId: autre, statut: .enLigne, vuLe: DemoWorld.fixedNow)
        banc.realtime.emettre(presence: presence)
        await waitUntil { @MainActor in banc.model.presence == presence }
    }

    func testFrappeSignaleLaSaisiePuisLArretApresInactivite() async throws {
        let banc = try await ouvert()
        defer { banc.suivi.cancel() }
        banc.model.frappe()
        banc.model.frappe()
        await waitUntil { banc.journal.nombre("saisie debut") == 1 }
        await waitUntil { banc.journal.nombre("saisie fin") == 1 }
        XCTAssertEqual(banc.journal.nombre("saisie debut"), 1, "un seul signal dans la fenêtre de rafraîchissement")
        banc.model.frappe()
        await waitUntil { banc.journal.nombre("saisie debut") == 2 }
        await banc.model.finSaisie()
        XCTAssertEqual(banc.journal.nombre("saisie fin"), 2)
        await banc.model.finSaisie()
        XCTAssertEqual(banc.journal.nombre("saisie fin"), 2, "pas de second arrêt sans saisie en cours")
    }

    // MARK: - Epoch

    func testEpochChangeFluxQuittesEtReponsesIgnorees() async throws {
        let barriere = Gate()
        let banc = try await ouvert { messagerie, _ in
            messagerie.envoi = { _ in await barriere.wait(); return .envoye(messageId: "m-9") }
        }
        let envoi = Task { await banc.model.envoyer("Bonjour") }
        await waitUntil { banc.journal.nombre("envoyer") == 1 }
        _ = await banc.controller.signOut() // l'epoch d'identité avance
        banc.realtime.emettre(SessionMessagerie.message("m-3", auteur: autre, creeLe: "2026-11-02T10:06:00+00:00"))
        await barriere.open()
        let envoye = await envoi.value
        XCTAssertFalse(envoye, "réponse d'un epoch périmé ignorée")
        await banc.suivi.value // le suivi se termine de lui-même
        XCTAssertEqual(banc.model.messages.map(\.id), ["m-1", "m-2"], "rien n'est publié après le changement d'identité")
        XCTAssertEqual(banc.journal.nombre("message m-9"), 0, "aucune relecture pour une identité périmée")
        await waitUntil { banc.realtime.lecteurs("c-1") == 0 } // flux du fil quittés
    }

    // MARK: - Envoi

    func testEnvoiConfirmeRelitLaLigneParIdPuisLAffiche() async throws {
        let banc = try await ouvert()
        defer { banc.suivi.cancel() }
        let messagerie = banc.messagerie
        let envoye = SessionMessagerie.message("m-9", auteur: SessionMessagerie.moi, contenu: "Merci", creeLe: "2026-11-02T10:10:00+00:00")
        messagerie.envoi = { _ in messagerie.fil += [envoye]; return .envoye(messageId: "m-9") }
        banc.model.frappe()
        let resultat = await banc.model.envoyer("  Merci  ")
        XCTAssertTrue(resultat)
        XCTAssertEqual(banc.model.messages.map(\.id), ["m-1", "m-2", "m-9"], "bulle affichée après relecture de la ligne")
        XCTAssertLessThan(try XCTUnwrap(banc.journal.index("envoyer")), try XCTUnwrap(banc.journal.index("message m-9")))
        XCTAssertEqual(banc.journal.nombre("envoyer"), 1)
        XCTAssertFalse(banc.model.envoiEnCours)
        XCTAssertFalse(banc.model.envoiNonConfirme)
        await waitUntil { banc.journal.nombre("saisie fin") == 1 } // l'envoi arrête l'indicateur de saisie
        banc.realtime.emettre(envoye) // écho Realtime du même id
        await pause()
        XCTAssertEqual(banc.model.messages.filter { $0.id == "m-9" }.count, 1, "INSERT Realtime du même id ignoré")
    }

    func testEnvoiConfirmeMaisLigneNonRelueRelitLeFilEntier() async throws {
        let banc = try await ouvert()
        defer { banc.suivi.cancel() }
        let messagerie = banc.messagerie
        messagerie.envoi = { _ in
            messagerie.fil += [SessionMessagerie.message("m-9", auteur: SessionMessagerie.moi, creeLe: "2026-11-02T10:10:00+00:00")]
            return .envoye(messageId: "m-9")
        }
        messagerie.avantMessageParId = { throw JoleneError(.network, "coupure") }
        let avant = banc.journal.nombre("messages \(fil)")
        let resultat = await banc.model.envoyer("Merci")
        XCTAssertTrue(resultat, "le serveur a confirmé l'insertion : le texte n'est pas renvoyé")
        XCTAssertEqual(banc.journal.nombre("messages \(fil)"), avant + 1, "relecture du fil à défaut de la ligne")
        XCTAssertEqual(banc.model.messages.map(\.id), ["m-1", "m-2", "m-9"])
    }

    func testDelaiDEnvoiNonConfirmePuisRelectureSansRenvoi() async throws {
        let banc = try await ouvert(timeout: 0.15) { messagerie, _ in
            messagerie.envoi = { _ in
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return .envoye(messageId: "jamais")
            }
        }
        defer { banc.suivi.cancel() }
        let lectures = banc.journal.nombre("messages \(fil)")
        let resultat = await banc.model.envoyer("Bonjour")
        XCTAssertFalse(resultat)
        XCTAssertTrue(banc.model.envoiNonConfirme, "délai dépassé : envoi non confirmé")
        XCTAssertEqual(banc.journal.nombre("envoyer"), 1, "aucun renvoi automatique")
        XCTAssertEqual(banc.journal.nombre("messages \(fil)"), lectures + 1, "relecture du fil")
        XCTAssertNil(banc.model.refusEnvoi)
        XCTAssertFalse(banc.model.envoiEnCours)
    }

    func testIssueNonConfirmeeRelitLeFil() async throws {
        let banc = try await ouvert { messagerie, _ in messagerie.envoi = { _ in .nonConfirme } }
        defer { banc.suivi.cancel() }
        let lectures = banc.journal.nombre("messages \(fil)")
        let resultat = await banc.model.envoyer("Bonjour")
        XCTAssertFalse(resultat)
        XCTAssertTrue(banc.model.envoiNonConfirme)
        XCTAssertEqual(banc.journal.nombre("messages \(fil)"), lectures + 1)
        XCTAssertEqual(banc.journal.nombre("envoyer"), 1)
    }

    func testAntiFuiteEtRefusLaissentLeFilIntact() async throws {
        let banc = try await ouvert { messagerie, _ in messagerie.envoi = { _ in .antiFuite(.telephone) } }
        defer { banc.suivi.cancel() }
        let fuite = await banc.model.envoyer("06 12 34 56 78")
        XCTAssertFalse(fuite, "texte conservé par l'écran")
        XCTAssertEqual(banc.model.antiFuite, .telephone)
        XCTAssertEqual(banc.model.messages.count, 2)
        XCTAssertEqual(banc.journal.nombre("message "), 0, "aucune relecture par id sans message_id")
        banc.model.fermerAntiFuite()
        XCTAssertNil(banc.model.antiFuite)

        banc.messagerie.envoi = { _ in .antiFuite(nil) }
        let sansType = await banc.model.envoyer("texte")
        XCTAssertFalse(sansType)
        XCTAssertNil(banc.model.antiFuite, "type inconnu : pas de feuille, refus générique comme le web")
        XCTAssertEqual(banc.model.refusEnvoi?.code, CodeEnvoi.antiFuite)

        banc.messagerie.envoi = { _ in .refuse(code: CodeEnvoi.limite, message: "refus serveur") }
        let limite = await banc.model.envoyer("texte")
        XCTAssertFalse(limite)
        XCTAssertEqual(banc.model.refusEnvoi, FilModel.RefusEnvoi(code: CodeEnvoi.limite, message: "refus serveur"))
        XCTAssertFalse(banc.model.archivee)
        banc.model.effacerRefus()
        XCTAssertNil(banc.model.refusEnvoi)

        banc.messagerie.envoi = { _ in .refuse(code: CodeEnvoi.conversationArchivee, message: "refus serveur") }
        let archivee = await banc.model.envoyer("texte")
        XCTAssertFalse(archivee)
        XCTAssertTrue(banc.model.archivee, "409 CONVERSATION_ARCHIVEE : composeur désactivé")
        let envois = banc.journal.nombre("envoyer")
        let apres = await banc.model.envoyer("texte")
        XCTAssertFalse(apres)
        XCTAssertEqual(banc.journal.nombre("envoyer"), envois, "conversation archivée : rien n'est envoyé")
    }

    func testUnSeulEnvoiALaFoisEtTexteVideIgnore() async throws {
        let barriere = Gate()
        let banc = try await ouvert { messagerie, _ in
            messagerie.envoi = { _ in await barriere.wait(); return .refuse(code: nil, message: "refus") }
        }
        defer { banc.suivi.cancel() }
        let vide = await banc.model.envoyer("   \n ")
        XCTAssertFalse(vide)
        XCTAssertEqual(banc.journal.nombre("envoyer"), 0)
        let premier = Task { await banc.model.envoyer("un") }
        await waitUntil { @MainActor in banc.model.envoiEnCours }
        let second = await banc.model.envoyer("deux")
        XCTAssertFalse(second, "second geste pendant l'appel ignoré (verrou synchrone)")
        await barriere.open()
        _ = await premier.value
        XCTAssertEqual(banc.journal.nombre("envoyer"), 1)
    }

    func testSessionExpireeALEnvoi() async throws {
        let banc = try await ouvert { messagerie, _ in
            messagerie.envoi = { _ in throw JoleneError(.unauthorized, SessionController.sessionExpiredMessage) }
        }
        defer { banc.suivi.cancel() }
        let lectures = banc.journal.nombre("messages \(fil)")
        let resultat = await banc.model.envoyer("Bonjour")
        XCTAssertFalse(resultat)
        XCTAssertTrue(banc.model.sessionExpiree)
        XCTAssertFalse(banc.model.envoiNonConfirme, "401 : rien n'a été envoyé")
        XCTAssertEqual(banc.journal.nombre("messages \(fil)"), lectures, "pas de relecture")
        XCTAssertEqual(banc.model.message, SessionController.sessionExpiredMessage)
    }
}
