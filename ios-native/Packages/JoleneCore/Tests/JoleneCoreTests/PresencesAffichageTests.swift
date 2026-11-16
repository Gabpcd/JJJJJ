import XCTest
@testable import JoleneCore

/// Dérivations d'affichage de la page Présences (lot 2, T4a), sans texte : état du bloc de pointage d'une mission
/// (`BlocPointageMission.tsx` l.38-127 : fenêtre de 15 min, motifs CONTRAT / AUCUN_CRENEAU / HORS_CRENEAU, ligne
/// « prochain créneau » d'un autre jour), résumé d'une ligne d'historique (`PresencesSoignant.tsx` l.664-682 :
/// segments EFFECTIF fermés d'abord, pointages de la présence à défaut), mission et établissement d'une ligne, et
/// renvois web tant que les écrans natifs (T5a, T9a, lot 4) ne sont pas livrés.
final class PresencesAffichageTests: XCTestCase {
    private let maintenant = DemoWorld.fixedNow // 2026-11-02T00:00:00Z = lundi 2 novembre, 01h00 à Paris

    private func date(_ iso: String) throws -> Date { try DateHeureParis.instantJolene(iso) }

    private func creneau(_ debut: String, _ fin: String?, type: String = "PREVISIONNEL", pause: Bool = false,
                         id: String? = nil) -> MissionSlot {
        MissionSlot(id: id, missionId: "m-1", debut: debut, fin: fin, estPause: pause, typeCreneau: type)
    }

    private let periodeLongue = PeriodeMissionPointage(id: "m-1", debutLe: "2026-11-01T07:00:00Z", finLe: "2026-11-09T15:00:00Z")
    private func contrat(_ statut: String, id: String = "c-1") -> ContratPointage {
        ContratPointage(id: id, statut: statut, creeLe: "2026-10-30T00:00:00Z", missionId: "m-1")
    }

    // MARK: - Bloc de pointage

    func testDansLaFenetreDeQuinzeMinutesAvecContratSigneLeBlocEstPointable() {
        let affichage = BlocPointageAffichage.evaluer(
            creneaux: [creneau("2026-11-02T00:05:00Z", "2026-11-02T08:05:00Z")], mission: periodeLongue,
            contrat: contrat("SIGNE_COMPLET"), maintenant: maintenant)
        XCTAssertEqual(affichage, .pointable(.ouverture))
    }

    func testSegmentOuvertToujoursPointableMemeSansContratSigne() {
        // « Un départ doit toujours rester possible si une arrivée a déjà été enregistrée. »
        let affichage = BlocPointageAffichage.evaluer(
            creneaux: [creneau("2026-11-01T22:00:00Z", "2026-11-02T06:00:00Z"),
                       creneau("2026-11-01T22:00:00Z", nil, type: "EFFECTIF")],
            mission: periodeLongue, contrat: contrat("SIGNE_SOIGNANT"), maintenant: maintenant)
        XCTAssertEqual(affichage, .pointable(.fermeture))
    }

    func testContratNonSigneLeJourMemeSansLigneDeProchainCreneau() {
        let affichage = BlocPointageAffichage.evaluer(
            creneaux: [creneau("2026-11-02T06:00:00Z", "2026-11-02T14:00:00Z")], mission: periodeLongue,
            contrat: contrat("SIGNE_SOIGNANT"), maintenant: maintenant)
        XCTAssertEqual(affichage, .contratNonSigne(contratId: "c-1", prochainAutreJour: nil),
                       "prochain créneau le jour même (Paris) : pas de ligne « Aucun créneau à pointer aujourd’hui » (l.84)")
    }

    func testContratAbsentEtProchainCreneauUnAutreJour() throws {
        let affichage = BlocPointageAffichage.evaluer(
            creneaux: [creneau("2026-11-03T07:00:00Z", "2026-11-03T15:00:00Z")], mission: periodeLongue,
            contrat: nil, maintenant: maintenant)
        XCTAssertEqual(affichage, .contratNonSigne(contratId: nil, prochainAutreJour: try date("2026-11-03T07:00:00Z")),
                       "sans contrat, le motif reste CONTRAT et aucun bouton « Voir le contrat » (l.90)")
    }

    func testAucunCreneauPlanifie() {
        // Mission de plus de 24 h sans ligne PREVISIONNEL : aucun repli ponctuel.
        let affichage = BlocPointageAffichage.evaluer(creneaux: [], mission: periodeLongue, contrat: contrat("SIGNE_COMPLET"),
                                                      maintenant: maintenant)
        XCTAssertEqual(affichage, .aucunCreneau)
    }

    func testPointagePasEncoreOuvertLeJourMeme() throws {
        let affichage = BlocPointageAffichage.evaluer(
            creneaux: [creneau("2026-11-02T08:00:00Z", "2026-11-02T16:00:00Z")], mission: periodeLongue,
            contrat: contrat("SIGNE_COMPLET"), maintenant: maintenant)
        XCTAssertEqual(affichage, .pasEncoreOuvert(debut: try date("2026-11-02T08:00:00Z")))
    }

