import XCTest

/// Décisions de la garde de repos XCUITest (`PartageUITests/GardeReposDecision.swift`, compilé aussi dans JoleneUITests).
/// La pose de la garde et son effet sur XCTest ne se prouvent qu'en CI (`DemoGardeReposTests`, socle du job `ui`).
final class GardeReposDecisionTests: XCTestCase {
    func testFormesConnuesSeulement() {
        XCTAssertEqual(GardeReposDecision.forme(selecteur: "waitForQuiescenceIncludingAnimationsIdle:usingActivity:isPreEvent:",
                                                encodage: "v28@0:8B16B20B24"), .troisBooleens, "relevé sur Xcode 16.4")
        XCTAssertEqual(GardeReposDecision.forme(selecteur: "waitForQuiescenceIncludingAnimationsIdle:isPreEvent:",
                                                encodage: "v24@0:8B16B20"), .deuxBooleens)
        XCTAssertEqual(GardeReposDecision.forme(selecteur: "waitForQuiescenceIncludingAnimationsIdle:usingActivity:isPreEvent:",
                                                encodage: "v32@0:8B16@20B28"), .activiteObjet)
        // Retour non vide, argument d'un autre type, nombre d'arguments incohérent, autre sélecteur : rien n'est enveloppé.
        XCTAssertNil(GardeReposDecision.forme(selecteur: "waitForQuiescenceIncludingAnimationsIdle:isPreEvent:", encodage: "B24@0:8B16B20"))
        XCTAssertNil(GardeReposDecision.forme(selecteur: "waitForQuiescenceIncludingAnimationsIdle:isPreEvent:", encodage: "v24@0:8c16c20"))
        XCTAssertNil(GardeReposDecision.forme(selecteur: "waitForQuiescenceIncludingAnimationsIdle:isPreEvent:", encodage: "v28@0:8B16B20B24"))
        XCTAssertNil(GardeReposDecision.forme(selecteur: "_initiateQuiescenceChecksIncludingAnimationsIdle:", encodage: "v20@0:8B16"))
    }

    func testAucuneAttenteExpireeNeChangeRien() {
        let etat = GardeReposDecision()
        XCTAssertTrue(etat.avecAnimations(processus: 42, demande: true))
        XCTAssertFalse(etat.avecAnimations(processus: 42, demande: false), "une demande sans animations reste sans animations")
        XCTAssertFalse(etat.aVerifier(processus: 42, avecAnimations: true, duree: 49.9))
        XCTAssertFalse(etat.aVerifier(processus: 42, avecAnimations: false, duree: 61), "attente sans animations : hors de la garde")
        XCTAssertTrue(etat.aVerifier(processus: 42, avecAnimations: true, duree: 60.1))
    }

    func testExpirationDesAnimationsSuspendCeProcessusSeulement() {
        var etat = GardeReposDecision()
        XCTAssertTrue(etat.apresVerification(processus: 42, dureeAttente: 60.1, dureeBoucleSeule: 0.4), "première expiration")
        XCTAssertFalse(etat.avecAnimations(processus: 42, demande: true), "gestes suivants : boucle principale seule")
        XCTAssertTrue(etat.avecAnimations(processus: 43, demande: true), "un autre processus garde l'attente des animations")
        XCTAssertFalse(etat.aVerifier(processus: 42, avecAnimations: true, duree: 61), "processus déjà suspendu")
        XCTAssertFalse(etat.apresVerification(processus: 42, dureeAttente: 61, dureeBoucleSeule: 0.4), "une seule ligne par processus")
        etat.oublier()
        XCTAssertTrue(etat.avecAnimations(processus: 42, demande: true), "nouveau test, nouveau lancement : repart à zéro")
    }

    func testBouclePrincipaleLenteNeSuspendRien() {
        var etat = GardeReposDecision()
        XCTAssertFalse(etat.apresVerification(processus: 42, dureeAttente: 60, dureeBoucleSeule: 12), "app occupée : rien n'est masqué")
        XCTAssertTrue(etat.avecAnimations(processus: 42, demande: true))
        XCTAssertTrue(etat.aVerifier(processus: 42, avecAnimations: true, duree: 60), "deuxième vérification permise")
        _ = etat.apresVerification(processus: 42, dureeAttente: 60, dureeBoucleSeule: 12)
        _ = etat.apresVerification(processus: 42, dureeAttente: 60, dureeBoucleSeule: 12)
        XCTAssertFalse(etat.aVerifier(processus: 42, avecAnimations: true, duree: 60), "trois vérifications au plus par processus")
        XCTAssertTrue(etat.aVerifier(processus: 7, avecAnimations: true, duree: 60), "compte propre à chaque processus")
    }

    func testLignesDuJournal() {
        XCTAssertEqual(GardeReposDecision.ligneExpiration(duree: 60.6, test: "-[DemoGardeReposTests testX]"),
                       "Jolene diagnostic repos-xcuitest : attente des animations expirée (61 s) pendant -[DemoGardeReposTests testX] ; "
                       + "attente des animations suspendue pour ce processus")
        XCTAssertEqual(GardeReposDecision.ligneNonInstallee(vus: []),
                       "Jolene diagnostic repos-xcuitest : garde de repos non installée : aucun sélecteur vu")
        XCTAssertTrue(GardeReposDecision.ligneInstallee(selecteurs: ["b", "a"]).hasSuffix("installée sur a, b"))
    }
}
