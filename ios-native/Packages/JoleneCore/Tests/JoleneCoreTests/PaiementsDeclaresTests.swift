import XCTest
@testable import JoleneCore

/// Paiements déclarés (lot 3, T13, B9 ; HARD STOP n°4 délégué, TJ7) : textes verbatim du bandeau web
/// (`src/components/BandeauPaiementDeclare.tsx`) à leur ligne, deux textes vouvoyés épinglés, décodage des lignes
/// PostgREST (colonnes l.97, l.122, l.132, l.137), assemblage, règle de relecture après mutation (jamais un succès sans
/// relecture probante) et présentation de la carte (détail du web, aucun montant recalculé).
final class PaiementsDeclaresTests: XCTestCase {
    private typealias T = PaiementsDeclaresTextes
    private static let bandeau = "src/components/BandeauPaiementDeclare.tsx"
    private static let gains = "src/pages/MesGains.tsx"

    // MARK: - Verbatim (HARD STOP n°4)

    /// (texte natif, fichier web, ligne) : le texte figure tel quel à sa ligne (échappements `\'` ramenés à `'`).
    private static var attendus: [(String, String, Int)] {
        [
            (T.motifTitre, bandeau, 51), (T.envoyerContestation, bandeau, 62), (T.annuler, bandeau, 64),
            (T.confirmerReception, bandeau, 397), (T.contester, bandeau, 407),
            ("toast.success(confirme ? '\(T.paiementConfirme)' : '\(T.contestationEnvoyee)')", bandeau, 195),
            ("toast.error('\(T.erreurTraitement)')", bandeau, 200), (T.indisponibles, bandeau, 208),
            (T.erreurChargement, bandeau, 170), (T.reessayer, bandeau, 211), ("|| '\(T.etablissementDefaut)'", bandeau, 161),
            (T.mission, bandeau, 264), (T.indication, bandeau, 268), (T.methode, bandeau, 282), (T.date, bandeau, 288),
            (T.reference, bandeau, 295), (T.tauxRetenu, bandeau, 324), ("(\(T.demande) ${fmt(", bandeau, 326),
            (T.heuresRetenues, bandeau, 330), (T.brut, bandeau, 332), (T.montantDeclare, bandeau, 333),
            (T.pointagesEnregistres, bandeau, 342), (T.pointagesEnregistres, bandeau, 363), (T.pausePrecedente, bandeau, 352),
            (T.segment, bandeau, 354), (T.arrivee, bandeau, 371), (T.depart, bandeau, 374), (T.planifiees, bandeau, 318),
            ("'🏦 Virement'", bandeau, 72), ("'📝 Chèque'", bandeau, 73), ("'📄 Note d'honoraires'", bandeau, 74),
            ("'💳 Stripe Connect'", bandeau, 75), ("'💵 Espèces'", bandeau, 76), ("if (!m) return '—';", bandeau, 71),
            ("'📍 GPS' : '🔢 Code'", bandeau, 378), ("créneau${creneauxPlanifies.length > 1 ? 'x' : ''}", bandeau, 318),
            ("segment{creneauxEffectifs.length > 1 ? 's' : ''}", bandeau, 342),
            // Colonnes et filtres lus (gateways Supabase et démo).
            (".select('id, montant_net, mission_id, etablissement_id, reference_virement, methode, date_paiement')", bandeau, 97),
            (".eq('statut', 'DECLARE')", bandeau, 99),
            (".select('id, intitule, debut_le, fin_le, duree_heures, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique, total_brut, net_a_payer')", bandeau, 122),
            (".select('mission_id, pointage_arrivee_le, pointage_depart_le, methode_pointage_arrivee, heures_ajustees_litige')", bandeau, 132),
            (".select('id, mission_id, debut, fin, est_pause, type_creneau')", bandeau, 137),
            ("maxLength={500}", bandeau, 58), ("disabled={!motif.trim()}", bandeau, 61),
            // Règles de présentation reprises.
            ("p.mission?.rist_plafond_applique && p.mission.taux_rist_plafonne != null", bandeau, 236),
            ("<BandeauPaiementDeclare onUpdate={() => setReloadKey((key) => key + 1)} />", gains, 383),
        ]
    }

