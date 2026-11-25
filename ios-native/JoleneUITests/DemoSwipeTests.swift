import XCTest

/// Vue Swipe d'Explorer (L4-T3b, `/soignant/swipe-missions`) en démonstration, sur iPhone, iPad portrait et iPad
/// paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`). Fixture `demo-swipe.json` : douze cartes, dans l'ordre
/// `demo-mission-015`, `demo-swipe-choix` (contrat au choix), 016, 017, 018, 020, 021, 022, 023, 024, puis deux cartes
/// sans score, `demo-mission-019` et `demo-swipe-deja` (déjà swipée ailleurs). Aucune requête réseau (sentinelle).
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - Explorer s'ouvre sur la liste, la commande « Swipe · Liste » bascule, le quiz est proposé au premier contact avec
///   le paquet puis plus jamais, ses réponses s'appliquent à Explorer ; la question « missions urgentes » du web n'y
///   figure pas (D26), remplacée par un renvoi vers Pool urgence ;
/// - ✕ retire la carte (compteur 12 → 11), ⭐ la sauvegarde (elle figure dans Mes favoris) ;
/// - ❤️ : récapitulatif exact, puis feuille « première candidature » **la première fois seulement**, textes repris mot
///   pour mot du web (HARD STOP n°4) ; « Pas maintenant » n'envoie rien et ne mémorise rien ; la candidature envoyée
///   figure dans Mes missions › Candidatures ;
/// - « Annuler » du toast retire la candidature (absente de Mes missions), la carte ne revient pas dans le paquet (D4) ;
/// - carte `demo-swipe-choix` : choix du contrat demandé, ❤️ rejoué avec l'option ;
/// - cartes sans score : ni pastille ni « Pourquoi ? » ; carte déjà swipée : refus affiché, carte retirée ; fin de
///   paquet avec les missions sauvegardées, rayon élargi et retour à la liste ;
/// - lien `/soignant/swipe-missions` : Explorer en vue Swipe ; renvoi du quiz vers le Pool urgence natif ; détail d'une
///   carte, « Vérifier et postuler », « Suivant ».
///
/// Toutes les actions passent par les boutons `swipe-passer`, `swipe-sauvegarder`, `swipe-candidater` (D22) : le geste
/// de glissement n'est pas rejoué ici (fragile en CI), ses règles sont prouvées par `JoleneDesignLot4Tests`. Les règles
/// du modèle (carte retirée seulement après la réponse du serveur, refus, délai, epoch, feuille obligatoire avant le
/// premier envoi) sont prouvées par `SwipeModelTests` et `ParcoursCandidatureSwipeTests`. Le toast d'annulation dure
/// 5 s dans l'app (D4) ; `JOLENE_DEMO_SWIPE_ANNULATION` l'allonge ici (démo, DEBUG) pour que le test ne dépende pas de la
/// vitesse du simulateur.
final class DemoSwipeTests: JoleneUITestCase {
    private enum Attendus {
        static let total = 12
        static let premiere = "demo-mission-015"
        static let choix = "demo-swipe-choix"
        static let troisieme = "demo-mission-016"
        static let sansScore = "demo-mission-019"
        static let deja = "demo-swipe-deja"
        /// Cartes entre la deuxième et les deux cartes sans score, dans l'ordre servi.
        static let milieu = ["demo-mission-016", "demo-mission-017", "demo-mission-018", "demo-mission-020", "demo-mission-021",
                             "demo-mission-022", "demo-mission-023", "demo-mission-024"]
        /// Toasts gardés à l'écran pendant tout le test (5 s dans l'app, prouvées par `SwipeMarqueursTests`).
        static let annulation = ["JOLENE_DEMO_SWIPE_ANNULATION": "300"]
    }

