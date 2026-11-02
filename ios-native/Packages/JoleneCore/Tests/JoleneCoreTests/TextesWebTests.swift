import XCTest
@testable import JoleneCore

/// Textes juridiques et de consentement du lot 2 (`Legal/TextesWeb.swift`, LOT2_PLAN §3 TL,
/// HARD STOP n°4). L'égalité de chaque constante avec le texte du web est prouvée par la garde
/// Node `tests/node/textes-juridiques-ios.node.mjs` (qui vérifie aussi que `catalogue` liste
/// toutes les constantes) ; ce test vérifie la forme des textes et les assemblages, qui
/// reproduisent le rendu React des écrans sources.
final class TextesWebTests: XCTestCase {
    private let catalogue = TextesWeb.catalogue

    func testCatalogueCompletEtClesUniques() {
        XCTAssertGreaterThanOrEqual(catalogue.count, 60)
        XCTAssertEqual(Set(catalogue.map(\.cle)).count, catalogue.count, "clé dupliquée dans le catalogue")
        XCTAssertTrue(catalogue.contains(EntreeTexteWeb(cle: "ConsentementGps.baseLegale",
                                                        texte: TextesWeb.ConsentementGps.baseLegale)))
    }

    func testAucuneConstanteVideNiEspaceDeBordNiRetourALaLigne() {
        for entree in catalogue {
            XCTAssertFalse(entree.texte.isEmpty, entree.cle)
            XCTAssertEqual(entree.texte, entree.texte.trimmingCharacters(in: .whitespacesAndNewlines), entree.cle)
            XCTAssertFalse(entree.texte.contains("\n"), entree.cle)
            XCTAssertFalse(entree.texte.contains("  "), "\(entree.cle) contient une espace doublée")
        }
    }

    func testAucuneVariableDeGabarit() {
        // Les valeurs (date, empreinte) sont assemblées par les fonctions de TextesWeb, jamais
        // par un gabarit à remplir dans un texte juridique.
        let marqueurs = ["{", "}", "${", "%@", "%d", "%s", "%1$", "\\(", "<", ">"]
        for entree in catalogue {
            for marqueur in marqueurs {
                XCTAssertFalse(entree.texte.contains(marqueur), "\(entree.cle) contient « \(marqueur) »")
            }
        }
    }

    /// Le web tutoie dans huit textes : les reprendre au vouvoiement serait une reformulation
    /// (HARD STOP n°4). Ils restent verbatim, en attente de la décision de Gabrielle ; tout
    /// autre tutoiement fait échouer ce test, et une exception qui ne tutoie plus aussi.
    func testVouvoiementSaufTextesDuWebEnAttenteDeGabrielle() {
        let exceptions: Set<String> = [
            "BandeauSansGps.texte",
            "Presences.pointageSansGpsActive",
            "Presences.relanceTitre",
            "Presences.relanceExplication",
            "AttestationSante.documentsOriginaux",
            "ProfilConsentementGps.explicationActive",
            "ProfilConsentementGps.explicationRetiree",
            "ProfilConsentementGps.retire",
        ]
        let marques: Set<String> = ["tu", "te", "toi", "ton", "ta", "tes", "t"]
        for entree in catalogue {
            let mots = entree.texte.lowercased()
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { !$0.isEmpty }
            let tutoie = mots.contains { marques.contains($0) }
            if exceptions.contains(entree.cle) {
                XCTAssertTrue(tutoie, "\(entree.cle) ne tutoie plus : retirer l'exception")
            } else {
                XCTAssertFalse(tutoie, "\(entree.cle) tutoie : « \(entree.texte) »")
            }
        }
        XCTAssertTrue(exceptions.isSubset(of: Set(catalogue.map(\.cle))))
    }

