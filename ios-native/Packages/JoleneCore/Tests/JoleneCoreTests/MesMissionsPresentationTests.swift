import XCTest
@testable import JoleneCore

/// Textes et lignes de « Mes missions » (lot 1, T5), port de `MissionsSoignant.tsx` : onglet initial,
/// libellés `BADGES_STATUT`, planning vérifié (`analyserCompletudePlanningMission` sur les créneaux
/// relus), horaires en heure de Paris, montants serveur selon le régime (`montantFinanceAfficheMission`)
/// sans la correction client d'ancien plafond, états vides au vouvoiement.
final class MesMissionsPresentationTests: XCTestCase {
    private let maintenant = DemoWorld.fixedNow // 2026-11-02T00:00:00Z
    private let euro = "\u{00A0}€"
    private let etab = EtablissementSummary(id: "e-1", nom: "Clinique des Tests", adresseVille: "Lyon")

    private func record(_ id: String = "m-1", debut: String = "2026-11-05T07:00:00.000Z", fin: String = "2026-11-05T15:00:00.000Z",
                        nb: Int? = 1, statut: String = "ASSIGNEE", taux: Double? = 27, tauxRist: Double? = nil,
                        rist: Bool? = false, contrat: String? = "SALARIE", urgente: Bool = false) -> MissionRecord {
        MissionRecord(id: id, intitule: "Mission \(id)", description: nil, service: nil, professionRequise: "IDE",
                      specialiteMedicaleRequise: nil, accepteNonSpecialises: nil, debutLe: debut, finLe: fin, dureeHeures: nil,
                      nbCreneaux: nb, tauxHoraireBase: taux, tauxRistPlafonne: tauxRist, ristPlafondApplique: rist,
                      totalBrut: nil, netAPayer: nil, estUrgente: urgente, niveauUrgence: nil, statut: statut,
                      etablissementId: "e-1", typeContratRecherche: contrat, boosteeLe: nil, modeRemuneration: nil, retrocessionPct: nil)
    }

    private func creneau(_ id: String, mission: String = "m-1", _ debut: String, _ fin: String?) -> MissionSlot {
        MissionSlot(id: id, missionId: mission, debut: debut, fin: fin, estPause: false, typeCreneau: "PREVISIONNEL")
    }

    private func mission(_ record: MissionRecord, _ creneaux: [MissionSlot], etablissement: EtablissementSummary? = nil) -> Mission {
        MissionBusiness.enrich(record: record, context: DemoWorld.context, etablissement: etablissement ?? etab, slots: creneaux)
    }

    private func finance(_ id: String = "m-1", applique: String? = nil, recherche: String? = nil, brut: Double? = nil,
                         netAPayer: Double? = nil, netEstime: Double? = nil) -> MissionGainLigne {
        MissionGainLigne(id: id, typeContratApplique: applique, typeContratRecherche: recherche, totalBrut: brut,
                         netAPayer: netAPayer, netEstime: netEstime)
    }

    // MARK: - Onglets

    func testOngletInitialEtIdentifiantsCommeLeWeb() {
        XCTAssertEqual(MesMissionsOnglet.initial(tab: "candidatures", onglet: nil), .candidatures)
        XCTAssertEqual(MesMissionsOnglet.initial(tab: "passees", onglet: nil), .passees)
        XCTAssertEqual(MesMissionsOnglet.initial(tab: nil, onglet: "historique"), .passees, "ancien `?onglet=historique`")
        XCTAssertEqual(MesMissionsOnglet.initial(tab: "a-venir", onglet: nil), .aVenir, "cible de /soignant/planning")
        XCTAssertEqual(MesMissionsOnglet.initial(tab: nil, onglet: nil), .aVenir)
        XCTAssertEqual(MesMissionsOnglet.initial(tab: "inconnu", onglet: "mes_missions"), .aVenir)
        XCTAssertEqual(MesMissionsOnglet.initial(tab: "candidatures", onglet: "historique"), .candidatures, "`tab` est lu d'abord")
        XCTAssertEqual(MesMissionsOnglet.allCases.map(\.titre), ["Candidatures", "À venir", "Passées"])
        XCTAssertEqual(MesMissionsOnglet.allCases.map(\.identifiant),
                       ["missions-tab-candidatures", "missions-tab-avenir", "missions-tab-passees"])
    }

