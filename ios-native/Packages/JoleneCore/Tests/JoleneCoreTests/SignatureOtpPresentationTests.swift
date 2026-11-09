import XCTest
@testable import JoleneCore

/// Lot 2, T9b — présentation de la zone « Votre signature » (`Contrats/SignatureOtpPresentation.swift`), rendu de
/// `SessionSignatureOtp` (T8) tel que `SignerContratOtp.tsx` l.209-354 l'affiche : formulaire (case de consentement,
/// « Recevoir le code SMS pour signer », code envoyé, minuteur, tentatives, renvoi, « Signer »), confirmation après une
/// signature relue (l.209-221), indisponibilité bloquante du serveur (l.223-235 : `CONTRAT_INACTIF`,
/// `CONTRAT_DEJA_COMPLET`, `DEJA_SIGNE` seulement). Chaque texte vient de `TextesWeb.SignatureOtp` ou de
/// `LibellesWeb.SignatureOtp` (verbatim, gardés par TL) ; aucun texte n'est écrit ici.
final class SignatureOtpPresentationTests: XCTestCase {
    private struct ModeInattendu: Error {}
    private let t0 = Date(timeIntervalSince1970: 1_793_577_600)
    private let empreinte = String(repeating: "a", count: 64)

    private func session(pret: Bool = true) -> SessionSignatureOtp {
        SessionSignatureOtp(cle: CleSessionOtp(contratId: "contrat-a", empreinte: empreinte, documentPret: pret))
    }

    private func envoye(sms: Int? = 2, telephone: String? = "+**********00") -> IssueEnvoiOtp {
        .envoye(OtpEnvoye(role: "soignant", telephoneMasque: telephone, expireDansMinutes: 10, smsEnvoyes: 1, smsRestants: sms))
    }

    private func codeEnvoye(sms: Int? = 2) throws -> SessionSignatureOtp {
        var s = session()
        s.accepter(true)
        let demande = try XCTUnwrap(s.demanderEnvoi())
        s.terminerEnvoi(envoye(sms: sms), demande: demande, maintenant: t0)
        return s
    }

    private func presentation(_ s: SessionSignatureOtp, maintenant: Date? = nil, nouvelEnvoiAutorise: Bool = true,
                              actionsSuspendues: Bool = false) -> SignatureOtpPresentation {
        SignatureOtpPresentation(session: s, maintenant: maintenant ?? t0, nouvelEnvoiAutorise: nouvelEnvoiAutorise,
                                 actionsSuspendues: actionsSuspendues)
    }

