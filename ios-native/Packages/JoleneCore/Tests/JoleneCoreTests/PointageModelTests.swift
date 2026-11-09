import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports de ces tests (hors du main actor : lu par les ports).
private let utilisateurPointage = AuthenticatedUser(id: "u-pointage", email: "u-pointage@example.invalid",
                                                    emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                    appMetadataRole: "SOIGNANT")

/// Modèle du bloc de pointage (lot 2, T3 ; blueprint §2.5, P6 niveau 1) : un envoi à la fois, base relue avant
/// l'envoi, reçu `prepared` → `started` avant l'unique requête, réponse ignorée si l'epoch change ou si l'écran a
/// disparu (génération), délai `bounded` → vérification par relecture sans renvoi, hors ligne → aucun appel et reçu
/// `not_sent`, réconciliation au chargement. Revue fraîche de T3 : un HTTP 200 n'aboutit jamais à « non reçu » (M-A),
/// le bloc redevient opérant après une réapparition (M-B), session expirée signalée (m1), attente du pool (m2).
@MainActor
final class PointageModelTests: XCTestCase {
    private struct PretAuth: AuthPort {
        var utilisateur = utilisateurPointage
        func restoreSession() async throws -> AuthenticatedUser? { utilisateur }
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
        /// Levée par `scanner` après l'avoir compté (session expirée, m1).
        let erreurScan: JoleneError?
        /// Levée par `reconcilier` après l'avoir compté.
        let erreurReconciliation: JoleneError?

        init(etats: [Result<EtatPointage, JoleneError>], scans: [IssueScan] = [.enregistre(typeScan: .ouverture, numeroScan: 1)],
             reconciliations: [IssueScan] = [.incertain], preuves: [PreuveScan] = [], retenue: Gate? = nil,
             erreurScan: JoleneError? = nil, erreurReconciliation: JoleneError? = nil) {
            self.etats = etats; self.scans = scans; self.reconciliations = reconciliations; self.preuves = preuves
            self.retenue = retenue; self.erreurScan = erreurScan; self.erreurReconciliation = erreurReconciliation
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
            if let erreurScan { throw erreurScan }
            return issue
        }

        func reconcilier(recu: RecuScan, context: MissionReadContext) async throws -> IssueScan {
            let verdict = noterReconciliation()
            if let erreurReconciliation { throw erreurReconciliation }
            return verdict
        }

        func presences(context: MissionReadContext) async throws -> InstantanePresences { throw nonScripte }
        func consentementGps(context: MissionReadContext) async throws -> Bool? { throw nonScripte }
        func enregistrerConsentementGps(_ accepte: Bool, context: MissionReadContext) async throws -> Bool { throw nonScripte }
        func detail(missionId: String, context: MissionReadContext) async throws -> DetailPresences { throw nonScripte }
        func relancerValidation(missionId: String, context: MissionReadContext) async throws -> IssueRelance { throw nonScripte }
    }

    /// Port dont la requête et les relectures d'un HTTP 200 sont séparées, comme `SupabasePointageGateway` (seconde
    /// revue fraîche de T3, mi-1) : `envoyerScan` rend `.accepte` après `dureeEnvoi`, `relireScanAccepte` rend `relecture`
    /// après `dureeRelecture` (ou jamais, tant que `retenueRelecture` est fermée).
    private final class PortEnDeuxTemps: PointagePort, @unchecked Sendable {
        private let lock = NSLock()
        private var journal: [String] = []
        let scan: ScanEnregistre?
        let dureeEnvoi: TimeInterval
        let dureeRelecture: TimeInterval
        let relecture: IssueScan
        let retenueRelecture: Gate?

        init(scan: ScanEnregistre?, dureeEnvoi: TimeInterval = 0, dureeRelecture: TimeInterval = 0, relecture: IssueScan,
             retenueRelecture: Gate? = nil) {
            self.scan = scan; self.dureeEnvoi = dureeEnvoi; self.dureeRelecture = dureeRelecture; self.relecture = relecture
            self.retenueRelecture = retenueRelecture
        }

        func compte(_ nom: String) -> Int { lock.lock(); defer { lock.unlock() }; return journal.filter { $0 == nom }.count }
        private func noter(_ appel: String) { lock.lock(); journal.append(appel); lock.unlock() }

