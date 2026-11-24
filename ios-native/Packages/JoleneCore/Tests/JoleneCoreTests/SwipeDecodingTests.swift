import XCTest
@testable import JoleneCore

/// Décodage tolérant du paquet de swipe (lot 4, T3a) : clés de `fn_obtenir_missions_swipe` (`supabase/schema/public.sql`),
/// `score: null` jamais remplacé par 0, breakdown réduit aux nombres, ligne illisible écartée seule, `auth_required`
/// reconnu ; table `SwipeRefus` et amorçage du quiz.
final class SwipeDecodingTests: XCTestCase {
    private func paquet(_ json: String) throws -> PaquetSwipe {
        try JSONDecoder().decode(PaquetSwipe.self, from: Data(json.utf8))
    }

    private let ligneComplete = """
    {"mission_id":"m-1","intitule":"Nuit IDE","profession_requise":"IDE","etablissement_id":"e-1",
     "etablissement_nom":"Clinique A","etablissement_ville":"Lyon","etablissement_code_postal":"69003",
     "etablissement_logo_url":null,"etablissement_score":4.5,"taux_horaire_base":28.5,"duree_heures":12,
     "debut_le":"2026-12-01T19:00:00+00:00","fin_le":"2026-12-02T07:00:00+00:00","est_urgente":true,"service":"Réa",
     "type_contrat_applique":null,"type_contrat_recherche":"TOUS","nb_creneaux":1,"total_brut":342,"net_a_payer":null,
     "net_estime":290.5,"montant_ifm":0,"montant_icp":0,"montant_majoration_nuit":12.5,"montant_majoration_dimanche":0,
     "montant_majoration_ferie":0,"score":null,"breakdown":{"distance":20,"error":"x","tarif":true,"urgence":10},
     "paiement_rapide":false,"distance_km":3.2}
    """

