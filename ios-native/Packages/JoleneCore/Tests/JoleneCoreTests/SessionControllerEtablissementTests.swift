import XCTest
@testable import JoleneCore

// MARK: - Ports factices de l'espace établissement

/// Réponses scriptées de `fn_mes_permissions_etab` / `fn_mon_etablissement_complet` : chaque appel
/// consomme la réponse suivante, la dernière se répète (relecture identique).
actor EtabSessionScript {
    private var permissions: [Result<PermissionsEtabResult, Error>]
    private var profils: [Result<EtablissementProfil, Error>]

    init(permissions: [Result<PermissionsEtabResult, Error>], profils: [Result<EtablissementProfil, Error>]) {
        self.permissions = permissions
        self.profils = profils
    }

    func prochainesPermissions() -> Result<PermissionsEtabResult, Error> {
        permissions.count > 1 ? permissions.removeFirst() : permissions[0]
    }

    func prochainProfil() -> Result<EtablissementProfil, Error> {
        profils.count > 1 ? profils.removeFirst() : profils[0]
    }

    func remplacer(permissions: [Result<PermissionsEtabResult, Error>]) { self.permissions = permissions }
}

/// `EtabSessionPort` factice : journal partagé avec les autres ports (ordre des appels), barrières
/// optionnelles pour faire changer l'identité pendant qu'une réponse est en vol.
struct FakeEtabSession: EtabSessionPort {
    let script: EtabSessionScript
    let log: CallLog
    var permissionsGate: Gate?
    /// Numéro du premier appel `permissions` bloqué par `permissionsGate` (1 = dès le premier).
    var permissionsGateFromCall = 1
    var profilGate: Gate?

    init(script: EtabSessionScript, log: CallLog, permissionsGate: Gate? = nil, permissionsGateFromCall: Int = 1,
         profilGate: Gate? = nil) {
        self.script = script; self.log = log; self.permissionsGate = permissionsGate
        self.permissionsGateFromCall = permissionsGateFromCall; self.profilGate = profilGate
    }

    /// Membre confirmé de `etablissementId` (rôle et permissions servis), profil du même établissement.
    init(etablissementId: String, role: RoleEtab = .proprietaire, permissions: Set<PermissionEtab> = [.lecture, .missions],
         log: CallLog) {
        self.init(script: EtabSessionScript(
            permissions: [.success(PermissionsEtabResult(success: true, role: role, etablissementId: etablissementId,
                                                         permissions: PermissionsEtab(accordees: permissions)))],
            profils: [.success(EtablissementProfil(id: etablissementId, nom: "Clinique \(etablissementId)"))]), log: log)
    }

    func permissions(etablissementId: String?) async throws -> PermissionsEtabResult {
        await log.record("permissions(\(etablissementId ?? "nil"))")
        let appels = await log.entries.filter { $0.hasPrefix("permissions(") }.count
        if let permissionsGate, appels >= permissionsGateFromCall { await permissionsGate.wait() }
        return try await script.prochainesPermissions().get()
    }

    func profil() async throws -> EtablissementProfil {
        await log.record("profil")
        if let profilGate { await profilGate.wait() }
        return try await script.prochainProfil().get()
    }
}

/// Rôle serveur scripté (revalidation : le rôle change d'un appel à l'autre).
actor RoleScript {
    private var reponses: [Result<RoleResult, Error>]
    init(_ reponses: [Result<RoleResult, Error>]) { self.reponses = reponses }
    func prochain() -> Result<RoleResult, Error> { reponses.count > 1 ? reponses.removeFirst() : reponses[0] }
}

struct ScriptedRole: RolePort {
    let script: RoleScript
    let log: CallLog
    func currentRole() async throws -> RoleResult {
        await log.record("currentRole")
        return try await script.prochain().get()
    }
}

/// Port de drapeaux qui journalise chaque clé lue (`drapeau(<clé>)`), réponse fail-open.
private struct DrapeauxJournalises: FlagsPort {
    let log: CallLog
    func ecranActif(cle: String, defaut: Bool) async -> Bool {
        await log.record("drapeau(\(cle))")
        return defaut
    }
}

/// Coupe-circuit de l'espace (T14, M1) : valeur scriptée par appel (la dernière se répète), `nil` = réponse « défaut »
/// (ce que rend `SupabaseFlagsGateway` sur erreur, droits refusés ou clé absente), barrière optionnelle (délai).
private actor DrapeauEspaceScript {
    private var valeurs: [Bool?]
    init(_ valeurs: [Bool?]) { self.valeurs = valeurs }
    func prochaine() -> Bool? { valeurs.count > 1 ? valeurs.removeFirst() : valeurs[0] }
}

private struct DrapeauEspaceScripte: FlagsPort {
    let script: DrapeauEspaceScript
    let log: CallLog
    var gate: Gate?
    func ecranActif(cle: String, defaut: Bool) async -> Bool {
        await log.record("drapeau(\(cle))")
        guard cle == EspaceEtablissementDrapeau.cle else { return defaut }
        if let gate { await gate.wait() }
        return await script.prochaine() ?? defaut
    }
}

private struct ErreurReseauEtab: Error {}

private let confirmeLe = Date(timeIntervalSince1970: 1_700_000_000)

private func utilisateurEtab(_ id: String = "membre-1", role: String? = "ADMIN_ETABLISSEMENT",
                             etablissementId: String? = nil) -> AuthenticatedUser {
    AuthenticatedUser(id: id, email: "\(id)@example.invalid", emailConfirmedAt: confirmeLe,
                      appMetadataRole: role, appMetadataEtablissementId: etablissementId)
}

private func permissions(role: RoleEtab? = .proprietaire, etablissementId: String? = "etab-1",
                         accordees: Set<PermissionEtab> = [.lecture, .missions], success: Bool = true)
    -> Result<PermissionsEtabResult, Error> {
    .success(PermissionsEtabResult(success: success, role: role, etablissementId: etablissementId,
                                   permissions: PermissionsEtab(accordees: accordees)))
}

private func profil(_ id: String = "etab-1") -> Result<EtablissementProfil, Error> {
    .success(EtablissementProfil(id: id, nom: "Clinique \(id)", peutPublierMissions: true, statutVerification: "VERIFIE",
                                 contratServiceSigne: true))
}

