import XCTest
@testable import JoleneCore

/// Textes de la page Présences (lot 2, T4a) : les libellés repris tels quels sont dans `LibellesWeb` (garde Node
/// `textes-juridiques-ios`, au caractère près) ; `LibellesPresences` ne porte que les textes que le web tutoie,
/// vouvoyés (décision 9 du lot 1 : seule la personne change, comme la décision 6 du lot 2), les assemblages (dates,
/// durées, compteurs, comme le rendu React) et les textes opérationnels inventoriés dans `DECISIONS_LOT2.md`
/// (« Textes opérationnels hors web (T4a) »). Ce test relit les sources web : il rougit si un texte tutoyé change
/// d'un côté sans l'autre. Aucun texte juridique (le bandeau « à valider » vient de `TextesWeb.Presences`).
final class LibellesPresencesTests: XCTestCase {
    private var racine: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // JoleneCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // JoleneCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // ios-native
            .deletingLastPathComponent() // racine du dépôt
    }

    private func source(_ relatif: String) throws -> String {
        try String(contentsOf: racine.appendingPathComponent(relatif), encoding: .utf8)
    }

    private func date(_ iso: String) throws -> Date { try DateHeureParis.instantJolene(iso) }

    // MARK: - Vouvoiement

    func testTextesVouvoyesDontSeuleLaPersonneChange() throws {
        let page = try source("src/pages/PresencesSoignant.tsx")
        let bloc = try source("src/components/pointage/BlocPointageMission.tsx")
        let vouvoyes: [(natif: String, web: String, fichier: String)] = [
            (LibellesPresences.Liste.sousTitre, "Pointe tes arrivées et départs pour chaque mission", page),
            (LibellesPresences.Liste.erreurTitre, "Impossible de charger tes présences", page),
            (LibellesPresences.Liste.videAVenirDescription, "Tes prochaines missions assignées apparaîtront ici.", page),
            (LibellesPresences.Liste.videActivesDescription, "Tes missions actives apparaîtront ici, même entre deux créneaux.", page),
            (LibellesPresences.Liste.videAujourdhuiDescription, "Tes missions assignées apparaîtront ici le jour J pour le pointage.", page),
            (LibellesPresences.Liste.videHistoriqueDescription, "Ton historique de pointages apparaîtra ici.", page),
            (LibellesPresences.Bloc.aucunHoraire,
             "Aucun horaire de présence n'est enregistré pour cette mission. Contacte l'établissement avant de te déplacer.", bloc),
        ]
        let personnes = [("Pointe tes ", "Pointez vos "), ("charger tes ", "charger vos "), ("Tes ", "Vos "), ("Ton ", "Votre "),
                         ("Contacte ", "Contactez "), ("de te déplacer", "de vous déplacer")]
        for (natif, web, fichier) in vouvoyes {
            XCTAssertTrue(fichier.contains(web), "source web changée : \(web)")
            let converti = personnes.reduce(web) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
            XCTAssertEqual(natif, converti, "seule la personne change")
        }
    }

    func testAucunTexteTutoyeVideNiJuridique() {
        let tous = [LibellesPresences.Liste.sousTitre, LibellesPresences.Liste.erreurTitre,
                    LibellesPresences.Liste.videAVenirDescription, LibellesPresences.Liste.videActivesDescription,
                    LibellesPresences.Liste.videAujourdhuiDescription, LibellesPresences.Liste.videHistoriqueDescription,
                    LibellesPresences.Bloc.aucunHoraire, LibellesPresences.EspaceSoignant.titreSection,
                    LibellesPresences.Provisoire.etat, LibellesPresences.Provisoire.pointage]
        let tutoiement: Set<String> = ["tu", "te", "toi", "ton", "ta", "tes", "t"]
        for texte in tous {
            XCTAssertFalse(texte.trimmingCharacters(in: .whitespaces).isEmpty)
            let mots = texte.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            XCTAssertFalse(mots.contains { tutoiement.contains($0) }, "tutoiement dans « \(texte) »")
            for marque in ["consentement", "RGPD", "72", "Code ", "contester", "litige"] {
                XCTAssertFalse(texte.contains(marque), "« \(texte) » : marque « \(marque) » hors TextesWeb")
            }
        }
    }

    // MARK: - Liste

    func testCompteurDuBadgeAVenir() {
        XCTAssertEqual(LibellesPresences.Liste.badgeAVenir(1), "1 mission à venir")
        XCTAssertEqual(LibellesPresences.Liste.badgeAVenir(2), "2 missions à venir")
    }

    func testEtablissementEtVilleCommeLeWeb() {
        let republique = EtablissementSummary(id: "e-1", nom: "Établissement fictif République", adresseVille: "Paris")
        XCTAssertEqual(LibellesPresences.Liste.etablissementEtVille(republique), "Établissement fictif République · Paris")
        XCTAssertEqual(LibellesPresences.Liste.etablissementEtVille(EtablissementSummary(id: "e-2", nom: "Sans ville")), "Sans ville")
        XCTAssertEqual(LibellesPresences.Liste.etablissementEtVille(EtablissementSummary(id: "e-3", nom: "", adresseVille: "Paris")),
                       "Établissement · Paris", "`nom || 'Établissement'`")
        XCTAssertEqual(LibellesPresences.Liste.etablissementEtVille(nil), "Établissement")
        XCTAssertEqual(LibellesPresences.Liste.etablissement(nil), "Établissement")
        XCTAssertEqual(LibellesPresences.Liste.etablissement(republique), "Établissement fictif République")
    }

    func testHoraireEtJourDUneMissionAVenir() {
        XCTAssertEqual(LibellesPresences.Liste.horaire(debut: "2026-11-03T07:00:00Z", fin: "2026-11-03T15:00:00Z", dureeHeures: 8),
                       "08h00 → 16h00 (8h)")
        XCTAssertEqual(LibellesPresences.Liste.horaire(debut: "2026-11-03T07:00:00Z", fin: "2026-11-03T14:30:00Z", dureeHeures: 7.5),
                       "08h00 → 15h30 (7.5h)", "nombre JavaScript : point décimal, sans zéro inutile")
        XCTAssertEqual(LibellesPresences.Liste.horaire(debut: "2026-11-03T07:00:00Z", fin: "2026-11-03T15:00:00Z", dureeHeures: nil),
                       "08h00 → 16h00", "durée absente : rien")
        XCTAssertEqual(LibellesPresences.Liste.horaire(debut: "2026-11-03T07:00:00Z", fin: "2026-11-03T15:00:00Z", dureeHeures: 0),
                       "08h00 → 16h00", "durée nulle : rien (`dureeAffichageHeures ?` du web)")
        XCTAssertNil(LibellesPresences.Liste.horaire(debut: "illisible", fin: "2026-11-03T15:00:00Z", dureeHeures: 8))
        XCTAssertEqual(LibellesPresences.Liste.jour("2026-11-03T07:00:00Z"),
                       AccueilPresentation.Jour(semaine: "mar.", jour: "3", mois: "nov."))
        XCTAssertNil(LibellesPresences.Liste.jour(nil))
        XCTAssertEqual(LibellesPresences.Liste.statut("ASSIGNEE"), "Assignée")
        XCTAssertEqual(LibellesPresences.Liste.statut("EN_COURS"), "Active")
    }

    func testDateDeValidation() {
        XCTAssertEqual(LibellesPresences.Liste.dateValidation("2026-11-01T14:00:00Z"), "1 nov. 2026 à 15:00")
        XCTAssertNil(LibellesPresences.Liste.dateValidation(nil))
        XCTAssertNil(LibellesPresences.Liste.dateValidation("illisible"))
    }

    // MARK: - Bloc de pointage

    func testTextesDuBlocParMotif() throws {
        let bloc = LibellesPresences.Bloc.self
        XCTAssertNil(bloc.textes(.pointable(.ouverture)), "pointable : la zone de pointage (T4b) remplace les motifs")
        XCTAssertEqual(bloc.textes(.contratNonSigne(contratId: "c-1", prochainAutreJour: nil)),
                       .init(titre: "Contrat non signé",
                             details: ["Le contrat doit être signé par les deux parties avant le premier pointage."]))
        XCTAssertEqual(bloc.textes(.contratNonSigne(contratId: nil, prochainAutreJour: try date("2026-11-03T07:00:00Z"))),
                       .init(titre: "Contrat non signé",
                             details: ["Le contrat doit être signé par les deux parties avant le premier pointage.",
                                       "Aucun créneau à pointer aujourd’hui. Prochain créneau le mardi 3 novembre à 08h00."]))
        XCTAssertEqual(bloc.textes(.aucunCreneau),
                       .init(titre: "Aucun créneau planifié",
                             details: ["Aucun horaire de présence n'est enregistré pour cette mission. Contactez l'établissement avant de vous déplacer."]))
        XCTAssertEqual(bloc.textes(.pasEncoreOuvert(debut: try date("2026-11-02T08:00:00Z"))),
                       .init(titre: "Pointage pas encore ouvert",
                             details: ["Le pointage ouvrira 15 minutes avant le créneau de 09h00."]))
        XCTAssertEqual(bloc.textes(.aucunAujourdhui(prochain: try date("2026-11-03T07:00:00Z"))),
                       .init(titre: "Aucun créneau à pointer aujourd’hui", details: ["Prochain créneau le mardi 3 novembre à 08h00."]))
        XCTAssertEqual(bloc.textes(.aucunAujourdhui(prochain: nil)),
                       .init(titre: "Aucun créneau à pointer aujourd’hui", details: ["Tous les créneaux planifiés sont terminés."]))
    }

    // MARK: - Lignes d'historique

    func testMethodeDePointageCommeLeWeb() {
        let ligne = LibellesPresences.Ligne.self
        XCTAssertEqual(ligne.methode(nil), "—")
        XCTAssertEqual(ligne.methode(""), "—", "`if (!m)` du web")
        XCTAssertEqual(ligne.methode("GPS"), "📍 GPS")
        XCTAssertEqual(ligne.methode("CODE"), "🔢 Code")
        XCTAssertEqual(ligne.methode("CODE_ROTATIF"), "🔢 Code")
        XCTAssertEqual(ligne.methode("QR"), "🔢 Code")
        XCTAssertEqual(ligne.methode("MANUEL"), "MANUEL", "valeur inconnue : affichée telle quelle")
    }

    func testHorodatageEtDateDeMission() throws {
        XCTAssertEqual(LibellesPresences.Ligne.horodatage(try date("2026-10-31T07:00:00Z")), "31 oct. · 08h00")
        XCTAssertEqual(LibellesPresences.Ligne.horodatage(nil), "—")
        XCTAssertEqual(LibellesPresences.Ligne.dateMission("2026-10-31T07:00:00.000Z"), "31 oct. 2026")
        XCTAssertNil(LibellesPresences.Ligne.dateMission(nil))
    }

    /// `heuresTravaillees.toFixed(1)` puis « h » : arrondi de `Number.prototype.toFixed` (l'entier le plus proche de la
    /// valeur binaire exacte, le plus grand à égalité), qui diffère de `printf` aux seules égalités exactes.
    func testHeuresCommeToFixedDuWeb() {
        let ligne = LibellesPresences.Ligne.self
        XCTAssertEqual(ligne.heures(8), "8.0h")
        XCTAssertEqual(ligne.heures(7.5), "7.5h")
        XCTAssertEqual(ligne.heures(0.25), "0.3h", "égalité exacte : vers le plus grand (printf donnerait 0.2)")
        XCTAssertEqual(ligne.heures(1.25), "1.3h")
        XCTAssertEqual(ligne.heures(0.15), "0.1h", "0,15 vaut 0,1499… en binaire : 0.1 comme le web")
        XCTAssertEqual(ligne.heures(0.45), "0.5h")
        XCTAssertEqual(ligne.heures(7.983_333_333_333_333), "8.0h")
        XCTAssertEqual(ligne.heures(0), "0.0h", "`'0.0'` est une chaîne non vide : affichée")
        XCTAssertEqual(ligne.heures(nil), "—")
    }

    // MARK: - Textes opérationnels

    func testTextesOperationnelsInventories() {
        XCTAssertEqual(LibellesPresences.EspaceSoignant.titreSection, "Mon espace", "décision 24 du lot 2")
        XCTAssertEqual(LibellesPresences.Provisoire.etat, "Disponible au lot 2")
        XCTAssertEqual(LibellesPresences.Provisoire.pointage, "Le pointage dans l'application arrive avec la suite du lot 2.")
    }
}
