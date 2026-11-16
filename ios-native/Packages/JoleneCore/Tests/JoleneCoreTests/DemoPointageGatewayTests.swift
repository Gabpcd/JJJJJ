import XCTest
@testable import JoleneCore

/// Pointage du monde démo (lot 2, T3 ; blueprint §2.8) : fixtures `demo-presences.json`, codes 123456 (mission a,
/// ouverture), 654321 (mission b, fermeture), 100001 (refus P0002), 100002 (anti-rejeu 23514), scénario
/// `scan-incertain`, code d'une mission saisi dans le bloc d'une autre (revue fraîche de T3, M-A), code tourné jamais
/// rendu, aucun autre utilisateur. L'absence de réseau du cœur est prouvée par la garde statique `DemoNoNetworkTests`,
/// pas par ces tests.
final class DemoPointageGatewayTests: XCTestCase {
    private let terminal = DemoTerminalIdentity.identifiantDemo
    private var context: MissionReadContext { DemoWorld.context }

    private func recu(_ gateway: DemoPointageGateway, mission: String) async throws -> RecuScan {
        let etat = try await gateway.etat(missionId: mission, context: context)
        let preuves = try await gateway.preuvesScan(missionId: mission, context: context)
        return try RecuScan.preparer(userId: context.userId, epoch: 1, missionId: mission, terminalId: terminal,
                                     typeAttendu: etat.prochainTypeScan ?? .ouverture, nbScansAvant: etat.nbScans ?? 0,
                                     preuvesAvant: preuves.map(\.id), gps: .disponible)
            .demarrer(le: DemoWorld.fixedNow)
    }

    private func metadonnees(_ observation: ObservationGps? = .disponible(latitude: 48.8566, longitude: 2.3522, precisionM: 12)) -> MetadonneesScan {
        MetadonneesScan(idTerminal: terminal, observation: observation)
    }

