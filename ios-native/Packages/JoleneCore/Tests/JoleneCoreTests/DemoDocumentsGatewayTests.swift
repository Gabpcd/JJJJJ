import XCTest
@testable import JoleneCore

/// Monde démo des justificatifs (lot 2 T6, blueprint §2.8) : fixture `demo-documents.json`, envoi → `EN_ATTENTE` puis
/// `VERIFIE` à la seconde relecture, scénario `upload-incertain` réconcilié sans second envoi, aucun réseau.
final class DemoDocumentsGatewayTests: XCTestCase {
    private let c = DemoWorld.context

    private func autreContexte() -> MissionReadContext {
        var autre = DemoWorld.context
        autre.userId = "user-1"
        autre.profile.id = "user-1"
        return autre
    }

    private let pdf = Data("%PDF-1.4 demo".utf8)
    private var fichierPdf: FichierChoisi { FichierChoisi(nom: "carte-identite.pdf", mime: .pdf, tailleOctets: pdf.count) }

    func testFixtureEtDossierConformesAuBlueprint() async throws {
        let fichier = try DemoFixtures.loadDocuments()
        XCTAssertEqual(fichier.fixedNow, "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(PlanningHorlogeParis.instant(fichier.fixedNow), DemoWorld.fixedNow)
        let d = try await DemoDocumentsGateway().dossier(context: c)
        XCTAssertEqual(d.profil, SoignantExigencesDocuments(profession: "IDE", typeExercice: "MIXTE", rppsVerifie: false, adeliVerifie: false))
        XCTAssertEqual(d.profil?.profession, DemoWorld.context.profile.profession)
        XCTAssertEqual(d.profil?.typeExercice, DemoWorld.context.profile.typeExercice)
        XCTAssertEqual(d.exigences.map(\.typeDocument), ["CARTE_IDENTITE", "DIPLOME", "RCP_ASSURANCE", "RIB"],
                       "exigences fictives filtrées comme le web : VACCINATIONS écartée")
        XCTAssertTrue(d.exigences.allSatisfy { $0.description == "Exigence de démonstration" })
        XCTAssertEqual(fichier.exigences.map(\.typeDocument).contains("VACCINATIONS"), true, "la fixture prouve le filtre")
        let maintenant = DemoWorld.fixedNow
        let etats = Dictionary(uniqueKeysWithValues: d.exigences.map { ($0.typeDocument, d.etat(de: $0, maintenant: maintenant)) })
        guard case .rejetee = try XCTUnwrap(etats["CARTE_IDENTITE"]) else { return XCTFail("CARTE_IDENTITE REJETE malgré sa date passée") }
        guard case .presente(_, false) = try XCTUnwrap(etats["DIPLOME"]) else { return XCTFail("DIPLOME vérifié") }
        guard case .expiree = try XCTUnwrap(etats["RIB"]) else { return XCTFail("RIB expiré") }
        XCTAssertEqual(d.expirantBientot(maintenant: maintenant).map(\.typeDocument), ["RCP_ASSURANCE"], "RCP : 12 jours")
        XCTAssertEqual(d.expirantBientot(maintenant: maintenant).first.flatMap { DossierDocuments.joursRestants($0, maintenant: maintenant) }, 12)
        XCTAssertEqual(d.prochaineExigence(maintenant: maintenant)?.typeDocument, "CARTE_IDENTITE")
        XCTAssertNil(d.attestationSanteSigneeLe)
        XCTAssertTrue(d.documents.allSatisfy { $0.s3Cle?.hasPrefix("demo-soignant/documents/") == true })
    }

    func testEnvoiPuisVerifieALaSecondeRelecture() async throws {
        let gateway = DemoDocumentsGateway()
        let recu = try await gateway.preparerEnvoi(type: "CARTE_IDENTITE", fichier: fichierPdf, libelle: "Recto verso", context: c)
        XCTAssertEqual(recu.phase, .prepared)
        XCTAssertTrue(recu.s3Cle.hasPrefix("demo-soignant/documents/CARTE_IDENTITE/"))
        XCTAssertTrue(recu.s3Cle.hasSuffix("-carte-identite.pdf"))
        let second = try await gateway.preparerEnvoi(type: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil, context: c)
        XCTAssertNotEqual(second.s3Cle, recu.s3Cle, "horloge fixée : deux préparations donnent deux clés")

        let issue = try await gateway.envoyer(recu: try recu.demarrer(), octets: pdf, context: c)
        guard case let .verificationDemandee(id) = issue else { return XCTFail("envoi démo : vérification demandée, obtenu \(issue)") }
        let premiere = try await gateway.dossier(context: c)
        XCTAssertEqual(premiere.document(pour: "CARTE_IDENTITE")?.id, id, "la nouvelle pièce remplace la preuve active")
        XCTAssertEqual(premiere.document(pour: "CARTE_IDENTITE")?.statutVerification, "EN_ATTENTE")
        XCTAssertEqual(premiere.document(pour: "CARTE_IDENTITE")?.libelle, "Recto verso")
        XCTAssertEqual(premiere.documents.filter { $0.typeDocument == "CARTE_IDENTITE" }.count, 1, "l'ancienne preuve est révoquée")
        let seconde = try await gateway.dossier(context: c)
        XCTAssertEqual(seconde.document(pour: "CARTE_IDENTITE")?.statutVerification, "VERIFIE")
        let verifications = await gateway.appelsVerification
        XCTAssertEqual(verifications, [id], "verify-document une seule fois")
        let envois = await gateway.envois
        XCTAssertEqual(envois, 1)
        XCTAssertNil(seconde.prochaineExigence(maintenant: DemoWorld.fixedNow), "toutes les pièces critiques sont valides")
    }

    func testRecuHorsPhaseOuOctetsIncoherentsRefusesSansEnvoi() async throws {
        let gateway = DemoDocumentsGateway()
        let recu = try await gateway.preparerEnvoi(type: "DIPLOME", fichier: fichierPdf, libelle: nil, context: c)
        do {
            _ = try await gateway.envoyer(recu: recu, octets: pdf, context: c)
            XCTFail("un reçu non démarré n'est jamais envoyé")
        } catch let erreur as RecuErreur {
            XCTAssertEqual(erreur, .transitionInterdite(de: "prepared", vers: "stored"))
        }
        do {
            _ = try await gateway.envoyer(recu: try recu.demarrer(), octets: pdf + Data([0]), context: c)
            XCTFail("des octets d'une autre taille ne sont jamais envoyés")
        } catch let erreur as RecuErreur {
            XCTAssertEqual(erreur, .champInvalide("tailleOctets"))
        }
        do {
            _ = try await gateway.preparerEnvoi(type: "VACCINATIONS", fichier: fichierPdf, libelle: nil, context: c)
            XCTFail("pièce de santé : jamais proposée ni acceptée")
        } catch let erreur as RecuErreur {
            XCTAssertEqual(erreur, .champInvalide("typeDocument"))
        }
        let envois = await gateway.envois
        XCTAssertEqual(envois, 0)
    }

    func testReponsePerdueReconcilieeSansSecondEnvoiNiSecondeVerification() async throws {
        let gateway = DemoDocumentsGateway(scenario: .uploadIncertain)
        let recu = try await gateway.preparerEnvoi(type: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil, context: c).demarrer()
        let issue = try await gateway.envoyer(recu: recu, octets: pdf, context: c)
        XCTAssertEqual(issue, .incertain, "réponse perdue après application")
        let reconciliee = try await gateway.reconcilier(recu: recu, context: c)
        guard case let .verificationDemandee(id) = reconciliee else { return XCTFail("ligne relue avec sa tentative : \(reconciliee)") }
        let verifications = await gateway.appelsVerification
        XCTAssertEqual(verifications, [id])
        let envois = await gateway.envois
        XCTAssertEqual(envois, 1, "aucun second envoi")
        XCTAssertEqual(ScenarioDocumentsDemo(rawValue: "upload-incertain"), .uploadIncertain)
    }

    func testReconciliationSansObjetNiLigneEtRecuPrepare() async throws {
        let gateway = DemoDocumentsGateway()
        let recu = try await gateway.preparerEnvoi(type: "DIPLOME", fichier: fichierPdf, libelle: nil, context: c)
        let prepare = try await gateway.reconcilier(recu: recu, context: c)
        XCTAssertEqual(prepare, .nonEnvoye, "prepared : rien n'est parti")
        let demarre = try await gateway.reconcilier(recu: try recu.demarrer(), context: c)
        XCTAssertEqual(demarre, .nonEnvoye, "ni objet ni ligne : nouvelle sélection")
        let verifications = await gateway.appelsVerification
        XCTAssertEqual(verifications, [])
    }

    func testRevueReverificationAttestationConsultationCoherence() async throws {
        let gateway = DemoDocumentsGateway()
        let avant = try await gateway.dossier(context: c)
        let rejete = try XCTUnwrap(avant.document(pour: "CARTE_IDENTITE"))

        try await gateway.demanderRevue(documentId: rejete.id, context: c)
        let apresRevue = try await gateway.dossier(context: c)
        XCTAssertEqual(apresRevue.document(pour: "CARTE_IDENTITE")?.statutVerification, "REVUE_MANUELLE_REQUISE")
        do {
            try await gateway.demanderRevue(documentId: "inconnu", context: c)
            XCTFail("document inconnu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.message, MessagesDocuments.revueDocumentIntrouvable)
        }

        let verdict = try await gateway.reverifier(documentId: rejete.id, context: c)
        XCTAssertEqual(verdict, .enAttente)
        let verifications = await gateway.appelsVerification
        XCTAssertEqual(verifications, [rejete.id], "revérification manuelle seulement")

        let signee = try await gateway.signerAttestationSante(context: c)
        XCTAssertEqual(signee, DemoWorld.fixedNow)
        let apresAttestation = try await gateway.dossier(context: c)
        XCTAssertEqual(apresAttestation.attestationSanteSigneeLe, "2026-11-02T00:00:00.000Z", "valeur relue")

        let fichier = try await gateway.consulter(document: try XCTUnwrap(avant.document(pour: "DIPLOME")), context: c)
        XCTAssertTrue(fichier.isFileURL)
        XCTAssertTrue(fichier.path.hasPrefix(ConsultationDocuments.dossier.path), "copie temporaire protégée, jamais une URL distante")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fichier.path))
        ConsultationDocuments.effacerTout()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fichier.path))

        let coherence = try await gateway.coherence(context: c)
        XCTAssertEqual(coherence, CoherenceDocuments(coherent: true, problemes: []))
    }

    func testAutreUtilisateurRefuseAvecErreurDemoOnly() async throws {
        let gateway = DemoDocumentsGateway()
        let autre = autreContexte()
        let appels: [(String, () async throws -> Void)] = [
            ("dossier", { _ = try await gateway.dossier(context: autre) }),
            ("preparer", { _ = try await gateway.preparerEnvoi(type: "DIPLOME", fichier: self.fichierPdf, libelle: nil, context: autre) }),
            ("revue", { try await gateway.demanderRevue(documentId: "demo-doc-diplome", context: autre) }),
            ("attestation", { _ = try await gateway.signerAttestationSante(context: autre) }),
            ("coherence", { _ = try await gateway.coherence(context: autre) }),
        ]
        for (nom, appel) in appels {
            do {
                try await appel()
                XCTFail("\(nom) : la démo ne sert aucun autre utilisateur")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .demoOnly, nom)
            }
        }
    }

    /// Sentinelle « 0 requête » : tout le parcours démo passe sans qu'aucune requête n'atteigne le système d'URL.
    func testAucuneRequeteReseau() async throws {
        SentinelleReseau.reinitialiser()
        XCTAssertTrue(URLProtocol.registerClass(SentinelleReseau.self))
        defer { URLProtocol.unregisterClass(SentinelleReseau.self) }
        let gateway = DemoDocumentsGateway(scenario: .uploadIncertain)
        let d = try await gateway.dossier(context: c)
        let recu = try await gateway.preparerEnvoi(type: "CARTE_IDENTITE", fichier: fichierPdf, libelle: nil, context: c).demarrer()
        _ = try await gateway.envoyer(recu: recu, octets: pdf, context: c)
        _ = try await gateway.reconcilier(recu: recu, context: c)
        _ = try await gateway.reverifier(documentId: try XCTUnwrap(d.document(pour: "DIPLOME")).id, context: c)
        _ = try await gateway.consulter(document: try XCTUnwrap(d.document(pour: "DIPLOME")), context: c)
        _ = try await gateway.signerAttestationSante(context: c)
        _ = try await gateway.coherence(context: c)
        ConsultationDocuments.effacerTout()
        XCTAssertEqual(SentinelleReseau.compte, 0, "le monde démo n'envoie rien au réseau")
    }
}

/// Protocole d'URL témoin : compte toute requête vue par le système d'URL, sans jamais la servir.
final class SentinelleReseau: URLProtocol {
    private static let verrou = NSLock()
    nonisolated(unsafe) private static var vues = 0

    static var compte: Int { verrou.lock(); defer { verrou.unlock() }; return vues }
    static func reinitialiser() { verrou.lock(); vues = 0; verrou.unlock() }

    override class func canInit(with request: URLRequest) -> Bool {
        verrou.lock(); vues += 1; verrou.unlock()
        return false
    }
}