    /// Feuille « première candidature » : textes du web, mot pour mot (`VueSwipeMissions.tsx` l.540-563, HARD STOP n°4).
    private enum PremiereCandidature {
        static let titre = "Ta première candidature 🎉"
        static let description = "Ici, candidater est un engagement — pas un simple like."
        static let acceptation = "L'établissement peut t'accepter directement — si c'est le cas, la mission est confirmée : il compte sur toi auprès de ses patients."
        static let retraitLibre = "Tu peux retirer ta candidature librement tant qu'elle n'est pas acceptée."
        static let annulationTardive = "Après acceptation, une annulation tardive impacte ton score de fiabilité."
        static let pasMaintenant = "Pas maintenant"
        static let confirmer = "J'ai compris — envoyer ma candidature"
    }

    /// Phrase d'engagement du récapitulatif (`RecapitulatifCandidatureDialog.tsx` l.53, HARD STOP n°4).
    private static let engagementCandidature = "En confirmant, tu t’engages sur ces dates et horaires exacts. Une candidature peut être retirée tant qu’elle n’est pas acceptée."

    // MARK: - Bascule et quiz

    func testBasculeQuizAuPremierContactPuisPlusJamais() throws {
        launchDemo()
        connexionDemo()
        ouvrirExplorerEnListe()
        XCTAssertFalse(element("swipe-deck").exists, "Explorer s'ouvre sur la liste tant que le soignant n'a pas choisi Swipe")

        tap("explorer-vue-swipe")
        let quiz = defilement("swipe-quiz")
        require("Le quiz est proposé au premier contact avec le paquet", timeout: 30) {
            self.containerVisible(quiz) && self.element("swipe-quiz-valider").exists
        }
        XCTAssertEqual(element("swipe-quiz-titre").label, "4 questions pour un deck qui vous ressemble")
        XCTAssertEqual(elements(withPrefix: "swipe-quiz-horaire-").count, 3)
        XCTAssertEqual(elements(withPrefix: "swipe-quiz-rythme-").count, 3)
        XCTAssertEqual(elements(withPrefix: "swipe-quiz-rayon-").count, 4)
        XCTAssertEqual(elements(withPrefix: "swipe-quiz-taux-").count, 4)
        XCTAssertEqual(elements(withPrefix: "swipe-quiz-urgence").count, 0, "la question « missions urgentes » du web n'est pas portée (D26)")
        XCTAssertTrue(element("swipe-quiz-pool-urgence").exists, "renvoi vers Pool urgence à la place")
        record("\(proofPrefix)-swipe-quiz")

        let rayon = element("swipe-quiz-rayon-10")
        scrollTo(rayon, in: quiz)
        rayon.tap()
        require("La réponse « 10 km » est sélectionnée") { rayon.isSelected }
        let valider = element("swipe-quiz-valider")
        scrollTo(valider, in: quiz)
        XCTAssertEqual(valider.label, "C'est parti 🚀")
        valider.tap()
        require("Le quiz est refermé et le paquet affiché", timeout: 30) {
            !self.element("swipe-quiz").exists && self.element("swipe-restantes").exists
        }
        XCTAssertEqual(element("swipe-restantes").label, "12 missions à parcourir")
        require("La confirmation du quiz est affichée") { self.element("swipe-avis").exists }
        XCTAssertTrue(element("swipe-avis").label.contains("C'est noté — votre deck est personnalisé ✨"), element("swipe-avis").label)
        XCTAssertTrue(element("explorer-vue-swipe").isSelected)

        // Les réponses du quiz sont les critères d'Explorer : la liste annonce le rayon choisi.
        tap("explorer-vue-liste")
        require("La liste d'Explorer est de retour", timeout: 30) {
            self.containerVisible(self.element("missions-list")) && self.element("missions-rayon").exists
        }
        XCTAssertEqual(element("missions-rayon").label, "dans un rayon de 10 km")
        XCTAssertFalse(element("swipe-deck").exists)

        // Retour sur Swipe : le quiz ne revient plus.
        tap("explorer-vue-swipe")
        require("Le paquet est de retour") { self.element("swipe-restantes").exists }
        requireAbsence("Le quiz n'est proposé qu'une fois") { self.element("swipe-quiz").exists }
        record("\(proofPrefix)-swipe-paquet")
        verifierAucuneRequete()
    }

