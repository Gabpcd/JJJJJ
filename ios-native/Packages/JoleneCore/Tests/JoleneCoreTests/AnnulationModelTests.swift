import Foundation
import XCTest
@testable import JoleneCore

/// Dépôt de justificatifs scripté : issue du dépôt et présence relue, appels comptés.
actor EspionJustificatifs: JustificatifStoragePort {
    var issueDepot: IssueDepotJustificatif = .depose
    var present: Bool?
    var erreurExiste: JoleneError?
    private(set) var depots: [String] = []
    private(set) var relectures: [String] = []

    func scripter(depot: IssueDepotJustificatif, present: Bool? = nil, erreurExiste: JoleneError? = nil) {
        issueDepot = depot
        self.present = present
        self.erreurExiste = erreurExiste
    }

    func deposer(chemin: String, octets: Data, mime: MimeDocument, context: MissionReadContext) async throws -> IssueDepotJustificatif {
        depots.append(chemin)
        return issueDepot
    }

    func existe(chemin: String, context: MissionReadContext) async throws -> Bool {
        relectures.append(chemin)
        if let erreurExiste { throw erreurExiste }
        return present ?? depots.contains(chemin)
    }
}

/// Modèle de l'annulation (lot 1, T7) sur le monde démo : parcours ouvert comme le web, formulaire du web, reçu journalisé
/// avant le dépôt, dépôt incertain réconcilié par HEAD, reprise sans second dépôt, journal illisible bloquant, issue
/// annoncée après la relecture avec les conséquences du serveur.
@MainActor
final class AnnulationModelTests: XCTestCase {
    private let pdf = Data("%PDF-1.4 billet".utf8)
    private let explication = "Train supprimé ce matin, aucun autre trajet possible."
    private let candidatureId = "demo-candidature-retenue-003"

    private var fichierPdf: FichierPret {
        FichierPret(fichier: FichierChoisi(nom: "billet.pdf", mime: .pdf, tailleOctets: pdf.count), octets: pdf)
    }

    private func pret(missionId: String = "demo-assignee-003", espion: EspionJustificatifs = EspionJustificatifs(),
                      magasin: MagasinRecusEnMemoire = MagasinRecusEnMemoire()) async throws
        -> (AnnulationModel, DemoCandidatureGateway, Mission) {
        var gateways = DemoWorld.gateways()
        let candidature = DemoCandidatureGateway()
        gateways.candidature = candidature
        gateways.justificatifs = espion
        let controller = SessionController(gateways: gateways)
        let etat = await controller.signIn(email: "demonstration@example.invalid", password: "demonstration")
        let snapshot = try XCTUnwrap(etat.snapshot)
        let lue = try await DemoMissionsGateway().mission(id: missionId, context: snapshot.context)
        let mission = try XCTUnwrap(lue)
        let model = AnnulationModel(missionId: missionId, controller: controller, snapshot: snapshot, recus: magasin)
        await model.charger(mission)
        return (model, candidature, mission)
    }

    private func journal(_ magasin: MagasinRecusEnMemoire) -> ReceiptJournal<RecuJustificatif> {
        ReceiptJournal<RecuJustificatif>(store: magasin)
    }

    func testParcoursOuvertCommeLeWeb() async throws {
        let (retenue, _, _) = try await pret()
        XCTAssertEqual(retenue.entree, .candidature(id: candidatureId))
        let (directe, _, _) = try await pret(missionId: "demo-assignee-001")
        XCTAssertEqual(directe.entree, .mission)
        let (ouverte, _, _) = try await pret(missionId: "demo-mission-001")
        XCTAssertNil(ouverte.entree, "aucun bouton hors d'une mission assignée au soignant")
    }

