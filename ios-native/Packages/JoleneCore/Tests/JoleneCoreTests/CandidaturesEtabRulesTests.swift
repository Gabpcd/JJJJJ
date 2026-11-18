import XCTest
@testable import JoleneCore

/// Candidatures de l'espace établissement (lot 5, T6) : décodage tolérant de la lecture habilitée (aucune note, aucun
/// statut d'internat, aucun régime du profil), aiguillage D25/D10 avant tout appel, partition et ordre du web, issue
/// relue, mise en forme du récapitulatif, et monde démo (lecture, refus de droit, D25, planning modifié, acceptation et
/// refus partagés avec les missions).
final class CandidaturesEtabRulesTests: XCTestCase {
    // MARK: - Décodage

    private let lectureJSON = """
    {"mission":{"id":"m-1","intitule":"Nuit","etablissement_id":"e-1","etablissement_nom":"Clinique","statut":"OUVERTE",
      "mode_attribution":"CANDIDATURE","nb_creneaux":1,"profession_requise":"IDE","specialite_medicale_requise":null,
      "accepte_internes":true},
     "creneaux":[{"id":"c-1","mission_id":"m-1","debut":"2026-11-03T08:00:00.123456+00:00","fin":"2026-11-03T16:00:00+00:00",
       "est_pause":false,"type_creneau":"PREVISIONNEL"},{"id":"c-2","debut":null}],
     "candidatures":[{"id":"k-1","soignant_id":"s-1","message":"Bonjour","statut":"EN_ATTENTE","cree_le":"2026-11-01T08:00:00+00:00",
       "soignant":{"id":"s-1","prenom":"Camille","nom":"D.","nom_anonymise":true,"profession":"IDE","specialite_medicale":null,
         "type_exercice":"LIBERAL","est_etudiant":false,"internat":{"statut":"X"},"score_fiabilite":74.4,
         "total_missions_terminees":5,"note_moyenne":4.8,"nb_evaluations":3,"etudiant_details":"S3",
         "tous_documents_valides":true}},
       {"soignant_id":"s-2","statut":"EN_ATTENTE"}]}
    """

    func testDecodageTolerantSansNoteNiInternatNiRegime() throws {
        let lecture = try JSONDecoder().decode(LectureCandidaturesHabilitee.self, from: Data(lectureJSON.utf8))
        XCTAssertEqual(lecture.missionId, "m-1")
        XCTAssertEqual(lecture.intitule, "Nuit")
        XCTAssertEqual(lecture.etablissementId, "e-1")
        XCTAssertEqual(lecture.statutMission, "OUVERTE")
        XCTAssertEqual(lecture.nbCreneaux, 1)
        XCTAssertEqual(lecture.professionRequise, "IDE")
        XCTAssertEqual(lecture.creneaux.map(\.id), ["c-1"], "un créneau illisible est écarté (le planning devient inexact)")
        XCTAssertEqual(lecture.creneaux.first?.debut, "2026-11-03T08:00:00.123456+00:00", "chaîne servie conservée (D26)")
        XCTAssertEqual(lecture.candidatures.map(\.id), ["k-1"], "une candidature sans identifiant est écartée")
        let candidat = try XCTUnwrap(lecture.candidatures.first?.soignant)
        XCTAssertEqual(candidat, CandidatHabilite(id: "s-1", prenom: "Camille", nom: "D.", nomAnonymise: true, profession: "IDE",
                                                  estEtudiant: false, scoreFiabilite: 74, totalMissionsTerminees: 5,
                                                  tousDocumentsValides: true))
        XCTAssertEqual(lecture.candidatures.first?.message, "Bonjour")
        for jamais in ["note_moyenne", "nb_evaluations", "internat", "type_exercice", "etudiant_details", "specialite_medicale"] {
            XCTAssertFalse(CandidatHabilite.clesDecodees.contains(jamais), "\(jamais) jamais décodé (D8, D10)")
        }
        XCTAssertFalse(LectureCandidaturesHabilitee.clesMissionDecodees.contains("accepte_internes"))
    }

    func testMissionSansIdentifiantRefusee() {
        let json = #"{"mission":{"id":" "},"creneaux":[],"candidatures":[]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(LectureCandidaturesHabilitee.self, from: Data(json.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(LectureCandidaturesHabilitee.self, from: Data(#"{"creneaux":[]}"#.utf8)))
    }

    // MARK: - Aiguillage (D10, D25)

