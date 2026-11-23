import CoreGraphics
import XCTest

/// Pas suivant de `scrollTo` et dégagement d'un champ sous une barre de navigation, socle des tests
/// UI (`PartageUITests/PasDeDefilement.swift`, fichier compilé aussi dans JoleneUITests). Cadres
/// relevés au run 42579729412 (UI — ipad-landscape, 1180 × 820, conteneur 1180 × 736).
final class PasDeDefilementTests: XCTestCase {
    private let ecran = CGRect(x: 0, y: 0, width: 1180, height: 736)

    func testCibleAuDessusDuConteneurRemonteLaPage() {
        // `prefs-canal-sms` à y = −167,5 : il faut révéler le haut, quelle que soit la direction par défaut.
        let pas = PasDeDefilement.suivant(cible: CGRect(x: 274, y: -167.5, width: 632, height: 44), conteneur: ecran,
                                          versLaSuiteParDefaut: true)
        XCTAssertFalse(pas.versLaSuite)
        XCTAssertEqual(pas.amplitude, (736 - 44) * 0.4 / 736, accuracy: 0.0001)
    }

    func testCibleSousLeConteneurDescendDansLaPage() {
        // `revenus-retry` à y = 1061,5 dans un conteneur de 820 pt de haut.
        let conteneur = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let pas = PasDeDefilement.suivant(cible: CGRect(x: 246, y: 1061.5, width: 688, height: 48), conteneur: conteneur,
                                          versLaSuiteParDefaut: false)
        XCTAssertTrue(pas.versLaSuite)
        XCTAssertEqual(pas.amplitude, (820 - 48) * 0.4 / 820, accuracy: 0.0001)
    }

    func testCibleDansLeCadreMaisNonAtteignableRevientVersLeCentreSansLaDirectionParDefaut() {
        // Défaut corrigé (run 42579729412) : cible revenue dans le cadre du conteneur, sous la barre de
        // navigation (ou défilement inertiel en cours) ; l'ancienne règle reprenait la direction par
        // défaut (vers la suite) et la renvoyait hors du cadre, en alternance, vingt fois.
        let enHaut = PasDeDefilement.suivant(cible: CGRect(x: 274, y: 100, width: 632, height: 44), conteneur: ecran,
                                             versLaSuiteParDefaut: true)
        XCTAssertFalse(enHaut.versLaSuite, "cible dans la moitié haute : la page redescend vers elle")
        XCTAssertEqual(enHaut.amplitude, PasDeDefilement.amplitudeRecentrage)
        let enBas = PasDeDefilement.suivant(cible: CGRect(x: 274, y: 650, width: 632, height: 44), conteneur: ecran,
                                            versLaSuiteParDefaut: false)
        XCTAssertTrue(enBas.versLaSuite, "cible dans la moitié basse : la page monte vers elle")
        XCTAssertEqual(enBas.amplitude, PasDeDefilement.amplitudeRecentrage)
    }

    func testRecentrageCourtRameneLaCibleDansLaZoneVisibleSansDepasserLeCentre() {
        // Pas court : 0,15 × 736 = 110,4 pt ; une cible sous la barre (y = 100) arrive sous 240 pt.
        let deplacement = PasDeDefilement.amplitudeRecentrage * ecran.height
        XCTAssertGreaterThan(100 + deplacement, 140, "dégagée de la barre de navigation (32…140)")
        XCTAssertLessThan(100 + 44 + deplacement, ecran.midY + 44, "sans repartir de l'autre côté du centre")
    }

    func testCibleAbsenteOuSansCadreSuitLaDirectionDeRecherche() {
        XCTAssertEqual(PasDeDefilement.suivant(cible: nil, conteneur: ecran, versLaSuiteParDefaut: true),
                       PasDeDefilement(versLaSuite: true, amplitude: PasDeDefilement.amplitudeRecherche))
        XCTAssertEqual(PasDeDefilement.suivant(cible: .zero, conteneur: ecran, versLaSuiteParDefaut: false),
                       PasDeDefilement(versLaSuite: false, amplitude: PasDeDefilement.amplitudeRecherche))
    }

    func testAmplitudeBorneeEtConteneurVide() {
        // Cible plus haute que le conteneur : amplitude plancher 0,08 ; conteneur vide : direction de recherche.
        let grande = PasDeDefilement.suivant(cible: CGRect(x: 0, y: 900, width: 100, height: 800), conteneur: ecran,
                                             versLaSuiteParDefaut: false)
        XCTAssertEqual(grande, PasDeDefilement(versLaSuite: true, amplitude: 0.08))
        XCTAssertEqual(PasDeDefilement.suivant(cible: CGRect(x: 0, y: 10, width: 10, height: 10), conteneur: .zero,
                                               versLaSuiteParDefaut: true),
                       PasDeDefilement(versLaSuite: true, amplitude: PasDeDefilement.amplitudeRecherche))
    }

