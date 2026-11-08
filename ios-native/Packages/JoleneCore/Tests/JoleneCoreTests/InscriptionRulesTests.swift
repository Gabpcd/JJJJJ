import XCTest
@testable import JoleneCore

/// Règles pures du compte rapide soignant (lot 3, T7), portées de `src/pages/InscriptionRapide.tsx` l.55-115,
/// `src/lib/inscriptionProgressive.ts` l.26-99 et `mapperErreurInscription` (`src/lib/erreurs.ts` l.67-180).
final class InscriptionRulesTests: XCTestCase {
    private typealias T = InscriptionTextes

    // MARK: - Validation de saisie (l.58-70)

    func testEmailValideCommeLeMotifWeb() {
        for valide in ["a@b.c", " soignant@example.invalid ", "prenom.nom+tag@hopital.fr", "a@b.c.d", "x@y.z\n"] {
            XCTAssertTrue(InscriptionRules.emailValide(valide), valide)
        }
        for invalide in ["", "   ", "sans-arobase", "a@b", "a@.c", "@b.c", "a b@c.d", "a@b@c.d", "a@b.c d", "a@b\n.c"] {
            XCTAssertFalse(InscriptionRules.emailValide(invalide), invalide)
        }
    }

    func testEmailEnvoyeNormaliseCommeLeWeb() {
        XCTAssertEqual(InscriptionRules.emailNormalise("  Soignant@Example.Invalid \n"), "soignant@example.invalid")
    }

    func testErreursDeSaisieDansLOrdreDuFormulaireAvecLesTextesWeb() {
        let toutes = InscriptionRules.erreurs(email: "x", motDePasse: "1234567", profession: "", cgu: false)
        XCTAssertEqual(toutes, [.email: T.erreurEmail, .motDePasse: T.erreurMotDePasse,
                                .profession: T.erreurProfession, .cgu: T.erreurCGU])
        XCTAssertEqual(InscriptionRules.premierChampEnErreur(toutes), .email)
        let seulementCgu = InscriptionRules.erreurs(email: "a@b.c", motDePasse: "12345678", profession: "IDE", cgu: false)
        XCTAssertEqual(seulementCgu, [.cgu: T.erreurCGU])
        XCTAssertEqual(InscriptionRules.premierChampEnErreur(seulementCgu), .cgu)
        XCTAssertTrue(InscriptionRules.erreurs(email: "a@b.c", motDePasse: "12345678", profession: "IDE", cgu: true).isEmpty)
        XCTAssertNil(InscriptionRules.premierChampEnErreur([:]))
    }

    func testMotDePasseCompteEnUnitesUTF16CommeJavaScript() {
        // `form.password.length` : un emoji compte pour 2, un caractère accentué précomposé pour 1.
        XCTAssertNil(InscriptionRules.erreurs(email: "a@b.c", motDePasse: "😀😀😀😀", profession: "AS", cgu: true)[.motDePasse])
        XCTAssertEqual(InscriptionRules.erreurs(email: "a@b.c", motDePasse: "éééé", profession: "AS", cgu: true)[.motDePasse],
                       T.erreurMotDePasse)
    }

    func testSessionOuverteNeValideQueProfessionEtConsentement() {
        let erreurs = InscriptionRules.erreurs(email: "", motDePasse: "", profession: "", cgu: false, avecIdentifiants: false)
        XCTAssertEqual(erreurs, [.profession: T.erreurProfession, .cgu: T.erreurCGU])
    }

    // MARK: - Intention et métadonnées (l.46-52, l.74)

    func testIntentionSoignantEtMetadonneesIdentiquesAuWeb() {
        let intention = InscriptionRules.intention(profession: "IDE", cgu: true)
        XCTAssertEqual(intention, IntentionInscription(typeCompte: "SOIGNANT", profession: "IDE", nom: "", cgu: true, cgv: false))
        XCTAssertEqual(InscriptionRules.metadonnees(intention), .objet([
            "type": .chaine("SOIGNANT"), "profession": .chaine("IDE"), "nom": .chaine(""),
            "cgu": .booleen(true), "cgv": .booleen(false),
        ]))
        // `input.profession || null`, `input.nom || null`.
        XCTAssertNil(InscriptionRules.parametreTexte(""))
        XCTAssertNil(InscriptionRules.parametreTexte(nil))
        XCTAssertEqual(InscriptionRules.parametreTexte("IDE"), "IDE")
    }

    func testProfessionDuLienSeulementSiElleEstAuCatalogue() {
        XCTAssertEqual(InscriptionRules.professionDepuisLien(EtapeInscription(page: .soignant, query: "profession=IDE&ville=Lyon")), "IDE")
        XCTAssertEqual(InscriptionRules.professionDepuisLien(EtapeInscription(page: .soignant, query: "profession=PILOTE")), "")
        XCTAssertEqual(InscriptionRules.professionDepuisLien(EtapeInscription(page: .soignant, query: nil)), "")
        XCTAssertEqual(InscriptionRules.professionDepuisLien(nil), "")
        XCTAssertTrue(InscriptionRules.professionConnue("AUXILIAIRE_PUERICULTURE"))
        XCTAssertFalse(InscriptionRules.professionConnue("ide"), "comparaison exacte, comme le web")
    }

