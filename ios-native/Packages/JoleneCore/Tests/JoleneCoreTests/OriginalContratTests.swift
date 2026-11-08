import XCTest
@testable import JoleneCore

/// Lot 2, T8 — triple contrôle de l'original d'un contrat (`LOT2_PLAN.md` §2.5, `Contrats/OriginalContrat.swift`) :
/// SHA-256 des octets UTF-8 de `contenu_html` = `hash_document` (64 hex) = SHA-256 des octets Storage, avec
/// `storage_path` et `contenu_html_rendu_le` non nuls et aucune variable `{{…}}` (mêmes conditions que
/// `fn_signer_contrat_otp` l.56550-56558), plus le pilote (`workflows/contracts/business.ts` l.29-45) : aucune
/// signature sur une autre empreinte. Sinon un motif d'indisponibilité, jamais un original supposé.
final class OriginalContratTests: XCTestCase {
    private let html = "<!doctype html><p>Contrat d’essai — été</p>"

    private func contrat(html: String? = nil, hash: String? = nil, chemin: String? = "k-1/original-001.html",
                         renduLe: String? = "2026-11-01T14:05:00Z", id: String = "k-1") -> ContratDetail {
        let contenu = html ?? self.html
        return ContratDetail(id: id, missionId: "m-1", statut: "EN_ATTENTE_SIGNATURES", typeContrat: "CDD", contenuHtml: contenu,
                             hashDocument: hash ?? VerificationOriginal.empreinte(contenu), storagePath: chemin,
                             contenuHtmlRenduLe: renduLe, numeroContrat: "C-1")
    }

    private func motif(_ bloc: () throws -> OriginalContrat, file: StaticString = #filePath, line: UInt = #line) -> MotifOriginalIndisponible? {
        do {
            _ = try bloc()
            return nil
        } catch let erreur as ContratOriginalIndisponible {
            return erreur.motif
        } catch {
            XCTFail("erreur inattendue \(error)", file: file, line: line)
            return nil
        }
    }

