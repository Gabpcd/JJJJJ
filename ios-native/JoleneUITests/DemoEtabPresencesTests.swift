import XCTest

/// Présences de l'espace établissement en démo (lot 5, T8, B9 ; `docs/mobile-swift/LOT5_PLAN.md` §3 T8) sur iPhone, iPad
/// portrait et iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) : onglets dérivés (à valider, en cours, validées,
/// alertes), validation de M7 avec une note de 4 puis « Validée » relue, contestation « Absent » de M8 (hors zone)
/// relue, clôture du segment ouvert de M4 relue, validation en lot (M7 seule éligible, M8 en alerte exclue), mission
/// terminée sans pointage (M11) et présences d'une mission (destination `.presencesMission` du registre), actions
/// présentes pour POINTAGE_ONLY (la clôture y reçoit le refus du serveur fictif, mot pour mot) et absentes pour
/// LECTURE_SEULE. Aucune requête réseau. Vérifié par la CI seulement (aucun simulateur en local), dans l'éclat
/// « lot5-etablissement » du job `ui-lot1` de `ios-swift-ci.yml`, hors du socle.
///
/// Écart au blueprint : le segment à clôturer est celui de M4 (et non de M6) — T7 a livré M6 avec son premier créneau
/// pointé et fermé ; les présences démo reprennent les segments du pointage démo, une seule histoire par mission.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela : l'écran rendu par l'onglet Présences est celui de T8, sur
/// les données fictives, et chaque succès affiché suit une relecture. Les règles (créneaux relus avant l'envoi, un seul
/// appel par geste, issue inconnue relue, refus serveur mot pour mot, interceptions, heure future refusée) sont prouvées
/// au niveau 1 (`PresencesEtabModelTests`, `PresencesEtabRulesTests`, `ClotureSegmentTests`,
/// `SupabaseEtabPresencesGatewayTests`). Le séquestre réel n'est touché par aucun de ces tests (monde démo).
final class DemoEtabPresencesTests: JoleneUITestCase {
    private let espaceEtablissement = ["-JOLENE_DEMO_ESPACE", "etablissement"]
    private let m7 = "demo-etab-p07"
    private let m8 = "demo-etab-p08"