        func etat(missionId: String, context: MissionReadContext) async throws -> EtatPointage {
            noter("etat")
            return EtatPointage(statut: "ASSIGNEE", intitule: "Nuit", prochainTypeScan: .ouverture, nbScans: 0, segmentOuvert: false,
                                segments: [])
        }
        func preuvesScan(missionId: String, context: MissionReadContext) async throws -> [PreuveScan] { noter("preuves"); return [] }
        func envoyerScan(code: String, metadonnees: MetadonneesScan, recu: RecuScan, context: MissionReadContext) async throws -> EnvoiScan {
            noter("envoyerScan")
            await PointageModel.attendreReellement(dureeEnvoi)
            return .accepte(scan)
        }
        func relireScanAccepte(_ scan: ScanEnregistre?, recu: RecuScan, context: MissionReadContext) async throws -> IssueScan {
            noter("relireScanAccepte")
            if let retenueRelecture { await retenueRelecture.wait() }
            await PointageModel.attendreReellement(dureeRelecture)
            return relecture
        }
        func scanner(code: String, metadonnees: MetadonneesScan, recu: RecuScan, context: MissionReadContext) async throws -> IssueScan {
            noter("scanner")
            throw nonScripte
        }
        func reconcilier(recu: RecuScan, context: MissionReadContext) async throws -> IssueScan { noter("reconcilier"); return .nonRecu }
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

    /// Attentes du suivi rendues une à une par le test (aucune attente réelle) : `tic()` libère la plus ancienne.
    private actor Metronome {
        private(set) var durees: [TimeInterval] = []
        private var enAttente: [CheckedContinuation<Void, Never>] = []

        func attendre(_ duree: TimeInterval) async {
            durees.append(duree)
            await withCheckedContinuation { enAttente.append($0) }
        }

        func tic() {
            guard !enAttente.isEmpty else { return }
            enAttente.removeFirst().resume()
        }

        /// Revient dès qu'une attente est en cours.
        func attenteEnCours() async {
            while enAttente.isEmpty { await Task.yield() }
        }
    }

    /// Session, instantané et appareil partagés par les blocs d'un même écran (un journal de reçus par utilisateur).
    private struct Banc {
        let controller: SessionController
        let snapshot: SessionSnapshot
        let appareil: Appareil
    }

    private func nouveauBanc(_ port: any PointagePort, utilisateur: AuthenticatedUser = utilisateurPointage,
                      magasin: MagasinEspion = MagasinEspion(), reseau: ScenarioReseauDemo = .enLigne,
                      timeout: TimeInterval = SessionController.defaultResolutionTimeout) async throws -> Banc {
        var gateways = Gateways(auth: PretAuth(utilisateur: utilisateur), role: NeutralRole(), missions: PretMissions(),
                                clock: FixedClock(DemoWorld.fixedNow))
        gateways.pointage = port
        let controller = SessionController(gateways: gateways, resolutionTimeout: timeout)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue")
        let appareil = Appareil(localisation: DemoLocationPort(scenario: .accorde), reseau: DemoNetworkPathPort(scenario: reseau),
                                terminal: DemoTerminalIdentity(), recus: magasin)
        return Banc(controller: controller, snapshot: snapshot, appareil: appareil)
    }

    private func bloc(_ mission: String, _ banc: Banc, temps: TempsTest = TempsTest(), finLe: String? = "2026-11-02T08:05:00Z",
                      attendre: (@Sendable (TimeInterval) async -> Void)? = nil) -> PointageModel {
        PointageModel(missionId: mission, finLe: finLe, controller: banc.controller, snapshot: banc.snapshot, appareil: banc.appareil,
                      attendre: attendre ?? { temps.attendre($0) }, monotone: { temps.lire() })
    }

    private func modele(_ port: PortScripte, magasin: MagasinEspion = MagasinEspion(), temps: TempsTest = TempsTest(),
                        reseau: ScenarioReseauDemo = .enLigne, timeout: TimeInterval = SessionController.defaultResolutionTimeout,
                        finLe: String? = "2026-11-02T08:05:00Z",
                        attendre: (@Sendable (TimeInterval) async -> Void)? = nil) async throws -> (PointageModel, SessionController) {
        let banc = try await nouveauBanc(port, magasin: magasin, reseau: reseau, timeout: timeout)
        return (bloc(mission, banc, temps: temps, finLe: finLe, attendre: attendre), banc.controller)
    }

