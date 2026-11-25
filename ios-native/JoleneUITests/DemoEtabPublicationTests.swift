import XCTest

/// Publication d'une mission dans l'espace établissement en démo (lot 5, T9 ; `docs/mobile-swift/LOT5_PLAN.md` §3 T9) sur
/// iPhone, iPad portrait et iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) : destination `.publication` du
/// registre ouverte par « Publier » (barre de Missions), formulaire réduit au périmètre natif (D8), période → jours →
/// créneaux (jours dérivés au repos, puis travaillés au toucher), récapitulatif, publication relue, mission visible
/// parmi les « Ouvertes », renvois web au texte neutre, blocage de publication (`-JOLENE_DEMO_BLOCAGE 1`), aucun bouton
/// « Publier » sans la permission `missions` (POINTAGE_ONLY). Horloge démo : lundi 2 novembre 2026. Aucune requête
/// réseau. Vérifié par la CI seulement (aucun simulateur en local), dans l'éclat « lot5-etablissement » de
/// `ios-swift-ci.yml` (job `ui-lot1`), hors du socle.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela : l'écran rendu par la destination `.publication` est celui
/// de T9, sur le monde fictif ; les règles (charge de seize paramètres, re-dérivation, envoi unique, relecture, refus
/// serveur mot pour mot) sont prouvées au niveau 1 (`PublicationPayloadTests`, `PublicationModelTests`,
/// `DemoEtabPublicationGatewayTests`, `SupabaseEtabPublicationGatewayTests`).
final class DemoEtabPublicationTests: JoleneUITestCase {
    private let espaceEtablissement = ["-JOLENE_DEMO_ESPACE", "etablissement"]
    private static let professionIDE = "Infirmier(ère) Diplômé(e) d'État (IDE)"
    /// Jour civil de Paris de l'horloge démo (`DemoWorld.fixedNow`) et les deux suivants.
    private static let jours = ["2026-11-02", "2026-11-03", "2026-11-04"]

