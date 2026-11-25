import XCTest
@testable import JoleneCore

/// Câblage démo de la série (lot 4, T12 ; garde anti-oubli `Lot4Wiring<Domaine>Tests`, `LOT4_PLAN.md` §2.2) et monde
/// démo (§2.7) : fixture `demo-serie.json`, lecture ordonnée, acceptation par la candidature du même monde, réponses
/// scriptées au format du serveur (confrontées au dump).
final class Lot4WiringSerieTests: XCTestCase {
    private static let pack = "SERIE_1793577600000_demo01"
    private static let arret = "SERIE_1793577600000_demo02"
    private let c = DemoWorld.context

    private static func depot(_ chemin: String) throws -> String {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent(chemin)
        guard FileManager.default.fileExists(atPath: fichier.path) else {
            throw XCTSkip("\(chemin) introuvable : \(fichier.path)")
        }
        return try String(contentsOf: fichier, encoding: .utf8)
    }

    private func creneaux(_ mission: Mission) throws -> [CreneauConfirme] {
        try XCTUnwrap(CreneauxConfirmes.pourAction(PlanningCandidatInput(mission: mission)))
    }

    // MARK: - Câblage (garde anti-oubli du lot 4, `LOT4_PLAN.md` §2.2)

    func testMondeDemoCableLaSerie() async {
        let gateways = DemoWorld.gateways()
        XCTAssertTrue(gateways.serie is DemoSerieGateway)
        XCTAssertFalse(gateways.unwiredPorts.contains("serie"))
        XCTAssertFalse(DemoWorldTests.portsEnAttenteLot4.contains("serie"), "port livré avec son écran, jamais en attente")
        XCTAssertEqual(Lot4PortsTests.portsLot4.last, "serie", "quatorzième champ du bloc lot 4, après `exclusions`")

        // Stub par défaut : refus explicite qui cite la tranche et le plan.
        let nu = Gateways(auth: DemoAuthGateway(), role: DemoRoleGateway(), missions: DemoMissionsGateway())
        XCTAssertTrue(nu.serie is UnwiredPort)
        XCTAssertEqual(nu.unwiredPorts.last, "serie")
        for appel in [{ _ = try await nu.serie.missions(serieId: Self.pack, context: self.c) },
                      { _ = try await nu.serie.accepter(missionId: "m", creneaux: [], context: self.c) }] as [() async throws -> Void] {
            do {
                try await appel()
                XCTFail("le stub doit refuser")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .contract)
                XCTAssertTrue(erreur.message.contains("tranche T12 du lot 4"), erreur.message)
                XCTAssertTrue(erreur.message.contains("LOT4_PLAN.md"), erreur.message)
            } catch {
                XCTFail("erreur inattendue : \(error)")
            }
        }
    }

    // MARK: - Fixture

    func testFixtureDeuxSeriesAuxIdentifiantsDuWeb() throws {
        let fichier = try DemoFixtures.loadSerie()
        XCTAssertEqual(fichier.fixedNow, DateHeureParis.isoUTC(DemoWorld.fixedNow))
        XCTAssertEqual(fichier.series.map(\.serieId), [Self.pack, Self.arret])
        for serie in fichier.series {
            // Forme écrite et relue par le web (`src/components/CarteSerie.tsx` l.27).
            XCTAssertNotNil(serie.serieId.range(of: #"^SERIE_[0-9]{10,15}_[a-z0-9]{4,8}$"#, options: .regularExpression), serie.serieId)
        }
        XCTAssertEqual(fichier.series[0].missions.count, 5, "plan §2.7 : cinq missions")
        XCTAssertEqual(fichier.series[0].missions.compactMap(\.reponse).map(\.code), ["CONFLIT_PLANNING"], "une refusée pour conflit")
        let scriptees = fichier.series[1].missions.compactMap(\.reponse)
        XCTAssertEqual(scriptees.count, 2)
        XCTAssertEqual(scriptees[0].choixRequis, true)
        XCTAssertEqual(scriptees[0].options, DemoCandidatureGateway.Textes.choixContrat, "options du serveur")
        XCTAssertEqual(scriptees[1].code, CandidatureOutcome.codeRefusCodeDuTravail)
        // Chaque mission de série existe dans le monde démo et n'y figure qu'une fois.
        let ids = fichier.series.flatMap(\.missions).map(\.missionId)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    /// HARD STOP n°4 : les refus scriptés sont des messages du serveur, au format exact du dump, jamais rédigés ici.
    func testRefusScriptesAuFormatDuDump() throws {
        let dump = try Self.depot("supabase/schema/public.sql")
        let reponses = try DemoFixtures.loadSerie().series.flatMap(\.missions).compactMap(\.reponse)

        // Trigger `dec_verifier_repos_11h` : gabarit de l'exception, valeurs `%` remplacées.
        let gabarit = "[CODE DU TRAVAIL] Repos insuffisant % mission : % heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée."
        XCTAssertTrue(dump.contains("'\(gabarit)'"), "gabarit du trigger absent du dump")
        let conformite = try XCTUnwrap(reponses.first { $0.code == CandidatureOutcome.codeRefusCodeDuTravail }?.error)
        let motif = "^" + NSRegularExpression.escapedPattern(for: gabarit)
            .replacingOccurrences(of: "% mission", with: "(avant|apres) mission")
            .replacingOccurrences(of: "% heures", with: "[0-9]+\\.[0-9] heures") + "$"
        XCTAssertNotNil(conformite.range(of: motif, options: .regularExpression), conformite)

        // `fn_conflit_planning_soignant` : message de chevauchement, code posé par `fn_confirmer_action_planning_v1`.
        for fragment in ["'message', 'Tu es déjà confirmé(e) sur « ' || v_conflit.intitule ||", "'. Ce créneau chevauche la mission.'",
                         "'code', COALESCE(v_conflit->>'code', 'CONFLIT_PLANNING'),", "'DD/MM HH24hMI'"] {
            XCTAssertTrue(dump.contains(fragment), "« \(fragment) » absent du dump")
        }
        let conflit = try XCTUnwrap(reponses.first { $0.code == "CONFLIT_PLANNING" }?.error)
        XCTAssertNotNil(conflit.range(of: #"^Tu es déjà confirmé\(e\) sur « .+ » le [0-9]{2}/[0-9]{2} [0-9]{2}h[0-9]{2}–[0-9]{2}/[0-9]{2} [0-9]{2}h[0-9]{2}\. Ce créneau chevauche la mission\.$"#,
                                      options: .regularExpression), conflit)

        // `fn_resoudre_contrat_mission` : `{choix_requis, error, options}`.
        XCTAssertTrue(dump.contains("'Choisissez votre mode de contrat.'"))
        XCTAssertEqual(reponses.first { $0.choixRequis == true }?.error, "Choisissez votre mode de contrat.")
    }

    // MARK: - Lecture

    func testLectureOrdonneeEtSerieInconnue() async throws {
        let serie = DemoWorld.gateways().serie
        let pack = try await serie.missions(serieId: Self.pack, context: c)
        XCTAssertEqual(pack.map(\.id), ["demo-mission-001", "demo-mission-010", "demo-mission-013", "demo-mission-025", "demo-mission-028"])
        XCTAssertEqual(pack.map(\.record.debutLe), pack.map(\.record.debutLe).sorted(), "ordre `debut_le` croissant")
        XCTAssertTrue(pack.allSatisfy { $0.record.statut == "OUVERTE" && $0.planningExact && $0.etablissement?.id == "demo-etab-1" })
        let inconnue = try await serie.missions(serieId: "SERIE_1793577600000_absent", context: c)
        XCTAssertEqual(inconnue, [], "série inconnue : aucune mission, jamais une erreur")
        let arret = try await serie.missions(serieId: Self.arret, context: c)
        XCTAssertEqual(arret.map(\.record.statut), ["OUVERTE", "OUVERTE", "OUVERTE", "ASSIGNEE", "OUVERTE"])
        XCTAssertEqual(arret[3].record.soignantAssigneId, c.userId)
    }

    func testRefuseUnAutreUtilisateur() async {
        let serie = DemoWorld.gateways().serie
        var autre = c
        autre.userId = "autre"
        autre.profile.id = "autre"
        for appel in [{ _ = try await serie.missions(serieId: Self.pack, context: autre) },
                      { _ = try await serie.accepter(missionId: "demo-mission-001", creneaux: [], context: autre) }] as [() async throws -> Void] {
            do {
                try await appel()
                XCTFail("le monde démo refuse tout autre utilisateur")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .demoOnly)
            } catch {
                XCTFail("erreur inattendue : \(error)")
            }
        }
    }

    // MARK: - Acceptation

    func testAcceptationRelueDansLeMondeEtJamaisDeuxFois() async throws {
        let monde = DemoWorld.gateways()
        let pack = try await monde.serie.missions(serieId: Self.pack, context: c)
        let premiere = try XCTUnwrap(pack.first)
        let issue = try await monde.serie.accepter(missionId: premiere.id, creneaux: creneaux(premiere), context: c)
        XCTAssertEqual(issue, .confirmed(candidatureId: nil, contratId: "demo-contrat-demo-mission-001"))
        let relues = try await monde.serie.missions(serieId: Self.pack, context: c)
        XCTAssertEqual(relues.first?.record.statut, "ASSIGNEE")
        XCTAssertEqual(relues.first?.record.soignantAssigneId, c.userId)
        let seconde = try await monde.serie.accepter(missionId: premiere.id, creneaux: creneaux(premiere), context: c)
        XCTAssertEqual(seconde, .missionDejaAttribuee(message: DemoCandidatureGateway.Textes.missionIndisponible))
    }

    func testReponsesScripteesApresLesControlesDuServeur() async throws {
        let monde = DemoWorld.gateways()
        let pack = try await monde.serie.missions(serieId: Self.pack, context: c)
        let conflit = try XCTUnwrap(pack.first { $0.id == "demo-mission-013" })

        // Planning confirmé différent du planning servi : à reconfirmer, avant toute réponse scriptée.
        let autre = [CreneauConfirme(debut: "2026-11-15T08:00:00Z", fin: "2026-11-15T16:00:00Z")]
        let modifie = try await monde.serie.accepter(missionId: conflit.id, creneaux: autre, context: c)
        XCTAssertEqual(modifie, .planningAReconfirmer(code: DemoCandidatureGateway.codePlanningModifie,
                                                      message: DemoCandidatureGateway.Textes.planningModifie))

        let refus = try await monde.serie.accepter(missionId: conflit.id, creneaux: creneaux(conflit), context: c)
        guard case let .refusee(code, message, documents) = refus else { return XCTFail("refus attendu : \(refus)") }
        XCTAssertEqual(code, "CONFLIT_PLANNING")
        XCTAssertTrue(message.hasSuffix("Ce créneau chevauche la mission."))
        XCTAssertNil(documents)
        let relue = try await monde.missions.mission(id: conflit.id, context: c)
        XCTAssertEqual(relue?.record.statut, "OUVERTE", "refusée : jamais attribuée")

        let arret = try await monde.serie.missions(serieId: Self.arret, context: c)
        let choix = try await monde.serie.accepter(missionId: arret[0].id, creneaux: creneaux(arret[0]), context: c)
        XCTAssertEqual(choix, .choixRequis(DemoCandidatureGateway.Textes.choixContrat))
        let conformite = try await monde.serie.accepter(missionId: arret[2].id, creneaux: creneaux(arret[2]), context: c)
        guard case let .refusee(codeConformite, texte, _) = conformite else { return XCTFail("refus attendu : \(conformite)") }
        XCTAssertEqual(codeConformite, CandidatureOutcome.codeRefusCodeDuTravail)
        XCTAssertTrue(texte.hasPrefix("[CODE DU TRAVAIL] "), "texte du serveur restitué tel quel, marqueur compris")

        // Mission déjà pourvue de la série : refus du serveur, jamais une attribution.
        let pourvue = try await monde.serie.accepter(missionId: arret[3].id, creneaux: creneaux(arret[3]), context: c)
        XCTAssertEqual(pourvue, .missionDejaAttribuee(message: DemoCandidatureGateway.Textes.missionIndisponible))
    }
}
