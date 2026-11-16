import XCTest
@testable import JoleneCore

/// Lot 2, T8 — session de signature OTP (`Contrats/SessionSignatureOtp.swift`), port de `SessionSignatureOtp`
/// (`SignerContratOtp.tsx` l.61-207) et de ses tests de continuité (`SignerContratOtp.continuite.test.tsx`) :
/// clé (contrat, empreinte, document prêt) qui remet tout à zéro, un envoi à la fois, réponse d'une ancienne clé
/// ignorée, refus bloquants, tentatives restantes, minuteur dérivé de l'échéance (10 min), code jamais envoyé
/// s'il n'a pas six chiffres. Aucun texte nouveau : `TextesWeb.SignatureOtp`, `LibellesWeb.SignatureOtp`.
final class SessionSignatureOtpTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_577_600)
    private let empreinteA = String(repeating: "a", count: 64)
    private let empreinteB = String(repeating: "b", count: 64)

    private func session(contrat: String = "contrat-a", empreinte: String? = nil, pret: Bool = true) -> SessionSignatureOtp {
        SessionSignatureOtp(cle: CleSessionOtp(contratId: contrat, empreinte: empreinte ?? empreinteA, documentPret: pret))
    }

    private let envoye = IssueEnvoiOtp.envoye(OtpEnvoye(role: "soignant", telephoneMasque: "+**********00", expireDansMinutes: 10,
                                                         smsEnvoyes: 1, smsRestants: 2))

    /// Session à l'étape « code envoyé » à `t0`.
    private func codeEnvoye() throws -> SessionSignatureOtp {
        var s = session()
        s.accepter(true)
        let demande = try XCTUnwrap(s.demanderEnvoi())
        XCTAssertTrue(s.terminerEnvoi(envoye, demande: demande, maintenant: t0))
        return s
    }

    // MARK: - Envoi du code

    func testEnvoiExigeLeConsentementEtUnDocumentPret() throws {
        var bloque = session(pret: false)
        bloque.accepter(true)
        XCTAssertNil(bloque.demanderEnvoi(), "document indisponible : aucune requête (continuite.test l.14-19)")
        var sansEmpreinte = SessionSignatureOtp(cle: CleSessionOtp(contratId: "a", empreinte: nil, documentPret: true))
        sansEmpreinte.accepter(true)
        XCTAssertNil(sansEmpreinte.demanderEnvoi())
        var sansConsentement = session()
        XCTAssertFalse(sansConsentement.peutEnvoyer())
        XCTAssertNil(sansConsentement.demanderEnvoi())
        var s = session()
        s.accepter(true)
        XCTAssertNil(s.demanderEnvoi(nouvelEnvoiAutorise: false), "recette STAGING sans envoi autorisé")
        let demande = try XCTUnwrap(s.demanderEnvoi())
        XCTAssertEqual(demande.nature, .envoi)
        XCTAssertEqual(demande.contratId, "contrat-a")
        XCTAssertEqual(demande.empreinte, empreinteA)
        XCTAssertTrue(s.operationEnCours)
        XCTAssertNil(s.demanderEnvoi(), "un envoi à la fois (double tap : une seule requête)")
    }

    func testCodeEnvoyeAnnonceEtMinuteurDeDixMinutes() throws {
        let s = try codeEnvoye()
        XCTAssertEqual(s.etape, .otpEnvoye)
        XCTAssertFalse(s.operationEnCours)
        XCTAssertEqual(s.retour, .succes("Code envoyé au +**********00. Valide 10 min."), "format l.151")
        XCTAssertEqual(s.telephoneMasque, "+**********00")
        XCTAssertEqual(s.smsRestants, 2)
        XCTAssertEqual(s.code, "")
        XCTAssertEqual(s.secondesRestantes(maintenant: t0), 600)
        XCTAssertEqual(s.secondesRestantes(maintenant: t0.addingTimeInterval(61.2)), 539, "arrondi supérieur, comme Math.ceil")
        XCTAssertFalse(s.otpExpire(maintenant: t0.addingTimeInterval(599)))
        XCTAssertTrue(s.otpExpire(maintenant: t0.addingTimeInterval(600)))
        XCTAssertEqual(s.secondesRestantes(maintenant: t0.addingTimeInterval(9_000)), 0)
    }

    func testReponseDUneAncienneCleIgnoreeEtConsentementRemisAZero() throws {
        var s = session()
        s.accepter(true)
        let demande = try XCTUnwrap(s.demanderEnvoi())
        // L'empreinte change pendant l'envoi (continuite.test l.42-53).
        s.changerCle(CleSessionOtp(contratId: "contrat-a", empreinte: empreinteB, documentPret: true))
        XCTAssertFalse(s.terminerEnvoi(envoye, demande: demande, maintenant: t0), "réponse ignorée")
        XCTAssertEqual(s.etape, .idle)
        XCTAssertFalse(s.accepte, "consentement décoché à chaque changement de clé")
        XCTAssertNil(s.retour)
        XCTAssertFalse(s.operationEnCours)
        XCTAssertNil(s.telephoneMasque)
    }

    func testChangementDeContratEffaceLeCodeSaisi() throws {
        var s = try codeEnvoye()
        s.saisir("123456")
        s.changerCle(CleSessionOtp(contratId: "contrat-b", empreinte: empreinteB, documentPret: true))
        XCTAssertEqual(s.etape, .idle)
        XCTAssertEqual(s.code, "")
        XCTAssertFalse(s.accepte)
        XCTAssertFalse(s.peutEnvoyer(), "consentement à redonner (continuite.test l.30-40)")
        var meme = try codeEnvoye()
        meme.changerCle(meme.cle)
        XCTAssertEqual(meme.etape, .otpEnvoye, "même clé : rien n'est remis à zéro")
    }

    func testDocumentDevenuIndisponiblePendantLEnvoi() throws {
        var s = session()
        s.accepter(true)
        let demande = try XCTUnwrap(s.demanderEnvoi())
        s.changerCle(CleSessionOtp(contratId: "contrat-a", empreinte: empreinteA, documentPret: false))
        XCTAssertFalse(s.terminerEnvoi(envoye, demande: demande, maintenant: t0))
        XCTAssertNil(s.demanderEnvoi())
        XCTAssertNil(s.retour)
    }

    func testRefusNonBloquantPuisBloquant() throws {
        var s = session()
        s.accepter(true)
        var demande = try XCTUnwrap(s.demanderEnvoi())
        s.terminerEnvoi(.refuse(code: "TROP_DE_SMS_IP", message: "Trop de demandes de signature depuis votre IP. Réessayez dans 1h.",
                                bloquant: false), demande: demande, maintenant: t0)
        XCTAssertEqual(s.retour, .erreur("Trop de demandes de signature depuis votre IP. Réessayez dans 1h."))
        XCTAssertNil(s.erreurBloquante)
        XCTAssertEqual(s.etape, .idle)
        demande = try XCTUnwrap(s.demanderEnvoi(), "un refus non bloquant laisse réessayer")
        s.terminerEnvoi(.refuse(code: "TELEPHONE_MANQUANT", message: TextesWeb.SignatureOtp.telephoneManquant, bloquant: true),
                        demande: demande, maintenant: t0)
        XCTAssertEqual(s.erreurBloquante, ErreurBloquanteOtp(code: "TELEPHONE_MANQUANT", message: TextesWeb.SignatureOtp.telephoneManquant))
        XCTAssertNil(s.demanderEnvoi(), "plus aucun envoi après un refus bloquant")
    }

    func testEchecDeTransportAffichePuisLaisseReessayer() throws {
        var s = session()
        s.accepter(true)
        var demande = try XCTUnwrap(s.demanderEnvoi())
        s.echouerEnvoi(message: "Connexion impossible. Vérifiez votre réseau puis réessayez.", demande: demande)
        XCTAssertEqual(s.retour, .erreur("Connexion impossible. Vérifiez votre réseau puis réessayez."))
        XCTAssertFalse(s.operationEnCours)
        demande = try XCTUnwrap(s.demanderEnvoi())
        s.echouerEnvoi(message: nil, demande: demande)
        XCTAssertEqual(s.retour, .erreur(LibellesWeb.SignatureOtp.erreurReseauEnvoi), "repli du web l.156")
    }

    func testRenvoiInterditQuandPlusAucunSms() throws {
        var s = session()
        s.accepter(true)
        let demande = try XCTUnwrap(s.demanderEnvoi())
        s.terminerEnvoi(.envoye(OtpEnvoye(telephoneMasque: nil, expireDansMinutes: nil, smsEnvoyes: 3, smsRestants: 0)),
                        demande: demande, maintenant: t0)
        XCTAssertEqual(s.retour, .succes("Code envoyé au numéro masqué. Valide 10 min."), "repli sans valeur serveur")
        XCTAssertFalse(s.peutEnvoyer(), "bouton de renvoi désactivé à 0 SMS restant (l.335)")
    }

    // MARK: - Signature

    func testCodeNonNumeriqueOuIncompletJamaisEnvoye() throws {
        var s = try codeEnvoye()
        s.saisir("12a4 5")
        XCTAssertEqual(s.code, "1245", "seuls les chiffres sont gardés (l.315)")
        XCTAssertNil(s.demanderSignature(maintenant: t0))
        XCTAssertEqual(s.retour, .erreur(LibellesWeb.SignatureOtp.codeSixChiffresRequis))
        s.saisir("12345678")
        XCTAssertEqual(s.code, "123456", "six chiffres au plus")
    }

    func testSignatureExigeLeConsentement() throws {
        var s = try codeEnvoye()
        s.saisir("123456")
        s.accepter(false)
        XCTAssertNil(s.demanderSignature(maintenant: t0))
        XCTAssertEqual(s.retour, .erreur(TextesWeb.SignatureOtp.consentementRequis))
    }

    func testSignatureImpossibleApresExpiration() throws {
        var s = try codeEnvoye()
        s.saisir("123456")
        XCTAssertNil(s.demanderSignature(maintenant: t0.addingTimeInterval(600)), "code expiré : bouton désactivé (l.344)")
        XCTAssertTrue(s.peutEnvoyer(), "« Recevoir un nouveau code » reste possible")
    }

    func testCodeIncorrectAvecTentativesRestantesPuisSigne() throws {
        var s = try codeEnvoye()
        s.saisir("111111")
        var demande = try XCTUnwrap(s.demanderSignature(maintenant: t0))
        XCTAssertEqual(demande.nature, .signature(code: "111111"))
        XCTAssertNil(s.demanderSignature(maintenant: t0), "une signature à la fois")
        s.terminerSignature(.refuse(code: "OTP_INCORRECT", message: TextesWeb.SignatureOtp.otpIncorrect, tentativesRestantes: 4),
                            demande: demande)
        XCTAssertEqual(s.tentativesRestantes, 4)
        XCTAssertEqual(s.retour, .erreur(TextesWeb.SignatureOtp.otpIncorrect))
        XCTAssertEqual(s.etape, .otpEnvoye)
        XCTAssertEqual(TextesWeb.SignatureOtp.tentativesRestantes(n: try XCTUnwrap(s.tentativesRestantes)),
                       "Code incorrect. 4 tentatives restantes.")
        s.saisir("000000")
        demande = try XCTUnwrap(s.demanderSignature(maintenant: t0.addingTimeInterval(30)))
        s.terminerSignature(.signee(contratComplet: true), demande: demande)
        XCTAssertEqual(s.etape, .signe)
        XCTAssertEqual(s.retour, .succes("Contrat signé ✅ — Mission confirmée par les 2 parties."))
        XCTAssertEqual(s.contratComplet, true)
        XCTAssertNil(s.demanderEnvoi(), "plus rien à envoyer une fois signé")
    }

    func testHashDocumentChangeBloqueEnvoiEtSignature() throws {
        var s = try codeEnvoye()
        s.saisir("123456")
        let demande = try XCTUnwrap(s.demanderSignature(maintenant: t0))
        s.terminerSignature(.refuse(code: "HASH_DOCUMENT_CHANGE", message: TextesWeb.SignatureOtp.hashDocumentChange,
                                    tentativesRestantes: nil), demande: demande)
        XCTAssertEqual(s.erreurBloquante?.code, "HASH_DOCUMENT_CHANGE")
        XCTAssertNil(s.demanderSignature(maintenant: t0), "continuite.test l.70-80 : signer désactivé")
        XCTAssertNil(s.demanderEnvoi(), "et renvoyer le code aussi")
    }

    func testSignatureDUneAncienneCleIgnoree() throws {
        var s = try codeEnvoye()
        s.saisir("000000")
        let demande = try XCTUnwrap(s.demanderSignature(maintenant: t0))
        s.changerCle(CleSessionOtp(contratId: "contrat-a", empreinte: empreinteB, documentPret: true))
        s.terminerSignature(.signee(contratComplet: false), demande: demande)
        XCTAssertEqual(s.etape, .idle, "la signature d'une autre révision n'est jamais annoncée ici")
        XCTAssertNil(s.retour)
    }

    func testEchecDeTransportALaSignature() throws {
        var s = try codeEnvoye()
        s.saisir("000000")
        let demande = try XCTUnwrap(s.demanderSignature(maintenant: t0))
        s.echouerSignature(message: nil, demande: demande)
        XCTAssertEqual(s.retour, .erreur(LibellesWeb.SignatureOtp.erreurReseauSignature))
        XCTAssertEqual(s.etape, .otpEnvoye)
        XCTAssertFalse(s.operationEnCours)
    }

    // MARK: - T9b

    /// Refus serveur `OTP_EXPIRE` (`fn_signer_contrat_otp` live : `otp_envoye_a < now() - 10 min`, preuve passée à
    /// `expire`) : le serveur fait foi (décision 25), le code est expiré ici aussi — minuteur « Expiré », champ et
    /// « Signer » désactivés, « Recevoir un nouveau code » proposé (l.305, l.317, l.339, l.344).
    func testRefusOtpExpireExpireLeCodeLocalement() throws {
        var s = try codeEnvoye()
        s.saisir("000000")
        let demande = try XCTUnwrap(s.demanderSignature(maintenant: t0))
        s.terminerSignature(.refuse(code: "OTP_EXPIRE", message: TextesWeb.SignatureOtp.otpExpire, tentativesRestantes: nil),
                            demande: demande)
        XCTAssertEqual(s.retour, .erreur("Le code SMS a expiré (10 min). Demandez un nouveau code."), "MESSAGES_ERREUR l.39")
        XCTAssertNil(s.erreurBloquante, "non bloquant (l.115-119) : un nouveau code reste possible")
        XCTAssertEqual(s.etape, .otpEnvoye)
        XCTAssertTrue(s.otpExpire(maintenant: t0), "échéance du serveur dépassée, même si l'horloge locale ne l'est pas")
        XCTAssertEqual(s.secondesRestantes(maintenant: t0), 0)
        XCTAssertFalse(s.peutSigner(maintenant: t0))
        XCTAssertTrue(s.peutEnvoyer(), "« Recevoir un nouveau code »")
        let renvoi = try XCTUnwrap(s.demanderEnvoi())
        s.terminerEnvoi(envoye, demande: renvoi, maintenant: t0.addingTimeInterval(5))
        XCTAssertFalse(s.otpExpire(maintenant: t0.addingTimeInterval(5)), "nouveau code : nouvelle échéance de 10 min")
        XCTAssertEqual(s.secondesRestantes(maintenant: t0.addingTimeInterval(5)), 600)
    }

    func testAutresRefusNExpirentPasLeCode() throws {
        var s = try codeEnvoye()
        s.saisir("111111")
        let demande = try XCTUnwrap(s.demanderSignature(maintenant: t0))
        s.terminerSignature(.refuse(code: "OTP_INCORRECT", message: TextesWeb.SignatureOtp.otpIncorrect, tentativesRestantes: 4),
                            demande: demande)
        XCTAssertFalse(s.otpExpire(maintenant: t0))
        XCTAssertEqual(s.secondesRestantes(maintenant: t0), 600)
    }

    /// Le code saisi ne survit pas à la signature (mémoire seulement, jamais au-delà de son usage).
    func testSignatureEffaceLeCodeSaisi() throws {
        var s = try codeEnvoye()
        s.saisir("000000")
        let demande = try XCTUnwrap(s.demanderSignature(maintenant: t0))
        s.terminerSignature(.signee(contratComplet: false), demande: demande)
        XCTAssertEqual(s.etape, .signe)
        XCTAssertEqual(s.code, "")
    }

    /// Aucun journal ni message d'assertion ne montre le code : description, description de débogage et réflexion
    /// de la session et de la demande le masquent.
    func testLeCodeNApparaitDansAucuneDescription() throws {
        var s = try codeEnvoye()
        s.saisir("482913")
        let demande = try XCTUnwrap(s.demanderSignature(maintenant: t0))
        var dumpSession = ""
        dump(s, to: &dumpSession)
        var dumpDemande = ""
        dump(demande, to: &dumpDemande)
        for texte in [String(describing: s), String(reflecting: s), dumpSession,
                      String(describing: demande), String(reflecting: demande), dumpDemande,
                      String(describing: demande.nature), String(reflecting: demande.nature)] {
            XCTAssertFalse(texte.contains("482913"), "code exposé : \(texte.count) caractères")
        }
        XCTAssertEqual(demande.nature, .signature(code: "482913"), "la valeur reste transmise au port")
    }

    // MARK: - Reprise d'un code relu (recette STAGING)

    func testRepriseDUnCodeEncoreValideRelu() {
        var s = session()
        s.reprendre(otpExpireLe: t0.addingTimeInterval(300), maintenant: t0)
        XCTAssertEqual(s.etape, .otpEnvoye, "continuation relue par le serveur (l.85-98)")
        XCTAssertEqual(s.secondesRestantes(maintenant: t0), 300)
        s.reprendre(otpExpireLe: nil, maintenant: t0)
        XCTAssertEqual(s.etape, .idle, "plus de code valable : retour à l'envoi")
        XCTAssertFalse(s.accepte)
        var expire = session()
        expire.reprendre(otpExpireLe: t0.addingTimeInterval(-1), maintenant: t0)
        XCTAssertEqual(expire.etape, .idle)
    }
}
