import XCTest
@testable import JoleneCore

/// Textes et mise en forme de la publication (lot 5, T9) : formats du web, renvois web au texte neutre (D8), mention du
/// type de contrat affichée mot pour mot (intégration de la vague D, point 1, HARD STOP n°4, texte validé explicitement
/// par la fondatrice le 24/11/2026), et aucun texte de règle du travail ni de mode d'exercice écrit dans ce dossier.
final class PublicationPresentationTests: XCTestCase {
    private typealias P = PublicationPresentation

    func testFormatsDuWeb() {
        XCTAssertEqual(P.boutonPublier(creneaux: 0), "Publier la mission")
        XCTAssertEqual(P.boutonPublier(creneaux: 1), "Publier la mission")
        XCTAssertEqual(P.boutonPublier(creneaux: 3), "Publier la mission (3 créneaux)")
        XCTAssertEqual(P.resumeJours(travailles: 1, total: 3), "1 date travaillée sur 3")
        XCTAssertEqual(P.resumeJours(travailles: 2, total: 3), "2 dates travaillées sur 3")
        XCTAssertEqual(P.resumeRecap(creneaux: 1), "Planning exact · 1 créneau")
        XCTAssertEqual(P.resumeRecap(creneaux: 2), "Planning exact · 2 créneaux")
        XCTAssertEqual(P.duree(heures: 12), "12h00")
        XCTAssertEqual(P.duree(heures: 7.5), "7h30")
        XCTAssertEqual(P.tauxAffiche(30), "30.00 €/h")
        XCTAssertEqual(P.tauxAffiche(25.5), "25.50 €/h")
        XCTAssertEqual(P.libelleNiveau(1), "Modéré")
        XCTAssertEqual(P.libelleNiveau(2), "Élevé")
        XCTAssertEqual(P.libelleNiveau(3), "Critique")
        XCTAssertEqual(P.niveaux.map(\.niveau), Array(PublicationRules.niveauxUrgence))
        XCTAssertEqual(P.libelleMode(.premierArrive), "Premier arrivé")
        XCTAssertEqual(P.libelleMode(.candidature), "Je choisis")
        XCTAssertEqual(P.recapMode(.candidature), "Sur candidature")
    }

    func testDatesEtHeures() {
        XCTAssertEqual(P.libelleJour("2026-11-02"), "Lundi 2 novembre 2026")
        XCTAssertEqual(P.libelleJourTravaille("2026-11-02"), "Lundi 2 novembre 2026 travaillé")
        XCTAssertEqual(P.libelleJour("illisible"), "illisible")
        XCTAssertEqual(P.etatJour(true), "Travaillé")
        XCTAssertEqual(P.etatJour(false), "Repos")
        XCTAssertEqual(P.memeJour("2026-11-02"), "Même jour · lun. 2 nov.")
        XCTAssertEqual(P.lendemain("2026-11-02"), "Lendemain · mar. 3 nov.")
        let jour = PlanningDerive.Creneau(clientId: "c", heureDebut: "07:00", heureFin: "19:00", finJourSuivant: false)
        XCTAssertEqual(P.controleCreneau(date: "2026-11-02", creneau: jour).texte, "lun. 2 nov. 07:00 → lun. 2 nov. 19:00 · 12 h")
        XCTAssertTrue(P.controleCreneau(date: "2026-11-02", creneau: jour).valide)
        let inverse = PlanningDerive.Creneau(clientId: "c", heureDebut: "19:00", heureFin: "07:00", finJourSuivant: false)
        XCTAssertEqual(P.controleCreneau(date: "2026-11-02", creneau: inverse).texte, PlanningDerive.messageFinAvantDebut)
        XCTAssertFalse(P.controleCreneau(date: "2026-11-02", creneau: inverse).valide)
        let materialise = PlanningDerive.CreneauMaterialise(clientId: "c", id: nil, date: "2026-11-02", dateFin: "2026-11-03",
                                                            debut: "2026-11-02T21:00:00.000Z", fin: "2026-11-03T05:00:00.000Z", dureeHeures: 8)
        XCTAssertEqual(P.ligneRecap(materialise), "lundi 2 novembre 2026 · 22:00 → mardi 3 novembre 2026 · 06:00")

        XCTAssertEqual(P.dateDuJour("2026-11-02").map(P.cleJour), "2026-11-02", "aller-retour du sélecteur de date")
        XCTAssertNil(P.dateDuJour(""))
        for heure in ["00:00", "07:00", "19:30", "23:59"] {
            XCTAssertEqual(P.dateDeLHeure(heure).map(P.heure), heure, "aller-retour du sélecteur d'heure")
        }
        XCTAssertNil(P.dateDeLHeure("24:00"))
        XCTAssertNil(P.dateDeLHeure("7h"))
    }

