import XCTest
@testable import JoleneCore

/// Carte et détail du swipe (lot 4, T3b) : ports de `CardMissionSwipe.tsx` (`formatQuartier`, `momentLabel`,
/// `contratLabel`, accroche, « Pourquoi N ? », `aria-label`) et de `ModalDetailMissionSwipe.tsx` (conditions,
/// rémunération servie, « Pourquoi ce match »), états de fin de paquet, filtre du paquet dérivé d'Explorer.
/// Valeurs du serveur affichées telles quelles : score absent jamais remplacé par 0, aucun montant recalculé.
final class SwipePresentationTests: XCTestCase {
    // MARK: - Données

    /// Carte décodée depuis une ligne du paquet : champs de base, surchargés par `champs` (`NSNull()` pour `null`).
    private func carte(_ champs: [String: Any] = [:],
                       creneaux: [(String, String)] = [("2026-12-01T07:00:00+00:00", "2026-12-01T15:00:00+00:00")],
                       nbCreneaux: Int? = nil) throws -> CarteSwipe {
        var ligne: [String: Any] = [
            "mission_id": "m-1", "intitule": "Jour IDE", "profession_requise": "IDE", "etablissement_id": "e-1",
            "etablissement_nom": "Clinique A", "etablissement_ville": "Lyon", "etablissement_code_postal": "69003",
            "debut_le": creneaux.first?.0 ?? "2026-12-01T07:00:00+00:00", "fin_le": creneaux.last?.1 ?? "2026-12-01T15:00:00+00:00",
            "nb_creneaux": nbCreneaux ?? creneaux.count,
        ]
        ligne.merge(champs) { _, nouveau in nouveau }
        let decodee = try JSONDecoder().decode(LigneSwipe.self, from: JSONSerialization.data(withJSONObject: ligne))
        let slots = creneaux.enumerated().map { index, creneau in
            MissionSlot(id: "s-\(index)", missionId: "m-1", debut: creneau.0, fin: creneau.1, estPause: false, typeCreneau: "PREVISIONNEL")
        }
        return CarteSwipe(ligne: decodee, creneaux: slots)
    }

    // MARK: - Lieu

    func testQuartierCommeLeWeb() {
        XCTAssertEqual(SwipePresentation.quartier(ville: "Paris", codePostal: "75016"), "Paris 16e")
        XCTAssertEqual(SwipePresentation.quartier(ville: "Paris", codePostal: "75001"), "Paris 1er")
        XCTAssertEqual(SwipePresentation.quartier(ville: "Paris", codePostal: "75020"), "Paris 20e")
        XCTAssertEqual(SwipePresentation.quartier(ville: "Paris", codePostal: "75116"), "Paris 16e", "`cp.slice(3)` : deux derniers chiffres")
        XCTAssertEqual(SwipePresentation.quartier(ville: "Paris", codePostal: "75021"), "Paris 75021", "hors des vingt arrondissements")
        XCTAssertEqual(SwipePresentation.quartier(ville: "Paris", codePostal: "75000"), "Paris 75000")
        XCTAssertEqual(SwipePresentation.quartier(ville: "Lyon", codePostal: "69003"), "Lyon 69003")
        XCTAssertEqual(SwipePresentation.quartier(ville: "Lyon", codePostal: nil), "Lyon")
        XCTAssertEqual(SwipePresentation.quartier(ville: nil, codePostal: "69003"), "69003")
        XCTAssertEqual(SwipePresentation.quartier(ville: "", codePostal: ""), "")
        XCTAssertEqual(SwipePresentation.quartier(ville: "Paris", codePostal: "7501A"), "Paris 7501A")
    }

    func testLieuDistanceDuServeurEtNoteDeLEtablissement() throws {
        let avec = try carte(["distance_km": 3.2, "etablissement_score": 91.5])
        XCTAssertEqual(SwipePresentation.lieu(avec), "Lyon 69003 · 3.2 km", "distance servie, rendue comme le nombre JavaScript")
        XCTAssertEqual(SwipePresentation.scoreEtablissement(avec.etablissementScore), "92", "Math.round")
        XCTAssertEqual(SwipePresentation.scoreEtablissementDetail(avec.etablissementScore), "92/100")
        let sans = try carte(["etablissement_ville": NSNull(), "etablissement_code_postal": NSNull()])
        XCTAssertEqual(SwipePresentation.lieu(sans), "—", "ni quartier ni distance")
        XCTAssertNil(SwipePresentation.scoreEtablissement(sans.etablissementScore), "aucune note fabriquée")
        XCTAssertEqual(SwipePresentation.scoreEtablissement(84.4), "84")
        XCTAssertEqual(SwipePresentation.etablissement(avec), "Clinique A")
        XCTAssertEqual(SwipePresentation.etablissement(try carte(["etablissement_nom": NSNull()])), "Établissement")
    }

