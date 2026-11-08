import XCTest
@testable import JoleneCore

/// État éditable des filtres d'Explorer (lot 1, T4a) : port de `src/pages/RechercheMissions.tsx`
/// (état initial l.94-102, chips l.334-356, badge l.271-278, état vide l.431-456 dont l'action
/// secondaire l.440-455, « Réinitialiser » l.609-626 dont `setTauxMin(0)` l.618, saisie du taux
/// l.553-565, annonce du rayon l.604-607 ; feuille l.475-637).
final class ExplorerFiltresTests: XCTestCase {
    typealias S = MissionsTestSupport

    private func profil(rayon: Double? = 50, taux: Double? = 0, lat: Double? = 48.8566, lng: Double? = 2.3522) -> SoignantProfile {
        SoignantProfile(id: "user-1", profession: "IDE", adresseLat: lat, adresseLng: lng, rayonDeplacementKm: rayon,
                        tousDocumentsValides: false, typeContrat: "CDD", typesContratAcceptes: "[\"CDD\",\"LIBERAL\"]",
                        typeExercice: "MIXTE", tauxHoraireMinimum: taux)
    }

    func testFiltresInitiauxEgauxAuxFiltresParDefautDuLot0() {
        // La première lecture d'Explorer reste celle du lot 0 : mêmes filtres envoyés au port.
        for p in [profil(), profil(rayon: nil, taux: nil), profil(rayon: 0, taux: 12), profil(rayon: 15, taux: 30)] {
            XCTAssertEqual(ExplorerFiltres.initiaux(profile: p).missionFilters, MissionBusiness.defaultFilters(profile: p))
        }
        let initiaux = ExplorerFiltres.initiaux(profile: profil(rayon: 15, taux: 30))
        XCTAssertEqual(initiaux.rayonKm, 15)
        XCTAssertEqual(initiaux.tauxMin, 30)
        XCTAssertEqual(initiaux.ville, "")
        XCTAssertEqual(initiaux.profession, "")
        XCTAssertFalse(initiaux.urgentesOnly)
        XCTAssertEqual(initiaux.typeContrat, .tous)
        XCTAssertEqual(initiaux.horaire, .tous)
        XCTAssertNil(initiaux.etablissementId)
        XCTAssertEqual(ExplorerFiltres.initiaux(profile: profil(rayon: nil)).rayonKm, 50, "rayon absent → 50 km (`|| 50`)")
        XCTAssertEqual(ExplorerFiltres.initiaux(profile: profil(rayon: 0)).rayonKm, 50, "rayon nul → 50 km (`|| 50`)")
    }

    func testFiltresInitiauxConserventEtablissementDemande() {
        let filtres = ExplorerFiltres.initiaux(profile: profil(), etablissementId: "etab-2")
        XCTAssertEqual(filtres.etablissementId, "etab-2")
        XCTAssertEqual(filtres.missionFilters.etablissementId, "etab-2")
        XCTAssertNil(ExplorerFiltres.initiaux(profile: profil(), etablissementId: "").etablissementId,
                     "un identifiant vide n'est pas un filtre")
    }

    func testMissionFiltersDeriveChaqueChamp() {
        let filtres = ExplorerFiltres(ville: "Lyon", rayonKm: 25, tauxMin: 28, profession: "IADE", urgentesOnly: true,
                                      typeContrat: .liberal, horaire: .nuit, etablissementId: "etab-9")
        XCTAssertEqual(filtres.missionFilters,
                       MissionFilters(ville: "Lyon", rayonKm: 25, tauxMin: 28, profession: "IADE", urgentesOnly: true,
                                      typeContrat: .liberal, horaire: .nuit, etablissementId: "etab-9"))
    }

    func testReinitialiserReprendLeWebTauxAZeroEtEtablissementConserve() {
        let p = profil(rayon: 15, taux: 30)
        let modifies = ExplorerFiltres(ville: "Paris", rayonKm: 80, tauxMin: 40, profession: "IADE", urgentesOnly: true,
                                       typeContrat: .cdd, horaire: .weekend, etablissementId: "etab-2")
        let remis = modifies.reinitialises(profile: p)
        XCTAssertEqual(remis.ville, "")
        XCTAssertEqual(remis.rayonKm, 15, "rayon du profil (`soignant.rayon_deplacement_km || 50`)")
        // Web l.618 : `setTauxMin(0)` — le taux minimum du profil n'est PAS rétabli par « Réinitialiser ».
        XCTAssertEqual(remis.tauxMin, 0)
        XCTAssertEqual(remis.profession, "")
        XCTAssertFalse(remis.urgentesOnly)
        XCTAssertEqual(remis.typeContrat, .tous)
        XCTAssertEqual(remis.horaire, .tous)
        XCTAssertEqual(remis.etablissementId, "etab-2", "le filtre établissement vient du lien, pas des critères")
        XCTAssertEqual(modifies.reinitialises(profile: profil(rayon: nil)).rayonKm, 50)
    }

