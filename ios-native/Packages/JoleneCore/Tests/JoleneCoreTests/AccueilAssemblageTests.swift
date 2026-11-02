import XCTest
@testable import JoleneCore

/// Assemblage de l'Accueil (lot 1, T3), port de `enrichirPlanning` et du rendu de
/// `DashboardSoignant.tsx` (l.147-215, l.431-770) : planning PREVISIONNEL vérifié par
/// `CompletudePlanning` (rendu partiel `planning_indisponible`, jamais une erreur d'écran),
/// nom d'établissement issu de `fn_etablissements_safe`, propositions expirées écartées, gains du
/// mois relus mission par mission (décision 10), textes de l'écran.
final class AccueilAssemblageTests: XCTestCase {
    private let maintenant = DemoWorld.fixedNow // 2026-11-02T00:00:00Z (01:00 à Paris)
    private let contexte = MissionReadContext(userId: "u-1", email: "u-1@example.invalid",
                                              profile: SoignantProfile(id: "u-1", profession: "IDE", adresseLat: 48.8566, adresseLng: 2.3522))

    // MARK: - Fabriques

    private func ligne(_ id: String, statut: String? = "ASSIGNEE", intitule: String? = nil, etablissement: String? = "e-1",
                       etabNom: String? = "Nom du tableau de bord", urgente: Bool = false) -> DashboardMissionLigne {
        DashboardMissionLigne(id: id, intitule: intitule ?? "Mission \(id)", service: "Urgences",
                              debutLe: "2026-11-05T07:00:00.000Z", finLe: "2026-11-05T15:00:00.000Z", statut: statut,
                              estUrgente: urgente, tauxHoraireBase: 25, etablissementId: etablissement, etabNom: etabNom)
    }

    private func record(_ id: String, nbCreneaux: Int?, debut: String = "2026-11-05T07:00:00.000Z",
                        fin: String = "2026-11-05T15:00:00.000Z", statut: String = "ASSIGNEE") -> MissionRecord {
        MissionRecord(id: id, intitule: "Mission \(id)", description: nil, service: "Urgences", professionRequise: "IDE",
                      specialiteMedicaleRequise: nil, accepteNonSpecialises: nil, debutLe: debut, finLe: fin, dureeHeures: 8,
                      nbCreneaux: nbCreneaux, tauxHoraireBase: 25, tauxRistPlafonne: nil, ristPlafondApplique: nil,
                      totalBrut: nil, netAPayer: nil, estUrgente: false, niveauUrgence: nil, statut: statut,
                      etablissementId: "e-1", typeContratRecherche: "SALARIE", boosteeLe: nil, modeRemuneration: nil,
                      retrocessionPct: nil)
    }

    private func creneau(_ id: String, _ mission: String, _ debut: String, _ fin: String) -> MissionSlot {
        MissionSlot(id: id, missionId: mission, debut: debut, fin: fin, estPause: false, typeCreneau: "PREVISIONNEL")
    }

    private func assembler(_ corps: DashboardCorps, lecture: LectureMissionsAccueil?,
                           etablissements: [String: EtablissementSummary] = [:], gains: [MissionGainLigne]? = [],
                           contexte: MissionReadContext? = nil) throws -> DashboardSnapshot {
        try AccueilAssemblage.snapshot(corps: corps, context: contexte ?? self.contexte, maintenant: maintenant, lecture: lecture,
                                       etablissements: etablissements, gains: gains)
    }

    // MARK: - Planning

    func testPlanningCompletDonneLeProchainCreneauEtSonRang() throws {
        // Mission EN_COURS : premier créneau terminé, le prochain est le second (créneau 2/2).
        let corps = DashboardCorps(mesMissions: [ligne("m-1", statut: "EN_COURS")])
        let lecture = LectureMissionsAccueil(
            records: [record("m-1", nbCreneaux: 2, debut: "2026-11-01T07:00:00.000Z", fin: "2026-11-09T15:00:00.000Z", statut: "EN_COURS")],
            creneaux: [creneau("c-2", "m-1", "2026-11-09T07:00:00.000Z", "2026-11-09T15:00:00.000Z"),
                       creneau("c-1", "m-1", "2026-11-01T07:00:00.000Z", "2026-11-01T15:00:00.000Z")])
        let snapshot = try assembler(corps, lecture: lecture)
        let mission = try XCTUnwrap(snapshot.prochaines.first)
        XCTAssertEqual(mission.planning, .planifie(prochain: lecture.creneaux[0], rang: 2, nombre: 2))
        XCTAssertEqual(AccueilPresentation.planningProchaine(mission.planning), "lundi 9 nov. · 08h00 → 16h00 · créneau 2/2")
        XCTAssertEqual(AccueilPresentation.planningPourToi(mission.planning), "lundi 9 nov. · 08h00 → 16h00 · 2 créneaux au total")
        XCTAssertEqual(AccueilPresentation.jour(mission.planning).map { [$0.semaine, $0.jour, $0.mois] }, ["lun.", "9", "nov."])
        XCTAssertEqual(mission.mission?.id, "m-1", "la mission enrichie sert de valeur initiale au détail")
        XCTAssertFalse(snapshot.planningIndisponible)
    }

