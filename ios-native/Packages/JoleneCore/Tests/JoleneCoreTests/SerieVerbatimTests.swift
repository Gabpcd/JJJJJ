import XCTest
@testable import JoleneCore

/// Textes du détail de série (L4-T12 ; règle des textes du mémo des lots 2 à 5, HARD STOP n°4) : chaque texte affiché
/// est repris mot pour mot du web, à sa ligne source ; les textes tutoyés du web (non juridiques) passent au
/// vouvoiement (décision 9 du lot 1) et leur forme web reste à sa ligne ; aucun texte de conformité n'est écrit côté
/// Swift : un refus du serveur s'affiche tel que servi.
final class SerieVerbatimTests: XCTestCase {
    private typealias T = SerieTextes

    private static let web = "src/pages/DetailSerieSoignant.tsx"

    private static func sourceDepot(_ chemin: String) throws -> [String] {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent(chemin)
        guard FileManager.default.fileExists(atPath: fichier.path) else {
            throw XCTSkip("\(chemin) introuvable : \(fichier.path)")
        }
        return try String(contentsOf: fichier, encoding: .utf8).components(separatedBy: "\n")
    }

    /// Texte affiché (ou fragment fixe d'un texte assemblé) et sa ligne dans `DetailSerieSoignant.tsx`.
    private static var attendus: [(String, Int)] {
        [
            (T.pastille, 359), (T.titre, 359),
            (T.indisponibleTitre, 228), (T.indisponibleTexte, 229), (T.reessayer, 230),
            (T.introuvableTitre, 237), (T.introuvableTexte, 238), (T.explorer, 239),
            (T.creneaux, 432), (T.dejaPourvue, 469), (T.conflit, 472), (T.planningIndisponible, 474),
            (T.acceptationEnCours, 525), (T.annuler, 557), (T.accepterTous, 564),
            (T.choixContratTitre, 312), (T.bilanAucune.replacingOccurrences(of: "'", with: "\\'"), 346),
            // Assemblages : gabarits du web, à leur ligne.
            ("📅 Du {formatParis(first?.debut_le, 'd MMM')} au {formatParis(last?.debut_le, 'd MMM yyyy')}", 369),
            ("📋 {ouvertes.length} mission{ouvertes.length > 1 ? 's' : ''} disponible{ouvertes.length > 1 ? 's' : ''} sur {missions.length}", 372),
            ("🏥 {first.etablissements.nom} · {first.etablissements.adresse_ville}", 364),
            ("`Sélectionner la mission du ${formatParis(m.debut_le, 'd MMMM yyyy')}`", 450),
            ("`★ Accepter la sélection (${analyseSelection.missionsSelectionnees.length})`", 528),
            ("`La mission \"${mission.intitule}\" accepte salarié ou libéral : ", 313),
            ("`${reussies} mission(s) acceptée(s), ${echouees} en conflit.`", 343),
            // Règles portées, à leur ligne : lecture de la série, sélection initiale, boucle, arrêt, choix de contrat.
            (".ilike('description', `%[SERIE_ID:${decoded}]%`).order('debut_le', { ascending: true })", 95),
            ("missionsPlanifiees.filter((m: any) => m.statut === 'OUVERTE' && m.planning_exact)", 135),
            ("const ouvertes = missions.filter(m => m.statut === 'OUVERTE');", 244),
            ("analyserSelectionSerie(ouvertes, selectedIds, conflitMissionIds)", 264),
            ("for (const mission of toAccept) {", 289),
            ("p_action: 'ACCEPTER',", 297),
            ("p_choix_contrat: null,", 300),
            ("if (estBlocageCodeTravail(error)) {", 306),
            ("break;", 308),
            ("} else if (data?.choix_requis) {", 310),
            ("{isOpen && planningExact && (", 447),
        ]
    }

    func testChaqueTexteEtRegleEstVerbatimASaLigneWeb() throws {
        let source = try Self.sourceDepot(Self.web)
        for (texte, ligne) in Self.attendus {
            XCTAssertGreaterThanOrEqual(source.count, ligne)
            XCTAssertTrue(source[ligne - 1].contains(texte), "« \(texte) » absent de \(Self.web) l.\(ligne)")
        }
        // Le bilan de succès est le gabarit de l'animation (l.574) : pluriel sur « mission » et « acceptée ».
        XCTAssertTrue(source[574 - 1].contains("acceptée${"), source[574 - 1])
    }

