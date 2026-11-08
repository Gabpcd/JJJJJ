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

extension Verrouille {
    /// Lit puis vide une valeur optionnelle (barrière à usage unique).
    func prendre<T>() -> T? where Valeur == T? {
        var pris: T?
        modifier { pris = $0; $0 = nil }
        return pris
    }
}

/// Latence simulée d'un port lent (réseau mobile, appel IA) : interrompue par l'annulation, comme une requête.
func latenceSimulee(_ secondes: TimeInterval) async throws {
    guard secondes > 0 else { return }
    try await Task.sleep(nanoseconds: UInt64(secondes * 1_000_000_000))
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
    /// Barrière posée sur la prochaine réconciliation (toutes celles qui arrivent avant son ouverture l'attendent).
    let retenueReconciliation = Verrouille<Gate?>(nil)
    /// Barrière à usage unique : seule la prochaine relecture du dossier l'attend.
    let retenueDossier = Verrouille<Gate?>(nil)
    /// Latences simulées (secondes) : upload, réconciliation, revérification, téléchargement.
    let latenceEnvoi = Verrouille<TimeInterval>(0)
    let latenceReconciliation = Verrouille<TimeInterval>(0)
    let latenceReverification = Verrouille<TimeInterval>(0)
    let latenceConsultation = Verrouille<TimeInterval>(0)
    /// Erreur levée par l'upload après sa retenue (401 tardif).
    let erreurEnvoi = Verrouille<JoleneError?>(nil)
    /// Issue forcée de `verify-document` (m-d) ; nil : celle du port interne.
    let verificationEchoueeForcee = Verrouille<Bool?>(nil)
    /// Appels de `verificationEchouee` (hors `appels` : ils partent hors du chemin critique, sans ordre fixe).
    let observationsVerification = Verrouille(0)

    init(interne: any DocumentsPort = DemoDocumentsGateway(), magasin: MagasinRecusEnMemoire) {
        self.interne = interne; self.magasin = magasin
    }

    func nombre(_ nom: String) -> Int { appels.lire.filter { $0 == nom }.count }
    private func noter(_ nom: String) { appels.modifier { $0.append(nom) } }

    func dossier(context: MissionReadContext) async throws -> DossierDocuments {
        noter("dossier")
        if let retenue: Gate = retenueDossier.prendre() { await retenue.wait() }
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
        try await latenceSimulee(latenceEnvoi.lire)
        if let erreur = erreurEnvoi.lire { throw erreur }
        let issue = try await interne.envoyer(recu: recu, octets: octets, context: context)
        return issueEnvoiForcee.lire ?? issue
    }
    func reconcilier(recu: RecuDocument, context: MissionReadContext) async throws -> IssueEnvoiDocument {
        noter("reconcilier")
        if let retenue = retenueReconciliation.lire { await retenue.wait() }
        try await latenceSimulee(latenceReconciliation.lire)
        if let forcee = issueReconciliationForcee.lire { return forcee }
        return try await interne.reconcilier(recu: recu, context: context)
    }
    func reverifier(documentId: String, context: MissionReadContext) async throws -> VerdictDocument {
        noter("reverifier")
        try await latenceSimulee(latenceReverification.lire)
        return try await interne.reverifier(documentId: documentId, context: context)
    }
    func demanderRevue(documentId: String, context: MissionReadContext) async throws {
        noter("revue")
        try await interne.demanderRevue(documentId: documentId, context: context)
    }
    func consulter(document: DocumentSoignant, context: MissionReadContext) async throws -> URL {
        noter("consulter")
        try await latenceSimulee(latenceConsultation.lire)
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
    func verificationEchouee(documentId: String) async -> Bool? {
        observationsVerification.modifier { $0 += 1 }
        if let forcee = verificationEchoueeForcee.lire { return forcee }
        return await interne.verificationEchouee(documentId: documentId)
    }
}

/// Magasin de reçus dont l'effacement échoue (erreur de stockage du trousseau).
final class MagasinSansEffacement: ReceiptStorePort, @unchecked Sendable {
    let interne = MagasinRecusEnMemoire()
    func lire(_ cle: CleRecu) throws -> Data? { try interne.lire(cle) }
    func ecrire(_ donnees: Data, pour cle: CleRecu) throws { try interne.ecrire(donnees, pour: cle) }
    func effacer(_ cle: CleRecu) throws { throw CocoaError(.fileWriteUnknown) }
}

/// Attend qu'une condition du main actor devienne vraie (issue reprise hors du chemin critique), deux secondes au plus.
@MainActor
func attendreQue(_ condition: () -> Bool) async {
    let limite = Date().addingTimeInterval(2)
    while !condition(), Date() < limite { try? await Task.sleep(nanoseconds: 2_000_000) }
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

    private func pret(_ espion: EspionDocuments, attente: AttenteSimulee = AttenteSimulee(),
                      attendre: (@Sendable (TimeInterval) async throws -> Void)? = nil,
                      resolution: TimeInterval = SessionController.defaultResolutionTimeout,
                      recus: (any ReceiptStorePort)? = nil)
        async throws -> (DocumentsModel, SessionController) {
        var gateways = DemoWorld.gateways()
        gateways.documents = espion
        let controller = SessionController(gateways: gateways, resolutionTimeout: resolution)
        let etat = await controller.signIn(email: "demonstration@example.invalid", password: "demonstration")
        let snapshot = try XCTUnwrap(etat.snapshot, "session démo prête attendue, obtenu \(etat)")
        let model = DocumentsModel(controller: controller, snapshot: snapshot, recus: recus ?? espion.magasin,
                                   attendre: attendre ?? { secondes in await attente.attendre(secondes) })
        return (model, controller)
    }

    /// Second modèle de la même session sur le même journal, construit comme le fera l'écran (`@StateObject` recréé à
    /// la réouverture, seconde fenêtre iPad) : aucun registre n'est passé, celui du processus est implicite.
    private func autreModele(_ controller: SessionController, recus: any ReceiptStorePort,
                             attente: AttenteSimulee = AttenteSimulee()) async throws -> DocumentsModel {
        let etat = await controller.state
        let snapshot = try XCTUnwrap(etat.snapshot)
        return DocumentsModel(controller: controller, snapshot: snapshot, recus: recus,
                              attendre: { secondes in await attente.attendre(secondes) })
    }

    /// Reçu `started` d'un essai précédent (arrêt forcé pendant l'upload).
    private func recuDemarreEnAttente(_ magasin: MagasinRecusEnMemoire) async throws {
        let fichier = FichierChoisi(nom: "a.pdf", mime: .pdf, tailleOctets: 4)
        let prepare = try RecuDocument.preparer(userId: DemoWorld.context.userId, epoch: 1, typeDocument: "DIPLOME",
                                                fichier: fichier, horodatageMs: 1_793_577_600_000)
        try await journal(magasin).ecrire(prepare)
        try await journal(magasin).ecrire(try prepare.demarrer())
    }

    /// Dossier relu après l'envoi, la pièce `documentId` passée au statut et à la tentative donnés.
    private func dossierModifie(_ model: DocumentsModel, documentId: String, statut: String, tentative: String?) throws -> DossierDocuments {
        var dossier = try XCTUnwrap(model.dossier)
        XCTAssertTrue(dossier.documents.contains { $0.id == documentId }, "pièce envoyée relue")
        dossier.documents = dossier.documents.map { document in
            guard document.id == documentId else { return document }
            var modifie = document
            modifie.statutVerification = statut
            modifie.verificationAttemptId = tentative
            return modifie
        }
        return dossier
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
        // m-h : la célébration est ponctuelle (2,5 s sur le web, l.268-269) ; l'écran l'oublie après l'avoir montrée.
        model.oublierDossierComplet()
        XCTAssertFalse(model.dossierComplet)
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
        // Revue fraîche de T6, m-b : le dossier est lu AVANT la réconciliation (l'écran ne reste pas en `.chargement`
        // pendant elle), puis relu après son issue.
        XCTAssertEqual(Array(espion.appels.lire.prefix(3)), ["dossier", "reconcilier", "dossier"],
                       "dossier lu d'abord, réconciliation, puis relecture après l'issue")
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

    // MARK: - Revue fraîche de T6 : envoi en vol, délais longs, suivi, attestation

    /// M1 : `charger()` (apparition, tirer-pour-rafraîchir, retour au premier plan, blueprint §2.5) pendant l'upload ne
    /// réconcilie jamais le reçu `started` de l'envoi en vol : ni « non envoyé » prématuré, ni second `verify-document`.
    func testChargerPendantUnEnvoiNeReconcilieJamaisLeRecuEnVol() async throws {
        let magasin = MagasinRecusEnMemoire()
        let demo = DemoDocumentsGateway()
        let espion = EspionDocuments(interne: demo, magasin: magasin)
        let retenue = Gate()
        espion.retenueEnvoi.modifier { $0 = retenue }
        let (model, _) = try await pret(espion)
        await model.charger()

        let envoi = Task { await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil) }
        while espion.nombre("envoyer") == 0 { await Task.yield() }
        await model.charger()
        await model.charger()
        XCTAssertEqual(espion.nombre("reconcilier"), 0, "jamais de réconciliation du reçu d'un envoi en vol")
        XCTAssertEqual(model.envoi, .enCours(typeDocument: "CARTE_IDENTITE"), "la garde « un seul envoi » tient")
        await model.envoyer(typeDocument: "DIPLOME", fichier: fichierPdf, libelle: nil)
        XCTAssertEqual(espion.nombre("preparer"), 1, "second geste ignoré")

        await retenue.open()
        await envoi.value
        guard case .termine(.verificationDemandee) = model.envoi else {
            return XCTFail("vérification demandée attendue, obtenu \(model.envoi)")
        }
        let verifications = await demo.appelsVerification
        XCTAssertEqual(verifications.count, 1, "verify-document une seule fois pour ce document_id (décision 14)")
        XCTAssertEqual(espion.nombre("envoyer"), 1)
        XCTAssertTrue(magasin.cles().isEmpty)
        await model.attendreFinDuSuivi()
    }

    /// M1 : la réconciliation d'un reçu précédent (étape 1 de l'envoi) ne publie aucune issue au milieu de l'envoi et
    /// ne lève pas la garde : un second geste pendant la relecture qui la suit est ignoré.
    func testDoubleGestePendantLaReconciliationDeLEtapeUnUnSeulPreparer() async throws {
        let magasin = MagasinRecusEnMemoire()
        let espion = EspionDocuments(magasin: magasin)
        let (model, _) = try await pret(espion)
        await model.charger()
        try await recuDemarreEnAttente(magasin)
        espion.issueReconciliationForcee.modifier { $0 = .enregistre(documentId: "demo-doc-precedent") }
        let porte = Gate()
        espion.retenueDossier.modifier { $0 = porte }
        let lecturesAvant = espion.nombre("dossier")

        let premier = Task { await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil) }
        while espion.nombre("dossier") == lecturesAvant { await Task.yield() }
        XCTAssertEqual(espion.nombre("reconcilier"), 1, "reçu précédent réconcilié, relecture du dossier retenue")
        XCTAssertEqual(model.envoi, .enCours(typeDocument: "CARTE_IDENTITE"), "aucune issue publiée au milieu de l'envoi")
        await model.envoyer(typeDocument: "DIPLOME", fichier: fichierPdf, libelle: nil)
        XCTAssertEqual(espion.nombre("preparer"), 0, "second geste ignoré pendant l'étape 1")

        await porte.open()
        await premier.value
        XCTAssertEqual(espion.nombre("preparer"), 1)
        XCTAssertEqual(espion.nombre("envoyer"), 1)
        XCTAssertEqual(espion.nombre("reconcilier"), 1)
        await model.attendreFinDuSuivi()
    }

    /// M1 : deux chargements simultanés (apparition puis tirer-pour-rafraîchir) partagent une seule réconciliation.
    func testDeuxChargementsSimultanesUneSeuleReconciliation() async throws {
        let magasin = MagasinRecusEnMemoire()
        try await recuDemarreEnAttente(magasin)
        let espion = EspionDocuments(magasin: magasin)
        let retenue = Gate()
        espion.retenueReconciliation.modifier { $0 = retenue }
        let (model, _) = try await pret(espion)

        let premier = Task { await model.charger() }
        while espion.nombre("reconcilier") == 0 { await Task.yield() }
        let second = Task { await model.charger() }
        let limite = Date().addingTimeInterval(0.3)
        while espion.nombre("reconcilier") < 2, Date() < limite { await Task.yield() }
        XCTAssertEqual(espion.nombre("reconcilier"), 1, "une seule réconciliation à la fois")

        await retenue.open()
        await premier.value
        await second.value
        XCTAssertEqual(espion.nombre("reconcilier"), 1)
        XCTAssertEqual(model.envoi, .termine(.nonEnvoye))
        XCTAssertTrue(magasin.cles().isEmpty)
    }

    /// M2 : un upload plus long que `resolutionTimeout` (réseau mobile lent) aboutit : aucun « non envoyé », aucune
    /// réconciliation, une seule vérification.
    func testUploadPlusLongQueLaResolutionAboutitSansReconciliation() async throws {
        let magasin = MagasinRecusEnMemoire()
        let demo = DemoDocumentsGateway()
        let espion = EspionDocuments(interne: demo, magasin: magasin)
        espion.latenceEnvoi.modifier { $0 = 0.6 }
        let (model, controller) = try await pret(espion, resolution: 0.2)
        XCTAssertEqual(controller.resolutionTimeout, 0.2)
        await model.charger()

        await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil)

        guard case .termine(.verificationDemandee) = model.envoi else {
            return XCTFail("l'upload lent doit aboutir, obtenu \(model.envoi)")
        }
        XCTAssertEqual(espion.nombre("reconcilier"), 0, "aucun délai dépassé : aucune réconciliation")
        XCTAssertEqual(espion.nombre("envoyer"), 1)
        let verifications = await demo.appelsVerification
        XCTAssertEqual(verifications.count, 1)
        XCTAssertTrue(magasin.cles().isEmpty)
        await model.attendreFinDuSuivi()
    }

    /// M2 : revérification (appel IA attendu) et consultation (téléchargement) bornées par le délai des transferts,
    /// jamais par `resolutionTimeout` : aucun « Le service ne répond pas » alors que le serveur répond.
    func testReverificationEtConsultationLentesSansMessageDeDelai() async throws {
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        espion.latenceReverification.modifier { $0 = 0.6 }
        espion.latenceConsultation.modifier { $0 = 0.6 }
        let (model, _) = try await pret(espion, resolution: 0.2)
        await model.charger()
        let rejete = try XCTUnwrap(model.dossier?.document(pour: "CARTE_IDENTITE"))

        let verdict = await model.reverifier(documentId: rejete.id)
        XCTAssertEqual(verdict, .enAttente)
        XCTAssertNil(model.messageAction)
        let url = await model.consulter(try XCTUnwrap(model.dossier?.document(pour: "DIPLOME")))
        XCTAssertNotNil(url)
        XCTAssertNil(model.messageAction)
        ConsultationDocuments.effacerTout()
    }

    /// M2 : borne des transferts et de la vérification, distincte de `resolutionTimeout` (amendement de PRINCIPES
    /// l.107-114 dans `DECISIONS_LOT2.md`).
    func testDelaiDesTransfertsProportionnelALaTaille() {
        XCTAssertEqual(DocumentsModel.delaiTransfertMinimum, 120)
        XCTAssertEqual(DocumentsModel.debitPlancherOctetsParSeconde, 50_000)
        XCTAssertEqual(DocumentsModel.delaiTransfert(octets: 3_000_000), 120, "3 Mo : plancher de 120 s")
        XCTAssertEqual(DocumentsModel.delaiTransfert(octets: ClassementDocument.tailleMaxParDefaut),
                       30 + Double(ClassementDocument.tailleMaxParDefaut) / 50_000, accuracy: 0.000_1, "10 Mo : ≈ 240 s")
        XCTAssertEqual(DocumentsModel.delaiTransfert(octets: nil), DocumentsModel.delaiTransfert(octets: ClassementDocument.tailleMaxParDefaut),
                       "taille inconnue : celle du plafond")
        XCTAssertEqual(DocumentsModel.delaiTransfert(octets: -1), 120)
        XCTAssertGreaterThan(DocumentsModel.delaiTransfertMinimum, SessionController.defaultResolutionTimeout)
    }

    /// m11 : `verify-document` en erreur après le début de la tentative (503 `AI_NOT_CONFIGURED`, 500) passe la pièce en
    /// revue manuelle ; le statut relu donne l'issue « Document téléversé. Vérification manuelle en attente. » du web
    /// (`DocumentsSoignant.tsx` l.416-419), sans enchaînement.
    func testRevueManuelleRelueApresLaVerificationDonneVerificationManuelle() async throws {
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        let (model, _) = try await pret(espion)
        await model.charger()
        await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil)
        guard case let .termine(.verificationDemandee(id)) = model.envoi else {
            return XCTFail("vérification demandée attendue, obtenu \(model.envoi)")
        }
        let revue = try dossierModifie(model, documentId: id, statut: VerdictDocument.revueManuelleRequise.rawValue, tentative: nil)
        espion.dossierForce.modifier { $0 = revue }

        await model.attendreFinDuSuivi()

        XCTAssertEqual(model.envoi, .termine(.enregistre(documentId: id)))
        XCTAssertEqual(model.enVerification, [])
        XCTAssertNil(model.exigenceSuivante)
        XCTAssertFalse(model.dossierComplet)
    }

    /// m11 : `verify-document` refusé avant toute tentative (429, aucune ligne modifiée) : après 60 s de suivi sans
    /// tentative relue, vérification manuelle (« Revérifier ») ; une tentative en cours garde l'issue « en cours ».
    func testVerificationJamaisEngageeApresSoixanteSecondesDonneVerificationManuelle() async throws {
        for (tentative, manuelle) in [(nil as String?, true), ("a-1", false)] {
            let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
            let attente = AttenteSimulee()
            let (model, _) = try await pret(espion, attente: attente)
            await model.charger()
            await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil)
            guard case let .termine(.verificationDemandee(id)) = model.envoi else {
                return XCTFail("vérification demandée attendue, obtenu \(model.envoi)")
            }
            let enAttente = try dossierModifie(model, documentId: id, statut: "EN_ATTENTE", tentative: tentative)
            espion.dossierForce.modifier { $0 = enAttente }

            await model.attendreFinDuSuivi()

            let delais = await attente.delais
            XCTAssertEqual(delais.count, 12, "suivi de 60 s")
            XCTAssertEqual(model.envoi, manuelle ? .termine(.enregistre(documentId: id)) : .termine(.verificationDemandee(documentId: id)),
                           "tentative \(tentative ?? "nulle")")
        }
    }

    /// m4 : `arreterSuivi()` (fermeture de l'écran, T7) arrête la relecture du dossier.
    func testArreterLeSuiviAucuneRelectureEnsuite() async throws {
        let porte = Gate()
        let entrees = Verrouille(0)
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        let (model, _) = try await pret(espion, attendre: { _ in
            entrees.modifier { $0 += 1 }
            await porte.wait()
        })
        await model.charger()
        await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil)
        while entrees.lire == 0 { await Task.yield() }
        let lectures = espion.nombre("dossier")

        model.arreterSuivi()
        XCTAssertEqual(model.enVerification, [])
        await porte.open()
        await model.attendreFinDuSuivi()

        XCTAssertEqual(espion.nombre("dossier"), lectures, "aucune relecture après l'arrêt du suivi")
        XCTAssertEqual(entrees.lire, 1)
    }

    /// m4 : le suivi ne retient pas le modèle ; à sa disparition, la relecture s'arrête (le web efface son intervalle au
    /// démontage, l.254).
    func testSuiviArreteQuandLeModeleDisparait() async throws {
        let porte = Gate()
        let entrees = Verrouille(0)
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        var model: DocumentsModel? = try await pret(espion, attendre: { _ in
            entrees.modifier { $0 += 1 }
            await porte.wait()
        }).0
        await model?.charger()
        await model?.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil)
        while entrees.lire == 0 { await Task.yield() }
        let lectures = espion.nombre("dossier")
        // Référence faible par liste de capture : un `weak var` local jamais réaffecté est signalé par Swift 6.2
        // (#WeakMutability) et `weak let` n'existe pas avant Swift 6.2 (poste local en 6.1).
        let modeleLibere = { [weak model] in model == nil }

        model = nil
        XCTAssertTrue(modeleLibere(), "le suivi ne retient pas le modèle")
        await porte.open()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(espion.nombre("dossier"), lectures, "aucune relecture après la disparition du modèle")
        XCTAssertEqual(entrees.lire, 1)
    }

    /// m3 : une attestation déjà signée n'est jamais re-signée (`fn_signer_attestation_sante` réécrirait la date d'une
    /// déclaration sur l'honneur, `public.sql` l.56329-56332 ; web : `canSign = … && !signedAt`, l.69).
    func testAttestationDejaSigneeJamaisResignee() async throws {
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        let (model, _) = try await pret(espion)
        await model.charger()
        XCTAssertNil(model.dossier?.attestationSanteSigneeLe)
        let premiere = await model.signerAttestation()
        XCTAssertTrue(premiere)
        let signeeLe = try XCTUnwrap(model.dossier?.attestationSanteSigneeLe)

        let seconde = await model.signerAttestation()

        XCTAssertFalse(seconde, "déjà signée : aucune nouvelle signature")
        XCTAssertEqual(espion.nombre("attestation"), 1, "aucun second appel")
        XCTAssertEqual(model.dossier?.attestationSanteSigneeLe, signeeLe, "date d'origine conservée")
        XCTAssertNil(model.messageAction)
    }

    /// m2 : « Mettre à jour → » du bandeau d'expiration (l.606) et documents complémentaires étudiant / interne
    /// (l.851-900) : envoi possible hors exigences ; un type ni exigé, ni expirant, ni complémentaire reste refusé.
    func testEnvoiDUnDocumentComplementaireOuExpirantHorsExigences() async throws {
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        let (model, _) = try await pret(espion)
        await model.charger()
        // Profil démo : IDE, ni RPPS ni ADELI vérifié → scolarité et licence visibles (documents-complementaires.ts).
        await model.envoyer(typeDocument: "ATTESTATION_SCOLARITE", fichier: fichierPdf, libelle: nil)
        guard case .termine(.verificationDemandee) = model.envoi else {
            return XCTFail("document complémentaire envoyé, obtenu \(model.envoi)")
        }
        await model.attendreFinDuSuivi()
        await model.envoyer(typeDocument: "CARTE_ORDRE", fichier: fichierPdf, libelle: nil)
        XCTAssertEqual(model.envoi, .refuseAvantEnvoi(message: MessagesDocuments.enregistrementImpossible),
                       "qualification à l'Ordre : médecins seulement")
    }

    // MARK: - Seconde revue fraîche de T6 : instances multiples, gestes en file, délais, verdicts, epoch

    /// M1-bis : un upload lent du premier modèle est en vol ; l'écran est fermé puis rouvert (nouveau modèle, comme
    /// `@StateObject`, sur le même journal ; même cas avec deux fenêtres sur iPad). Le second ne réconcilie jamais l'essai
    /// en vol (reçu intact, ni « non envoyé » ni `cleanup_orphan`), ne lance aucun envoi, affiche l'envoi en cours puis en
    /// reprend l'issue ; une seule vérification pour le document.
    func testSecondModeleNeReconcilieNiNEnvoiePendantLEnvoiDuPremier() async throws {
        let magasin = MagasinRecusEnMemoire()
        let demo = DemoDocumentsGateway()
        let espion = EspionDocuments(interne: demo, magasin: magasin)
        let retenue = Gate()
        espion.retenueEnvoi.modifier { $0 = retenue }
        let (premier, controller) = try await pret(espion)
        await premier.charger()
        let envoi = Task { await premier.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil) }
        while espion.nombre("envoyer") == 0 { await Task.yield() }
        let journalise = try await journal(magasin).lire(userId: DemoWorld.context.userId)
        let enVol = try XCTUnwrap(journalise)
        XCTAssertEqual(enVol.phase, .started)

        let second = try await autreModele(controller, recus: magasin)
        await second.charger()
        XCTAssertEqual(espion.nombre("reconcilier"), 0, "jamais de réconciliation de l'essai en vol d'une autre instance")
        let relu = try await journal(magasin).lire(userId: DemoWorld.context.userId)
        XCTAssertEqual(relu, enVol, "reçu en vol intact")
        XCTAssertNotNil(second.dossier, "le dossier reste consultable")
        XCTAssertEqual(second.envoi, .enCours(typeDocument: "CARTE_IDENTITE"), "l'envoi en vol est affiché, jamais « non envoyé »")
        await second.envoyer(typeDocument: "DIPLOME", fichier: fichierPdf, libelle: nil)
        XCTAssertEqual(espion.nombre("preparer"), 1, "aucun second envoi tant que l'autre est en vol")
        XCTAssertEqual(espion.nombre("envoyer"), 1)

        await retenue.open()
        await envoi.value
        guard case let .termine(.verificationDemandee(id)) = premier.envoi else {
            return XCTFail("vérification demandée attendue, obtenu \(premier.envoi)")
        }
        await attendreQue { second.envoi != .enCours(typeDocument: "CARTE_IDENTITE") }
        XCTAssertEqual(second.envoi, .termine(.verificationDemandee(documentId: id)), "issue reprise par le second écran")
        let verifications = await demo.appelsVerification
        XCTAssertEqual(verifications, [id], "verify-document une seule fois pour ce document_id (décision 14)")
        XCTAssertEqual(espion.nombre("reconcilier"), 0)
        XCTAssertEqual(espion.nombre("envoyer"), 1)
        XCTAssertTrue(magasin.cles().isEmpty)
        await premier.attendreFinDuSuivi()
        await second.attendreFinDuSuivi()
    }

    /// M1-bis : la réconciliation « une seule à la fois » est partagée par toutes les instances du même utilisateur :
    /// deux écrans qui se chargent pendant qu'un reçu est en attente font une seule relecture (un seul rejeu, une seule
    /// vérification), et chacun en publie l'issue.
    func testDeuxModelesPartagentUneSeuleReconciliation() async throws {
        let magasin = MagasinRecusEnMemoire()
        try await recuDemarreEnAttente(magasin)
        let espion = EspionDocuments(magasin: magasin)
        let retenue = Gate()
        espion.retenueReconciliation.modifier { $0 = retenue }
        let (premier, controller) = try await pret(espion)
        let second = try await autreModele(controller, recus: magasin)

        let chargementPremier = Task { await premier.charger() }
        while espion.nombre("reconcilier") == 0 { await Task.yield() }
        let chargementSecond = Task { await second.charger() }
        while espion.nombre("dossier") < 2 { await Task.yield() }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(espion.nombre("reconcilier"), 1, "le second écran attend la réconciliation en cours")

        await retenue.open()
        await chargementPremier.value
        await chargementSecond.value
        XCTAssertEqual(espion.nombre("reconcilier"), 1)
        XCTAssertEqual(premier.envoi, .termine(.nonEnvoye))
        XCTAssertEqual(second.envoi, .termine(.nonEnvoye))
        XCTAssertTrue(magasin.cles().isEmpty)
    }

    /// m-a : deux gestes déjà en file sur le main actor (double tap) ne passent jamais tous deux la garde : un seul
    /// `verify-document` pour « Revérifier », une seule `fn_signer_attestation_sante`.
    func testDeuxGestesSimultanesUneSeuleAction() async throws {
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        let (model, _) = try await pret(espion)
        await model.charger()
        let rejete = try XCTUnwrap(model.dossier?.document(pour: "CARTE_IDENTITE"))

        async let premiere = model.reverifier(documentId: rejete.id)
        async let seconde = model.reverifier(documentId: rejete.id)
        let verdicts = await [premiere, seconde]
        XCTAssertEqual(espion.nombre("reverifier"), 1, "une seule revérification")
        XCTAssertEqual(verdicts.compactMap { $0 }, [.enAttente])

        async let signature = model.signerAttestation()
        async let doublon = model.signerAttestation()
        let signatures = await [signature, doublon]
        XCTAssertEqual(espion.nombre("attestation"), 1, "une seule signature de la déclaration sur l'honneur")
        XCTAssertEqual(signatures.filter { $0 }.count, 1)
        XCTAssertNil(model.actionEnCours)
    }

    /// m-b : avec un reçu en attente, le dossier est affiché sans attendre la réconciliation.
    func testDossierAfficheSansAttendreLaReconciliation() async throws {
        let magasin = MagasinRecusEnMemoire()
        try await recuDemarreEnAttente(magasin)
        let espion = EspionDocuments(magasin: magasin)
        let retenue = Gate()
        espion.retenueReconciliation.modifier { $0 = retenue }
        let (model, _) = try await pret(espion)

        let chargement = Task { await model.charger() }
        while espion.nombre("reconcilier") == 0 { await Task.yield() }
        XCTAssertNotNil(model.dossier, "dossier affiché pendant la réconciliation (jamais plusieurs minutes en chargement)")
        XCTAssertEqual(espion.appels.lire, ["dossier", "reconcilier"])

        await retenue.open()
        await chargement.value
        XCTAssertEqual(model.envoi, .termine(.nonEnvoye))
    }

    /// m-b : une réconciliation (ligne, HEAD, rejeu, nettoyage ; `verify-document` jamais attendu) est bornée à quatre
    /// lectures, jamais à la borne des transferts (≥ 120 s) ; délai dépassé : reçu gardé, réconcilié plus tard.
    func testReconciliationBorneeAQuatreLectures() async throws {
        XCTAssertEqual(DocumentsModel.requetesReconciliation, 4)
        let magasin = MagasinRecusEnMemoire()
        try await recuDemarreEnAttente(magasin)
        let espion = EspionDocuments(magasin: magasin)
        espion.latenceReconciliation.modifier { $0 = 0.5 }
        let (model, _) = try await pret(espion, resolution: 0.2)
        await model.charger()
        XCTAssertEqual(model.envoi, .termine(.nonEnvoye), "0,5 s < 4 × 0,2 s : la réconciliation aboutit")

        try await recuDemarreEnAttente(magasin)
        espion.latenceReconciliation.modifier { $0 = 3 }
        let debut = Date()
        await model.charger()
        XCTAssertLessThan(Date().timeIntervalSince(debut), 2, "borne de quatre lectures (0,8 s), pas celle des transferts")
        let garde = try await journal(magasin).lire(userId: DemoWorld.context.userId)
        XCTAssertEqual(garde?.phase, .started, "reçu gardé")
    }

    /// m-c : une ligne relue dont le verdict est déjà rendu (relancement après la vérification) n'est ni annoncée « en
    /// cours » ni suivie.
    func testVerdictDejaRenduALaReconciliationAucunSuivi() async throws {
        let magasin = MagasinRecusEnMemoire()
        try await recuDemarreEnAttente(magasin)
        let espion = EspionDocuments(magasin: magasin)
        espion.issueReconciliationForcee.modifier { $0 = .verdictRendu(documentId: "demo-doc-diplome") }
        let attente = AttenteSimulee()
        let (model, _) = try await pret(espion, attente: attente)
        await model.charger()
        XCTAssertEqual(model.envoi, .termine(.verdictRendu(documentId: "demo-doc-diplome")))
        XCTAssertEqual(model.enVerification, [])
        await model.attendreFinDuSuivi()
        let delais = await attente.delais
        XCTAssertEqual(delais, [], "aucun suivi d'une pièce déjà jugée")
        XCTAssertTrue(magasin.cles().isEmpty)
    }

    /// m-d : `verify-document` en erreur (429, 403, 503) : « vérification manuelle en attente » aussitôt, comme le web
    /// (l.413-425), sans attendre les 60 s du suivi (bloqué ici).
    func testErreurDeVerificationDonneAussitotVerificationManuelle() async throws {
        let porte = Gate()
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        espion.verificationEchoueeForcee.modifier { $0 = true }
        let (model, _) = try await pret(espion, attendre: { _ in await porte.wait() })
        await model.charger()
        await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil)
        let id = try XCTUnwrap(model.dossier?.document(pour: "CARTE_IDENTITE")?.id)

        await attendreQue { model.envoi == .termine(.enregistre(documentId: id)) }

        XCTAssertEqual(model.envoi, .termine(.enregistre(documentId: id)))
        XCTAssertEqual(model.enVerification, [], "suivi abandonné pour cette pièce")
        XCTAssertEqual(espion.observationsVerification.lire, 1)
        await porte.open()
        await model.attendreFinDuSuivi()
    }

    /// m-d : `verify-document` a répondu : relecture aussitôt (le web recharge, l.420), verdict affiché sans attendre la
    /// relecture suivante du suivi (bloqué ici).
    func testReponseDeVerificationRelitAussitotLeVerdict() async throws {
        let porte = Gate()
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        espion.verificationEchoueeForcee.modifier { $0 = false }
        let (model, _) = try await pret(espion, attendre: { _ in await porte.wait() })
        await model.charger()
        await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil)

        await attendreQue { model.dossierComplet }

        XCTAssertTrue(model.dossierComplet, "verdict VERIFIE relu dès la réponse de verify-document")
        XCTAssertEqual(model.dossier?.document(pour: "CARTE_IDENTITE")?.statutVerification, "VERIFIE")
        XCTAssertEqual(model.enVerification, [])
        await porte.open()
        await model.attendreFinDuSuivi()
    }

    /// m-f : un reçu qu'on ne parvient pas à effacer après sa réconciliation reste en vol : l'envoi est bloqué « suivi
    /// illisible » (renvoi web), jamais remplacé par « un autre reçu en cours », et aucun nouvel essai n'est préparé.
    func testEffacementImpossibleApresLaReconciliationGardeLeSuiviIllisible() async throws {
        let magasin = MagasinSansEffacement()
        let espion = EspionDocuments(magasin: magasin.interne)
        espion.issueReconciliationForcee.modifier { $0 = .nonEnvoye }
        let (model, _) = try await pret(espion, recus: magasin)
        await model.charger()
        try await recuDemarreEnAttente(magasin.interne)

        await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil)

        XCTAssertEqual(model.envoi, .suiviIllisible)
        XCTAssertEqual(espion.nombre("reconcilier"), 1)
        XCTAssertEqual(espion.nombre("preparer"), 0, "aucun nouvel essai tant que le reçu reste en vol")
    }

    /// m-f : identité quittée pendant l'upload, puis 401 tardif : aucun état de l'ancienne session n'est publié (ni
    /// « session expirée », ni erreur) ; le modèle périmé revient à `.inactif`.
    func testIdentiteQuitteePendantLEnvoiAucunEtatDeLAncienneSession() async throws {
        let espion = EspionDocuments(magasin: MagasinRecusEnMemoire())
        let retenue = Gate()
        espion.retenueEnvoi.modifier { $0 = retenue }
        espion.erreurEnvoi.modifier { $0 = JoleneError(.unauthorized, SessionController.sessionExpiredMessage) }
        let (model, controller) = try await pret(espion)
        await model.charger()
        let envoi = Task { await model.envoyer(typeDocument: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil) }
        while espion.nombre("envoyer") == 0 { await Task.yield() }

        _ = await controller.signOut()
        await retenue.open()
        await envoi.value

        XCTAssertFalse(model.sessionExpired, "401 d'une identité quittée : rien n'est publié")
        XCTAssertEqual(model.envoi, .inactif)
    }
}