    func testFormulaireIncompletSansAucunAppel() async throws {
        let espion = EspionJustificatifs()
        let (model, candidature, _) = try await pret(espion: espion)
        await model.annulerCandidature(id: candidatureId, motif: nil, texte: explication, accepte: true, fichier: fichierPdf)
        XCTAssertEqual(model.issue, .erreur(message: "Sélectionnez un motif."))
        await model.annulerCandidature(id: candidatureId, motif: .deuil, texte: "trop court", accepte: true, fichier: nil)
        XCTAssertEqual(model.issue, .erreur(message: "Veuillez ajouter une explication (min 20 caractères)."))
        await model.annulerCandidature(id: candidatureId, motif: .deuil, texte: explication, accepte: false, fichier: nil)
        XCTAssertEqual(model.issue, .erreur(message: "Veuillez cocher la case de confirmation."))
        let depots = await espion.depots
        XCTAssertTrue(depots.isEmpty)
        let relue = try await candidature.candidature(missionId: "demo-assignee-003", context: DemoWorld.context)
        XCTAssertEqual(relue?.statut, "ACCEPTEE", "rien n'est envoyé")
    }

    func testAnnulationAvecJustificatifJournaliseDeposeRattache() async throws {
        let espion = EspionJustificatifs()
        let magasin = MagasinRecusEnMemoire()
        let (model, candidature, _) = try await pret(espion: espion, magasin: magasin)
        await model.annulerCandidature(id: candidatureId, motif: .problemeTransport, texte: "  " + explication + " ",
                                       accepte: true, fichier: fichierPdf)
        XCTAssertEqual(model.issue, .annulee(message: "Candidature annulée."), "0 point serveur : « Candidature annulée. »")
        XCTAssertNil(model.entree, "le bouton disparaît après l'annulation relue")
        let depots = await espion.depots
        XCTAssertEqual(depots, ["demo-soignant/annulations-candidature/demo-candidature-retenue-003/1793577600000_billet.pdf"])
        let transmis = await candidature.justificatifTransmis(candidatureId: candidatureId)
        XCTAssertEqual(transmis, depots.first, "le chemin du reçu est celui transmis à la RPC")
        let restant = try await journal(magasin).lire(userId: DemoWorld.context.userId)
        XCTAssertNil(restant, "reçu rattaché puis effacé")
    }

    func testDepotRefuseNonEnvoyeEtAucuneAnnulation() async throws {
        let espion = EspionJustificatifs()
        await espion.scripter(depot: .refuse(statut: 403))
        let magasin = MagasinRecusEnMemoire()
        let (model, candidature, _) = try await pret(espion: espion, magasin: magasin)
        await model.annulerCandidature(id: candidatureId, motif: .autre, texte: explication, accepte: true, fichier: fichierPdf)
        XCTAssertEqual(model.issue, .erreur(message: LibellesAnnulation.depotImpossible))
        let recu = try await journal(magasin).lire(userId: DemoWorld.context.userId)
        XCTAssertEqual(recu?.phase, .notSent, "403 → not_sent")
        let relue = try await candidature.candidature(missionId: "demo-assignee-003", context: DemoWorld.context)
        XCTAssertEqual(relue?.statut, "ACCEPTEE", "aucune annulation sans le justificatif choisi")
    }

    func testDepotIncertainReconcilieParHEADSansSecondDepot() async throws {
        let espion = EspionJustificatifs()
        await espion.scripter(depot: .incertain, present: true)
        let (model, candidature, _) = try await pret(espion: espion)
        await model.annulerCandidature(id: candidatureId, motif: .autre, texte: explication, accepte: true, fichier: fichierPdf)
        XCTAssertEqual(model.issue, .annulee(message: "Candidature annulée."))
        let depots = await espion.depots
        let relectures = await espion.relectures
        XCTAssertEqual(depots.count, 1, "jamais redéposé")
        XCTAssertEqual(relectures, depots, "une relecture du même chemin")
        let transmis = await candidature.justificatifTransmis(candidatureId: candidatureId)
        XCTAssertEqual(transmis, depots.first)
    }