    func testListesDuConsentementGpsDansLOrdreDuWeb() {
        let gps = TextesWeb.ConsentementGps.self
        XCTAssertEqual(gps.ceQueNousFaisons, [gps.ceQueNousFaisons1, gps.ceQueNousFaisons2, gps.ceQueNousFaisons3])
        XCTAssertEqual(gps.ceQueNousNeFaisonsPas,
                       [gps.ceQueNousNeFaisonsPas1, gps.ceQueNousNeFaisonsPas2, gps.ceQueNousNeFaisonsPas3])
        XCTAssertTrue(gps.baseLegale.contains("Art. 6.1.a RGPD"))
    }

    func testMessagesDeSignatureParCodeCommeLeWeb() {
        let otp = TextesWeb.SignatureOtp.self
        XCTAssertEqual(Set(otp.parCode.keys), [
            "NON_AUTHENTIFIE", "NON_AUTORISE", "CONTRAT_INTROUVABLE", "CONTRAT_INACTIF",
            "CONTRAT_DEJA_COMPLET", "TELEPHONE_MANQUANT", "TROP_DE_SMS", "OTP_NON_DEMANDE",
            "OTP_EXPIRE", "OTP_INCORRECT", "TROP_DE_TENTATIVES", "DEJA_SIGNE", "HASH_DOCUMENT_CHANGE",
        ])
        XCTAssertEqual(otp.codesBloquants, [
            "TELEPHONE_MANQUANT", "TROP_DE_SMS", "CONTRAT_INACTIF", "CONTRAT_DEJA_COMPLET",
            "DEJA_SIGNE", "NON_AUTORISE", "HASH_DOCUMENT_CHANGE",
        ])
        XCTAssertTrue(otp.codesBloquants.isSubset(of: Set(otp.parCode.keys)))
        XCTAssertEqual(otp.parCode["OTP_EXPIRE"], otp.otpExpire)
        XCTAssertEqual(otp.parCode["HASH_DOCUMENT_CHANGE"], otp.hashDocumentChange)
    }

    /// `messageDepuisCode(code, result?.error || fallback)` (`SignerContratOtp.tsx` l.46-49,
    /// l.112-114) : message du code connu, sinon message serveur verbatim, sinon repli.
    func testMessageDepuisCodeReproduitLeWeb() {
        let otp = TextesWeb.SignatureOtp.self
        XCTAssertEqual(otp.message(code: "OTP_EXPIRE", erreurServeur: "texte serveur", repli: otp.repliSignature),
                       otp.otpExpire)
        XCTAssertEqual(otp.message(code: "TROP_DE_SMS_IP", erreurServeur: "Message serveur verbatim.",
                                   repli: otp.repliEnvoi), "Message serveur verbatim.")
        XCTAssertEqual(otp.message(code: "CONFIGURATION_SMS_INDISPONIBLE", erreurServeur: nil, repli: otp.repliEnvoi),
                       otp.repliEnvoi)
        XCTAssertEqual(otp.message(code: nil, erreurServeur: "", repli: otp.repliSignature), otp.repliSignature)
        XCTAssertEqual(otp.message(code: "", erreurServeur: nil, repli: ""), otp.messageParDefaut)
    }

    func testConfirmationDeSignatureCommeLeRenduWeb() {
        let otp = TextesWeb.SignatureOtp.self
        XCTAssertEqual(otp.confirmationSignature(contratComplet: false), "Contrat signé ✅")
        XCTAssertEqual(otp.confirmationSignature(contratComplet: true),
                       "Contrat signé ✅ — Mission confirmée par les 2 parties.")
    }