    func testPerimetreDAcceptationNative() {
        let etudianteAS = CandidatHabilite(id: "s", prenom: nil, nom: nil, profession: "AS", estEtudiant: true)
        let etudiantIDE = CandidatHabilite(id: "s", prenom: nil, nom: nil, profession: "IDE", estEtudiant: true)
        XCTAssertNil(CandidaturesEtabRules.motifRenvoiWeb(typeContratRecherche: "SALARIE", professionRequise: "IDE", candidat: nil))
        XCTAssertEqual(CandidaturesEtabRules.motifRenvoiWeb(typeContratRecherche: "TOUS", professionRequise: "IDE", candidat: nil),
                       .contratNonSalarie)
        XCTAssertEqual(CandidaturesEtabRules.motifRenvoiWeb(typeContratRecherche: "LIBERAL", professionRequise: "IDE", candidat: nil),
                       .contratNonSalarie)
        XCTAssertEqual(CandidaturesEtabRules.motifRenvoiWeb(typeContratRecherche: nil, professionRequise: "IDE", candidat: nil),
                       .contratNonSalarie, "contrat inconnu : jamais supposé salarié")
        XCTAssertEqual(CandidaturesEtabRules.motifRenvoiWeb(typeContratRecherche: "SALARIE", professionRequise: "MEDECIN", candidat: nil),
                       .medecin)
        XCTAssertEqual(CandidaturesEtabRules.motifRenvoiWeb(typeContratRecherche: "SALARIE", professionRequise: "AS", candidat: etudianteAS),
                       .cadreEtudiant)
        XCTAssertNil(CandidaturesEtabRules.motifRenvoiWeb(typeContratRecherche: "SALARIE", professionRequise: "IDE", candidat: etudiantIDE),
                     "seul l'étudiant aide-soignant est aiguillé ; le serveur décide du reste (correction 19)")
    }

    func testPartitionOrdreHistoriqueEtIssueRelue() {
        let a = CandidatureHabilitee(id: "a", soignantId: nil, statut: "EN_ATTENTE", creeLe: "1")
        let b = CandidatureHabilitee(id: "b", soignantId: nil, statut: "EN_ATTENTE", creeLe: "2", message: "Envoyé par super-like")
        let c = CandidatureHabilitee(id: "c", soignantId: nil, statut: "ACCEPTEE", creeLe: "3")
        let d = CandidatureHabilitee(id: "d", soignantId: nil, statut: "ANNULEE", creeLe: "4")
        XCTAssertEqual(CandidaturesEtabRules.enAttente([a, b, c, d]).map(\.id), ["b", "a"], "priorité historique d'abord (web l.365-368)")
        XCTAssertEqual(CandidaturesEtabRules.traitees([a, b, c, d]).map(\.id), ["c", "d"])

        let assignee = LectureCandidaturesHabilitee(missionId: "m", statutMission: "ASSIGNEE", nbCreneaux: 1, creneaux: [], candidatures: [c])
        let ouverte = LectureCandidaturesHabilitee(missionId: "m", statutMission: "OUVERTE", nbCreneaux: 1, creneaux: [], candidatures: [c])
        XCTAssertTrue(CandidaturesEtabRules.decisionConfirmee(.acceptee, candidatureId: "c", lecture: assignee))
        XCTAssertFalse(CandidaturesEtabRules.decisionConfirmee(.acceptee, candidatureId: "c", lecture: ouverte),
                       "ACCEPTEE sans mission ASSIGNEE : non confirmé")
        XCTAssertFalse(CandidaturesEtabRules.decisionConfirmee(.refusee, candidatureId: "c", lecture: assignee))
        XCTAssertEqual(CandidaturesEtabRules.motifRefus, "Refusé par l'établissement", "p_motif du web (l.320)")
    }

    // MARK: - Présentation

