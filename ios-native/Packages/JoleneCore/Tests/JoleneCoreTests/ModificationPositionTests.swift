import XCTest
@testable import JoleneCore

/// Position du profil dans la différence envoyée à `fn_modifier_mon_profil` (lot 3, T10) : `p_adresse_lat` et
/// `p_adresse_lng` passent des paramètres interdits (T9) aux autorisés, toujours en paire ; `p_adresse_rue`,
/// `p_adresse_ville`, `p_adresse_code_postal` restent interdits (le web les envoie à `null`, sans effet sous `COALESCE`).
final class ModificationPositionTests: XCTestCase {
    private let profil = ProfilComplet(id: "u-1", prenom: "Léa", nom: "Martin", profession: "IDE",
                                       villeRecherche: "Paris", adresseLat: 48.8566, adresseLng: 2.3522)

    private func difference(_ modifier: (inout FormulaireProfil) -> Void) -> ModificationProfil {
        let initial = FormulaireProfil(profil: profil)
        var saisi = initial
        modifier(&saisi)
        return ModificationProfil.depuis(initial: initial, saisi: saisi, profil: profil)
    }

    func testPositionLueDansLeFormulaire() {
        let formulaire = FormulaireProfil(profil: profil)
        XCTAssertEqual(formulaire.adresseLat, 48.8566)
        XCTAssertEqual(formulaire.adresseLng, 2.3522)
        XCTAssertTrue(formulaire.positionRenseignee)
        XCTAssertFalse(FormulaireProfil(profil: ProfilComplet(id: "u-1", prenom: "", nom: "")).positionRenseignee)
        XCTAssertFalse(String(describing: formulaire).contains("48.85"), "position masquée dans la description")
    }

    func testPositionChangeeEnvoyeeEnPaire() {
        let modification = difference { $0.adresseLat = 45.7578; $0.adresseLng = 4.832 }
        XCTAssertEqual(modification.parametres, ["p_adresse_lat": .reel(45.7578), "p_adresse_lng": .reel(4.832)])
        let seuleLongitude = difference { $0.adresseLng = 4.832 }
        XCTAssertEqual(seuleLongitude.parametres, ["p_adresse_lat": .reel(48.8566), "p_adresse_lng": .reel(4.832)],
                       "une coordonnée changée : la paire part")
        XCTAssertTrue(difference { _ in }.estVide, "position inchangée : rien n'est envoyé")
        XCTAssertTrue(difference { $0.adresseLat = nil; $0.adresseLng = nil }.estVide, "jamais d'effacement (`COALESCE`)")
        XCTAssertTrue(difference { $0.adresseLat = .nan }.estVide, "coordonnée non finie jamais envoyée")
    }

    func testParametresAutorisesEtInterditsDeLAdresse() {
        for autorise in ["p_adresse_lat", "p_adresse_lng", "p_avatar_url"] {
            XCTAssertTrue(ModificationProfil.parametresAutorises.contains(autorise), autorise)
            XCTAssertFalse(ModificationProfil.parametresInterdits.contains(autorise), autorise)
        }
        for interdit in ["p_adresse_rue", "p_adresse_ville", "p_adresse_code_postal", "p_consentement_gps"] {
            XCTAssertTrue(ModificationProfil.parametresInterdits.contains(interdit), interdit)
        }
        XCTAssertEqual(ModificationProfil.parametresAutorises.count + ModificationProfil.parametresInterdits.count, 29)
        let avatar = ModificationProfil(avatarUrl: "https://x.invalid/a.jpg")
        XCTAssertEqual(avatar.parametres, ["p_avatar_url": .texte("https://x.invalid/a.jpg")])
        XCTAssertTrue(ModificationProfil(adresseLat: 45.7).parametres.isEmpty, "une coordonnée seule ne part jamais")
    }
}
