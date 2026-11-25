import XCTest
@testable import JoleneCore

/// « Mes réclamations » (lot 4, T8) sur le monde démo (`DemoReclamationsGateway`) et sur des ports témoins : soumission
/// confirmée par la liste relue (PRINCIPES §3), statut « En attente », refus du serveur mot pour mot, erreur de lecture
/// affichée (jamais une liste vide fabriquée).
@MainActor
final class ReclamationsModelTests: XCTestCase {
    /// Port témoin : monde démo, avec une soumission ou une lecture remplacées.
    private struct PortTemoin: ReclamationsPort {
        var demo = DemoReclamationsGateway()
        var surLecture: (@Sendable () async throws -> [Reclamation])?
        var surSoumission: (@Sendable (DemoReclamationsGateway, CategorieReclamation, String, String, MissionReadContext) async throws
            -> IssueReclamation)?

        func lister(context: MissionReadContext) async throws -> [Reclamation] {
            if let surLecture { return try await surLecture() }
            return try await demo.lister(context: context)
        }

        func soumettre(categorie: CategorieReclamation, sujet: String, details: String,
                       context: MissionReadContext) async throws -> IssueReclamation {
            if let surSoumission { return try await surSoumission(demo, categorie, sujet, details, context) }
            return try await demo.soumettre(categorie: categorie, sujet: sujet, details: details, context: context)
        }
    }

    private func modele(_ port: any ReclamationsPort = DemoReclamationsGateway()) async throws -> ReclamationsModel {
        var gateways = DemoWorld.gateways()
        gateways.reclamations = port
        let controller = SessionController(gateways: gateways)
        let state = await controller.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        let model = ReclamationsModel(controller: controller, snapshot: try XCTUnwrap(state.snapshot, "session démo attendue"))
        await model.charger()
        return model
    }

    private func saisir(_ model: ReclamationsModel) {
        model.ouvrirFormulaire()
        model.choisir(.paiement)
        model.saisirSujet("  Montant à vérifier  ")
        model.saisirDetails("  Le montant affiché diffère du planning.  ")
    }

    func testListePuisSoumissionConfirmeeParLaRelecture() async throws {
        let model = try await modele()
        XCTAssertEqual(model.reclamations.map(\.id), ["demo-reclamation-001", "demo-reclamation-002"])
        XCTAssertEqual(model.reclamations.map { ReclamationsTextes.libelleStatut($0.statut) }, ["En attente", "Résolue"])
        XCTAssertEqual(ReclamationsTextes.meta(model.reclamations[0]), "Problème technique (bug, accès) · 31 oct. 2026 à 19:00")
        XCTAssertEqual(ReclamationsTextes.dateHeure(model.reclamations[1].traiteLe), "23 oct. 2026 à 02:00")

        XCTAssertFalse(model.peutEnvoyer, "feuille fermée")
        model.ouvrirFormulaire()
        XCTAssertEqual(model.categorie, .mission, "catégorie par défaut du web")
        XCTAssertFalse(model.peutEnvoyer, "sujet et détails vides")
        model.saisirSujet("   ")
        model.saisirDetails("Le montant affiché diffère du planning.")
        XCTAssertFalse(model.peutEnvoyer, "sujet vide après trim")
        saisir(model)
        XCTAssertTrue(model.peutEnvoyer)

        let envoyee = await model.envoyer()
        XCTAssertTrue(envoyee)
        XCTAssertEqual(model.confirmation, "Réclamation envoyée — nous reviendrons vers vous rapidement")
        XCTAssertFalse(model.formulaireOuvert)
        let premiere = try XCTUnwrap(model.reclamations.first)
        XCTAssertEqual(premiere, Reclamation(id: "demo-reclamation-ajout-1", categorie: "PAIEMENT", sujet: "Montant à vérifier",
                                             details: "Le montant affiché diffère du planning.", statut: "EN_ATTENTE",
                                             creeLe: "2026-11-02T00:00:00.000Z"), "sujet et détails nettoyés comme le web (trim)")
        XCTAssertEqual(ReclamationsTextes.libelleStatut(premiere.statut), "En attente")
        XCTAssertEqual(model.reclamations.count, 3)
        XCTAssertEqual([model.sujet, model.details], ["", ""], "formulaire remis à neuf")
        XCTAssertEqual(model.categorie, .mission)
    }

    func testAnnulerGardeLaSaisieCommeLeWeb() async throws {
        let model = try await modele()
        saisir(model)
        model.fermerFormulaire()
        XCTAssertFalse(model.formulaireOuvert)
        XCTAssertEqual(model.sujet, "  Montant à vérifier  ")
        XCTAssertEqual(model.categorie, .paiement)
    }

