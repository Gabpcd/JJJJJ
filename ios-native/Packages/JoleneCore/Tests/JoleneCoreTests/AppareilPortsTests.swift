import XCTest
@testable import JoleneCore

/// Ports d'appareil du lot 2 (blueprint §2.2) : position, réseau, identifiant terminal. Ce ne sont
/// pas des gateways backend : `Appareil` est injecté par `AppContainer` à côté de `Gateways`, avec une
/// implémentation réelle (cible app, T4b ; Keychain, JoleneSupabase) et une démo (ici), sans prompt
/// système ni réseau.
final class AppareilPortsTests: XCTestCase {
    // MARK: - Identifiant terminal (décision 7)

    func testFormatDeLIdentifiantTerminal() {
        XCTAssertTrue(IdentifiantTerminal.estValide("TERM_IOS_ABCDEFGHIJKLMNOPQRST"))
        XCTAssertTrue(IdentifiantTerminal.estValide("TERM_IOS_234567ABCDEFGHIJKLMN"))
        XCTAssertTrue(IdentifiantTerminal.estValide(DemoTerminalIdentity.identifiantDemo))
        for invalide in ["TERM_IOS_abcdefghijklmnopqrst", "TERM_IOS_ABCDEFGHIJKLMNOPQRS", "TERM_IOS_ABCDEFGHIJKLMNOPQRSTU",
                         "TERM_IOS_ABCDEFGHIJKLMNOPQRS0", "TERM_IOS_ABCDEFGHIJKLMNOPQRS1", "TERM_IOS_ABCDEFGHIJKLMNOPQRS8",
                         "TERM_WEB_ABCDEFGHIJKLMNOPQRST", "ABCDEFGHIJKLMNOPQRST", "", " TERM_IOS_ABCDEFGHIJKLMNOPQRST"] {
            XCTAssertFalse(IdentifiantTerminal.estValide(invalide), invalide)
        }
        XCTAssertEqual(IdentifiantTerminal.prefixe, "TERM_IOS_")
        XCTAssertEqual(IdentifiantTerminal.alphabet, "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567", "base32 RFC 4648")
    }

    func testGenerationAleatoireBase32() {
        var aleatoire = SystemRandomNumberGenerator()
        var vus = Set<String>()
        for _ in 0..<50 {
            let id = IdentifiantTerminal.generer(using: &aleatoire)
            XCTAssertTrue(IdentifiantTerminal.estValide(id), id)
            vus.insert(id)
        }
        XCTAssertEqual(vus.count, 50, "100 bits d'aléa : aucune collision attendue")
        var fixe = SuiteFixe(valeurs: Array(0..<32).map(UInt64.init))
        XCTAssertEqual(IdentifiantTerminal.generer(using: &fixe), "TERM_IOS_ABCDEFGHIJKLMNOPQRST")
    }

    func testTerminalDemoConstant() throws {
        let terminal = DemoTerminalIdentity()
        XCTAssertEqual(try terminal.identifiant(), "TERM_IOS_DEMODEMODEMODEMODEMO")
        XCTAssertEqual(try terminal.identifiant(), try terminal.identifiant())
    }

    // MARK: - Position (démo)

    func testScenariosGpsDemo() async {
        XCTAssertEqual(ScenarioGpsDemo.allCases.map(\.rawValue), ["accorde", "refuse", "indisponible", "reduite"],
                       "valeurs de -JOLENE_DEMO_GPS (DEBUG, T4b)")
        let attendus: [(ScenarioGpsDemo, AutorisationPosition, ObservationGps)] = [
            (.accorde, .accordee(precise: true), .disponible(latitude: 48.8566, longitude: 2.3522, precisionM: 12)),
            (.refuse, .refusee, .refusee),
            (.indisponible, .accordee(precise: true), .indisponible),
            (.reduite, .accordee(precise: false), .precisionReduite),
        ]
        for (scenario, autorisation, observation) in attendus {
            let port = DemoLocationPort(scenario: scenario)
            let avant = await port.autorisation()
            XCTAssertEqual(avant, .nonDeterminee, "\(scenario) : aucune décision avant la demande")
            let sansAccord = await port.positionUnique(delai: LocationPolicy.delaiPosition)
            XCTAssertEqual(sansAccord, .refusee, "\(scenario) : jamais de position sans autorisation")
            await port.demanderAutorisation()
            let apres = await port.autorisation()
            XCTAssertEqual(apres, autorisation, "\(scenario)")
            let position = await port.positionUnique(delai: LocationPolicy.delaiPosition)
            XCTAssertEqual(position, observation, "\(scenario)")
            let demandes = await port.demandes
            XCTAssertEqual(demandes, 1, "\(scenario) : une seule demande, aucun prompt système")
        }
    }

    func testDelaiDePositionDuWeb() {
        // `src/lib/platform.ts` l.298 : `getCurrentPosition({ enableHighAccuracy: true, timeout: 15000 })`.
        XCTAssertEqual(LocationPolicy.delaiPosition, 15)
    }

    // MARK: - Réseau (démo)

    func testReseauDemo() async {
        XCTAssertEqual(ScenarioReseauDemo.horsLigne.rawValue, "horsligne", "valeur de -JOLENE_DEMO_RESEAU (DEBUG, T4b)")
        let enLigne = DemoNetworkPathPort(scenario: .enLigne)
        let horsLigne = DemoNetworkPathPort(scenario: .horsLigne)
        let a = await enLigne.estEnLigne()
        let b = await horsLigne.estEnLigne()
        XCTAssertTrue(a)
        XCTAssertFalse(b)
        var recus: [Bool] = []
        for await valeur in horsLigne.changements() { recus.append(valeur) }
        XCTAssertEqual(recus, [false], "l'état courant, puis le flux se termine : le monde démo ne change jamais de réseau")
    }

