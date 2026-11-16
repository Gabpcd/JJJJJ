import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurPaiements = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                     emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                     appMetadataRole: "SOIGNANT")

/// Modèle des paiements déclarés (lot 3, T13, B9 ; liste de tests du blueprint §3 T13) :
/// - confirmer → succès seulement sur `.confirme` (relecture `CONFIRME` faite par le port), liste relue, onglet prévenu ;
/// - refus serveur `{error:'Paiement déjà confirmé'}` affiché verbatim, liste relue, jamais un succès ;
/// - contestation sans motif impossible (aucun appel), repli du web jamais envoyé ;
/// - `{success, litige_id}` sans relecture `CONTESTE` (le port lève « Erreur lors du traitement ») → erreur ;
/// - double tap impossible (une seule mutation en vol, boutons désactivés jusqu'à la relecture) ;
/// - 23505 non restituée (le port lève l'erreur générique) → message, jamais un succès ;
/// - délai dépassé → message, relecture, aucun renvoi ; epoch périmé → rien n'est publié.
@MainActor
final class PaiementsDeclaresModelTests: XCTestCase {
    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurPaiements }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw nonScripte }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    /// Port scripté : files de réponses, journal des appels ; `retenue` retient la mutation jusqu'à son ouverture.
    private final class ScriptedPaiements: PaiementsDeclaresPort, @unchecked Sendable {
        private let lock = NSLock()
        private var listes: [Result<[PaiementDeclare], Error>]
        private var mutations: [Result<IssuePaiement, Error>]
        private var journal: [String] = []
        var retenue: Gate?

        init(listes: [Result<[PaiementDeclare], Error>], mutations: [Result<IssuePaiement, Error>] = []) {
            self.listes = listes; self.mutations = mutations
        }

        var appels: [String] { lock.lock(); defer { lock.unlock() }; return journal }

        private func noter(_ appel: String) { lock.lock(); journal.append(appel); lock.unlock() }

        private func suivante<V>(_ file: inout [Result<V, Error>]) -> Result<V, Error> {
            lock.lock(); defer { lock.unlock() }
            return file.isEmpty ? .failure(nonScripte) : file.removeFirst()
        }

        func aConfirmer(context: MissionReadContext) async throws -> [PaiementDeclare] {
            noter("liste")
            return try suivante(&listes).get()
        }

        func confirmer(id: String, context: MissionReadContext) async throws -> IssuePaiement {
            noter("confirmer \(id)")
            if let retenue { await retenue.wait() }
            return try suivante(&mutations).get()
        }

        func contester(id: String, motif: String, context: MissionReadContext) async throws -> IssuePaiement {
            noter("contester \(id) « \(motif) »")
            if let retenue { await retenue.wait() }
            return try suivante(&mutations).get()
        }
    }

    private static func declare(_ id: String, statut: String = "DECLARE", confirme: Bool = false,
                                conteste: Bool = false) -> PaiementDeclare {
        PaiementDeclare(id: id, missionId: "m-\(id)", etablissementId: "e-1", montantNet: 162.4, methode: "VIREMENT",
                        statut: statut, confirmeParSoignant: confirme, conteste: conteste, etablissementNom: "Clinique")
    }

    private func pret(_ port: ScriptedPaiements,
                      delai: TimeInterval = SessionController.defaultResolutionTimeout) async throws -> (SessionController, SessionSnapshot) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.paiements = port
        let controller = SessionController(gateways: gateways, resolutionTimeout: delai)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return (controller, snapshot)
    }

    // MARK: - Lecture

    func testLectureEtSectionAbsenteSansPaiement() async throws {
        let port = ScriptedPaiements(listes: [.success([]), .success([Self.declare("p-1")])])
        let (controller, snapshot) = try await pret(port)
        let model = PaiementsDeclaresModel(controller: controller, snapshot: snapshot)
        XCTAssertFalse(model.afficheSection, "rien pendant la première lecture (web : null)")
        await model.chargerSiNecessaire(peremption: 0)
        XCTAssertEqual(model.etat, .pret([]))
        XCTAssertFalse(model.afficheSection, "aucun paiement : rien n'est rendu (`return null`, l.216)")
        await model.chargerSiNecessaire(peremption: 0)
        XCTAssertEqual(port.appels, ["liste"], "lu il y a moins de 60 s : pas de relecture")
        await model.chargerSiNecessaire(peremption: 1)
        XCTAssertEqual(model.cartes.map(\.id), ["p-1"], "jeton de péremption (tap PAIEMENT_RECU) : relecture")
        XCTAssertTrue(model.afficheSection)
    }

    func testEchecDeLectureMessageEtReprise() async throws {
        let port = ScriptedPaiements(listes: [.failure(JoleneError(.unknown, PaiementsDeclaresTextes.erreurChargement)),
                                              .success([Self.declare("p-1")])])
        let (controller, snapshot) = try await pret(port)
        let model = PaiementsDeclaresModel(controller: controller, snapshot: snapshot)
        await model.chargerSiNecessaire()
        XCTAssertEqual(model.etat, .echec("Impossible de charger les paiements à confirmer."))
        XCTAssertTrue(model.afficheSection)
        await model.chargerSiNecessaire()
        XCTAssertEqual(port.appels, ["liste"], "un échec attend « Réessayer »")
        await model.charger()
        XCTAssertEqual(model.cartes.map(\.id), ["p-1"])
    }

    // MARK: - Confirmer

    func testConfirmerAnnonceLeSuccesApresRelectureEtRelitLaListe() async throws {
        let relue = Self.declare("p-1", statut: "CONFIRME", confirme: true)
        let port = ScriptedPaiements(listes: [.success([Self.declare("p-1"), Self.declare("p-2")]), .success([Self.declare("p-2")])],
                                     mutations: [.success(.confirme(relue))])
        let (controller, snapshot) = try await pret(port)
        let model = PaiementsDeclaresModel(controller: controller, snapshot: snapshot)
        await model.charger()
        model.basculer("p-1")
        XCTAssertEqual(model.deplie, "p-1")

        await model.confirmer("p-1")

        XCTAssertEqual(model.issue, .confirme)
        XCTAssertEqual(model.cartes.map(\.id), ["p-2"], "carte retirée parce que le serveur ne la rend plus")
        XCTAssertNil(model.deplie, "carte disparue : plus rien de déplié")
        XCTAssertNil(model.enCours)
        XCTAssertEqual(model.miseAJour, 1, "l'onglet relit ses missions (onUpdate du web)")
        XCTAssertEqual(port.appels, ["liste", "confirmer p-1", "liste"])
    }

    func testRefusServeurVerbatimPaiementDejaConfirmeJamaisUnSucces() async throws {
        let port = ScriptedPaiements(listes: [.success([Self.declare("p-1")]), .success([])],
                                     mutations: [.success(.refuse(message: "Paiement déjà confirmé"))])
        let (controller, snapshot) = try await pret(port)
        let model = PaiementsDeclaresModel(controller: controller, snapshot: snapshot)
        await model.charger()
        await model.confirmer("p-1")
        XCTAssertEqual(model.issue, .erreur("Paiement déjà confirmé"), "message serveur verbatim")
        XCTAssertNotEqual(model.issue, .confirme)
        XCTAssertEqual(model.etat, .pret([]), "liste relue après le refus (confirmé ailleurs)")
        XCTAssertTrue(model.afficheSection, "l'issue reste affichée sans carte")
        XCTAssertEqual(model.miseAJour, 1)
    }

    /// Délai dépassé : le serveur a peut-être agi — message, relecture, aucun renvoi.
    func testDelaiDepasseRelitSansRenvoyer() async throws {
        let port = ScriptedPaiements(listes: [.success([Self.declare("p-1")]), .success([Self.declare("p-1")])],
                                     mutations: [.success(.confirme(Self.declare("p-1", statut: "CONFIRME", confirme: true)))])
        let gate = Gate()
        port.retenue = gate
        let (controller, snapshot) = try await pret(port, delai: 0.2)
        let model = PaiementsDeclaresModel(controller: controller, snapshot: snapshot)
        await model.charger()
        await model.confirmer("p-1")
        await gate.open()
        XCTAssertEqual(model.issue, .erreur(SessionController.timeoutMessage))
        XCTAssertEqual(port.appels.filter { $0.hasPrefix("confirmer") }.count, 1, "jamais renvoyée")
        XCTAssertEqual(port.appels.last, "liste", "relecture après un délai dépassé")
    }

    // MARK: - Double tap

    func testDoubleTapImpossibleUneSeuleMutationEnVol() async throws {
        let port = ScriptedPaiements(listes: [.success([Self.declare("p-1"), Self.declare("p-2")]), .success([Self.declare("p-2")])],
                                     mutations: [.success(.confirme(Self.declare("p-1", statut: "CONFIRME", confirme: true)))])
        let gate = Gate()
        port.retenue = gate
        let (controller, snapshot) = try await pret(port)
        let model = PaiementsDeclaresModel(controller: controller, snapshot: snapshot)
        await model.charger()

        let premier = Task { await model.confirmer("p-1") }
        while !port.appels.contains("confirmer p-1") { await Task.yield() }
        XCTAssertEqual(model.enCours, "p-1", "bouton désactivé pendant l'appel")
        await model.confirmer("p-1")      // second tap sur la même carte
        await model.confirmer("p-2")      // tap sur une autre carte
        model.basculerContestation("p-2") // ouverture d'un formulaire
        XCTAssertNil(model.contestation)
        XCTAssertFalse(model.peutEnvoyerContestation)
        await gate.open()
        await premier.value

        XCTAssertEqual(port.appels.filter { $0.hasPrefix("confirmer") }, ["confirmer p-1"], "une seule mutation envoyée")
        XCTAssertEqual(model.issue, .confirme)
        XCTAssertNil(model.enCours)
    }

    // MARK: - Contester

    func testContestationSansMotifImpossibleEtRepliDuWebJamaisEnvoye() async throws {
        let port = ScriptedPaiements(listes: [.success([Self.declare("p-1")])])
        let (controller, snapshot) = try await pret(port)
        let model = PaiementsDeclaresModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertFalse(model.peutEnvoyerContestation, "formulaire fermé")
        model.basculerContestation("p-1")
        XCTAssertEqual(model.contestation, "p-1")
        for blanc in ["", "   ", " \n\t "] {
            model.saisirMotif(blanc)
            XCTAssertFalse(model.peutEnvoyerContestation, "motif « \(blanc) » : `disabled={!motif.trim()}`")
            await model.envoyerContestation()
        }
        XCTAssertEqual(port.appels, ["liste"], "aucun appel sans motif, jamais le repli 'Contesté par le soignant'")
        model.basculerContestation("p-1")
        XCTAssertNil(model.contestation, "« Contester » referme le formulaire (l.402)")
        model.basculerContestation("p-1")
        XCTAssertEqual(model.motif, "", "un nouveau formulaire part d'un motif vide")
        model.saisirMotif(String(repeating: "x", count: 600))
        XCTAssertEqual(model.motif.unicodeScalars.count, 500, "maxLength 500 (l.58)")
        model.annulerContestation()
        XCTAssertNil(model.contestation)
        XCTAssertEqual(model.motif, "")
    }

    func testContestationEnvoieLeMotifSaisiEtAnnonceApresRelecture() async throws {
        let relue = Self.declare("p-1", statut: "CONTESTE", conteste: true)
        let port = ScriptedPaiements(listes: [.success([Self.declare("p-1")]), .success([])],
                                     mutations: [.success(.conteste(relue, litigeId: "l-1"))])
        let (controller, snapshot) = try await pret(port)
        let model = PaiementsDeclaresModel(controller: controller, snapshot: snapshot)
        await model.charger()
        model.basculerContestation("p-1")
        model.saisirMotif("  Montant erroné ")
        XCTAssertTrue(model.peutEnvoyerContestation)
        await model.envoyerContestation()
        XCTAssertEqual(port.appels, ["liste", "contester p-1 «   Montant erroné  »", "liste"], "motif tel que saisi (btrim serveur)")
        XCTAssertEqual(model.issue, .conteste)
        XCTAssertNil(model.contestation)
        XCTAssertEqual(model.motif, "")
        XCTAssertEqual(model.miseAJour, 1)
    }

    /// `{success, litige_id}` sans relecture `CONTESTE` : le port lève « Erreur lors du traitement » — jamais un succès ;
    /// le formulaire et le motif restent (le web ne referme qu'en cas de succès, l.197).
    func testSuccesSansRelectureCONTESTEEstUneErreur() async throws {
        let port = ScriptedPaiements(listes: [.success([Self.declare("p-1")]), .success([Self.declare("p-1")])],
                                     mutations: [.failure(JoleneError(.unknown, PaiementsDeclaresTextes.erreurTraitement))])
        let (controller, snapshot) = try await pret(port)
        let model = PaiementsDeclaresModel(controller: controller, snapshot: snapshot)
        await model.charger()
        model.basculerContestation("p-1")
        model.saisirMotif("Montant erroné")
        await model.envoyerContestation()
        XCTAssertEqual(model.issue, .erreur("Erreur lors du traitement"))
        XCTAssertNotEqual(model.issue, .conteste)
        XCTAssertEqual(model.contestation, "p-1")
        XCTAssertEqual(model.motif, "Montant erroné")
        XCTAssertEqual(model.cartes.map(\.id), ["p-1"], "la carte reste tant que le serveur la rend")
    }

    /// 23505 (violation d'unicité non restituée par B3) : message générique de la gateway, jamais un succès ; le refus
    /// `LITIGE_DEJA_OUVERT` de B3 est, lui, affiché verbatim.
    func testUnicite23505EtLitigeDejaOuvertJamaisUnSucces() async throws {
        let port = ScriptedPaiements(
            listes: [.success([Self.declare("p-1")]), .success([Self.declare("p-1")]), .success([Self.declare("p-1")])],
            mutations: [.failure(JoleneError(.unknown, PaiementsDeclaresTextes.erreurTraitement)),
                        .success(.refuse(message: "Un litige de ce type est déjà ouvert pour cette mission."))])
        let (controller, snapshot) = try await pret(port)
        let model = PaiementsDeclaresModel(controller: controller, snapshot: snapshot)
        await model.charger()
        model.basculerContestation("p-1")
        model.saisirMotif("Montant erroné")
        await model.envoyerContestation()
        XCTAssertEqual(model.issue, .erreur("Erreur lors du traitement"))
        await model.envoyerContestation()
        XCTAssertEqual(model.issue, .erreur("Un litige de ce type est déjà ouvert pour cette mission."))
        XCTAssertEqual(model.numeroIssue, 2, "chaque issue est réannoncée")
        XCTAssertEqual(port.appels.filter { $0.hasPrefix("contester") }.count, 2, "un envoi par tap, aucun renvoi automatique")
    }

    // MARK: - Epoch

    func testMutationDUnEpochPerimeNePublieRien() async throws {
        let port = ScriptedPaiements(listes: [.success([Self.declare("p-1")])],
                                     mutations: [.success(.confirme(Self.declare("p-1", statut: "CONFIRME", confirme: true)))])
        let gate = Gate()
        port.retenue = gate
        let (controller, snapshot) = try await pret(port)
        let model = PaiementsDeclaresModel(controller: controller, snapshot: snapshot)
        await model.charger()
        let mutation = Task { await model.confirmer("p-1") }
        while !port.appels.contains("confirmer p-1") { await Task.yield() }
        _ = await controller.signOut()
        await gate.open()
        await mutation.value
        XCTAssertNil(model.issue, "identité changée pendant l'appel : rien n'est publié")
        XCTAssertEqual(port.appels, ["liste", "confirmer p-1"], "aucune relecture pour une autre identité")
    }
}