    /// Critère T5 : `/soignant/missions` et ses alias du web (`src/App.tsx` l.384-398) ouvrent l'onglet
    /// natif Mes missions (`LinkRouter`), l'onglet affiché suivant `?tab=` comme le web.
    func testRouteEtAliasDuWebVersMesMissions() {
        for lien in ["/soignant/missions", "/soignant/missions?tab=candidatures", "/soignant/mes-matches", "/soignant/planning",
                     "/soignant/calendrier-sync", "/soignant/historique-missions", "https://jolene.app/soignant/missions?tab=passees"] {
            XCTAssertEqual(LinkRouter.resolve(link: lien), .missions, lien)
        }
        XCTAssertEqual(LinkRouter.resolve(link: "/soignant/missions/m-1"), .missionDetail(id: "m-1"), "une ligne ouvre le détail natif")
    }

    func testLibellesEtTonsDesStatutsBadgesStatut() {
        let attendus = ["ASSIGNEE": "Assignée", "EN_COURS": "Active", "TERMINEE": "Terminée", "ANNULEE_PAR_ETABLISSEMENT": "Annulée",
                        "ANNULEE_PAR_SOIGNANT": "Annulée (soignant)", "ABSENCE": "Absence", "LITIGE": "Litige",
                        "EXPIREE": "Expirée (non pourvue)", "OUVERTE": "Ouverte", "STATUT_NOUVEAU": "STATUT_NOUVEAU"]
        for (code, libelle) in attendus { XCTAssertEqual(MesMissionsPresentation.statut(code), libelle, code) }
        XCTAssertEqual(MesMissionsPresentation.badgeStatut("TERMINEE").ton, .succes)
        XCTAssertEqual(MesMissionsPresentation.badgeStatut("ABSENCE").ton, .erreur)
        XCTAssertEqual(MesMissionsPresentation.badgeStatut("ANNULEE_PAR_ETABLISSEMENT").ton, .info)
    }

    // MARK: - Planning vérifié

    func testCompletudeSurLesCreneauxRelusEtRepliPonctuel() {
        // Mission ponctuelle sans créneau détaillé ni `nb_creneaux` : le repli de 8 h est le planning.
        let ponctuelle = mission(record(nb: nil), [])
        let analyse = MesMissionsPresentation.completude(ponctuelle)
        XCTAssertTrue(analyse.complet)
        XCTAssertEqual(analyse.nombrePlanifie, 1)
        XCTAssertFalse(ponctuelle.creneauxPlanifies.isEmpty, "le planning candidat a ajouté son repli…")
        XCTAssertNil(ponctuelle.creneauxPlanifies.first?.missionId, "…sans `mission_id` : jamais compté comme créneau relu")

        let deux = mission(record(fin: "2026-11-06T15:00:00.000Z", nb: 2), [
            creneau("s-1", "2026-11-05T07:00:00.000Z", "2026-11-05T15:00:00.000Z"),
            creneau("s-2", "2026-11-06T07:00:00.000Z", "2026-11-06T15:00:00.000Z"),
        ])
        XCTAssertEqual(MesMissionsPresentation.completude(deux).nombrePlanifie, 2)

        let incomplete = mission(record(nb: 2), [creneau("s-1", "2026-11-05T07:00:00.000Z", "2026-11-05T15:00:00.000Z")])
        XCTAssertFalse(MesMissionsPresentation.completude(incomplete).complet, "nb_creneaux = 2, un seul créneau relu")
        let sansDetail = mission(record(nb: 1), [])
        XCTAssertFalse(MesMissionsPresentation.completude(sansDetail).complet, "mission récente (nb_creneaux = 1) sans ligne détaillée")
        let autreMission = mission(record(nb: 1), [creneau("s-x", mission: "m-autre", "2026-11-05T07:00:00.000Z", "2026-11-05T15:00:00.000Z")])
        XCTAssertFalse(MesMissionsPresentation.completude(autreMission).complet, "seuls les créneaux de la mission comptent")
    }

