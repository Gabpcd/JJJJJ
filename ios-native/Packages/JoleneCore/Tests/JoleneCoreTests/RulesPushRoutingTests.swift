import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/push-routing.json` : port de `navigationPathForEvent`
/// (`src/lib/pushNative.ts` l.251-315) et des 15 attentes de `src/lib/pushNative.test.ts`
/// (critère du plan l.196 : « table de routage testée unitairement sur les cas de
/// `src/lib/pushNative.test.ts` »).
final class RulesPushRoutingTests: XCTestCase {
    /// Payload tel que `send-push` le pose à la racine de l'APNs : seules les chaînes sont lues,
    /// toute autre valeur est ignorée par `valeurTexte` (`typeof value === 'string'`).
    private func payload(_ valeur: JSONValue?) throws -> [String: String] {
        guard case .object(let objet)? = valeur else {
            throw JoleneError(.contract, "vecteur sans objet data")
        }
        return objet.compactMapValues(\.string)
    }

    func testVecteursGoldenPushRouting() throws {
        let rejoues = try Golden.rejouer("push-routing") { vecteur in
            switch vecteur.fonction {
            case "navigationPathForEvent":
                let data = try payload(vecteur.input["data"])
                return .chaine(PushRouting.path(data: data, role: vecteur.input["role"]?.string))
            case "typesRoutes":
                return .array(PushRouting.typesRoutes.map(JSONValue.string))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 1_000)
    }

    func testLesQuinzeAttentesDePushNativeTestSontVectorisees() throws {
        let vitest = try Golden.charger("push-routing").filter { $0.name.hasPrefix("navigationPathForEvent/vitest-") }
        XCTAssertEqual(vitest.count, 15, "6 it, 15 attentes dans src/lib/pushNative.test.ts")
        XCTAssertEqual(Set(vitest.compactMap { $0.name.split(separator: "-").dropFirst().first }).count, 6)
    }

    func testChaqueTypeRouteEstCouvertPourChaqueRole() throws {
        let vecteurs = try Golden.charger("push-routing")
        XCTAssertEqual(PushRouting.typesRoutes.count, 32, "les 32 types des case de pushNative.ts l.263-313")
        for type in PushRouting.typesRoutes {
            let roles = Set(vecteurs.filter { $0.input["data"]?["type_evenement"]?.string == type }
                .map { $0.input["role"]?.string ?? "null" })
            XCTAssertTrue(roles.isSuperset(of: ["SOIGNANT", "ADMIN_ETABLISSEMENT", "ETABLISSEMENT", "ADMIN_PLATEFORME", "ADMIN", "null"]),
                          "\(type) : rôles couverts \(roles.sorted())")
        }
    }

    func testUserInfoAPNsNeLitQueLesChaines() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "t", "body": "b"], "sound": "default"],
            "type_evenement": "MISSION_URGENTE",
            "mission_id": NSNumber(value: 42),
            "litige_id": "l1",
        ]
        // `mission_id` numérique est ignoré comme sur le web : repli sans identifiant.
        XCTAssertEqual(PushRouting.path(userInfo: userInfo, role: "SOIGNANT"), "/soignant/missions")
        let avecLien: [AnyHashable: Any] = ["type_evenement": "PAIEMENT_RECU", "lien": " https://jolene.app/soignant/mes-gains?tab=apercu "]
        XCTAssertEqual(PushRouting.path(userInfo: avecLien, role: "SOIGNANT"), "/soignant/mes-gains?tab=apercu")
    }

    func testPaiementRecuGardeLaRouteWebMemeSansOngletNatif() {
        // Correction 15 du blueprint : l'onglet `paiements` n'existe pas sur le web ; le port garde
        // la route web à l'identique, c'est `LinkRouter`/l'écran Revenus qui choisit la section.
        XCTAssertEqual(PushRouting.path(data: ["type_evenement": "PAIEMENT_RECU"], role: "SOIGNANT"),
                       "/soignant/mes-gains?tab=paiements")
    }

    func testEspacesJavaScriptDuTrim() {
        // `String.prototype.trim` : U+FEFF et U+3000 sont retirés, U+0085 et U+180E sont conservés.
        XCTAssertEqual(PrimitivesJS.trim("\u{FEFF}\u{3000} a \u{2029}\u{A0}"), "a")
        XCTAssertEqual(PrimitivesJS.trim("\u{85}a\u{180E}"), "\u{85}a\u{180E}")
        XCTAssertEqual(PrimitivesJS.trim(" \u{301}"), "\u{301}", "le combinant reste seul, comme en UTF-16")
        XCTAssertEqual(PrimitivesJS.encodeURIComponent("m 1/2#?é😀!'()*~-_."), "m%201%2F2%23%3F%C3%A9%F0%9F%98%80!'()*~-_.")
    }
}
