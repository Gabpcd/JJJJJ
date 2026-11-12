import XCTest
@testable import JoleneCore

/// Thème de l'app (lot 3, T11, D16) : Système / Clair / Sombre, par appareil (clé `jolene.theme` du stockage de
/// l'appareil : `UserDefaults` en staging et production, mémoire vive en démo), défaut Système. Aucune donnée
/// de compte : le thème survit à une déconnexion et à la purge des préférences d'un compte supprimé.
@MainActor
final class PreferenceThemeTests: XCTestCase {
    func testDefautSystemeEtValeurIllisibleIgnoree() {
        XCTAssertEqual(PreferenceThemeModel(stockage: MemoireStockageAppareil()).choix, .systeme)
        XCTAssertEqual(PreferenceThemeModel(stockage: MemoireStockageAppareil(["jolene.theme": "violet"])).choix, .systeme)
        XCTAssertEqual(PreferenceThemeModel(stockage: MemoireStockageAppareil(["jolene.theme": "sombre"])).choix, .sombre)
        XCTAssertEqual(PreferenceThemeModel.cle, "jolene.theme")
    }

    func testChoixPersisteEtRelu() {
        let stockage = MemoireStockageAppareil()
        let theme = PreferenceThemeModel(stockage: stockage)
        theme.choisir(.sombre)
        XCTAssertEqual(theme.choix, .sombre)
        XCTAssertEqual(stockage.lire("jolene.theme"), "sombre")
        XCTAssertEqual(PreferenceThemeModel(stockage: stockage).choix, .sombre, "relu au lancement suivant")
        theme.choisir(.clair)
        XCTAssertEqual(PreferenceThemeModel(stockage: stockage).choix, .clair)
        theme.choisir(.systeme)
        XCTAssertEqual(stockage.lire("jolene.theme"), "systeme")
        XCTAssertEqual(PreferenceThemeModel(stockage: stockage).choix, .systeme)
    }

    func testPersistanceUserDefaults() throws {
        // Même contrat sur un vrai `UserDefaults` (domaine dédié au test, retiré ensuite).
        let domaine = "jolene.tests.theme.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domaine))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: domaine) }
        let stockage = StockageUserDefaultsTest(defaults: defaults)
        PreferenceThemeModel(stockage: stockage).choisir(.sombre)
        XCTAssertEqual(defaults.string(forKey: "jolene.theme"), "sombre")
        XCTAssertEqual(PreferenceThemeModel(stockage: stockage).choix, .sombre)
    }

    func testThemeHorsDesPreferencesDUnCompte() {
        // `CompteSuppression.purgerPreferencesLocales` ne retire que les clés portant l'identifiant du compte.
        let domaine = "jolene.tests.theme.purge.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domaine) else { return XCTFail("domaine de test") }
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: domaine) }
        defaults.set("sombre", forKey: PreferenceThemeModel.cle)
        _ = CompteSuppression.purgerPreferencesLocales(userId: "u-1", defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: PreferenceThemeModel.cle), "sombre", "le thème appartient à l'appareil")
    }

    func testOptionsDansLOrdreDeD16() {
        XCTAssertEqual(ChoixTheme.allCases, [.systeme, .clair, .sombre])
        XCTAssertEqual(ChoixTheme.allCases.map(\.rawValue), ["systeme", "clair", "sombre"])
        XCTAssertEqual(ChoixTheme(rawValue: "sombre"), .sombre)
    }
}

/// `StockageAppareilPort` sur un `UserDefaults` donné (le stockage réel de l'app vit dans la cible app).
private struct StockageUserDefaultsTest: StockageAppareilPort, @unchecked Sendable {
    let defaults: UserDefaults
    func lire(_ cle: String) -> String? { defaults.string(forKey: cle) }
    func ecrire(_ cle: String, _ valeur: String?) {
        if let valeur { defaults.set(valeur, forKey: cle) } else { defaults.removeObject(forKey: cle) }
    }
}
