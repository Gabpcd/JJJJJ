import XCTest
@testable import JoleneCore

/// Différence de saisie envoyée à `fn_modifier_mon_profil` (lot 3, T9) : seuls les champs changés partent,
/// jamais un paramètre hors de la liste du blueprint (type d'exercice, attestation L1222-5, GPS, urgence,
/// spécialités, profession) ; `COALESCE` côté serveur : rien n'est effacé.
final class ModificationProfilTests: XCTestCase {
    private let profil = ProfilComplet(
        id: "u-1", prenom: "Léa", nom: "Martin", email: "lea@example.invalid", telephone: "0600000000",
        dateNaissance: "1990-05-14", profession: "IDE", numeroRpps: nil, rppsVerifie: false, rayonDeplacementKm: 40,
        villeRecherche: "Lyon", tauxHoraireMinimum: 30, typesContratAcceptes: ["CDD", "LIBERAL"], bio: "Bonjour",
        anneesExperience: 7)

    private var initial: FormulaireProfil { FormulaireProfil(profil: profil) }

    private func difference(_ modifier: (inout FormulaireProfil) -> Void, profil: ProfilComplet? = nil) -> ModificationProfil {
        let base = profil ?? self.profil
        var saisi = FormulaireProfil(profil: base)
        modifier(&saisi)
        return ModificationProfil.depuis(initial: FormulaireProfil(profil: base), saisi: saisi, profil: base)
    }

    func testFormulaireInitialiseCommeLeWeb() {
        // `setRayon(data.rayon_deplacement_km ?? 30)`, `setAnneesExperience(data.annees_experience || 0)`.
        let vide = FormulaireProfil(profil: ProfilComplet(id: "u-1", prenom: "", nom: ""))
        XCTAssertEqual(vide.rayonDeplacementKm, 30)
        XCTAssertEqual(vide.anneesExperience, 0)
        XCTAssertEqual(vide.telephone, "")
        XCTAssertNil(vide.dateNaissance)
        XCTAssertFalse(vide.tauxDefini)
        XCTAssertFalse(FormulaireProfil(profil: ProfilComplet(id: "u", prenom: "", nom: "", tauxHoraireMinimum: 0)).tauxDefini,
                       "0 €/h : « Non défini » comme le web")
        XCTAssertEqual(initial.typesContrat, ["CDD", "LIBERAL"])
    }

    func testAucunChangementAucunParametre() {
        XCTAssertTrue(ModificationProfil.depuis(initial: initial, saisi: initial, profil: profil).estVide)
        XCTAssertTrue(ModificationProfil.depuis(initial: initial, saisi: initial, profil: profil).parametres.isEmpty)
        // Blancs autour d'une valeur inchangée : rien à envoyer.
        XCTAssertTrue(difference { $0.villeRecherche = "  Lyon " }.estVide)
    }

    func testSeulsLesChampsChangesPartent() {
        let modification = difference {
            $0.villeRecherche = "Grenoble"
            $0.rayonDeplacementKm = 25
            $0.bio = "Infirmière de nuit"
        }
        XCTAssertEqual(modification, ModificationProfil(rayonDeplacementKm: 25, villeRecherche: "Grenoble", bio: "Infirmière de nuit"))
        XCTAssertEqual(modification.parametres, [
            "p_ville_recherche": .texte("Grenoble"), "p_rayon_deplacement_km": .entier(25), "p_bio": .texte("Infirmière de nuit"),
        ])
    }

    func testToutLeFormulaireNEnvoieQueDesParametresAutorises() {
        let modification = difference {
            $0.prenom = "Lou"; $0.nom = "Bernard"; $0.telephone = "0611111111"; $0.dateNaissance = "1991-01-02"
            $0.numeroRpps = "10101010101"; $0.rayonDeplacementKm = 60; $0.villeRecherche = "Nice"
            $0.tauxHoraireMinimum = 35; $0.typesContrat = ["CDD"]; $0.bio = "Bio"; $0.anneesExperience = 9
        }
        let noms = Set(modification.parametres.keys)
        XCTAssertEqual(noms.count, 11)
        XCTAssertTrue(noms.isSubset(of: Set(ModificationProfil.parametresAutorises)))
        XCTAssertTrue(noms.isDisjoint(with: Set(ModificationProfil.parametresInterdits)))
        for interdit in ["p_type_exercice", "p_attestation_cumul_activite", "p_consentement_gps", "p_disponible_urgence",
                         "p_profession", "p_specialites"] {
            XCTAssertTrue(ModificationProfil.parametresInterdits.contains(interdit), interdit)
        }
        XCTAssertEqual(modification.parametres["p_types_contrat"], .textes(["CDD"]))
        XCTAssertEqual(modification.parametres["p_taux_horaire_minimum"], .reel(35))
        XCTAssertEqual(modification.parametres["p_annees_experience"], .entier(9))
    }