    func testChaqueTexteRepriseDuWebEstVerbatimASaLigne() throws {
        var lignes: [String: [String]] = [:]
        for (texte, fichier, ligne) in Self.attendus {
            if lignes[fichier] == nil { lignes[fichier] = try CompteVerbatimTests.lignes(fichier) }
            let source = try XCTUnwrap(lignes[fichier])
            XCTAssertGreaterThanOrEqual(source.count, ligne, fichier)
            let brute = source[ligne - 1].replacingOccurrences(of: "\\'", with: "'")
            XCTAssertTrue(brute.contains(texte), "« \(texte) » absent de \(fichier) l.\(ligne)")
        }
    }

    /// Deux textes tutoyés non juridiques passent au vouvoiement : l.55 (TJ7, décision 9 du lot 1) et l.259 (décision 9
    /// du lot 1, TJ8) ; leur source est épinglée (si le web change, le test rougit). Le motif de repli du web n'est jamais
    /// une constante native (TJ7).
    func testTextesVouvoyesEtRepliDuWebAbsent() throws {
        let source = try CompteVerbatimTests.lignes(Self.bandeau)
        XCTAssertTrue(source[54].contains("placeholder=\"Décris pourquoi tu contestes ce paiement...\""), "l.55")
        XCTAssertEqual(T.motifPlaceholder, "Décrivez pourquoi vous contestez ce paiement...")
        XCTAssertTrue(source[258].contains("{p.etablissement_nom} déclare t'avoir payé{' '}"), "l.259")
        XCTAssertEqual(T.declareVousAvoirPaye, "déclare vous avoir payé")
        // Repli `'Contesté par le soignant'` (l.61, l.190) : jamais envoyé (TJ7).
        XCTAssertTrue(source[60].contains("'Contesté par le soignant'") && source[189].contains("'Contesté par le soignant'"))
        let natifs = [T.motifTitre, T.motifPlaceholder, T.envoyerContestation, T.annuler, T.confirmerReception, T.contester,
                      T.paiementConfirme, T.contestationEnvoyee, T.erreurTraitement]
        XCTAssertFalse(natifs.contains { $0.contains("Contesté par le soignant") })
    }

    /// TJ7 : aucun texte sur la portée juridique d'une confirmation ou d'une contestation (ni renonciation, ni délai).
    func testAucunTexteJuridiqueAjoute() {
        let textes = [T.motifTitre, T.motifPlaceholder, T.envoyerContestation, T.annuler, T.confirmerReception, T.contester,
                      T.paiementConfirme, T.contestationEnvoyee, T.erreurTraitement, T.indisponibles, T.erreurChargement,
                      T.indication, T.declareVousAvoirPaye]
        for texte in textes {
            for interdit in ["renonc", "délai", "72", "jours", "irrévocable", "définitif", "juridique", "article", "Code "] {
                XCTAssertFalse(texte.localizedCaseInsensitiveContains(interdit), "« \(texte) » contient « \(interdit) »")
            }
        }
    }

    // MARK: - Décodage

    func testLigneDeclareeColonnesDuWebEtMontantNumerique() throws {
        let json = """
        [{"id":"p-1","montant_net":"162.40","mission_id":"m-1","etablissement_id":"e-1","reference_virement":null,
          "methode":"VIREMENT","date_paiement":"2026-11-01"},
         {"id":"p-2","montant_net":256,"mission_id":"m-2","etablissement_id":"e-2","reference_virement":"VIR-1",
          "methode":"CHEQUE","date_paiement":null,"statut":"CONTESTE","confirme_par_soignant":false,"conteste":true}]
        """
        let lignes = try JSONDecoder().decode([LignePaiementDeclare].self, from: Data(json.utf8))
        XCTAssertEqual(lignes.map(\.montantNet), [162.4, 256])
        XCTAssertNil(lignes[0].statut, "colonnes de l.97 : pas de statut dans la liste")
        XCTAssertEqual(lignes[1].statut, "CONTESTE")
        XCTAssertEqual(lignes[1].conteste, true)
        // `montant_net` est `numeric NOT NULL` : illisible → décalage de contrat, jamais un zéro affiché.
        for corps in [#"[{"id":"p","montant_net":null,"mission_id":"m","etablissement_id":"e"}]"#,
                      #"[{"id":"p","montant_net":"abc","mission_id":"m","etablissement_id":"e"}]"#,
                      #"[{"id":"","montant_net":1,"mission_id":"m","etablissement_id":"e"}]"#] {
            XCTAssertThrowsError(try JSONDecoder().decode([LignePaiementDeclare].self, from: Data(corps.utf8)), corps)
        }
    }