    func testDepotIncertainNonVerifieResteEnVolPuisRepriseSansDoublon() async throws {
        let espion = EspionJustificatifs()
        await espion.scripter(depot: .incertain, erreurExiste: JoleneError(.network, "hors ligne"))
        let magasin = MagasinRecusEnMemoire()
        let (model, candidature, _) = try await pret(espion: espion, magasin: magasin)
        await model.annulerCandidature(id: candidatureId, motif: .autre, texte: explication, accepte: true, fichier: fichierPdf)
        XCTAssertEqual(model.issue, .erreur(message: LibellesAnnulation.depotIncertain))
        let enVol = try await journal(magasin).lire(userId: DemoWorld.context.userId)
        XCTAssertEqual(enVol?.phase, .started, "le reçu reste en vol, rien n'est renvoyé")
        // Reprise (réouverture de la modale) : le HEAD prouve l'objet, la confirmation le reprend sans le redéposer.
        await espion.scripter(depot: .depose, present: true)
        await model.preparerJustificatif(candidatureId: candidatureId)
        XCTAssertEqual(model.justificatifDejaDepose, "billet.pdf")
        await model.annulerCandidature(id: candidatureId, motif: .autre, texte: explication, accepte: true, fichier: nil)
        XCTAssertEqual(model.issue, .annulee(message: "Candidature annulée."))
        let depots = await espion.depots
        XCTAssertEqual(depots.count, 1, "pas de doublon à la reprise")
        let transmis = await candidature.justificatifTransmis(candidatureId: candidatureId)
        XCTAssertEqual(transmis, enVol?.chemin)
    }

    func testArretForceAvantLeDepotObjetAbsentNonEnvoye() async throws {
        let magasin = MagasinRecusEnMemoire()
        let fichier = FichierChoisi(nom: "billet.pdf", mime: .pdf, tailleOctets: 4)
        let prepare = try RecuJustificatif.preparer(userId: DemoWorld.context.userId, candidatureId: candidatureId, fichier: fichier,
                                                    horodatageMs: 1)
        try await journal(magasin).ecrire(prepare)
        try await journal(magasin).ecrire(try prepare.demarrer())
        let espion = EspionJustificatifs()
        await espion.scripter(depot: .depose, present: false)
        let (model, _, _) = try await pret(espion: espion, magasin: magasin)
        await model.preparerJustificatif(candidatureId: candidatureId)
        XCTAssertNil(model.justificatifDejaDepose, "objet absent : nouvelle sélection")
        let recu = try await journal(magasin).lire(userId: DemoWorld.context.userId)
        XCTAssertEqual(recu?.phase, .notSent)
    }

    func testJustificatifDUneAutreCandidatureAbandonne() async throws {
        let magasin = MagasinRecusEnMemoire()
        let fichier = FichierChoisi(nom: "billet.pdf", mime: .pdf, tailleOctets: 4)
        let autre = try RecuJustificatif.preparer(userId: DemoWorld.context.userId, candidatureId: "demo-autre", fichier: fichier,
                                                  horodatageMs: 1)
        try await journal(magasin).ecrire(autre)
        try await journal(magasin).ecrire(try autre.demarrer())
        try await journal(magasin).ecrire(try autre.demarrer().stocker())
        let (model, _, _) = try await pret(magasin: magasin)
        await model.preparerJustificatif(candidatureId: candidatureId)
        XCTAssertNil(model.justificatifDejaDepose)
        let recu = try await journal(magasin).lire(userId: DemoWorld.context.userId)
        XCTAssertEqual(recu?.phase, .nonRattache)
    }

