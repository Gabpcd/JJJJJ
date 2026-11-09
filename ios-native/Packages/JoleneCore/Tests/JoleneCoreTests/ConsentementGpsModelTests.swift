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

        init(valeur: Bool?, lectures: [JoleneError?] = [nil], erreurEnregistrement: JoleneError? = nil, valeurImposee: Bool? = nil) {
            self.valeur = valeur; self.lectures = lectures; self.erreurEnregistrement = erreurEnregistrement
            self.valeurImposee = valeurImposee
        }

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
            try noterEnregistrement(accepte).get()
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

        func connexion() async throws -> AuditResultat { .enregistre }
        func deconnexion() async throws -> AuditResultat { .enregistre }
        func activite() async throws -> AuditResultat { .enregistre }
        func ecrire(action: AuditAction, typeRessource: String, idRessource: String, details: [String: String],
                    context: MissionReadContext) async throws -> AuditResultat {
            let detail = details.keys.sorted().map { "\($0)=\(details[$0] ?? "")" }.joined(separator: ",")
            await journal.noter("\(action.rawValue) \(typeRessource) \(idRessource) \(detail)")
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
