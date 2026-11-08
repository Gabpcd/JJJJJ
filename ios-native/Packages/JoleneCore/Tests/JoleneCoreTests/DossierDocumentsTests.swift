import XCTest
@testable import JoleneCore

/// Règles d'affichage du dossier documentaire (lot 2 T6), portées de `src/pages/DocumentsSoignant.tsx` :
/// exigences filtrées (l.205, règle golden de T2b), `docsRequis` critiques (l.236), pièce valide (l.237-239),
/// prochaine étape (l.243-246), expiration proche (l.279-283), REJETE avant EXPIRE (l.659-664), RCP libérale
/// (l.613-617), ordre critiques puis optionnelles (l.521-524).
final class DossierDocumentsTests: XCTestCase {
    /// Horloge de référence : 2026-11-02T00:00:00Z (`DemoWorld.fixedNow`).
    private let maintenant = DemoWorld.fixedNow

    private func regle(_ type: String, critique: Bool = true, exercice: String = "TOUS", profession: String = "IDE") -> ExigenceDocument {
        ExigenceDocument(id: "r-\(type)-\(profession)", profession: profession, typeDocument: type, estCritique: critique,
                         typeExerciceRequis: exercice)
    }

    private var regles: [ExigenceDocument] {
        [regle("CARTE_IDENTITE"), regle("DIPLOME"), regle("RCP_ASSURANCE", exercice: "LIBERAL_ONLY"),
         regle("RIB", critique: false, exercice: "LIBERAL_ONLY"), regle("ATTESTATION_EMPLOYEUR", critique: false, exercice: "SALARIE_ONLY"),
         regle("VACCINATIONS"), regle("MEDECINE_TRAVAIL"), regle("CARTE_IDENTITE", profession: "AS")]
    }

    private let profilMixte = SoignantExigencesDocuments(profession: "IDE", typeExercice: "MIXTE", rppsVerifie: false, adeliVerifie: false)

    private var documents: [DocumentSoignant] {
        [DocumentSoignant(id: "d-ci", typeDocument: "CARTE_IDENTITE", valideJusqua: "2026-10-01", statutVerification: "REJETE",
                          motifRejet: "Document illisible"),
         DocumentSoignant(id: "d-dip", typeDocument: "DIPLOME", statutVerification: "VERIFIE"),
         DocumentSoignant(id: "d-rcp", typeDocument: "RCP_ASSURANCE", valideJusqua: "2026-11-14", statutVerification: "VERIFIE"),
         DocumentSoignant(id: "d-rib", typeDocument: "RIB", valideJusqua: "2026-10-15", statutVerification: "EXPIRE")]
    }

    private func dossier(profil: SoignantExigencesDocuments? = nil, documents: [DocumentSoignant]? = nil) -> DossierDocuments {
        DossierDocuments.assembler(profil: profil ?? profilMixte, regles: regles, documents: documents ?? self.documents,
                                   attestationSanteSigneeLe: nil)
    }

    func testExigencesFiltreesMixteCumuleEtTypesExclusJamaisProposes() {
        let d = dossier()
        XCTAssertEqual(d.exigences.map(\.typeDocument), ["CARTE_IDENTITE", "DIPLOME", "RCP_ASSURANCE", "RIB", "ATTESTATION_EMPLOYEUR"],
                       "MIXTE cumule LIBERAL_ONLY et SALARIE_ONLY ; autre profession et pièces de santé écartées")
        for exclu in ["VACCINATIONS", "MEDECINE_TRAVAIL", "ARRET_MALADIE", "AUTRE"] {
            XCTAssertFalse(d.peutEnvoyer(typeDocument: exclu), "\(exclu) jamais proposé à l'envoi")
        }
        XCTAssertTrue(d.peutEnvoyer(typeDocument: "DIPLOME"))
        let salarie = dossier(profil: SoignantExigencesDocuments(profession: "IDE", typeExercice: "SALARIE", rppsVerifie: false, adeliVerifie: false))
        XCTAssertEqual(salarie.exigences.map(\.typeDocument), ["CARTE_IDENTITE", "DIPLOME", "ATTESTATION_EMPLOYEUR"])
        XCTAssertEqual(salarie.alerteRcp(maintenant: maintenant), nil, "RCP exigée en libéral et en mixte seulement")
    }

