import XCTest
@testable import JoleneCore

/// Lot 2, T8 — contrats d'échange des contrats (`Contrats/ContratModels.swift`) : projections explicites
/// (liste : `ListeContrats.tsx` l.69 ; détail : colonnes lues par `ContratMission.tsx`, sans images ni IP
/// de signature ; mission : l.220), décodage tolérant (`statut` NULLable, embed `missions` nul ou absent).
final class ContratModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testProjectionDeLaListeEstCelleDuWeb() {
        // ListeContrats.tsx l.69, sans espaces (paramètre PostgREST `select`).
        XCTAssertEqual(ContratResume.selection,
                       "id,mission_id,numero_contrat,type_contrat,statut,soignant_id,etablissement_id,signature_soignant,"
                       + "signature_etablissement,cree_le,missions(intitule,debut_le,fin_le)")
        XCTAssertFalse(ContratResume.selection.contains("*"))
    }

    func testProjectionDuDetailSansImageNiIPNiNavigateur() {
        XCTAssertFalse(ContratDetail.selection.contains("*"))
        for colonne in ["id", "mission_id", "soignant_id", "etablissement_id", "numero_contrat", "type_contrat", "statut",
                        "contenu_html", "hash_document", "storage_path", "contenu_html_rendu_le", "signature_soignant",
                        "signature_soignant_le", "signature_etablissement", "signature_etablissement_le", "cree_le"] {
            XCTAssertTrue(ContratDetail.colonnes.contains(colonne), colonne)
        }
        for interdite in ["signature_image_soignant", "signature_image_etablissement", "signature_ip_soignant",
                          "signature_ip_etablissement", "signature_navigateur_soignant", "signature_navigateur_etablissement"] {
            XCTAssertFalse(ContratDetail.colonnes.contains(interdite), "\(interdite) n'est jamais lue par l'app")
        }
        XCTAssertEqual(ContratDetail.selection, ContratDetail.colonnes.joined(separator: ","))
        XCTAssertEqual(MissionContrat.selection, "id,intitule,service,debut_le,fin_le,duree_heures,taux_horaire_base")
    }

    func testCarteDeListeAvecEmbedMissionEtStatutNul() throws {
        let cartes = try decode([ContratResume].self, """
        [{"id":"k-1","mission_id":"m-1","numero_contrat":"C-1","type_contrat":"CDD","statut":"EN_ATTENTE_SIGNATURES",
          "soignant_id":"u-1","etablissement_id":"e-1","signature_soignant":false,"signature_etablissement":true,
          "cree_le":"2026-11-01T10:00:00+00:00","missions":{"intitule":"Nuit","debut_le":"2026-11-03T19:00:00+00:00","fin_le":null}},
         {"id":"k-2","mission_id":"m-2","statut":null,"missions":null}]
        """)
        XCTAssertEqual(cartes.count, 2)
        XCTAssertEqual(cartes[0].numeroContrat, "C-1")
        XCTAssertEqual(cartes[0].signatureEtablissement, true)
        XCTAssertEqual(cartes[0].mission, MissionResumeContrat(intitule: "Nuit", debutLe: "2026-11-03T19:00:00+00:00", finLe: nil))
        // `statut` NULLable (`public.sql` l.68786) : même effet que le web (filtre « en attente », priorité nulle).
        XCTAssertEqual(cartes[1].statut, "")
        XCTAssertNil(cartes[1].mission)
    }

    func testDetailToleranteEtContexteNonDecodeDeLaLigne() throws {
        let detail = try decode(ContratDetail.self, """
        {"id":"k-1","mission_id":"m-1","soignant_id":"u-1","etablissement_id":"e-1","numero_contrat":"C-1",
         "type_contrat":"CDD","statut":null,"mode_signature":"JOLENE_OTP","contenu_html":"<p>x</p>",
         "hash_document":null,"storage_path":null,"contenu_html_rendu_le":null,"signature_soignant":null,
         "signature_soignant_le":null,"signature_etablissement":false,"signature_etablissement_le":null,
         "cree_le":"2026-11-01T10:00:00+00:00","est_compte_test":true}
        """)
        XCTAssertEqual(detail.statut, "")
        XCTAssertEqual(detail.numeroContrat, "C-1")
        XCTAssertEqual(detail.soignantId, "u-1")
        XCTAssertEqual(detail.modeSignature, "JOLENE_OTP")
        XCTAssertFalse(detail.estCompteTest, "relu dans `soignants`, jamais pris de la ligne du contrat")
        XCTAssertNil(detail.mission)
        XCTAssertNil(detail.etablissementNom)
    }

    func testMissionDuContratToleranteAuxNombres() throws {
        let mission = try decode(MissionContrat.self, """
        {"id":"m-1","intitule":"Nuit","service":null,"debut_le":"2026-11-03T19:00:00+00:00","fin_le":"2026-11-04T07:00:00+00:00",
         "duree_heures":12,"taux_horaire_base":"28.5"}
        """)
        XCTAssertEqual(mission.dureeHeures, 12)
        XCTAssertNil(mission.tauxHoraireBase, "valeur d'un autre type : nil, jamais un échec du document")
    }

    /// Textes opérationnels de T8 (`DECISIONS_LOT2.md`, « Textes opérationnels hors web (T8) ») gardés mot pour mot
    /// (revue fraîche de T8, mineur 4) ; le message du téléchargement vient désormais de `LibellesWeb` (web l.428).
    func testTextesOperationnelsDeT8InventoriesMotPourMot() {
        XCTAssertEqual(MessagesContrats.indisponible, "Les contrats ne peuvent pas être chargés. Réessayez.")
        XCTAssertEqual(FichierContratTemporaire.messageIndisponible, "Aucun contrat téléchargeable pour le moment.")
        XCTAssertEqual(FichierContratTemporaire.messageIndisponible, LibellesWeb.Contrat.aucunTelechargeable)
    }

    func testInitsDuLot2ConservesEtOriginalComplete() {
        // Inits posés par T1 (Lot2PortsTests) : toujours valides.
        let detail = ContratDetail(id: "k-1", missionId: "m-1", statut: "EN_ATTENTE_SIGNATURES")
        XCTAssertNil(detail.numeroContrat)
        XCTAssertFalse(detail.estCompteTest)
        let original = OriginalContrat(contratId: "k-1", html: "<p>Contrat</p>", empreinte: String(repeating: "a", count: 64))
        XCTAssertNil(original.numeroContrat)
        XCTAssertEqual(ContratResume(id: "k-1", missionId: "m-1", statut: "ANNULE").statut, "ANNULE")
    }
}