/// Jeu de ports d'un compte établissement : auth restaurable (état mutable), rôle scripté, session
/// établissement scriptée, profil soignant toujours absent (jamais demandé pour un établissement).
private struct EtabFixture {
    var log = CallLog()
    var auth: MutableAuthState
    var roles: RoleScript
    var session: EtabSessionScript
    var permissionsGate: Gate?
    var permissionsGateFromCall = 1
    var profilGate: Gate?
    var timeout: TimeInterval = SessionController.defaultResolutionTimeout
    var signInResult: Result<AuthenticatedUser, Error> = .success(utilisateurEtab())
    var profilSoignant: SoignantProfile?
    var audit = FakeAudit()
    /// T14 (M1) : port de drapeaux ; nil = port non câblé (fail-open, défaut des autres tests).
    var flags: FlagsPort?

    init(restored: AuthenticatedUser? = utilisateurEtab(),
         roles: [Result<RoleResult, Error>] = [.success(RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-1"))],
         permissions perms: [Result<PermissionsEtabResult, Error>] = [permissions()],
         profils: [Result<EtablissementProfil, Error>] = [profil()]) {
        auth = MutableAuthState(restored: restored, restoreError: nil)
        self.roles = RoleScript(roles)
        session = EtabSessionScript(permissions: perms, profils: profils)
    }

    func gateways() -> Gateways {
        var gateways = Gateways(
            auth: FakeAuth(restored: nil, restoreError: nil, signInResult: signInResult, signOutError: nil, signInGate: nil,
                           log: log, mutable: auth),
            role: ScriptedRole(script: roles, log: log),
            missions: FakeMissions(profile: profilSoignant, profileError: nil, gate: nil, log: log),
            clock: FixedClock(confirmeLe)
        )
        gateways.audit = audit
        if let flags { gateways.flags = flags }
        gateways.etablissement.session = FakeEtabSession(script: session, log: log, permissionsGate: permissionsGate,
                                                         permissionsGateFromCall: permissionsGateFromCall, profilGate: profilGate)
        return gateways
    }

    /// Configuration de production par défaut (revue B8 de #1147, m2) : espace FERMÉ ; les tests de l'espace ouvert (démo,
    /// puis STAGING à T13 et production à T14) le demandent par `espace: .ouvert`.
    func controller(espace: OuvertureEspaceEtablissement = .ferme) -> SessionController {
        SessionController(gateways: gateways(), resolutionTimeout: timeout, espaceEtablissement: espace)
    }
}

// MARK: - Tests

/// Session de l'espace établissement (lot 5, T2a ; `LOT5_PLAN.md` §2.2, D1, D2, D3) : résolution par
/// `EspaceResolution`, périmètre confirmé par `fn_mes_permissions_etab(NULL)`, profil sous-ensemble,
/// revalidation silencieuse, relecture des permissions après un refus de droit, epoch à chaque frontière.
final class SessionControllerEtablissementTests: XCTestCase {

    // MARK: Ouverture de l'espace

    func testMembreConfirmeOuvreLEspaceEtablissement() async throws {
        let fixture = EtabFixture()
        let controller = fixture.controller(espace: .ouvert)
        let state = await controller.start()
        guard case let .readyEtablissement(snapshot) = state else { return XCTFail("espace établissement attendu, obtenu \(state)") }
        XCTAssertTrue(state.isReady)
        XCTAssertNil(state.snapshot, "aucun SoignantProfile fabriqué (D1)")
        XCTAssertNil(state.message)
        XCTAssertEqual(state.snapshotEtablissement, snapshot)
        XCTAssertEqual(snapshot.user, utilisateurEtab())
        XCTAssertEqual(snapshot.role, RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-1"))
        XCTAssertEqual(snapshot.context, EtablissementReadContext(userId: "membre-1", etablissementId: "etab-1", roleEtab: .proprietaire,
                                                                  permissions: PermissionsEtab(accordees: [.lecture, .missions]), epoch: 1))
        XCTAssertNoThrow(try snapshot.context.verifier())
        XCTAssertEqual(snapshot.etablissement, try profil().get())
        XCTAssertEqual(snapshot.epoch, 1)
        let epoch = await controller.epoch
        XCTAssertEqual(epoch, snapshot.epoch)
        let entries = await fixture.log.entries
        XCTAssertEqual(entries, ["restoreSession", "currentRole", "permissions(nil)", "profil"],
                       "périmètre serveur demandé sans identifiant (D2), aucun profil soignant")
    }

    func testRepliSigneQuandLeRoleServeurEstIndisponible() async {
        let fixture = EtabFixture(restored: utilisateurEtab(etablissementId: "etab-1"), roles: [.failure(ErreurReseauEtab())])
        let state = await fixture.controller(espace: .ouvert).start()
        XCTAssertEqual(state.snapshotEtablissement?.context.etablissementId, "etab-1",
                       "raccourci signé app_metadata, confirmé par fn_mes_permissions_etab : \(state)")
    }

    func testLegacyConfirmeParLePerimetreServeur() async {
        let legacy = utilisateurEtab("etab-legacy", role: "ETABLISSEMENT")
        let fixture = EtabFixture(restored: legacy, roles: [.success(RoleResult(role: "ADMIN_ETABLISSEMENT"))],
                                  permissions: [permissions(etablissementId: "etab-legacy")], profils: [profil("etab-legacy")])
        let state = await fixture.controller(espace: .ouvert).start()
        guard case let .readyEtablissement(snapshot) = state else { return XCTFail("legacy confirmé attendu, obtenu \(state)") }
        XCTAssertEqual(snapshot.context.etablissementId, "etab-legacy", "le serveur confirme etablissements.id = user.id")
        XCTAssertEqual(snapshot.context.roleEtab, .proprietaire)
    }

    func testLegacyRefuseQuandLeServeurNeSertAucunRole() async {
        let legacy = utilisateurEtab("etab-legacy", role: "ETABLISSEMENT")
        let fixture = EtabFixture(restored: legacy, roles: [.success(RoleResult(role: "ADMIN_ETABLISSEMENT"))],
                                  permissions: [permissions(role: nil, etablissementId: nil)])
        let state = await fixture.controller(espace: .ouvert).start()
        XCTAssertEqual(state, .blocked(.unsupportedRole(SessionState.etabSansAccesCode)))
        let entries = await fixture.log.entries
        XCTAssertFalse(entries.contains("profil"), "aucun profil lu sans périmètre confirmé")
    }

    func testMembreRevoqueEstBloqueSansAcces() async {
        let fixture = EtabFixture(permissions: [permissions(role: nil, etablissementId: nil, accordees: [])])
        let state = await fixture.controller(espace: .ouvert).start()
        XCTAssertEqual(state, .blocked(.unsupportedRole(SessionState.etabSansAccesCode)))
        XCTAssertTrue(state.message?.contains("jolene.app") ?? false)
    }

    func testCandidatDivergentBloqueAvantToutProfil() async {
        let fixture = EtabFixture(permissions: [permissions(etablissementId: "etab-2")])
        let state = await fixture.controller(espace: .ouvert).start()
        XCTAssertEqual(state, .blocked(.unsupportedRole(SessionState.etabScopeDivergentCode)))
        let entries = await fixture.log.entries
        XCTAssertFalse(entries.contains("profil"))
    }

    func testProfilDUnAutreEtablissementEstUneDivergence() async {
        let fixture = EtabFixture(profils: [profil("etab-2")])
        let state = await fixture.controller(espace: .ouvert).start()
        XCTAssertEqual(state, .blocked(.unsupportedRole(SessionState.etabScopeDivergentCode)),
                       "un profil d'un autre établissement n'est jamais un repli")
    }

    func testCompteInactifRenvoieALaConnexionSansPurge() async {
        let fixture = EtabFixture(permissions: [permissions(role: nil, etablissementId: nil, accordees: [], success: false)])
        let state = await fixture.controller(espace: .ouvert).start()
        XCTAssertEqual(state, .signedOut(message: SessionController.sessionCheckFailedMessage))
        let signOuts = await fixture.log.signOutCount
        XCTAssertEqual(signOuts, 0)
    }

    func testRoleEtablissementInconnuNOuvreJamaisLEspace() async {
        let fixture = EtabFixture(permissions: [permissions(role: .inconnu("ADMIN_PLATEFORME"), accordees: [])])
        let state = await fixture.controller(espace: .ouvert).start()
        XCTAssertEqual(state, .blocked(.unsupportedRole("ADMIN_PLATEFORME")))
    }

    // MARK: Espace fermé hors démo (report sur main ; revue B8 de #1147, m2)

    /// Refus exact d'avant le lot 5 (`MobileAccess.validate`) et aucun appel établissement : ni permissions, ni profil.
    /// Statique : appelée aussi depuis un test `@MainActor`, sans envoyer `self` d'un domaine d'isolation à l'autre.
    private static func verifierRefusDAvantLeLot5(_ state: SessionState, log: CallLog, file: StaticString = #filePath,
                                           line: UInt = #line) async {
        XCTAssertEqual(state, .blocked(.unsupportedRole("ADMIN_ETABLISSEMENT")), file: file, line: line)
        XCTAssertEqual(state, .blocked(MobileAccess.validate(user: utilisateurEtab(), role: "ADMIN_ETABLISSEMENT")),
                       "même refus que MobileAccess.validate (main avant le lot 5)", file: file, line: line)
        let appels = await log.entries
        XCTAssertFalse(appels.contains { $0.hasPrefix("permissions(") || $0 == "profil" }, "appels : \(appels)",
                       file: file, line: line)
    }

    /// Défaut du contrôleur, `.ferme` (fail-closed) : restauration. Avant T14, c'était aussi la configuration de production.
    func testEspaceFermeParDefautRendLeRefusDAvantLeLot5SansAppelEtablissement() async {
        let fixture = EtabFixture()
        let state = await SessionController(gateways: fixture.gateways()).start()
        await Self.verifierRefusDAvantLeLot5(state, log: fixture.log)
    }

    func testEspaceFermeConnexion() async {
        let fixture = EtabFixture(restored: nil)
        let controller = fixture.controller()
        _ = await controller.start()
        let state = await controller.signIn(email: "membre-1@example.invalid", password: "mot-de-passe")
        await Self.verifierRefusDAvantLeLot5(state, log: fixture.log)
    }

    func testEspaceFermeRevalidationSilencieuseSoignantVersEtablissement() async {
        var fixture = EtabFixture(restored: utilisateurEtab(role: "SOIGNANT"),
                                  roles: [.success(RoleResult(role: "SOIGNANT")),
                                          .success(RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-1"))])
        fixture.profilSoignant = SoignantProfile(id: "membre-1", profession: "IDE")
        let controller = fixture.controller()
        guard case .ready = await controller.start() else { return XCTFail("espace soignant attendu d'abord") }
        let state = await controller.start() // reprise après 30 min : revalidation silencieuse, même identité
        await Self.verifierRefusDAvantLeLot5(state, log: fixture.log)
    }

    func testEspaceFermeEvenementSessionDUnAutreUtilisateur() async {
        var fixture = EtabFixture(restored: utilisateurEtab("soignant-1", role: "SOIGNANT"),
                                  roles: [.success(RoleResult(role: "SOIGNANT")),
                                          .success(RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-1"))])
        fixture.profilSoignant = SoignantProfile(id: "soignant-1", profession: "IDE")
        let controller = fixture.controller()
        guard case .ready = await controller.start() else { return XCTFail("espace soignant attendu d'abord") }
        await fixture.auth.set(restored: utilisateurEtab(), restoreError: nil)
        let state = await controller.handleAuthEvent(.session(userId: "membre-1"))
        await Self.verifierRefusDAvantLeLot5(state, log: fixture.log)
    }

    func testEspaceFermeRefuseAussiLeCompteLegacy() async {
        let legacy = utilisateurEtab("etab-legacy", role: "ETABLISSEMENT")
        let fixture = EtabFixture(restored: legacy, roles: [.success(RoleResult(role: "ETABLISSEMENT", etablissementId: nil))])
        let state = await fixture.controller().start()
        await Self.verifierRefusDAvantLeLot5(state, log: fixture.log)
        XCTAssertNil(state.snapshotEtablissement)
    }

    /// `SessionStore` sur l'espace fermé : aucun drapeau `ios_natif_etab_*` lu, à la connexion comme à la reprise.
    @MainActor
    func testEspaceFermeLeStoreNeLitAucunDrapeauEtablissement() async {
        let fixture = EtabFixture(restored: nil)
        var gateways = fixture.gateways()
        gateways.flags = DrapeauxJournalises(log: fixture.log)
        let store = SessionStore(controller: SessionController(gateways: gateways))
        await store.start()
        await store.signIn(email: "membre-1@example.invalid", password: "mot-de-passe")
        await Self.verifierRefusDAvantLeLot5(store.state, log: fixture.log)
        await fixture.auth.set(restored: utilisateurEtab(), restoreError: nil) // session persistée, reprise
        await store.start()
        await Self.verifierRefusDAvantLeLot5(store.state, log: fixture.log)
        let lus = await fixture.log.entries.filter { $0.hasPrefix("drapeau(") }
        XCTAssertEqual(lus, [], "aucun drapeau lu pour un espace fermé")
        XCTAssertNil(store.ecransEtablissement.epochCharge)
    }

    /// T13 (24/11/2026) : staging ouvert pour la recette contre le serveur de test ; T14 (25/11/2026) : production
    /// ouverte (`DECISIONS_LOT5.md`, sections T13 et T14). Refermer la production fait échouer ce test, la garde Node
    /// (`tests/node/contrats-etablissement-ios.node.mjs`) et la garde `etablissement` de la soumission App Store.
    func testOuvertureParModeDeLancement() {
        XCTAssertEqual(OuvertureEspaceEtablissement.pour(mode: .demo), .ouvert)
        XCTAssertEqual(OuvertureEspaceEtablissement.pour(mode: .staging), .ouvert, "T13 : recette STAGING")
        XCTAssertEqual(OuvertureEspaceEtablissement.pour(mode: .production), .ouvert, "T14 : production ouverte")
    }

    /// T14 : avec la table de production (`pour(mode: .production)`), comme avec celle de STAGING, un compte
    /// établissement confirmé par le serveur reçoit l'espace établissement ; un contrôleur fermé (`.ferme`, défaut
    /// fail-closed) rend au même compte le refus d'avant le lot 5, sans aucun appel établissement.
    func testStagingEtProductionOuvrentLEspaceLeVerrouFermeLeRefuse() async {
        for mode in [JoleneMode.staging, .production] {
            let fixture = EtabFixture()
            let ouvert = await SessionController(gateways: fixture.gateways(),
                                                 espaceEtablissement: .pour(mode: mode)).start()
            guard case .readyEtablissement = ouvert else {
                return XCTFail("\(mode) : espace établissement attendu, reçu \(ouvert)")
            }
        }
        let fermee = EtabFixture()
        let ferme = await SessionController(gateways: fermee.gateways(), espaceEtablissement: .ferme).start()
        await Self.verifierRefusDAvantLeLot5(ferme, log: fermee.log)
    }

    /// Second parcours STAGING (25/11/2026) : un même message de connexion couvre trois causes ; le diagnostic (DEBUG,
    /// valeur d'accessibilité de `login-error`) nomme l'étape et la nature de l'échec, sans secret.
    func testDiagnosticNommeLEtapeEtLaNatureDuRefus() async {
        let jete = EtabFixture(permissions: [.failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))])
        let controleur = jete.controller(espace: .ouvert)
        let etat = await controleur.signIn(email: "membre-1@example.invalid", password: "mot-de-passe")
        XCTAssertEqual(etat, .signedOut(message: SessionController.sessionCheckFailedMessage))
        let diagnostic = await controleur.diagnostic
        XCTAssertEqual(diagnostic, "permissions:unauthorized:Votre session a expiré. Reconnectez-vous.")
        XCTAssertFalse(diagnostic?.contains("example.invalid") ?? true, "jamais l'adresse")
        XCTAssertFalse(diagnostic?.contains("mot-de-passe") ?? true, "jamais le mot de passe")

        let inactif = EtabFixture(permissions: [permissions(role: nil, etablissementId: nil, accordees: [], success: false)])
        let autre = inactif.controller(espace: .ouvert)
        _ = await autre.signIn(email: "membre-1@example.invalid", password: "mot-de-passe")
        let perimetre = await autre.diagnostic
        XCTAssertEqual(perimetre, "permissions:perimetre:compteInactif", "success:false de fn_mes_permissions_etab")

        let ouvert = EtabFixture().controller(espace: .ouvert)
        guard case .readyEtablissement = await ouvert.signIn(email: "membre-1@example.invalid", password: "mot-de-passe") else {
            return XCTFail("espace établissement attendu")
        }
        let aucun = await ouvert.diagnostic
        XCTAssertNil(aucun, "aucun diagnostic sur une connexion réussie")

        // Revue de #1187, m6 : un défaut de contrat nomme la clé fautive (`JoleneError.detail`), jamais sa valeur.
        let contrat = EtabFixture(permissions: [.failure(JoleneError(.contract, "Réponse inattendue.", detail: "success"))])
        let decodage = contrat.controller(espace: .ouvert)
        _ = await decodage.signIn(email: "membre-1@example.invalid", password: "mot-de-passe")
        let cle = await decodage.diagnostic
        XCTAssertEqual(cle, "permissions:contract:success")

        // Revue de #1187, r2 : un `success:false` porteur d'un message serveur le recopie, masqué et tronqué.
        let uuid = "3f2b9c1e-8a4d-4c2e-9b7a-1d2e3f4a5b6c"
        let jeton = Self.jetonFabrique()
        let brut = "Compte inactif pour \(uuid) (membre-1@example.invalid) jeton \(jeton)"
        let refus = EtabFixture(permissions: [.success(PermissionsEtabResult(
            success: false, role: nil, etablissementId: nil, permissions: .aucune, messageServeur: brut))])
        let serveur = refus.controller(espace: .ouvert)
        let etatRefus = await serveur.signIn(email: "membre-1@example.invalid", password: "mot-de-passe")
        XCTAssertEqual(etatRefus, .signedOut(message: SessionController.sessionCheckFailedMessage), "comportement inchangé")
        let message = await serveur.diagnostic
        XCTAssertEqual(message, "permissions:refus:Compte inactif pour <uuid> (<adresse>) jeton <jeton>")
        for secret in [uuid, "example.invalid", jeton, String(jeton.prefix(3)), "3f2b9c1e"] {
            XCTAssertFalse(message?.contains(secret) ?? true, "jamais \(secret)")
        }
    }

    /// Jeton en forme de JWT fabriqué à l'exécution : aucun littéral en forme de secret dans les sources.
    private static func jetonFabrique() -> String {
        let segment = { (texte: String) in
            Data(texte.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return [segment(#"{"alg":"HS256"}"#), segment(#"{"sub":"x"}"#), segment("signature")].joined(separator: ".")
    }

    /// Troisième parcours STAGING : une session acceptée par Auth mais non enregistrée (trousseau refusé) arrête la
    /// connexion avec son propre message, jamais celui des identifiants, et un diagnostic qui la nomme.
    func testSessionNonEnregistreeArreteLaConnexionNommement() async {
        var fixture = EtabFixture()
        fixture.signInResult = .failure(JoleneError(.unknown, "Impossible d'enregistrer votre session sur cet appareil. Réessayez.",
                                                    detail: JoleneError.detailSessionNonEnregistree))
        let controleur = fixture.controller(espace: .ouvert)
        let etat = await controleur.signIn(email: "membre-1@example.invalid", password: "mot-de-passe")
        XCTAssertEqual(etat, .signedOut(message: "Impossible d'enregistrer votre session sur cet appareil. Réessayez."))
        let diagnostic = await controleur.diagnostic
        XCTAssertEqual(diagnostic, "connexion:unknown:session-non-enregistree")
        let appels = await fixture.log.entries
        XCTAssertTrue(appels.allSatisfy { !$0.contains("permissions") }, "aucune lecture de session")
    }

    /// Revue de #1191, M1 : le stockage retenu est lisible avant toute connexion et joint à chaque diagnostic d'échec ;
    /// sans stockage décrit (doubles de test, démo), le diagnostic est inchangé.
    func testStockageRetenuLisibleEtJointAuDiagnostic() async {
        var gateways = EtabFixture(permissions: [.failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.",
                                                                      detail: "postgrest=42501;jwt=non;exp=-;hote=-"))]).gateways()
        gateways.diagnosticStockage = "stockage=memoire;sonde=-34018"
        let controleur = SessionController(gateways: gateways, espaceEtablissement: .ouvert)
        XCTAssertEqual(controleur.diagnosticStockage, "stockage=memoire;sonde=-34018", "lisible avant la connexion")
        _ = await controleur.signIn(email: "membre-1@example.invalid", password: "mot-de-passe")
        let diagnostic = await controleur.diagnostic
        XCTAssertEqual(diagnostic, "permissions:unauthorized:postgrest=42501;jwt=non;exp=-;hote=- | stockage=memoire;sonde=-34018")

        let sansStockage = EtabFixture().controller(espace: .ouvert)
        XCTAssertNil(sansStockage.diagnosticStockage)
    }

    /// Revue de #1187, r2 : masquage avant troncature, 160 caractères au plus, jamais un fragment d'identifiant.
    func testDiagnosticServeurMasqueAvantDeTronquer() {
        let uuid = "3f2b9c1e-8a4d-4c2e-9b7a-1d2e3f4a5b6c"
        XCTAssertEqual(DiagnosticServeur.masquer(String(repeating: "a", count: 150) + " " + uuid),
                       String(repeating: "a", count: 150) + " <uuid>")
        XCTAssertEqual(DiagnosticServeur.masquer(String(repeating: "b", count: 200)), String(repeating: "b", count: 160) + "…")
        XCTAssertFalse(DiagnosticServeur.masquer(String(repeating: "c", count: 155) + " " + uuid).contains("3f2b"))
        let cle = ["sb", "publishable", "abcdefghijklmnop0123"].joined(separator: "_")
        XCTAssertEqual(DiagnosticServeur.masquer("clé \(cle)\n  fin"), "clé <clé> fin")
        // Le message serveur ne change jamais le résultat comparé.
        XCTAssertEqual(PermissionsEtabResult(success: false, role: nil, etablissementId: nil, permissions: .aucune, messageServeur: "x"),
                       PermissionsEtabResult(success: false, role: nil, etablissementId: nil, permissions: .aucune),
                       "le message serveur est exclu de l'égalité")
    }

    // MARK: Coupe-circuit distant de l'espace (T14, M1 de la revue de #1190)

    private func fixtureDrapeau(espace valeurs: [Bool?], gate: Gate? = nil) -> EtabFixture {
        var fixture = EtabFixture()
        fixture.flags = DrapeauEspaceScripte(script: DrapeauEspaceScript(valeurs), log: fixture.log, gate: gate)
        return fixture
    }

    /// Drapeau à 0 : exactement le refus d'un espace fermé (avant T14), sans aucun appel établissement ; le drapeau est
    /// lu après le rôle, avant `fn_mes_permissions_etab`.
    func testDrapeauEspaceA0RendLeRefusDAvantT14SansAppelEtablissement() async {
        for mode in [JoleneMode.staging, .production] {
            let fixture = fixtureDrapeau(espace: [false])
            let state = await SessionController(gateways: fixture.gateways(), espaceEtablissement: .pour(mode: mode)).start()
            await Self.verifierRefusDAvantLeLot5(state, log: fixture.log)
            let entries = await fixture.log.entries
            XCTAssertEqual(entries, ["restoreSession", "currentRole", "drapeau(\(EspaceEtablissementDrapeau.cle))"],
                           "\(mode) : drapeau lu après le rôle, aucun appel établissement")
        }
    }

    /// Drapeau à 1 : espace ouvert ; le drapeau est lu avant le périmètre serveur.
    func testDrapeauEspaceA1OuvreLEspace() async {
        let fixture = fixtureDrapeau(espace: [true])
        let state = await SessionController(gateways: fixture.gateways(), espaceEtablissement: .pour(mode: .production)).start()
        guard case .readyEtablissement = state else { return XCTFail("espace établissement attendu, reçu \(state)") }
        let entries = await fixture.log.entries
        XCTAssertEqual(entries, ["restoreSession", "currentRole", "drapeau(\(EspaceEtablissementDrapeau.cle))",
                                 "permissions(nil)", "profil"])
    }

    /// Absent, illisible ou en erreur (le port rend alors son défaut) : fail-open, comme les sept drapeaux d'écran.
    func testDrapeauEspaceAbsentOuIllisibleResteOuvertFailOpen() async {
        let fixture = fixtureDrapeau(espace: [nil])
        let state = await SessionController(gateways: fixture.gateways(), espaceEtablissement: .pour(mode: .production)).start()
        guard case .readyEtablissement = state else { return XCTFail("fail-open attendu, reçu \(state)") }
        let nonCable = EtabFixture() // UnwiredFlagsPort : défaut
        let ouvert = await nonCable.controller(espace: .ouvert).start()
        guard case .readyEtablissement = ouvert else { return XCTFail("port non câblé : fail-open attendu, reçu \(ouvert)") }
    }

    /// Délai de lecture épuisé : fail-open, l'espace s'ouvre quand même.
    func testDrapeauEspaceEnDelaiResteOuvertFailOpen() async {
        var fixture = fixtureDrapeau(espace: [false], gate: Gate()) // jamais ouverte
        fixture.timeout = 0.05
        let state = await fixture.controller(espace: .ouvert).start()
        guard case .readyEtablissement = state else { return XCTFail("délai épuisé : fail-open attendu, reçu \(state)") }
    }

    /// Fermeture à distance : un espace ouvert, revalidé (retour au premier plan) avec le drapeau passé à 0, rend le refus
    /// et avance l'epoch (les écrans établissement sont démontés), sans appel établissement de plus.
    func testDrapeauEspacePasseA0EnRevalidationFermeLEspaceEtAvanceLEpoch() async {
        let fixture = fixtureDrapeau(espace: [true, false])
        let controller = fixture.controller(espace: .ouvert)
        let premier = await controller.start()
        guard case .readyEtablissement = premier else { return XCTFail("espace ouvert attendu, reçu \(premier)") }
        let epoch = await controller.epoch
        let revalide = await controller.start()
        XCTAssertEqual(revalide, .blocked(.unsupportedRole("ADMIN_ETABLISSEMENT")), "même refus qu'un espace fermé")
        let apres = await controller.epoch
        XCTAssertEqual(apres, epoch + 1, "frontière de périmètre : epoch avancé")
        let permissionsLues = await fixture.log.entries.filter { $0.hasPrefix("permissions(") }.count
        XCTAssertEqual(permissionsLues, 1, "aucun appel établissement après la coupure")
    }

    /// Monde démo : `-JOLENE_FLAG_ios_natif_etab_espace_actif false` (`DemoFlagsGateway`) ferme l'espace de la même façon.
    func testDrapeauEspaceSurchargeDemoFermeLEspace() async {
        var fixture = EtabFixture()
        let surcharges = DemoFlagsGateway.surcharges(arguments: ["Jolene", "-JOLENE_FLAG_\(EspaceEtablissementDrapeau.cle)", "false"])
        XCTAssertEqual(surcharges, [EspaceEtablissementDrapeau.cle: false])
        fixture.flags = DemoFlagsGateway(surcharges: surcharges)
        let state = await SessionController(gateways: fixture.gateways(), espaceEtablissement: .pour(mode: .demo)).start()
        await Self.verifierRefusDAvantLeLot5(state, log: fixture.log)
        var ouverte = EtabFixture()
        ouverte.flags = DemoFlagsGateway()
        let ouvert = await SessionController(gateways: ouverte.gateways(), espaceEtablissement: .pour(mode: .demo)).start()
        guard case .readyEtablissement = ouvert else { return XCTFail("démo sans surcharge : espace ouvert, reçu \(ouvert)") }
    }

    /// Espace fermé (`.ferme`, défaut du contrôleur) : le coupe-circuit n'est jamais lu.
    func testDrapeauEspaceJamaisLuPourUnEspaceFerme() async {
        let fixture = fixtureDrapeau(espace: [true])
        _ = await SessionController(gateways: fixture.gateways()).start() // `.ferme`
        let lus = await fixture.log.entries.filter { $0.hasPrefix("drapeau(") }
        XCTAssertEqual(lus, [], "espace fermé : aucun drapeau lu")
    }

    func testPortSessionNonCableNOuvreJamaisLEspace() async {
        var gateways = EtabFixture().gateways()
        gateways.etablissement = .nonCable
        let state = await SessionController(gateways: gateways, espaceEtablissement: .ouvert).start()
        XCTAssertEqual(state, .signedOut(message: SessionController.sessionCheckFailedMessage),
                       "sans fn_mes_permissions_etab, aucun espace établissement ouvert")
    }

    // MARK: Échecs transitoires et délais

    func testEchecReseauDesPermissionsSansPurgeDeLaSession() async {
        let fixture = EtabFixture(permissions: [.failure(ErreurReseauEtab())])
        let state = await fixture.controller(espace: .ouvert).start()
        XCTAssertEqual(state, .signedOut(message: SessionController.sessionCheckFailedMessage))
        let signOuts = await fixture.log.signOutCount
        XCTAssertEqual(signOuts, 0, "une panne réseau ne purge pas la session persistée")
    }

    func testEchecReseauDuProfilSansPurgeDeLaSession() async {
        let fixture = EtabFixture(profils: [.failure(ErreurReseauEtab())])
        let state = await fixture.controller(espace: .ouvert).start()
        XCTAssertEqual(state, .signedOut(message: SessionController.profileLoadFailedMessage))
    }

    func testDelaiDesPermissionsEpuise() async {
        var fixture = EtabFixture()
        fixture.permissionsGate = Gate() // jamais ouverte
        fixture.timeout = 0.05
        let controller = fixture.controller(espace: .ouvert)
        let state = await controller.start()
        XCTAssertEqual(state, .signedOut(message: SessionController.sessionCheckFailedMessage))
        let epoch = await controller.epoch
        let gateways = await controller.gateways(for: epoch)
        XCTAssertNotNil(gateways, "aucune identité n'a changé")
    }

    func testDelaiDuProfilEpuise() async {
        var fixture = EtabFixture()
        fixture.profilGate = Gate()
        fixture.timeout = 0.05
        let state = await fixture.controller(espace: .ouvert).start()
        XCTAssertEqual(state, .signedOut(message: SessionController.profileLoadFailedMessage))
    }

    func testReponseDesPermissionsPerimeeApresDeconnexion() async {
        var fixture = EtabFixture()
        let gate = Gate()
        fixture.permissionsGate = gate
        let controller = fixture.controller(espace: .ouvert)
        let log = fixture.log
        let demarrage = Task { await controller.start() }
        await waitUntil { await log.entries.contains("permissions(nil)") }
        let deconnecte = await controller.signOut()
        XCTAssertEqual(deconnecte, .signedOut(message: nil))
        await gate.open()
        let tardif = await demarrage.value
        XCTAssertEqual(tardif, .signedOut(message: nil), "la réponse d'un epoch périmé est jetée")
        let state = await controller.state
        XCTAssertEqual(state, .signedOut(message: nil))
        let entries = await log.entries
        XCTAssertFalse(entries.contains("profil"), "aucun profil lu pour un epoch périmé")
    }

    // MARK: Revalidation (reprise après 30 minutes)

    func testRevalidationSilencieuseConserveLEspaceSurEchecTransitoire() async {
        let fixture = EtabFixture(permissions: [permissions(), .failure(ErreurReseauEtab())])
        let controller = fixture.controller(espace: .ouvert)
        let premier = await controller.start()
        XCTAssertNotNil(premier.snapshotEtablissement)
        let epoch = await controller.epoch
        let revalide = await controller.start()
        XCTAssertEqual(revalide, premier, "erreur transitoire en revalidation : espace conservé tel quel")
        let meme = await controller.epoch
        XCTAssertEqual(meme, epoch)
    }

    func testRevalidationSansPassageParChargement() async {
        var fixture = EtabFixture()
        let gate = Gate()
        fixture.permissionsGate = gate
        fixture.permissionsGateFromCall = 2
        let controller = fixture.controller(espace: .ouvert)
        _ = await controller.start()
        let log = fixture.log
        let revalidation = Task { await controller.start() }
        await waitUntil { await log.entries.filter { $0 == "permissions(nil)" }.count == 2 }
        let pendant = await controller.state
        XCTAssertNotNil(pendant.snapshotEtablissement, "aucun .loading pendant la revalidation : \(pendant)")
        await gate.open()
        let apres = await revalidation.value
        XCTAssertNotNil(apres.snapshotEtablissement)
    }

    func testRevalidationRemplaceRoleEtPermissionsAEpochConstant() async {
        let fixture = EtabFixture(permissions: [permissions(role: .rh, accordees: [.missions, .candidatures, .pointage, .lecture]),
                                                permissions(role: .lectureSeule, accordees: [.lecturePaiement, .lecture])])
        let controller = fixture.controller(espace: .ouvert)
        let premier = await controller.start()
        let epoch = await controller.epoch
        let revalide = await controller.start()
        XCTAssertEqual(revalide.snapshotEtablissement?.context.roleEtab, .lectureSeule)
        XCTAssertEqual(revalide.snapshotEtablissement?.context.permissions, PermissionsEtab(accordees: [.lecturePaiement, .lecture]))
        XCTAssertEqual(revalide.snapshotEtablissement?.epoch, premier.snapshotEtablissement?.epoch)
        let meme = await controller.epoch
        XCTAssertEqual(meme, epoch, "même identité, même établissement : epoch constant, écrans re-filtrés")
    }

    func testRevalidationQuiChangeDEtablissementBloqueEtAvanceLEpoch() async {
        let fixture = EtabFixture(roles: [.success(RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-1")),
                                          .success(RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-2"))],
                                  permissions: [permissions(etablissementId: "etab-1"), permissions(etablissementId: "etab-2")],
                                  profils: [profil("etab-1"), profil("etab-2")])
        let controller = fixture.controller(espace: .ouvert)
        _ = await controller.start()
        let epoch = await controller.epoch
        let revalide = await controller.start()
        XCTAssertEqual(revalide, .blocked(.unsupportedRole(SessionState.etabScopeDivergentCode)),
                       "membre de plusieurs établissements qui bascule : renvoi web, jamais un mélange")
        let apres = await controller.epoch
        XCTAssertEqual(apres, epoch + 1)
        let perime = await controller.gateways(for: epoch)
        XCTAssertNil(perime, "les caches de l'ancien établissement sont invalidés")
    }

    func testRevalidationQuiChangeDEspaceAvanceLEpoch() async {
        var fixture = EtabFixture(roles: [.success(RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-1")),
                                          .success(RoleResult(role: "SOIGNANT"))])
        fixture.profilSoignant = SoignantProfile(id: "membre-1", profession: "IDE")
        let controller = fixture.controller(espace: .ouvert)
        _ = await controller.start()
        let epoch = await controller.epoch
        let revalide = await controller.start()
        guard case let .ready(snapshot) = revalide else { return XCTFail("espace soignant attendu, obtenu \(revalide)") }
        let apres = await controller.epoch
        XCTAssertEqual(apres, epoch + 1, "changement d'espace à identité constante : frontière d'epoch")
        XCTAssertEqual(snapshot.epoch, apres)
        let perime = await controller.gateways(for: epoch)
        XCTAssertNil(perime)
    }

    func testRevalidationQuiRetireLAccesAvanceLEpoch() async {
        let fixture = EtabFixture(permissions: [permissions(), permissions(role: nil, etablissementId: nil, accordees: [])])
        let controller = fixture.controller(espace: .ouvert)
        _ = await controller.start()
        let epoch = await controller.epoch
        let revalide = await controller.start()
        XCTAssertEqual(revalide, .blocked(.unsupportedRole(SessionState.etabSansAccesCode)))
        let apres = await controller.epoch
        XCTAssertEqual(apres, epoch + 1)
    }

    // MARK: Relecture des permissions après un refus de droit (42501 en liste blanche)

    func testRelectureApresRefusRemplaceLesPermissionsUneSeuleFois() async {
        let fixture = EtabFixture(permissions: [permissions(role: .rh, accordees: [.missions, .candidatures, .pointage, .lecture]),
                                                permissions(role: .pointageOnly, accordees: [.pointage, .lecture])])
        let controller = fixture.controller(espace: .ouvert)
        let premier = await controller.start()
        let snapshot = try? XCTUnwrap(premier.snapshotEtablissement)
        let epoch = await controller.epoch
        let releve = await controller.refreshEtablissementScope(epoch: epoch)
        guard case let .readyEtablissement(maj) = releve else { return XCTFail("espace conservé attendu, obtenu \(releve)") }
        XCTAssertEqual(maj.context.roleEtab, .pointageOnly)
        XCTAssertEqual(maj.context.permissions, PermissionsEtab(accordees: [.pointage, .lecture]))
        XCTAssertEqual(maj.epoch, epoch, "seuls rôle et permissions changent : epoch constant")
        XCTAssertEqual(maj.etablissement, snapshot?.etablissement, "le profil n'est pas relu")
        let entries = await fixture.log.entries
        XCTAssertEqual(entries.filter { $0 == "permissions(nil)" }.count, 2, "une seule relecture par refus")
        XCTAssertEqual(entries.filter { $0 == "profil" }.count, 1)
        let signOuts = await fixture.log.signOutCount
        XCTAssertEqual(signOuts, 0, "un refus de droit ne déconnecte jamais")
    }

    func testRelectureQuiChangeDEtablissementBloqueEtAvanceLEpoch() async {
        let fixture = EtabFixture(permissions: [permissions(etablissementId: "etab-1"), permissions(etablissementId: "etab-2")])
        let controller = fixture.controller(espace: .ouvert)
        _ = await controller.start()
        let epoch = await controller.epoch
        let releve = await controller.refreshEtablissementScope(epoch: epoch)
        XCTAssertEqual(releve, .blocked(.unsupportedRole(SessionState.etabScopeDivergentCode)))
        let apres = await controller.epoch
        XCTAssertEqual(apres, epoch + 1)
        let perime = await controller.gateways(for: epoch)
        XCTAssertNil(perime)
    }

    func testRelectureMembreRevoqueBloqueEtAvanceLEpoch() async {
        let fixture = EtabFixture(permissions: [permissions(), permissions(role: nil, etablissementId: nil, accordees: [])])
        let controller = fixture.controller(espace: .ouvert)
        _ = await controller.start()
        let epoch = await controller.epoch
        let releve = await controller.refreshEtablissementScope(epoch: epoch)
        XCTAssertEqual(releve, .blocked(.unsupportedRole(SessionState.etabSansAccesCode)))
        let apres = await controller.epoch
        XCTAssertEqual(apres, epoch + 1)
    }

    func testRelectureEnEchecTransitoireConserveLEspace() async {
        let fixture = EtabFixture(permissions: [permissions(), .failure(ErreurReseauEtab())])
        let controller = fixture.controller(espace: .ouvert)
        let premier = await controller.start()
        let epoch = await controller.epoch
        let releve = await controller.refreshEtablissementScope(epoch: epoch)
        XCTAssertEqual(releve, premier, "relecture impossible : état conservé, jamais « session expirée »")
        let meme = await controller.epoch
        XCTAssertEqual(meme, epoch)
    }

    func testRelecturePourUnEpochPerimeEstSansEffet() async {
        let fixture = EtabFixture()
        let controller = fixture.controller(espace: .ouvert)
        let premier = await controller.start()
        let epoch = await controller.epoch
        let releve = await controller.refreshEtablissementScope(epoch: epoch - 1)
        XCTAssertEqual(releve, premier)
        let entries = await fixture.log.entries
        XCTAssertEqual(entries.filter { $0 == "permissions(nil)" }.count, 1, "aucune lecture pour un epoch périmé")
    }

    func testRelectureHorsEspaceEtablissementEstSansEffet() async {
        var fixture = EtabFixture(restored: utilisateurEtab(role: "SOIGNANT"), roles: [.success(RoleResult(role: "SOIGNANT"))])
        fixture.profilSoignant = SoignantProfile(id: "membre-1", profession: "IDE")
        let controller = fixture.controller(espace: .ouvert)
        let premier = await controller.start()
        XCTAssertNotNil(premier.snapshot)
        let epoch = await controller.epoch
        let releve = await controller.refreshEtablissementScope(epoch: epoch)
        XCTAssertEqual(releve, premier)
        let entries = await fixture.log.entries
        XCTAssertFalse(entries.contains("permissions(nil)"), "aucune lecture établissement pour un soignant")
    }

    func testReponseDeRelecturePerimeeApresDeconnexion() async {
        var fixture = EtabFixture()
        let gate = Gate()
        fixture.permissionsGate = gate
        fixture.permissionsGateFromCall = 2
        let controller = fixture.controller(espace: .ouvert)
        _ = await controller.start()
        let epoch = await controller.epoch
        let log = fixture.log
        let relecture = Task { await controller.refreshEtablissementScope(epoch: epoch) }
        await waitUntil { await log.entries.filter { $0 == "permissions(nil)" }.count == 2 }
        _ = await controller.signOut()
        await gate.open()
        let tardive = await relecture.value
        XCTAssertEqual(tardive, .signedOut(message: nil), "une relecture tardive ne ressuscite pas l'espace")
    }

    // MARK: Frontières d'identité

    func testDeconnexionPuisConnexionSoignantChangeDEspaceEtDEpoch() async {
        var fixture = EtabFixture(roles: [.success(RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-1")),
                                          .success(RoleResult(role: "SOIGNANT"))])
        fixture.signInResult = .success(utilisateurEtab("soignant-1", role: "SOIGNANT"))
        fixture.profilSoignant = SoignantProfile(id: "soignant-1", profession: "IDE")
        let controller = fixture.controller(espace: .ouvert)
        let etab = await controller.start()
        let epochEtab = try? XCTUnwrap(etab.snapshotEtablissement?.epoch)
        _ = await controller.signOut()
        let soignant = await controller.signIn(email: "soignant-1@example.invalid", password: "mot-de-passe")
        guard case let .ready(snapshot) = soignant else { return XCTFail("espace soignant attendu, obtenu \(soignant)") }
        XCTAssertEqual(snapshot.epoch, (epochEtab ?? 0) + 2, "déconnexion puis connexion : deux frontières d'identité")
        XCTAssertNil(soignant.snapshotEtablissement)
    }

    // MARK: Façade SwiftUI

    @MainActor
    func testStorePublieLaRelectureDesPermissions() async {
        let fixture = EtabFixture(permissions: [permissions(role: .proprietaire, accordees: [.lecture, .missions]),
                                                permissions(role: .lectureSeule, accordees: [.lecturePaiement, .lecture])])
        let store = SessionStore(controller: fixture.controller(espace: .ouvert))
        await store.start()
        XCTAssertEqual(store.state.snapshotEtablissement?.context.roleEtab, .proprietaire)
        await store.refreshEtablissementScope()
        XCTAssertEqual(store.state.snapshotEtablissement?.context.roleEtab, .lectureSeule)
        XCTAssertFalse(store.state.snapshotEtablissement?.context.permissions.missions ?? true, "écrans re-filtrés")
    }

    @MainActor
    func testStoreSansEspaceEtablissementNeRelitRien() async {
        let fixture = EtabFixture(restored: nil)
        let store = SessionStore(controller: fixture.controller(espace: .ouvert))
        await store.start()
        await store.refreshEtablissementScope()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        let entries = await fixture.log.entries
        XCTAssertFalse(entries.contains("permissions(nil)"))
    }

    /// Correction 12 : `fn_maj_activite_soignant` n'est jamais appelée pour un établissement, et aucun
    /// profil soignant n'est demandé. Garde de non-régression pour l'audit de session du lot 1 (T9).
    @MainActor
    func testAucuneActiviteSoignantNiProfilSoignantPourUnEtablissement() async {
        let fixture = EtabFixture(restored: nil)
        let store = SessionStore(controller: fixture.controller(espace: .ouvert))
        await store.start()
        await store.signIn(email: "membre-1@example.invalid", password: "mot-de-passe")
        XCTAssertNotNil(store.state.snapshotEtablissement)
        // Revalidation (reprise après 30 minutes) : la session persistée est celle de la connexion.
        await fixture.auth.set(restored: utilisateurEtab(), restoreError: nil)
        await store.start()
        XCTAssertNotNil(store.state.snapshotEtablissement)
        await store.signOut()
        // Laisse s'exécuter une éventuelle tâche d'audit non attendue.
        for _ in 0..<20 { await Task.yield() }
        let audit = await fixture.audit.journal.entries
        XCTAssertFalse(audit.contains("activite"), "aucune activité soignant pour un établissement : \(audit)")
        let entries = await fixture.log.entries
        XCTAssertFalse(entries.contains { $0.hasPrefix("profile(") }, "aucun profil soignant demandé : \(entries)")
    }
}
