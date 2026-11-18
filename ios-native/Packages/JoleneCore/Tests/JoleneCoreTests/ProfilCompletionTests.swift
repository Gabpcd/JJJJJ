import Foundation
import XCTest
@testable import JoleneCore

/// Port de `calculerCompletionProfil` (soft-gate `peut_candidater`, décision 3). Les trois premiers cas sont
/// les vecteurs de `src/lib/profil-soignant.test.ts` (profil IDE complet, adresse absente, téléphone absent).
final class ProfilCompletionTests: XCTestCase {
    /// `profilBase` du test web.
    private func profilBase() -> SoignantProfile {
        var profil = SoignantProfile(id: "u-1", profession: "IDE", adresseLat: 48.8566, adresseLng: 2.3522)
        profil.prenom = "Marie"
        profil.nom = "Lefèvre"
        profil.dateNaissance = "1990-01-01"
        profil.telephone = "0612345678"
        profil.rppsVerifie = true
        return profil
    }

    func testProfilCompletSeptSurSept() {
        let resume = ProfilCompletion.calculer(profilBase())
        XCTAssertEqual(resume.items.count, 7)
        XCTAssertEqual(resume.items.filter(\.rempli).count, 7)
        XCTAssertEqual(resume.pourcentage, 100)
        XCTAssertTrue(resume.estComplet)
        XCTAssertTrue(resume.peutCandidater)
        XCTAssertEqual(resume.items.map(\.cle), ["prenom", "nom", "date_naissance", "telephone", "rpps", "profession", "adresse"])
    }

    func testAdresseAbsenteRecommandeeSansBloquer() {
        var profil = profilBase()
        profil.adresseLat = nil
        profil.adresseLng = nil
        let resume = ProfilCompletion.calculer(profil)
        XCTAssertEqual(resume.pourcentage, 86, "6/7 arrondi comme Math.round")
        XCTAssertTrue(resume.peutCandidater)
        XCTAssertEqual(resume.recommandesManquants, ["adresse"])
    }

    func testTelephoneAbsentBloque() {
        var profil = profilBase()
        profil.telephone = nil
        let resume = ProfilCompletion.calculer(profil)
        XCTAssertFalse(resume.peutCandidater)
        XCTAssertEqual(resume.obligatoiresManquants, ["telephone"])
    }

    func testChaineVideEtCoordonneeNulleComptentCommeAbsentes() {
        var profil = profilBase()
        profil.prenom = ""
        profil.adresseLat = 0
        let resume = ProfilCompletion.calculer(profil)
        XCTAssertEqual(resume.obligatoiresManquants, ["prenom"], "`!!''` est faux")
        XCTAssertEqual(resume.recommandesManquants, ["adresse"], "`!!0` est faux")
    }

    func testProfessionsSansRppsNeComptentPasLeRpps() {
        for profession in ["AS", "AES", "AUXILIAIRE_PUERICULTURE"] {
            var profil = profilBase()
            profil.profession = profession
            profil.rppsVerifie = false
            let resume = ProfilCompletion.calculer(profil)
            XCTAssertFalse(resume.items.map(\.cle).contains("rpps"), profession)
            XCTAssertEqual(resume.items.count, 6, profession)
            XCTAssertTrue(resume.peutCandidater, profession)
        }
    }

    func testRppsNonVerifieOuProfessionVideBloque() {
        var profil = profilBase()
        profil.rppsVerifie = false
        XCTAssertEqual(ProfilCompletion.calculer(profil).obligatoiresManquants, ["rpps"])
        profil.rppsVerifie = nil
        XCTAssertEqual(ProfilCompletion.calculer(profil).obligatoiresManquants, ["rpps"])
        var sansProfession = profilBase()
        sansProfession.profession = ""
        sansProfession.rppsVerifie = false
        let resume = ProfilCompletion.calculer(sansProfession)
        XCTAssertEqual(resume.obligatoiresManquants, ["rpps"], "profession vide : RPPS toujours obligatoire")
        XCTAssertEqual(resume.recommandesManquants, ["profession"])
    }

    func testSansProfilAucuneCandidature() {
        let resume = ProfilCompletion.calculer(nil)
        XCTAssertEqual(resume.pourcentage, 0)
        XCTAssertFalse(resume.peutCandidater)
        XCTAssertTrue(resume.items.isEmpty)
        XCTAssertEqual(ProfilCompletion.totalItemsSansProfil, 7)
    }

    func testColonnesDuSoftGateDecodeesDuSelectDirect() throws {
        let json = Data("""
        {"id":"u-1","profession":"IDE","adresse_lat":null,"adresse_lng":null,"rayon_deplacement_km":null,
         "tous_documents_valides":false,"type_contrat":null,"types_contrat_acceptes":null,"type_exercice":null,
         "taux_horaire_minimum":null,"prenom":"Marie","nom":"Lefèvre","date_naissance":"1990-01-01",
         "telephone":null,"rpps_verifie":true}
        """.utf8)
        let profil = try JSONDecoder().decode(SoignantProfile.self, from: json)
        XCTAssertEqual(profil.prenom, "Marie")
        XCTAssertEqual(profil.dateNaissance, "1990-01-01")
        XCTAssertNil(profil.telephone)
        XCTAssertEqual(profil.rppsVerifie, true)
        XCTAssertEqual(ProfilCompletion.calculer(profil).obligatoiresManquants, ["telephone"])
    }
}
