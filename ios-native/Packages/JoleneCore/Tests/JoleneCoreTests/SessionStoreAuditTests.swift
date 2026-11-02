import XCTest
@testable import JoleneCore

/// Audit de session (lot 1, T9, décision 5) : comme `src/contexts/AuthContext.tsx` l.169-210,
/// `fn_audit_connexion('CONNEXION')` + `fn_maj_activite_soignant()` après une connexion explicite
/// réussie (jamais après une restauration), `fn_audit_connexion('DECONNEXION')` AVANT la
/// révocation. Best-effort : borné à `resolutionTimeout`, jamais bloquant, jamais une erreur affichée.
@MainActor
final class SessionStoreAuditTests: XCTestCase {

    func testConnexionPuisActiviteUneSeuleFoisApresUneConnexionPrete() async {
        let monde = SessionDurcieMonde()
        let store = monde.store()
        await store.start()
        await store.signIn(email: "t9@example.invalid", password: "secret-value")
        XCTAssertTrue(store.state.isReady, "obtenu \(store.state)")
        await store.auditEnCours?.value
        let apresConnexion = await monde.journal.audits()
        XCTAssertEqual(apresConnexion, ["audit:connexion", "audit:activite"])

        // Reprise après 30 minutes (revalidation) : aucune nouvelle ligne d'audit.
        await store.start()
        await store.auditEnCours?.value
        let apresReprise = await monde.journal.audits()
        XCTAssertEqual(apresReprise, ["audit:connexion", "audit:activite"], "une seule écriture par connexion")
    }

    func testRestaurationDeSessionNAuditeJamais() async {
        let monde = SessionDurcieMonde(restored: soignantDurci)
        let store = monde.store()
        await store.start()
        XCTAssertTrue(store.state.isReady)
        await store.auditEnCours?.value
        let audits = await monde.journal.audits()
        XCTAssertEqual(audits, [], "une restauration n'est pas une connexion (web : audit dans connexion() seulement)")
        XCTAssertNil(store.auditEnCours)
    }

    func testEchecDAuditNEmpechePasLaSessionPrete() async {
        var monde = SessionDurcieMonde()
        monde.audit = ScriptedAudit(journal: monde.journal, erreur: JoleneError(.network, "réseau"))
        let store = monde.store()
        await store.signIn(email: "t9@example.invalid", password: "secret-value")
        XCTAssertTrue(store.state.isReady, "obtenu \(store.state)")
        await store.auditEnCours?.value
        XCTAssertTrue(store.state.isReady, "une erreur d'audit ne retransforme jamais la connexion en échec")
        XCTAssertNil(store.state.message)
        let audits = await monde.journal.audits()
        XCTAssertEqual(audits, ["audit:connexion", "audit:activite"], "l'activité est tentée même si l'audit a échoué (appels indépendants, web)")
    }

    func testAuditMuetNeRetientPasLaConnexion() async {
        let gate = Gate()
        var monde = SessionDurcieMonde()
        monde.audit = ScriptedAudit(journal: monde.journal, gate: gate)
        let store = monde.store()
        await store.signIn(email: "t9@example.invalid", password: "secret-value")
        XCTAssertTrue(store.state.isReady, "la connexion rend la main sans attendre l'audit")
        let journal = monde.journal
        await waitUntil { await journal.audits() == ["audit:connexion"] }
        await gate.open()
        await store.auditEnCours?.value
        let audits = await monde.journal.audits()
        XCTAssertEqual(audits, ["audit:connexion", "audit:activite"])
    }

    func testAuditBorneParLeDelaiDeResolution() async {
        let gate = Gate()
        var monde = SessionDurcieMonde()
        monde.timeout = 0.05
        monde.audit = ScriptedAudit(journal: monde.journal, gate: gate)
        let store = monde.store()
        await store.signIn(email: "t9@example.invalid", password: "secret-value")
        await store.auditEnCours?.value
        // Barrière jamais ouverte : chaque appel est abandonné au délai, l'activité est quand même tentée.
        let audits = await monde.journal.audits()
        XCTAssertEqual(audits, ["audit:connexion", "audit:activite"])
        XCTAssertTrue(store.state.isReady)
        await gate.open()
    }