    func testAucunCreneauAujourdhuiAvecOuSansProchain() throws {
        let demain = BlocPointageAffichage.evaluer(
            creneaux: [creneau("2026-11-03T07:00:00Z", "2026-11-03T15:00:00Z")], mission: periodeLongue,
            contrat: contrat("SIGNE_COMPLET"), maintenant: maintenant)
        XCTAssertEqual(demain, .aucunAujourdhui(prochain: try date("2026-11-03T07:00:00Z")))

        let termines = BlocPointageAffichage.evaluer(
            creneaux: [creneau("2026-10-31T07:00:00Z", "2026-10-31T15:00:00Z")], mission: periodeLongue,
            contrat: contrat("SIGNE_COMPLET"), maintenant: maintenant)
        XCTAssertEqual(termines, .aucunAujourdhui(prochain: nil), "« Tous les créneaux planifiés sont terminés. »")
    }

    func testMissionPonctuelleSansCreneauUtiliseSaPlageGlobale() {
        // Repli ponctuel (`ajouterRepliMissionPonctuelle`, l.43) : plage de 8 h, fenêtre ouverte à 00h50 (Paris).
        let ponctuelle = PeriodeMissionPointage(id: "m-1", debutLe: "2026-11-02T00:05:00Z", finLe: "2026-11-02T08:05:00Z")
        let affichage = BlocPointageAffichage.evaluer(creneaux: [], mission: ponctuelle, contrat: contrat("SIGNE_COMPLET"),
                                                      maintenant: maintenant)
        XCTAssertEqual(affichage, .pointable(.ouverture))
    }

    func testBlocsDuMondeDemo() async throws {
        let instantane = try await DemoPointageGateway(clock: FixedClock(maintenant)).presences(context: DemoWorld.context)
        let listes = instantane.listes(maintenant: maintenant)
        let parId = Dictionary(uniqueKeysWithValues: listes.missionsAujourdhui.map { ($0.mission.id, $0) })
        let a = try XCTUnwrap(parId["demo-presence-a"]), b = try XCTUnwrap(parId["demo-presence-b"])
        let c = try XCTUnwrap(parId["demo-presence-c"])
        XCTAssertEqual(BlocPointageAffichage.evaluer(a, contrat: listes.contrats["demo-presence-a"], maintenant: maintenant),
                       .pointable(.ouverture), "mission a : dans les 15 min, contrat signé")
        XCTAssertEqual(BlocPointageAffichage.evaluer(b, contrat: listes.contrats["demo-presence-b"], maintenant: maintenant),
                       .pointable(.fermeture), "mission b : segment ouvert")
        XCTAssertEqual(BlocPointageAffichage.evaluer(c, contrat: listes.contrats["demo-presence-c"], maintenant: maintenant),
                       .contratNonSigne(contratId: "demo-contrat-pointage-c", prochainAutreJour: nil), "mission c : motif CONTRAT")
    }

    // MARK: - Résumé d'une ligne d'historique

    func testResumeDepuisLesSegmentsEffectifsFermes() throws {
        let resume = ResumeLignePresence.construire(
            creneaux: [creneau("2026-10-28T12:30:00Z", "2026-10-28T15:00:00Z", type: "EFFECTIF"),
                       creneau("2026-10-28T07:00:00Z", "2026-10-28T12:00:00Z", type: "EFFECTIF"),
                       creneau("2026-10-28T12:00:00Z", "2026-10-28T12:30:00Z", type: "EFFECTIF", pause: true),
                       creneau("2026-10-28T16:00:00Z", nil, type: "EFFECTIF"),
                       creneau("2026-10-28T06:00:00Z", "2026-10-28T18:00:00Z")],
            pointageArriveeLe: "2026-10-28T06:55:00Z", pointageDepartLe: "2026-10-28T15:10:00Z")
        XCTAssertEqual(resume, ResumeLignePresence(arrivee: try date("2026-10-28T07:00:00Z"), depart: try date("2026-10-28T15:00:00Z"),
                                                   heures: 7.5),
                       "segments EFFECTIF fermés hors pause, triés par début ; la présence legacy ne sert qu'à défaut")
    }

    func testResumeDepuisLaPresenceQuandAucunSegment() throws {
        let complet = ResumeLignePresence.construire(creneaux: [], pointageArriveeLe: "2026-10-30T07:00:00Z",
                                                     pointageDepartLe: "2026-10-30T15:00:00Z")
        XCTAssertEqual(complet, ResumeLignePresence(arrivee: try date("2026-10-30T07:00:00Z"), depart: try date("2026-10-30T15:00:00Z"),
                                                    heures: 8))
        let sansDepart = ResumeLignePresence.construire(creneaux: [], pointageArriveeLe: "2026-10-30T07:00:00Z", pointageDepartLe: nil)
        XCTAssertEqual(sansDepart, ResumeLignePresence(arrivee: try date("2026-10-30T07:00:00Z"), depart: nil, heures: nil))
        XCTAssertEqual(ResumeLignePresence.construire(creneaux: [], pointageArriveeLe: nil, pointageDepartLe: "illisible"),
                       ResumeLignePresence(arrivee: nil, depart: nil, heures: nil), "une date illisible n'est jamais affichée")
    }

