import XCTest
@testable import JoleneCore

/// Décodage tolérant du corps de `fn_dashboard_soignant_complet` (lot 1, T3 ; blueprint §2.4,
/// §2.6) : fixture démo, valeurs NULL ou absentes, lignes illisibles écartées une à une,
/// `{error}` jamais pris pour un succès, aucune donnée sensible ni `gains_mois.net_total` décodés.
final class DashboardDecodingTests: XCTestCase {
    private func corps(_ json: String) throws -> DashboardCorps {
        try DashboardCorps.decoder(Data(json.utf8))
    }

    private let contexte = MissionReadContext(userId: "u-1", email: "u-1@example.invalid",
                                              profile: SoignantProfile(id: "u-1", profession: "IDE"))

    private func assembler(_ corps: DashboardCorps) throws -> DashboardSnapshot {
        try AccueilAssemblage.snapshot(corps: corps, context: contexte, maintenant: DemoWorld.fixedNow,
                                       lecture: LectureMissionsAccueil(records: [], creneaux: []), etablissements: [:], gains: [])
    }

    func testFixtureDemoDecodeToutesLesSections() throws {
        let fichier = try DemoFixtures.loadDashboard()
        XCTAssertEqual(fichier.fixedNow, "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(PlanningHorlogeParis.instant(fichier.fixedNow), DemoWorld.fixedNow)
        let corps = fichier.dashboard
        XCTAssertNil(corps.erreur)
        XCTAssertEqual(corps.profil?.prenom, "Camille")
        XCTAssertEqual(corps.profil?.tousDocumentsValides, false)
        // `mes_missions` : ORDER BY debut_le LIMIT 3 (public.sql, `fn_dashboard_soignant_complet`).
        XCTAssertEqual(corps.mesMissions.map(\.id), ["demo-assignee-001", "demo-assignee-002", "demo-assignee-003"])
        XCTAssertEqual(corps.mesMissions.map(\.statut), ["ASSIGNEE", "ASSIGNEE", "ASSIGNEE"])
        XCTAssertEqual(corps.missionsOuvertes.map(\.id), ["demo-mission-001", "demo-mission-002", "demo-mission-003"])
        XCTAssertEqual(corps.propositions.map(\.id), ["demo-proposition-001"])
        XCTAssertEqual(corps.propositions.first?.mission.id, "demo-mission-011")
        XCTAssertEqual(corps.propositions.first?.creeLe, "2026-11-01T23:30:00.000Z", "proposée 30 min avant l'horloge démo")
        XCTAssertEqual(corps.documents.map(\.typeDocument), ["CARTE_IDENTITE"])
        XCTAssertEqual(corps.heuresSemaine, 8)
        XCTAssertEqual(corps.gainsMoisNbMissions, 1)
        XCTAssertEqual(corps.missionsOublieesCount, 0)
        XCTAssertEqual(corps.notifsNonLues, 2)
        // Dix missions ASSIGNEE (revue B8 de T5, 2e passe : la liste « À venir » de Mes missions dépasse
        // la hauteur de l'écran) ; le tableau de bord en garde les trois premières, comme le serveur.
        XCTAssertEqual(fichier.missionsAssignees.map(\.record.id), (1...10).map { String(format: "demo-assignee-%03d", $0) })
        XCTAssertEqual(Array(fichier.missionsAssignees.prefix(3)).map(\.record.id), corps.mesMissions.map(\.id))
        XCTAssertTrue(fichier.missionsAssignees.allSatisfy { $0.record.statut == "ASSIGNEE" })
        let debuts = fichier.missionsAssignees.compactMap { PlanningHorlogeParis.instant($0.record.debutLe) }
        XCTAssertEqual(debuts, debuts.sorted(), "ordre `debut_le` croissant : les trois premières sont les prochaines")
        XCTAssertEqual(debuts.count, 10)
        XCTAssertEqual(fichier.gainsMissions.map(\.id), ["demo-terminee-001"])

        // Les missions ouvertes du tableau de bord sont les trois premières missions démo (ORDER BY
        // debut_le LIMIT 3) : mêmes intitulés, mêmes horaires, même établissement.
        let demo = try DemoFixtures.loadMissions().missions
        for ligne in corps.missionsOuvertes {
            let source = try XCTUnwrap(demo.first { $0.record.id == ligne.id })
            XCTAssertEqual(ligne.intitule, source.record.intitule)
            XCTAssertEqual(ligne.debutLe, source.record.debutLe)
            XCTAssertEqual(ligne.finLe, source.record.finLe)
            XCTAssertEqual(ligne.etablissementId, source.record.etablissementId)
            XCTAssertEqual(ligne.tauxHoraireBase, source.record.tauxHoraireBase)
        }
    }

    func testNullEtClesAbsentesNeFontPasEchouerLeDecodage() throws {
        let nuls = try corps("""
        {"profil":null,"missions_ouvertes":null,"mes_missions":null,"propositions":null,"documents":null,
         "heures_semaine":null,"gains_mois":null,"missions_oubliees_count":null,"notifs_non_lues":null}
        """)
        XCTAssertNil(nuls.profil)
        XCTAssertEqual(nuls.mesMissions, [])
        XCTAssertEqual(nuls.missionsOuvertes, [])
        XCTAssertEqual(nuls.propositions, [])
        XCTAssertEqual(nuls.documents, [])
        XCTAssertEqual(nuls.heuresSemaine, 0)
        XCTAssertEqual(nuls.gainsMoisNbMissions, 0)
        XCTAssertEqual(nuls.missionsOublieesCount, 0)
        XCTAssertEqual(nuls.notifsNonLues, 0)
        XCTAssertEqual(try corps("{}"), nuls, "clé absente et NULL donnent le même corps")
        let snapshot = try assembler(nuls)
        XCTAssertEqual(snapshot.prochaines, [])
        XCTAssertEqual(snapshot.pourToi, [])
        XCTAssertNil(snapshot.profil)
    }

    func testLignesIllisiblesEcarteesUneAUne() throws {
        let decode = try corps("""
        {"mes_missions":[{"intitule":"Sans identifiant"},{"id":"","intitule":"Identifiant vide"},42,
                         {"id":"m-1","intitule":"Mission lisible","debut_le":"2026-11-05T07:00:00+00:00",
                          "fin_le":"2026-11-05T15:00:00+00:00","duree_heures":8,"statut":"ASSIGNEE",
                          "etablissement_id":"e-1","etab_nom":"Clinique","est_urgente":null}],
         "missions_ouvertes":{"id":"pas-un-tableau"},
         "propositions":[{"id":"p-1","mission_id":"m-2","cree_le":"2026-11-01T23:30:00+00:00","missions":null},
                         {"id":"p-2","mission_id":"m-3","cree_le":"2026-11-01T23:30:00+00:00",
                          "missions":{"intitule":"Proposée","debut_le":"2026-11-13T07:00:00+00:00","fin_le":"2026-11-13T15:00:00+00:00"}}],
         "heures_semaine":7.5,"notifs_non_lues":3.0,"missions_oubliees_count":"2","gains_mois":{"nb_missions":4}}
        """)
        XCTAssertEqual(decode.mesMissions.map(\.id), ["m-1"])
        XCTAssertEqual(decode.mesMissions.first?.estUrgente, false, "est_urgente NULL vaut false")
        XCTAssertEqual(decode.mesMissions.first?.etabNom, "Clinique")
        XCTAssertEqual(decode.missionsOuvertes, [], "une section qui n'est pas un tableau est vide, jamais une erreur d'écran")
        XCTAssertEqual(decode.propositions.map(\.id), ["p-2"], "une proposition sans mission jointe n'est jamais affichée")
        XCTAssertEqual(decode.propositions.first?.mission.id, "m-3", "mission jointe sans id : celui de la candidature")
        XCTAssertEqual(decode.heuresSemaine, 7.5)
        XCTAssertEqual(decode.notifsNonLues, 3)
        XCTAssertEqual(decode.missionsOublieesCount, 2)
        XCTAssertEqual(decode.gainsMoisNbMissions, 4)
    }

    func testErreurServeurJamaisPriseePourUnSucces() throws {
        let nonAuthentifie = try corps(#"{"error":"Non authentifié"}"#)
        XCTAssertEqual(nonAuthentifie.erreur, "Non authentifié")
        XCTAssertThrowsError(try assembler(nonAuthentifie)) { error in
            XCTAssertEqual((error as? JoleneError)?.kind, .unauthorized)
            XCTAssertEqual((error as? JoleneError)?.message, SessionController.sessionExpiredMessage)
        }
        let autre = try corps(#"{"error":"Profil soignant introuvable"}"#)
        XCTAssertThrowsError(try assembler(autre)) { error in
            XCTAssertEqual(error as? JoleneError, JoleneError(.unknown, "Profil soignant introuvable"), "message serveur verbatim")
        }
    }

    func testCorpsQuiNestPasUnObjetEstUnRefusDeContrat() {
        for brut in ["[]", "null", "\"texte\"", "{"] {
            XCTAssertThrowsError(try corps(brut), brut) { error in
                XCTAssertEqual((error as? JoleneError)?.kind, .contract, brut)
            }
        }
    }

    func testAucuneDonneeSensibleNiNetTotalDecodes() throws {
        let decode = try corps("""
        {"profil":{"prenom":"Alex","nom":"Martin","telephone":"06 00 00 00 00","date_naissance":"1990-01-01",
                   "numero_rpps":"00000000000","numero_adeli":null,"profession":"IDE","tous_documents_valides":true,
                   "type_exercice":"SALARIE","score_fiabilite":4.5},
         "gains_mois":{"net_total":224.6,"brut_total":208,"nb_missions":1}}
        """)
        let profil = try XCTUnwrap(decode.profil)
        XCTAssertEqual(profil, DashboardProfil(prenom: "Alex", profession: "IDE", tousDocumentsValides: true, typeExercice: "SALARIE"))
        XCTAssertEqual(Mirror(reflecting: profil).children.compactMap(\.label).sorted(),
                       ["prenom", "profession", "tousDocumentsValides", "typeExercice"],
                       "le profil du tableau de bord ne sert qu'à la salutation et à l'accroche (blueprint §2.6)")
        let champs = Mirror(reflecting: decode).children.compactMap(\.label)
        XCTAssertFalse(champs.contains { $0.lowercased().contains("total") }, "gains_mois.net_total n'est jamais décodé (décision 10)")
        XCTAssertEqual(decode.gainsMoisNbMissions, 1)
    }
}
