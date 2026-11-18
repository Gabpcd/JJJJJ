import Foundation
import XCTest
@testable import JoleneCore

/// Reçu du justificatif d'annulation (lot 1, T7) et journal générique rejoué avec ce reçu (consigne « Lot 1 T7 » de
/// `DECISIONS_LOT2.md`) : chemin du web, graphe des phases, encodage strict, un seul essai en vol, illisible fail-closed.
final class RecuJustificatifTests: XCTestCase {
    private let userId = "demo-soignant"
    private let candidatureId = "demo-candidature-retenue-003"
    private let fichier = FichierChoisi(nom: "Billet SNCF annulé.pdf", mime: .pdf, tailleOctets: 2_048)

    private func prepare(horodatage: Int64 = 1_793_577_600_000, candidature: String? = nil) throws -> RecuJustificatif {
        try RecuJustificatif.preparer(userId: userId, candidatureId: candidature ?? candidatureId, fichier: fichier,
                                      horodatageMs: horodatage)
    }

    func testCheminDuWebEtNomAssaini() throws {
        let recu = try prepare()
        XCTAssertEqual(RecuJustificatif.domaine, "justificatif")
        XCTAssertEqual(recu.phase, .prepared)
        XCTAssertTrue(recu.chemin.hasPrefix("demo-soignant/annulations-candidature/demo-candidature-retenue-003/1793577600000_"),
                      recu.chemin)
        XCTAssertEqual(recu.chemin, "demo-soignant/annulations-candidature/demo-candidature-retenue-003/1793577600000_"
                       + ClassementDocument.sanitiserNomFichier(fichier.nom, mime: .pdf))
        XCTAssertTrue(RecuJustificatif.cheminValide(recu.chemin, userId: userId, candidatureId: candidatureId))
        XCTAssertEqual(recu.attemptId, recu.chemin)
        XCTAssertEqual(recu.nomFichier, "Billet SNCF annulé.pdf", "nom d'origine gardé pour la reprise")
    }

    func testCheminsRefuses() {
        let base = "demo-soignant/annulations-candidature/demo-candidature-retenue-003/"
        for chemin in [base + "../x.pdf", "autre/annulations-candidature/demo-candidature-retenue-003/1_a.pdf",
                       base + "1_a b.pdf", base + "sous/1_a.pdf", "demo-soignant/documents/demo-candidature-retenue-003/1_a.pdf",
                       base] {
            XCTAssertFalse(RecuJustificatif.cheminValide(chemin, userId: userId, candidatureId: candidatureId), chemin)
        }
    }

    func testBornesDuFichier() {
        let trop = FichierChoisi(nom: "a.pdf", mime: .pdf, tailleOctets: 5 * 1024 * 1024 + 1)
        XCTAssertThrowsError(try RecuJustificatif.preparer(userId: userId, candidatureId: candidatureId, fichier: trop,
                                                           horodatageMs: 1)) { erreur in
            XCTAssertEqual(erreur as? RecuErreur, .champInvalide("tailleOctets"))
        }
        XCTAssertThrowsError(try RecuJustificatif.preparer(userId: "a/b", candidatureId: candidatureId, fichier: fichier, horodatageMs: 1))
    }

    func testGrapheDesPhases() throws {
        let prepare = try prepare()
        let demarre = try prepare.demarrer()
        let stocke = try demarre.stocker()
        XCTAssertEqual(try stocke.rattacher().phase, .rattache)
        XCTAssertEqual(try stocke.abandonner().phase, .nonRattache)
        XCTAssertEqual(try prepare.marquerNonEnvoye().phase, .notSent)
        XCTAssertEqual(try demarre.marquerNonEnvoye().phase, .notSent)
        XCTAssertThrowsError(try prepare.stocker())
        XCTAssertThrowsError(try stocke.marquerNonEnvoye(), "un objet déposé n'est jamais « non envoyé »")
        XCTAssertThrowsError(try demarre.rattacher(), "jamais rattaché sans dépôt prouvé")
        for terminal in [try stocke.rattacher(), try stocke.abandonner(), try prepare.marquerNonEnvoye()] {
            XCTAssertTrue(terminal.estTermine, terminal.phase.rawValue)
        }
        XCTAssertFalse(stocke.estTermine)
        XCTAssertThrowsError(try demarre.verifierSuccession(apres: stocke)) { erreur in
            XCTAssertEqual(erreur as? RecuErreur, .transitionInterdite(de: "stored", vers: "started"))
        }
        XCTAssertThrowsError(try demarre.verifierSuccession(apres: nil)) { erreur in
            XCTAssertEqual(erreur as? RecuErreur, .transitionInterdite(de: "absent", vers: "started"))
        }
    }

