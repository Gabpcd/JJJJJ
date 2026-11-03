import XCTest
@testable import JoleneCore

/// Ajout au calendrier (lot 1, T5, décision 18 ; `CalendarWriterTests` du blueprint) : un événement par
/// créneau PREVISIONNEL d'un planning complet (comme l'ICS du web), alarmes -1440 / -60 min, URL de la
/// mission ; double d'`EKEventStore` (`AppareilFactice`) : accord refusé → message sans écriture,
/// accord → N événements, journal de dédoublonnage par compte (`RECETTE_DEVICE_LOT1.md` §4).
@MainActor
final class AjoutCalendrierTests: XCTestCase {
    private struct EchecEcriture: Error {}

    /// Double d'`EKEventStore` : état d'accord, réponse à la demande, écritures et échecs scriptés.
    private final class AppareilFactice: CalendrierAppareil {
        var etat: AccesCalendrier
        var reponse: Bool
        /// Rangs (0, 1, …) des écritures qui échouent.
        var echecs: Set<Int>
        private(set) var demandes = 0
        private(set) var tentatives = 0
        private(set) var ecrits: [EvenementCalendrier] = []
        /// Retient la demande d'accès jusqu'à son ouverture (deux taps rapprochés).
        var retenue: Gate?

        init(etat: AccesCalendrier = .accorde, reponse: Bool = true, echecs: Set<Int> = []) {
            self.etat = etat; self.reponse = reponse; self.echecs = echecs
        }

        func acces() -> AccesCalendrier { etat }

        func demanderAcces() async -> Bool {
            demandes += 1
            if let retenue { await retenue.wait() }
            if reponse { etat = .accorde }
            return reponse
        }

        func enregistrer(_ evenement: EvenementCalendrier) throws {
            defer { tentatives += 1 }
            if echecs.contains(tentatives) { throw EchecEcriture() }
            ecrits.append(evenement)
        }
    }

    private let etab = EtablissementSummary(id: "e-1", nom: "Clinique des Tests", adresseVille: "Lyon")

    private func record(_ id: String = "m-1", debut: String = "2026-11-05T07:00:00.000Z", fin: String = "2026-11-06T15:00:00.000Z",
                        nb: Int? = 2) -> MissionRecord {
        MissionRecord(id: id, intitule: "Mission de nuit", description: nil, service: nil, professionRequise: "IDE",
                      specialiteMedicaleRequise: nil, accepteNonSpecialises: nil, debutLe: debut, finLe: fin, dureeHeures: 16,
                      nbCreneaux: nb, tauxHoraireBase: 27, tauxRistPlafonne: nil, ristPlafondApplique: false, totalBrut: nil,
                      netAPayer: nil, estUrgente: false, niveauUrgence: nil, statut: "ASSIGNEE", etablissementId: "e-1",
                      typeContratRecherche: "SALARIE", boosteeLe: nil, modeRemuneration: nil, retrocessionPct: nil)
    }

    private func creneau(_ id: String?, _ debut: String, _ fin: String?, mission: String = "m-1") -> MissionSlot {
        MissionSlot(id: id, missionId: mission, debut: debut, fin: fin, estPause: false, typeCreneau: "PREVISIONNEL")
    }

    private var deuxCreneaux: Mission {
        MissionBusiness.enrich(record: record(), context: DemoWorld.context, etablissement: etab, slots: [
            creneau("s-2", "2026-11-06T07:00:00.000Z", "2026-11-06T15:00:00.000Z"),
            creneau("s-1", "2026-11-05T07:00:00.000Z", "2026-11-05T15:00:00.000Z"),
        ])
    }

    // MARK: - Événements

    func testUnEvenementParCreneauPlanifieAvecRappelsEtLien() throws {
        let evenements = CalendrierMission.evenements(pour: deuxCreneaux)
        XCTAssertEqual(evenements.count, 2, "un événement par créneau, jamais une plage globale")
        let premier = try XCTUnwrap(evenements.first)
        XCTAssertEqual(premier.titre, "Mission de nuit")
        XCTAssertEqual(DateHeureParis.isoUTC(premier.debut), "2026-11-05T07:00:00.000Z", "créneaux triés par début")
        XCTAssertEqual(DateHeureParis.isoUTC(premier.fin), "2026-11-05T15:00:00.000Z")
        XCTAssertEqual(premier.lieu, "Lyon")
        XCTAssertEqual(premier.notes, "Mission Jolene — Clinique des Tests")
        XCTAssertEqual(premier.url?.absoluteString, "https://jolene.app/soignant/missions/m-1")
        XCTAssertEqual(premier.alarmesMinutes, [-1440, -60])
        XCTAssertEqual(evenements.map(\.cle), ["m-1|s-1|2026-11-05T07:00:00.000Z|2026-11-05T15:00:00.000Z",
                                               "m-1|s-2|2026-11-06T07:00:00.000Z|2026-11-06T15:00:00.000Z"])
    }