    func testJournalIllisibleBloqueLeJustificatifSansRien() async throws {
        let magasin = MagasinRecusEnMemoire()
        let cle = try XCTUnwrap(CleRecu(domaine: RecuJustificatif.domaine, userId: DemoWorld.context.userId))
        try magasin.ecrire(Data("illisible".utf8), pour: cle)
        let espion = EspionJustificatifs()
        let (model, candidature, _) = try await pret(espion: espion, magasin: magasin)
        await model.preparerJustificatif(candidatureId: candidatureId)
        XCTAssertEqual(model.issue, .bloquee(message: LibellesAnnulation.suiviIllisible))
        await model.annulerCandidature(id: candidatureId, motif: .autre, texte: explication, accepte: true, fichier: fichierPdf)
        XCTAssertEqual(model.issue, .bloquee(message: LibellesAnnulation.suiviIllisible))
        // Revue B8 de #1156, m7 : même sans justificatif, rien ne part depuis la modale ; la voie est le web.
        await model.annulerCandidature(id: candidatureId, motif: .autre, texte: explication, accepte: true, fichier: nil)
        XCTAssertEqual(model.issue, .bloquee(message: LibellesAnnulation.suiviIllisible))
        let depots = await espion.depots
        XCTAssertTrue(depots.isEmpty)
        let relue = try await candidature.candidature(missionId: "demo-assignee-003", context: DemoWorld.context)
        XCTAssertEqual(relue?.statut, "ACCEPTEE")
        XCTAssertEqual(try magasin.lire(cle), Data("illisible".utf8), "le reçu n'est jamais réécrit")
    }

    /// Revue B8 de #1156, m2 : réponse perdue alors que le serveur avait annulé ; le nouvel essai rend `STATUT_INVALIDE`,
    /// la candidature est relue `ANNULEE` avant tout message : annulation relue, reçu `stored` rattaché, aucun nouveau dépôt.
    func testStatutInvalideRelueAnnuleeAnnonceLAnnulation() async throws {
        let espion = EspionJustificatifs()
        let magasin = MagasinRecusEnMemoire()
        let (model, candidature, _) = try await pret(espion: espion, magasin: magasin)
        let fichier = FichierChoisi(nom: "billet.pdf", mime: .pdf, tailleOctets: 4)
        var recu = try RecuJustificatif.preparer(userId: DemoWorld.context.userId, candidatureId: candidatureId, fichier: fichier,
                                                 horodatageMs: 1)
        try await journal(magasin).ecrire(recu)
        recu = try recu.demarrer()
        try await journal(magasin).ecrire(recu)
        recu = try recu.stocker()
        try await journal(magasin).ecrire(recu)
        _ = try await candidature.annulerCandidature(id: candidatureId, motif: "AUTRE", texte: explication,
                                                     justificatifPath: recu.chemin, context: DemoWorld.context)
        await model.preparerJustificatif(candidatureId: candidatureId)
        XCTAssertEqual(model.justificatifDejaDepose, "billet.pdf")
        await model.annulerCandidature(id: candidatureId, motif: .autre, texte: explication, accepte: true, fichier: nil)
        XCTAssertEqual(model.issue, .annulee(message: "Candidature annulée."))
        XCTAssertNil(model.entree)
        let depots = await espion.depots
        XCTAssertTrue(depots.isEmpty, "aucun nouveau dépôt")
        let restant = try await journal(magasin).lire(userId: DemoWorld.context.userId)
        XCTAssertNil(restant, "reçu clos puis effacé")
    }

    func testStatutInvalideNonAnnuleeResteUnRefusVerbatim() async throws {
        // Proposition de l'Accueil, `PROPOSEE` : refus `STATUT_INVALIDE` relu non annulé → message du serveur tel quel.
        let (model, _, _) = try await pret()
        await model.annulerCandidature(id: "demo-proposition-001", motif: .autre, texte: explication, accepte: true, fichier: nil)
        XCTAssertEqual(model.issue, .erreur(message: "Candidature pas dans un état annulable (statut : PROPOSEE)"))
    }

