import XCTest
@testable import JoleneCore

/// Reçu durable d'un envoi d'avatar (lot 3, T10 ; PRINCIPES §4) : graphe des phases sans retour en arrière, contrôle de
/// succession (même contrat que `RecuDurable` du lot 2), JSON versionné à clés triées, relecture stricte, aucun octet
/// d'image, aucune URL signée, description masquée.
final class RecuAvatarTests: XCTestCase {
    private let recu = RecuAvatar(userId: "u-1", attemptId: "essai-1", chemin: "u-1/avatar-1793577600000.jpg")

    func testGrapheDesPhases() throws {
        let permises: Set<String> = ["prepared>started", "prepared>not_sent", "started>stored", "started>refused",
                                     "started>not_sent", "stored>refused", "stored>not_sent"]
        for depart in RecuAvatar.Phase.allCases {
            for arrivee in RecuAvatar.Phase.allCases {
                XCTAssertEqual(RecuAvatar.transitionPermise(de: depart, vers: arrivee),
                               permises.contains("\(depart.rawValue)>\(arrivee.rawValue)"), "\(depart) → \(arrivee)")
            }
        }
        XCTAssertEqual(try recu.vers(.started).vers(.stored).phase, .stored)
        XCTAssertThrowsError(try recu.vers(.stored)) {
            XCTAssertEqual($0 as? RecuAvatar.Erreur, .transitionInterdite(de: "prepared", vers: "stored"))
        }
        XCTAssertTrue(try recu.vers(.started).vers(.refused).estTermine)
        XCTAssertTrue(try recu.vers(.notSent).estTermine)
        XCTAssertFalse(try recu.vers(.started).vers(.stored).estTermine)
    }

    func testSuccession() throws {
        XCTAssertNoThrow(try recu.verifierSuccession(apres: nil), "premier enregistrement en prepared")
        XCTAssertThrowsError(try recu.vers(.started).verifierSuccession(apres: nil)) {
            XCTAssertEqual($0 as? RecuAvatar.Erreur, .transitionInterdite(de: "absent", vers: "started"))
        }
        let enCours = try recu.vers(.started)
        XCTAssertNoThrow(try enCours.verifierSuccession(apres: recu))
        XCTAssertNoThrow(try enCours.verifierSuccession(apres: enCours), "réécriture identique")
        XCTAssertThrowsError(try recu.verifierSuccession(apres: enCours), "jamais de retour en arrière")
        let autreChemin = RecuAvatar(userId: "u-1", attemptId: "essai-1", chemin: "u-1/avatar-2.jpg", phase: .started)
        XCTAssertThrowsError(try autreChemin.verifierSuccession(apres: recu)) {
            XCTAssertEqual($0 as? RecuAvatar.Erreur, .illisible, "champ immuable modifié")
        }
    }

    func testEncodageVersionneTrieSansURLNiOctet() throws {
        let donnees = try recu.vers(.started).encoder()
        let texte = String(decoding: donnees, as: UTF8.self)
        XCTAssertEqual(texte, #"{"attempt_id":"essai-1","chemin":"u-1\/avatar-1793577600000.jpg","phase":"started","user_id":"u-1","v":1}"#)
        XCTAssertFalse(texte.contains("http") || texte.contains("token"), "ni URL signée ni jeton")
        XCTAssertEqual(try RecuAvatar.decoder(donnees, userId: "u-1"), try recu.vers(.started))
        XCTAssertEqual(RecuAvatar.domaine, "avatar")
    }

    func testRelectureStricte() throws {
        func refuse(_ json: String, _ attendu: RecuAvatar.Erreur, userId: String = "u-1", file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try RecuAvatar.decoder(Data(json.utf8), userId: userId), file: file, line: line) {
                XCTAssertEqual($0 as? RecuAvatar.Erreur, attendu, json, file: file, line: line)
            }
        }
        let valide = #"{"attempt_id":"e","chemin":"u-1/avatar-1.jpg","phase":"stored","user_id":"u-1","v":1}"#
        XCTAssertEqual(try RecuAvatar.decoder(Data(valide.utf8), userId: "u-1").phase, .stored)
        refuse(valide, .utilisateurDifferent, userId: "u-2")
        refuse(#"{"attempt_id":"e","chemin":"u-1/avatar-1.jpg","phase":"stored","user_id":"u-1","v":2}"#, .illisible)
        refuse(#"{"attempt_id":"e","chemin":"u-1/avatar-1.jpg","phase":"stored","user_id":"u-1","v":1,"url":"x"}"#, .illisible)
        refuse(#"{"attempt_id":"e","chemin":"u-1/avatar-1.jpg","phase":"inconnue","user_id":"u-1","v":1}"#, .illisible)
        refuse(#"{"attempt_id":"","chemin":"u-1/avatar-1.jpg","phase":"stored","user_id":"u-1","v":1}"#, .illisible)
        refuse(#"{"attempt_id":"e","chemin":"u-2/avatar-1.jpg","phase":"stored","user_id":"u-1","v":1}"#, .illisible)
        refuse(#"{"attempt_id":"e","chemin":"u-1/avatar-../x.jpg","phase":"stored","user_id":"u-1","v":1}"#, .illisible)
        refuse("illisible", .illisible)
    }

    func testDescriptionMasquee() throws {
        let rendu = String(describing: try recu.vers(.started).vers(.stored))
        XCTAssertEqual(rendu, "RecuAvatar(phase: stored)")
        XCTAssertFalse(rendu.contains("u-1"))
    }

    func testMagasinEnMemoire() async throws {
        let magasin = RecusAvatarEnMemoire()
        let absent = try await magasin.lire(userId: "u-1")
        XCTAssertNil(absent)
        try await magasin.ecrire(recu)
        let relu = try await magasin.lire(userId: "u-1")
        XCTAssertEqual(relu, recu)
        try await magasin.effacer(userId: "u-1")
        try await magasin.effacer(userId: "u-1")
        let efface = try await magasin.lire(userId: "u-1")
        XCTAssertNil(efface, "effacer un reçu absent n'est pas une erreur")
        await magasin.deposer(Data("altéré".utf8), userId: "u-1")
        do {
            _ = try await magasin.lire(userId: "u-1")
            XCTFail("reçu altéré relu")
        } catch {
            XCTAssertEqual(error as? RecuAvatar.Erreur, .illisible, "jamais traduit en « aucun reçu »")
        }
    }
}