    func testNombreDeCreneauxDivergentRendLePlanningIndisponible() throws {
        let corps = DashboardCorps(mesMissions: [ligne("m-1")])
        let lecture = LectureMissionsAccueil(records: [record("m-1", nbCreneaux: 3)],
                                             creneaux: [creneau("c-1", "m-1", "2026-11-05T07:00:00.000Z", "2026-11-05T15:00:00.000Z")])
        let mission = try XCTUnwrap(try assembler(corps, lecture: lecture).prochaines.first)
        XCTAssertEqual(mission.planning, .indisponible, "un planning tronqué n'est jamais présenté comme exact")
        XCTAssertEqual(AccueilPresentation.planningProchaine(mission.planning), AccueilPresentation.planningAConfirmer)
        XCTAssertEqual(AccueilPresentation.planningAConfirmer, "Planning détaillé à confirmer")
        XCTAssertNil(AccueilPresentation.jour(mission.planning))
    }

    func testLectureEnEchecRendToutLePlanningIndisponibleSansErreurDEcran() throws {
        let corps = DashboardCorps(missionsOuvertes: [ligne("m-2", statut: nil)], mesMissions: [ligne("m-1")])
        let snapshot = try assembler(corps, lecture: nil)
        XCTAssertTrue(snapshot.planningIndisponible)
        XCTAssertEqual((snapshot.prochaines + snapshot.pourToi).map(\.planning), [.indisponible, .indisponible])
        XCTAssertEqual((snapshot.prochaines + snapshot.pourToi).map(\.mission), [nil, nil])
        XCTAssertEqual(snapshot.prochaines.map(\.id), ["m-1"], "les lignes du tableau de bord restent affichées")
    }

    func testFicheMissionAbsenteRendSeuleCetteMissionIndisponible() throws {
        let corps = DashboardCorps(missionsOuvertes: [ligne("m-2", statut: nil)], mesMissions: [ligne("m-1")])
        let lecture = LectureMissionsAccueil(records: [record("m-1", nbCreneaux: 1)],
                                             creneaux: [creneau("c-1", "m-1", "2026-11-05T07:00:00.000Z", "2026-11-05T15:00:00.000Z")])
        let snapshot = try assembler(corps, lecture: lecture)
        XCTAssertEqual(snapshot.prochaines.first?.planning, .planifie(prochain: lecture.creneaux[0], rang: 1, nombre: 1))
        XCTAssertEqual(snapshot.pourToi.first?.planning, .indisponible, "sans nb_creneaux relu, le planning n'est pas vérifiable")
        XCTAssertNil(snapshot.pourToi.first?.mission)
        XCTAssertEqual(AccueilPresentation.planningProchaine(snapshot.prochaines[0].planning), "jeudi 5 nov. · 08h00 → 16h00")
    }

    func testMissionPonctuelleSansCreneauUtiliseLeRepliDeLaPeriode() throws {
        let corps = DashboardCorps(mesMissions: [ligne("m-1")])
        let lecture = LectureMissionsAccueil(records: [record("m-1", nbCreneaux: nil)], creneaux: [])
        let mission = try XCTUnwrap(try assembler(corps, lecture: lecture).prochaines.first)
        guard case let .planifie(prochain, rang, nombre) = mission.planning else { return XCTFail("repli ponctuel attendu") }
        XCTAssertEqual(prochain?.debut, "2026-11-05T07:00:00.000Z")
        XCTAssertEqual(rang, 1)
        XCTAssertEqual(nombre, 1)
    }