    func testAssemblageNomsMissionsPresencesEtCreneauxParMission() {
        let lignes = [LignePaiementDeclare(id: "p-1", montantNet: 10, missionId: "m-1", etablissementId: "e-1", methode: "VIREMENT"),
                      LignePaiementDeclare(id: "p-2", montantNet: 20, missionId: "m-2", etablissementId: "e-2")]
        let assembles = PaiementsDeclaresAssemblage.assembler(
            lignes, etablissements: ["e-1": "Clinique"],
            missions: [MissionPaiementDeclare(id: "m-1", intitule: "Nuit")],
            presences: [PresencePaiementDeclare(missionId: "m-1"), PresencePaiementDeclare(missionId: "m-3")],
            creneaux: [CreneauPaiementDeclare(id: "c-1", missionId: "m-2", debut: "2026-11-01T07:00:00+00:00")])
        XCTAssertEqual(assembles.map(\.id), ["p-1", "p-2"], "ordre serveur")
        XCTAssertEqual(assembles.map(\.statut), ["DECLARE", "DECLARE"], "liste filtrée sur DECLARE (l.99)")
        XCTAssertEqual(assembles[0].etablissementNom, "Clinique")
        XCTAssertNil(assembles[1].etablissementNom, "fn_etablissements_safe seul : aucun nom deviné")
        XCTAssertEqual(PaiementsDeclaresPresentation.carte(assembles[1]).nom, "Établissement", "repli du web, l.161")
        XCTAssertEqual(assembles[0].mission?.intitule, "Nuit")
        XCTAssertNil(assembles[1].mission)
        XCTAssertEqual(assembles[0].presences.count, 1)
        XCTAssertEqual(assembles[1].creneaux.map(\.id), ["c-1"])
        XCTAssertEqual(PaiementsDeclaresAssemblage.identifiants(["m-1", "", "m-2", "m-1"]), ["m-1", "m-2"])
    }

    // MARK: - Relecture après mutation (jamais un succès sans relecture probante)

    private func paiement(statut: String, confirme: Bool = false, conteste: Bool = false) -> PaiementDeclare {
        PaiementDeclare(id: "p-1", missionId: "m-1", etablissementId: "e-1", montantNet: 162.4, methode: "VIREMENT",
                        statut: statut, confirmeParSoignant: confirme, conteste: conteste)
    }

    func testConfirmationExigeLaRelectureCONFIRMEEtLAccordDuSoignant() throws {
        let relue = paiement(statut: "CONFIRME", confirme: true)
        XCTAssertEqual(try PaiementsDeclaresRelecture.confirmation(relue: relue), .confirme(relue))
        for nonProbante in [nil, paiement(statut: "DECLARE"), paiement(statut: "CONFIRME", confirme: false),
                            paiement(statut: "CONTESTE", conteste: true)] as [PaiementDeclare?] {
            XCTAssertThrowsError(try PaiementsDeclaresRelecture.confirmation(relue: nonProbante)) { erreur in
                XCTAssertEqual(erreur as? JoleneError, JoleneError(.unknown, "Erreur lors du traitement"))
            }
        }
    }

    /// `{success, litige_id}` sans relecture `CONTESTE` → erreur, jamais un succès (blueprint §3 T13).
    func testContestationExigeLaRelectureCONTESTE() throws {
        let relue = paiement(statut: "CONTESTE", conteste: true)
        XCTAssertEqual(try PaiementsDeclaresRelecture.contestation(relue: relue, litigeId: "l-1"), .conteste(relue, litigeId: "l-1"))
        for nonProbante in [nil, paiement(statut: "DECLARE"), paiement(statut: "CONTESTE", conteste: false),
                            paiement(statut: "CONFIRME", confirme: true)] as [PaiementDeclare?] {
            XCTAssertThrowsError(try PaiementsDeclaresRelecture.contestation(relue: nonProbante, litigeId: "l-1")) { erreur in
                XCTAssertEqual((erreur as? JoleneError)?.message, "Erreur lors du traitement")
            }
        }
    }