    func testChipsRapidesBasculentCommeLeWeb() {
        let base = ExplorerFiltres.initiaux(profile: profil())
        XCTAssertTrue(base.basculantUrgentes().urgentesOnly)
        XCTAssertFalse(base.basculantUrgentes().basculantUrgentes().urgentesOnly)
        XCTAssertEqual(base.basculantHoraire(.weekend).horaire, .weekend)
        XCTAssertEqual(base.basculantHoraire(.weekend).basculantHoraire(.weekend).horaire, .tous, "second appui = TOUS")
        XCTAssertEqual(base.basculantHoraire(.weekend).basculantHoraire(.nuit).horaire, .nuit, "une seule dimension d'horaire")
        XCTAssertEqual(base.basculantHoraire(.jour).horaire, .jour)
        // Une bascule ne touche aucun autre critère.
        var attendu = base; attendu.urgentesOnly = true
        XCTAssertEqual(base.basculantUrgentes(), attendu)
        XCTAssertEqual(ExplorerFiltres.chipsRapides.map(\.horaire), [nil, .weekend, .nuit, .jour])
        XCTAssertEqual(ExplorerFiltres.chipsRapides.map(\.titre), ["🔥 Urgentes", "📅 Week-end", "🌙 Nuit", "☀️ Jour"])
        XCTAssertEqual(ExplorerFiltres.chipsRapides.map(\.identifiant), ["chip-urgentes", "chip-weekend", "chip-nuit", "chip-jour"])
    }

    func testChipActifSelonLEtat() {
        let base = ExplorerFiltres.initiaux(profile: profil())
        let urgentes = ExplorerFiltres.chipsRapides[0], weekend = ExplorerFiltres.chipsRapides[1]
        XCTAssertFalse(base.estActif(urgentes))
        XCTAssertTrue(base.basculantUrgentes().estActif(urgentes))
        XCTAssertFalse(base.basculantUrgentes().estActif(weekend))
        XCTAssertTrue(base.basculantHoraire(.weekend).estActif(weekend))
        XCTAssertEqual(base.basculer(urgentes), base.basculantUrgentes())
        XCTAssertEqual(base.basculer(weekend), base.basculantHoraire(.weekend))
    }

    func testNombreFiltresActifsHorsChipsEtRayon() {
        let base = ExplorerFiltres.initiaux(profile: profil())
        XCTAssertEqual(base.nombreFiltresActifs, 0)
        // Les chips rapides et le rayon ne comptent pas (badge web l.271-278).
        var chips = base.basculantUrgentes().basculantHoraire(.nuit); chips.rayonKm = 5
        XCTAssertEqual(chips.nombreFiltresActifs, 0)
        var tout = base
        tout.profession = "IADE"; tout.ville = "Paris"; tout.tauxMin = 25; tout.typeContrat = .cdd
        XCTAssertEqual(tout.nombreFiltresActifs, 4)
        var villeBlanche = base; villeBlanche.ville = "   "
        XCTAssertEqual(villeBlanche.nombreFiltresActifs, 0, "ville réduite à des espaces : inactive (`trim()`)")
        XCTAssertEqual(ExplorerFiltres.libelleFiltresActifs(0), "Aucun filtre actif")
        XCTAssertEqual(ExplorerFiltres.libelleFiltresActifs(1), "1 filtre actif")
        XCTAssertEqual(ExplorerFiltres.libelleFiltresActifs(3), "3 filtres actifs")
    }

    func testActionEtatVidePrioriteAuxChipsPuisRayon() {
        let base = ExplorerFiltres.initiaux(profile: profil())
        XCTAssertEqual(base.actionEtatVide, .elargirRayon)
        XCTAssertEqual(base.basculantUrgentes().actionEtatVide, .effacerFiltresRapides)
        XCTAssertEqual(base.basculantHoraire(.jour).actionEtatVide, .effacerFiltresRapides)
        var auMaximum = base; auMaximum.rayonKm = 100
        XCTAssertNil(auMaximum.actionEtatVide, "rayon déjà à 100 km et aucune chip : pas d'action secondaire")

        let effaces = base.basculantUrgentes().basculantHoraire(.weekend).effacantFiltresRapides()
        XCTAssertFalse(effaces.urgentesOnly)
        XCTAssertEqual(effaces.horaire, .tous)
        var elargi = base; elargi.rayonKm = 90
        XCTAssertEqual(elargi.elargissantRayon().rayonKm, 100, "`Math.min(100, r + 20)`")
        XCTAssertEqual(base.elargissantRayon().rayonKm, 70)
        XCTAssertEqual(ExplorerFiltres.ActionEtatVide.effacerFiltresRapides.titre, "Effacer les filtres rapides")
        XCTAssertEqual(ExplorerFiltres.ActionEtatVide.elargirRayon.titre, "Élargir le rayon (+20 km)")
        XCTAssertEqual(base.appliquant(.elargirRayon), base.elargissantRayon())
        XCTAssertEqual(base.basculantUrgentes().appliquant(.effacerFiltresRapides), base)
    }

