import XCTest
@testable import JoleneCore

// MARK: - Doubles de l'avatar (T10)

/// Stockage simulé : journal des opérations, refus ou perte de réponse scriptés.
actor StockageAvatarSimule: StockageAvatarPort {
    enum Issue { case depose, refus, perte }
    var issueDepot: Issue = .depose
    var erreurURL: Error?
    private(set) var operations: [String] = []
    private(set) var objets: [String: Data] = [:]
    /// Retient le dépôt jusqu'à ouverture (envoi « en vol »).
    var barriere: Gate?
    /// Dépôt lent (réseau lent, revue B8 de T10, m7) : durée réelle du dépôt, en secondes.
    var delaiDepot: TimeInterval = 0

    func scripter(depot: Issue = .depose, erreurURL: Error? = nil, barriere: Gate? = nil, delaiDepot: TimeInterval = 0) {
        issueDepot = depot; self.erreurURL = erreurURL; self.barriere = barriere; self.delaiDepot = delaiDepot
    }

    func deposer(chemin: String, jpeg: Data, context: MissionReadContext) async throws {
        operations.append("deposer \(chemin)")
        if let barriere { await barriere.wait() }
        if delaiDepot > 0 { try await Task.sleep(nanoseconds: UInt64(delaiDepot * 1_000_000_000)) }
        switch issueDepot {
        case .refus: throw RefusStockageAvatar(statut: 403)
        case .perte:
            objets[chemin] = jpeg
            throw JoleneError(.network, "Connexion impossible.")
        case .depose:
            objets[chemin] = jpeg
        }
    }

    func urlSignee(chemin: String, dureeSecondes: Int, context: MissionReadContext) throws -> URL {
        operations.append("signer \(chemin) \(dureeSecondes)")
        if let erreurURL { throw erreurURL }
        return URL(string: "https://ref.supabase.co/storage/v1/object/sign/jolene-documents/\(chemin)?token=t")!
    }

    func image(url: URL) -> Data? { objets.values.first }
}

/// Profil simulé pour l'avatar : `avatar_url` écrite par `modifier`, refus, perte de réponse ou profil relu sans l'URL ;
/// barrières optionnelles de lecture (réconciliation en vol) et d'écriture (enregistrement en vol).
actor ProfilAvatarSimule: ProfilPort {
    enum Issue { case lie, refus, perte, nonLie }
    var ligne = ProfilComplet(id: "u-1", prenom: "Léa", nom: "Martin", profession: "IDE")
    var issue: Issue = .lie
    var erreurLecture: Error?
    private(set) var ecritures: [ModificationProfil] = []
    private(set) var lectures = 0
    var barriereLecture: Gate?
    var barriereEcriture: Gate?

    func scripter(_ issue: Issue, erreurLecture: Error? = nil) { self.issue = issue; self.erreurLecture = erreurLecture }
    func poserAvatar(_ url: String?) { ligne.avatarUrl = url }
    func retenir(lecture: Gate? = nil, ecriture: Gate? = nil) { barriereLecture = lecture; barriereEcriture = ecriture }

    func profil(context: MissionReadContext) async throws -> ProfilComplet {
        lectures += 1
        if let barriereLecture { await barriereLecture.wait() }
        if let erreurLecture { throw erreurLecture }
        return ligne
    }

    func modifier(_ champs: ModificationProfil, context: MissionReadContext) async throws -> ProfilComplet {
        ecritures.append(champs)
        if let barriereEcriture { await barriereEcriture.wait() }
        switch issue {
        case .refus: throw RefusEnregistrementProfil("Non authentifié")
        case .perte:
            ligne.avatarUrl = champs.avatarUrl ?? ligne.avatarUrl
            throw JoleneError(.network, "Connexion impossible.")
        case .nonLie: return ligne
        case .lie:
            ligne.avatarUrl = champs.avatarUrl ?? ligne.avatarUrl
            if let ville = champs.villeRecherche { ligne.villeRecherche = ville }
            if let bio = champs.bio { ligne.bio = bio }
            if let lat = champs.adresseLat, let lng = champs.adresseLng { ligne.adresseLat = lat; ligne.adresseLng = lng }
            return ligne
        }
    }
}