    // MARK: - ✕ et ⭐

    func testPasserPuisSauvegarderFigureDansMesFavoris() throws {
        ouvrirSwipe()
        carteEnTete(Attendus.premiere)
        let score = element("swipe-score-\(Attendus.premiere)")
        XCTAssertTrue(score.exists, "score servi : pastille")
        XCTAssertEqual(score.label, "Score 94 sur 100")
        XCTAssertTrue(element("swipe-pourquoi-\(Attendus.premiere)").label.hasPrefix("Pourquoi 94 ?"),
                      element("swipe-pourquoi-\(Attendus.premiere)").label)
        XCTAssertEqual(element("swipe-etablissement-\(Attendus.premiere)").label, "Cabinet fictif du Parc")
        XCTAssertEqual(element("swipe-lieu-\(Attendus.premiere)").label, "Vincennes 94300 · 6.4 km")
        XCTAssertEqual(element("swipe-accroche-\(Attendus.premiere)").label, "29€/h")
        record("\(proofPrefix)-swipe-carte")

        tap("swipe-passer")
        attendreRestantes(11)
        carteEnTete(Attendus.choix)
        XCTAssertFalse(element("swipe-card-\(Attendus.premiere)").exists, "carte passée : retirée après la réponse du serveur")
        XCTAssertFalse(element("swipe-erreur").exists)

        tap("swipe-sauvegarder")
        attendreRestantes(10)
        let toast = element("swipe-toast")
        require("La sauvegarde relue est annoncée") { toast.exists }
        XCTAssertTrue(toast.label.contains("Mission sauvegardée ⭐"), toast.label)

        // ⭐ : la mission figure dans Mes favoris (lot 1).
        tap("explorer-favoris-ouvrir")
        require("Mes favoris liste la mission sauvegardée depuis le paquet", timeout: 30) {
            self.containerVisible(self.element("favoris-screen")) && self.element("favori-mission-\(Attendus.choix)").exists
        }
        record("\(proofPrefix)-swipe-favori")
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        require("Le paquet est de retour, sans la carte sauvegardée") { self.element("swipe-restantes").exists }
        XCTAssertEqual(element("swipe-restantes").label, "10 missions à parcourir")
        XCTAssertFalse(element("swipe-card-\(Attendus.choix)").exists)
        verifierAucuneRequete()
    }

    // MARK: - ❤️

    func testCandidaterRecapitulatifPuisPremiereCandidatureUneSeuleFois() throws {
        ouvrirSwipe()
        carteEnTete(Attendus.premiere)

        // Première candidature du compte : récapitulatif, puis la feuille ; « Pas maintenant » n'envoie rien.
        tap("swipe-candidater")
        confirmerRecapitulatif()
        verifierPremiereCandidature()
        record("\(proofPrefix)-swipe-premiere-candidature")
        tap("swipe-premiere-annuler")
        require("La feuille est refermée sans envoi") { !self.element("swipe-premiere-candidature").exists }
        attendreRestantes(Attendus.total)
        XCTAssertFalse(element("swipe-toast").exists, "« Pas maintenant » : aucune candidature")
        carteEnTete(Attendus.premiere)

        // La feuille n'a pas été mémorisée : elle revient, puis « J'ai compris » envoie la candidature.
        tap("swipe-candidater")
        confirmerRecapitulatif()
        verifierPremiereCandidature()
        let compris = element("swipe-premiere-confirmer")
        scrollTo(compris, in: defilement("swipe-premiere-candidature"))
        compris.tap()
        let toast = element("swipe-toast")
        require("La candidature relue est annoncée", timeout: 30) {
            !self.element("swipe-premiere-candidature").exists && toast.exists
        }
        XCTAssertTrue(toast.label.contains("Candidature envoyée ✓"), toast.label)
        attendreRestantes(11)
        XCTAssertFalse(element("swipe-erreur").exists)
        XCTAssertTrue(element("swipe-documents").exists, "documents du profil fictif à valider : avis du serveur (`docs_a_completer`)")
        record("\(proofPrefix)-swipe-candidature-envoyee")

        // Deuxième ❤️ du compte : le récapitulatif, plus jamais la feuille.
        tap("swipe-passer")
        attendreRestantes(10)
        carteEnTete(Attendus.troisieme)
        tap("swipe-candidater")
        confirmerRecapitulatif()
        require("La seconde candidature part sans feuille", timeout: 30) {
            !self.element("candidature-recap").exists && self.element("swipe-restantes").label == "9 missions à parcourir"
        }
        XCTAssertFalse(element("swipe-premiere-candidature").exists, "feuille « première candidature » : une seule fois par compte")

        // Mes missions › Candidatures contient les deux missions.
        tabButton("tab-missions", label: "Mes missions").tap()
        tap("missions-tab-candidatures")
        require("Les candidatures du paquet sont dans Mes missions › Candidatures", timeout: 30) {
            self.element("missions-tab-candidatures").isSelected
                && self.element("mes-mission-\(Attendus.premiere)").exists && self.element("mes-mission-\(Attendus.troisieme)").exists
        }
        record("\(proofPrefix)-swipe-mes-missions")
        verifierAucuneRequete()
    }