    // MARK: Glissement sans effet (feuille à crans, run 44797977486, UI — ipad-portrait)

    /// Cadres relus avant le premier glissement et après le quarantième : récapitulatif d'acceptation à mi-hauteur.
    private let feuille = CGRect(x: 120, y: 546, width: 580, height: 364)
    private let confirmer = CGRect(x: 154, y: 899, width: 512, height: 48)

    func testFeuilleACransLePasCalculeEstCeluiDesQuaranteGlissementsIdentiques() {
        // Cible sous le conteneur (947 > 910) : la page monte de (364 − 48) × 0,4 = 126,4 pt, de 791,2 à 664,8.
        let pas = PasDeDefilement.suivant(cible: confirmer, conteneur: feuille, versLaSuiteParDefaut: true)
        XCTAssertTrue(pas.versLaSuite)
        XCTAssertEqual(pas.amplitude * feuille.height, 126.4, accuracy: 0.01)
        XCTAssertEqual(feuille.minY + feuille.height * (0.5 + pas.amplitude / 2), 791.2, accuracy: 0.01)
        XCTAssertEqual(feuille.minY + feuille.height * (0.5 - pas.amplitude / 2), 664.8, accuracy: 0.01)
    }

    func testGlissementSansEffetCibleEtConteneurInchanges() {
        XCTAssertTrue(PasDeDefilement.sansEffet(cibleAvant: confirmer, cibleApres: confirmer,
                                                conteneurAvant: feuille, conteneurApres: feuille))
        // Arrondi au demi-point d'une relecture : toujours le même cadre.
        XCTAssertTrue(PasDeDefilement.sansEffet(cibleAvant: confirmer, cibleApres: confirmer.offsetBy(dx: 0, dy: 0.25),
                                                conteneurAvant: feuille, conteneurApres: feuille))
    }

    func testGlissementQuiDeplaceLaCibleOuLaFeuilleALEffetAttendu() {
        // Le contenu a défilé : la cible est remontée.
        XCTAssertFalse(PasDeDefilement.sansEffet(cibleAvant: confirmer, cibleApres: confirmer.offsetBy(dx: 0, dy: -126.4),
                                                 conteneurAvant: feuille, conteneurApres: feuille))
        // La feuille est passée au cran haut : le conteneur a grandi, même si la cible n'a pas bougé.
        let cranHaut = CGRect(x: 120, y: 80, width: 580, height: 1020)
        XCTAssertFalse(PasDeDefilement.sansEffet(cibleAvant: confirmer, cibleApres: confirmer,
                                                 conteneurAvant: feuille, conteneurApres: cranHaut))
    }

    func testCibleSansCadreNEstJamaisUnGlissementSansEffet() {
        // Ligne pas encore créée par une liste paresseuse : le défilement de recherche continue, sans élan.
        XCTAssertFalse(PasDeDefilement.sansEffet(cibleAvant: nil, cibleApres: nil, conteneurAvant: feuille, conteneurApres: feuille))
        XCTAssertFalse(PasDeDefilement.sansEffet(cibleAvant: .zero, cibleApres: .zero, conteneurAvant: feuille, conteneurApres: feuille))
        XCTAssertFalse(PasDeDefilement.sansEffet(cibleAvant: nil, cibleApres: confirmer, conteneurAvant: feuille, conteneurApres: feuille))
    }

    func testElanSeulementApresDeuxGlissementsSansEffetDeSuite() {
        XCTAssertEqual(PasDeDefilement.seuilSansEffet, 2)
        XCTAssertFalse(PasDeDefilement.elanRequis(glissementsSansEffet: 0))
        XCTAssertFalse(PasDeDefilement.elanRequis(glissementsSansEffet: 1), "un glissement perdu se rejoue d'abord sans élan")
        XCTAssertTrue(PasDeDefilement.elanRequis(glissementsSansEffet: 2))
        XCTAssertTrue(PasDeDefilement.elanRequis(glissementsSansEffet: 39))
    }

    func testChampRecouvertParUneBarreDeNavigation() {
        let barre = CGRect(x: 0, y: 32, width: 1180, height: 108)
        // `profil-ville-recherche` relevé sous la barre : touché sur la bande visible de 4 pt, sans focus.
        XCTAssertTrue(PasDeDefilement.recouvertParUneBarre(CGRect(x: 300, y: 104, width: 580, height: 41), barres: [barre]))
        XCTAssertFalse(PasDeDefilement.recouvertParUneBarre(CGRect(x: 300, y: 140, width: 580, height: 41), barres: [barre]),
                       "bord à bord : pas de recouvrement")
        XCTAssertFalse(PasDeDefilement.recouvertParUneBarre(CGRect(x: 300, y: 300, width: 580, height: 41), barres: [barre]))
        XCTAssertFalse(PasDeDefilement.recouvertParUneBarre(CGRect(x: 300, y: 104, width: 580, height: 41), barres: []),
                       "aucune barre atteignable (écran recouvert par une feuille) : rien à dégager")
        XCTAssertFalse(PasDeDefilement.recouvertParUneBarre(CGRect(x: 300, y: 104, width: 580, height: 41), barres: [.zero]))
    }