    func testFixtureALHorlogeDuMondeEtSansEstEtab() throws {
        let fixture = try DemoPointageGateway.Fixture.charger()
        XCTAssertEqual(fixture.fixedNow, "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(PlanningHorlogeParis.instant(fixture.fixedNow), DemoWorld.fixedNow)
        XCTAssertNil(fixture.consentementGps, "le soignant démo n'a pas encore répondu")
        XCTAssertEqual(fixture.missions.map(\.id), ["demo-presence-a", "demo-presence-b", "demo-presence-c", "demo-presence-d",
                                                    "demo-presence-e"])
        XCTAssertEqual(fixture.codesAffiches, ["demo-presence-a": "123456", "demo-presence-b": "654321"])
    }

    func testInstantaneDeLaDemoEtOngletsAttendus() async throws {
        let gateway = DemoPointageGateway()
        let instantane = try await gateway.presences(context: context)
        XCTAssertEqual(instantane.chargeLe, DemoWorld.fixedNow)
        let listes = instantane.listes(maintenant: DemoWorld.fixedNow)
        XCTAssertEqual(listes.missionsAujourdhui.map(\.mission.id), ["demo-presence-a", "demo-presence-b", "demo-presence-c"])
        XCTAssertEqual(listes.missionsEnCours.map(\.mission.id), ["demo-presence-b"])
        XCTAssertEqual(listes.missionsAVenir.map(\.mission.id), ["demo-presence-d", "demo-presence-e"])
        XCTAssertEqual(listes.missionsAVenir.map(\.planningAConfirmer), [false, true])
        XCTAssertEqual(listes.contrats["demo-presence-c"]?.statut, "SIGNE_SOIGNANT")
        XCTAssertEqual(listes.missionsAujourdhui.first?.etablissement?.id, "demo-etab-1", "noms par les établissements démo")
        let a = try XCTUnwrap(listes.missionsAujourdhui.first)
        let dispo = DisponibilitePointage.evaluerDisponibilitePointage(creneaux: a.creneaux, contratStatut: listes.contrats[a.mission.id]?.statut,
                                                                       maintenant: DemoWorld.fixedNow)
        XCTAssertEqual(dispo.action, .ouverture, "créneau 00:05Z : pointage ouvert 15 min avant")
        let c = try XCTUnwrap(listes.missionsAujourdhui.last)
        XCTAssertEqual(DisponibilitePointage.evaluerDisponibilitePointage(creneaux: c.creneaux, contratStatut: listes.contrats[c.mission.id]?.statut,
                                                                          maintenant: DemoWorld.fixedNow).motif, .contrat)
        XCTAssertEqual(instantane.lignesHistorique(soignantId: context.userId).map(\.id),
                       ["demo-presence-h1-presence", "demo-presence-h2-presence", "effectifs-mission-demo-presence-h3"])
        XCTAssertEqual(instantane.presencesValidees.map(\.valideLe), ["2026-11-01T14:00:00.000Z"], "validée il y a 10 h")
    }

    func testOuvertureParLeCodeDeLaMissionA() async throws {
        let gateway = DemoPointageGateway()
        let avant = try await gateway.etat(missionId: "demo-presence-a", context: context)
        XCTAssertEqual(avant.prochainTypeScan, .ouverture)
        XCTAssertEqual(avant.nbScans, 0)
        let started = try await recu(gateway, mission: "demo-presence-a")
        let issue = try await gateway.scanner(code: "123456", metadonnees: metadonnees(), recu: started, context: context)
        XCTAssertEqual(issue, .enregistre(typeScan: .ouverture, numeroScan: 1))
        let apres = try await gateway.etat(missionId: "demo-presence-a", context: context)
        XCTAssertEqual(apres.statut, "EN_COURS")
        XCTAssertEqual(apres.prochainTypeScan, .fermeture)
        XCTAssertEqual(apres.nbScans, 1)
        XCTAssertEqual(apres.segments.map(\.fin), [nil], "segment ouvert")
        // Le code a tourné : le même code ne pointe plus, et le nouveau n'est rendu nulle part.
        let second = try await recu(gateway, mission: "demo-presence-a")
        let rejoue = try await gateway.scanner(code: "123456", metadonnees: metadonnees(), recu: second, context: context)
        XCTAssertEqual(rejoue, .refuse(sqlstate: "P0002", message: "Code de pointage invalide ou expiré."))
        let preuves = try await gateway.preuvesScan(missionId: "demo-presence-a", context: context)
        XCTAssertEqual(preuves.map(\.numeroScan), [1])
        XCTAssertEqual(preuves.first?.idTerminal, terminal)
        let presences = try await gateway.presences(context: context)
        XCTAssertEqual(presences.listes(maintenant: DemoWorld.fixedNow).missionsEnCours.map(\.mission.id),
                       ["demo-presence-a", "demo-presence-b"])
    }

    func testFermetureParLeCodeDeLaMissionBSansCoordonneesSiGpsRefuse() async throws {
        let gateway = DemoPointageGateway()
        let avant = try await gateway.etat(missionId: "demo-presence-b", context: context)
        XCTAssertEqual(avant.prochainTypeScan, .fermeture)
        XCTAssertEqual(avant.nbScans, 1)
        let started = try await recu(gateway, mission: "demo-presence-b")
        XCTAssertEqual(started.preuvesAvant, ["demo-scan-demo-presence-b-1"], "base : l'ouverture déjà pointée")
        let issue = try await gateway.scanner(code: "654321", metadonnees: metadonnees(.refusee), recu: started, context: context)
        XCTAssertEqual(issue, .enregistre(typeScan: .fermeture, numeroScan: 2))
        let apres = try await gateway.etat(missionId: "demo-presence-b", context: context)
        XCTAssertEqual(apres.segmentOuvert, false)
        XCTAssertEqual(apres.segments.map(\.fin), ["2026-11-02T00:00:00.000Z"])
        let recues = await gateway.metadonneesRecues
        XCTAssertEqual(recues.count, 1)
        XCTAssertNil(recues.first?.latitude, "GPS refusé : aucune coordonnée")
        XCTAssertNil(recues.first?.longitude)
        XCTAssertNil(recues.first?.precisionGpsM)
    }

    func testCodesDeRefusVerbatim() async throws {
        let gateway = DemoPointageGateway()
        let started = try await recu(gateway, mission: "demo-presence-a")
        let inconnu = try await gateway.scanner(code: DemoPointageGateway.codeInconnuDemo, metadonnees: metadonnees(), recu: started,
                                                context: context)
        XCTAssertEqual(inconnu, .refuse(sqlstate: "P0002", message: "Code de pointage invalide ou expiré."))
        let rejeu = try await gateway.scanner(code: DemoPointageGateway.codeAntiRejeuDemo, metadonnees: metadonnees(), recu: started,
                                              context: context)
        XCTAssertEqual(rejeu, .refuse(sqlstate: "23514", message: "Scan déjà pris en compte. Prochain scan possible dans 87 secondes."))
        let etat = try await gateway.etat(missionId: "demo-presence-a", context: context)
        XCTAssertEqual(etat.nbScans, 0, "un refus n'écrit rien")
        let recues = await gateway.metadonneesRecues
        XCTAssertTrue(recues.isEmpty)
    }

    func testCodeDeLaMissionASaisiDansLeBlocBEnregistreSurA() async throws {
        let gateway = DemoPointageGateway()
        let started = try await recu(gateway, mission: "demo-presence-b")
        let issue = try await gateway.scanner(code: "123456", metadonnees: metadonnees(), recu: started, context: context)
        XCTAssertEqual(issue, .enregistreSurAutreMission(missionId: "demo-presence-a", typeScan: .ouverture, numeroScan: 1),
                       "le code désigne la mission (comme le serveur) : jamais `.incertain`, jamais « non reçu »")
        let a = try await gateway.etat(missionId: "demo-presence-a", context: context)
        XCTAssertEqual(a.nbScans, 1)
        XCTAssertEqual(a.statut, "EN_COURS")
        let b = try await gateway.etat(missionId: "demo-presence-b", context: context)
        XCTAssertEqual(b.nbScans, 1, "mission b inchangée")
        XCTAssertEqual(b.prochainTypeScan, .fermeture)
        let preuvesB = try await gateway.preuvesScan(missionId: "demo-presence-b", context: context)
        XCTAssertEqual(preuvesB.map(\.id), started.preuvesAvant, "aucune preuve ajoutée à b")
        let verdict = try await gateway.reconcilier(recu: started, context: context)
        XCTAssertNotEqual(verdict, .nonRecu)
    }

    /// Seconde revue fraîche de T3 (mi-6) : même garde que `SupabasePointageGateway.scanner`, le terminal du reçu est
    /// celui des métadonnées envoyées ; sinon erreur de contrat et rien n'est appliqué.
    func testTerminalDuRecuDifferentDesMetadonneesRefuseEnContrat() async throws {
        let gateway = DemoPointageGateway()
        let started = try await recu(gateway, mission: "demo-presence-a")
        let autreTerminal = MetadonneesScan(idTerminal: "TERM_IOS_AUTREAUTREAUTREAUTRE", observation: nil)
        do {
            _ = try await gateway.scanner(code: "123456", metadonnees: autreTerminal, recu: started, context: context)
            XCTFail("terminal du reçu différent : erreur de contrat attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
        }
        let etat = try await gateway.etat(missionId: "demo-presence-a", context: context)
        XCTAssertEqual(etat.nbScans, 0, "rien n'est appliqué")
        let recues = await gateway.metadonneesRecues
        XCTAssertTrue(recues.isEmpty)
    }

    func testScanIncertainPuisReconciliation() async throws {
        let gateway = DemoPointageGateway(scenario: .scanIncertain)
        let started = try await recu(gateway, mission: "demo-presence-a")
        let issue = try await gateway.scanner(code: "123456", metadonnees: metadonnees(), recu: started, context: context)
        XCTAssertEqual(issue, .incertain, "réponse perdue après application")
        let verdict = try await gateway.reconcilier(recu: started, context: context)
        XCTAssertEqual(verdict, .enregistre(typeScan: .ouverture, numeroScan: 1), "la relecture retrouve le scan, sans second envoi")
        let preuves = try await gateway.preuvesScan(missionId: "demo-presence-a", context: context)
        XCTAssertEqual(preuves.count, 1, "un seul segment créé")
    }

    // MARK: - Seconde revue fraîche de T4b (m2) : scénarios DEBUG de reprise

    private func attendre401(_ libelle: String, _ appel: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await appel()
            XCTFail("\(libelle) : 401 attendu", file: file, line: line)
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur, JoleneError(.unauthorized, SessionController.sessionExpiredMessage), libelle, file: file, line: line)
        } catch {
            XCTFail("\(libelle) : \(error)", file: file, line: line)
        }
    }

