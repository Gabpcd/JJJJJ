import XCTest
@testable import JoleneCore

/// Boîte verrouillée (doubles de test partagés entre le main actor et les ports).
final class Verrouille<Valeur>: @unchecked Sendable {
    private let verrou = NSLock()
    private var valeur: Valeur
    init(_ valeur: Valeur) { self.valeur = valeur }
    var lire: Valeur { verrou.lock(); defer { verrou.unlock() }; return valeur }
    func modifier(_ action: (inout Valeur) -> Void) { verrou.lock(); action(&valeur); verrou.unlock() }
}

/// Port documents espion : délègue au monde démo, journalise chaque appel et relit le journal de reçus au moment
/// exact de l'envoi (preuve « reçu `started` journalisé AVANT l'upload »).
final class EspionDocuments: DocumentsPort, @unchecked Sendable {
    let interne: any DocumentsPort
    let magasin: MagasinRecusEnMemoire
    let appels = Verrouille<[String]>([])
    let phaseALEnvoi = Verrouille<[RecuDocument.Phase?]>([])
    let issueEnvoiForcee = Verrouille<IssueEnvoiDocument?>(nil)
    let issueReconciliationForcee = Verrouille<IssueEnvoiDocument?>(nil)
    let dossierForce = Verrouille<DossierDocuments?>(nil)
    let erreurDossier = Verrouille<JoleneError?>(nil)
    let retenueEnvoi = Verrouille<Gate?>(nil)

    init(interne: any DocumentsPort = DemoDocumentsGateway(), magasin: MagasinRecusEnMemoire) {
        self.interne = interne; self.magasin = magasin
    }

    func nombre(_ nom: String) -> Int { appels.lire.filter { $0 == nom }.count }
    private func noter(_ nom: String) { appels.modifier { $0.append(nom) } }

    func dossier(context: MissionReadContext) async throws -> DossierDocuments {
        noter("dossier")
        if let erreur = erreurDossier.lire { throw erreur }
        if let force = dossierForce.lire { return force }
        return try await interne.dossier(context: context)
    }
    func preparerEnvoi(type: String, fichier: FichierChoisi, libelle: String?, context: MissionReadContext) async throws -> RecuDocument {
        noter("preparer")
        return try await interne.preparerEnvoi(type: type, fichier: fichier, libelle: libelle, context: context)
    }
    func envoyer(recu: RecuDocument, octets: Data, context: MissionReadContext) async throws -> IssueEnvoiDocument {
        noter("envoyer")
        let journalise = try? await ReceiptJournal<RecuDocument>(store: magasin).lire(userId: context.userId)
        phaseALEnvoi.modifier { $0.append(journalise?.phase) }
        if let retenue = retenueEnvoi.lire { await retenue.wait() }
        let issue = try await interne.envoyer(recu: recu, octets: octets, context: context)
        return issueEnvoiForcee.lire ?? issue
    }
    func reconcilier(recu: RecuDocument, context: MissionReadContext) async throws -> IssueEnvoiDocument {
        noter("reconcilier")
        if let forcee = issueReconciliationForcee.lire { return forcee }
        return try await interne.reconcilier(recu: recu, context: context)
    }
    func reverifier(documentId: String, context: MissionReadContext) async throws -> VerdictDocument {
        noter("reverifier")
        return try await interne.reverifier(documentId: documentId, context: context)
    }
    func demanderRevue(documentId: String, context: MissionReadContext) async throws {
        noter("revue")
        try await interne.demanderRevue(documentId: documentId, context: context)
    }
    func consulter(document: DocumentSoignant, context: MissionReadContext) async throws -> URL {
        noter("consulter")
        return try await interne.consulter(document: document, context: context)
    }
    func signerAttestationSante(context: MissionReadContext) async throws -> Date {
        noter("attestation")
        return try await interne.signerAttestationSante(context: context)
    }
    func coherence(context: MissionReadContext) async throws -> CoherenceDocuments? {
        noter("coherence")
        return try await interne.coherence(context: context)
    }
}

/// Attente simulée du suivi de vérification : instantanée, journalisée.
actor AttenteSimulee {
    private(set) var delais: [TimeInterval] = []
    func attendre(_ secondes: TimeInterval) { delais.append(secondes) }
}

/// Modèle des justificatifs (lot 2 T6, blueprint §2.5) : un envoi à la fois, reçu journalisé avant l'upload et effacé
/// après la relecture, réconciliation au chargement (jamais de renvoi), suivi du verdict toutes les 5 s pendant 60 s,
/// enchaînement vers l'exigence suivante, journal illisible bloquant (renvoi web).
@MainActor
final class DocumentsModelTests: XCTestCase {
    private let pdf = Data("%PDF-1.4 demo".utf8)

