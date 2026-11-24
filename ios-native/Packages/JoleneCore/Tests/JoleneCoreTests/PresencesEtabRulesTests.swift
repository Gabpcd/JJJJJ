import XCTest
@testable import JoleneCore

/// Présences de l'établissement (lot 5, T8) : décodage en liste blanche (jamais de position, de `coherence_incidents`
/// ni de durée servie), onglets dérivés de `SynthesePresence` et de l'horloge (`PresencesEtablissement.tsx` l.194-211),
/// missions terminées sans pointage, cartes (textes du web, aucune durée facturée), monde démo (M4 segment ouvert, M6 en
/// cours, M7 à valider, M8 hors zone, M11 sans pointage ; écritures relues, refus du serveur fictif mot pour mot).
final class PresencesEtabRulesTests: XCTestCase {
    private typealias R = PresencesEtabRules
    private typealias P = PresencesEtabPresentation
    private let maintenant = DemoWorld.fixedNow // 2026-11-02T00:00:00Z

    private func creneau(_ id: String, _ debut: String, _ fin: String?, type: String = "PREVISIONNEL", mission: String = "m-1") -> MissionSlot {
        MissionSlot(id: id, missionId: mission, debut: debut, fin: fin, estPause: false, typeCreneau: type)
    }

    private var planifie: MissionSlot { creneau("p-1", "2026-10-31T06:00:00Z", "2026-10-31T14:00:00Z") }
    private var pointe: MissionSlot { creneau("e-1", "2026-10-31T06:01:00Z", "2026-10-31T14:03:00Z", type: "EFFECTIF") }

    private func presence(_ id: String = "p-1", valide: Bool = false, perimetre: Bool? = true, teleportation: Bool? = false,
                          mock: Bool = false, creneaux: [MissionSlot]? = nil, nbCreneaux: Int? = 1, motif: String? = nil,
                          distance: Double? = 35) -> PresenceEtab {
        PresenceEtab(id: id, missionId: "m-1", valideParEtablissement: valide, valideLe: valide ? "2026-11-01T09:00:00Z" : nil,
                     motifLitige: motif, soignantId: "s-1", distanceEtablissementM: distance, perimetreGpsValide: perimetre,
                     alerteTeleportation: teleportation, arriveeMockDetected: mock, departMockDetected: false,
                     mission: MissionPresenceEtab(id: "m-1", intitule: "Nuit", service: "Urgences", debutLe: "2026-10-31T06:00:00Z",
                                                  finLe: "2026-10-31T14:00:00Z", nbCreneaux: nbCreneaux, etablissementId: "demo-etab-1"),
                     creneaux: creneaux ?? [planifie, pointe])
    }

    // MARK: - Décodage

