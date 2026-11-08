import Foundation
import XCTest
@testable import JoleneCore

/// Journal générique des reçus durables (décision 23 du lot 2 : T7 du lot 1 absent, T1 livre le journal ;
/// blueprint `LOT2_PLAN.md` §2.2 et §2.6 ; PRINCIPES §4 ; pilote `mobile-native/src/workflows/presence/attemptJournal.ts`).
/// Une clé par (utilisateur, domaine) ; écriture refusée tant qu'un reçu non terminé d'un autre essai existe ;
/// relecture après écriture ; tout échec du magasin et tout reçu illisible donnent `RecuErreur.illisible`, sans
/// réparation (rien n'est réécrit ni effacé).
final class ReceiptJournalTests: XCTestCase {
    private let userId = "0b4d2b8e-4a9f-4b1c-9e0a-7f3c1d2e5a66"
    private let autreUtilisateur = "a7d0c1f2-3b4e-4c5d-8e9f-0a1b2c3d4e5f"
    private let terminal = "TERM_IOS_ABCDEFGHIJKLMNOPQRST"
    private let essai1 = "6f1c2c1e-4c1a-4f55-9a0e-2b7b1d9e8a01"
    private let essai2 = "8d2e3f4a-5b6c-4d7e-8f90-a1b2c3d4e5f6"
    private let t0 = Date(timeIntervalSince1970: 1_793_577_600)

    private func scan(_ attemptId: String, userId: String? = nil, missionId: String = "m-1") throws -> RecuScan {
        try RecuScan.preparer(userId: userId ?? self.userId, epoch: 1, missionId: missionId, terminalId: terminal,
                              typeAttendu: .ouverture, nbScansAvant: 0, preuvesAvant: ["s-1"], gps: .nonDemande,
                              attemptId: attemptId)
    }

    private func document(userId: String? = nil, horodatageMs: Int64 = 1_793_577_600_000) throws -> RecuDocument {
        try RecuDocument.preparer(userId: userId ?? self.userId, epoch: 1, typeDocument: "DIPLOME",
                                  fichier: FichierChoisi(nom: "diplome.pdf", mime: .pdf, tailleOctets: 1_024),
                                  horodatageMs: horodatageMs)
    }

    private func cle(_ domaine: String, _ userId: String? = nil) throws -> CleRecu {
        try XCTUnwrap(CleRecu(domaine: domaine, userId: userId ?? self.userId))
    }

    static func issue(_ operation: () async throws -> Void) async -> RecuErreur? {
        do {
            try await operation()
            return nil
        } catch let error as RecuErreur {
            return error
        } catch {
            return .champInvalide("erreur inattendue : \(error)")
        }
    }

    // MARK: - Clés

    func testUneCleParUtilisateurEtParDomaine() async throws {
        let magasin = MagasinRecusEnMemoire()
        let scans = ReceiptJournal<RecuScan>(store: magasin)
        let documents = ReceiptJournal<RecuDocument>(store: magasin)
        let a = try scan(essai1)
        let b = try scan(essai2, userId: autreUtilisateur)
        let d = try document()
        try await scans.ecrire(a)
        try await scans.ecrire(b)
        try await documents.ecrire(d)

        XCTAssertEqual(magasin.cles(), Set([try cle("scan"), try cle("scan", autreUtilisateur), try cle("document")]))
        let luA = try await scans.lire(userId: userId)
        let luB = try await scans.lire(userId: autreUtilisateur)
        let luD = try await documents.lire(userId: userId)
        let absent = try await documents.lire(userId: autreUtilisateur)
        XCTAssertEqual(luA, a)
        XCTAssertEqual(luB, b)
        XCTAssertEqual(luD, d)
        XCTAssertNil(absent, "aucun reçu : nil, jamais un reçu supposé")
        XCTAssertEqual(try cle("scan").compte, "scan.\(userId)", "compte Keychain : <domaine>.<userId>")
    }