    // MARK: - Assemblage

    func testAppareilDemoParDefaut() async throws {
        let appareil = Appareil.demo()
        XCTAssertTrue(appareil.localisation is DemoLocationPort)
        XCTAssertTrue(appareil.reseau is DemoNetworkPathPort)
        // Magasin de reçus (blueprint §2.2, décision 23 : livré par T1) : en mémoire en démo, vierge à chaque monde.
        let recus = try XCTUnwrap(appareil.recus as? MagasinRecusEnMemoire)
        XCTAssertTrue(recus.cles().isEmpty)
        let cle = try XCTUnwrap(CleRecu(domaine: "scan", userId: DemoWorld.context.userId))
        try recus.ecrire(Data("{}".utf8), pour: cle)
        XCTAssertEqual(try recus.lire(cle), Data("{}".utf8))
        XCTAssertTrue(try XCTUnwrap(Appareil.demo().recus as? MagasinRecusEnMemoire).cles().isEmpty, "aucun état partagé")
        try recus.effacer(cle)
        XCTAssertNil(try recus.lire(cle))
        XCTAssertEqual(try appareil.terminal.identifiant(), DemoTerminalIdentity.identifiantDemo)
        let enLigne = await appareil.reseau.estEnLigne()
        XCTAssertTrue(enLigne)
        await appareil.localisation.demanderAutorisation()
        let position = await appareil.localisation.positionUnique(delai: LocationPolicy.delaiPosition)
        XCTAssertEqual(position, .disponible(latitude: DemoWorld.context.profile.adresseLat ?? 0,
                                             longitude: DemoWorld.context.profile.adresseLng ?? 0, precisionM: 12),
                       "position démo = adresse du profil fictif")
        let surcharge = Appareil.demo(gps: .refuse, reseau: .horsLigne)
        let horsLigne = await surcharge.reseau.estEnLigne()
        XCTAssertFalse(horsLigne)
        await surcharge.localisation.demanderAutorisation()
        let refus = await surcharge.localisation.autorisation()
        XCTAssertEqual(refus, .refusee)
    }

    func testMetadonneesDuScanReprennentLesClesDuWeb() throws {
        // `PointageRotatifSoignant.tsx` l.122-126 : `{ id_terminal }`, plus `latitude`, `longitude`, `precision_gps_m`
        // seulement quand une position est disponible (P3, forme ; décision 5 : rien en précision réduite).
        let id = "TERM_IOS_ABCDEFGHIJKLMNOPQRST"
        func cles(_ observation: ObservationGps?) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(MetadonneesScan(idTerminal: id, observation: observation)))
                as? [String: Any])
        }
        let complet = try cles(.disponible(latitude: 45.76, longitude: 4.85, precisionM: 8.5))
        XCTAssertEqual(Set(complet.keys), ["id_terminal", "latitude", "longitude", "precision_gps_m"])
        XCTAssertEqual(complet["id_terminal"] as? String, id)
        XCTAssertEqual(complet["latitude"] as? Double, 45.76)
        XCTAssertEqual(complet["longitude"] as? Double, 4.85)
        XCTAssertEqual(complet["precision_gps_m"] as? Double, 8.5)
        for observation in [ObservationGps.refusee, .indisponible, .precisionReduite, nil] {
            XCTAssertEqual(Set(try cles(observation).keys), ["id_terminal"], "\(String(describing: observation)) : aucune coordonnée")
        }
        XCTAssertEqual(MetadonneesScan(idTerminal: id, observation: .precisionReduite).gps, .reduite)
        XCTAssertEqual(MetadonneesScan(idTerminal: id, observation: nil).gps, .nonDemande)
    }

    func testMetadonneesDuScanMasquentLesCoordonneesHorsDuCorpsDeLaRequete() {
        // Revue fraîche de T1 (M6), rappelée par celle de T3 (m8) : descriptions et réflexion ne portent jamais les
        // coordonnées (rien ne doit pouvoir les journaliser ni les afficher) ; seul `encode` les écrit, pour `p_metadata`.
        let metadonnees = MetadonneesScan(idTerminal: "TERM_IOS_ABCDEFGHIJKLMNOPQRST",
                                          observation: .disponible(latitude: 45.761234, longitude: 4.851234, precisionM: 8.5))
        var vidage = ""
        dump(metadonnees, to: &vidage)
        let rendus = [String(describing: metadonnees), String(reflecting: metadonnees), "\(metadonnees)", vidage,
                      "\(Mirror(reflecting: metadonnees).children.map(\.value))"]
        let etiquettes = "\(Mirror(reflecting: metadonnees).children.compactMap(\.label))"
        for rendu in rendus + [etiquettes] {
            for valeur in ["45.76", "4.85", "8.5", "latitude", "longitude", "precision"] {
                XCTAssertFalse(rendu.contains(valeur), "« \(valeur) » exposé par « \(rendu) »")
            }
        }
        for rendu in rendus {
            XCTAssertTrue(rendu.contains("available") || rendu.contains("disponible"), "état GPS conservé : \(rendu)")
        }
        XCTAssertEqual(metadonnees.latitude, 45.761234, "valeur conservée pour le corps de la requête")
    }
}

/// Générateur déterministe : rend les valeurs dans l'ordre, puis recommence.
private struct SuiteFixe: RandomNumberGenerator {
    var valeurs: [UInt64]
    var index = 0
    mutating func next() -> UInt64 {
        defer { index = (index + 1) % valeurs.count }
        return valeurs[index]
    }
}