    /// Attente minimale avant un verdict « non reçu » d'un essai sorti sans réponse après `ecoule` secondes (m2).
    private func attenteNonRecu(apres ecoule: TimeInterval) -> TimeInterval {
        ecoule + PointageModel.attentePoolPostgREST + RecuScan.delaiAbsenceProuvee
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
        // m2 : sorti par le délai `bounded`, la requête a pu attendre le pool PostgREST (10 s) puis s'exécuter (8 s).
        XCTAssertEqual(try XCTUnwrap(temps.attentes.first), attenteNonRecu(apres: 0.2), accuracy: 1e-9,
                       "relecture immédiate sans preuve, puis délai `bounded` + 10 s + 8 s monotones avant la suivante (mi-2)")
        XCTAssertEqual(model.issue, .enregistre(.ouverture))
        XCTAssertTrue(magasin.vide)
        await jamais.open()
    }

    func testRelectureSansPreuveApresHuitSecondesNonRecu() async throws {
        let port = PortScripte(etats: [.success(etat())], scans: [.incertain], reconciliations: [.nonRecu])
        let magasin = MagasinEspion()
        let temps = TempsTest()
        let (model, _) = try await modele(port, magasin: magasin, temps: temps)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(try XCTUnwrap(temps.attentes.first), attenteNonRecu(apres: 0), accuracy: 1e-9,
                       "réponse perdue : attente du pool et du `statement_timeout` avant le verdict « non reçu » (m2, mi-2)")
        XCTAssertEqual(model.issue, .nonRecu, "saisie du code courant demandée")
        XCTAssertEqual(port.compte("scanner"), 1)
        XCTAssertEqual(magasin.phases, ["prepared", "started", "effacé"])
        XCTAssertTrue(model.peutEnvoyer)
    }

    /// Seconde revue fraîche de T3 (mi-2) : relecture immédiate après une réponse perdue (blueprint §2.5) ; une preuve
    /// déjà présente est confirmée sans attendre le délai du « non reçu ».
    func testPreuveDejaPresenteConfirmeeSansAttente() async throws {
        let port = PortScripte(etats: [.success(etat()), .success(etat()), .success(etat(.fermeture, nbScans: 1, statut: "EN_COURS"))],
                               scans: [.incertain], reconciliations: [.enregistre(typeScan: .ouverture, numeroScan: 1)])
        let temps = TempsTest()
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin, temps: temps)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(model.issue, .enregistre(.ouverture))
        XCTAssertTrue(temps.attentes.isEmpty, "aucune attente avant la première relecture")
        XCTAssertEqual(port.compte("reconcilier"), 1)
        XCTAssertTrue(magasin.vide)
    }