    func testAnnulerDuToastRetireLaCandidatureSansRemettreLaCarte() throws {
        ouvrirSwipe()
        tap("swipe-candidater")
        confirmerRecapitulatif()
        let compris = element("swipe-premiere-confirmer")
        require("La feuille « première candidature » est présentée") { compris.exists }
        scrollTo(compris, in: defilement("swipe-premiere-candidature"))
        compris.tap()
        let annuler = element("swipe-toast-annuler")
        require("Le toast propose « Annuler »", timeout: 30) { self.visible(annuler) && annuler.isEnabled }
        XCTAssertEqual(annuler.label, "Annuler")
        attendreRestantes(11)

        annuler.tap()
        let toast = element("swipe-toast")
        require("Le retrait relu est annoncé", timeout: 30) { toast.exists && toast.label.contains("Candidature retirée") }
        XCTAssertFalse(element("swipe-toast-annuler").exists, "un seul retrait par candidature")
        XCTAssertTrue(element("swipe-toast-mission").exists, "accès au détail de la mission (D4)")
        XCTAssertEqual(element("swipe-restantes").label, "11 missions à parcourir", "D4 : la carte n'est pas remise dans le paquet")
        XCTAssertFalse(element("swipe-card-\(Attendus.premiere)").exists)
        carteEnTete(Attendus.choix)
        XCTAssertFalse(element("swipe-erreur").exists)
        record("\(proofPrefix)-swipe-candidature-retiree")

        tabButton("tab-missions", label: "Mes missions").tap()
        tap("missions-tab-candidatures")
        require("L'onglet Candidatures est affiché", timeout: 30) { self.element("missions-tab-candidatures").isSelected }
        requireAbsence("La candidature retirée n'est plus dans Mes missions") { self.element("mes-mission-\(Attendus.premiere)").exists }
        verifierAucuneRequete()
    }

