import XCTest
@testable import JoleneCore

/// Port de `verifierPlanningExact` et `empreintePlanning` (`src/components/ListeCandidatures.tsx`
/// l.60-106) : le planning exact qu'un établissement confirme avant d'accepter une candidature
/// (lot 5, T3). Les fonctions web étant privées à un composant React, elles n'ont pas de vecteur
/// golden : chaque branche et les quatre cas planning de `ListeCandidatures.test.tsx` (l.72,
/// l.135, l.151, l.167) sont rejoués ici.
final class PlanningExactEtabTests: XCTestCase {
    private func prev(_ id: String?, _ debut: String, _ fin: String?, pause: Bool = false, type: String = "PREVISIONNEL") -> MissionSlot {
        MissionSlot(id: id, missionId: "mission-1", debut: debut, fin: fin, estPause: pause, typeCreneau: type)
    }

    /// Créneau de nuit des tests vitest (`ListeCandidatures.test.tsx` l.30-38).
    private var nuit: MissionSlot { prev("creneau-nuit", "2026-07-30T20:00:00+02:00", "2026-07-31T06:00:00+02:00") }

    // MARK: - Branches de verifierPlanningExact (l.65-97)

    func testPlanningIndisponible() {
        let verification = PlanningExactEtab.verifier([nuit], nbCreneauxAttendus: 1, indisponible: true)
        XCTAssertEqual(verification, PlanningExactEtab.Verification(creneaux: [], erreur: "Le planning détaillé est momentanément indisponible."))
        XCTAssertFalse(verification.exact)
    }

    func testNombreAttenduNonVerifiable() {
        for nombre in [nil, 0, -1] as [Int?] {
            XCTAssertEqual(PlanningExactEtab.verifier([nuit], nbCreneauxAttendus: nombre).erreur,
                           "Le nombre de créneaux contractuels doit être confirmé.", "nb_creneaux = \(String(describing: nombre))")
        }
    }

    func testPlanningIncompletAccordeLePluriel() {
        XCTAssertEqual(PlanningExactEtab.verifier([], nbCreneauxAttendus: 1).erreur,
                       "Planning incomplet : 1 créneau attendu, 0 chargé.")
        XCTAssertEqual(PlanningExactEtab.verifier([nuit], nbCreneauxAttendus: 2).erreur,
                       "Planning incomplet : 2 créneaux attendus, 1 chargé.")
        let deux = [nuit, prev("c2", "2026-07-31T20:00:00+02:00", "2026-08-01T06:00:00+02:00")]
        XCTAssertEqual(PlanningExactEtab.verifier(deux, nbCreneauxAttendus: 1).erreur,
                       "Planning incomplet : 1 créneau attendu, 2 chargés.")
    }

    func testPausesEtEffectifsNeComptentPas() {
        let lignes = [
            nuit,
            prev("pause", "2026-07-31T01:00:00+02:00", "2026-07-31T01:30:00+02:00", pause: true),
            prev("effectif", "2026-07-30T20:05:00+02:00", nil, type: "EFFECTIF"),
        ]
        let verification = PlanningExactEtab.verifier(lignes, nbCreneauxAttendus: 1)
        XCTAssertNil(verification.erreur)
        XCTAssertEqual(verification.creneaux, [nuit])
    }

    func testFinManquanteOuVide() {
        for fin in [nil, ""] as [String?] {
            XCTAssertEqual(PlanningExactEtab.verifier([prev("c", "2026-07-30T20:00:00+02:00", fin)], nbCreneauxAttendus: 1).erreur,
                           "Chaque créneau doit comporter une date et une heure de fin exactes.")
        }
    }

    func testFinNonPosterieureAuDebut() {
        for fin in ["2026-07-30T20:00:00+02:00", "2026-07-30T19:00:00+02:00"] {
            XCTAssertEqual(PlanningExactEtab.verifier([prev("c", "2026-07-30T20:00:00+02:00", fin)], nbCreneauxAttendus: 1).erreur,
                           "Le planning contient un créneau dont les horaires sont invalides.")
        }
    }