    func testSessionExpireeAuScanAppliqueePuisToutAppelEn401JusquALaRevalidation() async throws {
        let expiration = ExpirationSessionDemo()
        let gateway = DemoPointageGateway(scenario: .sessionExpireeScan, expiration: expiration)
        let started = try await recu(gateway, mission: "demo-presence-a")
        await attendre401("scan") { _ = try await gateway.scanner(code: "123456", metadonnees: self.metadonnees(), recu: started,
                                                                   context: self.context) }
        let recues = await gateway.metadonneesRecues
        XCTAssertEqual(recues.count, 1, "le scan est appliqué une fois avant le 401 (réponse perdue : rien n'est affirmé)")
        let expiree = await expiration.expiree
        XCTAssertTrue(expiree)
        await attendre401("état") { _ = try await gateway.etat(missionId: "demo-presence-a", context: self.context) }
        await attendre401("réconciliation") { _ = try await gateway.reconcilier(recu: started, context: self.context) }
        await attendre401("consentement") { _ = try await gateway.consentementGps(context: self.context) }
        await attendre401("présences") { _ = try await gateway.presences(context: self.context) }

        await expiration.revalider()
        let verdict = try await gateway.reconcilier(recu: started, context: context)
        XCTAssertEqual(verdict, .enregistre(typeScan: .ouverture, numeroScan: 1), "après la revalidation, la relecture retrouve le scan")
        let preuves = try await gateway.preuvesScan(missionId: "demo-presence-a", context: context)
        XCTAssertEqual(preuves.count, 1, "un seul segment créé")
        let suivant = try await recu(gateway, mission: "demo-presence-b")
        let issue = try await gateway.scanner(code: "654321", metadonnees: metadonnees(), recu: suivant, context: context)
        XCTAssertEqual(issue, .enregistre(typeScan: .fermeture, numeroScan: 2), "scénario à usage unique : le scan suivant est normal")
    }

