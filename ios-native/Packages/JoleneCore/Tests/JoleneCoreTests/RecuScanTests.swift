import XCTest
@testable import JoleneCore

/// Reçu durable d'un scan de pointage (blueprint lot 2 §2.5-§2.6, PRINCIPES §4, décision 2) :
/// transitions pures, fail-closed. Aucun code saisi, aucune coordonnée, aucun jeton dans le reçu ;
/// jamais de renvoi automatique : seule la relecture de `scans_pointage` tranche.
final class RecuScanTests: XCTestCase {
    private let userId = "0b4d2b8e-4a9f-4b1c-9e0a-7f3c1d2e5a66"
    private let terminal = "TERM_IOS_ABCDEFGHIJKLMNOPQRST"
    private let tentative = "6f1c2c1e-4c1a-4f55-9a0e-2b7b1d9e8a01"
    private let t0 = Date(timeIntervalSince1970: 1_793_577_600)

    private func prepare(preuves: [String] = ["s-2", "s-1"], existant: RecuScan? = nil,
                         gps: RecuScan.Gps = .disponible) throws -> RecuScan {
        try RecuScan.preparer(userId: userId, epoch: 3, missionId: "m-1", terminalId: terminal, typeAttendu: .ouverture,
                              nbScansAvant: 2, preuvesAvant: preuves, gps: gps, attemptId: tentative, existant: existant)
    }

    private func erreur(_ operation: () throws -> Void) -> RecuErreur? {
        do {
            try operation()
            return nil
        } catch let error as RecuErreur {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
            return nil
        }
    }

    // MARK: - Préparation

    func testPreparerPoseLaBaselineTrieeSansDoublon() throws {
        let recu = try prepare(preuves: ["s-3", "s-1", "s-3", "s-2"])
        XCTAssertEqual(recu.phase, .prepared)
        XCTAssertEqual(recu.version, 1)
        XCTAssertEqual(recu.preuvesAvant, ["s-1", "s-2", "s-3"], "ids triés, dédoublonnés")
        XCTAssertEqual(recu.nbScansAvant, 2)
        XCTAssertEqual(recu.typeAttendu, .ouverture)
        XCTAssertEqual(recu.terminalId, terminal)
        XCTAssertEqual(recu.attemptId, tentative)
        XCTAssertNil(recu.sqlstate)
        XCTAssertNil(recu.demarreLe)
        XCTAssertFalse(recu.estTermine)
    }

    func testIdentifiantDeTentativeAleatoireParDefaut() throws {
        let a = try RecuScan.preparer(userId: userId, epoch: 1, missionId: "m-1", terminalId: terminal, typeAttendu: .fermeture,
                                      nbScansAvant: 1, preuvesAvant: [], gps: .nonDemande)
        let b = try RecuScan.preparer(userId: userId, epoch: 1, missionId: "m-1", terminalId: terminal, typeAttendu: .fermeture,
                                      nbScansAvant: 1, preuvesAvant: [], gps: .nonDemande)
        XCTAssertNotNil(UUID(uuidString: a.attemptId))
        XCTAssertNotEqual(a.attemptId, b.attemptId)
    }

