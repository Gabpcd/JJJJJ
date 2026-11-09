import XCTest
@testable import JoleneCore

/// Lot 2, T8 — règles d'affichage des contrats portées du web (`Contrats/ContratRules.swift`) :
/// `contratCorrespondAuFiltre` et `?statut=` (`ListeContrats.tsx` l.20-28, l.55-56), `cddSansOriginal`
/// (`ContratMission.tsx` l.62-66), bandeaux (l.552-576), compte à rebours (l.578-582), statut (l.593-596),
/// pied de page (l.535-537, l.831-837), certificat (l.656), signatures (l.672, l.691), zone de signature
/// (l.709), rendu serveur (l.359-364). Aucune règle n'est réécrite : chaque cas renvoie à sa ligne web.
final class ContratRulesTests: XCTestCase {
    private func contrat(statut: String = "EN_ATTENTE_SIGNATURES", type: String? = "CDD", html: String? = nil,
                         hash: String? = nil, chemin: String? = nil, renduLe: String? = nil,
                         soignant: Bool? = nil, etablissement: Bool? = nil, soignantLe: String? = nil,
                         etablissementLe: String? = nil, creeLe: String? = "2026-11-01T14:00:00Z") -> ContratDetail {
        ContratDetail(id: "k-1", missionId: "m-1", statut: statut, typeContrat: type, contenuHtml: html, hashDocument: hash,
                      storagePath: chemin, contenuHtmlRenduLe: renduLe, signatureSoignant: soignant,
                      signatureEtablissement: etablissement, signatureSoignantLe: soignantLe,
                      signatureEtablissementLe: etablissementLe, creeLe: creeLe)
    }

    // MARK: - Liste

    func testFiltresDeLaListeCommeLeWeb() {
        XCTAssertEqual(FiltreContrat.allCases.map(\.rawValue), ["Tous", "EN_ATTENTE_SIGNATURES", "SIGNE_COMPLET", "ANNULE"])
        let statuts = ["BROUILLON", "EN_ATTENTE_SIGNATURES", "SIGNE_SOIGNANT", "SIGNE_ETABLISSEMENT", "SIGNE_COMPLET",
                       "ANNULE", "EXPIRE", "REFUSE", ""]
        XCTAssertEqual(statuts.filter { ContratRules.correspondAuFiltre(statut: $0, filtre: .tous) }, statuts)
        XCTAssertEqual(statuts.filter { ContratRules.correspondAuFiltre(statut: $0, filtre: .enAttenteSignatures) },
                       ["BROUILLON", "EN_ATTENTE_SIGNATURES", "SIGNE_SOIGNANT", "SIGNE_ETABLISSEMENT", ""])
        XCTAssertEqual(statuts.filter { ContratRules.correspondAuFiltre(statut: $0, filtre: .signeComplet) }, ["SIGNE_COMPLET"])
        XCTAssertEqual(statuts.filter { ContratRules.correspondAuFiltre(statut: $0, filtre: .annule) }, ["ANNULE"])
    }

    func testFiltreInitialDepuisLeParametreStatut() {
        XCTAssertEqual(FiltreContrat.initial(statut: "SIGNE_COMPLET"), .signeComplet)
        XCTAssertEqual(FiltreContrat.initial(statut: "EN_ATTENTE_SIGNATURES"), .enAttenteSignatures)
        XCTAssertEqual(FiltreContrat.initial(statut: "EXPIRE"), .tous, "statut hors liste → Tous (l.56)")
        XCTAssertEqual(FiltreContrat.initial(statut: nil), .tous)
        XCTAssertEqual(FiltreContrat.initial(statut: "signe_complet"), .tous, "comparaison exacte, comme `includes`")
    }

    func testFiltrerGardeLOrdreServeur() {
        let liste = [ContratResume(id: "a", missionId: "m", statut: "SIGNE_COMPLET"),
                     ContratResume(id: "b", missionId: "m", statut: "EN_ATTENTE_SIGNATURES"),
                     ContratResume(id: "c", missionId: "m", statut: "BROUILLON")]
        XCTAssertEqual(ContratRules.filtrer(liste, filtre: .enAttenteSignatures).map(\.id), ["b", "c"])
        XCTAssertEqual(ContratRules.filtrer(liste, filtre: .tous).map(\.id), ["a", "b", "c"])
    }

