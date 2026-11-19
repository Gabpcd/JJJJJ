import XCTest
@testable import JoleneCore

/// Modèle des candidatures d'une mission (lot 5, T6) : double relecture avant l'envoi (empreinte divergente → alerte du
/// web, aucun envoi), écho exact des chaînes relues, succès seulement après relecture (`ACCEPTEE` + `ASSIGNEE`, ou
/// `REFUSEE`), issue inconnue relue jamais renvoyée, refus serveur verbatim (`[CODE DU TRAVAIL]` compris), renvois web
/// avant tout appel (D10, D25), refus de droit relu une fois, pas de double envoi. Session établissement réelle du monde
/// démo (`DemoWorld.gateways(espace:)`, espace ouvert), ports des candidatures et des missions scriptés.
@MainActor
final class CandidaturesEtabModelTests: XCTestCase {
    private struct PanneTest: Error {}

    /// Port scripté : lectures et traitements consomment chacun leur file ; chaque appel s'inscrit au journal.
    private final class Script: EtabCandidaturesPort, @unchecked Sendable {
        enum Lecture { case lue(LectureCandidaturesHabilitee), echec(Error) }
        enum Traitement { case issue(TraitementCandidatureOutcome), echec(Error) }
        private let lock = NSLock()
        private var lectures: [Lecture]
        private var traitements: [Traitement]
        private var journal: [String] = []
        private var charges: [[CreneauConfirmePayload]] = []

        init(lectures: [Lecture], traitements: [Traitement] = []) {
            self.lectures = lectures; self.traitements = traitements
        }

        var appels: [String] { lock.withLock { journal } }
        var chargesEnvoyees: [[CreneauConfirmePayload]] { lock.withLock { charges } }

        private func lectureSuivante() -> Lecture {
            lock.withLock {
                journal.append("lecture")
                return lectures.isEmpty ? .echec(PanneTest()) : lectures.removeFirst()
            }
        }

        private func traitementSuivant(_ appel: String, charge: [CreneauConfirmePayload]? = nil) -> Traitement {
            lock.withLock {
                journal.append(appel)
                if let charge { charges.append(charge) }
                return traitements.isEmpty ? .echec(PanneTest()) : traitements.removeFirst()
            }
        }

        func lecture(missionId: String, context: EtablissementReadContext) async throws -> LectureCandidaturesHabilitee {
            switch lectureSuivante() {
            case let .lue(lue): return lue
            case let .echec(erreur): throw erreur
            }
        }

        func accepter(candidatureId: String, creneauxConfirmes: [CreneauConfirmePayload],
                      context: EtablissementReadContext) async throws -> TraitementCandidatureOutcome {
            switch traitementSuivant("accepter \(candidatureId)", charge: creneauxConfirmes) {
            case let .issue(issue): return issue
            case let .echec(erreur): throw erreur
            }
        }

        func refuser(candidatureId: String, context: EtablissementReadContext) async throws -> TraitementCandidatureOutcome {
            switch traitementSuivant("refuser \(candidatureId)") {
            case let .issue(issue): return issue
            case let .echec(erreur): throw erreur
            }
        }
    }

    /// Mission lue par T5 : seul `type_contrat_recherche` sert (D25).
    private struct Missions: EtabMissionsPort {
        var typeContrat: String? = "SALARIE"
        var introuvable = false

        func missions(context: EtablissementReadContext, statut: String?, page: Int) async throws -> EtabMissionsPage { throw PanneTest() }
        func mission(id: String, context: EtablissementReadContext) async throws -> EtabMissionDetail? {
            guard !introuvable else { return nil }
            return EtabMissionDetail(mission: EtabMissionResume(id: id, intitule: "Mission", statut: "OUVERTE",
                                                                typeContratRecherche: typeContrat, etablissementId: "demo-etab-1"),
                                     creneaux: [], soignantAssigneId: nil)
        }
        func soignant(id: String, context: EtablissementReadContext) async throws -> SoignantPourEtab? { nil }
    }

    private final class Compteur: @unchecked Sendable {
        private let lock = NSLock()
        private var valeur = 0
        var nombre: Int { lock.withLock { valeur } }
        func incrementer() { lock.withLock { valeur += 1 } }
    }