    func testChoixDuContratDemandePuisRejoue() throws {
        ouvrirSwipe()
        tap("swipe-passer")
        attendreRestantes(11)
        carteEnTete(Attendus.choix)

        tap("swipe-candidater")
        confirmerRecapitulatif()
        let compris = element("swipe-premiere-confirmer")
        require("La feuille « première candidature » est présentée") { compris.exists }
        scrollTo(compris, in: defilement("swipe-premiere-candidature"))
        compris.tap()

        // Mission au contrat « Salarié ou libéral », profil démo mixte : le serveur demande le mode de contrat.
        let feuille = defilement("choix-contrat")
        let confirmer = element("choix-contrat-confirmer")
        require("Le choix du contrat est demandé", timeout: 30) { self.containerVisible(feuille) && confirmer.exists }
        XCTAssertTrue(element("choix-contrat-SALARIE").exists && element("choix-contrat-LIBERAL").exists)
        XCTAssertFalse(confirmer.isEnabled, "aucune option choisie : rien à confirmer")
        XCTAssertFalse(element("swipe-toast").exists, "aucune candidature sans contrat choisi")
        record("\(proofPrefix)-swipe-choix-contrat")
        let liberal = element("choix-contrat-LIBERAL")
        scrollTo(liberal, in: feuille)
        liberal.tap()
        require("L'option est sélectionnée") { liberal.isSelected && confirmer.isEnabled }
        scrollTo(confirmer, in: feuille)
        confirmer.tap()

        let toast = element("swipe-toast")
        require("Le ❤️ rejoué avec l'option est confirmé", timeout: 30) { !self.element("choix-contrat").exists && toast.exists }
        XCTAssertTrue(toast.label.contains("Candidature envoyée ✓"), toast.label)
        attendreRestantes(10)
        XCTAssertFalse(element("swipe-card-\(Attendus.choix)").exists)
        XCTAssertFalse(element("swipe-erreur").exists)

        tabButton("tab-missions", label: "Mes missions").tap()
        tap("missions-tab-candidatures")
        require("La candidature au contrat choisi est dans Mes missions › Candidatures", timeout: 30) {
            self.element("missions-tab-candidatures").isSelected && self.element("mes-mission-\(Attendus.choix)").exists
        }
        verifierAucuneRequete()
    }

    // MARK: - Paquet entier

    func testCartesSansScoreCarteRefuseePuisFinDePaquet() throws {
        ouvrirSwipe()
        // Une mission sauvegardée, re-proposée en fin de paquet.
        tap("swipe-sauvegarder")
        attendreRestantes(11)
        tap("swipe-passer")
        attendreRestantes(10)
        var restantes = 10
        for carte in Attendus.milieu {
            carteEnTete(carte)
            XCTAssertTrue(element("swipe-score-\(carte)").exists, "\(carte) : score servi")
            tap("swipe-passer")
            restantes -= 1
            attendreRestantes(restantes)
        }

        // Cartes sans score servi : ni pastille ni « Pourquoi ? », jamais « 0/100 ».
        carteEnTete(Attendus.sansScore)
        XCTAssertTrue(element("swipe-etablissement-\(Attendus.sansScore)").exists)
        XCTAssertEqual(elements(withPrefix: "swipe-score-").count, 0, "aucune pastille de score sans score servi")
        XCTAssertEqual(elements(withPrefix: "swipe-pourquoi-").count, 0)
        record("\(proofPrefix)-swipe-sans-score")
        tap("swipe-passer")
        attendreRestantes(1)
        carteEnTete(Attendus.deja)
        XCTAssertEqual(elements(withPrefix: "swipe-score-").count, 0)

        // Carte déjà swipée ailleurs : refus du serveur affiché (libellé, jamais le code technique), carte retirée.
        tap("swipe-passer")
        let erreur = element("swipe-erreur")
        let fin = defilement("swipe-fin-paquet")
        require("Le refus est affiché et le paquet est terminé", timeout: 30) { erreur.exists && self.containerVisible(fin) }
        XCTAssertTrue(erreur.label.contains("Vous avez déjà répondu à cette mission."), erreur.label)
        XCTAssertFalse(erreur.label.contains("mission_deja_swipee"), "jamais le code technique")
        XCTAssertFalse(element("swipe-deck").exists)
        XCTAssertEqual(element("swipe-fin-titre").label, "Vous avez tout vu pour aujourd'hui")

        // Fin de paquet : la mission sauvegardée est re-proposée, le rayon élargi ramène à la liste.
        // (`demo-favoris.json` en porte déjà une, `demo-mission-002` : deux missions ouvertes à venir.)
        let favori = element("swipe-favori-\(Attendus.premiere)")
        scrollTo(favori, in: fin)
        XCTAssertEqual(element("swipe-favoris-title").label, "Vos missions sauvegardées (2)")
        XCTAssertTrue(element("swipe-favori-demo-mission-002").exists, "favori de la fixture re-proposé lui aussi")
        record("\(proofPrefix)-swipe-fin-paquet")
        let secondaire = element("swipe-fin-secondaire")
        scrollTo(secondaire, in: fin)
        XCTAssertEqual(secondaire.label, "📍 Élargir le rayon (+20 km)")
        secondaire.tap()
        require("La liste d'Explorer est affichée, rayon élargi", timeout: 30) {
            self.containerVisible(self.element("missions-list")) && self.element("missions-rayon").exists
                && self.element("explorer-vue-liste").isSelected
        }
        XCTAssertEqual(element("missions-rayon").label, "dans un rayon de 70 km")
        verifierAucuneRequete()
    }

