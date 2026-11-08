import XCTest
@testable import JoleneCore

/// Reçu durable d'un envoi de justificatif (blueprint lot 2 §2.5-§2.6, décision 14) : clé Storage
/// déterministe posée AVANT l'envoi, mêmes contrôles de chemin que `fn_remplacer_document_soignant`
/// (`public.sql` l.53103-53109) et `cleanup_orphan` ; aucun octet, aucune URL signée dans le reçu.
final class RecuDocumentTests: XCTestCase {
    private let userId = "0b4d2b8e-4a9f-4b1c-9e0a-7f3c1d2e5a66"
    private let ms: Int64 = 1_793_577_600_123

    private func prepare(nom: String = "Diplôme d'État.PDF", mime: MimeDocument = .pdf, taille: Int = 2_048,
                         type: String = "DIPLOME", libelle: String? = nil, existant: RecuDocument? = nil) throws -> RecuDocument {
        try RecuDocument.preparer(userId: userId, epoch: 4, typeDocument: type,
                                  fichier: FichierChoisi(nom: nom, mime: mime, tailleOctets: taille), libelle: libelle,
                                  horodatageMs: ms, existant: existant)
    }

    private func erreur(_ operation: () throws -> Void) -> RecuErreur? {
        do {
            try operation()
            return nil
        } catch let error as RecuErreur {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
            return nil
        }
    }

    // MARK: - Clé Storage

    func testCleDeterministeDuWeb() throws {
        // `src/pages/DocumentsSoignant.tsx` l.372 : `${user.id}/documents/${type}/${Date.now()}-${nomSanitise}`.
        let recu = try prepare()
        XCTAssertEqual(recu.s3Cle, "\(userId)/documents/DIPLOME/1793577600123-Diplome-d-Etat.pdf")
        XCTAssertEqual(recu.phase, .prepared)
        XCTAssertEqual(recu.mime, .pdf)
        XCTAssertEqual(recu.tailleOctets, 2_048)
        XCTAssertNil(recu.documentId)
        XCTAssertEqual(RecuDocument.domaine, "document")
    }

    func testControlesDuServeurSurLaCle() {
        XCTAssertTrue(RecuDocument.cleValide("\(userId)/documents/RIB/1-rib.pdf", userId: userId, typeDocument: "RIB"))
        XCTAssertFalse(RecuDocument.cleValide("autre/documents/RIB/1-rib.pdf", userId: userId, typeDocument: "RIB"), "hors préfixe")
        XCTAssertFalse(RecuDocument.cleValide("\(userId)/documents/DIPLOME/1-rib.pdf", userId: userId, typeDocument: "RIB"),
                       "type de document différent")
        XCTAssertFalse(RecuDocument.cleValide("\(userId)/documents/RIB/1..pdf", userId: userId, typeDocument: "RIB"), "..")
        XCTAssertFalse(RecuDocument.cleValide("\(userId)/documents/RIB/1-ri\\b.pdf", userId: userId, typeDocument: "RIB"), "antislash")
        XCTAssertFalse(RecuDocument.cleValide("\(userId)/documents/RIB/1-rib é.pdf", userId: userId, typeDocument: "RIB"),
                       "4ᵉ segment hors ^[A-Za-z0-9._-]+$")
        XCTAssertFalse(RecuDocument.cleValide("\(userId)/documents/RIB/a/b.pdf", userId: userId, typeDocument: "RIB"),
                       "exactement quatre segments côté natif")
        XCTAssertFalse(RecuDocument.cleValide("\(userId)/documents/RIB/", userId: userId, typeDocument: "RIB"), "segment vide")
        let longue = "\(userId)/documents/RIB/" + String(repeating: "a", count: 512)
        XCTAssertFalse(RecuDocument.cleValide(longue, userId: userId, typeDocument: "RIB"), "> 512 caractères")
    }