    func testRepliPonctuelEtPlanningIncompletSansEvenement() {
        let ponctuelle = MissionBusiness.enrich(record: record(fin: "2026-11-05T15:00:00.000Z", nb: nil), context: DemoWorld.context,
                                                etablissement: nil, slots: [])
        let repli = CalendrierMission.evenements(pour: ponctuelle)
        XCTAssertEqual(repli.count, 1, "mission ponctuelle de 24 h au plus sans créneau détaillé : sa plage, comme l'ICS")
        XCTAssertEqual(repli.first?.notes, "Mission Jolene", "sans établissement relu")
        XCTAssertNil(repli.first?.lieu)

        let incomplete = MissionBusiness.enrich(record: record(nb: 3), context: DemoWorld.context, etablissement: etab, slots: [
            creneau("s-1", "2026-11-05T07:00:00.000Z", "2026-11-05T15:00:00.000Z"),
        ])
        XCTAssertEqual(CalendrierMission.evenements(pour: incomplete), [], "planning non confirmé : aucun horaire exporté")
        let sansFin = MissionBusiness.enrich(record: record(nb: 1), context: DemoWorld.context, etablissement: etab, slots: [
            creneau(nil, "2026-11-05T07:00:00.000Z", nil),
        ])
        XCTAssertEqual(CalendrierMission.evenements(pour: sansFin), [])
    }

    func testUrlEncodeLIdentifiantEtCleDeRang() {
        XCTAssertEqual(CalendrierMission.url(missionId: "a b/c")?.absoluteString, "https://jolene.app/soignant/missions/a%20b%2Fc",
                       "comme `encodeURIComponent`")
        XCTAssertNil(CalendrierMission.url(missionId: ""))
        // Jeu ASCII explicite (revue B8 de T5) : `CharacterSet.alphanumerics` contient des lettres et
        // chiffres Unicode, que `encodeURIComponent` encode en UTF-8.
        XCTAssertEqual(CalendrierMission.encodeURIComponent("été-١"), "%C3%A9t%C3%A9-%D9%A1")
        XCTAssertEqual(CalendrierMission.encodeURIComponent("Az09-_.!~*'()"), "Az09-_.!~*'()", "non réservés de `encodeURIComponent`")
        XCTAssertEqual(CalendrierMission.encodeURIComponent("a+b&c=d?#%"), "a%2Bb%26c%3Dd%3F%23%25")
        XCTAssertEqual(CalendrierMission.url(missionId: "été")?.absoluteString, "https://jolene.app/soignant/missions/%C3%A9t%C3%A9")
        let sansId = creneau(nil, "2026-11-05T07:00:00.000Z", "2026-11-05T15:00:00.000Z")
        XCTAssertEqual(CalendrierMission.cle(missionId: "m-1", creneau: sansId, rang: 0),
                       "m-1|rang-1|2026-11-05T07:00:00.000Z|2026-11-05T15:00:00.000Z")
    }

    // MARK: - Accord et écriture

    func testAccordAccordeEcritNEvenementsEtLesNoteAuJournal() async {
        let appareil = AppareilFactice()
        let journal = JournalCalendrierMemoire()
        let issue = await AjoutCalendrier(appareil: appareil, journal: journal).ajouter(deuxCreneaux)
        XCTAssertEqual(issue, IssueAjoutCalendrier(message: "2 créneaux ajoutés à votre calendrier.", succes: true, ajoutes: 2))
        XCTAssertEqual(appareil.ecrits.count, 2)
        XCTAssertEqual(appareil.demandes, 0, "accord déjà donné : aucune demande")
        XCTAssertEqual(journal.entrees.count, 2)
    }

