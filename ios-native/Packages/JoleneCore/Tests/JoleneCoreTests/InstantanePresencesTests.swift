import XCTest
@testable import JoleneCore

/// Instantané de la page Présences (lot 2, T3) : décodage tolérant des lignes PostgREST de `PresencesSoignant.tsx`,
/// colonnes imposées, contrat à statut nul (consigne T3), listes par `ListesPresences` et historique trié comme le web.
final class InstantanePresencesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private let maintenant = Date(timeIntervalSince1970: 1_793_577_600) // 2026-11-02T00:00:00Z

    // MARK: - Colonnes

    func testColonnesSansMontantNiCodeNiEmbedEtablissements() {
        XCTAssertEqual(MissionPresenceLue.selection, "id,intitule,service,debut_le,fin_le,duree_heures,statut,etablissement_id")
        XCTAssertEqual(PresenceLue.colonnes, ["id", "mission_id", "soignant_id", "pointage_arrivee_le", "pointage_depart_le",
                                              "valide_par_etablissement", "valide_le", "methode_pointage_arrivee",
                                              "methode_pointage_depart"])
        XCTAssertEqual(MissionDePresence.colonnes, ["id", "intitule", "etablissement_id", "debut_le", "fin_le", "statut"])
        for colonne in MissionPresenceLue.colonnes + PresenceLue.colonnes + MissionDePresence.colonnes {
            XCTAssertFalse(colonne.hasPrefix("code_pointage"), "gap B1-ter : le code rotatif n'est jamais demandé")
            XCTAssertFalse(colonne.contains("etablissements"), "noms par fn_etablissements_safe seulement")
            XCTAssertFalse(["total_brut", "net_a_payer", "net_estime", "latitude", "longitude"].contains(colonne))
        }
    }

    // MARK: - Décodage tolérant

    func testMissionAStatutNulEtSansProfessionRequise() throws {
        // La projection du web ne lit pas `profession_requise` (consigne T3) ; `statut` est NULLable.
        let mission = try decode(MissionPresenceLue.self, """
        {"id":"m-1","intitule":"Nuit","service":null,"debut_le":"2026-11-02T00:05:00Z","fin_le":"2026-11-02T08:05:00Z",
         "duree_heures":"huit","statut":null,"etablissement_id":"etab-1"}
        """)
        XCTAssertEqual(mission, MissionPresenceLue(id: "m-1", intitule: "Nuit", debutLe: "2026-11-02T00:05:00Z",
                                                   finLe: "2026-11-02T08:05:00Z", statut: "", etablissementId: "etab-1"))
        XCTAssertFalse(PointageRules.pointageDisponible(statut: mission.statut), "statut nul : jamais pointable")
        XCTAssertThrowsError(try decode(MissionPresenceLue.self, #"{"id":"m-2","fin_le":"2026-11-02T08:05:00Z"}"#),
                             "debut_le NOT NULL : exigé")
    }

    func testLigneMalFormeeEcarteeSansViderLaListe() throws {
        let lignes = try decode([LigneTolerante<PresenceLue>].self, """
        [{"id":"p-1","mission_id":"m-1","valide_par_etablissement":true,"missions":{"id":"m-1","intitule":"A","etablissement_id":"etab-1"}},
         {"mission_id":"sans-id"},
         {"id":"p-2","valide_par_etablissement":"oui","missions":"illisible","arrivee_lat":48.8}]
        """)
        let presences = LigneTolerante.valeurs(lignes)
        XCTAssertEqual(presences.map(\.id), ["p-1", "p-2"])
        XCTAssertEqual(presences[0].mission, MissionDePresence(id: "m-1", intitule: "A", etablissementId: "etab-1"))
        XCTAssertNil(presences[1].valideParEtablissement, "valeur d'un autre type : nil, jamais une supposition")
        XCTAssertNil(presences[1].mission)
    }

    func testContratAStatutNulLuCommeLeWeb() throws {
        // `contrats_mission.statut` NULLable (`public.sql` l.68786) : nul → "", non terminal, priorité 0 (consigne T3).
        let contrats = try decode([ContratPointage].self, """
        [{"id":"nul","mission_id":"m-1","statut":null,"cree_le":"2026-10-02T00:00:00Z"},
         {"id":"envoye","mission_id":"m-1","statut":"ENVOYE","cree_le":"2026-10-01T00:00:00Z"},
         {"id":"absent","mission_id":"m-2"}]
        """)
        XCTAssertEqual(contrats.map(\.statut), ["", "ENVOYE", ""])
        XCTAssertEqual(DisponibilitePointage.choisirContratPointage(Array(contrats.prefix(2)))?.id, "nul", "plus récent, non terminal")
        let etat = DisponibilitePointage.evaluerDisponibilitePointage(
            creneaux: [MissionSlot(debut: "2026-11-02T00:05:00Z", fin: "2026-11-02T08:05:00Z", estPause: false, typeCreneau: "PREVISIONNEL")],
            contratStatut: contrats[0].statut, maintenant: maintenant)
        XCTAssertEqual(etat.motif, .contrat, "un statut nul bloque le pointage, comme le web")
    }

    // MARK: - Assemblage

    private func instantane() -> InstantanePresences {
        let actives = [
            MissionPresenceLue(id: "a", intitule: "A", debutLe: "2026-11-02T00:05:00Z", finLe: "2026-11-02T08:05:00Z",
                               dureeHeures: 8, statut: "ASSIGNEE", etablissementId: "etab-1"),
            MissionPresenceLue(id: "b", intitule: "B", debutLe: "2026-11-01T22:00:00Z", finLe: "2026-11-02T06:00:00Z",
                               dureeHeures: 8, statut: "EN_COURS", etablissementId: "etab-2"),
        ]
        let terminees = [
            MissionPresenceLue(id: "h1", debutLe: "2026-10-31T07:00:00Z", finLe: "2026-10-31T15:00:00Z", statut: "TERMINEE",
                               etablissementId: "etab-1"),
            MissionPresenceLue(id: "h3", debutLe: "2026-10-28T07:00:00Z", finLe: "2026-10-28T15:00:00Z", statut: "TERMINEE",
                               etablissementId: "etab-3"),
        ]
        let validee = PresenceLue(id: "p-h1", missionId: "h1", pointageArriveeLe: "2026-10-31T07:00:00Z",
                                  pointageDepartLe: "2026-10-31T15:00:00Z", valideParEtablissement: true,
                                  valideLe: "2026-11-01T14:00:00Z", mission: MissionDePresence(id: "h1", etablissementId: "etab-1"))
        let aValider = PresenceLue(id: "p-h2", missionId: "h2", pointageArriveeLe: "2026-10-30T07:00:00Z",
                                   pointageDepartLe: "2026-10-30T15:00:00Z", valideParEtablissement: false,
                                   mission: MissionDePresence(id: "h2", etablissementId: "etab-9", finLe: "2026-10-30T15:00:00Z"))
        let creneaux = [
            MissionSlot(id: "b-eff", missionId: "b", debut: "2026-11-01T22:00:00Z", fin: nil, estPause: false, typeCreneau: "EFFECTIF"),
            MissionSlot(id: "a-prev", missionId: "a", debut: "2026-11-02T00:05:00Z", fin: "2026-11-02T08:05:00Z", estPause: false,
                        typeCreneau: "PREVISIONNEL"),
            MissionSlot(id: "h3-eff", missionId: "h3", debut: "2026-10-28T07:00:00Z", fin: "2026-10-28T15:00:00Z", estPause: false,
                        typeCreneau: "EFFECTIF"),
        ]
        return InstantanePresences(
            missions: actives, presencesValidees: [validee], historique: [aValider, validee], missionsHistorique: terminees,
            creneaux: creneaux,
            contrats: [ContratPointage(id: "c-a", statut: "SIGNE_COMPLET", missionId: "a"),
                       ContratPointage(id: "c-b", statut: "SIGNE_COMPLET", missionId: "b"),
                       ContratPointage(id: "c-x", statut: "SIGNE_COMPLET", missionId: nil)],
            etablissements: ["etab-1": EtablissementSummary(id: "etab-1", nom: "Établissement fictif République")],
            chargeLe: maintenant)
    }

    func testIdentifiantsDansLOrdreDuWebDedoublonnes() {
        let i = instantane()
        XCTAssertEqual(i.identifiantsMissions, ["a", "b", "h1", "h2", "h3"])
        XCTAssertEqual(InstantanePresences.identifiantsEtablissements(missions: i.missions, presencesValidees: i.presencesValidees,
                                                                      historique: i.historique, missionsHistorique: i.missionsHistorique),
                       ["etab-1", "etab-2", "etab-9", "etab-3"])
    }

    func testListesEtContratsParListesPresences() {
        let listes = instantane().listes(maintenant: maintenant)
        XCTAssertEqual(listes.missionsAujourdhui.map(\.mission.id), ["a", "b"], "créneau du jour, segment ouvert")
        XCTAssertEqual(listes.missionsEnCours.map(\.mission.id), ["b"])
        XCTAssertEqual(listes.missionsAujourdhui.first?.etablissement?.nom, "Établissement fictif République")
        XCTAssertEqual(listes.contrats.mapValues(\.id), ["a": "c-a", "b": "c-b"], "contrat sans mission_id : jamais retenu")
    }

    func testHistoriqueTrieParDateDecroissanteAvecLigneReconstruite() {
        let lignes = instantane().lignesHistorique(soignantId: "s-1")
        XCTAssertEqual(lignes.map(\.id), ["p-h1", "p-h2", "effectifs-mission-h3"])
        XCTAssertEqual(lignes.map(\.missionId), ["h1", "h2", "h3"])
        guard case let .presence(presence, creneaux, etablissement) = lignes[0] else { return XCTFail("présence attendue") }
        XCTAssertEqual(presence.id, "p-h1")
        XCTAssertEqual(creneaux, [])
        XCTAssertEqual(etablissement?.id, "etab-1")
        XCTAssertEqual(PointageRules.historiqueAffiche(lignes, aValider: true).map(\.id), ["p-h2", "effectifs-mission-h3"],
                       "à valider : départ pointé, non validée (l.284-288)")
        XCTAssertEqual(PointageRules.historiqueAffiche(lignes, aValider: false).count, 3)
    }

    func testCleDeTriDuWeb() {
        let vide = LigneHistoriquePresence.presence(PresenceLue(id: "v"), creneaux: [], etablissement: nil)
        XCTAssertEqual(vide.cleTri, 0, "|| 0 du web")
        let parFin = LigneHistoriquePresence.presence(PresenceLue(id: "f", pointageDepartLe: "",
                                                                  mission: MissionDePresence(finLe: "1970-01-01T00:00:01Z")),
                                                      creneaux: [], etablissement: nil)
        XCTAssertEqual(parFin.cleTri, 1_000, "chaîne vide ignorée, puis fin de mission")
        let illisible = LigneHistoriquePresence.presence(PresenceLue(id: "i", pointageDepartLe: "pas une date"), creneaux: [],
                                                         etablissement: nil)
        XCTAssertTrue(illisible.cleTri.isNaN)
    }
}
