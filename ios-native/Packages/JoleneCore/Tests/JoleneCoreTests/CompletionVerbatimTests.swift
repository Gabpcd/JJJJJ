import XCTest
@testable import JoleneCore

/// Textes de la complétion soignant (lot 3, T8 ; HARD STOP n°4) : chaque annotation `// source: fichier:ligne` de
/// `Inscription/CompletionProfil.swift` est relue contre le fichier cité, littéral compris (même lecture que
/// `InscriptionVerbatimTests` : lignes nettoyées de leurs bords, jointes par une espace, `\'` ramené à `'`), en attendant
/// la garde `check-textes-juridiques-ios.mjs` de L2-TL (absente de la base du lot 3). Les phrases assemblées (type
/// d'exercice unique, informations à vérifier) sont comparées au rendu du JSX ou du gabarit web. Le catalogue des
/// professions natif est relu contre le web (`PROFESSIONS`) et contre l'enum `type_profession` du dump.
final class CompletionVerbatimTests: XCTestCase {
    private typealias T = CompletionTextes

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

    private static func rendu(_ lignes: [String], _ debut: Int, _ fin: Int) -> String {
        lignes[(debut - 1)...(fin - 1)].map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            .replacingOccurrences(of: "\\'", with: "'")
    }

    private static let fichierSwift = "ios-native/Packages/JoleneCore/Sources/JoleneCore/Inscription/CompletionProfil.swift"
    private static let soignant = "src/pages/InscriptionSoignant.tsx"

