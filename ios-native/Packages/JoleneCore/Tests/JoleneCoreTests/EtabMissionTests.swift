import XCTest
@testable import JoleneCore

/// Missions de l'établissement (lot 5, T5) : décodage tolérant sans montant, filtres et compteurs du web
/// (`ListeMissions.tsx` l.27-36, l.161-166), carte et détail (`CarteMission.tsx`, `DetailMission.tsx`), liens soumis
/// aux permissions servies et renvoyés au web tant que leur tranche n'est pas livrée, monde démo (M1…M11).
final class EtabMissionTests: XCTestCase {
    private let decodeur = JSONDecoder()

    private func ligne(_ json: String) throws -> EtabMissionResume {
        try decodeur.decode(EtabMissionResume.self, from: Data(json.utf8))
    }

    private func mission(statut: String, mode: String = "CANDIDATURE", soignant: String? = nil, nbCreneaux: Int = 1,
                         debut: String = "2026-11-05T06:00:00.000Z", fin: String = "2026-11-05T14:00:00.000Z") -> EtabMissionResume {
        EtabMissionResume(id: "m-1", intitule: "Mission", statut: statut, debutLe: debut, finLe: fin, nbCreneaux: nbCreneaux,
                          professionRequise: "IDE", typeContratRecherche: "SALARIE", estUrgente: false,
                          etablissementId: "etab-1", soignantAssigneId: soignant, modeAttribution: mode)
    }

    private func creneau(_ debut: String, _ fin: String?, id: String = "c-1") -> MissionSlot {
        MissionSlot(id: id, missionId: "m-1", debut: debut, fin: fin, estPause: false, typeCreneau: "PREVISIONNEL")
    }

    // MARK: - Décodage

    func testColonnesDecodeesSansAucunMontant() {
        let cles = EtabMissionResume.clesDecodees
        XCTAssertEqual(cles, ["id", "etablissement_id", "intitule", "description", "service", "profession_requise", "debut_le",
                              "fin_le", "nb_creneaux", "statut", "est_urgente", "niveau_urgence", "soignant_assigne_id",
                              "mode_attribution", "type_contrat_recherche", "cree_le"])
        for montant in ["taux_horaire_base", "total_brut", "net_a_payer", "taux_rist_plafonne", "rist_plafond_applique",
                        "net_estime", "montant_commission_ttc"] {
            XCTAssertFalse(cles.contains(montant), "\(montant) jamais lu (D15)")
        }
        let soignant = SoignantPourEtab.clesDecodees
        for interdit in ["note_moyenne", "nb_evaluations", "type_exercice", "internat", "etudiant_details"] {
            XCTAssertFalse(soignant.contains(interdit), "\(interdit) jamais décodé")
        }
    }

