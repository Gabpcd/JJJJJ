import XCTest
@testable import JoleneCore

/// Règles et présentation des favoris (lot 1, T4b), port de `MesFavorisSoignant.tsx` : filtre des
/// missions affichées (l.46-49), libellés d'un établissement suivi (l.143-160), décodage tolérant de la
/// jointure `missions(...)` et des éléments de `fn_mes_favoris_etablissements`, filtre établissement
/// d'Explorer (« Voir missions ouvertes », l.164).
final class FavorisReglesTests: XCTestCase {
    private let maintenant = DemoWorld.fixedNow // 2026-11-02T00:00:00Z

    private func apercu(_ id: String, statut: String? = "OUVERTE", debut: String? = "2026-11-10T07:00:00.000Z",
                        fin: String? = "2026-11-10T15:00:00.000Z") -> MissionSauvegardee.Apercu {
        MissionSauvegardee.Apercu(id: id, intitule: "Mission \(id)", debutLe: debut, finLe: fin, dureeHeures: 8,
                                  nbCreneaux: 1, statut: statut)
    }

    private func ligne(_ missionId: String, _ apercu: MissionSauvegardee.Apercu?) -> MissionSauvegardee {
        MissionSauvegardee(id: "s-\(missionId)", missionId: missionId, creeLe: "2026-11-01T10:00:00+00:00", mission: apercu)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Missions affichées

    func testSeulesLesMissionsOuvertesAVenirSontAffichees() {
        let lignes = [
            ligne("m-ouverte", apercu("m-ouverte")),
            ligne("m-passee", apercu("m-passee", debut: "2026-11-01T07:00:00.000Z")),
            ligne("m-maintenant", apercu("m-maintenant", debut: "2026-11-02T00:00:00.000Z")),
            ligne("m-assignee", apercu("m-assignee", statut: "ASSIGNEE")),
            ligne("m-sans-statut", apercu("m-sans-statut", statut: nil)),
            ligne("m-masquee", nil),
            ligne("m-date-illisible", apercu("m-date-illisible", debut: "demain")),
            ligne("m-sans-date", apercu("m-sans-date", debut: nil)),
            ligne("m-ouverte-2", apercu("m-ouverte-2", debut: "2026-12-01T07:00:00+01:00")),
        ]
        let affichees = FavorisRegles.missionsAffichees(lignes, maintenant: maintenant)
        // Web : `m && m.statut === 'OUVERTE' && new Date(m.debut_le) > new Date()`, ordre serveur conservé.
        XCTAssertEqual(affichees.map(\.missionId), ["m-ouverte", "m-ouverte-2"])
    }

    func testUneMissionParIdentifiantEnGardantLaPremiere() {
        let lignes = [ligne("m-1", apercu("m-1")), ligne("m-2", apercu("m-2")),
                      MissionSauvegardee(id: "s-bis", missionId: "m-1", creeLe: nil, mission: apercu("m-1"))]
        XCTAssertEqual(FavorisRegles.missionsAffichees(lignes, maintenant: maintenant).map(\.id), ["s-m-1", "s-m-2"])
    }

    func testEtoileAllumeeSurToutesLesLignesMemeNonAffichees() {
        // L'étoile reflète l'existence de la ligne `missions_sauvegardees` (web : `.maybeSingle()` sur la
        // ligne), pas son affichage dans « Mes favoris » : une mission masquée ou passée reste sauvegardée.
        let lignes = [ligne("m-masquee", nil), ligne("m-passee", apercu("m-passee", debut: "2026-10-01T07:00:00.000Z"))]
        XCTAssertTrue(FavorisRegles.estSauvegardee("m-masquee", dans: lignes))
        XCTAssertTrue(FavorisRegles.estSauvegardee("m-passee", dans: lignes))
        XCTAssertFalse(FavorisRegles.estSauvegardee("m-autre", dans: lignes))
        XCTAssertFalse(FavorisRegles.estSauvegardee("", dans: lignes))
    }

    func testVerrouDecision8() {
        XCTAssertTrue(FavorisRegles.ajoutEtablissementNonPropose.contains("décision 8"))
        XCTAssertTrue(FavorisRegles.ajoutEtablissementNonPropose.contains("LOT1_PLAN.md"))
    }

    // MARK: - Présentation

    func testDetailDUneMissionSauvegardee() {
        // Web : `formatDateMission(m) · formatDureeCompacte(m)` (l.71).
        let unJour = MissionSauvegardee.Apercu(id: "m", intitule: "M", debutLe: "2026-11-03T07:00:00.000Z",
                                               finLe: "2026-11-03T15:00:00.000Z", dureeHeures: 8, nbCreneaux: 1, statut: "OUVERTE")
        XCTAssertEqual(FavorisPresentation.detailMission(unJour), "mardi 3 novembre 2026 · 8h")
        let multi = MissionSauvegardee.Apercu(id: "m", intitule: "M", debutLe: "2026-11-08T07:00:00.000Z",
                                              finLe: "2026-11-10T15:00:00.000Z", dureeHeures: 16, nbCreneaux: 2, statut: "OUVERTE")
        XCTAssertEqual(FavorisPresentation.detailMission(multi), "8 → 10 novembre 2026 · 2 créneaux · 16 h au total")
        XCTAssertEqual(FavorisPresentation.titreMission(unJour), "M")
        var sansTitre = unJour
        sansTitre.intitule = "  "
        XCTAssertEqual(FavorisPresentation.titreMission(sansTitre), "Mission")
    }

    func testLibellesDUnEtablissementSuivi() {
        let lilas = EtablissementFavori(id: "e-1", nom: "Établissement fictif des Lilas", ville: "Les Lilas", logoUrl: nil,
                                        typeEtablissement: "CENTRE_HOSPITALIER", nbMissionsOuvertes: 10,
                                        creeLe: "2026-10-15T09:00:00.000Z")
        // Web l.149-150 : `{e.ville ?? '—'}{e.type_etablissement && ` · ${type.replace(/_/g, ' ').toLowerCase()}`}`.
        XCTAssertEqual(FavorisPresentation.lieu(lilas), "Les Lilas · centre hospitalier")
        var sansVille = lilas
        sansVille.ville = nil
        sansVille.typeEtablissement = nil
        XCTAssertEqual(FavorisPresentation.lieu(sansVille), "—")
        XCTAssertEqual(FavorisPresentation.nom(lilas), "Établissement fictif des Lilas")
        var sansNom = lilas
        sansNom.nom = nil
        XCTAssertEqual(FavorisPresentation.nom(sansNom), "Établissement")

        // Web l.153-157 : badge seulement au-delà de 0, pluriel au-delà de 1.
        XCTAssertNil(FavorisPresentation.badgeMissions(nil))
        XCTAssertNil(FavorisPresentation.badgeMissions(0))
        XCTAssertEqual(FavorisPresentation.badgeMissions(1), "1 mission")
        XCTAssertEqual(FavorisPresentation.badgeMissions(10), "10 missions")
        XCTAssertFalse(FavorisPresentation.afficheVoirMissions(nil))
        XCTAssertFalse(FavorisPresentation.afficheVoirMissions(0))
        XCTAssertTrue(FavorisPresentation.afficheVoirMissions(10))

        // Web l.160 : `format(new Date(e.cree_le), 'd MMM yyyy', { locale: fr })`, heure de Paris.
        XCTAssertEqual(FavorisPresentation.favoriDepuis("2026-10-15T09:00:00.000Z"), "Favori depuis le 15 oct. 2026")
        XCTAssertEqual(FavorisPresentation.favoriDepuis("2026-10-31T23:30:00+00:00"), "Favori depuis le 1 nov. 2026")
        XCTAssertNil(FavorisPresentation.favoriDepuis(nil))
        XCTAssertNil(FavorisPresentation.favoriDepuis("hier"))
    }

    func testTitresEtEtoile() {
        XCTAssertEqual(FavorisPresentation.titreMissions(0), "Missions sauvegardées")
        XCTAssertEqual(FavorisPresentation.titreMissions(2), "Missions sauvegardées (2)")
        XCTAssertEqual(FavorisPresentation.libelleEtoile(sauvegardee: false), "Sauvegarder cette mission")
        XCTAssertEqual(FavorisPresentation.libelleEtoile(sauvegardee: true), "Retirer de mes missions sauvegardées")
        XCTAssertEqual(FavorisPresentation.valeurEtoile(sauvegardee: true), "Sauvegardée")
        XCTAssertEqual(FavorisPresentation.valeurEtoile(sauvegardee: false), "Non sauvegardée")
        XCTAssertEqual(FavorisPresentation.libelleFiltreEtablissement(nom: "Clinique des Tests"), "Missions de « Clinique des Tests »")
        XCTAssertEqual(FavorisPresentation.libelleFiltreEtablissement(nom: nil), "Missions d'un établissement sélectionné")
        XCTAssertEqual(FavorisPresentation.libelleFiltreEtablissement(nom: " "), "Missions d'un établissement sélectionné")
    }

    // MARK: - Filtre établissement d'Explorer

    func testVoirMissionsOuvertesFiltreSurLEtablissementSansToucherLesAutresCriteres() {
        var filtres = ExplorerFiltres.initiaux(profile: DemoWorld.context.profile)
        filtres.urgentesOnly = true
        filtres.rayonKm = 20
        let filtre = filtres.filtrantEtablissement("demo-etab-2")
        XCTAssertEqual(filtre.etablissementId, "demo-etab-2")
        XCTAssertTrue(filtre.urgentesOnly)
        XCTAssertEqual(filtre.rayonKm, 20)
        XCTAssertEqual(filtre.missionFilters.etablissementId, "demo-etab-2")
        let retire = filtre.filtrantEtablissement(nil)
        XCTAssertNil(retire.etablissementId)
        XCTAssertEqual(retire, filtres, "retirer le filtre rend les critères précédents")
        XCTAssertNil(filtres.filtrantEtablissement("  ").etablissementId, "identifiant vide : aucun filtre")
    }

    // MARK: - Décodage

    func testJointureMissionDecodeeEtTolerante() throws {
        let complete = try decode(MissionSauvegardee.self, """
        {"id":"s-1","mission_id":"m-1","cree_le":"2026-11-01T10:00:00+00:00",
         "missions":{"id":"m-1","intitule":"Remplacement IDE","debut_le":"2026-11-10T07:00:00+00:00",
                     "fin_le":"2026-11-10T15:00:00+00:00","duree_heures":8,"nb_creneaux":1,"statut":"OUVERTE"}}
        """)
        XCTAssertEqual(complete.mission, MissionSauvegardee.Apercu(id: "m-1", intitule: "Remplacement IDE",
                                                                   debutLe: "2026-11-10T07:00:00+00:00",
                                                                   finLe: "2026-11-10T15:00:00+00:00", dureeHeures: 8,
                                                                   nbCreneaux: 1, statut: "OUVERTE"))
        // Jointure masquée par la RLS des missions : la ligne reste (étoile), la mission n'est pas affichée.
        let masquee = try decode(MissionSauvegardee.self, #"{"id":"s-2","mission_id":"m-2","cree_le":null,"missions":null}"#)
        XCTAssertEqual(masquee, MissionSauvegardee(id: "s-2", missionId: "m-2", creeLe: nil))
        let illisible = try decode(MissionSauvegardee.self, #"{"id":"s-3","mission_id":"m-3","missions":{"intitule":"sans id"}}"#)
        XCTAssertNil(illisible.mission, "jointure sans id : écartée seule, la ligne reste")
        let numerique = try decode(MissionSauvegardee.self, """
        {"id":"s-4","mission_id":"m-4","missions":{"id":"m-4","intitule":null,"duree_heures":"8","nb_creneaux":2.0,"statut":"OUVERTE"}}
        """)
        XCTAssertEqual(numerique.mission?.id, "m-4")
        XCTAssertNil(numerique.mission?.dureeHeures, "valeur non numérique ignorée seule")
        XCTAssertEqual(numerique.mission?.nbCreneaux, 2)
        XCTAssertThrowsError(try decode(MissionSauvegardee.self, #"{"id":"s-5"}"#), "mission_id conditionne l'étoile")
    }

    func testEtablissementFavoriDecodeTolerant() throws {
        let favori = try decode(EtablissementFavori.self, """
        {"etablissement_id":"e-1","nom":"Clinique","ville":"Lyon","logo_url":"https://example.invalid/l.png",
         "type_etablissement":"CLINIQUE","nb_missions_ouvertes":3.0,"cree_le":"2026-10-01T09:00:00+00:00"}
        """)
        XCTAssertEqual(favori.nbMissionsOuvertes, 3, "count(*) relayé en nombre réel : accepté s'il est entier")
        let bancal = try decode(EtablissementFavori.self, #"{"etablissement_id":"e-2","nom":12,"nb_missions_ouvertes":"3"}"#)
        XCTAssertEqual(bancal.id, "e-2")
        XCTAssertNil(bancal.nom)
        XCTAssertNil(bancal.nbMissionsOuvertes)
        XCTAssertThrowsError(try decode(EtablissementFavori.self, #"{"nom":"sans id"}"#))
    }

    func testApercuDepuisUneLigneMission() throws {
        let mission = try XCTUnwrap(DemoFixtures.loadMissions().missions.first { $0.record.id == "demo-mission-006" })
        let apercu = MissionSauvegardee.Apercu(mission.record)
        XCTAssertEqual(apercu.id, "demo-mission-006")
        XCTAssertEqual(apercu.intitule, mission.record.intitule)
        XCTAssertEqual(apercu.debutLe, mission.record.debutLe)
        XCTAssertEqual(apercu.finLe, mission.record.finLe)
        XCTAssertEqual(apercu.dureeHeures, 16)
        XCTAssertEqual(apercu.nbCreneaux, 2)
        XCTAssertEqual(apercu.statut, "OUVERTE")
        XCTAssertEqual(apercu.horaires, mission.record.horaires)
    }
}