    func testRenvoisWebAuTexteNeutre() {
        XCTAssertEqual(P.renvoiWebMessage, "Cette option se configure sur jolene.app.", "texte neutre de D8, mot pour mot")
        XCTAssertEqual(P.RenvoiWeb.allCases.map(\.identifiant), [
            "publier-renvoi-web-liberal", "publier-renvoi-web-medecin", "publier-renvoi-web-recurrence", "publier-renvoi-web-dupliquer",
        ])
        XCTAssertEqual(P.RenvoiWeb.liberal.url.absoluteString, "https://jolene.app/etablissement/missions/creer")
        XCTAssertEqual(P.RenvoiWeb.medecin.url, P.RenvoiWeb.liberal.url)
        XCTAssertEqual(P.RenvoiWeb.recurrence.url, P.RenvoiWeb.liberal.url)
        XCTAssertEqual(P.RenvoiWeb.dupliquer.url.absoluteString, "https://jolene.app/etablissement/missions")
        XCTAssertTrue(P.RenvoiWeb.medecin.titre.hasSuffix("Médecin"))
        for renvoi in P.RenvoiWeb.allCases { XCTAssertFalse(renvoi.titre.isEmpty) }
    }

    func testRenvoiDUnBlocageSelonSonCode() {
        for code in ["PUBLICATION_SUSPENDUE", "FACTURES_IMPAYEES"] {
            XCTAssertEqual(P.urlBlocage(code: code).absoluteString, "https://jolene.app/etablissement/facturation", code)
        }
        for code in ["ETABLISSEMENT_NON_VERIFIE", "VERIFICATION_INCOMPLETE", "CONTRAT_SERVICE_REQUIS", "CODE_INCONNU"] {
            XCTAssertEqual(P.urlBlocage(code: code).absoluteString, "https://jolene.app/etablissement/activer", code)
        }
    }

    func testIssueNonConfirmee() {
        XCTAssertEqual(P.texteNonConfirmee(detail: nil), P.nonConfirmee)
        XCTAssertEqual(P.texteNonConfirmee(detail: ""), P.nonConfirmee)
        XCTAssertEqual(P.texteNonConfirmee(detail: "Délai dépassé."), "Délai dépassé.\n" + P.nonConfirmee)
        XCTAssertFalse(P.nonConfirmee.lowercased().contains("publiée"), "jamais un succès supposé")
    }

    // MARK: - HARD STOP n°4

    /// La mention du type de contrat (texte du web à portée juridique, `TextesWeb.PublicationEtablissement`) est affichée
    /// mot pour mot depuis la décision c de l'intégration de la vague D (`DECISIONS_LOT5.md`, point 1 ; texte validé
    /// explicitement par la fondatrice le 24/11/2026). Verrou gardé : si elle
    /// redevenait `nil`, l'espace établissement devrait rester fermé hors démonstration.
    func testMentionContratExigeeAvantToutEspaceOuvertHorsDemo() {
        XCTAssertNotNil(PublicationPresentation.mentionContrat, "décision c : mention affichée")
        if PublicationPresentation.mentionContrat == nil {
            XCTAssertEqual(OuvertureEspaceEtablissement.pour(mode: .staging), .ferme,
                           "récapitulatif sans mention du type de contrat : espace fermé en STAGING")
            XCTAssertEqual(OuvertureEspaceEtablissement.pour(mode: .production), .ferme,
                           "récapitulatif sans mention du type de contrat : espace fermé en production")
        } else {
            XCTAssertEqual(PublicationPresentation.mentionContrat?.libelle, TextesWeb.PublicationEtablissement.optionSalarieLibelle)
            XCTAssertEqual(PublicationPresentation.mentionContrat?.description, TextesWeb.PublicationEtablissement.optionSalarieDescription)
        }
    }

    /// Aucun texte de `PublicationPresentation` ne reprend le texte verrouillé ni ne nomme un plafond d'heures.
    func testAucunTexteJuridiqueEcritIci() {
        let textes = [P.titreEcran, P.intitule, P.description, P.profession, P.service, P.planningTitre, P.planningAide, P.taux,
                      P.urgente, P.urgenteAide, P.modeSelection, P.modePremierArriveAide, P.modeCandidatureAide, P.succes,
                      P.datesTitre, P.datesAide, P.recapTitre, P.recapMessage, P.renvoiWebMessage, P.nonConfirmee]
            + P.RenvoiWeb.allCases.map(\.titre) + P.niveaux.map(\.libelle)
        let interdit = TextesWeb.PublicationEtablissement.optionSalarieDescription
        for texte in textes {
            XCTAssertFalse(texte.contains(interdit), texte)
            XCTAssertNil(texte.range(of: #"\b48\s?h\b|plafond l[ée]gal|employeur"#, options: [.regularExpression, .caseInsensitive]), texte)
        }
    }
}
