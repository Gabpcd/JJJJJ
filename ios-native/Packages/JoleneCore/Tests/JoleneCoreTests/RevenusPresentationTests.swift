import XCTest
@testable import JoleneCore

/// Présentation de l'onglet Revenus (lot 3, T12, B9 ; HARD STOP n°4 délégué) : libellés des sept états du paiement
/// rapide (`PaiementsEscrowAVenir.tsx` l.42-80, invariant « jamais garanti », tutoiement verbatim), lignes de mission
/// (`MesGains.tsx` l.698-786 : montant par `montantFinanceAfficheMission`, régime de la mission, état de la dernière
/// déclaration), totaux serveur (`PageStripeConnect.tsx` l.392-417), notes « net estimé » verbatim, renvois web. Chaque
/// texte repris du web figure tel quel à sa ligne source ; les textes adaptés au vouvoiement et ceux sans équivalent
/// web sont épinglés ici et listés dans `DECISIONS_LOT3.md` (section T12).
final class RevenusPresentationTests: XCTestCase {
    private typealias T = RevenusTextes

    private static let gains = "src/pages/MesGains.tsx"
    private static let escrow = "src/components/gains/PaiementsEscrowAVenir.tsx"
    private static let stripe = "src/pages/PageStripeConnect.tsx"
    private static let noteNetEstime = "src/components/NoteNetEstime.tsx"

    // MARK: - Verbatim (HARD STOP n°4)