    // MARK: - À venir

    func testLigneAVenirProchainCreneauEtDuree() {
        let deux = mission(record(fin: "2026-11-06T14:30:00.000Z", nb: 2, urgente: true), [
            creneau("s-1", "2026-11-01T07:00:00.000Z", "2026-11-01T15:00:00.000Z"),
            creneau("s-2", "2026-11-06T07:00:00.000Z", "2026-11-06T14:30:00.000Z"),
        ])
        let ligne = MesMissionsPresentation.ligneAVenir(deux, maintenant: maintenant)
        XCTAssertEqual(ligne.id, "m-1")
        XCTAssertEqual(ligne.badges.map(\.texte), ["Assignée", "🔥 Urgent"], "pastille du web (l.548)")
        XCTAssertEqual(ligne.badges.map(\.texteAccessible), ["Assignée", "Urgent"], "`aria-label=\"Urgent\"` du web")
        XCTAssertEqual(ligne.horaire, "Prochain créneau : 6 nov. · 08h00 → 15h30 (7,5h)", "créneau terminé ignoré, heure de Paris")
        XCTAssertFalse(ligne.horaireAConfirmer)
        XCTAssertEqual(ligne.jour, AccueilPresentation.Jour(semaine: "ven.", jour: "6", mois: "nov."))
        XCTAssertEqual(ligne.lieu, "Clinique des Tests · Lyon")
        XCTAssertEqual(ligne.remuneration, "27,00\(euro)/h")
        XCTAssertNil(ligne.montant)
        XCTAssertEqual(ligne.texteAccessible,
                       "Assignée, Urgent, Mission m-1, Clinique des Tests · Lyon, Prochain créneau : 6 nov. · 08h00 → 15h30 (7,5h), 27,00\(euro)/h")

        let huit = MesMissionsPresentation.ligneAVenir(mission(record(), [creneau("s-1", "2026-11-05T07:00:00.000Z", "2026-11-05T15:00:00.000Z")]),
                                                       maintenant: maintenant)
        XCTAssertEqual(huit.horaire, "Prochain créneau : 5 nov. · 08h00 → 16h00 (8h)")
    }

    func testLigneAVenirTousTerminesOuPlanningAConfirmer() {
        let terminee = mission(record(statut: "EN_COURS"), [creneau("s-1", "2026-11-01T07:00:00.000Z", "2026-11-01T15:00:00.000Z")])
        let ligne = MesMissionsPresentation.ligneAVenir(terminee, maintenant: maintenant)
        XCTAssertEqual(ligne.horaire, "Tous les créneaux planifiés sont terminés")
        XCTAssertFalse(ligne.horaireAConfirmer)
        XCTAssertEqual(ligne.badges.map(\.texte), ["Active"])
        XCTAssertEqual(ligne.jour?.jour, "5", "sans prochain créneau : `debut_le` de la mission")

        let incomplete = mission(record(nb: 2), [creneau("s-1", "2026-11-05T07:00:00.000Z", "2026-11-05T15:00:00.000Z")])
        let aConfirmer = MesMissionsPresentation.ligneAVenir(incomplete, maintenant: maintenant)
        XCTAssertEqual(aConfirmer.horaire, "Planning détaillé à confirmer")
        XCTAssertTrue(aConfirmer.horaireAConfirmer)
        XCTAssertEqual(aConfirmer.jour?.jour, "5")
    }