    func testCreneauxTousPassesLaissentUnPlanningSansProchainCreneau() throws {
        let corps = DashboardCorps(mesMissions: [ligne("m-1", statut: "EN_COURS")])
        let lecture = LectureMissionsAccueil(records: [record("m-1", nbCreneaux: 1, debut: "2026-11-01T07:00:00.000Z", fin: "2026-11-01T15:00:00.000Z")],
                                             creneaux: [creneau("c-1", "m-1", "2026-11-01T07:00:00.000Z", "2026-11-01T15:00:00.000Z")])
        let mission = try XCTUnwrap(try assembler(corps, lecture: lecture).prochaines.first)
        XCTAssertEqual(mission.planning, .planifie(prochain: nil, rang: nil, nombre: 1))
        XCTAssertEqual(AccueilPresentation.planningProchaine(mission.planning), AccueilPresentation.planningAConfirmer)
    }

    // MARK: - Établissement, cohorte de test, ordre

    func testNomEtablissementSafeDAbordPuisTableauDeBordPuisRepli() throws {
        let corps = DashboardCorps(mesMissions: [ligne("m-1", etablissement: "e-1"), ligne("m-2", etablissement: "e-2"),
                                                 ligne("m-3", etablissement: "e-3", etabNom: nil), ligne("m-4", etablissement: nil, etabNom: " ")])
        let safe = ["e-1": EtablissementSummary(id: "e-1", nom: "Clinique safe", adresseVille: "Lyon"),
                    "e-3": EtablissementSummary(id: "e-3", nom: "  ")]
        let snapshot = try assembler(corps, lecture: nil, etablissements: safe)
        XCTAssertEqual(snapshot.prochaines.map(\.etablissementNom),
                       ["Clinique safe", "Nom du tableau de bord", "Établissement", "Établissement"])
        XCTAssertEqual(snapshot.prochaines.map(\.etablissementVille), ["Lyon", nil, nil, nil])
    }

    func testMissionsDeTestPlaywrightMasqueesAuxComptesOrdinaires() throws {
        let corps = DashboardCorps(missionsOuvertes: [ligne("o-1", statut: nil, intitule: "[pw-test:abc] Ouverte"), ligne("o-2", statut: nil)],
                                   mesMissions: [ligne("m-1", intitule: "[playwright-test] Assignée"), ligne("m-2")])
        let ordinaire = try assembler(corps, lecture: nil)
        XCTAssertEqual(ordinaire.prochaines.map(\.id), ["m-2"])
        XCTAssertEqual(ordinaire.pourToi.map(\.id), ["o-2"])
        XCTAssertEqual(AccueilAssemblage.identifiantsMissions(corps, email: contexte.email), ["m-2", "o-2"])

        var playwright = contexte
        playwright.email = "playwright-soignant@example.invalid"
        let test = try assembler(corps, lecture: nil, contexte: playwright)
        XCTAssertEqual(test.prochaines.map(\.id), ["m-1", "m-2"])
        XCTAssertEqual(test.pourToi.map(\.id), ["o-1", "o-2"])
    }

    func testIdentifiantsUniquesDansLOrdreDuTableauDeBord() throws {
        let proposition = DashboardProposition(id: "p-1", missionId: "o-1", creeLe: "2026-11-01T23:30:00.000Z", typeContratChoisi: nil,
                                               mission: ligne("o-1", statut: nil))
        let corps = DashboardCorps(missionsOuvertes: [ligne("o-1", statut: nil), ligne("o-2", statut: nil)],
                                   mesMissions: [ligne("m-1")], propositions: [proposition])
        XCTAssertEqual(AccueilAssemblage.identifiantsMissions(corps, email: nil), ["m-1", "o-1", "o-2"])
        XCTAssertEqual(AccueilAssemblage.identifiantsEtablissements(corps), ["e-1"])
    }

    // MARK: - Propositions

    func testPropositionsExpireesOuIllisiblesEcartees() throws {
        func proposition(_ id: String, creeLe: String) -> DashboardProposition {
            DashboardProposition(id: id, missionId: "o-\(id)", creeLe: creeLe, typeContratChoisi: nil, mission: ligne("o-\(id)", statut: nil, urgente: true))
        }
        let corps = DashboardCorps(propositions: [
            proposition("p-1", creeLe: "2026-11-01T23:30:00.000Z"), // 30 min : 1 h 30 restantes
            proposition("p-2", creeLe: "2026-11-01T21:59:00.000Z"), // 2 h 01 : expirée
            proposition("p-3", creeLe: "pas une date"),
            proposition("p-4", creeLe: "2026-11-01T22:05:00.000Z"), // 1 h 55 : 5 min restantes
        ])
        let snapshot = try assembler(corps, lecture: nil, etablissements: ["e-1": EtablissementSummary(id: "e-1", nom: "Clinique safe")])
        XCTAssertEqual(snapshot.propositions.map(\.id), ["p-1", "p-4"])
        XCTAssertEqual(snapshot.propositions.map(\.etablissementNom), ["Clinique safe", "Clinique safe"])
        XCTAssertEqual(snapshot.propositions.map { AccueilPresentation.tempsRestant(expireLe: $0.expireLe, maintenant: maintenant) },
                       ["1h 30min", "0h 05min"])
        XCTAssertNil(AccueilPresentation.tempsRestant(expireLe: snapshot.propositions[0].expireLe,
                                                       maintenant: snapshot.propositions[0].expireLe), "à l'échéance, la carte disparaît")
        XCTAssertEqual(AccueilAssemblage.expirationPropositionMinutes, 120)
    }

