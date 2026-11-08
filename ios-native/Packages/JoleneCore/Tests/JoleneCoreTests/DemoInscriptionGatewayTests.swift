import XCTest
@testable import JoleneCore

/// Inscription du monde démo (lot 3, T7 ; blueprint §2.7) : aucun réseau, comptes en mémoire vive partagés avec la
/// connexion démo, refus du serveur rejoués verbatim, complétion (T8) refusée explicitement.
final class DemoInscriptionGatewayTests: XCTestCase {
    private let intention = InscriptionRules.intention(profession: "IDE", cgu: true)

    private func monde(refus: RefusInscriptionDemo? = nil) -> (DemoAuthGateway, DemoInscriptionGateway) {
        let auth = DemoAuthGateway()
        return (auth, DemoInscriptionGateway(auth: auth, refus: refus))
    }

    func testDemoWorldCableLInscriptionSurLaSessionDeLaConnexionDemo() async throws {
        let gateways = DemoWorld.gateways()
        XCTAssertTrue(gateways.inscription is DemoInscriptionGateway)
        XCTAssertFalse(gateways.unwiredPorts.contains("inscription"))
        let resultat = try await gateways.inscription.creerCompte(email: "Nouveau@Example.Invalid", motDePasse: "motdepasse",
                                                                 intention: intention)
        XCTAssertEqual(resultat, .confirmationEnvoyee)
        let user = try await gateways.auth.signIn(email: "nouveau@example.invalid", password: "motdepasse")
        XCTAssertEqual(user.id, DemoInscriptionGateway.nouveauSoignantId, "la connexion démo retrouve le compte créé")
        XCTAssertNotNil(user.emailConfirmedAt, "démo : confirmation réputée faite (aucun e-mail)")
        XCTAssertNil(user.appMetadataRole)
        let autre = try await gateways.auth.signIn(email: DemoWorld.context.email ?? "", password: "x")
        XCTAssertEqual(autre, DemoWorld.user, "toute autre adresse ouvre le compte démo du lot 0")
    }

    func testCompteDemoExistantEtRefusSimules() async throws {
        let (_, gateway) = monde()
        let existant = try await gateway.creerCompte(email: DemoWorld.context.email ?? "", motDePasse: "x", intention: intention)
        XCTAssertEqual(existant, .connexionRequise)
        let (_, compteExistant) = monde(refus: .compteExistant)
        let refusExistant = try await compteExistant.creerCompte(email: "a@b.c", motDePasse: "motdepasse", intention: intention)
        XCTAssertEqual(refusExistant, .connexionRequise)
        let (_, captcha) = monde(refus: .captcha)
        do {
            _ = try await captcha.creerCompte(email: "a@b.c", motDePasse: "motdepasse", intention: intention)
            XCTFail("refus captcha attendu")
        } catch let refus as RefusInscription {
            XCTAssertTrue(refus.estCaptcha)
            XCTAssertEqual(refus.message, InscriptionTextes.erreurInattendue)
        }
    }

    func testArgumentDeLancementDesRefus() {
        XCTAssertEqual(RefusInscriptionDemo(arguments: ["-JOLENE_MODE", "demo", "-JOLENE_DEMO_INSCRIPTION_REFUS", "CAPTCHA_FAILED"]), .captcha)
        XCTAssertEqual(RefusInscriptionDemo(arguments: ["-JOLENE_DEMO_INSCRIPTION_REFUS", "USER_ALREADY_REGISTERED"]), .compteExistant)
        XCTAssertNil(RefusInscriptionDemo(arguments: ["-JOLENE_DEMO_INSCRIPTION_REFUS"]))
        XCTAssertNil(RefusInscriptionDemo(arguments: ["-JOLENE_DEMO_INSCRIPTION_REFUS", "INCONNU"]))
        XCTAssertNil(RefusInscriptionDemo(arguments: []))
    }

    func testLienDeConfirmationDemoOuvreLeNouveauCompte() async throws {
        let (auth, gateway) = monde()
        let refus = try await gateway.confirmer(.tokenHash(tokenHash: "autre", otpType: "signup"))
        XCTAssertEqual(refus, .lienRefuse(message: InscriptionTextes.lienNonValide))
        let recuperation = try await gateway.confirmer(.tokenHash(tokenHash: "demo", otpType: "recovery"))
        XCTAssertEqual(recuperation, .lienRefuse(message: InscriptionTextes.lienNonValide), "un lien de reset n'ouvre rien")
        let pkce = try await gateway.confirmer(.pkce(code: "demo"))
        XCTAssertEqual(pkce, .lienRefuse(message: InscriptionTextes.lienNonValide))
        let restaureAvant = try await auth.restoreSession()
        XCTAssertNil(restaureAvant)

        let confirme = try await gateway.confirmer(.tokenHash(tokenHash: DemoInscriptionGateway.tokenHashDemo, otpType: "signup"))
        XCTAssertEqual(confirme, .sessionOuverte)
        let restaure = try await auth.restoreSession()
        XCTAssertEqual(restaure?.id, DemoInscriptionGateway.nouveauSoignantId, "session relue après la confirmation")
        let contexte = try await gateway.contexte()
        XCTAssertEqual(contexte?.intention, intention, "compte par défaut : IDE, CGU acceptées")
        XCTAssertEqual(contexte?.emailConfirme, true)
    }