    func testBornesDuRecu() {
        let mille = (1...1_000).map { "s-\($0)" }
        XCTAssertNoThrow(try prepare(preuves: mille), "1 000 preuves : borne incluse")
        XCTAssertEqual(erreur { _ = try self.prepare(preuves: mille + ["s-1001"]) }, .borneDepassee)
        XCTAssertEqual(erreur { _ = try self.prepare(preuves: ["s-1", ""]) }, .champInvalide("preuvesAvant"))
        XCTAssertEqual(erreur { _ = try self.prepare(preuves: ["s 1"]) }, .champInvalide("preuvesAvant"))
        XCTAssertEqual(erreur {
            _ = try RecuScan.preparer(userId: self.userId, epoch: 1, missionId: "m-1", terminalId: "TERM IOS", typeAttendu: .ouverture,
                                      nbScansAvant: 0, preuvesAvant: [], gps: .nonDemande)
        }, .champInvalide("terminalId"))
        XCTAssertEqual(erreur {
            _ = try RecuScan.preparer(userId: "", epoch: 1, missionId: "m-1", terminalId: self.terminal, typeAttendu: .ouverture,
                                      nbScansAvant: 0, preuvesAvant: [], gps: .nonDemande)
        }, .champInvalide("userId"))
        XCTAssertEqual(erreur {
            _ = try RecuScan.preparer(userId: self.userId, epoch: 1, missionId: " ", terminalId: self.terminal, typeAttendu: .ouverture,
                                      nbScansAvant: 0, preuvesAvant: [], gps: .nonDemande)
        }, .champInvalide("missionId"))
        XCTAssertEqual(erreur {
            _ = try RecuScan.preparer(userId: self.userId, epoch: -1, missionId: "m-1", terminalId: self.terminal, typeAttendu: .ouverture,
                                      nbScansAvant: -1, preuvesAvant: [], gps: .nonDemande)
        }, .champInvalide("epoch"))
        XCTAssertEqual(erreur {
            _ = try RecuScan.preparer(userId: self.userId, epoch: 1, missionId: "m-1", terminalId: self.terminal, typeAttendu: .ouverture,
                                      nbScansAvant: 0, preuvesAvant: [], gps: .nonDemande, attemptId: "pas-un-uuid")
        }, .champInvalide("attemptId"))
    }

    func testUnSecondRecuEstRefuseTantQueLePremierNEstPasReconcilie() throws {
        // Pilote `attemptJournal.ts` l.70-72 : « Un autre pointage doit être réconcilié avant de continuer. »
        let enCours = try prepare()
        XCTAssertEqual(erreur { _ = try self.prepare(existant: enCours) }, .recuEnCours)
        let demarre = try enCours.demarrer(le: t0)
        XCTAssertEqual(erreur { _ = try self.prepare(existant: demarre) }, .recuEnCours)
        XCTAssertEqual(RecuScan.messageRecuEnCours, "Un autre pointage doit être réconcilié avant de continuer.")
        // Un reçu terminé (refusé, non envoyé) ne bloque pas : le journal le remplace.
        XCTAssertNoThrow(try prepare(existant: try demarre.refuser(sqlstate: "P0002")))
        XCTAssertNoThrow(try prepare(existant: try enCours.marquerNonEnvoye()))
        // Le journal est tenu par utilisateur : un reçu d'un autre compte ici est une corruption.
        var autre = enCours
        autre.userId = "autre"
        XCTAssertEqual(erreur { _ = try self.prepare(existant: autre) }, .utilisateurDifferent)
    }

    // MARK: - Transitions

    func testParcoursNominalPreparedStarted() throws {
        let demarre = try prepare().demarrer(le: t0)
        XCTAssertEqual(demarre.phase, .started)
        XCTAssertEqual(demarre.demarreLe, t0)
        XCTAssertFalse(demarre.estTermine)
    }

    func testTransitionsInterdites() throws {
        let prepare = try prepare()
        let demarre = try prepare.demarrer(le: t0)
        XCTAssertEqual(erreur { _ = try demarre.demarrer(le: self.t0) }, .transitionInterdite(de: "started", vers: "started"),
                       "jamais revenir de started vers un second envoi")
        XCTAssertEqual(erreur { _ = try prepare.refuser(sqlstate: "P0002") }, .transitionInterdite(de: "prepared", vers: "refused"),
                       "un refus suppose un envoi")
        XCTAssertEqual(erreur { _ = try demarre.marquerNonEnvoye() }, .transitionInterdite(de: "started", vers: "not_sent"),
                       "après l'envoi, seule la relecture prouve l'absence")
        let refuse = try demarre.refuser(sqlstate: "23514")
        XCTAssertEqual(refuse.phase, .refused)
        XCTAssertEqual(refuse.sqlstate, "23514")
        XCTAssertTrue(refuse.estTermine)
        XCTAssertEqual(erreur { _ = try refuse.demarrer(le: self.t0) }, .transitionInterdite(de: "refused", vers: "started"))
        let horsLigne = try prepare.marquerNonEnvoye()
        XCTAssertEqual(horsLigne.phase, .notSent)
        XCTAssertTrue(horsLigne.estTermine)
        XCTAssertEqual(erreur { _ = try horsLigne.demarrer(le: self.t0) }, .transitionInterdite(de: "not_sent", vers: "started"))
        XCTAssertEqual(erreur { _ = try demarre.refuser(sqlstate: "") }, .champInvalide("sqlstate"))
    }