    func testEncodageStrictEtUtilisateur() throws {
        let recu = try prepare().demarrer()
        let donnees = try recu.encoder()
        XCTAssertEqual(try RecuJustificatif.decoder(donnees, userId: userId), recu)
        XCTAssertThrowsError(try RecuJustificatif.decoder(donnees, userId: "autre")) { erreur in
            XCTAssertEqual(erreur as? RecuErreur, .utilisateurDifferent)
        }
        var objet = try XCTUnwrap(try JSONSerialization.jsonObject(with: donnees) as? [String: Any])
        objet["url_signee"] = "https://exemple.invalid"
        XCTAssertThrowsError(try RecuJustificatif.decoder(try JSONSerialization.data(withJSONObject: objet), userId: userId),
                             "clé inattendue : illisible")
        objet["url_signee"] = nil
        objet["version"] = 2
        XCTAssertThrowsError(try RecuJustificatif.decoder(try JSONSerialization.data(withJSONObject: objet), userId: userId),
                             "version inconnue : illisible")
        XCTAssertEqual(Set(try XCTUnwrap(try JSONSerialization.jsonObject(with: donnees) as? [String: Any]).keys),
                       ["version", "user_id", "candidature_id", "chemin", "mime", "taille_octets", "nom_fichier", "phase"],
                       "aucun octet de fichier ni URL dans le reçu")
    }

    func testJournalUnSeulEssaiEnVolPuisEffacement() async throws {
        let magasin = MagasinRecusEnMemoire()
        let journal = ReceiptJournal<RecuJustificatif>(store: magasin)
        let premier = try prepare()
        try await journal.ecrire(premier)
        try await journal.ecrire(try premier.demarrer())
        let second = try prepare(horodatage: 1_793_577_600_001)
        do {
            try await journal.ecrire(second)
            XCTFail("un second essai ne passe pas tant que le premier est en vol")
        } catch {
            XCTAssertEqual(error as? RecuErreur, .recuEnCours)
        }
        let stocke = try premier.demarrer().stocker()
        try await journal.ecrire(stocke)
        let lu = try await journal.lire(userId: userId)
        XCTAssertEqual(lu, stocke)
        try await journal.ecrire(try stocke.rattacher())
        try await journal.effacer(try stocke.rattacher())
        let vide = try await journal.lire(userId: userId)
        XCTAssertNil(vide)
        XCTAssertTrue(magasin.cles().isEmpty)
    }

    func testJournalIllisibleSansReparation() async throws {
        let magasin = MagasinRecusEnMemoire()
        let cle = try XCTUnwrap(CleRecu(domaine: RecuJustificatif.domaine, userId: userId))
        try magasin.ecrire(Data("pas du json".utf8), pour: cle)
        let journal = ReceiptJournal<RecuJustificatif>(store: magasin)
        do {
            _ = try await journal.lire(userId: userId)
            XCTFail("reçu illisible attendu")
        } catch {
            XCTAssertEqual(error as? RecuErreur, .illisible)
        }
        XCTAssertEqual(try magasin.lire(cle), Data("pas du json".utf8), "rien n'est réécrit ni effacé")
    }
}

/// Règles pures de l'annulation (lot 1, T7) : parcours ouvert comme le web, formulaire et messages du web, preuves de
/// relecture, aucun barème.
final class AnnulationRulesTests: XCTestCase {
    private func mission(statut: String = "ASSIGNEE", assigne: String? = "demo-soignant") -> MissionRecord {
        var record = DemoFixturesTestSupport.recordAssignee()
        record.statut = statut
        record.soignantAssigneId = assigne
        return record
    }

    private func candidature(_ statut: String, mission: String = "demo-assignee-003") -> CandidatureRecord {
        CandidatureRecord(id: "c-1", missionId: mission, statut: statut, message: nil, typeContratChoisi: nil, creeLe: nil)
    }

