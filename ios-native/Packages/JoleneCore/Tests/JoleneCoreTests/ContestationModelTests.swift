import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurContestation = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                        emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                        appMetadataRole: "SOIGNANT")

/// Contestation d'une présence (lot 2, T5b, HARD STOP n°4 ; décision 9, D12) : bouton seulement si la présence est
/// validée, sans litige, et si le serveur dit la fenêtre ouverte ; toute erreur de lecture masque le panneau
/// (fail-closed) ; un litige existant n'affiche que son statut ; refus serveur verbatim, puis plus de bouton ; erreur de
/// transport ou délai dépassé : feuille ouverte avec le message, envoi verrouillé pendant la relecture ; motif nettoyé
/// comme `sanitizeText` et borné.
@MainActor
final class ContestationModelTests: XCTestCase {
    private struct PortError: Error {}

    private final class Port: ContestationPort, @unchecked Sendable {
        private let lock = NSLock()
        /// Réponses successives de `litige` (la dernière est reprise une fois la liste épuisée).
        var lectures: [Result<LitigePresence?, Error>] = [.success(nil)]
        var fenetre: Result<Bool, Error> = .success(true)
        var issue: Result<IssueContestation, Error> = .success(.ouverte(LitigePresence(id: "l-1", statut: "OUVERT")))
        /// Envoi en vol tant que le test n'ouvre pas `sortie` (délai dépassé : jamais ouverte).
        var porteEnvoi: Gate?
        /// Relecture en vol (après l'envoi) : `entree` ouverte par le port, `sortie` attendue.
        var porteRelecture: (entree: Gate, sortie: Gate)?
        private(set) var lecturesFenetre = 0
        private(set) var lecturesLitige = 0
        private(set) var envois: [(missionId: String, presenceId: String, motif: String)] = []

        func litige(presenceId: String, context: MissionReadContext) async throws -> LitigePresence? {
            let (reponse, porte) = lock.withLock { () -> (Result<LitigePresence?, Error>, (entree: Gate, sortie: Gate)?) in
                lecturesLitige += 1
                let reponse = lectures.count > 1 ? lectures.removeFirst() : lectures[0]
                return (reponse, envois.isEmpty ? nil : porteRelecture)
            }
            if let porte {
                await porte.entree.open()
                await porte.sortie.wait()
            }
            return try reponse.get()
        }

        func fenetreOuverte(missionId: String, context: MissionReadContext) async throws -> Bool {
            try lock.withLock { () -> Result<Bool, Error> in lecturesFenetre += 1; return fenetre }.get()
        }

