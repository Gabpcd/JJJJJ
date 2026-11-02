import XCTest
@testable import JoleneCore

/// Suppression de compte (lot 1, T8 ; Apple 5.1.1), port de `SectionConfidentialite.tsx` l.81-105 :
/// un seul appel, aucun renvoi, succès = réponse serveur seule (aucune relecture possible, le JWT est
/// révoqué), puis fin de session **locale** avant tout événement du SDK : l'écran « Compte supprimé »
/// s'affiche, jamais « Votre session a expiré ».
@MainActor
final class CompteModelTests: XCTestCase {
    private let utilisateur = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                appMetadataRole: "SOIGNANT")
    private let autreUtilisateur = AuthenticatedUser(id: "u-2", email: "u-2@example.invalid",
                                                     emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                     appMetadataRole: "SOIGNANT")

    /// Port d'auth du scénario : restauration de `u-1`, connexion de `u-2`, purge locale journalisée
    /// et, comme le SDK (`signOut(scope: .local)`, AuthClient l.1100-1102), un `.signedOut` émis par la purge.
    private struct CompteAuth: AuthPort, LocalSignOutPort {
        var restored: AuthenticatedUser
        var connecte: AuthenticatedUser
        var log: CallLog
        var events: AuthEventEmitter
        var purgeGate: Gate?

        func restoreSession() async throws -> AuthenticatedUser? { restored }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { connecte }
        func signOut() async throws { await log.record("signOut") }
        func authEvents() -> AsyncStream<AuthEvent> { events.stream() }
        func signOutLocally() async {
            await log.record("signOutLocally")
            events.emit(.signedOut)
            if let purgeGate { await purgeGate.wait() }
        }
    }

    private struct Scenario {
        var store: SessionStore
        var snapshot: SessionSnapshot
        var avis: AvisFinDeCompte
        var model: CompteModel
        var log: CallLog
        var events: AuthEventEmitter
        var appels: AccountCalls
        var preferences: UserDefaults
    }

    /// Domaine de préférences propre au test (jamais `UserDefaults.standard`) ; rien n'est écrit sur
    /// disque tant que le test n'y pose pas de clé.
    private func preferencesIsolees() -> UserDefaults {
        UserDefaults(suiteName: "jolene.tests.compte.\(UUID().uuidString)")!
    }

    private func scenario(compte: FakeAccount = FakeAccount(), timeout: TimeInterval = SessionController.defaultResolutionTimeout,
                          purgeGate: Gate? = nil, preferences: UserDefaults? = nil) async throws -> Scenario {
        let preferences = preferences ?? preferencesIsolees()
        let log = CallLog()
        let events = AuthEventEmitter()
        let auth = CompteAuth(restored: utilisateur, connecte: autreUtilisateur, log: log, events: events, purgeGate: purgeGate)
        var gateways = Lot1Fakes.gateways()
        gateways.auth = auth
        gateways.role = FakeRole(result: .success(RoleResult(role: "SOIGNANT")), gate: nil, log: log)
        gateways.missions = FakeMissions(profile: SoignantProfile(id: "u-1", profession: "IDE"), profileError: nil, gate: nil, log: log)
        gateways.compte = compte
        let store = SessionStore(controller: SessionController(gateways: gateways, resolutionTimeout: timeout))
        await store.start()
        let snapshot = try XCTUnwrap(store.state.snapshot, "session prête attendue, obtenu \(store.state)")
        let avis = AvisFinDeCompte()
        return Scenario(store: store, snapshot: snapshot, avis: avis,
                        model: CompteModel(session: store, snapshot: snapshot, avis: avis, preferences: preferences),
                        log: log, events: events, appels: compte.appels, preferences: preferences)
    }

    // MARK: - Succès

    func testSuppressionConfirmeeSignaleLaFinPuisRetireLIdentiteLocalement() async throws {
        let s = try await scenario(compte: FakeAccount(outcome: .deleted))
        XCTAssertEqual(s.model.etat, .pret)
        XCTAssertFalse(s.model.enCours)

        await s.model.supprimer()

        XCTAssertEqual(s.model.etat, .termine(.supprime))
        XCTAssertTrue(s.model.enCours, "plus aucune action possible : la racine de l'app prend le relais")
        XCTAssertEqual(s.avis.issue, .supprime, "écran « Compte supprimé » demandé")
        XCTAssertEqual(s.store.state, .signedOut(message: nil), "jamais « Votre session a expiré »")
        let epoch = await s.store.controller.epoch
        XCTAssertEqual(epoch, s.snapshot.epoch + 1, "identité retirée : caches invalidés")
        let appels = await s.appels.count
        XCTAssertEqual(appels, 1, "un seul appel, aucune relecture possible (JWT révoqué)")
        let journal = await s.log.entries
        XCTAssertTrue(journal.contains("signOutLocally"), "purge locale de la session (Keychain)")
        XCTAssertFalse(journal.contains("signOut"), "pas de révocation globale : l'edge a déjà révoqué les sessions")
    }

    func testLEvenementSignedOutDuSDKApresLaPurgeNAffichePasSessionExpiree() async throws {
        let s = try await scenario(compte: FakeAccount(outcome: .deleted))
        await s.model.supprimer()
        // L'identité est retirée AVANT la purge : l'événement du SDK arrive sans identité active.
        let etat = await s.store.controller.handleAuthEvent(.signedOut)
        XCTAssertEqual(etat, .signedOut(message: nil))
        XCTAssertNotEqual(etat, .signedOut(message: SessionController.sessionExpiredMessage))
    }

    func testLaFinEstSignaleeAvantQueLaPurgeNeSeTermine() async throws {
        // Purge bloquée : l'écran dédié est déjà demandé et l'identité déjà retirée.
        let purge = Gate()
        let s = try await scenario(compte: FakeAccount(outcome: .deleted), purgeGate: purge)
        let model = s.model, log = s.log
        let suppression = Task { await model.supprimer() }
        await waitUntil { await log.entries.contains("signOutLocally") }
        XCTAssertEqual(s.avis.issue, .supprime)
        let etat = await s.store.controller.state
        XCTAssertEqual(etat, .signedOut(message: nil))
        await purge.open()
        await suppression.value
        XCTAssertEqual(s.store.state, .signedOut(message: nil))
    }

    func testSuppressionConfirmeePurgeLesPreferencesLocalesDuCompteSeulement() async throws {
        // LOT1_PLAN l.252 : journal calendrier (T5) et préférence biométrie (T9), une clé par userId.
        let nom = "jolene.tests.compte.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: nom))
        defer { preferences.removePersistentDomain(forName: nom) }
        preferences.set(["m-1"], forKey: "jolene.calendrier.journal.u-1")
        preferences.set(true, forKey: "jolene.biometrie.activee.u-1")
        preferences.set(true, forKey: "jolene.biometrie.activee.u-2")
        preferences.set(true, forKey: "jolene.menu-1")
        let s = try await scenario(compte: FakeAccount(outcome: .deleted), preferences: preferences)

        await s.model.supprimer()

        XCTAssertNil(preferences.object(forKey: "jolene.calendrier.journal.u-1"))
        XCTAssertNil(preferences.object(forKey: "jolene.biometrie.activee.u-1"))
        XCTAssertEqual(preferences.bool(forKey: "jolene.biometrie.activee.u-2"), true, "un autre compte n'est pas touché")
        XCTAssertEqual(preferences.bool(forKey: "jolene.menu-1"), true, "segment entier exigé : « menu-1 » n'est pas « u-1 »")
    }

    func testUnRefusNePurgeAucunePreference() async throws {
        let nom = "jolene.tests.compte.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: nom))
        defer { preferences.removePersistentDomain(forName: nom) }
        preferences.set(true, forKey: "jolene.biometrie.activee.u-1")
        for issue in [DeleteAccountOutcome.refused(code: "ACCOUNT_PROFILE_CONFLICT", message: "M"),
                      .refused(code: "ANONYMISATION_NON_CONFIRMEE", message: "M")] {
            let s = try await scenario(compte: FakeAccount(outcome: issue), preferences: preferences)
            await s.model.supprimer()
            XCTAssertEqual(preferences.bool(forKey: "jolene.biometrie.activee.u-1"), true,
                           "suppression non confirmée : préférences conservées (\(issue))")
        }
    }

    // MARK: - Refus serveur

    func testRefus409AfficheLeMessageServeurVerbatimSansDeconnexion() async throws {
        let message = "Votre compte nécessite une vérification manuelle avant suppression."
        let s = try await scenario(compte: FakeAccount(outcome: .refused(code: "ACCOUNT_PROFILE_CONFLICT", message: message)))
        await s.model.supprimer()

        XCTAssertEqual(s.model.etat, .refuse(message: message))
        XCTAssertEqual(s.model.messageRefus, message)
        XCTAssertFalse(s.model.enCours, "une nouvelle tentative manuelle reste possible")
        XCTAssertEqual(s.model.tentatives, 1)
        XCTAssertNil(s.avis.issue)
        XCTAssertTrue(s.store.state.isReady, "la session reste ouverte")
        let epoch = await s.store.controller.epoch
        XCTAssertEqual(epoch, s.snapshot.epoch)
        let journal = await s.log.entries
        XCTAssertFalse(journal.contains("signOutLocally"))
    }

    func testRefusSansCodeEtLimiteDeDebitRestentAffichesSurLEcran() async throws {
        for (code, message) in [(String?.none, "Demande deja en cours"), (nil, "Demande de suppression déjà en cours."),
                                (nil, "Compte desactive"), ("DERNIER_PROPRIETAIRE", "Transferez d'abord le role de proprietaire a un autre membre.")] {
            let s = try await scenario(compte: FakeAccount(outcome: .refused(code: code, message: message)))
            await s.model.supprimer()
            XCTAssertEqual(s.model.etat, .refuse(message: message), "\(message)")
            XCTAssertNil(s.avis.issue)
            XCTAssertTrue(s.store.state.isReady)
        }
    }

    func testRefus503QuiLaissentUnCompteBanniOuAnonymiseForcentLaDeconnexionLocale() async throws {
        let cas = [
            ("AUTH_DELETE_PENDING", "Compte bloque et anonymise; suppression Auth en cours de finalisation"),
            ("ANONYMISATION_NON_CONFIRMEE", "Anonymisation du profil non confirmée ; suppression Auth non effectuée."),
        ]
        for (code, message) in cas {
            let s = try await scenario(compte: FakeAccount(outcome: .refused(code: code, message: message)))
            await s.model.supprimer()
            XCTAssertEqual(s.model.etat, .termine(.deconnecte(message: message)), code)
            XCTAssertEqual(s.avis.issue, .deconnecte(message: message), "message serveur verbatim sur l'écran de fin")
            XCTAssertEqual(s.store.state, .signedOut(message: nil), code)
            let journal = await s.log.entries
            XCTAssertTrue(journal.contains("signOutLocally"), code)
        }
    }

    func testUneNouvelleTentativeManuelleApresUnRefusEstPossibleUneFoisTermineePlusAucune() async throws {
        let s = try await scenario(compte: FakeAccount(outcome: .refused(code: nil, message: "Demande deja en cours")))
        await s.model.supprimer()
        await s.model.supprimer()
        var appels = await s.appels.count
        XCTAssertEqual(appels, 2, "chaque tentative est une action explicite de l'utilisateur")
        XCTAssertEqual(s.model.tentatives, 2, "jeton d'annonce VoiceOver renouvelé")

        let fini = try await scenario(compte: FakeAccount(outcome: .deleted))
        await fini.model.supprimer()
        await fini.model.supprimer()
        appels = await fini.appels.count
        XCTAssertEqual(appels, 1, "plus aucun appel une fois le compte supprimé")
    }

    // MARK: - Transport, délai, session

    func testErreurReseauNeConfirmeRienEtNeRenvoieRien() async throws {
        let s = try await scenario(compte: FakeAccount(erreur: JoleneError(.network, "Connexion impossible.")))
        await s.model.supprimer()
        XCTAssertEqual(s.model.etat, .refuse(message: CompteSuppression.confirmationIndisponibleMessage))
        XCTAssertTrue(s.store.state.isReady)
        XCTAssertNil(s.avis.issue)
        let appels = await s.appels.count
        XCTAssertEqual(appels, 1, "aucun renvoi automatique d'une mutation au résultat inconnu")
    }

    func testDelaiDepasseBorneAResolutionTimeoutSansRenvoi() async throws {
        let jamais = Gate()
        let s = try await scenario(compte: FakeAccount(outcome: .deleted, gate: jamais), timeout: 0.2)
        await s.model.supprimer()
        XCTAssertEqual(s.model.etat, .refuse(message: CompteSuppression.confirmationIndisponibleMessage),
                       "un délai dépassé ne prouve pas que le serveur n'a pas agi")
        XCTAssertTrue(s.store.state.isReady)
        let appels = await s.appels.count
        XCTAssertEqual(appels, 1)
        await jamais.open()
    }

    func testSessionExpireeEtRefusDeContratAffichentLeurMessage() async throws {
        let expiree = JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")
        let s = try await scenario(compte: FakeAccount(erreur: expiree))
        await s.model.supprimer()
        XCTAssertEqual(s.model.etat, .refuse(message: expiree.message))

        let contrat = JoleneError(.contract, "Cette version de l'application n'est plus compatible avec le service. Mettez-la à jour.")
        let c = try await scenario(compte: FakeAccount(erreur: contrat))
        await c.model.supprimer()
        XCTAssertEqual(c.model.etat, .refuse(message: contrat.message))
    }

    func testDoubleAppuiPendantLAppelNEnvoieQuUneSeuleDemande() async throws {
        let gate = Gate()
        let s = try await scenario(compte: FakeAccount(outcome: .deleted, gate: gate))
        let model = s.model, appelsRecus = s.appels
        let premier = Task { await model.supprimer() }
        await waitUntil { await appelsRecus.count == 1 }
        XCTAssertEqual(s.model.etat, .envoi)
        XCTAssertTrue(s.model.enCours)
        await s.model.supprimer()
        await gate.open()
        await premier.value
        let appels = await s.appels.count
        XCTAssertEqual(appels, 1)
        XCTAssertEqual(s.model.etat, .termine(.supprime))
    }

    // MARK: - Epoch d'identité

    func testEpochPerimeAvantLAppelAucuneDemandeEnvoyee() async throws {
        let s = try await scenario(compte: FakeAccount(outcome: .deleted))
        await s.store.signOut()
        await s.model.supprimer()
        let appels = await s.appels.count
        XCTAssertEqual(appels, 0, "l'identité a changé : jamais de suppression pour un autre epoch")
        XCTAssertEqual(s.model.etat, .pret)
        XCTAssertNil(s.avis.issue)
    }

    func testIdentiteRetireeParLeSDKPendantLAppelPuisSuccesAfficheQuandMemeCompteSupprime() async throws {
        let gate = Gate()
        let s = try await scenario(compte: FakeAccount(outcome: .deleted, gate: gate))
        let model = s.model, appelsRecus = s.appels
        let suppression = Task { await model.supprimer() }
        await waitUntil { await appelsRecus.count == 1 }
        // Rafraîchissement refusé par le SDK pendant l'appel (jetons révoqués par l'edge).
        let pendant = await s.store.controller.handleAuthEvent(.signedOut)
        XCTAssertEqual(pendant, .signedOut(message: SessionController.sessionExpiredMessage))
        await gate.open()
        await suppression.value
        XCTAssertEqual(s.avis.issue, .supprime, "l'écran dédié remplace « session expirée »")
        XCTAssertEqual(s.store.state, .signedOut(message: nil))
    }

    func testUneAutreIdentiteConnecteePendantLAppelNEstJamaisDeconnectee() async throws {
        let gate = Gate()
        let s = try await scenario(compte: FakeAccount(outcome: .deleted, gate: gate))
        let model = s.model, appelsRecus = s.appels
        let suppression = Task { await model.supprimer() }
        await waitUntil { await appelsRecus.count == 1 }
        _ = await s.store.controller.signOut()
        let autre = await s.store.controller.signIn(email: "u-2@example.invalid", password: "x")
        XCTAssertEqual(autre.snapshot?.user.id, "u-2")
        await gate.open()
        await suppression.value
        let etat = await s.store.controller.state
        XCTAssertEqual(etat.snapshot?.user.id, "u-2", "la session d'un autre utilisateur n'est pas touchée")
        XCTAssertNil(s.avis.issue)
        let journal = await s.log.entries
        XCTAssertFalse(journal.contains("signOutLocally"))
    }

    // MARK: - Fin de session locale (SessionController)

    func testSignOutLocallyRetireLIdentiteAvantLaPurgeEtIgnoreLEvenementDuSDK() async throws {
        let s = try await scenario()
        let controller = s.store.controller
        let etat = await controller.signOutLocally()
        XCTAssertEqual(etat, .signedOut(message: nil))
        let epoch = await controller.epoch
        XCTAssertEqual(epoch, s.snapshot.epoch + 1)
        let gateways = await controller.gateways(for: s.snapshot.epoch)
        XCTAssertNil(gateways, "l'ancien epoch n'est plus servi")
        let apres = await controller.handleAuthEvent(.signedOut)
        XCTAssertEqual(apres, .signedOut(message: nil))
        let journal = await s.log.entries
        XCTAssertEqual(journal.filter { $0 == "signOutLocally" }.count, 1)
        XCTAssertFalse(journal.contains("signOut"))
    }

    func testSignOutLocallyEstBorneQuandLaPurgeNeRendPasLaMain() async throws {
        let jamais = Gate()
        let s = try await scenario(timeout: 0.2, purgeGate: jamais)
        let etat = await s.store.controller.signOutLocally()
        XCTAssertEqual(etat, .signedOut(message: nil), "une purge muette ne retient pas la déconnexion")
        await jamais.open()
    }

    func testAuthPortSansPurgeLocaleSeRabatSurSignOut() async {
        let log = CallLog()
        let auth: AuthPort = FakeAuth(restored: nil, restoreError: nil, signInResult: .failure(nonScripte),
                                      signOutError: JoleneError(.network, "réseau"), signInGate: nil, log: log)
        await auth.signOutLocally()
        let journal = await log.entries
        XCTAssertEqual(journal, ["signOut"], "défaut : signOut toléré (erreur avalée)")
    }

    // MARK: - Avis de fin de compte

    func testAvisFinDeCompteSignaleEtAcquitte() {
        let avis = AvisFinDeCompte()
        XCTAssertNil(avis.issue)
        avis.signaler(.deconnecte(message: "M"))
        XCTAssertEqual(avis.issue, .deconnecte(message: "M"))
        avis.acquitter()
        XCTAssertNil(avis.issue)
    }
}

