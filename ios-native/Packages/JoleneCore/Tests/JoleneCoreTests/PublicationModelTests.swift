import XCTest
@testable import JoleneCore

/// Modèle de la publication d'une mission (lot 5, T9 ; `LOT5_PLAN.md` §3 T9) : période → jours → créneaux (état
/// dérivé), re-dérivation qui conserve les jours restés dans la période et leurs exceptions, jour au repos jamais
/// envoyé, chevauchement bloqué localement, « appliquer le premier créneau à tous », un seul envoi sur double toucher,
/// « publiée » seulement sur l'issue relue du port, refus serveur mot pour mot, issue inconnue jamais un succès.
/// Session établissement réelle du monde démo (`DemoWorld.gateways(espace:)`, espace ouvert), port de publication scripté.
@MainActor
final class PublicationModelTests: XCTestCase {
    private struct PanneTest: Error {}

    /// Port scripté : chaque appel s'inscrit au journal avec son brouillon ; `retenir` suspend l'appel jusqu'à `liberer`.
    private final class Script: EtabPublicationPort, @unchecked Sendable {
        enum Reponse { case issue(PublicationOutcome), echec(Error) }
        private let lock = NSLock()
        private var reponses: [Reponse]
        private var recus: [PublicationMission] = []
        private var enAttente: [CheckedContinuation<Void, Never>] = []
        private var libere = false
        private let retenir: Bool
        private var minimumServeur: Double?

        /// `minimumServeur` : plancher rendu par le port (`nil` : lecture impossible, `PlancherTauxIndisponible`).
        init(_ reponses: [Reponse] = [], retenir: Bool = false, minimumServeur: Double? = PublicationRules.tauxMinimum) {
            self.reponses = reponses; self.retenir = retenir; self.minimumServeur = minimumServeur
        }

        func definirMinimum(_ valeur: Double?) { lock.withLock { minimumServeur = valeur } }

        func tauxMinimumSalarie(context: EtablissementReadContext) async throws -> Double {
            guard let valeur = lock.withLock({ minimumServeur }) else { throw PlancherTauxIndisponible("paramètre absent") }
            return valeur
        }

        var brouillons: [PublicationMission] { lock.withLock { recus } }

        /// Libère les appels suspendus, et ceux qui ne le sont pas encore (aucune course avec l'inscription de l'appel).
        func liberer() {
            let suspendus = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                libere = true
                defer { enAttente = [] }
                return enAttente
            }
            suspendus.forEach { $0.resume() }
        }

