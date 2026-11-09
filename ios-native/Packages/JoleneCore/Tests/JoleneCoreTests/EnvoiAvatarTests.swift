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

    func scripter(depot: Issue = .depose, erreurURL: Error? = nil, barriere: Gate? = nil) {
        issueDepot = depot; self.erreurURL = erreurURL; self.barriere = barriere
    }

    func deposer(chemin: String, jpeg: Data, context: MissionReadContext) async throws {
        operations.append("deposer \(chemin)")
        if let barriere { await barriere.wait() }
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

/// Profil simulé pour l'avatar : `avatar_url` écrite par `modifier`, refus, perte de réponse ou profil relu sans l'URL.
actor ProfilAvatarSimule: ProfilPort {
    enum Issue { case lie, refus, perte, nonLie }
    var ligne = ProfilComplet(id: "u-1", prenom: "Léa", nom: "Martin", profession: "IDE")
    var issue: Issue = .lie
    var erreurLecture: Error?
    private(set) var ecritures: [ModificationProfil] = []
    private(set) var lectures = 0

    func scripter(_ issue: Issue, erreurLecture: Error? = nil) { self.issue = issue; self.erreurLecture = erreurLecture }
    func poserAvatar(_ url: String?) { ligne.avatarUrl = url }

    func profil(context: MissionReadContext) throws -> ProfilComplet {
        lectures += 1
        if let erreurLecture { throw erreurLecture }
        return ligne
    }

    func modifier(_ champs: ModificationProfil, context: MissionReadContext) throws -> ProfilComplet {
        ecritures.append(champs)
        switch issue {
        case .refus: throw RefusEnregistrementProfil("Non authentifié")
        case .perte:
            ligne.avatarUrl = champs.avatarUrl ?? ligne.avatarUrl
            throw JoleneError(.network, "Connexion impossible.")
        case .nonLie: return ligne
        case .lie:
            ligne.avatarUrl = champs.avatarUrl ?? ligne.avatarUrl
            return ligne
        }
    }
}

/// Enchaînement d'un changement d'avatar (lot 3, T10 ; blueprint §3 T10, PRINCIPES §3-§4) : reçu écrit avant toute
/// requête, refus 403 du stockage → reçu `refused` et AUCUN `p_avatar_url` ; arrêt entre dépôt et RPC → relecture de
/// `avatar_url` au retour, pas de second envoi automatique ; succès seulement sur l'URL relue.
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
        let recus: RecusAvatarEnMemoire
        let registre: RegistreEnvoisAvatar
    }

    private func monde(recus: RecusAvatarEnMemoire = RecusAvatarEnMemoire()) -> Monde {
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
        let recus = RecusAvatarEnMemoire()
        try await recus.ecrire(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: chemin, phase: .stored))
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
    }

    func testArretApresLaRPCConfirmeParLaRelecture() async throws {
        let recus = RecusAvatarEnMemoire()
        try await recus.ecrire(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: chemin, phase: .stored))
        let m = monde(recus: recus)
        let lie = "https://ref.supabase.co/storage/v1/object/sign/jolene-documents/\(chemin)?token=t"
        await m.profil.poserAvatar(lie)
        let issue = try await m.envoi.reconcilier(context: contexte)
        XCTAssertEqual(issue, .confirmee(URL(string: lie)!))
        let ecritures = await m.profil.ecritures
        XCTAssertTrue(ecritures.isEmpty)
        let reste = try await recus.lire(userId: "u-1")
        XCTAssertNil(reste)
    }

    func testReçuPrepareOuTerminalSoldeSansRelecture() async throws {
        let recus = RecusAvatarEnMemoire()
        try await recus.ecrire(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: chemin, phase: .prepared))
        let m = monde(recus: recus)
        let prepare = try await m.envoi.reconcilier(context: contexte)
        XCTAssertEqual(prepare, .nonConfirmee, "rien n'est parti : la photo n'a pas changé")
        let lectures = await m.profil.lectures
        XCTAssertEqual(lectures, 0, "aucune requête n'est partie : pas de relecture utile")
        let aucune = try await m.envoi.reconcilier(context: contexte)
        XCTAssertEqual(aucune, .aucune)
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
        let issue = try await m.envoi.reconcilier(context: contexte)
        XCTAssertEqual(issue, .nonConfirmee)
        let ecritures = await m.profil.ecritures
        XCTAssertTrue(ecritures.isEmpty)
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
    }

    func testRefusServeurDuProfilVerbatimEtProfilReluSansURL() async throws {
        let m = monde()
        await m.profil.scripter(.refus)
        let message = await refus { _ = try await m.envoi.televerser(jpeg: jpeg, context: contexte) }
        XCTAssertEqual(message, "Non authentifié", "message serveur verbatim")
        let apresRefus = try await m.recus.lire(userId: "u-1")
        XCTAssertNil(apresRefus)

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
        let recus = RecusAvatarEnMemoire()
        await recus.deposer(Data("altéré".utf8), userId: "u-1")
        let m = monde(recus: recus)
        let message = await refus { _ = try await m.envoi.televerser(jpeg: jpeg, context: contexte) }
        XCTAssertEqual(message, "Une erreur est survenue lors de l'upload. Veuillez réessayer.")
        let operations = await m.stockage.operations
        XCTAssertTrue(operations.isEmpty, "fail-closed : aucune requête sans reçu durable")

        let enPanne = RecusAvatarEnMemoire()
        await enPanne.tomberEnPanne(JoleneError(.unknown, "trousseau"))
        let n = monde(recus: enPanne)
        _ = await refus { _ = try await n.envoi.televerser(jpeg: jpeg, context: contexte) }
        let rien = await n.stockage.operations
        XCTAssertTrue(rien.isEmpty)
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
    }

    func testReçuInterrompuSoldeAvantUnNouvelEnvoiChoisiParLUtilisateur() async throws {
        let recus = RecusAvatarEnMemoire()
        try await recus.ecrire(RecuAvatar(userId: "u-1", attemptId: "essai-0", chemin: "u-1/avatar-1.jpg", phase: .started))
        let m = monde(recus: recus)
        _ = try await m.envoi.televerser(jpeg: jpeg, context: contexte)
        let operations = await m.stockage.operations
        XCTAssertEqual(operations.first, "deposer \(chemin)", "le nouvel envoi seul, l'ancien n'est jamais rejoué")
        XCTAssertEqual(operations.count, 2)
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
