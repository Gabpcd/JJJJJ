import XCTest
@testable import JoleneCore

/// Marqueurs locaux, réglages et quiz de la vue Swipe (lot 4, T3b ; `LOT4_PLAN.md` §2.6, décisions D4, D6 et D26) :
/// trois drapeaux d'interface par compte, purgés à la suppression du compte ; vue par défaut ; durée du toast
/// d'annulation (5 s, surcharge réservée à la démonstration en DEBUG) ; quiz à quatre questions, sans la question
/// « missions urgentes » du web, dont les réponses dérivent les préférences du scoring et les critères d'Explorer.
final class SwipeMarqueursTests: XCTestCase {
    // MARK: - Marqueurs

    func testMarqueursAbsentsPuisPosesParCompte() {
        let stockage = MemoireStockageAppareil()
        let marqueurs = SwipeMarqueurs(stockage: stockage, userId: "u-1")
        XCTAssertFalse(marqueurs.quizVu)
        XCTAssertFalse(marqueurs.premiereCandidatureVue)
        XCTAssertEqual(marqueurs.vue, .liste, "sans préférence : la liste du lot 1 (écart assumé avec le web, qui ouvre sur Swipe)")
        XCTAssertEqual(SwipeMarqueurs.vueParDefaut, .liste)

        marqueurs.marquerQuizVu()
        marqueurs.memoriser(.swipe)
        XCTAssertTrue(marqueurs.quizVu)
        XCTAssertFalse(marqueurs.premiereCandidatureVue, "chaque marqueur a sa clé")
        XCTAssertEqual(marqueurs.vue, .swipe)
        marqueurs.memoriser(.liste)
        XCTAssertEqual(marqueurs.vue, .liste)

        let autre = SwipeMarqueurs(stockage: stockage, userId: "u-2")
        XCTAssertFalse(autre.quizVu, "un autre compte sur le même appareil repart sans marqueur")
        XCTAssertEqual(autre.vue, .liste)
        stockage.ecrire(SwipeMarqueurs.cleVue(userId: "u-2"), "carte")
        XCTAssertEqual(autre.vue, .liste, "valeur inconnue (vue Carte du web) : vue par défaut")
    }

    func testClesParCompteRetireesALaSuppressionDuCompte() throws {
        let userId = "0b6f2d3e-1c4a-4b5d-9e8f-7a6b5c4d3e2f"
        XCTAssertEqual(SwipeMarqueurs.cles(userId: userId), [
            "jolene.swipe.quiz.\(userId)", "jolene.swipe.premiereCandidature.\(userId)", "jolene.explorer.vue.\(userId)",
        ])
        let nom = "jolene.tests.swipe.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: nom))
        defer { defaults.removePersistentDomain(forName: nom) }
        for cle in SwipeMarqueurs.cles(userId: userId) + SwipeMarqueurs.cles(userId: "autre-compte") {
            defaults.set("1", forKey: cle)
        }
        let retirees = CompteSuppression.purgerPreferencesLocales(userId: userId, defaults: defaults)
        XCTAssertEqual(Set(retirees), Set(SwipeMarqueurs.cles(userId: userId)), "l'identifiant est un segment entier de chaque clé")
        for cle in SwipeMarqueurs.cles(userId: "autre-compte") {
            XCTAssertEqual(defaults.string(forKey: cle), "1", "les marqueurs d'un autre compte restent")
        }
    }

    // MARK: - Réglages

    func testDureeDuToastCinqSecondesSaufSurchargeDemoEnDebug() {
        let variable = ReglagesSwipe.variableDureeAnnulation
        XCTAssertEqual(ReglagesSwipe.dureeAnnulation, 5, "décision D4 : toast de 5 s")
        XCTAssertEqual(ReglagesSwipe.dureeAnnulation(demo: true, debug: true, environnement: [:]), 5)
        XCTAssertEqual(ReglagesSwipe.dureeAnnulation(demo: true, debug: true, environnement: [variable: "60"]), 60)
        XCTAssertEqual(ReglagesSwipe.dureeAnnulation(demo: false, debug: true, environnement: [variable: "60"]), 5,
                       "jamais hors démonstration")
        XCTAssertEqual(ReglagesSwipe.dureeAnnulation(demo: true, debug: false, environnement: [variable: "60"]), 5,
                       "jamais dans un build de livraison")
        for invalide in ["0", "-3", "abc", "", "1.5", "601"] {
            XCTAssertEqual(ReglagesSwipe.dureeAnnulation(demo: true, debug: true, environnement: [variable: invalide]), 5, invalide)
        }
        XCTAssertEqual(ReglagesSwipe.dureeAnnulation(demo: true, debug: true, environnement: [variable: "600"]), 600)
        let reglages = ReglagesSwipe(stockage: MemoireStockageAppareil())
        XCTAssertEqual(reglages.dureeAnnulation, 5)
        reglages.marqueurs(userId: "u-1").marquerQuizVu()
        XCTAssertTrue(reglages.marqueurs(userId: "u-1").quizVu, "même stockage pour tous les marqueurs du lancement")
    }

    // MARK: - Quiz