    // MARK: - Lien et détail

    func testLienVersLeSwipePuisDetailDUneCarte() throws {
        // Lien universel `/soignant/swipe-missions` : Explorer en vue Swipe, jamais un écran empilé ni un renvoi web.
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/swipe-missions"], environment: Attendus.annulation)
        connexionDemo()
        let quiz = defilement("swipe-quiz")
        require("Le lien ouvre Explorer en vue Swipe (quiz du premier contact)", timeout: 30) {
            self.containerVisible(quiz) && self.element("swipe-quiz-pool-urgence").exists
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T3b) : jamais un renvoi web")

        // Renvoi du quiz vers Pool urgence : écran natif depuis L4-T11 (`DemoPoolUrgenceTests`), empilé sur le Profil,
        // jamais un renvoi web (le test attendait le renvoi web d'avant la livraison de T11, run 45446351274) ; le quiz
        // ne revient pas.
        let pool = element("swipe-quiz-pool-urgence")
        scrollTo(pool, in: quiz)
        XCTAssertEqual(pool.label, "Ouvrir Pool urgence")
        pool.tap()
        let ecranPool = defilement("pool-screen")
        require("Le pool urgence natif est ouvert", timeout: 30) {
            self.containerVisible(ecranPool) && self.element("pool-toggle").exists
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T11) : jamais un renvoi web")
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        require("Le pool urgence est retiré, le Profil à sa racine") {
            !self.element("pool-screen").exists && self.containerVisible(self.element("profile-list"))
        }
        tabButton("tab-explorer", label: "Explorer").tap()
        require("Le paquet est affiché, sans quiz", timeout: 30) {
            !self.element("swipe-quiz").exists && self.element("swipe-restantes").exists
        }
        XCTAssertTrue(element("explorer-vue-swipe").isSelected)
        attendreRestantes(Attendus.total)
        carteEnTete(Attendus.premiere)

        // Détail de la carte : « Vérifier et postuler » ouvre le récapitulatif, jamais un envoi direct.
        toucherDetail(de: Attendus.premiere)
        let detail = defilement("swipe-detail-feuille")
        require("Le détail de la carte est présenté") { self.containerVisible(detail) && self.element("swipe-detail-titre").exists }
        XCTAssertEqual(element("swipe-detail-titre").label, "Démonstration · Médecine polyvalente 15")
        XCTAssertEqual(element("swipe-detail-score").label, "Match 94 sur 100")
        XCTAssertTrue(element("swipe-detail-condition-tarif").label.contains("29 €/h"), element("swipe-detail-condition-tarif").label)
        record("\(proofPrefix)-swipe-detail")
        let postuler = element("swipe-detail-postuler")
        scrollTo(postuler, in: detail)
        XCTAssertEqual(postuler.label, "Vérifier et postuler")
        postuler.tap()
        let annulerRecap = element("candidature-recap-cancel")
        require("Le récapitulatif remplace le détail", timeout: 30) {
            !self.element("swipe-detail-feuille").exists && annulerRecap.exists
        }
        scrollTo(annulerRecap, in: defilement("candidature-recap"))
        annulerRecap.tap()
        require("Le récapitulatif est refermé sans envoi") { !self.element("candidature-recap").exists }
        attendreRestantes(Attendus.total)
        XCTAssertFalse(element("swipe-toast").exists)

        // « Suivant » du détail : la carte est passée.
        toucherDetail(de: Attendus.premiere)
        let suivant = element("swipe-detail-suivant")
        require("Le détail est de nouveau présenté") { suivant.exists }
        scrollTo(suivant, in: defilement("swipe-detail-feuille"))
        suivant.tap()
        require("Le détail est refermé") { !self.element("swipe-detail-feuille").exists }
        attendreRestantes(11)
        carteEnTete(Attendus.choix)
        verifierAucuneRequete()
    }