    func testMissionSimpleUnJourRecapPublieeRelueVisibleParmiLesOuvertes() throws {
        launchDemo(extraArguments: espaceEtablissement)
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirPublication()
        let ecran = element("publier-screen")
        XCTAssertFalse(element("placeholder-etab-publication").exists, "écran de T9, jamais le provisoire")
        let ouvrirRecap = element("publier-ouvrir-recap")

        saisirIntitule("Renfort de jour")
        choisirProfession()
        choisirPeriode(jours: 1)
        let jour = element("publier-jour-\(Self.jours[0])")
        XCTAssertEqual(jour.value as? String, "Repos", "un jour dérivé de la période arrive au repos, jamais prérempli")
        XCTAssertFalse(element("publier-creneau-\(Self.jours[0])-0").exists, "aucun créneau affiché pour un jour au repos")
        basculer(jour, attendu: "Travaillé")
        let controle = element("publier-creneau-\(Self.jours[0])-0-controle")
        scrollTo(controle, in: ecran)
        XCTAssertEqual(controle.label, "lun. 2 nov. 07:00 → lun. 2 nov. 19:00 · 12 h", "créneau proposé par le web")
        XCTAssertEqual(element("publier-jours-resume").label, "1 date travaillée sur 1")
        record("\(proofPrefix)-etab-publication-planning")
        saisirTaux("30")

        // Options renvoyées au web (D8) : texte neutre, URL routée, aucun choix de contrat ni de mode d'exercice natif.
        for (cle, url) in [("liberal", "https://jolene.app/etablissement/missions/creer"),
                           ("medecin", "https://jolene.app/etablissement/missions/creer"),
                           ("recurrence", "https://jolene.app/etablissement/missions/creer"),
                           ("dupliquer", "https://jolene.app/etablissement/missions")] {
            let renvoi = element("publier-renvoi-web-\(cle)")
            scrollTo(renvoi, in: ecran)
            XCTAssertEqual(renvoi.value as? String, url, "renvoi \(cle)")
            XCTAssertTrue(renvoi.label.hasSuffix("Cette option se configure sur jolene.app."), renvoi.label)
        }
        record("\(proofPrefix)-etab-publication-renvois-web")

        scrollTo(ouvrirRecap, in: ecran)
        require("La saisie valide active la publication") { ouvrirRecap.isEnabled }
        XCTAssertEqual(ouvrirRecap.label, "Publier la mission")
        ouvrirRecap.tap()
        attendreRecap()
        XCTAssertEqual(element("publier-recap-title").label, "Récapitulatif avant publication")
        XCTAssertEqual(element("publier-recap-total").label, "Planning exact · 1 créneau · Durée estimée 12h00")
        XCTAssertTrue(element("publier-recap-creneau-1").label.contains("lundi 2 novembre 2026 · 07:00 → lundi 2 novembre 2026 · 19:00"),
                      element("publier-recap-creneau-1").label)
        XCTAssertFalse(element("publier-recap-creneau-2").exists)
        // Décision c de l'intégration de la vague D : mention du web (`FormulaireMission.tsx` l.766), mot pour mot.
        let contrat = element("publier-recap-contrat")
        XCTAssertTrue(contrat.exists, "mention du type de contrat affichée dans le récapitulatif")
        XCTAssertTrue(contrat.label.contains("Vous êtes l’employeur : CDD, bulletin de paie, plafond légal 48 h/semaine"),
                      contrat.label)
        XCTAssertFalse(element("publier-succes").exists, "aucun succès avant l'envoi")
        record("\(proofPrefix)-etab-publication-recap")
        confirmerRecap()

        let succes = element("publier-succes")
        require("La mission est annoncée publiée après relecture", timeout: 30) {
            !self.element("publier-recap").exists && succes.exists
        }
        XCTAssertTrue(succes.label.contains("Mission publiée"), succes.label)
        XCTAssertFalse(element("publier-ouvrir-recap").exists, "le formulaire publié ne peut pas être renvoyé")
        record("\(proofPrefix)-etab-publication-succes")

        tap("publier-succes-missions")
        attendreListeOuvertes(nombre: 6)
        let carte = element("etab-mission-card-demo-etab-publiee-1")
        scrollTo(carte, in: element("etab-missions-scroll"))
        XCTAssertTrue(carte.label.contains("Renfort de jour"), carte.label)
        XCTAssertTrue(carte.label.contains("Ouverte"), carte.label)
        XCTAssertFalse(carte.label.contains("Urgence"), "mission simple : aucune urgence envoyée")
        XCTAssertFalse(carte.label.contains("€"), "aucun montant sur la carte (D15)")
        record("\(proofPrefix)-etab-publication-liste")
    }

