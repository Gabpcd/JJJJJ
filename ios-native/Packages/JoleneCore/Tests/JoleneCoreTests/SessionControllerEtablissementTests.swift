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
        gateways.etablissement.session = FakeEtabSession(script: session, log: log, permissionsGate: permissionsGate,
                                                         permissionsGateFromCall: permissionsGateFromCall, profilGate: profilGate)
        return gateways
    }

    func controller() -> SessionController { SessionController(gateways: gateways(), resolutionTimeout: timeout) }
}

// MARK: - Tests

/// Session de l'espace établissement (lot 5, T2a ; `LOT5_PLAN.md` §2.2, D1, D2, D3) : résolution par
/// `EspaceResolution`, périmètre confirmé par `fn_mes_permissions_etab(NULL)`, profil sous-ensemble,
/// revalidation silencieuse, relecture des permissions après un refus de droit, epoch à chaque frontière.
final class SessionControllerEtablissementTests: XCTestCase {

    // MARK: Ouverture de l'espace

    func testMembreConfirmeOuvreLEspaceEtablissement() async throws {
        let fixture = EtabFixture()
        let controller = fixture.controller()
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
        let state = await fixture.controller().start()
        XCTAssertEqual(state.snapshotEtablissement?.context.etablissementId, "etab-1",
                       "raccourci signé app_metadata, confirmé par fn_mes_permissions_etab : \(state)")
    }

    func testLegacyConfirmeParLePerimetreServeur() async {
        let legacy = utilisateurEtab("etab-legacy", role: "ETABLISSEMENT")
        let fixture = EtabFixture(restored: legacy, roles: [.success(RoleResult(role: "ADMIN_ETABLISSEMENT"))],
                                  permissions: [permissions(etablissementId: "etab-legacy")], profils: [profil("etab-legacy")])
        let state = await fixture.controller().start()
        guard case let .readyEtablissement(snapshot) = state else { return XCTFail("legacy confirmé attendu, obtenu \(state)") }
        XCTAssertEqual(snapshot.context.etablissementId, "etab-legacy", "le serveur confirme etablissements.id = user.id")
        XCTAssertEqual(snapshot.context.roleEtab, .proprietaire)
    }

    func testLegacyRefuseQuandLeServeurNeSertAucunRole() async {
        let legacy = utilisateurEtab("etab-legacy", role: "ETABLISSEMENT")
        let fixture = EtabFixture(restored: legacy, roles: [.success(RoleResult(role: "ADMIN_ETABLISSEMENT"))],
                                  permissions: [permissions(role: nil, etablissementId: nil)])
        let state = await fixture.controller().start()
        XCTAssertEqual(state, .blocked(.unsupportedRole(SessionState.etabSansAccesCode)))
        let entries = await fixture.log.entries
        XCTAssertFalse(entries.contains("profil"), "aucun profil lu sans périmètre confirmé")
    }

    func testMembreRevoqueEstBloqueSansAcces() async {
        let fixture = EtabFixture(permissions: [permissions(role: nil, etablissementId: nil, accordees: [])])
        let state = await fixture.controller().start()
        XCTAssertEqual(state, .blocked(.unsupportedRole(SessionState.etabSansAccesCode)))
        XCTAssertTrue(state.message?.contains("jolene.app") ?? false)
    }

    func testCandidatDivergentBloqueAvantToutProfil() async {
        let fixture = EtabFixture(permissions: [permissions(etablissementId: "etab-2")])
        let state = await fixture.controller().start()
        XCTAssertEqual(state, .blocked(.unsupportedRole(SessionState.etabScopeDivergentCode)))
        let entries = await fixture.log.entries
        XCTAssertFalse(entries.contains("profil"))
    }

    func testProfilDUnAutreEtablissementEstUneDivergence() async {
        let fixture = EtabFixture(profils: [profil("etab-2")])
        let state = await fixture.controller().start()
        XCTAssertEqual(state, .blocked(.unsupportedRole(SessionState.etabScopeDivergentCode)),
                       "un profil d'un autre établissement n'est jamais un repli")
    }

    func testCompteInactifRenvoieALaConnexionSansPurge() async {
        let fixture = EtabFixture(permissions: [permissions(role: nil, etablissementId: nil, accordees: [], success: false)])
        let state = await fixture.controller().start()
        XCTAssertEqual(state, .signedOut(message: SessionController.sessionCheckFailedMessage))
        let signOuts = await fixture.log.signOutCount
        XCTAssertEqual(signOuts, 0)
    }