    func testAnnulationSansCandidatureMessageDuWeb() async throws {
        let (model, candidature, mission) = try await pret(missionId: "demo-assignee-001")
        await model.annulerMission()
        XCTAssertEqual(model.issue, .annulee(message: "Participation annulée. Ton score sera mis à jour."))
        XCTAssertNil(model.entree)
        let annulee = await candidature.missionAnnulee("demo-assignee-001")
        XCTAssertTrue(annulee)
        await model.charger(mission)
        XCTAssertNil(model.entree, "un rechargement ne fait pas revenir le bouton")
        await model.annulerMission()
        XCTAssertEqual(model.issue, .erreur(message: "Cette mission ne vous est pas assignée"))
    }

    /// Revue B8 delta de #1156 (m1), intégration de la vague B : l'annulation sans candidature a abouti côté serveur mais
    /// sa réponse s'est perdue ; le nouvel essai est refusé. La mission est relue avant tout message : remise en ligne
    /// (sans le soignant de la session), c'est une annulation relue, jamais un refus qui oriente vers un litige.
    func testRefusApresReponsePerdueRelitLaMissionEtAnnonceLAnnulation() async throws {
        let gateways = DemoWorld.gateways() // candidature et missions du même monde démo : l'annulation est relue
        let controller = SessionController(gateways: gateways)
        let etat = await controller.signIn(email: "demonstration@example.invalid", password: "demonstration")
        let snapshot = try XCTUnwrap(etat.snapshot)
        let lue = try await gateways.missions.mission(id: "demo-assignee-001", context: snapshot.context)
        let avant = try XCTUnwrap(lue)
        XCTAssertTrue(AnnulationRules.annulable(avant.record, userId: snapshot.context.userId))
        // Réponse perdue : le serveur simulé a annulé, l'écran ne l'a pas su.
        _ = try await gateways.candidature.annulerMission(id: "demo-assignee-001", motif: nil, context: snapshot.context)
        let model = AnnulationModel(missionId: "demo-assignee-001", controller: controller, snapshot: snapshot)
        await model.charger(avant)
        XCTAssertNotNil(model.entree, "l'écran affiche encore la mission assignée")
        await model.annulerMission()
        XCTAssertEqual(model.issue, .annulee(message: "Participation annulée. Ton score sera mis à jour."))
        XCTAssertNil(model.entree)
    }

    /// Lecture de la mission en échec (`mission(id:)`), le reste délégué.
    private struct MissionsEnPanne: MissionsPort {
        let base: MissionsPort
        func profile(userId: String) async throws -> SoignantProfile? { try await base.profile(userId: userId) }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] {
            try await base.listMissions(context: context, filters: filters)
        }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? {
            throw JoleneError(.network, "Le service ne répond pas.")
        }
    }

    /// Revue B8 de #1158 (m4) : si la relecture qui suit un refus échoue, le refus du serveur s'affiche tel quel, jamais
    /// l'erreur réseau de la relecture.
    func testRefusPuisRelectureEnEchecAfficheLeRefusDuServeur() async throws {
        var gateways = DemoWorld.gateways()
        gateways.missions = MissionsEnPanne(base: gateways.missions)
        let controller = SessionController(gateways: gateways)
        let etat = await controller.signIn(email: "demonstration@example.invalid", password: "demonstration")
        let snapshot = try XCTUnwrap(etat.snapshot)
        let lue = try await DemoMissionsGateway().mission(id: "demo-assignee-001", context: snapshot.context)
        let avant = try XCTUnwrap(lue)
        // Annulation déjà faite côté serveur simulé : le nouvel essai est refusé, la relecture échoue.
        _ = try await gateways.candidature.annulerMission(id: "demo-assignee-001", motif: nil, context: snapshot.context)
        let model = AnnulationModel(missionId: "demo-assignee-001", controller: controller, snapshot: snapshot)
        await model.charger(avant)
        await model.annulerMission()
        XCTAssertEqual(model.issue, .erreur(message: "Cette mission ne vous est pas assignée"))
    }
}
