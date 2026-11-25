import XCTest
@testable import JoleneCore

/// Décodage des réponses de « Mes évaluations » et de « Mon score » (L4-T9, `LOT4_PLAN.md` §2.4) : valeurs serveur
/// reprises telles quelles (`note_moyenne` jamais recalculée), réponse illisible jamais lue comme un état vide, clé
/// `events` des événements (correction 16).
final class EvaluationsScoreDecodingTests: XCTestCase {
    private func json(_ texte: String) throws -> ValeurJSON {
        try JSONDecoder().decode(ValeurJSON.self, from: Data(texte.utf8))
    }

    // MARK: - Évaluations

    func testPageNoteMoyenneEtStatistiquesDuServeurJamaisRecalculees() throws {
        // `note_moyenne` 3.9 et `note_moyenne_globale` 4.9 ne correspondent volontairement à aucun calcul sur les
        // critères (4, 4, 5, 4 → 4,25) : seule la valeur servie doit ressortir.
        let page = try XCTUnwrap(EvaluationsDecodage.page(try json("""
        {"success":true,"total":41,"limit":20,"offset":20,
         "notations":[{"id":"n-1","mission_id":"m-1","mission_intitule":"Remplacement IDE","mission_fin_le":"2026-10-26T18:00:00+00:00",
                       "etablissement_id":"e-1","etablissement_nom":"Clinique des Tests","critere_1":4,"critere_2":4,"critere_3":5,
                       "critere_4":4,"note_moyenne":3.9,"commentaire":"Très bien.","signale":false,"cree_le":"2026-10-28T09:30:00+00:00"},
                      {"id":"n-2","note_moyenne":"5","critere_1":"4","signale":"non","commentaire":null}],
         "stats":{"note_moyenne_globale":4.9,"total_evaluations":41,"pct_5_etoiles":33.3},
         "evolution_6m":[{"mois":"2026-09","note_moyenne":4.5,"nb":2},{"note_moyenne":4},{"mois":"2026-10","note_moyenne":null,"nb":1}],
         "etabs_disponibles":[{"id":"e-1","nom":"Clinique des Tests"},{"id":"","nom":"x"},{"nom":"sans id"}]}
        """)))
        XCTAssertEqual(page.total, 41)
        XCTAssertEqual(page.notations.count, 2)
        XCTAssertEqual(page.notations[0], NotationRecue(id: "n-1", missionId: "m-1", missionIntitule: "Remplacement IDE",
                                                         missionFinLe: "2026-10-26T18:00:00+00:00", etablissementId: "e-1",
                                                         etablissementNom: "Clinique des Tests", criteres: [4, 4, 5, 4],
                                                         noteMoyenne: 3.9, commentaire: "Très bien.", signale: false,
                                                         creeLe: "2026-10-28T09:30:00+00:00"))
        XCTAssertEqual(page.notations[1], NotationRecue(id: "n-2"), "valeurs d'un autre type ignorées seules : jamais une note fabriquée")
        XCTAssertNil(page.notations[1].signale, "`signale` illisible : signalement non proposé")
        XCTAssertEqual(page.stats, StatsEvaluations(noteMoyenneGlobale: 4.9, totalEvaluations: 41, pct5Etoiles: 33.3))
        XCTAssertEqual(page.evolution, [PointEvolutionNotes(mois: "2026-09", noteMoyenne: 4.5, nb: 2),
                                        PointEvolutionNotes(mois: "2026-10", noteMoyenne: nil, nb: 1)])
        XCTAssertEqual(page.etablissements, [EtablissementEvaluateur(id: "e-1", nom: "Clinique des Tests")])
    }