    func testBadgesStatutsEtRecapitulatif() {
        let fiable = CandidatHabilite(id: "s", prenom: "Alex", nom: "F.", profession: "AS", estEtudiant: false,
                                      scoreFiabilite: 74, totalMissionsTerminees: 6, tousDocumentsValides: true)
        XCTAssertEqual(CandidaturesEtabPresentation.badges(fiable).map(\.texte),
                       ["Aide-Soignant(e) (AS)", "✅ Documents validés", "⭐ 74/100"])
        let nouveau = CandidatHabilite(id: "s", prenom: "Lou", nom: "E.", profession: "AS", estEtudiant: true,
                                       scoreFiabilite: 90, totalMissionsTerminees: 2, tousDocumentsValides: false)
        XCTAssertEqual(CandidaturesEtabPresentation.badges(nouveau).map(\.texte),
                       ["Aide-Soignant(e) (AS)", "🎓 Étudiant", "📄 Documents en vérification", "Pas encore d'évaluation"],
                       "score affiché à partir de trois missions terminées (web l.458)")
        XCTAssertEqual(CandidaturesEtabPresentation.nom(fiable), "Alex F.")
        XCTAssertEqual(CandidaturesEtabPresentation.nom(nil), "Soignant")
        XCTAssertEqual(CandidaturesEtabPresentation.statut(.init(id: "x", soignantId: nil, statut: "ACCEPTEE", creeLe: nil)).texte, "✅ Acceptée")
        XCTAssertEqual(CandidaturesEtabPresentation.statut(.init(id: "x", soignantId: nil, statut: "ANNULEE", creeLe: nil)).texte, "❌ Refusée",
                       "parité du web : tout autre statut qu'ACCEPTEE")

        let jour = MissionSlot(id: "c-1", debut: "2026-11-05T06:00:00.000Z", fin: "2026-11-05T18:00:00.000Z", estPause: false, typeCreneau: "PREVISIONNEL")
        let nuit = MissionSlot(id: "c-2", debut: "2026-11-05T19:00:00Z", fin: "2026-11-06T02:30:00Z", estPause: false, typeCreneau: "PREVISIONNEL")
        XCTAssertEqual(CandidaturesEtabPresentation.resumeRecap([jour]), "1 créneau · 12 h au total")
        XCTAssertEqual(CandidaturesEtabPresentation.resumeRecap([jour, nuit]), "2 créneaux · 19,5 h au total")
        XCTAssertEqual(CandidaturesEtabPresentation.ligneRecap(jour), "jeudi 5 novembre 2026 · 07:00 → 19:00")
        XCTAssertEqual(CandidaturesEtabPresentation.ligneRecap(nuit), "jeudi 5 novembre 2026 · 20:00 → ven. 6 nov. · 03:30")
        XCTAssertEqual(CandidaturesEtabPresentation.heures(8 + 1.0 / 3), "8,33")
        XCTAssertEqual(CandidaturesEtabPresentation.heures(7.5), "7,5")
        XCTAssertEqual(CandidaturesEtabPresentation.heures(12), "12")
        XCTAssertEqual(CandidaturesEtabPresentation.urlCgv.absoluteString, "https://jolene.app/cgv#art8")
        XCTAssertEqual(CandidaturesEtabPresentation.urlAcceptationWeb(missionId: "m 1").absoluteString,
                       "https://jolene.app/etablissement/missions/m%201")
    }

    // MARK: - Monde démo

    private func contexte(_ permissions: Set<PermissionEtab> = Set(PermissionEtab.allCases)) -> EtablissementReadContext {
        EtablissementReadContext(userId: DemoEtablissementWorld.userId, etablissementId: "demo-etab-1", roleEtab: .proprietaire,
                                 permissions: PermissionsEtab(accordees: permissions), epoch: 1)
    }

    private func charge(_ lecture: LectureCandidaturesHabilitee) throws -> [CreneauConfirme] {
        try XCTUnwrap(PlanningExactEtab.creneauxConfirmes(PlanningExactEtab.verifier(lecture.creneaux, nbCreneauxAttendus: lecture.nbCreneaux)))
    }