    /// mi-2 : un « non reçu » relu avant la fin de l'attente monotone reste « à relire » ; pendant l'attente, l'envoi est
    /// terminé (`charger()` relit l'état) et aucune seconde réconciliation ne part en parallèle.
    func testNonRecuAvantLeDelaiARelireHorsEnvoi() async throws {
        let port = PortScripte(etats: [.success(etat())], scans: [.incertain],
                               reconciliations: [.nonRecu, .enregistre(typeScan: .ouverture, numeroScan: 1)])
        let metronome = Metronome()
        let (model, _) = try await modele(port, attendre: { await metronome.attendre($0) })
        await model.charger()
        let envoi = Task { await model.pointer(code: "123456", gps: nil) }
        await metronome.attenteEnCours()
        XCTAssertFalse(model.envoiEnCours, "envoi terminé : seule la vérification attend")
        XCTAssertEqual(model.issue, .verification)
        XCTAssertFalse(model.peutEnvoyer)
        XCTAssertEqual(port.compte("reconcilier"), 1, "relecture immédiate")
        let lectures = port.compte("etat")
        await model.charger()
        XCTAssertEqual(port.compte("etat"), lectures + 1, "état relu pendant l'attente")
        XCTAssertEqual(port.compte("reconcilier"), 1, "aucune seconde réconciliation en parallèle")
        let durees = await metronome.durees
        XCTAssertEqual(try XCTUnwrap(durees.first), attenteNonRecu(apres: 0), accuracy: 1e-9, "reste de l'attente du « non reçu » (m2)")
        await metronome.tic()
        await envoi.value
        XCTAssertEqual(model.issue, .enregistre(.ouverture), "« non reçu » trop tôt : relu, puis preuve trouvée")
        XCTAssertEqual(port.compte("scanner"), 1)
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

    // MARK: - HTTP 200 sur une autre mission (revue fraîche de T3, M-A)

    func testCodeDUneAutreMissionEnregistreLaBasJamaisNonRecu() async throws {
        let port = PortScripte(etats: [.success(etat())],
                               scans: [.enregistreSurAutreMission(missionId: "m-2", typeScan: .ouverture, numeroScan: 1)],
                               reconciliations: [.nonRecu])
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(model.issue, .enregistreSurAutreMission(.ouverture, missionId: "m-2"), "mission réellement pointée signalée")
        XCTAssertEqual(port.compte("reconcilier"), 0, "un HTTP 200 n'est jamais réconcilié sur la mission du reçu")
        XCTAssertEqual(Array(port.appels.suffix(2)), ["scanner", "etat"], "état de ce bloc relu")
        XCTAssertEqual(magasin.phases, ["prepared", "started", "effacé"], "essai soldé : aucun reçu en cours pour les autres blocs")
        XCTAssertFalse(model.notationAProposer, "la note est celle de la mission pointée (T5a)")
        XCTAssertTrue(model.peutEnvoyer)
        await model.rafraichir()
        XCTAssertEqual(model.issue, .enregistreSurAutreMission(.ouverture, missionId: "m-2"), "aucun « non reçu » ensuite")
        XCTAssertEqual(port.compte("scanner"), 1)
    }

    func testAccepteSansPreuveSuiviIllisibleJamaisNonRecu() async throws {
        let port = PortScripte(etats: [.success(etat())], scans: [.accepteSansPreuve], reconciliations: [.nonRecu])
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(model.issue, .suiviIllisible, "COMMIT prouvé, mission non établie : renvoi web, jamais « non reçu »")
        XCTAssertEqual(port.compte("reconcilier"), 0)
        XCTAssertEqual(magasin.phases, ["prepared", "started", "effacé"],
                       "soldé : une réconciliation filtrée sur la mission du reçu conclurait à tort « non reçu »")
        XCTAssertFalse(model.peutEnvoyer)
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(port.compte("scanner"), 1, "aucun nouveau scan depuis ce bloc")
        await model.rafraichir()
        XCTAssertEqual(model.issue, .suiviIllisible, "même génération : le message reste affiché")
        XCTAssertEqual(port.compte("reconcilier"), 0)
        // Seconde revue fraîche de T3 (mi-3) : levé par le premier `charger()` réussi après une réapparition du bloc
        // (onglet rouvert, écran rechargé au retour du renvoi web) ; l'état est relu et un nouvel envoi relit sa base.
        model.desactiver()
        await model.charger()
        XCTAssertNil(model.issue, "réapparition : état relu, bloc de nouveau opérant")
        XCTAssertTrue(model.peutEnvoyer)
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(port.compte("scanner"), 2, "nouvel envoi, base relue")
        XCTAssertEqual(port.compte("reconcilier"), 0, "un HTTP 200 n'est jamais réconcilié")
    }

    // MARK: - Reçu commun soldé par un autre bloc (seconde revue fraîche de T3, MJ-1)

    /// Blocs A (`m-1`) et B (`m-2`) du même écran, sur le même journal (un reçu par utilisateur) et la même horloge
    /// monotone ; A envoie un scan dont la réponse est perdue, puis ses relectures ne concluent pas.
    private func blocsAvecAEnSuivi(scans: [IssueScan] = [.incertain], reconciliations: [IssueScan]) async throws
        -> (a: PointageModel, b: PointageModel, port: PortScripte, magasin: MagasinEspion) {
        let port = PortScripte(etats: [.success(etat())], scans: scans, reconciliations: reconciliations)
        let magasin = MagasinEspion()
        let temps = TempsTest()
        let banc = try await nouveauBanc(port, magasin: magasin)
        let a = bloc(mission, banc, temps: temps)
        let b = bloc("m-2", banc, temps: temps)
        await a.charger()
        await b.charger()
        await a.pointer(code: "123456", gps: nil)
        return (a, b, port, magasin)
    }

    private var relecturesSansConclusion: [IssueScan] {
        Array(repeating: IssueScan.incertain, count: PointageModel.maxRelectures)
    }

    func testRecuSoldeParUnAutreBlocEnregistreLeveLaVerification() async throws {
        let (a, b, port, magasin) = try await blocsAvecAEnSuivi(
            reconciliations: relecturesSansConclusion + [.enregistre(typeScan: .ouverture, numeroScan: 1)])
        XCTAssertEqual(a.issue, .verification, "relectures sans conclusion : A attend")
        XCTAssertFalse(a.peutEnvoyer)
        await b.reconcilier()
        XCTAssertTrue(magasin.vide, "reçu commun soldé par la réconciliation du bloc B")
        XCTAssertNil(b.issue, "B ne publie rien pour l'essai de la mission m-1")
        await a.rafraichir()
        XCTAssertNotEqual(a.issue, .verification, "A n'est plus figé en vérification")
        XCTAssertEqual(a.issue, .enregistre(.ouverture), "issue conclue par B rendue au bloc de la mission du reçu")
        XCTAssertTrue(a.peutEnvoyer)
        XCTAssertEqual(port.compte("scanner"), 1, "aucun second scan")
    }

    func testRecuSoldeParUnAutreBlocNonRecuLeveLaVerification() async throws {
        let (a, b, port, magasin) = try await blocsAvecAEnSuivi(reconciliations: relecturesSansConclusion + [.nonRecu])
        XCTAssertEqual(a.issue, .verification)
        await b.reconcilier()
        XCTAssertTrue(magasin.vide)
        XCTAssertNil(b.issue)
        await a.rafraichir()
        XCTAssertEqual(a.issue, .nonRecu, "saisie du code courant demandée au bloc A")
        XCTAssertTrue(a.peutEnvoyer)
        XCTAssertEqual(port.compte("scanner"), 1)
    }

    /// `.suiviIllisible` venu de la réconciliation (heure de l'appareil reculée) : le reçu reste `started` ; quand B le
    /// solde (horloge revenue), A reprend la main.
    func testSuiviIllisibleDeReconciliationSoldeParUnAutreBlocLeve() async throws {
        let (a, b, port, magasin) = try await blocsAvecAEnSuivi(reconciliations: [.horlogeIncoherente, .nonRecu])
        XCTAssertEqual(a.issue, .suiviIllisible, "horloge incohérente : suivi non vérifiable")
        XCTAssertFalse(a.peutEnvoyer)
        await b.reconcilier()
        XCTAssertTrue(magasin.vide)
        XCTAssertNil(b.issue)
        await a.rafraichir()
        XCTAssertEqual(a.issue, .nonRecu)
        XCTAssertTrue(a.peutEnvoyer)
        XCTAssertEqual(port.compte("scanner"), 1)
    }

    /// Reçu disparu sans issue transmise : la vérification est levée (l'état vient d'être relu ; tout nouvel envoi relit
    /// sa base), jamais un succès supposé.
    func testRecuDisparuSansIssueTransmiseLeveLaVerification() async throws {
        let (a, _, port, magasin) = try await blocsAvecAEnSuivi(reconciliations: [.incertain])
        XCTAssertEqual(a.issue, .verification)
        let recu = try await journal(magasin).lire(userId: utilisateurPointage.id)
        try await journal(magasin).effacer(XCTUnwrap(recu))
        await a.rafraichir()
        XCTAssertNil(a.issue)
        XCTAssertTrue(a.peutEnvoyer)
        XCTAssertEqual(port.compte("scanner"), 1)
    }

    /// Le reçu de A toujours en attente : A reste en vérification (aucune levée prématurée).
    func testRecuToujoursEnAttenteGardeLaVerification() async throws {
        let (a, b, _, magasin) = try await blocsAvecAEnSuivi(reconciliations: [.incertain])
        await b.reconcilier()
        XCTAssertFalse(magasin.vide)
        await a.rafraichir()
        XCTAssertEqual(a.issue, .verification)
        XCTAssertFalse(a.peutEnvoyer)
        XCTAssertNil(b.issue, "B n'affiche pas la vérification de l'essai de A")
    }

    // MARK: - Requête et relectures d'un HTTP 200 bornées à part (seconde revue fraîche de T3, mi-1)

    private let scanAccepte = ScanEnregistre(typeScanEffectue: .ouverture, prochainTypeScan: .fermeture, creneauEffectifId: "c-1",
                                             horodatageEffectif: nil, horodatageArrondi: nil, numeroScan: 1, validationEtabRequise: false)

    /// Requête puis relectures, chacune sous le délai, leur somme au-delà : un HTTP 200 tardif reste un succès relu.
    func testHTTP200TardifPuisRelecturesSousLeDelaiChacuneSuccesRelu() async throws {
        let port = PortEnDeuxTemps(scan: scanAccepte, dureeEnvoi: 0.6, dureeRelecture: 0.6,
                                   relecture: .enregistreSurAutreMission(missionId: "m-2", typeScan: .ouverture, numeroScan: 1))
        let magasin = MagasinEspion()
        let banc = try await nouveauBanc(port, magasin: magasin, timeout: 1.0)
        let model = bloc(mission, banc)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(model.issue, .enregistreSurAutreMission(.ouverture, missionId: "m-2"),
                       "1,2 s en tout pour un délai de 1 s : jamais « incertain », jamais « non reçu »")
        XCTAssertEqual(port.compte("envoyerScan"), 1)
        XCTAssertEqual(port.compte("relireScanAccepte"), 1)
        XCTAssertEqual(port.compte("reconcilier"), 0, "un HTTP 200 n'est jamais réconcilié")
        XCTAssertEqual(port.compte("scanner"), 0, "le modèle appelle les deux moitiés")
        XCTAssertTrue(magasin.vide)
    }

    /// Relectures hors délai après un HTTP 200 : accepté sans preuve (suivi non vérifiable), reçu soldé, aucune
    /// réconciliation ni « non reçu ».
    func testRelecturesApresHTTP200HorsDelaiAccepteSansPreuve() async throws {
        let jamais = Gate()
        let port = PortEnDeuxTemps(scan: scanAccepte, relecture: .enregistre(typeScan: .ouverture, numeroScan: 1), retenueRelecture: jamais)
        let magasin = MagasinEspion()
        let banc = try await nouveauBanc(port, magasin: magasin, timeout: 0.2)
        let model = bloc(mission, banc)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(model.issue, .suiviIllisible, "COMMIT prouvé, mission non établie")
        XCTAssertEqual(port.compte("reconcilier"), 0)
        XCTAssertEqual(magasin.phases, ["prepared", "started", "effacé"], "reçu soldé : aucun « non reçu » ensuite")
        await jamais.open()
    }

    func testDemoCodeDeLaMissionASaisiDansLeBlocB() async throws {
        let magasin = MagasinEspion()
        let banc = try await nouveauBanc(DemoPointageGateway(), utilisateur: DemoWorld.user, magasin: magasin)
        let blocA = bloc("demo-presence-a", banc)
        let blocB = bloc("demo-presence-b", banc)
        await blocA.charger()
        await blocB.charger()
        XCTAssertEqual(blocA.etat?.nbScans, 0)
        XCTAssertEqual(blocB.etat?.prochainTypeScan, .fermeture)
        await blocB.pointer(code: "123456", gps: nil)
        XCTAssertEqual(blocB.issue, .enregistreSurAutreMission(.ouverture, missionId: "demo-presence-a"),
                       "le code de la mission a pointe la mission a (horloge fixe : jamais bloqué en vérification)")
        XCTAssertEqual(blocB.etat?.nbScans, 1, "mission b inchangée")
        XCTAssertEqual(blocB.etat?.prochainTypeScan, .fermeture)
        XCTAssertTrue(magasin.vide, "reçu soldé")
        XCTAssertTrue(blocB.peutEnvoyer)
        await blocA.rafraichir()
        XCTAssertEqual(blocA.etat?.nbScans, 1, "le scan est sur la mission a")
        XCTAssertEqual(blocA.etat?.statut, "EN_COURS")
        XCTAssertTrue(blocA.peutEnvoyer, "aucun « reçu en cours » ne bloque l'autre bloc")
    }

    // MARK: - Disparition et réapparition de l'écran (revue fraîche de T3, M-B et m7)

    func testReponseIgnoreeApresDesactiverPuisBlocDeNouveauOperant() async throws {
        let retenue = Gate()
        let port = PortScripte(etats: [.success(etat()), .success(etat()), .success(etat(.fermeture, nbScans: 1, statut: "EN_COURS"))],
                               scans: [.enregistre(typeScan: .ouverture, numeroScan: 1), .enregistre(typeScan: .fermeture, numeroScan: 2)],
                               retenue: retenue)
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        let envoi = Task { await model.pointer(code: "123456", gps: nil) }
        await port.entreeScanner.wait()
        model.desactiver()
        XCTAssertFalse(model.peutEnvoyer)
        // Réapparition pendant l'envoi : réactivé, mais aucune lecture en parallèle de l'envoi (m7).
        await model.charger()
        XCTAssertEqual(port.compte("etat"), 2, "charger() gardé pendant un envoi")
        await retenue.open()
        await envoi.value
        XCTAssertNil(model.issue, "réponse émise avant la disparition : ignorée")
        XCTAssertEqual(magasin.phases, ["prepared", "started", "effacé"], "essai décidé par le serveur : reçu soldé quand même")
        // Seconde revue fraîche de T3 (mi-4) : le bloc réactivé pendant l'envoi (son `charger()` a sauté la lecture)
        // relit son état dans la génération courante dès la fin de l'envoi, sans attendre le tic de 15 s.
        XCTAssertEqual(port.compte("etat"), 3, "état relu pour le bloc réactivé")
        XCTAssertEqual(model.etat?.prochainTypeScan, .fermeture, "aucun état ni libellé périmé")
        // De nouveau opérant : charger, puis pointer.
        await model.charger()
        XCTAssertEqual(model.etat?.prochainTypeScan, .fermeture)
        XCTAssertTrue(model.peutEnvoyer)
        await model.pointer(code: "654321", gps: nil)
        XCTAssertEqual(port.compte("scanner"), 2)
        XCTAssertEqual(model.issue, .enregistre(.fermeture))
    }

    /// mi-4 : réponse perdue pendant la disparition, bloc réactivé avant la fin de l'envoi : le reçu `started` est
    /// réconcilié dans la génération courante (la réponse elle-même reste ignorée).
    func testReponsePerduePendantLaDisparitionReconcilieeApresReactivation() async throws {
        let retenue = Gate()
        let port = PortScripte(etats: [.success(etat())], scans: [.incertain],
                               reconciliations: [.enregistre(typeScan: .ouverture, numeroScan: 1)], retenue: retenue)
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        let envoi = Task { await model.pointer(code: "123456", gps: nil) }
        await port.entreeScanner.wait()
        model.desactiver()
        await model.charger()
        await retenue.open()
        await envoi.value
        XCTAssertEqual(port.compte("reconcilier"), 1, "réconcilié par le bloc réactivé")
        XCTAssertEqual(model.issue, .enregistre(.ouverture), "relecture de la génération courante")
        XCTAssertTrue(magasin.vide)
        XCTAssertEqual(port.compte("scanner"), 1)
    }

    func testDesactiverSansReactivationRendLeBlocInerte() async throws {
        let port = PortScripte(etats: [.success(etat())])
        let (model, _) = try await modele(port)
        await model.charger()
        model.desactiver()
        await model.pointer(code: "123456", gps: nil)
        await model.reconcilier()
        XCTAssertEqual(port.compte("scanner"), 0, "écran disparu : aucun envoi")
        XCTAssertEqual(port.appels, ["etat"])
        model.activer()
        XCTAssertTrue(model.peutEnvoyer, "réactivé sans relecture : l'état connu reste affiché")
    }

    func testSuivreToutesLesQuinzeSecondesEtArretALAnnulation() async throws {
        let port = PortScripte(etats: [.success(etat())])
        let metronome = Metronome()
        let (model, _) = try await modele(port, attendre: { await metronome.attendre($0) })
        await model.charger()
        let suivi = Task { await model.suivre() }
        await metronome.attenteEnCours()
        XCTAssertEqual(port.compte("etat"), 1)
        await metronome.tic()
        await metronome.attenteEnCours()
        XCTAssertEqual(port.compte("etat"), 2, "un tic : une relecture")
        let durees = await metronome.durees
        XCTAssertEqual(durees, [PointageModel.intervalleSuivi, PointageModel.intervalleSuivi])
        XCTAssertEqual(PointageModel.intervalleSuivi, 15, "`refetchInterval: 15000` du web (l.71)")
        suivi.cancel()
        await metronome.tic()
        await suivi.value
        XCTAssertEqual(port.compte("etat"), 2, "annulé : plus aucune relecture")
    }

    func testDesactiverArreteLeSuiviQuiRepartApresReapparition() async throws {
        let port = PortScripte(etats: [.success(etat())])
        let metronome = Metronome()
        let (model, _) = try await modele(port, attendre: { await metronome.attendre($0) })
        await model.charger()
        let suivi = Task { await model.suivre() }
        await metronome.attenteEnCours()
        model.desactiver()
        await metronome.tic()
        await suivi.value
        XCTAssertEqual(port.compte("etat"), 1, "écran disparu : suivi arrêté")
        // Réapparition : `charger()` puis `suivre()` (consigne T4b).
        await model.charger()
        XCTAssertEqual(port.compte("etat"), 2)
        let reprise = Task { await model.suivre() }
        await metronome.attenteEnCours()
        await metronome.tic()
        await metronome.attenteEnCours()
        XCTAssertEqual(port.compte("etat"), 3, "suivi de nouveau opérant")
        reprise.cancel()
        await metronome.tic()
        await reprise.value
    }

    // MARK: - Session expirée (revue fraîche de T3, m1)

    func testSessionExpireeAuScanSignaleeRecuGardeSansRenvoi() async throws {
        let port = PortScripte(etats: [.success(etat())], erreurScan: JoleneError(.unauthorized, "session expirée (test)"))
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertTrue(model.sessionExpired, "session expirée signalée, jamais un refus métier")
        XCTAssertEqual(model.issue, .verification)
        XCTAssertEqual(port.compte("reconcilier"), 0, "aucune relecture sans session")
        XCTAssertEqual(magasin.phases, ["prepared", "started"], "reçu gardé : réconcilié au retour de l'utilisateur")
        XCTAssertEqual(port.compte("scanner"), 1)
    }

    func testSessionExpireePendantLaReconciliationSignaleeAussitot() async throws {
        let port = PortScripte(etats: [.success(etat())], scans: [.incertain],
                               erreurReconciliation: JoleneError(.unauthorized, "session expirée (test)"))
        let magasin = MagasinEspion()
        let (model, _) = try await modele(port, magasin: magasin)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertTrue(model.sessionExpired, "signalée dès la relecture, sans attendre le tic de 15 s")
        XCTAssertEqual(port.compte("reconcilier"), 1, "relectures arrêtées")
        XCTAssertEqual(model.issue, .verification)
        XCTAssertEqual(magasin.phases, ["prepared", "started"])
    }

    // MARK: - Session expirée : bloc « Session à vérifier » de la zone (revue fraîche de T4b, M1)

    /// Bloc dont l'instantané est celui du `SessionStore` (revalidé par « Vérifier ma session »).
    private func blocAvecSession(_ port: PortScripte, magasin: MagasinEspion = MagasinEspion())
        async throws -> (PointageModel, SessionStore, ConsentementGpsModel) {
        let banc = try await nouveauBanc(port, magasin: magasin)
        let store = SessionStore(controller: banc.controller)
        await store.start()
        let snapshot = try XCTUnwrap(store.state.snapshot)
        let model = bloc(mission, Banc(controller: banc.controller, snapshot: snapshot, appareil: banc.appareil))
        return (model, store, ConsentementGpsModel(controller: banc.controller, snapshot: snapshot))
    }

    func testSessionExpireeAuScanAfficheLaVerificationDeSessionPuisReconcilieApresRevalidation() async throws {
        let port = PortScripte(etats: [.success(etat())], reconciliations: [.enregistre(typeScan: .ouverture, numeroScan: 1)],
                               erreurScan: JoleneError(.unauthorized, "session expirée (test)"))
        let magasin = MagasinEspion()
        let (model, store, consentement) = try await blocAvecSession(port, magasin: magasin)
        await model.charger()
        await model.pointer(code: "123456", gps: nil)
        XCTAssertEqual(model.issue, .verification)
        XCTAssertEqual(AffichageZonePointage(pointage: model, consentement: consentement), .sessionAVerifier,
                       "401 au scan : jamais « Vérification du pointage… » sans fin, le bloc de reconnexion du lot 1")
        await model.verifierSession(store, consentement: consentement)
        XCTAssertFalse(model.sessionExpired, "session revalidée, même identité : état relu")
        XCTAssertEqual(port.compte("reconcilier"), 1, "le reçu gardé est réconcilié par relecture")
        XCTAssertEqual(port.compte("scanner"), 1, "jamais de renvoi du code")
        XCTAssertEqual(model.issue, .enregistre(.ouverture))
        XCTAssertEqual(AffichageZonePointage(pointage: model, consentement: consentement), .saisie(etat()))
        XCTAssertTrue(magasin.vide, "reçu soldé après la relecture")
    }

    func testSessionExpireeAuChargementAfficheLaVerificationDeSessionEtNonLIndisponibilite() async throws {
        let port = PortScripte(etats: [.failure(JoleneError(.unauthorized, SessionController.sessionExpiredMessage)), .success(etat())])
        let (model, store, consentement) = try await blocAvecSession(port)
        await model.charger()
        XCTAssertTrue(model.sessionExpired)
        XCTAssertEqual(AffichageZonePointage(pointage: model, consentement: consentement), .sessionAVerifier,
                       "un « Réessayer » ne peut rien réparer : la session est à vérifier")
        await model.verifierSession(store, consentement: consentement)
        XCTAssertEqual(AffichageZonePointage(pointage: model, consentement: consentement), .saisie(etat()))
        XCTAssertEqual(port.compte("etat"), 2)
    }

    func testVerifierSessionSousUneAutreIdentiteNeRelitRien() async throws {
        let port = PortScripte(etats: [.failure(JoleneError(.unauthorized, SessionController.sessionExpiredMessage)), .success(etat())])
        let (model, store, consentement) = try await blocAvecSession(port)
        await model.charger()
        await store.signOut()
        await model.verifierSession(store, consentement: consentement)
        XCTAssertEqual(port.compte("etat"), 1, "nouvel epoch : la zone est reconstruite, ce bloc ne relit rien")
    }
}