    func testSessionExpireeALaLectureDuConsentementJusquALaRevalidation() async throws {
        let expiration = ExpirationSessionDemo()
        let gateway = DemoPointageGateway(scenario: .sessionExpireeConsentement, expiration: expiration)
        await attendre401("première lecture du consentement") { _ = try await gateway.consentementGps(context: self.context) }
        await attendre401("lecture avant la revalidation") { _ = try await gateway.consentementGps(context: self.context) }
        await expiration.revalider()
        let relu = try await gateway.consentementGps(context: context)
        XCTAssertNil(relu, "consentement NULL de la fixture, inchangé")
        let recues = await gateway.metadonneesRecues
        XCTAssertTrue(recues.isEmpty)
    }

    func testPremierEnregistrementDuConsentementEnEchecPuisLeSuivantAboutit() async throws {
        let gateway = DemoPointageGateway(scenario: .consentementEchec)
        do {
            _ = try await gateway.enregistrerConsentementGps(true, context: context)
            XCTFail("premier fn_consentir_gps en échec attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur, JoleneError(.network, SessionController.timeoutMessage), "délai dépassé, comme une panne du service")
        }
        let apresEchec = try await gateway.consentementGps(context: context)
        XCTAssertNil(apresEchec, "un échec n'écrit rien")
        let relu = try await gateway.enregistrerConsentementGps(true, context: context)
        XCTAssertEqual(relu, true, "le suivant aboutit")
    }

    func testAuthDemoRevalideLaSessionSeulementQuandElleEstOuverte() async throws {
        let expiration = ExpirationSessionDemo()
        let auth = DemoAuthGateway(expiration: expiration)
        await expiration.expirer()
        let avant = try await auth.restoreSession()
        XCTAssertNil(avant)
        let toujours = await expiration.expiree
        XCTAssertTrue(toujours, "aucune session ouverte : rien à revalider")
        _ = try await auth.signIn(email: DemoWorld.user.email ?? "demonstration@example.invalid", password: "demonstration")
        let restaure = try await auth.restoreSession()
        XCTAssertEqual(restaure, DemoWorld.user)
        let apres = await expiration.expiree
        XCTAssertFalse(apres, "« Vérifier ma session » (restauration) revalide la session démo")
    }

    func testConsentementDetailEtRelance() async throws {
        let gateway = DemoPointageGateway()
        let initial = try await gateway.consentementGps(context: context)
        XCTAssertNil(initial)
        let relu = try await gateway.enregistrerConsentementGps(false, context: context)
        XCTAssertEqual(relu, false)
        let reluEnsuite = try await gateway.consentementGps(context: context)
        XCTAssertEqual(reluEnsuite, false)
        let detail = try await gateway.detail(missionId: "demo-presence-h3", context: context)
        XCTAssertEqual(detail.creneaux.filter { $0.typeCreneau == "EFFECTIF" }.count, 2)
        XCTAssertEqual(detail.resume?.pointageEffectue, true)
        let inconnue = try await gateway.detail(missionId: "inconnue", context: context)
        XCTAssertNil(inconnue.resume, "mission inconnue : carte masquée")
        let premiere = try await gateway.relancerValidation(missionId: "demo-presence-h2", context: context)
        XCTAssertEqual(premiere, .envoyee(message: "Établissement relancé. Il a été notifié de valider tes présences."))
        let seconde = try await gateway.relancerValidation(missionId: "demo-presence-h2", context: context)
        XCTAssertEqual(seconde, .refusee(message: "Tu as déjà relancé cet établissement aujourd'hui. Il a été notifié."))
    }

    func testMissionInconnueEtAutreUtilisateur() async throws {
        let gateway = DemoPointageGateway()
        do {
            _ = try await gateway.etat(missionId: "inconnue", context: context)
            XCTFail("mission inconnue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur, JoleneError(.unknown, "Mission introuvable"), "message serveur verbatim (l.35162)")
        }
        var autre = DemoWorld.context
        autre.userId = "user-1"
        autre.profile.id = "user-1"
        do {
            _ = try await gateway.presences(context: autre)
            XCTFail("la démo ne sert aucun autre utilisateur")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
    }
}