    func testAccordRefuseMessageSansEcritureNiNouvelleDemande() async {
        let appareil = AppareilFactice(etat: .refuse)
        let issue = await AjoutCalendrier(appareil: appareil, journal: JournalCalendrierMemoire()).ajouter(deuxCreneaux)
        XCTAssertEqual(issue.message, IssueAjoutCalendrier.accesRefuse)
        XCTAssertFalse(issue.succes)
        XCTAssertEqual(appareil.demandes, 0, "un refus n'est jamais redemandé de force")
        XCTAssertEqual(appareil.tentatives, 0)
    }

    func testPremiereDemandeAccepteeOuRefusee() async {
        let accepte = AppareilFactice(etat: .nonDetermine, reponse: true)
        let ok = await AjoutCalendrier(appareil: accepte, journal: JournalCalendrierMemoire()).ajouter(deuxCreneaux)
        XCTAssertEqual(accepte.demandes, 1)
        XCTAssertEqual(ok.ajoutes, 2)

        let refuse = AppareilFactice(etat: .nonDetermine, reponse: false)
        let non = await AjoutCalendrier(appareil: refuse, journal: JournalCalendrierMemoire()).ajouter(deuxCreneaux)
        XCTAssertEqual(refuse.demandes, 1)
        XCTAssertEqual(non.message, IssueAjoutCalendrier.accesRefuse)
        XCTAssertEqual(refuse.tentatives, 0)
    }

    func testSecondAjoutSansDoublonEtCreneauModifieAjoute() async {
        let appareil = AppareilFactice()
        let ajout = AjoutCalendrier(appareil: appareil, journal: JournalCalendrierMemoire())
        _ = await ajout.ajouter(deuxCreneaux)
        let second = await ajout.ajouter(deuxCreneaux)
        XCTAssertEqual(second, IssueAjoutCalendrier(message: IssueAjoutCalendrier.dejaAjoutes, succes: true, dejaPresents: 2))
        // Écriture seule : l'app ne relit pas le calendrier, elle ne sait que ce qu'elle a ajouté
        // (un événement supprimé par l'utilisateur n'est jamais réajouté, RECETTE_DEVICE_LOT1 §4).
        XCTAssertEqual(IssueAjoutCalendrier.dejaAjoutes,
                       "Les créneaux de cette mission ont déjà été ajoutés à votre calendrier depuis Jolene sur cet appareil.")
        XCTAssertEqual(appareil.ecrits.count, 2, "mêmes horaires : aucun nouvel événement")

        // L'établissement a déplacé le second créneau : un événement pour ce créneau, l'autre déjà ajouté.
        let deplacee = MissionBusiness.enrich(record: record(), context: DemoWorld.context, etablissement: etab, slots: [
            creneau("s-1", "2026-11-05T07:00:00.000Z", "2026-11-05T15:00:00.000Z"),
            creneau("s-2", "2026-11-06T08:00:00.000Z", "2026-11-06T15:00:00.000Z"),
        ])
        let troisieme = await ajout.ajouter(deplacee)
        XCTAssertEqual(troisieme.message, "1 créneau ajouté à votre calendrier (1 déjà ajouté auparavant).",
                       "jamais « déjà présent » : le calendrier n'est pas relu")
        XCTAssertEqual(appareil.ecrits.count, 3)
    }

    func testEchecsPartielEtTotalSeCompletentAuTapSuivant() async {
        let appareil = AppareilFactice(echecs: [1])
        let journal = JournalCalendrierMemoire()
        let ajout = AjoutCalendrier(appareil: appareil, journal: journal)
        let partiel = await ajout.ajouter(deuxCreneaux)
        XCTAssertEqual(partiel.message, "1 créneau ajouté à votre calendrier, 1 n'a pas pu l'être. Réessayez pour compléter.")
        XCTAssertFalse(partiel.succes)
        XCTAssertEqual(journal.entrees.count, 1, "seul le créneau écrit est noté")
        let complete = await ajout.ajouter(deuxCreneaux)
        XCTAssertEqual(complete.message, "1 créneau ajouté à votre calendrier (1 déjà ajouté auparavant).")
        XCTAssertEqual(appareil.ecrits.count, 2, "aucun doublon après l'échec partiel")

        let enPanne = AppareilFactice(echecs: [0, 1])
        let total = await AjoutCalendrier(appareil: enPanne, journal: JournalCalendrierMemoire()).ajouter(deuxCreneaux)
        XCTAssertEqual(total, IssueAjoutCalendrier(message: IssueAjoutCalendrier.echecTotal, succes: false, echecs: 2))
    }