    // MARK: - Rémunération

    func testAccrocheMontantSelonLeRegimeDeLaMissionSinonTauxHoraire() throws {
        let salariee = try carte(["type_contrat_recherche": "SALARIE", "net_estime": 162.4, "total_brut": 208, "net_a_payer": 224.6, "taux_horaire_base": 26])
        XCTAssertEqual(SwipePresentation.accroche(salariee), .init(montant: "~162€", unite: "net estimé*"))
        XCTAssertEqual(SwipePresentation.accroche(salariee).texte, "~162€ net estimé*")
        XCTAssertFalse(SwipePresentation.estLiberale(salariee))

        let liberale = try carte(["type_contrat_recherche": "LIBERAL", "net_a_payer": 839.5, "total_brut": 800, "paiement_rapide": true])
        XCTAssertEqual(SwipePresentation.accroche(liberale), .init(montant: "840€", unite: "honoraires"), "Math.round, sans « ~ »")
        XCTAssertTrue(SwipePresentation.paiementRapide(liberale), "⚡ : honoraires libéraux et drapeau serveur")

        let auChoix = try carte(["type_contrat_recherche": "TOUS", "total_brut": 248, "paiement_rapide": true])
        XCTAssertEqual(SwipePresentation.accroche(auChoix), .init(montant: "~248€", unite: "brut indicatif"))
        XCTAssertFalse(SwipePresentation.paiementRapide(auChoix), "contrat non choisi : jamais le badge ⚡")

        let taux = try carte(["type_contrat_recherche": "SALARIE", "taux_horaire_base": 28.5])
        XCTAssertEqual(SwipePresentation.accroche(taux), .init(montant: "28.5€", unite: "/h"), "aucun montant servi : taux horaire")
        XCTAssertEqual(SwipePresentation.accroche(taux).texte, "28.5€/h")
        XCTAssertEqual(SwipePresentation.accroche(try carte(["taux_horaire_base": 0])), .init(montant: "—", unite: "/h"))
        XCTAssertEqual(SwipePresentation.accroche(try carte()), .init(montant: "—", unite: "/h"))
        XCTAssertFalse(SwipePresentation.paiementRapide(try carte(["type_contrat_recherche": "LIBERAL", "paiement_rapide": true])),
                       "libérale sans montant servi : pas de badge, comme le web")
    }

    func testRegimeDeLaMissionJamaisCeluiDuProfil() throws {
        // `type_contrat_applique` l'emporte sur le contrat recherché ; le profil du soignant n'entre jamais ici.
        let appliquee = try carte(["type_contrat_applique": "LIBERAL", "type_contrat_recherche": "SALARIE", "net_a_payer": 500, "net_estime": 300])
        XCTAssertEqual(SwipePresentation.montant(appliquee)?.nature, .honorairesLiberaux)
        XCTAssertEqual(SwipePresentation.contrat("SALARIE"), "Salarié (CDD)")
        XCTAssertEqual(SwipePresentation.contrat("LIBERAL"), "Libéral")
        XCTAssertEqual(SwipePresentation.contrat("TOUS"), "Salarié ou libéral")
        XCTAssertNil(SwipePresentation.contrat(nil))
        XCTAssertNil(SwipePresentation.contrat("MIXTE"), "un régime de profil n'est pas un contrat de mission")
    }

    // MARK: - Planning, moment, étiquettes