    func testDeconnexionAuditeeAvantLaRevocation() async {
        let monde = SessionDurcieMonde()
        let store = monde.store()
        await store.signIn(email: "t9@example.invalid", password: "secret-value")
        await store.auditEnCours?.value
        await store.signOut()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        let entrees = await monde.journal.entries
        XCTAssertEqual(entrees, ["signIn", "audit:connexion", "audit:activite", "audit:deconnexion", "signOut"],
                       "DECONNEXION part avec le jeton encore valide, avant signOut (web l.202-208)")
    }

    func testDeconnexionMalgreUnAuditEnEchecOuMuet() async {
        var monde = SessionDurcieMonde(restored: soignantDurci)
        monde.audit = ScriptedAudit(journal: monde.journal, erreur: JoleneError(.unknown, "refus"))
        let store = monde.store()
        await store.start()
        await store.signOut()
        XCTAssertEqual(store.state, .signedOut(message: nil), "un audit refusé ne bloque pas la déconnexion")
        let entrees = await monde.journal.entries
        XCTAssertEqual(entrees.suffix(2), ["audit:deconnexion", "signOut"])

        let gate = Gate()
        var muet = SessionDurcieMonde(restored: soignantDurci)
        muet.timeout = 0.05
        muet.audit = ScriptedAudit(journal: muet.journal, gate: gate)
        let store2 = muet.store()
        await store2.start()
        await store2.signOut()
        XCTAssertEqual(store2.state, .signedOut(message: nil), "audit muet : borné, puis déconnexion")
        let entrees2 = await muet.journal.entries
        XCTAssertEqual(entrees2.suffix(2), ["audit:deconnexion", "signOut"])
        await gate.open()
    }

    func testCompteBloqueAuditeLaConnexionEtLaDeconnexionSansActivite() async {
        var monde = SessionDurcieMonde()
        monde.role = "ADMIN_ETABLISSEMENT"
        let store = monde.store()
        await store.signIn(email: "t9@example.invalid", password: "secret-value")
        guard case .blocked = store.state else { return XCTFail("obtenu \(store.state)") }
        await store.auditEnCours?.value
        let apresConnexion = await monde.journal.audits()
        XCTAssertEqual(apresConnexion, ["audit:connexion"],
                       "session Auth ouverte : connexion journalisée (web) ; activité réservée au soignant servi")
        await store.signOut()
        let entrees = await monde.journal.entries
        XCTAssertEqual(entrees.suffix(2), ["audit:deconnexion", "signOut"])
    }

    func testConnexionRefuseeEtDeconnexionSansSessionNAuditentRien() async {
        var monde = SessionDurcieMonde()
        monde.signInUser = nil
        let store = monde.store()
        await store.start()
        await store.signIn(email: "t9@example.invalid", password: "mauvais")
        XCTAssertEqual(store.state, .signedOut(message: SessionController.genericSignInMessage))
        XCTAssertNil(store.auditEnCours)
        await store.signOut()
        let audits = await monde.journal.audits()
        XCTAssertEqual(audits, [], "aucune session : rien à journaliser")
    }

    func testDoubleAppuiSurDeconnexionNAuditeQuUneFois() async {
        let gate = Gate()
        var monde = SessionDurcieMonde(restored: soignantDurci)
        monde.audit = ScriptedAudit(journal: monde.journal, gate: gate)
        let store = monde.store()
        await store.start()
        let journal = monde.journal
        async let premier: Void = store.signOut()
        await waitUntil { await journal.audits() == ["audit:deconnexion"] }
        await store.signOut()
        await gate.open()
        await premier
        let entrees = await monde.journal.entries
        XCTAssertEqual(entrees.filter { $0 == "audit:deconnexion" }.count, 1)
        XCTAssertEqual(entrees.filter { $0 == "signOut" }.count, 1)
        XCTAssertEqual(store.state, .signedOut(message: nil))
    }
}