    func testDispenseDuDiplomeParLeRPPS() {
        let rpps = dossier(profil: SoignantExigencesDocuments(profession: "IDE", typeExercice: "MIXTE", rppsVerifie: true, adeliVerifie: false))
        XCTAssertFalse(rpps.exigences.map(\.typeDocument).contains("DIPLOME"))
        let iade = DossierDocuments.assembler(
            profil: SoignantExigencesDocuments(profession: "IADE", typeExercice: "SALARIE", rppsVerifie: true, adeliVerifie: false),
            regles: [regle("DIPLOME", profession: "IADE")], documents: [], attestationSanteSigneeLe: nil)
        XCTAssertEqual(iade.exigences.map(\.typeDocument), ["DIPLOME"], "le RPPS ne dispense pas du diplôme de spécialité")
    }

    func testRejetePrimeSurExpireEtEtatParExigence() throws {
        let d = dossier()
        let parType = Dictionary(uniqueKeysWithValues: d.exigences.map { ($0.typeDocument, d.etat(de: $0, maintenant: maintenant)) })
        guard case let .rejetee(ci) = try XCTUnwrap(parType["CARTE_IDENTITE"]) else {
            return XCTFail("REJETE avec une date passée reste Rejeté (l.661-664)")
        }
        XCTAssertEqual(ci.motifRejet, "Document illisible")
        XCTAssertEqual(parType["DIPLOME"], .presente(documents[1], diplomeSpecialiseAConfirmer: false))
        XCTAssertEqual(parType["RCP_ASSURANCE"], .presente(documents[2], diplomeSpecialiseAConfirmer: false))
        XCTAssertEqual(parType["RIB"], .expiree(documents[3]))
        XCTAssertEqual(parType["ATTESTATION_EMPLOYEUR"], .manquante)
    }

    func testPiecesValidesProchaineEtapeEtManquants() {
        let d = dossier()
        XCTAssertEqual(d.exigencesCritiques.map(\.typeDocument), ["CARTE_IDENTITE", "DIPLOME", "RCP_ASSURANCE"])
        XCTAssertEqual(d.exigencesValidees(maintenant: maintenant).map(\.typeDocument), ["DIPLOME", "RCP_ASSURANCE"])
        XCTAssertEqual(d.nombreManquants(maintenant: maintenant), 1)
        XCTAssertEqual(d.prochaineExigence(maintenant: maintenant)?.typeDocument, "CARTE_IDENTITE")
        // Le 15 novembre, la RCP n'est plus valide : elle redevient une étape.
        let apres = DemoWorld.fixedNow.addingTimeInterval(13 * 86_400)
        XCTAssertEqual(d.exigencesValidees(maintenant: apres).map(\.typeDocument), ["DIPLOME"])
        XCTAssertEqual(d.alerteRcp(maintenant: apres), .expiree)
        var complet = documents
        complet[0] = DocumentSoignant(id: "d-ci2", typeDocument: "CARTE_IDENTITE", statutVerification: "VERIFIE")
        XCTAssertNil(dossier(documents: complet).prochaineExigence(maintenant: maintenant), "tout est valide : aucune étape")
        XCTAssertEqual(dossier(documents: complet).nombreManquants(maintenant: maintenant), 0)
    }

    func testExpirationProcheMoinsDeTrenteJours() {
        let d = dossier(documents: documents + [
            DocumentSoignant(id: "d-30", typeDocument: "AUTRE", valideJusqua: "2026-12-02", statutVerification: "VERIFIE"),
            DocumentSoignant(id: "d-29", typeDocument: "KBIS", valideJusqua: "2026-12-01", statutVerification: "VERIFIE"),
            DocumentSoignant(id: "d-att", typeDocument: "RIB", valideJusqua: "2026-11-10", statutVerification: "EN_ATTENTE"),
        ])
        XCTAssertEqual(d.expirantBientot(maintenant: maintenant).map(\.id), ["d-rcp", "d-29"],
                       "VERIFIE, non expiré, moins de 30 jours pleins (date-fns `differenceInDays`)")
        XCTAssertEqual(DossierDocuments.joursRestants(documents[2], maintenant: maintenant), 12)
        XCTAssertNil(DossierDocuments.joursRestants(DocumentSoignant(id: "x", typeDocument: "RIB"), maintenant: maintenant))
    }

    func testDiplomeDeSpecialiteAConfirmer() {
        let d = DossierDocuments.assembler(
            profil: SoignantExigencesDocuments(profession: "IADE", typeExercice: "SALARIE", rppsVerifie: false, adeliVerifie: false),
            regles: [regle("DIPLOME", profession: "IADE")],
            documents: [DocumentSoignant(id: "d-1", typeDocument: "DIPLOME", statutVerification: "VERIFIE", professionCertifiee: "IDE")],
            attestationSanteSigneeLe: nil)
        XCTAssertEqual(d.etat(de: d.exigences[0], maintenant: maintenant),
                       .presente(d.documents[0], diplomeSpecialiseAConfirmer: true))
        XCTAssertEqual(d.exigencesValidees(maintenant: maintenant), [], "diplôme non certifié IADE : pas valide")
    }