/// Règles pures et textes de la suppression de compte. Les textes RGPD sont ceux du web
/// (`SectionConfidentialite.tsx`, tutoiement, HARD STOP n°4) : leur égalité mot pour mot avec la
/// source web est vérifiée par `CompteSuppressionVerbatimTests` (JoleneSupabaseTests, `swift test`
/// macOS, qui lit le dépôt).
final class CompteSuppressionTests: XCTestCase {
    func testPhraseDeConfirmationEtMessagesParDefaut() {
        XCTAssertEqual(CompteSuppression.motConfirmation, "SUPPRIMER")
        XCTAssertEqual(CompteSuppression.refusParDefautMessage, "Suppression impossible.", "SectionConfidentialite.tsx l.89")
        XCTAssertFalse(CompteSuppression.confirmationIndisponibleMessage.isEmpty)
    }

    func testSeulsLesRefus503QuiLaissentUnCompteBanniOuAnonymiseForcentLaDeconnexion() {
        XCTAssertEqual(CompteSuppression.codesDeconnexionForcee, ["AUTH_DELETE_PENDING", "ANONYMISATION_NON_CONFIRMEE"])
        for code in ["AUTH_DELETE_PENDING", "ANONYMISATION_NON_CONFIRMEE"] {
            XCTAssertTrue(CompteSuppression.forceDeconnexion(code: code), code)
        }
        for code in [nil, "", "ACCOUNT_PROFILE_CONFLICT", "DERNIER_PROPRIETAIRE", "DERNIER_PROPRIETAIRE_GROUPE", "auth_delete_pending"] {
            XCTAssertFalse(CompteSuppression.forceDeconnexion(code: code), code ?? "nil")
        }
    }