    private func modele(_ script: Script, missions: Missions = Missions(),
                        relectures: Compteur = Compteur()) async throws -> CandidaturesEtabModel {
        var gateways = DemoWorld.gateways(espace: .etablissement(.init()))
        gateways.etablissement.candidatures = script
        gateways.etablissement.missions = missions
        let controller = SessionController(gateways: gateways, espaceEtablissement: .ouvert)
        _ = await controller.start()
        let etat = await controller.signIn(email: DemoEspace.emailEtablissement, password: "demo")
        guard case let .readyEtablissement(snapshot) = etat else {
            XCTFail("espace établissement démo attendu, obtenu \(etat)")
            throw PanneTest()
        }
        return CandidaturesEtabModel(missionId: "m-1", controller: controller, snapshot: snapshot,
                                     relirePerimetre: { relectures.incrementer() })
    }

    // MARK: - Données

    private let debutMicro = "2026-11-03T08:00:00.123456+00:00"

    private func creneau(fin: String = "2026-11-03T16:00:00+00:00") -> MissionSlot {
        MissionSlot(id: "c-1", missionId: "m-1", debut: debutMicro, fin: fin, estPause: false, typeCreneau: "PREVISIONNEL")
    }

    private func candidat(etudiant: Bool = false, profession: String = "IDE") -> CandidatHabilite {
        CandidatHabilite(id: "s-1", prenom: "Camille", nom: "D.", nomAnonymise: true, profession: profession, estEtudiant: etudiant)
    }

    private func lecture(statut: String = "EN_ATTENTE", mission: String = "OUVERTE", fin: String = "2026-11-03T16:00:00+00:00",
                         nbCreneaux: Int = 1, creneaux: [MissionSlot]? = nil, profession: String = "IDE",
                         etudiant: Bool = false) -> LectureCandidaturesHabilitee {
        LectureCandidaturesHabilitee(
            missionId: "m-1", statutMission: mission, nbCreneaux: nbCreneaux, creneaux: creneaux ?? [creneau(fin: fin)],
            candidatures: [CandidatureHabilitee(id: "k-1", soignantId: "s-1", statut: statut, creeLe: "2026-11-01T08:00:00Z",
                                                soignant: candidat(etudiant: etudiant, profession: profession == "AS" ? "AS" : "IDE"))],
            intitule: "Mission", etablissementId: "demo-etab-1", modeAttribution: "CANDIDATURE", professionRequise: profession)
    }

    // MARK: - Lecture

    func testChargementLectureEtContratRecherche() async throws {
        let script = Script(lectures: [.lue(lecture())])
        let model = try await modele(script)
        XCTAssertEqual(model.etat, .chargement)
        await model.charger()
        XCTAssertEqual(model.etat, .chargee)
        XCTAssertEqual(model.typeContratRecherche, "SALARIE")
        XCTAssertTrue(model.verification.exact)
        XCTAssertEqual(model.enAttente.map(\.id), ["k-1"])
        XCTAssertTrue(model.peutAccepter(model.enAttente[0]))
        XCTAssertEqual(script.appels, ["lecture"])
    }

    func testMissionIllisibleEtRefusDeDroitRelitLesPermissionsUneFois() async throws {
        let introuvable = try await modele(Script(lectures: [.lue(lecture())]), missions: Missions(introuvable: true))
        await introuvable.charger()
        XCTAssertEqual(introuvable.etat, .introuvable)

        let relectures = Compteur()
        let refus = try await modele(Script(lectures: [.echec(RefusAccesEtablissement(message: "Mission indisponible ou accès refusé"))]),
                                     relectures: relectures)
        await refus.charger()
        XCTAssertEqual(refus.etat, .accesRefuse("Mission indisponible ou accès refusé"), "jamais « session expirée »")
        XCTAssertEqual(relectures.nombre, 1, "permissions relues une fois par refus (D12)")
    }

    // MARK: - Acceptation

    func testDoubleRelectureEchoExactEtSuccesSeulementApresRelecture() async throws {
        let script = Script(lectures: [.lue(lecture()), .lue(lecture()), .lue(lecture()), .lue(lecture(statut: "ACCEPTEE", mission: "ASSIGNEE"))],
                            traitements: [.issue(.acceptee(contratId: "ct-1"))])
        let model = try await modele(script)
        await model.charger()
        await model.ouvrirAcceptation(candidatureId: "k-1")
        XCTAssertEqual(model.recap?.creneaux.map(\.debut), [debutMicro], "récapitulatif sur les créneaux relus")
        XCTAssertNil(model.annonce)
        await model.confirmerAcceptation()
        XCTAssertEqual(script.appels, ["lecture", "lecture", "lecture", "accepter k-1", "lecture"])
        XCTAssertEqual(script.chargesEnvoyees, [[CreneauConfirme(debut: debutMicro, fin: "2026-11-03T16:00:00+00:00")]],
                       "écho exact des chaînes relues, microsecondes et décalage conservés (D26)")
        XCTAssertEqual(model.annonce, .succes("Candidature acceptée ! Le soignant est assigné."))
        XCTAssertNil(model.recap)
        XCTAssertNil(model.enCours)
        XCTAssertEqual(model.traitees.map(\.statut), ["ACCEPTEE"])
    }