    /// Pied de page de `ContratMission.tsx` l.831-837 : la mention choisie, puis « Signature
    /// électronique simple. », puis la régularisation des montants sauf cadre employeur.
    func testPiedDePageDuContratCommeLeRenduWeb() {
        let contrat = TextesWeb.Contrat.self
        XCTAssertEqual(contrat.piedDePage(.salarieEcrit),
                       "Contrat salarié écrit — art. L.1242-12 du Code du travail. Signature électronique simple. "
                       + "Les montants prévisionnels sont régularisés selon les heures validées et les éventuelles "
                       + "corrections contradictoires.")
        XCTAssertEqual(contrat.piedDePage(.prestationLiberale),
                       "Contrat de prestation entre l’établissement et le professionnel libéral. Signature "
                       + "électronique simple. Les montants prévisionnels sont régularisés selon les heures "
                       + "validées et les éventuelles corrections contradictoires.")
        XCTAssertEqual(contrat.piedDePage(.cadreEmployeur),
                       "Contrat salarié préparé selon le cadre déclaré par l’employeur. Signature électronique simple.")
    }

    func testDocumentOfficielFigeCommeLeRenduWeb() {
        let contrat = TextesWeb.Contrat.self
        let empreinte = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abwxyz"
        XCTAssertEqual(contrat.documentOfficielFige(dateFormatee: "02/11/2026 à 10:00", empreinte: empreinte),
                       "Document officiel figé le 02/11/2026 à 10:00 — empreinte 01234567…wxyz")
        XCTAssertEqual(contrat.documentOfficielFige(dateFormatee: "02/11/2026 à 10:00", empreinte: nil),
                       "Document officiel figé le 02/11/2026 à 10:00")
        XCTAssertEqual(contrat.documentOfficielFige(dateFormatee: "02/11/2026 à 10:00", empreinte: ""),
                       "Document officiel figé le 02/11/2026 à 10:00")
    }

    func testAttestationSigneeLeCommeLeRenduWeb() {
        XCTAssertEqual(TextesWeb.AttestationSante.signeeLe(dateFormatee: "2 novembre 2026"),
                       "✅ Attestation signée le 2 novembre 2026")
    }

    /// Q9 (LOT2_PLAN §7, DECISIONS_LOT2, en attente de Gabrielle) : aucun texte de délai de
    /// contestation n'est repris (le web annonce 72 h, le serveur lit
    /// `parametres_litiges.delai_contestation_pointage_h`, 48 h par défaut). Seuls les libellés de
    /// statut et les boutons du panneau sont portés ; le refus serveur s'affiche tel quel.
    func testAucunTexteDeDelaiDeContestation() {
        let contestation = catalogue.filter { $0.cle.hasPrefix("Contestation.") }
        XCTAssertFalse(contestation.isEmpty)
        for entree in contestation {
            for marque in ["72", "48", "délai", "tranchera", "pour répondre", "pour contester"] {
                XCTAssertFalse(entree.texte.lowercased().contains(marque), "\(entree.cle) contient « \(marque) »")
            }
        }
    }

    /// `STATUT_CONFIG[litige.statut]?.label || litige.statut` (`PanneauContestation.tsx` l.266).
    func testLibelleDeStatutDeContestationCommeLeWeb() {
        let contestation = TextesWeb.Contestation.self
        XCTAssertEqual(contestation.libellesStatut.count, 13)
        XCTAssertEqual(contestation.libelleStatut(code: "OUVERT"), "Ouvert")
        XCTAssertEqual(contestation.libelleStatut(code: "EN_MEDIATION"), "En médiation")
        XCTAssertEqual(contestation.libelleStatut(code: "RESOLU_FAVEUR_ETAB"), "Résolu en faveur de l’établissement")
        XCTAssertEqual(contestation.libelleStatut(code: "STATUT_INCONNU"), "STATUT_INCONNU")
    }

    /// Interrupteur du Profil (`SectionPreferences.tsx` l.133-136) et retour après bascule (l.161).
    func testConsentementGpsDuProfilCommeLeRenduWeb() {
        let profil = TextesWeb.ProfilConsentementGps.self
        XCTAssertEqual(profil.explication(consentementActif: true), profil.explicationActive)
        XCTAssertEqual(profil.explication(consentementActif: false), profil.explicationRetiree)
        XCTAssertEqual(profil.retourBascule(consentementActif: true), "Consentement GPS activé.")
        XCTAssertEqual(profil.retourBascule(consentementActif: false), profil.retire)
        XCTAssertEqual(profil.libelleAccessibilite, profil.libelle)
    }

