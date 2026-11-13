import XCTest
@testable import JoleneCore

/// Détail des présences d'une mission (lot 2, T5a) : port des dérivations et du rendu de
/// `src/pages/DetailPresencesMission.tsx` pour le soignant. Chaque rendu attendu est écrit comme le web l'afficherait
/// (fragments de `LibellesWeb.DetailPresences`, espaces du JSX, dates de Paris). Les créneaux EFFECTIF fermés font foi ;
/// `heures_reelles` du serveur n'existe pas dans le modèle ; la synthèse serveur absente masque la carte seule.
final class PresentationDetailPresencesTests: XCTestCase {
    /// 2026-11-02T00:00:00Z = lundi 2 novembre, 01h00 à Paris.
    private let maintenant = DemoWorld.fixedNow

    private func mission(statut: String = "TERMINEE", debut: String = "2026-10-30T07:00:00Z", fin: String = "2026-10-30T15:00:00Z",
                         duree: Double? = 8) -> MissionPresenceLue {
        MissionPresenceLue(id: "m-1", intitule: "Mission de test", service: "Urgences", debutLe: debut, finLe: fin, dureeHeures: duree,
                           statut: statut, etablissementId: "e-1")
    }

    private func slot(_ id: String, _ type: String, _ debut: String, _ fin: String?, pause: Bool = false) -> MissionSlot {
        MissionSlot(id: id, missionId: "m-1", debut: debut, fin: fin, estPause: pause, typeCreneau: type)
    }

    private func construire(_ mission: MissionPresenceLue, _ creneaux: [MissionSlot],
                            resume: ResumePresencesServeur? = ResumePresencesServeur(pointageEffectue: true),
                            presence: PresenceControlee? = nil) -> PresentationDetailPresences {
        PresentationDetailPresences.construire(mission: mission, creneaux: creneaux, resume: resume, presence: presence,
                                               maintenant: maintenant)
    }

    // MARK: - En-tête

    func testEnTeteUnCreneauTermineEtPlanningTermine() {
        let p = construire(mission(), [
            slot("prevu", "PREVISIONNEL", "2026-10-30T07:00:00Z", "2026-10-30T15:00:00Z"),
            slot("e-1", "EFFECTIF", "2026-10-30T07:10:00Z", "2026-10-30T15:00:00Z"),
        ])
        XCTAssertEqual(p.entete.intitule, "Mission de test")
        XCTAssertEqual(p.entete.service, "Urgences")
        XCTAssertEqual(p.entete.periode, "📅 ven. 30 oct. 2026 · 08:00 → 16:00")
        XCTAssertEqual(p.entete.heures, "⏱ 8h sur 1 créneau")
        XCTAssertEqual(p.entete.progression, "Progression : 1/1 créneau échu · planning terminé")
    }

    func testEnTetePlusieursDatesProchainCreneauEtPluriels() {
        let p = construire(mission(statut: "EN_COURS", debut: "2026-11-01T07:00:00Z", fin: "2026-11-03T15:30:00Z"), [
            slot("p1", "PREVISIONNEL", "2026-11-01T07:00:00Z", "2026-11-01T15:00:00Z"),
            slot("p2", "PREVISIONNEL", "2026-11-03T07:00:00Z", "2026-11-03T15:30:00Z"),
        ])
        XCTAssertEqual(p.entete.periode, "📅 2 dates planifiées · 1 nov. 2026 → 3 nov. 2026")
        XCTAssertEqual(p.entete.heures, "⏱ 16,5h sur 2 créneaux")
        XCTAssertEqual(p.entete.progression, "Progression : 1/2 créneaux échus · prochain : mar. 3 nov. 2026 · 08:00 → 16:30")
    }