    // MARK: - CDD sans original

    func testCddSansOriginal() {
        XCTAssertTrue(ContratRules.cddSansOriginal(contrat()))
        XCTAssertFalse(ContratRules.cddSansOriginal(contrat(type: "CDDU")), "seul le CDD attend l'employeur")
        XCTAssertFalse(ContratRules.cddSansOriginal(contrat(chemin: "k-1/a.html")))
        XCTAssertFalse(ContratRules.cddSansOriginal(contrat(hash: String(repeating: "a", count: 64))))
        XCTAssertFalse(ContratRules.cddSansOriginal(contrat(renduLe: "2026-11-01T14:05:00Z")))
        XCTAssertFalse(ContratRules.cddSansOriginal(contrat(soignant: true)), "une preuve de signature exclut la préparation")
        XCTAssertFalse(ContratRules.cddSansOriginal(contrat(statut: "SIGNE_ETABLISSEMENT")))
        for terminal in ["ANNULE", "EXPIRE", "REFUSE"] {
            XCTAssertFalse(ContratRules.cddSansOriginal(contrat(statut: terminal)), terminal)
        }
    }

    // MARK: - Bandeaux, compte à rebours, statut

    func testBandeauxDuContrat() {
        XCTAssertEqual(ContratRules.bandeaux(contrat(statut: "ANNULE")), [.annule])
        XCTAssertEqual(ContratRules.bandeaux(contrat(statut: "EXPIRE")), [.expire])
        XCTAssertEqual(ContratRules.bandeaux(contrat(statut: "REFUSE")), [.refuse])
        XCTAssertEqual(ContratRules.bandeaux(contrat(etablissement: true)), [.autrePartieASigne])
        XCTAssertEqual(ContratRules.bandeaux(contrat(soignant: true, etablissement: true)), [], "déjà signé par moi : rien")
        XCTAssertEqual(ContratRules.bandeaux(contrat(statut: "SIGNE_COMPLET", etablissement: true)), [])
        XCTAssertEqual(ContratRules.bandeaux(contrat(statut: "ANNULE", etablissement: true)), [.annule])
        XCTAssertEqual(ContratRules.bandeaux(contrat()), [])
    }

    func testCompteAReboursAfficheHorsStatutsTerminauxAvecCreeLe() {
        XCTAssertTrue(ContratRules.afficheCompteARebours(contrat()))
        XCTAssertTrue(ContratRules.afficheCompteARebours(contrat(statut: "")), "statut nul : non terminal")
        for statut in ["SIGNE_COMPLET", "ANNULE", "EXPIRE", "REFUSE"] {
            XCTAssertFalse(ContratRules.afficheCompteARebours(contrat(statut: statut)), statut)
        }
        XCTAssertFalse(ContratRules.afficheCompteARebours(contrat(creeLe: nil)))
        XCTAssertFalse(ContratRules.afficheCompteARebours(contrat(creeLe: "")))
    }

    func testStatutAffiche() {
        XCTAssertEqual(ContratRules.statutAffiche(contrat(statut: "SIGNE_COMPLET")), .signe)
        XCTAssertEqual(ContratRules.statutAffiche(contrat(statut: "ANNULE")), .annule)
        XCTAssertEqual(ContratRules.statutAffiche(contrat(statut: "EXPIRE")), .enAttente, "le web n'a que trois libellés (l.593-596)")
        XCTAssertEqual(ContratRules.statutAffiche(contrat(statut: "SIGNE_SOIGNANT")), .enAttente)
    }

    /// T9a : même correspondance pour la pastille de la liste (`ListeContrats.tsx` l.162-163) et l'en-tête du
    /// contrat (l.593-596), depuis le seul code serveur.
    func testStatutAfficheDepuisLeCodeServeur() {
        XCTAssertEqual(ContratRules.statutAffiche(statut: "SIGNE_COMPLET"), .signe)
        XCTAssertEqual(ContratRules.statutAffiche(statut: "ANNULE"), .annule)
        for statut in ["EN_ATTENTE_SIGNATURES", "SIGNE_SOIGNANT", "EXPIRE", "REFUSE", "", "signe_complet"] {
            XCTAssertEqual(ContratRules.statutAffiche(statut: statut), .enAttente, statut)
        }
        for statut in ["SIGNE_COMPLET", "ANNULE", "EXPIRE"] {
            XCTAssertEqual(ContratRules.statutAffiche(contrat(statut: statut)), ContratRules.statutAffiche(statut: statut))
        }
    }