    func testMetadonneesHorsBornesDuServeurRefusees() {
        // `fn_remplacer_document_soignant` l.53110-53115 : 1 octet à 10 Mo, nom non vide ≤ 255.
        XCTAssertEqual(erreur { _ = try self.prepare(taille: 0) }, .champInvalide("tailleOctets"))
        XCTAssertEqual(erreur { _ = try self.prepare(taille: 10_485_761) }, .champInvalide("tailleOctets"))
        XCTAssertNoThrow(try prepare(taille: 10_485_760))
        XCTAssertEqual(erreur { _ = try self.prepare(type: "diplome") }, .champInvalide("typeDocument"))
        XCTAssertEqual(erreur { _ = try self.prepare(type: "RIB/../X") }, .champInvalide("typeDocument"))
        XCTAssertEqual(erreur {
            _ = try RecuDocument.preparer(userId: "", epoch: 1, typeDocument: "RIB",
                                          fichier: FichierChoisi(nom: "a.pdf", mime: .pdf, tailleOctets: 1), horodatageMs: 1)
        }, .champInvalide("userId"))
        XCTAssertEqual(erreur {
            _ = try RecuDocument.preparer(userId: "u/x", epoch: 1, typeDocument: "RIB",
                                          fichier: FichierChoisi(nom: "a.pdf", mime: .pdf, tailleOctets: 1), horodatageMs: 1)
        }, .champInvalide("userId"))
    }

    func testNomEtLibelleConservesPourLeRejeuDeLEnregistrement() throws {
        // Revue fraîche de T1 (seconde passe) : après un arrêt forcé (objet présent, aucune ligne), le rejeu de
        // `fn_remplacer_document_soignant` exige `p_nom_fichier` non vide (`public.sql` l.53110-53115) ; le web passe
        // le nom d'origine du fichier et le libellé saisi (`DocumentsSoignant.tsx` l.385-388). Le reçu v1 garde les
        // deux : aucune v2 à prévoir pour T6.
        let recu = try prepare(nom: "Diplôme d'État.PDF", libelle: "Diplôme d'infirmier")
        XCTAssertEqual(recu.nomFichier, "Diplôme d'État.PDF", "nom d'origine, comme le web (la clé porte le nom assaini)")
        XCTAssertEqual(recu.libelle, "Diplôme d'infirmier")
        XCTAssertNil(try prepare().libelle, "aucun libellé saisi")
        let relu = try RecuDocument.decoder(try recu.demarrer().stocker().encoder(), userId: userId)
        XCTAssertEqual(relu.nomFichier, "Diplôme d'État.PDF")
        XCTAssertEqual(relu.libelle, "Diplôme d'infirmier")
    }

    func testNomEtLibelleAuxBornesDuServeur() {
        // l.53112-53114 : `NULLIF(btrim(p_nom_fichier), '')` non nul, `length(p_nom_fichier) <= 255`,
        // `length(p_libelle) <= 500` ; `length` compte les points de code, `btrim` retire les espaces.
        XCTAssertEqual(erreur { _ = try self.prepare(nom: "") }, .champInvalide("nomFichier"))
        XCTAssertEqual(erreur { _ = try self.prepare(nom: "   ") }, .champInvalide("nomFichier"))
        XCTAssertNoThrow(try prepare(nom: String(repeating: "é", count: 251) + ".pdf"), "255 points de code")
        XCTAssertEqual(erreur { _ = try self.prepare(nom: String(repeating: "é", count: 252) + ".pdf") },
                       .champInvalide("nomFichier"), "256 points de code")
        XCTAssertEqual(erreur { _ = try self.prepare(nom: String(repeating: "e\u{301}", count: 126) + ".pdf") },
                       .champInvalide("nomFichier"), "130 caractères affichés mais 256 points de code")
        XCTAssertNoThrow(try prepare(libelle: ""))
        XCTAssertNoThrow(try prepare(libelle: String(repeating: "a", count: 500)))
        XCTAssertEqual(erreur { _ = try self.prepare(libelle: String(repeating: "a", count: 501)) }, .champInvalide("libelle"))
    }