    func testValidationNoteeContestationEtClotureRelues() throws {
        launchDemo(extraArguments: espaceEtablissement)
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirPresences()
        XCTAssertEqual(element("etab-presences-tab-a_valider").label, "À valider (2)")
        XCTAssertEqual(element("etab-presences-tab-en_cours").label, "En cours (2)")
        XCTAssertEqual(element("etab-presences-tab-validees").label, "Validées (0)")
        XCTAssertEqual(element("etab-presences-tab-alertes").label, "Alertes (2)", "M8 hors zone et M11 sans pointage")
        XCTAssertEqual(element("etab-presence-statut-\(m7)").label, "À valider")
        XCTAssertFalse(element("placeholder-etab-presences").exists, "écran de T8, jamais le provisoire")
        record("\(proofPrefix)-etab-presences-a-valider")

        // M7 : note obligatoire, validation, puis « Validée » seulement après relecture.
        let valider = element("etab-presence-valider-\(m7)")
        scrollTo(valider, in: defilement)
        valider.tap()
        let confirmer = element("etab-presence-confirmer")
        require("La note est demandée avant la validation") { confirmer.exists && self.element("etab-presence-note-4").exists }
        XCTAssertEqual(element("etab-validation-titre").label, "Noter Camille pour valider")
        XCTAssertFalse(confirmer.isEnabled, "aucune validation sans note")
        tap("etab-presence-note-4")
        require("La note choisie active la validation") { confirmer.isEnabled }
        record("\(proofPrefix)-etab-presence-note")
        scrollTo(confirmer, in: element("etab-validation-feuille"))
        confirmer.tap()
        let succes = element("etab-presences-succes")
        require("La validation relue est annoncée", timeout: 30) { !confirmer.exists && succes.exists }
        XCTAssertTrue(succes.label.contains("Présence validée et note 4/5 envoyée !"), succes.label)
        XCTAssertEqual(element("etab-presences-tab-a_valider").label, "À valider (1)")
        XCTAssertEqual(element("etab-presences-tab-validees").label, "Validées (1)")
        XCTAssertFalse(element("etab-presence-valider-\(m7)").exists, "une présence validée n'est plus proposée")
        tap("etab-presences-tab-validees")
        let statut = element("etab-presence-statut-\(m7)")
        require("M7 est relue « Validée »") { statut.exists && statut.label == "Validée" }
        record("\(proofPrefix)-etab-presence-validee")

        // M8 (hors zone) : contestation « Absent », motif relu.
        tap("etab-presences-tab-alertes")
        let horsZone = element("etab-presence-alerte-\(m8)-hors_zone")
        require("L'alerte hors zone de M8 est listée") { horsZone.exists }
        XCTAssertEqual(horsZone.label, "Hors zone")
        XCTAssertTrue(element("etab-presences-sans-pointage").exists, "missions terminées sans pointage")
        XCTAssertTrue(element("etab-presence-sans-pointage-demo-etab-m11").exists)
        let contester = element("etab-presence-contester-\(m8)")
        scrollTo(contester, in: defilement)
        contester.tap()
        let feuille = element("etab-contestation-feuille")
        let envoyer = element("etab-contestation-envoyer")
        require("La contestation est ouverte") { self.containerVisible(feuille) && envoyer.exists }
        XCTAssertFalse(envoyer.isEnabled, "sans motif : envoi impossible")
        let motif = element("etab-contestation-motif")
        focus(motif, in: feuille)
        motif.typeText("Absent")
        fermerLePaveNumerique()
        require("Un motif saisi active l'envoi") { envoyer.isEnabled }
        tap("etab-contestation-envoyer")
        let litige = element("etab-presence-litige-\(m8)")
        require("La contestation relue est affichée", timeout: 30) { !feuille.exists && litige.exists }
        XCTAssertTrue(litige.label.contains("Litige : Absent"), litige.label)
        let avertissement = element("etab-presences-avertissement")
        XCTAssertTrue(avertissement.exists && avertissement.label.contains("Contestation enregistrée."))
        record("\(proofPrefix)-etab-presence-contestee")

        // M4 : segment ouvert clôturé à l'heure proposée (maintenant), segment fermé relu.
        tap("etab-presences-tab-en_cours")
        let cloturer = element("etab-presence-cloturer-demo-etab-m04")
        require("La clôture du segment ouvert de M4 est proposée") { cloturer.exists }
        XCTAssertFalse(element("etab-presence-cloturer-demo-etab-m06").exists, "M6 : aucun segment ouvert")
        scrollTo(cloturer, in: defilement)
        cloturer.tap()
        let confirmerCloture = element("etab-cloture-confirmer")
        require("L'heure de fin est demandée") { confirmerCloture.exists }
        record("\(proofPrefix)-etab-cloture")
        scrollTo(confirmerCloture, in: element("etab-cloture-feuille"))
        confirmerCloture.tap()
        let cloture = element("etab-presences-succes")
        require("Le segment clôturé est relu", timeout: 30) {
            !confirmerCloture.exists && cloture.exists && cloture.label.contains("Segment clôturé.")
        }
        XCTAssertFalse(element("etab-presence-cloturer-demo-etab-m04").exists, "segment fermé relu : plus de clôture proposée")
        XCTAssertEqual(element("etab-presence-statut-demo-etab-p04").label, "En cours", "le planning de M4 n'est pas terminé")
        record("\(proofPrefix)-etab-segment-cloture")
    }

    func testValidationEnLotExclutLAlertePuisPresencesDUneMission() throws {
        launchDemo(extraArguments: espaceEtablissement)
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirPresences()
        let lot = element("etab-presences-lot")
        require("La validation en lot est proposée") { lot.exists }
        XCTAssertEqual(lot.label, "Tout valider (sans alerte) · 1 présences", "M7 seule éligible, M8 en alerte exclue")
        scrollTo(lot, in: defilement)
        lot.tap()
        let confirmer = element("etab-presences-lot-confirmer")
        require("La confirmation du lot est présentée") { confirmer.exists }
        XCTAssertEqual(confirmer.label, "Valider 1 présences")
        scrollTo(confirmer, in: element("etab-presences-lot-feuille"))
        confirmer.tap()
        let resultat = element("etab-presences-lot-resultat")
        require("Le résultat relu du lot est affiché", timeout: 30) { !confirmer.exists && resultat.exists }
        XCTAssertTrue(resultat.label.contains("1 présence validée sur 1 sélectionnée."), resultat.label)
        XCTAssertEqual(element("etab-presences-tab-validees").label, "Validées (1)")
        XCTAssertEqual(element("etab-presences-tab-a_valider").label, "À valider (1)", "M8 reste à valider")
        XCTAssertTrue(element("etab-presence-valider-\(m8)").exists)
        XCTAssertFalse(element("etab-presences-lot").isEnabled, "plus aucune présence sans alerte")
        record("\(proofPrefix)-etab-presences-lot")

        // Mission terminée sans pointage : détail natif, puis présences de la mission (destination du registre).
        tap("etab-presences-tab-alertes")
        let sansPointage = element("etab-presence-sans-pointage-demo-etab-m11")
        scrollTo(sansPointage, in: defilement)
        sansPointage.tap()
        let titre = element("etab-mission-titre")
        require("Le détail de M11 est relu") { titre.exists && titre.label == "Démonstration · Terminée sans pointage" }
        let lien = element("etab-mission-lien-presences")
        scrollTo(lien, in: element("etab-mission-detail"))
        XCTAssertEqual(lien.label.contains("sur jolene.app"), false, "T8 livrée : écran natif, plus la page web")
        lien.tap()
        require("Les présences de la mission sont relues") {
            self.defilement.exists && self.element("etab-presences-sans-pointage").exists
        }
        XCTAssertFalse(element("etab-presences-tabs").exists, "présences d'une mission : ni onglets ni lot")
        XCTAssertFalse(element("placeholder-etab-presences-mission").exists)
        XCTAssertTrue(element("etab-presences-lien-pointage").exists, "le code de pointage de la mission reste à un toucher (T7)")
        record("\(proofPrefix)-etab-presences-mission")
    }