        func contester(missionId: String, presenceId: String, motif: String,
                       context: MissionReadContext) async throws -> IssueContestation {
            let (reponse, porte) = lock.withLock { () -> (Result<IssueContestation, Error>, Gate?) in
                envois.append((missionId, presenceId, motif))
                return (issue, porteEnvoi)
            }
            if let porte { await porte.wait() }
            return try reponse.get()
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

    private func model(_ port: Port, valideLe: String? = "2026-11-01T14:00:00Z",
                       delai: TimeInterval = SessionController.defaultResolutionTimeout) async throws -> ContestationModel {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.contestation = port
        let controller = SessionController(gateways: gateways, resolutionTimeout: delai)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return ContestationModel(presenceId: "p-1", missionId: "m-1", valideLe: valideLe, controller: controller, snapshot: snapshot)
    }

    /// Modèle chargé, formulaire ouvert, motif valide saisi.
    private func pretAEnvoyer(_ port: Port, delai: TimeInterval = SessionController.defaultResolutionTimeout) async throws -> ContestationModel {
        let contestation = try await model(port, delai: delai)
        await contestation.charger()
        contestation.ouvrirFormulaire()
        contestation.saisirMotif("Les heures validées sont fausses.")
        XCTAssertTrue(contestation.peutEnvoyer)
        return contestation
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
        litigeIllisible.lectures = [.failure(PortError())]
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
        port.lectures = [.success(LitigePresence(id: "l-9", statut: "EN_MEDIATION", presenceId: "p-1"))]
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

    func testRefusServeurVerbatimPuisPlusDeBoutonEtMotifTropCourtSansRequete() async throws {
        let refus = "Fenêtre de contestation fermée pour ce type de litige. Contactez le support."
        let port = Port()
        port.issue = .success(.refusee(message: refus))
        let contestation = try await model(port)
        await contestation.charger()
        contestation.ouvrirFormulaire()
        contestation.saisirMotif("<i>court</i>")
        await contestation.envoyer()
        XCTAssertEqual(contestation.erreur, "Le motif doit contenir entre 10 et 2 000 caractères.")
        XCTAssertTrue(port.envois.isEmpty, "motif nettoyé sous 10 caractères : aucune requête")
        XCTAssertEqual(contestation.etat, .contestable, "borne locale : la saisie reste corrigeable")

        contestation.saisirMotif("Les heures validées sont fausses.")
        await contestation.envoyer()
        XCTAssertEqual(contestation.erreur, refus, "refus du serveur affiché tel quel")
        XCTAssertTrue(contestation.formulaireOuvert, "refus lu dans la feuille")
        XCTAssertEqual(contestation.etat, .refusee(refus))
        XCTAssertFalse(contestation.peutEnvoyer, "refus du serveur : plus d'envoi (revue B8, m3)")
        contestation.annuler()
        contestation.ouvrirFormulaire()
        XCTAssertFalse(contestation.formulaireOuvert, "plus de « Contester » après un refus")
        XCTAssertEqual(contestation.etat, .refusee(refus), "le panneau garde le refus du serveur")
        XCTAssertEqual(port.envois.count, 1)

        contestation.saisirMotif(String(repeating: "é", count: 600))
        XCTAssertEqual(contestation.motif.unicodeScalars.count, 500, "saisie bornée comme le web (slice(0, 500))")
    }

    // MARK: - Erreur de transport (revue B8, M1)

    func testErreurReseauPuisLitigeReluAfficheLeStatut() async throws {
        let port = Port()
        port.issue = .failure(JoleneError(.network, "Connexion impossible. Vérifiez votre réseau puis réessayez."))
        port.lectures = [.success(nil), .success(LitigePresence(id: "l-2", statut: "OUVERT", presenceId: "p-1"))]
        let contestation = try await pretAEnvoyer(port)
        await contestation.envoyer()
        XCTAssertEqual(contestation.litige?.id, "l-2", "contestation reçue malgré la réponse perdue : statut relu")
        XCTAssertEqual(contestation.libelleStatut, "Ouvert")
        XCTAssertFalse(contestation.formulaireOuvert)
        XCTAssertNil(contestation.erreur)
        XCTAssertEqual(port.envois.count, 1, "jamais de renvoi")
    }

    func testErreurReseauPuisRelectureEnEchecGardeLaFeuilleOuverteEtVerrouilleLEnvoi() async throws {
        let port = Port()
        port.issue = .failure(PortError())
        port.lectures = [.success(nil), .failure(PortError())]
        let relecture = (entree: Gate(), sortie: Gate())
        port.porteRelecture = relecture
        let contestation = try await pretAEnvoyer(port)
        let envoi = Task { await contestation.envoyer() }
        await relecture.entree.wait()
        XCTAssertFalse(contestation.peutEnvoyer, "« Envoyer » verrouillé pendant la relecture")
        XCTAssertTrue(contestation.envoiEnCours)
        XCTAssertEqual(contestation.erreur, LibellesDetailPresences.Contestation.erreurEnvoi)
        await relecture.sortie.open()
        await envoi.value
        XCTAssertTrue(contestation.formulaireOuvert, "relecture en échec : la feuille reste ouverte")
        XCTAssertEqual(contestation.etat, .contestable)
        XCTAssertEqual(contestation.erreur, "La contestation n'a pas pu être envoyée. Réessayez.")
        XCTAssertTrue(contestation.peutEnvoyer, "après la relecture : nouvel essai possible")
        XCTAssertEqual(port.envois.count, 1, "une seule requête")
        XCTAssertEqual(port.lecturesLitige, 2, "chargement puis relecture")
    }

    func testDelaiDepasseGardeLaFeuilleOuverteAvecLeMessage() async throws {
        let port = Port()
        port.porteEnvoi = Gate() // jamais ouverte : la réponse n'arrive pas
        let contestation = try await pretAEnvoyer(port, delai: 0.3)
        await contestation.envoyer()
        XCTAssertEqual(contestation.erreur, SessionController.timeoutMessage)
        XCTAssertTrue(contestation.formulaireOuvert)
        XCTAssertEqual(contestation.etat, .contestable)
        XCTAssertFalse(contestation.envoiEnCours)
        XCTAssertEqual(port.envois.count, 1)
        XCTAssertEqual(port.lecturesLitige, 2, "relecture après le délai dépassé")
    }

    // MARK: - Nettoyage du motif (revue B8, M2) et messages serveur (m6)

    func testNettoyageNeRetireQueLesBalises() {
        let intact = "Arrivée 7h<8h prévues, départ 19h -> 2h non comptées"
        XCTAssertEqual(ContestationModel.nettoyer(intact), intact, "« <8h » et « -> » sont du texte (sanitizeText)")
        let surDeuxLignes = "Arrivée réelle < 7h\nDépart 19h -> validé 17h, écart de 2h"
        XCTAssertEqual(ContestationModel.nettoyer(surDeuxLignes), surDeuxLignes)
        XCTAssertEqual(ContestationModel.nettoyer(" <p>Heures <b>fausses</b></p><!-- x --> "), "Heures fausses")
        XCTAssertEqual(ContestationModel.nettoyer("a </i> b"), "a  b")
    }

    func testMessagesServeurPresentsDansLeDump() throws {
        let dump = try String(contentsOf: Lot3PortsTests.dumpURL, encoding: .utf8)
        for message in MessagesContestationServeur.tous {
            XCTAssertTrue(dump.contains("'" + message + "'"), "« \(message) » absent de supabase/schema/public.sql")
        }
    }
}