    func testEnTeteSansCreneauPlanifieRepliSurLaMission() {
        // Mission de plus de 24 h sans PREVISIONNEL : aucun repli ponctuel (`ajouterRepliMissionPonctuelle`).
        let p = construire(mission(statut: "ASSIGNEE", debut: "2026-11-10T07:00:00Z", fin: "2026-11-14T15:00:00Z", duree: 104), [])
        XCTAssertEqual(p.entete.periode, "📅 10/11/2026 08:00 → 14/11/2026 16:00")
        XCTAssertEqual(p.entete.heures, "⏱ 104h prévues")
        XCTAssertEqual(p.entete.progression, "Planning détaillé à confirmer.")
        XCTAssertEqual(construire(mission(statut: "ASSIGNEE", debut: "2026-11-10T07:00:00Z", fin: "2026-11-14T15:00:00Z", duree: nil), [])
            .entete.heures, nil, "aucune durée prévue : ligne omise (le web écrirait « nullh prévues »)")
    }

    func testMissionPonctuelleSansPrevisionnelUtiliseSaPlage() {
        // Moins de 24 h : la plage de la mission devient le créneau planifié (l.165).
        let p = construire(mission(), [slot("e-1", "EFFECTIF", "2026-10-30T07:00:00Z", "2026-10-30T15:00:00Z")])
        XCTAssertEqual(p.entete.heures, "⏱ 8h sur 1 créneau")
        XCTAssertEqual(p.jours.first?.segments.first?.etiquette, "Créneau planifié 1 / 1")
    }

    func testMissionClotureeAvantLaFinDuPlanning() {
        let p = construire(mission(statut: "TERMINEE", debut: "2026-11-01T07:00:00Z", fin: "2026-11-03T15:00:00Z"), [
            slot("p1", "PREVISIONNEL", "2026-11-01T07:00:00Z", "2026-11-01T15:00:00Z"),
            slot("p2", "PREVISIONNEL", "2026-11-03T07:00:00Z", "2026-11-03T15:00:00Z"),
            slot("e-1", "EFFECTIF", "2026-11-01T07:00:00Z", "2026-11-01T15:00:00Z"),
        ])
        XCTAssertEqual(p.entete.progression, "Mission clôturée · 1/2 créneaux initialement prévus étaient échus")
        XCTAssertEqual(p.synthese?.cloture, LibellesWeb.DetailPresences.clotureAvantFin)
        XCTAssertNil(p.synthese?.bilan, "mission terminée sans segment ouvert : bilan finalisable")
        XCTAssertFalse(p.synthese?.alertes.contains(LibellesWeb.DetailPresences.alerteDeficit) ?? true,
                       "aucun déficit signalé pour une mission clôturée avant la fin du planning")
    }

    // MARK: - Synthèse

    func testSyntheseMasqueeSansReponseServeurResteRendu() {
        let p = construire(mission(), [slot("e-1", "EFFECTIF", "2026-10-30T07:00:00Z", "2026-10-30T15:00:00Z")], resume: nil)
        XCTAssertNil(p.synthese, "`{error}` ou réponse illisible : carte de synthèse masquée")
        XCTAssertEqual(p.jours.count, 1, "le reste de l'écran est rendu")
        XCTAssertEqual(p.titreSegments, "Détail des créneaux travaillés (1 segment)")
    }

