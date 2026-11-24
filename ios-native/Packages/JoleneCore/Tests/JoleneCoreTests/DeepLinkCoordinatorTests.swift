import XCTest
@testable import JoleneCore

/// Choix par espace des liens entrants (lot 5, T2b ; `docs/mobile-swift/LOT5_PLAN.md` §3 T2, §5 « Lien étab reçu dans
/// l'espace soignant », « `/contrat/:id` partagé »). La décision du coordinateur de l'app (`DeepLinkCoordinator`, cible
/// Jolene, sans tests unitaires hors XCUITest) vit dans `AiguillageLiens` (JoleneCore) : ces tests la prouvent au
/// niveau 1 ; `DemoEtabLiensTests` (XCUITest, CI) prouve l'exécution par `EtablissementTabView`.
///
/// Ce que ces tests prouvent :
/// - espace soignant : un lien établissement est un renvoi web (Safari), `/contrat/{id}` ouvre le contrat soignant ;
/// - espace établissement : un onglet est présenté dans la coquille (epoch de l'espace), un écran non livré et tout lien
///   soignant sont des renvois web, `/contrat/{id}` n'ouvre jamais l'écran soignant ;
/// - lien reçu sans espace : mémorisé puis rejoué une fois dans l'espace qui s'ouvre si l'espace établissement est
///   ouvrable (démo) ; sinon (staging, production avant T14) renvoi web présenté aussitôt, comme avant le lot 5 ;
/// - anti-boucle du renvoi affiché, fermeture de l'espace par son epoch.
@MainActor
final class DeepLinkCoordinatorTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    private func soignant(epoch: Int) -> SessionSnapshot {
        let user = AuthenticatedUser(id: "u-soignant", email: "u-soignant@example.invalid",
                                     emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000), appMetadataRole: "SOIGNANT")
        let profil = SoignantProfile(id: user.id, profession: "IDE")
        return SessionSnapshot(user: user, role: RoleResult(role: "SOIGNANT"), profile: profil,
                               context: MissionReadContext(userId: user.id, email: user.email, profile: profil), epoch: epoch)
    }

    private func etablissement(epoch: Int) -> EtablissementSessionSnapshot {
        let user = AuthenticatedUser(id: "u-etab", email: "u-etab@example.invalid",
                                     emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                     appMetadataRole: "ADMIN_ETABLISSEMENT", appMetadataEtablissementId: "etab-1")
        let contexte = EtablissementReadContext(userId: user.id, etablissementId: "etab-1", roleEtab: .proprietaire,
                                                permissions: PermissionsEtab(accordees: [.lecture]), epoch: epoch)
        return EtablissementSessionSnapshot(user: user, role: RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-1"),
                                            context: contexte, etablissement: EtablissementProfil(id: "etab-1", nom: "Clinique"))
    }

    // MARK: - Espace soignant (inchangé)

    func testLienEtablissementDansLEspaceSoignantVaVersSafari() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush(), espaceEtablissement: .ouvert)
        XCTAssertNil(aiguillage.ouvrirEspace(soignant(epoch: 3)))
        let lien = url("https://jolene.app/etablissement/missions/m-1")
        XCTAssertEqual(aiguillage.recevoir(url: lien), .renvoiWeb(.etablissement(lien)),
                       "un lien établissement n'ouvre jamais un écran établissement dans l'espace soignant")
    }

    func testContratDansLEspaceSoignantOuvreLeContratSoignant() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush(), espaceEtablissement: .ouvert)
        _ = aiguillage.ouvrirEspace(soignant(epoch: 3))
        guard case let .naviguer(_, route, epoch)? = aiguillage.recevoir(url: url("https://jolene.app/contrat/c-1")) else {
            return XCTFail("contrat soignant attendu")
        }
        XCTAssertEqual(route, .contrat(id: "c-1"))
        XCTAssertEqual(epoch, 3)
    }

    // MARK: - Espace établissement

    func testOngletsDansLEspaceEtablissement() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush(), espaceEtablissement: .ouvert)
        XCTAssertNil(aiguillage.ouvrirEspaceEtablissement(etablissement(epoch: 7)))
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/etablissement/messagerie")),
                       .naviguerEtablissement(CibleEtablissement(onglet: .messages), route: .messagerie(conversation: nil), epoch: 7))
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/etablissement/missions?statut=OUVERTE")),
                       .naviguerEtablissement(CibleEtablissement(onglet: .missions, statut: "OUVERTE"),
                                              route: .missions(statut: "OUVERTE", periode: nil), epoch: 7))
        XCTAssertEqual(aiguillage.recevoir(url: url("https://jolene.app/etablissement/dashboard")),
                       .naviguerEtablissement(CibleEtablissement(onglet: .accueil), route: .accueil, epoch: 7))
    }

    func testEcranNonLivreEtLienSoignantDansLEspaceEtablissementVontVersSafari() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush(), espaceEtablissement: .ouvert)
        _ = aiguillage.ouvrirEspaceEtablissement(etablissement(epoch: 7))
        let detail = url("https://jolene.app/etablissement/missions/m-1?source=mail")
        XCTAssertEqual(aiguillage.recevoir(url: detail),
                       .naviguerEtablissement(CibleEtablissement(onglet: .missions, destination: .detailMission(id: "m-1")),
                                              route: .missionDetail(id: "m-1"), epoch: 7), "T5 livrée : détail natif")
        let publication = url("https://jolene.app/etablissement/missions/creer?source=mail")
        XCTAssertEqual(aiguillage.recevoir(url: publication),
                       .naviguerEtablissement(CibleEtablissement(onglet: .missions, destination: .publication),
                                              route: .publierMission, epoch: 7), "T9 livrée : publication native")
        let duplication = url("https://jolene.app/etablissement/missions/creer?dupliquer=m-1")
        XCTAssertEqual(aiguillage.recevoir(url: duplication), .renvoiWeb(.etablissement(duplication)),
                       "T9 (D8) : la duplication reste sur le web")
        let presences = url("https://jolene.app/etablissement/presences/mission/m-1")
        XCTAssertEqual(aiguillage.recevoir(url: presences), .renvoiWeb(.etablissement(presences)), "T8 non livrée")
        let soignantLien = url("https://jolene.app/soignant/missions/m-1")
        XCTAssertEqual(aiguillage.recevoir(url: soignantLien), .renvoiWeb(.safari(soignantLien)),
                       "un lien soignant n'ouvre jamais l'espace soignant depuis l'espace établissement")
        let invitation = url("https://jolene.app/etab/invitation/jeton")
        XCTAssertEqual(aiguillage.recevoir(url: invitation), .renvoiWeb(.etablissement(invitation)))
    }

    func testContratDansLEspaceEtablissementNOuvreJamaisLeContratSoignant() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush(), espaceEtablissement: .ouvert)
        _ = aiguillage.ouvrirEspaceEtablissement(etablissement(epoch: 7))
        let contrat = url("https://jolene.app/contrat/c-1")
        XCTAssertEqual(aiguillage.recevoir(url: contrat), .renvoiWeb(.safari(contrat)),
                       "contrat de l'espace établissement (T10) non livré : renvoi web, jamais `ContratScreen` soignant")
        XCTAssertEqual(LinkRouter.etablissementDestination(link: contrat.absoluteString)?.route.cible?.destination,
                       .contrat(id: "c-1"))
    }

    func testRenvoiAfficheIgnoreLeMemeLienDansLEspaceEtablissement() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush(), espaceEtablissement: .ouvert)
        _ = aiguillage.ouvrirEspaceEtablissement(etablissement(epoch: 7))
        let contrat = url("https://jolene.app/contrat/c-1")
        aiguillage.renvoiWebPresente(.safari(contrat))
        XCTAssertNil(aiguillage.recevoir(url: contrat), "le renvoi affiché n'est jamais rejoué comme lien universel")
        aiguillage.renvoiWebFerme()
        XCTAssertEqual(aiguillage.recevoir(url: contrat), .renvoiWeb(.safari(contrat)))
    }

    // MARK: - Lien reçu sans espace

    func testLienEtablissementAvantLEspaceEstRejoueUneFoisSiLEspaceEstOuvrable() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush(), espaceEtablissement: .ouvert)
        XCTAssertNil(aiguillage.recevoir(url: url("https://jolene.app/etablissement/mon-compte")), "mémorisé (démo)")
        XCTAssertTrue(aiguillage.aUnLienEnAttente)
        XCTAssertEqual(aiguillage.ouvrirEspaceEtablissement(etablissement(epoch: 2)),
                       .naviguerEtablissement(CibleEtablissement(onglet: .compte), route: .monCompte, epoch: 2))
        aiguillage.fermerEspace(epoch: 2)
        XCTAssertNil(aiguillage.ouvrirEspaceEtablissement(etablissement(epoch: 3)), "rejoué une seule fois")
    }

    func testLienEtablissementMemoriseRedevientUnRenvoiDansLEspaceSoignant() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush(), espaceEtablissement: .ouvert)
        let lien = url("https://jolene.app/etablissement/presences?tab=alertes")
        XCTAssertNil(aiguillage.recevoir(url: lien))
        XCTAssertEqual(aiguillage.ouvrirEspace(soignant(epoch: 4)), .renvoiWeb(.etablissement(lien)))
    }

    func testLienSoignantAvantLEspaceRejoueDansLEspaceEtablissementEnRenvoiWeb() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush(), espaceEtablissement: .ouvert)
        let lien = url("https://jolene.app/soignant/mes-gains")
        XCTAssertNil(aiguillage.recevoir(url: lien), "lien de l'espace soignant : mémorisé (lot 3)")
        XCTAssertEqual(aiguillage.ouvrirEspaceEtablissement(etablissement(epoch: 5)), .renvoiWeb(.safari(lien)))
    }

    func testEspaceEtablissementFermeLienEtablissementResteUnRenvoiImmediat() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush()) // défaut : fermé (staging, production avant T14)
        let lien = url("https://jolene.app/etablissement/missions/m-1")
        XCTAssertEqual(aiguillage.recevoir(url: lien), .renvoiWeb(.etablissement(lien)), "comportement d'avant le lot 5")
        XCTAssertFalse(aiguillage.aUnLienEnAttente)
    }

    /// Revue B8 de #1147, m1 : un lien établissement sans route native (invitation d'équipe, renvoi web assumé) est
    /// présenté aussitôt même quand l'espace est ouvrable — un invité sans compte, ou un compte bloqué, le voit.
    func testLienEtablissementSansRouteNativeResteUnRenvoiImmediatMemeOuvrable() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush(), espaceEtablissement: .ouvert)
        for chemin in ["https://jolene.app/etab/invitation/t", "https://jolene.app/etablissement/facturation",
                       "https://jolene.app/etablissement/missions/m-1/modifier"] {
            let lien = url(chemin)
            XCTAssertEqual(aiguillage.recevoir(url: lien), .renvoiWeb(.etablissement(lien)), chemin)
            XCTAssertFalse(aiguillage.aUnLienEnAttente, "\(chemin) : jamais mémorisé")
        }
    }

    /// Revue B8 de #1147, m3 : espace fermé dans ce lancement, une ouverture d'espace établissement n'est pas suivie.
    func testOuvertureDEspaceEtablissementIgnoreeQuandLEspaceEstFerme() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush()) // défaut : fermé
        let soignantLien = url("https://jolene.app/soignant/mes-gains")
        XCTAssertNil(aiguillage.recevoir(url: soignantLien), "lien soignant mémorisé")
        XCTAssertNil(aiguillage.ouvrirEspaceEtablissement(etablissement(epoch: 2)), "aucune ouverture suivie")
        XCTAssertTrue(aiguillage.aUnLienEnAttente, "le lien en attente reste à l'espace soignant")
        let etab = url("https://jolene.app/etablissement/messagerie")
        XCTAssertEqual(aiguillage.recevoir(url: etab), .renvoiWeb(.etablissement(etab)), "aucun espace établissement ouvert")
        guard case .naviguer? = aiguillage.ouvrirEspace(soignant(epoch: 3)) else { return XCTFail("lien soignant rejoué") }
    }

    func testFermetureDeLEspaceEtablissementParSonEpoch() {
        let aiguillage = AiguillageLiens(taps: BoiteTapsPush(), espaceEtablissement: .ouvert)
        _ = aiguillage.ouvrirEspaceEtablissement(etablissement(epoch: 7))
        aiguillage.fermerEspace(epoch: 6)
        XCTAssertNotNil(aiguillage.recevoir(url: url("https://jolene.app/etablissement/messagerie")), "autre epoch : sans effet")
        aiguillage.fermerEspace(epoch: 7)
        XCTAssertNil(aiguillage.recevoir(url: url("https://jolene.app/etablissement/messagerie")), "espace fermé : mémorisé")
        XCTAssertTrue(aiguillage.aUnLienEnAttente)
    }

    func testDescriptionMasqueeDeLActionEtablissement() {
        let action = AiguillageLiens.Action.naviguerEtablissement(
            CibleEtablissement(onglet: .missions, destination: .detailMission(id: "secret")),
            route: .missionDetail(id: "secret"), epoch: 1)
        XCTAssertFalse(action.description.contains("secret"), action.description)
        XCTAssertFalse(String(describing: action).contains("secret"))
    }
}