    func testMomentDeriveDesHorairesReelsEtDesMajorationsServies() throws {
        XCTAssertEqual(SwipePresentation.moment(try carte()), "☀️ jour")
        XCTAssertEqual(SwipePresentation.dureeMoment(try carte()), "8 h · ☀️ jour")
        let nuit = try carte(creneaux: [("2026-12-01T19:00:00+00:00", "2026-12-02T07:00:00+00:00")])
        XCTAssertEqual(SwipePresentation.moment(nuit), "🌙 nuit", "20 h à Paris : nuit, sans majoration servie")
        XCTAssertEqual(SwipePresentation.dureeMoment(nuit), "12 h · 🌙 nuit")
        XCTAssertEqual(SwipePresentation.moment(try carte(["montant_majoration_dimanche": 12])), "☀️ dimanche")
        XCTAssertEqual(SwipePresentation.moment(try carte(["montant_majoration_dimanche": 12, "montant_majoration_ferie": 30])), "🎉 férié",
                       "le férié passe avant le dimanche")
        let incomplet = try carte(nbCreneaux: 2)
        XCTAssertFalse(SwipePresentation.planning(incomplet).exact)
        XCTAssertEqual(SwipePresentation.moment(incomplet), "planning à confirmer")
        XCTAssertEqual(SwipePresentation.dureeMoment(incomplet), "Horaires non vérifiés · planning à confirmer")
        let demi = try carte(creneaux: [("2026-12-01T07:00:00+00:00", "2026-12-01T14:30:00+00:00")])
        XCTAssertEqual(SwipePresentation.dureeMoment(demi), "7,5 h · ☀️ jour", "heures au format français")
    }

    func testEtiquettesEtRaisonsDuScore() throws {
        let complete = try carte(["service": "Réa", "type_contrat_recherche": "TOUS", "score": 85, "breakdown": ["distance": 20, "urgence": 10]])
        XCTAssertEqual(SwipePresentation.etiquettes(complete), ["IDE", "Réa", "Salarié ou libéral"])
        XCTAssertEqual(SwipePresentation.raisons(complete), "proche de chez toi · mission urgente")
        XCTAssertEqual(SwipeTextes.pourquoi(85), "Pourquoi 85 ?")
        XCTAssertEqual(SwipePresentation.etiquettes(try carte(["profession_requise": NSNull()])), [], "aucune étiquette inventée")
        let sansScore = try carte(["score": NSNull(), "breakdown": ["distance": 20]])
        XCTAssertNil(SwipePresentation.raisons(sansScore), "score inconnu : pas de « Pourquoi ? »")
        XCTAssertNil(SwipePresentation.raisons(try carte(["score": 70, "breakdown": [String: Any]()])), "score sans raison : rien")
        XCTAssertEqual(SwipePresentation.raisons(try carte(["score": 0, "breakdown": ["tarif": 3]])), "bien payée vs le marché",
                       "un vrai 0 servi reste un score connu")
    }

    func testLibelleAccessibiliteCommeLAriaLabelDuWeb() throws {
        let complete = try carte(["type_contrat_recherche": "SALARIE", "net_estime": 162.4, "score": 85])
        XCTAssertEqual(SwipePresentation.libelleAccessibilite(complete),
                       "Mission IDE à Clinique A, environ 162 euros net estimé*, score 85 sur 100. Toucher pour le détail.")
        XCTAssertEqual(SwipePresentation.libelleAccessibilite(try carte()), "Mission IDE à Clinique A. Toucher pour le détail.")
    }

    // MARK: - Détail

