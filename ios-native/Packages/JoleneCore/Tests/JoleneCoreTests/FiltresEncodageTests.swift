import XCTest
@testable import JoleneCore

/// Recherches sauvegardées (L4-T4) : encodage des critères d'Explorer en `p_filtres` (sept clés camelCase du web),
/// port du validateur serveur, lecture de `fn_lister_mes_filtres_sauvegardes`, application d'une recherche à Explorer et
/// mise en forme. La clé de comparaison et la préparation de l'alerte sont celles d'`AlerteRecherche` (golden T2).
final class FiltresEncodageTests: XCTestCase {
    private let profil = SoignantProfile(id: "u-1", profession: "IDE", adresseLat: 48.85, adresseLng: 2.35)

    private func explorer(ville: String = "Paris", rayon: Double = 25, taux: Double = 30, profession: String = "",
                          urgentes: Bool = true, contrat: MissionFilters.TypeContrat = .cdd,
                          horaire: MissionFilters.Horaire = .nuit, etablissement: String? = "etab-1") -> ExplorerFiltres {
        ExplorerFiltres(ville: ville, rayonKm: rayon, tauxMin: taux, profession: profession, urgentesOnly: urgentes,
                        typeContrat: contrat, horaire: horaire, etablissementId: etablissement)
    }

    // MARK: - Critères envoyés

