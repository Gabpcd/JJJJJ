import XCTest
@testable import JoleneCore

/// Force du nouveau mot de passe et validité du formulaire (lot 3, T11), port à l'identique de `calculerForce`
/// (`src/components/soignant/ChangementMotDePasse.tsx` l.198-208) et des dérivations l.37-40 : 12 unités UTF-16
/// minimum (`mdp.length >= 12`), classes ASCII des expressions régulières sans drapeau `u` (`/[A-Z]/`,
/// `/[a-z]/`, `/[0-9]/`, `/[^A-Za-z0-9]/`), égalité stricte `===` (unité UTF-16 par unité, sans normalisation).
final class ForceMotDePasseTests: XCTestCase {
    private func force(_ texte: String) -> ForceMotDePasse { .calculer(texte) }

    func testCinqCriteresEtScoreCommeCalculerForce() {
        XCTAssertEqual(force(""), ForceMotDePasse(longueur: false, majuscule: false, minuscule: false, chiffre: false, special: false))
        XCTAssertEqual(force("").score, 0)
        XCTAssertEqual(force("a").score, 1)
        XCTAssertEqual(force("aA").score, 2)
        XCTAssertEqual(force("aA1").score, 3)
        XCTAssertEqual(force("aA1!").score, 4)
        let complet = force("Abcdefghij1!")
        XCTAssertEqual(complet, ForceMotDePasse(longueur: true, majuscule: true, minuscule: true, chiffre: true, special: true))
        XCTAssertEqual(complet.score, 5)
        XCTAssertTrue(complet.estValide, "motDePasseValide = force.score === 5 (l.38)")
        XCTAssertFalse(force("Abcdefghi1!").estValide, "11 caractères : critère de longueur non rempli")
        XCTAssertTrue(force("Abcdefghi1!").majuscule)
        XCTAssertFalse(force("abcdefghijk1!").majuscule)
        XCTAssertEqual(ForceMotDePasse.longueurMinimale, 12)
    }

    func testLongueurEnUnitesUTF16CommeLengthJavaScript() {
        // « 😀 » vaut 2 unités UTF-16 (`'😀'.length === 2`) : six emoji font 12 unités, comme sur le web.
        XCTAssertTrue(force(String(repeating: "😀", count: 6)).longueur)
        XCTAssertFalse(force(String(repeating: "😀", count: 5) + "a").longueur, "11 unités")
        // « é » précomposé = 1 unité, décomposé (e + U+0301) = 2 unités.
        XCTAssertFalse(force(String(repeating: "é", count: 11)).longueur)
        XCTAssertTrue(force(String(repeating: "e\u{301}", count: 6)).longueur)
    }

    func testClassesASCIISeulementSansDrapeauUnicode() {
        // Lettres accentuées et chiffres non ASCII : ni majuscule, ni minuscule, ni chiffre — caractère spécial.
        let accents = force("ÉÀÇéàç١٢")
        XCTAssertFalse(accents.majuscule)
        XCTAssertFalse(accents.minuscule)
        XCTAssertFalse(accents.chiffre)
        XCTAssertTrue(accents.special, "/[^A-Za-z0-9]/ : toute unité hors ASCII alphanumérique")
        XCTAssertTrue(force(" ").special, "l'espace est un caractère spécial")
        XCTAssertTrue(force("😀").special)
        XCTAssertFalse(force("Az09").special)
        XCTAssertTrue(force("Z").majuscule && force("A").majuscule)
        XCTAssertTrue(force("z").minuscule && force("a").minuscule)
        XCTAssertTrue(force("0").chiffre && force("9").chiffre)
        // Bornes voisines des plages ASCII : « @ » (0x40), « [ » (0x5B), « ` » (0x60), « { » (0x7B), « / », « : ».
        for voisin in ["@", "[", "`", "{", "/", ":"] {
            let resultat = force(voisin)
            XCTAssertFalse(resultat.majuscule || resultat.minuscule || resultat.chiffre, voisin)
            XCTAssertTrue(resultat.special, voisin)
        }
    }

    func testCorrespondanceStricteEtFormulaireValide() {
        // `correspond = nouveauMdp.length > 0 && nouveauMdp === confirmationMdp` (l.39).
        XCTAssertFalse(MotDePasse.correspond(nouveau: "", confirmation: ""), "un nouveau mot de passe vide ne correspond jamais")
        XCTAssertTrue(MotDePasse.correspond(nouveau: "Abcdefghij1!", confirmation: "Abcdefghij1!"))
        XCTAssertFalse(MotDePasse.correspond(nouveau: "Abcdefghij1!", confirmation: "Abcdefghij1! "))
        // `===` compare les unités UTF-16 : « é » précomposé et décomposé diffèrent (Swift les dirait égaux).
        XCTAssertEqual("é", "e\u{301}", "prémisse : l'égalité Swift normalise")
        XCTAssertFalse(MotDePasse.correspond(nouveau: "Motdepasse1!é", confirmation: "Motdepasse1!e\u{301}"))

        // `formValide = ancienMdp.length > 0 && motDePasseValide && correspond` (l.40).
        XCTAssertTrue(MotDePasse.formValide(ancien: "x", nouveau: "Abcdefghij1!", confirmation: "Abcdefghij1!"))
        XCTAssertFalse(MotDePasse.formValide(ancien: "", nouveau: "Abcdefghij1!", confirmation: "Abcdefghij1!"))
        XCTAssertFalse(MotDePasse.formValide(ancien: "x", nouveau: "abcdefghij1!", confirmation: "abcdefghij1!"), "4 critères sur 5")
        XCTAssertFalse(MotDePasse.formValide(ancien: "x", nouveau: "Abcdefghij1!", confirmation: "Abcdefghij1?"))
        // L'ancien mot de passe n'est jamais rogné : une espace seule est une saisie (`length > 0`).
        XCTAssertTrue(MotDePasse.formValide(ancien: " ", nouveau: "Abcdefghij1!", confirmation: "Abcdefghij1!"))
    }

    func testRegleWebInchangee() throws {
        // Garde de dérive : la règle portée est celle du fichier web, ligne pour ligne.
        let source = try CompteVerbatimTests.lignes("src/components/soignant/ChangementMotDePasse.tsx")
        let attendues: [(Int, String)] = [
            (38, "const motDePasseValide = force.score === 5;"),
            (39, "const correspond = nouveauMdp.length > 0 && nouveauMdp === confirmationMdp;"),
            (40, "const formValide = ancienMdp.length > 0 && motDePasseValide && correspond;"),
            (200, "longueur: mdp.length >= 12,"),
            (201, "majuscule: /[A-Z]/.test(mdp),"),
            (202, "minuscule: /[a-z]/.test(mdp),"),
            (203, "chiffre: /[0-9]/.test(mdp),"),
            (204, "special: /[^A-Za-z0-9]/.test(mdp),"),
            (206, "const score = Object.values(criteres).filter(Boolean).length;"),
        ]
        for (ligne, texte) in attendues {
            XCTAssertEqual(source[ligne - 1].trimmingCharacters(in: .whitespaces), texte, "ChangementMotDePasse.tsx l.\(ligne)")
        }
    }
}