    func testCleHorsContratRefusee() async throws {
        XCTAssertNil(CleRecu(domaine: "scan", userId: "a/b"), "jamais un séparateur de chemin")
        XCTAssertNil(CleRecu(domaine: "scan", userId: ""))
        XCTAssertNil(CleRecu(domaine: "Scan", userId: userId), "domaine en minuscules")
        XCTAssertNil(CleRecu(domaine: "scan.x", userId: userId), "le point sépare domaine et utilisateur")
        XCTAssertNil(CleRecu(domaine: "", userId: userId))
        XCTAssertEqual(RecuScan.domaine, "scan")
        XCTAssertEqual(RecuDocument.domaine, "document")
        let journal = ReceiptJournal<RecuScan>(store: MagasinRecusEnMemoire())
        let lecture = await Self.issue { _ = try await journal.lire(userId: "a/b") }
        XCTAssertEqual(lecture, .illisible)
    }

    // MARK: - Un seul essai en vol par utilisateur et par domaine

    func testEcritureRefuseeTantQuUnAutreEssaiNEstPasTermine() async throws {
        let magasin = MagasinRecusEnMemoire()
        let journal = ReceiptJournal<RecuScan>(store: magasin)
        let premier = try scan(essai1)
        let second = try scan(essai2)
        try await journal.ecrire(premier)

        let pendantPrepared = await Self.issue { try await journal.ecrire(second) }
        XCTAssertEqual(pendantPrepared, .recuEnCours, "« Un autre pointage doit être réconcilié avant de continuer. »")
        let intact = try await journal.lire(userId: userId)
        XCTAssertEqual(intact, premier, "le reçu en vol reste intact")

        let demarre = try premier.demarrer(le: t0)
        try await journal.ecrire(demarre)
        let pendantStarted = await Self.issue { try await journal.ecrire(second) }
        XCTAssertEqual(pendantStarted, .recuEnCours)
        let effacementAutreEssai = await Self.issue { try await journal.effacer(second) }
        XCTAssertEqual(effacementAutreEssai, .recuEnCours, "un essai n'efface jamais le reçu d'un autre")

        try await journal.ecrire(try demarre.refuser(sqlstate: "P0002"))
        try await journal.ecrire(second)
        let remplace = try await journal.lire(userId: userId)
        XCTAssertEqual(remplace, second, "un reçu terminé cède la place au nouvel essai")
    }

    func testLesDomainesSontIndependants() async throws {
        let magasin = MagasinRecusEnMemoire()
        try await ReceiptJournal<RecuScan>(store: magasin).ecrire(try scan(essai1))
        try await ReceiptJournal<RecuDocument>(store: magasin).ecrire(try document())
        XCTAssertEqual(magasin.cles().count, 2, "un scan en vol ne bloque pas un justificatif (et réciproquement)")
    }

    // MARK: - Graphe des phases pour un même essai

    func testMemeEssaiSuitLeGrapheDesPhases() async throws {
        let journal = ReceiptJournal<RecuScan>(store: MagasinRecusEnMemoire())
        let prepare = try scan(essai1)
        let demarre = try prepare.demarrer(le: t0)

        let premierEnStarted = await Self.issue { try await journal.ecrire(demarre) }
        XCTAssertEqual(premierEnStarted, .transitionInterdite(de: "absent", vers: "started"),
                       "le premier enregistrement d'un essai est toujours `prepared` (reçu écrit AVANT l'envoi)")
        try await journal.ecrire(prepare)
        try await journal.ecrire(prepare)
        try await journal.ecrire(demarre)
        let retour = await Self.issue { try await journal.ecrire(prepare) }
        XCTAssertEqual(retour, .transitionInterdite(de: "started", vers: "prepared"), "jamais de retour en arrière")
        let relu = try await journal.lire(userId: userId)
        XCTAssertEqual(relu, demarre)

        let autreMission = try scan(essai1, missionId: "m-2").demarrer(le: t0)
        let immuable = await Self.issue { try await journal.ecrire(autreMission) }
        XCTAssertEqual(immuable, .champInvalide("missionId"), "même essai : champs immuables identiques")
        let horsLigneApresEnvoi = await Self.issue { try await journal.ecrire(try prepare.marquerNonEnvoye()) }
        XCTAssertEqual(horsLigneApresEnvoi, .transitionInterdite(de: "started", vers: "not_sent"),
                       "après `started`, seule la relecture prouve l'absence")
    }