    // MARK: Abscisse du glissement

    /// Run 42593592247, UI — ipad-landscape (`DemoProfilTests.testPrenomVideRefuseAvecLeMessageServeur`) : les vingt
    /// glissements de `scrollTo` partaient de (590 ; 564,4), sur le curseur `profil-rayon` (262…918 × 538…569) ; le
    /// curseur captait le geste (« Rayon : 50 km », le milieu de sa piste) et la page ne défilait pas.
    func testDepartSurUnCurseurDecaleLeGlissementSurLeBordGauche() {
        let viewport = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let curseur = CGRect(x: 262, y: 538, width: 656, height: 31)
        XCTAssertEqual(PasDeDefilement.abscisseDeGlissement(viewport: viewport, departY: 564.4, obstacles: [curseur]),
                       118, accuracy: 0.001)
    }

    func testDepartLibreGardeLeMilieu() {
        let viewport = CGRect(x: 0, y: 0, width: 1180, height: 820)
        XCTAssertEqual(PasDeDefilement.abscisseDeGlissement(viewport: viewport, departY: 564.4, obstacles: []), 590)
        // Curseur loin du point de départ (au-dessus de sa zone tactile élargie) : le milieu reste libre.
        let curseur = CGRect(x: 262, y: 321, width: 656, height: 31)
        XCTAssertEqual(PasDeDefilement.abscisseDeGlissement(viewport: viewport, departY: 564.4, obstacles: [curseur]), 590)
    }

    func testZoneTactileDuCurseurPlusHauteQueSonCadre() {
        // Un `UISlider` répond au-delà de ses 31 pt de cadre : 6 pt au-dessus du cadre, le départ est encore capté.
        let viewport = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let curseur = CGRect(x: 262, y: 538, width: 656, height: 31)
        XCTAssertEqual(PasDeDefilement.abscisseDeGlissement(viewport: viewport, departY: 532, obstacles: [curseur]),
                       118, accuracy: 0.001)
    }

    func testBordGaucheAussiOccupePasseAuBordDroitPuisAuMilieu() {
        let viewport = CGRect(x: 0, y: 0, width: 402, height: 874)
        let centre = CGRect(x: 48, y: 400, width: 306, height: 31)
        let gauche = CGRect(x: 0, y: 400, width: 60, height: 31)
        XCTAssertEqual(PasDeDefilement.abscisseDeGlissement(viewport: viewport, departY: 415, obstacles: [centre, gauche]),
                       361.8, accuracy: 0.001)
        let toute = CGRect(x: 0, y: 400, width: 402, height: 31)
        XCTAssertEqual(PasDeDefilement.abscisseDeGlissement(viewport: viewport, departY: 415, obstacles: [toute]), 201,
                       "aucun couloir libre : le milieu, comme avant")
    }

    /// Run 43296363876, UI — iphone (fusion des lots 2 et 3, `DemoPhotoPositionTests.testPositionRenseigneLaVilleEnregistreeEtRelue`
    /// et `.testGeocodageSansResultatPositionRecupereeVilleInchangee`) : sur l'iPhone 17 (402 pt), le curseur `profil-rayon`
    /// (32,2…370,5 × 581,7…612,7) couvre les trois couloirs (201 ; 40,2 ; 361,8) ; les quarante glissements de
    /// `scrollTo("profil-enregistrer")` partaient de (201 ; 600,7), sur le curseur, et la page ne défilait jamais. Les
    /// gouttières des bords (hors de la piste d'un curseur pleine largeur) restent libres : la droite d'abord (le bord
    /// gauche porte le geste système de retour).
    func testCurseurPleineLargeurSurIPhonePasseALaGouttiereDroite() {
        let viewport = CGRect(x: 0, y: 0, width: 402, height: 874)
        let rayon = CGRect(x: 32.2, y: 581.7, width: 338.3, height: 31)
        XCTAssertEqual(PasDeDefilement.abscisseDeGlissement(viewport: viewport, departY: 600.7, obstacles: [rayon]),
                       390, accuracy: 0.001)
        // Gouttière droite occupée aussi (contrôle qui touche le bord droit) : la gouttière gauche.
        let droite = CGRect(x: 360, y: 581.7, width: 42, height: 31)
        XCTAssertEqual(PasDeDefilement.abscisseDeGlissement(viewport: viewport, departY: 600.7, obstacles: [rayon, droite]),
                       12, accuracy: 0.001)
    }
}