    func testSyntheseHeuresRetardDepartAnticipePausesDistanceEtMethode() {
        let resume = ResumePresencesServeur(pointageEffectue: true, dureePauseMin: 45, distanceM: 512.4, alerteTeleportation: false,
                                            methodeArrivee: "CODE_ROTATIF", methodeDepart: "QR")
        let p = construire(mission(), [
            slot("prevu", "PREVISIONNEL", "2026-10-30T07:00:00Z", "2026-10-30T15:00:00Z"),
            slot("e-1", "EFFECTIF", "2026-10-30T07:12:30Z", "2026-10-30T11:00:00Z"),
            slot("e-2", "EFFECTIF", "2026-10-30T11:30:00Z", "2026-10-30T14:58:00Z"),
            slot("pause", "EFFECTIF", "2026-10-30T11:00:00Z", "2026-10-30T11:30:00Z", pause: true),
        ], resume: resume, presence: PresenceControlee(id: "pr-1", valideParEtablissement: false, heuresAjusteesLitige: 6.5))
        let synthese = p.synthese
        let valeurs = Dictionary(uniqueKeysWithValues: (synthese?.valeurs ?? []).map { ($0.titre, $0.valeur) })
        XCTAssertEqual(synthese?.valeurs.map(\.titre), ["Heures planifiées", "Heures réelles", "Heures retenues après litige", "Retard",
                                                        "Départ anticipé", "Pauses / interruptions", "Distance GPS", "Méthode"])
        XCTAssertEqual(valeurs["Heures planifiées"], "8h")
        // 3 h 47 min 30 s + 3 h 28 min = 435,5 min = 7,2583 h → « 7,26 » (deux décimales au plus).
        XCTAssertEqual(valeurs["Heures réelles"], "7,26h")
        XCTAssertEqual(valeurs["Heures retenues après litige"], "6,5h")
        XCTAssertEqual(valeurs["Retard"], "+12 min", "differenceInMinutes tronque 12 min 30 s")
        XCTAssertEqual(valeurs["Départ anticipé"], "-2 min")
        XCTAssertEqual(valeurs["Pauses / interruptions"], "30 min", "interruption calculée prioritaire sur `duree_pause_min`")
        XCTAssertEqual(valeurs["Distance GPS"], "512m")
        XCTAssertEqual(synthese?.valeurs.first { $0.titre == "Distance GPS" }?.ton, .alerte, "au-delà de 500 m")
        XCTAssertEqual(valeurs["Méthode"], "CODE_ROTATIF", "méthode d'arrivée d'abord (l.373)")
        XCTAssertEqual(synthese?.valeurs.first { $0.titre == "Heures réelles" }?.ton, .neutre, "7,26 h ≥ 90 % de 8 h")
        XCTAssertTrue(synthese?.alertes.isEmpty ?? false)
    }

    func testSyntheseDeficitAlerteTeleportationEtPauseServeur() {
        let resume = ResumePresencesServeur(pointageEffectue: true, dureePauseMin: 20, alerteTeleportation: true)
        let p = construire(mission(), [
            slot("prevu", "PREVISIONNEL", "2026-10-30T07:00:00Z", "2026-10-30T15:00:00Z"),
            slot("e-1", "EFFECTIF", "2026-10-30T07:00:00Z", "2026-10-30T13:00:00Z"),
        ], resume: resume)
        let synthese = p.synthese
        XCTAssertEqual(synthese?.valeurs.first { $0.titre == "Heures réelles" }?.ton, .alerte, "6 h < 90 % de 8 h")
        XCTAssertEqual(synthese?.valeurs.first { $0.titre == "Pauses / interruptions" }?.valeur, "20 min",
                       "aucune interruption calculée : `duree_pause_min` du serveur")
        XCTAssertEqual(synthese?.alertes, ["🚨 Alerte téléportation détectée", "⚠️ Heures réelles inférieures à 90% du planifié"])
        XCTAssertNil(synthese?.valeurs.first { $0.titre == "Méthode" }, "méthode absente : aucune valeur")
    }