    func testLigneCompleteDecodeeTelleQuelleScoreNullConserve() throws {
        let lu = try paquet(#"{"missions":[\#(ligneComplete)]}"#)
        XCTAssertEqual(lu.lignesEcartees, 0)
        XCTAssertNil(lu.error)
        let ligne = try XCTUnwrap(lu.missions.first)
        XCTAssertNil(ligne.score, "score inconnu : jamais « 0/100 » fabriqué")
        XCTAssertEqual(ligne.breakdown, ["distance": 20, "urgence": 10], "seuls les nombres du breakdown comptent")
        XCTAssertEqual(ligne.distanceKm, 3.2)
        XCTAssertEqual(ligne.netEstime, 290.5)
        XCTAssertEqual(ligne.montants.majorationNuit, 12.5)
        XCTAssertTrue(ligne.estUrgente)
        XCTAssertEqual(ligne.record.statut, "OUVERTE", "le paquet ne sert que des missions ouvertes")
        XCTAssertEqual(ligne.etablissement.nom, "Clinique A")

        let creneau = MissionSlot(id: "s-1", missionId: "m-1", debut: "2026-12-01T19:00:00+00:00", fin: "2026-12-02T07:00:00+00:00",
                                  estPause: false, typeCreneau: "PREVISIONNEL")
        let carte = CarteSwipe(ligne: ligne, creneaux: [creneau])
        XCTAssertEqual(carte.id, "m-1")
        XCTAssertTrue(carte.mission.planningExact, "un créneau pour nb_creneaux = 1 : planning exact")
        XCTAssertEqual(carte.mission.distanceKm, 3.2, "distance servie par le payload, jamais recalculée")
        XCTAssertEqual(carte.mission.etablissement?.adresseVille, "Lyon")
        XCTAssertEqual(carte.raisons, "proche de chez toi · mission urgente", "points décroissants (RaisonsScore, golden T2)")
    }

    func testScoreEntierEtBreakdownVideOuAbsent() throws {
        let lu = try paquet("""
        {"missions":[
          {"mission_id":"m-1","intitule":"A","etablissement_id":"e","debut_le":"d","fin_le":"f","score":82,"breakdown":{}},
          {"mission_id":"m-2","intitule":"B","etablissement_id":"e","debut_le":"d","fin_le":"f","score":"82","breakdown":null},
          {"mission_id":"m-3","intitule":"C","etablissement_id":"e","debut_le":"d","fin_le":"f","score":82.5,"paiement_rapide":"true"}
        ]}
        """)
        XCTAssertEqual(lu.missions.map(\.score), [82, nil, nil], "texte ou fraction : ignorés seuls")
        XCTAssertEqual(lu.missions.map(\.breakdown), [[:], [:], [:]])
        XCTAssertEqual(lu.missions.map(\.paiementRapide), [false, false, false], "badge seulement sur un booléen vrai")
        XCTAssertEqual(CarteSwipe(ligne: lu.missions[0], creneaux: []).raisons, "")
    }

    /// Breakdown réel de `fn_calculer_score_matching` (`public.sql`, `v_breakdown` v3 et retours anticipés) : `null`
    /// (`distance_km`, `taux_median`) et textes (`error`, `filtre_dur_ko`) ne font jamais échouer le paquet et sont
    /// ignorés par « Pourquoi N ? » (revue B8 de #1161, m1).
    func testBreakdownReelAvecNullEtTexteToleréEtRaisonsParLeJsonBrut() throws {
        let lu = try paquet("""
        {"missions":[
          {"mission_id":"m-1","intitule":"A","etablissement_id":"e","debut_le":"d","fin_le":"f","score":74,
           "breakdown":{"tarif":18,"distance":22,"horaire":10,"etablissement":8,"urgence":0,"soignant_fiabilite":9,
                        "fraicheur":0,"connaissance_etab":0,"service":0,"paiement_rapide":4,"boost":0,
                        "distance_km":null,"taux_median":null}},
          {"mission_id":"m-2","intitule":"B","etablissement_id":"e","debut_le":"d","fin_le":"f","score":0,
           "breakdown":{"error":"soignant_introuvable"}},
          {"mission_id":"m-3","intitule":"C","etablissement_id":"e","debut_le":"d","fin_le":"f","score":0,
           "breakdown":{"filtre_dur_ko":"distance_excessive","distance_km":62.3}}
        ]}
        """)
        XCTAssertEqual(lu.missions.map(\.missionId), ["m-1", "m-2", "m-3"], "aucune ligne écartée pour un breakdown réel")
        let cartes = lu.missions.map { CarteSwipe(ligne: $0, creneaux: []) }
        XCTAssertEqual(cartes[0].raisons, "paiement rapide ⚡ · proche de chez toi", "épinglée d'abord, puis points décroissants")
        XCTAssertEqual(cartes[0].raisons, RaisonsScore.raisons(json: cartes[0].breakdownBrut), "source unique : le JSON brut")
        XCTAssertNil(cartes[0].breakdown["distance_km"], "un null n'est jamais un nombre")
        XCTAssertEqual(cartes[1].raisons, "", "texte seul : aucune raison")
        XCTAssertEqual(cartes[2].raisons, "", "clé numérique sans libellé : aucune raison")
        XCTAssertEqual(cartes[0].score, 74)
        XCTAssertEqual(cartes[1].score, 0, "0 servi par le serveur : affiché tel quel")
    }

    /// Filtre du paquet sur la distance servie (`distance_km` arrondi par le serveur), comme le web (revue B8 de #1161, m2).
    func testFiltreDuPaquetLitLaDistanceDuServeur() throws {
        let lu = try paquet("""
        {"missions":[{"mission_id":"m-1","intitule":"A","etablissement_id":"e","debut_le":"2026-12-01T19:00:00+00:00",
          "fin_le":"2026-12-02T07:00:00+00:00","nb_creneaux":1,"distance_km":20.1}]}
        """)
        var carte = CarteSwipe(ligne: try XCTUnwrap(lu.missions.first), creneaux: [])
        carte.mission.distanceKm = 19.9 // une distance recalculée ailleurs ne change pas le filtre
        XCTAssertEqual(carte.missionPaquet.distanceKm, 20.1)
        let filtre = FiltrePaquetSwipe(rayonKm: 20)
        XCTAssertTrue(FiltrePaquetSwipe.filtrer([carte], filtre: filtre, professionParcours: nil, mission: \.missionPaquet).isEmpty,
                      "20,1 km servis > rayon de 20 km : écartée")
    }

    func testLigneSansCleRequiseEcarteeSeule() throws {
        let lu = try paquet("""
        {"missions":[
          {"intitule":"Sans id","etablissement_id":"e","debut_le":"d","fin_le":"f"},
          {"mission_id":"m-2","intitule":"Lisible","etablissement_id":"e","debut_le":"d","fin_le":"f"},
          {"mission_id":"m-3","intitule":"Sans établissement","debut_le":"d","fin_le":"f"},
          42
        ]}
        """)
        XCTAssertEqual(lu.missions.map(\.missionId), ["m-2"])
        XCTAssertEqual(lu.lignesEcartees, 3)
    }

    func testAuthRequiredReconnu() throws {
        let lu = try paquet(#"{"missions":[],"error":"auth_required"}"#)
        XCTAssertTrue(lu.nonAuthentifie)
        XCTAssertTrue(lu.missions.isEmpty)
        XCTAssertFalse(try paquet(#"{"missions":[]}"#).nonAuthentifie)
    }

    func testFixtureDemoDouzeCartesDontDeuxSansScore() throws {
        let fichier = try DemoFixtures.loadSwipe()
        XCTAssertEqual(fichier.fixedNow, "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(fichier.paquet.missions.count, 12)
        XCTAssertEqual(fichier.paquet.lignesEcartees, 0)
        XCTAssertEqual(fichier.paquet.missions.filter { $0.score == nil }.map(\.missionId), ["demo-mission-019", "demo-swipe-deja"])
        let epinglee = try XCTUnwrap(fichier.paquet.missions.first { $0.missionId == "demo-mission-018" })
        XCTAssertTrue(epinglee.paiementRapide)
        XCTAssertEqual(CarteSwipe(ligne: epinglee, creneaux: []).raisons, "tu connais cet établissement · paiement rapide ⚡")
        // T3b : dix missions de `demo-missions.json` et les deux missions de recette du paquet, jamais listées par Explorer.
        let explorer = Set(try DemoFixtures.loadMissions().missions.map(\.record.id))
        let recette = fichier.missionsRecette.map(\.record.id)
        XCTAssertEqual(recette, ["demo-swipe-choix", "demo-swipe-deja"])
        XCTAssertTrue(explorer.isDisjoint(with: recette), "une mission de recette n'entre pas dans demo-missions.json")
        XCTAssertEqual(fichier.paquet.missions.filter { explorer.contains($0.missionId) }.count, 10)
        XCTAssertTrue(fichier.paquet.missions.allSatisfy { explorer.contains($0.missionId) || recette.contains($0.missionId) },
                      "chaque carte a sa mission : demo-missions.json ou mission de recette du paquet")
        XCTAssertEqual(fichier.dejaSwipees, ["demo-swipe-deja"])
        XCTAssertEqual(try DemoFixtures.swipesAnterieurs(), ["demo-swipe-deja"])
        // Ordre servi : la carte « choix du contrat » en deuxième, la carte déjà swipée en dernier (XCUITest par boutons).
        XCTAssertEqual(fichier.paquet.missions.map(\.missionId).prefix(3), ["demo-mission-015", "demo-swipe-choix", "demo-mission-016"])
        XCTAssertEqual(fichier.paquet.missions.last?.missionId, "demo-swipe-deja")
        let choix = try XCTUnwrap(fichier.missionsRecette.first)
        XCTAssertEqual(choix.record.typeContratRecherche, "TOUS", "contrat au choix : le ❤️ du profil MIXTE demande l'option")
        XCTAssertEqual(choix.record.statut, "OUVERTE")
        XCTAssertEqual(choix.creneaux.count, 1)
        XCTAssertTrue(fichier.missionsRecette.allSatisfy { $0.record.modeAttribution == CandidatureRules.modeCandidature },
                      "jamais « premier arrivé » : le détail ne propose pas d'acceptation immédiate")
    }

    func testSwipeRefusTraduitLesCodesEtGardeLesMessagesRediges() {
        XCTAssertEqual(SwipeRefus.libelles.count, 6, "sept codes du corps SQL, `auth_required` traité à part")
        XCTAssertNil(SwipeRefus.libelles["auth_required"])
        XCTAssertEqual(SwipeRefus.traduire("mission_deja_swipee").code, "mission_deja_swipee")
        XCTAssertEqual(SwipeRefus.traduire("mission_deja_swipee").message, "Vous avez déjà répondu à cette mission.")
        let redige = SwipeRefus.traduire("Vous avez déjà candidaté à cette mission")
        XCTAssertNil(redige.code)
        XCTAssertEqual(redige.message, "Vous avez déjà candidaté à cette mission", "message serveur verbatim")
        XCTAssertEqual(SwipeRefus.traduire(nil).message, SwipeRefus.repli)
        XCTAssertTrue(SwipeRefus.estHorsPaquet("mission_indisponible"))
        XCTAssertTrue(SwipeRefus.estHorsPaquet("acces_refuse"), "revue B8 de #1165, m1 : refus définitif pour la mission")
        XCTAssertTrue(SwipeRefus.estHorsPaquet("profession_incompatible"))
        XCTAssertFalse(SwipeRefus.estHorsPaquet("direction_invalide"))
        XCTAssertFalse(SwipeRefus.estHorsPaquet("profil_introuvable"), "défaut de session, pas de la mission")
        XCTAssertFalse(SwipeRefus.estHorsPaquet(nil))
    }

    func testPreferencesAmorceesCommeLeQuizWeb() {
        XCTAssertEqual(PreferencesMatching.depuisQuiz(horaire: .nuit, rythme: .weekend),
                       PreferencesMatching(nuit: 0.8, jour: 0.3, weekend: 0.8, semaine: 0.3))
        XCTAssertEqual(PreferencesMatching.depuisQuiz(horaire: .jour, rythme: .semaine),
                       PreferencesMatching(nuit: 0.3, jour: 0.8, weekend: 0.3, semaine: 0.8))
        XCTAssertEqual(PreferencesMatching.depuisQuiz(horaire: .tous, rythme: .tous),
                       PreferencesMatching(nuit: 0.5, jour: 0.5, weekend: 0.5, semaine: 0.5))
        XCTAssertTrue(PreferencesMatching(nuit: 0, jour: 1, weekend: 0.5, semaine: 0.5).dansLesBornes)
        XCTAssertFalse(PreferencesMatching(nuit: 1.1, jour: 0, weekend: 0, semaine: 0).dansLesBornes)
    }
}