    // MARK: - Gains (décision 10)

    func testGainsRelusMissionParMissionCommeLeWeb() {
        let lignes = [
            MissionGainLigne(id: "t-1", typeContratApplique: "LIBERAL", typeContratRecherche: "SALARIE", totalBrut: 1_000, netAPayer: 980, netEstime: 780),
            MissionGainLigne(id: "t-2", typeContratApplique: nil, typeContratRecherche: "SALARIE", totalBrut: 444.68, netAPayer: 444.68, netEstime: 346.85),
            MissionGainLigne(id: "t-3", typeContratApplique: "SALARIE", typeContratRecherche: nil, totalBrut: 300, netAPayer: 320, netEstime: nil),
            MissionGainLigne(id: "t-4", typeContratApplique: "TOUS", typeContratRecherche: "TOUS", totalBrut: nil, netAPayer: 210, netEstime: 150),
            MissionGainLigne(id: "t-5", typeContratApplique: "LIBERAL", typeContratRecherche: nil, totalBrut: 90, netAPayer: nil, netEstime: nil),
            MissionGainLigne(id: "t-6", typeContratApplique: nil, typeContratRecherche: nil, totalBrut: nil, netAPayer: nil, netEstime: nil),
        ]
        XCTAssertEqual(lignes.map { GainsDuMois.montant($0)?.nature },
                       [.honorairesLiberaux, .netSalarieEstime, nil, .brutIndicatif, .honorairesLiberaux, nil])
        XCTAssertEqual(lignes.map { GainsDuMois.montant($0)?.montant }, [980, 346.85, nil, 210, 90, nil],
                       "libéral : net_a_payer puis total_brut ; salarié : net_estime seul ; sinon total_brut puis net_a_payer")
        let gains = GainsDuMois.agreger(lignes)
        XCTAssertEqual(gains, GainsDuMois(honoraires: 1_070, netSalarie: 346.85, brutIndicatif: 210, nombreMissions: 4))
        XCTAssertEqual(AccueilPresentation.texteGains(gains),
                       "💰 Ce mois : 1\u{202F}070,00\u{00A0}€ d’honoraires + 346,85\u{00A0}€ net salarié estimé* + 210,00\u{00A0}€ brut indicatif sur 4 missions")
        XCTAssertTrue(AccueilPresentation.afficheNoteNetEstime(gains))

        let liberal = GainsDuMois.agreger([lignes[0]])
        XCTAssertEqual(AccueilPresentation.texteGains(liberal), "💰 Ce mois : 980,00\u{00A0}€ d’honoraires sur 1 mission")
        XCTAssertFalse(AccueilPresentation.afficheNoteNetEstime(liberal), "la note ne couvre que le net estimé et le brut indicatif")
        XCTAssertNil(AccueilPresentation.texteGains(GainsDuMois.agreger([])), "aucune mission relue : carte masquée")
        XCTAssertNil(AccueilPresentation.texteGains(GainsDuMois.agreger([lignes[2], lignes[5]])), "aucun montant serveur : carte masquée")
    }

    func testGainsIndisponiblesMasquentLaCarteSansErreur() throws {
        let corps = DashboardCorps(gainsMoisNbMissions: 3)
        let sansGains = try assembler(corps, lecture: nil, gains: nil)
        XCTAssertNil(sansGains.gains)
        XCTAssertEqual(sansGains.gainsMoisNbMissions, 3, "compteur serveur conservé")
        let avecGains = try assembler(corps, lecture: nil, gains: [MissionGainLigne(id: "t-1", typeContratApplique: "SALARIE",
                                                                                     typeContratRecherche: nil, totalBrut: 208,
                                                                                     netAPayer: 224.6, netEstime: 162.4)])
        XCTAssertEqual(avecGains.gains, GainsDuMois(honoraires: 0, netSalarie: 162.4, brutIndicatif: 0, nombreMissions: 1))
    }

