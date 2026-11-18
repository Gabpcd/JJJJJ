import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurContestation = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                        emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                        appMetadataRole: "SOIGNANT")

/// Contestation d'une présence (lot 2, T5b, HARD STOP n°4 ; décision 9, D12) : bouton seulement si la présence est
/// validée, sans litige, et si le serveur dit la fenêtre ouverte ; toute erreur masque le panneau (fail-closed) ; un
/// litige existant n'affiche que son statut ; refus serveur verbatim ; motif nettoyé et borné.
@MainActor
final class ContestationModelTests: XCTestCase {
    private struct PortError: Error {}

    private final class Port: ContestationPort, @unchecked Sendable {
        private let lock = NSLock()
        var litigeLu: Result<LitigePresence?, Error> = .success(nil)
        var fenetre: Result<Bool, Error> = .success(true)
        var issue: Result<IssueContestation, Error> = .success(.ouverte(LitigePresence(id: "l-1", statut: "OUVERT")))
        private(set) var lecturesFenetre = 0
        private(set) var envois: [(missionId: String, presenceId: String, motif: String)] = []

        func litige(presenceId: String, context: MissionReadContext) async throws -> LitigePresence? {
            try lock.withLock { litigeLu }.get()
        }

        func fenetreOuverte(missionId: String, context: MissionReadContext) async throws -> Bool {
            try lock.withLock { () -> Result<Bool, Error> in lecturesFenetre += 1; return fenetre }.get()
        }

        func contester(missionId: String, presenceId: String, motif: String,
                       context: MissionReadContext) async throws -> IssueContestation {
            try lock.withLock { () -> Result<IssueContestation, Error> in
                envois.append((missionId, presenceId, motif))
                return issue
            }.get()
        }
    }

    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurContestation }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw PortError() }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    private func model(_ port: Port, valideLe: String? = "2026-11-01T14:00:00Z") async throws -> ContestationModel {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.contestation = port
        let controller = SessionController(gateways: gateways)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return ContestationModel(presenceId: "p-1", missionId: "m-1", valideLe: valideLe, controller: controller, snapshot: snapshot)
    }

    // MARK: - Affichage décidé par le serveur

    func testFenetreServeurVraieAfficheLeBouton() async throws {
        let port = Port()
        let contestation = try await model(port)
        await contestation.charger()
        XCTAssertEqual(contestation.etat, .contestable)
        XCTAssertEqual(port.lecturesFenetre, 1)
    }

    func testFenetreFermeeErreurOuPresenceNonValideeNeRendentRien() async throws {
        let fermee = Port()
        fermee.fenetre = .success(false)
        var contestation = try await model(fermee)
        await contestation.charger()
        XCTAssertEqual(contestation.etat, .masque, "fenêtre fermée : rien")

        let enErreur = Port()
        enErreur.fenetre = .failure(JoleneError(.network, "Connexion impossible."))
        contestation = try await model(enErreur)
        await contestation.charger()
        XCTAssertEqual(contestation.etat, .masque, "erreur de la fenêtre : rien (fail-closed)")

        let litigeIllisible = Port()
        litigeIllisible.litigeLu = .failure(PortError())
        contestation = try await model(litigeIllisible)
        await contestation.charger()
        XCTAssertEqual(contestation.etat, .masque, "erreur de lecture du litige : rien (fail-closed)")
        XCTAssertEqual(litigeIllisible.lecturesFenetre, 0)

        let nonValidee = Port()
        contestation = try await model(nonValidee, valideLe: nil)
        await contestation.charger()
        XCTAssertEqual(contestation.etat, .masque, "valide_le nul : jamais de bouton")
        XCTAssertEqual(nonValidee.lecturesFenetre, 0, "aucune fenêtre demandée sans validation")
    }

    func testLitigeExistantAfficheSonStatutSeul() async throws {
        let port = Port()
        port.litigeLu = .success(LitigePresence(id: "l-9", statut: "EN_MEDIATION", presenceId: "p-1"))
        let contestation = try await model(port)
        await contestation.charger()
        XCTAssertEqual(contestation.litige?.id, "l-9")
        XCTAssertEqual(contestation.libelleStatut, "En médiation", "libellé de STATUT_CONFIG (l.51)")
        XCTAssertEqual(port.lecturesFenetre, 0, "litige existant : statut seul, aucune fenêtre demandée")
        contestation.ouvrirFormulaire()
        XCTAssertFalse(contestation.formulaireOuvert, "aucun formulaire sur un litige existant")
    }

    // MARK: - Envoi

    func testEnvoiNettoieLeMotifPuisAfficheLeStatutRelu() async throws {
        let port = Port()
        let contestation = try await model(port)
        await contestation.charger()
        contestation.ouvrirFormulaire()
        contestation.saisirMotif("  <b>Arrivée</b> à 7h, pas 8h  ")
        XCTAssertTrue(contestation.peutEnvoyer)
        await contestation.envoyer()
        XCTAssertEqual(port.envois.count, 1)
        XCTAssertEqual(port.envois.first?.motif, "Arrivée à 7h, pas 8h", "balises retirées, trim (sanitizeText)")
        XCTAssertEqual(port.envois.first?.missionId, "m-1")
        XCTAssertEqual(port.envois.first?.presenceId, "p-1")
        XCTAssertEqual(contestation.libelleStatut, "Ouvert")
        XCTAssertFalse(contestation.formulaireOuvert)
        XCTAssertNil(contestation.erreur)
    }

    func testRefusServeurVerbatimEtMotifTropCourtSansRequete() async throws {
        let port = Port()
        port.issue = .success(.refusee(message: "Fenêtre de contestation fermée pour ce type de litige. Contactez le support."))
        let contestation = try await model(port)
        await contestation.charger()
        contestation.ouvrirFormulaire()
        contestation.saisirMotif("<i>court</i>")
        await contestation.envoyer()
        XCTAssertEqual(contestation.erreur, "Le motif doit contenir entre 10 et 2 000 caractères.")
        XCTAssertTrue(port.envois.isEmpty, "motif nettoyé sous 10 caractères : aucune requête")

        contestation.saisirMotif("Les heures validées sont fausses.")
        await contestation.envoyer()
        XCTAssertEqual(contestation.erreur, "Fenêtre de contestation fermée pour ce type de litige. Contactez le support.",
                       "refus du serveur affiché tel quel")
        XCTAssertTrue(contestation.formulaireOuvert, "refus : formulaire ouvert")
        XCTAssertEqual(contestation.etat, .contestable)

        contestation.saisirMotif(String(repeating: "é", count: 600))
        XCTAssertEqual(contestation.motif.unicodeScalars.count, 500, "saisie bornée comme le web (slice(0, 500))")
    }
}