    func testAssemblagesRendusCommeLeWeb() throws {
        // `formatParis(…, 'd MMM')` et `'d MMM yyyy'` : heure de Paris, mois abrégé de date-fns.
        XCTAssertEqual(T.periode(debut: "2026-11-03T07:00:00.000Z", fin: "2026-11-30T20:00:00.000Z"), "📅 Du 3 nov. au 30 nov. 2026")
        XCTAssertEqual(T.periode(debut: "2026-12-31T23:30:00.000Z", fin: "illisible"), "📅 Du 1 janv. au illisible",
                       "jour civil de Paris ; date illisible rendue telle quelle")
        XCTAssertEqual(T.disponibles(1, sur: 5), "📋 1 mission disponible sur 5")
        XCTAssertEqual(T.disponibles(4, sur: 5), "📋 4 missions disponibles sur 5")
        XCTAssertEqual(T.disponibles(0, sur: 2), "📋 0 mission disponible sur 2")
        XCTAssertEqual(T.etablissement(nom: "Clinique des Tests", ville: "Lyon"), "🏥 Clinique des Tests · Lyon")
        XCTAssertEqual(T.etablissement(nom: "Clinique des Tests", ville: nil), "🏥 Clinique des Tests")
        XCTAssertEqual(T.selectionner(debut: "2026-11-03T07:00:00.000Z"), "Sélectionner la mission du 3 novembre 2026")
        XCTAssertEqual(T.accepterSelection(3), "★ Accepter la sélection (3)")
        XCTAssertEqual(T.choixContratDescription(intitule: "Renfort de nuit"),
                       "La mission \"Renfort de nuit\" accepte salarié ou libéral : ouvrez son détail pour choisir votre mode de contrat avant d'accepter.")
        XCTAssertEqual(T.bilanPartiel(reussies: 2, echouees: 1), "2 mission(s) acceptée(s), 1 en conflit.")
        XCTAssertEqual(T.bilanSucces(1), "1 mission acceptée !")
        XCTAssertEqual(T.bilanSucces(4), "4 missions acceptées !")
        XCTAssertEqual(T.acceptee, LibellesCandidature.assignee, "libellé du détail de mission (lot 1), pas un texte nouveau")
    }

    /// HARD STOP n°4 : un refus du serveur est rendu seul et tel quel sur sa mission — ni titre, ni préfixe, ni suffixe —
    /// qu'il vienne d'un refus structuré ou de l'exception d'un trigger de conformité.
    func testRefusDuServeurRenduSeulEtTelQuel() {
        let conformite = "[CODE DU TRAVAIL] Repos insuffisant avant mission : 8.5 heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée."
        let conflit = "Tu es déjà confirmé(e) sur « Garde de nuit » le 12/11 08h00–12/11 16h00. Ce créneau chevauche la mission."
        XCTAssertEqual(IssueMissionSerie.codeDuTravail(message: conformite).ligne(intitule: "Renfort"),
                       LigneResultatSerie(titre: nil, texte: conformite, ton: .erreur, lienDetail: false))
        XCTAssertEqual(IssueMissionSerie.refusee(code: "CONFLIT_PLANNING", message: conflit).ligne(intitule: "Renfort"),
                       LigneResultatSerie(titre: nil, texte: conflit, ton: .erreur, lienDetail: false))
        XCTAssertEqual(IssueMissionSerie.refusee(code: nil, message: "Cette mission n'est plus disponible.").ligne(intitule: "Renfort").texte,
                       "Cette mission n'est plus disponible.")
        XCTAssertEqual(IssueMissionSerie.planningModifie(message: DemoCandidatureGateway.Textes.planningModifie).ligne(intitule: "Renfort").texte,
                       DemoCandidatureGateway.Textes.planningModifie)
        // Seul le choix de contrat requis mène au détail de la mission ; son texte est celui du web, vouvoyé.
        let choix = IssueMissionSerie.choixContratRequis.ligne(intitule: "Renfort")
        XCTAssertEqual(choix, LigneResultatSerie(titre: T.choixContratTitre, texte: T.choixContratDescription(intitule: "Renfort"),
                                                 ton: .attention, lienDetail: true))
        XCTAssertEqual(IssueMissionSerie.acceptee.ligne(intitule: "Renfort"), LigneResultatSerie(texte: T.acceptee, ton: .succes))
        XCTAssertEqual(IssueMissionSerie.nonEnvoyee.ligne(intitule: "Renfort"), LigneResultatSerie(texte: T.nonEnvoyee, ton: .information))
        XCTAssertEqual(IssueMissionSerie.planningIncomplet.ligne(intitule: "Renfort").texte, PlanningCandidatRules.messagePlanningIncomplet)
        XCTAssertEqual(IssueMissionSerie.nonConfirmee(message: SessionController.timeoutMessage).ligne(intitule: "Renfort").texte,
                       SessionController.timeoutMessage)
        // Verdict du serveur seulement : une mission n'est « en conflit » que par un refus structuré.
        XCTAssertTrue(IssueMissionSerie.codeDuTravail(message: conformite).estConflitServeur)
        XCTAssertTrue(IssueMissionSerie.refusee(code: "CONFLIT_PLANNING", message: conflit).estConflitServeur)
        for issue in [IssueMissionSerie.acceptee, .choixContratRequis, .refusee(code: nil, message: "x"), .planningModifie(message: "x"),
                      .planningIncomplet, .nonConfirmee(message: "x"), .nonEnvoyee] {
            XCTAssertFalse(issue.estConflitServeur, "\(issue)")
        }
    }