    // MARK: - Motif

    func testMotifBorneA500ScalairesUnicode() {
        XCTAssertEqual(PaiementsDeclaresModel.longueurMaxMotif, 500)
        let long = String(repeating: "a", count: 520)
        XCTAssertEqual(PaiementsDeclaresModel.limiter(long).unicodeScalars.count, 500)
        // Un emoji composé compte plusieurs scalaires côté serveur (`char_length`) : la borne porte sur les scalaires.
        let emojis = String(repeating: "👩‍⚕️", count: 200)
        XCTAssertLessThanOrEqual(PaiementsDeclaresModel.limiter(emojis).unicodeScalars.count, 500)
        XCTAssertEqual(PaiementsDeclaresModel.limiter("Montant erroné"), "Montant erroné")
    }

    // MARK: - Présentation

    private func complet() -> PaiementDeclare {
        PaiementDeclare(
            id: "p-1", missionId: "m-1", etablissementId: "e-1", montantNet: 162.4, methode: "VIREMENT",
            referenceVirement: "VIR-1", datePaiement: "2026-11-01", statut: "DECLARE", etablissementNom: "Clinique des Tests",
            mission: MissionPaiementDeclare(id: "m-1", intitule: "Nuit", debutLe: "2026-11-01T07:00:00+00:00",
                                            finLe: "2026-11-01T15:00:00+00:00", tauxHoraireBase: 30, tauxRistPlafonne: 26,
                                            ristPlafondApplique: true, totalBrut: 208),
            presences: [PresencePaiementDeclare(missionId: "m-1", pointageArriveeLe: "2026-11-01T07:05:00+00:00",
                                                heuresAjusteesLitige: 7.5)],
            creneaux: [
                CreneauPaiementDeclare(id: "c-p", missionId: "m-1", debut: "2026-11-01T07:00:00+00:00",
                                       fin: "2026-11-01T15:00:00+00:00", estPause: false, typeCreneau: "PREVISIONNEL"),
                CreneauPaiementDeclare(id: "c-e1", missionId: "m-1", debut: "2026-11-01T07:05:00+00:00",
                                       fin: "2026-11-01T11:00:00+00:00", estPause: false, typeCreneau: "EFFECTIF"),
                CreneauPaiementDeclare(id: "c-e2", missionId: "m-1", debut: "2026-11-01T11:30:00+00:00",
                                       fin: "2026-11-01T15:00:00+00:00", estPause: false, typeCreneau: "EFFECTIF"),
                CreneauPaiementDeclare(id: "c-o", missionId: "m-1", debut: "2026-11-01T15:30:00+00:00", fin: nil,
                                       estPause: false, typeCreneau: "EFFECTIF"),
            ])
    }

    func testCarteCompleteCommeLeBandeauDuWeb() {
        let carte = PaiementsDeclaresPresentation.carte(complet())
        let nbsp = "\u{00A0}"
        XCTAssertEqual(carte.titre, "💰 Clinique des Tests déclare vous avoir payé 162,40\(nbsp)€")
        // Revue B8 n°1, m5 : l'en-tête rendu (`prefixe` puis `montant` en couleur) et son libellé d'accessibilité
        // (`titre`) ont une seule source ; le séparateur `{' '}` de l.259 appartient au préfixe.
        XCTAssertEqual(carte.prefixe, "💰 Clinique des Tests déclare vous avoir payé ")
        XCTAssertEqual(carte.montant, "162,40\(nbsp)€")
        XCTAssertEqual(carte.titre, carte.prefixe + carte.montant)
        XCTAssertEqual(carte.mission, "Mission : Nuit")
        XCTAssertEqual(carte.indication, "Touchez pour voir le détail · Confirmez ou contestez")
        XCTAssertEqual(carte.infos.map { "\($0.libelle) \($0.valeur)" },
                       ["Méthode : 🏦 Virement", "Date : 1 nov. 2026", "Référence : VIR-1"])
        let mission = carte.blocMission
        XCTAssertNotNil(mission)
        XCTAssertEqual(mission?.periode, "dim. 1 nov. 2026", "un seul créneau planifié : date du début de mission")
        XCTAssertEqual(mission?.horaires, "1 créneau · 8h00 planifiées")
        XCTAssertEqual(mission?.taux, "Taux retenu : 26,00\(nbsp)€/h (demandé : 30,00\(nbsp)€/h)", "taux Rist appliqué (l.236-238)")
        XCTAssertEqual(mission?.heuresRetenues, "Heures retenues après litige : 7h30")
        XCTAssertEqual(mission?.brut, "Brut : 208,00\(nbsp)€")
        XCTAssertEqual(mission?.montantDeclare, "Montant déclaré : 162,40\(nbsp)€")
        // Segments effectifs fermés (le créneau ouvert est ignoré), pause entre segments, heures de Paris.
        XCTAssertEqual(carte.pointages?.titre, "Pointages enregistrés · 2 segments")
        XCTAssertEqual(carte.pointages?.lignes, ["Segment 1 · 1 nov. · 08h05 → 12h00 · 3h55",
                                                 "Pause précédente : 0h30",
                                                 "Segment 2 · 1 nov. · 12h30 → 16h00 · 3h30"])
    }