    func testDecodageEnListeBlancheSansPositionNiDureeServie() throws {
        let json = #"""
        {"id":"p-1","mission_id":"m-1","soignant_id":"s-1","distance_etablissement_m":420.4,"perimetre_gps_valide":false,
         "alerte_teleportation":null,"arrivee_mock_detected":true,"depart_mock_detected":false,"valide_par_etablissement":null,
         "valide_le":null,"motif_litige":"Absent","arrivee_lat":48.86,"arrivee_lng":2.35,"coherence_incidents":["DUREE_TROP_COURTE"],
         "missions":{"id":"m-1","intitule":"Nuit","service":null,"debut_le":"2026-10-31T06:00:00Z","fin_le":"2026-10-31T14:00:00Z",
                     "duree_heures":8,"nb_creneaux":1,"etablissement_id":"e-1","total_brut":240}}
        """#
        let presence = try JSONDecoder().decode(PresenceEtab.self, from: Data(json.utf8))
        XCTAssertEqual(presence, PresenceEtab(
            id: "p-1", missionId: "m-1", valideParEtablissement: false, valideLe: nil, motifLitige: "Absent", soignantId: "s-1",
            distanceEtablissementM: 420.4, perimetreGpsValide: false, alerteTeleportation: nil, arriveeMockDetected: true,
            departMockDetected: false,
            mission: MissionPresenceEtab(id: "m-1", intitule: "Nuit", service: nil, debutLe: "2026-10-31T06:00:00Z",
                                         finLe: "2026-10-31T14:00:00Z", nbCreneaux: 1, etablissementId: "e-1")),
            "`valide_par_etablissement` nul vaut faux ; aucune clé hors liste n'est retenue")
        let cles = PresenceEtab.clesDecodees + MissionPresenceEtab.clesDecodees
        XCTAssertEqual(PresenceEtab.clesDecodees, ["id", "mission_id", "soignant_id", "distance_etablissement_m", "perimetre_gps_valide",
                                                   "alerte_teleportation", "arrivee_mock_detected", "depart_mock_detected",
                                                   "valide_par_etablissement", "valide_le", "motif_litige"])
        XCTAssertEqual(MissionPresenceEtab.clesDecodees, ["id", "intitule", "service", "debut_le", "fin_le", "nb_creneaux", "etablissement_id"])
        for interdite in ["arrivee_lat", "arrivee_lng", "depart_lat", "depart_lng", "coherence_incidents", "duree_heures",
                          "heures_reelles", "alertes_fraude", "total_brut", "net_a_payer", "taux_horaire_base"] {
            XCTAssertFalse(cles.contains(interdite), "\(interdite) n'est jamais lue")
        }
        XCTAssertThrowsError(try JSONDecoder().decode(PresenceEtab.self, from: Data(#"{"id":" ","mission_id":"m-1"}"#.utf8)))
    }

    // MARK: - Onglets

    func testOngletsDerivesDeLaSyntheseEtDeLHorloge() throws {
        let aValider = presence("a")
        let horsZone = presence("b", perimetre: false)
        let ouverte = presence("c", creneaux: [planifie, creneau("e-2", "2026-10-31T06:01:00Z", nil, type: "EFFECTIF")])
        let planningIncomplet = presence("d", nbCreneaux: 2)
        let validee = presence("e", valide: true, teleportation: true)
        let avantLaFin = presence("f", creneaux: [creneau("p-2", "2026-11-01T20:00:00Z", "2026-11-02T04:00:00Z"),
                                                  creneau("e-3", "2026-11-01T20:01:00Z", "2026-11-01T23:00:00Z", type: "EFFECTIF")])
        let repartition = R.repartir([aValider, horsZone, ouverte, planningIncomplet, validee, avantLaFin], maintenant: maintenant)
        XCTAssertEqual(repartition.aValider.map(\.id), ["a", "b"], "une présence en alerte reste à valider")
        XCTAssertEqual(repartition.enCours.map(\.id), ["c", "d", "f"], "pointage ouvert, planning non vérifiable, planning non terminé")
        XCTAssertEqual(repartition.validees.map(\.id), ["e"])
        XCTAssertEqual(repartition.alertes.map(\.id), ["b", "e"], "hors zone et téléportation, validée ou non")
        XCTAssertEqual(repartition.sansAlerte.map(\.id), ["a"], "lot : périmètre confirmé, aucune téléportation")
        XCTAssertEqual(repartition.presences(.aValider).count, 2)

        // La même présence devient validable quand l'horloge passe la fin du dernier créneau : rien n'est mémorisé.
        let plusTard = try DateHeureParis.instantJolene("2026-11-02T04:00:00Z")
        XCTAssertEqual(R.repartir([avantLaFin], maintenant: plusTard).aValider.map(\.id), ["f"])
        XCTAssertTrue(R.analyser(planningIncomplet, maintenant: maintenant).planningIndisponible)
        XCTAssertFalse(R.analyser(planningIncomplet, maintenant: maintenant).validationPossible)
        var sansMission = aValider
        sansMission.mission = nil
        XCTAssertFalse(R.analyser(sansMission, maintenant: maintenant).validationPossible, "mission illisible : jamais validable")
    }

    func testLotExclutPerimetreNonConfirmeEtTeleportation() {
        XCTAssertTrue(R.sansAlerte(presence()))
        XCTAssertFalse(R.sansAlerte(presence(perimetre: nil)), "périmètre non renseigné : hors lot, comme le serveur")
        XCTAssertFalse(R.sansAlerte(presence(perimetre: false)))
        XCTAssertFalse(R.sansAlerte(presence(teleportation: true)))
        XCTAssertTrue(R.sansAlerte(presence(teleportation: nil)))
        XCTAssertFalse(R.aAlerte(presence(perimetre: nil)), "non renseigné n'est pas une alerte (web l.206)")
        XCTAssertEqual(R.alertes(presence(perimetre: false, teleportation: true, mock: true)), [.teleportation, .horsZone, .gpsTruque])
        XCTAssertEqual(R.Alerte.allCases.map(\.rawValue), ["teleportation", "hors_zone", "gps_truque"])
        XCTAssertEqual(OngletPresencesEtab.allCases.map(\.rawValue), ["a_valider", "en_cours", "validees", "alertes"])
        XCTAssertEqual(OngletPresencesEtab(parametre: "alertes"), .alertes)
        XCTAssertEqual(OngletPresencesEtab(parametre: "inconnu"), .aValider)
        XCTAssertEqual(OngletPresencesEtab(parametre: nil), .aValider)
    }

    func testMissionsTermineesSansPointage() {
        let terminees = [EtabMissionResume(id: "m-1", intitule: "Pointée"), EtabMissionResume(id: "m-9", intitule: "Sans pointage")]
        XCTAssertEqual(R.missionsSansPointage(terminees: terminees, presences: [presence()]).map(\.id), ["m-9"])
        XCTAssertEqual(R.missionsSansPointage(terminees: terminees, presences: []).map(\.id), ["m-1", "m-9"])
    }

    // MARK: - Cartes

    func testCarteAValiderTextesDuWebSansDureeFacturee() {
        let soignant = SoignantPourEtab(id: "s-1", prenom: "Camille", nom: "Démo", profession: "IDE")
        let carte = P.carte(presence(), soignant: soignant, maintenant: maintenant)
        XCTAssertEqual(carte.titre, "Camille Démo · Infirmier(ère) Diplômé(e) d'État (IDE)")
        XCTAssertEqual(carte.sousTitre, "Nuit · Urgences")
        XCTAssertEqual(carte.prevu, "Prévu · 1 créneau")
        XCTAssertEqual(carte.prevuDetail, "sam. 31 oct. 2026 · 07:00 → 15:00 · 8h00")
        XCTAssertEqual(carte.reel, "Réel · 1 segment terminé")
        XCTAssertEqual(carte.reelDetail, "8h02 travaillées")
        XCTAssertEqual(carte.reelPeriode, "Du 31/10/2026 07:01 au 31/10/2026 15:03")
        XCTAssertEqual(carte.statut, P.Badge("À valider", ton: .info))
        XCTAssertNil(carte.explication)
        XCTAssertTrue(carte.aValider)
        XCTAssertFalse(carte.segmentOuvert)
        XCTAssertEqual(carte.prenom, "Camille")
        XCTAssertTrue(carte.alertes.isEmpty && carte.detailsAlertes.isEmpty && carte.litige == nil)
        XCTAssertEqual(P.carte(presence(), soignant: nil, maintenant: maintenant).titre, "Soignant", "repli du web (l.430)")
        XCTAssertNil(P.carte(presence(), soignant: nil, maintenant: maintenant).prenom)
    }

    func testCarteAlertesLitigeEtValidee() {
        let alerte = P.carte(presence(perimetre: false, teleportation: true, mock: true, motif: " Absent ", distance: 420.5),
                             soignant: nil, maintenant: maintenant)
        XCTAssertEqual(alerte.alertes.map(\.cle), [.teleportation, .horsZone, .gpsTruque])
        XCTAssertEqual(alerte.alertes.map(\.badge.texte), ["Téléportation", "Hors zone", "GPS truqué"])
        XCTAssertEqual(alerte.detailsAlertes, ["Hors périmètre à l'arrivée (421m)", "Téléportation détectée"])
        XCTAssertEqual(alerte.litige, "⚠️ Litige : Absent")
        XCTAssertTrue(alerte.aValider, "contester et valider restent proposés pour une présence en alerte à valider")
        XCTAssertEqual(P.detailHorsPerimetre(nil), "Hors périmètre à l'arrivée (distance indisponible)")
        XCTAssertEqual(P.detailHorsPerimetre(-1), "Hors périmètre à l'arrivée (distance indisponible)")

        let validee = P.carte(presence(valide: true), soignant: nil, maintenant: maintenant)
        XCTAssertEqual(validee.statut, P.Badge("Validée", ton: .succes))
        XCTAssertFalse(validee.aValider)
        XCTAssertNil(validee.explication)
    }

    func testCarteEnCoursExplicationsDuWeb() throws {
        let ouvert = creneau("e-2", "2026-10-31T06:01:00Z", nil, type: "EFFECTIF")
        let segmentOuvert = P.carte(presence(creneaux: [planifie, ouvert]), soignant: nil, maintenant: maintenant)
        XCTAssertEqual(segmentOuvert.statut.texte, "En cours")
        XCTAssertTrue(segmentOuvert.segmentOuvert)
        XCTAssertEqual(segmentOuvert.reel, "Réel · 0 segment terminé")
        XCTAssertEqual(segmentOuvert.reelDetail, "0h00 travaillées · pointage ouvert")
        XCTAssertNil(segmentOuvert.reelPeriode)
        XCTAssertEqual(segmentOuvert.explication, P.explicationPointageOuvert)
        XCTAssertFalse(segmentOuvert.aValider)

        let incomplet = P.carte(presence(nbCreneaux: 2), soignant: nil, maintenant: maintenant)
        XCTAssertEqual(incomplet.explication, P.explicationPlanningIndisponible)

        let nuit = [creneau("p-2", "2026-11-01T20:00:00Z", "2026-11-02T04:00:00Z"),
                    creneau("e-3", "2026-11-01T20:01:00Z", "2026-11-01T23:00:00Z", type: "EFFECTIF")]
        let avantLaFin = P.carte(presence(creneaux: nuit), soignant: nil, maintenant: maintenant)
        XCTAssertEqual(avantLaFin.explication, "Mission en cours : validation après le dernier créneau, le 02/11/2026 à 05:00.")
        XCTAssertEqual(avantLaFin.prevuDetail, "dim. 1 nov. 2026 · 21:00 → lun. 2 nov. 2026 · 05:00 · 8h00")

        let jamaisPointe = P.carte(presence(creneaux: [planifie]), soignant: nil, maintenant: maintenant)
        XCTAssertEqual(jamaisPointe.explication, P.explicationAucunSegment)
        XCTAssertNil(jamaisPointe.reel)

        let sansPlanning = P.carte(presence(creneaux: [pointe], nbCreneaux: 1), soignant: nil, maintenant: maintenant)
        XCTAssertEqual(sansPlanning.prevu, "Prévu · 0 créneau")
        XCTAssertEqual(sansPlanning.prevuDetail, P.planningIndisponible)
    }

    func testLibellesDOngletsLotEtEtatsVides() {
        XCTAssertEqual(OngletPresencesEtab.allCases.map { P.libelle($0, nombre: 2) },
                       ["À valider (2)", "En cours (2)", "Validées (2)", "Alertes (2)"])
        XCTAssertEqual(P.lotResume(3), "3 présences à valider")
        XCTAssertEqual(P.lotBouton(1), "Tout valider (sans alerte) · 1 présences")
        XCTAssertEqual(P.lotTitre(2), "Valider 2 présences ?")
        XCTAssertEqual(P.lotConfirmer(2), "Valider 2 présences")
        XCTAssertEqual(P.lotResultat(validees: 1, selectionnees: 2), "1 présence validée sur 2 sélectionnées.")
        XCTAssertEqual(P.lotResultat(validees: 2, selectionnees: 2), "2 présences validées sur 2 sélectionnées.")
        XCTAssertEqual(P.lotResultat(validees: 0, selectionnees: 1), "0 présence validée sur 1 sélectionnée.")
        XCTAssertEqual(P.validationTitre(prenom: "Camille"), "Noter Camille pour valider")
        XCTAssertEqual(P.validationTitre(prenom: nil), "Noter le soignant pour valider")
        XCTAssertEqual(P.succesValidationNotee(4), "Présence validée et note 4/5 envoyée !")
        XCTAssertEqual((1...2).map(P.etoiles), ["1 étoile", "2 étoiles"])
        XCTAssertEqual(P.etatVide(.alertes, sansPointage: true).titre, "Aucune autre alerte")
        XCTAssertEqual(P.etatVide(.alertes, sansPointage: false).titre, "Aucune alerte")
        XCTAssertEqual(P.periodeSansPointage(EtabMissionResume(id: "m", intitule: "x", debutLe: "2026-10-27T06:00:00Z", finLe: "2026-10-27T14:00:00Z")),
                       "27/10/2026 07:00 → 27/10/2026 15:00")
        XCTAssertEqual(P.periodeSansPointage(EtabMissionResume(id: "m", intitule: "x")), "")
    }

    // MARK: - Garde de dérive des textes repris du web

    func testTextesVerbatimDuWeb() throws {
        try SourceWebLot5.verifier("src/pages/PresencesEtablissement.tsx", contient: [
            P.sousTitre, P.titreErreur, P.sansPointageTitre, P.sansPointageMessage, P.soignantInconnu, P.statutValidee, P.statutAValider,
            P.statutEnCours, P.alerteHorsZone, P.alerteGpsTruque, P.validationMessage, P.validerEtNoter, P.plusEligible,
            P.succesValidation, P.lotNote, P.lotMessage, P.lotAucuneEligible, P.lotPlusEligible, P.succesContestation,
            "À valider (", "En cours (", "Validées (", "Alertes (", "Tout valider (sans alerte) · ", " pour valider",
            "Présence validée et note ", "/5 envoyée !", " présences à valider", " présences ?",
            P.etatVide(.aValider, sansPointage: false).titre, P.etatVide(.aValider, sansPointage: false).message,
            P.etatVide(.enCours, sansPointage: false).titre, P.etatVide(.enCours, sansPointage: false).message,
            P.etatVide(.validees, sansPointage: false).titre, P.etatVide(.validees, sansPointage: false).message,
            P.etatVide(.alertes, sansPointage: false).titre, P.etatVide(.alertes, sansPointage: false).message,
            P.etatVide(.alertes, sansPointage: true).titre, P.etatVide(.alertes, sansPointage: true).message,
        ])
        try SourceWebLot5.verifier("src/components/CarteValidation.tsx", contient: [
            P.detailTeleportation, P.planningIndisponible, P.planningAConfirmer, P.explicationPlanningIndisponible,
            P.explicationPointageOuvert, P.explicationAucunSegment, P.explicationPlanningNonConfirme, P.noterPourValider,
            P.contester, P.contestationPlaceholder, P.contestationEnvoyer, "Prévu · ", "Réel · ", " travaillées",
            " · pointage ouvert", "Hors périmètre à l'arrivée", " (distance indisponible)", "⚠️ Litige : ",
            "Mission en cours : validation après le dernier créneau, le ",
        ])
        try SourceWebLot5.verifier("src/components/presence/BadgesAntiTrichePresence.tsx", contient: [P.alerteTeleportation])
        try SourceWebLot5.verifier("src/components/NotationRapide.tsx", contient: ["déjà notée", " étoile", "'Note'", "ETAB_VERS_SOIGNANT"])
    }

    // MARK: - Monde démo

    private func contexte(_ role: RoleEtab = .proprietaire) throws -> EtablissementReadContext {
        let permissions = try DemoFixtures.loadPermissionsEtab().roles[role.brut] ?? .aucune
        return EtablissementReadContext(userId: DemoEtablissementWorld.userId, etablissementId: "demo-etab-1", roleEtab: role,
                                        permissions: permissions, epoch: 1)
    }

    func testMondeDemoOngletsEtMissionSansPointage() async throws {
        let gateway = DemoEtabPresencesGateway()
        let presences = try await gateway.presences(context: try contexte())
        XCTAssertEqual(presences.map(\.id), ["demo-etab-p04", "demo-etab-p06", "demo-etab-p07", "demo-etab-p08"])
        let repartition = R.repartir(presences, maintenant: maintenant)
        XCTAssertEqual(repartition.aValider.map(\.missionId), ["demo-etab-m07", "demo-etab-m08"])
        XCTAssertEqual(repartition.enCours.map(\.missionId), ["demo-etab-m04", "demo-etab-m06"])
        XCTAssertTrue(repartition.validees.isEmpty)
        XCTAssertEqual(repartition.alertes.map(\.missionId), ["demo-etab-m08"])
        XCTAssertEqual(repartition.sansAlerte.map(\.missionId), ["demo-etab-m07"], "M7 seule éligible au lot, M8 hors zone exclue")
        XCTAssertNotNil(ClotureSegment.bornes(creneaux: presences[0].creneaux, maintenant: maintenant), "M4 : segment ouvert à clôturer")
        XCTAssertNil(ClotureSegment.bornes(creneaux: presences[1].creneaux, maintenant: maintenant), "M6 : aucun segment ouvert (T7)")
        let terminees = try await gateway.missionsTerminees(context: try contexte())
        XCTAssertEqual(R.missionsSansPointage(terminees: terminees, presences: presences).map(\.id), ["demo-etab-m11"])
        // Segments de M4 et M6 : ceux du dernier état du pointage démo (T7), une seule histoire par mission.
        let pointage = try DemoFixtures.loadEtabPointage()
        for mission in ["demo-etab-m04", "demo-etab-m06"] {
            let segments = try XCTUnwrap(pointage.scenarios.first { $0.missionId == mission }?.etats.last?.etat.segments)
            let effectifs = try XCTUnwrap(presences.first { $0.missionId == mission }).creneaux.filter { $0.typeCreneau == "EFFECTIF" }
            XCTAssertEqual(effectifs.compactMap(\.id), segments.map(\.id), mission)
            XCTAssertEqual(effectifs.map(\.debut), segments.map(\.debut), mission)
            XCTAssertEqual(effectifs.map(\.fin), segments.map(\.fin), mission)
        }
        // Autre compte ou autre établissement : rien n'est servi.
        var etranger = try contexte()
        etranger.userId = "autre"
        do {
            _ = try await gateway.presences(context: etranger)
            XCTFail("compte fictif seulement")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
        var autreEtab = try contexte()
        autreEtab.etablissementId = "demo-etab-2"
        let vides = try await gateway.presences(context: autreEtab)
        XCTAssertTrue(vides.isEmpty)
    }

    func testMondeDemoValidationContestationEtLotRelus() async throws {
        let gateway = DemoEtabPresencesGateway()
        let context = try contexte()
        let avantFin = try await gateway.valider(presenceId: "demo-etab-p06", context: context)
        XCTAssertEqual(avantFin, .refusee(message: "La présence ne peut être validée avant la fin du dernier créneau planifié."))
        let ouvert = try await gateway.validerLot(ids: ["demo-etab-p07"], context: try contexte(.lectureSeule))
        XCTAssertEqual(ouvert, .refusee(message: "Non autorisé"), "lot : permission contrôlée dans le corps de la RPC")
        let sansDroit = try await gateway.valider(presenceId: "demo-etab-p07", context: try contexte(.lectureSeule))
        XCTAssertEqual(sansDroit, .accesRefuse(message: DemoEtabPresencesGateway.roleInsuffisant))

        let lot = try await gateway.validerLot(ids: ["demo-etab-p07", "demo-etab-p08"], context: try contexte(.pointageOnly))
        XCTAssertEqual(lot, .traitee(validees: 1, selectionnees: 2), "M8 hors zone exclue par le serveur, comptes relus")
        let relues = try await gateway.presences(context: context)
        XCTAssertEqual(relues.first { $0.id == "demo-etab-p07" }?.valideParEtablissement, true)
        XCTAssertEqual(relues.first { $0.id == "demo-etab-p07" }?.valideLe, "2026-11-02T00:00:00.000Z", "heure du serveur fictif")
        XCTAssertEqual(relues.first { $0.id == "demo-etab-p08" }?.valideParEtablissement, false)
        let deja = try await gateway.valider(presenceId: "demo-etab-p07", context: context)
        XCTAssertEqual(deja, .validee(valideLe: "2026-11-02T00:00:00.000Z"), "déjà validée : état relu")

        let court = try await gateway.contester(presenceId: "demo-etab-p08", motif: " ab ", context: context)
        XCTAssertEqual(court, .refusee(message: "Le motif est obligatoire (3 caractères min.)"))
        let conteste = try await gateway.contester(presenceId: "demo-etab-p08", motif: "  Absent ", context: context)
        XCTAssertEqual(conteste, .contestee(motifLitige: "Absent"))
        let apres = try await gateway.presences(context: context)
        XCTAssertEqual(apres.first { $0.id == "demo-etab-p08" }?.motifLitige, "Absent")
        let inconnue = try await gateway.valider(presenceId: "inconnue", context: context)
        XCTAssertEqual(inconnue, .refusee(message: "Présence introuvable"))

        let notee = try await gateway.noter(missionId: "demo-etab-m07", note: 4, context: context)
        XCTAssertEqual(notee, .enregistree)
        let renotee = try await gateway.noter(missionId: "demo-etab-m07", note: 5, context: context)
        XCTAssertEqual(renotee, .enregistree, "déjà notée = succès (NotationRapide.tsx l.61)")
        let enCours = try await gateway.noter(missionId: "demo-etab-m06", note: 4, context: context)
        XCTAssertEqual(enCours, .nonEnregistree(message: "Seules les missions TERMINEE peuvent être notées"))
    }

    func testMondeDemoClotureDuSegmentOuvertRelue() async throws {
        let gateway = DemoEtabPresencesGateway()
        let context = try contexte()
        let fin = maintenant
        let pointageSeul = try await gateway.cloturerSegment(missionId: "demo-etab-m04", heureFin: fin, context: try contexte(.pointageOnly))
        XCTAssertEqual(pointageSeul, .accesRefuse(message: "Vous n'êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission."),
                       "le serveur exige est_admin_etablissement() : refus mot pour mot")
        let terminee = try await gateway.cloturerSegment(missionId: "demo-etab-m07", heureFin: fin, context: context)
        XCTAssertEqual(terminee, .refusee(message: "Mission demo-etab-m07 introuvable ou dans un statut incompatible."))
        let sansSegment = try await gateway.cloturerSegment(missionId: "demo-etab-m06", heureFin: fin, context: context)
        XCTAssertEqual(sansSegment, .refusee(message: "Aucun créneau effectif ouvert à fermer pour cette mission."))
        let tropTot = try await gateway.cloturerSegment(missionId: "demo-etab-m04", heureFin: fin.addingTimeInterval(-3600), context: context)
        guard case let .refusee(message) = tropTot else { return XCTFail("refus attendu, obtenu \(tropTot)") }
        XCTAssertTrue(message.hasPrefix("L'heure de fin (") && message.hasSuffix(") doit être postérieure au début du créneau (2026-11-01T23:58:00.000Z)."), message)

        let cloturee = try await gateway.cloturerSegment(missionId: "demo-etab-m04", heureFin: fin, context: context)
        XCTAssertEqual(cloturee, .cloturee)
        let relus = try await gateway.creneaux(missionId: "demo-etab-m04", context: context)
        XCTAssertEqual(relus.filter { $0.typeCreneau == "EFFECTIF" }.map(\.fin), ["2026-11-02T00:00:00.000Z"], "segment fermé relu")
        XCTAssertNil(ClotureSegment.bornes(creneaux: relus, maintenant: maintenant))
        let encore = try await gateway.cloturerSegment(missionId: "demo-etab-m04", heureFin: fin, context: context)
        XCTAssertEqual(encore, .refusee(message: "Aucun créneau effectif ouvert à fermer pour cette mission."))
    }

    func testPortCableDansLeMondeDemo() {
        let ports = DemoEtablissementWorld.gateways(identite: { DemoEtablissementWorld.userId })
        XCTAssertTrue(ports.presences is DemoEtabPresencesGateway)
        XCTAssertFalse(ports.unwiredPorts.contains("etablissement.presences"))
        XCTAssertTrue(EtabDestination.presencesMission(missionId: "m").ecranLivre, "T8")
    }
}