    // MARK: - Étapes

    /// Connexion, Explorer, bascule sur Swipe, quiz remis à plus tard : paquet complet affiché.
    private func ouvrirSwipe(environment: [String: String] = Attendus.annulation) {
        launchDemo(environment: environment)
        connexionDemo()
        ouvrirExplorerEnListe()
        tap("explorer-vue-swipe")
        let quiz = defilement("swipe-quiz")
        let plusTard = element("swipe-quiz-plus-tard")
        require("Le quiz est proposé au premier contact avec le paquet", timeout: 30) { self.containerVisible(quiz) && plusTard.exists }
        scrollTo(plusTard, in: quiz)
        XCTAssertEqual(plusTard.label, "Plus tard")
        plusTard.tap()
        require("Le quiz est refermé et le paquet affiché", timeout: 30) {
            !self.element("swipe-quiz").exists && self.element("swipe-restantes").exists
        }
        attendreRestantes(Attendus.total)
        XCTAssertTrue(element("explorer-vue-swipe").isSelected)
        XCTAssertFalse(element("swipe-avis").exists, "« Plus tard » : aucune préférence envoyée, aucune confirmation")
    }

    /// Onglet Explorer : la liste du lot 1 et la commande « Swipe · Liste » (coupe-circuit lu), « Liste » sélectionnée.
    private func ouvrirExplorerEnListe() {
        tabButton("tab-explorer", label: "Explorer").tap()
        let swipe = element("explorer-vue-swipe")
        require("Explorer affiche la liste et la commande Swipe · Liste", timeout: 30) {
            self.containerVisible(self.element("missions-list")) && self.visible(swipe)
        }
        XCTAssertTrue(element("explorer-vue-liste").isSelected, "sans préférence : la liste")
        XCTAssertFalse(swipe.isSelected)
        XCTAssertEqual(swipe.label, "Swipe")
        XCTAssertEqual(element("explorer-vue-liste").label, "Liste")
    }

    /// « Voir le détail » de la carte du dessus `id`, cherché DANS cette carte : les cartes de fond exposent encore leur
    /// propre bouton à XCUITest (défaut d'accessibilité de `SwipeCardStack` relevé sur simulateur iOS 18.6, non corrigé),
    /// et la première correspondance globale de `swipe-detail` est celle d'une carte de fond, que l'on ne peut toucher.
    private func toucherDetail(de id: String, file: StaticString = #filePath, line: UInt = #line) {
        let bouton = element("swipe-card-\(id)").descendants(matching: .any).matching(identifier: "swipe-detail").firstMatch
        require("« Voir le détail » de la carte \(id) est atteignable", file: file, line: line) {
            self.visible(bouton) && bouton.isEnabled
        }
        bouton.tap()
    }

    private func attendreRestantes(_ nombre: Int, file: StaticString = #filePath, line: UInt = #line) {
        let attendu = nombre == 1 ? "1 mission à parcourir" : "\(nombre) missions à parcourir"
        let compteur = element("swipe-restantes")
        require("Le paquet annonce « \(attendu) »", timeout: 30, file: file, line: line) {
            compteur.exists && compteur.label == attendu && self.element("swipe-passer").isEnabled
        }
    }

