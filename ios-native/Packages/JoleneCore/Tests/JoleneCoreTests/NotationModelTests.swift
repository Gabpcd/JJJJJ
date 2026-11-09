import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurNotation = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                    emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                    appMetadataRole: "SOIGNANT")

/// Notation rapide au départ final (lot 2, T5a, décision 10 ; parité `SheetNotationRapide` et
/// `PointageRotatifSoignant.tsx` l.152-163) : proposée une fois par mission et par utilisateur, après relecture de
/// `fin_le` (`maintenant ≥ fin − 30 min`) ; note globale répliquée sans détail ; « déjà notée » silencieux ; refus
/// serveur verbatim ; jamais de lecture de note (écriture seule).
@MainActor
final class NotationModelTests: XCTestCase {
    private struct ModelError: Error {}

    private final class PortNotation: NotationPort, @unchecked Sendable {
        private let lock = NSLock()
        var fin: Result<String?, Error> = .success("2026-11-02T00:20:00Z")
        var issues: [Result<IssueNotation, Error>] = []
        private(set) var envois: [(missionId: String, note: Int, criteres: CriteresNotation?)] = []
        private(set) var lecturesFin = 0

        func noter(missionId: String, note: Int, criteres: CriteresNotation?,
                   context: MissionReadContext) async throws -> IssueNotation {
            let issue = lock.withLock { () -> Result<IssueNotation, Error> in
                envois.append((missionId, note, criteres))
                return issues.isEmpty ? .success(.enregistree) : issues.removeFirst()
            }
            return try issue.get()
        }