    func testBilansNonDefinitifs() {
        // Segment ouvert.
        let ouvert = construire(mission(statut: "EN_COURS", debut: "2026-11-01T22:00:00Z", fin: "2026-11-02T06:00:00Z"), [
            slot("prevu", "PREVISIONNEL", "2026-11-01T22:00:00Z", "2026-11-02T06:00:00Z"),
            slot("e-1", "EFFECTIF", "2026-11-01T22:00:00Z", nil),
        ])
        XCTAssertEqual(ouvert.synthese?.bilan, "Bilan définitif après la fermeture du pointage en cours.")
        let segment = ouvert.jours.first?.segments.first
        XCTAssertEqual(segment?.depart, "⏳ En cours — départ non pointé")
        XCTAssertEqual(segment?.departPointe, false)
        XCTAssertNil(segment?.duree)
        XCTAssertEqual(segment?.validation, "Pointage en cours")
        XCTAssertEqual(segment?.tonValidation, .attention)

        // Créneau à venir, segment fermé : bilan après le dernier créneau (heure de Paris).
        let avant = construire(mission(statut: "EN_COURS", debut: "2026-11-01T22:00:00Z", fin: "2026-11-02T06:00:00Z"), [
            slot("prevu", "PREVISIONNEL", "2026-11-01T22:00:00Z", "2026-11-02T06:00:00Z"),
            slot("e-1", "EFFECTIF", "2026-11-01T22:00:00Z", "2026-11-01T23:30:00Z"),
        ])
        XCTAssertEqual(avant.synthese?.bilan,
                       "Bilan définitif après le dernier créneau, le 02/11/2026 à 07:00. Aucun déficit n’est signalé avant cette échéance.")
        XCTAssertEqual(avant.jours.first?.segments.first?.ecarts.map(\.texte), ["Bilan après l’échéance de 07:00"])
        XCTAssertEqual(avant.jours.first?.segments.first?.validation, "Mission en cours")

        // Aucun créneau planifié, mission en cours : bilan indisponible.
        let sansPlanning = construire(mission(statut: "EN_COURS", debut: "2026-11-01T07:00:00Z", fin: "2026-11-05T15:00:00Z"), [
            slot("e-1", "EFFECTIF", "2026-11-01T07:00:00Z", "2026-11-01T15:00:00Z"),
        ])
        XCTAssertEqual(sansPlanning.synthese?.bilan, "Bilan définitif indisponible tant que le planning détaillé n’est pas confirmé.")
        XCTAssertEqual(sansPlanning.jours.first?.segments.first?.sansHoraire, "Planning détaillé à confirmer.")
    }

    // MARK: - Créneaux travaillés

    func testSegmentsParJourAvecInterruptionEtRepriseCommeLeRendu() {
        let p = construire(mission(), [
            slot("prevu", "PREVISIONNEL", "2026-10-30T07:00:00Z", "2026-10-30T15:00:00Z"),
            slot("e-2", "EFFECTIF", "2026-10-30T12:30:00Z", "2026-10-30T15:00:00Z"),
            slot("e-1", "EFFECTIF", "2026-10-30T07:05:00Z", "2026-10-30T12:00:00Z"),
        ], presence: PresenceControlee(id: "pr-1", valideParEtablissement: true, valideLe: "2026-11-01T14:00:00Z"))
        XCTAssertEqual(p.titreSegments, "Détail des créneaux travaillés (2 segments)")
        XCTAssertEqual(p.jours.map(\.titre), ["📅 vendredi 30 octobre 2026"])
        let segments = p.jours[0].segments
        XCTAssertEqual(segments.map(\.id), ["e-1", "e-2"], "triés par début")
        XCTAssertEqual(segments[0].etiquette, "Segment travaillé 1 / 2 · créneau planifié 1/1")
        XCTAssertNil(segments[0].interruption)
        XCTAssertEqual(segments[0].horairePrevu, "ven. 30 oct. 2026 · 08:00 → 16:00")
        XCTAssertEqual(segments[0].ecarts.map(\.texte), ["Retard : +5 min"], "retard sur le premier segment associé seulement")
        XCTAssertEqual(segments[0].arrivee, "▶ Arrivée 30/10/2026 08:05:00")
        XCTAssertEqual(segments[0].depart, "■ Départ 30/10/2026 13:00:00")
        XCTAssertEqual(segments[0].duree, "Durée : 4h55")
        XCTAssertEqual(segments[0].validation, "✅ Validé le 01/11/2026 15:00")
        XCTAssertEqual(segments[0].ton, .succes)
        XCTAssertEqual(segments[1].etiquette, "Segment travaillé 2 / 2 · reprise après interruption · créneau planifié 1/1")
        XCTAssertEqual(segments[1].interruption, "Pause / interruption depuis le segment précédent : 0h30")
        XCTAssertEqual(segments[1].ecarts, [], "départ à l'heure : aucun départ anticipé")
        XCTAssertEqual(segments[1].duree, "Durée : 2h30")
    }