    func testQuizQuatreQuestionsSansLaQuestionUrgence() {
        XCTAssertEqual(QuizSwipe.horaires.map(\.titre), ["☀️ De jour", "🌙 De nuit", "Les deux"])
        XCTAssertEqual(QuizSwipe.horaires.map(\.valeur), [.jour, .nuit, .tous])
        XCTAssertEqual(QuizSwipe.rythmes.map(\.titre), ["Semaine", "Week-end", "Les deux"])
        XCTAssertEqual(QuizSwipe.rythmes.map(\.valeur), [.semaine, .weekend, .tous])
        XCTAssertEqual(QuizSwipe.rayons.map(\.titre), ["5 km", "10 km", "20 km", "50 km"])
        XCTAssertEqual(QuizSwipe.rayons.map(\.valeur), [5, 10, 20, 50])
        XCTAssertEqual(QuizSwipe.taux.map(\.titre), ["Peu importe", "≥ 25 €/h", "≥ 30 €/h", "≥ 35 €/h"])
        XCTAssertEqual(QuizSwipe.taux.map(\.valeur), [0, 25, 30, 35])
        XCTAssertEqual(QuizSwipe.titre, "4 questions pour un deck qui vous ressemble", "la cinquième question du web n'est pas portée (D26)")
        for identifiants in [QuizSwipe.horaires.map(\.identifiant), QuizSwipe.rythmes.map(\.identifiant),
                             QuizSwipe.rayons.map(\.identifiant), QuizSwipe.taux.map(\.identifiant)] {
            XCTAssertEqual(Set(identifiants).count, identifiants.count, "identifiants d'option uniques par question")
        }
        // Aucun texte du quiz ne propose d'activer la disponibilité urgente : seul un renvoi neutre vers Pool urgence.
        let textes = [QuizSwipe.titre, QuizSwipe.description, QuizSwipe.questionHoraire, QuizSwipe.questionRythme,
                      QuizSwipe.questionRayon, QuizSwipe.questionTaux, QuizSwipe.valider, QuizSwipe.plusTard, QuizSwipe.confirmation]
            + QuizSwipe.horaires.map(\.titre) + QuizSwipe.rythmes.map(\.titre) + QuizSwipe.rayons.map(\.titre) + QuizSwipe.taux.map(\.titre)
        for texte in textes {
            XCTAssertFalse(texte.lowercased().contains("urgen"), texte)
        }
        XCTAssertEqual(QuizSwipe.poolUrgenceAction, "Ouvrir Pool urgence")
        XCTAssertFalse(QuizSwipe.poolUrgenceTexte.contains("mieux payées"), "aucune promesse reprise de la question du web")
    }

    func testReponsesParDefautDuWebEtPreferencesDansLesBornes() {
        let defaut = ReponsesQuizSwipe()
        XCTAssertEqual(defaut, ReponsesQuizSwipe(horaire: .tous, rythme: .tous, rayonKm: 20, tauxMin: 0))
        XCTAssertEqual(defaut.preferences, PreferencesMatching(nuit: 0.5, jour: 0.5, weekend: 0.5, semaine: 0.5))
        for horaire in PreferencesMatching.Horaire.allCases {
            for rythme in PreferencesMatching.Rythme.allCases {
                XCTAssertTrue(ReponsesQuizSwipe(horaire: horaire, rythme: rythme).preferences.dansLesBornes, "\(horaire) \(rythme)")
            }
        }
    }

    func testReponsesAppliqueesAuxCriteresDExplorerCommeLeWeb() {
        let depart = ExplorerFiltres(ville: "Lyon", rayonKm: 50, tauxMin: 0, profession: "IDE", urgentesOnly: true,
                                     typeContrat: .liberal, horaire: .tous, etablissementId: "e-1")
        let nuit = ReponsesQuizSwipe(horaire: .nuit, rythme: .weekend, rayonKm: 10, tauxMin: 30).appliquees(a: depart)
        XCTAssertEqual(nuit.rayonKm, 10)
        XCTAssertEqual(nuit.tauxMin, 30)
        XCTAssertEqual(nuit.horaire, .nuit, "une seule dimension d'horaire : jour ou nuit l'emporte sur le week-end")
        XCTAssertEqual(ReponsesQuizSwipe(horaire: .jour, rythme: .tous).appliquees(a: depart).horaire, .jour)
        XCTAssertEqual(ReponsesQuizSwipe(horaire: .tous, rythme: .weekend).appliquees(a: depart).horaire, .weekend)
        XCTAssertEqual(ReponsesQuizSwipe(horaire: .tous, rythme: .semaine).appliquees(a: depart).horaire, .tous,
                       "« Semaine » n'a pas de filtre : l'horaire reste celui d'Explorer")
        var dejaNuit = depart
        dejaNuit.horaire = .nuit
        XCTAssertEqual(ReponsesQuizSwipe().appliquees(a: dejaNuit).horaire, .nuit, "« Les deux » ne retire pas un filtre posé")
        // Les autres critères d'Explorer ne sont pas touchés par le quiz.
        XCTAssertEqual(nuit.ville, "Lyon")
        XCTAssertEqual(nuit.profession, "IDE")
        XCTAssertEqual(nuit.typeContrat, .liberal)
        XCTAssertEqual(nuit.etablissementId, "e-1")
        XCTAssertTrue(nuit.urgentesOnly, "le quiz natif ne touche jamais aux missions urgentes")
        XCTAssertEqual(ReponsesQuizSwipe().appliquees(a: depart).rayonKm, 20, "rayon par défaut du quiz, comme le web")
    }

    func testVuesDExplorer() {
        XCTAssertEqual(VueExplorer.allCases.map(\.rawValue), ["swipe", "liste"], "identifiants `explorer-vue-swipe` / `explorer-vue-liste`")
        XCTAssertEqual(SwipeTextes.vueSwipe, "Swipe")
        XCTAssertEqual(SwipeTextes.vueListe, "Liste")
    }
}
