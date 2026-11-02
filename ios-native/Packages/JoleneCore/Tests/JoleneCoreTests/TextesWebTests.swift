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

    /// Le web tutoie dans cinq textes : les reprendre au vouvoiement serait une reformulation
    /// (HARD STOP n°4). Ils restent verbatim, en attente de la décision de Gabrielle ; tout
    /// autre tutoiement fait échouer ce test, et une exception qui ne tutoie plus aussi.
    func testVouvoiementSaufTextesDuWebEnAttenteDeGabrielle() {
        let exceptions: Set<String> = [
            "BandeauSansGps.texte",
            "Presences.pointageSansGpsActive",
            "Presences.relanceTitre",
            "Presences.relanceExplication",
            "AttestationSante.documentsOriginaux",
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

    func testDelaisAffichesParLeWebRestentCeuxDuWeb() {
        // Q9 (en attente de Gabrielle) : le web annonce 72 h, le serveur lit
        // `parametres_litiges.delai_contestation_pointage_h` (48 h par défaut). Le texte reste
        // celui du web ; aucun délai n'est recalculé ni réécrit côté natif.
        XCTAssertTrue(TextesWeb.Contestation.delaiContestation.hasPrefix("Vous avez 72 h après la validation"))
        XCTAssertTrue(TextesWeb.CompteARebours.expire.contains("72h"))
    }
}