    func testDemoLectureM1EtudianteEtM3Incomplet() async throws {
        let gateway = DemoEtabCandidaturesGateway(etat: DemoEtabEtatCandidatures())
        let m1 = try await gateway.lecture(missionId: "demo-etab-m01", context: contexte())
        XCTAssertEqual(m1.candidatures.map(\.id), ["demo-etab-m01-cand-1", "demo-etab-m01-cand-2", "demo-etab-m01-cand-3"])
        XCTAssertEqual(m1.candidatures.map { $0.soignant?.nom }, ["D.", "F.", "E."], "nom à l'initiale, comme le serveur")
        XCTAssertTrue(m1.candidatures.allSatisfy { $0.soignant?.nomAnonymise == true })
        XCTAssertEqual(m1.candidatures.last?.soignant?.estEtudiant, true)
        XCTAssertTrue(PlanningExactEtab.verifier(m1.creneaux, nbCreneauxAttendus: m1.nbCreneaux).exact)
        let m3 = try await gateway.lecture(missionId: "demo-etab-m03", context: contexte())
        XCTAssertEqual(PlanningExactEtab.verifier(m3.creneaux, nbCreneauxAttendus: m3.nbCreneaux).erreur,
                       "Planning incomplet : 2 créneaux attendus, 1 chargé.")
        do {
            _ = try await gateway.lecture(missionId: "demo-etab-m01", context: contexte([.lecture, .pointage]))
            XCTFail("lecture refusée sans la permission candidatures")
        } catch let refus as RefusAccesEtablissement {
            XCTAssertEqual(refus.message, "Mission indisponible ou accès refusé")
        }
        var autre = contexte()
        autre.userId = "intrus"
        do {
            _ = try await gateway.lecture(missionId: "demo-etab-m01", context: autre)
            XCTFail("compte fictif seulement")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
    }

    func testDemoAcceptationPartageeAvecLesMissionsEtRefus() async throws {
        let etat = DemoEtabEtatCandidatures()
        let gateway = DemoEtabCandidaturesGateway(etat: etat)
        let missions = DemoEtabMissionsGateway(etat: etat)
        let m1 = try await gateway.lecture(missionId: "demo-etab-m01", context: contexte())
        let refus = try await gateway.refuser(candidatureId: "demo-etab-m01-cand-2", context: contexte())
        XCTAssertEqual(refus, .refusEnregistre)
        let issue = try await gateway.accepter(candidatureId: "demo-etab-m01-cand-1", creneauxConfirmes: try charge(m1), context: contexte())
        XCTAssertEqual(issue, .acceptee(contratId: nil))
        let relue = try await gateway.lecture(missionId: "demo-etab-m01", context: contexte())
        XCTAssertEqual(relue.statutMission, "ASSIGNEE")
        XCTAssertEqual(relue.candidatures.map(\.statut), ["ACCEPTEE", "REFUSEE", "REFUSEE"])
        XCTAssertTrue(CandidaturesEtabRules.decisionConfirmee(.acceptee, candidatureId: "demo-etab-m01-cand-1", lecture: relue))
        let detail = try await missions.mission(id: "demo-etab-m01", context: contexte())
        XCTAssertEqual(detail?.mission.statut, "ASSIGNEE", "une seule source : la mission acceptée est relue assignée")
        XCTAssertEqual(detail?.soignantAssigneId, "demo-soignant")
        XCTAssertNil(detail?.candidaturesEnAttente, "mission sortie de l'état OUVERTE : plus de pastille")
        do {
            _ = try await gateway.refuser(candidatureId: "demo-etab-m01-cand-2", context: contexte())
            XCTFail("déjà traitée")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.message, "Cette candidature a déjà été traitée.")
        }
    }

    func testDemoD25PlanningModifieEtChargeDivergente() async throws {
        let gateway = DemoEtabCandidaturesGateway(etat: DemoEtabEtatCandidatures(planningModifie: true))
        let modifie = TraitementCandidatureOutcome.planningAReconfirmer(
            code: "PLANNING_MODIFIE_RECONFIRMER",
            message: "Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires.")
        let tous = try await gateway.accepter(candidatureId: "demo-etab-m09-cand-1", creneauxConfirmes: [], context: contexte())
        XCTAssertEqual(tous, .renvoiWeb(motif: .contratNonSalarie))
        let medecin = try await gateway.accepter(candidatureId: "demo-etab-m10-cand-1", creneauxConfirmes: [], context: contexte())
        XCTAssertEqual(medecin, .renvoiWeb(motif: .medecin))
        let etudiante = try await gateway.accepter(candidatureId: "demo-etab-m01-cand-3", creneauxConfirmes: [], context: contexte())
        XCTAssertEqual(etudiante, .renvoiWeb(motif: .cadreEtudiant))
        let m1 = try await gateway.lecture(missionId: "demo-etab-m01", context: contexte())
        let premiere = try await gateway.accepter(candidatureId: "demo-etab-m01-cand-1", creneauxConfirmes: try charge(m1), context: contexte())
        XCTAssertEqual(premiere, modifie, "-JOLENE_DEMO_PLANNING_MODIFIE : première acceptation à reconfirmer")
        let faux = [CreneauConfirme(debut: "2026-11-05T06:00:00.000Z", fin: "2026-11-05T17:00:00.000Z")]
        let divergente = try await gateway.accepter(candidatureId: "demo-etab-m01-cand-1", creneauxConfirmes: faux, context: contexte())
        XCTAssertEqual(divergente, modifie, "charge différente du planning")
        let seconde = try await gateway.accepter(candidatureId: "demo-etab-m01-cand-1", creneauxConfirmes: try charge(m1), context: contexte())
        XCTAssertEqual(seconde, .acceptee(contratId: nil), "seconde confirmation du même planning")
    }

    func testLancementDemoPlanningModifie() {
        guard case let .etablissement(configuration) = DemoEspaceLancement.espace(arguments: [
            "-JOLENE_DEMO_ESPACE", "etablissement", "-JOLENE_DEMO_PLANNING_MODIFIE", "1",
        ]) else { return XCTFail("espace établissement attendu") }
        XCTAssertTrue(configuration.planningModifie)
        guard case let .etablissement(defaut) = DemoEspaceLancement.espace(arguments: ["-JOLENE_DEMO_ESPACE", "etablissement"]) else {
            return XCTFail("espace établissement attendu")
        }
        XCTAssertFalse(defaut.planningModifie)
    }
}