/// Magasin de reçus espion (revue B8 de T10, m9) : journal ORDONNÉ des phases écrites (`prepared`, `started`,
/// `stored`, `refused`, `not_sent`) et des effacements (`effacé`), au-dessus d'un magasin en mémoire. Un test prouve
/// ainsi qu'une phase terminale a été JOURNALISÉE avant l'effacement, et pas seulement que le reçu a disparu (un code
/// qui effacerait le reçu sans écrire `refused` ou `not_sent` rendrait ces tests rouges). `semer` et `semerBrut`
/// posent un état initial sans trace.
actor RecusAvatarEspion: RecusAvatarPort {
    private let magasin = RecusAvatarEnMemoire()
    private(set) var journal: [String] = []

    func semer(_ recu: RecuAvatar) async throws { try await magasin.ecrire(recu) }
    func semerBrut(_ donnees: Data?, userId: String) async { await magasin.deposer(donnees, userId: userId) }
    func tomberEnPanne(_ erreur: Error?) async { await magasin.tomberEnPanne(erreur) }
    func brut(userId: String) async -> Data? { await magasin.brut(userId: userId) }

    func lire(userId: String) async throws -> RecuAvatar? { try await magasin.lire(userId: userId) }

    func ecrire(_ recu: RecuAvatar) async throws {
        try await magasin.ecrire(recu)
        journal.append(recu.phase.rawValue)
    }

    func effacer(userId: String) async throws {
        try await magasin.effacer(userId: userId)
        journal.append("effacé")
    }
}