    // MARK: - Réconciliation (relecture de `scans_pointage`)

    func testPreuveHorsBaselineDuMemeTerminalEtDeLaMissionEstUnSucces() throws {
        // §2.5 : `scans_pointage` où mission_id = reçu, id ∉ baseline, id_terminal = reçu ; en plus,
        // numero_scan > nb_scans relu avant l'envoi (`numero_scan = COALESCE(nb_scans, 0) + 1`, public.sql l.55667).
        let recu = try prepare(preuves: ["s-1", "s-2"]).demarrer(le: t0)
        let scans = [
            PreuveScan(id: "s-2", missionId: "m-1", numeroScan: 2, typeScan: .fermeture, idTerminal: terminal),
            PreuveScan(id: "s-9", missionId: "m-1", numeroScan: 3, typeScan: .ouverture, idTerminal: "TERM_IOS_AUTREAUTREAUTREAUTRE"),
            PreuveScan(id: "s-3", missionId: "m-1", numeroScan: 3, typeScan: .ouverture, idTerminal: terminal),
        ]
        XCTAssertEqual(try recu.reconcilier(scans: scans, relueLe: t0.addingTimeInterval(1)),
                       .recu(PreuveScan(id: "s-3", missionId: "m-1", numeroScan: 3, typeScan: .ouverture, idTerminal: terminal)),
                       "seule une preuve absente de la baseline, du même terminal ET de la même mission prouve la réception")
    }

    func testUnScanDuMemeTerminalSurUneAutreMissionNeProuveRien() throws {
        // Revue fraîche de T1 : un scan du même appareil sur une autre mission du jour (hors baseline, celle-ci
        // n'étant relue que pour la mission du reçu) ne devient jamais un faux succès, même si la requête de
        // relecture oublie son filtre `mission_id`.
        let recu = try prepare(preuves: ["s-1", "s-2"]).demarrer(le: t0)
        let ailleurs = [
            PreuveScan(id: "x-1", missionId: "m-2", numeroScan: 3, typeScan: .ouverture, idTerminal: terminal),
            PreuveScan(id: "x-2", missionId: nil, numeroScan: 5, typeScan: .ouverture, idTerminal: terminal),
        ]
        XCTAssertEqual(try recu.reconcilier(scans: ailleurs, relueLe: t0.addingTimeInterval(1)), .aRelire)
        XCTAssertEqual(try recu.reconcilier(scans: ailleurs, relueLe: t0.addingTimeInterval(8)), .nonRecu,
                       "mission absente ou différente : aucune preuve")
    }

    func testUnePreuveAnterieureALEssaiNeProuveRien() throws {
        // nb_scans_avant = 2 : une ligne de numéro ≤ 2 hors baseline (baseline tronquée, ligne relue en retard)
        // précède l'envoi ; une ligne sans numéro ne prouve rien (fail-closed).
        let recu = try prepare(preuves: ["s-1"]).demarrer(le: t0)
        let anciennes = [
            PreuveScan(id: "s-2", missionId: "m-1", numeroScan: 2, typeScan: .fermeture, idTerminal: terminal),
            PreuveScan(id: "s-4", missionId: "m-1", numeroScan: nil, typeScan: .ouverture, idTerminal: terminal),
        ]
        XCTAssertEqual(try recu.reconcilier(scans: anciennes, relueLe: t0.addingTimeInterval(9)), .nonRecu)
    }