    func testRedirectionDuLienDeConfirmationVersLHoteWeb() {
        XCTAssertEqual(InscriptionRules.redirectionConfirmation.absoluteString, "https://jolene.app/inscription/confirmer")
        XCTAssertEqual(LinkRouter.resolve(link: InscriptionRules.redirectionConfirmation.absoluteString),
                       .confirmerInscription(credentials: nil), "le lien revient dans l'app par la route de confirmation")
    }

    // MARK: - Refus GoTrue du `signUp`

    func testCompteExistantDetecteCommeLeWeb() {
        XCTAssertTrue(InscriptionRules.estCompteExistant(messageServeur: "User already registered"))
        XCTAssertTrue(InscriptionRules.estCompteExistant(messageServeur: "A user with this email address has already been registered"))
        XCTAssertFalse(InscriptionRules.estCompteExistant(messageServeur: "Signups not allowed for this instance"))
    }

    func testRefusDeCreationTraduitsCommeMapperErreurInscription() {
        let cas: [(String, String?, String, String)] = [
            ("Password is known to be weak and easy to guess, please choose a different one.", "weak_password",
             "WEAK_PASSWORD", T.motDePasseDivulgue),
            ("Something", "weak_password", "WEAK_PASSWORD", T.motDePasseDivulgue),
            ("Email rate limit exceeded", "over_email_send_rate_limit", "EMAIL_RATE_LIMIT", T.tropDeTentatives),
            ("For security purposes, you can only request this once every 60 seconds", nil, "EMAIL_RATE_LIMIT", T.tropDeTentatives),
            ("Unable to validate email address: invalid email", "email_address_invalid", "INVALID_EMAIL", T.emailInvalide),
            ("Password should be at least 12 characters.", nil, "WEAK_PASSWORD", "Le mot de passe doit contenir au moins 12 caractères."),
            ("password is too short", nil, "WEAK_PASSWORD", T.motDePasseFaible),
            ("Signups not allowed for this instance", "signup_disabled", "UNKNOWN", T.erreurInattendue),
        ]
        for (message, code, codeAttendu, texte) in cas {
            let refus = InscriptionRules.refusCreation(messageServeur: message, codeServeur: code)
            XCTAssertEqual(refus.code, codeAttendu, message)
            XCTAssertEqual(refus.message, texte, message)
            XCTAssertFalse(refus.estCaptcha, message)
        }
    }

    func testRefusCaptchaRendLeMessageGeneriqueEtSonCode() {
        // Blueprint §3 T7 : « captcha refusé → message générique + renvoi web » (« Rafraîchissez la page » est sans
        // objet dans l'app) ; le code permet le renvoi web quand le présentateur `.safari` existe (D25).
        for (message, code) in [("captcha protection: request disallowed (invalid-input-response)", "captcha_failed"),
                                ("captcha verification process failed", nil)] {
            let refus = InscriptionRules.refusCreation(messageServeur: message, codeServeur: code)
            XCTAssertTrue(refus.estCaptcha, message)
            XCTAssertEqual(refus.message, T.erreurInattendue)
            XCTAssertFalse(refus.message.contains("Rafraîchissez"))
        }
    }

    // MARK: - Exceptions de `fn_demarrer_inscription`

    func testRefusDeDemarrage22023VerbatimServeur23505CommeLeWeb() {
        XCTAssertEqual(InscriptionRules.refusDemarrage(sqlstate: "22023", messageServeur: "Choisissez votre profession."),
                       RefusInscription(code: "SQLSTATE_22023", message: "Choisissez votre profession."))
        XCTAssertEqual(InscriptionRules.refusDemarrage(sqlstate: "22023", messageServeur: "  ").message, T.erreurInattendue)
        for code in ["ACCOUNT_ALREADY_REGISTERED", "ACCOUNT_TYPE_MISMATCH", "ACCOUNT_REGISTRATION_INCOMPLETE"] {
            XCTAssertEqual(InscriptionRules.refusDemarrage(sqlstate: "23505", messageServeur: code),
                           RefusInscription(code: "SQLSTATE_23505", message: T.compteDejaEspace), code)
        }
        for code in ["ACCOUNT_TYPE_INVALID", "ACCOUNT_AUTH_INACTIVE", "ACCOUNT_PROFILE_CONFLICT", "ACCOUNT_REGISTRATION_IN_PROGRESS"] {
            XCTAssertEqual(InscriptionRules.refusDemarrage(sqlstate: "23505", messageServeur: code).message, T.erreurInattendue, code)
        }
        XCTAssertEqual(InscriptionRules.codesEspaceExistant.count, 3)
    }

    func testMessagesDErreurDeTransport() {
        XCTAssertEqual(InscriptionRules.messageErreur(JoleneError(.network, "x")), T.connexionInstable)
        XCTAssertEqual(InscriptionRules.messageErreur(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")),
                       "Votre session a expiré. Reconnectez-vous.")
        XCTAssertEqual(InscriptionRules.messageErreur(JoleneError(.contract, "x")), T.erreurInattendue)
        XCTAssertEqual(InscriptionRules.messageErreur(RefusInscription(code: "C", message: "verbatim")), "verbatim")
        XCTAssertEqual(InscriptionRules.messageErreur(CancellationError()), T.erreurInattendue)
    }
}