    private var fichierPdf: FichierPret {
        FichierPret(fichier: FichierChoisi(nom: "carte-identite.pdf", mime: .pdf, tailleOctets: pdf.count), octets: pdf)
    }

    private func pret(_ espion: EspionDocuments, attente: AttenteSimulee = AttenteSimulee())
        async throws -> (DocumentsModel, SessionController) {
        var gateways = DemoWorld.gateways()
        gateways.documents = espion
        let controller = SessionController(gateways: gateways)
        let etat = await controller.signIn(email: "demonstration@example.invalid", password: "demonstration")
        let snapshot = try XCTUnwrap(etat.snapshot, "session démo prête attendue, obtenu \(etat)")
        let model = DocumentsModel(controller: controller, snapshot: snapshot, recus: espion.magasin,
                                   attendre: { secondes in await attente.attendre(secondes) })
        return (model, controller)
    }

    private func journal(_ magasin: MagasinRecusEnMemoire) -> ReceiptJournal<RecuDocument> {
        ReceiptJournal<RecuDocument>(store: magasin)
    }

    func testChargementPublieLeDossierEtLaCoherence() async throws {
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        let (model, _) = try await pret(espion)
        XCTAssertEqual(model.etat, .chargement)
        await model.charger()
        let dossier = try XCTUnwrap(model.dossier)
        XCTAssertEqual(dossier.exigences.map(\.typeDocument), ["CARTE_IDENTITE", "DIPLOME", "RCP_ASSURANCE", "RIB"])
        XCTAssertEqual(model.coherence, CoherenceDocuments(coherent: true, problemes: []))
        XCTAssertEqual(espion.appels.lire, ["dossier", "coherence"], "aucun reçu en attente : aucune réconciliation")
        XCTAssertEqual(model.envoi, .inactif)
    }

    func testEchecDeChargementPuisReprise() async throws {
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        espion.erreurDossier.modifier { $0 = JoleneError(.network, MessagesDocuments.chargementImpossible) }
        let (model, _) = try await pret(espion)
        await model.charger()
        XCTAssertEqual(model.etat, .echec(MessagesDocuments.chargementImpossible))
        espion.erreurDossier.modifier { $0 = JoleneError(.unauthorized, "Votre session a expiré.") }
        await model.charger()
        XCTAssertTrue(model.sessionExpired)
        espion.erreurDossier.modifier { $0 = nil }
        await model.charger()
        XCTAssertNotNil(model.dossier)
        XCTAssertFalse(model.sessionExpired)
    }

    func testEnvoiJournaliseAvantUploadEffaceApresPuisSuiviJusquAuVerdict() async throws {
        let magasin = MagasinRecusEnMemoire()
        let espion = EspionDocuments(magasin: magasin)
        let attente = AttenteSimulee()
        let (model, _) = try await pret(espion, attente: attente)
        await model.charger()

        await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil)
        guard case let .termine(.verificationDemandee(id)) = model.envoi else {
            return XCTFail("vérification demandée attendue, obtenu \(model.envoi)")
        }
        XCTAssertEqual(espion.phaseALEnvoi.lire, [.started], "reçu `started` journalisé avant l'unique upload")
        XCTAssertEqual(espion.nombre("envoyer"), 1)
        XCTAssertTrue(magasin.cles().isEmpty, "reçu effacé après la relecture")
        XCTAssertEqual(model.enVerification, [id], "vérification suivie en ligne")