    func testAbsenceProuveeSeulementHuitSecondesApresLEnvoi() throws {
        // §2.5 (corrigé v2) : statement_timeout de `authenticated` (migration 20260720172000 l.6-7).
        let recu = try prepare(preuves: ["s-1"]).demarrer(le: t0)
        let scans = [PreuveScan(id: "s-1", missionId: "m-1", numeroScan: 1, typeScan: .ouverture, idTerminal: terminal)]
        XCTAssertEqual(try recu.reconcilier(scans: scans, relueLe: t0.addingTimeInterval(7.9)), .aRelire)
        XCTAssertEqual(try recu.reconcilier(scans: scans, relueLe: t0.addingTimeInterval(8)), .nonRecu)
        XCTAssertEqual(try recu.reconcilier(scans: [], relueLe: t0.addingTimeInterval(60)), .nonRecu)
        XCTAssertEqual(try recu.reconcilier(scans: [], relueLe: t0), .aRelire, "délai nul : relire")
        XCTAssertEqual(RecuScan.delaiAbsenceProuvee, 8)
    }

    func testHorlogeQuiReculeEstUnVerdictFailClosedExplicite() throws {
        // Revue fraîche de T1 : relecture datée AVANT le passage `started` (heure de l'appareil reculée) :
        // l'écoulement des 8 s n'est pas établi. Jamais `.nonRecu` (qui rouvrirait l'envoi), jamais un `.aRelire`
        // silencieux : verdict dédié, le reçu reste `started` (aucun nouveau scan).
        let recu = try prepare(preuves: ["s-1"]).demarrer(le: t0)
        XCTAssertEqual(try recu.reconcilier(scans: [], relueLe: t0.addingTimeInterval(-0.001)), .horlogeIncoherente)
        XCTAssertEqual(try recu.reconcilier(scans: [], relueLe: t0.addingTimeInterval(-86_400)), .horlogeIncoherente)
        let preuve = PreuveScan(id: "s-5", missionId: "m-1", numeroScan: 3, typeScan: .ouverture, idTerminal: terminal)
        XCTAssertEqual(try recu.reconcilier(scans: [preuve], relueLe: t0.addingTimeInterval(-60)), .recu(preuve),
                       "une preuve relue reste une preuve, quelle que soit l'horloge")
        XCTAssertEqual(recu.phase, .started)
    }

    func testChaqueVerdictAUneIssueDeScan() {
        // Revue fraîche de T1 (seconde passe) : `PointagePort.reconcilier` rend une `IssueScan` ; chaque verdict a la
        // sienne, et aucune ne rouvre l'envoi sans preuve. `.aRelire` : rien n'est prouvé, le reçu reste `started`
        // (`.incertain`, nouvelle relecture) ; `.horlogeIncoherente` : issue dédiée, jamais `.nonRecu` ni `.incertain`
        // (relecture en boucle).
        let preuve = PreuveScan(id: "s-9", missionId: "m-1", numeroScan: 4, typeScan: .fermeture, idTerminal: terminal)
        XCTAssertEqual(IssueScan(reconciliation: .recu(preuve)), .enregistre(typeScan: .fermeture, numeroScan: 4))
        XCTAssertEqual(IssueScan(reconciliation: .aRelire), .incertain)
        XCTAssertEqual(IssueScan(reconciliation: .nonRecu), .nonRecu)
        XCTAssertEqual(IssueScan(reconciliation: .horlogeIncoherente), .horlogeIncoherente)
        let sansNumero = PreuveScan(id: "s-9", missionId: "m-1", numeroScan: nil, typeScan: .fermeture, idTerminal: terminal)
        XCTAssertEqual(IssueScan(reconciliation: .recu(sansNumero)), .incertain, "une preuve sans numéro ne prouve rien")
    }

