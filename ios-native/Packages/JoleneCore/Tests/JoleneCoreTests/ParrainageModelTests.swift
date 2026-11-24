import Foundation
import XCTest
@testable import JoleneCore

/// Écran Parrainage (L4-T6) : lecture de `soignants` et de `fn_obtenir_mes_parrainages` (forme exacte, `public.sql`),
/// lien partagé qui ne porte que le code, textes repris de `PageParrainage.tsx`, aucun montant ni condition de prime
/// affichés (bloc T6-HS, HARD STOP n°4), monde démo (fixture `demo-parrainage.json`, refus verbatim de
/// `fn_appliquer_parrainage`).
final class ParrainageModelTests: XCTestCase {
    private static let reponse: ValeurJSON = .objet([
        "filleuls": .tableau([
            .objet(["id": .chaine("p1"), "filleul_id": .chaine("f1"), "prenom": .chaine("Inès"), "statut": .chaine("VALIDE"),
                    "cree_le": .chaine("2026-10-20T09:00:00+00:00"), "premiere_mission_le": .chaine("2026-10-25T09:00:00+00:00"),
                    "prime_versee_le": .null, "reste_gmv_avant_prime": .nombre(120), "seuil_atteint": .booleen(false)]),
            .objet(["id": .chaine("p2"), "filleul_id": .chaine("f2"), "prenom": .null, "statut": .chaine("EN_ATTENTE"),
                    "cree_le": .chaine("2026-10-28T23:30:00+00:00"), "premiere_mission_le": .null]),
            .objet(["id": .chaine("p3"), "prenom": .chaine("Sans identifiant")]),
            .objet(["id": .chaine("p4"), "filleul_id": .chaine("f4"), "prenom": .chaine("Léo"), "statut": .null]),
        ]),
        "total_gains_eur": .nombre(0), "nb_primes_versees": .nombre(0), "prime_eur": .nombre(25), "seuil_gmv_eur": .nombre(500),
        "mon_parrain": .null,
    ])

    // MARK: - Lecture

    func testDecodageDeLaFormeServeur() throws {
        let etat = try XCTUnwrap(ParrainageDecodage.etat(
            profil: .objet(["code_parrainage": .chaine("  JOLENE-DEMO "), "badge_ambassadeur": .booleen(true)]),
            reponse: Self.reponse))
        XCTAssertTrue(etat.profilPresent)
        XCTAssertEqual(etat.code, "JOLENE-DEMO", "code sans espaces de bord, comme `trim()` du web (l.68)")
        XCTAssertTrue(etat.badgeAmbassadeur)
        XCTAssertEqual(etat.filleuls.map(\.id), ["f1", "f2", "f4"], "identifiant = `filleul_id` (l.71), ligne sans id écartée")
        XCTAssertEqual(etat.filleuls[1].prenom, "Soignant", "prénom absent : « Soignant » (l.72)")
        XCTAssertEqual(etat.filleuls[2].statut, "INSCRIT", "statut absent : INSCRIT (l.75)")
        XCTAssertNil(etat.monParrain)
        XCTAssertEqual(etat.primeEur, 25, "montant serveur lu, jamais affiché par l'écran natif (T6-HS)")

        let parraine = ParrainageDecodage.etat(profil: nil, reponse: .objet([
            "filleuls": .tableau([]), "mon_parrain": .objet(["parrain_prenom": .chaine("Awa"), "statut": .chaine("EN_ATTENTE")]),
        ]))
        XCTAssertEqual(parraine?.profilPresent, false)
        XCTAssertNil(parraine?.code)
        XCTAssertEqual(parraine?.monParrain, MonParrain(prenom: "Awa", statut: "EN_ATTENTE"))
    }

    func testReponseIllisibleJamaisUnEtatVide() {
        XCTAssertNil(ParrainageDecodage.etat(profil: nil, reponse: .objet(["filleuls": .chaine("x")])),
                     "`!Array.isArray(result?.filleuls)` : erreur (l.64)")
        XCTAssertNil(ParrainageDecodage.etat(profil: nil, reponse: .tableau([])))
        XCTAssertNil(ParrainageDecodage.etat(profil: nil, reponse: .objet(["error": .chaine("x"), "filleuls": .tableau([])])))
        XCTAssertEqual(ParrainageDecodage.etat(profil: .objet(["code_parrainage": .chaine("   ")]),
                                               reponse: .objet(["filleuls": .tableau([])]))?.code, nil, "code vide : aucun lien")
    }

    // MARK: - Présentation

    func testLienPartageNePorteQueLeCode() throws {
        XCTAssertEqual(ParrainagePresentation.lien(code: "JOLENE-DEMO")?.absoluteString,
                       "https://jolene.app/inscription/soignant?ref=JOLENE-DEMO", "PageParrainage.tsx l.41")
        XCTAssertEqual(ParrainagePresentation.lien(code: "A B&c=d")?.absoluteString,
                       "https://jolene.app/inscription/soignant?ref=A%20B%26c%3Dd", "`encodeURIComponent`")
        XCTAssertNil(ParrainagePresentation.lien(code: ""))
        let lien = try XCTUnwrap(ParrainagePresentation.lien(code: "JOLENE-DEMO"))
        let composants = try XCTUnwrap(URLComponents(url: lien, resolvingAgainstBaseURL: false))
        XCTAssertEqual(composants.queryItems?.map(\.name), ["ref"], "aucun identifiant d'utilisateur, aucun jeton")
        XCTAssertNil(composants.fragment)
        XCTAssertEqual(ParrainagePresentation.messagePartage(lien: lien),
                       "Rejoignez Jolene, la plateforme de staffing médical ! Inscrivez-vous avec mon lien : "
                           + "https://jolene.app/inscription/soignant?ref=JOLENE-DEMO", "l.107-109")
    }

