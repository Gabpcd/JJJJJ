import XCTest
@testable import JoleneCore

/// Mes missions du monde démo (lot 1, T5) : `demo-mes-missions.json` (candidatures, passées) et les
/// missions ASSIGNEE de `demo-dashboard.json` (« À venir », source unique avec l'Accueil), aucun
/// réseau, horloge fixée. Les valeurs attendues sont celles que le XCUITest `DemoMesMissionsTests`
/// relit à l'écran.
final class DemoMesMissionsTests: XCTestCase {
    private let euro = "\u{00A0}€"
    private var port: MesMissionsPort { DemoWorld.gateways().mesMissions }

    func testFixtureHorlogeFixeeEtCoherenceAvecLeTableauDeBord() throws {
        let fichier = try DemoFixtures.loadMesMissions()
        XCTAssertEqual(fichier.fixedNow, "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(fichier.candidatures.map(\.id), ["demo-candidature-001", "demo-candidature-002"])
        XCTAssertEqual(fichier.passees.map(\.mission.record.id), ["demo-terminee-001", "demo-terminee-002", "demo-annulee-001"])
        // Même mission terminée que les gains de l'Accueil : mêmes valeurs serveur.
        let gains = try XCTUnwrap(DemoFixtures.loadDashboard().gainsMissions.first)
        let terminee = try XCTUnwrap(fichier.passees.first { $0.finance.id == gains.id })
        XCTAssertEqual(terminee.finance, gains)
        let ouvertes = Set(try DemoFixtures.loadMissions().missions.map(\.record.id))
        XCTAssertTrue(fichier.candidatures.allSatisfy { ouvertes.contains($0.missionId) }, "candidatures sur des missions démo ouvertes")
    }

    func testCandidaturesEnAttenteAvecLeurMissionEnrichie() async throws {
        let candidatures = try await port.candidatures(context: DemoWorld.context)
        XCTAssertEqual(candidatures.map(\.id), ["demo-candidature-001", "demo-candidature-002"], "`cree_le` décroissant")
        let lignes = candidatures.compactMap { MesMissionsPresentation.ligne(candidature: $0, maintenant: DemoWorld.fixedNow) }
        XCTAssertEqual(lignes.map(\.id), ["demo-mission-004", "demo-mission-009"])
        XCTAssertEqual(lignes.map(\.texteAccessible), [
            "⏳ En attente de réponse, Salarié, Démonstration · Soins de suite 4, Établissement fictif République · Paris, 6 nov. · 21h00 → 05h00, 26,00\(euro)/h",
            "⏳ En attente de réponse, ★ Priorité historique, Libéral, Démonstration · Médecine polyvalente 9, Cabinet fictif du Parc · Vincennes, 11 nov. · 08h00 → 16h00, 23,00\(euro)/h",
        ])
    }

    func testCandidaturesDeSessionEnTeteEtMissionMasqueeEcartee() async throws {
        let posee = CandidatureRecord(id: "session-1", missionId: "demo-mission-002", statut: "EN_ATTENTE", message: nil,
                                      typeContratChoisi: nil, creeLe: "2026-11-02T00:00:00.000Z")
        let masquee = CandidatureRecord(id: "session-2", missionId: "demo-mission-999", statut: "EN_ATTENTE", message: nil,
                                        typeContratChoisi: nil, creeLe: "2026-11-02T00:00:00.000Z")
        let acceptee = CandidatureRecord(id: "session-3", missionId: "demo-mission-003", statut: "ACCEPTEE", message: nil,
                                         typeContratChoisi: nil, creeLe: "2026-11-02T00:00:00.000Z")
        let gateway = DemoMesMissionsGateway(candidaturesDeSession: { [posee, masquee, acceptee] })
        let candidatures = try await gateway.candidatures(context: DemoWorld.context)
        XCTAssertEqual(candidatures.map(\.id), ["session-1", "demo-candidature-001", "demo-candidature-002"],
                       "mission absente écartée, statut hors attente filtré, la plus récente d'abord")
        XCTAssertEqual(candidatures.first?.mission?.etablissement?.nom, "Établissement fictif des Lilas")
    }

    func testAVenirLesMissionsAssigneesDeLAccueil() async throws {
        let page = try await port.aVenir(context: DemoWorld.context, page: 0)
        XCTAssertEqual(page.missions.map(\.id), ["demo-assignee-001", "demo-assignee-002"])
        XCTAssertFalse(page.aSuivre)
        XCTAssertEqual(page.finances, [:])
        let lignes = page.missions.map { MesMissionsPresentation.ligneAVenir($0, maintenant: DemoWorld.fixedNow) }
        XCTAssertEqual(lignes.map(\.horaire), ["Prochain créneau : 5 nov. · 08h00 → 16h00 (8h)",
                                               "Prochain créneau : 9 nov. · 08h00 → 16h00 (8h)"])
        XCTAssertEqual(lignes.map(\.lieu), ["Établissement fictif République · Paris", "Établissement fictif des Lilas · Les Lilas"])
        XCTAssertEqual(page.missions.map { CalendrierMission.evenements(pour: $0).count }, [1, 2], "créneaux ajoutables au calendrier")
        let suivante = try await port.aVenir(context: DemoWorld.context, page: 1)
        XCTAssertEqual(suivante.missions, [], "une seule page en démo")
    }

    func testPasseesMontantsServeurEtDetailLisible() async throws {
        let page = try await port.passees(context: DemoWorld.context, page: 0)
        XCTAssertEqual(page.missions.map(\.id), ["demo-terminee-001", "demo-terminee-002", "demo-annulee-001"], "`debut_le` décroissant")
        let lignes = page.missions.map { MesMissionsPresentation.lignePassee($0, finance: page.finances[$0.id]) }
        XCTAssertEqual(lignes.map(\.texteAccessible), [
            "Terminée, Démonstration · Mission terminée 1, Établissement fictif République, 1 nov. 2026, Net salarié estimé* : ~162,40\(euro)",
            "Terminée, Démonstration · Mission terminée 2, Établissement fictif des Lilas, 20 oct. → 21 oct. 2026, Honoraires bruts : 448,00\(euro)",
            "Annulée, Démonstration · Mission annulée, Cabinet fictif du Parc, 12 oct. 2026",
        ])
        let detail = try await DemoWorld.gateways().missions.mission(id: "demo-terminee-002", context: DemoWorld.context)
        XCTAssertEqual(detail?.record.statut, "TERMINEE", "une mission passée s'ouvre en détail")
        XCTAssertEqual(detail?.creneauxPlanifies.count, 2)
    }

    private static func autreContexte() -> MissionReadContext {
        var autre = DemoWorld.context
        autre.userId = "user-1"
        autre.profile.id = "user-1"
        return autre
    }

    func testAutreUtilisateurRefuseAvecErreurDemoOnly() async {
        let autre = Self.autreContexte()
        for appel in [{ _ = try await self.port.candidatures(context: autre) },
                      { _ = try await self.port.aVenir(context: autre, page: 0) },
                      { _ = try await self.port.passees(context: autre, page: 0) }] as [() async throws -> Void] {
            do {
                try await appel()
                XCTFail("la démo ne sert aucun autre utilisateur")
            } catch let error as JoleneError {
                XCTAssertEqual(error, JoleneError(.demoOnly, DemoWorld.messageDemoSeulement))
            } catch {
                XCTFail("type d'erreur inattendu : \(error)")
            }
        }
    }

    func testPaginationDeCinquanteCommeLeWeb() {
        let missions = (0..<120).map { index in
            Mission(record: MissionRecord(id: "m-\(index)", intitule: "M", description: nil, service: nil, professionRequise: "IDE",
                                          specialiteMedicaleRequise: nil, accepteNonSpecialises: nil, debutLe: "2026-11-05T07:00:00.000Z",
                                          finLe: "2026-11-05T15:00:00.000Z", dureeHeures: nil, nbCreneaux: 1, tauxHoraireBase: nil,
                                          tauxRistPlafonne: nil, ristPlafondApplique: nil, totalBrut: nil, netAPayer: nil, estUrgente: false,
                                          niveauUrgence: nil, statut: "ASSIGNEE", etablissementId: "e", typeContratRecherche: nil,
                                          boosteeLe: nil, modeRemuneration: nil, retrocessionPct: nil),
                    etablissement: nil, distanceKm: nil, creneauxPlanifies: [], planningExact: false)
        }
        let premiere = DemoMesMissionsGateway.page(missions, page: 0)
        XCTAssertEqual(premiere.missions.map(\.id).first, "m-0")
        XCTAssertEqual(premiere.missions.count, MissionsPage.taille)
        XCTAssertTrue(premiere.aSuivre, "page pleine : « Charger plus » proposé")
        let troisieme = DemoMesMissionsGateway.page(missions, page: 2)
        XCTAssertEqual(troisieme.missions.map(\.id), (100..<120).map { "m-\($0)" })
        XCTAssertFalse(troisieme.aSuivre)
        XCTAssertEqual(DemoMesMissionsGateway.page(missions, page: 3).missions, [])
    }
}