    func testEmpreinteDivergenteRemplaceLeRecapitulatifSansEnvoi() async throws {
        let modifiee = lecture(fin: "2026-11-03T17:00:00+00:00")
        let script = Script(lectures: [.lue(lecture()), .lue(lecture()), .lue(modifiee)])
        let model = try await modele(script)
        await model.charger()
        await model.ouvrirAcceptation(candidatureId: "k-1")
        await model.confirmerAcceptation()
        XCTAssertEqual(script.appels, ["lecture", "lecture", "lecture"], "aucun envoi d'un récapitulatif obsolète")
        XCTAssertEqual(model.recap?.creneaux.first?.fin, "2026-11-03T17:00:00+00:00", "récapitulatif remplacé")
        XCTAssertEqual(model.recap?.alerte,
                       "Le planning a changé depuis l’ouverture. Vérifiez les nouveaux horaires puis confirmez de nouveau.")
    }

    func testRelectureQuiNeConfirmePasNAnnonceJamaisLeSucces() async throws {
        let script = Script(lectures: [.lue(lecture()), .lue(lecture()), .lue(lecture()), .lue(lecture())],
                            traitements: [.issue(.acceptee(contratId: nil))])
        let model = try await modele(script)
        await model.charger()
        await model.ouvrirAcceptation(candidatureId: "k-1")
        await model.confirmerAcceptation()
        XCTAssertNotEqual(model.annonce, .succes(CandidaturesEtabPresentation.succesAcceptation))
        XCTAssertEqual(model.recap?.alerte, CandidaturesEtabPresentation.nonConfirmee)
    }

    func testIssueInconnueRelueJamaisRenvoyee() async throws {
        let script = Script(lectures: [.lue(lecture()), .lue(lecture()), .lue(lecture()), .lue(lecture(statut: "ACCEPTEE", mission: "ASSIGNEE"))],
                            traitements: [.echec(JoleneError(.network, SessionController.timeoutMessage))])
        let model = try await modele(script)
        await model.charger()
        await model.ouvrirAcceptation(candidatureId: "k-1")
        await model.confirmerAcceptation()
        XCTAssertEqual(script.appels.filter { $0.hasPrefix("accepter") }.count, 1, "un délai ne prouve rien : relecture, aucun renvoi")
        XCTAssertEqual(model.annonce, .succes(CandidaturesEtabPresentation.succesAcceptation), "acceptation confirmée par la relecture")
    }

    func testPlanningAReconfirmerRelitEtAttendLaReconfirmation() async throws {
        let message = "Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires."
        let script = Script(lectures: [.lue(lecture()), .lue(lecture()), .lue(lecture()), .lue(lecture())],
                            traitements: [.issue(.planningAReconfirmer(code: "PLANNING_MODIFIE_RECONFIRMER", message: message))])
        let model = try await modele(script)
        await model.charger()
        await model.ouvrirAcceptation(candidatureId: "k-1")
        await model.confirmerAcceptation()
        XCTAssertEqual(script.appels, ["lecture", "lecture", "lecture", "accepter k-1", "lecture"])
        XCTAssertEqual(model.recap?.alerte, message, "message serveur verbatim, récapitulatif relu")
        XCTAssertNil(model.annonce)
    }

    func testRefusServeurVerbatimCodeDuTravailEtPaiement() async throws {
        let codeDuTravail = "[CODE DU TRAVAIL] Semaine du 30/11/2026 : 40.0h Jolene + 10.0h ailleurs = 50.0h total (max 48h)"
        let script = Script(lectures: [.lue(lecture()), .lue(lecture()), .lue(lecture()), .lue(lecture())],
                            traitements: [.issue(.refusee(code: CandidatureOutcome.codeRefusCodeDuTravail, message: codeDuTravail,
                                                          documentsRequisPour: nil))])
        let model = try await modele(script)
        await model.charger()
        await model.ouvrirAcceptation(candidatureId: "k-1")
        await model.confirmerAcceptation()
        XCTAssertEqual(model.recap?.alerte, codeDuTravail, "refus du Code du travail affiché tel quel (HARD STOP n°4)")

        let paiement = "Cette mission ne peut pas être attribuée : le mandat SEPA de l'établissement n'est pas encore posé (IBAN à ajouter dans Paramètres → Facturation)."
        let script2 = Script(lectures: [.lue(lecture()), .lue(lecture()), .lue(lecture())],
                             traitements: [.issue(.paiementNonConfigure(message: paiement))])
        let model2 = try await modele(script2)
        await model2.charger()
        await model2.ouvrirAcceptation(candidatureId: "k-1")
        await model2.confirmerAcceptation()
        XCTAssertEqual(model2.annonce, .paiement(paiement))
        XCTAssertNil(model2.recap)
    }