    /// Message des tentatives restantes (`SignerContratOtp.tsx` l.322-327) : affiché sous 5 ;
    /// pluriel au-delà de 1 ; à 0, le message des tentatives épuisées.
    func testTentativesRestantesCommeLeRenduWeb() {
        let otp = TextesWeb.SignatureOtp.self
        XCTAssertEqual(otp.tentativesRestantes(n: 4), "Code incorrect. 4 tentatives restantes.")
        XCTAssertEqual(otp.tentativesRestantes(n: 1), "Code incorrect. 1 tentative restante.")
        XCTAssertEqual(otp.tentativesRestantes(n: 0), "Trop de tentatives. Renvoyez un nouveau code SMS.")
        XCTAssertEqual(otp.tentativesRestantes(n: -1), otp.tentativesEpuisees)
        XCTAssertNil(otp.tentativesRestantes(n: 5))
        XCTAssertNil(otp.tentativesRestantes(n: 6))
    }

    /// Envoi du code (`SignerContratOtp.tsx` l.151, l.296, l.299) et minuteur (l.110, l.305).
    func testEnvoiDuCodeEtMinuteurCommeLeRenduWeb() {
        let otp = TextesWeb.SignatureOtp.self
        XCTAssertEqual(otp.codeEnvoye(telephoneMasque: "06 •• •• •• 12", minutes: 10),
                       "Code envoyé au 06 •• •• •• 12. Valide 10 min.")
        XCTAssertEqual(otp.codeEnvoyeAu(telephoneMasque: "06 •• •• •• 12"), "Code envoyé au 06 •• •• •• 12")
        XCTAssertEqual(otp.codeEnvoyeAu(telephoneMasque: nil), "Code envoyé au numéro masqué")
        XCTAssertEqual(otp.codeEnvoyeAu(telephoneMasque: ""), "Code envoyé au numéro masqué")
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
    }

    /// Durée restante du compte à rebours (`Countdown72hSignature.tsx` l.49-51, l.72).
    func testDureeDuCompteAReboursCommeLeRenduWeb() {
        let rebours = TextesWeb.CompteARebours.self
        XCTAssertEqual(rebours.duree(restantSecondes: 62 * 3600), "62h 00m 00s")
        XCTAssertEqual(rebours.duree(restantSecondes: 3661), "1h 01m 01s")
        XCTAssertEqual(rebours.duree(restantSecondes: 59), "0h 00m 59s")
    }

    /// Relance de l'établissement (`DetailPresencesMission.tsx` l.120-123) : message serveur
    /// s'il existe (`??` : seul un message absent est remplacé), sinon le repli du web.
    func testMessageDeRelanceCommeLeWeb() {
        let presences = TextesWeb.Presences.self
        XCTAssertEqual(presences.messageRelance(succes: true, message: nil, erreur: nil), "Établissement relancé.")
        XCTAssertEqual(presences.messageRelance(succes: true, message: "Relance envoyée.", erreur: nil), "Relance envoyée.")
        XCTAssertEqual(presences.messageRelance(succes: false, message: nil, erreur: "Déjà relancé."), "Déjà relancé.")
        XCTAssertEqual(presences.messageRelance(succes: false, message: nil, erreur: nil), "Relance impossible.")
        XCTAssertEqual(presences.relancer, "Relancer l'établissement")
    }

    /// Pied de la page `/contrat/:id/certificat` (`CertificatSignaturePage.tsx` l.214-215).
    func testMentionDeLaPageCertificat() {
        XCTAssertTrue(TextesWeb.Certificat.mentionPage.hasPrefix("Conforme art. 1366-1367 Code civil — "))
    }
}