    // MARK: - Lignes du monde démo

    func testLignesDemoMissionEtablissementEtResume() async throws {
        let instantane = try await DemoPointageGateway(clock: FixedClock(maintenant)).presences(context: DemoWorld.context)
        let lignes = instantane.lignesHistorique(soignantId: DemoWorld.context.userId)
        XCTAssertEqual(lignes.map(\.id), ["demo-presence-h1-presence", "demo-presence-h2-presence", "effectifs-mission-demo-presence-h3"])

        let validee = lignes[0]
        XCTAssertEqual(instantane.mission(de: validee), MissionDeLigne(intitule: "Démonstration · Présence validée",
                                                                      debutLe: "2026-10-31T07:00:00.000Z"))
        XCTAssertEqual(validee.etablissement?.nom, "Établissement fictif République")
        XCTAssertTrue(validee.valideParEtablissement)
        XCTAssertFalse(validee.origineEffectifsSansPresence)
        XCTAssertEqual(validee.methodeArrivee, "CODE")
        XCTAssertEqual(validee.resume.heures, 8)

        let reconstruite = lignes[2]
        XCTAssertEqual(instantane.mission(de: reconstruite), MissionDeLigne(intitule: "Démonstration · Heures pointées sans présence",
                                                                           debutLe: "2026-10-28T07:00:00.000Z"),
                       "ligne reconstruite : mission relue dans les missions terminées")
        XCTAssertEqual(reconstruite.etablissement?.nom, "Cabinet fictif du Parc")
        XCTAssertTrue(reconstruite.origineEffectifsSansPresence)
        XCTAssertNil(reconstruite.methodeArrivee)
        XCTAssertNil(reconstruite.methodeDepart)
        XCTAssertEqual(reconstruite.pointageArriveeLe, "2026-10-28T07:00:00.000Z")
        XCTAssertEqual(reconstruite.resume.heures, 7.5)

        let presence = try XCTUnwrap(instantane.presencesValidees.first)
        XCTAssertEqual(instantane.etablissement(de: presence)?.nom, "Établissement fictif République")
    }

    // MARK: - Renvois web

    func testRenvoisWebResolusParLeRouteurSansURLEnDur() throws {
        let contrat = try XCTUnwrap(PresencesRenvois.contrat(id: "c-1"))
        XCTAssertEqual(contrat.externalURL?.absoluteString, "https://jolene.app/contrat/c-1")
        XCTAssertFalse(contrat.isNative, "contrat natif à T9a : renvoi web d'ici là")
        XCTAssertEqual(PresencesRenvois.litiges?.externalURL?.absoluteString, "https://jolene.app/soignant/litiges")
    }

    /// Récapitulatif financier du détail des présences (décision 11 : non porté, renvoi web jusqu'au lot 3) : route
    /// FORCÉE web, construite sans `LinkRouter`, pour survivre au routage natif de `/soignant/presences/mission/:id`
    /// (T10). Revue fraîche de T5a, M3 : `AccueilPresentation.renvoiWeb` rendait nil dès que la route devenait native.
    func testRecapitulatifFinancierResteUnRenvoiWebQuandLeDetailDevientNatif() throws {
        let recapitulatif = try XCTUnwrap(PresencesRenvois.recapitulatifFinancier(missionId: "m-1"))
        XCTAssertEqual(recapitulatif, .safari(try XCTUnwrap(URL(string: "https://jolene.app/soignant/presences/mission/m-1"))))
        XCTAssertFalse(recapitulatif.isNative)
        XCTAssertEqual(PresencesRenvois.recapitulatifFinancier(missionId: "demo-presence-a")?.externalURL?.absoluteString,
                       "https://jolene.app/soignant/presences/mission/demo-presence-a")

        // Indépendance du routage natif : sur un chemin que `LinkRouter` rend DÉJÀ natif (détail d'une mission), la route
        // forcée reste un renvoi web. Quand T10 routera `/soignant/presences/mission/:id` vers `DetailPresencesScreen`, le
        // renvoi du récapitulatif ne disparaîtra donc pas (là où `AccueilPresentation.renvoiWeb` rendrait nil).
        XCTAssertEqual(LinkRouter.resolve(link: "/soignant/missions/m-1"), .missionDetail(id: "m-1"))
        XCTAssertNil(AccueilPresentation.renvoiWeb("/soignant/missions/m-1"), "le renvoi résolu par le routeur disparaît")
        let force = try XCTUnwrap(PresencesRenvois.renvoiWebForce("/soignant/missions/", identifiant: "m-1"))
        XCTAssertEqual(force.externalURL?.absoluteString, "https://jolene.app/soignant/missions/m-1")
        XCTAssertFalse(force.isNative)

        // Identifiant hors segment sûr (vide, séparateurs, requête, fragment, traversée, encodage) : aucun renvoi.
        for invalide in ["", "a/b", "a?tab=x", "a#b", "..", "m 1", "m%2F1", "é"] {
            XCTAssertNil(PresencesRenvois.recapitulatifFinancier(missionId: invalide), "« \(invalide) » accepté")
        }
    }
}