    func testUnSecondEnvoiEstRefuseTantQueLePremierNEstPasReconcilie() throws {
        let enCours = try prepare()
        XCTAssertEqual(erreur { _ = try self.prepare(existant: enCours) }, .recuEnCours)
        let stocke = try enCours.demarrer().stocker()
        XCTAssertEqual(erreur { _ = try self.prepare(existant: stocke) }, .recuEnCours)
        XCTAssertNoThrow(try prepare(existant: try stocke.refuser()))
        XCTAssertNoThrow(try prepare(existant: try stocke.enregistrer(documentId: "d-1").demanderVerification()))
        var autre = enCours
        autre.userId = "autre"
        XCTAssertEqual(erreur { _ = try self.prepare(existant: autre) }, .utilisateurDifferent)
    }

    // MARK: - Transitions

    func testParcoursNominal() throws {
        let demarre = try prepare().demarrer()
        XCTAssertEqual(demarre.phase, .started)
        let stocke = try demarre.stocker()
        XCTAssertEqual(stocke.phase, .stored)
        let enregistre = try stocke.enregistrer(documentId: "d-1")
        XCTAssertEqual(enregistre.phase, .registered)
        XCTAssertEqual(enregistre.documentId, "d-1")
        XCTAssertFalse(enregistre.estTermine, "verify-document reste à demander une fois")
        let verifie = try enregistre.demanderVerification()
        XCTAssertEqual(verifie.phase, .verificationDemandee)
        XCTAssertTrue(verifie.estTermine)
    }

    func testReconciliationParRelecture() throws {
        // §2.5 : ligne relue par s3_cle → enregistré (même après un envoi incertain) ; objet présent sans
        // ligne → stocké (fn_remplacer idempotente) ; ni l'un ni l'autre → non envoyé.
        let demarre = try prepare().demarrer()
        XCTAssertEqual(try demarre.enregistrer(documentId: "d-2").phase, .registered)
        XCTAssertEqual(try demarre.stocker().phase, .stored)
        XCTAssertEqual(try demarre.marquerNonEnvoye().phase, .notSent)
        XCTAssertEqual(try prepare().marquerNonEnvoye().phase, .notSent, "hors ligne : rien n'est parti")
    }

    func testTransitionsInterdites() throws {
        let prepare = try prepare()
        XCTAssertEqual(erreur { _ = try prepare.stocker() }, .transitionInterdite(de: "prepared", vers: "stored"))
        XCTAssertEqual(erreur { _ = try prepare.enregistrer(documentId: "d") }, .transitionInterdite(de: "prepared", vers: "registered"))
        XCTAssertEqual(erreur { _ = try prepare.refuser() }, .transitionInterdite(de: "prepared", vers: "refused"))
        let stocke = try prepare.demarrer().stocker()
        XCTAssertEqual(erreur { _ = try stocke.demarrer() }, .transitionInterdite(de: "stored", vers: "started"), "jamais un second envoi")
        XCTAssertEqual(erreur { _ = try stocke.marquerNonEnvoye() }, .transitionInterdite(de: "stored", vers: "not_sent"),
                       "l'objet existe : il est enregistré ou nettoyé, jamais oublié")
        XCTAssertEqual(erreur { _ = try stocke.demanderVerification() },
                       .transitionInterdite(de: "stored", vers: "verification_demandee"), "verify-document exige une ligne")
        XCTAssertEqual(erreur { _ = try stocke.enregistrer(documentId: " ") }, .champInvalide("documentId"))
        let enregistre = try stocke.enregistrer(documentId: "d-1")
        XCTAssertEqual(erreur { _ = try enregistre.refuser() }, .transitionInterdite(de: "registered", vers: "refused"),
                       "une ligne enregistrée n'est jamais nettoyée par le client")
        let verifie = try enregistre.demanderVerification()
        XCTAssertEqual(erreur { _ = try verifie.demanderVerification() },
                       .transitionInterdite(de: "verification_demandee", vers: "verification_demandee"),
                       "verify-document une seule fois par document")
        let refuse = try stocke.refuser()
        XCTAssertEqual(erreur { _ = try refuse.enregistrer(documentId: "d-1") }, .transitionInterdite(de: "refused", vers: "registered"))
    }

