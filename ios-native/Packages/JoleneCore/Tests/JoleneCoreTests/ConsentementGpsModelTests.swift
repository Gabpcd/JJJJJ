import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports de ces tests (hors du main actor : lu par les ports).
private let utilisateurConsentement = AuthenticatedUser(id: "u-consentement", email: "u-consentement@example.invalid",
                                                        emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                        appMetadataRole: "SOIGNANT")

/// Consentement GPS (lot 2, T4b ; décision 4, correction 15) : la feuille verbatim s'ouvre au premier pointage quand
/// `soignants.consentement_gps` est NULL ; « Autoriser » → `fn_consentir_gps(true)` puis relecture puis audit
/// `RGPD_CONSENTEMENT_DONNE` (parité `PresencesSoignant.tsx` l.58-96), puis seulement l'autorisation iOS ; « Je refuse »
/// → `false`, bandeau, pointage sans GPS, aucune autorisation iOS ; un échec de la RPC ne fait aucune hypothèse locale ;
/// retrait et réactivation depuis le Profil → `fn_consentir_gps(actif)` puis relecture, sans audit `GPS_CONSENTEMENT_*`
/// (absent du CHECK). Aucun texte produit par le modèle : l'écran lit `TextesWeb`.
@MainActor
final class ConsentementGpsModelTests: XCTestCase {
    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurConsentement }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw nonScripte }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    /// Port de pointage dont seul le consentement répond : valeur serveur en mémoire, échecs scriptés, journal ordonné.
    private final class PortConsentement: PointagePort, @unchecked Sendable {
        private let lock = NSLock()
        private var valeur: Bool?
        private var lectures: [JoleneError?]
        private let erreurEnregistrement: JoleneError?
        private var trace: [String] = []
        /// Valeur que le serveur retient, quelle que soit la demande (relecture ≠ hypothèse).
        private let valeurImposee: Bool?
        /// Ouverte quand `fn_consentir_gps` est en vol ; `retenue` la garde en vol tant que le test ne l'ouvre pas.
        let entreeEnregistrement = Gate()
        let retenue: Gate?

        init(valeur: Bool?, lectures: [JoleneError?] = [nil], erreurEnregistrement: JoleneError? = nil, valeurImposee: Bool? = nil,
             retenue: Gate? = nil) {
            self.valeur = valeur; self.lectures = lectures; self.erreurEnregistrement = erreurEnregistrement
            self.valeurImposee = valeurImposee; self.retenue = retenue
        }

        /// Nombre d'appels `fn_consentir_gps` reçus.
        var enregistrements: Int { journal.filter { $0.hasPrefix("fn_consentir_gps") }.count }

        var journal: [String] { lock.lock(); defer { lock.unlock() }; return trace }

        private func noterLecture() -> Result<Bool?, JoleneError> {
            lock.lock(); defer { lock.unlock() }
            trace.append("lire")
            let erreur = lectures.count > 1 ? lectures.removeFirst() : lectures[0]
            if let erreur { return .failure(erreur) }
            return .success(valeur)
        }

        private func noterEnregistrement(_ accepte: Bool) -> Result<Bool, JoleneError> {
            lock.lock(); defer { lock.unlock() }
            trace.append("fn_consentir_gps(\(accepte))")
            if let erreurEnregistrement { return .failure(erreurEnregistrement) }
            valeur = valeurImposee ?? accepte
            trace.append("relire")
            return .success(valeur ?? false)
        }

        func consentementGps(context: MissionReadContext) async throws -> Bool? { try noterLecture().get() }
        func enregistrerConsentementGps(_ accepte: Bool, context: MissionReadContext) async throws -> Bool {
            let resultat = noterEnregistrement(accepte)
            await entreeEnregistrement.open()
            if let retenue { await retenue.wait() }
            return try resultat.get()
        }

        func presences(context: MissionReadContext) async throws -> InstantanePresences { throw nonScripte }
        func etat(missionId: String, context: MissionReadContext) async throws -> EtatPointage { throw nonScripte }
        func scanner(code: String, metadonnees: MetadonneesScan, recu: RecuScan, context: MissionReadContext) async throws -> IssueScan {
            throw nonScripte
        }
        func reconcilier(recu: RecuScan, context: MissionReadContext) async throws -> IssueScan { throw nonScripte }
        func detail(missionId: String, context: MissionReadContext) async throws -> DetailPresences { throw nonScripte }
        func relancerValidation(missionId: String, context: MissionReadContext) async throws -> IssueRelance { throw nonScripte }
    }

    /// Audit espion : action, ressource et détails de chaque écriture, dans l'ordre.
    private actor JournalAudit {
        private(set) var ecritures: [String] = []
        func noter(_ entree: String) { ecritures.append(entree) }
    }

    private struct AuditEspion: AuditPort {
        let journal = JournalAudit()
        var erreur: JoleneError?
        /// Ouverte quand l'audit est en vol ; `retenue` le garde en vol tant que le test ne l'ouvre pas (m2).
        let entree = Gate()
        var retenue: Gate?

        func connexion() async throws -> AuditResultat { .enregistre }
        func deconnexion() async throws -> AuditResultat { .enregistre }
        func activite() async throws -> AuditResultat { .enregistre }
        func ecrire(action: AuditAction, typeRessource: String, idRessource: String, details: [String: String],
                    context: MissionReadContext) async throws -> AuditResultat {
            let detail = details.keys.sorted().map { "\($0)=\(details[$0] ?? "")" }.joined(separator: ",")
            await journal.noter("\(action.rawValue) \(typeRessource) \(idRessource) \(detail)")
            await entree.open()
            if let retenue { await retenue.wait() }
            if let erreur { throw erreur }
            return .enregistre
        }
    }

    private func modele(_ port: PortConsentement, audit: AuditEspion = AuditEspion()) async throws -> (ConsentementGpsModel, SessionController) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.pointage = port
        gateways.audit = audit
        let controller = SessionController(gateways: gateways)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue")
        return (ConsentementGpsModel(controller: controller, snapshot: snapshot), controller)
    }

    // MARK: - Lecture

    func testConsentementNulOuvreLaFeuilleEtLaisseLInterrupteurEteint() async throws {
        let (model, _) = try await modele(PortConsentement(valeur: nil))
        XCTAssertEqual(model.etat, .chargement)
        XCTAssertEqual(model.decision, .sansGps, "non lu : jamais de position supposée")
        await model.charger()
        XCTAssertEqual(model.etat, .lu(nil))
        XCTAssertNil(model.valeur)
        XCTAssertEqual(model.decision, .recueillir, "NULL : feuille de consentement avant le premier pointage (décision 4)")
        XCTAssertFalse(model.bandeauSansGps, "le bandeau ne suit qu'un refus (`consentementGPS === false`, l.509)")
        XCTAssertFalse(model.interrupteurActif, "NULL n'est jamais affiché comme un consentement donné (décision déléguée)")
    }

    func testConsentementVraiLocaliseEtFauxAfficheLeBandeau() async throws {
        let (accorde, _) = try await modele(PortConsentement(valeur: true))
        await accorde.charger()
        XCTAssertEqual(accorde.decision, .localiser)
        XCTAssertTrue(accorde.interrupteurActif)
        XCTAssertFalse(accorde.bandeauSansGps)

        let (refuse, _) = try await modele(PortConsentement(valeur: false))
        await refuse.charger()
        XCTAssertEqual(refuse.decision, .sansGps)
        XCTAssertTrue(refuse.bandeauSansGps)
        XCTAssertFalse(refuse.interrupteurActif)
    }

    func testLectureEnEchecNeSupposeRienEtGardeLeMessage() async throws {
        let (model, _) = try await modele(PortConsentement(valeur: true, lectures: [JoleneError(.network, "Réseau indisponible.")]))
        await model.charger()
        XCTAssertEqual(model.etat, .indisponible("Réseau indisponible."))
        XCTAssertEqual(model.decision, .sansGps, "consentement illisible : pointage sans position, jamais une feuille ni un GPS supposé")
        XCTAssertFalse(model.interrupteurActif)
        XCTAssertFalse(model.bandeauSansGps)
    }

    func testSessionExpireeALaLecture() async throws {
        let (model, _) = try await modele(PortConsentement(valeur: nil, lectures: [JoleneError(.unauthorized, "Votre session a expiré.")]))
        await model.charger()
        XCTAssertTrue(model.sessionExpired)
    }

    // MARK: - Feuille du premier pointage

    func testAutoriserEnregistrePuisRelitPuisAuditePuisDemandeLAutorisationIOS() async throws {
        let port = PortConsentement(valeur: nil)
        let audit = AuditEspion()
        let (model, _) = try await modele(port, audit: audit)
        await model.charger()
        let localisation = DemoLocationPort(scenario: .accorde)
        let relu = await model.repondre(accepte: true, localisation: localisation)
        XCTAssertEqual(relu, true)
        XCTAssertEqual(port.journal, ["lire", "fn_consentir_gps(true)", "relire"], "RPC puis relecture, aucune autre requête")
        let ecritures = await audit.journal.ecritures
        XCTAssertEqual(ecritures, ["RGPD_CONSENTEMENT_DONNE soignant u-consentement consentement=true,type=gps"],
                       "audit du web (l.67-74) : ressource soignant, détails type gps et consentement")
        let demandes = await localisation.demandes
        XCTAssertEqual(demandes, 1, "autorisation iOS demandée seulement après « Autoriser »")
        XCTAssertEqual(model.etat, .lu(true))
        XCTAssertEqual(model.retour, .enregistre)
        XCTAssertEqual(model.decision, .localiser)
        XCTAssertFalse(model.enCours)
    }

    func testRefuserEnregistreFauxAfficheLeBandeauSansAutorisationIOS() async throws {
        let port = PortConsentement(valeur: nil)
        let audit = AuditEspion()
        let (model, _) = try await modele(port, audit: audit)
        await model.charger()
        let localisation = DemoLocationPort(scenario: .accorde)
        let relu = await model.repondre(accepte: false, localisation: localisation)
        XCTAssertEqual(relu, false)
        XCTAssertEqual(port.journal, ["lire", "fn_consentir_gps(false)", "relire"])
        let ecritures = await audit.journal.ecritures
        XCTAssertEqual(ecritures, ["RGPD_CONSENTEMENT_DONNE soignant u-consentement consentement=false,type=gps"],
                       "le refus est audité comme sur le web (l.87-94)")
        let demandes = await localisation.demandes
        XCTAssertEqual(demandes, 0, "un refus ne déclenche jamais la demande système")
        XCTAssertEqual(model.retour, .sansGps)
        XCTAssertTrue(model.bandeauSansGps)
        XCTAssertEqual(model.decision, .sansGps, "un refus ne bloque jamais le pointage : il part sans position")
    }

    func testEchecDeLaRPCNeFaitAucuneHypotheseLocaleNiAudit() async throws {
        let port = PortConsentement(valeur: nil, erreurEnregistrement: JoleneError(.unknown, "Impossible d'enregistrer votre choix de localisation. Réessayez."))
        let audit = AuditEspion()
        let (model, _) = try await modele(port, audit: audit)
        await model.charger()
        let localisation = DemoLocationPort(scenario: .accorde)
        let relu = await model.repondre(accepte: true, localisation: localisation)
        XCTAssertNil(relu)
        XCTAssertEqual(model.etat, .lu(nil), "aucune hypothèse locale : la valeur reste celle relue avant")
        XCTAssertEqual(model.retour, .echec("Impossible d'enregistrer votre choix de localisation. Réessayez."))
        let ecritures = await audit.journal.ecritures
        XCTAssertTrue(ecritures.isEmpty, "aucun audit sans consentement enregistré")
        let demandes = await localisation.demandes
        XCTAssertEqual(demandes, 0)
        XCTAssertEqual(model.decision, .recueillir, "la feuille sera reproposée au prochain pointage")
    }

    func testValeurRelueFaitFoiSurLaDemande() async throws {
        let port = PortConsentement(valeur: nil, valeurImposee: false)
        let audit = AuditEspion()
        let (model, _) = try await modele(port, audit: audit)
        await model.charger()
        let localisation = DemoLocationPort(scenario: .accorde)
        let relu = await model.repondre(accepte: true, localisation: localisation)
        XCTAssertEqual(relu, false, "la valeur rendue est celle relue au serveur")
        XCTAssertEqual(model.etat, .lu(false))
        XCTAssertEqual(model.retour, .sansGps)
        let ecritures = await audit.journal.ecritures
        XCTAssertEqual(ecritures, ["RGPD_CONSENTEMENT_DONNE soignant u-consentement consentement=false,type=gps"], "audit de la valeur relue")
        let demandes = await localisation.demandes
        XCTAssertEqual(demandes, 0, "aucune demande système sans consentement relu")
    }

    func testAuditEnEchecEstAvaleSansToucherAuConsentement() async throws {
        var audit = AuditEspion()
        audit.erreur = JoleneError(.network, "Réseau indisponible.")
        let (model, _) = try await modele(PortConsentement(valeur: nil), audit: audit)
        await model.charger()
        let relu = await model.repondre(accepte: true, localisation: DemoLocationPort(scenario: .accorde))
        XCTAssertEqual(relu, true)
        XCTAssertEqual(model.retour, .enregistre, "audit best-effort (décision 5 du lot 1) : jamais une erreur affichée")
        XCTAssertFalse(model.sessionExpired)
    }

    // MARK: - Profil (retrait et réactivation, correction 15)

    func testRetraitDepuisLeProfilSansAudit() async throws {
        let port = PortConsentement(valeur: true)
        let audit = AuditEspion()
        let (model, _) = try await modele(port, audit: audit)
        await model.charger()
        await model.basculer(false)
        XCTAssertEqual(port.journal, ["lire", "fn_consentir_gps(false)", "relire"])
        XCTAssertEqual(model.etat, .lu(false))
        XCTAssertEqual(model.retour, .bascule(actif: false))
        XCTAssertFalse(model.interrupteurActif)
        let ecritures = await audit.journal.ecritures
        XCTAssertTrue(ecritures.isEmpty, "GPS_CONSENTEMENT_* absentes du CHECK : aucun audit client (correction 15)")
    }

    func testReactivationDepuisLeProfilSansAuditNiDemandeSysteme() async throws {
        let port = PortConsentement(valeur: false)
        let audit = AuditEspion()
        let (model, _) = try await modele(port, audit: audit)
        await model.charger()
        await model.basculer(true)
        XCTAssertEqual(model.etat, .lu(true))
        XCTAssertEqual(model.retour, .bascule(actif: true))
        XCTAssertTrue(model.interrupteurActif)
        let ecritures = await audit.journal.ecritures
        XCTAssertTrue(ecritures.isEmpty)
        model.oublierRetour()
        XCTAssertNil(model.retour)
    }

    func testBasculeEnEchecGardeLaValeurRelue() async throws {
        let port = PortConsentement(valeur: true, erreurEnregistrement: JoleneError(.network, "Réseau indisponible."))
        let (model, _) = try await modele(port)
        await model.charger()
        await model.basculer(false)
        XCTAssertEqual(model.etat, .lu(true), "aucune hypothèse locale : l'interrupteur reste sur la valeur relue")
        XCTAssertEqual(model.retour, .echec("Réseau indisponible."))
        XCTAssertTrue(model.interrupteurActif)
    }

    func testReponseDUnEpochPerimeIgnoree() async throws {
        let port = PortConsentement(valeur: nil)
        let (model, controller) = try await modele(port)
        await model.charger()
        _ = await controller.signOut()
        let relu = await model.repondre(accepte: true, localisation: DemoLocationPort(scenario: .accorde))
        XCTAssertNil(relu, "epoch quitté : rien n'est envoyé ni publié")
        XCTAssertEqual(port.journal, ["lire"])
        XCTAssertEqual(model.etat, .lu(nil))
    }

    // MARK: - Revue fraîche de T4b : premier consentement depuis le Profil (M2)

    func testActivationDepuisLeProfilSansReponsePresenteLaFeuilleSansAucuneRPC() async throws {
        let port = PortConsentement(valeur: nil)
        let audit = AuditEspion()
        let (model, _) = try await modele(port, audit: audit)
        await model.charger()
        XCTAssertFalse(model.feuilleRequise)
        await model.basculer(true)
        XCTAssertTrue(model.feuilleRequise, "NULL → activé : la feuille verbatim (finalité, durée, base légale) d'abord (RGPD art. 4, 11 ; art. 13)")
        XCTAssertEqual(port.journal, ["lire"], "aucun `fn_consentir_gps` avant la réponse à la feuille")
        let ecritures = await audit.journal.ecritures
        XCTAssertTrue(ecritures.isEmpty)
        XCTAssertEqual(model.etat, .lu(nil), "rien n'est supposé : l'interrupteur reste éteint")
        XCTAssertNil(model.retour)
        XCTAssertFalse(model.enCours)
    }

    func testFeuilleDuProfilAccepteeEnregistreRelitAuditeEtActive() async throws {
        let port = PortConsentement(valeur: nil)
        let audit = AuditEspion()
        let (model, _) = try await modele(port, audit: audit)
        await model.charger()
        await model.basculer(true)
        let localisation = DemoLocationPort(scenario: .accorde)
        let relu = await model.repondre(accepte: true, localisation: localisation)
        XCTAssertEqual(relu, true)
        XCTAssertFalse(model.feuilleRequise, "la feuille se ferme après la réponse")
        XCTAssertEqual(port.journal, ["lire", "fn_consentir_gps(true)", "relire"], "RPC puis relecture, comme au premier pointage")
        let ecritures = await audit.journal.ecritures
        XCTAssertEqual(ecritures, ["RGPD_CONSENTEMENT_DONNE soignant u-consentement consentement=true,type=gps"],
                       "premier consentement audité (correction 15 du blueprint)")
        XCTAssertTrue(model.interrupteurActif)
        XCTAssertEqual(model.retour, .enregistre, "retour du web après la feuille (`PresencesSoignant.tsx` l.76)")
        let demandes = await localisation.demandes
        XCTAssertEqual(demandes, 1, "autorisation iOS demandée seulement après « Autoriser » (décision 4)")
    }

    func testFeuilleDuProfilRefuseeEnregistreFauxEtAudite() async throws {
        let port = PortConsentement(valeur: nil)
        let audit = AuditEspion()
        let (model, _) = try await modele(port, audit: audit)
        await model.charger()
        await model.basculer(true)
        let localisation = DemoLocationPort(scenario: .accorde)
        let relu = await model.repondre(accepte: false, localisation: localisation)
        XCTAssertEqual(relu, false)
        XCTAssertFalse(model.feuilleRequise)
        let ecritures = await audit.journal.ecritures
        XCTAssertEqual(ecritures, ["RGPD_CONSENTEMENT_DONNE soignant u-consentement consentement=false,type=gps"])
        XCTAssertFalse(model.interrupteurActif)
        XCTAssertEqual(model.retour, .sansGps)
        let demandes = await localisation.demandes
        XCTAssertEqual(demandes, 0)
    }

    func testFeuilleDuProfilEnEchecSeFermeSansHypothese() async throws {
        let port = PortConsentement(valeur: nil, erreurEnregistrement: JoleneError(.network, "Réseau indisponible."))
        let (model, _) = try await modele(port)
        await model.charger()
        await model.basculer(true)
        let relu = await model.repondre(accepte: true, localisation: nil)
        XCTAssertNil(relu)
        XCTAssertFalse(model.feuilleRequise, "la feuille se ferme ; le message d'échec est affiché sous l'interrupteur")
        XCTAssertEqual(model.retour, .echec("Réseau indisponible."))
        XCTAssertEqual(model.etat, .lu(nil))
    }

    func testFermerLaFeuilleDuProfilSansReponseNEnregistreRien() async throws {
        let port = PortConsentement(valeur: nil)
        let (model, _) = try await modele(port)
        await model.charger()
        await model.basculer(true)
        model.fermerFeuille()
        XCTAssertFalse(model.feuilleRequise)
        XCTAssertEqual(port.journal, ["lire"])
        XCTAssertEqual(model.etat, .lu(nil))
    }

    func testReponseAUneValeurNulleSansFeuilleAuditeLaPremiereReponse() async throws {
        // Filet (revue fraîche de T4b, M2) : une bascule vers « retiré » depuis NULL est une première réponse, auditée.
        let port = PortConsentement(valeur: nil)
        let audit = AuditEspion()
        let (model, _) = try await modele(port, audit: audit)
        await model.charger()
        await model.basculer(false)
        XCTAssertEqual(port.journal, ["lire", "fn_consentir_gps(false)", "relire"])
        let ecritures = await audit.journal.ecritures
        XCTAssertEqual(ecritures, ["RGPD_CONSENTEMENT_DONNE soignant u-consentement consentement=false,type=gps"])
        XCTAssertEqual(model.retour, .bascule(actif: false))
    }

    // MARK: - Revue fraîche de T4b : ligne du Profil (M3)

    func testLigneDuProfilChargementPuisErreurPuisReprise() async throws {
        let port = PortConsentement(valeur: true, lectures: [JoleneError(.network, "Réseau indisponible."), nil])
        let (model, _) = try await modele(port)
        XCTAssertEqual(model.ligneProfil, .chargement, "pendant la lecture : indicateur, jamais un interrupteur éteint")
        await model.charger()
        XCTAssertEqual(model.ligneProfil, .indisponible("Réseau indisponible."),
                       "lecture en échec : message du port et « Réessayer », jamais « consentement retiré »")
        await model.charger()
        XCTAssertEqual(model.ligneProfil, .interrupteur(actif: true), "reprise : la valeur relue")
    }

    func testLigneDuProfilNulAfficheLInterrupteurEteint() async throws {
        let (model, _) = try await modele(PortConsentement(valeur: nil))
        await model.charger()
        XCTAssertEqual(model.ligneProfil, .interrupteur(actif: false))
    }

    // MARK: - Revue fraîche de T4b : envoi unique (m1)

    func testDoubleTapSurAutoriserUnSeulEnregistrementEtUnSeulAudit() async throws {
        let port = PortConsentement(valeur: nil)
        let audit = AuditEspion()
        let (model, _) = try await modele(port, audit: audit)
        await model.charger()
        let localisation = DemoLocationPort(scenario: .accorde)
        // Deux touchers rapprochés : deux tâches enfilées avant que la première n'atteigne son premier `await`.
        let premier = Task { await model.repondre(accepte: true, localisation: localisation) }
        let second = Task { await model.repondre(accepte: true, localisation: localisation) }
        let reponses = [await premier.value, await second.value]
        XCTAssertEqual(port.enregistrements, 1, "un seul `fn_consentir_gps`")
        let ecritures = await audit.journal.ecritures
        XCTAssertEqual(ecritures.count, 1, "une seule ligne d'audit (journal immuable)")
        XCTAssertEqual(reponses.compactMap { $0 }, [true], "le second toucher ne rend rien : aucun second pointage")
        let demandes = await localisation.demandes
        XCTAssertEqual(demandes, 1)
    }

    func testDoubleBasculeDuProfilUnSeulEnregistrement() async throws {
        let port = PortConsentement(valeur: true)
        let (model, _) = try await modele(port)
        await model.charger()
        let premier = Task { await model.basculer(false) }
        let second = Task { await model.basculer(false) }
        await premier.value
        await second.value
        XCTAssertEqual(port.enregistrements, 1)
        XCTAssertEqual(model.etat, .lu(false))
    }

    func testInterrupteurAfficheLaDemandeEnVolPuisLaValeurRelue() async throws {
        let retenue = Gate()
        let port = PortConsentement(valeur: true, retenue: retenue)
        let (model, _) = try await modele(port)
        await model.charger()
        let bascule = Task { await model.basculer(false) }
        await port.entreeEnregistrement.wait()
        XCTAssertEqual(model.ligneProfil, .interrupteur(actif: false),
                       "pendant la demande, l'interrupteur montre le choix en vol (aucun retour visuel qui inviterait à un second toucher)")
        XCTAssertTrue(model.enCours)
        XCTAssertTrue(model.interrupteurActif, "la valeur relue n'a pas changé : aucune hypothèse locale")
        await retenue.open()
        await bascule.value
        XCTAssertEqual(model.ligneProfil, .interrupteur(actif: false))
        XCTAssertFalse(model.interrupteurActif)
    }

    func testBasculeEnEchecRevientALaValeurRelue() async throws {
        let port = PortConsentement(valeur: true, erreurEnregistrement: JoleneError(.network, "Réseau indisponible."))
        let (model, _) = try await modele(port)
        await model.charger()
        await model.basculer(false)
        XCTAssertEqual(model.ligneProfil, .interrupteur(actif: true), "échec : retour à la valeur relue")
    }

    // MARK: - Revue fraîche de T4b : identité changée pendant la réponse (m2)

    func testEpochQuittePendantLAuditRendNilSansAutorisationIOS() async throws {
        let retenue = Gate()
        var audit = AuditEspion()
        audit.retenue = retenue
        let port = PortConsentement(valeur: nil)
        let (model, controller) = try await modele(port, audit: audit)
        await model.charger()
        let localisation = DemoLocationPort(scenario: .accorde)
        let reponse = Task { await model.repondre(accepte: true, localisation: localisation) }
        await audit.entree.wait()
        _ = await controller.signOut()
        await retenue.open()
        let relu = await reponse.value
        XCTAssertNil(relu, "epoch quitté : rien n'est rendu, donc aucun pointage ni position demandée")
        XCTAssertNil(model.retour, "rien n'est publié")
        let demandes = await localisation.demandes
        XCTAssertEqual(demandes, 0, "aucun prompt iOS après une déconnexion")
    }

    func testEpochQuittePendantLaRPCRendNil() async throws {
        let retenue = Gate()
        let port = PortConsentement(valeur: nil, retenue: retenue)
        let (model, controller) = try await modele(port)
        await model.charger()
        let localisation = DemoLocationPort(scenario: .accorde)
        let reponse = Task { await model.repondre(accepte: true, localisation: localisation) }
        await port.entreeEnregistrement.wait()
        _ = await controller.signOut()
        await retenue.open()
        let relu = await reponse.value
        XCTAssertNil(relu)
        XCTAssertEqual(model.etat, .lu(nil), "la valeur relue d'un epoch quitté n'est pas publiée")
        let demandes = await localisation.demandes
        XCTAssertEqual(demandes, 0)
    }

    // MARK: - Position au moment du pointage (décisions 4 et 5)

    func testPositionDuPointageSelonLAutorisationIOS() async {
        let accorde = DemoLocationPort(scenario: .accorde)
        let position = await LocalisationPointage.observer(accorde)
        XCTAssertEqual(position, .disponible(latitude: 48.8566, longitude: 2.3522, precisionM: 12))
        let demandesAccorde = await accorde.demandes
        XCTAssertEqual(demandesAccorde, 1, "consentement donné, autorisation iOS non déterminée : demandée une fois")

        let refuse = DemoLocationPort(scenario: .refuse)
        let refusee = await LocalisationPointage.observer(refuse)
        XCTAssertEqual(refusee, .refusee)

        let reduite = await LocalisationPointage.observer(DemoLocationPort(scenario: .reduite))
        XCTAssertEqual(reduite, .precisionReduite, "précision réduite : aucune coordonnée (décision 5)")
        XCTAssertNil(MetadonneesScan(idTerminal: DemoTerminalIdentity.identifiantDemo, observation: reduite).latitude)

        let indisponible = await LocalisationPointage.observer(DemoLocationPort(scenario: .indisponible))
        XCTAssertEqual(indisponible, .indisponible)
    }

    func testAutorisationDejaDonneeNEstPasRedemandee() async {
        let localisation = DemoLocationPort(scenario: .accorde)
        await localisation.demanderAutorisation()
        _ = await LocalisationPointage.observer(localisation)
        let demandes = await localisation.demandes
        XCTAssertEqual(demandes, 1, "aucune seconde demande système")
    }

    func testDelaiDeLaPositionEstCeluiDuWeb() {
        XCTAssertEqual(LocalisationPointage.delai, 15, "`timeout: 15000` (src/lib/platform.ts l.298)")
        XCTAssertEqual(LocalisationPointage.delai, LocationPolicy.delaiPosition)
    }
}
