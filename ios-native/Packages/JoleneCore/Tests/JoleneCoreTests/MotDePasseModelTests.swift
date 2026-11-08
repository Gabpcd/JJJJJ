import XCTest
@testable import JoleneCore

// MARK: - Doubles du compte (T11)

/// Entrée d'audit détaillée (action, ressource, détails), pour les preuves de T11.
struct EntreeAudit: Equatable, Sendable {
    var action: String
    var typeRessource: String
    var idRessource: String
    var details: [String: String]
}

actor JournalAuditDetaille {
    private(set) var entrees: [EntreeAudit] = []
    func record(_ entree: EntreeAudit) { entrees.append(entree) }
}

/// Audit qui garde les détails ; `erreur` simule un journal indisponible.
struct AuditDetaille: AuditPort {
    let journal = JournalAuditDetaille()
    var erreur: JoleneError?

    func connexion() async throws -> AuditResultat { .enregistre }
    func deconnexion() async throws -> AuditResultat { .enregistre }
    func activite() async throws -> AuditResultat { .enregistre }
    func ecrire(action: AuditAction, typeRessource: String, idRessource: String, details: [String: String],
                context: MissionReadContext) async throws -> AuditResultat {
        await journal.record(EntreeAudit(action: action.rawValue, typeRessource: typeRessource, idRessource: idRessource, details: details))
        if let erreur { throw erreur }
        return .enregistre
    }
}

/// Serveur d'authentification simulé : issues scriptées dans l'ordre, appels comptés (longueurs seulement).
actor ServeurMotDePasse {
    private var issues: [Result<ResultatMotDePasse, Error>]
    private(set) var appels: [(ancien: Int, nouveau: Int)] = []
    var barriere: Gate?

    init(issues: [Result<ResultatMotDePasse, Error>]) { self.issues = issues }

    var nombreAppels: Int { appels.count }

    func retenir(_ gate: Gate) { barriere = gate }

    func changer(ancien: String, nouveau: String) async throws -> ResultatMotDePasse {
        appels.append((ancien.count, nouveau.count))
        if let barriere { await barriere.wait() }
        guard !issues.isEmpty else { throw JoleneError(.contract, "issue non scriptée") }
        return try issues.removeFirst().get()
    }
}

struct FakeMotDePasse: MotDePassePort {
    let serveur: ServeurMotDePasse
    func changer(ancien: String, nouveau: String, context: MissionReadContext) async throws -> ResultatMotDePasse {
        try await serveur.changer(ancien: ancien, nouveau: nouveau)
    }
}