    func testReconcilierExigeUnRecuDemarre() throws {
        let prepare = try prepare()
        XCTAssertEqual(erreur { _ = try prepare.reconcilier(scans: [], relueLe: self.t0) },
                       .transitionInterdite(de: "prepared", vers: "reconciled"), "un reçu prepared n'a rien envoyé")
        var sansDate = try prepare.demarrer(le: t0)
        sansDate.demarreLe = nil
        XCTAssertEqual(erreur { _ = try sansDate.reconcilier(scans: [], relueLe: self.t0) }, .illisible, "fail-closed")
    }

    // MARK: - Encodage durable

    func testAucunCodeNiCoordonneeDansLeRecu() throws {
        let recu = try prepare().demarrer(le: t0)
        let labels = Mirror(reflecting: recu).children.compactMap(\.label).map { $0.lowercased() }
        for interdit in ["code", "otp", "latitude", "longitude", "hmac", "token", "jeton"] {
            XCTAssertFalse(labels.contains { $0.contains(interdit) }, "champ interdit : \(interdit)")
        }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try recu.encoder()) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["version", "user_id", "epoch", "attempt_id", "mission_id", "terminal_id", "type_attendu",
                                        "nb_scans_avant", "preuves_avant", "gps", "phase", "demarre_le"])
        XCTAssertEqual(json["phase"] as? String, "started")
        XCTAssertEqual(json["gps"] as? String, "available")
        XCTAssertEqual(json["type_attendu"] as? String, "OUVERTURE")
    }

    func testAllerRetourEtRelectureFailClosed() throws {
        let recu = try prepare(gps: .reduite).demarrer(le: t0)
        let data = try recu.encoder()
        XCTAssertEqual(try RecuScan.decoder(data, userId: userId), recu)
        XCTAssertEqual(erreur { _ = try RecuScan.decoder(data, userId: "autre") }, .utilisateurDifferent,
                       "un reçu n'est relu que par le même utilisateur")
        XCTAssertEqual(erreur { _ = try RecuScan.decoder(Data("{}".utf8), userId: self.userId) }, .illisible)
        XCTAssertEqual(erreur { _ = try RecuScan.decoder(Data("pas du json".utf8), userId: self.userId) }, .illisible)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["version"] = 2
        XCTAssertEqual(erreur { _ = try RecuScan.decoder(try JSONSerialization.data(withJSONObject: json), userId: self.userId) },
                       .illisible, "version inconnue")
        json["version"] = 1
        json["code_saisi"] = "123456"
        XCTAssertEqual(erreur { _ = try RecuScan.decoder(try JSONSerialization.data(withJSONObject: json), userId: self.userId) },
                       .illisible, "clé inattendue : jamais relue")
        json["code_saisi"] = nil
        json["phase"] = "terminé"
        XCTAssertEqual(erreur { _ = try RecuScan.decoder(try JSONSerialization.data(withJSONObject: json), userId: self.userId) },
                       .illisible)
        json["phase"] = "started"
        json["preuves_avant"] = ["s-2", "s-1"]
        XCTAssertEqual(erreur { _ = try RecuScan.decoder(try JSONSerialization.data(withJSONObject: json), userId: self.userId) },
                       .illisible, "baseline non triée : altérée")
        XCTAssertEqual(RecuScan.messageIllisible,
                       "Le suivi sécurisé du pointage ne peut pas être vérifié. Aucun nouveau scan ne peut être envoyé.")
    }

    func testEtatsGpsDuRecu() {
        XCTAssertEqual(RecuScan.Gps.allCases.map(\.rawValue), ["available", "denied", "unavailable", "reduced", "not_requested"])
        XCTAssertEqual(RecuScan.Gps(observation: .disponible(latitude: 1, longitude: 2, precisionM: 3)), .disponible)
        XCTAssertEqual(RecuScan.Gps(observation: .refusee), .refusee)
        XCTAssertEqual(RecuScan.Gps(observation: .indisponible), .indisponible)
        XCTAssertEqual(RecuScan.Gps(observation: .precisionReduite), .reduite)
        XCTAssertEqual(RecuScan.Gps(observation: nil), .nonDemande, "consentement absent ou refusé : position jamais demandée")
        XCTAssertEqual(RecuScan.domaine, "scan")
    }
}
