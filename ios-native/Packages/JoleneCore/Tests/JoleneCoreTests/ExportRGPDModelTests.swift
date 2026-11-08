import XCTest
@testable import JoleneCore

/// Serveur d'export simulé : réponses scriptées, appels comptés, barrière optionnelle.
actor ServeurExport {
    private var reponses: [Result<ExportDonneesRGPD, Error>]
    private(set) var appels = 0
    private var barriere: Gate?

    init(_ reponses: [Result<ExportDonneesRGPD, Error>]) { self.reponses = reponses }

    func retenir(_ gate: Gate) { barriere = gate }

    func exporter() async throws -> ExportDonneesRGPD {
        appels += 1
        if let barriere { await barriere.wait() }
        guard !reponses.isEmpty else { throw JoleneError(.contract, "réponse non scriptée") }
        return try reponses.removeFirst().get()
    }
}

struct FakeExportRGPD: ExportRGPDPort {
    let serveur: ServeurExport
    func exporter(context: MissionReadContext) async throws -> ExportDonneesRGPD { try await serveur.exporter() }
}

/// Modèle de l'export RGPD du hub (lot 3, T11) : un fichier n'est écrit que pour un export reçu, dans un
/// dossier temporaire propre à l'export (protection complète), proposé à la feuille de partage puis
/// supprimé à sa fermeture ; un refus `{error}` est affiché verbatim et n'écrit rien ; audit
/// `RGPD_EXPORT_DONNEES` best-effort après l'écriture ; une seule demande à la fois ; epoch d'identité.
@MainActor
final class ExportRGPDModelTests: XCTestCase {
    private static let brut = #"{"utilisateur_id":"u-1","profil":{"prenom":"Léa","nom":"Martin"},"missions":[]}"#
    private let utilisateur = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000))
    /// Racine temporaire propre à chaque test (XCTest crée une instance par méthode), retirée en fin de test.
    private let racine = FileManager.default.temporaryDirectory.appendingPathComponent("export-rgpd-tests-\(UUID().uuidString)")

    private func preparerRacine() throws {
        try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
        let dossier = racine
        addTeardownBlock { try? FileManager.default.removeItem(at: dossier) }
    }

    private struct Scenario {
        var store: SessionStore
        var model: ExportRGPDModel
        var serveur: ServeurExport
        var audit: AuditDetaille
    }

    private func scenario(_ reponses: [Result<ExportDonneesRGPD, Error>]) async throws -> Scenario {
        if !FileManager.default.fileExists(atPath: racine.path) { try preparerRacine() }
        let log = CallLog()
        let serveur = ServeurExport(reponses)
        let audit = AuditDetaille()
        var gateways = Lot1Fakes.gateways(audit: audit)
        gateways.auth = FakeAuth(restored: utilisateur, signInResult: .success(utilisateur), log: log)
        gateways.role = FakeRole(result: .success(RoleResult(role: "SOIGNANT")), gate: nil, log: log)
        gateways.missions = FakeMissions(profile: SoignantProfile(id: "u-1", profession: "IDE"), profileError: nil, gate: nil, log: log)
        gateways.exportRGPD = FakeExportRGPD(serveur: serveur)
        let store = SessionStore(controller: SessionController(gateways: gateways))
        await store.start()
        let snapshot = try XCTUnwrap(store.state.snapshot)
        let model = ExportRGPDModel(session: store, snapshot: snapshot, dossier: DossierExportTemporaire(racine: racine))
        return Scenario(store: store, model: model, serveur: serveur, audit: audit)
    }

    private var contenuRacine: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: racine.path))?.sorted() ?? []
    }

    func testExportJSONEcritLeFichierDuJourPuisLePropose() async throws {
        let s = try await scenario([.success(ExportDonneesRGPD(json: Data(Self.brut.utf8)))])
        await s.model.exporter(.json)
        let partage = try XCTUnwrap(s.model.partage, "fichier proposé à la feuille de partage")
        XCTAssertEqual(partage.nom, "mes-donnees-jolene-2026-11-02.json")
        XCTAssertEqual(partage.url.lastPathComponent, partage.nom)
        XCTAssertEqual(partage.format, .json)
        XCTAssertEqual(try String(contentsOf: partage.url, encoding: .utf8), """
        {
          "utilisateur_id": "u-1",
          "profil": {
            "prenom": "Léa",
            "nom": "Martin"
          },
          "missions": []
        }
        """)
        XCTAssertTrue(partage.url.deletingLastPathComponent().lastPathComponent.hasPrefix(DossierExportTemporaire.prefixe),
                      "dossier propre à l'export, sous la racine temporaire")
        XCTAssertEqual(partage.url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path,
                       racine.standardizedFileURL.path)
        XCTAssertTrue(DossierExportTemporaire.optionsEcriture.contains(.completeFileProtection), "NSFileProtectionComplete (§2.6)")
        XCTAssertNil(s.model.enCours)
        XCTAssertNil(s.model.succes, "rien n'est annoncé avant la fin du partage")
        XCTAssertNil(s.model.erreur)
        let audit = await s.audit.journal.entrees
        XCTAssertEqual(audit, [EntreeAudit(action: "RGPD_EXPORT_DONNEES", typeRessource: "soignant", idRessource: "u-1",
                                           details: ["format": "json"])])
    }

    func testExportCSVAplatiCommeLeWeb() async throws {
        let s = try await scenario([.success(ExportDonneesRGPD(json: Data(Self.brut.utf8)))])
        await s.model.exporter(.csv)
        let partage = try XCTUnwrap(s.model.partage)
        XCTAssertEqual(partage.nom, "mes-donnees-jolene-2026-11-02.csv")
        XCTAssertEqual(try String(contentsOf: partage.url, encoding: .utf8),
                       "Champ,Valeur\n\"utilisateur_id\",\"u-1\"\n\"profil.prenom\",\"Léa\"\n\"profil.nom\",\"Martin\"\n\"missions\",\"[]\"")
        let audit = await s.audit.journal.entrees
        XCTAssertEqual(audit.map(\.details), [["format": "csv"]])
    }

    func testPartageTermineSupprimeLeFichierPuisAnnonceLeSucces() async throws {
        let s = try await scenario([.success(ExportDonneesRGPD(json: Data(Self.brut.utf8)))])
        await s.model.exporter(.json)
        let partage = try XCTUnwrap(s.model.partage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: partage.url.path))
        s.model.partageTermine(complete: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partage.url.path), "fichier supprimé à la fermeture de la feuille")
        XCTAssertEqual(contenuRacine, [], "dossier de l'export supprimé, aucun résidu")
        XCTAssertNil(s.model.partage)
        XCTAssertEqual(s.model.succes, "Données exportées en JSON.")
        // Second appel sans effet (la feuille signale sa fermeture une seule fois, la vue peut la relayer deux fois).
        s.model.partageTermine(complete: true)
        XCTAssertEqual(s.model.succes, "Données exportées en JSON.")
    }

    func testPartageAnnuleSupprimeLeFichierSansSucces() async throws {
        let s = try await scenario([.success(ExportDonneesRGPD(json: Data(Self.brut.utf8)))])
        await s.model.exporter(.csv)
        let partage = try XCTUnwrap(s.model.partage)
        s.model.partageTermine(complete: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partage.url.path))
        XCTAssertEqual(contenuRacine, [])
        XCTAssertNil(s.model.succes, "partage annulé : aucun succès fabriqué")
        XCTAssertNil(s.model.erreur)
    }

    func testRefusDuServeurVerbatimAucunFichier() async throws {
        let s = try await scenario([.failure(JoleneError(.unknown, ExportRGPD.refusLimiteServeur))])
        await s.model.exporter(.json)
        XCTAssertNil(s.model.partage)
        XCTAssertEqual(s.model.erreur, "Trop d'exports en peu de temps. Réessayez dans quelques minutes.")
        XCTAssertEqual(contenuRacine, [], "aucun fichier écrit sur un refus `{error}`")
        let audit = await s.audit.journal.entrees
        XCTAssertTrue(audit.isEmpty)
        XCTAssertNil(s.model.enCours, "nouvel essai manuel possible")
    }

    func testCorpsIllisibleAucunFichier() async throws {
        let s = try await scenario([.success(ExportDonneesRGPD(json: Data("[]".utf8)))])
        await s.model.exporter(.csv)
        XCTAssertNil(s.model.partage)
        XCTAssertEqual(s.model.erreur, ExportRGPD.Textes.echec)
        XCTAssertEqual(contenuRacine, [])
    }

    func testSessionExpireePuisVerification() async throws {
        let s = try await scenario([.failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))])
        await s.model.exporter(.json)
        XCTAssertTrue(s.model.sessionExpiree)
        XCTAssertEqual(s.model.erreur, "Votre session a expiré. Reconnectez-vous.")
        await s.model.verifierSession()
        XCTAssertFalse(s.model.sessionExpiree)
        XCTAssertNil(s.model.erreur)
    }

    func testUneSeuleDemandeALaFois() async throws {
        let s = try await scenario([.success(ExportDonneesRGPD(json: Data(Self.brut.utf8)))])
        let barriere = Gate()
        await s.serveur.retenir(barriere)
        let model = s.model
        let premier = Task { await model.exporter(.json) }
        while await s.serveur.appels == 0 { await Task.yield() }
        XCTAssertEqual(model.enCours, .json)
        await model.exporter(.csv)
        await model.exporter(.json)
        await barriere.open()
        await premier.value
        let appels = await s.serveur.appels
        XCTAssertEqual(appels, 1, "les deux boutons sont désactivés pendant l'export (`exportLoading`, l.119, l.127)")
        XCTAssertEqual(model.partage?.format, .json)
        // Feuille ouverte : aucun second export tant qu'elle n'est pas fermée.
        await model.exporter(.csv)
        let apres = await s.serveur.appels
        XCTAssertEqual(apres, 1)
    }

    func testReponseDUneIdentitePerimeeNEcritRien() async throws {
        let s = try await scenario([.success(ExportDonneesRGPD(json: Data(Self.brut.utf8)))])
        let barriere = Gate()
        await s.serveur.retenir(barriere)
        let model = s.model
        let export = Task { await model.exporter(.json) }
        while await s.serveur.appels == 0 { await Task.yield() }
        await s.store.signOut()
        await barriere.open()
        await export.value
        XCTAssertNil(model.partage)
        XCTAssertEqual(contenuRacine, [], "aucun fichier pour une identité partie")
        let audit = await s.audit.journal.entrees
        XCTAssertTrue(audit.isEmpty)
    }

    func testResidusDUnExportInterrompuPurgesALaCreation() async throws {
        // Un export laissé par un arrêt brutal (feuille jamais fermée) est retiré au prochain écran.
        try preparerRacine()
        let residu = racine.appendingPathComponent("\(DossierExportTemporaire.prefixe)ancien")
        try FileManager.default.createDirectory(at: residu, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: residu.appendingPathComponent("mes-donnees-jolene-2026-10-01.json"))
        let autre = racine.appendingPathComponent("autre-dossier")
        try FileManager.default.createDirectory(at: autre, withIntermediateDirectories: true)
        _ = try await scenario([])
        XCTAssertEqual(contenuRacine, ["autre-dossier"], "seuls les dossiers d'export sont purgés")
    }
}