/// Modèle de l'écran « Changer mon mot de passe » (lot 3, T11) : formulaire dérivé (critères, correspondance),
/// une seule demande, succès annoncé seulement sur `.modifie` (champs effacés, audit best-effort ensuite), refus
/// verbatim, refus verrouillé quand le serveur exige une réauthentification (D13), issue inconnue jamais
/// présentée comme un succès, epoch d'identité.
@MainActor
final class MotDePasseModelTests: XCTestCase {
    private static let valide = "Nouveau-mdp-2026"
    private let utilisateur = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000))

    private struct Scenario {
        var store: SessionStore
        var model: MotDePasseModel
        var serveur: ServeurMotDePasse
        var audit: AuditDetaille
        var log: CallLog
    }

    private func scenario(_ issues: [Result<ResultatMotDePasse, Error>], audit: AuditDetaille = AuditDetaille(),
                          timeout: TimeInterval = SessionController.defaultResolutionTimeout) async throws -> Scenario {
        let log = CallLog()
        let serveur = ServeurMotDePasse(issues: issues)
        var gateways = Lot1Fakes.gateways(audit: audit)
        gateways.auth = FakeAuth(restored: utilisateur, signInResult: .success(utilisateur), log: log)
        gateways.role = FakeRole(result: .success(RoleResult(role: "SOIGNANT")), gate: nil, log: log)
        gateways.missions = FakeMissions(profile: SoignantProfile(id: "u-1", profession: "IDE"), profileError: nil, gate: nil, log: log)
        gateways.motDePasse = FakeMotDePasse(serveur: serveur)
        let store = SessionStore(controller: SessionController(gateways: gateways, resolutionTimeout: timeout))
        await store.start()
        let snapshot = try XCTUnwrap(store.state.snapshot, "session prête attendue, obtenu \(store.state)")
        return Scenario(store: store, model: MotDePasseModel(session: store, snapshot: snapshot), serveur: serveur, audit: audit, log: log)
    }

    private func remplir(_ model: MotDePasseModel, ancien: String = "ancien-mdp", nouveau: String = valide, confirmation: String? = nil) {
        model.ancien = ancien
        model.nouveau = nouveau
        model.confirmation = confirmation ?? nouveau
    }

    // MARK: - Formulaire dérivé

    func testFormulaireDeriveDeLaSaisie() async throws {
        let s = try await scenario([])
        let model = s.model
        XCTAssertFalse(model.afficheJauge, "jauge affichée seulement une fois la saisie commencée (l.156)")
        XCTAssertFalse(model.peutSoumettre)
        model.nouveau = "abc"
        XCTAssertTrue(model.afficheJauge)
        XCTAssertEqual(model.force.score, 1)
        XCTAssertFalse(model.afficheNonCorrespondance, "rien tant que la confirmation est vide (l.169)")
        model.confirmation = "abd"
        XCTAssertTrue(model.afficheNonCorrespondance)
        XCTAssertFalse(model.afficheCorrespondance)
        remplir(model)
        XCTAssertTrue(model.afficheCorrespondance, "« Mots de passe identiques. » (l.174-178)")
        XCTAssertFalse(model.afficheNonCorrespondance)
        XCTAssertTrue(model.peutSoumettre)
        model.ancien = ""
        XCTAssertFalse(model.peutSoumettre, "ancien mot de passe exigé (l.40)")
        let nombre = await s.serveur.nombreAppels
        XCTAssertEqual(nombre, 0, "aucun appel sans soumission")
    }

    func testFormulaireInvalideNEnvoieRien() async throws {
        let s = try await scenario([.success(.modifie)])
        remplir(s.model, nouveau: "court1A!", confirmation: "court1A!")
        await s.model.changer()
        let nombre = await s.serveur.nombreAppels
        XCTAssertEqual(nombre, 0)
        XCTAssertNil(s.model.succes)
    }

    // MARK: - Issues

    func testSuccesEffaceLesChampsPuisAuditeSansBloquer() async throws {
        let s = try await scenario([.success(.modifie)])
        remplir(s.model)
        await s.model.changer()
        XCTAssertEqual(s.model.succes, "Mot de passe modifié avec succès.")
        XCTAssertNil(s.model.erreur)
        XCTAssertEqual([s.model.ancien, s.model.nouveau, s.model.confirmation], ["", "", ""], "champs effacés (l.98-100)")
        XCTAssertFalse(s.model.enCours)
        let appels = await s.serveur.appels
        XCTAssertEqual(appels.map { $0.ancien }, ["ancien-mdp".count])
        XCTAssertEqual(appels.map { $0.nouveau }, [Self.valide.count])
        let audit = await s.audit.journal.entrees
        XCTAssertEqual(audit, [EntreeAudit(action: "DONNEES_PERSO_MODIFICATION", typeRessource: "utilisateur", idRessource: "u-1",
                                           details: ["champ": "mot_de_passe", "horodatage": "2026-11-02T00:00:00.000Z"])])
        // Une saisie après le succès efface l'encart.
        s.model.ancien = "a"
        XCTAssertNil(s.model.succes)
    }

    func testAuditIndisponibleNeRetireJamaisLeSucces() async throws {
        let s = try await scenario([.success(.modifie)], audit: AuditDetaille(erreur: JoleneError(.network, "réseau")))
        remplir(s.model)
        await s.model.changer()
        XCTAssertEqual(s.model.succes, MotDePasse.Textes.succes, "le journal ne retarde ni n'annule la confirmation (l.78-92)")
        XCTAssertNil(s.model.erreur)
    }

    func testAncienIncorrectGardeLaSaisieSansAudit() async throws {
        let s = try await scenario([.success(.ancienIncorrect)])
        remplir(s.model)
        await s.model.changer()
        XCTAssertEqual(s.model.erreur, "Ancien mot de passe incorrect.")
        XCTAssertNil(s.model.succes)
        XCTAssertEqual(s.model.nouveau, Self.valide, "saisie conservée sur un refus")
        XCTAssertTrue(s.model.peutSoumettre, "nouvel essai manuel possible")
        let audit = await s.audit.journal.entrees
        XCTAssertTrue(audit.isEmpty)
        // Une nouvelle saisie efface le refus.
        s.model.ancien = "autre"
        XCTAssertNil(s.model.erreur)
    }

    func testRefusServeurVerbatim() async throws {
        let s = try await scenario([.success(.refuse(message: "Une erreur est survenue. Veuillez réessayer."))])
        remplir(s.model)
        await s.model.changer()
        XCTAssertEqual(s.model.erreur, "Une erreur est survenue. Veuillez réessayer.")
        XCTAssertFalse(s.model.reauthentificationExigee)
    }

    func testReauthentificationExigeeVerrouilleLeFormulaire() async throws {
        let s = try await scenario([.success(.reauthentificationRequise), .success(.modifie)])
        remplir(s.model)
        await s.model.changer()
        XCTAssertEqual(s.model.erreur, MotDePasse.Textes.reauthentificationRequise)
        XCTAssertTrue(s.model.reauthentificationExigee)
        XCTAssertFalse(s.model.peutSoumettre, "refus verrouillé (D13) : aucun nouvel envoi depuis cet écran")
        remplir(s.model, ancien: "x")
        XCTAssertEqual(s.model.erreur, MotDePasse.Textes.reauthentificationRequise, "le verrou reste affiché pendant la saisie")
        await s.model.changer()
        let nombre = await s.serveur.nombreAppels
        XCTAssertEqual(nombre, 1, "jamais de second appel une fois la réauthentification exigée")
    }

    func testIssueInconnueJamaisPresenteeCommeUnSucces() async throws {
        for erreur in [JoleneError(.network, "réseau"), JoleneError(.unknown, "inconnu")] {
            let s = try await scenario([.failure(erreur)])
            remplir(s.model)
            await s.model.changer()
            XCTAssertEqual(s.model.erreur, MotDePasse.Textes.confirmationIndisponible, "\(erreur.kind)")
            XCTAssertNil(s.model.succes)
            XCTAssertEqual(s.model.nouveau, Self.valide, "saisie conservée")
            let audit = await s.audit.journal.entrees
            XCTAssertTrue(audit.isEmpty)
        }
    }

    func testDelaiDepasseIssueInconnue() async throws {
        let s = try await scenario([.success(.modifie)], timeout: 0.05)
        let barriere = Gate()
        await s.serveur.retenir(barriere)
        remplir(s.model)
        await s.model.changer()
        XCTAssertEqual(s.model.erreur, MotDePasse.Textes.confirmationIndisponible)
        XCTAssertNil(s.model.succes)
        XCTAssertFalse(s.model.enCours)
        await barriere.open()
    }

    func testContratVerbatimSansSessionExpiree() async throws {
        let s = try await scenario([.failure(JoleneError(.contract, "Mettez à jour l'application."))])
        remplir(s.model)
        await s.model.changer()
        XCTAssertEqual(s.model.erreur, "Mettez à jour l'application.")
        XCTAssertFalse(s.model.sessionExpiree)
    }

    func testSessionExpireePuisVerification() async throws {
        let s = try await scenario([.failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))])
        remplir(s.model)
        await s.model.changer()
        XCTAssertTrue(s.model.sessionExpiree)
        XCTAssertEqual(s.model.erreur, "Votre session a expiré. Reconnectez-vous.")
        await s.model.verifierSession()
        XCTAssertFalse(s.model.sessionExpiree)
        XCTAssertNil(s.model.erreur)
        XCTAssertEqual(s.model.nouveau, Self.valide, "saisie conservée pour un nouvel appui")
    }

    func testDoubleAppuiUneSeuleDemande() async throws {
        let s = try await scenario([.success(.modifie)])
        let barriere = Gate()
        await s.serveur.retenir(barriere)
        remplir(s.model)
        let model = s.model
        let premier = Task { await model.changer() }
        while await s.serveur.nombreAppels == 0 { await Task.yield() }
        XCTAssertTrue(model.enCours)
        XCTAssertFalse(model.peutSoumettre)
        await model.changer()
        await barriere.open()
        await premier.value
        let nombre = await s.serveur.nombreAppels
        XCTAssertEqual(nombre, 1, "bouton désactivé pendant l'appel (`enCours`, l.44)")
        XCTAssertEqual(model.succes, MotDePasse.Textes.succes)
    }

    func testReponseDUneIdentitePerimeeIgnoree() async throws {
        let s = try await scenario([.success(.modifie)])
        let barriere = Gate()
        await s.serveur.retenir(barriere)
        remplir(s.model)
        let model = s.model
        let envoi = Task { await model.changer() }
        while await s.serveur.nombreAppels == 0 { await Task.yield() }
        await s.store.signOut()
        await barriere.open()
        await envoi.value
        XCTAssertNil(model.succes, "identité partie : aucun succès publié")
        XCTAssertNil(model.erreur)
        let audit = await s.audit.journal.entrees
        XCTAssertTrue(audit.isEmpty, "aucun audit pour une identité périmée")
    }

    // MARK: - Session (vérification de l'ancien mot de passe par `signIn`)

    func testSessionDuMemeUtilisateurNeChangePasDEpoch() async throws {
        // La vérification de l'ancien mot de passe (`signIn`) et `update(user:)` émettent `.signedIn` et
        // `.userUpdated` pour le même utilisateur : ni epoch avancé, ni relecture de session (blueprint §3 T11).
        let s = try await scenario([])
        let controleur = s.store.controller
        let epoch = await controleur.epoch
        let etat = await controleur.state
        let lectures = await s.log.entries.filter { $0 == "restoreSession" }.count
        _ = await controleur.handleAuthEvent(.session(userId: "u-1"))
        let epochApres = await controleur.epoch
        let etatApres = await controleur.state
        let lecturesApres = await s.log.entries.filter { $0 == "restoreSession" }.count
        XCTAssertEqual(epochApres, epoch)
        XCTAssertEqual(etatApres, etat)
        XCTAssertEqual(lecturesApres, lectures, "aucune relecture de session pour le même utilisateur")
        let servis = await controleur.gateways(for: epoch)
        XCTAssertNotNil(servis, "les écrans de l'epoch restent servis")
    }
}