    func testPointageOnlyActionsPresentesRefusDeClotureMotPourMot() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_ROLE_ETAB", "POINTAGE_ONLY"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirPresences()
        for action in ["etab-presence-valider-\(m7)", "etab-presence-contester-\(m7)", "etab-presences-lot", "etab-presence-valider-\(m8)"] {
            XCTAssertTrue(element(action).exists, "\(action) : action offerte avec la permission pointage servie")
        }
        tap("etab-presences-tab-en_cours")
        let cloturer = element("etab-presence-cloturer-demo-etab-m04")
        require("La clôture est proposée avec la permission pointage") { cloturer.exists }
        scrollTo(cloturer, in: defilement)
        cloturer.tap()
        let confirmer = element("etab-cloture-confirmer")
        require("L'heure de fin est demandée") { confirmer.exists }
        scrollTo(confirmer, in: element("etab-cloture-feuille"))
        confirmer.tap()
        let erreur = element("etab-presences-erreur")
        require("Le refus du serveur est affiché", timeout: 30) { !confirmer.exists && erreur.exists }
        XCTAssertTrue(erreur.label.contains("Vous n'êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission."), erreur.label)
        XCTAssertTrue(cloturer.exists, "segment toujours ouvert : rien n'a été clôturé")
        record("\(proofPrefix)-etab-presences-pointage-only")
    }

    func testLectureSeuleListeLisibleActionsAbsentes() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_ROLE_ETAB", "LECTURE_SEULE"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirPresences()
        XCTAssertEqual(element("etab-presences-tab-a_valider").label, "À valider (2)", "la lecture reste ouverte")
        XCTAssertTrue(element("etab-presence-\(m7)").exists)
        for action in ["etab-presence-valider-\(m7)", "etab-presence-contester-\(m7)", "etab-presences-lot",
                       "etab-presence-valider-\(m8)", "etab-presence-contester-\(m8)"] {
            XCTAssertFalse(element(action).exists, "\(action) : aucune action sans la permission pointage")
        }
        tap("etab-presences-tab-en_cours")
        require("Les présences en cours sont listées") { self.element("etab-presence-demo-etab-p04").exists }
        XCTAssertFalse(element("etab-presence-cloturer-demo-etab-m04").exists, "aucune clôture sans la permission pointage")
        XCTAssertFalse(element("etab-acces-refuse").exists)
        record("\(proofPrefix)-etab-presences-lecture-seule")
    }

    // MARK: Étapes

    /// Défilement de l'écran : la `ScrollView` qui porte `etab-presences-scroll`, ou `etab-presences-screen` quand
    /// SwiftUI fond le conteneur avec son seul enfant accessible (présences d'une mission, sans la barre d'onglets) —
    /// même règle que `defilementPointage` de `DemoEtabPointageTests`.
    private var defilement: XCUIElement {
        app.scrollViews.matching(NSPredicate(format: "identifier IN %@", ["etab-presences-scroll", "etab-presences-screen"])).firstMatch
    }

    private func ouvrirPresences() {
        toucherOnglet("tab-etab-presences", label: "Présences")
        require("Les présences de l'établissement sont relues") {
            self.containerVisible(self.element("etab-presences-screen")) && !self.element("etab-presences-loading").exists
                && self.element("etab-presences-tab-a_valider").exists
        }
    }
}