    func testSaisieDuTauxMinimum() {
        // Web : `Number(e.target.value) || 0` et `value={tauxMin || ''}`.
        XCTAssertEqual(ExplorerFiltres.taux(depuisSaisie: ""), 0)
        XCTAssertEqual(ExplorerFiltres.taux(depuisSaisie: "25"), 25)
        XCTAssertEqual(ExplorerFiltres.taux(depuisSaisie: " 25 "), 25)
        XCTAssertEqual(ExplorerFiltres.taux(depuisSaisie: "25.5"), 25.5)
        XCTAssertEqual(ExplorerFiltres.taux(depuisSaisie: "25,5"), 25.5, "clavier décimal français : virgule acceptée")
        XCTAssertEqual(ExplorerFiltres.taux(depuisSaisie: "abc"), 0)
        XCTAssertEqual(ExplorerFiltres.taux(depuisSaisie: "-3"), 0, "un taux négatif est inerte (`tauxMin > 0`) : ramené à 0")
        XCTAssertEqual(ExplorerFiltres.taux(depuisSaisie: "inf"), 0)
        XCTAssertEqual(ExplorerFiltres.saisie(depuisTaux: 0), "")
        XCTAssertEqual(ExplorerFiltres.saisie(depuisTaux: 25), "25")
        // Réaffichage à la réouverture de la feuille : virgule décimale du clavier français.
        XCTAssertEqual(ExplorerFiltres.saisie(depuisTaux: 25.5), "25,5")
        XCTAssertEqual(ExplorerFiltres.saisie(depuisTaux: 0.25), "0,25")
    }

    func testSaisieDuTauxAllerRetourAvecLaVirgule() {
        // Saisi « 25,5 » → appliqué → feuille rouverte : « 25,5 » réaffiché, relu à l'identique.
        for saisie in ["25,5", "25.5", "30", "12,75"] {
            let taux = ExplorerFiltres.taux(depuisSaisie: saisie)
            let reaffichee = ExplorerFiltres.saisie(depuisTaux: taux)
            XCTAssertFalse(reaffichee.contains("."), "« \(saisie) » réaffiché sans point : \(reaffichee)")
            XCTAssertEqual(ExplorerFiltres.taux(depuisSaisie: reaffichee), taux, "aller-retour de « \(saisie) »")
        }
        XCTAssertEqual(ExplorerFiltres.saisie(depuisTaux: ExplorerFiltres.taux(depuisSaisie: "25.5")), "25,5")
    }

    func testRayonBornesEtLibelles() {
        XCTAssertEqual(ExplorerFiltres.rayonMinimumKm, 5)
        XCTAssertEqual(ExplorerFiltres.rayonMaximumKm, 100)
        XCTAssertEqual(ExplorerFiltres.rayonPasKm, 5)
        XCTAssertEqual(ExplorerFiltres.libelleRayon(50), "Rayon : 50 km")
        XCTAssertEqual(ExplorerFiltres.libelleRayon(37), "Rayon : 37 km", "rayon du profil hors pas : affiché tel quel")
        // Le rayon n'est annoncé que s'il s'applique réellement : position du soignant connue (web l.604-607).
        XCTAssertTrue(ExplorerFiltres.rayonApplicable(profile: profil()))
        XCTAssertFalse(ExplorerFiltres.rayonApplicable(profile: profil(lat: nil)))
        XCTAssertFalse(ExplorerFiltres.rayonApplicable(profile: profil(lng: nil)))
        // La condition est l'absence de latitude/longitude, pas d'adresse : une adresse saisie mais
        // non géocodée a la même conséquence, le message parle donc de la position.
        XCTAssertEqual(ExplorerFiltres.messageRayonInapplicable,
                       "Votre position n'est pas connue : la distance des missions ne peut pas être calculée et le rayon ne s'applique pas.")
        XCTAssertFalse(ExplorerFiltres.messageRayonInapplicable.contains("adresse"))
        XCTAssertEqual(ExplorerFiltres.libelleCompteur(0), "0 mission")
        XCTAssertEqual(ExplorerFiltres.libelleCompteur(1), "1 mission")
        XCTAssertEqual(ExplorerFiltres.libelleCompteur(30), "30 missions")
    }

    func testOptionsDesSelecteursDansLOrdreDuWeb() {
        XCTAssertEqual(ExplorerFiltres.optionsContrat.map(\.valeur), [.tous, .cdd, .liberal])
        XCTAssertEqual(ExplorerFiltres.optionsContrat.map(\.titre), ["Tous", "CDD", "Libéral"])
        XCTAssertEqual(ExplorerFiltres.optionsHoraire.map(\.valeur), [.tous, .jour, .nuit, .weekend])
        XCTAssertEqual(ExplorerFiltres.optionsHoraire.map(\.titre), ["Tous", "Jour", "Nuit", "Week-end"])
        // Profession : « » = profession du profil avec équivalences, puis `PROFESSIONS` du web.
        let professions = ExplorerFiltres.optionsProfession(profile: profil())
        XCTAssertEqual(professions.first?.valeur, "")
        XCTAssertEqual(professions.first?.titre, "Ma profession : Infirmier(ère) Diplômé(e) d'État (IDE)")
        XCTAssertEqual(professions.dropFirst().map(\.valeur), MissionPresentation.professions.map(\.valeur))
        XCTAssertEqual(professions.count, 18)
    }
}