    func testUrgenteNiveauDeuxPeriodeDeTroisJoursUnJourRemisAuRepos() throws {
        launchDemo(extraArguments: espaceEtablissement)
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirPublication()
        let ecran = element("publier-screen")

        saisirIntitule("Renfort urgent")
        choisirProfession()
        choisirPeriode(jours: 3)
        for date in Self.jours { basculer(element("publier-jour-\(date)"), attendu: "Travaillé") }
        XCTAssertEqual(element("publier-jours-resume").label, "3 dates travaillées sur 3")
        // « Décocher » le deuxième jour : il reste dans la période, au repos, et son créneau n'est plus dérivé.
        basculer(element("publier-jour-\(Self.jours[1])"), attendu: "Repos")
        XCTAssertEqual(element("publier-jours-resume").label, "2 dates travaillées sur 3")
        XCTAssertFalse(element("publier-creneau-\(Self.jours[1])-0").exists)
        record("\(proofPrefix)-etab-publication-trois-jours")
        saisirTaux("32")

        let urgente = app.switches.matching(identifier: "publier-urgente").firstMatch
        scrollTo(urgente, in: ecran)
        XCTAssertFalse(element("publier-niveau-2").exists, "niveau proposé seulement pour une mission urgente")
        cocher(urgente, in: ecran)
        let niveau = element("publier-niveau-2")
        scrollTo(niveau, in: ecran)
        niveau.tap()
        require("Le niveau 2 est choisi") { niveau.isSelected }
        let candidature = element("publier-mode-CANDIDATURE")
        scrollTo(candidature, in: ecran)
        candidature.tap()
        require("Le mode « Je choisis » est choisi") { candidature.isSelected }
        XCTAssertEqual(element("publier-mode-aide").label, "Les soignants postulent, vous consultez les profils et choisissez.")

        let ouvrirRecap = element("publier-ouvrir-recap")
        scrollTo(ouvrirRecap, in: ecran)
        require("La saisie valide active la publication") { ouvrirRecap.isEnabled }
        XCTAssertEqual(ouvrirRecap.label, "Publier la mission (2 créneaux)", "créneaux dérivés des jours travaillés")
        ouvrirRecap.tap()
        attendreRecap()
        XCTAssertEqual(element("publier-recap-total").label, "Planning exact · 2 créneaux · Durée estimée 24h00")
        XCTAssertTrue(element("publier-recap-creneau-1").label.contains("lundi 2 novembre 2026"), element("publier-recap-creneau-1").label)
        XCTAssertTrue(element("publier-recap-creneau-2").label.contains("mercredi 4 novembre 2026"),
                      "le jour remis au repos n'est pas envoyé : \(element("publier-recap-creneau-2").label)")
        XCTAssertFalse(element("publier-recap-creneau-3").exists)
        let infos = element("publier-recap-infos")
        XCTAssertTrue(infos.exists)
        record("\(proofPrefix)-etab-publication-recap-urgente")
        confirmerRecap()
        require("La mission urgente est annoncée publiée après relecture", timeout: 30) {
            !self.element("publier-recap").exists && self.element("publier-succes").exists
        }

        // La charge reçue par le monde démo (journalisée) est relue par la liste : urgence de niveau 2, deux créneaux.
        tap("publier-succes-missions")
        attendreListeOuvertes(nombre: 6)
        let carte = element("etab-mission-card-demo-etab-publiee-1")
        scrollTo(carte, in: element("etab-missions-scroll"))
        XCTAssertTrue(carte.label.contains("Urgence niveau élevé"), carte.label)
        XCTAssertTrue(carte.label.contains("2 créneaux · 24 h planifiées"), carte.label)
        XCTAssertTrue(carte.label.contains("Renfort urgent"), carte.label)
        record("\(proofPrefix)-etab-publication-urgente-liste")
    }

    func testBlocageDePublicationMessageServeurEtRenvoiWeb() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_BLOCAGE", "1"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirPublication()
        let ecran = element("publier-screen")
        saisirIntitule("Renfort de jour")
        choisirProfession()
        choisirPeriode(jours: 1)
        basculer(element("publier-jour-\(Self.jours[0])"), attendu: "Travaillé")
        saisirTaux("30")
        let ouvrirRecap = element("publier-ouvrir-recap")
        scrollTo(ouvrirRecap, in: ecran)
        require("La saisie valide active la publication") { ouvrirRecap.isEnabled }
        ouvrirRecap.tap()
        attendreRecap()
        confirmerRecap()

