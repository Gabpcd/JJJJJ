import XCTest
@testable import JoleneCore

/// Textes de « Mes évaluations », de « Mon score » et de la contestation d'un événement de score (L4-T9, HARD STOP
/// n°4 : aucun texte nouveau à portée juridique) : chaque texte affiché figure mot pour mot à sa ligne du web ; les
/// textes tutoyés du web passent au vouvoiement (décision 9 du lot 1) et leur forme web reste à sa ligne ; les motifs
/// de contestation sont ceux de `ModaleReclamationScore.tsx` (valeur et libellé). Les seuls textes sans équivalent web
/// sont des libellés techniques listés ici (`natifs`).
final class EvaluationsScoreVerbatimTests: XCTestCase {
    private typealias E = EvaluationsTextes
    private typealias S = ScoreTextes

    private static func sourceDepot(_ chemin: String) throws -> [String] {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent(chemin)
        guard FileManager.default.fileExists(atPath: fichier.path) else {
            throw XCTSkip("\(chemin) introuvable : \(fichier.path)")
        }
        return try String(contentsOf: fichier, encoding: .utf8).components(separatedBy: "\n").map(decoder)
    }

    /// Texte rendu d'une ligne de source : entités HTML du JSX et apostrophe échappée d'un littéral JavaScript.
    private static func decoder(_ ligne: String) -> String {
        ligne.replacingOccurrences(of: "\\'", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: "\u{00A0}")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static let evaluations = "src/pages/EvaluationsSoignant.tsx"
    private static let score = "src/pages/PageScoreSoignant.tsx"
    private static let breakdown = "src/components/BreakdownScore.tsx"
    private static let badge = "src/components/BadgeNiveauV2.tsx"
    private static let graphique = "src/components/GraphiqueEvolutionScore.tsx"
    private static let notations = "src/components/NotationsRecues.tsx"
    private static let modale = "src/components/score/ModaleReclamationScore.tsx"

    /// (texte, fichier web, ligne) : le texte figure tel quel à sa ligne source.
    private static var attendus: [(String, String, Int)] {
        var lignes: [(String, String, Int)] = [
            // Mes évaluations
            (E.titre, evaluations, 58), (E.enTete, evaluations, 117), (E.noteMoyenne, evaluations, 128),
            (E.pasEncoreDEvaluation, evaluations, 135), (E.totalEvaluations, evaluations, 139), (E.pct5Etoiles, evaluations, 143),
            (E.evolution6m, evaluations, 148), (E.dernierMois, evaluations, 155), (E.graphiqueTitre, evaluations, 164),
            (E.filtrePeriode, evaluations, 191), (E.libelle(.tout), evaluations, 193), (E.libelle(.troisMois), evaluations, 194),
            (E.libelle(.sixMois), evaluations, 195), (E.libelle(.douzeMois), evaluations, 196),
            (E.filtreNote, evaluations, 202), (E.toutesNotes, evaluations, 204), (E.libelle(noteMin: 5), evaluations, 205),
            (E.libelle(noteMin: 4), evaluations, 206), (E.libelle(noteMin: 3), evaluations, 207),
            (E.filtreEtablissement, evaluations, 213), (E.tousEtablissements, evaluations, 215),
            ("{total} évaluation{total > 1 ? 's' : ''}", evaluations, 223),
            (E.videTitre, evaluations, 240), (E.videDescription, evaluations, 240),
            ("« {n.commentaire} »", evaluations, 299), (E.dejaSignalee, evaluations, 321),
            (E.signalerCetteEvaluation, evaluations, 321), ("Page {page + 1} / {totalPages}", evaluations, 332),
            (E.precedent, evaluations, 334), (E.suivant, evaluations, 335), (E.erreurChargement, evaluations, 93),
            ("const PAR_PAGE = \(EvaluationsDecodage.parPage);", evaluations, 41),
            ("motif.trim().length < \(EvaluationsPresentation.longueurMotifMin)", evaluations, 458),
            // Feuille de signalement (modale jumelle, déjà vouvoyée)
            (E.signalementTitre, notations, 165), (E.signalementExplicationDebut, notations, 177),
            (E.signalementExplicationFin, notations, 178), (E.signalementMotif, notations, 182),
            (E.signalementPlaceholder, notations, 188), (E.signalementMotifRequis, notations, 139),
            (E.erreurSignalement, notations, 154), (E.signalementTransmis, notations, 157), (E.annuler, notations, 195),
            (E.signaler, notations, 198), ("Note moyenne : {Number(notation.note_moyenne).toFixed(1)}/5", notations, 173),
            ("{motif.length} / 10+", notations, 191),
            // Mon score
            (S.titre, score, 38), (S.enTete, score, 110), (S.scoreAbsent, score, 122), ("Score disponible après ", score, 124),
            (" de plus.", score, 124), (S.sur100, score, 130), (S.periodeProbatoireIndicatif, score, 133),
            (S.calculTitre, score, 146), (S.voirLeDetail, score, 147), (S.masquer, score, 148),
            (S.calculRegles[1], score, 155), (S.calculRegles[2], score, 156), (S.calculRegles[3], score, 157),
            (S.calculRegles[4], score, 158), (S.notationsTitre, score, 172), ("✔️ Décision admin : {ev.decision_admin}", score, 197),
            ("{pts > 0 ? '+' : ''}{pts} pts", score, 203), (S.contester, score, 210), (S.traitee, score, 214),
            (S.nonContestable, score, 214), (S.decisionSous72h, score, 223),
            ("totalMissions < \(ScorePresentation.missionsAvantScore)", score, 100),
            ("{ p_limit: \(ScoreDecodage.limiteEvenements) }", score, 63),
            // Niveau
            (S.nonNote, badge, 36),
            // Détail du calcul
            (S.periodeProbatoire, breakdown, 88), (S.periodeProbatoireTexte, breakdown, 90), (S.inactivesTitre, breakdown, 102),
            (" (pas assez de données). Les autres composantes voient leur poids majoré proportionnellement.", breakdown, 104),
            ("% redistribué", breakdown, 108), ("poids {c.poids_effectif.toFixed(0)}%", breakdown, 126),
            (S.malusBonusTitre, breakdown, 158), ("⚠️ Litiges perdus 12 mois : ", breakdown, 161), ("(cap -20)", breakdown, 161),
            ("🚫 Absence sans prévenir : ", breakdown, 164),
            ("Bonus super-actif (plus de 50 missions sur 12 mois) : ", breakdown, 167), (S.formule, breakdown, 175),
            // Évolution
            (S.pasEncoreDHistorique, graphique, 58), (S.evolutionApparaitra, graphique, 59), (S.evolutionTitre, graphique, 67),
            ("Données limitées : ", graphique, 72), (". Le graphique s'enrichira avec le temps.", graphique, 72),
            ("name=\"\(S.serieScore)\"", graphique, 86), ("{ p_limit: \(ScoreDecodage.moisEvolution) }", graphique, 27),
            // Notations reçues
            (S.aucuneNotation, notations, 69), (S.missionTermineeLe, notations, 85), (S.noteePar, notations, 86),
            ("'Établissement'", notations, 75), ("{cible} anonyme", notations, 86),
            ("⭐ {Number(n.note_moyenne).toFixed(1)}/5", notations, 91),
            ("{ p_limit: \(EvaluationsDecodage.limiteScore) }", notations, 49),
            // Contestation
            (S.contestationTitre, modale, 115), (S.contestationMotif, modale, 124), (S.contestationTexte, modale, 132),
            (S.texteRequis, modale, 82), ("'\(S.erreur)'", modale, 99), (S.erreurReseau, modale, 106),
            (S.reclamationEnvoyee, modale, 102), (S.annuler, modale, 181), (S.envoyer, modale, 185),
            ("{evenementInfo.points} pts", modale, 120), ("{texte.length} / 20+", modale, 140),
            ("texte.trim().length < \(ScorePresentation.longueurTexteMin)", modale, 81),
        ]
        for (rang, critere) in S.criteres.enumerated() {
            lignes.append((rang == 0 ? "['\(critere)'" : "'\(critere)'", notations, 27))
        }
        for (rang, niveau) in S.niveaux.enumerated() {
            lignes.append(("\(niveau.code): { label: '\(niveau.label)'", badge, 23 + rang))
            lignes.append(("emoji: '\(niveau.emoji)'", badge, 23 + rang))
        }
        for (rang, cle) in CleComposanteScore.allCases.enumerated() {
            let composante = S.composante(cle)
            lignes.append(("cle: '\(cle.rawValue)_pct', label: '\(composante.label)', description: '\(composante.description)'",
                           breakdown, 44 + rang))
        }
        return lignes
    }

    func testChaqueTexteAfficheEstVerbatimASaLigneWeb() throws {
        var sources: [String: [String]] = [:]
        for (texte, fichier, ligne) in Self.attendus {
            if sources[fichier] == nil { sources[fichier] = try Self.sourceDepot(fichier) }
            let source = try XCTUnwrap(sources[fichier])
            XCTAssertGreaterThanOrEqual(source.count, ligne, fichier)
            guard source.count >= ligne else { continue }
            XCTAssertTrue(source[ligne - 1].contains(texte), "« \(texte) » absent de \(fichier) l.\(ligne)")
        }
    }

    /// Motifs de contestation (HARD STOP : repris de `ModaleReclamationScore.tsx` l.22-29) : mêmes valeurs, mêmes
    /// libellés, même ordre que le web — et que la liste acceptée par le serveur.
    func testMotifsDeContestationSontCeuxDuWeb() throws {
        let source = try Self.sourceDepot(Self.modale)
        XCTAssertTrue(source[22 - 1].contains("const MOTIFS = ["), "ModaleReclamationScore.tsx l.22")
        XCTAssertTrue(source[29 - 1].hasPrefix("];"), "ModaleReclamationScore.tsx l.29 : six motifs, pas un de plus")
        XCTAssertEqual(MotifContestationScore.allCases.count, 6)
        for (rang, motif) in MotifContestationScore.allCases.enumerated() {
            XCTAssertEqual(source[23 + rang - 1].trimmingCharacters(in: .whitespaces),
                           "{ value: '\(motif.rawValue)', label: '\(S.libelle(motif))' },", "motif \(motif.rawValue)")
        }
        let schema = try Self.sourceDepot("supabase/schema/public.sql")
        let acceptes = MotifContestationScore.allCases.map { "'\($0.rawValue)'" }
        let liste = schema.joined(separator: "\n").components(separatedBy: "IF p_motif_categorie NOT IN (").dropFirst().first
        let serveur = try XCTUnwrap(liste?.components(separatedBy: ") THEN").first)
        for motif in acceptes { XCTAssertTrue(serveur.contains(motif), "motif \(motif) refusé par fn_creer_reclamation_score") }
        XCTAssertEqual(serveur.components(separatedBy: ",").count, 6, "le serveur accepte exactement six motifs")
    }

    func testTextesTutoyesDuWebAuVouvoiement() throws {
        let sourcesScore: [(String, Int)] = [
            (Self.score, 113), (Self.score, 154), (Self.score, 181), (Self.score, 231), (Self.score, 234),
            (Self.modale, 78), (Self.modale, 138), (Self.modale, 176),
        ]
        XCTAssertEqual(S.vouvoiements.count, sourcesScore.count)
        XCTAssertEqual(S.vouvoiements.map { $0.natif },
                       [S.sousTitre, S.calculRegles[0], S.evenementsTitre, S.aucunEvenementTitre, S.aucunEvenementTexte,
                        S.motifRequis, S.contestationPlaceholder, S.examenParAdmin])
        var paires = Array(zip(S.vouvoiements, sourcesScore)).map { ($0.0.web, $0.0.natif, $0.1.0, $0.1.1) }
        XCTAssertEqual(E.vouvoiements.map { $0.natif }, [E.sousTitre])
        paires += E.vouvoiements.map { ($0.web, $0.natif, Self.evaluations, 120) }
        for (web, natif, fichier, ligne) in paires {
            let source = try Self.sourceDepot(fichier)
            XCTAssertTrue(source[ligne - 1].contains(web), "« \(web) » absent de \(fichier) l.\(ligne)")
            XCTAssertNotEqual(web, natif)
            for tutoiement in [" tu ", "Tu ", " te ", " tes ", " ton ", " ta ", "Ta ", "Ton ", "Sélectionne ", "Sélectionne —", "Explique ", "contacte "] {
                XCTAssertFalse(natif.contains(tutoiement), "« \(natif) » doit être vouvoyé (« \(tutoiement) »)")
            }
        }
    }

    /// Aucun texte tutoyé ne reste dans les textes affichés ; aucun texte du justificatif n'est porté (D10).
    func testAucunTutoiementResiduelNiTexteDuJustificatif() throws {
        let affiches = Self.attendus.map { $0.0 } + S.vouvoiements.map { $0.natif } + E.vouvoiements.map { $0.natif }
            + [E.signalementExplication, E.signalementNonConfirme, S.chargementImpossible, S.contestationNonConfirmee]
        // Champ « Justificatif non médical (optionnel — PDF, image, max 5 Mo) » et son avertissement (l.144, l.170).
        for texte in affiches {
            for interdit in ["ustificatif", "certificat", "diagnostic", "max 5 Mo", "Choisir un fichier"] {
                XCTAssertFalse(texte.contains(interdit), "texte du justificatif porté : « \(texte) »")
            }
        }
        for natif in [E.sousTitre, E.signalementExplication, E.signalementPlaceholder, S.sousTitre, S.examenParAdmin] {
            for tutoiement in [" tes ", " ton ", "Ta ", " te ", "signale-la"] { XCTAssertFalse(natif.contains(tutoiement), natif) }
        }
    }

    /// Textes natifs sans équivalent web : libellés techniques seulement, vouvoyés, sans délai ni engagement.
    func testTextesNatifsSontDesLibellesTechniques() {
        let natifs = [E.signalementNonConfirme, E.noteIndisponible, E.reessayer, S.chargementImpossible, S.reessayer,
                      S.contestationNonConfirmee]
        for texte in natifs {
            for engagement in ["72", "heure", "jour", "admin", "sera", "décision", "pénalité"] {
                XCTAssertFalse(texte.lowercased().contains(engagement), "« \(texte) » : libellé technique attendu")
            }
        }
    }
}