    func testPlanningNonConfirmeSansDemandeDAcces() async {
        let appareil = AppareilFactice(etat: .nonDetermine)
        let incomplete = MissionBusiness.enrich(record: record(nb: 3), context: DemoWorld.context, etablissement: etab, slots: [])
        let issue = await AjoutCalendrier(appareil: appareil, journal: JournalCalendrierMemoire()).ajouter(incomplete)
        XCTAssertEqual(issue.message, IssueAjoutCalendrier.planningNonConfirme)
        XCTAssertFalse(issue.succes)
        XCTAssertEqual(appareil.demandes, 0)
    }

    func testDeuxTapsRapprochesPartagentLaMemeOperation() async {
        let barriere = Gate()
        let appareil = AppareilFactice(etat: .nonDetermine)
        appareil.retenue = barriere
        let ajout = AjoutCalendrier(appareil: appareil, journal: JournalCalendrierMemoire())
        let mission = deuxCreneaux
        let premier = Task { await ajout.ajouter(mission) }
        let second = Task { await ajout.ajouter(mission) }
        // Le premier tap est suspendu dans la demande d'accès ; le second a le temps d'arriver.
        while appareil.demandes == 0 { await Task.yield() }
        for _ in 0..<10 { await Task.yield() }
        await barriere.open()
        let issues = [await premier.value, await second.value]
        XCTAssertEqual(issues.map(\.ajoutes), [2, 2], "les deux taps rendent l'issue de la même opération")
        XCTAssertEqual(appareil.demandes, 1)
        XCTAssertEqual(appareil.ecrits.count, 2, "aucun doublon")
    }

    // MARK: - Journal par compte

    func testJournalPersistantParCompteEtPurgeALaSuppression() {
        let nom = "jolene.tests.calendrier.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: nom)!
        defer { defaults.removePersistentDomain(forName: nom) }
        let userId = "0b4d2b8e-4a9f-4b1c-9e0a-7f3c1d2e5a66"
        XCTAssertEqual(JournalCalendrierPreferences.cle(userId: userId), "jolene.calendrier.journal.\(userId)")
        let journal = JournalCalendrierPreferences(userId: userId, defaults: defaults)
        journal.noter("m-1|s-1|a|b")
        journal.noter("m-1|s-1|a|b")
        XCTAssertTrue(JournalCalendrierPreferences(userId: userId, defaults: defaults).contient("m-1|s-1|a|b"), "relu au lancement suivant")
        XCTAssertEqual(defaults.stringArray(forKey: JournalCalendrierPreferences.cle(userId: userId)), ["m-1|s-1|a|b"], "sans doublon")
        XCTAssertFalse(JournalCalendrierPreferences(userId: "autre-compte", defaults: defaults).contient("m-1|s-1|a|b"),
                       "un autre compte a son propre journal")
        let retirees = CompteSuppression.purgerPreferencesLocales(userId: userId, defaults: defaults)
        XCTAssertEqual(retirees, ["jolene.calendrier.journal.\(userId)"], "convention de clé de T8 : l'identifiant est un segment entier")
        XCTAssertFalse(JournalCalendrierPreferences(userId: userId, defaults: defaults).contient("m-1|s-1|a|b"))
    }

    // MARK: - Démonstration

    func testCalendrierDemoEnMemoireEtRefusForce() async {
        let demo = CalendrierAppareilDemo()
        let issue = await AjoutCalendrier(appareil: demo, journal: JournalCalendrierMemoire()).ajouter(deuxCreneaux)
        XCTAssertEqual(issue.ajoutes, 2)
        XCTAssertEqual(demo.evenements.count, 2, "gardés en mémoire, aucune écriture système")
        let refus = CalendrierAppareilDemo(refuse: true)
        let refusee = await AjoutCalendrier(appareil: refus, journal: JournalCalendrierMemoire()).ajouter(deuxCreneaux)
        XCTAssertEqual(refusee.message, IssueAjoutCalendrier.accesRefuse)
        XCTAssertEqual(refus.evenements, [])
        // Surcharge DEBUG lue par `AppContainer` (liste centralisée des surcharges), jamais ailleurs.
        XCTAssertEqual(CalendrierAppareilDemo.variableRefus, "JOLENE_FORCE_CALENDRIER_REFUS")
    }
}