    func testPageIllisibleJamaisUnePageVide() throws {
        for (reponse, raison) in [
            (#"{"success":false,"error_code":"NON_AUTHENTIFIE"}"#, "refus"),
            (#"{"total":0,"notations":[]}"#, "sans success"),
            (#"{"success":"true","total":0,"notations":[]}"#, "success non booléen"),
            (#"{"success":true,"notations":[]}"#, "sans total"),
            (#"{"success":true,"total":1.5,"notations":[]}"#, "total non entier"),
            (#"{"success":true,"total":0}"#, "sans notations"),
            (#"{"success":true,"total":1,"notations":[{"note_moyenne":5}]}"#, "notation sans id"),
            (#"[]"#, "tableau"),
        ] {
            XCTAssertNil(EvaluationsDecodage.page(try json(reponse)), raison)
        }
        let vide = try XCTUnwrap(EvaluationsDecodage.page(try json(#"{"success":true,"total":0,"notations":[]}"#)))
        XCTAssertEqual(vide, PageEvaluations(total: 0, notations: [], stats: nil, evolution: [], etablissements: []),
                       "page vide servie : statistiques absentes, jamais fabriquées")
    }

    func testListeDesNotationsDeMonScoreSansSignale() throws {
        let liste = try XCTUnwrap(EvaluationsDecodage.liste(try json("""
        [{"id":"n-1","mission_id":"m-1","mission_intitule":"Renfort","mission_fin_le":"2026-09-21T00:00:00Z","critere_1":4,
          "critere_2":5,"critere_3":4,"critere_4":5,"note_moyenne":4.5,"commentaire":null,"cree_le":"2026-09-23T00:00:00Z"}]
        """)))
        XCTAssertEqual(liste.map(\.id), ["n-1"])
        XCTAssertEqual(liste[0].noteMoyenne, 4.5)
        XCTAssertNil(liste[0].signale, "`fn_lister_notations_recues` ne sert pas `signale`")
        XCTAssertNil(liste[0].etablissementNom, "établissement jamais servi par cette RPC")
        XCTAssertEqual(EvaluationsDecodage.liste(try json("[]")), [])
        XCTAssertNil(EvaluationsDecodage.liste(try json(#"{"error":"Non authentifié"}"#)), "objet : jamais une liste vide")
        XCTAssertNil(EvaluationsDecodage.liste(try json(#"[{"note_moyenne":4}]"#)))
    }

    // MARK: - Score

    func testBreakdownDuDernierCalculEtPoidsInitialDuServeur() throws {
        let fichier = try DemoFixtures.loadScore()
        let breakdown = try XCTUnwrap(ScoreDecodage.breakdown(calcul: fichier.breakdown, profil: fichier.soignant))
        XCTAssertTrue(breakdown.calcule)
        XCTAssertEqual(breakdown.score, 72.6)
        XCTAssertEqual(breakdown.niveau, "OR")
        XCTAssertEqual(breakdown.enPeriodeProbatoire, false)
        XCTAssertEqual(breakdown.totalMissionsTerminees, 12)
        XCTAssertEqual(breakdown.composantes.map(\.cle), CleComposanteScore.allCases, "ordre de COMPOSANTES_DEF")
        XCTAssertEqual(breakdown.composantes[0], ComposanteScore(cle: .notationEtabSoignant, pct: 88.8, poids: 38.9))
        XCTAssertEqual(breakdown.composantes[3], ComposanteScore(cle: .reactivite, pct: nil, poids: nil, poidsInitial: 10),
                       "composante inactive : poids initial de composantes_inactives_json")
        XCTAssertEqual(breakdown.absenceSansPrevenirMalus, -5)
        XCTAssertEqual(breakdown.litigesMalus, 0)
        XCTAssertEqual(breakdown.bonusSuperActif, 0)
    }

    func testBreakdownSansCalculNeFabriqueNiScoreNiNiveau() throws {
        // Le web remplace alors un score absent par 50 et un niveau absent par Bronze (PageScoreSoignant.tsx l.75-76).
        let sansRien = try XCTUnwrap(ScoreDecodage.breakdown(calcul: try json("{}"), profil: try json("{}")))
        XCTAssertEqual(sansRien, BreakdownScore(score: nil, niveau: nil), "ni 50, ni Bronze, ni période probatoire supposée")
        XCTAssertFalse(sansRien.calcule)
        XCTAssertTrue(sansRien.composantes.isEmpty)

        let profil = try json(#"{"total_missions_terminees":2,"score_fiabilite":50.00,"niveau":"BRONZE","en_periode_probatoire":true}"#)
        let duProfil = try XCTUnwrap(ScoreDecodage.breakdown(calcul: try json("{}"), profil: profil))
        XCTAssertEqual(duProfil, BreakdownScore(score: 50, niveau: "BRONZE", enPeriodeProbatoire: true, totalMissionsTerminees: 2),
                       "valeurs du profil servies par le serveur")
        let sansProfil = try XCTUnwrap(ScoreDecodage.breakdown(calcul: try json("{}"), profil: nil))
        XCTAssertNil(sansProfil.totalMissionsTerminees)
        XCTAssertNil(ScoreDecodage.breakdown(calcul: try json("[]"), profil: profil), "réponse qui n'est pas un objet")
        XCTAssertNil(ScoreDecodage.breakdown(calcul: try json("{}"), profil: try json("[]")), "profil qui n'est pas un objet")
    }

    func testEvolutionTableauOuIllisible() throws {
        let points = try XCTUnwrap(ScoreDecodage.evolution(try DemoFixtures.loadScore().evolution))
        XCTAssertEqual(points.map(\.mois), ["2026-06", "2026-07", "2026-08", "2026-09", "2026-10", "2026-11"])
        XCTAssertEqual(points.last, PointEvolutionScore(mois: "2026-11", score: 72.6, niveau: "OR"))
        XCTAssertEqual(ScoreDecodage.evolution(try json("[]")), [])
        XCTAssertNil(ScoreDecodage.evolution(try json(#"{"error":"Non authentifié"}"#)), "objet au lieu d'un tableau")
        XCTAssertNil(ScoreDecodage.evolution(try json(#"[{"score":70}]"#)), "point sans mois")
    }

    func testEvenementsSousLaCleEventsEtContestableCalculeParLeServeur() throws {
        let evenements = try XCTUnwrap(ScoreDecodage.evenements(try DemoFixtures.loadScore().evenements))
        XCTAssertEqual(evenements.map(\.id), ["demo-evenement-001", "demo-evenement-002", "demo-evenement-003"])
        XCTAssertEqual(evenements.map(\.contestable), [true, false, false], "un seul contestable dans la fixture")
        XCTAssertEqual(evenements[0], EvenementScore(id: "demo-evenement-001", typeEvenement: "ANNULATION_12_24H", points: -5,
                                                     motif: "Annulation entre 12 h et 24 h avant le début de la mission",
                                                     contestable: true, creeLe: "2026-10-23T00:00:00.000Z",
                                                     missionId: "demo-mission-notee-005"))
        XCTAssertEqual(evenements[1].pointsAffiches, -4, "points corrigés par l'admin, servis par le serveur")
        XCTAssertEqual(evenements[1].decisionAdmin, "REDUIRE")
        XCTAssertEqual(evenements[2].pointsAffiches, 5)
    }

    func testEvenementsSousUneAutreCleOuDUnAutreTypeRefusesCommeContrat() throws {
        let evenement = #"{"id":"e-1","type_evenement":"NO_SHOW","points":-10,"points_corriges":null,"motif":"m","contestable":true,"decision_admin":null,"cree_le":"2026-10-01T00:00:00Z","mission_id":null}"#
        XCTAssertEqual(ScoreDecodage.evenements(try json(#"{"success":true,"type":"SOIGNANT","events":[\#(evenement)]}"#))?.count, 1)
        // Correction 16 : la clé que lit le web n'existe pas dans la réponse du serveur.
        XCTAssertNil(ScoreDecodage.evenements(try json(#"{"success":true,"type":"SOIGNANT","evenements":[\#(evenement)]}"#)),
                     "une réponse `evenements` n'est jamais lue comme « aucun événement »")
        XCTAssertNil(ScoreDecodage.evenements(try json("[\(evenement)]")), "tableau nu")
        XCTAssertNil(ScoreDecodage.evenements(try json(#"{"success":true,"type":"ETAB","events":[]}"#)), "réponse d'un établissement")
        XCTAssertNil(ScoreDecodage.evenements(try json(#"{"success":false,"error":"Profil non identifié"}"#)))
        XCTAssertNil(ScoreDecodage.evenements(try json(#"{"success":true,"type":"SOIGNANT","events":[{"type_evenement":"NO_SHOW"}]}"#)),
                     "événement sans id")
        let sansAccord = try XCTUnwrap(ScoreDecodage.evenements(try json(
            #"{"success":true,"type":"SOIGNANT","events":[{"id":"e-2","type_evenement":"AUTRE","contestable":"true"}]}"#)))
        XCTAssertEqual(sansAccord.map(\.contestable), [false], "`contestable` non booléen : aucune contestation proposée")
        XCTAssertEqual(ScoreDecodage.evenements(try json(#"{"success":true,"type":"SOIGNANT","events":[]}"#)), [])
    }

    func testMotifsDeContestationSontCeuxDuServeur() {
        XCTAssertEqual(MotifContestationScore.allCases.map(\.rawValue),
                       ["URGENCE_MEDICALE", "DEUIL", "FORCE_MAJEURE", "ERREUR_JOLENE", "CONTEXTE_PARTICULIER", "AUTRE"])
        XCTAssertEqual(PeriodeEvaluations.allCases.map(\.rawValue), ["TOUT", "3M", "6M", "12M"])
        XCTAssertEqual(EvaluationsDecodage.parPage, 20)
    }
}