    func testFinPourChaqueIssueDuPort() {
        XCTAssertEqual(CompteSuppression.fin(pour: .deleted), .supprime)
        XCTAssertEqual(CompteSuppression.fin(pour: .refused(code: "AUTH_DELETE_PENDING", message: "M")), .deconnecte(message: "M"))
        XCTAssertNil(CompteSuppression.fin(pour: .refused(code: "ACCOUNT_PROFILE_CONFLICT", message: "M")))
        XCTAssertNil(CompteSuppression.fin(pour: .refused(code: nil, message: "Demande deja en cours")))
    }

    func testPurgeDesPreferencesParSegmentDIdentifiant() throws {
        let nom = "jolene.tests.compte.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: nom))
        defer { preferences.removePersistentDomain(forName: nom) }
        let uid = "0b4d2b8e-4a9f-4b1c-9e0a-7f3c1d2e5a66"
        for cle in ["jolene.biometrie.activee.\(uid)", "jolene.calendrier:\(uid.uppercased())", "\(uid)/journal",
                    "jolene.biometrie.activee.autre", "jolene.\(uid)x", "jolene.x\(uid)"] {
            preferences.set(1, forKey: cle)
        }
        let purgees = CompteSuppression.purgerPreferencesLocales(userId: uid, defaults: preferences)
        XCTAssertEqual(Set(purgees), ["jolene.biometrie.activee.\(uid)", "jolene.calendrier:\(uid.uppercased())", "\(uid)/journal"])
        for cle in ["jolene.biometrie.activee.autre", "jolene.\(uid)x", "jolene.x\(uid)"] {
            XCTAssertNotNil(preferences.object(forKey: cle), "\(cle) conservée")
        }
        XCTAssertEqual(CompteSuppression.purgerPreferencesLocales(userId: "  ", defaults: preferences), [], "identifiant vide : rien")
    }

