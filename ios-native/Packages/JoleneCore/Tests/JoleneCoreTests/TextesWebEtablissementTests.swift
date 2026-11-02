import XCTest
@testable import JoleneCore

/// Textes du lot 5 (espace établissement) repris verbatim du web dans `Legal/TextesWeb.swift`
/// (LOT5_PLAN §2.9, D30, HARD STOP n°4). L'égalité au caractère près avec le web est prouvée par
/// la garde Node `tests/node/textes-juridiques-ios.node.mjs` (TL du lot 2) ; ce test vérifie la
/// présence au catalogue et l'assemblage de la mention CGV tel que React la rend.
final class TextesWebEtablissementTests: XCTestCase {
    func testTextesDuLot5AuCatalogue() {
        let cles = Set(TextesWeb.catalogue.map(\.cle))
        for cle in [
            "CandidaturesEtablissement.cgvAvantLien",
            "CandidaturesEtablissement.cgvCheminLien",
            "CandidaturesEtablissement.cgvLien",
            "CandidaturesEtablissement.cgvApresLien",
            "BlocageEtablissement.publicationSuspendue",
            "BlocageEtablissement.verificationEnCoursTitre",
            "BlocageEtablissement.verificationEnCoursDetail",
            "PublicationEtablissement.optionSalarieLibelle",
            "PublicationEtablissement.optionSalarieDescription",
        ] {
            XCTAssertTrue(cles.contains(cle), cle)
        }
    }

    /// `ListeCandidatures.tsx` l.393-397 : texte, `{' '}`, lien, puis « . Elles précisent… » collé
    /// au lien (aucune espace avant le point).
    func testMentionCgvRendueCommeLeWeb() {
        let mention = TextesWeb.CandidaturesEtablissement.cgvMention
        XCTAssertEqual(
            mention,
            TextesWeb.CandidaturesEtablissement.cgvAvantLien + " " + TextesWeb.CandidaturesEtablissement.cgvLien
                + TextesWeb.CandidaturesEtablissement.cgvApresLien
        )
        XCTAssertTrue(mention.contains("direct — CGV art. 8. Elles précisent"))
        XCTAssertFalse(mention.contains("  "))
        XCTAssertEqual(TextesWeb.CandidaturesEtablissement.cgvCheminLien, "/cgv#art8")
    }

    /// La mention OTP « Conforme art. 1366-1367 Code civil » de l'écran de signature est celle du
    /// lot 2 (`Contrat.otpDescription`) : le lot 5 ne la duplique pas.
    func testMentionSignatureOtpHeriteeDuLot2() {
        let textes = TextesWeb.catalogue.filter { $0.texte == TextesWeb.Contrat.otpDescription }
        XCTAssertEqual(textes.map(\.cle), ["Contrat.otpDescription"])
    }
}