    /// T9a : appel à signer d'une carte (`aSigner`, `ListeContrats.tsx` l.156-159, branche soignant) : tout contrat
    /// non annulé que le soignant n'a pas signé. Le serveur décide seul d'une signature.
    func testASignerParMoiCommeLaListeDuWeb() {
        func carte(_ statut: String, _ soignant: Bool?) -> ContratResume {
            ContratResume(id: "k-1", missionId: "m-1", statut: statut, signatureSoignant: soignant)
        }
        XCTAssertTrue(ContratRules.aSignerParMoi(carte("EN_ATTENTE_SIGNATURES", false)))
        XCTAssertTrue(ContratRules.aSignerParMoi(carte("SIGNE_ETABLISSEMENT", nil)), "drapeau absent : non signé (`!c.signature_soignant`)")
        XCTAssertTrue(ContratRules.aSignerParMoi(carte("EXPIRE", false)), "seul ANNULE est exclu par le web")
        XCTAssertFalse(ContratRules.aSignerParMoi(carte("ANNULE", false)))
        XCTAssertFalse(ContratRules.aSignerParMoi(carte("SIGNE_SOIGNANT", true)))
        XCTAssertFalse(ContratRules.aSignerParMoi(carte("SIGNE_COMPLET", true)))
    }

    // MARK: - Pied de page

