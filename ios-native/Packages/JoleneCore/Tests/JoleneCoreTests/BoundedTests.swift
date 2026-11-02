import XCTest
@testable import JoleneCore

/// Borne d'un appel de port (`Session/Bounded.swift`), extraite de `SessionController` au lot 1
/// (blueprint §2.3) pour que les modèles d'écran bornent chaque lecture et chaque mutation au
/// même délai que la résolution de session (`resolutionTimeout`, 15 s par défaut).
final class BoundedTests: XCTestCase {
    func testLaReponseAvantLeDelaiGagne() async throws {
        let valeur = try await bounded(timeout: 5) { 42 }
        XCTAssertEqual(valeur, 42)
    }

    func testUneErreurDuPortEstPropageeTelleQuelle() async {
        do {
            _ = try await bounded(timeout: 5) { () async throws -> Int in
                throw JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.")
            }
            XCTFail("erreur du port attendue")
        } catch let error as JoleneError {
            XCTAssertEqual(error, JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
        }
    }

    func testLeDepassementEstUneErreurReseauGenerique() async {
        let debut = Date()
        do {
            _ = try await bounded(timeout: 0.05) { () async throws -> Int in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
            XCTFail("dépassement attendu")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .network)
            XCTAssertEqual(error.message, SessionController.timeoutMessage)
            XCTAssertEqual(error.message, "Le service ne répond pas. Vérifiez votre connexion puis réessayez.")
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(debut), 2, "le délai, pas la réponse, rend la main")
    }

    func testUnPortQuiIgnoreLAnnulationNeRetientPasLAppelant() async {
        let barriere = Gate()
        let debut = Date()
        do {
            _ = try await bounded(timeout: 0.05) { () async throws -> Int in
                await barriere.wait() // n'observe jamais l'annulation
                return 1
            }
            XCTFail("dépassement attendu")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .network)
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(debut), 2, "aucun groupe structuré n'attend le port muet")
        await barriere.open()
    }

    func testLeTravailPerdantEstAnnule() async {
        let journal = CallLog()
        do {
            _ = try await bounded(timeout: 0.05) { () async throws -> Int in
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    await journal.record("travail annulé")
                    throw error
                }
                return 1
            }
            XCTFail("dépassement attendu")
        } catch {}
        for _ in 0..<200 {
            if await journal.entries.contains("travail annulé") { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let entrees = await journal.entries
        XCTAssertEqual(entrees, ["travail annulé"])
    }

    func testLAnnulationDeLAppelantEstUneAnnulationPasUnDelai() async {
        // Le `.task` d'une vue qui disparaît annule le modèle d'écran : afficher « Le service ne
        // répond pas » serait faux. `CancellationError` est rendue sans attendre le délai (les
        // modèles la traitent comme une annulation, `MissionsModelsTests`).
        let barriere = Gate()
        let journal = CallLog()
        let debut = Date()
        let appel = Task { () -> Error? in
            do {
                _ = try await bounded(timeout: 30) { () async throws -> Int in
                    await journal.record("démarré")
                    await barriere.wait() // port muet : n'observe jamais l'annulation
                    return 1
                }
                return nil
            } catch {
                return error
            }
        }
        for _ in 0..<400 {
            if await journal.entries.contains("démarré") { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        appel.cancel()
        let erreur = await appel.value
        XCTAssertTrue(erreur is CancellationError, "attendu : CancellationError, obtenu : \(String(describing: erreur))")
        XCTAssertNil(erreur as? JoleneError, "jamais le message de délai dépassé")
        XCTAssertLessThan(Date().timeIntervalSince(debut), 5, "l'annulation rend la main sans attendre le délai de 30 s")
        await barriere.open()
    }

    func testUnAppelantDejaAnnuleRecoitUneAnnulationEtLeTravailEstAnnule() async {
        let depart = Gate()
        let journal = CallLog()
        let appel = Task { () -> Error? in
            await depart.wait() // non annulable : l'appel part d'une tâche déjà annulée
            do {
                _ = try await bounded(timeout: 30) { () async throws -> Int in
                    do {
                        try await Task.sleep(nanoseconds: 30_000_000_000)
                    } catch {
                        await journal.record("travail annulé")
                        throw error
                    }
                    return 1
                }
                return nil
            } catch {
                return error
            }
        }
        appel.cancel()
        await depart.open()
        let erreur = await appel.value
        XCTAssertTrue(erreur is CancellationError, "attendu : CancellationError, obtenu : \(String(describing: erreur))")
        for _ in 0..<400 {
            if await journal.entries.contains("travail annulé") { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let entrees = await journal.entries
        XCTAssertEqual(entrees, ["travail annulé"], "le travail en vol est annulé avec l'appelant")
    }

    func testLeControleurExposeSonDelaiSansIsolation() {
        let socle = Gateways(auth: NeutralAuth(), role: NeutralRole(), missions: NeutralMissions())
        // `nonisolated` : lisible par un modèle d'écran @MainActor sans `await`.
        XCTAssertEqual(SessionController(gateways: socle).resolutionTimeout, 15)
        XCTAssertEqual(SessionController.defaultResolutionTimeout, 15)
        XCTAssertEqual(SessionController(gateways: socle, resolutionTimeout: 0.5).resolutionTimeout, 0.5)
    }

    func testLeControleurBorneSesAppelsParLeMemeHelper() async {
        // Restauration muette : le contrôleur rend la main au délai, état récupérable.
        let barriere = Gate()
        let socle = Gateways(auth: SilentAuth(gate: barriere), role: NeutralRole(), missions: NeutralMissions())
        let controleur = SessionController(gateways: socle, resolutionTimeout: 0.05)
        let etat = await controleur.start()
        XCTAssertEqual(etat, .signedOut(message: SessionController.restoreFailedMessage))
        let reessai = await controleur.canRetryRestore
        XCTAssertTrue(reessai)
        await barriere.open()
    }
}

/// Port d'auth dont la restauration reste bloquée jusqu'à l'ouverture de la barrière.
private struct SilentAuth: AuthPort {
    let gate: Gate
    func restoreSession() async throws -> AuthenticatedUser? {
        await gate.wait()
        return nil
    }
    func signIn(email: String, password: String) async throws -> AuthenticatedUser {
        throw JoleneError(.invalidCredentials, "refusé")
    }
    func signOut() async throws {}
}
