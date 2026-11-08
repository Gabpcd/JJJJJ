import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports de ces tests (hors du main actor : lu par les ports).
private let utilisateurPointage = AuthenticatedUser(id: "u-pointage", email: "u-pointage@example.invalid",
                                                    emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                    appMetadataRole: "SOIGNANT")

/// Modèle du bloc de pointage (lot 2, T3 ; blueprint §2.5, P6 niveau 1) : un envoi à la fois, base relue avant
/// l'envoi, reçu `prepared` → `started` avant l'unique requête, réponse ignorée si l'epoch change, délai `bounded` →
/// vérification par relecture sans renvoi, hors ligne → aucun appel et reçu `not_sent`, réconciliation au chargement.
@MainActor
final class PointageModelTests: XCTestCase {
    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurPointage }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw nonScripte }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    /// Port de pointage scripté : chaque liste de réponses est consommée dans l'ordre (la dernière se répète).
    private final class PortScripte: PointagePort, @unchecked Sendable {
        private let lock = NSLock()
        private var etats: [Result<EtatPointage, JoleneError>]
        private var scans: [IssueScan]
        private var reconciliations: [IssueScan]
        private var journal: [String] = []
        private var recusRecus: [RecuScan] = []
        private var metadonneesRecues: [MetadonneesScan] = []
        let preuves: [PreuveScan]
        let entreeScanner = Gate()
        let retenue: Gate?

        init(etats: [Result<EtatPointage, JoleneError>], scans: [IssueScan] = [.enregistre(typeScan: .ouverture, numeroScan: 1)],
             reconciliations: [IssueScan] = [.incertain], preuves: [PreuveScan] = [], retenue: Gate? = nil) {
            self.etats = etats; self.scans = scans; self.reconciliations = reconciliations; self.preuves = preuves
            self.retenue = retenue
        }

        var appels: [String] { lock.lock(); defer { lock.unlock() }; return journal }
        func compte(_ nom: String) -> Int { appels.filter { $0 == nom }.count }
        var recus: [RecuScan] { lock.lock(); defer { lock.unlock() }; return recusRecus }
        var metadonnees: [MetadonneesScan] { lock.lock(); defer { lock.unlock() }; return metadonneesRecues }

        private static func suivant<T>(_ liste: inout [T]) -> T {
            liste.count > 1 ? liste.removeFirst() : liste[0]
        }

        /// Sections critiques synchrones (verrou interdit dans un contexte asynchrone).
        private func noterEtat() -> Result<EtatPointage, JoleneError> {
            lock.lock(); defer { lock.unlock() }
            journal.append("etat")
            return Self.suivant(&etats)
        }

        private func noter(_ appel: String) {
            lock.lock(); defer { lock.unlock() }
            journal.append(appel)
        }

        private func noterScan(_ recu: RecuScan, _ metadonnees: MetadonneesScan) -> IssueScan {
            lock.lock(); defer { lock.unlock() }
            journal.append("scanner"); recusRecus.append(recu); metadonneesRecues.append(metadonnees)
            return Self.suivant(&scans)
        }

        private func noterReconciliation() -> IssueScan {
            lock.lock(); defer { lock.unlock() }
            journal.append("reconcilier")
            return Self.suivant(&reconciliations)
        }

        func etat(missionId: String, context: MissionReadContext) async throws -> EtatPointage {
            try noterEtat().get()
        }

        func preuvesScan(missionId: String, context: MissionReadContext) async throws -> [PreuveScan] {
            noter("preuves")
            return preuves
        }

        func scanner(code: String, metadonnees: MetadonneesScan, recu: RecuScan, context: MissionReadContext) async throws -> IssueScan {
            let issue = noterScan(recu, metadonnees)
            await entreeScanner.open()
            if let retenue { await retenue.wait() }
            return issue
        }

        func reconcilier(recu: RecuScan, context: MissionReadContext) async throws -> IssueScan {
            noterReconciliation()
        }

        func presences(context: MissionReadContext) async throws -> InstantanePresences { throw nonScripte }
        func consentementGps(context: MissionReadContext) async throws -> Bool? { throw nonScripte }
        func enregistrerConsentementGps(_ accepte: Bool, context: MissionReadContext) async throws -> Bool { throw nonScripte }
        func detail(missionId: String, context: MissionReadContext) async throws -> DetailPresences { throw nonScripte }
        func relancerValidation(missionId: String, context: MissionReadContext) async throws -> IssueRelance { throw nonScripte }
    }

    /// Horloge monotone et attentes du modèle, avancées par le test (aucune attente réelle).
    private final class TempsTest: @unchecked Sendable {
        private let lock = NSLock()
        private var instant: TimeInterval = 1_000
        private var demandes: [TimeInterval] = []
        func lire() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return instant }
        func attendre(_ duree: TimeInterval) { lock.lock(); demandes.append(duree); instant += max(0, duree); lock.unlock() }
        var attentes: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return demandes }
    }

    /// Magasin espion : phases écrites dans l'ordre, effacements comptés.
    private final class MagasinEspion: ReceiptStorePort, @unchecked Sendable {
        private let lock = NSLock()
        private let interne = MagasinRecusEnMemoire()
        private var ecrites: [String] = []
        var illisible = false
        func lire(_ cle: CleRecu) throws -> Data? {
            if illisible { return Data("pas un reçu".utf8) }
            return try interne.lire(cle)
        }
        func ecrire(_ donnees: Data, pour cle: CleRecu) throws {
            let phase = (try? JSONSerialization.jsonObject(with: donnees) as? [String: Any])?["phase"] as? String ?? "?"
            lock.lock(); ecrites.append(phase); lock.unlock()
            try interne.ecrire(donnees, pour: cle)
        }
        func effacer(_ cle: CleRecu) throws {
            lock.lock(); ecrites.append("effacé"); lock.unlock()
            try interne.effacer(cle)
        }
        var phases: [String] { lock.lock(); defer { lock.unlock() }; return ecrites }
        var vide: Bool { interne.cles().isEmpty }
    }

    private let mission = "m-1"
    private let terminal = DemoTerminalIdentity.identifiantDemo
    private let position = ObservationGps.disponible(latitude: 48.8566, longitude: 2.3522, precisionM: 12)

    private func etat(_ prochain: TypeScan = .ouverture, nbScans: Int = 0, statut: String = "ASSIGNEE") -> EtatPointage {
        EtatPointage(statut: statut, intitule: "Nuit", prochainTypeScan: prochain, nbScans: nbScans, segmentOuvert: prochain == .fermeture,
                     segments: [])
    }

    private func modele(_ port: PortScripte, magasin: MagasinEspion = MagasinEspion(), temps: TempsTest = TempsTest(),
                        reseau: ScenarioReseauDemo = .enLigne, timeout: TimeInterval = SessionController.defaultResolutionTimeout,
                        finLe: String? = "2026-11-02T08:05:00Z") async throws -> (PointageModel, SessionController) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.pointage = port
        let controller = SessionController(gateways: gateways, resolutionTimeout: timeout)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue")
        let appareil = Appareil(localisation: DemoLocationPort(scenario: .accorde), reseau: DemoNetworkPathPort(scenario: reseau),
                                terminal: DemoTerminalIdentity(), recus: magasin)
        let model = PointageModel(missionId: mission, finLe: finLe, controller: controller, snapshot: snapshot, appareil: appareil,
                                  attendre: { temps.attendre($0) }, monotone: { temps.lire() })
        return (model, controller)
    }

    private func journal(_ magasin: MagasinEspion) -> ReceiptJournal<RecuScan> { ReceiptJournal<RecuScan>(store: magasin) }

    // MARK: - Envoi

    func testSuccesRelitLaBaseEcritLeRecuPuisLEfface() async throws {
        let preuve = PreuveScan(id: "s-0", missionId: mission, numeroScan: 0, idTerminal: "TERM_IOS_AUTREAUTREAUTREAUTRE")
        let port = PortScripte(etats: [.success(etat()), .success(etat()), .success(etat(.fermeture, nbScans: 1, statut: "EN_COURS"))],
                               preuves: [preuve, PreuveScan(id: "autre", missionId: "m-2")])
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        XCTAssertEqual(model.etat, etat())
        XCTAssertTrue(model.peutEnvoyer)
        await model.pointer(code: " 123456 ", gps: position)
        XCTAssertEqual(model.issue, .enregistre(.ouverture))
        let appels = port.appels
        XCTAssertEqual(appels.count, 5)
        XCTAssertEqual(appels.first, "etat")
        XCTAssertEqual(Set(appels[1...2]), ["etat", "preuves"], "base relue avant l'envoi (en parallèle)")
        XCTAssertEqual(Array(appels.suffix(2)), ["scanner", "etat"], "état relu après le succès")
        XCTAssertEqual(model.etat?.prochainTypeScan, .fermeture, "nouvel état relu avant tout second scan")
        let recu = try XCTUnwrap(port.recus.first)
        XCTAssertEqual(recu.phase, .started)
        XCTAssertEqual(recu.preuvesAvant, ["s-0"], "base de la mission seulement")
        XCTAssertEqual(recu.nbScansAvant, 0)
        XCTAssertEqual(recu.typeAttendu, .ouverture)
        XCTAssertEqual(recu.gps, .disponible)
        XCTAssertEqual(recu.terminalId, terminal)
        XCTAssertEqual(port.metadonnees, [MetadonneesScan(idTerminal: terminal, observation: position)])
        XCTAssertEqual(magasin.phases, ["prepared", "started", "effacé"])
        XCTAssertTrue(magasin.vide)
        XCTAssertFalse(model.envoiEnCours)
        XCTAssertFalse(model.notationAProposer, "ouverture : jamais de note")
    }

    func testDoubleTapUnSeulAppel() async throws {
        let retenue = Gate()
        let port = PortScripte(etats: [.success(etat())], retenue: retenue)
        let (model, _) = try await modele(port)
        await model.charger()
        let premier = Task { await model.pointer(code: "123456", gps: nil) }
        await port.entreeScanner.wait()
        XCTAssertTrue(model.envoiEnCours)
        XCTAssertFalse(model.peutEnvoyer)
        await model.pointer(code: "123456", gps: nil)
        await retenue.open()
        await premier.value
        XCTAssertEqual(port.compte("scanner"), 1, "un envoi à la fois (web l.116)")
        XCTAssertEqual(model.issue, .enregistre(.ouverture))
        XCTAssertEqual(port.metadonnees.first?.latitude, nil, "position non demandée : aucune coordonnée")
    }

    func testReponseIgnoreeSiLEpochChange() async throws {
        let retenue = Gate()
        let port = PortScripte(etats: [.success(etat())], retenue: retenue)
        let magasin = MagasinEspion()
        let (model, controller) = try await modele(port, magasin: magasin)
        await model.charger()
        let envoi = Task { await model.pointer(code: "123456", gps: nil) }
        await port.entreeScanner.wait()
        _ = await controller.signOut()
        await retenue.open()
        await envoi.value
        XCTAssertNil(model.issue, "réponse d'un epoch périmé ignorée (web l.39)")
        XCTAssertEqual(magasin.phases, ["prepared", "started"], "reçu gardé : réconcilié au retour de l'utilisateur")
        XCTAssertEqual(port.compte("etat"), 2, "aucune relecture pour un epoch périmé")
    }

    func testDelaiDepasseVerificationPuisReconciliationSansRenvoi() async throws {
        let jamais = Gate()
        let port = PortScripte(etats: [.success(etat()), .success(etat()), .success(etat(.fermeture, nbScans: 1))],
                               reconciliations: [.incertain, .enregistre(typeScan: .ouverture, numeroScan: 1)], retenue: jamais)
        let temps = TempsTest()
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin, temps: temps, timeout: 0.2)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(port.compte("scanner"), 1, "jamais de renvoi")
        XCTAssertEqual(port.compte("reconcilier"), 2)
        XCTAssertEqual(temps.attentes.first, RecuScan.delaiAbsenceProuvee, "8 s monotones avant la première relecture")
        XCTAssertEqual(model.issue, .enregistre(.ouverture))
        XCTAssertTrue(magasin.vide)
        await jamais.open()
    }

    func testRelectureSansPreuveApresHuitSecondesNonRecu() async throws {
        let port = PortScripte(etats: [.success(etat())], scans: [.incertain], reconciliations: [.nonRecu])
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(model.issue, .nonRecu, "saisie du code courant demandée")
        XCTAssertEqual(port.compte("scanner"), 1)
        XCTAssertEqual(magasin.phases, ["prepared", "started", "effacé"])
        XCTAssertTrue(model.peutEnvoyer)
    }

    func testIncertainPersistantResteEnVerification() async throws {
        let port = PortScripte(etats: [.success(etat())], scans: [.incertain], reconciliations: [.incertain])
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(model.issue, .verification)
        XCTAssertEqual(port.compte("reconcilier"), PointageModel.maxRelectures)
        XCTAssertFalse(model.peutEnvoyer, "bouton désactivé tant que le reçu n'est pas réconcilié")
        XCTAssertEqual(magasin.phases, ["prepared", "started"])
        // Le suivi reprend la réconciliation, toujours sans renvoi.
        await model.rafraichir()
        XCTAssertEqual(port.compte("scanner"), 1)
        XCTAssertEqual(port.compte("reconcilier"), 2 * PointageModel.maxRelectures)
    }

    func testHorsLigneAucunAppelEtRecuNonEnvoye() async throws {
        let port = PortScripte(etats: [.success(etat())])
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin, reseau: .horsLigne)
        await model.charger()
        await model.pointer(code: "123456", gps: position)
        XCTAssertEqual(model.issue, .horsLigne)
        XCTAssertEqual(port.appels, ["etat"], "aucune requête hors ligne, aucune file")
        XCTAssertEqual(magasin.phases, ["prepared", "not_sent"])
        let recu = try await journal(magasin).lire(userId: utilisateurPointage.id)
        XCTAssertEqual(recu?.phase, .notSent)
        XCTAssertTrue(recu?.estTermine == true)
    }

    // MARK: - Refus

    func testRefusVerbatimRecuRefusePuisEfface() async throws {
        let port = PortScripte(etats: [.success(etat())], scans: [.refuse(sqlstate: "P0002", message: "Code de pointage invalide ou expiré.")])
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(model.issue, .refuse(message: "Code de pointage invalide ou expiré.", codeInvalide: true))
        XCTAssertEqual(magasin.phases, ["prepared", "started", "refused", "effacé"])
        XCTAssertEqual(Array(port.appels.suffix(2)), ["scanner", "etat"], "relecture après le refus, avant l'effacement")
        XCTAssertTrue(magasin.vide)
    }

    func testRefusSansSQLStateEfface() async throws {
        let port = PortScripte(etats: [.success(etat())],
                               scans: [.refuse(sqlstate: nil, message: "[CODE DU TRAVAIL] Repos insuffisant avant mission.")])
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(model.issue, .refuse(message: "[CODE DU TRAVAIL] Repos insuffisant avant mission.", codeInvalide: false))
        XCTAssertEqual(magasin.phases, ["prepared", "started", "effacé"])
    }

    func testAntiRejeuRelanceLaReconciliationEtProposeLaNote() async throws {
        let port = PortScripte(etats: [.success(etat(.fermeture, nbScans: 1, statut: "EN_COURS"))],
                               scans: [.refuse(sqlstate: "23514", message: "Scan déjà pris en compte. Prochain scan possible dans 87 secondes.")],
                               reconciliations: [.enregistre(typeScan: .fermeture, numeroScan: 2)])
        let (model, _) = try await modele(port, finLe: "2026-11-02T00:10:00Z")
        await model.charger()
        await model.pointer(code: "654321", gps: nil)
        XCTAssertEqual(model.issue, .enregistre(.fermeture), "un scan de ce terminal vient d'être enregistré")
        XCTAssertEqual(port.compte("scanner"), 1)
        XCTAssertEqual(port.compte("reconcilier"), 1)
        XCTAssertTrue(model.notationAProposer, "FERMETURE, fin prévue − 30 min atteinte (l.155-160)")
    }

    // MARK: - Réconciliation au chargement et garde-fous

    func testReconciliationAuChargementDUnReculDemarre() async throws {
        let magasin = MagasinEspion()
        let prepare = try RecuScan.preparer(userId: utilisateurPointage.id, epoch: 1, missionId: mission, terminalId: terminal,
                                            typeAttendu: .ouverture, nbScansAvant: 0, preuvesAvant: [], gps: .nonDemande)
        try await journal(magasin).ecrire(prepare)
        try await journal(magasin).ecrire(prepare.demarrer(le: DemoWorld.fixedNow))
        let port = PortScripte(etats: [.success(etat())], reconciliations: [.nonRecu])
        let temps = TempsTest()
        let (model, _) = try await modele(port, magasin: magasin, temps: temps)
        await model.charger()
        XCTAssertEqual(model.issue, .nonRecu)
        XCTAssertEqual(port.compte("scanner"), 0)
        XCTAssertTrue(temps.attentes.isEmpty, "essai d'un autre processus : verdict de l'horloge murale de la gateway")
        XCTAssertTrue(magasin.vide)
    }

    func testRecuPrepareOrphelinMarqueNonEnvoyePuisEfface() async throws {
        let magasin = MagasinEspion()
        try await journal(magasin).ecrire(RecuScan.preparer(userId: utilisateurPointage.id, epoch: 1, missionId: mission,
                                                            terminalId: terminal, typeAttendu: .ouverture, nbScansAvant: 0,
                                                            preuvesAvant: [], gps: .nonDemande))
        let port = PortScripte(etats: [.success(etat())])
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        XCTAssertEqual(magasin.phases, ["prepared", "not_sent", "effacé"], "aucune requête n'est partie avant `started`")
        XCTAssertEqual(port.compte("reconcilier"), 0)
        XCTAssertNil(model.issue)
    }

    func testRecuEnCoursBloqueUnNouvelEnvoi() async throws {
        let magasin = MagasinEspion()
        let autre = try RecuScan.preparer(userId: utilisateurPointage.id, epoch: 1, missionId: "m-2", terminalId: terminal,
                                          typeAttendu: .ouverture, nbScansAvant: 0, preuvesAvant: [], gps: .nonDemande)
        try await journal(magasin).ecrire(autre)
        try await journal(magasin).ecrire(autre.demarrer(le: DemoWorld.fixedNow))
        let port = PortScripte(etats: [.success(etat())])
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        // La réconciliation du reçu de m-2 reste incertaine : le pointage de m-1 est bloqué.
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(model.issue, .recuEnCours)
        XCTAssertEqual(port.compte("scanner"), 0)
    }

    func testJournalIllisibleBloqueSansEnvoi() async throws {
        let magasin = MagasinEspion()
        magasin.illisible = true
        let port = PortScripte(etats: [.success(etat())])
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        XCTAssertEqual(model.issue, .suiviIllisible)
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(model.issue, .suiviIllisible)
        XCTAssertEqual(port.compte("scanner"), 0)
        XCTAssertTrue(magasin.phases.isEmpty, "un reçu illisible n'est jamais réécrit ni effacé")
    }

    func testEtatRefuseVerbatimEtAucunEnvoi() async throws {
        let port = PortScripte(etats: [.failure(JoleneError(.unknown, "Accès interdit"))])
        let (model, _) = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.chargement, .indisponible("Accès interdit"))
        XCTAssertFalse(model.peutEnvoyer)
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(port.compte("scanner"), 0)
    }

    func testCodeIllisibleOuStatutNonPointableNEnvoieRien() async throws {
        let port = PortScripte(etats: [.success(etat(statut: "TERMINEE"))])
        let (model, _) = try await modele(port)
        await model.charger()
        XCTAssertFalse(model.peutEnvoyer, "statut non pointable (l.94)")
        await model.pointer(code: "12345", gps: nil)
        XCTAssertEqual(port.appels, ["etat"], "code de cinq chiffres : rien n'est envoyé")
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(port.compte("scanner"), 0, "statut relu non pointable : aucun envoi")
    }
}
