import XCTest
@testable import JoleneCore

/// Contrats d'échange des ports du lot 2 (`Models/Lot2Results.swift`, blueprint §2.3-§2.4) : décodage en
/// liste blanche, projections imposées, issues. Ce fichier de test peut nommer les clés interdites pour
/// prouver qu'elles sont ignorées ; les sources Swift ne les nomment jamais (garde de T0).
final class Lot2ResultsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func cles<T: Encodable>(_ valeur: T) throws -> Set<String> {
        Set(try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valeur)) as? [String: Any]).keys)
    }

    // MARK: - Pointage

    func testReponseDuScanDecodeeSansLeCodeSuivant() throws {
        // `fn_scanner_code_pointage`, `public.sql` l.55871-55885 (correction 9, décision 8).
        let scan = try decode(ScanEnregistre.self, """
        {"nouveau_code":"482913","nouveau_hmac":"f00dbabe","type_scan_effectue":"OUVERTURE","prochain_type_scan":"FERMETURE",
         "creneau_effectif_id":"c-9","horodatage_effectif":"2026-11-02T00:07:12.5+00:00","horodatage_arrondi":"2026-11-02T00:00:00+00:00",
         "numero_scan":3,"validation_etab_requise":false}
        """)
        XCTAssertEqual(scan, ScanEnregistre(typeScanEffectue: .ouverture, prochainTypeScan: .fermeture, creneauEffectifId: "c-9",
                                            horodatageEffectif: "2026-11-02T00:07:12.5+00:00",
                                            horodatageArrondi: "2026-11-02T00:00:00+00:00", numeroScan: 3,
                                            validationEtabRequise: false))
        let labels = Mirror(reflecting: scan).children.compactMap(\.label).map { $0.lowercased() }
        XCTAssertFalse(labels.contains { $0.contains("nouveau") || $0.contains("hmac") }, "absent du modèle")
        XCTAssertFalse(String(describing: scan).contains("482913"), "jamais dans une description journalisable")
        XCTAssertEqual(try cles(scan), ["type_scan_effectue", "prochain_type_scan", "creneau_effectif_id", "horodatage_effectif",
                                        "horodatage_arrondi", "numero_scan", "validation_etab_requise"])
        XCTAssertThrowsError(try decode(ScanEnregistre.self, #"{"type_scan_effectue":"OUVERTURE"}"#),
                             "numero_scan conditionne la relecture : exigé")
    }

    func testEtatDuPointageEnListeBlanche() throws {
        // `fn_etat_pointage_mission` l.35180-35190 : `code_pointage_actif` jamais décodé ; `est_etab` vaut null
        // pour le soignant (consigne T3 de `DECISIONS_LOT2.md`) et n'est pas décodé non plus.
        let etat = try decode(EtatPointage.self, """
        {"statut":"EN_COURS","intitule":"Nuit","prochain_type_scan":"FERMETURE","nb_scans":1,"segment_ouvert":true,
         "segments":[{"id":"c-1","debut":"2026-11-01T22:00:00+00:00","fin":null}],"code_pointage_actif":"654321","est_etab":null}
        """)
        XCTAssertEqual(etat.statut, "EN_COURS")
        XCTAssertEqual(etat.prochainTypeScan, .fermeture)
        XCTAssertEqual(etat.nbScans, 1)
        XCTAssertEqual(etat.segmentOuvert, true)
        XCTAssertEqual(etat.segments, [SegmentPointage(id: "c-1", debut: "2026-11-01T22:00:00+00:00", fin: nil)])
        XCTAssertFalse(String(describing: etat).contains("654321"))
        XCTAssertEqual(try cles(etat), ["statut", "intitule", "prochain_type_scan", "nb_scans", "segment_ouvert", "segments"])
        let tolerant = try decode(EtatPointage.self, #"{"nb_scans":null,"prochain_type_scan":"PAUSE","segments":null}"#)
        XCTAssertNil(tolerant.prochainTypeScan, "valeur inconnue : nil, jamais une supposition")
        XCTAssertNil(tolerant.nbScans)
        XCTAssertEqual(tolerant.segments, [])
    }

    func testEtatDuPointageRefuseLaFormeErrorEtLesClesDiscriminantesManquantes() {
        // Revue fraîche de T1 : `{error}` HTTP 200 (`public.sql` l.35162, l.35169) ne devient jamais un état vide
        // plausible (segments [], tout à nil). Le succès porte toujours `nb_scans` et `prochain_type_scan`
        // (`jsonb_build_object` l.35180-35190, valeurs nulles comprises).
        for json in [#"{"error":"Accès interdit"}"#, #"{"error":"Mission introuvable"}"#, "{}", #"{"nb_scans":1}"#,
                     #"{"prochain_type_scan":"OUVERTURE"}"#, #"{"error":"Accès interdit","nb_scans":1,"prochain_type_scan":"OUVERTURE"}"#] {
            XCTAssertThrowsError(try decode(EtatPointage.self, json), json)
        }
    }

    func testUnSegmentMalFormeNeVidePasLesAutres() throws {
        let etat = try decode(EtatPointage.self, """
        {"nb_scans":3,"prochain_type_scan":"FERMETURE","segments":[{"id":"c-1","debut":"2026-11-01T22:00:00+00:00","fin":"2026-11-02T01:00:00+00:00"},
         {"id":5,"debut":"x"},{"debut":"2026-11-02T01:30:00+00:00"},{"id":"c-2","debut":"2026-11-02T01:30:00+00:00","fin":null}]}
        """)
        XCTAssertEqual(etat.segments, [SegmentPointage(id: "c-1", debut: "2026-11-01T22:00:00+00:00", fin: "2026-11-02T01:00:00+00:00"),
                                       SegmentPointage(id: "c-2", debut: "2026-11-02T01:30:00+00:00", fin: nil)],
                       "tolérance par segment : seuls les segments mal formés sont écartés")
    }

    func testProjectionDesPreuvesDeScan() throws {
        // T3 (corrigé v2) : jamais `code_saisi`, `ip_address`, `latitude`, `longitude` (lisibles via `sp_select` l.79931).
        // `mission_id` (revue fraîche de T1) : la réconciliation vérifie elle-même la mission du reçu.
        XCTAssertEqual(PreuveScan.colonnes, ["id", "mission_id", "numero_scan", "type_scan", "scanne_le", "id_terminal",
                                             "precision_gps_m"])
        XCTAssertEqual(PreuveScan.selection, "id,mission_id,numero_scan,type_scan,scanne_le,id_terminal,precision_gps_m")
        let preuve = try decode(PreuveScan.self, """
        {"id":"s-1","mission_id":"m-1","numero_scan":2,"type_scan":"FERMETURE","scanne_le":"2026-11-02T08:00:00+00:00",
         "id_terminal":"TERM_IOS_X","precision_gps_m":12.5,"code_saisi":"123456","latitude":48.8,"longitude":2.3}
        """)
        XCTAssertEqual(preuve.missionId, "m-1")
        XCTAssertEqual(preuve.numeroScan, 2)
        XCTAssertEqual(preuve.typeScan, .fermeture)
        XCTAssertEqual(preuve.precisionGpsM, 12.5)
        XCTAssertEqual(try cles(preuve), Set(PreuveScan.colonnes))
    }

    func testTypesDeScan() {
        XCTAssertEqual(TypeScan.allCases.map(\.rawValue), ["OUVERTURE", "FERMETURE"])
    }

    func testResumeServeurDuDetailSansHeuresReelles() throws {
        // `fn_presences_detail_mission` l.48938-48958 ; `heures_reelles` jamais affichée (web l.341-344).
        let resume = try decode(ResumePresencesServeur.self, """
        {"pointage_effectue":true,"heures_reelles":7.5,"duree_pause_min":30,"distance_m":42.5,"alerte_teleportation":false,
         "methode_arrivee":"QR","methode_depart":"CODE"}
        """)
        XCTAssertEqual(resume, ResumePresencesServeur(pointageEffectue: true, dureePauseMin: 30, distanceM: 42.5,
                                                      alerteTeleportation: false, methodeArrivee: "QR", methodeDepart: "CODE"))
        XCTAssertFalse(Mirror(reflecting: resume).children.contains { $0.label?.lowercased().contains("reelle") == true })
        XCTAssertEqual(DetailPresences(missionId: "m-1").resume, nil, "sans réponse : carte de synthèse masquée")
        let sansPresence = try decode(ResumePresencesServeur.self, #"{"pointage_effectue":false,"heures_planifiees":8}"#)
        XCTAssertEqual(sansPresence, ResumePresencesServeur(pointageEffectue: false), "l.48928 : aucune présence")
    }

    func testResumeServeurRefuseLaFormeErrorEtExigePointageEffectue() {
        // Revue fraîche de T1 : `{error:'Accès refusé' | 'Mission introuvable'}` HTTP 200 (l.48918, l.48922) ne donne
        // jamais un résumé non nil (carte affichée vide) : la carte est masquée (§2.4). `pointage_effectue` est
        // toujours un booléen dans les deux formes de succès (l.48928, l.48939).
        for json in [#"{"error":"Accès refusé"}"#, #"{"error":"Mission introuvable"}"#, "{}", #"{"pointage_effectue":null}"#,
                     #"{"pointage_effectue":"oui"}"#, #"{"distance_m":12}"#, #"{"error":"Accès refusé","pointage_effectue":true}"#] {
            XCTAssertThrowsError(try decode(ResumePresencesServeur.self, json), json)
        }
    }

    // MARK: - Notation

    func testNoteGlobaleRepliqueeSurLesQuatreCriteres() {
        // `NotationRapide.tsx` l.47 : `criteres ?? [note, note, note, note]`.
        XCTAssertEqual(CriteresNotation.repliques(note: 4), CriteresNotation(4, 4, 4, 4))
        XCTAssertEqual(CriteresNotation(5, 4, 3, 2).valeurs, [5, 4, 3, 2])
    }

    // MARK: - Documents

    func testVerdictsDeVerifyDocument() {
        XCTAssertEqual(VerdictDocument.allCases.map(\.rawValue), ["VERIFIE", "REJETE", "EN_ATTENTE", "REVUE_MANUELLE_REQUISE"])
    }

    func testCoherenceDocuments() throws {
        // `fn_verifier_coherence_documents` l.65853-65872 : `problemes` est un tableau de textes.
        let coherence = try decode(CoherenceDocuments.self, #"{"coherent":false,"problemes":["1 document(s) sans nom lisible"]}"#)
        XCTAssertEqual(coherence, CoherenceDocuments(coherent: false, problemes: ["1 document(s) sans nom lisible"], message: nil))
        let vide = try decode(CoherenceDocuments.self, #"{"coherent":true,"message":"Pas assez de documents vérifiés","documents":[]}"#)
        XCTAssertEqual(vide.problemes, [])
        XCTAssertEqual(vide.message, "Pas assez de documents vérifiés")
    }

    func testDocumentSoignantClesDuDump() throws {
        let document = try decode(DocumentSoignant.self, """
        {"id":"d-1","type_document":"DIPLOME","statut_verification":"REJETE","valide_jusqua":"2026-01-01","s3_cle":"u/documents/DIPLOME/1-a.pdf",
         "nom_fichier":"a.pdf","type_mime":"application/pdf","taille_octets":12,"motif_rejet":"Illisible","televerse_le":"2026-10-01T00:00:00Z",
         "verification_attempt_id":null}
        """)
        XCTAssertEqual(document.statutVerification, "REJETE")
        XCTAssertEqual(document.valideJusqua, "2026-01-01")
        XCTAssertEqual(document.s3Cle, "u/documents/DIPLOME/1-a.pdf")
    }

    // MARK: - Contrats

    func testProjectionImposeeDuCertificat() throws {
        // Correction 22 : GRANT colonne par colonne (l.86518-86570) ; `select=*` lèverait 42501.
        XCTAssertEqual(SignatureCertificat.colonnes, ["id", "contrat_id", "signataire_user_id", "signataire_role", "signe_a",
                                                      "ip_signature", "user_agent", "hash_document", "otp_valide_a",
                                                      "psc_session_active", "rpps_verifie", "traits_identite_verifies",
                                                      "statut_signature", "cree_le"])
        XCTAssertFalse(SignatureCertificat.selection.contains("*"))
        let ligne = try decode(SignatureCertificat.self, #"{"id":"s-1","contrat_id":"k-1","statut_signature":"signe","signataire_role":"SOIGNANT"}"#)
        XCTAssertEqual(ligne.statutSignature, "signe")
        XCTAssertEqual(try cles(ligne), ["id", "contrat_id", "signataire_role", "statut_signature"])
    }

    func testDetailDuContratEtPreuveDeSignature() throws {
        let contrat = try decode(ContratDetail.self, """
        {"id":"k-1","mission_id":"m-1","statut":"SIGNE_SOIGNANT","type_contrat":"CDD","signature_soignant":true,
         "signature_etablissement":false,"signature_soignant_le":"2026-11-01T10:00:00Z","hash_document":"ab","storage_path":"k-1.html",
         "contenu_html_rendu_le":"2026-11-01T09:00:00Z","cree_le":"2026-11-01T08:00:00Z"}
        """)
        XCTAssertEqual(contrat.preuve, PreuveSignatureContrat(statut: "SIGNE_SOIGNANT", signatureSoignant: true,
                                                              signatureEtablissement: false,
                                                              signatureSoignantLe: "2026-11-01T10:00:00Z"))
        XCTAssertEqual(contrat.typeContrat, "CDD")
        XCTAssertNil(contrat.contenuHtml)
    }
}