    func testCriteresDExplorerSeptClesSansEtablissement() {
        let criteres = FiltresSauvegardesEncodage.criteres(explorer())
        XCTAssertEqual(criteres, FiltresAlerte(profession: "", rayonKm: 25, tauxMin: 30, typeContrat: "CDD", urgentesOnly: true,
                                               horaire: "NUIT", villeRecherche: "Paris"))
        guard case .objet(let objet) = FiltresSauvegardesEncodage.valeur(criteres) else { return XCTFail("objet attendu") }
        XCTAssertEqual(Set(objet.keys), Set(FiltresSauvegardesEncodage.clesAutorisees), "sept clés, jamais etablissementId")
        XCTAssertEqual(objet["villeRecherche"], .chaine("Paris"), "ville → villeRecherche")
        XCTAssertTrue(FiltresSauvegardesEncodage.estValide(.objet(objet)))
        // Clé de comparaison : nombres écrits comme JSON.stringify (entiers sans décimale).
        XCTAssertEqual(AlerteRecherche.cle(.objet(objet)),
                       #"{"horaire":"NUIT","profession":"","rayonKm":25,"tauxMin":30,"typeContrat":"CDD","urgentesOnly":true,"villeRecherche":"Paris"}"#)
    }

    /// Une recherche créée par le web (mêmes sept clés, autre ordre) est reconnue identique : réactivée, jamais doublée ;
    /// une recherche de même nom avec d'autres critères n'est jamais réutilisée (le nom libre prend un suffixe).
    func testRechercheDuWebAvecLesSeptClesReconnueIdentique() {
        let criteres = FiltresSauvegardesEncodage.criteres(explorer())
        let web = FiltreSauvegarde(id: "web", nom: "Ma recherche", filtres: .objet([
            "villeRecherche": .chaine("Paris"), "horaire": .chaine("NUIT"), "urgentesOnly": .booleen(true),
            "typeContrat": .chaine("CDD"), "tauxMin": .nombre(30), "rayonKm": .nombre(25), "profession": .chaine(""),
        ]), alerteActive: false, frequence: .quotidienne)
        let autre = FiltreSauvegarde(id: "autre", nom: "Alerte missions", filtres: .objet(["profession": .chaine("IDE"), "rayonKm": .nombre(100)]),
                                     alerteActive: true, frequence: .immediate)
        let preparation = AlerteRecherche.preparer(criteres: criteres, recherches: [autre, web], nomBase: "Alerte missions")
        XCTAssertEqual(preparation.deja?.id, "web")
        let sansIdentique = AlerteRecherche.preparer(criteres: criteres, recherches: [autre], nomBase: "Alerte missions")
        XCTAssertNil(sansIdentique.deja)
        XCTAssertEqual(sansIdentique.nom, "Alerte missions (2)")
        // Une recherche web à six clés (une absente) n'est pas identique : la comparaison exige les sept.
        var incomplete = web
        if case .objet(var objet) = web.filtres { objet["villeRecherche"] = nil; incomplete.filtres = .objet(objet) }
        XCTAssertNil(AlerteRecherche.preparer(criteres: criteres, recherches: [incomplete], nomBase: "x").deja)
    }

    // MARK: - Validateur

    func testValidateurRefuseCeQueLeServeurRefuserait() {
        let valide = FiltresSauvegardesEncodage.valeur(FiltresSauvegardesEncodage.criteres(explorer()))
        guard case .objet(let objet) = valide else { return XCTFail("objet attendu") }
        func avec(_ cle: String, _ valeur: ValeurJSON?) -> ValeurJSON {
            var copie = objet
            copie[cle] = valeur
            return .objet(copie)
        }
        XCTAssertFalse(FiltresSauvegardesEncodage.estValide(avec("etablissementId", .chaine("etab-1"))), "clé hors liste")
        XCTAssertFalse(FiltresSauvegardesEncodage.estValide(avec("typeContrat", .chaine("INTERIM"))))
        XCTAssertFalse(FiltresSauvegardesEncodage.estValide(avec("horaire", .chaine("SOIR"))))
        XCTAssertFalse(FiltresSauvegardesEncodage.estValide(avec("urgentesOnly", .chaine("true"))))
        XCTAssertFalse(FiltresSauvegardesEncodage.estValide(avec("villeRecherche", .nombre(75))))
        XCTAssertFalse(FiltresSauvegardesEncodage.estValide(avec("rayonKm", .nombre(-5))))
        XCTAssertFalse(FiltresSauvegardesEncodage.estValide(avec("tauxMin", .nombre(10001))))
        XCTAssertFalse(FiltresSauvegardesEncodage.estValide(avec("tauxMin", .chaine("1e3"))))
        XCTAssertFalse(FiltresSauvegardesEncodage.estValide(avec("rayonKm", .booleen(true))))
        XCTAssertTrue(FiltresSauvegardesEncodage.estValide(avec("tauxMin", .chaine("25.5"))))
        // m4 : la borne de 20 caractères de `p->>k` vaut aussi pour un nombre JSON (forme décimale, sans exposant).
        XCTAssertFalse(FiltresSauvegardesEncodage.estValide(avec("tauxMin", .nombre(0.000012345678901234567))), "23 caractères")
        XCTAssertTrue(FiltresSauvegardesEncodage.estValide(avec("tauxMin", .nombre(0.30000000000000004))), "19 caractères")
        XCTAssertTrue(FiltresSauvegardesEncodage.estValide(avec("rayonKm", .nombre(1e-7))))
        XCTAssertEqual(FiltresSauvegardesEncodage.texteNumerique(1e-7), "0.0000001")
        XCTAssertEqual(FiltresSauvegardesEncodage.texteNumerique(25), "25")
        XCTAssertFalse(FiltresSauvegardesEncodage.estValide(avec("tauxMin", .chaine("0.000012345678901234567"))))
        XCTAssertTrue(FiltresSauvegardesEncodage.estValide(avec("typeContrat", .null)), "null vaut TOUS")
        XCTAssertTrue(FiltresSauvegardesEncodage.estValide(.objet([:])), "toutes les clés sont facultatives côté serveur")
        XCTAssertFalse(FiltresSauvegardesEncodage.estValide(.tableau([])))
        XCTAssertEqual(FiltresSauvegardesEncodage.nomSaisi("  Nuits  "), "Nuits")
        XCTAssertNil(FiltresSauvegardesEncodage.nomSaisi(" \n "))
    }

    // MARK: - Lecture

    func testLectureDeLaListeTolerante() throws {
        let reponse: ValeurJSON = .tableau([
            .objet(["id": .chaine("r1"), "nom": .chaine("Nuits"), "audience": .chaine("SOIGNANT_RECHERCHE_MISSIONS"),
                    "filtres": .objet(["horaire": .chaine("NUIT")]), "alerte_active": .booleen(true),
                    "frequence_alerte": .chaine("IMMEDIATE"), "dernier_check_le": .chaine("2026-11-01T18:00:00.123456+00:00"),
                    "nb_resultats_dernier_check": .nombre(3), "cree_le": .chaine("x"), "mis_a_jour_le": .chaine("y")]),
            .objet(["id": .chaine("etab"), "nom": .chaine("Annuaire"), "audience": .chaine("ETAB_RECHERCHE_SOIGNANTS"),
                    "alerte_active": .booleen(false)]),
            .objet(["id": .chaine("r2"), "nom": .chaine("Sans critères"), "filtres": .null, "alerte_active": .booleen(false),
                    "frequence_alerte": .chaine("MENSUELLE"), "nb_resultats_dernier_check": .chaine("2")]),
        ])
        let liste = try XCTUnwrap(FiltresSauvegardesEncodage.liste(reponse))
        XCTAssertEqual(liste.map(\.id), ["r1", "r2"], "ordre serveur, autre audience écartée")
        XCTAssertEqual(liste[0], FiltreSauvegarde(id: "r1", nom: "Nuits", filtres: .objet(["horaire": .chaine("NUIT")]), alerteActive: true,
                                                  frequence: .immediate, dernierCheckLe: "2026-11-01T18:00:00.123456+00:00",
                                                  nbResultatsDernierCheck: 3))
        XCTAssertEqual(liste[1].filtres, .objet([:]), "`filtres ?? {}`")
        XCTAssertNil(liste[1].frequence, "fréquence inconnue : jamais une valeur plausible")
        XCTAssertEqual(liste[1].nbResultatsDernierCheck, 0)
        XCTAssertEqual(FiltresSauvegardesEncodage.liste(.tableau([])), [])
        XCTAssertNil(FiltresSauvegardesEncodage.liste(.objet(["error": .chaine("Non authentifié")])), "pas un tableau")
        XCTAssertNil(FiltresSauvegardesEncodage.liste(.tableau([.objet(["nom": .chaine("x"), "alerte_active": .booleen(true)])])),
                     "ligne sans identifiant")
        XCTAssertNil(FiltresSauvegardesEncodage.liste(.tableau([.objet(["id": .chaine("x"), "nom": .chaine("x")])])),
                     "état d'alerte illisible")
    }

    // MARK: - Application à Explorer

    func testAllerALaRechercheAppliqueLesClesDuBonType() {
        let precedent = explorer(ville: "", rayon: 50, taux: 0, profession: "", urgentes: false, contrat: .tous, horaire: .tous)
        let applique = FiltresSauvegardesEncodage.explorer(depuis: .objet([
            "profession": .chaine("AS"), "rayonKm": .nombre(30), "tauxMin": .nombre(22.5), "typeContrat": .chaine("LIBERAL"),
            "urgentesOnly": .booleen(true), "horaire": .chaine("WEEKEND"), "villeRecherche": .chaine("Lyon"),
        ]), precedent: precedent)
        XCTAssertEqual(applique, explorer(ville: "Lyon", rayon: 30, taux: 22.5, profession: "AS", urgentes: true, contrat: .liberal,
                                          horaire: .weekend, etablissement: nil))
        let partiel = FiltresSauvegardesEncodage.explorer(depuis: .objet([
            "rayonKm": .chaine("30"), "horaire": .chaine("SOIR"), "urgentesOnly": .nombre(1), "villeRecherche": .chaine("Nantes"),
        ]), precedent: precedent)
        var attendu = precedent
        attendu.ville = "Nantes"
        attendu.etablissementId = nil
        XCTAssertEqual(partiel, attendu, "type inattendu ou valeur inconnue : critère courant conservé ; établissement retiré")
    }

    // MARK: - Présentation

    func testMiseEnFormeDUneRecherche() {
        var recherche = FiltreSauvegarde(id: "r1", nom: "Nuits", filtres: .objet([:]), alerteActive: true, frequence: .immediate,
                                         dernierCheckLe: "2026-11-01T18:00:00.000Z", nbResultatsDernierCheck: 3)
        XCTAssertEqual(FiltresPresentation.etatAlerte(recherche), "🔔 Alertes toutes les heures")
        XCTAssertEqual(FiltresPresentation.dernierCheck(recherche), "Dernier check : 01 nov. 19:00", "heure de Paris")
        XCTAssertEqual(FiltresPresentation.resultats(recherche), "3 résultats")
        recherche.nbResultatsDernierCheck = 1
        XCTAssertEqual(FiltresPresentation.resultats(recherche), "1 résultat")
        recherche.nbResultatsDernierCheck = 0
        XCTAssertNil(FiltresPresentation.resultats(recherche))
        recherche.frequence = .hebdomadaire
        XCTAssertEqual(FiltresPresentation.etatAlerte(recherche), "🔔 Alertes hebdomadaire")
        recherche.frequence = nil
        XCTAssertEqual(FiltresPresentation.etatAlerte(recherche), FiltresTextes.alerteActiveSansFrequence)
        recherche.alerteActive = false
        XCTAssertEqual(FiltresPresentation.etatAlerte(recherche), "🔕 Alertes désactivées")
        recherche.dernierCheckLe = "illisible"
        XCTAssertNil(FiltresPresentation.dernierCheck(recherche))
        XCTAssertEqual(FiltresPresentation.nomBaseAlerte(filtres: explorer(), profile: profil),
                       "Alerte missions \(MissionPresentation.professionLabel("IDE"))", "profession du profil à défaut d'Explorer")
        XCTAssertEqual(FiltresPresentation.nomBaseAlerte(filtres: explorer(profession: "AS"), profile: profil),
                       "Alerte missions \(MissionPresentation.professionLabel("AS"))")
        XCTAssertEqual(FiltresPresentation.nomBaseAlerte(filtres: explorer(), profile: SoignantProfile(id: "u-1", profession: "")),
                       "Alerte missions")
        XCTAssertTrue(FiltresTextes.alerteRapideDescription(profession: "Infirmier", rayonKm: 50)
            .contains("une mission Infirmier correspondant à vos critères (rayon 50 km)"))
        // m1 : un filtre établissement actif n'est jamais retiré sans le dire.
        XCTAssertFalse(FiltresTextes.alerteRapideDescription(profession: nil, rayonKm: 50).contains(FiltresTextes.etablissementNonRepris))
        XCTAssertTrue(FiltresTextes.alerteRapideDescription(profession: nil, rayonKm: 50, filtreEtablissement: true)
            .hasSuffix(" " + FiltresTextes.etablissementNonRepris))
        // M1 : messages exacts d'une alerte existante, jamais une promesse de fréquence.
        XCTAssertEqual(FiltresTextes.alerteExisteDeja(frequence: .immediate), "Une alerte existe déjà pour cette recherche (toutes les heures).")
        XCTAssertEqual(FiltresTextes.alerteExisteDeja(frequence: .quotidienne), "Une alerte existe déjà pour cette recherche (chaque jour).")
        XCTAssertEqual(FiltresTextes.alerteExisteDeja(frequence: .hebdomadaire), "Une alerte existe déjà pour cette recherche (chaque semaine).")
        XCTAssertEqual(FiltresTextes.alerteExisteDeja(frequence: nil), "Une alerte existe déjà pour cette recherche.")
        XCTAssertEqual(FiltresTextes.alerteActiveePour(frequence: .hebdomadaire), "Alerte activée pour cette recherche (chaque semaine).")
    }

    /// Décision 9 du lot 1 : textes non juridiques au vouvoiement, jamais de tutoiement résiduel.
    func testVouvoiement() {
        for (web, natif) in FiltresTextes.vouvoiements {
            XCTAssertNotEqual(web, natif)
            for marque in [" tu ", " tes ", "Ton ", " ta "] { XCTAssertFalse(natif.contains(marque), "« \(marque) » dans « \(natif) »") }
        }
    }
}
