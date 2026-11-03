import XCTest
@testable import JoleneCore

/// Textes juridiques et de consentement du lot 2 (`Legal/TextesWeb.swift`, LOT2_PLAN §3 TL,
/// HARD STOP n°4). L'égalité de chaque constante avec le texte du web est prouvée par la garde
/// Node `tests/node/textes-juridiques-ios.node.mjs` (qui vérifie aussi que `catalogue` liste
/// toutes les constantes, que le code web de chaque assemblage n'a pas changé et que chaque rendu
/// de `scripts/mobile/textes-web-ios-rendus.json` est asserté ici mot pour mot) ; ce test vérifie
/// la forme des textes et les rendus assemblés montrés à Gabrielle.
final class TextesWebTests: XCTestCase {
    private let catalogue = TextesWeb.catalogue

    /// Les deux catalogues (HARD STOP et libellés), clés préfixées par leur fichier.
    static let tousLesTextes: [EntreeTexteWeb] =
        TextesWeb.catalogue.map { EntreeTexteWeb(cle: "TextesWeb." + $0.cle, texte: $0.texte) }
        + LibellesWeb.catalogue.map { EntreeTexteWeb(cle: "LibellesWeb." + $0.cle, texte: $0.texte) }

    func testCatalogueCompletEtClesUniques() {
        XCTAssertGreaterThanOrEqual(catalogue.count, 60)
        XCTAssertEqual(Set(catalogue.map(\.cle)).count, catalogue.count, "clé dupliquée dans le catalogue")
        XCTAssertTrue(catalogue.contains(EntreeTexteWeb(cle: "ConsentementGps.baseLegale",
                                                        texte: TextesWeb.ConsentementGps.baseLegale)))
        XCTAssertEqual(Set(Self.tousLesTextes.map(\.cle)).count, Self.tousLesTextes.count)
    }

    func testAucuneConstanteVideNiEspaceDeBordNiRetourALaLigne() {
        for entree in Self.tousLesTextes {
            XCTAssertFalse(entree.texte.isEmpty, entree.cle)
            XCTAssertEqual(entree.texte, entree.texte.trimmingCharacters(in: .whitespacesAndNewlines), entree.cle)
            XCTAssertFalse(entree.texte.contains("\n"), entree.cle)
            XCTAssertFalse(entree.texte.contains("  "), "\(entree.cle) contient une espace doublée")
        }
    }

    func testAucuneVariableDeGabarit() {
        // Les valeurs (date, empreinte) sont assemblées par les fonctions de TextesWeb et de
        // LibellesWeb, jamais par un gabarit à remplir dans un texte.
        let marqueurs = ["{", "}", "${", "%@", "%d", "%s", "%1$", "\\(", "<", ">"]
        for entree in Self.tousLesTextes {
            for marqueur in marqueurs {
                XCTAssertFalse(entree.texte.contains(marqueur), "\(entree.cle) contient « \(marqueur) »")
            }
        }
    }