        let blocage = element("publier-blocage")
        require("Le blocage du serveur est affiché, rien n'est publié", timeout: 30) {
            !self.element("publier-recap").exists && blocage.exists
        }
        scrollTo(blocage, in: ecran, downward: false)
        XCTAssertTrue(blocage.label.contains("Publication suspendue en raison d obligations de paiement à régulariser."), blocage.label)
        XCTAssertFalse(element("publier-succes").exists, "jamais « publiée » sur un refus")
        let ouvrir = element("publier-blocage-ouvrir")
        XCTAssertEqual(ouvrir.value as? String, "https://jolene.app/etablissement/facturation", "renvoi web du blocage")
        record("\(proofPrefix)-etab-publication-blocage")
    }

    func testPointageOnlySansBoutonPublier() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_ROLE_ETAB", "POINTAGE_ONLY"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        require("L'Accueil établissement est affiché") { self.containerVisible(self.element("etab-accueil-screen")) }
        XCTAssertFalse(element("etab-accueil-publier").exists, "aucune publication sans la permission missions (Accueil)")
        tabButton("tab-etab-missions", label: "Missions").tap()
        require("La liste des missions est relue") {
            self.containerVisible(self.element("etab-missions-screen")) && self.element("etab-missions-count").exists
        }
        XCTAssertFalse(element("etab-missions-publier").exists, "aucun bouton « Publier » sans la permission missions")
        XCTAssertFalse(element("publier-screen").exists)
        record("\(proofPrefix)-etab-publication-pointage-only")
    }

    // MARK: Étapes

    private func ouvrirPublication() {
        tabButton("tab-etab-missions", label: "Missions").tap()
        require("La liste des missions est relue") {
            self.containerVisible(self.element("etab-missions-screen")) && self.element("etab-missions-count").exists
        }
        tap("etab-missions-publier")
        require("Le registre de destinations ouvre l'écran de publication") {
            self.containerVisible(self.element("publier-screen")) && self.element("publier-intitule").exists
        }
    }

    private func saisirIntitule(_ texte: String) {
        let ecran = element("publier-screen")
        let intitule = element("publier-intitule")
        focus(intitule, in: ecran)
        intitule.typeText(texte)
        intitule.typeText("\n")
        require("Le clavier est fermé après l'intitulé") { !self.app.keyboards.firstMatch.exists }
        XCTAssertEqual(intitule.value as? String, texte)
    }

    /// Profession par le menu : la liste native ne propose pas la profession renvoyée au web (D8).
    private func choisirProfession() {
        let profession = element("publier-profession")
        scrollTo(profession, in: element("publier-screen"))
        tap("publier-profession")
        let option = app.buttons[Self.professionIDE].firstMatch
        require("La liste des professions est ouverte") { self.visible(option) }
        XCTAssertFalse(app.buttons["Médecin"].exists, "« Médecin » absent de la liste native (renvoi web, D8)")
        // Le choix est prouvé par le récapitulatif et par la mission relue.
        option.tap()
        require("Le menu des professions est refermé") { !option.exists || !self.visible(option) }
    }

    /// Pose la première puis la dernière date (jour de l'horloge démo), puis étend la période jour par jour.
    private func choisirPeriode(jours nombre: Int) {
        let ecran = element("publier-screen")
        let debut = element("publier-date-debut-choisir")
        scrollTo(debut, in: ecran)
        // Le sélecteur et ses boutons « jour précédent / suivant » n'existent qu'une fois la date posée.
        XCTAssertFalse(element("publier-date-debut-suivant").exists, "aucune date fictive affichée avant le choix")
        debut.tap()
        require("La première date est posée") { self.element("publier-date-debut-suivant").exists }
        XCTAssertFalse(element("publier-jour-\(Self.jours[0])").exists, "une seule borne : aucun jour dérivé")
        let fin = element("publier-date-fin-choisir")
        scrollTo(fin, in: ecran)
        fin.tap()
        // Les cartes des jours sont dans une liste paresseuse (`LazyVStack` de `PlanningJoursEditor`) : un jour hors de
        // l'écran n'existe pas encore pour XCUITest. En iPad paysage (820 pt de haut), « Choisir la date » de fin est au
        // bas de l'écran et la carte du jour dérivé en dessous (run 45446351274 : trois tests en échec ici, le résumé
        // « 0 date travaillée sur 1 » affiché, la carte non encore construite). Le jour est donc ramené dans la vue avant
        // d'être exigé : la preuve reste l'existence de la carte du jour dérivé.
        require("La période d'un jour est posée") { !fin.exists && self.element("publier-jours-resume").exists }
        let premierJour = element("publier-jour-\(Self.jours[0])")
        scrollTo(premierJour, in: ecran)
        require("La période d'un jour dérive son jour") { premierJour.exists }
        if nombre > 1 {
            let suivant = element("publier-date-fin-suivant")
            for rang in 1..<nombre {
                scrollTo(suivant, in: ecran, downward: false)
                suivant.tap()
                let jour = element("publier-jour-\(Self.jours[rang])")
                scrollTo(jour, in: ecran)
                require("La période étendue dérive le jour \(Self.jours[rang])") { jour.exists }
            }
        }
        XCTAssertFalse(element("publier-jour-\(nombre < Self.jours.count ? Self.jours[nombre] : "2026-11-05")").exists,
                       "aucun jour hors de la période")
        // Liste paresseuse : le résumé (toujours construit) compte les jours dérivés, sans dépendre du défilement.
        let resume = element("publier-jours-resume").label
        XCTAssertTrue(resume.hasSuffix(" sur \(nombre)"), "\(nombre) jour(s) dérivé(s) de la période : \(resume)")
    }

    /// Bascule un jour (travaillé / repos) et exige l'état relu ; un toucher perdu est rejoué une fois, et consigné.
    private func basculer(_ jour: XCUIElement, attendu: String, file: StaticString = #filePath, line: UInt = #line) {
        scrollTo(jour, in: element("publier-screen"), file: file, line: line)
        let description = "Le jour \(jour.identifier) est « \(attendu) »"
        jour.tap()
        if !attendreSansEchec(description, timeout: 5, file: file, line: line, condition: { (jour.value as? String) == attendu }) {
            consignerRejeu(description, issue: "toucher sans effet en 5 s : un seul nouveau toucher", file: file, line: line)
            jour.tap()
        }
        require(description, file: file, line: line) { (jour.value as? String) == attendu }
    }

    private func saisirTaux(_ valeur: String) {
        let ecran = element("publier-screen")
        let taux = element("publier-taux")
        scrollTo(taux, in: ecran)
        focus(taux, in: ecran)
        taux.typeText(valeur)
        // Pavé décimal sans touche Entrée : fermé par « OK », jamais par un glissement.
        fermerLePaveNumerique()
        XCTAssertEqual(taux.value as? String, valeur)
    }

    /// Coche un interrupteur (`ToggleRow` : commutateur à droite de la ligne) et exige l'état coché ; rejoué seulement si
    /// la valeur relue vaut encore « 0 », trois fois au plus.
    private func cocher(_ interrupteur: XCUIElement, in ecran: XCUIElement) {
        for _ in 0..<3 where (interrupteur.value as? String) != "1" {
            if coveredByNavigationBar(interrupteur) { drag(ecran, fromY: 0.4, toY: 0.6) }
            require("L'interrupteur \(interrupteur.identifier) est activable") { interrupteur.isEnabled }
            interrupteur.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            if attendreSansEchec("L'interrupteur \(interrupteur.identifier) est coché", timeout: 3,
                                 condition: { (interrupteur.value as? String) == "1" }) { break }
        }
        require("L'interrupteur \(interrupteur.identifier) est coché") { (interrupteur.value as? String) == "1" }
    }

    private func attendreRecap() {
        require("Le récapitulatif est présenté") {
            self.element("publier-recap").exists && self.element("publier-recap-total").exists
        }
    }

    /// « Publier » : la feuille s'ouvre à mi-hauteur, le bouton est d'abord ramené dans la vue.
    private func confirmerRecap() {
        let confirmer = element("publier-recap-confirm")
        require("Le récapitulatif est présenté") { confirmer.exists }
        scrollTo(confirmer, in: element("publier-recap"))
        require("La publication est active") { confirmer.isEnabled }
        XCTAssertEqual(confirmer.label, "Publier")
        confirmer.tap()
    }

    /// Retour à la liste des missions relue, filtre « Ouvertes ».
    private func attendreListeOuvertes(nombre: Int) {
        require("La liste des missions est relue après la publication", timeout: 30) {
            self.containerVisible(self.element("etab-missions-screen")) && self.element("etab-missions-count").exists
        }
        tap("etab-missions-filtre-OUVERTE")
        require("Le filtre Ouvertes compte la mission publiée") {
            self.element("etab-missions-count").label == "\(nombre) missions trouvées"
        }
    }
}