    func testDateDeDemarrageFractionnaireRelueALIdentique() async throws {
        let journal = ReceiptJournal<RecuScan>(store: MagasinRecusEnMemoire())
        let prepare = try scan(essai1)
        try await journal.ecrire(prepare)
        let demarre = try prepare.demarrer(le: Date(timeIntervalSince1970: 1_793_577_600.123_456))
        try await journal.ecrire(demarre)
        try await journal.ecrire(demarre)
        try await journal.ecrire(try demarre.refuser(sqlstate: "23514"))
        let relu = try await journal.lire(userId: userId)
        XCTAssertEqual(relu?.phase, .refused)
    }

    func testJustificatifsDansLeMemeJournalGenerique() async throws {
        let journal = ReceiptJournal<RecuDocument>(store: MagasinRecusEnMemoire())
        let prepare = try document()
        XCTAssertEqual(prepare.attemptId, prepare.s3Cle, "l'essai d'un justificatif est sa clé Storage déterministe")
        try await journal.ecrire(prepare)
        let demarre = try prepare.demarrer()
        try await journal.ecrire(demarre)
        let stocke = try demarre.stocker()
        try await journal.ecrire(stocke)
        let enregistre = try stocke.enregistrer(documentId: "d-1")
        try await journal.ecrire(enregistre)
        let autre = try document(horodatageMs: 1_793_577_700_000)
        let pendantEnvoi = await Self.issue { try await journal.ecrire(autre) }
        XCTAssertEqual(pendantEnvoi, .recuEnCours)
        let retour = await Self.issue { try await journal.ecrire(stocke) }
        XCTAssertEqual(retour, .transitionInterdite(de: "registered", vers: "stored"))
        try await journal.ecrire(try enregistre.demanderVerification())
        try await journal.ecrire(autre)
        try await journal.effacer(autre)
        let vide = try await journal.lire(userId: userId)
        XCTAssertNil(vide)
    }

    // MARK: - Relecture après écriture et effacement

    func testRelectureApresEcriture() async throws {
        let infidele = MagasinDeTest()
        infidele.relitAutreChose = true
        let alteration = await Self.issue { try await ReceiptJournal<RecuScan>(store: infidele).ecrire(try self.scan(self.essai1)) }
        XCTAssertEqual(alteration, .illisible, "octets relus différents de ceux écrits")

        let oublieux = MagasinDeTest()
        oublieux.ignoreEcriture = true
        let perte = await Self.issue { try await ReceiptJournal<RecuScan>(store: oublieux).ecrire(try self.scan(self.essai1)) }
        XCTAssertEqual(perte, .illisible, "écriture acceptée mais rien relu")
    }

    func testEffacementVerifieParRelecture() async throws {
        let magasin = MagasinDeTest()
        let journal = ReceiptJournal<RecuScan>(store: magasin)
        let recu = try scan(essai1)
        try await journal.effacer(recu)
        XCTAssertEqual(magasin.appels.filter { $0.hasPrefix("effacer") }, [], "aucun reçu : rien à effacer")
        try await journal.ecrire(recu)
        try await journal.effacer(recu)
        let vide = try await journal.lire(userId: userId)
        XCTAssertNil(vide)

        try await journal.ecrire(recu)
        magasin.ignoreEffacement = true
        let reste = await Self.issue { try await journal.effacer(recu) }
        XCTAssertEqual(reste, .illisible, "effacement accepté mais reçu encore présent")
    }

    // MARK: - Échecs et reçus illisibles : fail-closed, sans réparation

    func testToutEchecDuMagasinEstIllisible() async throws {
        let recu = try scan(essai1)
        for panne in MagasinDeTest.Panne.allCases {
            let magasin = MagasinDeTest()
            let journal = ReceiptJournal<RecuScan>(store: magasin)
            if panne != .ecriture { try await journal.ecrire(recu) }
            magasin.panne = panne
            let lecture = await Self.issue { _ = try await journal.lire(userId: self.userId) }
            let ecriture = await Self.issue { try await journal.ecrire(recu) }
            let effacement = await Self.issue { try await journal.effacer(recu) }
            switch panne {
            case .lecture:
                XCTAssertEqual([lecture, ecriture, effacement], [.illisible, .illisible, .illisible], "panne \(panne)")
            case .ecriture:
                XCTAssertEqual([lecture, ecriture, effacement], [nil, .illisible, nil], "panne \(panne)")
            case .effacement:
                XCTAssertEqual([lecture, ecriture, effacement], [nil, nil, .illisible], "panne \(panne)")
            }
        }
    }