    /// Le web tutoie dans huit textes, tous HARD STOP : les reprendre au vouvoiement serait une
    /// reformulation (HARD STOP n°4). Ils restent verbatim, en attente de la décision de Gabrielle ;
    /// tout autre tutoiement (dans l'un ou l'autre fichier) fait échouer ce test, et une exception
    /// qui ne tutoie plus aussi.
    func testVouvoiementSaufTextesDuWebEnAttenteDeGabrielle() {
        let exceptions: Set<String> = [
            "TextesWeb.BandeauSansGps.texte",
            "TextesWeb.Presences.pointageSansGpsActive",
            "TextesWeb.Presences.relanceTitre",
            "TextesWeb.Presences.relanceExplication",
            "TextesWeb.AttestationSante.documentsOriginaux",
            "TextesWeb.ProfilConsentementGps.explicationActive",
            "TextesWeb.ProfilConsentementGps.explicationRetiree",
            "TextesWeb.ProfilConsentementGps.retire",
        ]
        let marques: Set<String> = ["tu", "te", "toi", "ton", "ta", "tes", "t"]
        for entree in Self.tousLesTextes {
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
        XCTAssertTrue(exceptions.isSubset(of: Set(Self.tousLesTextes.map(\.cle))))
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
    /// l.112-114) : message du code connu, sinon message serveur verbatim, sinon repli, sinon défaut.
    func testMessageDepuisCodeReproduitLeWeb() {
        let otp = TextesWeb.SignatureOtp.self
        let libelles = LibellesWeb.SignatureOtp.self
        XCTAssertEqual(otp.message(code: "OTP_EXPIRE", erreurServeur: "texte serveur", repli: libelles.repliSignature),
                       "Le code SMS a expiré (10 min). Demandez un nouveau code.")
        XCTAssertEqual(otp.message(code: "TROP_DE_SMS_IP", erreurServeur: "Message serveur verbatim.",
                                   repli: libelles.repliEnvoi), "Message serveur verbatim.")
        XCTAssertEqual(otp.message(code: "CONFIGURATION_SMS_INDISPONIBLE", erreurServeur: nil, repli: libelles.repliEnvoi),
                       libelles.repliEnvoi)
        XCTAssertEqual(otp.message(code: nil, erreurServeur: "", repli: libelles.repliSignature), libelles.repliSignature)
        XCTAssertEqual(otp.message(code: nil, erreurServeur: nil, repli: ""), "Une erreur est survenue. Réessayez.")
        XCTAssertEqual(otp.message(code: "", erreurServeur: nil, repli: ""), libelles.messageParDefaut)
    }

    /// Confirmation de `SignerContratOtp.tsx` l.195-198 (gabarit de la l.197), affichée l.214.
    func testConfirmationDeSignatureCommeLeRenduWeb() {
        let otp = TextesWeb.SignatureOtp.self
        XCTAssertEqual(otp.confirmationSignature(contratComplet: false), "Contrat signé ✅")
        XCTAssertEqual(otp.confirmationSignature(contratComplet: true), "Contrat signé ✅ — Mission confirmée par les 2 parties.")
        XCTAssertEqual(otp.contratSigneMessage, otp.contratSigne)
    }

    /// Pied de page de `ContratMission.tsx` l.831-837 : la mention choisie, puis « Signature
    /// électronique simple. », puis la régularisation des montants sauf cadre employeur
    /// (`{!texteEmployeur && …}`, l.836 ; zone gardée par la garde Node).
    func testPiedDePageDuContratCommeLeRenduWeb() {
        let contrat = TextesWeb.Contrat.self
        XCTAssertEqual(contrat.MentionPiedDePage.salarieEcrit.texte, "Contrat salarié écrit — art. L.1242-12 du Code du travail.")
        XCTAssertEqual(contrat.piedDePage(.salarieEcrit), "Contrat salarié écrit — art. L.1242-12 du Code du travail. Signature électronique simple. Les montants prévisionnels sont régularisés selon les heures validées et les éventuelles corrections contradictoires.")
        XCTAssertEqual(contrat.piedDePage(.prestationLiberale), "Contrat de prestation entre l’établissement et le professionnel libéral. Signature électronique simple. Les montants prévisionnels sont régularisés selon les heures validées et les éventuelles corrections contradictoires.")
        XCTAssertEqual(contrat.piedDePage(.cadreEmployeur), "Contrat salarié préparé selon le cadre déclaré par l’employeur. Signature électronique simple.")
        XCTAssertEqual(contrat.MentionPiedDePage.allCases.count, 3)
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
    /// `parametres_litiges.delai_contestation_pointage_h`, 48 h par défaut), ni dans le groupe
    /// Contestation ni ailleurs, dans l'un ou l'autre fichier.
    func testAucunTexteDeDelaiDeContestation() {
        let contestation = Self.tousLesTextes.filter { $0.cle.contains(".Contestation.") }
        XCTAssertFalse(contestation.isEmpty)
        for entree in contestation {
            for marque in ["72", "48", "délai", "tranchera", "pour répondre", "pour contester"] {
                XCTAssertFalse(entree.texte.lowercased().contains(marque), "\(entree.cle) contient « \(marque) »")
            }
        }
        for entree in Self.tousLesTextes {
            let texte = entree.texte.lowercased()
            let sujet = texte.contains("contest") || texte.contains("litige")
            let delai = texte.contains("délai")
                || texte.range(of: #"\d+\s?(h|heures?|jours?)\b"#, options: .regularExpression) != nil
            XCTAssertFalse(sujet && delai, "\(entree.cle) associe contestation et délai : « \(entree.texte) »")
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

    /// Interrupteur du Profil (`SectionPreferences.tsx` l.134-136) et retour après bascule (l.159-162).
    func testConsentementGpsDuProfilCommeLeRenduWeb() {
        let profil = TextesWeb.ProfilConsentementGps.self
        XCTAssertEqual(profil.explication(consentementActif: true), "Ta position sera capturée uniquement au moment de l'arrivée et du départ.")
        XCTAssertEqual(profil.explication(consentementActif: false), "Sans GPS, tes pointages seront validés manuellement par l'établissement — rien à faire de ton côté.")
        XCTAssertEqual(profil.retourBascule(consentementActif: true), "Consentement GPS activé.")
        XCTAssertEqual(profil.retourBascule(consentementActif: false), "Consentement GPS retiré — tes pointages seront validés manuellement par l'établissement.")
        XCTAssertEqual(profil.libelleAccessibilite, profil.libelle)
    }

    /// Message des tentatives restantes (`SignerContratOtp.tsx` l.322-328) : affiché sous 5 ;
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

    /// Compte à rebours (`Countdown72hSignature.tsx` l.38-75) : expiré à zéro, alerte urgente sous
    /// 24 h (couleur `destructive`), sinon « Signature à finaliser sous », suivi de la durée.
    func testCompteAReboursCommeLeRenduWeb() {
        let rebours = TextesWeb.CompteARebours.self
        XCTAssertEqual(rebours.texte(restantSecondes: 0), "⚠\u{FE0F} Délai de signature expiré (72h dépassées).")
        XCTAssertEqual(rebours.texte(restantSecondes: -5), rebours.expire)
        XCTAssertEqual(rebours.texte(restantSecondes: 62 * 3600), "Signature à finaliser sous 62h 00m 00s")
        XCTAssertEqual(rebours.texte(restantSecondes: 24 * 3600), "Signature à finaliser sous 24h 00m 00s")
        XCTAssertEqual(rebours.texte(restantSecondes: 23 * 3600 + 59 * 60 + 59), "Signature urgente — moins de 24h restantes ! 23h 59m 59s")
    }

    /// Certificat (`CertificatSignature.tsx` l.121, l.162-165) et bloc « Empreinte du document
    /// signé » de la page `/contrat/:id/certificat` (`CertificatSignaturePage.tsx` l.203-208).
    func testCertificatCommeLeRenduWeb() {
        let certificat = TextesWeb.Certificat.self
        XCTAssertEqual(certificat.statut(estSigne: true, codeBrut: "signe"), "✅ Signé")
        XCTAssertEqual(certificat.statut(estSigne: false, codeBrut: "en_attente"), "en_attente")
        XCTAssertEqual(certificat.rpps(verifie: true), "✓")
        XCTAssertEqual(certificat.rpps(verifie: false), "—")
        XCTAssertEqual(certificat.psc(actif: true), "✓")
        XCTAssertEqual(certificat.psc(actif: false), "—")
        XCTAssertEqual(certificat.explicationEmpreinte(storagePath: "contrats/2026/c-001.html"), "SHA-256 du contrat figé au moment de la signature. Si vous recalculez le hash du contenu HTML stocké (storage_path : contrats/2026/c-001.html), vous devez retrouver cette empreinte — c'est la preuve que le document n'a pas été modifié depuis la signature.")
        XCTAssertEqual(certificat.explicationEmpreinte(storagePath: nil), "SHA-256 du contrat figé au moment de la signature. Si vous recalculez le hash du contenu HTML stocké (storage_path : —), vous devez retrouver cette empreinte — c'est la preuve que le document n'a pas été modifié depuis la signature.")
        XCTAssertEqual(certificat.explicationEmpreinte(storagePath: ""), certificat.explicationEmpreinte(storagePath: nil))
        XCTAssertTrue(certificat.mentionPage.hasPrefix("Conforme art. 1366-1367 Code civil — "))
    }
}