    func testSegmentSansCreneauDuJourEtJoursTries() {
        let p = construire(mission(statut: "TERMINEE", debut: "2026-10-28T07:00:00Z", fin: "2026-10-30T15:00:00Z"), [
            slot("prevu", "PREVISIONNEL", "2026-10-28T07:00:00Z", "2026-10-28T15:00:00Z"),
            slot("e-2", "EFFECTIF", "2026-10-30T07:00:00Z", "2026-10-30T15:00:00Z"),
            slot("e-1", "EFFECTIF", "2026-10-28T07:00:00Z", "2026-10-28T14:00:00Z"),
        ])
        XCTAssertEqual(p.jours.map(\.titre), ["📅 mercredi 28 octobre 2026", "📅 vendredi 30 octobre 2026"])
        XCTAssertEqual(p.jours[0].segments[0].etiquette, "Créneau planifié 1 / 1")
        XCTAssertEqual(p.jours[0].segments[0].ecarts.map(\.texte), ["Départ anticipé : -60 min"])
        XCTAssertNil(p.jours[1].segments[0].etiquette, "un seul segment, aucun créneau associé")
        XCTAssertEqual(p.jours[1].segments[0].sansHoraire, "Aucun créneau planifié ne correspond à ce jour.")
        XCTAssertEqual(p.jours[1].segments[0].validation, "✅ Relevé clôturé", "mission terminée sans présence")
    }

    func testAucunSegmentEnregistre() {
        let p = construire(mission(statut: "ASSIGNEE", debut: "2026-11-03T07:00:00Z", fin: "2026-11-03T15:00:00Z"),
                           [slot("prevu", "PREVISIONNEL", "2026-11-03T07:00:00Z", "2026-11-03T15:00:00Z")], resume: nil)
        XCTAssertEqual(p.titreSegments, "Détail des créneaux travaillés (0 segment)")
        XCTAssertTrue(p.jours.isEmpty)
    }

    func testStatutsDeValidationEtTonsDesSegments() {
        let creneaux = [
            slot("prevu", "PREVISIONNEL", "2026-10-30T07:00:00Z", "2026-10-30T15:00:00Z"),
            slot("e-1", "EFFECTIF", "2026-10-30T07:00:00Z", "2026-10-30T15:00:00Z"),
        ]
        let enAttente = construire(mission(statut: "EN_COURS"), creneaux, presence: PresenceControlee(id: "pr", valideParEtablissement: false))
        XCTAssertEqual(enAttente.jours[0].segments[0].validation, "⏳ En attente de validation")
        XCTAssertTrue(enAttente.relanceProposee, "présence non validée et validation possible (l.249-254)")

        let arbitrage = construire(mission(), creneaux, presence: PresenceControlee(id: "pr", heuresAjusteesLitige: 7))
        XCTAssertEqual(arbitrage.jours[0].segments[0].validation, "✅ Relevé clôturé après arbitrage")

        let teleportation = construire(mission(), creneaux, presence: PresenceControlee(id: "pr", valideParEtablissement: true,
                                                                                       alerteTeleportation: true))
        XCTAssertEqual(teleportation.jours[0].segments[0].ton, .alerte)
        XCTAssertEqual(teleportation.jours[0].segments[0].validation, "✅ Validé", "validée sans date : « le … » omis")

        let horsPerimetre = construire(mission(), creneaux, presence: PresenceControlee(id: "pr", distanceEtablissementM: 320,
                                                                                       perimetreGpsValide: false))
        XCTAssertEqual(horsPerimetre.jours[0].segments[0].ton, .attention)
        let sansMesure = construire(mission(), creneaux, presence: PresenceControlee(id: "pr", perimetreGpsValide: false))
        XCTAssertEqual(sansMesure.jours[0].segments[0].ton, .neutre, "périmètre faux sans distance mesurée : bordure neutre")
    }