/// Enchaînement d'un changement d'avatar (lot 3, T10 ; blueprint §3 T10, PRINCIPES §3-§4) : reçu écrit avant toute
/// requête, refus 403 du stockage → reçu `refused` et AUCUN `p_avatar_url` ; arrêt entre dépôt et RPC → relecture de
/// `avatar_url` au retour, pas de second envoi automatique ; succès seulement sur l'URL relue. Revue B8 : suite des
/// phases journalisées (m9), reprise d'un reçu illisible à la réconciliation (m8), réconciliations simultanées (m6).
final class EnvoiAvatarTests: XCTestCase {
    private let contexte = MissionReadContext(userId: "u-1", email: "u-1@example.invalid",
                                              profile: SoignantProfile(id: "u-1", profession: "IDE"))
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])
    private let instant = Date(timeIntervalSince1970: 1_793_577_600)
    private let chemin = "u-1/avatar-1793577600000.jpg"

    private struct Monde {
        let envoi: EnvoiAvatar
        let stockage: StockageAvatarSimule
        let profil: ProfilAvatarSimule
        let recus: RecusAvatarEspion
        let registre: RegistreEnvoisAvatar
    }

    private func monde(recus: RecusAvatarEspion = RecusAvatarEspion()) -> Monde {
        let stockage = StockageAvatarSimule()
        let profil = ProfilAvatarSimule()
        let registre = RegistreEnvoisAvatar()
        let envoi = EnvoiAvatar(stockage: stockage, profil: profil, recus: recus, horloge: FixedClock(instant),
                                registre: registre, identifiant: { "essai-1" })
        return Monde(envoi: envoi, stockage: stockage, profil: profil, recus: recus, registre: registre)
    }

    private func refus(_ operation: () async throws -> Void) async -> String? {
        do {
            try await operation()
            return nil
        } catch let refus as RefusAvatar {
            return refus.message
        } catch {
            XCTFail("refus certain attendu, obtenu \(error)")
            return nil
        }
    }

    func testSuccesReçuAvantLEnvoiURLSigneeCinqAnsPuisRelueEtReçuEfface() async throws {
        let m = monde()
        let url = try await m.envoi.televerser(jpeg: jpeg, context: contexte)
        XCTAssertEqual(url.absoluteString, "https://ref.supabase.co/storage/v1/object/sign/jolene-documents/\(chemin)?token=t")
        let operations = await m.stockage.operations
        XCTAssertEqual(operations, ["deposer \(chemin)", "signer \(chemin) 157680000"])
        let ecritures = await m.profil.ecritures
        XCTAssertEqual(ecritures, [ModificationProfil(avatarUrl: url.absoluteString)], "seul `p_avatar_url` part")
        XCTAssertEqual(ecritures.first?.parametres.keys.sorted(), ["p_avatar_url"])
        let reste = try await m.recus.lire(userId: "u-1")
        XCTAssertNil(reste, "reçu effacé après la relecture")
        let journal = await m.recus.journal
        XCTAssertEqual(journal, ["prepared", "started", "stored", "effacé"], "chaque phase journalisée avant l'étape suivante")
    }

    func testRefus403DuStockageReçuRefusedEtAucunPAvatarUrl() async throws {
        let m = monde()
        await m.stockage.scripter(depot: .refus)
        let message = await refus { _ = try await m.envoi.televerser(jpeg: jpeg, context: contexte) }
        XCTAssertEqual(message, "Une erreur est survenue lors de l'upload. Veuillez réessayer.")
        let ecritures = await m.profil.ecritures
        XCTAssertTrue(ecritures.isEmpty, "aucun `p_avatar_url` envoyé après un refus du stockage")
        let operations = await m.stockage.operations
        XCTAssertEqual(operations, ["deposer \(chemin)"], "ni URL signée ni renvoi")
        let reste = try await m.recus.lire(userId: "u-1")
        XCTAssertNil(reste, "reçu `refused` (terminal) soldé")
        let journal = await m.recus.journal
        XCTAssertEqual(journal, ["prepared", "started", "refused", "effacé"], "`refused` journalisé AVANT l'effacement")
    }

    func testReçuEcritAvantLeDepotEtEnStartedPendantLEnvoi() async throws {
        let m = monde()
        let barriere = Gate()
        await m.stockage.scripter(barriere: barriere)
        let envoi = m.envoi
        let contexte = contexte
        let jpeg = jpeg
        let tache = Task { try await envoi.televerser(jpeg: jpeg, context: contexte) }
        var recu: RecuAvatar?
        for _ in 0..<200 {
            recu = try await m.recus.lire(userId: "u-1")
            if recu?.phase == .started { break }
            await Task.yield()
        }
        XCTAssertEqual(recu?.phase, .started, "reçu durable écrit avant que la requête parte")
        XCTAssertEqual(recu?.chemin, chemin)
        // Écran rouvert pendant l'envoi : la réconciliation ne touche pas un essai en vol.
        let pendant = try await envoi.reconcilier(context: contexte)
        XCTAssertEqual(pendant, .aucune)
        let encore = try await m.recus.lire(userId: "u-1")
        XCTAssertEqual(encore?.phase, .started)
        await barriere.open()
        _ = try await tache.value
        let fin = try await m.recus.lire(userId: "u-1")
        XCTAssertNil(fin)
    }

    func testArretEntreDepotEtRPCRelectureAuRetourSansSecondEnvoi() async throws {
        // Envoi interrompu après le dépôt (RPC jamais partie) : le reçu reste en `stored`.
        let recus = RecusAvatarEspion()
        try await recus.semer(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: chemin, phase: .stored))
        let m = monde(recus: recus)
        let issue = try await m.envoi.reconcilier(context: contexte)
        XCTAssertEqual(issue, .nonConfirmee, "avatar_url relue ne désigne pas l'objet : rien n'est lié")
        let operations = await m.stockage.operations
        XCTAssertTrue(operations.isEmpty, "aucun second dépôt automatique")
        let ecritures = await m.profil.ecritures
        XCTAssertTrue(ecritures.isEmpty, "aucun `p_avatar_url` rejoué")
        let lectures = await m.profil.lectures
        XCTAssertEqual(lectures, 1, "relecture de `avatar_url`")
        let reste = try await recus.lire(userId: "u-1")
        XCTAssertNil(reste, "essai clos (not_sent) puis soldé")
        let journal = await recus.journal
        XCTAssertEqual(journal, ["not_sent", "effacé"], "`not_sent` journalisé AVANT l'effacement")
    }

    func testArretApresLaRPCConfirmeParLaRelecture() async throws {
        let recus = RecusAvatarEspion()
        try await recus.semer(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: chemin, phase: .stored))
        let m = monde(recus: recus)
        let lie = "https://ref.supabase.co/storage/v1/object/sign/jolene-documents/\(chemin)?token=t"
        await m.profil.poserAvatar(lie)
        let issue = try await m.envoi.reconcilier(context: contexte)
        XCTAssertEqual(issue, .confirmee(URL(string: lie)!))
        let ecritures = await m.profil.ecritures
        XCTAssertTrue(ecritures.isEmpty)
        let reste = try await recus.lire(userId: "u-1")
        XCTAssertNil(reste)
        let journal = await recus.journal
        XCTAssertEqual(journal, ["effacé"], "envoi confirmé : aucun `not_sent`")
    }

    func testReçuPrepareOuTerminalSoldeSansRelecture() async throws {
        let recus = RecusAvatarEspion()
        try await recus.semer(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: chemin, phase: .prepared))
        let m = monde(recus: recus)
        let prepare = try await m.envoi.reconcilier(context: contexte)
        XCTAssertEqual(prepare, .nonConfirmee, "rien n'est parti : la photo n'a pas changé")
        let lectures = await m.profil.lectures
        XCTAssertEqual(lectures, 0, "aucune requête n'est partie : pas de relecture utile")
        let journal = await recus.journal
        XCTAssertEqual(journal, ["not_sent", "effacé"], "essai `prepared` clos `not_sent` puis soldé")
        let aucune = try await m.envoi.reconcilier(context: contexte)
        XCTAssertEqual(aucune, .aucune)

        // Reçu déjà terminal (refus journalisé, effacement interrompu) : soldé sans nouvelle phase.
        let terminal = RecusAvatarEspion()
        try await terminal.semer(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: chemin, phase: .refused))
        let t = monde(recus: terminal)
        let issueTerminale = try await t.envoi.reconcilier(context: contexte)
        XCTAssertEqual(issueTerminale, .aucune)
        let journalTerminal = await terminal.journal
        XCTAssertEqual(journalTerminal, ["effacé"])
    }

    func testPerteDeReponseDuDepotLaisseLeReçuStartedPuisReconciliation() async throws {
        let m = monde()
        await m.stockage.scripter(depot: .perte)
        do {
            _ = try await m.envoi.televerser(jpeg: jpeg, context: contexte)
            XCTFail("issue inconnue attendue")
        } catch {
            XCTAssertFalse(error is RefusAvatar, "un délai ou une coupure n'est pas un refus certain")
        }
        let recu = try await m.recus.lire(userId: "u-1")
        XCTAssertEqual(recu?.phase, .started, "issue inconnue : reçu conservé pour la réconciliation")
        let avant = await m.recus.journal
        XCTAssertEqual(avant, ["prepared", "started"], "aucune phase terminale tant que l'issue est inconnue")
        let issue = try await m.envoi.reconcilier(context: contexte)
        XCTAssertEqual(issue, .nonConfirmee)
        let ecritures = await m.profil.ecritures
        XCTAssertTrue(ecritures.isEmpty)
        let apres = await m.recus.journal
        XCTAssertEqual(apres, ["prepared", "started", "not_sent", "effacé"])
    }

    func testPerteDeReponseDeLaRPCConfirmeeParLaRelecture() async throws {
        let m = monde()
        await m.profil.scripter(.perte)
        do {
            _ = try await m.envoi.televerser(jpeg: jpeg, context: contexte)
            XCTFail("issue inconnue attendue")
        } catch {
            XCTAssertFalse(error is RefusAvatar)
        }
        let recu = try await m.recus.lire(userId: "u-1")
        XCTAssertEqual(recu?.phase, .stored)
        let issue = try await m.envoi.reconcilier(context: contexte)
        guard case let .confirmee(url) = issue else { return XCTFail("relecture : avatar lié, obtenu \(issue)") }
        XCTAssertTrue(AvatarProfil.urlDesigne(url.absoluteString, chemin: chemin))
        let ecritures = await m.profil.ecritures
        XCTAssertEqual(ecritures.count, 1, "une seule écriture, jamais rejouée")
        let journal = await m.recus.journal
        XCTAssertEqual(journal, ["prepared", "started", "stored", "effacé"], "lié et relu : aucun `not_sent`")
    }

    func testRefusServeurDuProfilVerbatimEtProfilReluSansURL() async throws {
        let m = monde()
        await m.profil.scripter(.refus)
        let message = await refus { _ = try await m.envoi.televerser(jpeg: jpeg, context: contexte) }
        XCTAssertEqual(message, "Non authentifié", "message serveur verbatim")
        let apresRefus = try await m.recus.lire(userId: "u-1")
        XCTAssertNil(apresRefus)
        let journal = await m.recus.journal
        XCTAssertEqual(journal, ["prepared", "started", "stored", "refused", "effacé"])

        let autre = monde()
        await autre.profil.scripter(.nonLie)
        do {
            _ = try await autre.envoi.televerser(jpeg: jpeg, context: contexte)
            XCTFail("profil relu sans l'URL : aucun succès")
        } catch {
            XCTAssertFalse(error is RefusAvatar)
        }
        let recu = try await autre.recus.lire(userId: "u-1")
        XCTAssertEqual(recu?.phase, .stored, "issue non prouvée : la réconciliation tranchera")
    }

    func testReçuIllisibleOuMagasinEnPanneRienNEstEnvoye() async throws {
        let recus = RecusAvatarEspion()
        await recus.semerBrut(Data("altéré".utf8), userId: "u-1")
        let m = monde(recus: recus)
        let message = await refus { _ = try await m.envoi.televerser(jpeg: jpeg, context: contexte) }
        XCTAssertEqual(message, "Une erreur est survenue lors de l'upload. Veuillez réessayer.")
        let operations = await m.stockage.operations
        XCTAssertTrue(operations.isEmpty, "fail-closed : aucune requête sans reçu durable")

        let enPanne = RecusAvatarEspion()
        await enPanne.tomberEnPanne(JoleneError(.unknown, "trousseau"))
        let n = monde(recus: enPanne)
        _ = await refus { _ = try await n.envoi.televerser(jpeg: jpeg, context: contexte) }
        let rien = await n.stockage.operations
        XCTAssertTrue(rien.isEmpty)
    }

    /// Revue B8 de T10, m8 : un reçu ILLISIBLE (octets présents mais indécodables, autre version, autre utilisateur)
    /// bloquait tout envoi pour toujours (le trousseau survit à la réinstallation). Voie de reprise : la réconciliation
    /// (ouverture de l'écran) le retire — essai inconnu clos, sans requête ni `p_avatar_url` ; la photo affichée reste
    /// `avatar_url` relue à l'ouverture ; un nouvel envoi choisi par l'utilisateur peut alors partir. L'envoi lui-même
    /// reste fail-closed (test précédent) : seule la réconciliation reprend.
    func testReçuIllisibleRetireParLaReconciliationPuisNouvelEnvoiPossible() async throws {
        for altere in [Data("altéré".utf8),
                       Data(#"{"attempt_id":"e","chemin":"u-1/avatar-1.jpg","phase":"stored","user_id":"u-1","v":2}"#.utf8),
                       Data(#"{"attempt_id":"e","chemin":"u-2/avatar-1.jpg","phase":"stored","user_id":"u-2","v":1}"#.utf8)] {
            let recus = RecusAvatarEspion()
            await recus.semerBrut(altere, userId: "u-1")
            let m = monde(recus: recus)
            let issue = try await m.envoi.reconcilier(context: contexte)
            XCTAssertEqual(issue, .aucune, "essai inconnu : rien à annoncer, la photo relue fait foi")
            let journal = await recus.journal
            XCTAssertEqual(journal, ["effacé"], "reçu illisible retiré, aucune phase inventée")
            let brut = await recus.brut(userId: "u-1")
            XCTAssertNil(brut)
            let operations = await m.stockage.operations
            XCTAssertTrue(operations.isEmpty, "aucune requête pendant la reprise")
            let ecritures = await m.profil.ecritures
            XCTAssertTrue(ecritures.isEmpty, "aucun `p_avatar_url` envoyé pendant la reprise")
            _ = try await m.envoi.televerser(jpeg: jpeg, context: contexte)
            let apres = await m.stockage.operations
            XCTAssertEqual(apres.first, "deposer \(chemin)", "nouvel envoi choisi par l'utilisateur, avec un reçu neuf")
        }
    }

    /// Revue B8 de T10, m8 : un magasin EN PANNE (trousseau verrouillé, erreur du système) n'est pas un reçu illisible :
    /// rien n'est effacé, la réconciliation échoue fermée (l'état d'un envoi précédent reste inconnu).
    func testMagasinEnPanneALaReconciliationRienNEstEfface() async throws {
        let recus = RecusAvatarEspion()
        try await recus.semer(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: chemin, phase: .stored))
        await recus.tomberEnPanne(JoleneError(.unknown, "trousseau"))
        let m = monde(recus: recus)
        let message = await refus { _ = try await m.envoi.reconcilier(context: contexte) }
        XCTAssertEqual(message, "Une erreur est survenue lors de l'upload. Veuillez réessayer.")
        await recus.tomberEnPanne(nil)
        let reste = try await recus.lire(userId: "u-1")
        XCTAssertEqual(reste?.phase, .stored, "reçu conservé pour une réconciliation ultérieure")
        let journal = await recus.journal
        XCTAssertTrue(journal.isEmpty)
        let lectures = await m.profil.lectures
        XCTAssertEqual(lectures, 0)
    }

    /// Revue B8 de T10, m6 : deux réconciliations du même reçu ne s'entrelacent pas. La seconde, lancée pendant la
    /// relecture de la première, rend `.aucune` sans rien écrire (jamais `transitionInterdite` ni échec parasite) ;
    /// la première clôt l'essai une seule fois.
    func testDeuxReconciliationsSimultaneesUnSeulSolde() async throws {
        let recus = RecusAvatarEspion()
        try await recus.semer(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: chemin, phase: .stored))
        let m = monde(recus: recus)
        let barriere = Gate()
        await m.profil.retenir(lecture: barriere)
        let envoi = m.envoi
        let contexte = contexte
        let premiere = Task { try await envoi.reconcilier(context: contexte) }
        var lectures = 0
        for _ in 0..<500 {
            lectures = await m.profil.lectures
            if lectures == 1 { break }
            await Task.yield()
        }
        XCTAssertEqual(lectures, 1, "première réconciliation en relecture")
        let seconde = try await envoi.reconcilier(context: contexte)
        XCTAssertEqual(seconde, .aucune, "reçu déjà en cours de réconciliation : rien n'est touché")
        await barriere.open()
        let issue = try await premiere.value
        XCTAssertEqual(issue, .nonConfirmee)
        let journal = await recus.journal
        XCTAssertEqual(journal, ["not_sent", "effacé"], "essai clos une seule fois")
        let lecturesFinales = await m.profil.lectures
        XCTAssertEqual(lecturesFinales, 1, "une seule relecture")
    }

    func testFichierVideOuTropLourdRefuseAvantToutReçu() async throws {
        let m = monde()
        let vide = await refus { _ = try await m.envoi.televerser(jpeg: Data(), context: contexte) }
        XCTAssertEqual(vide, "Le fichier sélectionné est vide.")
        let lourd = await refus {
            _ = try await m.envoi.televerser(jpeg: Data(count: AvatarProfil.tailleMaxOctets + 1), context: contexte)
        }
        XCTAssertEqual(lourd, "Le fichier ne doit pas dépasser 2 Mo.")
        let operations = await m.stockage.operations
        XCTAssertTrue(operations.isEmpty)
        let recu = try await m.recus.lire(userId: "u-1")
        XCTAssertNil(recu)
        let journal = await m.recus.journal
        XCTAssertTrue(journal.isEmpty, "aucun reçu pour un fichier refusé avant l'envoi")
    }

    func testReçuInterrompuSoldeAvantUnNouvelEnvoiChoisiParLUtilisateur() async throws {
        let recus = RecusAvatarEspion()
        try await recus.semer(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: "u-1/avatar-1.jpg", phase: .started))
        let m = monde(recus: recus)
        _ = try await m.envoi.televerser(jpeg: jpeg, context: contexte)
        let operations = await m.stockage.operations
        XCTAssertEqual(operations.first, "deposer \(chemin)", "le nouvel envoi seul, l'ancien n'est jamais rejoué")
        XCTAssertEqual(operations.count, 2)
        let journal = await recus.journal
        XCTAssertEqual(journal, ["not_sent", "effacé", "prepared", "started", "stored", "effacé"],
                       "ancien essai clos `not_sent` avant le reçu du nouvel envoi")
    }

    func testContexteInvalideRefuse() async {
        let m = monde()
        let invalide = MissionReadContext(userId: "u-1", email: nil, profile: SoignantProfile(id: "u-2", profession: "IDE"))
        do {
            _ = try await m.envoi.televerser(jpeg: jpeg, context: invalide)
            XCTFail("contexte invalide accepté")
        } catch {
            XCTAssertEqual((error as? JoleneError)?.kind, .contract)
        }
    }
}