    func testEmpreinteSHA256HexMinusculeDesOctetsUTF8() {
        // Vecteur NIST « abc ».
        XCTAssertEqual(VerificationOriginal.empreinte("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertTrue(VerificationOriginal.estEmpreinte(VerificationOriginal.empreinte("abc")))
        XCTAssertFalse(VerificationOriginal.estEmpreinte(VerificationOriginal.empreinte("abc").uppercased()), "regex de l'edge : minuscules")
        XCTAssertFalse(VerificationOriginal.estEmpreinte(String(repeating: "a", count: 63)))
        XCTAssertFalse(VerificationOriginal.estEmpreinte(nil))
    }

    func testOriginalControleRenduAvecSonEmpreinteEtSonNumero() throws {
        let detail = contrat()
        let original = try VerificationOriginal.verifier(detail, octetsStorage: Data(html.utf8), signatures: [])
        XCTAssertEqual(original, OriginalContrat(contratId: "k-1", html: html, empreinte: VerificationOriginal.empreinte(html),
                                                 numeroContrat: "C-1"))
    }

    func testFixtureDemoEmpreinteEgaleACelleDeLExporteur() throws {
        let fichier = try DemoFixtures.loadContrats()
        XCTAssertEqual(fichier.originaux.count, 2)
        for reference in fichier.originaux {
            let ligne = try XCTUnwrap(fichier.contrats.first { $0.id == reference.contratId })
            let octets = try DemoFixtures.originalDemo(fichier: reference.fichier)
            XCTAssertEqual(ligne.storagePath, reference.storagePath)
            XCTAssertEqual(VerificationOriginal.empreinte(try XCTUnwrap(ligne.contenuHtml)), ligne.hashDocument,
                           "SHA-256 calculé par l'exporteur")
            let original = try VerificationOriginal.verifier(ligne, octetsStorage: octets,
                                                             signatures: fichier.signatures.filter { $0.contratId == ligne.id })
            XCTAssertEqual(original.empreinte, ligne.hashDocument)
        }
    }

    func testUnOctetModifieDansStorageRendLOriginalIndisponible() {
        var octets = Data(html.utf8)
        octets[octets.count - 1] ^= 0x01
        XCTAssertEqual(motif { try VerificationOriginal.verifier(contrat(), octetsStorage: octets, signatures: []) }, .storageMismatch)
        XCTAssertEqual(motif { try VerificationOriginal.verifier(contrat(), octetsStorage: Data(), signatures: []) }, .storageMismatch)
        XCTAssertEqual(motif { try VerificationOriginal.verifier(contrat(), octetsStorage: Data((html + "\n").utf8), signatures: []) },
                       .storageMismatch, "aucune normalisation : les octets signés exactement")
    }

    func testVariableNonRendueOuContenuVide() {
        let gabarit = "<p>{{x}}</p>"
        XCTAssertEqual(motif { try VerificationOriginal.verifier(contrat(html: gabarit), octetsStorage: Data(gabarit.utf8), signatures: []) },
                       .variablesNonRendues)
        XCTAssertEqual(VerificationOriginal.motifAvantStorage(contrat(html: "  \n")), .nonFige)
    }

    func testDocumentNonFige() {
        XCTAssertEqual(VerificationOriginal.motifAvantStorage(contrat(chemin: nil)), .nonFige)
        XCTAssertEqual(VerificationOriginal.motifAvantStorage(contrat(chemin: "")), .nonFige)
        XCTAssertEqual(VerificationOriginal.motifAvantStorage(contrat(renduLe: nil)), .nonFige)
        let sansHtml = ContratDetail(id: "k-1", missionId: "m-1", statut: "EN_ATTENTE_SIGNATURES", contenuHtml: nil,
                                     hashDocument: String(repeating: "a", count: 64), storagePath: "k-1/a.html",
                                     contenuHtmlRenduLe: "2026-11-01T14:05:00Z")
        XCTAssertEqual(VerificationOriginal.motifAvantStorage(sansHtml), .nonFige)
        var sansHash = contrat()
        sansHash.hashDocument = nil
        XCTAssertEqual(VerificationOriginal.motifAvantStorage(sansHash), .nonFige)
    }

    func testEmpreinteServeurInvalideOuDifferente() {
        XCTAssertEqual(VerificationOriginal.motifAvantStorage(contrat(hash: String(repeating: "0", count: 64))), .hashMismatch)
        XCTAssertEqual(VerificationOriginal.motifAvantStorage(contrat(hash: VerificationOriginal.empreinte(html).uppercased())),
                       .hashMismatch)
        XCTAssertEqual(VerificationOriginal.motifAvantStorage(contrat(hash: "abc")), .hashMismatch)
        XCTAssertNil(VerificationOriginal.motifAvantStorage(contrat()))
    }

    func testCheminStorageHorsDuDossierDuContrat() {
        XCTAssertTrue(VerificationOriginal.cheminValide("k-1/original-001.html", contratId: "k-1"))
        XCTAssertTrue(VerificationOriginal.cheminValide("k-1/0c7e1c2a-5f3b-4a8e-9d21-7b6f3e2a1c90.html", contratId: "k-1"))
        for chemin in ["k-2/a.html", "k-1/../k-2/a.html", "k-1/a.htm", "k-1/a b.html", "/k-1/a.html", "k-1/sous/a.html",
                       "k-1/.html", "k-1/a.html?x=1", "k-1/" + String(repeating: "a", count: 300) + ".html"] {
            XCTAssertFalse(VerificationOriginal.cheminValide(chemin, contratId: "k-1"), chemin)
            XCTAssertEqual(VerificationOriginal.motifAvantStorage(contrat(chemin: chemin)), .storageMismatch, chemin)
        }
    }

    func testOriginalTropVolumineuxRefuseAvantStorage() {
        let gros = String(repeating: "a", count: VerificationOriginal.tailleMaxOctets + 1)
        XCTAssertEqual(VerificationOriginal.motifAvantStorage(contrat(html: gros)), .storageMismatch)
        XCTAssertEqual(VerificationOriginal.tailleMaxOctets, 2 * 1024 * 1024, "borne de 2 Mo (blueprint T8)")
    }

    func testSignatureSurUneAutreEmpreinte() throws {
        let autre = String(repeating: "b", count: 64)
        let signee = try JSONDecoder().decode(SignatureCertificat.self, from: Data("""
        {"id":"s-1","contrat_id":"k-1","statut_signature":"signe","signe_a":"2026-11-01T15:00:00Z","hash_document":"\(autre)"}
        """.utf8))
        XCTAssertEqual(motif { try VerificationOriginal.verifier(contrat(), octetsStorage: Data(html.utf8), signatures: [signee]) },
                       .signatureMismatch)
        let enAttente = try JSONDecoder().decode(SignatureCertificat.self, from: Data("""
        {"id":"s-2","contrat_id":"k-1","statut_signature":"otp_envoye","signe_a":null,"otp_valide_a":null,"hash_document":null}
        """.utf8))
        XCTAssertNoThrow(try VerificationOriginal.verifier(contrat(), octetsStorage: Data(html.utf8), signatures: [enAttente]),
                         "un OTP envoyé n'engage aucune empreinte")
        let otpValide = try JSONDecoder().decode(SignatureCertificat.self, from: Data("""
        {"id":"s-3","contrat_id":"k-1","statut_signature":"otp_envoye","otp_valide_a":"2026-11-01T15:00:00Z","hash_document":null}
        """.utf8))
        XCTAssertEqual(motif { try VerificationOriginal.verifier(contrat(), octetsStorage: Data(html.utf8), signatures: [otpValide]) },
                       .signatureMismatch)
    }

    // MARK: - Fichier temporaire du partage

    func testFichierTemporaireProtegeNommeParLeNumeroPuisEfface() throws {
        let original = OriginalContrat(contratId: "k-1", html: html, empreinte: VerificationOriginal.empreinte(html), numeroContrat: "C/1 é")
        let url = try FichierContratTemporaire.ecrire(original)
        XCTAssertEqual(url.lastPathComponent, "Contrat-C-1--.html", "numéro assaini : lettres ASCII, chiffres, tiret, souligné")
        XCTAssertEqual(try Data(contentsOf: url), Data(html.utf8), "octets contrôlés, tels quels")
        XCTAssertTrue(url.path.hasPrefix(FichierContratTemporaire.dossier().path))
        let valeurs = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(valeurs.isExcludedFromBackup, true)
        FichierContratTemporaire.effacer(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(FichierContratTemporaire.nomFichier(numero: nil, contratId: "k-1"), "Contrat-k-1.html")
        XCTAssertEqual(FichierContratTemporaire.nomFichier(numero: "", contratId: "k-1"), "Contrat-k-1.html")
        let autre = try FichierContratTemporaire.ecrire(original)
        FichierContratTemporaire.effacerTout()
        XCTAssertFalse(FileManager.default.fileExists(atPath: autre.path))
    }
}
