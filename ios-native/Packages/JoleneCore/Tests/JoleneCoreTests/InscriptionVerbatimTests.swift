import XCTest
@testable import JoleneCore

/// Textes de l'inscription native (lot 3, T7 ; HARD STOP n°4) : chaque texte affiché est repris mot pour mot du web
/// (ou du serveur), à sa ligne source. Garde locale en attendant `scripts/mobile/check-textes-juridiques-ios.mjs`
/// (L2-TL), absent de la base du lot 3 : chaque annotation `// source: fichier:ligne` de `InscriptionRules.swift` et
/// de `DemoInscriptionGateway.swift` est relue contre le fichier cité, littéral compris (texte JSX sur plusieurs
/// lignes joint par une espace, comme React ; `\'` d'une chaîne JavaScript ramené à `'`).
final class InscriptionVerbatimTests: XCTestCase {
    private typealias T = InscriptionTextes

    private static func racine() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url
    }

    private static func source(_ chemin: String) throws -> [String] {
        let fichier = racine().appendingPathComponent(chemin)
        guard FileManager.default.fileExists(atPath: fichier.path) else { throw XCTSkip("\(chemin) introuvable") }
        return try String(contentsOf: fichier, encoding: .utf8).components(separatedBy: "\n")
    }

    /// Texte des lignes `debut...fin` tel que rendu : chaque ligne nettoyée de ses espaces de bord, lignes jointes par
    /// une espace (JSX), échappements `\'` d'une chaîne JavaScript ramenés à `'`.
    private static func rendu(_ lignes: [String], _ debut: Int, _ fin: Int) -> String {
        lignes[(debut - 1)...(fin - 1)].map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            .replacingOccurrences(of: "\\'", with: "'")
    }

    private static let rapide = "src/pages/InscriptionRapide.tsx"
    private static let confirmation = "src/pages/ConfirmationInscription.tsx"
    private static let parcours = "src/pages/ParcoursInscription.tsx"
    private static let connexion = "src/pages/PageConnexion.tsx"
    private static let erreurs = "src/lib/erreurs.ts"
    private static let schema = "supabase/schema/public.sql"

    /// (texte, fichier, première ligne, dernière ligne).
    private static var attendus: [(String, String, Int, Int)] {
        [
            (T.creerCompteSoignant, connexion, 334, 334),
            (T.titre, rapide, 132, 132), (T.sousTitre, rapide, 136, 136), (T.email, rapide, 157, 157),
            (T.motDePasse, rapide, 180, 180), (T.aideMotDePasse, rapide, 211, 211), (T.profession, rapide, 221, 221),
            (T.choisirProfession, rapide, 230, 230),
            (T.cguDebut, rapide, 265, 265), (T.cguLienCGU, rapide, 272, 272), (T.cguMilieu, rapide, 274, 274),
            (T.cguLienConfidentialite, rapide, 281, 281), (T.cguFin, rapide, 283, 283),
            (#"href="/cgu""#, rapide, 267, 267), (#"href="/confidentialite""#, rapide, 276, 276),
            (T.erreurEmail, rapide, 60, 60), (T.erreurMotDePasse, rapide, 62, 62), (T.erreurProfession, rapide, 64, 64),
            (T.erreurCGU, rapide, 68, 68),
            (T.confirmationEnvoyee, rapide, 322, 324),
            (T.creationEnCours, rapide, 347, 347), (T.seConnecterEtContinuer, rapide, 349, 349),
            (T.jaiConfirme, rapide, 351, 351), (T.creerMonCompte, rapide, 352, 352), (T.aucunDocument, rapide, 356, 356),
            (T.dejaUnCompte, rapide, 361, 361), (T.seConnecter, rapide, 363, 363),
            (T.compteDejaEspace, rapide, 101, 101), (T.compteExistant, rapide, 107, 107),
            ("ACCOUNT_ALREADY_REGISTERED|ACCOUNT_TYPE_MISMATCH|ACCOUNT_REGISTRATION_INCOMPLETE", rapide, 98, 98),
            (T.motDePasseDivulgue, erreurs, 86, 86), (T.tropDeTentatives, erreurs, 102, 102), (T.emailInvalide, erreurs, 109, 109),
            ("Le mot de passe doit contenir au moins ${n} caractères.", erreurs, 119, 119),
            (T.motDePasseFaible, erreurs, 127, 127), (T.connexionInstable, erreurs, 149, 149),
            (T.erreurInattendue, erreurs, 178, 178), ("msgLower.includes('captcha')", erreurs, 132, 132),
            (T.reprendreInscription, confirmation, 74, 74), (T.lienNonValide, confirmation, 76, 77),
            (T.seConnecter, confirmation, 80, 80),
            (T.reprendreInscription, parcours, 97, 97), (T.choisirEspace, parcours, 100, 100),
            (T.jeSuisSoignant, parcours, 115, 115), (T.jeRepresenteEtablissement, parcours, 121, 121),
            (T.espaceIndisponible, parcours, 80, 80), (T.reessayer, parcours, 107, 107), (T.seDeconnecter, parcours, 126, 126),
            (DemoInscriptionGateway.refusTypeOuConditions, schema, 30163, 30163),
            (DemoInscriptionGateway.refusProfession, schema, 30167, 30167),
        ]
    }

    func testChaqueTexteAfficheEstVerbatimASaLigneSource() throws {
        var fichiers: [String: [String]] = [:]
        for (texte, fichier, debut, fin) in Self.attendus {
            if fichiers[fichier] == nil { fichiers[fichier] = try Self.source(fichier) }
            let lignes = try XCTUnwrap(fichiers[fichier])
            XCTAssertGreaterThanOrEqual(lignes.count, fin, fichier)
            XCTAssertTrue(Self.rendu(lignes, debut, fin).contains(texte), "« \(texte) » absent de \(fichier) l.\(debut)-\(fin)")
        }
    }

    func testPhraseDeConsentementAssembleeCommeLeJSX() throws {
        // `J’accepte les{" "}<a>CGU</a>{" "}et la{" "}<a>politique de confidentialité</a>.` (l.264-284) : React joint les
        // fragments par les `{" "}` et colle le point au second lien (saut de ligne → aucune espace).
        XCTAssertEqual(T.cguPhrase, "J’accepte les CGU et la politique de confidentialité.")
        let lignes = try Self.source(Self.rapide)
        XCTAssertEqual(lignes[265 - 1].trimmingCharacters(in: .whitespaces), T.cguDebut + #"{" "}"#)
        XCTAssertEqual(lignes[273 - 1].trimmingCharacters(in: .whitespaces), #"</a>{" "}"#)
        XCTAssertEqual(lignes[274 - 1].trimmingCharacters(in: .whitespaces), T.cguMilieu + #"{" "}"#)
        XCTAssertEqual(lignes[282 - 1].trimmingCharacters(in: .whitespaces), "</a>")
        XCTAssertEqual(lignes[283 - 1].trimmingCharacters(in: .whitespaces), T.cguFin)
        XCTAssertEqual(T.urlCGU.absoluteString, "https://jolene.app/cgu")
        XCTAssertEqual(T.urlConfidentialite.absoluteString, "https://jolene.app/confidentialite")
        // Pages juridiques hors AASA : jamais renvoyées dans l'app par lien universel.
        XCTAssertNil(AASAPatterns.firstMatch(path: T.urlCGU.path))
        XCTAssertNil(AASAPatterns.firstMatch(path: T.urlConfidentialite.path))
    }

    func testTexteDuRenvoiDeLongueurAssembleCommeLeGabarit() {
        XCTAssertEqual(T.motDePasseLongueur("12"), "Le mot de passe doit contenir au moins 12 caractères.")
    }

    /// Chaque annotation `// source: fichier:ligne[-ligne]` est suivie de la déclaration de son texte, dont le littéral
    /// figure à la source citée : une annotation décalée ou un texte modifié rougit ce test.
    func testAnnotationsSourceDesFichiersSwiftConcordent() throws {
        let fichiersSwift = [
            "ios-native/Packages/JoleneCore/Sources/JoleneCore/Inscription/InscriptionRules.swift",
            "ios-native/Packages/JoleneCore/Sources/JoleneCore/Demo/DemoInscriptionGateway.swift",
        ]
        let annotation = try NSRegularExpression(pattern: #"^\s*// source: ([^:]+):(\d+)(?:-(\d+))?\s*$"#)
        let litteral = try NSRegularExpression(pattern: #"static (?:let|func) \w+[^=]*?(?:=|->[^{]*\{)\s*"((?:[^"\\]|\\.)*)""#)
        var verifiees = 0
        var sources: [String: [String]] = [:]
        for chemin in fichiersSwift {
            let lignes = try Self.source(chemin)
            for (index, ligne) in lignes.enumerated() {
                let plage = NSRange(ligne.startIndex..., in: ligne)
                guard let trouve = annotation.firstMatch(in: ligne, range: plage),
                      let fichier = Range(trouve.range(at: 1), in: ligne).map({ String(ligne[$0]) }),
                      let debut = Range(trouve.range(at: 2), in: ligne).flatMap({ Int(ligne[$0]) }) else { continue }
                let fin = Range(trouve.range(at: 3), in: ligne).flatMap { Int(ligne[$0]) } ?? debut
                // Déclaration sur la ligne suivante, ou ses deux suivantes (fonction de gabarit).
                let bloc = lignes[(index + 1)..<min(lignes.count, index + 3)].joined(separator: " ")
                let plageBloc = NSRange(bloc.startIndex..., in: bloc)
                guard let decl = litteral.firstMatch(in: bloc, range: plageBloc),
                      let valeur = Range(decl.range(at: 1), in: bloc).map({ String(bloc[$0]) }) else {
                    XCTFail("\(chemin) l.\(index + 1) : annotation sans déclaration de texte")
                    continue
                }
                if sources[fichier] == nil { sources[fichier] = try Self.source(fichier) }
                let cible = try XCTUnwrap(sources[fichier])
                // Littéral Swift → texte : seul `\(minimum)` (gabarit) diffère du JavaScript `${n}`.
                let texte = valeur.replacingOccurrences(of: #"\(minimum)"#, with: "${n}")
                XCTAssertTrue(Self.rendu(cible, debut, fin).contains(texte),
                              "\(chemin) l.\(index + 1) : « \(texte) » absent de \(fichier) l.\(debut)-\(fin)")
                verifiees += 1
            }
        }
        XCTAssertEqual(verifiees, 53, "toutes les annotations sont relues (42 + 2 de T7, + 8 refus serveur démo de T8, + 1 de la revue B8 de T8 : 409 `ACCOUNT_ALREADY_REGISTERED`)")
    }

    func testAucunTexteNouveauNiTutoiementNiMentionJuridiqueReformulee() {
        let tous = Self.attendus.map { $0.0 } + [T.cguPhrase]
        for texte in tous {
            for tutoiement in [" tu ", " tes ", " ton ", "Tu ", "Ton "] {
                XCTAssertFalse(texte.contains(tutoiement), "« \(texte) » : tutoiement")
            }
        }
        // Le consentement ne cite aucun article ni aucune règle : seulement la phrase et les deux pages web.
        XCTAssertFalse(T.cguPhrase.contains("article") || T.cguPhrase.contains("RGPD"))
    }
}