    func testNoteNetEstimeVerbatimDuWeb() {
        // `src/components/NoteNetEstime.tsx` : texte repris mot pour mot (HARD STOP n°4).
        XCTAssertEqual(AccueilPresentation.noteNetEstime,
                       "* Pour une mission salariée, le net est estimé après cotisations sociales et avant prélèvement à la source. "
                       + "Tant que le régime n'est pas choisi, le montant affiché reste une rémunération brute indicative. "
                       + "Cette estimation peut différer du net du bulletin officiel établi par l’employeur ou son service paie.")
    }

    // MARK: - Textes de l'écran

    func testSalutationSelonLHeureLocaleCommeLeWeb() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        func a(_ iso: String) -> Date { PlanningHorlogeParis.instant(iso)! }
        XCTAssertEqual(AccueilPresentation.salutation(prenom: "Camille", maintenant: a("2026-11-02T03:59:00Z"), fuseau: paris), "Bonsoir, Camille")
        XCTAssertEqual(AccueilPresentation.salutation(prenom: "Camille", maintenant: a("2026-11-02T04:00:00Z"), fuseau: paris), "Bonjour, Camille")
        XCTAssertEqual(AccueilPresentation.salutation(prenom: "Camille", maintenant: a("2026-11-02T16:59:00Z"), fuseau: paris), "Bonjour, Camille")
        XCTAssertEqual(AccueilPresentation.salutation(prenom: "Camille", maintenant: a("2026-11-02T17:00:00Z"), fuseau: paris), "Bonsoir, Camille")
        XCTAssertEqual(AccueilPresentation.salutation(prenom: "  ", maintenant: a("2026-11-02T10:00:00Z"), fuseau: paris), "Bonjour")
        XCTAssertEqual(AccueilPresentation.salutation(prenom: nil, maintenant: a("2026-11-02T10:00:00Z"), fuseau: paris), "Bonjour")
    }

    func testAccrocheSelonDocumentsEtMissionsOuvertes() {
        let valide = DashboardProfil(prenom: "A", profession: "IDE", tousDocumentsValides: true, typeExercice: nil)
        let enCours = DashboardProfil(prenom: "A", profession: "IDE", tousDocumentsValides: false, typeExercice: nil)
        XCTAssertEqual(AccueilPresentation.accroche(profil: enCours, nombreOuvertes: 3), "3 missions près de chez vous — vous pouvez déjà postuler.")
        XCTAssertEqual(AccueilPresentation.accroche(profil: enCours, nombreOuvertes: 1), "1 mission près de chez vous — vous pouvez déjà postuler.")
        XCTAssertEqual(AccueilPresentation.accroche(profil: nil, nombreOuvertes: 0),
                       "Vous pouvez déjà postuler — vos documents validés débloquent l'acceptation.")
        XCTAssertEqual(AccueilPresentation.accroche(profil: valide, nombreOuvertes: 2), "2 missions pour vous 🔥")
        XCTAssertEqual(AccueilPresentation.accroche(profil: valide, nombreOuvertes: 0), "On trouve votre prochaine mission ? 🔥")
    }

    func testLibellesStatutRemunerationCompteurs() {
        XCTAssertEqual(AccueilPresentation.statut("ASSIGNEE"), "Assignée")
        XCTAssertEqual(AccueilPresentation.statut("EN_COURS"), "Active")
        XCTAssertEqual(AccueilPresentation.statut("AUTRE"), "AUTRE")
        XCTAssertEqual(AccueilPresentation.remuneration(25), "25,00\u{00A0}€/h")
        XCTAssertNil(AccueilPresentation.remuneration(nil))
        XCTAssertEqual(AccueilPresentation.texteNotifications(1), "1 notification non lue")
        XCTAssertEqual(AccueilPresentation.texteNotifications(2), "2 notifications non lues")
        XCTAssertNil(AccueilPresentation.texteNotifications(0))
        XCTAssertEqual(AccueilPresentation.texteOubliPointage(1), "1 mission semble attendre un pointage de départ. Vérifiez vos présences.")
        XCTAssertEqual(AccueilPresentation.texteOubliPointage(3), "3 missions semblent attendre un pointage de départ. Vérifiez vos présences.")
        XCTAssertNil(AccueilPresentation.texteOubliPointage(0))
        XCTAssertEqual(AccueilPresentation.nombrePourToiAffiches, 2, "le web affiche les deux premières (slice(0, 2))")
    }
}