        func finPrevue(missionId: String, context: MissionReadContext) async throws -> String? {
            let reponse = lock.withLock { () -> Result<String?, Error> in
                lecturesFin += 1
                return fin
            }
            return try reponse.get()
        }
    }

    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurNotation }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw ModelError() }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    /// 2026-11-02T00:00:00Z.
    private func pret(_ port: PortNotation) async throws -> (SessionController, SessionSnapshot) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.notation = port
        let controller = SessionController(gateways: gateways)
        let state = await controller.start()
        return (controller, try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)"))
    }

    private func model(_ port: PortNotation, memoire: any MemoireNotation = MemoireNotationEnMemoire(),
                       mission: String = "m-1") async throws -> NotationModel {
        let (controller, snapshot) = try await pret(port)
        return NotationModel(missionId: mission, controller: controller, snapshot: snapshot, memoire: memoire)
    }

    // MARK: - Proposition

    func testProposeeApresFinMoinsTrenteMinutesPuisUneSeuleFois() async throws {
        let port = PortNotation()
        let memoire = MemoireNotationEnMemoire()
        let notation = try await model(port, memoire: memoire)
        await notation.proposer()
        XCTAssertTrue(notation.ouverte, "fin prévue à 01h20 (Paris), maintenant 01h00 : dans les 30 min")
        XCTAssertTrue(memoire.dejaProposee(userId: "u-1", missionId: "m-1"), "mémoire posée avant l'ouverture")
        notation.plusTard()
        XCTAssertFalse(notation.ouverte)
        await notation.proposer()
        XCTAssertFalse(notation.ouverte, "« Plus tard » : jamais reproposée pour cette mission")
        XCTAssertEqual(port.lecturesFin, 1, "mémoire lue avant toute relecture")

        let autre = try await model(port, memoire: memoire, mission: "m-2")
        await autre.proposer()
        XCTAssertTrue(autre.ouverte, "une autre mission reste proposable")
    }

    func testPasProposeeAvantFinMoinsTrenteMinutesNiSurErreur() async throws {
        let port = PortNotation()
        port.fin = .success("2026-11-02T06:00:00Z")
        let memoire = MemoireNotationEnMemoire()
        let notation = try await model(port, memoire: memoire)
        await notation.proposer()
        XCTAssertFalse(notation.ouverte, "fin relue à 07h00 (Paris) : départ non final")
        XCTAssertFalse(memoire.dejaProposee(userId: "u-1", missionId: "m-1"), "rien n'est mémorisé")

        port.fin = .failure(JoleneError(.network, "Le service ne répond pas."))
        await notation.proposer()
        XCTAssertFalse(notation.ouverte, "relecture en échec : rien n'est proposé (le pointage n'est jamais gêné)")
        port.fin = .success(nil)
        await notation.proposer()
        XCTAssertFalse(notation.ouverte, "mission illisible : rien n'est proposé")
        port.fin = .success("pas une date")
        await notation.proposer()
        XCTAssertFalse(notation.ouverte, "fin illisible : rien n'est proposé")
        XCTAssertEqual(port.lecturesFin, 4, "la fin prévue est relue à chaque proposition (revue de L2-T3, m6)")
    }

    func testMemoireParUtilisateurEtParMissionDansUserDefaults() throws {
        let suite = "jolene.tests.notation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memoire = MemoireNotationDefaults(defaults: defaults)
        XCTAssertEqual(MemoireNotationDefaults.cle(userId: "u-1", missionId: "m-1"), "jolene.notation.checkout.u-1.m-1")
        XCTAssertFalse(memoire.dejaProposee(userId: "u-1", missionId: "m-1"))
        memoire.marquerProposee(userId: "u-1", missionId: "m-1")
        XCTAssertTrue(memoire.dejaProposee(userId: "u-1", missionId: "m-1"))
        XCTAssertFalse(memoire.dejaProposee(userId: "u-2", missionId: "m-1"), "par utilisateur")
        XCTAssertFalse(memoire.dejaProposee(userId: "u-1", missionId: "m-2"), "par mission")
        XCTAssertTrue(MemoireNotationDefaults(defaults: defaults).dejaProposee(userId: "u-1", missionId: "m-1"), "persistée")
    }

    // MARK: - Saisie et envoi

    func testNoteGlobaleSansDetailEtEnvoiEnregistre() async throws {
        let port = PortNotation()
        let notation = try await model(port)
        await notation.proposer()
        XCTAssertFalse(notation.peutEnvoyer, "aucune note choisie")
        await notation.envoyer()
        XCTAssertTrue(port.envois.isEmpty)
        notation.choisirNote(4)
        XCTAssertTrue(notation.peutEnvoyer)
        await notation.envoyer()
        XCTAssertEqual(port.envois.count, 1)
        XCTAssertEqual(port.envois.first?.note, 4)
        XCTAssertNil(port.envois.first?.criteres, "sans détail : la gateway réplique la note sur les quatre critères")
        XCTAssertFalse(notation.ouverte)
        XCTAssertEqual(notation.retour, .remerciement)
        XCTAssertEqual(notation.note, 0, "feuille réinitialisée à la fermeture")
    }

    func testDetailPreRempliParLaNoteOuTrois() async throws {
        let port = PortNotation()
        let notation = try await model(port)
        await notation.proposer()
        notation.basculerDetail()
        XCTAssertEqual(notation.criteres, [3, 3, 3, 3], "`note || 3`")
        notation.basculerDetail()
        XCTAssertNil(notation.criteres)
        notation.choisirNote(5)
        notation.basculerDetail()
        XCTAssertEqual(notation.criteres, [5, 5, 5, 5])
        notation.choisirCritere(2, 2)
        notation.choisirCritere(7, 1)
        notation.choisirCritere(0, 9)
        XCTAssertEqual(notation.criteres, [5, 5, 2, 5], "index et valeur hors bornes ignorés")
        notation.choisirNote(1)
        XCTAssertEqual(notation.criteres, [5, 5, 2, 5], "détail ouvert : les critères ne suivent plus la note")
        await notation.envoyer()
        XCTAssertEqual(port.envois.first?.criteres, CriteresNotation(5, 5, 2, 5))
        XCTAssertEqual(port.envois.first?.note, 1)
    }

    func testDejaNoteeSilencieuxRefusVerbatimEtTransport() async throws {
        let port = PortNotation()
        port.issues = [.success(.refusee(message: "Notation impossible pendant un litige en médiation ou en revue admin. Vous pourrez noter après résolution.")),
                       .failure(JoleneError(.network, "Le service ne répond pas.")),
                       .success(.dejaNotee)]
        let notation = try await model(port)
        await notation.proposer()
        notation.choisirNote(3)
        await notation.envoyer()
        XCTAssertTrue(notation.ouverte, "refus serveur : la feuille reste ouverte")
        XCTAssertEqual(notation.retour, .erreur("Notation impossible pendant un litige en médiation ou en revue admin. Vous pourrez noter après résolution."))
        await notation.envoyer()
        XCTAssertTrue(notation.ouverte)
        XCTAssertEqual(notation.retour, .erreur("La note n'a pas pu être enregistrée. Réessayez."))
        await notation.envoyer()
        XCTAssertFalse(notation.ouverte, "« déjà notée » : rien à montrer, la feuille se ferme comme un succès (l.58-61)")
        XCTAssertEqual(notation.retour, .remerciement)
        XCTAssertEqual(port.envois.count, 3)
        notation.oublierRetour()
        XCTAssertNil(notation.retour)
    }

    func testSessionExpireeALEnvoi() async throws {
        let port = PortNotation()
        port.issues = [.failure(JoleneError(.unauthorized, "Votre session a expiré."))]
        let notation = try await model(port)
        await notation.proposer()
        notation.choisirNote(2)
        await notation.envoyer()
        XCTAssertTrue(notation.sessionExpired)
        XCTAssertEqual(notation.retour, .erreur("Votre session a expiré."))
        XCTAssertTrue(notation.ouverte)
    }

    func testAucunControleDeStatutCoteClient() async throws {
        // Le serveur accepte une mission EN_COURS dont le départ est pointé (`fn_creer_notation_mission`) : le modèle ne
        // filtre rien sur le statut et ne relit aucune note (écriture seule).
        let port = PortNotation()
        let notation = try await model(port)
        await notation.proposer()
        notation.choisirNote(4)
        await notation.envoyer()
        XCTAssertEqual(port.envois.map(\.missionId), ["m-1"])
    }

    func testTextesDeLaFeuille() {
        XCTAssertEqual(LibellesWeb.Notation.titre, "Mission terminée 🎉 Comment ça s'est passé ?")
        XCTAssertEqual(LibellesDetailPresences.Notation.criteres,
                       ["Accueil", "Encadrement", "Clarté des consignes", "Paiement / administratif"])
        XCTAssertEqual(LibellesDetailPresences.Notation.etoiles(1), "1 étoile")
        XCTAssertEqual(LibellesDetailPresences.Notation.etoiles(4), "4 étoiles")
        XCTAssertEqual([LibellesWeb.Notation.detailler, LibellesWeb.Notation.masquerDetail, LibellesWeb.Notation.envoyer,
                        LibellesWeb.Notation.plusTard],
                       ["Détailler ma note (optionnel)", "Masquer le détail", "Envoyer ma note", "Plus tard"])
    }
}
