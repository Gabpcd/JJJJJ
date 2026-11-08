import XCTest
@testable import JoleneCore

/// `formatHeures` de `src/components/planning/PlanningMissionCandidat.tsx` (l.23-25) :
/// `heures.toLocaleString('fr-FR', { maximumFractionDigits: 2 })`. Règle unique du cœur
/// (`MissionPresentation.heuresPlanning`), appelée par `JoleneDesign.SlotList` pour le résumé
/// « N créneaux · X h au total » et, à venir, par le formateur de ligne web (« · X h », T2/T6a).
///
/// Vecteurs relevés sous Node v24.14.0 (version de la CI, `Intl` fr-FR de l'ICU embarqué) avec
/// exactement l'expression du web. La fonction web est locale à un `.tsx` (JSX), donc non importable
/// par le type stripping de `scripts/mobile/export-golden-vectors.mjs` : les sorties sont versées ici
/// en dur. Commande de relevé :
/// `node -e "for (const h of [/* entrées */]) console.log(JSON.stringify([h, h.toLocaleString('fr-FR', { maximumFractionDigits: 2 })]))"`.
/// Règle : si un vecteur diverge, on corrige le port, jamais le vecteur.
final class MissionsPresentationHeuresTests: XCTestCase {
    /// (entrée, sortie Node). U+202F = espace fine insécable des milliers d'`Intl` fr-FR.
    static let vecteurs: [(Double, String)] = [
        (0, "0"), (0.25, "0,25"), (0.5, "0,5"), (1, "1"), (7.5, "7,5"), (8, "8"), (12, "12"),
        (17.5, "17,5"), (21, "21"), (24, "24"),
        // Créneaux à la minute : 7 h 20, 7 h 50, 40 min, 20 min, 10 h 05.
        (7 + 20.0 / 60, "7,33"), (7 + 50.0 / 60, "7,83"), (2.0 / 3, "0,67"), (1.0 / 3, "0,33"), (10 + 5.0 / 60, "10,08"),
        // Arrondi « moitié vers l'infini » sur le décimal le plus court de JavaScript (1.005 → 1,01, pas 1,00).
        (0.005, "0,01"), (0.015, "0,02"), (1.005, "1,01"), (2.675, "2,68"), (1.125, "1,13"), (0.125, "0,13"),
        (0.994, "0,99"), (0.995, "1"), (0.999, "1"), (99.995, "100"),
        // Milliers.
        (999.999, "1\u{202F}000"), (1000, "1\u{202F}000"), (1234.5, "1\u{202F}234,5"), (12345.678, "12\u{202F}345,68"),
        (1_000_000, "1\u{202F}000\u{202F}000"),
        (1e21, "1\u{202F}000\u{202F}000\u{202F}000\u{202F}000\u{202F}000\u{202F}000\u{202F}000"),
        (5e-7, "0"),
        // Hors domaine (une durée est bornée à 0 côté web), portés pour la fidélité : signe ASCII, « -0 ».
        (-1.5, "-1,5"), (-0.001, "-0"), (-0.0, "-0"),
    ]

    func testHeuresPlanningReproduitToLocaleStringFrFR() {
        for (entree, attendu) in Self.vecteurs {
            XCTAssertEqual(MissionPresentation.heuresPlanning(entree), attendu, "heuresPlanning(\(entree))")
        }
        XCTAssertEqual(Self.vecteurs.count, 35)
    }

    func testHeuresPlanningValeursNonFinies() {
        // Node : NaN → « NaN », Infinity → « ∞ », -Infinity → « -∞ ».
        XCTAssertEqual(MissionPresentation.heuresPlanning(.nan), "NaN")
        XCTAssertEqual(MissionPresentation.heuresPlanning(.infinity), "\u{221E}")
        XCTAssertEqual(MissionPresentation.heuresPlanning(-.infinity), "-\u{221E}")
    }

    func testHeuresPlanningNEstPasLeFormatDeFormatMission() {
        // Deux règles web distinctes : `format-mission.ts` arrondit au dixième (« 7,3 ») ;
        // `PlanningMissionCandidat.tsx` au centième, avec séparateur de milliers (« 7,33 »).
        XCTAssertEqual(FormatMission.formatHeures(7 + 20.0 / 60), "7,3")
        XCTAssertEqual(MissionPresentation.heuresPlanning(7 + 20.0 / 60), "7,33")
    }
}