    func testCarteSansSegmentNiMissionEtMethodesDuWeb() {
        var p = complet()
        p.creneaux = []
        p.presences = [PresencePaiementDeclare(missionId: "m-1", pointageArriveeLe: "2026-10-20T07:00:00+00:00",
                                               pointageDepartLe: "2026-10-20T15:00:00+00:00", methodePointageArrivee: "CODE")]
        p.mission?.ristPlafondApplique = false
        let carte = PaiementsDeclaresPresentation.carte(p)
        XCTAssertEqual(carte.blocMission?.horaires, "08h00 → 16h00", "sans créneau planifié : horaires de la mission")
        XCTAssertEqual(carte.blocMission?.taux, "Taux retenu : 30,00\u{00A0}€/h", "sans Rist : taux de base, sans « demandé »")
        XCTAssertEqual(carte.pointages?.titre, "Pointages enregistrés")
        XCTAssertEqual(carte.pointages?.lignes, ["20 oct. · Arrivée : 09h00 · Départ : 17h00 · (🔢 Code)"])
        p.presences = []
        p.mission = nil
        p.datePaiement = nil
        p.referenceVirement = nil
        let nue = PaiementsDeclaresPresentation.carte(p)
        XCTAssertNil(nue.mission)
        XCTAssertNil(nue.blocMission)
        XCTAssertNil(nue.pointages)
        XCTAssertEqual(nue.infos.map(\.cle), ["methode"])
        let methodes = ["VIREMENT", "CHEQUE", "NOTE_HONORAIRES", "STRIPE_CONNECT", "ESPECES", "BULLETIN_PAIE", ""]
            .map(PaiementsDeclaresPresentation.methode)
        XCTAssertEqual(methodes, ["🏦 Virement", "📝 Chèque", "📄 Note d'honoraires", "💳 Stripe Connect", "💵 Espèces",
                                  "BULLETIN_PAIE", "—"])
    }

    func testPeriodeSurPlusieursCreneauxPlanifies() {
        var p = complet()
        p.creneaux = [
            CreneauPaiementDeclare(id: "a", missionId: "m-1", debut: "2026-11-01T07:00:00+00:00", fin: "2026-11-01T15:00:00+00:00",
                                   estPause: false, typeCreneau: "PREVISIONNEL"),
            CreneauPaiementDeclare(id: "pause", missionId: "m-1", debut: "2026-11-01T11:00:00+00:00", fin: "2026-11-01T11:30:00+00:00",
                                   estPause: true, typeCreneau: "PREVISIONNEL"),
            CreneauPaiementDeclare(id: "b", missionId: "m-1", debut: "2026-11-03T07:00:00+00:00", fin: "2026-11-03T11:00:00+00:00",
                                   estPause: false, typeCreneau: "PREVISIONNEL"),
        ]
        let mission = PaiementsDeclaresPresentation.carte(p).blocMission
        XCTAssertEqual(mission?.periode, "1 nov. 2026 → 3 nov. 2026")
        XCTAssertEqual(mission?.horaires, "2 créneaux · 12h00 planifiées", "pause exclue")
    }
}