    /// Le web n'affiche le taux que s'il est renseigné et non nul (`{m.taux_horaire_base && …}`, l.470 et
    /// l.562) : un taux à 0 n'est jamais rendu « 0,00 €/h ». Le format natif « 26,00 €/h » (Explorer,
    /// Accueil, détail) est conservé ; l'écart de format avec le web est consigné dans `PARITE_SOIGNANT.md`.
    func testTauxNulOuAbsentMasqueCommeLeWeb() throws {
        let creneaux = [creneau("s-1", "2026-11-05T07:00:00.000Z", "2026-11-05T15:00:00.000Z")]
        XCTAssertNil(MesMissionsPresentation.ligneAVenir(mission(record(taux: 0), creneaux), maintenant: maintenant).remuneration)
        XCTAssertNil(MesMissionsPresentation.ligneAVenir(mission(record(taux: nil), creneaux), maintenant: maintenant).remuneration)
        XCTAssertEqual(MesMissionsPresentation.ligneAVenir(mission(record(taux: 26), creneaux), maintenant: maintenant).remuneration,
                       "26,00\(euro)/h")
        var candidature = CandidatureRecord(id: "c-1", missionId: "m-1", statut: "EN_ATTENTE", message: nil, typeContratChoisi: nil, creeLe: nil)
        candidature.mission = mission(record(taux: 0), creneaux)
        let ligne = try XCTUnwrap(MesMissionsPresentation.ligne(candidature: candidature, maintenant: maintenant))
        XCTAssertNil(ligne.remuneration)
        XCTAssertFalse(ligne.texteAccessible.contains("€"), "aucun taux nul dans le libellé : \(ligne.texteAccessible)")
    }

    // MARK: - Candidatures

    func testLigneCandidaturePastillesEtHoraire() throws {
        var candidature = CandidatureRecord(id: "c-1", missionId: "m-1", statut: "EN_ATTENTE", message: "Je suis en SUPER-LIKE",
                                            typeContratChoisi: "LIBERAL", creeLe: "2026-11-01T09:30:00.000Z")
        XCTAssertNil(MesMissionsPresentation.ligne(candidature: candidature, maintenant: maintenant), "sans mission relue : écartée")
        candidature.mission = mission(record(debut: "2026-11-06T20:00:00.000Z", fin: "2026-11-07T04:00:00.000Z"),
                                      [creneau("s-1", "2026-11-06T20:00:00.000Z", "2026-11-07T04:00:00.000Z")])
        let ligne = try XCTUnwrap(MesMissionsPresentation.ligne(candidature: candidature, maintenant: maintenant))
        XCTAssertEqual(ligne.badges.map(\.texte), ["⏳ En attente de réponse", "★ Priorité historique", "Libéral"])
        XCTAssertEqual(ligne.horaire, "6 nov. · 21h00 → 05h00")
        XCTAssertEqual(ligne.jour, AccueilPresentation.Jour(semaine: "ven.", jour: "6", mois: "nov."))

        // Créneaux tous passés : le premier créneau planifié reste affiché (web l.430-432).
        candidature.mission = mission(record(debut: "2026-10-30T07:00:00.000Z", fin: "2026-10-30T15:00:00.000Z"),
                                      [creneau("s-1", "2026-10-30T07:00:00.000Z", "2026-10-30T15:00:00.000Z")])
        XCTAssertEqual(MesMissionsPresentation.ligne(candidature: candidature, maintenant: maintenant)?.horaire, "30 oct. · 08h00 → 16h00")

        // Planning incomplet : « à confirmer », pavé sur `debut_le`.
        candidature.mission = mission(record(nb: 3), [creneau("s-1", "2026-11-05T07:00:00.000Z", "2026-11-05T15:00:00.000Z")])
        let incomplete = try XCTUnwrap(MesMissionsPresentation.ligne(candidature: candidature, maintenant: maintenant))
        XCTAssertEqual(incomplete.horaire, "Planning détaillé à confirmer")
        XCTAssertTrue(incomplete.horaireAConfirmer)
        XCTAssertEqual(incomplete.jour?.jour, "5")
    }

