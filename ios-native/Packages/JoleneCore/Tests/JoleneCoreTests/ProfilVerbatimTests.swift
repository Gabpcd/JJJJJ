import XCTest
@testable import JoleneCore

/// Textes de l'écran « Mon profil » (lot 3, T9 ; HARD STOP n°4) : chaque texte affiché est repris mot pour
/// mot du web, à sa ligne source ; les textes tutoyés du web (non juridiques) passent au vouvoiement
/// (décision 9 du lot 1) et leur forme web reste à sa ligne. Type d'exercice et attestation de cumul
/// (art. L1222-5, correction 8) : aucun de leurs textes n'est porté ; le seul texte natif sans équivalent
/// web est le libellé du renvoi, listé dans `DECISIONS_LOT3.md` parmi les textes à relire par Gabrielle.
final class ProfilVerbatimTests: XCTestCase {
    private typealias T = ProfilEdition.Textes
    private typealias M = ChoixModesExercice.Textes

    private static func sourceDepot(_ chemin: String) throws -> String {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent(chemin)
        guard FileManager.default.fileExists(atPath: fichier.path) else {
            throw XCTSkip("\(chemin) introuvable : \(fichier.path)")
        }
        return try String(contentsOf: fichier, encoding: .utf8)
    }

    private static let profilSoignant = "src/pages/ProfilSoignant.tsx"
    private static let principal = "src/components/profil-soignant/SectionProfilPrincipal.tsx"
    private static let preferences = "src/components/profil-soignant/SectionPreferences.tsx"
    private static let bio = "src/components/SectionBio.tsx"
    private static let choixModes = "src/components/ChoixModesExercice.tsx"
    private static let hub = "src/pages/MonCompteSoignant.tsx"

    /// (texte, fichier web, ligne) : le texte figure tel quel à sa ligne source.
    private static var attendus: [(String, String, Int)] {
        [
            (T.titre, profilSoignant, 333), (T.titre, hub, 59),
            (T.succes, profilSoignant, 293), (T.reessayer, profilSoignant, 412),
            (T.enregistrer, profilSoignant, 499), (T.enregistrement, profilSoignant, 499),
            (T.sectionInformations, principal, 790), (T.prenom, principal, 795), (T.nom, principal, 810),
            (T.telephone, principal, 825), (T.dateNaissance, principal, 835), (T.email, principal, 850),
            (T.profession, principal, 733), (T.rpps, principal, 780),
            (T.nonModifiableApresRpps, principal, 733), (T.nonModifiableApresRpps, principal, 780),
            (T.nonModifiableApresRpps, principal, 797), (T.nonModifiableApresRpps, principal, 812),
            (T.rppsVerifie, principal, 722), (T.numeroRpps, principal, 246), (T.suffixeOptionnel, principal, 246),
            (T.suffixeRequis, principal, 246), (T.rppsPlaceholder, principal, 251), ("/11 chiffres", principal, 258),
            (T.rppsAide, principal, 262), (T.villeRecherche, principal, 879), (T.villeRecherchePlaceholder, principal, 887),
            (T.typeExercice, principal, 897),
            (T.presentation, bio, 46), (T.bio, bio, 51), (T.bioPlaceholder, bio, 56), ("/500", bio, 61),
            (T.anneesExperience, bio, 68),
            (T.tauxTitre, preferences, 71), (T.tauxNonDefini, preferences, 76), (T.tauxMinimum, preferences, 96),
            (T.tauxMaximum, preferences, 96), (T.rayonTitre, preferences, 102), (T.rayonAide, preferences, 103),
            ("Rayon : ", preferences, 105), (T.rayonMinimum, preferences, 117), (T.rayonMaximum, preferences, 117),
            (M.titre, choixModes, 26), (M.aide, choixModes, 27), (M.libelleSalarie, choixModes, 20),
            (M.libelleLiberal, choixModes, 21), (M.chargement, choixModes, 41), (M.indisponible, choixModes, 43),
            (M.reessayer, choixModes, 44), (M.liberalNonPropose, choixModes, 46), (M.anciennePreference, choixModes, 47),
            (M.aucunMode, choixModes, 48),
        ]
    }

    func testChaqueTexteAfficheEstVerbatimASaLigneWeb() throws {
        var lignes: [String: [String]] = [:]
        for (texte, fichier, ligne) in Self.attendus {
            if lignes[fichier] == nil { lignes[fichier] = try Self.sourceDepot(fichier).components(separatedBy: "\n") }
            let source = try XCTUnwrap(lignes[fichier])
            XCTAssertGreaterThanOrEqual(source.count, ligne, fichier)
            XCTAssertTrue(source[ligne - 1].contains(texte), "« \(texte) » absent de \(fichier) l.\(ligne)")
        }
    }