    func testRenvoisWebAvantToutAppel() async throws {
        let tous = Script(lectures: [.lue(lecture())])
        let modelTous = try await modele(tous, missions: Missions(typeContrat: "TOUS"))
        await modelTous.charger()
        XCTAssertFalse(modelTous.peutAccepter(modelTous.enAttente[0]))
        await modelTous.ouvrirAcceptation(candidatureId: "k-1")
        XCTAssertEqual(modelTous.annonce, .renvoiWeb(.contratNonSalarie, message: nil))
        XCTAssertEqual(tous.appels, ["lecture"], "aucune relecture ni envoi")

        let medecin = Script(lectures: [.lue(lecture(profession: "MEDECIN"))])
        let modelMedecin = try await modele(medecin)
        await modelMedecin.charger()
        await modelMedecin.ouvrirAcceptation(candidatureId: "k-1")
        XCTAssertEqual(modelMedecin.annonce, .renvoiWeb(.medecin, message: nil))

        let etudiante = Script(lectures: [.lue(lecture(profession: "AS", etudiant: true))])
        let modelEtudiante = try await modele(etudiante)
        await modelEtudiante.charger()
        await modelEtudiante.ouvrirAcceptation(candidatureId: "k-1")
        XCTAssertEqual(modelEtudiante.annonce, .renvoiWeb(.cadreEtudiant, message: nil))
        XCTAssertEqual(etudiante.appels, ["lecture"], "CADRE_ETUDIANT_AS_CONFIRME n'est jamais envoyé")
        XCTAssertTrue(modelEtudiante.peutRefuser(modelEtudiante.enAttente[0]), "le refus reste natif")
    }

    func testPlanningIncompletBloqueLAcceptation() async throws {
        let script = Script(lectures: [.lue(lecture(nbCreneaux: 2))])
        let model = try await modele(script)
        await model.charger()
        XCTAssertEqual(model.verification.erreur, "Planning incomplet : 2 créneaux attendus, 1 chargé.")
        XCTAssertFalse(model.peutAccepter(model.enAttente[0]))
        await model.ouvrirAcceptation(candidatureId: "k-1")
        XCTAssertEqual(model.annonce, .erreur("Planning incomplet : 2 créneaux attendus, 1 chargé."))
        XCTAssertNil(model.recap)
        XCTAssertEqual(script.appels, ["lecture"])
    }

    // MARK: - Refus

    func testRefusReluEtPasDeDoubleEnvoi() async throws {
        let script = Script(lectures: [.lue(lecture()), .lue(lecture(statut: "REFUSEE"))],
                            traitements: [.issue(.refusEnregistre)])
        let model = try await modele(script)
        await model.charger()
        // Deux touchers : le second trouve `enCours` déjà posé (avant tout `await`) et n'envoie rien.
        let premier = Task { await model.refuser(candidatureId: "k-1") }
        await model.refuser(candidatureId: "k-1")
        await premier.value
        XCTAssertEqual(script.appels.filter { $0.hasPrefix("refuser") }, ["refuser k-1"], "un seul envoi")
        XCTAssertEqual(model.annonce, .succes("Candidature refusée."))
        XCTAssertEqual(model.traitees.map(\.statut), ["REFUSEE"])
        XCTAssertNil(model.enCours)
    }

    func testRefusDejaTraiteVerbatim() async throws {
        let script = Script(lectures: [.lue(lecture()), .lue(lecture(statut: "ACCEPTEE", mission: "ASSIGNEE"))],
                            traitements: [.echec(JoleneError(.unknown, "Cette candidature a déjà été traitée."))])
        let model = try await modele(script)
        await model.charger()
        await model.refuser(candidatureId: "k-1")
        XCTAssertEqual(model.annonce, .erreur("Cette candidature a déjà été traitée."), "refus serveur verbatim après relecture")
    }
}
