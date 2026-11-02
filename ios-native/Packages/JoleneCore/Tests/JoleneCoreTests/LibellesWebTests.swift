import XCTest
@testable import JoleneCore

/// Libellés non juridiques du lot 2 (`Libelles/LibellesWeb.swift`, LOT2_PLAN §3 TL, hors HARD STOP).
/// L'égalité de chaque constante avec le texte du web, l'absence de marque juridique et la zone web
/// de chaque assemblage sont prouvées par la garde Node `tests/node/textes-juridiques-ios.node.mjs` ;
/// ce test assert les rendus assemblés (chacun repris mot pour mot de
/// `scripts/mobile/textes-web-ios-rendus.json`, ce que la garde vérifie). La forme des textes
/// (vide, gabarit, tutoiement, délai de contestation) est testée avec ceux de TextesWeb
/// (`TextesWebTests.tousLesTextes`).
final class LibellesWebTests: XCTestCase {
    func testCatalogueCompletEtClesUniques() {
        let catalogue = LibellesWeb.catalogue
        XCTAssertGreaterThanOrEqual(catalogue.count, 40)
        XCTAssertEqual(Set(catalogue.map(\.cle)).count, catalogue.count, "clé dupliquée dans le catalogue")
        XCTAssertTrue(catalogue.contains(EntreeTexteWeb(cle: "SignatureOtp.renvoyerCode",
                                                        texte: LibellesWeb.SignatureOtp.renvoyerCode)))
    }

    /// Relance de l'établissement (`DetailPresencesMission.tsx` l.120-123) : message serveur s'il
    /// existe (`??` : seul un message absent est remplacé), sinon le repli du web.
    func testMessageDeRelanceCommeLeWeb() {
        let presences = LibellesWeb.Presences.self
        XCTAssertEqual(presences.messageRelance(succes: true, message: nil, erreur: nil), "Établissement relancé.")
        XCTAssertEqual(presences.messageRelance(succes: true, message: "Relance envoyée.", erreur: nil), "Relance envoyée.")
        XCTAssertEqual(presences.messageRelance(succes: false, message: nil, erreur: "Déjà relancé."), "Déjà relancé.")
        XCTAssertEqual(presences.messageRelance(succes: false, message: nil, erreur: nil), "Relance impossible.")
        XCTAssertEqual(presences.relancer, "Relancer l'établissement")
    }

    /// Envoi du code (`SignerContratOtp.tsx` l.149-152, l.296-300), minuteur (l.109-110, l.305) et
    /// renvoi (l.335-339).
    func testEnvoiDuCodeMinuteurEtRenvoiCommeLeRenduWeb() {
        let otp = LibellesWeb.SignatureOtp.self
        XCTAssertEqual(otp.codeEnvoye(telephoneMasque: "06 •• •• •• 12", minutes: 10), "Code envoyé au 06 •• •• •• 12. Valide 10 min.")
        XCTAssertEqual(otp.codeEnvoyeAu(telephoneMasque: "06 •• •• •• 12"), "Code envoyé au 06 •• •• •• 12")
        XCTAssertEqual(otp.codeEnvoyeAu(telephoneMasque: nil), "Code envoyé au numéro masqué")
        XCTAssertEqual(otp.codeEnvoyeAu(telephoneMasque: ""), "Code envoyé au numéro masqué")
        // « (dernier envoi possible) » à 0 : formulation du web, signalée à Gabrielle (à 0, le
        // bouton de renvoi est désactivé avec l'infobulle du plafond).
        XCTAssertEqual(otp.smsRestants(n: 0), "(dernier envoi possible)")
        XCTAssertEqual(otp.smsRestants(n: 1), "(1 envoi restant)")
        XCTAssertEqual(otp.smsRestants(n: 2), "(2 envois restants)")
        XCTAssertEqual(otp.minuteur(secondesRestantes: 600), "10:00")
        XCTAssertEqual(otp.minuteur(secondesRestantes: 65), "01:05")
        XCTAssertEqual(otp.minuteur(secondesRestantes: 0), "Expiré")
        XCTAssertEqual(otp.erreurReseauEnvoi, "Erreur réseau. Réessayez.")
        XCTAssertEqual(otp.erreurReseauSignature, otp.erreurReseauEnvoi)
        XCTAssertEqual(otp.renvoi(otpExpire: true), "Recevoir un nouveau code")
        XCTAssertEqual(otp.renvoi(otpExpire: false), "Renvoyer le code")
        XCTAssertEqual(otp.infobulleRenvoi(nouvelEnvoiAutorise: false, smsRestants: 2), "Aucun nouvel envoi autorisé pour cette recette")
        XCTAssertEqual(otp.infobulleRenvoi(nouvelEnvoiAutorise: false, smsRestants: 0), otp.renvoiNonAutoriseRecette)
        XCTAssertEqual(otp.infobulleRenvoi(nouvelEnvoiAutorise: true, smsRestants: 0), "3 SMS max par 24h atteints")
        XCTAssertNil(otp.infobulleRenvoi(nouvelEnvoiAutorise: true, smsRestants: 1))
        XCTAssertNil(otp.infobulleRenvoi(nouvelEnvoiAutorise: true, smsRestants: nil))
    }

    /// Durée restante du compte à rebours (`Countdown72hSignature.tsx` l.49-51, l.72).
    func testDureeDuCompteAReboursCommeLeRenduWeb() {
        let rebours = LibellesWeb.CompteARebours.self
        XCTAssertEqual(rebours.duree(restantSecondes: 62 * 3600), "62h 00m 00s")
        XCTAssertEqual(rebours.duree(restantSecondes: 3661), "1h 01m 01s")
        XCTAssertEqual(rebours.duree(restantSecondes: 59), "0h 00m 59s")
    }

    /// En-tête de la page certificat (`CertificatSignaturePage.tsx` l.186).
    func testEnTeteDuCertificatCommeLeRenduWeb() {
        XCTAssertEqual(LibellesWeb.Certificat.contrat(numero: "CTR-2026-0001", id: "c-001"), "Contrat CTR-2026-0001")
        XCTAssertEqual(LibellesWeb.Certificat.contrat(numero: nil, id: "c-001"), "Contrat c-001")
        XCTAssertEqual(LibellesWeb.Certificat.contrat(numero: "", id: "c-001"), "Contrat c-001")
    }

    /// `String(valeur).padStart(2, '0')` du web.
    func testDeuxChiffres() {
        XCTAssertEqual(LibellesWeb.deuxChiffres(0), "00")
        XCTAssertEqual(LibellesWeb.deuxChiffres(7), "07")
        XCTAssertEqual(LibellesWeb.deuxChiffres(42), "42")
    }
}