    func testTextesDeLEcranDeFin() {
        XCTAssertEqual(FinDeCompte.supprime.titre, "Compte supprimé")
        XCTAssertEqual(FinDeCompte.supprime.message, CompteSuppression.Textes.finSupprimeMessage)
        let forcee = FinDeCompte.deconnecte(message: "Compte bloque et anonymise; suppression Auth en cours de finalisation")
        XCTAssertEqual(forcee.titre, CompteSuppression.Textes.finDeconnecteTitre)
        XCTAssertEqual(forcee.message, "Compte bloque et anonymise; suppression Auth en cours de finalisation", "message serveur verbatim")
    }

    func testTextesRGPDDuWebEnTutoiementTantQueNonValides() {
        // Copie de référence (HARD STOP n°4) ; l'égalité avec la source web est gardée côté JoleneSupabaseTests.
        let t = CompteSuppression.Textes.self
        XCTAssertEqual(t.sectionTitre, "Suppression de compte")
        XCTAssertEqual(t.sectionAvertissement,
                       "La suppression de ton compte est irréversible. Tes données seront anonymisées conformément au RGPD.")
        XCTAssertEqual(t.boutonOuvrir, "Supprimer mon compte")
        XCTAssertEqual(t.confirmationTitre, "Supprimer mon compte")
        XCTAssertEqual(t.confirmationAvertissement,
                       "Cette action est irréversible. Tes données seront anonymisées conformément au RGPD.")
        XCTAssertEqual(t.confirmationConsigne, "Tape SUPPRIMER pour confirmer.")
        XCTAssertEqual(t.confirmationExemple, "Tape SUPPRIMER")
        XCTAssertEqual(t.boutonAnnuler, "Annuler")
        XCTAssertEqual(t.boutonConfirmer, "Supprimer définitivement")
    }
}