    func testConditionsEtRemunerationServieSansCalculClient() throws {
        let salariee = try carte(["service": "Réa", "duree_heures": 8, "taux_horaire_base": 26, "type_contrat_recherche": "SALARIE", "net_estime": 162.4, "total_brut": 208, "net_a_payer": 1224.6, "montant_majoration_nuit": 12, "montant_ifm": 20, "montant_icp": 20])
        XCTAssertEqual(SwipePresentation.conditions(salariee).map(\.valeur), ["IDE", "Réa", "26 €/h", "8h"])
        XCTAssertEqual(SwipePresentation.conditions(salariee).map(\.libelle), ["Profession", "Service", "Tarif horaire", "Durée"])
        let remuneration = try XCTUnwrap(SwipePresentation.remuneration(salariee))
        XCTAssertEqual(remuneration.libelle, "Net salarié estimé*")
        XCTAssertEqual(remuneration.montant, "~162\u{00A0}€")
        XCTAssertTrue(remuneration.noteNetEstime, "astérisque : la note du web l'accompagne")
        XCTAssertEqual(remuneration.lignes.map(\.libelle), ["Total brut", "Total avant cotisations"],
                       "colonnes servies seulement : ni brut de base, ni cumul des majorations, ni IFM + ICP")
        XCTAssertEqual(remuneration.lignes.map(\.valeur), ["208\u{00A0}€", "1\u{202F}225\u{00A0}€"])

        let liberale = try XCTUnwrap(SwipePresentation.remuneration(try carte(["type_contrat_recherche": "LIBERAL", "net_a_payer": 840, "total_brut": 800])))
        XCTAssertEqual(liberale.libelle, "Honoraires bruts")
        XCTAssertEqual(liberale.montant, "840\u{00A0}€")
        XCTAssertFalse(liberale.noteNetEstime)
        XCTAssertEqual(liberale.lignes.map(\.libelle), ["Total brut"], "pas de « total avant cotisations » en libéral")

        XCTAssertNil(SwipePresentation.remuneration(try carte(["taux_horaire_base": 26])), "aucun montant servi : aucun bloc")
        let sansNet = try XCTUnwrap(SwipePresentation.remuneration(try carte(["type_contrat_recherche": "SALARIE", "total_brut": 208])))
        XCTAssertEqual(sansNet.libelle, "Rémunération indicative")
        XCTAssertNil(sansNet.montant, "net estimé absent : aucun montant mis en avant, jamais le brut à sa place")
        XCTAssertEqual(SwipePresentation.conditions(try carte()).map(\.valeur), ["IDE", "—", "—", "—"])
        XCTAssertEqual(SwipePresentation.eurosEntiers(nil), "—")
        XCTAssertEqual(SwipePresentation.eurosEntiers(0), "0\u{00A0}€")
    }

    func testPourquoiCeMatchCommeLeDetailWeb() throws {
        let complete = try carte(["score": 88, "breakdown": ["tarif": 15, "distance": 20, "distance_km": 3.2, "horaire": 12, "etablissement": 9.5, "urgence": 10, "connaissance_etab": 3, "paiement_rapide": 2, "error": "x", "soignant_fiabilite": 9] as [String: Any]])
        XCTAssertEqual(SwipePresentation.raisonsDetail(complete).map { "\($0.libelle) : \($0.valeur)" }, [
            "Tarif vs marché local : 15 / 20", "Distance (3.2 km) : 20 / 20", "Vos horaires préférés : 12 / 15",
            "Qualité établissement : 9.5 / 15", "Urgence (bonus) : +10 / 10", "Vous connaissez cet établissement : +3",
            "⚡ Paiement rapide : +2",
        ])
        let sobre = try carte(["score": 40, "breakdown": ["tarif": 0, "distance": 5, "distance_km": NSNull(), "urgence": 0, "connaissance_etab": 0] as [String: Any]])
        XCTAssertEqual(SwipePresentation.raisonsDetail(sobre).map { "\($0.libelle) : \($0.valeur)" },
                       ["Tarif vs marché local : 0 / 20", "Distance : 5 / 20"], "bonus nuls masqués, distance sans kilomètres")
        XCTAssertEqual(SwipePresentation.raisonsDetail(try carte(["score": NSNull(), "breakdown": ["tarif": 15]])), [], "pas de score : pas de bloc")
        XCTAssertEqual(SwipePresentation.raisonsDetail(try carte(["score": 70, "breakdown": [String: Any]()])), [])
    }

    // MARK: - Fin de paquet, compteur, filtre

    func testFinDePaquetToutVuOuRienDeNouveau() {
        let toutVu = SwipePresentation.finDePaquet(paquetLuNonVide: true)
        XCTAssertEqual(toutVu.titre, "Vous avez tout vu pour aujourd'hui")
        XCTAssertEqual(toutVu.alerte, "🔔 Me prévenir des prochaines missions")
        XCTAssertTrue(toutVu.elargirLeRayon)
        XCTAssertEqual(toutVu.secondaire, "📍 Élargir le rayon (+20 km)")
        let rien = SwipePresentation.finDePaquet(paquetLuNonVide: false)
        XCTAssertEqual(rien.titre, "Aucune nouvelle mission à parcourir", "jamais « aucune mission » : la liste peut en montrer")
        XCTAssertEqual(rien.alerte, "🔔 Me prévenir dès qu'une mission arrive")
        XCTAssertFalse(rien.elargirLeRayon)
        XCTAssertEqual(rien.secondaire, "Voir la recherche en liste")
        XCTAssertEqual(SwipeTextes.favorisTitre(3), "Vos missions sauvegardées (3)")
        XCTAssertEqual(SwipePresentation.favorisAffiches, 5)
    }

