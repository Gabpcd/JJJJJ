import XCTest
@testable import JoleneCore

/// Présentation de la feuille « Filtres » d'Explorer (`ExplorerFeuilleFiltres`) : chaque
/// ouverture est neuve et part des critères appliqués, « Afficher les missions » n'applique rien
/// avant la fin de la fermeture, « Fermer » (ou un glissement) n'applique rien du tout. Le parcours
/// complet est rejoué sur trois formats par `DemoExplorerTests.testFiltresSeRouvrentApresChaqueApplication`
/// et `testFermerLesFiltresNAppliqueRien`.
final class ExplorerFeuilleFiltresTests: XCTestCase {
    private func profil() -> SoignantProfile {
        SoignantProfile(id: "user-1", profession: "IDE", adresseLat: 48.8566, adresseLng: 2.3522, rayonDeplacementKm: 50,
                        tousDocumentsValides: false, typeContrat: "CDD", typesContratAcceptes: "[\"CDD\",\"LIBERAL\"]",
                        typeExercice: "MIXTE", tauxHoraireMinimum: 0)
    }

    private var initiaux: ExplorerFiltres { ExplorerFiltres.initiaux(profile: profil()) }

    private var cdd: ExplorerFiltres {
        var filtres = initiaux
        filtres.typeContrat = .cdd
        return filtres
    }

    func testFermeeAuDepartSansRienEnAttente() {
        let feuille = ExplorerFeuilleFiltres()
        XCTAssertNil(feuille.ouverture)
        XCTAssertNil(feuille.enAttente)
    }

    func testOuvrirFigeLesCriteresAppliques() {
        var feuille = ExplorerFeuilleFiltres()
        feuille.ouvrir(avec: cdd)
        XCTAssertEqual(feuille.ouverture?.filtres, cdd, "la feuille part des critères appliqués")
        XCTAssertNil(feuille.enAttente)
    }

    func testChaqueOuvertureEstUneNouvellePresentation() throws {
        // Une ouverture n'est jamais l'écriture sans effet d'une valeur déjà posée : même si la
        // précédente est restée posée (présentation refusée par UIKit), la suivante est distincte.
        var feuille = ExplorerFeuilleFiltres()
        feuille.ouvrir(avec: initiaux)
        let premiere = try XCTUnwrap(feuille.ouverture)
        feuille.ouvrir(avec: initiaux)
        let seconde = try XCTUnwrap(feuille.ouverture)
        XCTAssertNotEqual(premiere.id, seconde.id)
        XCTAssertNotEqual(premiere, seconde)
        XCTAssertEqual(premiere.filtres, seconde.filtres)
    }

    func testAfficherLesMissionsNeRendLesCriteresQuALaFermetureEtUneSeuleFois() {
        var feuille = ExplorerFeuilleFiltres()
        feuille.ouvrir(avec: initiaux)
        feuille.enregistrer(cdd)
        XCTAssertEqual(feuille.enAttente, cdd, "enregistrés, pas encore appliqués")
        // `.sheet(item:)` remet la liaison à nil, puis `onDismiss` clôture.
        feuille.ouverture = nil
        XCTAssertEqual(feuille.cloturer(), cdd)
        XCTAssertNil(feuille.enAttente)
        XCTAssertNil(feuille.cloturer(), "une seconde clôture n'applique rien de plus")
    }

    func testFermerSansAfficherNeRendRien() {
        // « Fermer », glissement vers le bas, appui hors de la feuille : rien n'est enregistré.
        var feuille = ExplorerFeuilleFiltres()
        feuille.ouvrir(avec: initiaux)
        feuille.ouverture = nil
        XCTAssertNil(feuille.cloturer())
    }

    func testLeDernierEnregistrementGagne() {
        var feuille = ExplorerFeuilleFiltres()
        feuille.ouvrir(avec: initiaux)
        feuille.enregistrer(cdd)
        feuille.enregistrer(initiaux)
        XCTAssertEqual(feuille.cloturer(), initiaux)
    }

    func testUneOuvertureEffaceUnEnregistrementEnSuspens() {
        var feuille = ExplorerFeuilleFiltres()
        feuille.ouvrir(avec: initiaux)
        feuille.enregistrer(cdd)
        feuille.ouvrir(avec: initiaux)
        XCTAssertNil(feuille.enAttente)
        feuille.ouverture = nil
        XCTAssertNil(feuille.cloturer(), "un enregistrement d'une présentation précédente n'est jamais appliqué")
    }
}