    func testLesParametresAutorisesEtInterditsCouvrentLaSignatureSQL() throws {
        // Signature de `fn_modifier_mon_profil` (public.sql l.43891) : 29 paramètres, chacun classé une fois.
        let dump = try String(contentsOf: Lot3PortsTests.dumpURL, encoding: .utf8)
        let ligne = try XCTUnwrap(dump.split(separator: "\n").first { $0.hasPrefix("CREATE OR REPLACE FUNCTION \"public\".\"fn_modifier_mon_profil\"(") })
        let parametres = ligne.components(separatedBy: "\"p_").dropFirst().map { "p_" + $0.prefix { $0 != "\"" } }
        XCTAssertEqual(parametres.count, 29)
        XCTAssertEqual(Set(parametres), Set(ModificationProfil.parametresAutorises + ModificationProfil.parametresInterdits))
        XCTAssertTrue(Set(ModificationProfil.parametresAutorises).isDisjoint(with: Set(ModificationProfil.parametresInterdits)))
    }

    func testPrenomOuNomVidesSontEnvoyesPourQueLeServeurLesRefuse() {
        // `{error:'Le prénom ne peut pas être vide'}` (l.43906) plutôt qu'un faux succès silencieux.
        XCTAssertEqual(difference { $0.prenom = "   " }.prenom, "")
        XCTAssertEqual(difference { $0.nom = "" }.nom, "")
        XCTAssertEqual(difference { $0.prenom = "  Lou " }.prenom, "Lou")
    }

    func testUnChampVideNEffaceRien() {
        // `COALESCE` : téléphone, ville, bio, RPPS vidés ne sont pas envoyés (la relecture rend la valeur serveur).
        let modification = difference {
            $0.telephone = ""; $0.villeRecherche = " "; $0.bio = "  "; $0.numeroRpps = ""; $0.tauxHoraireMinimum = nil
        }
        XCTAssertTrue(modification.estVide)
    }

    func testIdentiteFigeeApresLeControleRpps() {
        var verifie = profil
        verifie.rppsVerifie = true
        verifie.numeroRpps = "10101010101"
        let modification = difference({
            $0.prenom = "Lou"; $0.nom = "Bernard"; $0.dateNaissance = "1991-01-02"; $0.numeroRpps = "20202020202"
            $0.villeRecherche = "Nice"
        }, profil: verifie)
        XCTAssertEqual(modification, ModificationProfil(villeRecherche: "Nice"))
    }

    func testRppsFiltreEtSeulementPourUneProfessionARpps() {
        XCTAssertEqual(FormulaireProfil.filtrerRpps("101 0101-0101 99"), "10101010101")
        XCTAssertEqual(difference { $0.numeroRpps = "1010" }.numeroRpps, "1010", "saisie partielle : le serveur contrôle")
        var aes = profil
        aes.profession = "AES"
        XCTAssertNil(difference({ $0.numeroRpps = "10101010101" }, profil: aes).numeroRpps, "AES : aucun champ RPPS")
        var aideSoignant = profil
        aideSoignant.profession = "AS"
        XCTAssertEqual(difference({ $0.numeroRpps = "10101010101" }, profil: aideSoignant).numeroRpps, "10101010101")
    }

    func testBornesDuWeb() {
        XCTAssertEqual(difference { $0.rayonDeplacementKm = 500 }.rayonDeplacementKm, 100)
        XCTAssertEqual(difference { $0.rayonDeplacementKm = 1 }.rayonDeplacementKm, 5)
        XCTAssertEqual(difference { $0.anneesExperience = 80 }.anneesExperience, 50)
        XCTAssertEqual(difference { $0.anneesExperience = 0 }.anneesExperience, 0)
        let longue = String(repeating: "a", count: 600)
        XCTAssertEqual(difference { $0.bio = longue }.bio?.count, 500)
        XCTAssertEqual(FormulaireProfil.limiterBio(longue).count, 500)
    }

    func testContratsVidesJamaisEnvoyes() {
        XCTAssertNil(difference { $0.typesContrat = [] }.typesContratAcceptes)
        XCTAssertEqual(difference { $0.typesContrat = ["CDD"] }.typesContratAcceptes, ["CDD"])
    }
}