    func testCompteursEtValeursAssemblesCommeLeWeb() {
        // `{rpps.length}/11 chiffres` (l.257-259 : affiché seulement entre 1 et 10 chiffres), `{bio.length}/500`,
        // `Rayon : {rayon} km`, `${tauxHoraireMinimum} €/h`.
        XCTAssertEqual(T.rppsCompteur(3), "3/11 chiffres")
        XCTAssertNil(T.rppsCompteur(0))
        XCTAssertNil(T.rppsCompteur(11))
        XCTAssertEqual(T.bioCompteur(42), "42/500")
        XCTAssertEqual(T.rayon(50), "Rayon : 50 km")
        XCTAssertEqual(T.taux(28), "28 €/h")
        // Apostrophes typographiques du web conservées.
        XCTAssertTrue(T.rppsAide.contains("l’identité"))
        XCTAssertTrue(M.titre.contains("’") && M.indisponible.contains("l’ajout"))
    }

    func testTextesTutoyesDuWebAuVouvoiement() throws {
        let sources: [(String, String, Int)] = [
            (ProfilEdition.vouvoiements[0].web, Self.principal, 881),
            (ProfilEdition.vouvoiements[1].web, Self.preferences, 72),
            (ProfilEdition.vouvoiements[2].web, Self.profilSoignant, 411),
        ]
        XCTAssertEqual(ProfilEdition.vouvoiements.map { $0.natif }, [T.villeRechercheAide, T.tauxAide, T.chargementEchec])
        for (web, fichier, ligne) in sources {
            let source = try Self.sourceDepot(fichier).components(separatedBy: "\n")
            XCTAssertTrue(source[ligne - 1].contains(web), "« \(web) » absent de \(fichier) l.\(ligne)")
        }
        for natif in ProfilEdition.vouvoiements.map({ $0.natif }) {
            for tutoiement in [" tu ", " tes ", "Ton ", " ton ", "Tu ", "Indique "] {
                XCTAssertFalse(natif.contains(tutoiement), "« \(natif) » doit être vouvoyé")
            }
        }
    }

    func testAucunTexteDuTypeDExerciceNiDeLAttestationDeCumulNEstPorte() throws {
        // Section web l.894-1011 (radios, attestation L1222-5) : rien n'en est repris, hors son titre.
        let tous = Self.attendus.map { $0.0 } + ProfilEdition.vouvoiements.map { $0.natif } + [T.typeExerciceWeb, T.voirSurLeWeb]
        for interdit in ["L1222-5", "cumul", "J'atteste", "J’atteste", "Salarié(e)", "Mixte", "parcours libéral"] {
            XCTAssertFalse(tous.contains { $0.contains(interdit) }, "texte juridique porté : « \(interdit) »")
        }
        let modification = Set(Mirror(reflecting: ModificationProfil()).children.compactMap(\.label))
        XCTAssertFalse(modification.contains("typeExercice"))
        XCTAssertFalse(modification.contains("attestationCumulActivite"))
    }

    func testLibelleDuRenvoiDuTypeDExerciceEpingleSansSourceWeb() throws {
        // Texte natif non juridique, sans équivalent web (le web affiche la section elle-même) : listé parmi les
        // textes à relire par Gabrielle (`DECISIONS_LOT3.md`, HARD STOP n°4).
        XCTAssertEqual(T.typeExerciceWeb, "Le type d'exercice se modifie sur jolene.app.")
        let decisions = try Self.sourceDepot("docs/mobile-swift/DECISIONS_LOT3.md")
        let entete = "- Textes **sans équivalent web** (non juridiques, à relire par Gabrielle)"
        let debut = try XCTUnwrap(decisions.range(of: entete), "puce des textes sans équivalent web de DECISIONS_LOT3.md")
        let suite = decisions[debut.upperBound...]
        let puce = suite.range(of: "\n- ").map { suite[..<$0.lowerBound] } ?? suite
        XCTAssertTrue(puce.contains("« \(T.typeExerciceWeb) »"), "DECISIONS_LOT3.md liste le libellé du renvoi")
        XCTAssertTrue(puce.contains("« \(T.enregistrementEchec) »"), "DECISIONS_LOT3.md liste le message de repli")
        let web = try Self.sourceDepot(Self.principal)
        XCTAssertFalse(web.contains(T.typeExerciceWeb), "aucune source web : le libellé n'est pas présenté comme verbatim")
        // « Voir sur jolene.app » : libellé natif des renvois web du lot 1 (Accueil), réutilisé tel quel.
        let accueil = try Self.sourceDepot("ios-native/Jolene/Screens/Accueil/AccueilScreen.swift")
        XCTAssertTrue(accueil.contains("\"\(T.voirSurLeWeb)\""))
    }
}