    func testMentionDuPiedDePage() {
        let employeur = #"<section data-jolene-cdd="employeur-v1" data-cadre="TEXTE_EMPLOYEUR">"#
        XCTAssertEqual(ContratRules.mentionPiedDePage(contrat(html: employeur)), .cadreEmployeur)
        XCTAssertEqual(ContratRules.mentionPiedDePage(contrat(html: "<section data-jolene-cdd='employeur-v1' data-cadre='TEXTE_EMPLOYEUR'>")),
                       .cadreEmployeur, "guillemets simples acceptés (l.536-537)")
        XCTAssertEqual(ContratRules.mentionPiedDePage(contrat(html: #"<section data-jolene-cdd="employeur-v1" data-cadre="PRIVE_TERME_PRECIS">"#)),
                       .salarieEcrit)
        XCTAssertEqual(ContratRules.mentionPiedDePage(contrat(type: "CDDU", html: employeur)), .salarieEcrit,
                       "texteEmployeur exige un CDD ; un CDDU au cadre employeur reçoit la mention salariée (#1122)")
        XCTAssertEqual(ContratRules.mentionPiedDePage(contrat(type: "SALARIE")), .salarieEcrit)
        XCTAssertEqual(ContratRules.mentionPiedDePage(contrat(type: "REMPLACEMENT_LIBERAL")), .prestationLiberale)
        XCTAssertEqual(ContratRules.mentionPiedDePage(contrat(type: nil)), .prestationLiberale)
    }

    /// L2-TJ : `TYPES_CONTRAT_MENTION_SALARIEE` du web (`ContratMission.tsx` l.65, #1122, mention validée par Gabrielle
    /// le 08/11/2026) : CDD, SALARIE, CDDU et VACATION reçoivent « Contrat salarié écrit — art. L.1242-12 du Code du
    /// travail. » ; tout autre type (ou un type absent) la mention de prestation libérale. Comparaison exacte, comme
    /// `Array.includes` du web (casse comprise).
    func testMentionSalarieePourCdduEtVacationCommeLeWeb() {
        for type in ["CDD", "SALARIE", "CDDU", "VACATION"] {
            XCTAssertEqual(ContratRules.mentionPiedDePage(contrat(type: type)), .salarieEcrit, type)
        }
        for type in ["LIBERAL", "REMPLACEMENT_LIBERAL", "cddu", "Vacation", "VACATIONS", "", "INTERIM"] {
            XCTAssertEqual(ContratRules.mentionPiedDePage(contrat(type: type)), .prestationLiberale, type)
        }
        XCTAssertEqual(ContratRules.mentionPiedDePage(contrat(type: nil)), .prestationLiberale)
        XCTAssertEqual(TextesWeb.Contrat.typesMentionSalariee, ["CDD", "SALARIE", "CDDU", "VACATION"])
        XCTAssertEqual(TextesWeb.Contrat.piedDePage(ContratRules.mentionPiedDePage(contrat(type: "VACATION"))),
                       "Contrat salarié écrit — art. L.1242-12 du Code du travail. Signature électronique simple. Les montants prévisionnels sont régularisés selon les heures validées et les éventuelles corrections contradictoires.")
        let employeur = #"<section data-jolene-cdd="employeur-v1" data-cadre="TEXTE_EMPLOYEUR">"#
        XCTAssertEqual(ContratRules.mentionPiedDePage(contrat(type: "VACATION", html: employeur)), .salarieEcrit,
                       "le cadre employeur reste réservé au CDD (l.535-537)")
    }

    // MARK: - Signatures et zone de signature

    func testSignaturesAfficheesEtCertificat() {
        XCTAssertTrue(ContratRules.signatureEtablissementAffichee(contrat(statut: "SIGNE_COMPLET")))
        XCTAssertTrue(ContratRules.signatureEtablissementAffichee(contrat(etablissement: true)))
        XCTAssertFalse(ContratRules.signatureEtablissementAffichee(contrat(etablissementLe: "2026-11-01T15:00:00Z")),
                       "la date seule ne suffit pas (l.672)")
        XCTAssertTrue(ContratRules.signatureSoignantAffichee(contrat(soignant: true)))
        XCTAssertFalse(ContratRules.signatureSoignantAffichee(contrat()))
        XCTAssertTrue(ContratRules.certificatVisible(contrat(soignant: true)))
        XCTAssertTrue(ContratRules.certificatVisible(contrat(etablissement: true)))
        XCTAssertFalse(ContratRules.certificatVisible(contrat(statut: "SIGNE_COMPLET")), "le web lit les drapeaux (l.656)")
    }

    func testZoneDeSignature() {
        let pret = contrat(type: "CDDU", chemin: "k-1/a.html")
        XCTAssertTrue(ContratRules.zoneSignatureVisible(pret))
        XCTAssertFalse(ContratRules.zoneSignatureVisible(contrat()), "CDD à préparer par l'employeur")
        XCTAssertFalse(ContratRules.zoneSignatureVisible(contrat(type: "CDDU", soignant: true)), "déjà signé par moi")
        for statut in ["SIGNE_COMPLET", "ANNULE", "EXPIRE"] {
            XCTAssertFalse(ContratRules.zoneSignatureVisible(contrat(statut: statut, type: "CDDU")), statut)
        }
        // Le web n'exclut pas REFUSE de la zone (l.709) ; la signature serveur le refuse (CONTRAT_INACTIF).
        XCTAssertTrue(ContratRules.zoneSignatureVisible(contrat(statut: "REFUSE", type: "CDDU")))
        XCTAssertTrue(ContratRules.dejaSigneParMoi(contrat(soignant: true)))
        XCTAssertFalse(ContratRules.dejaSigneParMoi(contrat(soignantLe: "2026-11-01T15:00:00Z")), "drapeau du web (l.533)")
    }

    // MARK: - Rendu serveur

    func testRenduServeurDemandeSeulementSansOriginalNiSignatureHorsCddEtTerminaux() {
        XCTAssertTrue(ContratRules.renduServeurADemander(contrat(type: "CDDU")))
        XCTAssertTrue(ContratRules.renduServeurADemander(contrat(type: "REMPLACEMENT_LIBERAL", html: "<p>{{x}}</p>")))
        XCTAssertFalse(ContratRules.renduServeurADemander(contrat()), "CDD sans original : jamais de rendu (décision 19)")
        XCTAssertFalse(ContratRules.renduServeurADemander(contrat(type: "CDDU", chemin: "k-1/a.html")))
        XCTAssertFalse(ContratRules.renduServeurADemander(contrat(type: "CDDU", etablissement: true)), "document figé")
        XCTAssertFalse(ContratRules.renduServeurADemander(contrat(statut: "SIGNE_SOIGNANT", type: "CDDU")))
        for statut in ["ANNULE", "EXPIRE", "REFUSE"] {
            XCTAssertFalse(ContratRules.renduServeurADemander(contrat(statut: statut, type: "CDDU")), statut)
        }
    }
}