    func testRecuIllisibleJamaisRepare() async throws {
        let garde = try scan(essai1)
        let illisibles: [Data] = [
            Data("pas du json".utf8),
            Data("{}".utf8),
            try scan(essai1, userId: autreUtilisateur).encoder(),  // reçu d'un autre utilisateur sous notre clé
            try document().encoder(),                               // reçu d'un autre domaine
            Data(repeating: 0x20, count: ReceiptJournal<RecuScan>.tailleMax + 1),
        ]
        for (rang, donnees) in illisibles.enumerated() {
            let magasin = MagasinDeTest()
            magasin.poser(donnees, cle: try cle("scan"))
            let journal = ReceiptJournal<RecuScan>(store: magasin)
            let lecture = await Self.issue { _ = try await journal.lire(userId: self.userId) }
            let ecriture = await Self.issue { try await journal.ecrire(garde) }
            let effacement = await Self.issue { try await journal.effacer(garde) }
            XCTAssertEqual([lecture, ecriture, effacement], [.illisible, .illisible, .illisible], "cas \(rang)")
            XCTAssertEqual(magasin.donnees(try cle("scan")), donnees, "cas \(rang) : ni réécrit ni effacé")
            XCTAssertFalse(magasin.appels.contains { $0.hasPrefix("ecrire") || $0.hasPrefix("effacer") }, "cas \(rang)")
        }
    }

    func testRecuHorsContratJamaisJournalise() async throws {
        var recu = try scan(essai1)
        recu.terminalId = "TERM_WEB_abc"
        let magasin = MagasinDeTest()
        let refus = await Self.issue { try await ReceiptJournal<RecuScan>(store: magasin).ecrire(recu) }
        XCTAssertEqual(refus, .illisible)
        XCTAssertTrue(magasin.appels.allSatisfy { !$0.hasPrefix("ecrire") }, "aucune écriture d'un reçu qui ne se relirait pas")
    }

    // MARK: - Sérialisation

    func testEcrituresConcurrentesSerialiseesEntreInstances() async throws {
        // Entrelacement forcé (revue fraîche de T1, seconde passe) : la lecture du reçu précédent par le premier essai
        // est retenue jusqu'au lancement du second, puis jusqu'à ce que le second lise à son tour (au plus
        // `fenetre`). Avec `JournalRecusActeur`, le second ne peut pas lire pendant cette retenue : la fenêtre expire,
        // le premier écrit, le second voit son reçu en vol. Sans sérialisation, les deux liraient « aucun reçu » en
        // même temps et écriraient tous deux : le test rougit (deux lectures simultanées, fenêtre non expirée).
        let magasin = MagasinEntrelace(fenetre: 0.3)
        let premier = try scan(essai1)
        let second = try scan(essai2)
        let journalA = ReceiptJournal<RecuScan>(store: magasin)
        let journalB = ReceiptJournal<RecuScan>(store: magasin)

        // Tâches détachées : aucune isolation héritée du test, seule la sérialisation du journal les ordonne.
        let a = Task.detached { () -> RecuErreur? in
            do { try await journalA.ecrire(premier); return nil } catch { return error as? RecuErreur ?? .champInvalide("\(error)") }
        }
        try await magasin.attendrePremiereLectureRetenue()
        let b = Task.detached { () -> RecuErreur? in
            do { try await journalB.ecrire(second); return nil } catch { return error as? RecuErreur ?? .champInvalide("\(error)") }
        }
        magasin.signalerSecondEssaiLance()
        let issueA = await a.value
        let issueB = await b.value

        XCTAssertEqual(magasin.lecturesSimultaneesMax, 1, "jamais deux lectures du journal en même temps")
        XCTAssertTrue(magasin.fenetreExpiree, "le second essai, lancé, n'a pas pu lire pendant la retenue du premier")
        XCTAssertNil(issueA, "le premier essai gagne")
        XCTAssertEqual(issueB, .recuEnCours, "le second voit le reçu en vol du premier")
        let relu = try await journalA.lire(userId: userId)
        XCTAssertEqual(relu, premier)
    }
}