    func testAlerteRcpLiberaleEtMixte() {
        XCTAssertNil(dossier().alerteRcp(maintenant: maintenant), "RCP vérifiée et valide")
        XCTAssertEqual(dossier(documents: []).alerteRcp(maintenant: maintenant), .manquante)
        let enAttente = [DocumentSoignant(id: "d", typeDocument: "RCP_ASSURANCE", statutVerification: "EN_ATTENTE")]
        XCTAssertEqual(dossier(documents: enAttente).alerteRcp(maintenant: maintenant), .manquante)
        let expiree = [DocumentSoignant(id: "d", typeDocument: "RCP_ASSURANCE", valideJusqua: "2026-10-01", statutVerification: "REJETE")]
        XCTAssertEqual(dossier(documents: expiree).alerteRcp(maintenant: maintenant), .expiree, "date passée, quel que soit le statut (l.616)")
    }

    func testOrdreCritiquesPuisOptionnellesEtPieceLaPlusRecente() {
        let d = DossierDocuments.assembler(profil: profilMixte,
                                           regles: [regle("RIB", critique: false), regle("DIPLOME"), regle("KBIS", critique: false),
                                                    regle("CARTE_IDENTITE")],
                                           documents: [DocumentSoignant(id: "recent", typeDocument: "DIPLOME", statutVerification: "EN_ATTENTE"),
                                                       DocumentSoignant(id: "ancien", typeDocument: "DIPLOME", statutVerification: "VERIFIE")],
                                           attestationSanteSigneeLe: "2026-10-01T09:00:00+00:00")
        XCTAssertEqual(d.exigencesOrdonnees.map(\.typeDocument), ["DIPLOME", "CARTE_IDENTITE", "RIB", "KBIS"])
        XCTAssertEqual(d.document(pour: "DIPLOME")?.id, "recent", "la plus récente, comme `mesDocuments.find`")
        XCTAssertEqual(d.attestationSanteSigneeLe, "2026-10-01T09:00:00+00:00")
    }

    func testSansProfilAucuneExigence() {
        let vide = DossierDocuments.assembler(profil: nil, regles: regles, documents: documents, attestationSanteSigneeLe: nil)
        XCTAssertEqual(vide.exigences, [])
        XCTAssertEqual(vide.documents, [], "sans dossier professionnel, aucune pièce n'est chargée (l.186-191)")
        XCTAssertNil(vide.prochaineExigence(maintenant: maintenant))
        XCTAssertFalse(vide.peutEnvoyer(typeDocument: "DIPLOME"))
    }

    /// Preuve d'enregistrement relue par `s3_cle` (réconciliation) : une vérification est engagée dès que le
    /// statut a quitté `EN_ATTENTE` ou qu'une tentative existe (`verify-document` l.154-183).
    func testPreuveDEnregistrementEtVerificationEngagee() throws {
        let decode = { (json: String) in try JSONDecoder().decode(PreuveDocument.self, from: Data(json.utf8)) }
        let neuve = try decode(#"{"id":"d-1","s3_cle":"u/documents/DIPLOME/1-a.pdf","statut_verification":"EN_ATTENTE","verification_attempt_id":null}"#)
        XCTAssertFalse(neuve.verificationEngagee)
        XCTAssertEqual(neuve.issue, .enregistre(documentId: "d-1"))
        let tentee = try decode(#"{"id":"d-1","s3_cle":"k","statut_verification":"EN_ATTENTE","verification_attempt_id":"a-1"}"#)
        XCTAssertEqual(tentee.issue, .verificationDemandee(documentId: "d-1"))
        let revue = try decode(#"{"id":"d-1","s3_cle":"k","statut_verification":"REVUE_MANUELLE_REQUISE"}"#)
        XCTAssertTrue(revue.verificationEngagee)
        let nul = try decode(#"{"id":"d-1","s3_cle":"k","statut_verification":null}"#)
        XCTAssertFalse(nul.verificationEngagee, "statut nul : aucune preuve de vérification")
        XCTAssertEqual(PreuveDocument.selection, "id,s3_cle,statut_verification,verification_attempt_id")
    }
}