    /// Décision 9 du lot 1 : textes non juridiques au vouvoiement ; la forme tutoyée du web reste à sa ligne.
    func testTextesTutoyesDuWebAuVouvoiement() throws {
        let source = try Self.sourceDepot(Self.web)
        let lignes = [527, 541, 543, 278, 313]
        XCTAssertEqual(T.vouvoiements.count, lignes.count)
        XCTAssertEqual(T.vouvoiements.prefix(4).map { $0.natif }, [T.decocherConflits, T.confirmationTitre, T.confirmationDescription, T.selectionACorriger])
        XCTAssertTrue(T.choixContratDescription(intitule: "X").hasSuffix(T.vouvoiements[4].natif))
        for ((web, natif), ligne) in zip(T.vouvoiements, lignes) {
            XCTAssertTrue(source[ligne - 1].contains(web), "« \(web) » absent de l.\(ligne)")
            XCTAssertNotEqual(web, natif)
        }
        let natifs = T.vouvoiements.map { $0.natif } + [T.arret, T.nonConfirmee, T.nonEnvoyee, T.ouvrirDetail, T.voirContrats,
                                                         T.introuvableTexte, T.indisponibleTexte]
        for natif in natifs {
            for tutoiement in [" tu ", " ta ", " ton ", " tes ", "Tu ", "Vérifie ", "Confirme ", "Décoche ", "Corrige ", " ouvre "] {
                XCTAssertFalse(natif.contains(tutoiement), "« \(natif) » doit être vouvoyé")
            }
        }
    }

    /// HARD STOP n°4 et décision 2 du lot 1 : aucun texte de conformité n'est écrit côté Swift. Le bloc « Vérification
    /// de compatibilité » du web (l.376-428), ses articles de loi et la modale d'explication ne sont pas portés ; les
    /// textes natifs sans équivalent web décrivent ce que l'app a fait, sans qualifier le refus du serveur.
    func testAucunTexteDeConformiteEcritCoteSwift() throws {
        let source = try Self.sourceDepot(Self.web)
        // Le bloc existe toujours côté web, aux lignes citées : sa non-reprise est un écart consigné, pas un oubli.
        XCTAssertTrue(source[378 - 1].contains("Vérification de compatibilité"))
        XCTAssertTrue(source[399 - 1].contains("Repos 11h respecté"))
        XCTAssertTrue(source[400 - 1].contains("Plafond 48h respecté"))
        let tous = [T.pastille, T.titre, T.indisponibleTitre, T.indisponibleTexte, T.reessayer, T.introuvableTitre, T.introuvableTexte,
                    T.explorer, T.creneaux, T.dejaPourvue, T.conflit, T.planningIndisponible, T.acceptationEnCours, T.decocherConflits,
                    T.confirmationTitre, T.confirmationDescription, T.annuler, T.accepterTous, T.selectionACorriger,
                    T.choixContratTitre, T.bilanAucune, T.acceptee, T.nonEnvoyee, T.arret, T.ouvrirDetail, T.voirContrats, T.nonConfirmee,
                    T.periode(debut: "2026-11-03T07:00:00.000Z", fin: "2026-11-30T20:00:00.000Z"), T.disponibles(2, sur: 3),
                    T.selectionner(debut: "2026-11-03T07:00:00.000Z"), T.accepterSelection(2), T.choixContratDescription(intitule: "X"),
                    T.bilanPartiel(reussies: 1, echouees: 1), T.bilanSucces(2)]
        let interdits = ["code du travail", "repos", "11h", "11 h", "48h", "48 h", "44h", "35h", "plafond", "art.", "article", "légal", "loi"]
        for texte in tous {
            for interdit in interdits {
                XCTAssertFalse(texte.lowercased().contains(interdit), "« \(texte) » : « \(interdit) » ne s'écrit pas côté Swift")
            }
        }
        // Le texte d'arrêt ne reprend ni ne qualifie le refus : il dit seulement que la suite n'a pas été envoyée.
        XCTAssertEqual(T.arret, "L’acceptation s’est arrêtée sur ce refus. Les missions suivantes n’ont pas été envoyées.")
    }
}