/// Magasin qui force l'entrelacement de deux essais : la PREMIÈRE lecture est retenue jusqu'à
/// `signalerSecondEssaiLance()` (5 s au plus), puis jusqu'au début d'une seconde lecture ou l'expiration de `fenetre`.
/// Compte les lectures simultanées. Sémaphores bloquants : `lire` est synchrone (protocole `ReceiptStorePort`).
final class MagasinEntrelace: ReceiptStorePort, @unchecked Sendable {
    private let base = MagasinRecusEnMemoire()
    private let verrou = NSLock()
    private let lancement = DispatchSemaphore(value: 0)
    private let secondeLecture = DispatchSemaphore(value: 0)
    private let fenetre: TimeInterval
    private var lectures = 0
    private var enCours = 0
    private var maximum = 0
    private var retenue = false
    private var expiree = false

    init(fenetre: TimeInterval) {
        self.fenetre = fenetre
    }

    var lecturesSimultaneesMax: Int { verrou.lock(); defer { verrou.unlock() }; return maximum }
    var fenetreExpiree: Bool { verrou.lock(); defer { verrou.unlock() }; return expiree }
    private var premiereRetenue: Bool { verrou.lock(); defer { verrou.unlock() }; return retenue }

    func signalerSecondEssaiLance() { lancement.signal() }

    /// Attend que la première lecture soit retenue (5 s au plus).
    func attendrePremiereLectureRetenue() async throws {
        var attente = 0
        while !premiereRetenue {
            guard attente < 5_000 else { throw PanneEntrelacement() }
            attente += 1
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    struct PanneEntrelacement: Error {}

    func lire(_ cle: CleRecu) throws -> Data? {
        verrou.lock()
        lectures += 1
        let rang = lectures
        enCours += 1
        maximum = max(maximum, enCours)
        if rang == 1 { retenue = true }
        verrou.unlock()
        defer { verrou.lock(); enCours -= 1; verrou.unlock() }
        if rang == 1 {
            _ = lancement.wait(timeout: .now() + 5)
            let issue = secondeLecture.wait(timeout: .now() + fenetre)
            verrou.lock(); expiree = issue == .timedOut; verrou.unlock()
        } else if rang == 2 {
            secondeLecture.signal()
        }
        return try base.lire(cle)
    }

    func ecrire(_ donnees: Data, pour cle: CleRecu) throws { try base.ecrire(donnees, pour: cle) }
    func effacer(_ cle: CleRecu) throws { try base.effacer(cle) }
}

/// Magasin de test : pannes, écriture ignorée, relecture altérée, effacement ignoré ; journal des appels.
final class MagasinDeTest: ReceiptStorePort, @unchecked Sendable {
    enum Panne: CaseIterable { case lecture, ecriture, effacement }
    struct PanneSimulee: Error {}

    private let verrou = NSLock()
    private var elements: [CleRecu: Data] = [:]
    private var journalAppels: [String] = []
    var panne: Panne?
    var relitAutreChose = false
    var ignoreEcriture = false
    var ignoreEffacement = false

    var appels: [String] {
        verrou.lock(); defer { verrou.unlock() }
        return journalAppels
    }

    func poser(_ donnees: Data, cle: CleRecu) {
        verrou.lock(); defer { verrou.unlock() }
        elements[cle] = donnees
    }

    func donnees(_ cle: CleRecu) -> Data? {
        verrou.lock(); defer { verrou.unlock() }
        return elements[cle]
    }

    func lire(_ cle: CleRecu) throws -> Data? {
        verrou.lock(); defer { verrou.unlock() }
        journalAppels.append("lire \(cle.compte)")
        if panne == .lecture { throw PanneSimulee() }
        guard let valeur = elements[cle] else { return nil }
        return relitAutreChose ? valeur + Data(" ".utf8) : valeur
    }

    func ecrire(_ donnees: Data, pour cle: CleRecu) throws {
        verrou.lock(); defer { verrou.unlock() }
        journalAppels.append("ecrire \(cle.compte)")
        if panne == .ecriture { throw PanneSimulee() }
        if !ignoreEcriture { elements[cle] = donnees }
    }

    func effacer(_ cle: CleRecu) throws {
        verrou.lock(); defer { verrou.unlock() }
        journalAppels.append("effacer \(cle.compte)")
        if panne == .effacement { throw PanneSimulee() }
        if !ignoreEffacement { elements[cle] = nil }
    }
}