    // MARK: - Relance et contrôles

    func testRelanceSeulementPourUnePresenceNonValideeQuandLaValidationEstPossible() {
        let fermes = [
            slot("prevu", "PREVISIONNEL", "2026-10-30T07:00:00Z", "2026-10-30T15:00:00Z"),
            slot("e-1", "EFFECTIF", "2026-10-30T07:00:00Z", "2026-10-30T15:00:00Z"),
        ]
        XCTAssertFalse(construire(mission(), fermes).relanceProposee, "aucune présence : rien à relancer")
        XCTAssertFalse(construire(mission(), fermes, presence: PresenceControlee(id: "pr", valideParEtablissement: true)).relanceProposee)
        let enCours = [
            slot("prevu", "PREVISIONNEL", "2026-11-01T22:00:00Z", "2026-11-02T06:00:00Z"),
            slot("e-1", "EFFECTIF", "2026-11-01T22:00:00Z", nil),
        ]
        XCTAssertFalse(construire(mission(statut: "EN_COURS"), enCours, presence: PresenceControlee(id: "pr")).relanceProposee,
                       "planning non terminé, segment ouvert : validation impossible")
        XCTAssertTrue(construire(mission(), fermes, presence: PresenceControlee(id: "pr")).relanceProposee,
                      "`valide_par_etablissement` nul : non validée")
    }

    func testControlesDuPointage() throws {
        let presence = PresenceControlee(id: "pr", distanceEtablissementM: 42.6, perimetreGpsValide: true, arriveePrecisionGpsM: 12.4,
                                         departPrecisionGpsM: -1, alerteTeleportation: true)
        let controles = try XCTUnwrap(construire(mission(), [], presence: presence).controles)
        XCTAssertEqual(controles.lignes.map(\.texte), ["Première arrivée : 43m", "Précision première arrivée : 12m"],
                       "précision négative : mesure indisponible (`mesureGpsDisponible`)")
        XCTAssertEqual(controles.lignes.first?.ton, .succes)
        XCTAssertEqual(controles.lignes.first?.perimetre, true)
        XCTAssertTrue(controles.alerteTeleportation)
        XCTAssertNil(construire(mission(), []).controles, "aucune présence : pas de carte « Contrôles du pointage »")
        let vide = try XCTUnwrap(construire(mission(), [], presence: PresenceControlee(id: "pr")).controles)
        XCTAssertTrue(vide.lignes.isEmpty, "carte rendue avec son titre seul, comme le web")
    }

    // MARK: - Formats

    func testFormatDesHeuresCommeToLocaleStringFrFR() {
        XCTAssertEqual(LibellesDetailPresences.heures(8), "8")
        XCTAssertEqual(LibellesDetailPresences.heures(7.5), "7,5")
        XCTAssertEqual(LibellesDetailPresences.heures(7.125), "7,13")
        XCTAssertEqual(LibellesDetailPresences.heures(7.333_333), "7,33")
        XCTAssertEqual(LibellesDetailPresences.heures(0), "0")
        XCTAssertEqual(LibellesDetailPresences.heures(1234.5), "1\u{202F}234,5")
    }

    func testDifferenceEnMinutesTronqueeVersZero() throws {
        let a = try DateHeureParis.instantJolene("2026-10-30T07:12:59Z")
        let b = try DateHeureParis.instantJolene("2026-10-30T07:00:00Z")
        XCTAssertEqual(PresentationDetailPresences.minutes(a, b), 12)
        XCTAssertEqual(PresentationDetailPresences.minutes(b, a), -12)
    }
}