    /// Chaque annotation est suivie de la déclaration de son texte, dont le littéral figure à la source citée.
    func testAnnotationsSourceDeCompletionProfilConcordent() throws {
        let annotation = try NSRegularExpression(pattern: #"^\s*// source: ([^:]+):(\d+)(?:-(\d+))?\s*$"#)
        let litteral = try NSRegularExpression(pattern: #"static let \w+[^=]*=\s*"((?:[^"\\]|\\.)*)""#)
        let lignes = try Self.source(Self.fichierSwift)
        var sources: [String: [String]] = [:]
        var verifiees = 0
        for (index, ligne) in lignes.enumerated() {
            let plage = NSRange(ligne.startIndex..., in: ligne)
            guard let trouve = annotation.firstMatch(in: ligne, range: plage),
                  let fichier = Range(trouve.range(at: 1), in: ligne).map({ String(ligne[$0]) }),
                  let debut = Range(trouve.range(at: 2), in: ligne).flatMap({ Int(ligne[$0]) }) else { continue }
            let fin = Range(trouve.range(at: 3), in: ligne).flatMap { Int(ligne[$0]) } ?? debut
            let suivante = lignes[index + 1]
            guard let decl = litteral.firstMatch(in: suivante, range: NSRange(suivante.startIndex..., in: suivante)),
                  let valeur = Range(decl.range(at: 1), in: suivante).map({ String(suivante[$0]) }) else {
                XCTFail("l.\(index + 1) : annotation sans déclaration de texte sur la ligne suivante")
                continue
            }
            if sources[fichier] == nil { sources[fichier] = try Self.source(fichier) }
            let cible = try XCTUnwrap(sources[fichier])
            XCTAssertGreaterThanOrEqual(cible.count, fin, fichier)
            XCTAssertTrue(Self.rendu(cible, debut, fin).contains(valeur),
                          "CompletionProfil.swift l.\(index + 1) : « \(valeur) » absent de \(fichier) l.\(debut)-\(fin)")
            verifiees += 1
        }
        XCTAssertEqual(verifiees, 46, "toutes les annotations de CompletionProfil.swift sont relues")
    }

    func testPhraseDuTypeUniqueAssembleeCommeLeJSX() throws {
        // `En tant que <strong>{label}</strong>, votre type d'exercice est automatiquement défini comme <strong>{…}</strong>.`
        let lignes = try Self.source(Self.soignant)
        let jsx = lignes[68 - 1].trimmingCharacters(in: .whitespaces)
        XCTAssertTrue(jsx.hasPrefix("En tant que <strong>{getLabelProfession(profession)}</strong>, votre type d'exercice est automatiquement défini comme <strong>{"), jsx)
        XCTAssertTrue(jsx.hasSuffix("</strong>."), jsx)
        XCTAssertTrue(jsx.contains("uniqueType === 'SALARIE' ? 'salarié' : uniqueType === 'LIBERAL' ? 'libéral' : 'mixte'"), jsx)
        XCTAssertEqual(CompletionRules.phraseTypeUnique(profession: "AS", type: "SALARIE"),
                       "En tant que \(MissionPresentation.professionLabel("AS")), votre type d'exercice est automatiquement défini comme salarié.")
    }

    func testListeDesInformationsAVerifierAssembleeCommeLeGabarit() throws {
        let lignes = try Self.source(Self.soignant)
        XCTAssertTrue(lignes[356 - 1].contains("message: `Vérifiez les informations suivantes : ${manque.join(', ')}.`"))
        // Ordre des éléments du web (l.355), « cohérence du RPPS » exclue (vérification en temps réel non portée, D11).
        let ordre = [T.manquePrenom, T.manqueNom, T.manqueTelephone, T.manqueDateNaissance, T.manqueProfession,
                     T.manqueModeExercice, T.manqueRpps].map { "'\($0)'" }
        let ligne = lignes[355 - 1]
        let positions = try ordre.map { try XCTUnwrap(ligne.range(of: $0), $0).lowerBound }
        XCTAssertEqual(positions, positions.sorted(), "ordre du web")
        XCTAssertTrue(ligne.contains("'cohérence du RPPS'"))
        XCTAssertEqual(CompletionRules.messageManques([T.manquePrenom, T.manqueModeExercice]),
                       "Vérifiez les informations suivantes : prénom, mode d’exercice.")
    }

    func testAucunTexteJuridiqueReformuleNiAjoute() {
        // Exclusivité et libellés de mode d'exercice : verbatim web ; aucun article de loi, aucune règle juridique nouvelle.
        let textes = [T.exclusivite, T.referentielIndisponible, T.questionSalarie, T.aucunRpps, T.aideRppsAnnuaire,
                      T.etudiant, ChoixModesExercice.Textes.libelleSalarie, ChoixModesExercice.Textes.libelleLiberal]
        for texte in textes {
            for marque in ["L1222", "article", "arrêté", "Code du travail", "jurisprudence"] {
                XCTAssertFalse(texte.contains(marque), "« \(texte) » : \(marque)")
            }
        }
        // Le bandeau étudiant du web cite l'arrêté du 3 février 2022 (DeclarationEtudiant.tsx l.108) : non porté (D11).
        XCTAssertEqual(T.etudiant, "🎓 Je suis étudiant(e) en santé")
    }

    /// Professions : catalogue natif (`MissionPresentation.professions`) = `PROFESSIONS` du web (constantes.ts, même
    /// ordre, mêmes libellés) = enum `type_profession` du dump (`supabase/schema/public.sql`, ensemble) = référentiel
    /// démo `demo-types-exercice.json` (17 lignes du seed). Une profession ajoutée d'un seul côté rougit ce test.
    func testCatalogueDesProfessionsSynchroniseAvecLeWebEtLEnumDB() throws {
        let constantes = try Self.source("src/lib/constantes.ts").joined(separator: "\n")
        let debut = try XCTUnwrap(constantes.range(of: "export const PROFESSIONS = ["))
        let fin = try XCTUnwrap(constantes.range(of: "] as const;", range: debut.upperBound..<constantes.endIndex))
        let bloc = String(constantes[debut.upperBound..<fin.lowerBound])
        let motif = try NSRegularExpression(pattern: #"\{ valeur: '([A-Z_]+)', label: (?:'((?:[^'\\]|\\.)*)'|"([^"]*)") \}"#)
        let web: [(String, String)] = motif.matches(in: bloc, range: NSRange(bloc.startIndex..., in: bloc)).compactMap { m in
            guard let v = Range(m.range(at: 1), in: bloc) else { return nil }
            let libelle = Range(m.range(at: 2), in: bloc).map { String(bloc[$0]) }
                ?? Range(m.range(at: 3), in: bloc).map { String(bloc[$0]) } ?? ""
            return (String(bloc[v]), libelle.replacingOccurrences(of: "\\'", with: "'"))
        }
        XCTAssertEqual(web.count, 17)
        XCTAssertEqual(web.map(\.0), MissionPresentation.professions.map(\.valeur), "codes et ordre du web")
        XCTAssertEqual(web.map(\.1), MissionPresentation.professions.map(\.label), "libellés du web")

        let schema = try Self.source("supabase/schema/public.sql")
        let ouverture = try XCTUnwrap(schema.firstIndex(of: #"CREATE TYPE "public"."type_profession" AS ENUM ("#))
        let fermeture = try XCTUnwrap(schema[ouverture...].firstIndex(of: ");"))
        let enumDB = schema[(ouverture + 1)..<fermeture].map {
            $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "',"))
        }
        XCTAssertEqual(Set(enumDB), Set(MissionPresentation.professions.map(\.valeur)), "enum DB type_profession")
        XCTAssertEqual(enumDB.count, 17)

        let referentiel: DemoFixtures.TypesExerciceFile = try DemoFixtures.load("demo-types-exercice")
        XCTAssertEqual(Set(referentiel.typesExercice.keys), Set(MissionPresentation.professions.map(\.valeur)),
                       "référentiel démo : une ligne par profession (seed versionné)")
        XCTAssertEqual(referentiel.source, "supabase/migrations/20260714084802_synchroniser_regles_profil_exercice.sql")
        XCTAssertEqual(referentiel.typesExercice["AS"], ["SALARIE"], "AS : salarié uniquement (seed)")
        XCTAssertEqual(referentiel.typesExercice["IDE"], ["SALARIE", "LIBERAL", "MIXTE"], "IDE : trois types (seed)")
    }
}
