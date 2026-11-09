import XCTest
@testable import JoleneCore

/// Inscription du monde démo (lot 3, T7 ; blueprint §2.7) : aucun réseau, comptes en mémoire vive partagés avec la
/// connexion démo, refus du serveur rejoués verbatim ; complétion (T8) : brouillon fusionné, référentiel du seed,
/// `register-soignant` simulée (contrôles et messages verbatim) puis bascule vers l'espace `demo-soignant`.
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

    // MARK: - Complétion (T8)

    /// Ouvre le nouveau compte démo (lien de confirmation) et démarre son parcours soignant.
    private func compteAvecParcours(refus: RefusInscriptionDemo? = nil,
                                    profession: String = "IDE") async throws -> (DemoAuthGateway, DemoInscriptionGateway) {
        let (auth, gateway) = monde(refus: refus)
        _ = try await gateway.creerCompte(email: "nouveau@example.invalid", motDePasse: "motdepasse",
                                          intention: InscriptionRules.intention(profession: profession, cgu: true))
        _ = try await auth.signIn(email: "nouveau@example.invalid", password: "motdepasse")
        _ = try await gateway.demarrer(intention: InscriptionRules.intention(profession: profession, cgu: true))
        return (auth, gateway)
    }

    private static func formulaire(profession: String = "IDE", rpps: String = "") -> FormulaireInscription {
        FormulaireInscription(prenom: "Léa", nom: "Martin", telephone: "0612345678", dateNaissance: "1990-05-14",
                              profession: profession, typesContrat: ["CDD"], rpps: rpps)
    }

    func testCompletionLivreeDansLeMondeDemo() {
        let (_, gateway) = monde()
        XCTAssertTrue(gateway.completionLivree, "T8 : brouillon, modes d'exercice et finalisation servis")
        XCTAssertTrue(DemoWorld.gateways().inscription.completionLivree)
        XCTAssertFalse(UnwiredInscriptionPort().completionLivree, "le stub non câblé reste verrouillé")
    }

    func testBrouillonFusionneEtReluSansParcoursRefuse() async throws {
        let (auth, sansParcours) = monde()
        _ = try await sansParcours.creerCompte(email: "n@example.invalid", motDePasse: "motdepasse", intention: intention)
        _ = try await auth.signIn(email: "n@example.invalid", password: "motdepasse")
        do {
            _ = try await sansParcours.enregistrerBrouillon(FormulaireInscription(prenom: "Léa"))
            XCTFail("P0002 attendu sans parcours")
        } catch let refus as RefusInscription {
            XCTAssertEqual(refus, RefusInscription(code: "SQLSTATE_P0002", message: "Inscription introuvable."))
        }
        let (_, gateway) = try await compteAvecParcours()
        let premier = try await gateway.enregistrerBrouillon(FormulaireInscription(prenom: "Léa", typesContrat: ["CDD"], rayon: 25))
        XCTAssertEqual(premier.brouillon.prenom, "Léa")
        XCTAssertEqual(premier.brouillon.profession, "IDE", "profession du parcours conservée")
        let second = try await gateway.enregistrerBrouillon(FormulaireInscription(nom: "Martin", typesContrat: ["CDD", "LIBERAL"]))
        XCTAssertEqual(second.brouillon.prenom, "Léa", "fusion de premier niveau : une clé absente est conservée")
        XCTAssertEqual(second.brouillon.nom, "Martin")
        XCTAssertEqual(second.brouillon.rayon, 25)
        XCTAssertEqual(second.brouillon.typesContrat, ["CDD", "LIBERAL"])
        let relu = try await gateway.parcours(userId: DemoInscriptionGateway.nouveauSoignantId)
        XCTAssertEqual(relu, second, "brouillon relu par la lecture du parcours")
    }

    func testReferentielDuSeedPourToutesLesIdentites() async throws {
        let (auth, gateway) = monde()
        _ = try await auth.signIn(email: DemoWorld.context.email ?? "", password: "x")
        let ide = try await gateway.typesExercice(profession: "IDE")
        XCTAssertEqual(ide, ["SALARIE", "LIBERAL", "MIXTE"], "référentiel public : servi aussi à l'espace démo (édition du profil)")
        let aideSoignant = try await gateway.typesExercice(profession: "AS")
        XCTAssertEqual(aideSoignant, ["SALARIE"])
        let inconnue = try await gateway.typesExercice(profession: "PILOTE")
        XCTAssertEqual(inconnue, ["SALARIE", "LIBERAL", "MIXTE"], "défaut serveur `COALESCE` d'une profession absente")
        let (_, indisponible) = monde(refus: .referentielIndisponible)
        do {
            _ = try await indisponible.typesExercice(profession: "IDE")
            XCTFail("référentiel indisponible attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .network)
        }
    }

    func testFinalisationBasculeVersLEspaceDemoApresRelecture() async throws {
        let (auth, gateway) = try await compteAvecParcours()
        let resultat = try await gateway.finaliser(Self.formulaire())
        XCTAssertEqual(resultat, .finalisee(soignantId: DemoWorld.context.userId))
        let restaure = try await auth.restoreSession()
        XCTAssertEqual(restaure, DemoWorld.user, "session relue : espace `demo-soignant` (blueprint §2.7)")
        do {
            _ = try await gateway.parcours(userId: DemoInscriptionGateway.nouveauSoignantId)
            XCTFail("le nouveau compte a disparu au profit de l'espace démo")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
    }

    func testFinalisationRefuseeCommeRegisterSoignantAvecSesMessagesVerbatim() async throws {
        let cas: [(RefusInscriptionDemo?, String, FormulaireInscription, ResultatFinalisation)] = [
            (.mineur, "IDE", Self.formulaire(),
             .refusee(code: "UNDERAGE", message: "Vous devez avoir au moins 18 ans pour vous inscrire.")),
            (.rppsDejaEnregistre, "IDE", Self.formulaire(),
             .refusee(code: "RPPS_ALREADY_REGISTERED",
                      message: "Ce numéro RPPS est déjà associé à un compte Jolene. Connectez-vous à ce compte, ou contactez le support si ce n'est pas vous.")),
            (.finalisationEnAttente, "IDE", Self.formulaire(),
             .finalisationEnAttente(message: "Votre profil est enregistré. Reconnectez-vous pour reprendre votre espace.")),
            (nil, "MEDECIN", Self.formulaire(profession: "MEDECIN"),
             .refusee(code: "RPPS_FORMAT_INVALID", message: "Le numéro RPPS est obligatoire pour votre profession (11 chiffres).")),
            (nil, "IDE", Self.formulaire(rpps: "123"),
             .refusee(code: "RPPS_FORMAT_INVALID", message: "Numéro RPPS invalide (11 chiffres attendus).")),
            (nil, "IDE", FormulaireInscription(prenom: "", nom: "Martin", dateNaissance: "1990-05-14", profession: "IDE"),
             .refusee(code: "MISSING_REQUIRED_FIELDS", message: "Champs obligatoires manquants (prénom, nom, profession).")),
            (nil, "IDE", FormulaireInscription(prenom: "Léa", nom: "Martin", dateNaissance: "", profession: "IDE"),
             .refusee(code: "MISSING_REQUIRED_FIELDS", message: "Date de naissance requise.")),
        ]
        for (refus, profession, formulaire, attendu) in cas {
            let (auth, gateway) = try await compteAvecParcours(refus: refus, profession: profession)
            let resultat = try await gateway.finaliser(formulaire)
            XCTAssertEqual(resultat, attendu, "\(refus?.rawValue ?? "contrôle serveur")")
            let restaure = try await auth.restoreSession()
            XCTAssertEqual(restaure?.id, DemoInscriptionGateway.nouveauSoignantId, "refus : aucune bascule")
        }
    }

    func testArgumentsDeLancementDesRefusDeLaCompletion() {
        for refus in [RefusInscriptionDemo.mineur, .rppsDejaEnregistre, .finalisationEnAttente, .referentielIndisponible,
                      .compteDejaFinalise] {
            XCTAssertEqual(RefusInscriptionDemo(arguments: [RefusInscriptionDemo.argument, refus.rawValue]), refus)
        }
        XCTAssertEqual(RefusInscriptionDemo.compteDejaFinalise.rawValue, "ACCOUNT_ALREADY_REGISTERED")
    }

    /// Revue B8 de T8, M1 : 409 `ACCOUNT_ALREADY_REGISTERED` simulé — le profil existe déjà côté serveur (bascule vers
    /// l'espace démo faite) et la réponse est une issue inconnue, message serveur verbatim en repli : le modèle relit le
    /// rôle et ouvre l'espace.
    func testCompteDejaFinaliseRendUneIssueIndetermineeProfilExistant() async throws {
        let (auth, gateway) = try await compteAvecParcours(refus: .compteDejaFinalise)
        let resultat = try await gateway.finaliser(Self.formulaire())
        XCTAssertEqual(resultat, .indeterminee(message: "Ce compte soignant existe déjà. Connectez-vous pour continuer."))
        let restaure = try await auth.restoreSession()
        XCTAssertEqual(restaure, DemoWorld.user, "profil déjà créé : l'espace démo existe")
    }

    /// Revue B8 de T8, B1 : variante `JOLENE_DEMO_BROUILLON=etudiant` (brouillon d'un étudiant commencé sur le web) — la
    /// finalisation démo rend `.parcoursEtudiant` comme `register-soignant` n'est jamais appelée en production, sans
    /// bascule ; le brouillon fusionné garde la déclaration (jamais réécrite par le natif).
    func testBrouillonEtudiantNEstJamaisFinaliseEnDemo() async throws {
        XCTAssertEqual(VarianteBrouillonDemo(rawValue: "etudiant"), .etudiant)
        let auth = DemoAuthGateway()
        let gateway = DemoInscriptionGateway(auth: auth, brouillon: .etudiant)
        _ = try await gateway.confirmer(.tokenHash(tokenHash: DemoInscriptionGateway.tokenHashDemo, otpType: "signup"))
        let parcours = try await gateway.demarrer(intention: InscriptionRules.intention(profession: "AS", cgu: true))
        XCTAssertEqual(parcours.brouillon.estEtudiant, true)
        XCTAssertEqual(parcours.brouillon.profession, "AS")
        let resultat = try await gateway.finaliser(Self.formulaire(profession: "AS"))
        XCTAssertEqual(resultat, .parcoursEtudiant)
        let restaure = try await auth.restoreSession()
        XCTAssertEqual(restaure?.id, DemoInscriptionGateway.nouveauSoignantId, "aucune bascule vers l'espace démo")
        let relu = try await gateway.parcours(userId: DemoInscriptionGateway.nouveauSoignantId)
        XCTAssertEqual(relu?.brouillon.estEtudiant, true, "déclaration conservée (`donnees || p_donnees`)")
        XCTAssertEqual(relu?.brouillon.prenom, "Léa", "saisie du formulaire fusionnée")
    }

    /// Revue B8 de T8, m4 : la réponse « salarié(e) » est fusionnée dans le brouillon démo comme sur le serveur.
    func testReponseSalarieFusionneeDansLeBrouillonDemo() async throws {
        let (_, gateway) = try await compteAvecParcours()
        let relu = try await gateway.enregistrerBrouillon(FormulaireInscription(prenom: "Léa", estSalarieEtablissement: true))
        XCTAssertEqual(relu.brouillon.estSalarieEtablissement, true)
        let suivant = try await gateway.enregistrerBrouillon(FormulaireInscription(nom: "Martin"))
        XCTAssertEqual(suivant.brouillon.estSalarieEtablissement, true, "clé absente : conservée")
    }

    func testRefusDeLaCompletionSansEffetSurLaCreationDuCompte() async throws {
        for refus in [RefusInscriptionDemo.mineur, .rppsDejaEnregistre, .finalisationEnAttente, .referentielIndisponible,
                      .compteDejaFinalise] {
            let (_, gateway) = monde(refus: refus)
            let resultat = try await gateway.creerCompte(email: "a@b.c", motDePasse: "motdepasse", intention: intention)
            XCTAssertEqual(resultat, .confirmationEnvoyee, refus.rawValue)
        }
    }

    func testVarianteDeBrouillonSimuleUneRepriseSansModeCoche() async throws {
        XCTAssertEqual(VarianteBrouillonDemo(rawValue: "complet"), .complet)
        XCTAssertEqual(VarianteBrouillonDemo.variableEnvironnement, "JOLENE_DEMO_BROUILLON")
        let auth = DemoAuthGateway()
        let gateway = DemoInscriptionGateway(auth: auth, brouillon: .complet)
        _ = try await gateway.confirmer(.tokenHash(tokenHash: DemoInscriptionGateway.tokenHashDemo, otpType: "signup"))
        let parcours = try await gateway.demarrer(intention: InscriptionRules.intention(profession: "IDE", cgu: true))
        let brouillon = parcours.brouillon
        XCTAssertEqual(brouillon.profession, "IDE", "profession de l'intention, figée")
        XCTAssertEqual([brouillon.prenom, brouillon.nom], ["Camille", "Démo"])
        XCTAssertTrue(CompletionRules.telephoneValide(brouillon.telephone ?? ""))
        XCTAssertTrue(CompletionRules.majeur(dateNaissance: brouillon.dateNaissance, maintenant: DemoWorld.fixedNow))
        XCTAssertEqual(brouillon.typesContrat, [], "aucun mode coché : le choix reste à l'utilisateur")
        XCTAssertNil(brouillon.rpps)
        let sansVariante = try await DemoInscriptionGateway(auth: DemoAuthGateway()).typesExercice(profession: "AS")
        XCTAssertEqual(sansVariante, ["SALARIE"])
    }
}