    func testParcoursDemarreUneFoisPuisRelu() async throws {
        let (auth, gateway) = monde()
        _ = try await gateway.creerCompte(email: "nouveau@example.invalid", motDePasse: "motdepasse", intention: intention)
        _ = try await auth.signIn(email: "nouveau@example.invalid", password: "motdepasse")
        let id = DemoInscriptionGateway.nouveauSoignantId
        let avant = try await gateway.parcours(userId: id)
        XCTAssertNil(avant)
        let demarre = try await gateway.demarrer(intention: intention)
        XCTAssertEqual(demarre.typeCompte, "SOIGNANT")
        XCTAssertEqual(demarre.brouillon.profession, "IDE")
        XCTAssertNotNil(demarre.consentementCguLe, "preuve serveur du consentement (défaut de colonne)")
        let second = try await gateway.demarrer(intention: InscriptionRules.intention(profession: "AS", cgu: true))
        XCTAssertEqual(second, demarre, "ON CONFLICT DO NOTHING : la ligne existante est rendue")
        let relu = try await gateway.parcours(userId: id)
        XCTAssertEqual(relu, demarre)
    }

    func testDemarrageRefuseCommeLeServeurAvecSesMessagesVerbatim() async throws {
        let (auth, gateway) = monde()
        _ = try await gateway.creerCompte(email: "n@example.invalid", motDePasse: "motdepasse", intention: intention)
        _ = try await auth.signIn(email: "n@example.invalid", password: "motdepasse")
        let cas: [(IntentionInscription, String)] = [
            (InscriptionRules.intention(profession: "IDE", cgu: false), "Vérifiez le type de compte et les conditions acceptées."),
            (InscriptionRules.intention(profession: "PILOTE", cgu: true), "Choisissez votre profession."),
            (IntentionInscription(typeCompte: "ADMIN", profession: "IDE", cgu: true), "Vérifiez le type de compte et les conditions acceptées."),
        ]
        for (refusee, message) in cas {
            do {
                _ = try await gateway.demarrer(intention: refusee)
                XCTFail("refus attendu pour \(refusee)")
            } catch let refus as RefusInscription {
                XCTAssertEqual(refus, RefusInscription(code: "SQLSTATE_22023", message: message))
            }
        }
    }

    func testLaDemoNeSertQueSonNouveauCompte() async throws {
        let (auth, gateway) = monde()
        _ = try await auth.signIn(email: DemoWorld.context.email ?? "", password: "x")
        let intention = self.intention
        let operations: [() async throws -> Void] = [
            { _ = try await gateway.demarrer(intention: intention) },
            { _ = try await gateway.parcours(userId: DemoWorld.context.userId) },
        ]
        for operation in operations {
            do {
                try await operation()
                XCTFail("refus attendu")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .demoOnly)
            }
        }
        let contexte = try await gateway.contexte()
        XCTAssertEqual(contexte?.userId, DemoWorld.context.userId)
        XCTAssertNil(contexte?.intention)
    }

    /// Verrou du gap T8 (`CLAUDE.md`, « un gap connu reste verrouillé ») : brouillon, modes d'exercice et finalisation
    /// refusent explicitement dans les deux mondes tant que T8 n'est pas livrée.
    func testCompletionRefuseeJusquATrancheT8() async {
        let (_, gateway) = monde()
        let attendu = UnwiredPorts.erreur(port: "complétion de l'inscription", tranche: "T8", lot: 3)
        XCTAssertTrue(attendu.message.contains("T8 du lot 3"))
        let operations: [() async throws -> Void] = [
            { _ = try await gateway.enregistrerBrouillon(FormulaireInscription(prenom: "Léa")) },
            { _ = try await gateway.typesExercice(profession: "IDE") },
            { _ = try await gateway.finaliser(FormulaireInscription(prenom: "Léa")) },
        ]
        for operation in operations {
            do {
                try await operation()
                XCTFail("refus T8 attendu")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur, attendu)
            } catch {
                XCTFail("erreur inattendue : \(error)")
            }
        }
    }
}