    private func formulaire(_ p: SignatureOtpPresentation, file: StaticString = #filePath, line: UInt = #line)
        throws -> SignatureOtpPresentation.Formulaire {
        guard case .formulaire(let f) = p.mode else {
            XCTFail("formulaire attendu, obtenu \(p.mode)", file: file, line: line)
            throw ModeInattendu()
        }
        return f
    }

    // MARK: - Formulaire avant l'envoi

    func testRecevoirLeCodeDesactiveTantQueLaCaseNEstPasCochee() throws {
        var s = session()
        var f = try formulaire(presentation(s))
        XCTAssertEqual(f.titre, "Signature électronique sécurisée", "l.242")
        XCTAssertEqual(f.explication, TextesWeb.SignatureOtp.explication, "l.244-245")
        XCTAssertEqual(f.consentement, "J'ai lu l'intégralité du contrat affiché ci-dessus et j'accepte ses termes.", "l.276")
        XCTAssertFalse(f.accepte)
        XCTAssertTrue(f.consentementActif)
        XCTAssertEqual(f.recevoir?.libelle, "Recevoir le code SMS pour signer", "libellé exact l.288")
        XCTAssertEqual(f.recevoir?.actif, false, "désactivé tant que la case n'est pas cochée (l.284)")
        XCTAssertNil(f.codeEnvoye, "aucun champ de code avant l'envoi (l.292)")
        XCTAssertNil(f.alerte)
        XCTAssertNil(f.retour)
        XCTAssertNil(f.suspension)
        s.accepter(true)
        f = try formulaire(presentation(s))
        XCTAssertTrue(f.accepte)
        XCTAssertEqual(f.recevoir?.actif, true)
    }

    func testDocumentNonPretOuEnvoiNonAutoriseDesactiventLEnvoi() throws {
        var nonPret = session(pret: false)
        nonPret.accepter(true)
        XCTAssertEqual(try formulaire(presentation(nonPret)).recevoir?.actif, false, "documentPret faux (l.284)")
        var s = session()
        s.accepter(true)
        XCTAssertEqual(try formulaire(presentation(s, nouvelEnvoiAutorise: false)).recevoir?.actif, false,
                       "recette STAGING sans envoi autorisé (l.284)")
    }

    func testActionsSuspenduesPendantLaRelectureDeLAdmission() throws {
        var s = session()
        s.accepter(true)
        let f = try formulaire(presentation(s, actionsSuspendues: true))
        XCTAssertEqual(f.suspension, "Vérification de la signature en cours…", "l.265")
        XCTAssertFalse(f.consentementActif, "case désactivée (l.271)")
        XCTAssertEqual(f.recevoir?.actif, false, "l.284")
    }

    func testOperationEnCoursDesactiveEtAnnonceLeChargement() throws {
        var s = session()
        s.accepter(true)
        _ = try XCTUnwrap(s.demanderEnvoi())
        let f = try formulaire(presentation(s))
        XCTAssertTrue(f.enCours, "indicateur de chargement (l.287)")
        XCTAssertEqual(f.recevoir?.actif, false, "anti double envoi : bouton désactivé pendant la requête (l.284)")
    }

    // MARK: - Code envoyé

    func testCodeEnvoyeMinuteurEtSmsRestants() throws {
        let s = try codeEnvoye()
        let f = try formulaire(presentation(s))
        XCTAssertNil(f.recevoir, "« Recevoir le code » remplacé par le champ et ses boutons (l.280-292)")
        XCTAssertEqual(f.retour, .succes("Code envoyé au +**********00. Valide 10 min."), "l.151")
        let code = try XCTUnwrap(f.codeEnvoye)
        XCTAssertEqual(code.destinataire, "Code envoyé au +**********00", "l.296")
        XCTAssertEqual(code.smsRestants, "(2 envois restants)", "l.297-300")
        XCTAssertEqual(code.minuteur, "10:00", "l.110")
        XCTAssertFalse(code.expire)
        XCTAssertTrue(code.champActif)
        XCTAssertNil(code.tentatives, "rien tant qu'aucun code faux n'est refusé (l.322)")
        XCTAssertEqual(code.renvoi, SignatureOtpPresentation.Bouton(libelle: "Renvoyer le code", actif: true, infobulle: nil))
        XCTAssertEqual(code.signer, SignatureOtpPresentation.Bouton(libelle: "Signer", actif: false, infobulle: nil),
                       "code incomplet : « Signer » désactivé (l.344)")
        let apres = try XCTUnwrap(try formulaire(presentation(s, maintenant: t0.addingTimeInterval(61))).codeEnvoye)
        XCTAssertEqual(apres.minuteur, "08:59", "minuteur dérivé de l'échéance, jamais décompté ailleurs")
    }

    func testSansNumeroNiSmsRestantsLeWebAfficheNumeroMasque() throws {
        var s = session()
        s.accepter(true)
        let demande = try XCTUnwrap(s.demanderEnvoi())
        s.terminerEnvoi(envoye(sms: nil, telephone: nil), demande: demande, maintenant: t0)
        let code = try XCTUnwrap(try formulaire(presentation(s)).codeEnvoye)
        XCTAssertEqual(code.destinataire, "Code envoyé au numéro masqué", "l.296")
        XCTAssertNil(code.smsRestants, "affiché seulement quand le serveur le donne (l.297)")
    }

    func testSixChiffresActiventSigner() throws {
        var s = try codeEnvoye()
        s.saisir("12345")
        XCTAssertEqual(try formulaire(presentation(s)).codeEnvoye?.signer.actif, false)
        s.saisir("123456")
        XCTAssertEqual(try formulaire(presentation(s)).codeEnvoye?.signer.actif, true)
        XCTAssertEqual(try formulaire(presentation(s, actionsSuspendues: true)).codeEnvoye?.signer.actif, false, "l.344")
        XCTAssertEqual(try formulaire(presentation(s, actionsSuspendues: true)).codeEnvoye?.champActif, false, "l.317")
        s.accepter(false)
        XCTAssertEqual(try formulaire(presentation(s)).codeEnvoye?.signer.actif, false, "consentement retiré (l.344)")
        XCTAssertEqual(try formulaire(presentation(s)).codeEnvoye?.renvoi.actif, false, "consentement retiré (l.335)")
    }

    func testCodeExpireAuMinuteurProposeUnNouveauCode() throws {
        var s = try codeEnvoye()
        s.saisir("123456")
        let code = try XCTUnwrap(try formulaire(presentation(s, maintenant: t0.addingTimeInterval(600))).codeEnvoye)
        XCTAssertEqual(code.minuteur, "Expiré", "l.305")
        XCTAssertTrue(code.expire)
        XCTAssertFalse(code.champActif, "champ désactivé une fois expiré (l.317)")
        XCTAssertEqual(code.renvoi.libelle, "Recevoir un nouveau code", "l.339")
        XCTAssertTrue(code.renvoi.actif)
        XCTAssertFalse(code.signer.actif, "l.344")
    }

    func testCodeIncorrectAfficheLesTentativesRestantes() throws {
        var s = try codeEnvoye()
        s.saisir("111111")
        let demande = try XCTUnwrap(s.demanderSignature(maintenant: t0))
        s.terminerSignature(.refuse(code: "OTP_INCORRECT", message: TextesWeb.SignatureOtp.otpIncorrect, tentativesRestantes: 4),
                            demande: demande)
        let f = try formulaire(presentation(s))
        XCTAssertEqual(f.retour, .erreur("Code incorrect. Vérifiez votre SMS et réessayez."), "MESSAGES_ERREUR l.40")
        XCTAssertEqual(f.codeEnvoye?.tentatives, "Code incorrect. 4 tentatives restantes.", "l.326")
    }

    func testPlusAucunSmsDesactiveLeRenvoiAvecSonInfobulle() throws {
        let s = try codeEnvoye(sms: 0)
        let code = try XCTUnwrap(try formulaire(presentation(s)).codeEnvoye)
        XCTAssertEqual(code.smsRestants, "(dernier envoi possible)", "formulation du web à 0 (l.299)")
        XCTAssertEqual(code.renvoi, SignatureOtpPresentation.Bouton(libelle: "Renvoyer le code", actif: false,
                                                                   infobulle: "3 SMS max par 24h atteints"), "l.335-336")
        let recette = try XCTUnwrap(try formulaire(presentation(try codeEnvoye(), nouvelEnvoiAutorise: false)).codeEnvoye)
        XCTAssertEqual(recette.renvoi.infobulle, "Aucun nouvel envoi autorisé pour cette recette", "l.336")
        XCTAssertFalse(recette.renvoi.actif)
    }

    // MARK: - Refus bloquants

    func testRefusBloquantDansLeFormulaireMasqueLeRetour() throws {
        var s = try codeEnvoye()
        s.saisir("123456")
        let demande = try XCTUnwrap(s.demanderSignature(maintenant: t0))
        s.terminerSignature(.refuse(code: "HASH_DOCUMENT_CHANGE", message: TextesWeb.SignatureOtp.hashDocumentChange,
                                    tentativesRestantes: nil), demande: demande)
        let f = try formulaire(presentation(s))
        XCTAssertEqual(f.alerte, TextesWeb.SignatureOtp.hashDocumentChange, "alerte du formulaire (l.250-255)")
        XCTAssertNil(f.retour, "retour masqué par l'erreur bloquante (l.257)")
        XCTAssertEqual(f.codeEnvoye?.signer.actif, false)
        XCTAssertEqual(f.codeEnvoye?.renvoi.actif, false)
    }

    func testSeulesTroisErreursBloquantesRendentLaSignatureIndisponible() throws {
        XCTAssertEqual(SignatureOtpPresentation.codesIndisponibles, ["CONTRAT_INACTIF", "CONTRAT_DEJA_COMPLET", "DEJA_SIGNE"],
                       "l.223-225")
        for (code, message) in [("CONTRAT_INACTIF", TextesWeb.SignatureOtp.contratInactif),
                                ("CONTRAT_DEJA_COMPLET", TextesWeb.SignatureOtp.contratDejaComplet),
                                ("DEJA_SIGNE", TextesWeb.SignatureOtp.dejaSigne)] {
            var s = session()
            s.accepter(true)
            let demande = try XCTUnwrap(s.demanderEnvoi())
            s.terminerEnvoi(.refuse(code: code, message: message, bloquant: true), demande: demande, maintenant: t0)
            XCTAssertEqual(presentation(s).mode, .indisponible(titre: "Signature non disponible pour le moment", message: message),
                           "\(code) : titre l.230 et message l.231")
        }
        for (code, message) in [("TELEPHONE_MANQUANT", TextesWeb.SignatureOtp.telephoneManquant),
                                ("TROP_DE_SMS", TextesWeb.SignatureOtp.tropDeSms),
                                ("NON_AUTORISE", TextesWeb.SignatureOtp.nonAutorise)] {
            var s = session()
            s.accepter(true)
            let demande = try XCTUnwrap(s.demanderEnvoi())
            s.terminerEnvoi(.refuse(code: code, message: message, bloquant: true), demande: demande, maintenant: t0)
            let f = try formulaire(presentation(s))
            XCTAssertEqual(f.alerte, message, "\(code) : alerte dans le formulaire, jamais « Signature non disponible »")
            XCTAssertEqual(f.recevoir?.actif, false)
        }
    }

    // MARK: - Signé

    func testSigneAfficheLaConfirmationEtLaMentionDuWeb() throws {
        var s = try codeEnvoye()
        s.saisir("000000")
        let demande = try XCTUnwrap(s.demanderSignature(maintenant: t0))
        s.terminerSignature(.signee(contratComplet: false), demande: demande)
        XCTAssertEqual(presentation(s).mode, .signee(confirmation: "Contrat signé ✅",
                                                     mention: "Signé avec succès. Horodatage, IP et hash du document conservés (art. 1366-1367 Code civil)."),
                       "l.214-217")
        var complet = try codeEnvoye()
        complet.saisir("000000")
        let autre = try XCTUnwrap(complet.demanderSignature(maintenant: t0))
        complet.terminerSignature(.signee(contratComplet: true), demande: autre)
        guard case .signee(let confirmation, _) = presentation(complet).mode else { return XCTFail("signé attendu") }
        XCTAssertEqual(confirmation, "Contrat signé ✅ — Mission confirmée par les 2 parties.", "l.197")
    }

    func testAucunePresentationNExposeLeCodeSaisi() throws {
        var s = try codeEnvoye()
        s.saisir("482913")
        let p = presentation(s)
        XCTAssertFalse(String(describing: p).contains("482913"))
        XCTAssertFalse(String(reflecting: p).contains("482913"))
    }
}