    func testStatutsEtCompteursDuWeb() throws {
        let etat = try XCTUnwrap(ParrainageDecodage.etat(profil: nil, reponse: Self.reponse))
        XCTAssertEqual(etat.filleuls.map { ParrainagePresentation.statut($0) }, ["1ère mission faite", "⏳ En attente", "Inscrit"],
                       "l.342-351")
        XCTAssertEqual(ParrainagePresentation.valides(etat.filleuls), 1, "VALIDE ou première mission (l.112)")
        XCTAssertEqual(ParrainagePresentation.compteurInscrits(1), "filleul inscrit")
        XCTAssertEqual(ParrainagePresentation.compteurInscrits(3), "filleuls inscrits", "l.284")
        XCTAssertEqual(ParrainagePresentation.compteurMissions(0), "mission terminée")
        XCTAssertEqual(ParrainagePresentation.compteurMissions(2), "missions terminées", "l.288")
        XCTAssertEqual(ParrainagePresentation.dateInscription(etat.filleuls[0].creeLe), "20/10/2026")
        XCTAssertEqual(ParrainagePresentation.dateInscription(etat.filleuls[1].creeLe), "29/10/2026", "jour civil de Paris")
        XCTAssertEqual(ParrainagePresentation.dateInscription(nil), "—")
    }

    /// Aucun texte de l'écran natif ne porte un montant, une condition ou une promesse de prime (T6-HS, HARD STOP n°4).
    func testAucunMontantNiConditionDePrime() {
        let textes = ParrainageTextes.tous + [ParrainagePresentation.compteurInscrits(2), ParrainagePresentation.compteurMissions(2)]
        for texte in textes {
            for interdit in ["€", "prime", "Prime", "versé", "IBAN", "500", "25", "Ambassadeur sur", "3 filleuls", "avantages"] {
                XCTAssertFalse(texte.contains(interdit), "« \(texte) » contient « \(interdit) »")
            }
        }
    }

    // MARK: - Modèle

    private struct PortTemoin: ParrainagePort {
        var etat: Result<EtatParrainage, JoleneError>
        func etat(context: MissionReadContext) async throws -> EtatParrainage { try etat.get() }
        func appliquer(code: String, context: MissionReadContext) async throws -> ApplicationParrainage { .aReessayer }
    }

    @MainActor
    private func modele(_ port: PortTemoin) async throws -> ParrainageModel {
        var gateways = DemoWorld.gateways()
        gateways.parrainage = port
        let controller = SessionController(gateways: gateways)
        let state = await controller.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        let snapshot = try XCTUnwrap(state.snapshot, "session démo prête attendue, obtenu \(state)")
        return ParrainageModel(controller: controller, snapshot: snapshot)
    }

    @MainActor
    func testChargementPuisEchecAvecLeMessageDuWeb() async throws {
        let etat = EtatParrainage(profilPresent: true, code: "ABCD", badgeAmbassadeur: false, filleuls: [], primeEur: nil,
                                  seuilGmvEur: nil, monParrain: nil)
        let pret = try await modele(PortTemoin(etat: .success(etat)))
        XCTAssertEqual(pret.etat, .chargement)
        await pret.charger()
        XCTAssertEqual(pret.etat, .pret(etat))

        let echec = try await modele(PortTemoin(etat: .failure(JoleneError(.network, "Connexion impossible."))))
        await echec.charger()
        XCTAssertEqual(echec.etat, .echec("Le parrainage est temporairement indisponible. Réessayez dans un instant."), "l.85")
        let session = try await modele(PortTemoin(etat: .failure(JoleneError(.unauthorized, "Session expirée."))))
        await session.charger()
        XCTAssertEqual(session.etat, .echec("Session expirée."), "session expirée signalée telle quelle")
    }

    // MARK: - Démo

    private func essai(_ gateway: DemoParrainageGateway, _ code: String) async throws -> ApplicationParrainage {
        try await gateway.appliquer(code: code, context: DemoWorld.context)
    }

    func testDemoFixtureEtRefusVerbatim() async throws {
        let gateway = DemoParrainageGateway()
        let etat = try await gateway.etat(context: DemoWorld.context)
        XCTAssertEqual(etat.code, "JOLENE-DEMO")
        XCTAssertTrue(etat.profilPresent)
        XCTAssertEqual(etat.filleuls.count, 3)
        XCTAssertNil(etat.monParrain)

        let invalide = try await essai(gateway, "INCONNU1")
        XCTAssertEqual(invalide, .refusDefinitif(message: "Code de parrainage invalide"))
        let soi = try await essai(gateway, "jolene-demo")
        XCTAssertEqual(soi, .refusDefinitif(message: "Vous ne pouvez pas vous parrainer vous-même"))
        let succes = try await essai(gateway, "DEMO-XYZ")
        XCTAssertEqual(succes, .appliquee)
        let relu = try await gateway.etat(context: DemoWorld.context)
        XCTAssertEqual(relu.monParrain?.prenom, "Camille", "succès relu : `mon_parrain` posé")
        let deja = try await essai(gateway, "DEMO-XYZ")
        XCTAssertEqual(deja, .refusDefinitif(message: "Vous avez déjà appliqué un code de parrainage"))
    }

    func testDemoRefuseUnAutreContexte() async {
        var autre = DemoWorld.context
        autre.userId = "00000000-0000-4000-8000-000000000001"
        autre.profile.id = autre.userId
        do {
            _ = try await DemoParrainageGateway().etat(context: autre)
            XCTFail("contexte étranger refusé")
        } catch {
            XCTAssertEqual((error as? JoleneError)?.kind, .demoOnly)
        }
    }
}