    func testDateIllisible() {
        XCTAssertEqual(PlanningExactEtab.verifier([prev("c", "pas une date", "2026-07-30T20:00:00+02:00")], nbCreneauxAttendus: 1).erreur,
                       "Le planning contient une date ou une heure invalide.")
        XCTAssertEqual(PlanningExactEtab.verifier([prev("c", "2026-07-30T20:00:00+02:00", "demain")], nbCreneauxAttendus: 1).erreur,
                       "Le planning contient une date ou une heure invalide.")
    }

    func testPremierCreneauFautifDansLOrdreDuPlanning() {
        // `some` s'arrête au premier créneau fautif, dans l'ordre de début.
        let inverse = prev("inverse", "2026-07-30T08:00:00+02:00", "2026-07-30T07:00:00+02:00")
        let illisible = prev("illisible", "2026-07-31T08:00:00+02:00", "demain")
        XCTAssertEqual(PlanningExactEtab.verifier([illisible, inverse], nbCreneauxAttendus: 2).erreur,
                       "Le planning contient un créneau dont les horaires sont invalides.")
    }

    func testPlanningExactTrieParDebutDeFaconStable() {
        let b = prev("b", "2026-07-31T08:00:00+02:00", "2026-07-31T12:00:00+02:00")
        let a = prev("a", "2026-07-31T08:00:00+02:00", "2026-07-31T16:00:00+02:00")
        let veille = prev("v", "2026-07-30T08:00:00+02:00", "2026-07-30T16:00:00+02:00")
        let verification = PlanningExactEtab.verifier([b, a, veille], nbCreneauxAttendus: 3)
        XCTAssertNil(verification.erreur)
        XCTAssertEqual(verification.creneaux.map(\.id), ["v", "b", "a"], "à début égal, l'ordre serveur (debut, id) est conservé")
    }

    // MARK: - Cas planning de ListeCandidatures.test.tsx

    /// l.72 : le planning exact est relu puis renvoyé tel quel dans `p_creneaux_confirmes`.
    func testVitestPlanningExactEnvoyeTelQuel() throws {
        let verification = PlanningExactEtab.verifier([nuit], nbCreneauxAttendus: 1)
        XCTAssertNil(verification.erreur)
        XCTAssertEqual(PlanningExactEtab.dureeTotaleHeures(verification.creneaux), 10)
        XCTAssertEqual(PlanningExactEtab.creneauxConfirmes(verification),
                       [CreneauConfirme(debut: "2026-07-30T20:00:00+02:00", fin: "2026-07-31T06:00:00+02:00")])
    }

    /// l.135 : planning vide → acceptation bloquée.
    func testVitestPlanningVideBloque() {
        let verification = PlanningExactEtab.verifier([], nbCreneauxAttendus: 1)
        XCTAssertNotNil(verification.erreur)
        XCTAssertNil(PlanningExactEtab.creneauxConfirmes(verification))
    }

    /// l.151 : liste partielle par rapport au nombre contractuel.
    func testVitestListePartielleBloquee() throws {
        let erreur = try XCTUnwrap(PlanningExactEtab.verifier([nuit], nbCreneauxAttendus: 2).erreur)
        XCTAssertTrue(erreur.contains("2 créneaux attendus, 1 chargé"))
    }

    /// l.167 : planning modifié dans la boîte de dialogue → nouvelle confirmation, aucun envoi.
    func testVitestPlanningModifieExigeUneNouvelleConfirmation() {
        let ouverture = PlanningExactEtab.verifier([nuit], nbCreneauxAttendus: 1).creneaux
        var modifie = nuit
        modifie.debut = "2026-07-30T21:00:00+02:00"
        modifie.fin = "2026-07-31T07:00:00+02:00"
        let relu = PlanningExactEtab.verifier([modifie], nbCreneauxAttendus: 1).creneaux
        XCTAssertFalse(PlanningExactEtab.memeEmpreinte(relu, ouverture))
        XCTAssertTrue(PlanningExactEtab.memeEmpreinte(relu, PlanningExactEtab.verifier([modifie], nbCreneauxAttendus: 1).creneaux))
        XCTAssertEqual(PlanningExactEtab.messagePlanningModifie,
                       "Le planning a changé depuis l’ouverture. Vérifiez les nouveaux horaires puis confirmez de nouveau.")
    }