/// Monde démo (blueprint §2.7) : « SUPPRIMER » → `{success:true}` relu dans l'acteur, aucun réseau,
/// refus de tout autre utilisateur.
final class DemoAccountGatewayTests: XCTestCase {
    func testSuppressionDemoRelueUneSeuleFois() async throws {
        let gateway = DemoAccountGateway()
        let avant = await gateway.estSupprime()
        XCTAssertFalse(avant)
        let issue = try await gateway.deleteAccount(context: DemoWorld.context)
        XCTAssertEqual(issue, .deleted)
        let apres = await gateway.estSupprime()
        XCTAssertTrue(apres, "succès relu dans le monde démo, jamais fabriqué")
        let second = try await gateway.deleteAccount(context: DemoWorld.context)
        XCTAssertEqual(second, .refused(code: nil, message: "Compte desactive"), "comme l'edge après une suppression (403)")
    }

    func testDemoRefuseUnAutreUtilisateurEtUnContexteIncoherent() async {
        var autre = DemoWorld.context
        autre.userId = "user-1"
        autre.profile.id = "user-1"
        do {
            _ = try await DemoAccountGateway().deleteAccount(context: autre)
            XCTFail("la démo ne supprime aucun autre compte")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .demoOnly)
        } catch { XCTFail("\(error)") }

        var incoherent = DemoWorld.context
        incoherent.profile.id = "user-1"
        do {
            _ = try await DemoAccountGateway().deleteAccount(context: incoherent)
            XCTFail("profil désynchronisé")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
        } catch { XCTFail("\(error)") }
    }

    func testChaqueMondeDemoRepartDUnCompteIntact() async throws {
        let premier = try XCTUnwrap(DemoWorld.gateways().compte as? DemoAccountGateway)
        _ = try await premier.deleteAccount(context: DemoWorld.context)
        let second = try XCTUnwrap(DemoWorld.gateways().compte as? DemoAccountGateway)
        let supprime = await second.estSupprime()
        XCTAssertFalse(supprime)
    }

    func testLaPurgeLocaleDuMondeDemoVideLaSession() async throws {
        let auth = DemoAuthGateway()
        _ = try await auth.signIn(email: DemoWorld.context.email ?? "", password: "x")
        await auth.signOutLocally()
        let restauree = try await auth.restoreSession()
        XCTAssertNil(restauree)
    }
}