    func testRoleEtablissementInconnuNOuvreJamaisLEspace() async {
        let fixture = EtabFixture(permissions: [permissions(role: .inconnu("ADMIN_PLATEFORME"), accordees: [])])
        let state = await fixture.controller().start()
        XCTAssertEqual(state, .blocked(.unsupportedRole("ADMIN_PLATEFORME")))
    }

    func testPortSessionNonCableNOuvreJamaisLEspace() async {
        var gateways = EtabFixture().gateways()
        gateways.etablissement = .nonCable
        let state = await SessionController(gateways: gateways).start()
        XCTAssertEqual(state, .signedOut(message: SessionController.sessionCheckFailedMessage),
                       "sans fn_mes_permissions_etab, aucun espace établissement ouvert")
    }

    // MARK: Échecs transitoires et délais

    func testEchecReseauDesPermissionsSansPurgeDeLaSession() async {
        let fixture = EtabFixture(permissions: [.failure(ErreurReseauEtab())])
        let state = await fixture.controller().start()
        XCTAssertEqual(state, .signedOut(message: SessionController.sessionCheckFailedMessage))
        let signOuts = await fixture.log.signOutCount
        XCTAssertEqual(signOuts, 0, "une panne réseau ne purge pas la session persistée")
    }

    func testEchecReseauDuProfilSansPurgeDeLaSession() async {
        let fixture = EtabFixture(profils: [.failure(ErreurReseauEtab())])
        let state = await fixture.controller().start()
        XCTAssertEqual(state, .signedOut(message: SessionController.profileLoadFailedMessage))
    }

    func testDelaiDesPermissionsEpuise() async {
        var fixture = EtabFixture()
        fixture.permissionsGate = Gate() // jamais ouverte
        fixture.timeout = 0.05
        let controller = fixture.controller()
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
        let state = await fixture.controller().start()
        XCTAssertEqual(state, .signedOut(message: SessionController.profileLoadFailedMessage))
    }

    func testReponseDesPermissionsPerimeeApresDeconnexion() async {
        var fixture = EtabFixture()
        let gate = Gate()
        fixture.permissionsGate = gate
        let controller = fixture.controller()
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
        let controller = fixture.controller()
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
        let controller = fixture.controller()
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
        let controller = fixture.controller()
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
        let controller = fixture.controller()
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
        let controller = fixture.controller()
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
        let controller = fixture.controller()
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
        let controller = fixture.controller()
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
        let controller = fixture.controller()
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
        let controller = fixture.controller()
        _ = await controller.start()
        let epoch = await controller.epoch
        let releve = await controller.refreshEtablissementScope(epoch: epoch)
        XCTAssertEqual(releve, .blocked(.unsupportedRole(SessionState.etabSansAccesCode)))
        let apres = await controller.epoch
        XCTAssertEqual(apres, epoch + 1)
    }

    func testRelectureEnEchecTransitoireConserveLEspace() async {
        let fixture = EtabFixture(permissions: [permissions(), .failure(ErreurReseauEtab())])
        let controller = fixture.controller()
        let premier = await controller.start()
        let epoch = await controller.epoch
        let releve = await controller.refreshEtablissementScope(epoch: epoch)
        XCTAssertEqual(releve, premier, "relecture impossible : état conservé, jamais « session expirée »")
        let meme = await controller.epoch
        XCTAssertEqual(meme, epoch)
    }

    func testRelecturePourUnEpochPerimeEstSansEffet() async {
        let fixture = EtabFixture()
        let controller = fixture.controller()
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
        let controller = fixture.controller()
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
        let controller = fixture.controller()
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
        let controller = fixture.controller()
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
        let store = SessionStore(controller: fixture.controller())
        await store.start()
        XCTAssertEqual(store.state.snapshotEtablissement?.context.roleEtab, .proprietaire)
        await store.refreshEtablissementScope()
        XCTAssertEqual(store.state.snapshotEtablissement?.context.roleEtab, .lectureSeule)
        XCTAssertFalse(store.state.snapshotEtablissement?.context.permissions.missions ?? true, "écrans re-filtrés")
    }

    @MainActor
    func testStoreSansEspaceEtablissementNeRelitRien() async {
        let fixture = EtabFixture(restored: nil)
        let store = SessionStore(controller: fixture.controller())
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
        let store = SessionStore(controller: fixture.controller())
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