    func testEntreeCommeLeWeb() {
        let assignee = mission()
        XCTAssertEqual(AnnulationRules.entree(mission: assignee, userId: "demo-soignant", candidature: candidature("ACCEPTEE")),
                       .candidature(id: "c-1"))
        XCTAssertEqual(AnnulationRules.entree(mission: assignee, userId: "demo-soignant", candidature: nil), .mission)
        XCTAssertEqual(AnnulationRules.entree(mission: assignee, userId: "demo-soignant", candidature: candidature("EN_ATTENTE")),
                       .mission, "seule une candidature ACCEPTEE ouvre la modale (`candidatureRec`, l.486-504)")
        XCTAssertEqual(AnnulationRules.entree(mission: assignee, userId: "demo-soignant",
                                              candidature: candidature("ACCEPTEE", mission: "autre")), .mission)
        XCTAssertNil(AnnulationRules.entree(mission: mission(statut: "EN_COURS"), userId: "demo-soignant", candidature: nil),
                     "bouton seulement pour ASSIGNEE (l.1516)")
        XCTAssertNil(AnnulationRules.entree(mission: mission(assigne: "autre"), userId: "demo-soignant", candidature: nil))
        XCTAssertNil(AnnulationRules.entree(mission: mission(assigne: nil), userId: "demo-soignant", candidature: nil))
    }

    func testFormulaireEtMessagesDuWeb() {
        let vingt = String(repeating: "a", count: 20)
        XCTAssertEqual(AnnulationRules.manque(motif: nil, texte: vingt, accepte: true), "Sélectionnez un motif.")
        XCTAssertEqual(AnnulationRules.manque(motif: .deuil, texte: "  " + String(repeating: "a", count: 19) + "  ", accepte: true),
                       "Veuillez ajouter une explication (min 20 caractères).", "`texte.trim().length < 20`")
        XCTAssertEqual(AnnulationRules.manque(motif: .deuil, texte: vingt, accepte: false), "Veuillez cocher la case de confirmation.")
        XCTAssertNil(AnnulationRules.manque(motif: .deuil, texte: vingt, accepte: true))
        XCTAssertTrue(AnnulationRules.peutConfirmer(motif: .autre, texte: vingt, accepte: true))
        XCTAssertFalse(AnnulationRules.peutConfirmer(motif: .autre, texte: vingt, accepte: false))
        XCTAssertEqual(AnnulationRules.compteur("abc"), "3 / 20+")
        XCTAssertEqual(AnnulationRules.texteNettoye("\u{FEFF}  texte \n"), "texte", "`String.prototype.trim`")
        XCTAssertEqual(AnnulationRules.Motif.allCases.map(\.rawValue),
                       ["URGENCE_PERSONNELLE", "URGENCE_MEDICALE", "DEUIL", "PROBLEME_TRANSPORT", "CHANGEMENT_AVIS", "AUTRE"])
        XCTAssertEqual(AnnulationRules.Motif.changementAvis.libelle, "🤔 Changement d'avis")
    }

    func testPreuvesDeRelecture() {
        XCTAssertTrue(AnnulationRules.candidatureAnnuleeRelue(candidature("ANNULEE"), id: "c-1"))
        XCTAssertFalse(AnnulationRules.candidatureAnnuleeRelue(candidature("ACCEPTEE"), id: "c-1"))
        XCTAssertFalse(AnnulationRules.candidatureAnnuleeRelue(nil, id: "c-1"))
        XCTAssertTrue(AnnulationRules.missionAnnuleeRelue(statut: "OUVERTE", soignantAssigneId: nil, userId: "u", ligneLue: true))
        XCTAssertFalse(AnnulationRules.missionAnnuleeRelue(statut: "ASSIGNEE", soignantAssigneId: "u", userId: "u", ligneLue: true))
        XCTAssertTrue(AnnulationRules.missionAnnuleeRelue(statut: nil, soignantAssigneId: nil, userId: "u", ligneLue: false))
    }

    func testRenvoiWebDuDetailEnRouteForcee() {
        XCTAssertEqual(AnnulationRules.routeRenvoiWeb(missionId: "m-1"),
                       .safari(URL(string: "https://jolene.app/soignant/missions/m-1")!))
    }
}

/// Mission assignée de fixture, pour les tests de règles.
enum DemoFixturesTestSupport {
    static func recordAssignee() -> MissionRecord {
        // swiftlint:disable:next force_try
        try! DemoFixtures.loadDashboard().missionsAssignees.first { $0.record.id == "demo-assignee-003" }!.record
    }
}