    // MARK: - Empreinte (l.100-106) et écho exact (D26)

    func testEmpreinteIdDebutFinEnEgaliteStricte() {
        let sansId = prev(nil, "2026-07-30T20:00:00+02:00", "2026-07-31T06:00:00+02:00")
        XCTAssertEqual(PlanningExactEtab.empreinte([sansId, nuit]), [
            PlanningExactEtab.Empreinte(id: nil, debut: "2026-07-30T20:00:00+02:00", fin: "2026-07-31T06:00:00+02:00"),
            PlanningExactEtab.Empreinte(id: "creneau-nuit", debut: "2026-07-30T20:00:00+02:00", fin: "2026-07-31T06:00:00+02:00"),
        ])
        // Même instant, chaîne différente : le web compare des chaînes (`JSON.stringify`).
        let memeInstant = prev("creneau-nuit", "2026-07-30T18:00:00+00:00", "2026-07-31T04:00:00+00:00")
        XCTAssertFalse(PlanningExactEtab.memeEmpreinte([memeInstant], [nuit]))
        var autreId = nuit
        autreId.id = "autre"
        XCTAssertFalse(PlanningExactEtab.memeEmpreinte([autreId], [nuit]))
        XCTAssertFalse(PlanningExactEtab.memeEmpreinte([nuit, nuit], [nuit]))
    }

    func testEchoConserveMicrosecondesEtDecalage() {
        // Le serveur compare des instants à la microseconde (`::timestamptz`) : l'établissement
        // renvoie les chaînes lues, jamais une conversion par `Date` (D26, écart assumé avec
        // `CreneauxConfirmes.pourAction` du lot 1, qui refuse une fraction non nulle).
        let precis = prev("p", "2026-07-30T20:00:00.123456+02:00", "2026-07-31T06:00:00.654321+02:00")
        let verification = PlanningExactEtab.verifier([precis], nbCreneauxAttendus: 1)
        XCTAssertEqual(PlanningExactEtab.creneauxConfirmes(verification),
                       [CreneauConfirme(debut: "2026-07-30T20:00:00.123456+02:00", fin: "2026-07-31T06:00:00.654321+02:00")])
        let payload: [CreneauConfirmePayload]? = PlanningExactEtab.creneauxConfirmes(verification)
        XCTAssertEqual(payload?.count, 1)
    }

    func testDureeTotaleDeriveeDesInstantsServeur() {
        let creneaux = [
            prev("a", "2026-10-24T20:00:00+02:00", "2026-10-25T08:00:00+01:00"), // nuit de l'heure d'hiver : 13 h
            prev("b", "2026-07-31T08:00:00+02:00", "2026-07-31T12:30:00+02:00"),
        ]
        XCTAssertEqual(PlanningExactEtab.dureeTotaleHeures(creneaux), 17.5)
        XCTAssertEqual(PlanningExactEtab.dureeTotaleHeures([prev("x", "2026-07-31T12:00:00+02:00", "2026-07-31T08:00:00+02:00")]), 0,
                       "Math.max(0, …) : une durée négative ne retranche rien")
    }

    // MARK: - Garde de dérive des messages repris du web

    func testMessagesVerbatimDuWeb() throws {
        try SourceWebLot5.verifier("src/components/ListeCandidatures.tsx", contient: [
            PlanningExactEtab.messageIndisponible,
            PlanningExactEtab.messageNombreNonConfirme,
            PlanningExactEtab.messageFinManquante,
            PlanningExactEtab.messageHorairesInvalides,
            PlanningExactEtab.messageDateInvalide,
            PlanningExactEtab.messagePlanningModifie,
            PlanningExactEtab.messageAConfirmer,
            PlanningExactEtab.titreBandeauAConfirmer,
            PlanningExactEtab.detailBandeauAConfirmer,
            "`Planning incomplet : ${attendus} créneau${attendus > 1 ? 'x' : ''} attendu${attendus > 1 ? 's' : ''}, ${planifies.length} chargé${planifies.length > 1 ? 's' : ''}.`",
        ])
    }
}
