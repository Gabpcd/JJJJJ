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

    /// Nom assaini comme le web (`sanitiserNomFichier` garde la casse) : « Diplôme.JPG » → « Diplome.jpg ».
    private var cle: String { "\(uid)/documents/DIPLOME/1793577600000-Diplome.jpg" }
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

    /// `verify-document` part sans être attendu par le chemin critique (revue fraîche de T6, M2) : le test attend son
    /// arrivée — ou constate son absence — avant de conclure, pour qu'aucune requête tardive n'atteigne le test suivant.
    private func attendreRequetes(_ nombre: Int, delai: TimeInterval = 2, _ compte: () -> Int) async {
        let limite = Date().addingTimeInterval(delai)
        while compte() < nombre, Date() < limite { try? await Task.sleep(nanoseconds: 5_000_000) }
        try? await Task.sleep(nanoseconds: 50_000_000)
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
          "s3_bucket":"jolene-documents","type_mime":"application/pdf","taille_octets":2048,"libelle":null,"verification_attempt_id":null,
          "profession_certifiee":"IADE"}]
        """))

        let dossier = try await gateway().dossier(context: TestClient.context)

        XCTAssertEqual(dossier.profil, SoignantExigencesDocuments(profession: "IADE", typeExercice: "SALARIE", rppsVerifie: true, adeliVerifie: false))
        XCTAssertEqual(dossier.exigences.map(\.typeDocument), ["DIPLOME"], "salarié : pas de RCP ; pièce de santé jamais proposée ; IADE garde le diplôme")
        XCTAssertEqual(dossier.documents.first?.professionCertifiee, "IADE")
        XCTAssertEqual(dossier.documents.first?.valideDepuis, "2020-06-30")
        XCTAssertEqual(dossier.documents.first?.s3Bucket, "jolene-documents", "bucket lu pour la consultation (`doc.s3_bucket`, l.438)")
        XCTAssertTrue(SupabaseDocumentsGateway.selectionDocuments.split(separator: ",").contains("s3_bucket"))
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
        XCTAssertEqual(docs.query("supprime_le"), "is.NULL")
        XCTAssertEqual(docs.query("revoque_le"), "is.NULL")
        XCTAssertEqual(docs.query("order"), "televerse_le.desc.nullsfirst", "`order('televerse_le', { ascending: false })` : NULLS FIRST de PostgreSQL")
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

    func testEnvoiUploadSansEcraserEnregistrePuisLanceLaVerificationUneFoisSansLAttendre() async throws {
        stubUpload()
        stubRemplacer(#"{"success":true,"document_id":"\#(documentId)","idempotent":false}"#)
        stubVerify(.json(200, #"{"success":true,"verdict":"VERIFIE","analysis":{"motif_rejet":null}}"#))

        let issue = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)

        XCTAssertEqual(issue, .verificationDemandee(documentId: documentId))
        XCTAssertEqual(registry.requests(to: lignes).count, 0,
                       "le chemin critique n'attend ni la vérification ni sa relecture : le suivi relit la ligne (revue fraîche, M2)")
        await attendreRequetes(1) { appelsVerification().count }
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
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testLibelleAbsentEnvoyeVideCommeLeWeb() async throws {
        stubUpload()
        stubRemplacer(#"{"success":true,"document_id":"\#(documentId)","idempotent":false}"#)
        stubVerify(.json(200, #"{"success":true,"verdict":"EN_ATTENTE"}"#))
        _ = try await gateway().envoyer(recu: try recuDemarre(libelle: nil), octets: jpeg, context: TestClient.context)
        XCTAssertEqual(corps(registry.requests(to: remplacer).first)["p_libelle"] as? String, "", "p_libelle: libelle || ''")
        await attendreRequetes(1) { appelsVerification().count }
    }

    /// 429 (ou 503) de `verify-document` : jamais attendu, jamais relancé. L'issue « vérification manuelle » est tirée du
    /// statut relu par le suivi du modèle (`DocumentsModelTests`, revue fraîche m11).
    func testVerification429NonAttendueJamaisRelancee() async throws {
        for reponse in [StubResponse.json(429, #"{"error":"Trop de vérifications. Réessayez dans 1 minute."}"#),
                        .json(503, #"{"error":"Service de vérification automatique non configuré"}"#)] {
            registry.reset()
            stubUpload()
            stubRemplacer(#"{"success":true,"document_id":"\#(documentId)","idempotent":false}"#)
            stubVerify(reponse)

            let issue = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)

            XCTAssertEqual(issue, .verificationDemandee(documentId: documentId), "statut \(reponse.status) : verdict relu par le suivi")
            await attendreRequetes(1) { appelsVerification().count }
            XCTAssertEqual(appelsVerification().count, 1, "statut \(reponse.status) : aucun renvoi")
            XCTAssertEqual(registry.requests(to: remplacer).count, 1)
        }
    }

    /// Seconde revue fraîche de T6, m-d : l'issue de `verify-document`, jamais attendue par l'envoi, est observable sans
    /// relance — vrai sur une erreur (429, 403, 503 : le web annonce aussitôt « vérification manuelle en attente »,
    /// l.413-425), faux sur une réponse, nil pour un document dont ce port n'a lancé aucune vérification.
    func testIssueDeLaVerificationObservableSansRelance() async throws {
        for (reponse, echec) in [(StubResponse.json(429, #"{"error":"Trop de vérifications. Réessayez dans 1 minute."}"#), true),
                                 (.json(403, #"{"error":"Accès refusé"}"#), true),
                                 (.json(503, #"{"error":"Service de vérification automatique non configuré"}"#), true),
                                 (.json(200, #"{"success":true,"verdict":"VERIFIE"}"#), false)] {
            registry.reset()
            stubUpload()
            stubRemplacer(#"{"success":true,"document_id":"\#(documentId)","idempotent":false}"#)
            stubVerify(reponse)
            let passerelle = gateway()

            let issue = try await passerelle.envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)
            XCTAssertEqual(issue, .verificationDemandee(documentId: documentId))
            let observee = await passerelle.verificationEchouee(documentId: documentId)

            XCTAssertEqual(observee, echec, "statut \(reponse.status)")
            let inconnue = await passerelle.verificationEchouee(documentId: "00000000-0000-4000-8000-000000000000")
            XCTAssertNil(inconnue, "aucune vérification lancée pour ce document")
            await attendreRequetes(1) { appelsVerification().count }
            XCTAssertEqual(appelsVerification().count, 1, "statut \(reponse.status) : observée, jamais relancée")
        }
    }

    /// Correctif 4c84aa0e (m8 a) : un envoi annulé juste après l'enregistrement (délai de l'appelant) ne lance aucune
    /// vérification ; la réconciliation relira la ligne et proposera « Revérifier ».
    func testEnvoiAnnuleApresEnregistrementAucuneVerification() async throws {
        stubUpload()
        stubRemplacer(#"{"success":true,"document_id":"\#(documentId)","idempotent":false}"#)
        stubVerify(.json(200, #"{"success":true,"verdict":"VERIFIE"}"#))
        var annulable = gateway()
        annulable.avantVerification = { withUnsafeCurrentTask { $0?.cancel() } }
        let recu = try recuDemarre()
        let contexte = TestClient.context
        let passerelle = annulable
        let octets = jpeg

        let issue = try await Task { try await passerelle.envoyer(recu: recu, octets: octets, context: contexte) }.value

        XCTAssertEqual(issue, .incertain, "annulé : rien n'est annoncé, la réconciliation relit")
        XCTAssertEqual(registry.requests(to: remplacer).count, 1)
        await attendreRequetes(1, delai: 0.3) { appelsVerification().count }
        XCTAssertEqual(appelsVerification().count, 0, "aucune vérification après l'annulation")
    }

    /// m8 (c) : 409 « déjà existant » de Storage → issue incertaine, puis réconciliation : objet présent, aucune ligne →
    /// enregistrement rejoué sous la même clé et vérification une seule fois, jamais de second upload.
    func testUpload409IncertainPuisReconciliationRejoueUneFois() async throws {
        stubUpload(.json(409, #"{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}"#))
        let incertain = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)
        XCTAssertEqual(incertain, .incertain)
        XCTAssertEqual(registry.requests(to: remplacer).count, 0)

        registry.add("GET", lignes, respond: .json(200, "[]"))
        registry.add("HEAD", cheminObjet, respond: .json(200, ""))
        stubRemplacer(#"{"success":true,"document_id":"\#(documentId)","idempotent":false}"#)
        stubVerify(.json(200, #"{"success":true,"verdict":"VERIFIE"}"#))

        let reconcilie = try await gateway().reconcilier(recu: try recuDemarre(), context: TestClient.context)

        XCTAssertEqual(reconcilie, .verificationDemandee(documentId: documentId))
        XCTAssertEqual(registry.requests(to: cheminObjet).map(\.method), ["POST", "HEAD"], "un seul upload")
        XCTAssertEqual(corps(registry.requests(to: remplacer).first)["p_s3_cle"] as? String, cle)
        await attendreRequetes(1) { appelsVerification().count }
        XCTAssertEqual(appelsVerification().count, 1)
        XCTAssertEqual(appelsNettoyage().count, 0)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    /// m5 : session expirée pendant l'enregistrement (`NON_AUTHENTIFIE` jsonb, `PGRST301` JWT) → `.unauthorized`, ni
    /// nettoyage (l'objet sera rattaché après reconnexion, par réconciliation) ni vérification.
    func testSessionExpireeALEnregistrementSansNettoyage() async throws {
        for reponse in [StubResponse.json(200, #"{"success":false,"error_code":"NON_AUTHENTIFIE"}"#),
                        .json(401, #"{"code":"PGRST301","message":"JWT expired","details":null,"hint":null}"#)] {
            registry.reset()
            stubUpload()
            registry.add("POST", remplacer, respond: reponse)
            registry.add("POST", verify, respond: .json(200, #"{"success":true}"#))
            do {
                _ = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)
                XCTFail("statut \(reponse.status) : session expirée attendue")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .unauthorized, "statut \(reponse.status)")
                XCTAssertEqual(erreur.message, SupabaseErrorMapping.unauthorizedMessage)
            }
            XCTAssertEqual(registry.requests(to: verify).count, 0, "statut \(reponse.status) : ni nettoyage ni vérification")
        }
    }

    /// m5 : jeton refusé par Storage (`InvalidJWT` en HTTP 400) → session expirée, jamais `STOCKAGE_400`.
    func testJetonRefuseParStorageSessionExpiree() async throws {
        stubUpload(.json(400, #"{"statusCode":"400","error":"InvalidJWT","message":"\"exp\" claim timestamp check failed"}"#))
        do {
            _ = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)
            XCTFail("session expirée attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
        XCTAssertEqual(registry.requests(to: remplacer).count, 0)
        XCTAssertEqual(SupabaseDocumentsGateway.classerEchecUpload(StorageError(statusCode: "400", message: "Bucket not found", error: "Bucket not found")),
                       .refuse("STOCKAGE_400"), "un autre 400 reste un refus")
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
        stubUpload(.networkFailure(.cannotFindHost))
        let jamaisPartie = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)
        XCTAssertEqual(jamaisPartie, .nonEnvoye, "hôte introuvable, requête jamais partie : nouvelle sélection")

        // Seconde revue fraîche de T6, m-g : sur iOS, -1009 (`notConnectedToInternet`) peut survenir en cours de
        // transfert. Ce test l'attendait « non envoyé » (reçu effacé, objet possiblement orphelin) : il est incertain,
        // et le HEAD de la réconciliation tranche.
        registry.reset()
        stubUpload(.networkFailure(.notConnectedToInternet))
        let horsLigne = try await gateway().envoyer(recu: try recuDemarre(), octets: jpeg, context: TestClient.context)
        XCTAssertEqual(horsLigne, .incertain, "connexion perdue, peut-être en cours de transfert : réconciliation par exists(path:)")
        XCTAssertEqual(SupabaseDocumentsGateway.classerEchecUpload(URLError(.cannotConnectToHost)), .nonEnvoye)
        XCTAssertEqual(SupabaseDocumentsGateway.classerEchecUpload(URLError(.dnsLookupFailed)), .nonEnvoye)

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
        registry.add("GET", lignes, respond: .json(200, "[]"))
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
        let relecture = try XCTUnwrap(registry.requests(to: lignes).first)
        XCTAssertEqual(relecture.query("select"), PreuveDocument.selection)
        XCTAssertEqual(relecture.query("s3_cle"), "eq.\(cle)")
        XCTAssertEqual(relecture.query("soignant_id"), "eq.\(uid)")
        XCTAssertEqual(relecture.query("s3_bucket"), "eq.jolene-documents")
        XCTAssertEqual(registry.requests(to: lignes).count, 1, "aucune relecture après l'enregistrement : le suivi relit")
        await attendreRequetes(1) { appelsVerification().count }
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
        // Seconde revue fraîche de T6, m-c : issue dérivée du statut relu — une pièce déjà jugée n'est jamais annoncée
        // « vérification en cours » ; une revue manuelle donne « vérification manuelle en attente ».
        for (statut, attendue) in [("VERIFIE", IssueEnvoiDocument.verdictRendu(documentId: documentId)),
                                   ("REJETE", .verdictRendu(documentId: documentId)),
                                   ("REVUE_MANUELLE_REQUISE", .enregistre(documentId: documentId))] {
            registry.reset()
            stubPreuve(statut: statut, tentative: "a-1")
            let relue = try await gateway().reconcilier(recu: try recuDemarre(), context: TestClient.context)
            XCTAssertEqual(relue, attendue, statut)
        }
        XCTAssertEqual(registry.requests(to: verify).count, 0)
        XCTAssertEqual(registry.requests(to: remplacer).count, 0)
        XCTAssertEqual(registry.requests(to: cheminObjet).count, 0)
    }

    /// m7 : objet absent à la relecture → « non envoyé », puis `cleanup_orphan` best-effort sur la clé : un upload qui
    /// aurait abouti côté serveur après le HEAD ne laisse pas une pièce d'identité non référencée dans Storage.
    func testReconciliationObjetAbsentNonEnvoyeEtNettoyage() async throws {
        registry.add("GET", lignes, respond: .json(200, "[]"))
        registry.add("HEAD", cheminObjet, respond: .json(404, ""))
        registry.add("POST", verify, where: { Self.corps($0)["action"] as? String == "cleanup_orphan" },
                     respond: .json(200, #"{"success":true}"#))
        let issue = try await gateway().reconcilier(recu: try recuDemarre(), context: TestClient.context)
        XCTAssertEqual(issue, .nonEnvoye)
        XCTAssertEqual(registry.requests(to: remplacer).count, 0)
        XCTAssertEqual(appelsNettoyage().count, 1)
        XCTAssertEqual(corps(appelsNettoyage().first)["s3_cle"] as? String, cle)
        XCTAssertEqual(appelsVerification().count, 0)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    /// m5 : relecture refusée pour jeton expiré (`PGRST301`) → session expirée, jamais une issue incertaine sans fin.
    func testReconciliationJetonExpireSessionExpiree() async throws {
        registry.add("GET", lignes, respond: .json(401, #"{"code":"PGRST301","message":"JWT expired","details":null,"hint":null}"#))
        do {
            _ = try await gateway().reconcilier(recu: try recuDemarre(), context: TestClient.context)
            XCTFail("session expirée attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
        XCTAssertEqual(registry.requests(to: cheminObjet).count, 0)
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
        // m6 : `messageErreurEdgeFn` lit `error || message || motif` (src/lib/erreurs.ts l.574).
        for (json, attendu) in [(#"{"message":"Document introuvable"}"#, "Document introuvable"),
                                (#"{"error":"","motif":"Type de document non reconnu"}"#, "Type de document non reconnu"),
                                (#"{"detail":"x"}"#, MessagesDocuments.verificationImpossible)] {
            registry.reset()
            stubVerify(.json(400, json))
            do {
                _ = try await gateway().reverifier(documentId: documentId, context: TestClient.context)
                XCTFail("\(json) : refus")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.message, attendu, json)
                XCTAssertEqual(erreur.kind, .unknown)
            }
        }
        // m5 : 401 → session expirée, jamais un refus ordinaire.
        registry.reset()
        stubVerify(.json(401, #"{"error":"Non authentifié"}"#))
        do {
            _ = try await gateway().reverifier(documentId: documentId, context: TestClient.context)
            XCTFail("401 : session expirée")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
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

    /// m1 : une pièce envoyée avant 02e957ea (2026-03-17, clé `<uid>/<TYPE>/<ms>_<nom>`) reste consultable : seule la
    /// politique Storage compte (`fn_peut_gerer_objet_jolene` : premier segment = uid), bucket lu dans la ligne
    /// (`doc.s3_bucket || 'jolene-documents'`, `DocumentsSoignant.tsx` l.438).
    func testConsultationDUnePieceAncienneEtBucketDeLaLigne() async throws {
        let pdf = Data("%PDF-1.4 ancien".utf8)
        let ancienne = "\(uid)/DIPLOME/1710000000000_diplome.pdf"
        registry.add("GET", "/storage/v1/object/jolene-documents/\(ancienne)",
                     respond: StubResponse(status: 200, headers: ["Content-Type": "application/pdf"], body: pdf, failure: nil))
        registry.add("POST", "/rest/v1/rpc/fn_ecrire_audit_safe", respond: .json(200, #"{"success":true}"#))
        var document = DocumentSoignant(id: documentId, typeDocument: "DIPLOME", s3Cle: ancienne, nomFichier: "diplome.pdf",
                                        typeMime: "application/pdf")
        document.s3Bucket = "jolene-documents"

        let fichier = try await gateway().consulter(document: document, context: TestClient.context)
        defer { ConsultationDocuments.effacerTout() }

        XCTAssertEqual(try Data(contentsOf: fichier), pdf)
        XCTAssertEqual(corps(registry.requests(to: "/rest/v1/rpc/fn_ecrire_audit_safe").first)["p_cle_s3"] as? String, ancienne)
        XCTAssertTrue(registry.unmatched.isEmpty)

        for refusee in ["\(uid)/../autre/DIPLOME/1-a.pdf", "\(uid)", "/\(uid)/documents/DIPLOME/1-a.pdf", "\(uid)//DIPLOME/1-a.pdf"] {
            registry.reset()
            let suspecte = DocumentSoignant(id: documentId, typeDocument: "DIPLOME", s3Cle: refusee)
            do {
                _ = try await gateway().consulter(document: suspecte, context: TestClient.context)
                XCTFail("\(refusee) : refus attendu")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.message, MessagesDocuments.consultationImpossible, refusee)
            }
            XCTAssertTrue(registry.requests.isEmpty, "\(refusee) : aucun téléchargement")
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