    func testCompteurDuPaquet() {
        XCTAssertEqual(SwipeTextes.restantes(12), "12 missions à parcourir")
        XCTAssertEqual(SwipeTextes.restantes(1), "1 mission à parcourir")
        XCTAssertEqual(SwipeTextes.restantes(0), "0 missions à parcourir")
    }

    func testFiltreDuPaquetDeriveDesCriteresDExplorer() throws {
        let filtres = ExplorerFiltres(ville: "Lyon", rayonKm: 30, tauxMin: 25, profession: "IDE", urgentesOnly: true,
                                      typeContrat: .cdd, horaire: .nuit, etablissementId: "e-9")
        XCTAssertEqual(FiltrePaquetSwipe(explorer: filtres),
                       FiltrePaquetSwipe(urgentesOnly: true, horaire: .nuit, profession: "IDE", ville: "Lyon", rayonKm: 30,
                                         tauxMin: 25, typeContrat: "CDD"))
        let initiaux = ExplorerFiltres.initiaux(profile: DemoWorld.context.profile)
        let paquet = try DemoFixtures.loadSwipe().paquet.missions.map { CarteSwipe(ligne: $0, creneaux: []) }
        XCTAssertEqual(FiltrePaquetSwipe.filtrer(paquet, filtre: FiltrePaquetSwipe(explorer: initiaux), professionParcours: nil,
                                                 mission: \.missionPaquet).count, 12, "critères par défaut : tout le paquet démo")
        XCTAssertEqual(FiltrePaquetSwipe.filtrer(paquet, filtre: FiltrePaquetSwipe(explorer: initiaux.basculantUrgentes()),
                                                 professionParcours: nil, mission: \.missionPaquet).map(\.id),
                       ["demo-mission-016", "demo-mission-021"], "chip « Urgentes » appliquée au paquet comme à la liste")
    }

    // MARK: - Paquet démo

    func testCartesDuPaquetDemoTellesQueLEcranLesAffiche() async throws {
        let cartes = try await DemoWorld.gateways().swipe.paquet(context: DemoWorld.context)
        XCTAssertEqual(cartes.count, 12)
        let premiere = try XCTUnwrap(cartes.first)
        XCTAssertEqual(premiere.id, "demo-mission-015")
        XCTAssertEqual(SwipePresentation.etablissement(premiere), "Cabinet fictif du Parc")
        XCTAssertEqual(SwipePresentation.lieu(premiere), "Vincennes 94300 · 6.4 km")
        XCTAssertEqual(SwipePresentation.accroche(premiere).texte, "29€/h", "aucun montant servi par la fixture : taux horaire")
        XCTAssertEqual(SwipePresentation.dureeMoment(premiere), "8 h · ☀️ jour")
        XCTAssertEqual(SwipePresentation.etiquettes(premiere), ["IDE", "Médecine polyvalente", "Libéral"])
        XCTAssertNotNil(SwipePresentation.raisons(premiere))
        let choix = try XCTUnwrap(cartes.first { $0.id == "demo-swipe-choix" })
        XCTAssertEqual(SwipePresentation.lieu(choix), "Paris 11e · 1.4 km")
        XCTAssertEqual(SwipePresentation.etiquettes(choix), ["IDE", "Chirurgie ambulatoire", "Salarié ou libéral"])
        XCTAssertEqual(SwipePresentation.scoreEtablissement(choix.etablissementScore), "92")
        XCTAssertTrue(SwipePresentation.planning(choix).exact, "créneau de la mission de recette")
        let nuit = try XCTUnwrap(cartes.first { $0.id == "demo-mission-016" })
        XCTAssertEqual(SwipePresentation.moment(nuit), "🌙 nuit")
        for sansScore in cartes.filter({ $0.score == nil }) {
            XCTAssertNil(SwipePresentation.raisons(sansScore), sansScore.id)
            XCTAssertEqual(SwipePresentation.raisonsDetail(sansScore), [], sansScore.id)
            XCTAssertFalse(SwipePresentation.libelleAccessibilite(sansScore).contains("score"), sansScore.id)
        }
        XCTAssertEqual(cartes.filter { $0.score == nil }.map(\.id), ["demo-mission-019", "demo-swipe-deja"])
    }
}