    private func carteEnTete(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        require("La carte \(id) est en tête du paquet", file: file, line: line) {
            self.element("swipe-card-\(id)").exists && self.element("swipe-etablissement-\(id)").exists
        }
    }

    /// Récapitulatif exact du ❤️ (mêmes textes et identifiants que le détail de mission, lot 1) : planning listé, phrase
    /// d'engagement verbatim, puis « Envoyer ma candidature ».
    private func confirmerRecapitulatif() {
        let confirmer = element("candidature-recap-confirm")
        require("Le récapitulatif du planning est présenté", timeout: 30) { confirmer.exists && confirmer.isEnabled }
        XCTAssertEqual(element("candidature-recap-title").label, "Vérifiez votre engagement")
        let ligne = element("candidature-recap-planning-creneau-1")
        XCTAssertTrue(ligne.exists, "planning exact listé")
        XCTAssertTrue(ligne.label.contains("2026"), "jour avec l'année, comme le web : \(ligne.label)")
        let recap = defilement("candidature-recap")
        let phrase = element("candidature-recap-engagement")
        scrollTo(phrase, in: recap)
        XCTAssertEqual(phrase.label, Self.engagementCandidature, "phrase d'engagement verbatim du web (HARD STOP n°4)")
        XCTAssertEqual(confirmer.label, "Envoyer ma candidature")
        scrollTo(confirmer, in: recap)
        confirmer.tap()
    }

    /// Feuille « première candidature » : chaque texte est celui du web, mot pour mot (HARD STOP n°4).
    private func verifierPremiereCandidature() {
        let feuille = defilement("swipe-premiere-candidature")
        require("La feuille « première candidature » est présentée", timeout: 30) {
            self.containerVisible(feuille) && self.element("swipe-premiere-confirmer").exists
        }
        XCTAssertFalse(element("swipe-toast").exists, "rien n'est envoyé avant « J'ai compris »")
        XCTAssertEqual(element("swipe-premiere-titre").label, PremiereCandidature.titre)
        XCTAssertEqual(element("swipe-premiere-description").label, PremiereCandidature.description)
        XCTAssertEqual(element("swipe-premiere-acceptation").label, PremiereCandidature.acceptation)
        XCTAssertEqual(element("swipe-premiere-engagement-1").label, PremiereCandidature.retraitLibre)
        XCTAssertEqual(element("swipe-premiere-engagement-2").label, PremiereCandidature.annulationTardive)
        let confirmer = element("swipe-premiere-confirmer")
        scrollTo(confirmer, in: feuille)
        XCTAssertEqual(confirmer.label, PremiereCandidature.confirmer)
        let annuler = element("swipe-premiere-annuler")
        scrollTo(annuler, in: feuille)
        XCTAssertEqual(annuler.label, PremiereCandidature.pasMaintenant)
    }

    /// Conteneur de défilement : la `ScrollView` portant l'identifiant, sinon la première correspondance.
    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    /// Onglet Profil, puis sentinelle réseau : le swipe n'émet aucune requête en démonstration.
    private func verifierAucuneRequete() {
        tabButton("tab-profil", label: "Profil").tap()
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let sentinelle = element("network-sentinel")
        scrollTo(sentinelle, in: liste, downward: false)
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "la vue Swipe n'émet aucune requête en démonstration")
    }

    private func connexionDemo() {
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.containerVisible(scroll) }
        let email = element("login-email")
        focus(email, in: scroll)
        email.typeText(Self.demoEmail)
        let password = element("login-password")
        email.typeText("\n")
        if !hasKeyboardFocus(password) { focus(password, in: scroll) }
        require("Le mot de passe a le focus clavier") { self.hasKeyboardFocus(password) }
        password.typeText(Self.demoPassword)
        let submit = element("login-submit")
        require("Le bouton de connexion est activé") { submit.isEnabled }
        if app.keyboards.firstMatch.exists, !visible(submit) { scrollTo(submit, in: scroll) }
        toucherSeConnecter(submit, "La session démo est prête") { self.tabBarExists }
    }
}