    /// (texte natif, fichier web, ligne) : le texte figure tel quel à sa ligne (échappements `\'` ramenés à `'`).
    private static var attendus: [(String, String, Int)] {
        [
            (T.titre, gains, 837), (T.erreurTitre, gains, 367), (T.erreurDefaut, gains, 156), (T.reessayer, gains, 370),
            (T.videTitre, gains, 804), (T.videAction, gains, 804), (T.chargerPlus, gains, 799), (T.chargementSuite, gains, 799),
            (T.regimeAVerifier, gains, 764), (T.honorairesPrevisionnels, gains, 751), ("'brut du planning' : 'brut'", gains, 756),
            ("Voir mission ${m.intitule || ''}", gains, 703), ("🏥 {m.etablissements?.nom || '—'}", gains, 719),
            (T.factures, gains, 937), (T.paie, gains, 943), (T.noteSalariee, gains, 664), (T.noteLiberale, gains, 665),
            (T.noteCommune, gains, 666), ("<span>{m.taux_horaire_base} €/h</span>", gains, 733),
            ("<span>{Math.round(duree * 10) / 10}h</span>", gains, 732),
            ("{formatParis(m.debut_le, \"HH'h'mm\")} → {formatParis(m.fin_le, \"HH'h'mm\")}", gains, 730),
            ("select('id, intitule, debut_le, fin_le, duree_heures, nb_creneaux, taux_horaire_base, net_a_payer, net_estime, total_brut, statut, etablissement_id, service, type_contrat_applique, type_contrat_recherche, presences(valide_par_etablissement, valide_auto_72h_le, valide_le)')", gains, 95),
            ("p_action: 'DONNEES_PERSO_CONSULTATION'", gains, 149), ("p_type_ressource: 'soignant'", gains, 150),
            ("p_details: { page: 'mes_gains' }", gains, 151), ("const PAGE_SIZE = 50;", gains, 72),
            (T.kpiMois, stripe, 397), (T.kpiTotal, stripe, 404), (T.kpiAttente, stripe, 411), (T.noteTotaux, stripe, 417),
            (T.paiementRapide, escrow, 163), (T.aVenir, escrow, 168), (T.recemmentVerse, escrow, 175), (T.annules, escrow, 181),
            (T.escrowIndisponible, escrow, 117), (T.escrowErreurDefaut, escrow, 103), (T.reessayer, escrow, 120),
            (T.mission, escrow, 145),
            ("'Réservé'", escrow, 51), ("'le montant de ta confirmation, mis de côté'", escrow, 52),
            ("'En attente de validation des heures'", escrow, 55),
            ("\"l'établissement valide tes heures (automatique sous 72 h)\"", escrow, 56),
            ("`Versement en cours — estimé le ${jour(l.date_affichee)}`", escrow, 59), ("'Versement en cours'", escrow, 59),
            ("'ton virement est en route'", escrow, 61), ("'Paiement retardé'", escrow, 64),
            ("`nouvelle tentative le ${jour(l.date_affichee)}`", escrow, 65), ("'nous relançons le règlement'", escrow, 65),
            ("'Paiement en litige'", escrow, 68), ("'voir le litige de la mission'", escrow, 69),
            ("`Versé le ${jour(l.date_affichee)}`", escrow, 72), ("'Versé'", escrow, 72),
            ("'Paiement annulé'", escrow, 77), ("'contacte le support si besoin'", escrow, 78),
            ("toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' })", escrow, 40),
            ("verses.slice(0, 3)", escrow, 176),
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

    /// Libellés escrow : HARD STOP n°4 (`DECISIONS_LOT3.md`, « Restent verbatim web ») — tutoiement du web conservé,
    /// mot pour mot (décision du 09/11/2026 : le natif suit le web ; aucun « garanti »).
    func testLibellesEscrowVerbatimEnTutoiementSansGarantie() {
        let libelles = EtatEscrow.allCases.flatMap { etat -> [String] in
            let avecDate = RevenusPresentation.ligneEscrow(PaiementRapide(missionId: "m", honorairesCents: 1, etat: etat.rawValue,
                                                                         dateAffichee: "2026-11-04T08:00:00+00:00"))
            let sansDate = RevenusPresentation.ligneEscrow(PaiementRapide(missionId: "m", honorairesCents: 1, etat: etat.rawValue))
            return [avecDate?.libelle, avecDate?.detail, sansDate?.libelle, sansDate?.detail].compactMap { $0 }
        }
        for texte in libelles {
            XCTAssertFalse(texte.lowercased().contains("garanti"), "invariant I2 : jamais « garanti » (\(texte))")
            XCTAssertFalse(texte.contains("stationn"), "wording escrow : jamais « stationne » (\(texte))")
        }
    }

    /// Textes adaptés au vouvoiement (non juridiques, décision 9 du lot 1) ou sans équivalent web : épinglés, à relire
    /// par Gabrielle (`DECISIONS_LOT3.md`, section T12).
    func testTextesAdaptesOuSansEquivalentWeb() {
        XCTAssertEqual(T.sousTitre, "Vos gains, factures et documents de paie au même endroit")
        XCTAssertEqual(T.videDescription, "Vos gains apparaîtront ici après votre première mission terminée.")
        XCTAssertEqual(T.totauxIndisponibles, "Vos revenus sont temporairement indisponibles.")
        XCTAssertEqual(T.missionsTerminees, "Missions terminées")
        XCTAssertEqual(T.paiementSuiviDansFactures, "Paiement suivi dans Factures")
        XCTAssertEqual(T.noteNetEstime, AccueilPresentation.noteNetEstime, "note « net estimé » : une seule source (NoteNetEstime.tsx)")
    }

    func testNoteNetEstimeVerbatimDuComposantWeb() throws {
        // JSX : retours à la ligne et indentations réduits à une espace, comme le rendu du navigateur.
        let source = try CompteVerbatimTests.lignes(Self.noteNetEstime)[12...15]
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        XCTAssertEqual(source, T.noteNetEstime)
    }

    // MARK: - Paiements rapides

    private func ligne(_ etat: String, date: String? = nil, nom: String? = "Clinique", intitule: String? = "Nuit",
                       cents: Int = 24000) -> PaiementRapide {
        PaiementRapide(missionId: "m-\(etat)", missionIntitule: intitule, etablissementNom: nom, honorairesCents: cents,
                       etat: etat, dateAffichee: date)
    }

    func testLibelleEtAideDeChaqueEtat() throws {
        let date = "2026-11-04T08:00:00+00:00"
        let cas: [(String, String?, String, String, TonRevenus)] = [
            ("RESERVE", nil, "Réservé", "Clinique · le montant de ta confirmation, mis de côté", .info),
            ("ATTENTE_VALIDATION", nil, "En attente de validation des heures",
             "Clinique · l'établissement valide tes heures (automatique sous 72 h)", .info),
            ("VERSEMENT_EN_COURS", date, "Versement en cours — estimé le 04/11", "Clinique · ton virement est en route", .info),
            ("VERSEMENT_EN_COURS", nil, "Versement en cours", "Clinique · ton virement est en route", .info),
            ("RETARDE", date, "Paiement retardé", "Clinique · nouvelle tentative le 04/11", .alerte),
            ("RETARDE", nil, "Paiement retardé", "Clinique · nous relançons le règlement", .alerte),
            ("LITIGE", nil, "Paiement en litige", "Clinique · voir le litige de la mission", .alerte),
            ("VERSE", date, "Versé le 04/11", "Clinique", .succes),
            ("VERSE", nil, "Versé", "Clinique", .succes),
            ("ANNULE", nil, "Paiement annulé", "Clinique · contacte le support si besoin", .neutre),
        ]
        for (etat, dateAffichee, libelle, detail, ton) in cas {
            let affichee = try XCTUnwrap(RevenusPresentation.ligneEscrow(ligne(etat, date: dateAffichee)), etat)
            XCTAssertEqual(affichee.libelle, libelle, etat)
            XCTAssertEqual(affichee.detail, detail, etat)
            XCTAssertEqual(affichee.ton, ton, etat)
            XCTAssertEqual(affichee.montant, "240,00\u{00A0}€", "honoraires_cents / 100, jamais recalculé (règle #11)")
            XCTAssertEqual(affichee.ouvreMission, etat == "LITIGE", "seul le litige mène au détail de la mission (web l.152-155)")
        }
        XCTAssertNil(RevenusPresentation.ligneEscrow(ligne("INCONNU")), "état hors des sept : ligne non affichée (web l.134-135)")
    }

    /// `l.etablissement_nom || l.mission_intitule || 'Mission'` : une chaîne vide cède la place, comme `||` en JavaScript.
    func testRepliDuNomDeLaLigne() throws {
        XCTAssertEqual(RevenusPresentation.ligneEscrow(ligne("VERSE", nom: nil))?.detail, "Nuit")
        XCTAssertEqual(RevenusPresentation.ligneEscrow(ligne("VERSE", nom: ""))?.detail, "Nuit")
        XCTAssertEqual(RevenusPresentation.ligneEscrow(ligne("VERSE", nom: nil, intitule: nil))?.detail, "Mission")
        XCTAssertEqual(RevenusPresentation.ligneEscrow(ligne("RESERVE", nom: "", intitule: ""))?.detail,
                       "Mission · le montant de ta confirmation, mis de côté")
    }

    /// Jour `jj/mm` à l'heure de Paris (le web : heure locale de l'appareil, identique sur un appareil réglé sur la France).
    func testJourDuMoisEnHeureDeParis() {
        XCTAssertEqual(RevenusPresentation.jourMois("2026-10-31T23:30:00+00:00"), "01/11", "minuit passé à Paris (UTC+1)")
        XCTAssertEqual(RevenusPresentation.jourMois("2026-07-14T21:59:00+00:00"), "14/07", "heure d'été (UTC+2)")
        XCTAssertNil(RevenusPresentation.jourMois(nil))
        XCTAssertNil(RevenusPresentation.jourMois(""))
        XCTAssertNil(RevenusPresentation.jourMois("pas une date"))
    }

    /// Groupes du web (l.129-131, l.166-184) : « À venir » (cinq états), « Récemment versé » (trois au plus), « Annulés » ;
    /// ordre serveur conservé dans chaque groupe ; section présente dès qu'une ligne existe (I5 : absente sinon).
    func testGroupesAVenirVersesEtAnnules() {
        let lignes = ["RETARDE", "LITIGE", "ATTENTE_VALIDATION", "VERSEMENT_EN_COURS", "RESERVE"].map { ligne($0) }
            + (1...4).map { PaiementRapide(missionId: "v-\($0)", honorairesCents: 100 * $0, etat: "VERSE") }
            + [ligne("ANNULE"), ligne("INCONNU")]
        let affiche = RevenusPresentation.escrow(lignes)
        XCTAssertTrue(affiche.afficheSection)
        XCTAssertEqual(affiche.aVenir.map(\.etat), [.retarde, .litige, .attenteValidation, .versementEnCours, .reserve])
        XCTAssertEqual(affiche.verses.map(\.missionId), ["v-1", "v-2", "v-3"], "`verses.slice(0, 3)`")
        XCTAssertEqual(affiche.annules.map(\.missionId), ["m-ANNULE"])
        XCTAssertFalse(RevenusPresentation.escrow([]).afficheSection, "I5 : aucune ligne → section absente")
        let inconnue = RevenusPresentation.escrow([ligne("INCONNU")])
        XCTAssertTrue(inconnue.afficheSection, "le web affiche l'en-tête dès qu'une ligne existe (l.127)")
        XCTAssertTrue(inconnue.aVenir.isEmpty && inconnue.verses.isEmpty && inconnue.annules.isEmpty)
    }

    // MARK: - Missions terminées

    private func mission(_ id: String, applique: String?, recherche: String? = nil, net: Double? = nil, netEstime: Double? = nil,
                         brut: Double? = nil, paiement: PaiementSoignantLu? = nil, nom: String? = "Clinique",
                         service: String? = "Urgences") -> MissionTerminee {
        MissionTerminee(id: id, intitule: "Nuit", debutLe: "2026-11-01T07:00:00+00:00", finLe: "2026-11-01T15:00:00+00:00",
                        etablissementId: "e-1", typeContratApplique: applique, typeContratRecherche: recherche,
                        netAPayer: net, netEstime: netEstime, totalBrut: brut, dureeHeures: 8, tauxHoraireBase: 26,
                        service: service, statut: "TERMINEE", etablissementNom: nom, dernierPaiement: paiement)
    }

    func testLigneSalarieeNetEstimeEtEtatDeLaDeclaration() {
        let declare = PaiementSoignantLu(id: "p", missionId: "m-s", statut: "DECLARE", montantNet: .nombre(162.4))
        let ligne = RevenusPresentation.mission(mission("m-s", applique: "SALARIE", net: 224.6, netEstime: 162.4, brut: 208, paiement: declare))
        XCTAssertEqual(ligne.montant, "162,40\u{00A0}€", "net_estime seul, jamais net_a_payer")
        XCTAssertTrue(ligne.approximatif)
        XCTAssertEqual(ligne.nature, "Net salarié estimé*")
        XCTAssertEqual(ligne.details, ["brut : 208,00\u{00A0}€"])
        XCTAssertEqual(ligne.etat, EtatLigneRevenus(texte: "Réception à confirmer", ton: .neutre))
        XCTAssertEqual(ligne.titre, "Nuit")
        XCTAssertEqual(ligne.sousTitre, "🏥 Clinique · Urgences")
        XCTAssertEqual(ligne.horaires, "08h00 → 16h00 · 8h · 26 €/h")
        XCTAssertEqual(ligne.jour, AccueilPresentation.Jour(semaine: "dim.", jour: "1", mois: "nov."))
        XCTAssertEqual(ligne.actionAccessible, "Voir mission Nuit")
        let confirme = PaiementSoignantLu(id: "p", missionId: "m-s", statut: "CONFIRME", montantNet: .nombre(162.4), confirmeParSoignant: true)
        XCTAssertEqual(RevenusPresentation.mission(mission("m-s", applique: "SALARIE", paiement: confirme)).etat,
                       EtatLigneRevenus(texte: "Réception confirmée", ton: .succes))
        let conteste = PaiementSoignantLu(id: "p", missionId: "m-s", statut: "CONTESTE", conteste: true)
        XCTAssertEqual(RevenusPresentation.mission(mission("m-s", applique: "SALARIE", paiement: conteste)).etat,
                       EtatLigneRevenus(texte: "Paiement contesté", ton: .erreur))
        XCTAssertEqual(RevenusPresentation.mission(mission("m-s", applique: "SALARIE")).etat,
                       EtatLigneRevenus(texte: "Aucun versement déclaré", ton: .neutre))
    }

    /// Libéral : honoraires prévisionnels du planning (`net_a_payer`, puis `total_brut`) ; l'état de paiement du web vient
    /// des factures d'honoraires (lot 4) : le natif n'en déduit rien et renvoie à l'onglet Factures (texte sans équivalent web).
    func testLigneLiberaleHonorairesEtRenvoiAuxFactures() {
        let paiement = PaiementSoignantLu(id: "p", missionId: "m-l", statut: "CONFIRME", confirmeParSoignant: true)
        let ligne = RevenusPresentation.mission(mission("m-l", applique: "LIBERAL", net: 256, brut: 256, paiement: paiement))
        XCTAssertEqual(ligne.montant, "256,00\u{00A0}€")
        XCTAssertFalse(ligne.approximatif)
        XCTAssertEqual(ligne.nature, "Honoraires prévisionnels du planning")
        XCTAssertEqual(ligne.details, ["brut du planning : 256,00\u{00A0}€"])
        XCTAssertEqual(ligne.etat, EtatLigneRevenus(texte: "Paiement suivi dans Factures", ton: .neutre))
    }

    /// Contrat non choisi : rémunération brute indicative, « Régime à vérifier » (web l.763-765) ; le régime vient du contrat
    /// de la mission (appliqué puis recherché), jamais du profil.
    func testLigneSansRegimeBrutIndicatifEtRegimeAVerifier() {
        let ligne = RevenusPresentation.mission(mission("m-n", applique: nil, recherche: "TOUS", brut: 240, nom: nil, service: nil))
        XCTAssertEqual(ligne.montant, "240,00\u{00A0}€")
        XCTAssertTrue(ligne.approximatif)
        XCTAssertEqual(ligne.nature, "Rémunération brute indicative")
        XCTAssertEqual(ligne.details, ["brut : 240,00\u{00A0}€"])
        XCTAssertEqual(ligne.etat, EtatLigneRevenus(texte: "Régime à vérifier", ton: .neutre))
        XCTAssertEqual(ligne.sousTitre, "🏥 —", "nom absent : tiret du web, service absent omis")
        let parRecherche = RevenusPresentation.mission(mission("m-r", applique: nil, recherche: "LIBERAL", net: 100))
        XCTAssertEqual(parRecherche.etat.texte, "Paiement suivi dans Factures", "régime recherché à défaut d'appliqué")
    }

    func testLigneSansMontantServeur() {
        let ligne = RevenusPresentation.mission(mission("m-0", applique: "SALARIE", net: 224.6))
        XCTAssertNil(ligne.montant, "net_estime absent : aucun montant, jamais net_a_payer")
        XCTAssertNil(ligne.nature)
        XCTAssertEqual(ligne.details, [], "total_brut absent : pas de ligne brut")
    }

    /// Horaires et durée comme le web (l.729-733) : durée serveur sinon fin − début, arrondie au dixième
    /// (`Math.round(duree * 10) / 10`), nombres écrits comme JavaScript ; une valeur illisible est omise.
    func testHorairesDureeEtTauxCommeLeWeb() {
        var m = mission("m", applique: "SALARIE")
        m.dureeHeures = 7.25
        m.tauxHoraireBase = 27.5
        XCTAssertEqual(RevenusPresentation.mission(m).horaires, "08h00 → 16h00 · 7.3h · 27.5 €/h")
        m.dureeHeures = nil
        m.finLe = "2026-11-01T14:30:00+00:00"
        XCTAssertEqual(RevenusPresentation.mission(m).horaires, "08h00 → 15h30 · 7.5h · 27.5 €/h")
        m.tauxHoraireBase = nil
        m.debutLe = nil
        XCTAssertNil(RevenusPresentation.mission(m).horaires)
        XCTAssertNil(RevenusPresentation.mission(m).jour)
    }

    func testNotesDeBasDePageSelonLesContratsAppliques() {
        let salariee = mission("s", applique: "SALARIE")
        let liberale = mission("l", applique: "LIBERAL")
        let recherche = mission("r", applique: nil, recherche: "SALARIE")
        XCTAssertEqual(RevenusPresentation.noteBasDePage([salariee, liberale]), T.noteSalariee + T.noteLiberale + T.noteCommune)
        XCTAssertEqual(RevenusPresentation.noteBasDePage([liberale]), T.noteLiberale + T.noteCommune)
        XCTAssertEqual(RevenusPresentation.noteBasDePage([recherche]), T.noteCommune, "salMissions filtre `type_contrat_applique` seul (l.249)")
        XCTAssertTrue(RevenusPresentation.afficheNoteNetEstime([salariee]))
        XCTAssertFalse(RevenusPresentation.afficheNoteNetEstime([liberale, recherche]))
    }

    // MARK: - Renvois web

    func testRenvoisWebCanoniques() throws {
        XCTAssertEqual(RevenusPresentation.renvoiWeb(RevenusPresentation.lienFactures),
                       .safari(try XCTUnwrap(URL(string: "https://jolene.app/soignant/mes-gains?tab=factures"))))
        XCTAssertEqual(RevenusPresentation.renvoiWeb(RevenusPresentation.lienBulletins),
                       .safari(try XCTUnwrap(URL(string: "https://jolene.app/soignant/mes-gains?tab=bulletins"))))
        XCTAssertEqual(RevenusPresentation.renvoiWeb(RevenusPresentation.lienPresences(missionId: "m-1")),
                       .safari(try XCTUnwrap(URL(string: "https://jolene.app/soignant/presences/mission/m-1"))),
                       "détail des présences (lot 2) : `navigate('/soignant/presences/mission/${m.id}')`, l.705")
        XCTAssertNil(RevenusPresentation.renvoiWeb("/soignant/mes-gains"), "l'aperçu est natif : jamais un renvoi")
    }

    func testMontantDesTotauxFormatesCommeLeWeb() {
        XCTAssertEqual(RevenusPresentation.euros(1425.6), "1\u{202F}425,60\u{00A0}€")
        XCTAssertEqual(RevenusPresentation.euros(0), "0,00\u{00A0}€")
    }
}