    func testRefusDuServeurMotPourMotEtContrainteEnLibelleGenerique() async throws {
        for message in ["Rôle non autorisé", ReclamationsTextes.erreurSoumission] {
            let model = try await modele(PortTemoin(surSoumission: { _, _, _, _, _ in .refusee(message: message) }))
            saisir(model)
            let envoyee = await model.envoyer()
            XCTAssertFalse(envoyee)
            XCTAssertEqual(model.erreurFormulaire, message)
            XCTAssertTrue(model.formulaireOuvert, "la feuille reste ouverte")
            XCTAssertEqual(model.sujet, "  Montant à vérifier  ", "saisie conservée")
            XCTAssertNil(model.confirmation)
        }
        let vide = try await modele(PortTemoin(surSoumission: { _, _, _, _, _ in .refusee(message: "") }))
        saisir(vide)
        _ = await vide.envoyer()
        XCTAssertEqual(vide.erreurFormulaire, "Erreur lors de la soumission", "repli du web")
    }

    func testReclamationAnnonceeMaisAbsenteDeLaRelectureJamaisUnSucces() async throws {
        let fantome = Reclamation(id: "fantome", categorie: "AUTRE", sujet: "s", statut: "EN_ATTENTE")
        let model = try await modele(PortTemoin(surSoumission: { _, _, _, _, _ in .soumise(fantome) }))
        saisir(model)
        let envoyee = await model.envoyer()
        XCTAssertFalse(envoyee)
        XCTAssertEqual(model.erreurFormulaire, ReclamationsTextes.nonConfirmee)
        XCTAssertNil(model.confirmation)
        XCTAssertEqual(model.reclamations.count, 2)
    }

    func testErreursDeTransportEtDeLecture() async throws {
        // Réponse perdue : le serveur a enregistré la réclamation. La relecture la montre : succès, sans renvoi.
        let perdue = try await modele(PortTemoin(surSoumission: { demo, categorie, sujet, details, context in
            _ = try await demo.soumettre(categorie: categorie, sujet: sujet, details: details, context: context)
            throw JoleneError(.network, "Connexion impossible.")
        }))
        saisir(perdue)
        let retrouvee = await perdue.envoyer()
        XCTAssertTrue(retrouvee, "réclamation nouvelle relue : elle fait foi")
        XCTAssertEqual(perdue.confirmation, ReclamationsTextes.envoyee)
        XCTAssertEqual(perdue.reclamations.count, 3)
        XCTAssertFalse(perdue.formulaireOuvert)

        // Requête jamais reçue : l'erreur reste dans la feuille, rien n'est renvoyé.
        let coupee = try await modele(PortTemoin(surSoumission: { _, _, _, _, _ in throw JoleneError(.network, "Connexion impossible.") }))
        saisir(coupee)
        let envoyee = await coupee.envoyer()
        XCTAssertFalse(envoyee)
        XCTAssertEqual(coupee.erreurFormulaire, "Connexion impossible.")
        XCTAssertEqual(coupee.reclamations.count, 2)
        XCTAssertTrue(coupee.formulaireOuvert)

        let expiree = try await modele(PortTemoin(surSoumission: { _, _, _, _, _ in
            throw JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")
        }))
        saisir(expiree)
        _ = await expiree.envoyer()
        XCTAssertTrue(expiree.sessionExpiree)

        let lecture = try await modele(PortTemoin(surLecture: { throw JoleneError(.network, "Connexion impossible.") }))
        XCTAssertEqual(lecture.liste, .echec(ReclamationsTextes.chargementImpossible), "jamais une liste vide fabriquée")
    }

    func testCategoriesEtStatutsDuWeb() throws {
        XCTAssertEqual(CategorieReclamation.allCases.map(\.rawValue), ["MISSION", "PAIEMENT", "COMPORTEMENT", "TECHNIQUE", "AUTRE"],
                       "ordre du sélecteur web")
        XCTAssertEqual(CategorieReclamation.allCases.map(ReclamationsTextes.libelle), [
            "Mission (annulation, litige, problème)", "Paiement (retard, montant incorrect)",
            "Comportement (soignant ou établissement)", "Problème technique (bug, accès)", "Autre",
        ])
        XCTAssertEqual(ReclamationsTextes.libelleCategorie("INCONNUE"), "INCONNUE", "catégorie inconnue : son code, comme le web")
        XCTAssertEqual(["EN_ATTENTE", "EN_COURS", "RESOLUE", "FERMEE", "AUTRE"].map(ReclamationsTextes.libelleStatut),
                       ["En attente", "En cours de traitement", "Résolue", "Fermée", "En attente"])
        let lignes = try JSONDecoder().decode([Reclamation].self, from: Data(#"[{"id":"r1","statut":null,"sujet":3}]"#.utf8))
        XCTAssertEqual(lignes, [Reclamation(id: "r1", categorie: "", sujet: "", statut: "")], "décodage tolérant")
    }
}