    func testPastillesPrioriteEtContrat() {
        func candidature(message: String?, contrat: String?) -> CandidatureRecord {
            CandidatureRecord(id: "c", missionId: "m", statut: "EN_ATTENTE", message: message, typeContratChoisi: contrat, creeLe: nil)
        }
        XCTAssertTrue(MesMissionsPresentation.estPrioriteHistorique(candidature(message: "Super-Like ⭐", contrat: nil)))
        XCTAssertFalse(MesMissionsPresentation.estPrioriteHistorique(candidature(message: "super like", contrat: nil)), "tiret exigé, comme le web")
        XCTAssertFalse(MesMissionsPresentation.estPrioriteHistorique(candidature(message: nil, contrat: nil)))
        XCTAssertEqual(MesMissionsPresentation.contratChoisi(candidature(message: nil, contrat: "LIBERAL")), "Libéral")
        XCTAssertEqual(MesMissionsPresentation.contratChoisi(candidature(message: nil, contrat: "SALARIE")), "Salarié")
        XCTAssertEqual(MesMissionsPresentation.contratChoisi(candidature(message: nil, contrat: "CDD")), "Salarié", "toute valeur non libérale")
        XCTAssertNil(MesMissionsPresentation.contratChoisi(candidature(message: nil, contrat: nil)))
        XCTAssertNil(MesMissionsPresentation.contratChoisi(candidature(message: nil, contrat: "")))
    }

    // MARK: - Passées

    func testPeriodePasseeMonoEtMultiJours() {
        XCTAssertEqual(MesMissionsPresentation.periodePassee(mission(record(debut: "2026-11-01T07:00:00.000Z", fin: "2026-11-01T15:00:00.000Z"), [])),
                       "1 nov. 2026")
        XCTAssertEqual(MesMissionsPresentation.periodePassee(mission(record(debut: "2026-10-20T07:00:00.000Z", fin: "2026-10-21T15:00:00.000Z", nb: 2), [])),
                       "20 oct. → 21 oct. 2026")
        XCTAssertEqual(MesMissionsPresentation.periodePassee(mission(record(debut: "2026-10-12T20:00:00.000Z", fin: "2026-10-13T04:00:00.000Z"), [])),
                       "12 oct. 2026", "nuit de 8 h : une seule date")
    }

    func testMontantPasseeValeurServeurSelonLeRegime() {
        let passee = mission(record(statut: "TERMINEE"), [])
        XCTAssertEqual(MesMissionsPresentation.montantPassee(passee, finance: finance(applique: "SALARIE", brut: 208, netAPayer: 224.6, netEstime: 162.4)),
                       "Net salarié estimé* : ~162,40\(euro)", "salarié : `net_estime`, jamais `net_a_payer`")
        XCTAssertEqual(MesMissionsPresentation.montantPassee(passee, finance: finance(applique: "LIBERAL", brut: 400, netAPayer: 448)),
                       "Honoraires bruts : 448,00\(euro)")
        XCTAssertEqual(MesMissionsPresentation.montantPassee(passee, finance: finance(recherche: "TOUS", brut: 208, netAPayer: 224.6)),
                       "Rémunération brute indicative : ~208,00\(euro)", "régime non choisi : brut indicatif")
        XCTAssertNil(MesMissionsPresentation.montantPassee(passee, finance: finance(applique: "SALARIE", netAPayer: 224.6)),
                     "salarié sans net estimé : aucun montant")
        XCTAssertNil(MesMissionsPresentation.montantPassee(passee, finance: finance(applique: "LIBERAL", netAPayer: 0)), "montant nul masqué")
        XCTAssertNil(MesMissionsPresentation.montantPassee(passee, finance: nil))
        XCTAssertNil(MesMissionsPresentation.montantPassee(passee, finance: finance("autre", applique: "LIBERAL", netAPayer: 448)),
                     "colonnes d'une autre mission : jamais affichées")

        let ligne = MesMissionsPresentation.lignePassee(passee, finance: finance(applique: "LIBERAL", netAPayer: 448))
        XCTAssertEqual(ligne.badges.map(\.texte), ["Terminée"])
        XCTAssertEqual(ligne.lieu, "Clinique des Tests", "passées : établissement sans la ville, comme le web")
        XCTAssertNil(ligne.jour)
        XCTAssertEqual(ligne.horaire, "5 nov. 2026")
        XCTAssertEqual(ligne.texteAccessible, "Terminée, Mission m-1, Clinique des Tests, 5 nov. 2026, Honoraires bruts : 448,00\(euro)")
    }