    // MARK: - Encodage durable

    func testAucunOctetNiURLDansLeRecu() throws {
        let recu = try prepare().demarrer().stocker().enregistrer(documentId: "d-1")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try recu.encoder()) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["version", "user_id", "epoch", "s3_cle", "type_document", "mime", "taille_octets",
                                        "nom_fichier", "document_id", "phase"])
        let avecLibelle = try XCTUnwrap(JSONSerialization.jsonObject(with: try prepare(libelle: "Diplôme").encoder()) as? [String: Any])
        XCTAssertEqual(avecLibelle["libelle"] as? String, "Diplôme")
        XCTAssertEqual(avecLibelle["nom_fichier"] as? String, "Diplôme d'État.PDF")
        XCTAssertEqual(json["mime"] as? String, "application/pdf")
        XCTAssertEqual(json["phase"] as? String, "registered")
        let labels = Mirror(reflecting: recu).children.compactMap(\.label).map { $0.lowercased() }
        for interdit in ["octets", "data", "url", "signed", "bytes"] {
            XCTAssertFalse(labels.contains { $0 == interdit || $0.hasPrefix(interdit) }, "champ interdit : \(interdit)")
        }
    }

    func testAllerRetourEtRelectureFailClosed() throws {
        let recu = try prepare().demarrer()
        let data = try recu.encoder()
        XCTAssertEqual(try RecuDocument.decoder(data, userId: userId), recu)
        XCTAssertEqual(erreur { _ = try RecuDocument.decoder(data, userId: "autre") }, .utilisateurDifferent)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["s3_cle"] = "autre/documents/DIPLOME/1-a.pdf"
        XCTAssertEqual(erreur { _ = try RecuDocument.decoder(try JSONSerialization.data(withJSONObject: json), userId: self.userId) },
                       .illisible, "clé hors préfixe : reçu altéré")
        json["s3_cle"] = recu.s3Cle
        json["phase"] = "registered"
        XCTAssertEqual(erreur { _ = try RecuDocument.decoder(try JSONSerialization.data(withJSONObject: json), userId: self.userId) },
                       .illisible, "registered sans document_id")
        json["phase"] = "started"
        json["version"] = 9
        XCTAssertEqual(erreur { _ = try RecuDocument.decoder(try JSONSerialization.data(withJSONObject: json), userId: self.userId) },
                       .illisible)
        json["version"] = 1
        json["nom_fichier"] = " "
        XCTAssertEqual(erreur { _ = try RecuDocument.decoder(try JSONSerialization.data(withJSONObject: json), userId: self.userId) },
                       .illisible, "nom de fichier vide : rejeu impossible")
        json["nom_fichier"] = recu.nomFichier
        json["libelle"] = String(repeating: "a", count: 501)
        XCTAssertEqual(erreur { _ = try RecuDocument.decoder(try JSONSerialization.data(withJSONObject: json), userId: self.userId) },
                       .illisible, "libellé hors borne")
        json["libelle"] = nil
        json["url_signee"] = "https://example.invalid/x"
        XCTAssertEqual(erreur { _ = try RecuDocument.decoder(try JSONSerialization.data(withJSONObject: json), userId: self.userId) },
                       .illisible, "clé inattendue")
    }

    func testNomEtLibelleImmuablesPourUnMemeEssai() throws {
        let prepare = try prepare(libelle: "Diplôme")
        var renomme = try prepare.demarrer()
        renomme.nomFichier = "autre.pdf"
        XCTAssertEqual(erreur { try renomme.verifierSuccession(apres: prepare) }, .champInvalide("nomFichier"))
        var relibelle = try prepare.demarrer()
        relibelle.libelle = nil
        XCTAssertEqual(erreur { try relibelle.verifierSuccession(apres: prepare) }, .champInvalide("libelle"))
    }
}
