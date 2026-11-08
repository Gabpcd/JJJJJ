import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Compteur partagé par les prédicats de stub (réponses successives d'un même chemin).
final class CompteurStub: @unchecked Sendable {
    private let verrou = NSLock()
    private var valeur = 0
    func suivant() -> Int { verrou.lock(); defer { verrou.unlock() }; valeur += 1; return valeur }
}

/// Justificatifs sur Supabase (lot 2 T6, blueprint §2.3-§2.5, décision 14) — fiches `fn_remplacer_document_soignant`,
/// `fn_demander_revue_document`, `fn_verifier_coherence_documents`, `fn_signer_attestation_sante`, « Edge
/// `verify-document` » et « Storage du lot 2 » de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`. Clé Storage construite
/// comme le web (`DocumentsSoignant.tsx` l.372) ; upload `upsert: false` ; enregistrement idempotent ; `verify-document`
/// une seule fois par document ; réconciliation par `s3_cle` puis `exists(path:)` ; aucun octet conservé.
final class SupabaseDocumentsGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let uid = TestClient.userId
    private let documentId = "5b0e8f3c-2d4a-4c6e-9f1a-3e7d2c1b0a99"
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01])

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseDocumentsGateway {
        SupabaseDocumentsGateway(client: TestClient.make(), clock: FixedClock(DemoWorld.fixedNow))
    }

    private var cle: String { "\(uid)/documents/DIPLOME/1793577600000-diplome.jpg" }
    private var cheminObjet: String { "/storage/v1/object/jolene-documents/\(cle)" }
    private let verify = "/functions/v1/verify-document"
    private let remplacer = "/rest/v1/rpc/fn_remplacer_document_soignant"
    private let lignes = "/rest/v1/documents_soignants"

    private func recuDemarre(phase: RecuDocument.Phase = .started, libelle: String? = "Diplôme d'État") throws -> RecuDocument {
        let fichier = FichierChoisi(nom: "Diplôme.JPG", mime: .jpeg, tailleOctets: jpeg.count)
        var recu = try RecuDocument.preparer(userId: uid, epoch: 1, typeDocument: "DIPLOME", fichier: fichier, libelle: libelle,
                                             horodatageMs: 1_793_577_600_000)
        XCTAssertEqual(recu.s3Cle, cle)
        if phase == .prepared { return recu }
        recu = try recu.demarrer()
        if phase == .stored { recu = try recu.stocker() }
        return recu
    }

    private static func corps(_ requete: RecordedRequest?) -> [String: Any] { (requete?.bodyJSON as? [String: Any]) ?? [:] }
    private func corps(_ requete: RecordedRequest?) -> [String: Any] { Self.corps(requete) }

    private func appelsVerification() -> [RecordedRequest] {
        registry.requests(to: verify).filter { corps($0)["document_id"] != nil }
    }

    private func appelsNettoyage() -> [RecordedRequest] {
        registry.requests(to: verify).filter { corps($0)["action"] as? String == "cleanup_orphan" }
    }

    private func stubUpload(_ reponse: StubResponse? = nil) {
        registry.add("POST", cheminObjet, respond: reponse ?? .json(200, #"{"Key":"jolene-documents/\#(cle)","Id":"obj-1"}"#))
    }

    private func stubRemplacer(_ json: String) {
        registry.add("POST", remplacer, respond: .json(200, json))
    }

    private func stubVerify(_ reponse: StubResponse) {
        registry.add("POST", verify, where: { Self.corps($0)["document_id"] != nil }, respond: reponse)
    }

    private func stubPreuve(statut: String = "VERIFIE", tentative: String? = "a-1", where predicat: (@Sendable (RecordedRequest) -> Bool)? = nil) {
        let tentativeJSON = tentative.map { "\"\($0)\"" } ?? "null"
        registry.add("GET", lignes, where: predicat, respond: .json(200, """
        [{"id":"\(documentId)","s3_cle":"\(cle)","statut_verification":"\(statut)","verification_attempt_id":\(tentativeJSON)}]
        """))
    }

    // MARK: - Dossier

    func testDossierLitLesProjectionsDuWebEtFiltreParProfessionEtExercice() async throws {
        registry.add("GET", "/rest/v1/soignants", respond: .json(200, """
        {"profession":"IADE","type_exercice":"SALARIE","rpps_verifie":true,"adeli_verifie":false,"attestation_sante_signee_le":null}
        """))
        registry.add("GET", "/rest/v1/documents_requis_par_profession", respond: .json(200, """
        [{"id":"r-1","profession":"IADE","type_document":"DIPLOME","description":"Diplôme","a_expiration":false,"duree_validite_mois":null,"est_critique":true,"type_exercice_requis":"TOUS"},
         {"id":"r-2","profession":"IADE","type_document":"RCP_ASSURANCE","description":null,"a_expiration":true,"duree_validite_mois":12,"est_critique":true,"type_exercice_requis":"LIBERAL_ONLY"},
         {"id":"r-3","profession":"IADE","type_document":"VACCINATIONS","description":null,"a_expiration":false,"duree_validite_mois":null,"est_critique":true,"type_exercice_requis":"TOUS"}]
        """))
        registry.add("GET", lignes, respond: .json(200, """
        [{"id":"\(documentId)","type_document":"DIPLOME","nom_fichier":"diplome.pdf","statut_verification":"VERIFIE","valide_depuis":"2020-06-30",
          "valide_jusqua":null,"televerse_le":"2026-10-20T09:00:00+00:00","motif_rejet":null,"est_critique":true,"s3_cle":"\(uid)/documents/DIPLOME/1-diplome.pdf",
          "type_mime":"application/pdf","taille_octets":2048,"libelle":null,"verification_attempt_id":null,"profession_certifiee":"IADE"}]
        """))

        let dossier = try await gateway().dossier(context: TestClient.context)

        XCTAssertEqual(dossier.profil, SoignantExigencesDocuments(profession: "IADE", typeExercice: "SALARIE", rppsVerifie: true, adeliVerifie: false))
        XCTAssertEqual(dossier.exigences.map(\.typeDocument), ["DIPLOME"], "salarié : pas de RCP ; pièce de santé jamais proposée ; IADE garde le diplôme")
        XCTAssertEqual(dossier.documents.first?.professionCertifiee, "IADE")
        XCTAssertEqual(dossier.documents.first?.valideDepuis, "2020-06-30")
        let profil = try XCTUnwrap(registry.requests(to: "/rest/v1/soignants").first)
        XCTAssertEqual(profil.query("select"), SupabaseDocumentsGateway.selectionProfil)
        XCTAssertEqual(profil.query("id"), "eq.\(uid)")
        let regles = try XCTUnwrap(registry.requests(to: "/rest/v1/documents_requis_par_profession").first)
        XCTAssertEqual(regles.query("select"), "id,profession,type_document,description,a_expiration,duree_validite_mois,est_critique,type_exercice_requis",
                       "projection de DocumentsSoignant.tsx l.201")
        XCTAssertEqual(regles.query("profession"), "eq.IADE")
        let docs = try XCTUnwrap(registry.requests(to: lignes).first)
        XCTAssertEqual(docs.query("select"), SupabaseDocumentsGateway.selectionDocuments)
        XCTAssertFalse(docs.query("select")?.contains("resultat_ia,") ?? true, "seule la profession certifiée est lue dans resultat_ia")
        XCTAssertEqual(docs.query("soignant_id"), "eq.\(uid)")
        XCTAssertEqual(docs.query("supprime_le"), "is.null")
        XCTAssertEqual(docs.query("revoque_le"), "is.null")
        XCTAssertEqual(docs.query("order"), "televerse_le.desc")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testDossierSansProfilNeLitAucunePiece() async throws {
        registry.add("GET", "/rest/v1/soignants", respond: .json(406, """
        {"code":"PGRST116","details":"The result contains 0 rows","hint":null,"message":"JSON object requested, multiple (or no) rows returned"}
        """))
        let dossier = try await gateway().dossier(context: TestClient.context)
        XCTAssertEqual(dossier, DossierDocuments())
        XCTAssertEqual(registry.requests.count, 1, "sans dossier professionnel, aucune autre lecture (DocumentsSoignant.tsx l.186-191)")
    }

    func testDossierEnErreurDonneLeMessageDuWeb() async throws {
        // HTTP 500 (jamais rejoué par le SDK, contrairement à une coupure réseau sur un GET, correction 19).
        registry.add("GET", "/rest/v1/soignants", respond: .json(500, #"{"code":"XX000","message":"panne","details":null,"hint":null}"#))
        do {
            _ = try await gateway().dossier(context: TestClient.context)
            XCTFail("erreur attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.message, MessagesDocuments.chargementImpossible, "DocumentsSoignant.tsx l.218")
        }
        XCTAssertEqual(registry.requests.count, 1)
    }

    // MARK: - Préparation

    func testPreparationConstruitLaCleDuWebSansAucunAppel() async throws {
        let fichier = FichierChoisi(nom: "Diplôme.JPG", mime: .jpeg, tailleOctets: jpeg.count)
        let recu = try await gateway().preparerEnvoi(type: "DIPLOME", fichier: fichier, libelle: nil, context: TestClient.context)
        XCTAssertEqual(recu.s3Cle, cle, "<uid>/documents/<TYPE>/<ms>-<nom assaini>")
        XCTAssertEqual(recu.phase, .prepared)
        XCTAssertEqual(recu.nomFichier, "Diplôme.JPG", "nom d'origine gardé pour p_nom_fichier")
        XCTAssertTrue(registry.requests.isEmpty)
        do {
            _ = try await gateway().preparerEnvoi(type: "MEDECINE_TRAVAIL", fichier: fichier, libelle: nil, context: TestClient.context)
            XCTFail("pièce de santé refusée")
        } catch let erreur as RecuErreur {
            XCTAssertEqual(erreur, .champInvalide("typeDocument"))
        }
    }

    // MARK: - Envoi

    func testEnvoiUploadSansEcraserEnregistreVerifieUneFoisPuisRelit() async throws {
        stubUpload()
        stubRemplacer(#"{"success":true,"document_id":"\#(documentId)","idempotent":false}"#)
        stubVerify(.json(200, #"{"success":true,"verdict":"VERIFIE","analysis":{"motif_rejet":null}}"#))
        stubPreuve()

        let issue = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)

        XCTAssertEqual(issue, .verificationDemandee(documentId: documentId))
        let upload = try XCTUnwrap(registry.requests(to: cheminObjet).first)
        XCTAssertEqual(upload.method, "POST")
        XCTAssertEqual(upload.header("x-upsert"), "false", "jamais d'écrasement (aucune politique UPDATE)")
        let multipart = String(decoding: upload.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(multipart.contains("Content-Type: image/jpeg"), "type vérifié transmis")
        let rpc = corps(registry.requests(to: remplacer).first)
        XCTAssertEqual(Set(rpc.keys), ["p_type_document", "p_libelle", "p_s3_cle", "p_nom_fichier", "p_type_mime", "p_taille_octets"])
        XCTAssertEqual(rpc["p_type_document"] as? String, "DIPLOME")
        XCTAssertEqual(rpc["p_libelle"] as? String, "Diplôme d'État")
        XCTAssertEqual(rpc["p_s3_cle"] as? String, cle)
        XCTAssertEqual(rpc["p_nom_fichier"] as? String, "Diplôme.JPG")
        XCTAssertEqual(rpc["p_type_mime"] as? String, "image/jpeg")
        XCTAssertEqual(rpc["p_taille_octets"] as? Int, jpeg.count)
        XCTAssertEqual(appelsVerification().count, 1, "verify-document exactement une fois")
        XCTAssertEqual(corps(appelsVerification().first)["document_id"] as? String, documentId)
        XCTAssertEqual(appelsNettoyage().count, 0)
        let relecture = try XCTUnwrap(registry.requests(to: lignes).first)
        XCTAssertEqual(relecture.query("select"), PreuveDocument.selection)
        XCTAssertEqual(relecture.query("s3_cle"), "eq.\(cle)")
        XCTAssertEqual(relecture.query("soignant_id"), "eq.\(uid)")
        XCTAssertEqual(relecture.query("s3_bucket"), "eq.jolene-documents")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testLibelleAbsentEnvoyeVideCommeLeWeb() async throws {
        stubUpload()
        stubRemplacer(#"{"success":true,"document_id":"\#(documentId)","idempotent":false}"#)
        stubVerify(.json(200, #"{"success":true,"verdict":"EN_ATTENTE"}"#))
        stubPreuve(statut: "EN_ATTENTE")
        _ = try await gateway().envoyer(recu: try recuDemarre(libelle: nil), octets: jpeg, context: TestClient.context)
        XCTAssertEqual(corps(registry.requests(to: remplacer).first)["p_libelle"] as? String, "", "p_libelle: libelle || ''")
    }

    func testVerification429AucunRenvoiVerificationManuelle() async throws {
        stubUpload()
        stubRemplacer(#"{"success":true,"document_id":"\#(documentId)","idempotent":false}"#)
        stubVerify(.json(429, #"{"error":"Trop de vérifications. Réessayez dans 1 minute."}"#))
        stubPreuve(statut: "EN_ATTENTE", tentative: nil)

        let issue = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)

        XCTAssertEqual(issue, .enregistre(documentId: documentId), "« Vérification manuelle en attente » : Revérifier proposé, jamais relancé")
        XCTAssertEqual(appelsVerification().count, 1)
    }

    func testRefusDEnregistrementNettoieLOrphelinUneFois() async throws {
        for code in ["CHEMIN_DOCUMENT_INVALIDE", "METADONNEES_DOCUMENT_INVALIDES", "TYPE_DOCUMENT_INVALIDE", "DOCUMENT_INACTIF"] {
            registry.reset()
            stubUpload()
            stubRemplacer(#"{"success":false,"error_code":"\#(code)"}"#)
            registry.add("POST", verify, where: { Self.corps($0)["action"] as? String == "cleanup_orphan" },
                         respond: .json(200, #"{"success":true}"#))

            let issue = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)

            XCTAssertEqual(issue, .refuse(code: code))
            XCTAssertEqual(appelsNettoyage().count, 1, "\(code) : cleanup_orphan une fois (DocumentsSoignant.tsx l.395-397)")
            XCTAssertEqual(corps(appelsNettoyage().first)["s3_cle"] as? String, cle)
            XCTAssertEqual(appelsVerification().count, 0, "\(code) : aucune vérification")
            XCTAssertTrue(registry.unmatched.isEmpty)
        }
    }

    func testExceptionDeTriggerEstUnRefusAvecNettoyage() async throws {
        stubUpload()
        registry.add("POST", remplacer, respond: .json(400, #"{"code":"P0001","message":"refus","details":null,"hint":null}"#))
        registry.add("POST", verify, respond: .json(200, #"{"success":true}"#))
        let issue = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)
        XCTAssertEqual(issue, .refuse(code: "SQLSTATE_P0001"), "rollback prouvé, message jamais affiché")
        XCTAssertEqual(appelsNettoyage().count, 1)
        XCTAssertEqual(appelsVerification().count, 0)
    }

    func testEnregistrementIncertainSansNettoyageNiVerification() async throws {
        stubUpload()
        registry.add("POST", remplacer, respond: .networkFailure(.networkConnectionLost))
        let issue = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)
        XCTAssertEqual(issue, .incertain, "idempotente : la réconciliation la rejouera après relecture")
        XCTAssertEqual(registry.requests(to: verify).count, 0, "ni nettoyage ni vérification")
    }

    func testUploadRefuseHorsLigneOuIncertain() async throws {
        stubUpload(.json(403, #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"#))
        let refuse = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)
        XCTAssertEqual(refuse, .refuse(code: "STOCKAGE_403"))
        XCTAssertEqual(registry.requests(to: remplacer).count, 0)

        registry.reset()
        stubUpload(.networkFailure(.notConnectedToInternet))
        let horsLigne = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)
        XCTAssertEqual(horsLigne, .nonEnvoye, "requête jamais partie : nouvelle sélection")

        registry.reset()
        stubUpload(.networkFailure(.timedOut))
        let incertain = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)
        XCTAssertEqual(incertain, .incertain, "réponse perdue : réconciliation par exists(path:)")
        XCTAssertEqual(registry.requests(to: cheminObjet).count, 1, "aucun second upload")
        XCTAssertEqual(registry.requests(to: remplacer).count, 0)
    }

    func testRecuHorsPhaseOuAutreUtilisateurRefusAvantToutAppel() async throws {
        do {
            _ = try await gateway().envoyer(recu: try recuDemarre(phase: .prepared), octets: jpeg, context: TestClient.context)
            XCTFail("reçu non démarré")
        } catch let erreur as RecuErreur {
            XCTAssertEqual(erreur, .transitionInterdite(de: "prepared", vers: "stored"))
        }
        do {
            _ = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg + Data([0]), context: TestClient.context)
            XCTFail("taille incohérente")
        } catch let erreur as RecuErreur {
            XCTAssertEqual(erreur, .champInvalide("tailleOctets"))
        }
        var autre = TestClient.context
        autre.userId = "1c2d3e4f-0000-4000-8000-000000000001"
        autre.profile.id = autre.userId
        do {
            _ = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: autre)
            XCTFail("reçu d'un autre utilisateur")
        } catch let erreur as RecuErreur {
            XCTAssertEqual(erreur, .utilisateurDifferent)
        }
        XCTAssertTrue(registry.requests.isEmpty)
    }

    // MARK: - Réconciliation

    func testReconciliationObjetSansLigneRejoueLaMemeClePuisVerifieUneFois() async throws {
        let lectures = CompteurStub()
        registry.add("GET", lignes, where: { _ in lectures.suivant() == 1 }, respond: .json(200, "[]"))
        stubPreuve()
        registry.add("HEAD", cheminObjet, respond: .json(200, ""))
        stubRemplacer(#"{"success":true,"document_id":"\#(documentId)","idempotent":true}"#)
        stubVerify(.json(200, #"{"success":true,"verdict":"VERIFIE"}"#))

        let issue = try await gateway().reconcilier(recu: try recuDemarre(phase: .stored), context: TestClient.context)

        XCTAssertEqual(issue, .verificationDemandee(documentId: documentId))
        XCTAssertEqual(registry.requests(to: cheminObjet).map(\.method), ["HEAD"], "exists(path:), aucun upload")
        let rpc = corps(registry.requests(to: remplacer).first)
        XCTAssertEqual(rpc["p_s3_cle"] as? String, cle, "même clé : idempotente")
        XCTAssertEqual(rpc["p_nom_fichier"] as? String, "Diplôme.JPG")
        XCTAssertEqual(rpc["p_libelle"] as? String, "Diplôme d'État")
        XCTAssertEqual(appelsVerification().count, 1)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testReconciliationLignePresenteAucunAppelDeVerification() async throws {
        stubPreuve(statut: "EN_ATTENTE", tentative: "a-1")
        let engagee = try await gateway().reconcilier(recu: try recuDemarre(), context: TestClient.context)
        XCTAssertEqual(engagee, .verificationDemandee(documentId: documentId))
        registry.reset()
        stubPreuve(statut: "EN_ATTENTE", tentative: nil)
        let enregistree = try await gateway().reconcilier(recu: try recuDemarre(), context: TestClient.context)
        XCTAssertEqual(enregistree, .enregistre(documentId: documentId), "« Revérifier » proposé, jamais automatique")
        XCTAssertEqual(registry.requests(to: verify).count, 0)
        XCTAssertEqual(registry.requests(to: remplacer).count, 0)
        XCTAssertEqual(registry.requests(to: cheminObjet).count, 0)
    }

    func testReconciliationObjetAbsentNonEnvoye() async throws {
        registry.add("GET", lignes, respond: .json(200, "[]"))
        registry.add("HEAD", cheminObjet, respond: .json(404, ""))
        let issue = try await gateway().reconcilier(recu: try recuDemarre(), context: TestClient.context)
        XCTAssertEqual(issue, .nonEnvoye)
        XCTAssertEqual(registry.requests(to: remplacer).count, 0)
    }

    func testReconciliationRelectureImpossibleResteIncertaine() async throws {
        registry.add("GET", lignes, respond: .json(500, #"{"code":"XX000","message":"panne","details":null,"hint":null}"#))
        let issue = try await gateway().reconcilier(recu: try recuDemarre(), context: TestClient.context)
        XCTAssertEqual(issue, .incertain)
        XCTAssertEqual(registry.requests(to: cheminObjet).count, 0)
    }

    func testReconciliationRecuPrepareSansAucunAppel() async throws {
        let issue = try await gateway().reconcilier(recu: try recuDemarre(phase: .prepared), context: TestClient.context)
        XCTAssertEqual(issue, .nonEnvoye)
        XCTAssertTrue(registry.requests.isEmpty)
    }

    // MARK: - Revérification, revue, consultation, attestation, cohérence

    func testReverifierUnAppelVerdictOuMessageServeur() async throws {
        stubVerify(.json(200, #"{"success":true,"verdict":"REJETE","analysis":{"motif_rejet":"Flou"}}"#))
        let verdict = try await gateway().reverifier(documentId: documentId, context: TestClient.context)
        XCTAssertEqual(verdict, .rejete)
        XCTAssertEqual(appelsVerification().count, 1)
        registry.reset()
        stubVerify(.json(429, #"{"error":"Trop de vérifications. Réessayez dans 1 minute."}"#))
        do {
            _ = try await gateway().reverifier(documentId: documentId, context: TestClient.context)
            XCTFail("429 : refus")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.message, "Trop de vérifications. Réessayez dans 1 minute.", "message serveur verbatim")
        }
        XCTAssertEqual(appelsVerification().count, 1, "aucun renvoi")
    }

    func testDemanderRevueAvecLeMotifDuWeb() async throws {
        let rpc = "/rest/v1/rpc/fn_demander_revue_document"
        registry.add("POST", rpc, respond: .json(200, #"{"success":true,"revue_id":"r-1","message":"Demande transmise — en attente d'attribution."}"#))
        try await gateway().demanderRevue(documentId: documentId, context: TestClient.context)
        let envoye = corps(registry.requests(to: rpc).first)
        XCTAssertEqual(envoye["p_document_id"] as? String, documentId)
        XCTAssertEqual(envoye["p_motif"] as? String, "Contestation du verdict automatique depuis l’espace Documents")
        for (code, message) in [("DOCUMENT_INTROUVABLE", MessagesDocuments.revueDocumentIntrouvable),
                                ("MOTIF_INVALIDE", MessagesDocuments.revueMotifInvalide)] {
            registry.reset()
            registry.add("POST", rpc, respond: .json(200, #"{"success":false,"error_code":"\#(code)"}"#))
            do {
                try await gateway().demanderRevue(documentId: documentId, context: TestClient.context)
                XCTFail("\(code) : refus")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.message, message)
            }
        }
        registry.reset()
        registry.add("POST", rpc, respond: .json(200, #"{"success":false,"error_code":"NON_AUTHENTIFIE"}"#))
        do {
            try await gateway().demanderRevue(documentId: documentId, context: TestClient.context)
            XCTFail("session")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
    }

    func testConsultationTelechargeSousLeJetonPuisAuditeSansURLSignee() async throws {
        let pdf = Data("%PDF-1.4 justificatif".utf8)
        let objet = "\(uid)/documents/DIPLOME/1-diplome.pdf"
        registry.add("GET", "/storage/v1/object/jolene-documents/\(objet)",
                     respond: StubResponse(status: 200, headers: ["Content-Type": "application/pdf"], body: pdf, failure: nil))
        registry.add("POST", "/rest/v1/rpc/fn_ecrire_audit_safe", respond: .json(200, #"{"success":true}"#))
        let document = DocumentSoignant(id: documentId, typeDocument: "DIPLOME", s3Cle: objet, nomFichier: "diplome.pdf",
                                        typeMime: "application/pdf")

        let fichier = try await gateway().consulter(document: document, context: TestClient.context)
        defer { ConsultationDocuments.effacerTout() }

        XCTAssertTrue(fichier.isFileURL)
        XCTAssertEqual(try Data(contentsOf: fichier), pdf)
        XCTAssertEqual(fichier.pathExtension, "pdf")
        let audit = corps(registry.requests(to: "/rest/v1/rpc/fn_ecrire_audit_safe").first)
        XCTAssertEqual(audit["p_action"] as? String, "DOCUMENT_CONSULTATION")
        XCTAssertEqual(audit["p_type_ressource"] as? String, "document")
        XCTAssertEqual(audit["p_id_ressource"] as? String, documentId)
        XCTAssertEqual(audit["p_cle_s3"] as? String, objet)
        XCTAssertEqual((audit["p_details"] as? [String: Any])?["type_document"] as? String, "DIPLOME")
        XCTAssertTrue(registry.requests.allSatisfy { !$0.path.contains("/object/sign/") }, "aucune URL signée créée")
        XCTAssertTrue(registry.unmatched.isEmpty)

        let etranger = DocumentSoignant(id: documentId, typeDocument: "DIPLOME", s3Cle: "autre-utilisateur/documents/DIPLOME/1-a.pdf")
        do {
            _ = try await gateway().consulter(document: etranger, context: TestClient.context)
            XCTFail("objet hors du dossier de l'utilisateur")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.message, MessagesDocuments.consultationImpossible)
        }
    }

    func testSignerAttestationRelitLaDateServeur() async throws {
        let rpc = "/rest/v1/rpc/fn_signer_attestation_sante"
        registry.add("POST", rpc, respond: .json(200, #"{"success":true,"signe_le":"2026-11-02T10:00:00.123456+00:00"}"#))
        registry.add("GET", "/rest/v1/soignants", respond: .json(200, #"{"attestation_sante_signee_le":"2026-11-02T10:00:00.123+00:00"}"#))
        let date = try await gateway().signerAttestationSante(context: TestClient.context)
        XCTAssertEqual(date, try DateHeureParis.instantJolene("2026-11-02T10:00:00.123+00:00"), "valeur relue, jamais supposée")
        XCTAssertEqual(registry.requests(to: "/rest/v1/soignants").first?.query("select"), "attestation_sante_signee_le")

        registry.reset()
        registry.add("POST", rpc, respond: .json(200, #"{"error":"Soignant introuvable"}"#))
        do {
            _ = try await gateway().signerAttestationSante(context: TestClient.context)
            XCTFail("refus serveur")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.message, MessagesDocuments.signatureAttestationErreur)
        }
        XCTAssertEqual(registry.requests(to: "/rest/v1/soignants").count, 0)
    }

    func testCoherenceSansParametreEtLectureBestEffort() async throws {
        let rpc = "/rest/v1/rpc/fn_verifier_coherence_documents"
        registry.add("POST", rpc, respond: .json(200, #"{"coherent":false,"problemes":["Nom différent sur 1 document(s)"],"documents":[]}"#))
        let coherence = try await gateway().coherence(context: TestClient.context)
        XCTAssertEqual(coherence, CoherenceDocuments(coherent: false, problemes: ["Nom différent sur 1 document(s)"]))
        XCTAssertTrue(corps(registry.requests(to: rpc).first).isEmpty, "appel sans p_soignant_id (l.328)")
        for reponse in [StubResponse.json(403, #"{"code":"42501","message":"Accès refusé","details":null,"hint":null}"#),
                        .json(200, #"{"error":"Soignant introuvable"}"#), .networkFailure()] {
            registry.reset()
            registry.add("POST", rpc, respond: reponse)
            let lue = try await gateway().coherence(context: TestClient.context)
            XCTAssertNil(lue, "aucune bannière, jamais « session expirée »")
        }
    }
}