    func testMontantMasqueQuandLeWebCorrigeraitUnAncienPlafond() {
        let plafonnee = mission(record(statut: "TERMINEE", taux: 30, tauxRist: 25, rist: true, contrat: "LIBERAL"), [])
        XCTAssertNil(MesMissionsPresentation.montantPassee(plafonnee, finance: finance(applique: "LIBERAL", netAPayer: 200)),
                     "le web recalculerait 240 € : aucun montant plutôt qu'une valeur différente du web")
        XCTAssertNil(MesMissionsPresentation.montantPassee(plafonnee, finance: finance(recherche: "LIBERAL", netAPayer: 200)),
                     "contrat lu `type_contrat_applique ?? type_contrat_recherche`")
        XCTAssertEqual(MesMissionsPresentation.montantPassee(plafonnee, finance: finance(applique: "SALARIE", netEstime: 150)),
                       "Net salarié estimé* : ~150,00\(euro)", "salarié assigné : plafond possible, valeur stockée affichée")
        let sansPlafond = mission(record(statut: "TERMINEE", taux: 30, tauxRist: 25, rist: false, contrat: "LIBERAL"), [])
        XCTAssertEqual(MesMissionsPresentation.montantPassee(sansPlafond, finance: finance(applique: "LIBERAL", netAPayer: 200)),
                       "Honoraires bruts : 200,00\(euro)")
        let tauxEgaux = mission(record(statut: "TERMINEE", taux: 25, tauxRist: 25, rist: true, contrat: "LIBERAL"), [])
        XCTAssertEqual(MesMissionsPresentation.montantPassee(tauxEgaux, finance: finance(applique: "LIBERAL", netAPayer: 200)),
                       "Honoraires bruts : 200,00\(euro)", "taux publié non supérieur : aucune correction côté web")
    }

    // MARK: - Lieu et états

    func testNomEtablissementSourceSafeSinonRepli() {
        XCTAssertEqual(MesMissionsPresentation.lieu(mission(record(), []), avecVille: true), "Clinique des Tests · Lyon")
        let sansEtab = MissionBusiness.enrich(record: record(), context: DemoWorld.context, etablissement: nil, slots: [])
        XCTAssertEqual(MesMissionsPresentation.lieu(sansEtab, avecVille: true), "Établissement")
        let nomVide = mission(record(), [], etablissement: EtablissementSummary(id: "e-1", nom: "  ", adresseVille: "Lyon"))
        XCTAssertEqual(MesMissionsPresentation.lieu(nomVide, avecVille: true), "Établissement · Lyon")
    }

    func testEtatsVidesEtChargementAuVouvoiement() {
        XCTAssertEqual(MesMissionsPresentation.etatVide(.candidatures).titre, "Aucune candidature en attente")
        XCTAssertEqual(MesMissionsPresentation.etatVide(.aVenir).action, "Voir les missions disponibles")
        XCTAssertEqual(MesMissionsPresentation.etatVide(.passees).message, "Vos missions terminées et annulées apparaîtront ici.")
        XCTAssertEqual(MesMissionsPresentation.chargement(.candidatures),
                       "Chargement des candidatures — En attente de réponse de l’établissement…")
        XCTAssertEqual(MesMissionsPresentation.chargement(.passees), "Chargement des missions…")
        let tutoiement = try! NSRegularExpression(pattern: "\\b(tu|tes|ton|ta|toi|swipe)\\b", options: [.caseInsensitive])
        for onglet in MesMissionsOnglet.allCases {
            let vide = MesMissionsPresentation.etatVide(onglet)
            for texte in [vide.titre, vide.message, vide.action, MesMissionsPresentation.chargement(onglet)] {
                let plage = NSRange(texte.startIndex..., in: texte)
                XCTAssertNil(tutoiement.firstMatch(in: texte, range: plage), "« \(texte) » : vouvoiement sobre, swipe hors lot 1")
            }
        }
    }
}