    func testDecodageTolerantStatutInconnuConserve() throws {
        let lu = try ligne(#"{"id":"m-9","intitule":null,"statut":"NOUVEAU_STATUT","nb_creneaux":"2","est_urgente":"oui","taux_horaire_base":31}"#)
        XCTAssertEqual(lu.id, "m-9")
        XCTAssertEqual(lu.intitule, "")
        XCTAssertEqual(lu.statut, "NOUVEAU_STATUT", "statut inconnu toléré, tel quel")
        XCTAssertNil(lu.nbCreneaux)
        XCTAssertNil(lu.estUrgente)
        XCTAssertEqual(MesMissionsPresentation.statut(lu.statut ?? ""), "NOUVEAU_STATUT", "libellé brut")
        XCTAssertThrowsError(try ligne(#"{"id":"  ","intitule":"x"}"#), "identifiant vide refusé")
        XCTAssertThrowsError(try ligne(#"{"intitule":"x"}"#), "identifiant absent refusé")
    }

    func testSoignantDecodeScoreDecimal() throws {
        let lu = try decodeur.decode(SoignantPourEtab.self, from: Data(#"""
        {"id":"s-1","prenom":"Camille","nom":"D.","nom_anonymise":true,"profession":"IDE","telephone":null,
         "score_fiabilite":82.0,"total_missions_terminees":3,"note_moyenne":4.9,"internat":{"x":1}}
        """#.utf8))
        XCTAssertEqual(lu, SoignantPourEtab(id: "s-1", prenom: "Camille", nom: "D.", profession: "IDE", nomAnonymise: true,
                                            telephone: nil, numeroRpps: nil, scoreFiabilite: 82, totalMissionsTerminees: 3))
    }

    // MARK: - Filtres et compteurs

    func testFiltresDuWebEtParametreDeLien() {
        XCTAssertEqual(EtabMissionsFiltre.allCases.map(\.libelle),
                       ["Toutes", "Ouvertes", "Assignées", "Actives", "Terminées", "Expirées", "Annulées", "Litiges"])
        XCTAssertEqual(EtabMissionsFiltre.allCases.compactMap(\.statut),
                       ["OUVERTE", "ASSIGNEE", "EN_COURS", "TERMINEE", "EXPIREE", "ANNULEE_PAR_ETABLISSEMENT", "LITIGE"])
        XCTAssertEqual(EtabMissionsFiltre(parametre: "OUVERTE"), .ouvertes)
        XCTAssertEqual(EtabMissionsFiltre(parametre: "ABSENCE"), .toutes, "statut hors filtres : « Toutes », comme le web")
        XCTAssertEqual(EtabMissionsFiltre(parametre: nil), .toutes)
        XCTAssertEqual(EtabMissionsFiltre.toutes.identifiant, "etab-missions-filtre-toutes")
        XCTAssertEqual(EtabMissionsFiltre.annulees.identifiant, "etab-missions-filtre-ANNULEE_PAR_ETABLISSEMENT")
    }

    func testCompteursDerivesDesStatutsEtLibelles() {
        let compteurs = EtabMissionsCompteurs(statuts: ["OUVERTE", "OUVERTE", "ABSENCE", nil, "TERMINEE"])
        XCTAssertEqual(compteurs.nombre(.toutes), 5, "« Toutes » compte aussi les statuts hors filtres")
        XCTAssertEqual(compteurs.nombre(.ouvertes), 2)
        XCTAssertEqual(compteurs.nombre(.litiges), 0)
        XCTAssertEqual(EtabMissionsPresentation.libelle(.ouvertes, compteurs: compteurs), "Ouvertes (2)")
        XCTAssertEqual(EtabMissionsPresentation.libelle(.ouvertes, compteurs: nil), "Ouvertes", "jamais un « (0) » supposé")
        XCTAssertEqual(EtabMissionsPresentation.etatVide(.expirees, compteurs: compteurs).titre, "Aucune mission expirée")
        XCTAssertEqual(EtabMissionsPresentation.etatVide(.toutes, compteurs: EtabMissionsCompteurs(statuts: [])).titre,
                       "Publiez votre première mission")
        XCTAssertEqual(EtabMissionsPresentation.nombreTrouvees(1), "1 mission trouvée")
        XCTAssertEqual(EtabMissionsPresentation.nombreTrouvees(3), "3 missions trouvées")
    }

    // MARK: - Carte

    func testCartePlanningExactEtCandidatures() {
        let carte = EtabMissionsPresentation.carte(mission(statut: "OUVERTE"),
                                                   creneaux: [creneau("2026-11-05T06:00:00.000Z", "2026-11-05T14:00:00.000Z")],
                                                   candidaturesEnAttente: 2)
        XCTAssertEqual(carte.badges.map(\.texte), ["Ouverte", "2 candidatures à traiter", "💼 Salarié"])
        XCTAssertEqual(carte.periode, "jeudi 5 novembre 2026")
        XCTAssertEqual(carte.planning, "1 créneau · 8 h planifiées")
        XCTAssertFalse(carte.planningAConfirmer)
        XCTAssertEqual(carte.soignant, EtabMissionsPresentation.enAttenteSoignant)
        XCTAssertEqual(carte.sousTitre, MissionPresentation.professionLabel("IDE"))
    }

    func testCartePlanningIncompletJamaisPresenteCommeExact() {
        // M3 : deux créneaux attendus, un seul relu ; le web afficherait un repli ponctuel, le natif « à confirmer ».
        let carte = EtabMissionsPresentation.carte(mission(statut: "OUVERTE", nbCreneaux: 2),
                                                   creneaux: [creneau("2026-11-05T06:00:00.000Z", "2026-11-05T14:00:00.000Z")],
                                                   candidaturesEnAttente: nil)
        XCTAssertEqual(carte.planning, EtabMissionsPresentation.planningAConfirmer)
        XCTAssertTrue(carte.planningAConfirmer)
        XCTAssertEqual(carte.badges.map(\.texte), ["Ouverte", "💼 Salarié"], "aucune pastille sans compte relu")
    }

    func testCarteUrgenteMissionActiveSurPlusieursJours() {
        var urgente = mission(statut: "EN_COURS", soignant: "s-1", nbCreneaux: 2, debut: "2026-11-01T06:00:00.000Z",
                              fin: "2026-11-03T14:00:00.000Z")
        urgente.estUrgente = true
        urgente.niveauUrgence = 3
        let carte = EtabMissionsPresentation.carte(urgente, creneaux: [
            creneau("2026-11-01T06:00:00.000Z", "2026-11-01T14:00:00.000Z", id: "a"),
            creneau("2026-11-03T06:00:00.000Z", "2026-11-03T14:00:00.000Z", id: "b"),
        ], candidaturesEnAttente: 4)
        XCTAssertEqual(carte.badges.first?.texte, "URGENT · critique")
        XCTAssertEqual(carte.badges.map(\.texte).contains("4 candidatures à traiter"), false, "pastille réservée aux missions ouvertes")
        XCTAssertEqual(carte.periode, "Période active : 1 nov. → 3 nov. 2026")
        XCTAssertEqual(carte.planning, "2 créneaux · 16 h planifiées")
        XCTAssertNil(carte.soignant)
    }

    // MARK: - Détail

    func testPlanningDuDetail() {
        let base = mission(statut: "ASSIGNEE", soignant: "s-1")
        let exact = EtabMissionDetail(mission: base, creneaux: [creneau("2026-11-01T23:00:00.000Z", "2026-11-02T07:00:00.000Z")],
                                      soignantAssigneId: "s-1")
        guard case let .exact(resume, lignes) = EtabMissionsPresentation.planning(exact) else { return XCTFail("planning exact attendu") }
        XCTAssertEqual(resume, "1 créneau · 8 h planifiées au total")
        XCTAssertEqual(lignes, ["lundi 2 novembre 2026 · 00:00 → 08:00 · 8 h"])
        let nuit = EtabMissionsPresentation.ligneCreneau(creneau("2026-11-01T21:00:00.000Z", "2026-11-02T05:30:00.000Z"))
        XCTAssertEqual(nuit, "dimanche 1 novembre 2026 · 22:00 → lun. 2 nov. · 06:30 · 8,5 h")

        var incomplete = exact
        incomplete.mission.nbCreneaux = 2
        XCTAssertEqual(EtabMissionsPresentation.planning(incomplete), .aConfirmer(lignes: ["lundi 2 novembre 2026 · 00:00 → 08:00 · 8 h"]))
        var indisponible = exact
        indisponible.erreurPlanning = "Le planning a changé pendant son chargement. Réessayez."
        XCTAssertEqual(EtabMissionsPresentation.planning(indisponible),
                       .indisponible(message: "Planning détaillé momentanément indisponible : Le planning a changé pendant son chargement. Réessayez."))
    }

    func testFicheSoignant() {
        let nouveau = SoignantPourEtab(id: "s", prenom: "Camille", nom: "Démo", profession: "IDE", totalMissionsTerminees: 0)
        let fiche = EtabMissionsPresentation.fiche(nouveau, statutMission: "ASSIGNEE")
        XCTAssertEqual(fiche.nom, "Camille Démo")
        XCTAssertEqual(fiche.fiabilite, EtabMissionsPresentation.nouveauSurJolene)
        XCTAssertEqual(fiche.telephone, EtabMissionsPresentation.numeroJourMission, "téléphone jamais supposé")
        var fiable = nouveau
        fiable.scoreFiabilite = 74; fiable.totalMissionsTerminees = 6; fiable.telephone = "0600000000"; fiable.numeroRpps = "123"
        let ficheFiable = EtabMissionsPresentation.fiche(fiable, statutMission: "TERMINEE")
        XCTAssertEqual(ficheFiable.fiabilite, "74/100 (Fiable)")
        XCTAssertEqual(ficheFiable.telephone, "0600000000")
        XCTAssertEqual(ficheFiable.rpps, "RPPS : 123")
        XCTAssertNil(EtabMissionsPresentation.fiche(nouveau, statutMission: "TERMINEE").fiabilite, "évaluation sur le web (D8)")
        XCTAssertEqual(EtabMissionsPresentation.libelleFiabilite(40), "Moyen")
        XCTAssertEqual(EtabMissionsPresentation.libelleFiabilite(39), "À surveiller")
    }

    func testLiensSoumisAuxPermissionsEtRenvoyesAuWebAvantLeurTranche() {
        let tout = PermissionsEtab(accordees: Set(PermissionEtab.allCases))
        let ouverte = EtabMissionDetail(mission: mission(statut: "OUVERTE"), creneaux: [], soignantAssigneId: nil, candidaturesEnAttente: 3)
        let liensOuverte = EtabMissionsPresentation.liens(ouverte, permissions: tout)
        XCTAssertEqual(liensOuverte.map(\.cle), [.candidatures])
        XCTAssertEqual(liensOuverte.first?.cible, .ecran(.candidatures(missionId: "m-1")),
                       "T6 livrée : écran natif des candidatures")
        XCTAssertEqual(liensOuverte.first?.titre, "Candidatures")
        XCTAssertEqual(liensOuverte.first?.detail, "3 candidatures en attente")
        XCTAssertEqual(EtabMissionsPresentation.liens(ouverte, permissions: PermissionsEtab(accordees: [.lecture])), [],
                       "candidatures masquées sans la permission")

        let assignee = EtabMissionDetail(mission: mission(statut: "ASSIGNEE", soignant: "s-1"), creneaux: [], soignantAssigneId: "s-1")
        let liensAssignee = EtabMissionsPresentation.liens(assignee, permissions: tout)
        XCTAssertEqual(liensAssignee.map(\.cle), [.pointage, .contrat, .message])
        XCTAssertEqual(liensAssignee.first?.cible, .ecran(.pointage(missionId: "m-1")), "T7 livrée : écran natif du code de pointage")
        XCTAssertEqual(liensAssignee.first?.titre, "Code de pointage")
        XCTAssertEqual(EtabMissionsPresentation.liens(assignee, permissions: PermissionsEtab(accordees: [.lecture, .lecturePaiement]))
            .map(\.cle), [.message], "LECTURE_SEULE : ni pointage ni contrat")
        XCTAssertEqual(EtabMissionsPresentation.liens(assignee, permissions: PermissionsEtab(accordees: [.lecture, .pointage]))
            .map(\.cle), [.pointage, .message], "POINTAGE_ONLY : pointage, jamais contrat")
        let terminee = EtabMissionDetail(mission: mission(statut: "TERMINEE", soignant: "s-1"), creneaux: [], soignantAssigneId: "s-1")
        let liensTerminee = EtabMissionsPresentation.liens(terminee, permissions: tout)
        XCTAssertEqual(liensTerminee.map(\.cle), [.presences, .contrat, .message])
        XCTAssertEqual(liensTerminee.first?.cible, .ecran(.presencesMission(missionId: "m-1")), "T8 livrée : présences natives de la mission")
        XCTAssertEqual(liensTerminee.first?.titre, "Présences")
        XCTAssertTrue(liensTerminee.dropFirst().allSatisfy(\.estWeb), "T10, T11 non livrées")
        XCTAssertEqual(liensTerminee.map(\.identifiant),
                       ["etab-mission-lien-presences", "etab-mission-lien-contrat", "etab-mission-lien-message"])
    }

    func testActionsWebReserveesALaPermissionMissions() {
        let tout = PermissionsEtab(accordees: Set(PermissionEtab.allCases))
        XCTAssertEqual(EtabMissionsPresentation.actionsWeb(mission(statut: "OUVERTE"), permissions: tout).map(\.url.absoluteString), [
            "https://jolene.app/etablissement/missions/m-1/modifier",
            "https://jolene.app/etablissement/missions/creer?dupliquer=m-1",
            "https://jolene.app/etablissement/missions/m-1",
        ])
        XCTAssertEqual(EtabMissionsPresentation.actionsWeb(mission(statut: "ASSIGNEE"), permissions: tout).map(\.cle), [.dupliquer, .annuler])
        XCTAssertEqual(EtabMissionsPresentation.actionsWeb(mission(statut: "TERMINEE"), permissions: tout).map(\.cle), [.dupliquer])
        XCTAssertEqual(EtabMissionsPresentation.actionsWeb(mission(statut: "OUVERTE"), permissions: PermissionsEtab(accordees: [.lecture])), [])
        var speciale = mission(statut: "OUVERTE")
        speciale.id = "a b/c"
        XCTAssertEqual(EtabMissionsPresentation.actionsWeb(speciale, permissions: tout).map(\.url.absoluteString)[1],
                       "https://jolene.app/etablissement/missions/creer?dupliquer=a%20b%2Fc", "encodeURIComponent")
    }

    // MARK: - Monde démo

    private func contexte(_ permissions: Set<PermissionEtab>, userId: String = DemoEtablissementWorld.userId) -> EtablissementReadContext {
        EtablissementReadContext(userId: userId, etablissementId: "demo-etab-1", roleEtab: .proprietaire,
                                 permissions: PermissionsEtab(accordees: permissions), epoch: 1)
    }

    func testDemoOnzeMissionsCompteursDerivesEtM3Incomplete() async throws {
        let gateway = DemoEtabMissionsGateway()
        let page = try await gateway.missions(context: contexte([.lecture, .candidatures]), statut: nil, page: 0)
        XCTAssertEqual(page.missions.count, 11)
        XCTAssertFalse(page.aSuivre)
        XCTAssertEqual(page.missions.first?.id, "demo-etab-m10", "debut_le décroissant, comme le web")
        XCTAssertEqual(page.compteurs?.nombre(.toutes), 11)
        XCTAssertEqual(page.compteurs?.nombre(.ouvertes), 5)
        XCTAssertEqual(page.compteurs?.nombre(.expirees), 0)
        XCTAssertEqual(page.candidaturesEnAttente["demo-etab-m01"], 3, "dérivé des candidatures de la fixture")
        let m3 = try XCTUnwrap(page.missions.first { $0.id == "demo-etab-m03" })
        XCTAssertTrue(EtabMissionsPresentation.carte(m3, creneaux: page.creneaux["demo-etab-m03"] ?? [],
                                                     candidaturesEnAttente: nil).planningAConfirmer)

        let sansCandidatures = try await gateway.missions(context: contexte([.lecture]), statut: "OUVERTE", page: 0)
        XCTAssertEqual(sansCandidatures.missions.count, 5)
        XCTAssertEqual(sansCandidatures.candidaturesEnAttente, [:], "jamais lues sans la permission candidatures")
    }

    func testDemoDetailSoignantEtRefusHorsCompteFictif() async throws {
        let gateway = DemoEtabMissionsGateway()
        let lu = try await gateway.mission(id: "demo-etab-m04", context: contexte([.lecture]))
        let detail = try XCTUnwrap(lu)
        XCTAssertEqual(detail.mission.statut, "ASSIGNEE")
        XCTAssertEqual(detail.creneaux.map(\.debut), ["2026-11-01T23:00:00.000Z"])
        let soignantLu = try await gateway.soignant(id: try XCTUnwrap(detail.soignantAssigneId), context: contexte([.lecture]))
        let soignant = try XCTUnwrap(soignantLu)
        XCTAssertEqual(soignant.prenom, "Camille", "soignant fictif du monde soignant (une identité par identifiant)")
        let soignantInconnu = try await gateway.soignant(id: "inconnu", context: contexte([.lecture]))
        XCTAssertNil(soignantInconnu)
        let introuvable = try await gateway.mission(id: "demo-mission-001", context: contexte([.lecture]))
        XCTAssertNil(introuvable, "mission d'un autre monde : introuvable")
        let m1 = try await gateway.mission(id: "demo-etab-m01", context: contexte([.lecture, .candidatures]))
        XCTAssertEqual(m1?.candidaturesEnAttente, 3)
        do {
            _ = try await gateway.missions(context: contexte([.lecture], userId: "autre"), statut: nil, page: 0)
            XCTFail("compte non fictif refusé")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
    }
}