        func publier(_ brouillon: PublicationMission, context: EtablissementReadContext) async throws -> PublicationOutcome {
            lock.withLock { recus.append(brouillon) }
            if retenir {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let dejaLibere = lock.withLock { () -> Bool in
                        if libere { return true }
                        enAttente.append(continuation)
                        return false
                    }
                    if dejaLibere { continuation.resume() }
                }
            }
            let reponse = lock.withLock { reponses.isEmpty ? Reponse.echec(PanneTest()) : reponses.removeFirst() }
            switch reponse {
            case let .issue(issue): return issue
            case let .echec(erreur): throw erreur
            }
        }
    }

    /// `charger` : plancher lu avant de rendre le modèle (comme le `.task` de l'écran).
    private func modele(_ script: Script = Script(), charger: Bool = true) async throws -> PublicationModel {
        var gateways = DemoWorld.gateways(espace: .etablissement(.init()))
        gateways.etablissement.publication = script
        let controller = SessionController(gateways: gateways, espaceEtablissement: .ouvert)
        _ = await controller.start()
        let etat = await controller.signIn(email: DemoEspace.emailEtablissement, password: "demo")
        guard case let .readyEtablissement(snapshot) = etat else {
            XCTFail("espace établissement démo attendu, obtenu \(etat)")
            throw PanneTest()
        }
        var compteur = 0
        let model = PublicationModel(controller: controller, snapshot: snapshot, nouvelIdClient: {
            compteur += 1
            return "c\(compteur)"
        })
        if charger { await model.chargerTauxMinimum() }
        return model
    }

    /// Champs obligatoires valides ; le planning reste à saisir.
    private func remplirChamps(_ model: PublicationModel) {
        model.definirIntitule("IDE de nuit")
        model.definirProfession("IDE")
        model.definirTaux("30")
    }

    /// Mission d'un jour travaillé, prête pour le récapitulatif.
    private func remplirUnJour(_ model: PublicationModel, date: String = "2026-11-25") {
        remplirChamps(model)
        model.definirPeriode(debut: date, fin: date)
        model.basculerJour(date)
    }

    // MARK: - Plancher du taux horaire salarié (migration 20261125120000)

    /// Plancher lu au serveur (paramètre relevé à 12,50) : seul plancher de la validation et de l'avis ; avant la
    /// lecture, rien n'est publiable (fermé) et aucun avis n'est affiché.
    func testPlancherLuAuServeur() async throws {
        let model = try await modele(Script(minimumServeur: 12.5), charger: false)
        XCTAssertEqual(model.plancher, .enCours)
        XCTAssertNil(model.tauxMinimum)
        remplirChamps(model)
        XCTAssertEqual(model.champsInvalides, [.taux], "plancher non lu : fermé")
        XCTAssertNil(model.avisTauxSousLeMinimum)
        await model.chargerTauxMinimum()
        XCTAssertEqual(model.plancher, .lu(12.5))
        XCTAssertEqual(model.champsInvalides, [])
        model.definirTaux("12,40")
        XCTAssertEqual(model.champsInvalides, [.taux])
        XCTAssertEqual(model.avisTauxSousLeMinimum, "Le taux horaire doit être d'au moins 12,50 €/h.")
        model.definirTaux("12,50")
        XCTAssertEqual(model.champsInvalides, [])
        XCTAssertNil(model.avisTauxSousLeMinimum)
        XCTAssertNil(model.annonce)
    }

    /// Lecture impossible ou valeur illisible : fermé et nommé (`.indisponible`, message générique existant), jamais une
    /// constante substituée ; une relecture réussie rouvre le formulaire et retire ce message.
    func testPlancherIndisponibleFermeEtNomme() async throws {
        for serveur in [nil, 0, -1, Double.nan, Double.infinity] as [Double?] {
            let script = Script(minimumServeur: serveur)
            let model = try await modele(script)
            guard case .indisponible = model.plancher else {
                XCTFail("\(String(describing: serveur)) : plancher \(model.plancher)"); continue
            }
            XCTAssertNil(model.tauxMinimum)
            remplirUnJour(model)
            XCTAssertEqual(model.champsInvalides, [.taux], "\(String(describing: serveur))")
            XCTAssertFalse(model.peutOuvrirRecap)
            XCTAssertNil(model.avisTauxSousLeMinimum)
            XCTAssertEqual(model.annonce, .erreur(PublicationPresentation.messageErreurGenerique))
            model.ouvrirRecapitulatif()
            XCTAssertNil(model.recap, "aucun récapitulatif sans plancher lu")

            script.definirMinimum(12.31)
            await model.chargerTauxMinimum()
            XCTAssertEqual(model.plancher, .lu(12.31))
            XCTAssertNil(model.annonce, "message du plancher retiré après relecture")
            XCTAssertTrue(model.peutOuvrirRecap)
        }
    }

    /// Un plancher déjà lu n'est jamais remplacé par une erreur de relecture.
    func testPlancherLuConserveSurEchecUlterieur() async throws {
        let script = Script(minimumServeur: 12.5)
        let model = try await modele(script)
        XCTAssertEqual(model.plancher, .lu(12.5))
        script.definirMinimum(nil)
        await model.chargerTauxMinimum()
        XCTAssertEqual(model.plancher, .lu(12.5))
        XCTAssertNil(model.annonce)
    }

    /// Monde démo : la valeur de fixture du paramètre, après le contrôle de contexte.
    func testPlancherDuMondeDemo() async throws {
        let gateways = DemoWorld.gateways(espace: .etablissement(.init()))
        let controller = SessionController(gateways: gateways, espaceEtablissement: .ouvert)
        _ = await controller.start()
        let etat = await controller.signIn(email: DemoEspace.emailEtablissement, password: "demo")
        guard case let .readyEtablissement(snapshot) = etat else {
            XCTFail("espace établissement démo attendu, obtenu \(etat)"); return
        }
        let model = PublicationModel(controller: controller, snapshot: snapshot)
        await model.chargerTauxMinimum()
        XCTAssertEqual(model.plancher, .lu(DemoEtabPublicationGateway.tauxMinimumFixture))
        XCTAssertEqual(DemoEtabPublicationGateway.tauxMinimumFixture, 12.31)
    }

    /// Refus du verrou serveur (app restée à un plancher plus bas que le paramètre) : message serveur mot pour mot.
    func testRefusDuVerrouServeurMotPourMot() async throws {
        let message = "Le taux horaire doit être d'au moins 12,50 €/h."
        let script = Script([.issue(.refusee(code: "REFUS_METIER", message: message))])
        let model = try await modele(script)
        remplirUnJour(model)
        model.definirTaux("12.40")
        model.ouvrirRecapitulatif()
        XCTAssertNotNil(model.recap, "12,40 passe le plancher local de l'app (12,31)")
        await model.confirmerPublication()
        XCTAssertEqual(model.annonce, .erreur(message))
        XCTAssertEqual(model.etat, .saisie)
        XCTAssertEqual(script.brouillons.count, 1)
    }

    // MARK: - Période → jours → créneaux

    func testRienNEstPrerempli() async throws {
        let model = try await modele()
        XCTAssertEqual(model.saisie.dateDebut, "")
        XCTAssertEqual(model.saisie.dateFin, "")
        XCTAssertEqual(model.saisie.jours, [], "aucun jour sans période")
        XCTAssertEqual(model.creneaux, [])
        XCTAssertEqual(model.saisie.profession, "")
        XCTAssertEqual(model.champsInvalides, [.intitule, .profession, .taux])
        XCTAssertFalse(model.peutOuvrirRecap)
        XCTAssertEqual(model.erreursPlanning.map(\.type), [.plageInvalide])
        XCTAssertEqual(model.erreursPlanningAffichees, [], "période jamais saisie : aucune erreur affichée (web l.438)")
    }

    func testPeriodeDUnJour() async throws {
        let model = try await modele()
        model.definirPeriode(debut: "2026-11-25", fin: "2026-11-25")
        XCTAssertEqual(model.saisie.jours.map(\.date), ["2026-11-25"])
        XCTAssertEqual(model.saisie.jours.map(\.actif), [false], "un jour dérivé arrive au repos, comme le web")
        XCTAssertEqual(model.saisie.jours[0].creneaux.map(\.heureDebut), ["07:00"], "créneau proposé par le web, non envoyé au repos")
        XCTAssertEqual(model.creneaux, [], "jour au repos : aucun créneau dérivé")
        XCTAssertEqual(model.erreursPlanningAffichees.map(\.message), [PlanningDerive.messageAucuneDateTravaillee])

        model.basculerJour("2026-11-25")
        XCTAssertEqual(model.joursTravailles, 1)
        XCTAssertEqual(model.creneaux.map(\.debut), ["2026-11-25T06:00:00.000Z"], "07:00 à Paris en novembre")
        XCTAssertEqual(model.erreursPlanning, [])
    }

    func testPeriodeDeSeptJours() async throws {
        let model = try await modele()
        model.definirDateDebut("2026-11-23")
        XCTAssertEqual(model.saisie.jours, [], "une seule borne : aucune période, aucun jour")
        XCTAssertEqual(model.erreursPlanningAffichees.map(\.message), [PlanningDerive.messagePeriodeInvalide])
        model.definirDateFin("2026-11-29")
        XCTAssertEqual(model.saisie.jours.map(\.date), ["2026-11-23", "2026-11-24", "2026-11-25", "2026-11-26", "2026-11-27",
                                                        "2026-11-28", "2026-11-29"])
        XCTAssertTrue(model.saisie.jours.allSatisfy { !$0.actif })
        for jour in model.saisie.jours.prefix(5) { model.basculerJour(jour.date) }
        XCTAssertEqual(model.joursTravailles, 5)
        XCTAssertEqual(model.creneaux.count, 5, "les créneaux sont dérivés des jours travaillés")
        XCTAssertEqual(model.creneaux.map(\.date), ["2026-11-23", "2026-11-24", "2026-11-25", "2026-11-26", "2026-11-27"])
    }

    func testReductionDePeriodeConserveLesJoursRestantsEtLeursExceptions() async throws {
        let model = try await modele()
        model.definirPeriode(debut: "2026-11-23", fin: "2026-11-29")
        model.basculerJour("2026-11-25")
        model.basculerJour("2026-11-26")
        // Exception saisie le 25 : garde de nuit, plus un second créneau.
        var nuit = try XCTUnwrap(model.saisie.jours.first { $0.date == "2026-11-25" }?.creneaux.first)
        nuit.heureDebut = "21:00"
        nuit.heureFin = "06:00"
        nuit.finJourSuivant = true
        model.modifierCreneau(date: "2026-11-25", creneau: nuit)
        let exception = try XCTUnwrap(model.saisie.jours.first { $0.date == "2026-11-25" })

        // Réduction : le 25 et le 26 restent dans la période, tout le reste sort.
        model.definirPeriode(debut: "2026-11-25", fin: "2026-11-26")
        XCTAssertEqual(model.saisie.jours.map(\.date), ["2026-11-25", "2026-11-26"])
        XCTAssertEqual(model.saisie.jours.first, exception, "jour resté dans la période : état, créneaux et exception conservés")
        XCTAssertEqual(model.saisie.jours.map(\.actif), [true, true])
        XCTAssertEqual(model.creneaux.map(\.debut), ["2026-11-25T20:00:00.000Z", "2026-11-26T06:00:00.000Z"])

        // Extension : les jours ajoutés arrivent au repos, l'exception survit encore.
        model.definirDateFin("2026-11-28")
        XCTAssertEqual(model.saisie.jours.map(\.actif), [true, true, false, false])
        XCTAssertEqual(model.saisie.jours.first, exception)

        // Le 25 sort de la période puis y revient : l'exception a disparu avec le jour (jamais un état caché).
        model.definirDateDebut("2026-11-26")
        XCTAssertEqual(model.saisie.jours.map(\.date), ["2026-11-26", "2026-11-27", "2026-11-28"])
        model.definirDateDebut("2026-11-25")
        let revenu = try XCTUnwrap(model.saisie.jours.first)
        XCTAssertEqual(revenu.date, "2026-11-25")
        XCTAssertFalse(revenu.actif)
        XCTAssertEqual(revenu.creneaux.map(\.heureDebut), ["07:00"])

        // Période inversée : aucun jour, comme le web.
        model.definirDateFin("2026-11-20")
        XCTAssertEqual(model.saisie.jours, [])
        XCTAssertEqual(model.erreursPlanningAffichees.map(\.type), [.plageInvalide])
    }

    func testDecalerLesBornesReDerive() async throws {
        let model = try await modele()
        model.definirPeriode(debut: "2026-11-30", fin: "2026-11-30")
        model.basculerJour("2026-11-30")
        model.decalerDateFin(jours: 2)
        XCTAssertEqual(model.saisie.dateFin, "2026-12-02", "jour civil suivant, changement de mois compris")
        XCTAssertEqual(model.saisie.jours.map(\.date), ["2026-11-30", "2026-12-01", "2026-12-02"])
        XCTAssertEqual(model.saisie.jours.map(\.actif), [true, false, false], "le jour déjà travaillé le reste")
        model.decalerDateDebut(jours: 1)
        XCTAssertEqual(model.saisie.jours.map(\.date), ["2026-12-01", "2026-12-02"])
        model.decalerDateFin(jours: -1)
        XCTAssertEqual(model.saisie.jours.map(\.date), ["2026-12-01"])
    }

    func testChoisirUneDateDepuisLHorlogeDeLaSession() async throws {
        let model = try await modele()
        await model.choisirDateFin()
        XCTAssertEqual(model.saisie.dateFin, "2026-11-02", "jour civil de Paris de l'horloge démo")
        XCTAssertEqual(model.saisie.jours, [], "une seule borne : aucun jour")
        await model.choisirDateDebut()
        XCTAssertEqual(model.saisie.dateDebut, "2026-11-02")
        XCTAssertEqual(model.saisie.jours.map(\.date), ["2026-11-02"])
        model.definirDateDebut("2026-11-10")
        await model.choisirDateDebut()
        XCTAssertEqual(model.saisie.dateDebut, "2026-11-10", "une date déjà choisie n'est jamais remplacée")

        let autre = try await modele()
        autre.definirDateDebut("2026-11-12")
        await autre.choisirDateFin()
        XCTAssertEqual(autre.saisie.dateFin, "2026-11-12", "dernière date : la première si elle existe")
    }

    func testJourAuReposNonEnvoye() async throws {
        let script = Script([.issue(.publiee(missionId: "m-1"))])
        let model = try await modele(script)
        remplirChamps(model)
        model.definirPeriode(debut: "2026-11-25", fin: "2026-11-27")
        for jour in model.saisie.jours { model.basculerJour(jour.date) }
        XCTAssertEqual(model.creneaux.count, 3)
        model.basculerJour("2026-11-26")
        XCTAssertEqual(model.saisie.jours.map(\.actif), [true, false, true])
        XCTAssertEqual(model.saisie.jours[1].creneaux.count, 1, "le jour remis au repos garde son créneau saisi")
        XCTAssertEqual(model.creneaux.map(\.date), ["2026-11-25", "2026-11-27"])

        model.ouvrirRecapitulatif()
        let recap = try XCTUnwrap(model.recap)
        XCTAssertEqual(recap.creneaux.count, 2)
        XCTAssertEqual(recap.totalHeures, 24)
        await model.confirmerPublication()
        XCTAssertEqual(script.brouillons.map(\.creneaux), [[
            CreneauConfirme(debut: "2026-11-25T06:00:00Z", fin: "2026-11-25T18:00:00Z"),
            CreneauConfirme(debut: "2026-11-27T06:00:00Z", fin: "2026-11-27T18:00:00Z"),
        ]], "jamais le créneau du jour au repos")
    }

    func testChevauchementBloqueLocalement() async throws {
        let script = Script([.issue(.publiee(missionId: "m-1"))])
        let model = try await modele(script)
        remplirUnJour(model)
        model.ajouterCreneau("2026-11-25")
        XCTAssertEqual(model.saisie.jours[0].creneaux.count, 2, "deux créneaux 07:00 → 19:00 le même jour")
        XCTAssertEqual(model.erreursPlanning.map(\.type), [.chevauchement])
        XCTAssertEqual(model.creneauxEnErreur.count, 2)
        XCTAssertFalse(model.peutOuvrirRecap)
        model.ouvrirRecapitulatif()
        XCTAssertNil(model.recap)
        await model.confirmerPublication()
        XCTAssertEqual(script.brouillons, [], "aucun envoi d'un planning structurellement invalide")

        // Second créneau décalé : plus de chevauchement.
        var second = model.saisie.jours[0].creneaux[1]
        second.heureDebut = "19:00"
        second.heureFin = "21:00"
        model.modifierCreneau(date: "2026-11-25", creneau: second)
        XCTAssertEqual(model.erreursPlanning, [])
        XCTAssertTrue(model.peutOuvrirRecap)

        // Créneau invalide (fin avant le début sans lendemain) : bloqué aussi, message du web.
        second.heureFin = "18:00"
        model.modifierCreneau(date: "2026-11-25", creneau: second)
        XCTAssertEqual(model.erreursPlanning.map(\.type), [.creneauInvalide])
        XCTAssertFalse(model.peutOuvrirRecap)

        // Créneau retiré : le jour redevient valide ; jour travaillé sans créneau : bloqué.
        model.retirerCreneau(date: "2026-11-25", clientId: second.clientId)
        XCTAssertTrue(model.peutOuvrirRecap)
        model.retirerCreneau(date: "2026-11-25", clientId: model.saisie.jours[0].creneaux[0].clientId)
        XCTAssertEqual(model.erreursPlanning.map(\.type), [.creneauManquant])
    }

    func testAppliquerLePremierCreneauATous() async throws {
        let model = try await modele()
        model.definirPeriode(debut: "2026-11-25", fin: "2026-11-27")
        model.appliquerPremierCreneauATous()
        XCTAssertTrue(model.saisie.jours.allSatisfy { !$0.actif }, "sans jour travaillé, rien ne change")
        for jour in model.saisie.jours { model.basculerJour(jour.date) }
        var premier = model.saisie.jours[0].creneaux[0]
        premier.heureDebut = "08:00"
        premier.heureFin = "16:30"
        model.modifierCreneau(date: "2026-11-25", creneau: premier)
        model.ajouterCreneau("2026-11-26")
        model.basculerJour("2026-11-27")
        model.appliquerPremierCreneauATous()
        XCTAssertEqual(model.saisie.jours[1].creneaux.map { [$0.heureDebut, $0.heureFin] }, [["08:00", "16:30"]],
                       "jour travaillé : remplacé par le premier créneau")
        XCTAssertEqual(model.saisie.jours[2].creneaux.map(\.heureDebut), ["07:00"], "jour au repos : inchangé")
        XCTAssertEqual(Set(model.saisie.jours.flatMap { $0.creneaux.map(\.clientId) }).count, 3, "identifiants locaux distincts")
        // Initialiseur seulement : chaque jour reste modifiable ensuite.
        var copie = model.saisie.jours[1].creneaux[0]
        copie.heureFin = "12:00"
        model.modifierCreneau(date: "2026-11-26", creneau: copie)
        XCTAssertEqual(model.saisie.jours[0].creneaux.map(\.heureFin), ["16:30"])
        XCTAssertEqual(model.saisie.jours[1].creneaux.map(\.heureFin), ["12:00"])
    }

    // MARK: - Champs

    func testProfessionRenvoyeeAuWebJamaisRetenue() async throws {
        let model = try await modele()
        model.definirProfession("MEDECIN")
        XCTAssertEqual(model.saisie.profession, "")
        model.definirProfession("IADE")
        model.definirProfession("MEDECIN")
        XCTAssertEqual(model.saisie.profession, "IADE")
        model.definirNiveauUrgence(7)
        XCTAssertEqual(model.saisie.niveauUrgence, 1, "niveau hors bornes ignoré")
        model.definirIntitule(String(repeating: "a", count: 200))
        XCTAssertEqual(model.saisie.intitule.count, 120)
    }

    // MARK: - Récapitulatif et envoi

    func testRecapitulatifSurUnBrouillonFige() async throws {
        let model = try await modele()
        remplirUnJour(model)
        model.definirService("  Urgences ")
        model.definirDescription("Renfort [SERIE_ID:x]")
        model.definirModeAttribution(.candidature)
        model.definirUrgente(true)
        model.definirNiveauUrgence(2)
        model.definirTaux("32,5")
        XCTAssertTrue(model.peutOuvrirRecap)
        model.ouvrirRecapitulatif()
        let recap = try XCTUnwrap(model.recap)
        XCTAssertEqual(recap.brouillon, PublicationMission(
            intitule: "IDE de nuit", description: "Renfort [SERIE_ID:x]", professionRequise: "IDE", service: "Urgences",
            tauxHoraireBase: 32.5, estUrgente: true,
            creneaux: [CreneauConfirme(debut: "2026-11-25T06:00:00Z", fin: "2026-11-25T18:00:00Z")],
            niveauUrgence: 2, modeAttribution: .candidature))
        XCTAssertEqual(PublicationPayload(recap.brouillon).valeurs["p_description"], .chaine("Renfort"), "balise purgée à l'envoi")
        XCTAssertEqual(recap.totalHeures, 12)

        // Formulaire figé tant que le récapitulatif est ouvert.
        model.definirIntitule("Autre")
        model.basculerJour("2026-11-25")
        model.definirPeriode(debut: "2026-12-01", fin: "2026-12-02")
        XCTAssertEqual(model.saisie.intitule, "IDE de nuit")
        XCTAssertEqual(model.saisie.jours.map(\.date), ["2026-11-25"])
        model.annulerRecapitulatif()
        XCTAssertNil(model.recap)
        model.definirIntitule("Autre")
        XCTAssertEqual(model.saisie.intitule, "Autre")
    }

    func testDoubleToucherUnSeulAppel() async throws {
        let script = Script([.issue(.publiee(missionId: "m-1"))], retenir: true)
        let model = try await modele(script)
        remplirUnJour(model)
        model.ouvrirRecapitulatif()

        let premier = Task { await model.confirmerPublication() }
        while script.brouillons.isEmpty { await Task.yield() }
        XCTAssertTrue(model.enCours)
        await model.confirmerPublication()
        await model.confirmerPublication()
        model.annulerRecapitulatif()
        XCTAssertNotNil(model.recap, "le récapitulatif ne se ferme pas pendant l'envoi")
        XCTAssertEqual(script.brouillons.count, 1, "double toucher : un seul appel")
        XCTAssertEqual(model.etat, .saisie, "aucun succès avant l'issue relue")

        script.liberer()
        await premier.value
        XCTAssertEqual(script.brouillons.count, 1)
        XCTAssertEqual(model.etat, .publiee(missionId: "m-1"))
        XCTAssertNil(model.recap)
        XCTAssertFalse(model.enCours)

        // Publiée : plus aucun envoi ni modification possible sans repartir d'un formulaire vide.
        model.ouvrirRecapitulatif()
        await model.confirmerPublication()
        model.definirIntitule("Autre")
        XCTAssertEqual(script.brouillons.count, 1)
        XCTAssertEqual(model.saisie.intitule, "IDE de nuit")
        model.nouvellePublication()
        XCTAssertEqual(model.etat, .saisie)
        XCTAssertEqual(model.saisie, PublicationSaisie(), "formulaire vide, aucun reste de la mission publiée")
    }

    func testRefusServeurMotPourMotJamaisUnSucces() async throws {
        let refus = "Le planning dépasse 48 h pour la semaine du 23/11/2026."
        let script = Script([.issue(.refusee(code: "PLAFOND_48H_HEBDO", message: refus)), .issue(.publiee(missionId: "m-2"))])
        let model = try await modele(script)
        remplirUnJour(model)
        model.ouvrirRecapitulatif()
        await model.confirmerPublication()
        XCTAssertEqual(model.annonce, .erreur(refus))
        XCTAssertEqual(model.etat, .saisie)
        XCTAssertNil(model.recap, "retour au formulaire pour corriger")
        XCTAssertEqual(model.saisie.intitule, "IDE de nuit", "saisie conservée")

        // Nouvel essai explicite après correction : un second envoi, voulu.
        model.ouvrirRecapitulatif()
        XCTAssertNil(model.annonce)
        await model.confirmerPublication()
        XCTAssertEqual(script.brouillons.count, 2)
        XCTAssertEqual(model.etat, .publiee(missionId: "m-2"))
    }

    func testBlocageDeLEtablissement() async throws {
        let message = "Le contrat de service Jolene doit être signé avant de publier des missions."
        let script = Script([.issue(.blocageEtablissement(code: "CONTRAT_SERVICE_REQUIS", message: message))])
        let model = try await modele(script)
        remplirUnJour(model)
        model.ouvrirRecapitulatif()
        await model.confirmerPublication()
        XCTAssertEqual(model.annonce, .blocage(code: "CONTRAT_SERVICE_REQUIS", message: message))
        XCTAssertEqual(model.etat, .saisie)
        model.effacerAnnonce()
        XCTAssertNil(model.annonce)
    }

    func testIssueNonConfirmeeOuInconnueJamaisUnSuccesNiUnRenvoi() async throws {
        let attendues: [(Script.Reponse, PublicationModel.Annonce)] = [
            (.issue(.nonConfirmee(missionId: "m-3")), .nonConfirmee(detail: nil, missionId: "m-3")),
            (.echec(JoleneError(.network, "Connexion impossible.")), .nonConfirmee(detail: "Connexion impossible.", missionId: nil)),
            (.echec(PanneTest()), .nonConfirmee(detail: PublicationPresentation.messageErreurGenerique, missionId: nil)),
        ]
        for (reponse, annonce) in attendues {
            let script = Script([reponse])
            let model = try await modele(script)
            remplirUnJour(model)
            model.ouvrirRecapitulatif()
            await model.confirmerPublication()
            XCTAssertEqual(model.annonce, annonce, "issue inconnue ou non confirmée : à vérifier, jamais un succès")
            XCTAssertEqual(model.etat, .saisie)
            XCTAssertNil(model.recap)
            XCTAssertEqual(script.brouillons.count, 1, "aucun renvoi automatique")
        }
    }

    /// Revue B8 sécurité de la vague D (m3) : après une publication non confirmée, la mission existe peut-être ; le même
    /// formulaire ne peut plus être republié depuis cet écran (doublon, deux affectations possibles). Seul « Voir mes
    /// missions » (liste relue) mène plus loin ; une modification de la saisie ne lève pas le verrou.
    func testApresUnePublicationNonConfirmeeLeMemeFormulaireNeRepartPas() async throws {
        for reponse: Script.Reponse in [.issue(.nonConfirmee(missionId: "m-3")), .echec(JoleneError(.network, "Connexion impossible."))] {
            let script = Script([reponse, .issue(.publiee(missionId: "m-4"))])
            let model = try await modele(script)
            remplirUnJour(model)
            model.ouvrirRecapitulatif()
            await model.confirmerPublication()
            XCTAssertTrue(model.relectureRequise)
            XCTAssertFalse(model.peutOuvrirRecap, "publication bloquée tant que la liste n'est pas relue")
            model.definirIntitule("Renfort de nuit modifié")
            model.ouvrirRecapitulatif()
            XCTAssertNil(model.recap, "aucun récapitulatif rouvert")
            await model.confirmerPublication()
            XCTAssertEqual(script.brouillons.count, 1, "aucun second envoi")
            if case .nonConfirmee = model.annonce {} else { XCTFail("l'avertissement reste affiché : \(String(describing: model.annonce))") }
        }
    }

    func testRefusDeSessionNeVerrouillePasLaPublication() async throws {
        let script = Script([.echec(JoleneError(.unauthorized, "Session expirée.")), .issue(.publiee(missionId: "m-5"))])
        let model = try await modele(script)
        remplirUnJour(model)
        model.ouvrirRecapitulatif()
        await model.confirmerPublication()
        XCTAssertEqual(model.annonce, .erreur("Session expirée."), "refus de session : rien n'a été publié")
        XCTAssertFalse(model.relectureRequise)
        XCTAssertTrue(model.peutOuvrirRecap)
    }

    func testAnnulationSansAnnonce() async throws {
        let script = Script([.echec(CancellationError())])
        let model = try await modele(script)
        remplirUnJour(model)
        model.ouvrirRecapitulatif()
        await model.confirmerPublication()
        XCTAssertNil(model.annonce, "une annulation n'est jamais une erreur affichée")
        XCTAssertEqual(model.etat, .saisie)
        XCTAssertFalse(model.enCours)
    }
}