        await model.attendreFinDuSuivi()
        XCTAssertEqual(model.enVerification, [])
        XCTAssertEqual(model.dossier?.document(pour: "CARTE_IDENTITE")?.statutVerification, "VERIFIE")
        XCTAssertTrue(model.dossierComplet, "plus aucune pièce critique à fournir : célébration")
        XCTAssertNil(model.exigenceSuivante)
        let delais = await attente.delais
        XCTAssertEqual(delais, [5], "relecture toutes les 5 s, arrêtée dès le verdict")
    }

    func testEnchainementVersLExigenceSuivante() async throws {
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        let (model, _) = try await pret(espion)
        await model.charger()
        // La RCP est remplacée et vérifiée : la carte d'identité (rejetée) reste la prochaine étape.
        await model.envoyer(typeDocument: "RCP_ASSURANCE", fichier: fichierPdf, libelle: nil)
        await model.attendreFinDuSuivi()
        XCTAssertEqual(model.exigenceSuivante, "CARTE_IDENTITE")
        XCTAssertFalse(model.dossierComplet)
        model.oublierExigenceSuivante()
        XCTAssertNil(model.exigenceSuivante)
    }

    func testUnSeulEnvoiALaFois() async throws {
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        let retenue = Gate()
        espion.retenueEnvoi.modifier { $0 = retenue }
        let (model, _) = try await pret(espion)
        await model.charger()
        let premier = Task { await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil) }
        while espion.nombre("envoyer") == 0 { await Task.yield() }
        XCTAssertEqual(model.envoi, .enCours(typeDocument: "CARTE_IDENTITE"))
        await model.envoyer(typeDocument: "DIPLOME", fichier: fichierPdf, libelle: nil)
        XCTAssertEqual(espion.nombre("preparer"), 1, "le second geste est ignoré pendant l'envoi")
        await retenue.open()
        await premier.value
        XCTAssertEqual(espion.nombre("envoyer"), 1)
    }

    func testReponseIncertaineConserveLeRecuPuisReconcilieSansRenvoi() async throws {
        let magasin = MagasinRecusEnMemoire()
        let demo = DemoDocumentsGateway(scenario: .uploadIncertain)
        let espion = EspionDocuments(interne: demo, magasin: magasin)
        let (model, _) = try await pret(espion)
        await model.charger()
        await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil)
        guard case .termine(.verificationDemandee) = model.envoi else { return XCTFail("réconciliation immédiate : \(model.envoi)") }
        XCTAssertEqual(espion.nombre("envoyer"), 1, "jamais de second upload")
        XCTAssertEqual(espion.nombre("reconcilier"), 1)
        let verifications = await demo.appelsVerification
        XCTAssertEqual(verifications.count, 1, "verify-document une seule fois")
        XCTAssertTrue(magasin.cles().isEmpty)

        // Réconciliation encore incertaine : le reçu `started` est gardé et bloque un nouvel envoi.
        espion.issueEnvoiForcee.modifier { $0 = .incertain }
        espion.issueReconciliationForcee.modifier { $0 = .incertain }
        await model.envoyer(typeDocument: "DIPLOME", fichier: fichierPdf, libelle: nil)
        XCTAssertEqual(model.envoi, .termine(.incertain))
        let garde = try await journal(magasin).lire(userId: DemoWorld.context.userId)
        XCTAssertEqual(garde?.phase, .started)
        await model.envoyer(typeDocument: "RIB", fichier: fichierPdf, libelle: nil)
        XCTAssertEqual(model.envoi, .recuEnCours, "reçu en vol : réconcilier avant tout nouvel envoi")
        XCTAssertEqual(espion.nombre("envoyer"), 2)
        XCTAssertEqual(espion.nombre("reconcilier"), 3, "une réconciliation avant le nouvel envoi refusé")
    }

    func testRecuPrepareOrphelinMarqueNonEnvoyeSansAppelReseau() async throws {
        let magasin = MagasinRecusEnMemoire()
        let fichier = FichierChoisi(nom: "a.pdf", mime: .pdf, tailleOctets: 4)
        let orphelin = try RecuDocument.preparer(userId: DemoWorld.context.userId, epoch: 1, typeDocument: "DIPLOME",
                                                 fichier: fichier, horodatageMs: 1_793_577_600_000)
        try await journal(magasin).ecrire(orphelin)
        let espion = EspionDocuments(magasin: magasin)
        let (model, _) = try await pret(espion)
        await model.charger()
        XCTAssertTrue(magasin.cles().isEmpty, "sortie sûre : not_sent puis effacé")
        XCTAssertEqual(espion.nombre("reconcilier"), 0, "un reçu `prepared` n'a rien envoyé")
        XCTAssertEqual(model.envoi, .inactif)
    }

    func testRecuDemarreReconcilieAuChargement() async throws {
        let magasin = MagasinRecusEnMemoire()
        let fichier = FichierChoisi(nom: "a.pdf", mime: .pdf, tailleOctets: 4)
        let demarre = try RecuDocument.preparer(userId: DemoWorld.context.userId, epoch: 1, typeDocument: "DIPLOME",
                                                fichier: fichier, horodatageMs: 1_793_577_600_000)
        try await journal(magasin).ecrire(demarre)
        try await journal(magasin).ecrire(try demarre.demarrer())
        let espion = EspionDocuments(magasin: magasin)
        let (model, _) = try await pret(espion)
        await model.charger()
        XCTAssertEqual(espion.appels.lire.prefix(2), ["reconcilier", "dossier"], "réconciliation avant la lecture du dossier")
        XCTAssertEqual(model.envoi, .termine(.nonEnvoye), "ni objet ni ligne : nouvelle sélection demandée")
        XCTAssertTrue(magasin.cles().isEmpty)
    }

    func testJournalIllisibleBloqueLEnvoiSansJamaisLeReecrire() async throws {
        let magasin = MagasinRecusEnMemoire()
        let cle = try XCTUnwrap(CleRecu(domaine: RecuDocument.domaine, userId: DemoWorld.context.userId))
        let altere = Data("{\"version\":9}".utf8)
        try magasin.ecrire(altere, pour: cle)
        let espion = EspionDocuments(magasin: magasin)
        let (model, _) = try await pret(espion)
        await model.charger()
        XCTAssertEqual(model.envoi, .suiviIllisible)
        XCTAssertNotNil(model.dossier, "le dossier reste consultable")
        await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil)
        XCTAssertEqual(model.envoi, .suiviIllisible)
        XCTAssertEqual(espion.nombre("preparer"), 0)
        XCTAssertEqual(try magasin.lire(cle), altere, "jamais réécrit ni effacé par l'app")
        XCTAssertEqual(DocumentsModel.renvoiWeb, "/soignant/mes-documents?tab=justificatifs")
    }

    func testTypeNonProposeEtNomHorsBornesRefusesAvantToutEnvoi() async throws {
        let magasin = MagasinRecusEnMemoire()
        let espion = EspionDocuments(magasin: magasin)
        let (model, _) = try await pret(espion)
        await model.charger()
        await model.envoyer(typeDocument: "AUTRE", fichier: fichierPdf, libelle: nil)
        XCTAssertEqual(model.envoi, .refuseAvantEnvoi(message: MessagesDocuments.enregistrementImpossible),
                       "un envoi hors exigence affichée est impossible (correction 21)")
        let long = FichierPret(fichier: FichierChoisi(nom: String(repeating: "a", count: 300) + ".pdf", mime: .pdf, tailleOctets: pdf.count),
                               octets: pdf)
        await model.envoyer(typeDocument: "DIPLOME", fichier: long, libelle: nil)
        XCTAssertEqual(model.envoi, .termine(.refuse(code: "METADONNEES_DOCUMENT_INVALIDES")))
        XCTAssertEqual(espion.nombre("envoyer"), 0)
        XCTAssertTrue(magasin.cles().isEmpty, "aucun objet orphelin, aucun reçu")
    }

    func testSuiviArreteApresSoixanteSecondes() async throws {
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        let attente = AttenteSimulee()
        let (model, _) = try await pret(espion, attente: attente)
        await model.charger()
        let enAttente = DossierDocuments(exigences: model.dossier?.exigences ?? [],
                                         documents: [DocumentSoignant(id: "d-att", typeDocument: "DIPLOME", statutVerification: "EN_ATTENTE")],
                                         profil: model.dossier?.profil)
        await model.envoyer(typeDocument: "DIPLOME", fichier: fichierPdf, libelle: nil)
        espion.dossierForce.modifier { $0 = enAttente }
        await model.attendreFinDuSuivi()
        let delais = await attente.delais
        XCTAssertEqual(delais, Array(repeating: 5, count: 12), "5 s pendant 60 s, comme le web (l.252-253)")
        XCTAssertEqual(model.enVerification, [], "suivi abandonné après 60 s")
    }

    func testEpochPerimeAucunEnvoi() async throws {
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        let (model, controller) = try await pret(espion)
        await model.charger()
        _ = await controller.signOut()
        await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil)
        XCTAssertEqual(espion.nombre("preparer"), 0, "aucune action pour une session périmée")
        XCTAssertEqual(model.envoi, .inactif)
    }

    func testActionsRevueReverificationAttestationConsultation() async throws {
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        let (model, _) = try await pret(espion)
        await model.charger()
        let rejete = try XCTUnwrap(model.dossier?.document(pour: "CARTE_IDENTITE"))

        let revue = await model.demanderRevue(documentId: rejete.id)
        XCTAssertTrue(revue)
        XCTAssertEqual(model.dossier?.document(pour: "CARTE_IDENTITE")?.statutVerification, "REVUE_MANUELLE_REQUISE", "dossier relu")
        let introuvable = await model.demanderRevue(documentId: "inconnu")
        XCTAssertFalse(introuvable)
        XCTAssertEqual(model.messageAction, MessagesDocuments.revueDocumentIntrouvable)

        let verdict = await model.reverifier(documentId: rejete.id)
        XCTAssertEqual(verdict, .enAttente)
        XCTAssertEqual(espion.nombre("reverifier"), 1, "geste manuel, jamais automatique")

        let signee = await model.signerAttestation()
        XCTAssertTrue(signee)
        XCTAssertEqual(model.dossier?.attestationSanteSigneeLe, "2026-11-02T00:00:00.000Z")

        let url = await model.consulter(try XCTUnwrap(model.dossier?.document(pour: "DIPLOME")))
        XCTAssertNotNil(url)
        ConsultationDocuments.effacerTout()
        XCTAssertNil(model.actionEnCours)
    }
}
